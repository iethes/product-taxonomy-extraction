#!/usr/bin/env bash
set -euo pipefail

# Self-test for script/queue_ctl.sh's pure SQL-building functions.
# No network or Postgres calls -- mirrors script/test_targeted_qa_fix.sh's convention.
# Run: bash script/test_queue_ctl.sh

cd "$(dirname "$0")/.."
# QUEUE_SCHEMA is unset explicitly (not just left alone) so this test is deterministic even when run
# from an interactive shell that already exported it via `source script/load_env.sh` earlier in the
# same session -- queue_ctl.sh's top-level QUEUE_TABLE assignment (the one that applies here, since
# main() never runs under this test) is computed at source time from whatever QUEUE_SCHEMA the process
# environment happens to hold, so an inherited real value would otherwise silently change what these
# assertions need to match. (main(), when actually run, recomputes QUEUE_TABLE again after loading
# .env -- irrelevant here, but see queue_ctl.sh's main() for why.)
unset QUEUE_SCHEMA
source script/queue_ctl.sh

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- QUEUE_TABLE ---
[[ "$QUEUE_TABLE" == "public.task_queue" ]] || fail "QUEUE_TABLE should default to public.task_queue when QUEUE_SCHEMA is unset, got '$QUEUE_TABLE'"
echo "PASS: QUEUE_TABLE default"

# --- sql_quote ---
[[ "$(sql_quote "shopee_th_shampoo")" == "'shopee_th_shampoo'" ]] || fail "plain string should just be quoted"
[[ "$(sql_quote "o'brien")" == "'o''brien'" ]] || fail "embedded single quote must be doubled, not left to break the statement"
echo "PASS: sql_quote"

# --- build_submit_sql ---
sql=$(build_submit_sql "shopee_th_shampoo" "headless_taxonomy" "" "" "" "3" "100")
grep -qF "INSERT INTO public.task_queue" <<< "$sql" || fail "should target the fully-qualified QUEUE_TABLE, not bare task_queue"
grep -qF "'shopee_th_shampoo'" <<< "$sql" || fail "should quote the table name"
grep -qF "'headless_taxonomy'" <<< "$sql" || fail "should quote the script_type"
grep -qF "NULL, NULL, NULL" <<< "$sql" || fail "omitted month/max_turns/block_size should become SQL NULL"
grep -qF "3, 100, 'queued', now(), 0" <<< "$sql" || fail "loop_count/priority must be raw numeric literals, and status/submitted_at/iterations_run must be set explicitly -- task_queue has no DB-level defaults for them"

sql=$(build_submit_sql "shopee_th_shampoo" "targeted_qa_fix" "2026-06" "500" "300" "1" "999")
grep -qF "'2026-06'" <<< "$sql" || fail "provided month should be quoted, not NULL"
grep -qF "500, 300" <<< "$sql" || fail "provided max_turns/block_size should be raw numeric literals, not quoted"
echo "PASS: build_submit_sql"

# --- build_list_sql ---
sql=$(build_list_sql "")
grep -qF "FROM public.task_queue" <<< "$sql" || fail "should target the fully-qualified QUEUE_TABLE"
[[ "$sql" != *"WHERE"* ]] || fail "no status filter should mean no WHERE clause"

sql=$(build_list_sql "queued")
grep -qF "WHERE status = 'queued'" <<< "$sql" || fail "status filter should produce a quoted WHERE clause"
echo "PASS: build_list_sql"

# --- build_priority_sql ---
sql=$(build_priority_sql "42" "500")
grep -qF "UPDATE public.task_queue" <<< "$sql" || fail "should target the fully-qualified QUEUE_TABLE"
grep -qF "SET priority = 500" <<< "$sql" || fail "should set the new priority"
grep -qF "WHERE id = 42 AND status = 'queued'" <<< "$sql" || fail "must guard the UPDATE to status='queued' only"
echo "PASS: build_priority_sql"

# --- build_cancel_sql ---
sql=$(build_cancel_sql "42")
grep -qF "UPDATE public.task_queue" <<< "$sql" || fail "should target the fully-qualified QUEUE_TABLE"
grep -qF "SET status = 'cancelled'" <<< "$sql" || fail "should set status to cancelled"
grep -qF "WHERE id = 42 AND status = 'queued'" <<< "$sql" || fail "must guard the UPDATE to status='queued' only"
echo "PASS: build_cancel_sql"

echo "ALL TESTS PASSED"
