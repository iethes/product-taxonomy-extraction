#!/usr/bin/env bash
set -euo pipefail

# Separate polling loop from script/niq/queue_worker.sh -- claims only script_type='non_niq_qa' rows
# from the SAME shared p4ct2g2urhzcfnz.task_queue Postgres table. table_name is encoded as
# "{dataset}:{platform}" or "{dataset}:{platform}:{country}" for every row this worker claims (e.g.
# "babybath:shopee" or "cookiesbiscuit:shopee:TH") -- see the Global Constraints in
# docs/superpowers/plans/2026-08-06-non-niq-agentic-qa.md.
# See docs/superpowers/specs/2026-08-21-orchestrator-script-universalization-design.md for the
# shared queue_common.sh wrapper this now uses, and docs/non-niq-queue-submitter-handoff.md for the
# full task_queue column contract this script relies on (table_name encoding, block_size = max_rows,
# extra_args.kategori).
#
# Usage: script/non_niq/queue_worker.sh
# Requires QUEUE_DATABASE_URL (see script/load_env.sh / .env.example).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/queue_common.sh"

QUEUE_TABLE="${QUEUE_SCHEMA:-public}.task_queue"

# table_name is "{dataset}:{platform}" or "{dataset}:{platform}:{country}" -- country defaults to
# ID (matching non_niq_qa_v2.sh's own default) when the 3rd segment is absent, so pre-existing
# 2-segment queue rows keep working unchanged. Encoding country here (rather than a separate
# column) also makes the one_running_task_per_table lock correctly country-scoped.
split_table_name() {
  local table_name="$1"
  local dataset platform country
  IFS=':' read -r dataset platform country <<< "$table_name"
  echo "${dataset} ${platform} ${country:-ID}"
}

run_task() {
  local id="$1" table_name="$2" script_type="$3" month="$4" max_turns="$5" block_size="$6" loop_count="$7" extra_args="${8:-}"
  local dataset platform country
  read -r dataset platform country <<< "$(split_table_name "$table_name")"
  # block_size doubles as max_rows for script_type=non_niq_qa (same generic-slot-reused-per-
  # script_type convention niq's targeted_qa_fix already uses it for). kategori comes out of
  # extra_args (JSON, e.g. {"kategori":"Connected Light"}) -- empty/null extra_args is the common
  # case (no kategori sharding), jq's `// empty` makes that a no-op rather than an error.
  local max_rows="$block_size" kategori
  kategori=$(jq -r '.kategori // empty' <<< "${extra_args:-null}" 2>/dev/null) || kategori=""
  local iterations_run=0 final_status="failed" last_output="" signal=""
  local i
  for ((i = 1; i <= loop_count; i++)); do
    heartbeat "$id"
    last_output=$("${NON_NIQ_QA_SCRIPT:-./script/non_niq/non_niq_qa_v2.sh}" "$dataset" "$platform" "$country" "$max_turns" "$max_rows" "$kategori" 2>&1) || true
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
