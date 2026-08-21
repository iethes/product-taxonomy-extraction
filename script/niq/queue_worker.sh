#!/usr/bin/env bash
set -euo pipefail

# Pulls the highest-priority queued task from Postgres, runs script/headless_taxonomy.sh or
# script/targeted_qa_fix.sh up to loop_count times, and persists the result.
# See docs/superpowers/specs/2026-07-27-task-queue-design.md for the full design and
# docs/superpowers/specs/2026-08-21-orchestrator-script-universalization-design.md for the shared
# queue_common.sh wrapper this now uses.
#
# Usage: script/queue_worker.sh
# Requires QUEUE_DATABASE_URL (see script/load_env.sh / .env.example).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/queue_common.sh"

QUEUE_TABLE="${QUEUE_SCHEMA:-public}.task_queue"

run_underlying_script() {
  local script_type="$1" table="$2" month="$3" max_turns="$4" block_size="$5"
  case "$script_type" in
    headless_taxonomy)
      "${HEADLESS_TAXONOMY_SCRIPT:-./script/niq/headless_taxonomy.sh}" "$table" "$month" "$max_turns"
      ;;
    targeted_qa_fix)
      "${TARGETED_QA_FIX_SCRIPT:-./script/niq/targeted_qa_fix.sh}" "$table" "$block_size" "$max_turns"
      ;;
    *)
      echo "Unknown script_type: $script_type" >&2
      echo "QUEUE_SIGNAL: FAILED"
      ;;
  esac
}

# See queue_common.sh's persist_final_status comment for the `|| true` rationale on `signal=`:
# parse_queue_signal's pipeline exits non-zero whenever no QUEUE_SIGNAL line is found (e.g. the
# underlying script crashed before printing one) -- without `|| true` here, that would silently
# kill the whole worker loop instead of falling through to queue_signal_to_status's own
# "unparseable -> failed" handling.
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
  source "$(dirname "$0")/../load_env.sh"
  QUEUE_TABLE="${QUEUE_SCHEMA:-public}.task_queue"   # recompute now that .env is actually loaded
  : "${QUEUE_DATABASE_URL:?QUEUE_DATABASE_URL must be set (via .env or the environment)}"
  WORKER_ID="$(hostname)-$$"
  queue_main_loop "" "$WORKER_ID" run_task
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
