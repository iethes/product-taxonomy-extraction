#!/usr/bin/env bash
set -euo pipefail

# Usage: ./script/poc_multimodal_match.sh
# POC: Match-only taxonomy labeling for babycologne ID Shopee, July 2026.
# Compares agentic multimodal results against human QA (product_id_dict_qa).
# See docs/superpowers/specs/2026-08-04-agentic-multimodal-poc-design.md

PROJECT="sincere-hearth-273704"
DATASET="babycologne"
TABLE="master_babycologne_id_dev"
DICT_TABLE="babycologne_dict"
ENRICH_TABLE="0_pipeline_babycologne_shopee_id"
QA_TABLE="product_id_dict_qa"
MONTH="2026-07-01"
PLATFORM="Shopee"
TEMP_TABLE="_poc_match_20260804"
# Full reference for queries: project.dataset.table
TEMP_FULL="${PROJECT}.${DATASET}.${TEMP_TABLE}"
# bq --destination_table wants dataset.table, not project.dataset.table
TEMP_DEST="${DATASET}.${TEMP_TABLE}"

TIER1_MIN_SCORE=2
BATCH_SIZE=5
CLAUDE_MAX_TURNS=5

# ── helpers ──

bq_csv() {
  bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv "$1" | tail -n +2
}

bq_count() {
  bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "SELECT COUNT(*) FROM (${1})" | tail -1
}

# ── Tier 1: SQL keyword match ──

