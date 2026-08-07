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
echo "$q" | grep -q "qa_status = 'Not Reviewed'" || fail "worklist_query must gate priority-0 rows to qa_status = 'Not Reviewed' per design spec"
# Substring greps cannot catch a dropped comma between CTEs -- assert the join literally.
[[ "$q" == *$'),\nprioritized AS ('* ]] || fail "the CTE list must be comma-joined before prioritized AS -- otherwise the query is a BigQuery syntax error"
grep -c "AS priority" <<< "$q" | grep -qx 1 || fail "priority must be computed exactly once (in the prioritized CTE), never restated in the outer WHERE"
echo "PASS: worklist_query"

# --- primary_filter_table ---
single="babybath.filter_babybath"
[[ "$(primary_filter_table "$single" "babybath")" == "babybath.filter_babybath" ]] || fail "single-value filter_table should return as-is"

multi="babysunscreen.filter_babysunscreen;sunscreen.filter_sunscreen_hanasui"
[[ "$(primary_filter_table "$multi" "babysunscreen")" == "babysunscreen.filter_babysunscreen" ]] || fail "should return the table in the row's own dataset, never the cross-dataset one"
echo "PASS: primary_filter_table"

echo "ALL TESTS PASSED (part 1: SQL builders)"

# --- build_qa_prompt ---
# dict_identity_col is deliberately "sku_type" here (never sku_type_complete): the QA table's
# identity column is hardcoded sku_type_complete, and the assertions below prove the two are not
# wired to each other.
prompt=$(build_qa_prompt "babybath" "shopee" "babybath.master_babybath_id_dev" \
  "babybath.product_id_dict_qa" "babybath.babybath_dict" "babybath.filter_babybath" \
  "prod_id" "sku_type" "keywords_typo" "babybath_taxonomy_qa" "SELECT 1 /* worklist */" \
  "telonoil.product_id_dict")

echo "$prompt" | grep -q "RELEVANT to this category" || fail "prompt must state the relevance-check step first"
echo "$prompt" | grep -q "do NOT create a taxonomy entry" || fail "prompt must state irrelevant products are dropped, never routed elsewhere"
echo "$prompt" | grep -q "babybath.filter_babybath" || fail "prompt must name the correct write-target filter table"
echo "$prompt" | grep -q "babybath_taxonomy_qa" || fail "prompt must name the Meilisearch index to search"
echo "$prompt" | grep -q "non_niq_embed.py embed-query" || fail "prompt must instruct batch embedding via the CLI helper, not per-product"
echo "$prompt" | grep -q -- "--input-file" || fail "prompt must instruct the batch (--input-file/--output-file) embed-query contract, not a per-product call"
echo "$prompt" | grep -q "sku_type" || fail "prompt must reference the resolved dict identity column"
echo "$prompt" | grep -q "keywords_typo" || fail "prompt must reference the resolved dict typo column"
echo "$prompt" | grep -q "prod_id" || fail "prompt must reference the resolved QA primary-key column"
echo "$prompt" | grep -q "never the streaming API" || fail "prompt must repeat the DML-only / no-streaming-API constraint"
echo "$prompt" | grep -q "qa_confidence" || fail "prompt must instruct writing the qa_confidence _meta field"
echo "$prompt" | grep -q "human_review" || fail "prompt must instruct writing the human_review _meta field on the retry path"
echo "$prompt" | grep -q "Mapping table" || fail "prompt must state the mapping table is never modified"

# QA-table identity column is hardcoded sku_type_complete and must NOT follow dict_identity_col.
# Plain `grep sku_type_complete` would pass vacuously here (dict_identity_col="sku_type" is its
# substring), so assert on the distinguishing context on both sides.
echo "$prompt" | grep -q "brand/sku_type_complete values to" || fail "QA-table writes must name sku_type_complete literally, not the resolved dict_identity_col"
if echo "$prompt" | grep -qE "brand/sku_type values to \`[^\`]*product_id_dict_qa"; then
  fail "QA-table writes must never use the dict identity column (sku_type) -- the two are decoupled"
