#!/usr/bin/env bash
set -euo pipefail
# Self-test for script/non_niq/non_niq_qa.sh's pure helper functions.
# No network, BQ, or claude calls -- mirrors script/test_headless_taxonomy.sh's convention.
# Run: bash script/non_niq/test_non_niq_qa.sh

cd "$(dirname "$0")/../.."
source script/non_niq/non_niq_qa.sh

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- default_month_query ---
q=$(default_month_query "babybath.master_babybath_id_dev")
echo "$q" | grep -q "MAX(month)" || fail "default_month_query should find the latest month"
echo "$q" | grep -q "babybath.master_babybath_id_dev" || fail "default_month_query should reference the source table"
echo "PASS: default_month_query"

# --- worklist_query ---
q=$(worklist_query "babybath.master_babybath_id_dev" "babybath.product_id_dict_qa" "prod_id" "2026-07" "shopee")
echo "$q" | grep -q "babybath.master_babybath_id_dev" || fail "worklist_query should reference the source table"
echo "$q" | grep -q "babybath.product_id_dict_qa" || fail "worklist_query should reference the QA table"
echo "$q" | grep -q "prod_id" || fail "worklist_query should use the resolved QA primary-key column, not a hardcoded one"
echo "$q" | grep -q "cumulative_gmv_pct <= 90" || fail "worklist_query must use the 90% threshold (issue #2), not the epic's 95%"
echo "$q" | grep -q "SAFE.JSON_VALUE" || fail "worklist_query must use SAFE.JSON_VALUE, never bare JSON_VALUE, when reading _meta"
if echo "$q" | grep -qE '(^|[^.])JSON_VALUE'; then
  fail "worklist_query must never call bare JSON_VALUE (only SAFE.JSON_VALUE) on _meta"
fi
echo "$q" | grep -q "ORDER BY priority ASC, gmv_monthly DESC" || fail "worklist_query must order unreviewed before unconfident, then by GMV"
echo "PASS: worklist_query"

# --- primary_filter_table ---
single="babybath.filter_babybath"
[[ "$(primary_filter_table "$single" "babybath")" == "babybath.filter_babybath" ]] || fail "single-value filter_table should return as-is"

multi="babysunscreen.filter_babysunscreen;sunscreen.filter_sunscreen_hanasui"
[[ "$(primary_filter_table "$multi" "babysunscreen")" == "babysunscreen.filter_babysunscreen" ]] || fail "should return the table in the row's own dataset, never the cross-dataset one"
echo "PASS: primary_filter_table"

echo "ALL TESTS PASSED (part 1: SQL builders)"
