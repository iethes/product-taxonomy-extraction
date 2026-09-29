#!/usr/bin/env bash
set -euo pipefail
# Self-test for script/non_niq/susubayi_qa.sh's pure helper functions -- scoped to what was ported
# from non_niq_qa_v2.sh (AGENT_HARNESS gate, Claude/Codex result normalization, retry-limit
# detection) and the per-platform scope rules, not a full re-port of test_non_niq_qa_v2.sh.
# No network, BQ, or claude/codex calls.
# Run: bash tests/non_niq/test_susubayi_qa.sh

cd "$(dirname "$0")/../.."
source script/non_niq/susubayi_qa.sh

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- require_harness (AGENT_HARNESS availability gate, identical contract to non_niq_qa_v2.sh) ---
require_harness "claude" || fail "require_harness must accept 'claude'"
require_harness "not_a_real_harness" 2>/dev/null && fail "require_harness must reject an unrecognized harness name"
require_harness "pi" 2>/dev/null && fail "require_harness must reject 'pi' -- only claude/codex are wired up"
echo "PASS: require_harness"

# --- worklist_query scope: source Tier 1 + Official Store ---
q_tokopedia=$(worklist_query "susubayi.master_susubayi_id" "susubayilemonilo.product_id_dict_qa" "prod_id" "2026-07" "tokopedia")
echo "$q_tokopedia" | grep -qF "s.product_tier IN ('Tier 1')" || fail "worklist_query (tokopedia) must include Tier 1 products"
echo "$q_tokopedia" | grep -qF "s.principal = 'Official Store'" || fail "worklist_query (tokopedia) must include every Official Store regardless of GMV"
if echo "$q_tokopedia" | grep -qF "s.gmv_monthly > 0"; then
  fail "worklist_query (tokopedia) must not use positive GMV as an independent scope condition"
fi
echo "$q_tokopedia" | grep -qF "IN ('Tokopedia', 'Tokopedia | Shop')" || fail "worklist_query (tokopedia) must include Tokopedia | Shop"
if echo "$q_tokopedia" | grep -qF "WHEN s.ecommerce_platform = 'Tokopedia | Shop' THEN 'Tokopedia'"; then fail "worklist_query must preserve raw Tokopedia platform values"; fi
echo "$q_tokopedia" | grep -qF "REGEXP_REPLACE(TRIM(sku_name), r'\s+', ' ') AS normalized_sku_name" || fail "worklist_query must track QA state at normalized current-title grain"
echo "$q_tokopedia" | grep -qF "qts.normalized_sku_name = REGEXP_REPLACE(TRIM(sc.sku_name), r'\s+', ' ')" || fail "worklist_query must not let an old title suppress a reused product_id"

q=$(worklist_query "susubayi.master_susubayi_id" "susubayilemonilo.product_id_dict_qa" "prod_id" "2026-07" "shopee")
echo "$q" | grep -qF "s.product_tier IN ('Tier 1')" || fail "worklist_query (shopee) must use the source tier scope"
echo "$q" | grep -qF "s.principal = 'Official Store'" || fail "worklist_query (shopee) must still force-include Official Store regardless of GMV"
q_blibli=$(worklist_query "susubayi.master_susubayi_id" "susubayilemonilo.product_id_dict_qa" "prod_id" "2026-07" "blibli")
echo "$q_blibli" | grep -qF "s.product_tier IN ('Tier 1')" || fail "worklist_query (blibli) must use the source tier scope"
echo "$q_blibli" | grep -qF "master_mji_sellout_blibli" || fail "worklist_query (blibli) must still union the sellout feed"
q_forced=$(worklist_query "susubayi.master_susubayi_id" "susubayilemonilo.product_id_dict_qa" "prod_id" "2026-07" "tokopedia" "" "300" "" "'123','456'")
echo "$q_forced" | grep -qF "s.merchant_id IN ('123','456')" || fail "worklist_query must still OR in forced_merchant_ids_sql when given"
echo "PASS: worklist_query scope"

# --- build_qa_prompt: agent_meta_source threads into every _meta write, never hardcoded ---
prompt_claude=$(build_qa_prompt "shopee" "ID" "susubayi.master_susubayi_id" "qa" "dict" "filter" \
  "prod_id" "sku_type_complete" "keywords_typo" "susubayi_taxonomy_qa" "/tmp/w.jsonl" "1" "-" "susubayi_shopee_ID" "claude_code")
echo "$prompt_claude" | grep -qF '{"source":"claude_code","timestamp":"<now, ISO 8601 UTC>"}' || fail "build_qa_prompt must stamp _meta writes with the given agent_meta_source (claude_code)"
prompt_codex=$(build_qa_prompt "shopee" "ID" "susubayi.master_susubayi_id" "qa" "dict" "filter" \
  "prod_id" "sku_type_complete" "keywords_typo" "susubayi_taxonomy_qa" "/tmp/w.jsonl" "1" "-" "susubayi_shopee_ID" "codex")
