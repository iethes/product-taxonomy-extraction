#!/usr/bin/env bash
set -euo pipefail

# Self-test for script/niq/targeted_qa_fix_v2.sh's pure helper functions. No network, BQ, or claude calls --
# same scope discipline as tests/niq/test_targeted_qa_fix.sh.
# Run: bash tests/niq/test_targeted_qa_fix_v2.sh

cd "$(dirname "$0")/../.."
source script/niq/targeted_qa_fix_v2.sh

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- category_key_for ---
[[ "$(category_key_for "shopee_th_widget")" == "master_clean_niq.shopee_th_widget" ]] || fail "category_key_for should prefix with master_clean_niq"
echo "PASS: category_key_for"

# --- decide_next_step ---
[[ "$(decide_next_step '{"status":"blocked","blockers":["x"]}')" == "BLOCKED" ]] || fail "blocked status"
[[ "$(decide_next_step '{"status":"failed"}')" == "MARK_FAILED" ]] || fail "failed status"
[[ "$(decide_next_step '{"status":"complete","rows_created":5}')" == "GATE_AND_REFRESH" ]] || fail "complete with rows"
[[ "$(decide_next_step '{"status":"partial","rows_created":1}')" == "GATE_AND_REFRESH" ]] || fail "partial with rows"
[[ "$(decide_next_step '{"status":"complete","rows_created":0}')" == "NOOP" ]] || fail "complete with zero rows"
[[ "$(decide_next_step 'not json at all')" == "MARK_FAILED" ]] || fail "malformed json"
echo "PASS: decide_next_step"

# --- build_auto_discovery_prompt_v2 ---
sample_worklist='[{"taxonomy_id":"SKU-000001","canonical_name":"Sweety Silver Pants M","tier":"unlabelled","gmv":500000,"tier1_flags":{"null_size":true},"taxonomy_candidates":[],"brand_candidates":[],"sample_sku_names":["Sweety Silver M"]}]'
prompt=$(build_auto_discovery_prompt_v2 "shopee_th_diapers" "master_clean_niq.shopee_th_diapers" "$sample_worklist" 200)
echo "$prompt" | grep -q "SKU-000001" || fail "prompt must embed the worklist JSON verbatim"
echo "$prompt" | grep -q "never-reviewed rows before any unconfident row" || fail "prompt must document the strict-tier ordering it was given"
echo "$prompt" | grep -q "'targeted_qa_fix_v2'" || fail "SKU block claim must use the targeted_qa_fix_v2 scenario, matching mark_failed_qa's filter"
echo "$prompt" | grep -qF 'status: complete|partial|failed|blocked' || fail "prompt must specify the required output JSON shape"
echo "PASS: build_auto_discovery_prompt_v2"

# --- main(): worklist build + NOTHING_TO_DO short-circuit + post-processing wiring (static check -- live
# bq/python/claude calls are out of scope here, same convention as tests/niq/test_targeted_qa_fix.sh) ---
script_src=$(cat script/niq/targeted_qa_fix_v2.sh)
grep -qF 'worklist_json=$(python3 script/niq/qa_v2_worklist.py --table "$table" --block-size "$block_size")' <<< "$script_src" || fail "main() must build the worklist via qa_v2_worklist.py before invoking claude -p"
grep -qF 'if [[ "$worklist_json" == "[]" ]]; then' <<< "$script_src" || fail "main() must detect an empty worklist"
grep -qF 'echo "QUEUE_SIGNAL: NOTHING_TO_DO"' <<< "$script_src" || fail "main() must emit NOTHING_TO_DO when the worklist is empty"
grep -qF 'QA_FIX_TABLE="$table"' <<< "$script_src" || fail "main() must set QA_FIX_TABLE as a global for the EXIT trap to see"
grep -q 'trap.*qa_coverage_report\.sh.*EXIT' <<< "$script_src" || fail "main() must set an EXIT trap invoking qa_coverage_report.sh"
grep -qF 'build_auto_discovery_prompt_v2 "$table" "$category_key" "$worklist_json" "$block_size"' <<< "$script_src" || fail "main() must pass the worklist JSON to build_auto_discovery_prompt_v2"
grep -qF 'insert_qa_history_row' <<< "$script_src" || fail "main() must call insert_qa_history_row"
grep -qF 'echo "QUEUE_SIGNAL: BLOCKED"' <<< "$script_src" || fail "main() must emit BLOCKED in the BLOCKED case branch"
grep -qF 'echo "QUEUE_SIGNAL: FAILED"' <<< "$script_src" || fail "main() must emit FAILED in the MARK_FAILED and failed-gate branches"
signal_done_count=$(grep -cF 'echo "QUEUE_SIGNAL: DONE"' <<< "$script_src")
[[ "$signal_done_count" -eq 2 ]] || fail "main() must emit DONE in both the NOOP branch and the successful GATE_AND_REFRESH branch, got $signal_done_count occurrences"
echo "PASS: main() wiring (static check)"

echo "ALL TESTS PASSED"
