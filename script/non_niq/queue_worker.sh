#!/usr/bin/env bash
set -euo pipefail

# Separate polling loop from script/niq/queue_worker.sh -- claims only script_type='non_niq_qa' rows
# from the SAME shared p4ct2g2urhzcfnz.task_queue Postgres table. table_name is encoded as
# "{dataset}:{platform}" for every row this worker claims (e.g. "babybath:shopee") -- see the
# Global Constraints in docs/superpowers/plans/2026-08-06-non-niq-agentic-qa.md.
#
# Usage: script/non_niq/queue_worker.sh
# Requires QUEUE_DATABASE_URL (see script/load_env.sh / .env.example).

QUEUE_TABLE="${QUEUE_SCHEMA:-public}.task_queue"

split_table_name() {
  local table_name="$1"
  local dataset="${table_name%%:*}"
  local platform="${table_name#*:}"
  echo "${dataset} ${platform}"
}

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
    *) echo "failed" ;;
  esac
}

should_stop_looping() {
  case "$1" in
    DONE) echo "false" ;;
    *) echo "true" ;;
  esac
}

# Scoped to script_type='non_niq_qa' -- an unscoped version (like NIQ's own queue_worker.sh, which
# is intentionally left as-is per this plan's Global Constraints) would reset a still-running NIQ
# row back to 'queued' if that row's lease happened to look stale, defeating
# one_running_task_per_table and risking two concurrent NIQ sessions on the same table mid
# SKU-block-allocation.
reclaim_stale_leases_query() {
  echo "UPDATE ${QUEUE_TABLE} SET status='queued', claimed_by=NULL, claimed_at=NULL
    WHERE status='running' AND script_type='non_niq_qa'
      AND claimed_at < now() - interval '${LEASE_TIMEOUT_HOURS:-4} hours';"
}

reclaim_stale_leases() {
  queue_psql "$(reclaim_stale_leases_query)" -t -A >/dev/null
}

claim_next_task_query() {
  local worker_id="$1"
  echo "UPDATE ${QUEUE_TABLE} SET status='running', claimed_by='${worker_id}', claimed_at=now()
    WHERE id = (
      SELECT id FROM ${QUEUE_TABLE}
      WHERE status='queued' AND script_type='non_niq_qa'
        AND table_name NOT IN (SELECT table_name FROM ${QUEUE_TABLE} WHERE status='running')
      ORDER BY priority DESC, submitted_at ASC
      FOR UPDATE SKIP LOCKED LIMIT 1
    )
    RETURNING id, table_name, script_type, month, max_turns, block_size, loop_count;"
}

claim_next_task() {
  local out
  if ! out=$(queue_psql "$(claim_next_task_query "$WORKER_ID")" -t -A -F'|' 2>&1); then
    [[ "$(is_duplicate_key_error "$out")" == "true" ]] && { echo ""; return 0; }
    echo "$out" >&2
    return 1
  fi
  grep '|' <<< "$out" || true
}

heartbeat() {
  local id="$1"
  queue_psql "UPDATE ${QUEUE_TABLE} SET claimed_at=now() WHERE id=${id} AND status='running';" -t -A >/dev/null
}

_sql_quote() {
  local s="$1"
  echo "'${s//\'/\'\'}'"
}

persist_final_status() {
  local id="$1" status="$2" iterations_run="$3" output="$4"
  local last_result_json
  last_result_json=$(printf '%s' "$output" | jq -Rs '{raw_output: .}')
  queue_psql "
      UPDATE ${QUEUE_TABLE}
      SET status = $(_sql_quote "$status"), iterations_run = ${iterations_run}, updated_at = now(),
          last_result = $(_sql_quote "$last_result_json")::json
      WHERE id = ${id};" \
    -t -A >/dev/null
}

run_task() {
  local id="$1" table_name="$2" max_turns="$3" loop_count="$4"
  local dataset platform
  read -r dataset platform <<< "$(split_table_name "$table_name")"
  local iterations_run=0 final_status="failed" last_output="" signal=""
  local i
  for ((i = 1; i <= loop_count; i++)); do
    heartbeat "$id"
    last_output=$("${NON_NIQ_QA_SCRIPT:-./script/non_niq/non_niq_qa.sh}" "$dataset" "$platform" "$max_turns" 2>&1) || true
    echo "$last_output"
    iterations_run=$((iterations_run + 1))
    signal=$(parse_queue_signal "$last_output") || true
    final_status=$(queue_signal_to_status "$signal")
    [[ "$(should_stop_looping "$signal")" == "true" ]] && break
  done
  persist_final_status "$id" "$final_status" "$iterations_run" "$last_output"
}

main() {
  source "$(dirname "$0")/../load_env.sh"
  QUEUE_TABLE="${QUEUE_SCHEMA:-public}.task_queue"
  : "${QUEUE_DATABASE_URL:?QUEUE_DATABASE_URL must be set (via .env or the environment)}"
  WORKER_ID="non-niq-$(hostname)-$$"
  echo "Non-NIQ worker ${WORKER_ID} starting, polling every ${POLL_INTERVAL_SECONDS:-15}s"
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
    run_task "$id" "$table_name" "$max_turns" "$loop_count"
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
