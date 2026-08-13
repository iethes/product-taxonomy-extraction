#!/usr/bin/env bash
set -euo pipefail
# Self-test for script/non_niq/non_niq_qa.sh's pure helper functions.
# No network, BQ, or claude calls -- mirrors tests/niq/test_headless_taxonomy.sh's convention.
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
# The config Sheet's ecommerce_platform is lowercase ("shopee") but the source table's own column
# is Title-Case ("Shopee") -- confirmed live on babybath and telonoil. A lowercase WHERE filter
# against Title-Case data matches zero rows, always -- this was a real, previously-undetected bug.
echo "$q" | grep -q "s.ecommerce_platform = 'Shopee'" || fail "worklist_query must capitalize the platform filter to match the source table's Title-Case convention (got lowercase 'shopee' as input)"
if echo "$q" | grep -q "s.ecommerce_platform = 'shopee'"; then
  fail "worklist_query must never filter on the raw lowercase platform -- the source table stores Title-Case values, this would match zero rows"
fi
echo "$q" | grep -q "sc.ecommerce_platform" || fail "worklist_query must carry ecommerce_platform through to the final SELECT so the filter-table write uses the source table's real (Title-Case) value, not a reconstructed one"
# SAFE.JSON_VALUE(...) looks like the fix but is NOT valid BigQuery syntax (confirmed live:
# "SAFE with function json_value is not supported"). The correct, live-verified pattern is
# JSON_VALUE(SAFE.PARSE_JSON(_meta), ...) -- SAFE composes with PARSE_JSON, not JSON_VALUE.
echo "$q" | grep -q "JSON_VALUE(SAFE.PARSE_JSON(_meta)" || fail "worklist_query must read _meta via JSON_VALUE(SAFE.PARSE_JSON(_meta), ...)"
if echo "$q" | grep -q "SAFE.JSON_VALUE"; then
  fail "worklist_query must never call SAFE.JSON_VALUE -- it is not valid BigQuery syntax, use JSON_VALUE(SAFE.PARSE_JSON(_meta), ...) instead"
fi
if echo "$q" | grep -q "JSON_VALUE(_meta,"; then
  fail "worklist_query must never call JSON_VALUE directly on the raw _meta string -- it must go through SAFE.PARSE_JSON first"
fi
echo "$q" | grep -q "ORDER BY priority ASC, gmv_monthly DESC" || fail "worklist_query must order unreviewed before unconfident, then by GMV"
echo "$q" | grep -q "qa_status = 'Not Reviewed'" || fail "worklist_query must gate priority-0 rows to qa_status = 'Not Reviewed' per design spec"
# Substring greps cannot catch a dropped comma between CTEs -- assert the join literally.
[[ "$q" == *$'),\nprioritized AS ('* ]] || fail "the CTE list must be comma-joined before prioritized AS -- otherwise the query is a BigQuery syntax error"
grep -c "AS priority" <<< "$q" | grep -qx 1 || fail "priority must be computed exactly once (in the prioritized CTE), never restated in the outer WHERE"
echo "PASS: worklist_query"

# --- worklist_query enrichment (item_description/product_attributes_attrs) ---
# Shopee + a real enrichment table name -> enrichment_dedup CTE present with deduplication.
q_enriched=$(worklist_query "babybath.master_babybath_id_dev" "babybath.product_id_dict_qa" "prod_id" "2026-07" "shopee" "0_pipeline_babybath_shopee_id")
echo "$q_enriched" | grep -q "enrichment_dedup AS" || fail "worklist_query must create an enrichment_dedup CTE for deduplication"
echo "$q_enriched" | grep -q "QUALIFY ROW_NUMBER() OVER (PARTITION BY item_itemid ORDER BY timestamp DESC) = 1" || fail "worklist_query must dedupe enrichment table to latest row per item_itemid"
echo "$q_enriched" | grep -q "FROM \`sincere-hearth-273704.babybath.0_pipeline_babybath_shopee_id\`" || fail "worklist_query must reference the enrichment table in enrichment_dedup CTE"
echo "$q_enriched" | grep -q "LEFT JOIN enrichment_dedup e ON CAST(e.item_itemid AS STRING) = s.product_id" || fail "worklist_query must join the dedup CTE on item_itemid = product_id"
echo "$q_enriched" | grep -q "e.item_description, e.product_attributes_attrs" || fail "worklist_query must select item_description/product_attributes_attrs from the enrichment_dedup CTE"
echo "$q_enriched" | grep -q "sc.item_description, sc.product_attributes_attrs" || fail "worklist_query must carry item_description/product_attributes_attrs through to the final SELECT"

# Non-Shopee platform -> no join, NULL columns instead, even if an enrichment_table value is passed
# (confirmed live: non-Shopee 0_pipeline_* tables have a different schema with no description/specs).
q_noenrich=$(worklist_query "babybath.master_babybath_id_dev" "babybath.product_id_dict_qa" "prod_id" "2026-07" "lazada" "0_pipeline_babybath_lazada_id")
if echo "$q_noenrich" | grep -q "LEFT JOIN \`sincere-hearth-273704.babybath.0_pipeline"; then
  fail "worklist_query must never join the enrichment table for a non-Shopee platform"
fi
echo "$q_noenrich" | grep -q "NULL AS item_description, NULL AS product_attributes_attrs" || fail "worklist_query must select NULL item_description/product_attributes_attrs for non-Shopee platforms"

