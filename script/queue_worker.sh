#!/usr/bin/env bash
set -euo pipefail

# Pulls the highest-priority queued task from Postgres, runs script/headless_taxonomy.sh or
# script/targeted_qa_fix.sh up to loop_count times, and persists the result.
# See docs/superpowers/specs/2026-07-27-task-queue-design.md for the full design.
#
# Usage: script/queue_worker.sh
# Requires QUEUE_DATABASE_URL (see script/load_env.sh / .env.example).

parse_queue_signal() {
  local output="$1"
  grep -o 'QUEUE_SIGNAL: [A-Z_]*' <<< "$output" | tail -1 | awk '{print $2}'
}

is_duplicate_key_error() {
  [[ "$1" == *"duplicate key value violates unique constraint"* ]] && echo "true" || echo "false"
}

queue_signal_to_status() {
  case "$1" in
    NOTHING_TO_DO|DONE) echo "done" ;;
    BLOCKED) echo "blocked" ;;
    *) echo "failed" ;;   # FAILED, missing, or unparseable -- never silently treated as success
  esac
}

should_stop_looping() {
  case "$1" in
    DONE) echo "false" ;;
    *) echo "true" ;;    # NOTHING_TO_DO, BLOCKED, FAILED, or unrecognized all stop the loop
  esac
}

reclaim_stale_leases() {
  queue_psql "
    UPDATE task_queue SET status='queued', claimed_by=NULL, claimed_at=NULL
    WHERE status='running' AND claimed_at < now() - interval '${LEASE_TIMEOUT_HOURS:-4} hours';" -t -A >/dev/null
}

# REQUIRED, not optional -- see sql/postgres/001_task_queue.sql: SKIP LOCKED alone does not give
# per-table exclusion (it only skips locked rows, not other queued rows for the same table_name).
# The one_running_task_per_table unique index is what actually blocks a second concurrent claim, by
# raising a duplicate-key error on commit -- which this function must treat as "lost the race, no
# task claimed this round," not a crash.
claim_next_task() {
  local out
  if ! out=$(queue_psql "
    UPDATE task_queue SET status='running', claimed_by='${WORKER_ID}', claimed_at=now()
    WHERE id = (
      SELECT id FROM task_queue
      WHERE status='queued'
        AND table_name NOT IN (SELECT table_name FROM task_queue WHERE status='running')
      ORDER BY priority DESC, submitted_at ASC
      FOR UPDATE SKIP LOCKED LIMIT 1
    )
    RETURNING id, table_name, script_type, month, max_turns, block_size, loop_count;" -t -A -F'|' 2>&1)
  then
    [[ "$(is_duplicate_key_error "$out")" == "true" ]] && { echo ""; return 0; }
    echo "$out" >&2
    return 1
  fi
  # $out is polluted with non-data lines that psql always prints regardless of -t/-A: the "SET" tag
  # from queue_psql's search_path prefix statement, and (empirically confirmed against a live
  # postgres:16 client) the "UPDATE 1" command-completion tag that psql prints for an UPDATE...
  # RETURNING even under -t. Only the actual data line contains the -F'|' separator, so filter down to
  # that. `|| true` is required: grep exits 1 on the legitimate "no row claimed" case (empty $out),
  # which under `set -e` would otherwise be treated as this function failing.
  grep '|' <<< "$out" || true
}

heartbeat() {
  local id="$1"
  queue_psql "UPDATE task_queue SET claimed_at=now() WHERE id=${id} AND status='running';" -t -A >/dev/null
}

run_underlying_script() {
  local script_type="$1" table="$2" month="$3" max_turns="$4" block_size="$5"
  case "$script_type" in
    headless_taxonomy)
      "${HEADLESS_TAXONOMY_SCRIPT:-./script/headless_taxonomy.sh}" "$table" "$month" "$max_turns"
      ;;
    targeted_qa_fix)
      "${TARGETED_QA_FIX_SCRIPT:-./script/targeted_qa_fix.sh}" "$table" "$block_size" "$max_turns"
      ;;
    *)
      echo "Unknown script_type: $script_type" >&2
      echo "QUEUE_SIGNAL: FAILED"
      ;;
  esac
}

