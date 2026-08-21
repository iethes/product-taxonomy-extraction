#!/usr/bin/env bash
set -euo pipefail

# Separate polling loop from script/niq/queue_worker.sh -- claims only script_type='non_niq_qa' rows
# from the SAME shared p4ct2g2urhzcfnz.task_queue Postgres table. table_name is encoded as
# "{dataset}:{platform}" for every row this worker claims (e.g. "babybath:shopee") -- see the
# Global Constraints in docs/superpowers/plans/2026-08-06-non-niq-agentic-qa.md.
# See docs/superpowers/specs/2026-08-21-orchestrator-script-universalization-design.md for the
# shared queue_common.sh wrapper this now uses.
#
# Usage: script/non_niq/queue_worker.sh
# Requires QUEUE_DATABASE_URL (see script/load_env.sh / .env.example).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/queue_common.sh"

QUEUE_TABLE="${QUEUE_SCHEMA:-public}.task_queue"

split_table_name() {
  local table_name="$1"
  local dataset="${table_name%%:*}"
  local platform="${table_name#*:}"
  echo "${dataset} ${platform}"
}

run_task() {
  local id="$1" table_name="$2" script_type="$3" month="$4" max_turns="$5" block_size="$6" loop_count="$7"
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
  queue_main_loop "non_niq_qa" "$WORKER_ID" run_task
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