echo "$prompt_codex" | grep -qF '{"source":"codex","timestamp":"<now, ISO 8601 UTC>"}' || fail "build_qa_prompt must stamp _meta writes with source=codex when given"
if echo "$prompt_codex" | grep -qF '"source":"claude_code"'; then
  fail "build_qa_prompt (codex) must not leave any hardcoded claude_code _meta stamp behind"
fi
grep -qF "wrapper already ran one batch Meilisearch retrieval" <<< "$prompt_claude" || fail "prompt must consume wrapper-side retrieval"
if grep -q "non_niq_helper.py retrieve" <<< "$prompt_claude"; then
  fail "prompt must not repeat wrapper-side retrieval"
fi
echo "$prompt_claude" | grep -qF "non_niq_taxonomy_insert_log" || fail "susubayi prompt must require the shared taxonomy insert log"
echo "$prompt_claude" | grep -qF "SAME BigQuery transaction" || fail "susubayi prompt must require atomic dictionary/log writes"
echo "$prompt_claude" | grep -qF '"inserted_row"' || fail "susubayi prompt must define the inserted_row JSON envelope"
echo "$prompt_claude" | grep -qF "do not INSERT yet" || fail "Step A must defer the dictionary INSERT so 2c.1 logs the one true inserted row"
if echo "$prompt_claude" | grep -qF "fix any NULL found"; then
  fail "prompt must not instruct a post-insert UPDATE -- that would insert-then-mutate outside 2c.1's logged transaction"
fi
echo "PASS: build_qa_prompt agent_meta_source"

# --- extract_result_json: normalizes both Claude's envelope and Codex's bare result object ---
[[ "$(extract_result_json '{"result":"{\"status\":\"complete\"}"}')" == '{"status":"complete"}' ]] || fail "extract_result_json should pull the inner result JSON out of a Claude envelope"
[[ "$(extract_result_json '{"status":"complete","rows_qa_confirmed":1}')" == '{"status":"complete","rows_qa_confirmed":1}' ]] || fail "extract_result_json should accept Codex's direct final JSON object"
[[ "$(extract_result_json '{"result":""}')" == "" ]] || fail "extract_result_json should return empty when .result itself is empty"

# --- residual accounting: never merge automatic totals into an under-counted agent result ---
residual_counts_cover_worklist '{"rows_qa_confirmed":1,"rows_qa_unconfident":0,"rows_filtered":0,"rows_unresolved":0}' 1 || fail "residual counts should cover Susubayi worklist"
residual_counts_cover_worklist '{"rows_qa_confirmed":0,"rows_qa_unconfident":0,"rows_filtered":0,"rows_unresolved":0}' 1 && fail "under-counted Susubayi residual must block automatic-total merge"
residual_counts_cover_worklist '{"rows_qa_confirmed":-1,"rows_qa_unconfident":2,"rows_filtered":0,"rows_unresolved":0}' 1 && fail "negative Susubayi residual counts must block automatic-total merge"
echo "PASS: residual accounting"
echo "PASS: extract_result_json"

# --- is_claude_rate_limited / decide_queue_signal (unchanged contract, sanity check only) ---
is_claude_rate_limited '{"api_error_status":429,"num_turns":1}' || fail "is_claude_rate_limited must detect a 429 with num_turns<=1"
is_claude_rate_limited '{"api_error_status":429,"num_turns":20}' && fail "is_claude_rate_limited must NOT treat a 429 after real turns as a clean rate-limit retry"
[[ "$(decide_queue_signal '{"result":"{\"status\":\"complete\"}"}')" == "DONE" ]] || fail "decide_queue_signal must map status=complete to DONE"
echo "PASS: is_claude_rate_limited / decide_queue_signal"

# --- main() wiring: automatic confirmation precedes the residual-agent adapter ---
script_src=$(cat script/non_niq/susubayi_qa.sh)
grep -qF 'non_niq_helper.py" auto-confirm' <<< "$script_src" || fail "main() must auto-confirm exact-title Meilisearch matches"
grep -qF 'rows_auto_confirmed=$auto_confirmed' <<< "$script_src" || fail "main() must expose automatic confirmation counts"
grep -qF -- '-c sandbox_workspace_write.network_access=true' <<< "$script_src" || fail "main() must enable network access for Codex's workspace-write sandbox"
grep -qF 'signal=$(decide_queue_signal "$agent_output")' <<< "$script_src" || fail "main() must derive the post-run signal from the normalized agent_output, not a claude-only variable"
echo "PASS: main() wiring"

# --- main() wiring: code-side backstop for 2c.1's agent-trusted insert-log contract ---
grep -qF 'apply_taxonomy_insert_log_backstop "$agent_output" \' <<< "$script_src" \
  || fail "main() must run the shared insert-log backstop against this dataset's dict_table"
grep -qF 'run_start=$(date -u' <<< "$script_src" \
  || fail "main() must capture run_start before dispatching the agent, to scope the gap check"
if grep -qF '! agent_output=$(apply_taxonomy_insert_log_backstop' <<< "$script_src" && \
   grep -qF 'residual_valid=false' <<< "$script_src"; then
  :
else
  fail "main() must block the queue signal when the backstop finds an unlogged dictionary row"
fi
echo "PASS: main() insert-log gap backstop wiring"

echo "ALL TESTS PASSED"