# last_result is stored as `json`, not `jsonb` -- matches the pre-existing NocoDB-created column type
# (see Global Constraints: this design does not alter that column, to touch the shared table as little
# as possible).
#
# NOTE: this deliberately does NOT use `psql -v ... -c "... :'var' ..."` the way the brief originally
# specified. Empirically confirmed against a fresh, unmodified `postgres:16` client (not a shim/
# PgBouncer artifact -- reproduced against a bare local container with no queue_psql involved at all):
# psql's `:'var'` / `:var` interpolation is simply never performed inside a `-c` string, only for
# `-f`/stdin input. `-v` + `-c` combined with colon-variables always raises
# `ERROR: syntax error at or near ":"`. Since queue_psql (Task 1) sends everything through `-c` (see
# script/load_env.sh's own comment on why -- PgBouncer + a single implicit-transaction -c string is
# load-bearing there), colon-variable substitution can never work through it. Falling back to the
# same inline-SQL-building convention already used by Task 5's build_submit_sql/build_*_sql
# (docs/superpowers/plans/2026-07-27-task-queue.md), with the same single-quote-doubling escape.
_sql_quote() {
  local s="$1"
  echo "'${s//\'/\'\'}'"
}

persist_final_status() {
  local id="$1" status="$2" iterations_run="$3" output="$4"
  local last_result_json
  last_result_json=$(printf '%s' "$output" | jq -Rs '{raw_output: .}')
  queue_psql "
      UPDATE task_queue
      SET status = $(_sql_quote "$status"), iterations_run = ${iterations_run}, updated_at = now(),
          last_result = $(_sql_quote "$last_result_json")::json
      WHERE id = ${id};" \
    -t -A >/dev/null
}

# The `|| true` on both command substitutions below is required, not decorative: `signal` and
# `last_output` are already `local`-declared above, so these are bare reassignments -- under
# `set -euo pipefail`, a bare `var=$(...)` reassignment DOES propagate the substitution's exit status
# (unlike a combined `local var=$(...)`, which does not). parse_queue_signal's `grep -o ... | tail -1`
# pipeline exits non-zero whenever no QUEUE_SIGNAL line is found (e.g. the underlying script crashed
# before printing one) -- without `|| true` here, that would silently kill the whole worker loop
# instead of falling through to queue_signal_to_status's own "unparseable -> failed" handling.
# Confirmed empirically: a bare `signal=$(...)` reassignment of an already-local var, with a failing
# pipeline on the right-hand side, exits the enclosing function under set -e; `local signal=$(...)`
# (combined declare+assign) does NOT propagate the same way -- these are genuinely different, so the
# `|| true` is the correct fix, not a redundant safety net.
run_task() {
  local id="$1" table="$2" script_type="$3" month="$4" max_turns="$5" block_size="$6" loop_count="$7"
  local iterations_run=0 final_status="failed" last_output="" signal=""
  local i
  for ((i = 1; i <= loop_count; i++)); do
    heartbeat "$id"
    last_output=$(run_underlying_script "$script_type" "$table" "$month" "$max_turns" "$block_size" 2>&1) || true
    echo "$last_output"
    iterations_run=$((iterations_run + 1))
    signal=$(parse_queue_signal "$last_output") || true
    final_status=$(queue_signal_to_status "$signal")
    [[ "$(should_stop_looping "$signal")" == "true" ]] && break
  done
  persist_final_status "$id" "$final_status" "$iterations_run" "$last_output"
}

main() {
  source "$(dirname "$0")/load_env.sh"
  : "${QUEUE_DATABASE_URL:?QUEUE_DATABASE_URL must be set (via .env or the environment)}"
  WORKER_ID="$(hostname)-$$"
  echo "Worker ${WORKER_ID} starting, polling every ${POLL_INTERVAL_SECONDS:-15}s"
  while true; do
    reclaim_stale_leases
    local row
    row=$(claim_next_task) || { sleep "${POLL_INTERVAL_SECONDS:-15}"; continue; }
    if [[ -z "$row" ]]; then
      sleep "${POLL_INTERVAL_SECONDS:-15}"
      continue
    fi
    local id table_name script_type month max_turns block_size loop_count
    IFS='|' read -r id table_name script_type month max_turns block_size loop_count <<< "$row"
    echo "Claimed task ${id}: ${table_name} (${script_type})"
    run_task "$id" "$table_name" "$script_type" "$month" "$max_turns" "$block_size" "$loop_count"
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
