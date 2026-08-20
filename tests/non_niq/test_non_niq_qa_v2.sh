#!/usr/bin/env bash
set -euo pipefail
# Self-test for script/non_niq/non_niq_qa_v2.sh's pure helper functions.
# No network, BQ, or claude calls -- mirrors test_non_niq_qa.sh's convention.
# Run: bash tests/non_niq/test_non_niq_qa_v2.sh

cd "$(dirname "$0")/../.."
source script/non_niq/non_niq_qa_v2.sh

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- platform_match_clause (Tokopedia's own first-party 'Tokopedia | Shop' channel has NO
# separate config Sheet row -- 'tokopedia' as a CLI arg must match BOTH BigQuery platform values) ---
[[ "$(platform_match_clause "Tokopedia")" == "IN ('Tokopedia', 'Tokopedia | Shop')" ]] || fail "platform_match_clause must expand Tokopedia to match both 'Tokopedia' and 'Tokopedia | Shop'"
[[ "$(platform_match_clause "Shopee")" == "= 'Shopee'" ]] || fail "platform_match_clause must leave non-Tokopedia platforms as a plain equality check"
[[ "$(platform_match_clause "Blibli")" == "= 'Blibli'" ]] || fail "platform_match_clause must leave non-Tokopedia platforms as a plain equality check"
echo "PASS: platform_match_clause"

# --- default_month_query (identical shape to v1's, scoped per-platform) ---
q=$(default_month_query "cookiesbiscuit.master_cookiesbiscuit_id" "shopee")
echo "$q" | grep -q "MAX(month)" || fail "default_month_query should find the latest month"
echo "$q" | grep -q "cookiesbiscuit.master_cookiesbiscuit_id" || fail "default_month_query should reference the source table"
echo "$q" | grep -q "ecommerce_platform = 'Shopee'" || fail "default_month_query must scope MAX(month) to the given platform (Title-Case)"
if echo "$q" | grep -q "ecommerce_platform = 'shopee'"; then
  fail "default_month_query must never filter on the raw lowercase platform"
fi
q_tokopedia=$(default_month_query "cookiesbiscuit.master_cookiesbiscuit_id" "tokopedia")
echo "$q_tokopedia" | grep -qF "ecommerce_platform IN ('Tokopedia', 'Tokopedia | Shop')" || fail "default_month_query must resolve MAX(month) across BOTH Tokopedia platform values, not just plain 'Tokopedia'"
echo "PASS: default_month_query"

# --- worklist_query (product_tier-based, NOT cumulative-GMV) ---
q=$(worklist_query "cookiesbiscuit.master_cookiesbiscuit_id" "cookiesbiscuitlemonilo.product_id_dict_qa" "prod_id" "2026-07" "shopee")
echo "$q" | grep -qF "product_tier = 'Tier 1'" || fail "worklist_query (v2) must filter on the precomputed product_tier column, not recompute GMV percentiles"
if echo "$q" | grep -qi "cumulative_gmv_pct\|OVER (ORDER BY gmv_monthly"; then
  fail "worklist_query (v2) must NOT recompute a cumulative GMV window -- explicit user decision to trust product_tier instead"
fi
echo "$q" | grep -q "cookiesbiscuit.master_cookiesbiscuit_id" || fail "worklist_query (v2) should reference the source table"
echo "$q" | grep -q "prod_id" || fail "worklist_query (v2) should use the resolved QA primary-key column"
echo "$q" | grep -q "ecommerce_platform = 'Shopee'" || fail "worklist_query (v2) must capitalize the platform filter to Title-Case"
if echo "$q" | grep -q "ecommerce_platform = 'shopee'"; then
  fail "worklist_query (v2) must never filter on the raw lowercase platform"
fi
echo "$q" | grep -qF "REPLACE(s.image, '\"', '')" || fail "worklist_query (v2) must strip embedded double-quotes from image, same fix as v1"
echo "$q" | grep -q "JSON_VALUE(SAFE.PARSE_JSON(_meta)" || fail "worklist_query (v2) must read _meta via JSON_VALUE(SAFE.PARSE_JSON(_meta), ...)"
if echo "$q" | grep -q "SAFE.JSON_VALUE"; then
  fail "worklist_query (v2) must never call SAFE.JSON_VALUE -- not valid BigQuery syntax"
fi
echo "$q" | grep -q "ORDER BY priority ASC, gmv_monthly DESC" || fail "worklist_query (v2) must order unreviewed before unconfident, then by GMV"
echo "$q" | grep -q "qa_status = 'Not Reviewed'" || fail "worklist_query (v2) must gate priority-0 rows to qa_status = 'Not Reviewed'"
echo "$q" | grep -q "LIMIT 300" || fail "worklist_query (v2) must default row_limit to 300"
grep -c "AS priority" <<< "$q" | grep -qx 1 || fail "priority must be computed exactly once"
# product_id_dict_qa is INSERT-ONLY -- qa_state must aggregate to order-independent flags per
# product (LOGICAL_OR over the WHOLE history), never a raw un-deduped SELECT (fans out the LEFT
# JOIN, leaks already-resolved products back into the worklist forever -- confirmed live,
# project_non_niq_qa_state_fanout_bug.md, a 380-row v2 worklist was 100% already-resolved this
# way) and never a "latest row by timestamp" dedup either (also confirmed live to silently
# un-terminate products when a later write lands, since product_id_dict_qa has no reliable
# timestamp column).
echo "$q" | grep -qF "GROUP BY prod_id" || fail "qa_state must GROUP BY the resolved qa_pk_col, not select raw un-deduped rows"
echo "$q" | grep -qF "LOGICAL_OR(" || fail "qa_state must use LOGICAL_OR to aggregate qa_confidence/human_review across a product's WHOLE history, not just one (possibly stale) row"
echo "$q" | grep -qF "has_unconfident_pending" || fail "qa_state must track has_unconfident_pending as an aggregate flag"
echo "$q" | grep -qF "has_confident" || fail "qa_state must track has_confident as an aggregate flag"
echo "$q" | grep -qF "has_terminal" || fail "qa_state must track has_terminal as an aggregate flag"
echo "$q" | grep -qF "WHEN qs.has_unconfident_pending AND NOT qs.has_confident AND NOT qs.has_terminal THEN 1" || fail "priority 1 must require pending-and-never-resolved (order-independent), not a single fanned-out row's confidence"
if echo "$q" | grep -qF "qs.qa_confidence = 'unconfident'"; then
  fail "worklist_query (v2) must not gate priority 1 on a single un-aggregated qa_state row's qa_confidence -- that's the fan-out bug"
fi
if echo "$q" | grep -qiE "ROW_NUMBER\(\).*PARTITION BY.*qa_table|ORDER BY.*timestamp.*DESC.*=\s*1"; then
  fail "worklist_query (v2) must not dedupe qa_state via latest-row-by-timestamp -- confirmed live this silently un-terminates products, use aggregate flags instead"
fi
echo "PASS: worklist_query"

# --- worklist_query tokopedia platform expansion ---
q_tokopedia=$(worklist_query "cookiesbiscuit.master_cookiesbiscuit_id" "cookiesbiscuitlemonilo.product_id_dict_qa" "prod_id" "2026-07" "tokopedia")
echo "$q_tokopedia" | grep -qF "ecommerce_platform IN ('Tokopedia', 'Tokopedia | Shop')" || fail "worklist_query (v2) must scope the tokopedia worklist to BOTH platform values, not just plain 'Tokopedia'"
if echo "$q_tokopedia" | grep -qF "ecommerce_platform = 'Tokopedia'"; then
  fail "worklist_query (v2) must not use a plain equality check for tokopedia -- it would silently exclude 'Tokopedia | Shop' rows"
fi
echo "PASS: worklist_query tokopedia platform expansion"

# --- worklist_query filter_table exclusion ---
q_filtered=$(worklist_query "cookiesbiscuit.master_cookiesbiscuit_id" "cookiesbiscuitlemonilo.product_id_dict_qa" "prod_id" "2026-07" "shopee" "" "300" "cookiesbiscuitlemonilo.filter_cookiesbiscuit")
echo "$q_filtered" | grep -q "filter_state AS" || fail "worklist_query (v2) must create a filter_state CTE when filter_table is given"
echo "$q_filtered" | grep -qF "SELECT DISTINCT product_id FROM \`sincere-hearth-273704.cookiesbiscuitlemonilo.filter_cookiesbiscuit\`" || fail "worklist_query (v2) must select DISTINCT product_id from the filter table"
echo "$q_filtered" | grep -qF "WHEN fs.product_id IS NOT NULL THEN NULL" || fail "worklist_query (v2) must exclude already-filtered products"
[[ "$q_filtered" == *$'CASE\n      WHEN fs.product_id IS NOT NULL THEN NULL\n      WHEN qs.product_id IS NULL'* ]] || fail "the filter_table exclusion must be checked FIRST in the CASE, before the qa_state checks"
if echo "$q" | grep -q "filter_state\|fs.product_id"; then
  fail "worklist_query (v2) must not reference filter_state when no filter_table is given"
fi
echo "PASS: worklist_query filter_table exclusion"

# --- worklist_query enrichment (item_description/product_attributes_attrs, ported from v1) ---
q_enriched=$(worklist_query "cookiesbiscuit.master_cookiesbiscuit_id" "cookiesbiscuitlemonilo.product_id_dict_qa" "prod_id" "2026-07" "shopee" "0_pipeline_cookiesbiscuit_shopee_id")
echo "$q_enriched" | grep -q "enrichment_dedup AS" || fail "worklist_query (v2) must create an enrichment_dedup CTE for deduplication"
echo "$q_enriched" | grep -q "QUALIFY ROW_NUMBER() OVER (PARTITION BY item_itemid ORDER BY timestamp DESC) = 1" || fail "worklist_query (v2) must dedupe enrichment table to latest row per item_itemid"
echo "$q_enriched" | grep -q "FROM \`sincere-hearth-273704.cookiesbiscuit.0_pipeline_cookiesbiscuit_shopee_id\`" || fail "worklist_query (v2) must reference the enrichment table in enrichment_dedup CTE"
echo "$q_enriched" | grep -q "LEFT JOIN enrichment_dedup e ON CAST(e.item_itemid AS STRING) = s.product_id" || fail "worklist_query (v2) must join the dedup CTE on item_itemid = product_id"
echo "$q_enriched" | grep -q "e.item_description, e.product_attributes_attrs" || fail "worklist_query (v2) must select item_description/product_attributes_attrs from the enrichment_dedup CTE"
echo "$q_enriched" | grep -q "sc.item_description, sc.product_attributes_attrs" || fail "worklist_query (v2) must carry item_description/product_attributes_attrs through to the final SELECT"
echo "$q_enriched" | grep -qF "STRING_AGG(CONCAT(JSON_VALUE(a,'\$.name'),'=',JSON_VALUE(a,'\$.value')), '; ')" || fail "worklist_query (v2)'s enrichment_dedup CTE must project product_attributes_attrs down to a compact name=value string via STRING_AGG"
echo "$q_enriched" | grep -qF "COALESCE(" || fail "worklist_query (v2) must try raw SAFE.PARSE_JSON first and fall back to a normalized parse"
echo "$q_enriched" | grep -qF "SAFE.PARSE_JSON(product_attributes_attrs)," || fail "worklist_query (v2)'s COALESCE must try the raw product_attributes_attrs first, so already-valid JSON is never run through Python-repr normalization"
echo "$q_enriched" | grep -qF "CHR(39), CHR(34)" || fail "worklist_query (v2)'s Python-repr fallback must swap single quotes for double quotes"
echo "$q_enriched" | grep -qF "': None', ': null'" || fail "worklist_query (v2)'s Python-repr fallback must normalize None/True/False to JSON's null/true/false"

# Non-Shopee platform -> no join, NULL columns instead, even if an enrichment_table value is passed.
q_noenrich=$(worklist_query "cookiesbiscuit.master_cookiesbiscuit_id" "cookiesbiscuitlemonilo.product_id_dict_qa" "prod_id" "2026-07" "blibli" "0_pipeline_cookiesbiscuit_blibli_id")
if echo "$q_noenrich" | grep -q "enrichment_dedup AS"; then
  fail "worklist_query (v2) must never build the enrichment CTE for a non-Shopee platform"
fi
echo "$q_noenrich" | grep -q "NULL AS item_description, NULL AS product_attributes_attrs" || fail "worklist_query (v2) must select NULL item_description/product_attributes_attrs for non-Shopee platforms"

# No enrichment table given at all (Sheet's "0" column empty) -> same NULL fallback, even for Shopee.
q_missing=$(worklist_query "cookiesbiscuit.master_cookiesbiscuit_id" "cookiesbiscuitlemonilo.product_id_dict_qa" "prod_id" "2026-07" "shopee")
if echo "$q_missing" | grep -q "enrichment_dedup AS"; then
  fail "worklist_query (v2) must not attempt a join when no enrichment_table is given"
fi
echo "$q_missing" | grep -q "NULL AS item_description, NULL AS product_attributes_attrs" || fail "worklist_query (v2) must select NULL item_description/product_attributes_attrs when enrichment_table is omitted"

# enrichment_table literal string "null" (jq -r on a missing/null JSON key) must be treated the
# same as an unconfigured enrichment_table -- consistency with main()'s three-sentinel guard.
q_null_sentinel=$(worklist_query "cookiesbiscuit.master_cookiesbiscuit_id" "cookiesbiscuitlemonilo.product_id_dict_qa" "prod_id" "2026-07" "shopee" "null")
if echo "$q_null_sentinel" | grep -q "enrichment_dedup AS"; then
  fail "worklist_query (v2) must treat the literal string 'null' the same as an unconfigured enrichment_table"
fi
echo "$q_null_sentinel" | grep -q "NULL AS item_description, NULL AS product_attributes_attrs" || fail "worklist_query (v2) must select NULL item_description/product_attributes_attrs when enrichment_table is the literal string 'null'"
echo "PASS: worklist_query enrichment"

# --- primary_filter_table (identical to v1's) ---
single="babybath.filter_babybath"
[[ "$(primary_filter_table "$single" "babybath")" == "babybath.filter_babybath" ]] || fail "single-value filter_table should return as-is"
multi="babysunscreen.filter_babysunscreen;sunscreen.filter_sunscreen_hanasui"
[[ "$(primary_filter_table "$multi" "babysunscreen")" == "babysunscreen.filter_babysunscreen" ]] || fail "should return the table in the row's own dataset"
echo "PASS: primary_filter_table"

# sync_qa_status_query removed -- a separate external QA-labelling update process now owns
# flipping qa_status based on product_id_dict_qa, this harness must never write it.
if declare -F sync_qa_status_query >/dev/null; then
  fail "sync_qa_status_query must not exist -- qa_status writing is owned by an external process now"
fi

echo "ALL TESTS PASSED (part 1: SQL builders)"

# --- build_qa_prompt ---
prompt=$(build_qa_prompt "cookiesbiscuit" "shopee" "ID" "cookiesbiscuit.master_cookiesbiscuit_id" \
  "cookiesbiscuitlemonilo.product_id_dict_qa" "cookiesbiscuitlemonilo.cookiesbiscuitlemonilo_dict" \
  "cookiesbiscuitlemonilo.filter_cookiesbiscuit" \
  "prod_id" "sku_type_complete" "keywords_typo" "cookiesbiscuit_taxonomy_qa" "/tmp/cookiesbiscuit_shopee_v2_full_worklist.jsonl" \
  "42" "cookiesbiscuitlemonilo.product_id_dict")

echo "$prompt" | grep -qF "/tmp/cookiesbiscuit_shopee_v2_full_worklist.jsonl" || fail "STEP 0 must reference the materialized worklist file path"
echo "$prompt" | grep -qF "exactly 42 rows" || fail "STEP 0 must state the exact worklist row count"
echo "$prompt" | grep -qF "product_tier = 'Tier 1'" || fail "STEP 0 must describe the product_tier scoping, not GMV percentile scoping"
if echo "$prompt" | grep -qi "cumulative GMV\|top 90%"; then
  fail "prompt (v2) must not reference the v1 GMV-percentile scoping concept"
fi
echo "$prompt" | grep -q "item_description, product_attributes_attrs, priority" || fail "STEP 0 must list item_description/product_attributes_attrs in the worklist row shape"
echo "$prompt" | grep -q "product_attributes_attrs" || fail "STEP 2a must mention product_attributes_attrs as additional signal alongside item_description"
echo "$prompt" | grep -qi "Shopee-only signal and NULL on other platforms" || fail "STEP 2a must note item_description/product_attributes_attrs are Shopee-only and NULL elsewhere"
echo "$prompt" | grep -q "non_niq_helper.py retrieve" || fail "prompt must instruct batch retrieval via non_niq_helper.py's retrieve subcommand"
echo "$prompt" | grep -q "sku_type_complete" || fail "prompt must reference the resolved dict identity column"
echo "$prompt" | grep -q "keywords_typo" || fail "prompt must reference the resolved dict typo column"
echo "$prompt" | grep -q "prod_id" || fail "prompt must reference the resolved QA primary-key column"
echo "$prompt" | grep -q "never the streaming API" || fail "prompt must repeat the DML-only / no-streaming-API constraint"
echo "$prompt" | grep -q "qa_confidence" || fail "prompt must instruct writing the qa_confidence _meta field"
echo "$prompt" | grep -q "human_review" || fail "prompt must instruct writing the human_review _meta field"
echo "$prompt" | grep -q "Mapping table" || fail "prompt must state the mapping table is never modified"
if echo "$prompt" | grep -q "notify Discord\|notify-discord"; then
  fail "prompt must not reference Discord notification"
fi
# _meta must always be a JSON string ({"source":"claude_code","timestamp":"..."}), never a bare
# string like "claude_code" -- SAFE.PARSE_JSON on a bare string returns NULL, silently losing
# source/timestamp on every future read of that row.
echo "$prompt" | grep -qF '{"source":"claude_code","timestamp":"<now, ISO 8601 UTC>"}' || fail "prompt must define the baseline _meta JSON format with source+timestamp"
echo "$prompt" | grep -qF '2026-08-16T19:19:06Z' || fail "prompt must give a concrete ISO 8601 UTC example of the _meta timestamp format"
if echo "$prompt" | grep -qF "_meta='claude_code'"; then
  fail "prompt must never instruct stamping _meta as the bare string 'claude_code' -- that is not valid JSON"
fi
echo "$prompt" | grep -qF "NOT valid JSON" || fail "prompt must explicitly warn that a bare string _meta value is not valid JSON"
# qa_status writing is owned by a separate external QA-labelling update process now -- this
# harness must never instruct writing to it.
if grep -qi "qa_status = 'Reviewed'\|run the qa_status UPDATE\|SET qa_status" <<< "$prompt"; then
  fail "prompt must never instruct writing to qa_status -- that's owned by an external process now"
fi
echo "$prompt" | grep -qF "Never write to \`qa_status\`" || fail "prompt's Hard rules must explicitly state qa_status is never written by this harness"

prompt_nodict=$(build_qa_prompt "cookiesbiscuit" "shopee" "ID" "cookiesbiscuit.master_cookiesbiscuit_id" \
  "cookiesbiscuitlemonilo.product_id_dict_qa" "cookiesbiscuitlemonilo.cookiesbiscuitlemonilo_dict" \
  "cookiesbiscuitlemonilo.filter_cookiesbiscuit" \
  "prod_id" "sku_type_complete" "keywords_typo" "cookiesbiscuit_taxonomy_qa" "/tmp/cookiesbiscuit_shopee_v2_full_worklist.jsonl" \
  "42" "-")
echo "$prompt_nodict" | grep -q "2b. SKIPPED for this category" || fail "an unconfigured ('-') product_id_dict must skip step 2b"
if grep -qi "run the qa_status UPDATE\|SET qa_status" <<< "$prompt_nodict"; then
  fail "prompt_nodict must never instruct writing to qa_status either"
fi
echo "PASS: build_qa_prompt"

# --- extract_json_object / decide_queue_signal / format_result_summary (identical contract to v1) ---
[[ "$(extract_json_object 'prose {"status":"complete"} trailing')" == '{"status":"complete"}' ]] || fail "extract_json_object should pull the JSON object out of mixed text"
echo "PASS: extract_json_object"

[[ "$(extract_result_json '{"result":"{\"status\":\"complete\"}"}')" == '{"status":"complete"}' ]] || fail "extract_result_json should pull the inner result JSON out of the envelope"
[[ "$(extract_result_json '{"result":""}')" == "" ]] || fail "extract_result_json should return empty when .result itself is empty"
echo "PASS: extract_result_json"

[[ "$(decide_queue_signal '{"result":"{\"status\":\"blocked\"}"}')" == "BLOCKED" ]] || fail "decide_queue_signal should map status=blocked to BLOCKED"
[[ "$(decide_queue_signal '{"result":"{\"status\":\"complete\"}"}')" == "DONE" ]] || fail "decide_queue_signal should map status=complete to DONE"
[[ "$(decide_queue_signal '{"result":"{\"status\":\"partial\"}"}')" == "DONE" ]] || fail "decide_queue_signal should map status=partial to DONE"
[[ "$(decide_queue_signal 'garbage')" == "FAILED" ]] || fail "decide_queue_signal should map unparseable output to FAILED"
echo "PASS: decide_queue_signal"

garbage_envelope='garbage not json at all'
summary=$(format_result_summary "$garbage_envelope")
echo "$summary" | grep -q "Status: unknown" || fail "format_result_summary must show status=unknown for unparseable envelope"
echo "$summary" | grep -q "(unparseable)" || fail "format_result_summary must show (unparseable) for findings/blockers when result_json is empty"
echo "PASS: format_result_summary"

# --- main() wiring (grep the script source, no execution) ---
script_src=$(cat script/non_niq/non_niq_qa_v2.sh)
grep -qF "source_table=\$(echo \"\$category_json\" | jq -r '.master_table_prod')" <<< "$script_src" || fail "main() (v2) must resolve source_table from master_table_prod, not table"
if grep -qF "jq -r '.table')" <<< "$script_src"; then
  fail "main() (v2) must not read the v1 'table' (_dev) Sheet column at all"
fi
grep -qF '"source_table=$source_table" "qa_table=$qa_table" "dict_table=$dict_table" "filter_table=$filter_table"' <<< "$script_src" || fail "main() (v2) must guard source_table alongside the other required tables -- unlike v1, v2's worklist depends entirely on it"
grep -qF '"$(default_month_query "$source_table" "$platform")"' <<< "$script_src" || fail "main() (v2) must pass platform to default_month_query"
# qa_status writing is owned by a separate external QA-labelling update process now -- main() must
# never call any qa_status sync or SET qa_status.
if grep -q "sync_qa_status_query" <<< "$script_src"; then
  fail "main() (v2) must not reference sync_qa_status_query -- that function no longer exists, qa_status writing is owned by an external process now"
fi
if grep -qi "SET qa_status" <<< "$script_src"; then
  fail "main() (v2) must never write to qa_status -- that's owned by an external process now"
fi
grep -qF -- '--max_rows=1000000' <<< "$script_src" || fail "main() (v2) must pass --max_rows to bq query when materializing the worklist"
grep -qF 'local dataset="$1" platform="$2" country="${3:-ID}"' <<< "$script_src" || fail "main() (v2) must accept an optional COUNTRY positional arg, defaulting to ID"
grep -qF 'categories --country "$country"' <<< "$script_src" || fail "main() (v2) must pass the resolved country through to non_niq_helper.py categories"
grep -qF 'country="${country^^}"' <<< "$script_src" || fail "main() (v2) must uppercase a lowercase COUNTRY arg (e.g. th -> TH) before matching the Sheet"
grep -qF "worklist_file=\"/tmp/\${dataset}_\${platform}_\${country}_v2_full_worklist.jsonl\"" <<< "$script_src" || fail "main() (v2) must materialize the worklist to a v2-distinctly-named, country-scoped file"
grep -qF 'echo "QUEUE_SIGNAL: NOTHING_TO_DO"' <<< "$script_src" || fail "main() (v2) must emit NOTHING_TO_DO when the worklist is empty"
grep -qF 'echo "QUEUE_SIGNAL: $(decide_queue_signal "$claude_output")"' <<< "$script_src" || fail "main() (v2) must emit the post-run signal derived from decide_queue_signal"
grep -qE 'claude_output=\$\(claude -p .*\) \|\| true' <<< "$script_src" || fail "main() (v2) must tolerate a non-zero claude exit"
grep -qF 'format_result_summary "$claude_output"' <<< "$script_src" || fail "main() (v2) must print the human-readable summary"
grep -qF 'echo "$claude_output"' <<< "$script_src" || fail "main() (v2) must still echo the raw envelope"
if echo "$script_src" | grep -q "DISCORD_WEBHOOK_URL\|load_env.sh\|notify-discord\|notify_discord"; then
  fail "non_niq_qa_v2.sh must not reference Discord notification or load_env.sh"
fi
grep -qF "enrichment_table=\$(echo \"\$category_json\" | jq -r '.\"0\"')" <<< "$script_src" || fail "main() (v2) must resolve enrichment_table from the Sheet's \"0\" column, same as v1"
grep -qF '"$enrichment_table" "$max_rows" "$filter_table")' <<< "$script_src" || fail "main() (v2) must thread enrichment_table through to worklist_query"
echo "PASS: main() wiring"

echo "ALL TESTS PASSED (part 2: prompt + main)"
