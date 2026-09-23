#!/usr/bin/env bash
set -euo pipefail
# Self-test for script/non_niq/non_niq_qa_v2.sh's pure helper functions.
# No network, BQ, or claude calls -- mirrors test_non_niq_qa.sh's convention.
# Run: bash tests/non_niq/test_non_niq_qa_v2.sh

cd "$(dirname "$0")/../.."
source script/non_niq/non_niq_qa_v2.sh

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- require_harness (AGENT_HARNESS availability gate) ---
require_harness "claude" || fail "require_harness must accept 'claude' (the only wired-up, and presumably installed, harness in this environment)"
require_harness "not_a_real_harness" 2>/dev/null && fail "require_harness must reject an unrecognized harness name"
require_harness "codex" || fail "require_harness must accept 'codex' when its CLI is on PATH"
echo "PASS: require_harness"

# A failed bubblewrap setup must stop the run before any worklist or DML, while preserving
# Codex's automatic approval policy.
preflight_dir=$(mktemp -d)
cat > "$preflight_dir/bwrap" <<'BWRAP'
#!/usr/bin/env bash
echo 'bwrap: setting up uid map: Permission denied' >&2
exit 1
BWRAP
chmod +x "$preflight_dir/bwrap"
PATH="$preflight_dir:$PATH" codex_sandbox_preflight >/dev/null 2>&1 && fail "broken bubblewrap must fail fast"
cat > "$preflight_dir/bwrap" <<'BWRAP'
#!/usr/bin/env bash
exit 0
BWRAP
PATH="$preflight_dir:$PATH" codex_sandbox_preflight || fail "working bubblewrap must pass preflight"
rm -rf "$preflight_dir"
echo "PASS: codex_sandbox_preflight"

# --- Codex capacity retry gate: retry only a provably side-effect-free startup failure ---
capacity_test_dir=$(mktemp -d)
capacity_stdout="$capacity_test_dir/stdout.jsonl"
capacity_final="$capacity_test_dir/final.json"
cat > "$capacity_stdout" <<'JSONL'
{"type":"thread.started"}
{"type":"turn.started"}
{"type":"error","message":"Selected model is at capacity. Please try a different model."}
{"type":"turn.failed","error":{"message":"Selected model is at capacity. Please try a different model."}}
JSONL
: > "$capacity_final"
is_codex_startup_capacity_failure "$capacity_stdout" "$capacity_final" || fail "capacity-only Codex startup failure must be retryable"
echo '{"type":"item.completed","item":{"type":"command_execution"}}' >> "$capacity_stdout"
is_codex_startup_capacity_failure "$capacity_stdout" "$capacity_final" && fail "a Codex transcript with possible tool activity must never be retried"
sed -i '$d' "$capacity_stdout"
echo '{"status":"complete"}' > "$capacity_final"
is_codex_startup_capacity_failure "$capacity_stdout" "$capacity_final" && fail "a nonempty Codex final result must never be retried"
rm -rf "$capacity_test_dir"
echo "PASS: is_codex_startup_capacity_failure"

# --- Codex receives a private, writable clone of the host gcloud + ADC runtime ---
gcloud_fixture=$(mktemp -d)
gcloud_runtime=$(mktemp -d)
mkdir -p "$gcloud_fixture/configurations"
touch "$gcloud_fixture/credentials.db" "$gcloud_fixture/access_tokens.db" \
  "$gcloud_fixture/configurations/config_default" "$gcloud_fixture/application_default_credentials.json"
mapfile -t gcloud_runtime_paths < <(
  prepare_codex_gcloud_runtime "$gcloud_runtime" "$gcloud_fixture" \
    "$gcloud_fixture/application_default_credentials.json"
)
[[ "${gcloud_runtime_paths[0]}" == "$gcloud_runtime/gcloud" ]] || fail "Codex runtime must use a cloned writable CLOUDSDK_CONFIG"
[[ "${gcloud_runtime_paths[1]}" == "$gcloud_runtime/application_default_credentials.json" ]] || fail "Codex runtime must expose a copied ADC file"
[[ -f "$gcloud_runtime/gcloud/credentials.db" ]] || fail "Codex runtime must copy gcloud credentials"
[[ -f "$gcloud_runtime/application_default_credentials.json" ]] || fail "Codex runtime must copy ADC credentials"
[[ "$(stat -c '%a' "$gcloud_runtime/application_default_credentials.json")" == "600" ]] || fail "copied ADC credentials must be owner-readable only"
rm -rf -- "$gcloud_fixture" "$gcloud_runtime"
echo "PASS: prepare_codex_gcloud_runtime"

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

# --- worklist_query (stakeholder-aligned current-title coverage) ---
q=$(worklist_query "cookiesbiscuit.master_cookiesbiscuit_id" "cookiesbiscuitlemonilo.product_id_dict_qa" "prod_id" "2026-07" "shopee")
echo "$q" | grep -qF "s.product_tier IN ('Tier 1')" || fail "worklist_query (v2) must use the source table's precomputed Tier 1 population"
if echo "$q" | grep -qF "cumulative_gmv_share\|SUM(sc.gmv_monthly) OVER"; then
  fail "worklist_query (v2) must not recalculate GMV tiers"
