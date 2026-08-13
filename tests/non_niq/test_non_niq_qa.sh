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

# --- worklist_query row limit (Finding: unbounded worklists blow the turn budget) ---
# Default (no 7th arg) must be 300 -- live-observed that large categories (e.g. cookiesbiscuit,
# 6143 in-scope rows) exhaust a session's turn budget long before finishing.
echo "$q" | grep -q "LIMIT 300" || fail "worklist_query must default to LIMIT 300 when no row_limit is given"
q_row_limit=$(worklist_query "babybath.master_babybath_id_dev" "babybath.product_id_dict_qa" "prod_id" "2026-07" "shopee" "" "150")
echo "$q_row_limit" | grep -q "LIMIT 150" || fail "worklist_query must use the given row_limit when one is passed"
if echo "$q_row_limit" | grep -q "LIMIT 300"; then
  fail "worklist_query must not fall back to the default 300 when an explicit row_limit is given"
fi
# LIMIT must come after ORDER BY priority ASC, gmv_monthly DESC -- otherwise it would truncate an
# arbitrary (unordered) 300 rows instead of the highest-priority, highest-revenue ones.
[[ "$q_row_limit" == *$'ORDER BY priority ASC, gmv_monthly DESC\nLIMIT 150'* ]] || fail "LIMIT must come immediately after ORDER BY priority ASC, gmv_monthly DESC, not before it or on an unordered result"
echo "PASS: worklist_query row limit"

# --- worklist_query enrichment (item_description/product_attributes_attrs) ---
# Shopee + a real enrichment table name -> enrichment_dedup CTE present with deduplication.
q_enriched=$(worklist_query "babybath.master_babybath_id_dev" "babybath.product_id_dict_qa" "prod_id" "2026-07" "shopee" "0_pipeline_babybath_shopee_id")
echo "$q_enriched" | grep -q "enrichment_dedup AS" || fail "worklist_query must create an enrichment_dedup CTE for deduplication"
echo "$q_enriched" | grep -q "QUALIFY ROW_NUMBER() OVER (PARTITION BY item_itemid ORDER BY timestamp DESC) = 1" || fail "worklist_query must dedupe enrichment table to latest row per item_itemid"
echo "$q_enriched" | grep -q "FROM \`sincere-hearth-273704.babybath.0_pipeline_babybath_shopee_id\`" || fail "worklist_query must reference the enrichment table in enrichment_dedup CTE"
echo "$q_enriched" | grep -q "LEFT JOIN enrichment_dedup e ON CAST(e.item_itemid AS STRING) = s.product_id" || fail "worklist_query must join the dedup CTE on item_itemid = product_id"
echo "$q_enriched" | grep -q "e.item_description, e.product_attributes_attrs" || fail "worklist_query must select item_description/product_attributes_attrs from the enrichment_dedup CTE"
echo "$q_enriched" | grep -q "sc.item_description, sc.product_attributes_attrs" || fail "worklist_query must carry item_description/product_attributes_attrs through to the final SELECT"
# product_attributes_attrs must be projected down to a compact "name=value" string, not shipped as
# raw JSON -- live-measured on the FULL (untruncated, 140-row) babybath/shopee/2026-08 worklist:
# SUM(LENGTH(product_attributes_attrs)) dropped from 279503 (raw) to 28517 (compact) chars.
echo "$q_enriched" | grep -qF "STRING_AGG(CONCAT(JSON_VALUE(a,'\$.name'),'=',JSON_VALUE(a,'\$.value')), '; ')" || fail "worklist_query's enrichment_dedup CTE must project product_attributes_attrs down to a compact name=value string via STRING_AGG"
# Bare SAFE.PARSE_JSON(product_attributes_attrs) alone would null out ~94% of real rows (live-
# measured on the full enrichment table: 88280/94086 non-null only reachable via the fallback --
# most rows store this column as Python repr, single-quoted with None/True/False, not valid JSON).
# COALESCE tries the raw string first (so already-valid JSON, and any row whose real content has
# an apostrophe that the quote-swap would corrupt, is never touched by the fallback) and only
# normalizes (None/True/False -> null/true/false, ' -> ", via CHR() to dodge quoting hell) when the
# raw parse fails.
echo "$q_enriched" | grep -qF "COALESCE(" || fail "worklist_query must try raw SAFE.PARSE_JSON first and fall back to a normalized parse, not null out most real-world rows"
echo "$q_enriched" | grep -qF "SAFE.PARSE_JSON(product_attributes_attrs)," || fail "worklist_query's COALESCE must try the raw (untouched) product_attributes_attrs first, so already-valid JSON is never run through the Python-repr normalization"
echo "$q_enriched" | grep -qF "CHR(39), CHR(34)" || fail "worklist_query's Python-repr fallback must swap single quotes for double quotes (via CHR() to avoid bash/SQL quoting issues) so SAFE.PARSE_JSON can parse it"
echo "$q_enriched" | grep -qF "': None', ': null'" || fail "worklist_query's Python-repr fallback must normalize None/True/False to JSON's null/true/false"
if echo "$q_enriched" | grep -qE "SELECT item_itemid, item_description, product_attributes_attrs$"; then
  fail "worklist_query must not select the raw product_attributes_attrs column directly -- it must go through the STRING_AGG compaction"
