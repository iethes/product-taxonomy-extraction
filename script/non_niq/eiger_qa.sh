#!/usr/bin/env bash
set -euo pipefail

# Usage: script/non_niq/eiger_qa.sh <PLATFORM> [COUNTRY] [MAX_TURNS] [MAX_ROWS]
# e.g.  script/non_niq/eiger_qa.sh shopee
#       script/non_niq/eiger_qa.sh tokopedia ID 300 300
#
# Dedicated agentic QA script for eiger (Outdoor Equipment & Supplies) -- NOT a config variant of
# non_niq_qa_v2.sh. eiger has no free-text taxonomy dict table (Sheet's dict/product_id_dict
# columns are both '-', eiger.product_id_dict doesn't exist in BigQuery); categorization instead
# follows a fixed enumerated tree (docs/eiger_labelling_guidance.csv) and brand is constrained,
# for a small set of known multi-brand resellers, by eiger.brand_store_product_fix. See
# docs/superpowers/specs/2026-09-02-eiger-image-taxonomy-qa-design.md for the full design this
# implements, and docs/eiger-qa-handoff.md for a self-contained summary.
#
# Reuses non_niq_qa_v2.sh's scaffolding (worklist materialization shape, retry-once confidence
# loop, _meta conventions, result-summary/queue-signal plumbing) verbatim where it fits.

PROJECT="sincere-hearth-273704"
MEILI_URL="http://34.124.146.29:7700"
MEILI_INDEX="eiger_taxonomy_qa"

# eiger's real QA table -- the Sheet's own product_id_dict_image_qa column is correct but
# currently unread by non_niq_helper.py's ROW_FIELDS (see the design spec's Risks section), so
# it's hardcoded here rather than resolved from the Sheet like non_niq_qa_v2.sh's qa_table.
QA_TABLE="eiger.product_id_dict_image_qa"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PYTHON_BIN="${REPO_ROOT}/.venv/bin/python3"
GUIDANCE_CSV="${REPO_ROOT}/docs/eiger_labelling_guidance.csv"

source "${REPO_ROOT}/script/lib/common.sh"

# Identical to non_niq_qa_v2.sh's -- Tokopedia's own first-party channel carries a distinct
# 'Tokopedia | Shop' ecommerce_platform value with no separate config Sheet row.
platform_match_clause() {
  local platform_titlecase="$1"
  if [[ "$platform_titlecase" == "Tokopedia" ]]; then
    echo "IN ('Tokopedia', 'Tokopedia | Shop')"
  else
    echo "= '${platform_titlecase}'"
  fi
}

default_month_query() {
  local source_table="$1" platform="$2"
  local platform_titlecase="${platform^}"
  echo "SELECT FORMAT_DATE('%Y-%m', MAX(month)) FROM \`${PROJECT}.${source_table}\` WHERE ecommerce_platform $(platform_match_clause "$platform_titlecase")"
}

# Given the Sheet's raw filter_table cell (possibly ";"-separated), returns the ONE table living
# in this row's own dataset. Identical to non_niq_qa_v2.sh's.
primary_filter_table() {
  local filter_table_config="$1" dataset="$2"
  local entry
  IFS=';' read -ra entries <<< "$filter_table_config"
  for entry in "${entries[@]}"; do
    if [[ "$entry" == "${dataset}."* ]]; then
      echo "$entry"
      return 0
    fi
  done
  echo "${entries[0]}"
}