fi
echo "$q" | grep -q "cookiesbiscuit.master_cookiesbiscuit_id" || fail "worklist_query (v2) should reference the source table"
echo "$q" | grep -q "prod_id" || fail "worklist_query (v2) should use the resolved QA primary-key column"
echo "$q" | grep -q "ecommerce_platform = 'Shopee'" || fail "worklist_query (v2) must capitalize the platform filter to Title-Case"
if echo "$q" | grep -q "ecommerce_platform = 'shopee'"; then
  fail "worklist_query (v2) must never filter on the raw lowercase platform"
fi
echo "$q" | grep -qF "REPLACE(s.image, '\"', '')" || fail "worklist_query (v2) must strip embedded double-quotes from image, same fix as v1"
echo "$q" | grep -qF "sc.ecommerce_platform, sc.merchant_id" || fail "worklist_query (v2) must include merchant_id for real filter-table inserts"
echo "$q" | grep -qF "s.ecommerce_platform," || fail "worklist_query must retain the raw source platform"
echo "$q" | grep -qF "WHERE ecommerce_platform = 'Shopee'" || fail "worklist_query must scope QA history to the raw platform"
echo "$q" | grep -q "qa_title_state AS" || fail "worklist_query (v2) must build an exact-title QA state"
echo "$q" | grep -qF "REGEXP_REPLACE(TRIM(sku_name), r'\\s+', ' ') AS normalized_sku_name" || fail "worklist_query (v2) must normalize QA titles exactly like the stakeholder query"
echo "$q" | grep -qF "qts.normalized_sku_name = REGEXP_REPLACE(TRIM(sc.sku_name), r'\\s+', ' ')" || fail "worklist_query (v2) must match QA by product_id plus whitespace-normalized current title"
echo "$q" | grep -qF "qts.ecommerce_platform = sc.ecommerce_platform" || fail "QA title matching must keep platforms separate"
echo "$q" | grep -qF "WHEN qts.product_id IS NULL THEN 0" || fail "priority 0 must select current titles with no matching QA row"
if echo "$q" | grep -q "sc.qa_status"; then
  fail "worklist_query (v2) must not use the source qa_status as its normal coverage gate"
fi
echo "$q" | grep -q "JSON_VALUE(SAFE.PARSE_JSON(_meta)" || fail "worklist_query (v2) must read _meta via JSON_VALUE(SAFE.PARSE_JSON(_meta), ...)"
if echo "$q" | grep -q "SAFE.JSON_VALUE"; then
  fail "worklist_query (v2) must never call SAFE.JSON_VALUE -- not valid BigQuery syntax"
fi
echo "$q" | grep -q "ORDER BY priority ASC, gmv_monthly DESC" || fail "worklist_query (v2) must order title mismatches before unconfident retries, then by GMV"
echo "$q" | grep -q "LIMIT 100" || fail "worklist_query (v2) must default row_limit to 100"
grep -c "AS priority" <<< "$q" | grep -qx 1 || fail "priority must be computed exactly once"
# product_id_dict_qa is INSERT-ONLY -- qa_state must aggregate to order-independent flags per
# product for the retained pending-unconfident retry. A raw SELECT would fan out the LEFT JOIN;
# a latest-row sort can silently un-terminate products because _meta timestamps are unreliable.
echo "$q" | grep -qF "GROUP BY 1, 2" || fail "platform-scoped qa_state must GROUP BY product and platform"
echo "$q" | grep -qF "LOGICAL_OR(" || fail "qa_state must aggregate qa_confidence/human_review across a product's WHOLE history"
echo "$q" | grep -qF "has_unconfident_pending" || fail "qa_state must track has_unconfident_pending as an aggregate flag"
echo "$q" | grep -qF "has_confident" || fail "qa_state must track has_confident as an aggregate flag"
echo "$q" | grep -qF "has_terminal" || fail "qa_state must track has_terminal as an aggregate flag"
echo "$q" | grep -qF "WHEN qs.has_unconfident_pending AND NOT qs.has_confident AND NOT qs.has_terminal THEN 1" || fail "priority 1 must require pending-and-never-resolved, not a single fanned-out row"
if echo "$q" | grep -qF "qs.qa_confidence = 'unconfident'"; then
  fail "worklist_query (v2) must not gate priority 1 on a single un-aggregated qa_state row's qa_confidence"
fi
if echo "$q" | grep -qiE "ROW_NUMBER\(\).*PARTITION BY.*qa_table|ORDER BY.*timestamp.*DESC.*=\s*1"; then
  fail "worklist_query (v2) must not dedupe qa_state via latest-row-by-timestamp"
fi
echo "PASS: worklist_query"

# Regional QA tables call their platform column `ecommerce`. The live schema resolver passes that
# name as worklist_query's final argument; both QA state CTEs must use it and preserve it in joins.
q_regional=$(worklist_query "lighting.master_lighting_th" "lighting.product_id_dict_qa_regional" "product_id" "2026-08" "lazada" "" "300" "lighting.filter_lighting_id" "" "" "" "ecommerce")
echo "$q_regional" | grep -qF "WHERE ecommerce = 'Lazada'" || fail "worklist_query must use the resolved regional QA platform column"
if echo "$q_regional" | grep -qF "WHERE ecommerce_platform = 'Lazada'"; then
  fail "regional worklist query must not reference missing QA ecommerce_platform"