tier1_match() {
  echo "=== Tier 1: SQL keyword match ==="
  echo "Scoring ${PLATFORM} products (qa_status='Reviewed', month=${MONTH}) against ${DICT_TABLE}..."

  bq query --use_legacy_sql=false --project_id="${PROJECT}" \
    --destination_table="${TEMP_DEST}" \
    --replace \
    "
    WITH product_text AS (
      SELECT
        p.product_id,
        p.sku_name,
        p.image,
        p.brand AS master_brand,
        p.sku_type_complete AS existing_sku,
        COALESCE(e.item_description, '') AS item_desc,
        COALESCE(e.product_attributes_attrs, '') AS product_specs,
        LOWER(CONCAT(
          p.sku_name, ' ',
          IFNULL(e.item_description, ''), ' ',
          IFNULL(e.product_attributes_attrs, '')
        )) AS search_text
      FROM \`${PROJECT}.${DATASET}.${TABLE}\` p
      LEFT JOIN \`${PROJECT}.${DATASET}.${ENRICH_TABLE}\` e
        ON CAST(e.item_itemid AS STRING) = p.product_id
      WHERE p.ecommerce_platform = '${PLATFORM}'
        AND p.month = '${MONTH}'
        AND p.qa_status = 'Reviewed'
        AND NOT COALESCE(p.flag_GWP, FALSE)
    ),
    scored AS (
      SELECT
        pt.product_id,
        pt.sku_name,
        pt.image,
        pt.master_brand,
        pt.existing_sku,
        d.brand AS dict_brand,
        d.sku_type AS dict_sku_type,
        (SELECT COUNT(*) FROM UNNEST(SPLIT(LOWER(d.keywords), ' ')) AS kw
         WHERE LENGTH(kw) > 1 AND pt.search_text LIKE CONCAT('%', kw, '%'))
        +
        (SELECT COUNT(*) FROM UNNEST(SPLIT(LOWER(d.keywords_typo), ' ')) AS kw
         WHERE LENGTH(kw) > 1 AND pt.search_text LIKE CONCAT('%', kw, '%'))
        AS match_score
      FROM product_text pt
      CROSS JOIN \`${PROJECT}.${DATASET}.${DICT_TABLE}\` d
    ),
    ranked AS (
      SELECT *,
        ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY match_score DESC) AS rn
      FROM scored
    )
    SELECT
      product_id,
      sku_name,
      image,
      master_brand,
      existing_sku,
      dict_brand AS poc_brand,
      dict_sku_type AS poc_sku_type,
      match_score,
      rn
    FROM ranked
    WHERE rn = 1
    "

  local total matched
  total=$(bq_count "SELECT product_id FROM \`${TEMP_FULL}\`")
  matched=$(bq_count "SELECT product_id FROM \`${TEMP_FULL}\` WHERE match_score >= ${TIER1_MIN_SCORE}")

  local low
  low=$((total - matched))
  echo "Tier 1 done: ${matched}/${total} matched (score >= ${TIER1_MIN_SCORE}), ${low} need Tier 2"
}

# ── Tier 2: LLM multimodal match ──

build_dict_tsv() {
  bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "SELECT ROW_NUMBER() OVER() - 1 AS idx, brand, sku_type, keywords
     FROM \`${PROJECT}.${DATASET}.${DICT_TABLE}\`" > /tmp/poc_dict.tsv
  echo "Dict exported: $(wc -l < /tmp/poc_dict.tsv) entries"
}

tier2_match() {
  local low_count
  low_count=$(bq_count "SELECT product_id FROM \`${TEMP_FULL}\` WHERE match_score < ${TIER1_MIN_SCORE}")
  if [[ "$low_count" -eq 0 ]]; then
    echo "Tier 2: nothing to do (all matched in Tier 1)"
    return 0
  fi
  echo "=== Tier 2: LLM multimodal (${low_count} products, batches of ${BATCH_SIZE}) ==="

  build_dict_tsv

  # Fetch unmatched products as JSONL
  bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=json \
    --max_rows=100000 \
    "SELECT product_id, sku_name, image, master_brand, existing_sku
     FROM \`${TEMP_FULL}\`
     WHERE match_score < ${TIER1_MIN_SCORE}" \
    | jq -c '.[]' > /tmp/poc_tier2_products.jsonl

  local total_products matched=0 llm_matched=0
  total_products=$(wc -l < /tmp/poc_tier2_products.jsonl)
  local batch=()
  local batch_count=0

  while IFS= read -r line; do
    batch+=("$line")
    batch_count=$((batch_count + 1))
    if [[ $batch_count -ge ${BATCH_SIZE} ]]; then
      process_batch "${batch[@]}"
      local bm bl
      bm=$(echo "$batch_result" | jq -r '.matched // 0')
      bl=$(echo "$batch_result" | jq -r '.llm_matched // 0')
      matched=$((matched + bm))
      llm_matched=$((llm_matched + bl))
      batch=()
      batch_count=0
    fi
  done < /tmp/poc_tier2_products.jsonl

  # Last partial batch
  if [[ $batch_count -gt 0 ]]; then
    process_batch "${batch[@]}"
    local bm bl
    bm=$(echo "$batch_result" | jq -r '.matched // 0')
    bl=$(echo "$batch_result" | jq -r '.llm_matched // 0')
    matched=$((matched + bm))
    llm_matched=$((llm_matched + bl))
  fi

  echo "Tier 2 done: ${llm_matched}/${matched}/${total_products} (LLM match / batch total / total)"
}

process_batch() {
  local products_json
  products_json=$(printf '%s\n' "$@" | jq -s '.')

  local batch_size
  batch_size=$(echo "$products_json" | jq 'length')

  # Build prompt with full dict + product list
  local prompt
  prompt=$(cat <<PROMPT
You are matching e-commerce products to a taxonomy dictionary.

Match each product to ONE dict entry. Return ONLY JSON.

DICTIONARY (idx | brand | sku_type | keywords):
$(cat /tmp/poc_dict.tsv)

PRODUCTS (${batch_size} items):
$(echo "$products_json" | jq -r 'to_entries[] | "  Product \(.key): product_id=\(.value.product_id) | sku_name=\"\(.value.sku_name)\" | image=\(.value.image)"')

MATCH RULES:
1. Brand first — wrong brand = no match (-1).
2. Then product type/variant/size from keywords.
3. Scent/age_group only as tiebreakers.
4. If no dict entry matches, return -1.

Return ONLY this JSON array (no commentary):
[{"product_id":"...","dict_idx":N,"brand":"...","sku_type":"..."}, ...]
PROMPT
)

  echo "  Batch: ${batch_size} products → claude -p (${CLAUDE_MAX_TURNS} turns)..."

  local result
  result=$(claude -p --output-format json --permission-mode bypassPermissions \
    --max-turns "${CLAUDE_MAX_TURNS}" "$prompt" 2>/dev/null) || {
    echo "  WARNING: claude call failed"
    batch_result='{"matched":0,"llm_matched":0}'
    return
  }

  # Extract result JSON
  local parsed
  parsed=$(echo "$result" | jq -r '.result // empty' 2>/dev/null)
  # Sometimes the model wraps in code fences — try to recover
  if ! echo "$parsed" | jq -e '. | if type == "array" then true else false end' >/dev/null 2>&1; then
    parsed=$(echo "$parsed" | grep -Pzo '(?s)\[.*\]' | tr -d '\0' || echo "")
  fi
  if [[ -z "$parsed" ]] || ! echo "$parsed" | jq -e '.' >/dev/null 2>&1; then
    echo "  WARNING: no parseable JSON array in result"
    batch_result='{"matched":0,"llm_matched":0}'
    return
  fi

  # Write each match result to temp table
  local match_count=0
  echo "$parsed" | jq -c '.[]' | while IFS= read -r match; do
    local pid didx dbrand dtype
    pid=$(echo "$match" | jq -r '.product_id // empty')
    didx=$(echo "$match" | jq -r '.dict_idx // empty')
    dbrand=$(echo "$match" | jq -r '.brand // empty')
    dtype=$(echo "$match" | jq -r '.sku_type // empty')

    if [[ -z "$pid" || -z "$dtype" || "$didx" == "-1" || "$didx" == "null" ]]; then
      continue
    fi

    # ponytail: escape single quotes in brand/sku_type for SQL
    local safe_brand safe_type
    safe_brand="${dbrand//\'/\\\'}"
    safe_type="${dtype//\'/\\\'}"

    bq query --use_legacy_sql=false --project_id="${PROJECT}" \
      "UPDATE \`${TEMP_FULL}\`
       SET poc_brand = '${safe_brand}',
           poc_sku_type = '${safe_type}',
           match_source = 'LLM',
           match_score = 99
       WHERE product_id = '${pid}'" >/dev/null 2>&1
  done

  # Count how many got LLM matches
  local llm_count
  llm_count=$(echo "$parsed" | jq '[.[] | select(.dict_idx != "-1" and .dict_idx != null and .dict_idx != -1)] | length')
  batch_result="{\"matched\":${batch_size},\"llm_matched\":${llm_count}}"
}

# ── Swap Tier 1 columns into final column names ──

finalize_tier1() {
  echo "=== Finalizing Tier 1 results ==="
  bq query --use_legacy_sql=false --project_id="${PROJECT}" \
    "UPDATE \`${TEMP_FULL}\`
     SET match_source = 'TEXT'
     WHERE match_source IS NULL AND poc_sku_type IS NOT NULL"
}

# ── Load QA reference data ──

load_qa_ref() {
  echo "=== Loading QA reference data ==="
  bq query --use_legacy_sql=false --project_id="${PROJECT}" \
    "CREATE OR REPLACE TABLE \`${TEMP_DEST}\` AS
     SELECT
       t.*,
       q.brand AS qa_brand,
       q.sku_type_complete AS qa_sku_type
     FROM \`${TEMP_FULL}\` t
     LEFT JOIN \`${PROJECT}.${DATASET}.${QA_TABLE}\` q
       ON t.product_id = q.prod_id
       AND q.ecommerce_platform = '${PLATFORM}'"

  local with_qa
  with_qa=$(bq_count "SELECT product_id FROM \`${TEMP_FULL}\` WHERE qa_sku_type IS NOT NULL")
  echo "QA ref loaded: ${with_qa} products have QA data"
}

# ── Comparison report ──

run_comparison() {
  echo ""
  echo "============================================"
  echo "=== COMPARISON: POC vs Human QA ==="
  echo "============================================"

  bq query --use_legacy_sql=false --project_id="${PROJECT}" \
    "
    WITH results AS (
      SELECT
        COUNT(*) AS total,
        COUNTIF(poc_sku_type IS NOT NULL) AS matched,
        COUNTIF(match_source = 'TEXT') AS text_matched,
        COUNTIF(match_source = 'LLM') AS llm_matched,
        COUNTIF(poc_brand = qa_brand AND qa_brand IS NOT NULL) AS brand_match,
        COUNTIF(poc_sku_type = qa_sku_type AND qa_sku_type IS NOT NULL) AS exact_sku_match,
        COUNTIF(poc_brand = qa_brand AND poc_sku_type = qa_sku_type
                AND qa_brand IS NOT NULL AND qa_sku_type IS NOT NULL) AS full_match,
        COUNTIF(match_source = 'TEXT' AND poc_sku_type = qa_sku_type AND qa_sku_type IS NOT NULL) AS text_exact,
        COUNTIF(match_source = 'LLM' AND poc_sku_type = qa_sku_type AND qa_sku_type IS NOT NULL) AS llm_exact,
        COUNTIF(poc_sku_type IS NULL) AS unmatched,
        COUNTIF(qa_sku_type IS NOT NULL) AS has_qa
      FROM \`${TEMP_FULL}\`
    )
    SELECT
      total,
      matched, ROUND(100.0 * matched / NULLIF(total, 0), 1) AS matched_pct,
      text_matched, llm_matched,
      has_qa,
      ROUND(100.0 * brand_match / NULLIF(has_qa, 0), 1) AS brand_match_pct,
      ROUND(100.0 * exact_sku_match / NULLIF(has_qa, 0), 1) AS sku_match_pct,
      ROUND(100.0 * full_match / NULLIF(has_qa, 0), 1) AS full_match_pct,
      text_exact, llm_exact,
      unmatched
    FROM results
    "
}

show_mismatches() {
  echo ""
  echo "=== Top 20 mismatches (POC vs QA sku_type) ==="
  bq query --use_legacy_sql=false --project_id="${PROJECT}" --max_rows=20 \
    "SELECT product_id, sku_name,
            poc_brand, qa_brand,
            poc_sku_type, qa_sku_type,
            match_source
     FROM \`${TEMP_FULL}\`
     WHERE poc_sku_type IS NOT NULL
       AND qa_sku_type IS NOT NULL
       AND poc_sku_type != qa_sku_type
     ORDER BY match_score DESC
     LIMIT 20"
}

# ── Gate check ──

check_gates() {
  echo ""
  echo "=== Gate check ==="

  local result
  result=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "SELECT
       COUNT(*) AS total,
       COUNTIF(qa_sku_type IS NOT NULL) AS has_qa,
       COUNTIF(poc_brand = qa_brand AND qa_brand IS NOT NULL) AS brand_match,
       COUNTIF(poc_sku_type = qa_sku_type AND qa_sku_type IS NOT NULL) AS sku_match,
       COUNTIF(poc_sku_type IS NULL) AS unmatched
     FROM \`${TEMP_FULL}\`" | tail -1)

  IFS=',' read -r total has_qa brand_match sku_match unmatched <<< "$result"

  local match_rate=0 sku_rate=0 brand_rate=0
  [[ "${total:-0}" -gt 0 ]] && match_rate=$(echo "scale=1; 100 * (${total} - ${unmatched}) / ${total}" | bc 2>/dev/null || echo "0")
  [[ "${has_qa:-0}" -gt 0 ]] && sku_rate=$(echo "scale=1; 100 * ${sku_match} / ${has_qa}" | bc 2>/dev/null || echo "0")
  [[ "${has_qa:-0}" -gt 0 ]] && brand_rate=$(echo "scale=1; 100 * ${brand_match} / ${has_qa}" | bc 2>/dev/null || echo "0")

  local pass=true
  echo "  Match rate: ${match_rate}% (gate: >= 95%)"
  if (( $(echo "${match_rate} < 95" | bc -l 2>/dev/null || echo "0") )); then pass=false; fi
  echo "  SKU exact:  ${sku_rate}% (gate: >= 70%)"
  if (( $(echo "${sku_rate} < 70" | bc -l 2>/dev/null || echo "0") )); then pass=false; fi
  echo "  Brand:      ${brand_rate}% (gate: >= 95%)"
  if (( $(echo "${brand_rate} < 95" | bc -l 2>/dev/null || echo "0") )); then pass=false; fi

  if $pass; then
    echo "  RESULT: ALL GATES PASS"
  else
    echo "  RESULT: GATES FAILED"
  fi
}

# ── main ──

main() {
  echo "POC Multimodal Match — ${DATASET} ${PLATFORM} ${MONTH}"
  echo "Target: ${TEMP_FULL}"
  echo ""

  tier1_match
  finalize_tier1
  tier2_match
  load_qa_ref
  run_comparison
  show_mismatches
  check_gates

  echo ""
  echo "Temp table: ${TEMP_FULL} (drop with: bq rm -f -t ${TEMP_FULL})"
  echo "Done."
}

main "$@"