fi

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

# enrichment_table literal string "null" (jq -r on a missing/null JSON key) must be treated the
# same as "-"/empty -- consistency with main()'s three-sentinel guard (line ~432-438), even though
# this is currently unreachable (parse_categories always emits a "0" key today).
q_null_sentinel=$(worklist_query "babybath.master_babybath_id_dev" "babybath.product_id_dict_qa" "prod_id" "2026-07" "shopee" "null")
if echo "$q_null_sentinel" | grep -q "LEFT JOIN \`sincere-hearth-273704.babybath.0_pipeline"; then
  fail "worklist_query must treat the literal string 'null' the same as an unconfigured enrichment_table, never join sincere-hearth-273704.babybath.null"
fi
echo "$q_null_sentinel" | grep -q "NULL AS item_description, NULL AS product_attributes_attrs" || fail "worklist_query must select NULL item_description/product_attributes_attrs when enrichment_table is the literal string 'null'"
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
  "prod_id" "sku_type" "keywords_typo" "babybath_taxonomy_qa" "/tmp/babybath_shopee_full_worklist.jsonl" \
  "42" "telonoil.product_id_dict")

# STEP 0 must point Claude at the materialized worklist FILE + its exact row count, never hand it
# raw SQL to re-run itself -- re-running the enriched query yourself can render 18-320x larger than
# before enrichment (live-measured: 46 KB -> 14.7 MB on a 140-row category), which was silently
# truncating what Claude actually saw while it still reported status: partial (mapped to
# QUEUE_SIGNAL: DONE, so a truncated run looked identical to a finished one).
echo "$prompt" | grep -qF "/tmp/babybath_shopee_full_worklist.jsonl" || fail "STEP 0 must reference the materialized worklist file path"
echo "$prompt" | grep -qF "exactly 42 rows" || fail "STEP 0 must state the exact worklist row count Claude must account for"
echo "$prompt" | grep -q "do NOT query" || fail "STEP 0 must instruct Claude to Read the file, not query BigQuery for the worklist itself"
echo "$prompt" | grep -q "status: partial" || fail "STEP 0 must instruct Claude to report status: partial/blocked rather than silently processing a subset"
if echo "$prompt" | grep -qF "re-run this yourself"; then
  fail "STEP 0 must no longer tell Claude to re-run the worklist SQL itself"
fi
if echo "$prompt" | grep -qF "SELECT 1 /* worklist */"; then
  fail "prompt must never embed the raw worklist SQL text -- STEP 0 now points at the materialized file instead"
fi
echo "$prompt" | grep -qF "Derive /tmp/babybath_shopee_worklist.jsonl from /tmp/babybath_shopee_full_worklist.jsonl" || fail "STEP 1 must derive its {id,text} file from STEP 0's materialized worklist file, not from re-querying"
echo "$prompt" | grep -qF "jq -c '{id: .product_id, text: .sku_name}' /tmp/babybath_shopee_full_worklist.jsonl" || fail "STEP 1 must give Claude the exact jq one-liner to derive the {id,text} file, not ask it to hand-transcribe rows out of a potentially large worklist file (the same truncation exposure Finding 1 exists to eliminate)"

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
  "prod_id" "sku_type" "keywords_typo" "babybath_taxonomy_qa" "/tmp/babybath_shopee_full_worklist.jsonl" \
  "42" "-")
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