fi
echo "PASS: worklist_query regional QA platform column"

# --- worklist_query lighting/ID brand scope ---
q_lighting_id=$(worklist_query "lighting.master_lighting_id" "lighting.product_id_dict_qa_regional" "product_id" "2026-08" "shopee" "" "300" "lighting.filter_lighting_id" "" "" "" "ecommerce" "lighting" "ID")
echo "$q_lighting_id" | grep -qF "AND s.brand IN ('Cahaya', 'Surya')" || fail "lighting/ID worklists must be limited to Cahaya and Surya"
q_lighting_th=$(worklist_query "lighting.master_lighting_th" "lighting.product_id_dict_qa_regional" "product_id" "2026-08" "shopee" "" "300" "lighting.filter_lighting_id" "" "" "" "ecommerce" "lighting" "TH")
if echo "$q_lighting_th" | grep -qF "AND s.brand IN ('Cahaya', 'Surya')"; then
  fail "lighting brand restriction must not apply outside Indonesia"
fi
echo "PASS: worklist_query lighting/ID brand scope"

# --- worklist_query tokopedia platform expansion ---
q_tokopedia=$(worklist_query "cookiesbiscuit.master_cookiesbiscuit_id" "cookiesbiscuitlemonilo.product_id_dict_qa" "prod_id" "2026-07" "tokopedia")
echo "$q_tokopedia" | grep -qF "ecommerce_platform IN ('Tokopedia', 'Tokopedia | Shop')" || fail "worklist_query (v2) must scope the tokopedia worklist to BOTH platform values, not just plain 'Tokopedia'"
echo "$q_tokopedia" | grep -qF "s.url AS product_url" || fail "Tokopedia worklists must retain a product URL for the missing-image fallback"
if echo "$q_tokopedia" | grep -qF "ecommerce_platform = 'Tokopedia'"; then
  fail "worklist_query (v2) must not use a plain equality check for tokopedia -- it would silently exclude 'Tokopedia | Shop' rows"
fi
echo "PASS: worklist_query tokopedia platform expansion"

# --- worklist_query filter_table exclusion before stakeholder ranking ---
q_filtered=$(worklist_query "cookiesbiscuit.master_cookiesbiscuit_id" "cookiesbiscuitlemonilo.product_id_dict_qa" "prod_id" "2026-07" "shopee" "" "300" "cookiesbiscuitlemonilo.filter_cookiesbiscuit")
echo "$q_filtered" | grep -q "filter_state AS" || fail "worklist_query (v2) must create a filter_state CTE when filter_table is given"
echo "$q_filtered" | grep -qF "SELECT DISTINCT product_id FROM \`sincere-hearth-273704.cookiesbiscuitlemonilo.filter_cookiesbiscuit\`" || fail "worklist_query (v2) must select DISTINCT product_id from the filter table"
echo "$q_filtered" | grep -qF "LEFT JOIN filter_state fs ON fs.product_id = sc.product_id" || fail "worklist_query (v2) must join the filter table before ranking"
echo "$q_filtered" | grep -qF "WHERE fs.product_id IS NULL" || fail "worklist_query (v2) must remove filtered products before calculating cumulative GMV"
if echo "$q" | grep -q "filter_state\|fs.product_id"; then
  fail "worklist_query (v2) must not reference filter_state when no filter_table is given"
fi
echo "PASS: worklist_query filter_table exclusion"

# Run generated scope SQL against fixture data to verify merchant inclusion and exclusions.
q_forced=$(worklist_query "fixture.source" "fixture.qa" "prod_id" "2026-07" "tokopedia" "" "300" "fixture.filter" "" "" '"client","competitor"')
q_unforced=$(worklist_query "fixture.source" "fixture.qa" "prod_id" "2026-07" "tokopedia" "" "300" "fixture.filter")
python3 - "$q_forced" "$q_unforced" <<'PY_SCOPE'
import sqlite3
import sys

db = sqlite3.connect(":memory:")
db.create_function("FORMAT_DATE", 2, lambda fmt, date: date[:7])
db.executescript("""
CREATE TABLE source (product_id TEXT, sku_name TEXT, image TEXT, url TEXT, ecommerce_platform TEXT,
                     country TEXT, category TEXT, month TEXT, gmv_monthly REAL, merchant_id TEXT,
                     product_tier TEXT);
CREATE TABLE filter (product_id TEXT);
INSERT INTO source VALUES
 ('top', 'top', '', '', 'Tokopedia', 'ID', 'Cookies Biscuit', '2026-07-01', 80, 'ordinary', 'Tier 1'),
 ('tail', 'tail', '', '', 'Tokopedia', 'ID', 'Cookies Biscuit', '2026-07-01', 11, 'ordinary', 'Tier 3'),
 ('client-low', 'low', '', '', 'Tokopedia', 'ID', 'Cookies Biscuit', '2026-07-01', 9, 'client', 'Tier 3'),
 ('competitor-zero', 'zero', '', '', 'Tokopedia | Shop', 'ID', 'Cookies Biscuit', '2026-07-01', 0, 'competitor', 'Tier 3'),
 ('client-filtered', 'filtered', '', '', 'Tokopedia', 'ID', 'Cookies Biscuit', '2026-07-01', 500, 'client', 'Tier 1');
INSERT INTO filter VALUES ('client-filtered');
""")
def scope_ids(query):
    query = query.split(",\nqa_title_state AS (", 1)[0]
    query = query.replace("`sincere-hearth-273704.fixture.source`", "source")
    query = query.replace("`sincere-hearth-273704.fixture.filter`", "filter")
    return {row[0] for row in db.execute(query + " SELECT product_id FROM stakeholder_scope")}
