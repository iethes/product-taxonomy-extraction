#!/usr/bin/env bash
set -euo pipefail
# Self-test for script/non_niq/queue_worker.sh's pure helper functions.
# No network, Postgres, or claude calls -- mirrors tests/niq/test_queue_worker.sh's convention.
# Run: bash tests/non_niq/test_queue_worker.sh

cd "$(dirname "$0")/../.."
source script/non_niq/queue_worker.sh

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- split_table_name ---
read -r ds pl co <<< "$(split_table_name "babybath:shopee")"
[[ "$ds" == "babybath" && "$pl" == "shopee" && "$co" == "ID" ]] || fail "split_table_name should split dataset:platform on the colon and default country to ID"
echo "PASS: split_table_name (2-segment, default country)"

read -r ds pl co <<< "$(split_table_name "babybath:shopee:TH")"
[[ "$ds" == "babybath" && "$pl" == "shopee" && "$co" == "TH" ]] || fail "split_table_name should split dataset:platform:country on the colons"
echo "PASS: split_table_name (3-segment, explicit country)"

# --- reclaim query is script_type-scoped ---
q="$(reclaim_stale_leases_query "non_niq_qa")"
echo "$q" | grep -q "script_type" || fail "reclaim query must be scoped to script_type -- an unscoped reclaim can un-claim a still-running NIQ row"
echo "$q" | grep -q "non_niq_qa" || fail "reclaim query must scope specifically to script_type='non_niq_qa'"
echo "PASS: reclaim_stale_leases_query is script_type-scoped"

# --- claim query is script_type-scoped ---
q="$(claim_next_task_query "test-worker-1" "non_niq_qa")"
echo "$q" | grep -q "script_type='non_niq_qa'" || fail "claim query must only claim non_niq_qa rows, never NIQ rows"
echo "PASS: claim_next_task_query is script_type-scoped"

# A host-wide Codex sandbox failure must stop the worker before its first queue claim.
# Stub the environment loader and queue loop so this exercises main() without Postgres.
preflight_dir=$(mktemp -d)
trap 'rm -rf "$preflight_dir"' EXIT
cat > "$preflight_dir/bwrap" <<'BWRAP'
#!/usr/bin/env bash
echo 'bwrap: setting up uid map: Permission denied' >&2
exit 1
BWRAP
chmod +x "$preflight_dir/bwrap"
if output=$(
  source() { return 0; }
  queue_main_loop() { echo 'QUEUE_LOOP_CALLED'; }
  AGENT_HARNESS=codex
  QUEUE_DATABASE_URL=postgresql://example.invalid/unused
  PATH="$preflight_dir:$PATH"
  main 2>&1
  ); then
  fail "worker must fail before claiming when the Codex sandbox cannot start"
fi
[[ "$output" == *'bwrap: setting up uid map: Permission denied'* ]] || fail "worker must report the bubblewrap error"
[[ "$output" == *'stopped before claiming a task'* ]] || fail "worker must explain why it stopped"
[[ "$output" != *'QUEUE_LOOP_CALLED'* ]] || fail "worker must not enter the queue loop on sandbox failure"
echo "PASS: Codex sandbox failure stops worker before queue claim"

if ! output=$(
  source() { return 0; }
  queue_main_loop() { echo 'QUEUE_LOOP_CALLED'; }
  AGENT_HARNESS=claude
  QUEUE_DATABASE_URL=postgresql://example.invalid/unused
  PATH="$preflight_dir:$PATH"
  main 2>&1
  ); then
  fail "Claude worker must remain unaffected by Codex sandbox preflight"
fi
[[ "$output" == *'QUEUE_LOOP_CALLED'* ]] || fail "Claude worker must enter the queue loop"
echo "PASS: Claude worker still enters queue loop"

echo "ALL TESTS PASSED"
