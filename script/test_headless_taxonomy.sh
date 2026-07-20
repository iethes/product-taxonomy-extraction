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

# --- existing_llm_rows_query ---
# Bug caught live against shopee_sg_diapers (2026-07-20): 908 keyword-seed HUMAN rows existed with zero
# LLM rows, but the unscoped COUNT(*) treated that as "existing coverage" and misrouted to top_up instead
# of first_run. Almost every category has HUMAN keyword-seed rows before Phase 5 ever runs (see
# docs/quality-standards.md's coverage table) — only source='LLM' rows are evidence of a genuine prior pass.
q=$(existing_llm_rows_query "shopee_th_suncare")
echo "$q" | grep -q "product_taxonomy_map" || fail "existing_llm_rows_query should hit product_taxonomy_map"
echo "$q" | grep -q "master_table = 'shopee_th_suncare'" || fail "existing_llm_rows_query should scope by master_table"
echo "$q" | grep -q "source = 'LLM'" || fail "existing_llm_rows_query must scope to source='LLM' — HUMAN keyword-seed rows don't count as prior LLM coverage"
echo "PASS: existing_llm_rows_query"

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
echo "$prompt" | grep -q "priority for Pass 2 is closing the coverage gap quickly, not per-row precision" || fail "build_first_run_prompt's Pass 2 must state the coverage-over-precision priority, same as build_topup_prompt"
echo "$prompt" | grep -q "G1 (no dual-mapping), G2 (no HUMAN+LLM coexistence), G4 (no cross-category mapping), and G5 (provenance) are structural invariants" || fail "build_first_run_prompt must state hard gates are never optional even under a speed-first approach"
# Bug caught live against shopee_sg_diapers (2026-07-20): STEP 1 originally told the agent to treat ANY
# existing product_taxonomy_map row as a discrepancy — but HUMAN keyword-seed rows are the normal, expected
# starting state for a first LLM pass. Only existing LLM rows indicate the wrapper's scenario detection
# was wrong.
echo "$prompt" | grep -q "HUMAN rows.*normal and expected" || fail "build_first_run_prompt must say existing HUMAN keyword-seed rows are normal for a first run, not a discrepancy"
echo "$prompt" | grep -q "existing LLM rows" || fail "build_first_run_prompt must call out existing LLM rows specifically as the real red flag"
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
# Bug caught live against shopee_th_suncare (2026-07-20 real run): the agent worked only 31 of 790 worklist
# rows, self-limiting to match this category's older QA History cadence (33-58/session), which reflects the
# OLD targeted_qa_fix.sh workflow's smaller 200-slot/30-turn scope — not this scenario's real budget. This
# script's job is coverage speed, not per-row precision (that's targeted_qa_fix.sh's job now); it must process
# in bulk and attempt the entire live worklist, not a self-selected sample.
echo "$prompt" | grep -q "Do NOT process the live worklist one product at a time" || fail "build_topup_prompt must forbid one-by-one per-product processing"
echo "$prompt" | grep -q "BULK SQL" || fail "build_topup_prompt must instruct bulk SQL mapping, not per-item image reads"
echo "$prompt" | grep -q "resolve the ENTIRE live worklist" || fail "build_topup_prompt must forbid self-limiting to a sample"
echo "$prompt" | grep -q "older QA History session sizes" || fail "build_topup_prompt must explicitly warn against copying this category's older (targeted_qa_fix.sh-era) session-size cadence"
echo "$prompt" | grep -q "priority for this session is closing the coverage gap quickly, not per-row precision" || fail "build_topup_prompt must state the coverage-over-precision priority"
echo "$prompt" | grep -q "script/targeted_qa_fix.sh is the dedicated follow-up tool" || fail "build_topup_prompt must point precision work at targeted_qa_fix.sh"
echo "$prompt" | grep -q "G1 (no dual-mapping), G2 (no HUMAN+LLM coexistence), G4 (no cross-category mapping), and G5 (provenance) are structural invariants and must still pass" || fail "build_topup_prompt must state hard gates are never optional even under a speed-first approach"
echo "PASS: build_topup_prompt"

echo "ALL TESTS PASSED (part 1)"