assert scope_ids(sys.argv[1]) == {'top', 'client-low', 'competitor-zero'}
assert scope_ids(sys.argv[2]) == {'top'}
PY_SCOPE
echo "PASS: merchant whitelist includes low/zero-GMV products and retains filter exclusions"

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
  "42" "cookiesbiscuitlemonilo.product_id_dict" "cookiesbiscuit_shopee_ID")

grep -qF "/tmp/cookiesbiscuit_shopee_v2_full_worklist.jsonl" <<< "$prompt" || fail "STEP 0 must reference the materialized worklist file path"
grep -qF "exactly 42 rows" <<< "$prompt" || fail "STEP 0 must state the exact worklist row count"
grep -qi "Tier 1" <<< "$prompt" || fail "STEP 0 must describe the precomputed source-tier scope"
grep -qi "whitespace-normalized sku_name" <<< "$prompt" || fail "STEP 0 must explain the current-title QA matching rule"
grep -qi "precomputed Tier 1 product_tier" <<< "$prompt" || fail "prompt must describe the source table's stored tier"
grep -q "ecommerce_platform, merchant_id" <<< "$prompt" || fail "STEP 0 must carry merchant_id so filter inserts can preserve it"
grep -q "item_description, product_attributes_attrs, listing_changed" <<< "$prompt" || fail "STEP 0 must list enrichment and reverify fields in the worklist row shape"
grep -q "priority\. It is already scoped" <<< "$prompt" || fail "STEP 0 must list priority in the worklist row shape"
grep -q "product_attributes_attrs" <<< "$prompt" || fail "STEP 2a must mention product_attributes_attrs as additional signal alongside item_description"
grep -qi "Shopee-only signal and NULL on other platforms" <<< "$prompt" || fail "STEP 2a must note item_description/product_attributes_attrs are Shopee-only and NULL elsewhere"
if grep -q "non_niq_helper.py retrieve" <<< "$prompt"; then
  fail "prompt must not repeat wrapper-side Meilisearch retrieval"
fi
grep -qF "wrapper already ran one batch Meilisearch retrieval" <<< "$prompt" || fail "prompt must consume the wrapper's candidate artifact"
grep -q "sku_type_complete" <<< "$prompt" || fail "prompt must reference the resolved dict identity column"
grep -q "keywords_typo" <<< "$prompt" || fail "prompt must reference the resolved dict typo column"
grep -q "prod_id" <<< "$prompt" || fail "prompt must reference the resolved QA primary-key column"
grep -q "never the streaming API" <<< "$prompt" || fail "prompt must repeat the DML-only / no-streaming-API constraint"
grep -q "qa_confidence" <<< "$prompt" || fail "prompt must instruct writing the qa_confidence _meta field"
grep -q "human_review" <<< "$prompt" || fail "prompt must instruct writing the human_review _meta field"
grep -q "Determine one honest disposition for every worklist row" <<< "$prompt" || fail "prompt must force an explicit result for each product"
grep -q "If automatic approval review rejects a write" <<< "$prompt" || fail "prompt must handle a reviewer rejection without repackaging the same payload"
grep -q "chunks of at most 10 products" <<< "$prompt" || fail "prompt must cap each reviewed/write chunk at 10 products"
grep -qF 'v2_decisions.jsonl' <<< "$prompt" || fail "prompt must require a visible per-product ledger before DML"
grep -qF "that chunk's ledger lines in tool output BEFORE DML" <<< "$prompt" || fail "automatic reviewer must see the evidence before DML"
grep -q "every DML statement may affect at most 10" <<< "$prompt" || fail "prompt must prohibit whole-worklist bulk DML"
grep -q "never generate the ledger or identity selection by token rules" <<< "$prompt" || fail "prompt must reject heuristic taxonomy creation"
grep -q "make NO QA/dict/filter write" <<< "$prompt" || fail "ambiguous identities must stay unresolved rather than be written"
flat_prompt=$(echo "$prompt" | tr '\n' ' ' | tr -s ' ')
echo "$flat_prompt" | grep -q "leave an optional attribute NULL" || fail "prompt must permit evidence-supported NULLs in optional dict columns"
if grep -q "Every column on the new row must be non-null" <<< "$prompt"; then
  fail "prompt must not require values for optional dictionary columns"
fi
grep -q "Both tables intentionally name their identity column sku_type_complete" <<< "$prompt" || fail "prompt must explain when QA and dict identity columns share the same name"
if grep -q "Never write sku_type_complete to the QA table" <<< "$prompt"; then
  fail "prompt must not prohibit the QA table's required sku_type_complete column when the dict uses the same name"
fi
grep -q "Mapping table" <<< "$prompt" || fail "prompt must state the mapping table is never modified"
if grep -q "notify Discord\|notify-discord" <<< "$prompt"; then
  fail "prompt must not reference Discord notification"
