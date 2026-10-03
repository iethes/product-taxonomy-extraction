#!/usr/bin/env bash
set -euo pipefail

# Usage: script/non_niq/susubayi_qa.sh <PLATFORM> [COUNTRY] [MAX_TURNS] [MAX_ROWS]
# e.g.  script/non_niq/susubayi_qa.sh shopee
#       script/non_niq/susubayi_qa.sh blibli ID 500 300
#
# Dedicated agentic QA script for susubayi (Formula Milk) -- a copy of non_niq_qa_v2.sh's
# worklist/prompt/decision-tree machinery, hardcoded to dataset=susubayi, with four differences:
#
# 1. Tokopedia scope is every Tier 1 product OR every product whose principal is 'Official Store',
#    regardless of GMV. Other platforms retain the all-products-with-sales scope
#    (gmv_monthly > 0). Both scopes also include the merchant allowlist described below. See
#    worklist_query()'s tier_clause.
# 2. Blibli's worklist is the UNION of the normal master_table_prod scope (susubayi.master_susubayi_id)
#    with susubayi.master_mji_sellout_blibli, a separate MJI sellout feed for Blibli with its own
#    product_ids (confirmed live: 0 product_id overlap between the two tables for the same month).
#    That table has no gmv_monthly-in-the-same-sense/image columns -- every row in it is included
#    unconditionally (it's a sellout feed, every row already implies real sales), and its rows get
#    image = NULL, which the existing STEP 2a "download failed -> treat as TEXT-ONLY" fallback
#    already handles correctly (forces unconfident, no special-casing needed).
#    That table's `month` column is a DATE, and -- confirmed by the user, not yet observed live --
#    is not guaranteed to always land on the 1st of the month the way master_susubayi_id's does;
#    it can be any day in the 1st..last-day range of the month it represents. Matching via
#    FORMAT_DATE('%Y-%m', month) = '<target>' (same convention v2 already uses everywhere) is
#    correct for this regardless of which day-of-month is actually stored -- never compare it to
#    an exact DATE literal.
# 3. Every merchant_id tagged "Category Pipeline = Formula Milk" on the Client OS Only /
#    Competitor OS reference Sheet (same MERCHANT_REFERENCE_SPREADSHEET_ID non_niq_helper.py's
#    forced-merchants command already reads -- https://docs.google.com/spreadsheets/d/1Nf7TbmRhViS_vN-PNTXXSFEoGMoW4eKzYXHQEQjk--U,
#    gid=900705792 is that Sheet's "Client OS Only" tab) is force-included in the worklist
#    regardless of gmv_monthly -- this is v2's existing forced_merchant_ids_sql mechanism,
#    unchanged: confirmed live susubayi's config Sheet `category` value is literally "Formula
#    Milk", the exact string non_niq_helper.py's forced-merchants matches against, so this needs
#    no code change at all, just reuse.
# 4. Every row with principal = 'Official Store' on master_susubayi_id is force-included regardless
#    of gmv_monthly too, same OR-into-tier_clause treatment as the merchant-allowlist Sheet --
#    confirmed live this is a real, populated value (7,206 rows across all 5 platforms for
#    2026-08, not a typo/rare edge case). This is a plain column filter, unrelated to the
#    merchant-allowlist Sheet mechanism above -- it does NOT apply to master_mji_sellout_blibli
#    (that table also has a `principal` column, but the user was explicit this only applies to the
#    master table).
#
# kategori/MONTHLY_REVERIFY (v2 features for other datasets' sub-scoping / listing-swap
# detection) are dropped entirely here -- susubayi's source table has no `kategori` column and
# nobody has asked for monthly re-verify on this dataset, so keep this script's SQL to what it
# actually uses (same simplification eiger_qa.sh makes).
#
# AGENT_HARNESS env var (optional, defaults to "claude"): identical mechanism to non_niq_qa_v2.sh
# -- see its header comment for the full explanation. Claude and Codex have real adapters in
# main(); other names are recognized but refuse to run until wired up.
#       AGENT_HARNESS=codex script/non_niq/susubayi_qa.sh shopee

DATASET="susubayi"
PROJECT="sincere-hearth-273704"
MEILI_URL="http://34.124.146.29:7700"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PYTHON_BIN="${REPO_ROOT}/.venv/bin/python3"

source "${REPO_ROOT}/script/lib/common.sh"

# Identical to non_niq_qa_v2.sh's -- Claude and Codex have real adapters in main(); the remaining
# names let require_harness() distinguish "not installed" from "recognized but not wired yet".
declare -A HARNESS_BIN=(
  [claude]="claude"
  [codex]="codex"
  [pi]="pi"
  [omp]="omp"
  [opencode]="opencode"
)

# Validates the selected harness immediately before residual agent work, after wrapper-side
# automatic confirmations have been considered.
require_harness() {
  local harness="$1" bin
  bin="${HARNESS_BIN[$harness]:-}"
  if [[ -z "$bin" ]]; then
    echo "Unknown AGENT_HARNESS='${harness}' -- supported: ${!HARNESS_BIN[*]}" >&2
    return 1
  fi
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "AGENT_HARNESS='${harness}' selected but '${bin}' is not on PATH." >&2
    return 1
  fi
  case "$harness" in
    claude|codex) ;;
    *)
      echo "AGENT_HARNESS='${harness}' found on PATH, but its invocation/output-parsing isn't implemented in this script yet." >&2
      return 1
      ;;
  esac
}

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
  # Resolved from master_susubayi_id only, even for Blibli -- confirmed live both sources share
  # the same latest month currently. If the sellout feed ever lags, its UNION branch below just
  # contributes 0 rows for that run (same benign "no in-scope worklist" outcome v2 already has),
  # not a failure.
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
  echo "${entries[0]:-}"
}

