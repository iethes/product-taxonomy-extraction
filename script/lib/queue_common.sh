#!/usr/bin/env bash
# Shared postgres task-queue wrapper for script/niq/queue_worker.sh and
# script/non_niq/queue_worker.sh -- both duplicated this ~90% verbatim before this file existed.
# See docs/superpowers/specs/2026-08-21-orchestrator-script-universalization-design.md.
#
# Requires queue_psql() (script/load_env.sh) and QUEUE_TABLE to already be set by the caller
# before any function here is actually called (source order doesn't matter for function
# *definitions*, only for the values they read at call time).

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

_sql_quote() {
  local s="$1"
  echo "'${s//\'/\'\'}'"
}

# reclaim_stale_leases_query [script_type]
# Empty/omitted script_type = unscoped. A scoped worker (non_niq) MUST pass its script_type --
# an unscoped reclaim run by a scoped worker would reset a still-running row belonging to a
# DIFFERENT worker (e.g. niq's) back to 'queued' if that row's lease merely looked stale to this
# worker, defeating one_running_task_per_table for a table this worker doesn't even own.
reclaim_stale_leases_query() {
  local script_type="${1:-}"
  local type_filter=""
  [[ -n "$script_type" ]] && type_filter=" AND script_type=$(_sql_quote "$script_type")"
  echo "UPDATE ${QUEUE_TABLE} SET status='queued', claimed_by=NULL, claimed_at=NULL
    WHERE status='running'${type_filter}
      AND claimed_at < now() - interval '${LEASE_TIMEOUT_HOURS:-4} hours';"
}

reclaim_stale_leases() {
  queue_psql "$(reclaim_stale_leases_query "${1:-}")" -t -A >/dev/null
}

# claim_next_task_query <worker_id> [script_type]
# REQUIRED, not optional -- see sql/postgres/001_task_queue.sql: SKIP LOCKED alone does not give
# per-table exclusion. The one_running_task_per_table unique index is what actually blocks a
# second concurrent claim, by raising a duplicate-key error on commit -- which claim_next_task
# must treat as "lost the race, no task claimed this round," not a crash.
claim_next_task_query() {
  local worker_id="$1" script_type="${2:-}"
  local type_filter=""
  [[ -n "$script_type" ]] && type_filter=" AND script_type=$(_sql_quote "$script_type")"
  # extra_args (JSON, arbitrary per-script_type params -- e.g. non_niq_qa's kategori) is LAST in
  # the RETURNING list on purpose: queue_main_loop's `IFS='|' read` splits every field before it,
  # but the LAST named variable in a bash `read` absorbs the rest of the line verbatim, delimiters
  # included -- so a JSON value that happens to contain a literal "|" can't corrupt the parse only
  # as long as nothing is read after it.
  echo "UPDATE ${QUEUE_TABLE} SET status='running', claimed_by='${worker_id}', claimed_at=now()
    WHERE id = (
      SELECT id FROM ${QUEUE_TABLE}
      WHERE status='queued'${type_filter}
        AND table_name NOT IN (SELECT table_name FROM ${QUEUE_TABLE} WHERE status='running')
      ORDER BY priority DESC, submitted_at ASC
      FOR UPDATE SKIP LOCKED LIMIT 1
    )
    RETURNING id, table_name, script_type, month, max_turns, block_size, loop_count, extra_args;"
}

claim_next_task() {
  local worker_id="$1" script_type="${2:-}"
  local out
  if ! out=$(queue_psql "$(claim_next_task_query "$worker_id" "$script_type")" -t -A -F'|' 2>&1); then
    [[ "$(is_duplicate_key_error "$out")" == "true" ]] && { echo ""; return 0; }
    echo "$out" >&2
    return 1
  fi
  # $out is polluted with the "UPDATE 1" command-completion tag psql always prints regardless of
  # -t/-A. `|| true` is required: grep exits 1 on the legitimate "no row claimed" case (empty
  # $out), which under `set -e` would otherwise be treated as this function failing.
  grep '|' <<< "$out" || true
}

heartbeat() {
  local id="$1"
  queue_psql "UPDATE ${QUEUE_TABLE} SET claimed_at=now() WHERE id=${id} AND status='running';" -t -A >/dev/null
}

# extract_last_result_json <output>
# Scans $output for the LAST line that parses as JSON with a "signal" key (i.e. an emit_result
# line from the underlying orchestrator) and prints that. Falls back to the old
# {raw_output: ...} wrapping if no such line is found -- a run that crashed before reaching its
# emit_result call still gets *something* stored, not a DB write failure. Pulled out of
# persist_final_status as its own pure function so it's testable without a live database.
extract_last_result_json() {
  local output="$1"
  local last_result_json="" line
  while IFS= read -r line; do
    if echo "$line" | jq -e '.signal' >/dev/null 2>&1; then
      last_result_json="$line"
    fi
  done <<< "$output"
  if [[ -z "$last_result_json" ]]; then
    last_result_json=$(printf '%s' "$output" | jq -Rs '{raw_output: .}')
  fi
  echo "$last_result_json"
}