fi
# _meta must always be a JSON string ({"source":"claude_code","timestamp":"..."}), never a bare
# string like "claude_code" -- SAFE.PARSE_JSON on a bare string returns NULL, silently losing
# source/timestamp on every future read of that row.
grep -qF '{"source":"claude_code","timestamp":"<now, ISO 8601 UTC>"}' <<< "$prompt" || fail "prompt must define the baseline _meta JSON format with source+timestamp"
grep -qF '2026-08-16T19:19:06Z' <<< "$prompt" || fail "prompt must give a concrete ISO 8601 UTC example of the _meta timestamp format"
if grep -qF "_meta='claude_code'" <<< "$prompt"; then
  fail "prompt must never instruct stamping _meta as the bare string 'claude_code' -- that is not valid JSON"
fi
grep -qF "NOT valid JSON" <<< "$prompt" || fail "prompt must explicitly warn that a bare string _meta value is not valid JSON"
# qa_status writing is owned by a separate external QA-labelling update process now -- this
# harness must never instruct writing to it.
if grep -qi "qa_status = 'Reviewed'\|run the qa_status UPDATE\|SET qa_status" <<< "$prompt"; then
  fail "prompt must never instruct writing to qa_status -- that's owned by an external process now"
fi
grep -qF "Never write to \`qa_status\`" <<< "$prompt" || fail "prompt's Hard rules must explicitly state qa_status is never written by this harness"
grep -qF "either \`ecommerce\` or \`ecommerce_platform\`" <<< "$prompt" || fail "filter writes must accept both live Non-NIQ platform-column variants"
grep -qF "missing alternative platform" <<< "$prompt" || fail "a missing alternate filter platform column must never block a run"
grep -qF "live table schema is" <<< "$prompt" || fail "prompt must declare the live filter schema authoritative"
grep -qF "supersedes any fixed filter schema" <<< "$prompt" || fail "prompt must supersede stale fixed-schema design text"
if grep -qF "write exactly {ecommerce, product_id, sku_name, merchant_id, _meta}" <<< "$prompt"; then fail "prompt must never restore the UHT-only filter contract"; fi
if grep -qF "There is no \`ecommerce_platform\` column" <<< "$prompt"; then fail "prompt must never prohibit a live ecommerce_platform filter column"; fi
grep -qF "are distinct channels; do not collapse either value" <<< "$prompt" || fail "prompt must preserve separate Tokopedia channel values in writes"

# --- dict-column generation patterns (self-bootstrapping per-category config) ---
grep -qF "script/non_niq/dict_patterns/cookiesbiscuit.json" <<< "$prompt" || fail "Step A must reference this dataset's dict_patterns config path"
grep -qF '"sources"' <<< "$prompt" || fail "Step A must describe the dict_patterns JSON schema's sources key"
grep -qF '"separator"' <<< "$prompt" || fail "Step A must describe the dict_patterns JSON schema's separator key"
grep -qi "sample ~10-20 existing rows" <<< "$prompt" || fail "Step A must instruct inferring the pattern by sampling existing dict rows when no config exists"
grep -qi "skipping any source that's null/empty" <<< "$prompt" || fail "Step A must state that composition skips null/empty sources"
grep -qF "distinguish required identity/category fields from genuinely optional" <<< "$prompt" || fail "Step B must distinguish required and optional dict attributes from live evidence"
grep -qF "non_niq_taxonomy_insert_log" <<< "$prompt" || fail "prompt must require the shared taxonomy insert log"
grep -qF "SAME BigQuery transaction" <<< "$prompt" || fail "prompt must require atomic dictionary/log writes"
grep -qF '"inserted_row"' <<< "$prompt" || fail "prompt must define the inserted_row JSON envelope"
grep -qF "zero-row conditional INSERT" <<< "$prompt" || fail "prompt must avoid logging no-op dictionary inserts"
if grep -qi 'REPO_ROOT}/script/non_niq/dict_patterns/${dataset}' <<< "$prompt"; then
  fail "prompt must interpolate the real dataset name into the dict_patterns path, not leave a literal \${dataset} placeholder"
fi
echo "PASS: dict-column generation patterns"

# --- STEP 3: batched Meilisearch write-back for newly-minted taxonomy entries ---
grep -qF "STEP 3 -- Record all newly-minted dictionary rows" <<< "$prompt" || fail "prompt must include STEP 3 artifact and Meilisearch write-back"
grep -qF "/tmp/cookiesbiscuit_shopee_ID_v2_created_dict_rows.jsonl" <<< "$prompt" || fail "STEP 3 must create a complete dict-row artifact for Sheet write-back"
grep -qF "must contain all" <<< "$prompt" || fail "STEP 3 artifact must include every created row"
grep -qF "non_niq_helper.py index" <<< "$prompt" || fail "STEP 3 must invoke non_niq_helper.py's index subcommand"
grep -qF -- "--meili-index cookiesbiscuit_taxonomy_qa" <<< "$prompt" || fail "STEP 3 must pass the resolved meili_index to the index command"
grep -qi "never index an unconfident guess" <<< "$prompt" || fail "STEP 3 must explicitly exclude unconfident guesses from indexing"
grep -qi "zero confident new products, skip" <<< "$prompt" || fail "STEP 3 must instruct skipping the call entirely when there's nothing to index"
grep -qi "never one call per product" <<< "$prompt" || fail "STEP 3 must state the batch-not-per-product rule, same as STEP 1"
echo "PASS: STEP 3 Meilisearch write-back"