fi
echo "$prompt" | grep -q ", dict_identity_col=sku_type, " || fail "prompt's resolved-config line must still carry the live dict_identity_col"
echo "$prompt" | grep -q "Never write sku_type to the QA table" || fail "prompt must warn against writing the dict identity column to the QA table"

# step2_block, configured branch
echo "$prompt" | grep -q "Prior mapping check against" || fail "configured product_id_dict must produce a real step 2b prior-mapping instruction"
echo "$prompt" | grep -q "telonoil.product_id_dict" || fail "step 2b must name the configured product_id_dict table"
echo "$prompt" | grep -q "INFORMATION_SCHEMA.COLUMNS" || fail "step 2b must tell the agent to discover the unresolved product_id_dict schema before querying it"

# step2_block, unconfigured ('-') branch
prompt_nodict=$(build_qa_prompt "babybath" "shopee" "babybath.master_babybath_id_dev" \
  "babybath.product_id_dict_qa" "babybath.babybath_dict" "babybath.filter_babybath" \
  "prod_id" "sku_type" "keywords_typo" "babybath_taxonomy_qa" "SELECT 1 /* worklist */" "-")
echo "$prompt_nodict" | grep -q "2b. SKIPPED for this category" || fail "an unconfigured ('-') product_id_dict must skip step 2b"
echo "$prompt_nodict" | grep -q "Go straight to 2c" || fail "the skipped step 2b must send the agent straight to 2c"
if echo "$prompt_nodict" | grep -q "Prior mapping check against"; then
  fail "an unconfigured product_id_dict must not emit the prior-mapping instruction"
fi
if echo "$prompt_nodict" | grep -qF "${PROJECT}.-"; then
  fail "an unconfigured product_id_dict must never reach the prompt as a table reference"
fi
echo "PASS: build_qa_prompt"

# --- extract_json_object / decide_queue_signal (local duplicates, same contract as headless_taxonomy.sh) ---
[[ "$(extract_json_object 'prose {"status":"complete"} trailing')" == '{"status":"complete"}' ]] || fail "extract_json_object should pull the JSON object out of mixed text"
echo "PASS: extract_json_object"

complete_output='{"result":"{\"status\":\"complete\"}"}'
[[ "$(decide_queue_signal "$complete_output")" == "DONE" ]] || fail "complete status should map to DONE"
blocked_output='{"result":"{\"status\":\"blocked\"}"}'
[[ "$(decide_queue_signal "$blocked_output")" == "BLOCKED" ]] || fail "blocked status should map to BLOCKED"
garbage_output='not json at all'
[[ "$(decide_queue_signal "$garbage_output")" == "FAILED" ]] || fail "unparseable output should map to FAILED, never silently succeed"
echo "PASS: decide_queue_signal"

# --- main() wiring (grep the script source, no execution) ---
script_src=$(cat script/non_niq/non_niq_qa.sh)
grep -qF 'echo "QUEUE_SIGNAL: NOTHING_TO_DO"' <<< "$script_src" || fail "main() must emit NOTHING_TO_DO when the worklist is empty, before spending a claude -p call"
grep -qF 'echo "QUEUE_SIGNAL: $(decide_queue_signal "$claude_output")"' <<< "$script_src" || fail "main() must emit the post-run signal derived from decide_queue_signal"
grep -qE 'claude_output=\$\(claude -p .*\) \|\| true' <<< "$script_src" || fail "main() must tolerate a non-zero claude exit (|| true) so the transcript still gets echoed under set -e"
grep -qF "product_id_dict=\$(echo \"\$category_json\" | jq -r '.product_id_dict')" <<< "$script_src" || fail "main() must extract product_id_dict from the Sheet row and pass it to build_qa_prompt"
grep -qF 'for t in "qa_table=$qa_table" "dict_table=$dict_table" "filter_table=$filter_table"' <<< "$script_src" || fail "main() must guard qa_table/dict_table/filter_table against the Sheet's unconfigured '-' marker (and only those three -- '-' is legal for product_id_dict)"
echo "PASS: main() QUEUE_SIGNAL wiring"

echo "ALL TESTS PASSED (part 2: prompt + main)"