# Scope: product_tier = 'Tier 1' on master_table_prod, same convention as non_niq_qa_v2.sh.
# Unlike v2's generic version, qa_pk_col is not a parameter -- product_id is a fixed, confirmed
# column on QA_TABLE, so the non_niq_helper.py INFORMATION_SCHEMA round-trip v2 needs for
# per-category schema variance is skipped entirely.
worklist_query() {
  local source_table="$1" month="$2" platform="$3" enrichment_table="$4" row_limit="$5" filter_table="$6"
  local platform_titlecase="${platform^}"
  local dataset="${source_table%%.*}"
  local enrichment_cte_and_join="" enrichment_join="" enrichment_select="NULL AS item_description, NULL AS product_attributes_attrs"
  if [[ "$platform_titlecase" == "Shopee" && -n "$enrichment_table" && "$enrichment_table" != "-" && "$enrichment_table" != "null" ]]; then
    # Ported verbatim from non_niq_qa_v2.sh's worklist_query -- same live-confirmed
    # Python-repr-vs-JSON fallback for product_attributes_attrs.
    enrichment_cte_and_join="enrichment_dedup AS (
  SELECT item_itemid, item_description,
    (SELECT STRING_AGG(CONCAT(JSON_VALUE(a,'\$.name'),'=',JSON_VALUE(a,'\$.value')), '; ')
     FROM UNNEST(JSON_QUERY_ARRAY(COALESCE(
       SAFE.PARSE_JSON(product_attributes_attrs),
       SAFE.PARSE_JSON(REPLACE(REPLACE(REPLACE(REPLACE(product_attributes_attrs, ': None', ': null'), ': True', ': true'), ': False', ': false'), CHR(39), CHR(34)))
     ))) a) AS product_attributes_attrs
  FROM \`${PROJECT}.${dataset}.${enrichment_table}\`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY item_itemid ORDER BY timestamp DESC) = 1
),
"
    enrichment_join="LEFT JOIN enrichment_dedup e ON CAST(e.item_itemid AS STRING) = s.product_id"
    enrichment_select="e.item_description, e.product_attributes_attrs"
  fi
  cat <<SQL
WITH ${enrichment_cte_and_join}scoped AS (
  SELECT s.product_id, s.sku_name, REPLACE(s.image, '"', '') AS image, s.ecommerce_platform,
         s.qa_status, s.gmv_monthly, s.brand, s.mgh_2, s.mgh_3, s.mgh_4, s.product_type,
         s.sku_type_complete, s.brand_store, ${enrichment_select}
  FROM \`${PROJECT}.${source_table}\` s
  ${enrichment_join}
  WHERE s.product_tier = 'Tier 1'
    AND FORMAT_DATE('%Y-%m', s.month) = '${month}'
    AND s.ecommerce_platform $(platform_match_clause "$platform_titlecase")
),
qa_state AS (
  -- Order-independent LOGICAL_OR flags over the WHOLE per-product history, same fan-out-bug fix
  -- non_niq_qa_v2.sh uses (project memory project_non_niq_qa_state_fanout_bug.md) -- QA_TABLE is
  -- insert-only, a raw un-deduped join would leak resolved products back into the worklist.
  SELECT
    product_id,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.qa_confidence') = 'unconfident'
               AND COALESCE(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.human_review'), 'false') != 'true') AS has_unconfident_pending,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.qa_confidence') = 'confident') AS has_confident,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.human_review') = 'true') AS has_terminal
  FROM \`${PROJECT}.${QA_TABLE}\`
  GROUP BY product_id
),
filter_state AS (
  SELECT DISTINCT product_id FROM \`${PROJECT}.${filter_table}\`
),
prioritized AS (
  SELECT sc.product_id, sc.sku_name, sc.image, sc.gmv_monthly, sc.ecommerce_platform,
         sc.item_description, sc.product_attributes_attrs, sc.brand, sc.mgh_2, sc.mgh_3,
         sc.mgh_4, sc.product_type, sc.sku_type_complete, sc.brand_store,
    CASE
      WHEN fs.product_id IS NOT NULL THEN NULL
      WHEN qs.product_id IS NULL AND sc.qa_status = 'Not Reviewed' THEN 0
      WHEN qs.has_unconfident_pending AND NOT qs.has_confident AND NOT qs.has_terminal THEN 1
      ELSE NULL
    END AS priority
  FROM scoped sc
  LEFT JOIN qa_state qs ON qs.product_id = sc.product_id
  LEFT JOIN filter_state fs ON fs.product_id = sc.product_id
)
SELECT * FROM prioritized
WHERE priority IS NOT NULL
ORDER BY priority ASC, gmv_monthly DESC
LIMIT ${row_limit}
SQL
}

build_qa_prompt() {
  local platform="$1" country="$2" source_table="$3" filter_table="$4" worklist_file="$5"
  local worklist_count="$6" tmp_tag="$7"

  cat <<PROMPT
Eiger agentic QA session (image-taxonomy category, dedicated script -- NOT non_niq_qa_v2.sh) for
platform=${platform}, country=${country}. See
docs/superpowers/specs/2026-09-02-eiger-image-taxonomy-qa-design.md for the full design this
implements -- read it in full before starting if you have not already. Unlike every other
non-NIQ category, eiger has no free-text taxonomy dict table: categorization follows a fixed
enumerated tree (docs/eiger_labelling_guidance.csv) and brand is constrained, for a small set of
known multi-brand resellers, by eiger.brand_store_product_fix.

Resolved for this run: source_table=${PROJECT}.${source_table} (master_table_prod, Tier-1
scoped), qa_table=${PROJECT}.${QA_TABLE}, filter_table (write target)=${PROJECT}.${filter_table},
guidance_csv=${GUIDANCE_CSV}, brand_fix_table=${PROJECT}.eiger.brand_store_product_fix,
meilisearch_index=${MEILI_INDEX} (at ${MEILI_URL}).

STEP 0 -- The full worklist has ALREADY been materialized for you at
${worklist_file}, exactly ${worklist_count} rows, one JSON object per line (JSONL) -- do NOT
query BigQuery to re-fetch it, and do NOT trust any other row count than ${worklist_count}. Read
the file (in slices if it's too large for one Read) rather than querying BigQuery for it. Each
line has: product_id, sku_name, image, gmv_monthly, ecommerce_platform, item_description,
product_attributes_attrs, brand, mgh_2, mgh_3, mgh_4, product_type, sku_type_complete,
brand_store, priority. The brand/mgh_2/mgh_3/mgh_4/product_type/sku_type_complete/brand_store
fields are this product's EXISTING values on the source table (from a prior/legacy labelling
pass) -- a starting hypothesis to verify against the image and the guidance doc in STEP 2, not
a ground truth to copy blindly. It is already scoped to product_tier = 'Tier 1' and prioritized
(unreviewed rows before agent-flagged-unconfident retry rows, both by gmv_monthly descending) --
process it in that order. If you cannot account for all ${worklist_count} rows by the end of
your turn budget, explicitly report status: partial (or status: blocked if you cannot proceed at
all) -- never silently process a subset and report status: complete.

STEP 1 -- Retrieve Meilisearch candidates for the WHOLE worklist in ONE batch call, never one
call per product:
  1. Derive /tmp/${tmp_tag}_worklist.jsonl from ${worklist_file} (STEP 0's file) --
     one line per worklist product: {"id": "<product_id>", "text": "<sku_name>"}. Run:
       jq -c '{id: .product_id, text: .sku_name}' ${worklist_file} > /tmp/${tmp_tag}_worklist.jsonl
  2. Run:
     ${PYTHON_BIN} ${REPO_ROOT}/script/non_niq/non_niq_helper.py retrieve \\
       --input-file /tmp/${tmp_tag}_worklist.jsonl \\
       --output-file /tmp/${tmp_tag}_candidates.jsonl \\
       --meili-index ${MEILI_INDEX}
     Run this synchronously and wait for it to finish before continuing -- never background this
     call or any other tool call in this session.
  3. Read back /tmp/${tmp_tag}_candidates.jsonl -- one line per product:
     {"id": "<product_id>", "candidates": [{"product_id","sku_name","brand","sku_type_complete",
     "mgh_2","mgh_3","mgh_4","product_type"}, ...]}. Each product's candidates are already the
     top hybrid-search results (confirmed past-QA'd products with the SAME taxonomy fields this
     session writes) from ${MEILI_INDEX} -- use them as grounding context for STEP 2b/2c (e.g. "a
     very similar past product was categorized as mgh_4=X, product_type=Y"), never as a
     substitute for actually checking the guidance doc yourself. An empty candidates array means
     retrieval failed for this product -- treat it the same as "no candidates found", do not
     block on it.

STEP 2 -- For each product in the worklist, in order:

  2a. RELEVANT to this category (outdoor equipment & supplies / Eiger-adjacent apparel, gear,
      footwear)? This judgment is MULTIMODAL -- you must actually LOOK at the product image, not
      just read its URL. Download it to a local file and then open that file with the Read tool:
        curl -sSL --max-time 30 "<image_url>" -o /tmp/${tmp_tag}_<product_id>.jpg
        (then: Read /tmp/${tmp_tag}_<product_id>.jpg)
      Do this BEFORE making any relevance / brand / category judgment for the product. If the
      download fails, or the downloaded file is not a readable image, say so explicitly in your
      reasoning for that product and treat it as TEXT-ONLY -- grounds to mark it unconfident in
      2d.
      NO  -> write {product_id, ecommerce_platform, sku_name, reason} to
             \`${PROJECT}.${filter_table}\`, _meta stamped
             '{"source":"claude_code","timestamp":"<now, ISO 8601 UTC>"}' (see the _meta format
             rule below), do NOT write to \`${QA_TABLE}\`. Move to the next product. Use the
             worklist row's OWN \`ecommerce_platform\` value verbatim.
      YES -> continue to 2b.

  2b. Guidance-doc taxonomy path. Read ${GUIDANCE_CSV} in full (1061 rows, columns: mgh_2,
      mgh_3, mgh_4, product_type, "Product Style" -- the 5th column's header is literally
      "Product Style", trailing empty columns in the file are not used). Using the image +
      sku_name + item_description/product_attributes_attrs (Shopee-only, NULL elsewhere -- treat
      NULL as no extra signal) + this product's existing brand/mgh_2/mgh_3/mgh_4/product_type/
      sku_type_complete from the worklist row as a starting hypothesis to verify (NOT to copy
      blindly -- it may be wrong or stale) + STEP 1's candidates as grounding context, determine:
        - mgh_2: one of the 5 values that appear in the guidance CSV (Active, Lifestyle,
          Mountaineering, Riding, Tactical).
        - mgh_3, mgh_4, product_type: each MUST be chosen from values that actually co-occur
          with your prior choices as a real row in the guidance CSV -- never free-typed. If you
          are unsure between two candidate rows, prefer the one whose product_type most
          specifically matches the product (the CSV often lists near-duplicate product_type
          spellings, e.g. "Low-cut shoes" vs "Low Cut Shoes" -- match meaning, not exact string).
        - Product Style: among ONLY the Product Style values listed for your exact
          mgh_2/mgh_3/mgh_4/product_type combination in the CSV, pick the best fit. The CSV
          itself lists catch-all options ("Not assigned", "N/A", "Mix") at most leaf
          combinations -- if no more specific style clearly fits, use one of these catch-alls
          rather than treating this as a blocker. There is no valid "no guidance match" outcome
          once mgh_2/mgh_3/mgh_4/product_type are chosen correctly.
      Write the chosen Product Style value to BOTH sku_type_complete and keywords when you write
      this product's row in 2d (do not write anything to vlookup, color, or gender -- leave them
      out of the INSERT, they are unused by this pipeline).

  2c. Brand resolution. First check: does this product's brand_store (the worklist row's own
      brand_store field) match a brand_store value in \`${PROJECT}.eiger.brand_store_product_fix\`?
      Query it: \`SELECT * FROM \\\`${PROJECT}.eiger.brand_store_product_fix\\\` WHERE brand_store =
      '<brand_store>'\`.
        MATCH FOUND (one or more rows) -> brand MUST come from this table -- never invent a
          brand for this store. Prefer an exact \`url\` match to this product's own URL if one
          exists among the returned rows; otherwise, use the product's image/sku_name to pick
          the best-fitting brand among the store's listed brands in the result set.
        NO MATCH -> this store is not a known multi-brand reseller. Brand resolution is the
          worklist row's existing \`brand\` value, verified against the image/sku_name (correct
          it if the image clearly shows a different, real brand; otherwise keep it) -- same as
          any other field in 2b's prior-value verification.
      \`eiger.brand_store_product_fix\` is read-only reference data -- never write to it, and
      never treat a NO MATCH as license to invent a brand not actually visible in the
      image/sku_name/existing value.

  2d. Write + self-QA. Having determined brand (2c), mgh_2/mgh_3/mgh_4/product_type/Product
      Style (2b), INSERT one new row into \`${QA_TABLE}\`:
        (product_id, ecommerce_platform, brand, sku_name, sku_type_complete, mgh_2, mgh_3,
         mgh_4, product_type, image, keywords, timestamp, _meta)
      -- sku_type_complete and keywords both get the Product Style value from 2b; timestamp =
      CURRENT_TIMESTAMP(); image = the worklist row's own image URL; vlookup, color, gender are
      left out of the column list entirely (NULL).
      This table is INSERT-ONLY -- never UPDATE or DELETE an existing row, even a wrong one; a
      correction is a new row with the same product_id and a newer timestamp.
      Then, as an explicit, separate judgment (not folded into 2a-2c's reasoning), state how
      confident you are in the decision you just made for this product:
      - If this is the product's FIRST time being processed this session (no qa_confidence value
        existed for it before this run, i.e. it was priority 0 in the worklist): _meta =
        '{"source":"claude_code","qa_confidence":"confident","timestamp":"<now, ISO 8601 UTC>"}'
        if confident, or
        '{"source":"claude_code","qa_confidence":"unconfident","human_review":false,"timestamp":"<now>"}'
        if not.
      - If this product ALREADY had a qa_confidence:'unconfident', human_review:false row before
        this run (i.e. this is its one allowed retry, priority 1 in the worklist): and you are
        STILL unconfident after redoing 2a-2c with full multimodal effort, write _meta =
        '{"source":"claude_code","qa_confidence":"unconfident","human_review":true,"timestamp":"<now>"}'
        -- this is terminal, the product will not re-enter future worklists for this script.
        If you ARE confident on this retry, write the confident shape as above.

STEP 3 -- Meilisearch write-back for newly-confident categorizations. After STEP 2 finishes,
products that ended up recorded \`qa_confidence: "confident"\` in STEP 2d (whether first-time or
retry) are worth making searchable for future sessions. Filtered-out and unconfident products are
skipped -- never index an unconfident guess.
  1. Build one JSONL file of every qualifying product from this session, one line each -- you
     already have these values from your own STEP 2 writes, no requery needed:
     {"product_id": "<product_id>", "sku_name": "<sku_name>", "sku_type_complete": "<value written>",
      "brand": "<value written>", "mgh_2": "<value written>", "mgh_3": "<value written>",
      "mgh_4": "<value written>", "product_type": "<value written>"}
     at /tmp/${tmp_tag}_new_entries.jsonl. If there are zero qualifying products, skip this step
     entirely -- do not run the command below with an empty or missing file.
  2. Run ONE batch call (never one call per product):
     ${PYTHON_BIN} ${REPO_ROOT}/script/non_niq/non_niq_helper.py index \\
       --input-file /tmp/${tmp_tag}_new_entries.jsonl \\
       --meili-index ${MEILI_INDEX}
     Run this synchronously and wait for it to finish, same as every other tool call this
     session.

Hard rules, never relaxed:
- NEVER background any tool call and NEVER end your turn to wait for one to finish -- this is a
  single one-shot session with no way to resume and no notification will ever arrive. Always
  issue tool calls synchronously and wait for each one's real result before proceeding. Ending
  your turn before the full worklist is processed is not a valid outcome under any circumstance.
- All writes use bq query DML, never the streaming API -- CLAUDE.md's 90-minute streaming-buffer
  rule. The very next run's retry-cap logic depends on reading back this run's QA rows reliably.
- Never write to \`qa_status\` on the source table (master_table_prod). A separate QA-labelling
  update process reads \`${QA_TABLE}\` independently and flips \`qa_status\` to 'Reviewed' once a
  product has a row there.
- Every _meta read you do yourself (e.g. checking whether a product already has an unconfident
  row) must use JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.field'), never bare JSON_VALUE(_meta, ...)
  and never SAFE.JSON_VALUE(...) -- the latter LOOKS right but is not valid BigQuery syntax
  ("SAFE with function json_value is not supported"). Some existing _meta values on legacy human-
  labelled rows are NOT this pipeline's JSON shape at all (e.g. {"name":...,"role":"QAFREELANCE",
  ...}) -- SAFE.PARSE_JSON handles those fine, and JSON_VALUE for a field that isn't present
  simply returns NULL, which is correct/intended (those legacy rows have no qa_confidence, so
  they never satisfy the retry-eligible branch and are treated as already-resolved).
- Every _meta WRITE must be a JSON string, never a bare string. Baseline format:
    {"source":"claude_code","timestamp":"<now, ISO 8601 UTC>"}
  e.g. {"source":"claude_code","timestamp":"2026-09-02T19:19:06Z"}.
- Attempt to resolve the ENTIRE worklist within your turn budget this session -- do not
  self-limit to a small sample. Stop early only when genuinely low on turns, and say so honestly
  in findings.

If you hit a genuine blocker -- something wrong with these instructions, missing data, anything
that would make proceeding unsafe -- stop and output status='blocked' with the blockers array
populated. That is a valid, expected outcome.

Output ONLY this JSON when done, nothing else (rows_created_in_dict here means "rows this
session newly indexed into Meilisearch in STEP 3" -- eiger has no separate dict-table insert
event to count):
{status: complete|partial|failed|blocked, rows_qa_confirmed, rows_qa_unconfident, rows_filtered, rows_created_in_dict, findings, blockers}.
PROMPT
}

extract_json_object() {
  local text="$1"
  printf '%s' "$text" | grep -Pzo '(?s)\{.*\}' | tr -d '\0'
}

# Identical to non_niq_qa_v2.sh's -- shared contract, not shared code.
extract_result_json() {
  local claude_output="$1"
  local result_json
  result_json=$(echo "$claude_output" | jq -r '.result // empty' 2>/dev/null) || result_json=""
  if [[ -z "$result_json" ]]; then
    echo ""
    return
  fi
  if ! echo "$result_json" | jq -e . >/dev/null 2>&1; then
    local extracted
    extracted=$(extract_json_object "$result_json")
    if [[ -n "$extracted" ]] && echo "$extracted" | jq -e . >/dev/null 2>&1; then
      result_json="$extracted"
    fi
  fi
  echo "$result_json"
}

decide_queue_signal() {
  local claude_output="$1"
  local result_json
  result_json=$(extract_result_json "$claude_output")
  if [[ -z "$result_json" ]]; then
    echo "FAILED"
    return
  fi
  local status
  status=$(echo "$result_json" | jq -r '.status // empty' 2>/dev/null) || status=""
  case "$status" in
    blocked) echo "BLOCKED" ;;
    complete|partial) echo "DONE" ;;
    *) echo "FAILED" ;;
  esac
}

format_result_summary() {
  local claude_output="$1"
  local result_json
  result_json=$(extract_result_json "$claude_output")

  local status rows_confirmed rows_unconfident rows_filtered rows_created findings blockers
  if [[ -z "$result_json" ]]; then
    status="unknown"
    rows_confirmed="?"
    rows_unconfident="?"
    rows_filtered="?"
    rows_created="?"
    findings="(unparseable)"
    blockers="(unparseable)"
  else
    status=$(echo "$result_json" | jq -r '.status // "unknown"' 2>/dev/null) || status="unknown"
    rows_confirmed=$(echo "$result_json" | jq -r '.rows_qa_confirmed // "?"' 2>/dev/null) || rows_confirmed="?"
    rows_unconfident=$(echo "$result_json" | jq -r '.rows_qa_unconfident // "?"' 2>/dev/null) || rows_unconfident="?"
    rows_filtered=$(echo "$result_json" | jq -r '.rows_filtered // "?"' 2>/dev/null) || rows_filtered="?"
    rows_created=$(echo "$result_json" | jq -r '.rows_created_in_dict // "?"' 2>/dev/null) || rows_created="?"
    findings=$(echo "$result_json" | jq -r '
      if .findings == null then "(none)"
      elif (.findings | type) == "array" then (.findings | join("\n"))
      else (.findings | tostring) end' 2>/dev/null) || findings="(unparseable)"
    blockers=$(echo "$result_json" | jq -r '
      if .blockers == null or (.blockers | length) == 0 then "(none)"
      elif (.blockers | type) == "array" then (.blockers | join("\n"))
      else (.blockers | tostring) end' 2>/dev/null) || blockers="(unparseable)"
  fi

  local num_turns duration_ms total_cost
  num_turns=$(echo "$claude_output" | jq -r '.num_turns // "?"' 2>/dev/null) || num_turns="?"
  duration_ms=$(echo "$claude_output" | jq -r '.duration_ms // "?"' 2>/dev/null) || duration_ms="?"
  total_cost=$(echo "$claude_output" | jq -r '.total_cost_usd // "?"' 2>/dev/null) || total_cost="?"

  local per_model
  per_model=$(echo "$claude_output" | jq -r '
    (.modelUsage // {}) | to_entries[] |
    "  \(.key): $\(.value.costUSD) (in: \(.value.inputTokens) tok, out: \(.value.outputTokens) tok, cache_read: \(.value.cacheReadInputTokens) tok, cache_creation: \(.value.cacheCreationInputTokens) tok)"
  ' 2>/dev/null) || per_model=""
  [[ -z "$per_model" ]] && per_model="  (no model usage reported)"

  cat <<SUMMARY

=== eiger QA Session Result ===
Status: ${status}
Confirmed: ${rows_confirmed} | Unconfident: ${rows_unconfident} | Filtered: ${rows_filtered} | Indexed: ${rows_created}

Turns used: ${num_turns} | Duration: ${duration_ms}ms | Total cost: \$${total_cost}

Per-model cost:
${per_model}

Findings:
${findings}

Blockers:
${blockers}
SUMMARY
}

main() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <PLATFORM> [COUNTRY] [MAX_TURNS] [MAX_ROWS]" >&2
    exit 1
  fi
  local platform="$1" country="${2:-ID}" max_turns="${3:-300}" max_rows="${4:-300}"
  country="${country^^}"

  log INFO "Resolving config Sheet row for eiger/${platform}/${country}..."
  local category_json
  category_json=$("$PYTHON_BIN" "$(dirname "$0")/non_niq_helper.py" categories --country "$country" \
    | jq -c --arg pl "$platform" '.[] | select(.dataset == "eiger" and .ecommerce_platform == $pl)')
  if [[ -z "$category_json" ]]; then
    echo "No active config Sheet row for dataset=eiger platform=${platform} country=${country}" >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "eiger:${platform}" "FAILED" "No active config Sheet row for country=${country}"
    exit 1
  fi

  local source_table filter_table_config enrichment_table
  source_table=$(echo "$category_json" | jq -r '.master_table_prod')
  filter_table_config=$(echo "$category_json" | jq -r '.filter_table')
  enrichment_table=$(echo "$category_json" | jq -r '."0"')
  local filter_table
  filter_table=$(primary_filter_table "$filter_table_config" "eiger")
  log INFO "Config resolved: source_table=${source_table}, qa_table=${QA_TABLE}, filter_table=${filter_table}"

  local t
  for t in "source_table=$source_table" "filter_table=$filter_table"; do
    if [[ "${t#*=}" == "-" || "${t#*=}" == "null" || -z "${t#*=}" ]]; then
      echo "Config Sheet row for dataset=eiger platform=${platform} has unconfigured ${t%%=*} ('${t#*=}') -- cannot run eiger QA." >&2
      echo "QUEUE_SIGNAL: FAILED"
      emit_result "eiger:${platform}" "FAILED" "Unconfigured ${t%%=*} in config Sheet row"
      exit 1
    fi
  done

  log INFO "Querying BigQuery for the latest month on ${source_table}/${platform}..."
  local month
  if ! month=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "$(default_month_query "$source_table" "$platform")" | tail -1); then
    echo "bq query failed while resolving the latest month for ${source_table}/${platform} -- see bq's error above." >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "eiger:${platform}" "FAILED" "bq query failed resolving latest month for ${source_table}/${platform}"
    exit 1
  fi
  log INFO "Latest month resolved: ${month}"

  local tmp_tag="eiger_${platform}_${country}"
  local query
  query=$(worklist_query "$source_table" "$month" "$platform" "$enrichment_table" "$max_rows" "$filter_table")

  log INFO "Querying BigQuery to materialize the worklist (product_tier=Tier 1, limit=${max_rows})..."
  local worklist_file="/tmp/${tmp_tag}_full_worklist.jsonl"
  if ! bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=json --max_rows=1000000 \
    "$query" | jq -c '.[]' > "$worklist_file"; then
    echo "bq query failed while materializing the worklist for eiger/${platform}/${country} -- see bq's error above." >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "eiger:${platform}" "FAILED" "bq query failed materializing worklist for eiger/${platform}/${country}"
    exit 1
  fi

  local worklist_count
  worklist_count=$(wc -l < "$worklist_file" | tr -d ' ')

  if [[ "$worklist_count" == "0" ]]; then
    echo "No in-scope worklist for eiger/${platform}/${country}/${month} (product_tier=Tier 1) -- nothing to do."
    rm -f "$worklist_file"
    echo "QUEUE_SIGNAL: NOTHING_TO_DO"
    emit_result "eiger:${platform}" "NOTHING_TO_DO" "No in-scope worklist for eiger/${platform}/${country}/${month}"
    exit 0
  fi

  log INFO "Worklist materialized: ${worklist_count} rows (eiger/${platform}/${country}, month=${month})"

  local prompt
  prompt=$(build_qa_prompt "$platform" "$country" "$source_table" "$filter_table" "$worklist_file" "$worklist_count" "$tmp_tag")

  log INFO "Delegating to claude (max_turns=${max_turns}) -- embeds+retrieves via Meilisearch, then runs the per-product QA loop. No further progress output until it returns."

  local claude_output
  claude_output=$(claude -p --output-format json --permission-mode bypassPermissions --max-turns "$max_turns" "$prompt") || true
  log INFO "claude subprocess returned, formatting summary..."
  echo "$claude_output"
  format_result_summary "$claude_output"

  local signal
  signal=$(decide_queue_signal "$claude_output")
  echo "QUEUE_SIGNAL: ${signal}"
  emit_result "eiger:${platform}" "$signal" "eiger QA session finished"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
