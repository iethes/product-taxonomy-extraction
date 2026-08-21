#!/usr/bin/env bash
set -euo pipefail

# Self-test for script/niq/headless_taxonomy_v2.sh's pure helper functions.
# No network, BQ, or claude calls -- mirrors tests/niq/test_headless_taxonomy.sh's convention.
# Run: bash tests/niq/test_headless_taxonomy_v2.sh

cd "$(dirname "$0")/../.."
source script/niq/headless_taxonomy_v2.sh

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- decide_scenario / compute_block_size (ported verbatim from V1 -- same behavior expected) ---
[[ "$(decide_scenario 0)" == "first_run" ]] || fail "0 existing rows -> first_run"
[[ "$(decide_scenario 5000)" == "top_up" ]] || fail "nonzero existing rows -> top_up"
[[ "$(compute_block_size first_run 0)" == "2000" ]] || fail "first_run always claims 2000"
[[ "$(compute_block_size top_up 50)" == "200" ]] || fail "top_up floors the block size at 200"
[[ "$(compute_block_size top_up 500)" == "500" ]] || fail "top_up scales the block size with gap_count"
[[ "$(compute_block_size top_up 5000)" == "2000" ]] || fail "top_up caps the block size at 2000"
echo "PASS: decide_scenario / compute_block_size"

# --- build_topup_prompt_v2 ---
sample_worklist='[{"product_id":"P1","sku_name":"Sweety Silver Pants M","merchant_name":"Some Reseller","gmv":500000,"candidates":[{"taxonomy_id":"SKU-000001","canonical_name":"Sweety Silver Pants M x8","source_table":"shopee_id_adult_diapers","match_tier":"brand_match","normalized_distance":0.12}]}]'
prompt=$(build_topup_prompt_v2 "shopee_id_adult_diapers" "2026-06" "500" "412" "$sample_worklist")
echo "$prompt" | grep -q "shopee_id_adult_diapers" || fail "build_topup_prompt_v2 should mention the table"
echo "$prompt" | grep -qF "$sample_worklist" || fail "build_topup_prompt_v2 must embed the worklist JSON verbatim"
echo "$prompt" | grep -q "pre-fetched" || fail "build_topup_prompt_v2 must tell the agent the worklist is pre-fetched, not something to query itself"
echo "$prompt" | grep -q "source_table" || fail "build_topup_prompt_v2 must explain the source_table field"
echo "$prompt" | grep -q "never map a product directly to a cross-market taxonomy_id" || fail "build_topup_prompt_v2 must forbid direct cross-market mapping"
echo "$prompt" | grep -q "taxonomy_topup" || fail "build_topup_prompt_v2 should claim a taxonomy_topup-scenario SKU block"
echo "$prompt" | grep -q "status='blocked'" || fail "build_topup_prompt_v2 should document the blocked outcome"
echo "PASS: build_topup_prompt_v2"

# --- build_first_run_prompt_v2 ---
sample_pool='[{"product_id":"P2","sku_name":"Lively Underpad 60x90","merchant_name":"Reseller B","gmv":90000,"candidates":[{"taxonomy_id":"SKU-000099","canonical_name":"Lively Underpad 60x90cm x12","source_table":"shopee_th_adult_diapers","match_tier":"text_only","normalized_distance":0.2}]}]'
prompt=$(build_first_run_prompt_v2 "shopee_id_adult_diapers" "2026-06" "2000" "$sample_pool")
echo "$prompt" | grep -q "shopee_id_adult_diapers" || fail "build_first_run_prompt_v2 should mention the table"
echo "$prompt" | grep -qF "$sample_pool" || fail "build_first_run_prompt_v2 must embed the cross-market candidate JSON verbatim"
echo "$prompt" | grep -q "CASE WHEN flag_GWP THEN 0 ELSE" || fail "build_first_run_prompt_v2's brand-scope step must still zero GWP gmv"
echo "$prompt" | grep -q "never be used to decide whether an individual product gets extracted" || fail "build_first_run_prompt_v2 must forbid keyword pre-filtering of individual products"
echo "$prompt" | grep -q "pattern.*reference" || fail "build_first_run_prompt_v2 must frame sibling-table candidates as pattern reference, not direct-map targets"
echo "$prompt" | grep -q "status='blocked'" || fail "build_first_run_prompt_v2 should document the blocked outcome"
echo "PASS: build_first_run_prompt_v2"

# --- decide_queue_signal (ported verbatim from V1) ---
complete_output='{"result": "{\"status\": \"complete\", \"rows_created\": 5}"}'
[[ "$(decide_queue_signal "$complete_output")" == "DONE" ]] || fail "status=complete -> DONE"
blocked_output='{"result": "{\"status\": \"blocked\", \"blockers\": [\"x\"]}"}'
[[ "$(decide_queue_signal "$blocked_output")" == "BLOCKED" ]] || fail "status=blocked -> BLOCKED"
malformed_output='not json at all'
[[ "$(decide_queue_signal "$malformed_output")" == "FAILED" ]] || fail "unparseable output -> FAILED"
echo "PASS: decide_queue_signal"

# --- main() wiring (static check -- live bq/python/claude calls are out of scope here) ---
script_src=$(cat script/niq/headless_taxonomy_v2.sh)
grep -qF 'python3 script/niq/headless_v2_worklist.py --table "$table" --scenario "$scenario" --month "$month" --block-size "$block_size"' <<< "$script_src" || fail "main() must build the worklist via headless_v2_worklist.py with all four flags"
grep -qF 'if [[ "$worklist_json" == "[]" ]]; then' <<< "$script_src" || fail "main() must detect an empty worklist"
grep -qF 'echo "QUEUE_SIGNAL: NOTHING_TO_DO"' <<< "$script_src" || fail "main() must emit NOTHING_TO_DO when gap_count==0 or the worklist is empty"
grep -qF '<<< "$prompt"' <<< "$script_src" || fail "main() must pipe the prompt into claude -p via stdin, not argv (worklist JSON can exceed argv limits)"
grep -qF 'echo "QUEUE_SIGNAL: $(decide_queue_signal "$claude_output")"' <<< "$script_src" || fail "main() must emit the post-run signal derived from decide_queue_signal"
echo "PASS: main() wiring (static check)"

echo "ALL TESTS PASSED"
