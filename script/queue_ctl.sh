#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   script/queue_ctl.sh submit <table> <headless_taxonomy|targeted_qa_fix> \
#       [--month YYYY-MM] [--max-turns N] [--block-size N] [--loop-count N] [--priority N]
#   script/queue_ctl.sh list [--status queued|running|done|failed|blocked|cancelled]
#   script/queue_ctl.sh priority <task_id> <new_priority>
#   script/queue_ctl.sh cancel <task_id>
#
# NOTE on loop_count: for targeted_qa_fix tasks in brief mode (a hand-written '## Targeted QA Fix
# Brief' section in the category doc, not auto-discovery), the underlying script has no way to
# self-detect "nothing left to do." Set --loop-count 1 for those unless you know the brief needs
# multiple passes. See docs/superpowers/specs/2026-07-27-task-queue-design.md section 4.
#
# Requires QUEUE_DATABASE_URL (see script/load_env.sh / .env.example).

sql_quote() {
  local s="$1"
  echo "'${s//\'/\'\'}'"
}

build_submit_sql() {
  local table="$1" script_type="$2" month="$3" max_turns="$4" block_size="$5" loop_count="$6" priority="$7"
  local month_sql max_turns_sql block_size_sql
  [[ -z "$month" ]] && month_sql="NULL" || month_sql=$(sql_quote "$month")
  [[ -z "$max_turns" ]] && max_turns_sql="NULL" || max_turns_sql="$max_turns"
  [[ -z "$block_size" ]] && block_size_sql="NULL" || block_size_sql="$block_size"
  cat <<SQL
INSERT INTO task_queue (table_name, script_type, month, max_turns, block_size, loop_count, priority, status, submitted_at, iterations_run)
VALUES ($(sql_quote "$table"), $(sql_quote "$script_type"), ${month_sql}, ${max_turns_sql}, ${block_size_sql}, ${loop_count}, ${priority}, 'queued', now(), 0)
RETURNING id;
SQL
}

build_list_sql() {
  local status_filter="$1"
  if [[ -z "$status_filter" ]]; then
    echo "SELECT id, table_name, script_type, status, priority, iterations_run, loop_count, submitted_at FROM task_queue ORDER BY status, priority DESC, submitted_at ASC;"
  else
    echo "SELECT id, table_name, script_type, status, priority, iterations_run, loop_count, submitted_at FROM task_queue WHERE status = $(sql_quote "$status_filter") ORDER BY priority DESC, submitted_at ASC;"
  fi
}

build_priority_sql() {
  local task_id="$1" new_priority="$2"
  echo "UPDATE task_queue SET priority = ${new_priority}, updated_at = now() WHERE id = ${task_id} AND status = 'queued' RETURNING id;"
}

build_cancel_sql() {
  local task_id="$1"
  echo "UPDATE task_queue SET status = 'cancelled', updated_at = now() WHERE id = ${task_id} AND status = 'queued' RETURNING id;"
}

cmd_submit() {
  local table="$1" script_type="$2"
  shift 2
  local month="" max_turns="" block_size="" loop_count=3 priority=100
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --month) month="$2"; shift 2 ;;
      --max-turns) max_turns="$2"; shift 2 ;;
      --block-size) block_size="$2"; shift 2 ;;
      --loop-count) loop_count="$2"; shift 2 ;;
      --priority) priority="$2"; shift 2 ;;
      *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
  done
  queue_psql "$(build_submit_sql "$table" "$script_type" "$month" "$max_turns" "$block_size" "$loop_count" "$priority")"
}

cmd_list() {
  local status_filter=""
  [[ "${1:-}" == "--status" ]] && status_filter="${2:-}"
  queue_psql "$(build_list_sql "$status_filter")"
}

cmd_priority() {
  local task_id="$1" new_priority="$2"
  local out id_line
  out=$(queue_psql "$(build_priority_sql "$task_id" "$new_priority")" -t -A)
  # $out is polluted with non-data lines that psql always prints regardless of -t/-A: the "SET" tag
  # from queue_psql's search_path prefix statement, and the "UPDATE N" command-completion tag --
  # both present even when RETURNING matched zero rows (empirically confirmed against a live
  # postgres:16 client; see script/queue_worker.sh's claim_next_task for the same finding). A bare
  # `[[ -z "$out" ]]` check is therefore never true and would always report success. Filter down to
  # a line that is purely the numeric id RETURNING would emit. `|| true` is required: grep exits 1
  # on the legitimate "no row matched" case, which under `set -e` would otherwise be treated as this
  # function failing.
  id_line=$(grep -E '^[0-9]+$' <<< "$out" || true)
  if [[ -z "$id_line" ]]; then
    echo "Task ${task_id} already started (or doesn't exist) -- priority can no longer be changed." >&2
    exit 1
  fi
  echo "Task ${task_id} priority set to ${new_priority}."
}

cmd_cancel() {
  local task_id="$1"
  local out id_line
  out=$(queue_psql "$(build_cancel_sql "$task_id")" -t -A)
  # See cmd_priority for why we can't just check `-z "$out"` -- the SET/UPDATE-N tags are always
  # present, so we filter down to the bare numeric id line RETURNING emits on an actual match.
  id_line=$(grep -E '^[0-9]+$' <<< "$out" || true)
  if [[ -z "$id_line" ]]; then
    echo "Task ${task_id} already started (or doesn't exist) -- can no longer be cancelled." >&2
    exit 1
  fi
  echo "Task ${task_id} cancelled."
}

main() {
  source "$(dirname "$0")/load_env.sh"
  : "${QUEUE_DATABASE_URL:?QUEUE_DATABASE_URL must be set (via .env or the environment)}"
  local cmd="${1:-}"
  case "$cmd" in
    submit) shift; cmd_submit "$@" ;;
    list) shift; cmd_list "$@" ;;
    priority) shift; cmd_priority "$@" ;;
    cancel) shift; cmd_cancel "$@" ;;
    *)
      echo "Usage: $0 submit|list|priority|cancel ..." >&2
      exit 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
