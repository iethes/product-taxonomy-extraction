#!/usr/bin/env bash
set -euo pipefail

# Self-test for script/niq/custom_headless_taxonomy.sh's pure helper functions.
# No network, BQ, or claude calls — mirrors tests/niq/test_headless_taxonomy.sh's convention.
# Run: bash tests/niq/test_custom_headless_taxonomy.sh

cd "$(dirname "$0")/../.."
source script/niq/custom_headless_taxonomy.sh

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- worklist_query ---
q=$(worklist_query "makanananjing" "9_makanananjing_my_daily" "makanananjing_my")
echo "$q" | grep -q "makanananjing.9_makanananjing_my_daily" || fail "worklist_query should reference dataset.table"
echo "$q" | grep -q "SUM(s.gmv_daily) AS gmv_monthly" || fail "worklist_query should sum daily gmv into gmv_monthly"
echo "$q" | grep -q "CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END" || fail "worklist_query must zero GWP gmv in the cumulative calc"
echo "$q" | grep -q "cumulative_gmv_pct <= 95" || fail "worklist_query should apply the 95% threshold"
echo "$q" | grep -q "master_table = 'makanananjing_my'" || fail "worklist_query should scope the taxonomy_map join by CATEGORY"
echo "$q" | grep -q "canonical_name IS NULL" || fail "worklist_query should filter to unmapped products"
echo "$q" | grep -q "s.country = 'MY'" || fail "worklist_query should derive country MY from category suffix makanananjing_my"
echo "PASS: worklist_query"

# --- worklist_query derives country from category suffix, not hardcoded ---
q=$(worklist_query "alatmusik" "9_alatmusik_id_daily" "alatmusik_id")
echo "$q" | grep -q "s.country = 'ID'" || fail "worklist_query should derive country ID from category suffix alatmusik_id, not hardcode MY"
echo "PASS: worklist_query country derivation"

# --- gap_count_query ---
q=$(gap_count_query "makanananjing" "9_makanananjing_my_daily" "makanananjing_my")
echo "$q" | grep -q "SELECT COUNT(\*) FROM (" || fail "gap_count_query should wrap the worklist in COUNT(*)"
echo "$q" | grep -q "canonical_name IS NULL" || fail "gap_count_query should still carry the worklist's NULL filter"
echo "PASS: gap_count_query"

# --- existing_llm_rows_query ---
q=$(existing_llm_rows_query "makanananjing_my")
echo "$q" | grep -q "master_table = 'makanananjing_my'" || fail "existing_llm_rows_query should scope by CATEGORY, not the source table name"
echo "$q" | grep -q "source = 'LLM'" || fail "existing_llm_rows_query must scope to source='LLM'"
echo "PASS: existing_llm_rows_query"

# --- decide_scenario ---
[[ "$(decide_scenario 0)" == "first_run" ]] || fail "0 existing rows -> first_run"
[[ "$(decide_scenario 1832)" == "top_up" ]] || fail "nonzero existing rows -> top_up"
echo "PASS: decide_scenario"

# --- compute_block_size ---
[[ "$(compute_block_size first_run 0)" == "2000" ]] || fail "first_run always claims 2000 regardless of gap_count"
[[ "$(compute_block_size top_up 50)" == "200" ]] || fail "top_up floors the block size at 200"
[[ "$(compute_block_size top_up 500)" == "500" ]] || fail "top_up scales the block size with gap_count"
[[ "$(compute_block_size top_up 5000)" == "2000" ]] || fail "top_up caps the block size at 2000"
echo "PASS: compute_block_size"

# --- build_first_run_prompt ---
prompt=$(build_first_run_prompt "makanananjing" "9_makanananjing_my_daily" "makanananjing_my" "2000")
echo "$prompt" | grep -q "master_table = 'makanananjing_my'" || fail "build_first_run_prompt should key writes by CATEGORY"
echo "$prompt" | grep -q "makanananjing.9_makanananjing_my_daily" || fail "build_first_run_prompt should reference the source table"
echo "$prompt" | grep -q "next_start + 1999" || fail "build_first_run_prompt should size the SKU block claim from block_size"
echo "$prompt" | grep -q "'custom_full_rebuild'" || fail "build_first_run_prompt should tag the SKU block scenario"
echo "$prompt" | grep -q "meta_agent='CLAUDE_CODE'" || fail "build_first_run_prompt should require meta_agent on every row"
echo "$prompt" | grep -q "G1 (no dual-mapping)" || fail "build_first_run_prompt should carry the hard-gate invariants"
echo "$prompt" | grep -qF "category_key = 'makanananjing.makanananjing_my'" || fail "build_first_run_prompt should check category_brief by dataset.category, not a fixed master_clean_niq prefix"
echo "$prompt" | grep -qF "bq load" || fail "build_first_run_prompt must instruct bq load for the brief write"
echo "$prompt" | grep -qv "git add docs/categories" || fail "build_first_run_prompt must not instruct a git commit anymore"
echo "PASS: build_first_run_prompt"

# --- build_topup_prompt ---
prompt=$(build_topup_prompt "makanankucing" "9_makanankucing_my_daily" "makanankucing_my" "1832" "1832")
echo "$prompt" | grep -q "master_table = 'makanankucing_my'" || fail "build_topup_prompt should key writes by CATEGORY"
echo "$prompt" | grep -q "'custom_topup'" || fail "build_topup_prompt should tag the SKU block scenario"
echo "$prompt" | grep -q "next_start + 1832 - 1" || fail "build_topup_prompt should size the SKU block claim from block_size"
echo "$prompt" | grep -q "WITHOUT --skip-coexistence" || fail "build_topup_prompt should require the strict coexistence gate"
echo "$prompt" | grep -qF "category_key = 'makanankucing.makanankucing_my'" || fail "build_topup_prompt should read category_brief by dataset.category"
echo "$prompt" | grep -qF "'TAXONOMY'" || fail "build_topup_prompt's history insert must be tagged TAXONOMY"
echo "$prompt" | grep -qv "git add docs/categories" || fail "build_topup_prompt must not instruct a git commit anymore"
echo "PASS: build_topup_prompt"

echo "ALL PASS"