prompt_nodict=$(build_qa_prompt "cookiesbiscuit" "shopee" "ID" "cookiesbiscuit.master_cookiesbiscuit_id" \
  "cookiesbiscuitlemonilo.product_id_dict_qa" "cookiesbiscuitlemonilo.cookiesbiscuitlemonilo_dict" \
  "cookiesbiscuitlemonilo.filter_cookiesbiscuit" \
  "prod_id" "sku_type_complete" "keywords_typo" "cookiesbiscuit_taxonomy_qa" "/tmp/cookiesbiscuit_shopee_v2_full_worklist.jsonl" \
  "42" "-" "cookiesbiscuit_shopee_ID")
grep -q "2b. SKIPPED for this category" <<< "$prompt_nodict" || fail "an unconfigured ('-') product_id_dict must skip step 2b"
if grep -qi "run the qa_status UPDATE\|SET qa_status" <<< "$prompt_nodict"; then
  fail "prompt_nodict must never instruct writing to qa_status either"
fi
prompt_codex=$(build_qa_prompt "cookiesbiscuit" "shopee" "ID" "source" "qa" "dict" "filter" \
  "product_id" "sku_type_complete" "keywords_typo" "index" "/tmp/worklist.jsonl" "1" "-" "codex_test" "codex" "false" "/tmp/image_manifest.jsonl")
grep -qF '{"source":"codex","timestamp":"<now, ISO 8601 UTC>"}' <<< "$prompt_codex" || fail "Codex prompt must stamp _meta writes with source=codex"
grep -qF "dict_has_meta=false" <<< "$prompt_codex" || fail "prompt must expose the live dict _meta capability"
grep -qF "missing optional dict _meta column is never a blocker" <<< "$prompt_codex" || fail "missing dict _meta must not block the session"
grep -qF "attached" <<< "$prompt_codex" || fail "Codex prompt must use attached image sheets"
grep -qF "/tmp/image_manifest.jsonl" <<< "$prompt_codex" || fail "Codex prompt must identify the image manifest"
grep -qF "Do not call the sandboxed" <<< "$prompt_codex" || fail "Codex must not use the broken image viewer"
prompt_dict_meta=$(build_qa_prompt "cookiesbiscuit" "shopee" "ID" "source" "qa" "dict" "filter" \
  "product_id" "sku_type_complete" "keywords_typo" "index" "/tmp/worklist.jsonl" "1" "-" "codex_test" "codex" "true")
echo "$prompt_dict_meta" | grep -qF "dict_has_meta=true" || fail "prompt must expose dict_has_meta=true when resolved"
echo "$prompt_dict_meta" | grep -qF "Include the dict table's existing \`_meta\` column" || fail "dict rows must retain provenance stamping when the column exists"
echo "PASS: build_qa_prompt"

# --- extract_json_object / decide_queue_signal / format_result_summary (shared contract) ---
[[ "$(extract_json_object 'prose {"status":"complete"} trailing')" == '{"status":"complete"}' ]] || fail "extract_json_object should pull the JSON object out of mixed text"
echo "PASS: extract_json_object"