# Scope: source-table Tier 1 + Tier 2 OR principal = 'Official Store', regardless of GMV. Every
# platform also ORs in the configured forced-merchant allowlist. For platform=Blibli, unions in
# susubayi.master_mji_sellout_blibli (no gmv_monthly>0 filter needed there -- it's a sellout feed,
# every row already implies real sales) and dedupes defensively on product_id (confirmed 0 overlap
# live, but a future data refresh could change that).
worklist_query() {
  local source_table="$1" qa_table="$2" qa_pk_col="$3" month="$4" platform="$5" enrichment_table="${6:-}"
  local row_limit="${7:-300}"
  local filter_table="${8:-}"
  local forced_merchant_ids_sql="${9:-}"
  local qa_platform_col="${10:-ecommerce_platform}"
  local platform_titlecase="${platform^}"
  local dataset="${source_table%%.*}"
  # item_description/product_attributes_attrs enrichment is Shopee-only -- ported verbatim from
  # non_niq_qa_v2.sh's worklist_query.
  local enrichment_cte_and_join="" enrichment_join="" enrichment_select="NULL AS item_description, NULL AS product_attributes_attrs"
  if [[ "$platform_titlecase" == "Shopee" && -n "$enrichment_table" && "$enrichment_table" != "-" && "$enrichment_table" != "null" ]]; then
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
  # product_tier is the source's precomputed top-90%-GMV population. Official Store products
  # remain force-included. This master-table condition is never applied to the sellout branch.
  local tier_clause="(s.product_tier IN ('Tier 1') OR s.principal = 'Official Store')"
  if [[ -n "$forced_merchant_ids_sql" ]]; then
    tier_clause="(${tier_clause} OR s.merchant_id IN (${forced_merchant_ids_sql}))"
  fi
  # Blibli only: UNION in the sellout feed, then dedupe on product_id (preferring whichever row
  # has an image, since the sellout branch never does) -- see the header comment for why this
  # table needs its own branch instead of being folded into `scoped` directly.
  local scoped_cte
  if [[ "$platform_titlecase" == "Blibli" ]]; then
    scoped_cte="scoped_raw AS (
  SELECT s.product_id, s.sku_name, REPLACE(s.image, '\"', '') AS image, s.ecommerce_platform, s.qa_status, s.gmv_monthly, ${enrichment_select}
  FROM \`${PROJECT}.${source_table}\` s
  ${enrichment_join}
  WHERE ${tier_clause}
    AND FORMAT_DATE('%Y-%m', s.month) = '${month}'
    AND s.ecommerce_platform = 'Blibli'
  UNION ALL
  SELECT b.product_id, b.sku_name, CAST(NULL AS STRING) AS image, b.ecommerce_platform, b.qa_status, b.daily_gmv AS gmv_monthly, NULL AS item_description, NULL AS product_attributes_attrs
  FROM \`${PROJECT}.${dataset}.master_mji_sellout_blibli\` b
  WHERE b.country = 'ID'
    AND FORMAT_DATE('%Y-%m', b.month) = '${month}'
    AND b.ecommerce_platform = 'Blibli'
),
scoped AS (
  SELECT * EXCEPT(rn) FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY (image IS NULL OR image = '')) AS rn
    FROM scoped_raw
  )
  WHERE rn = 1
),"
  else
    scoped_cte="scoped AS (
  SELECT s.product_id, s.sku_name, REPLACE(s.image, '\"', '') AS image, s.ecommerce_platform, s.qa_status, s.gmv_monthly, ${enrichment_select}
  FROM \`${PROJECT}.${source_table}\` s
  ${enrichment_join}
  WHERE ${tier_clause}
    AND FORMAT_DATE('%Y-%m', s.month) = '${month}'
    AND s.ecommerce_platform $(platform_match_clause "$platform_titlecase")
),"
  fi
  cat <<SQL
WITH ${enrichment_cte_and_join}${scoped_cte}
qa_title_state AS (
  SELECT DISTINCT ${qa_pk_col} AS product_id, ${qa_platform_col} AS ecommerce_platform,
    REGEXP_REPLACE(TRIM(sku_name), r'\s+', ' ') AS normalized_sku_name
  FROM \`${PROJECT}.${qa_table}\`
  WHERE ${qa_platform_col} $(platform_match_clause "$platform_titlecase")
),
qa_state AS (
  -- Keep QA state at current-title grain. A marketplace can reuse a product_id for a new title;
  -- an older QA row for that product_id must not suppress review of the changed listing.
  SELECT
    ${qa_pk_col} AS product_id, ${qa_platform_col} AS ecommerce_platform,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.qa_confidence') = 'unconfident'
               AND COALESCE(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.human_review'), 'false') != 'true') AS has_unconfident_pending,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.qa_confidence') = 'confident') AS has_confident,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.human_review') = 'true') AS has_terminal
  FROM \`${PROJECT}.${qa_table}\`
  WHERE ${qa_platform_col} $(platform_match_clause "$platform_titlecase")
  GROUP BY ${qa_pk_col}, ${qa_platform_col}
),
filter_state AS (
  SELECT DISTINCT product_id FROM \`${PROJECT}.${filter_table}\`
),
prioritized AS (
  SELECT sc.product_id, sc.sku_name, sc.image, sc.gmv_monthly, sc.ecommerce_platform,
         sc.item_description, sc.product_attributes_attrs,
    CASE
      WHEN fs.product_id IS NOT NULL THEN NULL
      WHEN qts.product_id IS NULL THEN 0
      WHEN qs.has_unconfident_pending AND NOT qs.has_confident AND NOT qs.has_terminal THEN 1
      ELSE NULL
    END AS priority
  FROM scoped sc
  LEFT JOIN qa_title_state qts
    ON qts.product_id = sc.product_id
   AND qts.ecommerce_platform = sc.ecommerce_platform
   AND qts.normalized_sku_name = REGEXP_REPLACE(TRIM(sc.sku_name), r'\s+', ' ')
  LEFT JOIN qa_state qs
    ON qs.product_id = sc.product_id
   AND qs.ecommerce_platform = sc.ecommerce_platform
  LEFT JOIN filter_state fs ON fs.product_id = sc.product_id
)
SELECT * FROM prioritized
WHERE priority IS NOT NULL
ORDER BY priority ASC, gmv_monthly DESC
LIMIT ${row_limit}
SQL
}

build_qa_prompt() {
  local platform="$1" country="$2" source_table="$3" qa_table="$4" dict_table="$5" filter_table="$6"
  local qa_pk_col="$7" dict_identity_col="$8" dict_typo_col="$9" meili_index="${10}" worklist_file="${11}"
  local worklist_count="${12}" product_id_dict="${13}" tmp_tag="${14}" agent_meta_source="${15:-claude_code}"

  local qa_identity_col="sku_type_complete"
  local scope_description
  if [[ "${platform^}" == "Tokopedia" ]]; then
    scope_description="It is scoped to every Tier 1 product plus every product whose principal is 'Official Store', regardless of GMV. Configured Formula-Milk merchant IDs remain force-included regardless of product tier, principal, or GMV."
  else
    scope_description="It is scoped to products with gmv_monthly > 0 this month, plus every product whose principal is 'Official Store' and every configured Formula-Milk merchant, both regardless of GMV."
  fi

  local identity_column_instruction
  if [[ "$dict_identity_col" == "$qa_identity_col" ]]; then
    identity_column_instruction="- Both tables intentionally name their identity column ${qa_identity_col}. Write
  ${qa_identity_col} to the QA table in every QA-table write, and use that same column name when
  reading/matching against or minting a row in the ${DATASET}_dict table. The identical column name
  is expected; the target table determines its role."
  else
    identity_column_instruction="- The QA table's identity column is ${qa_identity_col}. It is the same on every category and is
  what you write in every QA-table write below. Never write ${dict_identity_col} to the QA table.
- ${dict_identity_col} is the ${DATASET}_dict table's identity column. Use it ONLY when
  reading/matching against, or minting a new row in, the dict table."
  fi

  local step2_block
  if [[ "$product_id_dict" == "-" || "$product_id_dict" == "null" || -z "$product_id_dict" ]]; then
    step2_block="  2b. SKIPPED for this category: product_id_dict is not configured (Sheet value '-'), so there is
      no prior mapping to check. Go straight to 2c for every product."
  else
    step2_block="  2b. Prior mapping check against \`${PROJECT}.${product_id_dict}\`. Its schema is NOT resolved for
      you -- FIRST discover its real shape with
      \`SELECT * FROM \\\`${PROJECT}.${product_id_dict}\\\` LIMIT 1\` (or read its
      INFORMATION_SCHEMA.COLUMNS), then query it precisely for this product's row. Do NOT assume
      a column name. If a mapping row exists for this product: is that mapping CORRECT?
      YES -> write those SAME brand/${qa_identity_col} values to \`${PROJECT}.${qa_table}\`, then go to 2d.
      NO, or no mapping row for this product -> continue to 2c."
  fi

  cat <<PROMPT
susubayi (Formula Milk) agentic QA session for platform=${platform}, country=${country}. This is
a dedicated per-dataset script (script/non_niq/susubayi_qa.sh), not non_niq_qa_v2.sh, but the
decision tree, confidence loop, and _meta conventions below are the same shared design every
non-NIQ category uses.

Resolved for this run: source_table=${PROJECT}.${source_table} (master_table_prod, Tier-1
scoped)$( [[ "$platform" == "blibli" ]] && echo ", UNIONed with ${PROJECT}.${DATASET}.master_mji_sellout_blibli (see below)" ),
qa_table=${PROJECT}.${qa_table}, dict_table=${PROJECT}.${dict_table},
filter_table (write target)=${PROJECT}.${filter_table}, qa_pk_col=${qa_pk_col},
dict_identity_col=${dict_identity_col}, dict_typo_col=${dict_typo_col},
product_id_dict (prior mapping table, read-only)=${product_id_dict},
meilisearch_index=${meili_index} (at ${MEILI_URL}).
$( [[ "$platform" == "blibli" ]] && cat <<BLIBLI_NOTE

This run's worklist merges TWO sources for Blibli: the normal Tier-1 master table, and a separate
MJI sellout feed (${PROJECT}.${DATASET}.master_mji_sellout_blibli) that has its own distinct
product_ids and NO product image at all. Rows from that second source have image = null/empty in
the worklist file below -- for those, STEP 2a's "image download failed -> treat as TEXT-ONLY" rule
applies as normal (this is expected for every sellout-sourced row, not an error to report).
BLIBLI_NOTE
)

Identity columns -- do not mix these up:
${identity_column_instruction}

STEP 0 -- The full worklist has ALREADY been materialized for you at
${worklist_file}, exactly ${worklist_count} rows, one JSON object per line (JSONL) -- do NOT query
BigQuery to re-fetch it, and do NOT trust any other row count than ${worklist_count}. Read the file
(in slices if it's too large for one Read) rather than querying BigQuery for it. Each line has:
product_id, sku_name, image, gmv_monthly, ecommerce_platform, item_description,
product_attributes_attrs, priority. ${scope_description} The worklist is prioritized (unreviewed
rows before agent-flagged-unconfident retry rows, both by gmv_monthly descending) -- process it in
that order.
If you cannot account for all
${worklist_count} rows by the end of your turn budget, explicitly report status: partial (or
status: blocked if you cannot proceed at all) -- never silently process a subset and report
status: complete.

Rows whose merchant_id is tagged "Category Pipeline = Formula Milk" on the Client OS Only /
Competitor OS reference Sheet remain force-included regardless of GMV. Official Store scope applies
to the master table only, not Blibli-sellout-sourced rows. Treat all scoped rows exactly like any
other worklist row; do not skip or deprioritize them for being low-GMV.

STEP 1 -- The wrapper already ran one batch Meilisearch retrieval and directly confirmed the
unambiguous case-insensitive exact-title matches. The remaining worklist contains only products
that did not qualify for that trusted fast path. Do NOT run retrieval yourself.

Read /tmp/${tmp_tag}_candidates.jsonl when evaluating each remaining product:
{"id": "<product_id>", "product_id": "<product_id>", "ecommerce_platform": "<raw platform>",
 "candidates": [{"product_id","sku_name","brand","sku_type_complete"}, ...]}
Candidates are top hybrid-search exemplars from ${meili_index}; look up a product by its raw
product_id/ecommerce_platform pair. Do not construct another Meilisearch request.

STEP 2 -- For each product in the worklist, in order:

  2a. RELEVANT to this category (Formula Milk)? This judgment is MULTIMODAL -- you must actually
      LOOK at the product image, not just read its URL. The image URL is the worklist's \`image\`
      column (may be null/empty for Blibli-sellout-sourced rows -- see the note above).
      For each product with a non-empty image, download it to a local file and then open that
      file with the Read tool:
        curl -sSL --max-time 30 "<image_url>" -o /tmp/${tmp_tag}_<product_id>.jpg
        (then: Read /tmp/${tmp_tag}_<product_id>.jpg)
      Do this BEFORE making any relevance / brand / sku_type judgment for the product. Text-only
      reasoning on sku_name is exactly the failure mode this harness exists to fix -- do not skip
      the download and infer from the URL or the name when an image URL IS present.
      If the download fails, the image field is null/empty, or the downloaded file is not a
      readable image (curl happily writes a 404 HTML body into a .jpg), say so explicitly in your
      reasoning for that product and treat it as TEXT-ONLY -- which is by itself grounds to mark it
      unconfident in 2d.
      Then, with the image (if any) + sku_name + item_description + product_attributes_attrs
      together (Shopee-only signal, NULL elsewhere -- treat NULL as simply having no extra signal)
      -- does this product genuinely belong in "${DATASET}" (Formula Milk)?
      NO  -> write {product_id, ecommerce_platform, sku_name, reason} to \`${PROJECT}.${filter_table}\`
             (this dataset's OWN filter table -- never write to a different dataset's filter table
             even if the Sheet cross-references one for read context), _meta stamped
             '{"source":"${agent_meta_source}","timestamp":"<now, ISO 8601 UTC>"}' (see the _meta format
             rule below), do NOT create a taxonomy entry. Move to the next product.
             Use the worklist row's OWN \`ecommerce_platform\` value verbatim (it's the source
             table's real, Title-Case value, e.g. "Shopee"/"Blibli" -- do not lowercase it or
             reconstruct it yourself, the Sheet's lowercase convention is NOT what's stored here).
      YES -> continue to 2b.

${step2_block}

  2c. Candidate check: read this product's line from the STEP 1 output file (match by
      product_id) -- its \`candidates\` array is already the confirmed exemplars (product_id,
      sku_name, brand, sku_type_complete of similar past-QA'd products) from Meilisearch hybrid
      search, retrieved for you in STEP 1. Not raw dict rows -- use them as grounding context, then
      check the candidates' implied dict entries against \`${PROJECT}.${dict_table}\` for the real
      match. An empty \`candidates\` array means retrieval failed for this product (see STEP 1's
      output for the warning) -- treat it the same as "no candidates found", do not block on it.
      Does a TRUE matching taxonomy record exist in ${dict_table}?
      YES -> write CORRECTED (re-pointed) brand/${qa_identity_col} values to
             \`${PROJECT}.${qa_table}\`.
      NO  -> two-step create in \`${PROJECT}.${dict_table}\`:
             Step A: FIRST resolve this category's generated-column pattern. Read
                     ${REPO_ROOT}/script/non_niq/dict_patterns/${DATASET}.json.
                     - EXISTS -> follow it mechanically: each key is a generated column (e.g.
                       sku_type_complete, keywords), its "sources" is the ordered list of other
                       dict-table columns it's composed from, "separator" is how they're joined.
                       Populate every listed source column first (grounded via
                       \`SELECT DISTINCT <column> FROM ${PROJECT}.${dict_table}\`, same technique
                       as Step B below), skipping any source that's null/empty when composing --
                       never emit a literal "null" or a dangling separator.
                     - MISSING -> infer the pattern yourself: sample ~10-20 existing rows from
                       \`${PROJECT}.${dict_table}\` and work out how sku_type_complete/keywords
                       (and any other generated columns this category has) are actually composed
                       from other columns. Then Write your inferred pattern to
                       ${REPO_ROOT}/script/non_niq/dict_patterns/${DATASET}.json in the schema
                       above, so the next session for this dataset reads it instead of
                       re-inferring.
                     Prepare brand + ${dict_identity_col} + keywords (+ ${dict_typo_col} if you
                     have common misspellings) for the complete dict row; do not INSERT yet.
                     Include the dict table's existing \`_meta\` column and stamp it with
                     '{"source":"${agent_meta_source}","timestamp":"<now, ISO 8601 UTC>"}' (see
                     the _meta format rule below -- NOT the bare string "${agent_meta_source}",
                     that is not valid JSON).
             Step B: populate the remaining attribute columns for this dict's schema, GROUNDED on
                     existing dict rows' actual vocabulary and formatting -- query
                     \`SELECT DISTINCT <column> FROM ${PROJECT}.${dict_table}\` per attribute column
                     before writing a new value, prefer an existing value over inventing one, and
                     match existing formatting exactly (e.g. "150 ml" not "150ml"). Every column
                     on the new row must be non-null EXCEPT ${dict_typo_col}. After printing this
                     product's complete ledger, INSERT the complete dictionary row once, then
                     verify with a \`SELECT\` for any NULL in a non-\`${dict_typo_col}\` column on
                     the just-inserted row (never trust bq's "affected rows" report as proof the
                     row is complete) -- an unexpected NULL means Step B's grounding was
                     incomplete, not something to patch after the fact.
             Then write brand/${qa_identity_col} values pointing at the new entry to
             \`${PROJECT}.${qa_table}\`.

  2c.1. Mandatory durable insert log for every NEW dictionary row: the dictionary-table INSERT
        and its log INSERT MUST run in the SAME BigQuery transaction. The shared append-only log
        table is \`${PROJECT}.magpie_reference.non_niq_taxonomy_insert_log\` with columns
        (target_table STRING, created_at TIMESTAMP, row_json JSON). Set target_table to the exact
        three-part target name \`${PROJECT}.${dict_table}\`. row_json MUST be the JSON envelope
        {"product_id":"<worklist product_id>","ecommerce_platform":"<worklist ecommerce_platform>",
         "inserted_row":{...exact columns and values inserted into ${PROJECT}.${dict_table}...}}.
        Write one log row only when this transaction actually inserts a NEW dictionary row; do
        not log an existing identity, a re-point, a filter, or a zero-row conditional INSERT.
        If either the dictionary INSERT or its log INSERT fails, the transaction must roll back
        both. After COMMIT, verify both the exact dictionary row and its matching log row exist.


  2d. Self-QA: as an explicit, separate judgment (not folded into 2a-2c's reasoning), state how
      confident you are in the decision you just made for this product. Then:
      - If this is the product's FIRST time being processed this session (no qa_confidence value
        existed for it before this run): write _meta =
        '{"source":"${agent_meta_source}","qa_confidence":"confident","timestamp":"<now, ISO 8601 UTC>"}' if
        confident, or
        '{"source":"${agent_meta_source}","qa_confidence":"unconfident","human_review":false,"timestamp":"<now>"}'
        if not.
      - If this product ALREADY had a qa_confidence:'unconfident', human_review:false row before
        this run (i.e. this is its one allowed retry): and you are STILL unconfident after
        redoing 2a-2c with full multimodal effort, write _meta =
        '{"source":"${agent_meta_source}","qa_confidence":"unconfident","human_review":true,"timestamp":"<now>"}'
        -- this is terminal, the product will not re-enter future worklists for this harness.
        If you ARE confident on this retry, write the confident shape as above.

STEP 3 -- Meilisearch write-back for newly-minted taxonomy entries. After STEP 2 finishes, some
products may have (a) required a brand-new \`${dict_table}\` entry (STEP 2c's NO branch) AND
(b) ended up recorded \`qa_confidence: "confident"\` in STEP 2d -- these are the ones worth making
searchable for future sessions. Every other product (re-points, filtered-out, unconfident) is
skipped -- never index an unconfident guess.
  1. Build one JSONL file of every qualifying product from this session, one line each --
     you already have these values from your own STEP 2 writes, no requery needed:
     {"product_id": "<product_id>", "sku_name": "<sku_name>", "sku_type_complete": "<value written to qa_table>", "brand": "<value written to qa_table>"}
     at /tmp/${tmp_tag}_new_entries.jsonl. If there are
     zero qualifying products, skip this step entirely -- do not run the command below with an
     empty or missing file.
  2. Run ONE batch call (never one call per product -- same rationale as STEP 1, model load
     dominates cost, not the embedding itself):
     ${PYTHON_BIN} ${REPO_ROOT}/script/non_niq/non_niq_helper.py index \\
       --input-file /tmp/${tmp_tag}_new_entries.jsonl \\
       --meili-index ${meili_index}
     Run this synchronously and wait for it to finish, same as every other tool call this session.

Hard rules, never relaxed:
- NEVER background any tool call (no async/background execution, of any command, at any step) and
  NEVER end your turn to wait for one to finish -- this is a single one-shot session with no way to
  resume and no notification will ever arrive. Always issue tool calls synchronously and wait for
  each one's real result before proceeding. Ending your turn before the full worklist is processed
  is not a valid outcome under any circumstance.
- Mapping table (product_id_dict / prior-engine table) is NEVER modified by this harness --
  corrections only ever land in \`${PROJECT}.${qa_table}\`.
- All writes use bq query DML, never the streaming API -- CLAUDE.md's 90-minute streaming-buffer
  rule. The very next run's retry-cap logic depends on reading back this run's QA rows reliably.
- Never write to \`qa_status\` on either source table. A separate QA-labelling update process reads
  \`${qa_table}\` independently and flips \`qa_status\` to 'Reviewed' once a product has a row there
  -- this harness's job is only to write \`${qa_table}\`/\`${dict_table}\`/\`${filter_table}\`,
  never \`qa_status\` itself.
- Every _meta read you do yourself (e.g. checking whether a product already has an unconfident
  row) must use JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.field'), never bare JSON_VALUE(_meta, ...)
  and never SAFE.JSON_VALUE(...) -- the latter LOOKS right but is not valid BigQuery syntax
  ("SAFE with function json_value is not supported"). Some existing _meta values are empty
  strings or the literal text "nan"; SAFE.PARSE_JSON returns NULL on those instead of raising, and
  JSON_VALUE on a NULL JSON value is itself safe.
- Every _meta WRITE must be a JSON string, never a bare string. Baseline format, used for every
  _meta write in this session unless a step above specifies a richer shape (2d's self-QA write
  adds qa_confidence/human_review on top of this same base):
    {"source":"${agent_meta_source}","timestamp":"<now, ISO 8601 UTC>"}
  e.g. {"source":"${agent_meta_source}","timestamp":"2026-08-16T19:19:06Z"}. A bare string like
  "${agent_meta_source}" (no braces/quotes-as-JSON) is NOT valid JSON -- SAFE.PARSE_JSON on it returns
  NULL, silently losing source/timestamp on every future read of that row.
- Attempt to resolve the ENTIRE worklist within your turn budget this session -- do not
  self-limit to a small sample. Stop early only when genuinely low on turns, and say so honestly
  in findings.

If you hit a genuine blocker -- something wrong with these instructions, missing data, anything
that would make proceeding unsafe -- stop and output status='blocked' with the blockers array
populated. That is a valid, expected outcome.

Output ONLY a valid JSON object when done, nothing else. Its status must be one of complete,
partial, failed, or blocked; its row counts must be integers; and findings/blockers must be arrays
of strings.
PROMPT
}

# Identical to non_niq_qa_v2.sh's -- detects claude -p's session-limit response, e.g.:
#   {"is_error":true,"num_turns":1,"api_error_status":429,"result":"You've hit your session limit
#    · resets 7:20pm (Asia/Jakarta)",...}
# Gated on api_error_status==429 AND num_turns<=1 ONLY -- a real session that hit turns of real
# BigQuery writes must NEVER be treated as "no work done" and retried, or the retry would re-run
# STEP 2's writes a second time.
is_claude_rate_limited() {
  local claude_output="$1"
  jq -e '.api_error_status == 429 and (.num_turns // 0) <= 1' <<< "$claude_output" >/dev/null 2>&1
}

# Identical to non_niq_qa_v2.sh's -- parses "resets 7:20pm (Asia/Jakarta)" out of claude's .result
# string into a unix epoch. Rolls forward to tomorrow if that clock time has already passed today.
parse_claude_reset_epoch() {
  local claude_output="$1" result time_str tz epoch now
  result=$(jq -r '.result // empty' <<< "$claude_output" 2>/dev/null) || return 1
  time_str=$(grep -oP 'resets \K\d{1,2}:\d{2}\s*[ap]m' <<< "$result" | head -1) || true
  [[ -z "$time_str" ]] && return 1
  tz=$(grep -oP '\(\K[A-Za-z_]+/[A-Za-z_]+(?=\))' <<< "$result" | head -1) || true
  epoch=$(TZ="${tz:-UTC}" date -d "$time_str" +%s 2>/dev/null) || return 1
  now=$(date +%s)
  if (( epoch <= now )); then
    epoch=$(TZ="${tz:-UTC}" date -d "$time_str tomorrow" +%s 2>/dev/null) || return 1
  fi
  echo "$epoch"
}

extract_json_object() {
  local text="$1"
  printf '%s' "$text" | grep -Pzo '(?s)\{.*\}' | tr -d '\0'
}

# Claude returns the requested final object in a JSON envelope's `.result`; Codex writes the
# schema-constrained final object directly via `--output-last-message`. Normalize both forms so
# all downstream queue logic has one result-object contract. Identical to non_niq_qa_v2.sh's.
extract_result_json() {
  local agent_output="$1" result_json extracted

  if echo "$agent_output" | jq -e 'type == "object" and has("status")' >/dev/null 2>&1; then
    echo "$agent_output"
    return
  fi

  result_json=$(echo "$agent_output" | jq -r '.result // empty' 2>/dev/null) || result_json=""
  if [[ -z "$result_json" ]]; then
    extracted=$(extract_json_object "$agent_output")
    if [[ -n "$extracted" ]] && echo "$extracted" | jq -e 'type == "object" and has("status")' >/dev/null 2>&1; then
      echo "$extracted"
    else
      echo ""
    fi
    return
  fi
  if ! echo "$result_json" | jq -e . >/dev/null 2>&1; then
    extracted=$(extract_json_object "$result_json")
    if [[ -n "$extracted" ]] && echo "$extracted" | jq -e . >/dev/null 2>&1; then
      result_json="$extracted"
    fi
  fi
  echo "$result_json"
}

extract_rows_created() {
  local claude_output="$1"
  local result_json
  result_json=$(extract_result_json "$claude_output")
  if [[ -z "$result_json" ]]; then
    echo "0"
    return
  fi
  echo "$result_json" | jq -r '.rows_created_in_dict // 0' 2>/dev/null || echo "0"
}

residual_counts_cover_worklist() {
  local result_json="$1" expected_count="$2"
  jq -e --argjson expected "$expected_count" '
    [.rows_qa_confirmed, .rows_qa_unconfident, .rows_filtered, .rows_unresolved] as $counts
    | ($counts | all(
        (type == "number") and (. >= 0) and (floor == .)
      ))
    and ($counts | add == $expected)
  ' <<< "$result_json" >/dev/null 2>&1
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

=== susubayi QA Session Result ===
Status: ${status}
Confirmed: ${rows_confirmed} | Unconfident: ${rows_unconfident} | Filtered: ${rows_filtered} | Created: ${rows_created}

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
  local platform="$1" country="${2:-ID}" max_turns="${3:-500}" max_rows="${4:-300}"
  country="${country^^}"

  local agent_harness="${AGENT_HARNESS:-claude}"
  log INFO "Agent harness requested: ${agent_harness}"

  log INFO "Resolving config Sheet row for ${DATASET}/${platform}/${country}..."
  local category_json
  category_json=$("$PYTHON_BIN" "$(dirname "$0")/non_niq_helper.py" categories --country "$country" \
    | jq -c --arg pl "$platform" '.[] | select(.dataset == "'"${DATASET}"'" and .ecommerce_platform == $pl)')
  if [[ -z "$category_json" ]]; then
    echo "No active config Sheet row for dataset=${DATASET} platform=${platform} country=${country}" >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "${DATASET}:${platform}" "FAILED" "No active config Sheet row for country=${country}"
    exit 1
  fi

  local source_table qa_table dict_table filter_table_config product_id_dict enrichment_table
  source_table=$(echo "$category_json" | jq -r '.master_table_prod')
  qa_table=$(echo "$category_json" | jq -r '.product_id_dict_qa')
  dict_table=$(echo "$category_json" | jq -r '.dict')
  filter_table_config=$(echo "$category_json" | jq -r '.filter_table')
  product_id_dict=$(echo "$category_json" | jq -r '.product_id_dict')
  enrichment_table=$(echo "$category_json" | jq -r '."0"')
  local filter_table
  filter_table=$(primary_filter_table "$filter_table_config" "$DATASET")
  log INFO "Config resolved: source_table=${source_table}, qa_table=${qa_table}, dict_table=${dict_table}, filter_table=${filter_table}"

  local t
  for t in "source_table=$source_table" "qa_table=$qa_table" "dict_table=$dict_table" "filter_table=$filter_table"; do
    if [[ "${t#*=}" == "-" || "${t#*=}" == "null" || -z "${t#*=}" ]]; then
      echo "Config Sheet row for dataset=${DATASET} platform=${platform} has unconfigured ${t%%=*} ('${t#*=}') -- cannot run susubayi QA." >&2
      echo "QUEUE_SIGNAL: FAILED"
      emit_result "${DATASET}:${platform}" "FAILED" "Unconfigured ${t%%=*} in config Sheet row"
      exit 1
    fi
  done

  log INFO "Resolving qa/dict column names via BigQuery INFORMATION_SCHEMA..."
  local columns_json qa_pk_col qa_platform_col dict_identity_col dict_typo_col
  columns_json=$("$PYTHON_BIN" "$(dirname "$0")/non_niq_helper.py" columns --project "$PROJECT" \
    --qa-table "$qa_table" --dict-table "$dict_table")
  qa_pk_col=$(echo "$columns_json" | jq -r '.qa_pk_col')
  qa_platform_col=$(echo "$columns_json" | jq -r '.qa_platform_col')
  dict_identity_col=$(echo "$columns_json" | jq -r '.dict_identity_col')
  dict_typo_col=$(echo "$columns_json" | jq -r '.dict_typo_col')
  log INFO "Columns resolved: qa_pk_col=${qa_pk_col}, dict_identity_col=${dict_identity_col}, dict_typo_col=${dict_typo_col}"

  log INFO "Querying BigQuery for the latest month on ${source_table}/${platform}..."
  local month
  if ! month=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "$(default_month_query "$source_table" "$platform")" | tail -1); then
    echo "bq query failed while resolving the latest month for ${source_table}/${platform} -- see bq's error above." >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "${DATASET}:${platform}" "FAILED" "bq query failed resolving latest month for ${source_table}/${platform}"
    exit 1
  fi
  log INFO "Latest month resolved: ${month}"

  # Merchant-allowlist Sheet lookup -- susubayi's config Sheet `category` is literally "Formula
  # Milk", the same string the Client OS Only / Competitor OS reference Sheet's Category Pipeline
  # column uses, so this force-includes exactly the merchants the user asked for regardless of GMV.
  local platform_titlecase="${platform^}"
  local category
  category=$(echo "$category_json" | jq -r '.category')
  log INFO "Checking merchant-allowlist Sheet for force-include merchant IDs (country=${country}, category=${category}, platform=${platform_titlecase})..."
  local forced_merchant_ids_json forced_merchant_ids_sql forced_merchant_count
  forced_merchant_ids_json=$("$PYTHON_BIN" "$(dirname "$0")/non_niq_helper.py" forced-merchants \
    --country "$country" --category "$category" --platform "$platform_titlecase") || forced_merchant_ids_json="[]"
  forced_merchant_ids_sql=$(echo "$forced_merchant_ids_json" | jq -r '[.[] | @json] | join(",")' 2>/dev/null) || forced_merchant_ids_sql=""
  forced_merchant_count=$(echo "$forced_merchant_ids_json" | jq 'length' 2>/dev/null) || forced_merchant_count=0
  log INFO "Force-include merchants resolved: ${forced_merchant_count}"

  local meili_index="${DATASET}_taxonomy_qa"
  local tmp_tag="${DATASET}_${platform}_${country}"

  local query
  query=$(worklist_query "$source_table" "$qa_table" "$qa_pk_col" "$month" "$platform" "$enrichment_table" "$max_rows" "$filter_table" "$forced_merchant_ids_sql" "$qa_platform_col")

  local scope_log="gmv_monthly>0 + Official Store + merchant allowlist"
  [[ "$platform_titlecase" == "Tokopedia" ]] && scope_log="Tier 1 + Official Store + merchant allowlist (GMV-independent)"
  log INFO "Querying BigQuery to materialize the worklist (${scope_log}, limit=${max_rows})..."
  local worklist_file="/tmp/${tmp_tag}_full_worklist.jsonl"
  if ! bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=json --max_rows=1000000 \
    "$query" | jq -c '.[]' > "$worklist_file"; then
    echo "bq query failed while materializing the worklist for ${DATASET}/${platform}/${country} -- see bq's error above." >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "${DATASET}:${platform}" "FAILED" "bq query failed materializing worklist for ${DATASET}/${platform}/${country}"
    exit 1
  fi

  local worklist_count
  worklist_count=$(wc -l < "$worklist_file" | tr -d ' ')

  if [[ "$worklist_count" == "0" ]]; then
    echo "No in-scope worklist for ${DATASET}/${platform}/${country}/${month} (${scope_log}) -- nothing to do."
    rm -f "$worklist_file"
    echo "QUEUE_SIGNAL: NOTHING_TO_DO"
    emit_result "${DATASET}:${platform}" "NOTHING_TO_DO" "No in-scope worklist for ${DATASET}/${platform}/${country}/${month}"
    exit 0
  fi

  log INFO "Worklist materialized: ${worklist_count} rows (${DATASET}/${platform}/${country}, month=${month})"
  local original_worklist_count="$worklist_count"

  local retrieval_file="/tmp/${tmp_tag}_worklist.jsonl"
  local candidates_file="/tmp/${tmp_tag}_candidates.jsonl"
  local residual_file="/tmp/${tmp_tag}_residual_worklist.jsonl"
  local auto_confirmation auto_confirmed
  jq -c '{id: (.product_id | tostring), product_id: (.product_id | tostring), ecommerce_platform: (.ecommerce_platform // ""), text: (.sku_name // "")}' "$worklist_file" > "$retrieval_file"
  if ! "$PYTHON_BIN" "$(dirname "$0")/non_niq_helper.py" retrieve \
    --input-file "$retrieval_file" --output-file "$candidates_file" \
    --meili-index "$meili_index" --meili-url "$MEILI_URL"; then
    echo "Meilisearch retrieval failed before automatic confirmation." >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "${DATASET}:${platform}" "FAILED" "Meilisearch retrieval failed"
    exit 1
  fi
  if ! auto_confirmation=$("$PYTHON_BIN" "$(dirname "$0")/non_niq_helper.py" auto-confirm \
    --input-file "$worklist_file" --candidates-file "$candidates_file" --residual-file "$residual_file" \
    --project "$PROJECT" --qa-table "$qa_table" --qa-pk-col "$qa_pk_col" \
    --qa-platform-col "$qa_platform_col" --dict-table "$dict_table" --identity-col "$dict_identity_col"); then
    echo "Automatic exact-title confirmation failed." >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "${DATASET}:${platform}" "FAILED" "Automatic exact-title confirmation failed"
    exit 1
  fi
  auto_confirmed=$(jq -r '.confirmed' <<< "$auto_confirmation")
  [[ "$auto_confirmed" =~ ^[0-9]+$ ]] || {
    echo "Automatic confirmation returned an invalid summary." >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "${DATASET}:${platform}" "FAILED" "Automatic confirmation returned an invalid summary"
    exit 1
  }
  worklist_file="$residual_file"
  worklist_count=$(wc -l < "$worklist_file" | tr -d ' ')
  if (( original_worklist_count != auto_confirmed + worklist_count )); then
    echo "Automatic confirmation accounting does not cover the original worklist." >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "${DATASET}:${platform}" "FAILED" "Automatic confirmation accounting mismatch"
    exit 1
  fi
  log INFO "Automatic exact-title confirmations: ${auto_confirmed}; agent residual: ${worklist_count}"
  if [[ "$worklist_count" == "0" ]]; then
    agent_output=$(jq -cn --argjson confirmed "$auto_confirmed" \
      '{status:"complete",rows_qa_confirmed:$confirmed,rows_qa_unconfident:0,rows_filtered:0,rows_created_in_dict:0,findings:["Confirmed by case-insensitive exact Meilisearch title match."],blockers:[]}')
    echo "$agent_output"
    format_result_summary "$agent_output"
    echo "QUEUE_SIGNAL: DONE"
    emit_result "${DATASET}:${platform}" "DONE" "susubayi QA session finished" "rows_created=0" "rows_auto_confirmed=$auto_confirmed"
    exit 0
  fi

  if ! require_harness "$agent_harness"; then
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "${DATASET}:${platform}" "FAILED" "AGENT_HARNESS='${agent_harness}' unavailable or unsupported"
    exit 1
  fi
  log INFO "Agent harness resolved for residual worklist: ${agent_harness}"

  local agent_meta_source
  case "$agent_harness" in
    claude) agent_meta_source="claude_code" ;;
    codex) agent_meta_source="codex" ;;
  esac

  local prompt
  prompt=$(build_qa_prompt "$platform" "$country" "$source_table" "$qa_table" "$dict_table" \
    "$filter_table" "$qa_pk_col" "$dict_identity_col" "$dict_typo_col" "$meili_index" "$worklist_file" \
    "$worklist_count" "$product_id_dict" "$tmp_tag" "$agent_meta_source")
  local run_start
  run_start=$(date -u '+%Y-%m-%dT%H:%M:%S')

  local agent_output=""
  if [[ "$agent_harness" == "codex" ]]; then
    # Identical adapter to non_niq_qa_v2.sh's -- see its main() comment for the full rationale
    # (--output-schema/--output-last-message for a structured result, network_access=true because
    # --approve-for-me's workspace-write sandbox blocks bq/curl/Meilisearch by default otherwise).
    local codex_final_file codex_stdout_file
    codex_final_file=$(mktemp "/tmp/${tmp_tag}_codex_final.XXXXXX")
    codex_stdout_file=$(mktemp "/tmp/${tmp_tag}_codex_stdout.XXXXXX")
    log INFO "Delegating to Codex -- uses automatic approval with workspace-write (network enabled); MAX_TURNS is a Claude-only CLI setting."
    codex exec --cd "$REPO_ROOT" --approve-for-me \
      -c sandbox_workspace_write.network_access=true \
      --output-schema "${REPO_ROOT}/script/non_niq/codex_qa_result_schema.json" \
      --output-last-message "$codex_final_file" "$prompt" > "$codex_stdout_file" || true
    if [[ -s "$codex_final_file" ]]; then
      agent_output=$(<"$codex_final_file")
    else
      agent_output=$(<"$codex_stdout_file")
    fi
  else
    # claude -p --output-format json buffers ALL of its output until the subprocess exits -- no
    # incremental progress from here until it returns. Logged explicitly so that gap reads as
    # "expected, still running" rather than "hung".
    log INFO "Delegating to claude (max_turns=${max_turns}) -- embeds+retrieves via Meilisearch, then runs the per-product QA loop. No further progress output until it returns."

    # Rate-limit retry: identical to non_niq_qa_v2.sh's -- capped at half LEASE_TIMEOUT_HOURS (default 2h) so a
    # sleep here can never outlast another worker's stale-lease reclaim window.
    local claude_output claude_attempt=1 max_claude_attempts=10
    local lease_safe_cap=$(( (${LEASE_TIMEOUT_HOURS:-2} * 3600) / 2 ))
    while :; do
      claude_output=$(claude -p --output-format json --permission-mode bypassPermissions --max-turns "$max_turns" "$prompt") || true
      is_claude_rate_limited "$claude_output" || break
      local wait_secs
      wait_secs=$(parse_claude_reset_epoch "$claude_output") && wait_secs=$(( wait_secs - $(date +%s) + 60 )) \
        || wait_secs=1800
      (( wait_secs < 60 )) && wait_secs=60
      if (( wait_secs > lease_safe_cap )); then
        log WARN "Claude session limit hit; reset is ${wait_secs}s away, longer than the safe lease window (${lease_safe_cap}s) -- exiting BLOCKED instead of sleeping through the task lease."
        echo "QUEUE_SIGNAL: BLOCKED"
        emit_result "${DATASET}:${platform}" "BLOCKED" "Claude session limit hit; reset further away than the safe lease window"
        exit 0
      fi
      claude_attempt=$((claude_attempt + 1))
      if (( claude_attempt > max_claude_attempts )); then
        log ERROR "Claude session limit hit again after ${max_claude_attempts} waits -- giving up."
        break
      fi
      log WARN "Claude session limit hit (attempt ${claude_attempt}/${max_claude_attempts}) -- sleeping ${wait_secs}s until reset."
      sleep "$wait_secs"
    done
    agent_output="$claude_output"
  fi
  # Unresolved rows alone are a normal, expected outcome (the agent's own status=partial already
  # maps to QUEUE_SIGNAL: DONE via decide_queue_signal -- see its case statement). The checks below
  # are a provenance/accounting AUDIT, never a gate: they append to findings and log loudly, but
  # deliberately never force status to "blocked" or skip the auto-confirmed merge below. A queue
  # BLOCKED signal stops queue_worker.sh's whole per-task iteration loop early (even when
  # iterations_run < loop_count) and parks the task -- far too disruptive a consequence for "this
  # audit query couldn't confirm something," which can itself be a false positive in the audit
  # query (see the 2026-09-30 lighting/ID incident on non_niq_qa_v2.sh's sibling check: a bug in
  # this exact insert-log query force-blocked an otherwise-clean 296-row session). The real DB
  # writes this run made already happened regardless of what these checks find.
  local result_json
  result_json=$(extract_result_json "$agent_output")
  if [[ -n "$result_json" ]] &&
    ! residual_counts_cover_worklist "$result_json" "$worklist_count"; then
    log ERROR "Agent result does not account for every residual row."
    # Merge onto the original agent_output (not result_json alone) -- for the Claude harness,
    # result_json is only the inner object extracted from claude_output.result and never carried
    # num_turns/duration_ms/total_cost_usd/modelUsage; rebuilding agent_output from result_json
    # alone silently dropped those envelope fields from the summary printed below.
    agent_output=$(jq -c --argjson result "$result_json" '
      . * ($result
        | .findings = ((.findings // []) + ["Post-run validation found incomplete residual row accounting; automatic totals may be incomplete."]))
    ' <<< "$agent_output")
  fi
  if [[ "$(extract_rows_created "$agent_output")" != "0" ]]; then
    # 2c.1 in the prompt is agent-trusted text, not code-enforced (unlike non_niq_qa_v3.py's
    # builder) -- apply_taxonomy_insert_log_backstop is the code-side backstop: any dict row that
    # appeared since run_start with no matching insert-log row means the agent skipped or failed
    # its mandatory log write. It only ever appends a finding (see its own doc comment) -- never
    # treat its return code as a reason to skip anything below.
    agent_output=$(apply_taxonomy_insert_log_backstop "$agent_output" \
      "\`${PROJECT}.${dict_table}\`" "${PROJECT}.${dict_table}" "$run_start" \
      "JSON_VALUE(log.row_json, '\$.inserted_row.brand') = cur.brand AND JSON_VALUE(log.row_json, '\$.inserted_row.${dict_identity_col}') = cur.\`${dict_identity_col}\`" \
      "$dict_table") || true
  fi
  if (( auto_confirmed > 0 )); then
    local auto_result_json
    auto_result_json=$(extract_result_json "$agent_output")
    if echo "$auto_result_json" | jq -e . >/dev/null 2>&1; then
      agent_output=$(jq -c --argjson confirmed "$auto_confirmed" \
        '.rows_qa_confirmed += $confirmed |
         .findings += ["Confirmed by case-insensitive exact Meilisearch title match."]' \
        <<< "$auto_result_json")
    fi
  fi
  log INFO "${agent_harness} subprocess returned, formatting summary..."
  echo "$agent_output"
  format_result_summary "$agent_output"

  local sheet_url rows_created new_entries_file
  sheet_url=$(echo "$category_json" | jq -r '.taxonomy_url')
  rows_created=$(extract_rows_created "$agent_output")
  new_entries_file="/tmp/${tmp_tag}_new_entries.jsonl"
  if [[ "$rows_created" != "0" && -s "$new_entries_file" ]]; then
    if [[ -n "$sheet_url" && "$sheet_url" != "-" && "$sheet_url" != "null" ]]; then
      log INFO "Appending ${rows_created} newly-created dict row(s) to the taxonomy Sheet..."
      "$PYTHON_BIN" "$(dirname "$0")/non_niq_helper.py" append-sheet \
        --input-file "$new_entries_file" --dict-table "$dict_table" --project "$PROJECT" \
        --dataset "$DATASET" --identity-col "$dict_identity_col" --sheet-url "$sheet_url" || true
    else
      log INFO "No taxonomy_url configured for ${DATASET} -- skipping Sheet write-back."
    fi
  fi

  local signal
  signal=$(decide_queue_signal "$agent_output")
  echo "QUEUE_SIGNAL: ${signal}"
  emit_result "${DATASET}:${platform}" "$signal" "susubayi QA session finished" "rows_created=$(extract_rows_created "$agent_output")" "rows_auto_confirmed=$auto_confirmed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
