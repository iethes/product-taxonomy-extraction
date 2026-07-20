#!/usr/bin/env bash
set -euo pipefail

# Self-test for script/headless_taxonomy.sh's pure helper functions.
# No network, BQ, or claude calls — mirrors script/test_targeted_qa_fix.sh's convention.
# Run: bash script/test_headless_taxonomy.sh

cd "$(dirname "$0")/.."
source script/headless_taxonomy.sh

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- worklist_query ---
q=$(worklist_query "shopee_th_suncare" "2026-06")
echo "$q" | grep -q "master_clean_niq.shopee_th_suncare" || fail "worklist_query should reference the source table"
echo "$q" | grep -q "2026-06" || fail "worklist_query should reference the month"
echo "$q" | grep -q "CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END" || fail "worklist_query must zero GWP gmv in the cumulative calc"
echo "$q" | grep -q "canonical_name IS NULL" || fail "worklist_query should filter to unmapped products"
echo "$q" | grep -q "cumulative_gmv_pct <= 95" || fail "worklist_query should apply the 95% threshold"
echo "PASS: worklist_query"

# --- gap_count_query ---
q=$(gap_count_query "shopee_th_suncare" "2026-06")
echo "$q" | grep -q "SELECT COUNT(\*) FROM (" || fail "gap_count_query should wrap the worklist in COUNT(*)"
echo "$q" | grep -q "canonical_name IS NULL" || fail "gap_count_query should still carry the worklist's NULL filter"
echo "PASS: gap_count_query"

# --- existing_rows_query ---
q=$(existing_rows_query "shopee_th_suncare")
echo "$q" | grep -q "product_taxonomy_map" || fail "existing_rows_query should hit product_taxonomy_map"
echo "$q" | grep -q "master_table = 'shopee_th_suncare'" || fail "existing_rows_query should scope by master_table"
echo "PASS: existing_rows_query"

# --- default_month_query ---
q=$(default_month_query "shopee_th_suncare")
echo "$q" | grep -q "MAX(month)" || fail "default_month_query should find the latest month"
echo "$q" | grep -q "master_clean_niq.shopee_th_suncare" || fail "default_month_query should reference the source table"
echo "PASS: default_month_query"

# --- decide_scenario ---
[[ "$(decide_scenario 0)" == "first_run" ]] || fail "0 existing rows -> first_run"
[[ "$(decide_scenario 5000)" == "top_up" ]] || fail "nonzero existing rows -> top_up"
echo "PASS: decide_scenario"

# --- compute_block_size ---
[[ "$(compute_block_size first_run 0)" == "2000" ]] || fail "first_run always claims 2000 regardless of gap_count"
[[ "$(compute_block_size top_up 50)" == "200" ]] || fail "top_up floors the block size at 200"
[[ "$(compute_block_size top_up 500)" == "500" ]] || fail "top_up scales the block size with gap_count"
[[ "$(compute_block_size top_up 5000)" == "2000" ]] || fail "top_up caps the block size at 2000"
echo "PASS: decide_scenario / compute_block_size"

# --- build_first_run_prompt ---
prompt=$(build_first_run_prompt "shopee_th_conditioner" "2026-06" "2000")
echo "$prompt" | grep -q "shopee_th_conditioner" || fail "build_first_run_prompt should mention the table"
echo "$prompt" | grep -q "2026-06" || fail "build_first_run_prompt should mention the resolved month"
echo "$prompt" | grep -q "2000" || fail "build_first_run_prompt should mention the claimed block size"
echo "$prompt" | grep -q "CASE WHEN flag_GWP THEN 0 ELSE" || fail "build_first_run_prompt's brand-scope step must zero GWP gmv"
echo "$prompt" | grep -q "never be used to decide whether an individual product gets extracted" || fail "build_first_run_prompt must forbid keyword pre-filtering of individual products"
echo "$prompt" | grep -q "status='blocked'" || fail "build_first_run_prompt should document the blocked outcome"
echo "PASS: build_first_run_prompt"

# --- build_topup_prompt ---
prompt=$(build_topup_prompt "shopee_th_suncare" "2026-06" "500" "412")
echo "$prompt" | grep -q "shopee_th_suncare" || fail "build_topup_prompt should mention the table"
echo "$prompt" | grep -q "412" || fail "build_topup_prompt should mention the pre-check gap_count as a hint"
echo "$prompt" | grep -q "do NOT trust that number" || fail "build_topup_prompt must tell the agent to re-verify the gap live"
echo "$prompt" | grep -q "reuse-before-mint" || fail "build_topup_prompt must instruct reuse-before-mint against existing taxonomy"
echo "$prompt" | grep -q "never be used to decide whether an individual product gets extracted" || fail "build_topup_prompt must forbid keyword pre-filtering of individual products"
echo "$prompt" | grep -q "taxonomy_topup" || fail "build_topup_prompt should claim a taxonomy_topup-scenario SKU block"
echo "$prompt" | grep -q "500" || fail "build_topup_prompt should mention the computed block size"
echo "$prompt" | grep -q "status='blocked'" || fail "build_topup_prompt should document the blocked outcome"
echo "PASS: build_topup_prompt"

echo "ALL TESTS PASSED (part 1)"