# --- extract_result_json ---
[[ "$(extract_result_json '{"result":"{\"status\":\"complete\"}"}')" == '{"status":"complete"}' ]] || fail "extract_result_json should pull the inner result JSON out of the envelope"
[[ "$(extract_result_json '{"result":""}')" == "" ]] || fail "extract_result_json should return empty when .result itself is empty"
[[ "$(extract_result_json 'garbage')" == "" ]] || fail "extract_result_json should return empty when the whole envelope is unparseable"
echo "PASS: extract_result_json"

complete_output='{"result":"{\"status\":\"complete\"}"}'
[[ "$(decide_queue_signal "$complete_output")" == "DONE" ]] || fail "complete status should map to DONE"
blocked_output='{"result":"{\"status\":\"blocked\"}"}'
[[ "$(decide_queue_signal "$blocked_output")" == "BLOCKED" ]] || fail "blocked status should map to BLOCKED"
garbage_output='not json at all'
[[ "$(decide_queue_signal "$garbage_output")" == "FAILED" ]] || fail "unparseable output should map to FAILED, never silently succeed"
echo "PASS: decide_queue_signal"

# --- format_result_summary ---
# Fields verified against a real `claude -p --output-format json` call during design -- not guessed.
fake_envelope='{"result":"{\"status\":\"complete\",\"rows_qa_confirmed\":12,\"rows_qa_unconfident\":3,\"rows_filtered\":2,\"rows_created_in_dict\":1,\"findings\":\"all good\",\"blockers\":[]}","total_cost_usd":0.1284843,"num_turns":47,"duration_ms":182340,"modelUsage":{"claude-sonnet-5":{"costUSD":0.1284843,"inputTokens":2,"outputTokens":7,"cacheReadInputTokens":25151,"cacheCreationInputTokens":20138}}}'
summary=$(format_result_summary "$fake_envelope")
echo "$summary" | grep -q "Status: complete" || fail "format_result_summary must show the status"
echo "$summary" | grep -q "Confirmed: 12" || fail "format_result_summary must show rows_qa_confirmed"
echo "$summary" | grep -q "Unconfident: 3" || fail "format_result_summary must show rows_qa_unconfident"
echo "$summary" | grep -q "Filtered: 2" || fail "format_result_summary must show rows_filtered"
echo "$summary" | grep -q "Created: 1" || fail "format_result_summary must show rows_created_in_dict"
echo "$summary" | grep -q "Turns used: 47" || fail "format_result_summary must show num_turns from the envelope"
echo "$summary" | grep -q "Duration: 182340ms" || fail "format_result_summary must show duration_ms from the envelope"
echo "$summary" | grep -q "Total cost: \$0.1284843" || fail "format_result_summary must show total_cost_usd from the envelope"
echo "$summary" | grep -q "claude-sonnet-5: \$0.1284843" || fail "format_result_summary must show per-model cost from modelUsage"
echo "$summary" | grep -q "in: 2 tok, out: 7 tok" || fail "format_result_summary must show per-model token usage"
echo "$summary" | grep -q "all good" || fail "format_result_summary must show findings in full"
echo "$summary" | grep -q "(none)" || fail "format_result_summary must show (none) for an empty blockers array"

fake_envelope_with_blockers='{"result":"{\"status\":\"blocked\",\"rows_qa_confirmed\":0,\"rows_qa_unconfident\":0,\"rows_filtered\":0,\"rows_created_in_dict\":0,\"findings\":\"none yet\",\"blockers\":[\"missing dict table\",\"auth expired\"]}","total_cost_usd":0.02,"num_turns":3,"duration_ms":5000,"modelUsage":{}}'
summary2=$(format_result_summary "$fake_envelope_with_blockers")
echo "$summary2" | grep -q "missing dict table" || fail "format_result_summary must list blockers in full when present"
echo "$summary2" | grep -q "auth expired" || fail "format_result_summary must list every blocker, not just the first"
echo "$summary2" | grep -q "no model usage reported" || fail "format_result_summary must handle an empty modelUsage object gracefully"

# Test unparseable envelope (transport error scenario) -- result_json is empty, all result-level
# fields must degrade to documented defaults, not blank strings (this was the bug: jq on empty
# input produces no output, not an error, so || fallback never fires).
garbage_envelope='garbage not json at all'
summary3=$(format_result_summary "$garbage_envelope")
echo "$summary3" | grep -q "Status: unknown" || fail "format_result_summary must show status=unknown for unparseable envelope"
echo "$summary3" | grep -q "Confirmed: ?" || fail "format_result_summary must show rows_confirmed=? for unparseable envelope"
echo "$summary3" | grep -q "Unconfident: ?" || fail "format_result_summary must show rows_qa_unconfident=? for unparseable envelope"
echo "$summary3" | grep -q "Filtered: ?" || fail "format_result_summary must show rows_filtered=? for unparseable envelope"
echo "$summary3" | grep -q "Created: ?" || fail "format_result_summary must show rows_created_in_dict=? for unparseable envelope"
echo "$summary3" | grep -q "Findings:" || fail "format_result_summary must have a Findings section even for garbage"
echo "$summary3" | grep -q "(unparseable)" || fail "format_result_summary must show (unparseable) for findings/blockers when result_json is empty"
echo "PASS: format_result_summary"

# --- main() wiring (grep the script source, no execution) ---
script_src=$(cat script/non_niq/non_niq_qa.sh)
grep -qF 'echo "QUEUE_SIGNAL: NOTHING_TO_DO"' <<< "$script_src" || fail "main() must emit NOTHING_TO_DO when the worklist is empty, before spending a claude -p call"
grep -qF 'echo "QUEUE_SIGNAL: $(decide_queue_signal "$claude_output")"' <<< "$script_src" || fail "main() must emit the post-run signal derived from decide_queue_signal"
grep -qE 'claude_output=\$\(claude -p .*\) \|\| true' <<< "$script_src" || fail "main() must tolerate a non-zero claude exit (|| true) so the transcript still gets echoed under set -e"
grep -qF "product_id_dict=\$(echo \"\$category_json\" | jq -r '.product_id_dict')" <<< "$script_src" || fail "main() must extract product_id_dict from the Sheet row and pass it to build_qa_prompt"
grep -qF 'for t in "qa_table=$qa_table" "dict_table=$dict_table" "filter_table=$filter_table"' <<< "$script_src" || fail "main() must guard qa_table/dict_table/filter_table against the Sheet's unconfigured '-' marker (and only those three -- '-' is legal for product_id_dict)"
grep -qF 'source "${REPO_ROOT}/script/load_env.sh"' <<< "$script_src" || fail "main() must source load_env.sh so DISCORD_WEBHOOK_URL (and other .env values) are available whether invoked directly or via the queue worker"
grep -qF 'format_result_summary "$claude_output"' <<< "$script_src" || fail "main() must print the human-readable summary"
grep -qF 'echo "$claude_output"' <<< "$script_src" || fail "main() must still echo the raw envelope -- the summary is additive, not a replacement"
echo "PASS: main() QUEUE_SIGNAL wiring"

# --- main() worklist materialization (Finding 1) ---
grep -qF -- '--max_rows=1000000' <<< "$script_src" || fail "main() must pass --max_rows to bq query when materializing the worklist -- bq query silently defaults to --max_rows=100 (confirmed live: a real 140-row worklist came back as exactly 100 rows without it), which would reproduce the truncation bug this materialization exists to fix"
grep -qF "worklist_file=\"/tmp/\${dataset}_\${platform}_full_worklist.jsonl\"" <<< "$script_src" || fail "main() must materialize the worklist to a distinctly-named file (not colliding with STEP 1's derived {id,text} file)"
grep -qF "jq -c '.[]'" <<< "$script_src" || fail "main() must convert bq's JSON array output to true JSONL (one object per line) via jq -c '.[]'"
grep -qF 'worklist_count=$(wc -l < "$worklist_file"' <<< "$script_src" || fail "main() must derive worklist_count from the materialized file's line count, not a separate redundant COUNT query"
if grep -qF 'SELECT COUNT(*) FROM ($query)' <<< "$script_src"; then
  fail "main() must not run a separate COUNT(*) query -- worklist_count comes from the materialized file"
fi
grep -qF 'build_qa_prompt "$dataset" "$platform" "$source_table" "$qa_table" "$dict_table" \' <<< "$script_src" || fail "main() must still call build_qa_prompt with the expected leading args"
grep -qF '"$worklist_file" \' <<< "$script_src" || fail "main() must pass the worklist FILE PATH (not raw SQL) as build_qa_prompt's worklist_file arg"
grep -qF '"$worklist_count" "$product_id_dict")' <<< "$script_src" || fail "main() must pass worklist_count into build_qa_prompt alongside product_id_dict"
echo "PASS: main() worklist materialization wiring"

# --- main() row-limit arg (4th positional, defaults to 300) ---
grep -qF 'max_turns="${3:-300}" max_rows="${4:-300}"' <<< "$script_src" || fail "main() must accept a 4th positional MAX_ROWS arg defaulting to 300"
grep -qF 'Usage: $0 <DATASET> <PLATFORM> [MAX_TURNS] [MAX_ROWS]' <<< "$script_src" || fail "main()'s usage message must document the new MAX_ROWS arg"
grep -qF '"$enrichment_table" "$max_rows")' <<< "$script_src" || fail "main() must pass max_rows through to worklist_query as the row_limit arg"
echo "PASS: main() row-limit arg wiring"

# --- main() DISCORD_WEBHOOK_URL warning (Finding 2) ---
grep -qF 'DISCORD_WEBHOOK_URL:-' <<< "$script_src" || fail "main() must check DISCORD_WEBHOOK_URL right after sourcing load_env.sh"
grep -qF 'WARNING: DISCORD_WEBHOOK_URL unset' <<< "$script_src" || fail "main() must warn on its own stderr when DISCORD_WEBHOOK_URL is unset -- otherwise the operator gets zero signal that Discord notifications are being skipped all session (notify_discord_new_entry's own warning only reaches Claude's Bash-tool output, never non_niq_qa.sh's stdout/stderr)"
echo "PASS: main() DISCORD_WEBHOOK_URL warning wiring"

echo "ALL TESTS PASSED (part 2: prompt + main)"
