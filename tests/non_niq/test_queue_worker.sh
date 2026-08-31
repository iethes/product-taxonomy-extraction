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
q="$(reclaim_stale_leases_query)"
echo "$q" | grep -q "script_type" || fail "reclaim query must be scoped to script_type -- an unscoped reclaim can un-claim a still-running NIQ row"
echo "$q" | grep -q "non_niq_qa" || fail "reclaim query must scope specifically to script_type='non_niq_qa'"
echo "PASS: reclaim_stale_leases_query is script_type-scoped"

# --- claim query is script_type-scoped ---
q="$(claim_next_task_query "test-worker-1")"
echo "$q" | grep -q "script_type='non_niq_qa'" || fail "claim query must only claim non_niq_qa rows, never NIQ rows"
echo "PASS: claim_next_task_query is script_type-scoped"

echo "ALL TESTS PASSED"