# No enrichment table given at all (Sheet's "0" column empty) -> same NULL fallback, even for Shopee.
q_missing=$(worklist_query "babybath.master_babybath_id_dev" "babybath.product_id_dict_qa" "prod_id" "2026-07" "shopee")
if echo "$q_missing" | grep -q "LEFT JOIN \`sincere-hearth-273704.babybath.0_pipeline"; then
  fail "worklist_query must not attempt a join when no enrichment_table is given"
fi
echo "PASS: worklist_query enrichment"

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
echo "$prompt" | grep -q "worklist row's OWN \`ecommerce_platform\` value verbatim" || fail "prompt must instruct using the worklist's real (Title-Case) ecommerce_platform value for the filter-table write, not a reconstructed/lowercased one"
echo "$prompt" | grep -q "babybath.filter_babybath" || fail "prompt must name the correct write-target filter table"
echo "$prompt" | grep -q "babybath_taxonomy_qa" || fail "prompt must name the Meilisearch index to search"
echo "$prompt" | grep -q "non_niq_helper.py retrieve" || fail "prompt must instruct batch retrieval via non_niq_helper.py's retrieve subcommand, not per-product"
echo "$prompt" | grep -q -- "--input-file" || fail "prompt must instruct the batch (--input-file/--output-file) retrieve contract, not a per-product call"
if echo "$prompt" | grep -q "curl.*POST.*search"; then
  fail "prompt must NOT tell Claude to construct its own Meilisearch search request -- retrieval is pre-computed by non_niq_helper.py"
fi
echo "$prompt" | grep -q "sku_type" || fail "prompt must reference the resolved dict identity column"
echo "$prompt" | grep -q "keywords_typo" || fail "prompt must reference the resolved dict typo column"
echo "$prompt" | grep -q "prod_id" || fail "prompt must reference the resolved QA primary-key column"
echo "$prompt" | grep -q "never the streaming API" || fail "prompt must repeat the DML-only / no-streaming-API constraint"
echo "$prompt" | grep -q "qa_confidence" || fail "prompt must instruct writing the qa_confidence _meta field"
echo "$prompt" | grep -q "human_review" || fail "prompt must instruct writing the human_review _meta field on the retry path"
echo "$prompt" | grep -q "Mapping table" || fail "prompt must state the mapping table is never modified"
echo "$prompt" | grep -q "product_attributes_attrs" || fail "STEP 2a must mention product_attributes_attrs as additional signal alongside item_description"
echo "$prompt" | grep -q "Step C: notify Discord" || fail "STEP 2c's mint-new-entry branch must notify Discord after Step B, before the QA-table write"
echo "$prompt" | grep -q "non_niq_helper.py notify-discord" || fail "prompt must instruct calling the notify-discord command"
echo "$prompt" | grep -q -- "--identity-col sku_type " || fail "notify-discord call must use the resolved dict_identity_col"
echo "$prompt" | grep -q -- "--dataset babybath" || fail "notify-discord call must pass the dataset"
echo "$prompt" | grep -q "never fails the session even if Discord is unreachable" || fail "prompt must tell Claude this call is non-blocking, don't wait/retry"

# QA-table identity column is hardcoded sku_type_complete and must NOT follow dict_identity_col.
# Plain `grep sku_type_complete` would pass vacuously here (dict_identity_col="sku_type" is its
# substring), so assert on the distinguishing context on both sides.
# The prompt hard-wraps, so single-line greps silently miss instructions split across lines (that
# is exactly how 2c's two QA-table writes survived the first pass at this fix). Flatten to one
# line first, then every assertion below is wrap-proof.
flat=$(echo "$prompt" | tr '\n' ' ' | tr -s ' ')

# All three QA-table write instructions -- 2b's, and BOTH of 2c's -- must name sku_type_complete.
echo "$flat" | grep -q "write those SAME brand/sku_type_complete values to \`sincere-hearth-273704.babybath.product_id_dict_qa\`" || fail "step 2b's QA-table write must name sku_type_complete"
echo "$flat" | grep -q "write CORRECTED (re-pointed) brand/sku_type_complete values to \`sincere-hearth-273704.babybath.product_id_dict_qa\`" || fail "step 2c's re-point QA-table write must name sku_type_complete, not the resolved dict_identity_col"
echo "$flat" | grep -q "write brand/sku_type_complete values pointing at the new entry to \`sincere-hearth-273704.babybath.product_id_dict_qa\`" || fail "step 2c's post-mint QA-table write must name sku_type_complete, not the resolved dict_identity_col"

# The general invariant: the dict identity column must never appear near a QA-table reference.
# \bsku_type([^_]|$) matches the dict value but not sku_type_complete. 140 chars of lookbehind
# covers the longest of the three write instructions above.
if echo "$flat" | grep -oE ".{0,140}product_id_dict_qa" | grep -qE "\bsku_type([^_]|\$)"; then
  fail "the dict identity column (sku_type) must never appear adjacent to a QA-table reference -- the two identity columns are decoupled"
fi

# ...and conversely it must still appear where it genuinely belongs: the dict table's own writes.
echo "$flat" | grep -q "Step A: insert brand + sku_type + keywords" || fail "the dict-table mint (Step A) must still use the resolved dict_identity_col"
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
grep -qF 'source "${REPO_ROOT}/script/load_env.sh"' <<< "$script_src" || fail "main() must source load_env.sh so DISCORD_WEBHOOK_URL (and other .env values) are available whether invoked directly or via the queue worker"
echo "PASS: main() QUEUE_SIGNAL wiring"

echo "ALL TESTS PASSED (part 2: prompt + main)"