[[ "$(extract_result_json '{"result":"{\"status\":\"complete\"}"}')" == '{"status":"complete"}' ]] || fail "extract_result_json should pull the inner result JSON out of the envelope"
[[ "$(extract_result_json '{"result":""}')" == "" ]] || fail "extract_result_json should return empty when .result itself is empty"
[[ "$(extract_result_json '{"status":"complete","rows_qa_confirmed":1}')" == '{"status":"complete","rows_qa_confirmed":1}' ]] || fail "extract_result_json should accept Codex's direct final JSON object"
echo "PASS: extract_result_json"

[[ "$(decide_queue_signal '{"result":"{\"status\":\"blocked\"}"}')" == "BLOCKED" ]] || fail "decide_queue_signal should map status=blocked to BLOCKED"
[[ "$(decide_queue_signal '{"result":"{\"status\":\"complete\"}"}')" == "DONE" ]] || fail "decide_queue_signal should map status=complete to DONE"
[[ "$(decide_queue_signal '{"result":"{\"status\":\"partial\"}"}')" == "DONE" ]] || fail "decide_queue_signal should map status=partial to DONE"
[[ "$(decide_queue_signal '{"status":"partial","rows_unresolved":1}')" == "DONE" ]] || fail "unresolved products must release a partial queue task"
[[ "$(decide_queue_signal '{"status":"complete","rows_unresolved":1}')" == "DONE" ]] || fail "unresolved products must release a complete queue task"
[[ "$(decide_queue_signal 'garbage')" == "FAILED" ]] || fail "decide_queue_signal should map unparseable output to FAILED"
echo "PASS: decide_queue_signal"

residual_counts_cover_worklist '{"rows_qa_confirmed":1,"rows_qa_unconfident":1,"rows_filtered":0,"rows_unresolved":0}' 2 || fail "residual counts should cover the worklist"
residual_counts_cover_worklist '{"rows_qa_confirmed":1,"rows_qa_unconfident":0,"rows_filtered":0,"rows_unresolved":0}' 2 && fail "under-counted residual work must block automatic-total merge"
residual_counts_cover_worklist '{"rows_qa_confirmed":1,"rows_qa_unconfident":0,"rows_filtered":0,"rows_unresolved":1}' 2 || fail "unresolved residual rows still account for a completed queue batch"
residual_counts_cover_worklist '{"rows_qa_confirmed":-1,"rows_qa_unconfident":3,"rows_filtered":0,"rows_unresolved":0}' 2 && fail "negative residual counts must block automatic-total merge"
residual_counts_cover_worklist '{"rows_qa_confirmed":0.5,"rows_qa_unconfident":1.5,"rows_filtered":0,"rows_unresolved":0}' 2 && fail "fractional residual counts must block automatic-total merge"
ledger_test_dir=$(mktemp -d)
printf '%s\n' '{"product_id":"1","ecommerce_platform":"Tokopedia","sku_name":"Example 20 gr"}' > "$ledger_test_dir/worklist.jsonl"
cat > "$ledger_test_dir/decisions.jsonl" <<'JSONL'
{"product_id":"1","ecommerce_platform":"Tokopedia","sku_name":"Example 20 gr","image_observation":"Package shows the named product","title_evidence":"Product title confirms 20 gr","identity_rationale":"The exact live dictionary identity matches","decision":"qa_confident","intended_table_values":{"brand":"Example"}}
JSONL
residual_ledger_covers_worklist "$ledger_test_dir/worklist.jsonl" "$ledger_test_dir/decisions.jsonl" || fail "a grounded ledger must pass coverage validation"
printf '%s\n' '{"product_id":"2","ecommerce_platform":"Tokopedia","sku_name":"Other"}' >> "$ledger_test_dir/decisions.jsonl"
residual_ledger_covers_worklist "$ledger_test_dir/worklist.jsonl" "$ledger_test_dir/decisions.jsonl" && fail "an extra ledger product must fail coverage validation"
cat > "$ledger_test_dir/worklist.jsonl" <<'JSONL'
{"product_id":"same","ecommerce_platform":"Tokopedia","sku_name":"First"}
{"product_id":"same","ecommerce_platform":"Tokopedia | Shop","sku_name":"Second"}
JSONL
cat > "$ledger_test_dir/decisions.jsonl" <<'JSONL'
{"product_id":"same","ecommerce_platform":"Tokopedia | Shop","sku_name":"Second","image_observation":"Package shows the named product","title_evidence":"Product title confirms 20 gr","identity_rationale":"The exact live dictionary identity matches","decision":"qa_confident","intended_table_values":{"brand":"Example"}}
{"product_id":"same","ecommerce_platform":"Tokopedia","sku_name":"First","image_observation":"Package shows the named product","title_evidence":"Product title confirms 20 gr","identity_rationale":"The exact live dictionary identity matches","decision":"qa_confident","intended_table_values":{"brand":"Example"}}
JSONL
residual_ledger_covers_worklist "$ledger_test_dir/worklist.jsonl" "$ledger_test_dir/decisions.jsonl" || fail "an exact raw row-identity ledger must pass"
sed -i 's/"Tokopedia | Shop","sku_name":"Second"/"Tokopedia","sku_name":"Second"/' "$ledger_test_dir/decisions.jsonl"
residual_ledger_covers_worklist "$ledger_test_dir/worklist.jsonl" "$ledger_test_dir/decisions.jsonl" && fail "a ledger with swapped raw row identity must fail coverage validation"
rm -rf "$ledger_test_dir"
echo "PASS: residual accounting and ledger coverage"

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
grep -qF 'local tmp_tag="${dataset}_${platform}_${country}"' <<< "$script_src" || fail "main() (v2) must derive a country-scoped scratch tag"
grep -qF 'worklist_file="/tmp/${tmp_tag}_v2_full_worklist.jsonl"' <<< "$script_src" || fail "main() (v2) must materialize the worklist to a v2-distinctly-named, country-scoped file"
grep -qF 'echo "QUEUE_SIGNAL: NOTHING_TO_DO"' <<< "$script_src" || fail "main() (v2) must emit NOTHING_TO_DO when the worklist is empty"
grep -qF 'non_niq_helper.py" auto-confirm' <<< "$script_src" || fail "main() must auto-confirm exact-title Meilisearch matches before agent work"
grep -qF 'rows_auto_confirmed=$auto_confirmed' <<< "$script_src" || fail "main() must expose automatic confirmation counts"
grep -qF 'signal=$(decide_queue_signal "$agent_output")' <<< "$script_src" || fail "main() (v2) must derive the post-run signal from the normalized agent result"
grep -qF 'echo "QUEUE_SIGNAL: ${signal}"' <<< "$script_src" || fail "main() (v2) must emit the derived post-run signal"
grep -qE 'claude_output=\$\(claude -p .*\) \|\| true' <<< "$script_src" || fail "main() (v2) must tolerate a non-zero Claude exit"
grep -qF 'codex exec --cd "$REPO_ROOT" --approve-for-me' <<< "$script_src" || fail "main() (v2) must invoke Codex with the automatic-approval adapter"
grep -qF '"${codex_image_args[@]}"' <<< "$script_src" || fail "Codex must receive image sheets as CLI attachments"
grep -qF 'prepare_codex_image_sheets.py' <<< "$script_src" || fail "wrapper must prepare image sheets before starting Codex"
grep -qF 'if [[ "$agent_harness" == "codex" ]] && ! codex_sandbox_preflight' <<< "$script_src" || fail "wrapper must fail fast when Codex bubblewrap is unavailable"
grep -qF 'CODEX_QA_REASONING_EFFORT:-high' <<< "$script_src" || fail "taxonomy decisions should default to high reasoning"
grep -qF -- '-c sandbox_workspace_write.network_access=true' <<< "$script_src" || fail "main() (v2) must enable network access for Codex's workspace-write sandbox -- bq/curl/Meilisearch all need it, and --approve-for-me alone does not grant it"
grep -qF -- '--output-schema ' <<< "$script_src" || fail "main() (v2) must constrain Codex's final result with a JSON Schema"
grep -qF -- '--output-last-message "$codex_final_file"' <<< "$script_src" || fail "main() (v2) must capture Codex's final message separately from stdout"
grep -qF 'is_codex_startup_capacity_failure "$codex_stdout_file" "$codex_final_file"' <<< "$script_src" || fail "main() must retry only proven startup capacity failures"
grep -qF 'Codex remained at capacity through all startup attempts' <<< "$script_src" || fail "capacity exhaustion must produce a structured failure instead of unparseable output"
grep -qF 'prepare_codex_gcloud_runtime "$codex_runtime_dir"' <<< "$script_src" || fail "main() must prepare a writable authenticated gcloud runtime for Codex"
grep -qF -- '--add-dir "$codex_runtime_dir"' <<< "$script_src" || fail "Codex must receive the temporary runtime as a writable sandbox directory"
grep -qF 'shell_environment_policy.include_only=["PATH","HOME","TMPDIR","LANG","LC_ALL","CLOUDSDK_CONFIG","GOOGLE_APPLICATION_CREDENTIALS"]' <<< "$script_src" || fail "Codex must receive only the prepared BigQuery credential variables and required shell runtime"
grep -qF 'RUNTIME AUTHENTICATION (already prepared)' <<< "$script_src" || fail "Codex prompt must prevent replacing its prepared credential runtime"
grep -qF 'format_result_summary "$agent_output"' <<< "$script_src" || fail "main() (v2) must print the normalized agent summary"
grep -qF 'echo "$agent_output"' <<< "$script_src" || fail "main() (v2) must still echo the normalized agent result"
jq -e '.properties.status.enum == ["complete", "partial", "failed", "blocked"]' script/non_niq/codex_qa_result_schema.json >/dev/null || fail "Codex result schema must constrain the session status"
jq -e '.required | index("rows_unresolved")' script/non_niq/codex_qa_result_schema.json >/dev/null || fail "Codex result schema must require unresolved-row accounting"
if echo "$script_src" | grep -q "DISCORD_WEBHOOK_URL\|load_env.sh\|notify-discord\|notify_discord"; then
  fail "non_niq_qa_v2.sh must not reference Discord notification or load_env.sh"
fi
grep -qF "enrichment_table=\$(echo \"\$category_json\" | jq -r '.\"0\"')" <<< "$script_src" || fail "main() (v2) must resolve enrichment_table from the Sheet's \"0\" column, same as v1"
grep -qF '"$enrichment_table" "$max_rows" "$filter_table" "$kategori" "$monthly_reverify" "$forced_merchant_ids_sql" "$qa_platform_col" "$dataset" "$country")' <<< "$script_src" || fail "main() (v2) must thread enrichment, scope, dataset, country, and resolved QA platform options through to worklist_query"
grep -qF 'NON_NIQ_QA_V2_SNAPSHOT=$(mktemp' <<< "$script_src" || fail "direct runs must execute from an immutable snapshot so concurrent edits cannot corrupt a live shell parse"
grep -qF 'created_entries_file="/tmp/${tmp_tag}_v2_created_dict_rows.jsonl"' <<< "$script_src" || fail "Sheet write-back must consume the all-created artifact"
if grep -qF -- '--input-file "$new_entries_file"' <<< "$script_src"; then
  fail "Sheet write-back must not reuse the confidence-filtered Meilisearch artifact"
fi
grep -qF 'non_niq_helper.py" forced-merchants' <<< "$script_src" || fail "main() must fetch client/competitor merchant IDs"
grep -qF -- '--country "$country" --category "$category" --platform "$platform_titlecase"' <<< "$script_src" || fail "merchant lookup must use the resolved country, category, and platform"
grep -qF "dict_has_meta=\$(echo \"\$columns_json\" | jq -r '.dict_has_meta')" <<< "$script_src" || fail "main() must read the live dict _meta capability"
grep -qF "qa_platform_col=\$(echo \"\$columns_json\" | jq -r '.qa_platform_col')" <<< "$script_src" || fail "main() must read the live QA platform column"
grep -qF '"$worklist_count" "$product_id_dict" "$tmp_tag" "$agent_meta_source" "$dict_has_meta" "$image_manifest_file")' <<< "$script_src" || fail "main() must pass dict and image capabilities into the generated prompt"
echo "PASS: main() wiring"

echo "ALL TESTS PASSED (part 2: prompt + main)"