# persist_final_status <id> <status> <iterations_run> <output>
# Stores a structured result as last_result instead of the whole raw output blob -- see
# extract_last_result_json above for how that's derived.
persist_final_status() {
  local id="$1" status="$2" iterations_run="$3" output="$4"
  local last_result_json
  last_result_json=$(extract_last_result_json "$output")
  queue_psql "
      UPDATE ${QUEUE_TABLE}
      SET status = $(_sql_quote "$status"), iterations_run = ${iterations_run}, updated_at = now(),
          last_result = $(_sql_quote "$last_result_json")::json
      WHERE id = ${id};" \
    -t -A >/dev/null
}

# queue_main_loop <script_type_filter> <worker_id> <run_task_fn>
# run_task_fn must already be defined by the caller; it's invoked as:
#   "$run_task_fn" <id> <table_name> <script_type> <month> <max_turns> <block_size> <loop_count> <extra_args>
# extra_args is a JSON blob (or empty) of arbitrary per-script_type params -- a run_task_fn that
# doesn't need it (e.g. niq's) can simply not reference the 8th positional arg.
queue_main_loop() {
  local script_type_filter="$1" worker_id="$2" run_task_fn="$3"
  echo "Worker ${worker_id} starting, polling every ${POLL_INTERVAL_SECONDS:-15}s"
  while true; do
    reclaim_stale_leases "$script_type_filter"
    local row
    row=$(claim_next_task "$worker_id" "$script_type_filter") || { sleep "${POLL_INTERVAL_SECONDS:-15}"; continue; }
    if [[ -z "$row" ]]; then
      sleep "${POLL_INTERVAL_SECONDS:-15}"
      continue
    fi
    local id table_name script_type month max_turns block_size loop_count extra_args
    IFS='|' read -r id table_name script_type month max_turns block_size loop_count extra_args <<< "$row"
    echo "Claimed task ${id}: ${table_name} (${script_type})"
    "$run_task_fn" "$id" "$table_name" "$script_type" "$month" "$max_turns" "$block_size" "$loop_count" "$extra_args"
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    --self-test)
      QUEUE_TABLE="public.task_queue"
      unscoped_reclaim=$(reclaim_stale_leases_query "")
      [[ "$unscoped_reclaim" != *"script_type"* ]] \
        || { echo "FAIL: unscoped reclaim query should not filter by script_type -> $unscoped_reclaim"; exit 1; }
      scoped_reclaim=$(reclaim_stale_leases_query "non_niq_qa")
      [[ "$scoped_reclaim" == *"script_type='non_niq_qa'"* ]] \
        || { echo "FAIL: scoped reclaim query missing filter -> $scoped_reclaim"; exit 1; }
      unscoped_claim=$(claim_next_task_query "worker-1" "")
      [[ "$unscoped_claim" != *"script_type="* ]] \
        || { echo "FAIL: unscoped claim query should not filter -> $unscoped_claim"; exit 1; }
      scoped_claim=$(claim_next_task_query "worker-1" "headless_taxonomy")
      [[ "$scoped_claim" == *"script_type='headless_taxonomy'"* ]] \
        || { echo "FAIL: scoped claim query missing filter -> $scoped_claim"; exit 1; }
      [[ "$(is_duplicate_key_error "duplicate key value violates unique constraint foo")" == "true" ]] \
        || { echo "FAIL: is_duplicate_key_error true case"; exit 1; }
      [[ "$(is_duplicate_key_error "some other error")" == "false" ]] \
        || { echo "FAIL: is_duplicate_key_error false case"; exit 1; }
      [[ "$(queue_signal_to_status "DONE")" == "done" ]] || { echo "FAIL: queue_signal_to_status DONE"; exit 1; }
      [[ "$(queue_signal_to_status "BLOCKED")" == "blocked" ]] || { echo "FAIL: queue_signal_to_status BLOCKED"; exit 1; }
      [[ "$(queue_signal_to_status "FAILED")" == "failed" ]] || { echo "FAIL: queue_signal_to_status FAILED"; exit 1; }
      [[ "$(should_stop_looping "DONE")" == "false" ]] || { echo "FAIL: should_stop_looping DONE"; exit 1; }
      [[ "$(should_stop_looping "BLOCKED")" == "true" ]] || { echo "FAIL: should_stop_looping BLOCKED"; exit 1; }
      found=$(extract_last_result_json "$(printf 'some noise\n{"timestamp":"t","table":"x","signal":"DONE","message":"ok"}\nQUEUE_SIGNAL: DONE')")
      [[ "$found" == '{"timestamp":"t","table":"x","signal":"DONE","message":"ok"}' ]] \
        || { echo "FAIL: extract_last_result_json found-case -> $found"; exit 1; }
      fallback=$(extract_last_result_json "$(printf 'plain crash output\nno json here')")
      echo "$fallback" | jq -e '.raw_output | test("plain crash output")' >/dev/null \
        || { echo "FAIL: extract_last_result_json fallback-case -> $fallback"; exit 1; }
      echo "self-test OK: queue_common.sh"
      ;;
    *)
      echo "Usage: $0 --self-test" >&2
      exit 1
      ;;
  esac
fi
