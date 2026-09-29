#!/usr/bin/env bash
set -euo pipefail

# Usage: script/non_niq/eiger_qa.sh <PLATFORM> [COUNTRY] [MAX_TURNS] [MAX_ROWS]
# e.g.  script/non_niq/eiger_qa.sh shopee
#       script/non_niq/eiger_qa.sh tokopedia ID 300 300
#       AGENT_HARNESS=codex script/non_niq/eiger_qa.sh tokopedia
# AGENT_HARNESS defaults to claude; Codex uses attached image sheets and its own JSON adapter.
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
source "${REPO_ROOT}/script/non_niq/codex_sandbox_preflight.sh"

require_eiger_harness() {
  case "$1" in
    claude|codex) ;;
    *) echo "Unsupported AGENT_HARNESS='$1' for eiger QA (supported: claude, codex)." >&2; return 1 ;;
  esac
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "AGENT_HARNESS='$1' selected but '$1' is not on PATH." >&2
    return 1
  fi
}

# Codex needs a writable copy of the already-authenticated gcloud configuration and ADC.
# Keep credentials in a private per-run directory; never ask the agent to log in again.
prepare_eiger_codex_gcloud_runtime() {
  local runtime_dir="$1" source_config="${2:-}" adc_source="${3:-}"
  if [[ -z "$source_config" ]]; then
    source_config="${CLOUDSDK_CONFIG:-}"
  fi
  if [[ -z "$source_config" ]]; then
    command -v gcloud >/dev/null 2>&1 || { echo "gcloud is unavailable" >&2; return 1; }
    source_config=$(gcloud info --format='value(config.paths.global_config_dir)') || return 1
  fi
  if [[ ! -d "$source_config" || ! -r "$source_config/credentials.db" ]]; then
    echo "no readable active gcloud credential store at ${source_config}" >&2
    return 1
  fi
  mkdir -p -- "${runtime_dir}/gcloud"
  cp -aL -- "${source_config}/." "${runtime_dir}/gcloud/"
  chmod -R u+rwX,go-rwx -- "$runtime_dir"
  if [[ -z "$adc_source" ]]; then
    adc_source="${GOOGLE_APPLICATION_CREDENTIALS:-${source_config}/application_default_credentials.json}"
  fi
  if [[ ! -r "$adc_source" ]]; then
    echo "no readable Application Default Credential at ${adc_source}" >&2
    return 1
  fi
  cp -L -- "$adc_source" "${runtime_dir}/application_default_credentials.json"
  chmod 600 -- "${runtime_dir}/application_default_credentials.json"
  printf '%s\n%s\n' "${runtime_dir}/gcloud" "${runtime_dir}/application_default_credentials.json"
}

# Retry only a capacity error that occurred before any Codex tool event or final answer.
is_eiger_codex_startup_capacity_failure() {
  local stdout_file="$1" final_file="$2"
  [[ ! -s "$final_file" && -s "$stdout_file" ]] || return 1
  jq -se '
    def event_message: (.error.message // .message // .error // "") | tostring;
    length > 0
    and any(.[]; (.type == "error" or .type == "turn.failed")
      and (event_message | test("selected model is at capacity"; "i")))
    and all(.[]; .type == "thread.started" or .type == "turn.started"
      or .type == "error" or .type == "turn.failed")
  ' "$stdout_file" >/dev/null 2>&1
}

EIGER_CODEX_RUNTIME_DIR=""
EIGER_CODEX_IMAGE_DIR=""
cleanup_eiger_codex_runtime() {
  if [[ "${EIGER_CODEX_RUNTIME_DIR:-}" == /tmp/eiger_*_codex_gcloud.* ]]; then
    rm -rf -- "$EIGER_CODEX_RUNTIME_DIR"
  fi
  if [[ "${EIGER_CODEX_IMAGE_DIR:-}" == /tmp/eiger_*_image_sheets.* ]]; then
    rm -rf -- "$EIGER_CODEX_IMAGE_DIR"
  fi
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

# Scope: source-table rows awaiting review in product_tier IN ('Tier 1'), the precomputed
# top-90%-GMV population. This matches the Eiger handoff worklist's source filters while
# retaining the QA history safeguards below. Keep raw ecommerce platforms distinct during QA
# matching.
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
  SELECT s.product_id, s.sku_name, REPLACE(s.image, '"', '') AS image, s.url, s.ecommerce_platform,
         s.qa_status, s.gmv_monthly, s.brand, s.mgh_2, s.mgh_3, s.mgh_4, s.product_type,
         s.sku_type_complete, s.brand_store, ${enrichment_select}
  FROM \`${PROJECT}.${source_table}\` s
  ${enrichment_join}
  WHERE s.qa_status = 'Not Reviewed'
    AND s.product_tier IN ('Tier 1')
    AND FORMAT_DATE('%Y-%m', s.month) = '${month}'
    AND s.ecommerce_platform $(platform_match_clause "$platform_titlecase")
),
qa_title_state AS (
  SELECT DISTINCT product_id, ecommerce_platform,
    REGEXP_REPLACE(TRIM(sku_name), r'\s+', ' ') AS normalized_sku_name
  FROM \`${PROJECT}.${QA_TABLE}\`
  WHERE ecommerce_platform $(platform_match_clause "$platform_titlecase")
),
qa_state AS (
  -- Order-independent LOGICAL_OR flags over the WHOLE per-product history, same fan-out-bug fix
  -- non_niq_qa_v2.sh uses (project memory project_non_niq_qa_state_fanout_bug.md) -- QA_TABLE is
  -- insert-only, a raw un-deduped join would leak resolved products back into the worklist.
  SELECT
    product_id, ecommerce_platform,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.qa_confidence') = 'unconfident'
               AND COALESCE(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.human_review'), 'false') != 'true') AS has_unconfident_pending,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.qa_confidence') = 'confident') AS has_confident,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.human_review') = 'true') AS has_terminal
  FROM \`${PROJECT}.${QA_TABLE}\`
  WHERE ecommerce_platform $(platform_match_clause "$platform_titlecase")
  GROUP BY product_id, ecommerce_platform
),
filter_state AS (
  SELECT DISTINCT product_id FROM \`${PROJECT}.${filter_table}\`
),
prioritized AS (
  SELECT sc.product_id, sc.sku_name, sc.image, sc.url, sc.gmv_monthly, sc.ecommerce_platform,
         sc.item_description, sc.product_attributes_attrs, sc.brand, sc.mgh_2, sc.mgh_3,
         sc.mgh_4, sc.product_type, sc.sku_type_complete, sc.brand_store,
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
  local platform="$1" country="$2" source_table="$3" filter_table="$4" worklist_file="$5"
  local worklist_count="$6" tmp_tag="$7" agent_meta_source="${8:-claude_code}"
  local image_manifest_file="${9:-}"
  local image_inspection_instruction
  local ledger_instruction="For Codex, STEP 2a-2d are decision preparation only: defer every QA/filter INSERT until the complete ledger has been validated."
  ledger_instruction+=" Before ANY BigQuery DML, write one explicit JSONL decision per raw (product_id, ecommerce_platform, sku_name) identity at"
  ledger_instruction+=" /tmp/${tmp_tag}_eiger_decisions.jsonl. Each object must contain product_id, ecommerce_platform, sku_name,"
  ledger_instruction+=" decision (qa_confident|qa_unconfident|filtered|unresolved), image_observation, title_evidence, identity_rationale,"
  ledger_instruction+=" and intended_table_values (the exact QA/filter columns and values for writes; null for unresolved)."
  ledger_instruction+=" Match every worklist identity exactly once. Validate the ledger against the worklist and print the complete ledger"
  ledger_instruction+=" before executing bounded DML. An ambiguous taxonomy path or brand remains unresolved with no write;"
  ledger_instruction+=" never fill it with a heuristic or a guessed identity. Report rows_unresolved in the final JSON."
  ledger_instruction+=" Status complete requires zero unresolved rows and full worklist accounting."
  if [[ -z "$image_manifest_file" ]]; then
    ledger_instruction=$(sed 's/^For Codex,/For this session,/' <<< "$ledger_instruction")
  fi
  if [[ -n "$image_manifest_file" ]]; then
    image_inspection_instruction="The wrapper already downloaded and decoded the worklist images and attached
      labelled contact sheets to your initial Codex prompt with --image. Read the exact row-to-panel
      mapping and download status in ${image_manifest_file}. Inspect each product's attached panel
      directly before making a relevance, brand, or taxonomy judgment. Do not call the sandboxed
      image-viewing tool on local files: this host's image viewer can fail while configuring bwrap
      loopback even when the JPEG exists. If the manifest says failed or the panel cannot establish
      a needed detail, record that limitation and use the text-only unconfident path. Never claim
      visual evidence that you cannot read from the attached panel."
  else
    image_inspection_instruction="Download each image to a local file and open it with the Read tool:
        curl -sSL --max-time 30 \"<image_url>\" -o /tmp/${tmp_tag}_<product_id>.jpg
        (then: Read /tmp/${tmp_tag}_<product_id>.jpg)
      Do this BEFORE making any relevance / brand / category judgment for the product. If the
      download fails or the file is not a readable image, state this for the product and treat
      it as TEXT-ONLY -- grounds to mark it unconfident in 2d."
  fi

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
line has: product_id, sku_name, image, url, gmv_monthly, ecommerce_platform, item_description,
product_attributes_attrs, brand, mgh_2, mgh_3, mgh_4, product_type, sku_type_complete,
brand_store, priority. The brand/mgh_2/mgh_3/mgh_4/product_type/sku_type_complete/brand_store
fields are this product's EXISTING values on the source table (from a prior/legacy labelling
pass) -- a starting hypothesis to verify against the image and the guidance doc in STEP 2, not
a ground truth to copy blindly. It is already scoped to product_tier IN ('Tier 1') and prioritized
(unreviewed rows before agent-flagged-unconfident retry rows, both by gmv_monthly descending) --
process it in that order. If you cannot account for all ${worklist_count} rows by the end of
your turn budget, explicitly report status: partial (or status: blocked if you cannot proceed at
all) -- never silently process a subset and report status: complete.

STEP 1 -- The wrapper already ran one batch Meilisearch retrieval and directly confirmed the
unambiguous case-insensitive exact-title matches whose full Eiger taxonomy tuple agreed. The
remaining worklist contains only products that did not qualify for that trusted fast path. Do NOT
run retrieval yourself.

Read /tmp/${tmp_tag}_candidates.jsonl when evaluating each remaining product:
{"id": "<product_id>", "product_id": "<product_id>", "ecommerce_platform": "<raw platform>",
 "candidates": [{"product_id","sku_name","brand","sku_type_complete",
 "mgh_2","mgh_3","mgh_4","product_type"}, ...]}. Candidates are top hybrid-search exemplars from
${MEILI_INDEX}; look up a product by raw product_id/ecommerce_platform pair. Do not construct
another Meilisearch request.

STEP 2 -- For each product in the worklist, in order:

  2a. RELEVANCE + GUIDANCE ELIGIBILITY. A product is eligible only if it is Eiger-adjacent
      (outdoor equipment & supplies, apparel, gear, or footwear) AND its established identity
      fits at least one exact mgh_2/mgh_3/mgh_4/product_type row in ${GUIDANCE_CSV}. This is
      MULTIMODAL: actually LOOK at the product image, not just its URL. ${image_inspection_instruction}
      NO (including a confidently identified product with no matching guidance row) -> INSERT
             only (ecommerce, product_id, sku_name, _meta) into \`${PROJECT}.${filter_table}\`;
             use the worklist row's own \`ecommerce_platform\` verbatim as \`ecommerce\`, and put
             \`reason: "no_matching_guideline_rule"\` with source and UTC timestamp in the JSON
             \`_meta\`. Do NOT write to \`${QA_TABLE}\`; move on. The filter table has no
             \`ecommerce_platform\` or \`reason\` column.
      If the identity is too unclear to decide whether a guidance row applies, do not filter it;
      continue to 2b/2d and record it as unconfident instead.
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
          combinations -- if no more specific style clearly fits, use one of these catch-alls.
          They apply only after an exact four-level guidance path has been established; never use
          them to force a product with no matching guidance rule into QA.
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
        '{"source":"${agent_meta_source}","qa_confidence":"confident","timestamp":"<now, ISO 8601 UTC>"}'
        if confident, or
        '{"source":"${agent_meta_source}","qa_confidence":"unconfident","human_review":false,"timestamp":"<now>"}'
        if not.
      - If this product ALREADY had a qa_confidence:'unconfident', human_review:false row before
        this run (i.e. this is its one allowed retry, priority 1 in the worklist): and you are
        STILL unconfident after redoing 2a-2c with full multimodal effort, write _meta =
        '{"source":"${agent_meta_source}","qa_confidence":"unconfident","human_review":true,"timestamp":"<now>"}'
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
    {"source":"${agent_meta_source}","timestamp":"<now, ISO 8601 UTC>"}
  e.g. {"source":"${agent_meta_source}","timestamp":"2026-09-02T19:19:06Z"}.
- Attempt to resolve the ENTIRE worklist within your turn budget this session -- do not
  self-limit to a small sample. Stop early only when genuinely low on turns, and say so honestly
  in findings.

If you hit a genuine blocker -- something wrong with these instructions, missing data, anything
that would make proceeding unsafe -- stop and output status='blocked' with the blockers array
populated. That is a valid, expected outcome.

${ledger_instruction}

Output ONLY this JSON when done, nothing else (rows_created_in_dict here means "rows this
session newly indexed into Meilisearch in STEP 3" -- eiger has no separate dict-table insert
event to count):
{status: complete|partial|failed|blocked, rows_qa_confirmed, rows_qa_unconfident, rows_filtered, rows_created_in_dict, rows_unresolved, findings, blockers}.
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
  if echo "$claude_output" | jq -e 'type == "object" and has("status")' >/dev/null 2>&1; then
    echo "$claude_output"
    return
  fi
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
  # Preserve unresolved counts in the result, but do not hold a completed queue
  # batch open solely because a product requires follow-up.
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

  local status rows_confirmed rows_unconfident rows_filtered rows_created rows_unresolved findings blockers
  if [[ -z "$result_json" ]]; then
    status="unknown"
    rows_confirmed="?"
    rows_unconfident="?"
    rows_filtered="?"
    rows_created="?"
    rows_unresolved="?"
    findings="(unparseable)"
    blockers="(unparseable)"
  else
    status=$(echo "$result_json" | jq -r '.status // "unknown"' 2>/dev/null) || status="unknown"
    rows_confirmed=$(echo "$result_json" | jq -r '.rows_qa_confirmed // "?"' 2>/dev/null) || rows_confirmed="?"
    rows_unconfident=$(echo "$result_json" | jq -r '.rows_qa_unconfident // "?"' 2>/dev/null) || rows_unconfident="?"
    rows_filtered=$(echo "$result_json" | jq -r '.rows_filtered // "?"' 2>/dev/null) || rows_filtered="?"
    rows_created=$(echo "$result_json" | jq -r '.rows_created_in_dict // "?"' 2>/dev/null) || rows_created="?"
    rows_unresolved=$(echo "$result_json" | jq -r '.rows_unresolved // 0' 2>/dev/null) || rows_unresolved="?"
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
Confirmed: ${rows_confirmed} | Unconfident: ${rows_unconfident} | Filtered: ${rows_filtered} | Indexed: ${rows_created} | Unresolved: ${rows_unresolved}

Turns used: ${num_turns} | Duration: ${duration_ms}ms | Total cost: \$${total_cost}

Per-model cost:
${per_model}

Findings:
${findings}

Blockers:
${blockers}
SUMMARY
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

residual_ledger_covers_worklist() {
  local worklist_file="$1" decisions_file="$2"
  [[ -s "$decisions_file" ]] || return 1
  jq -e -s 'all(.[];
    (.product_id | type) == "string" and
    (.ecommerce_platform | type) == "string" and
    (.sku_name | type) == "string" and
    (.image_observation | type) == "string" and
    (.title_evidence | type) == "string" and
    (.identity_rationale | type) == "string" and
    (.decision == "qa_confident" or .decision == "qa_unconfident" or
     .decision == "filtered" or .decision == "unresolved") and
    (if .decision == "unresolved" then .intended_table_values == null
     else (.intended_table_values | type) == "object" end)
  )' "$decisions_file" >/dev/null 2>&1 || return 1
  diff -q \
    <(jq -c '[ (.product_id | tostring), (.ecommerce_platform // ""), (.sku_name // "") ]' "$worklist_file" | sort) \
    <(jq -c '[ (.product_id | tostring), (.ecommerce_platform // ""), (.sku_name // "") ]' "$decisions_file" | sort) >/dev/null
}

main() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <PLATFORM> [COUNTRY] [MAX_TURNS] [MAX_ROWS]" >&2
    exit 1
  fi
  local platform="$1" country="${2:-ID}" max_turns="${3:-300}" max_rows="${4:-300}"
  country="${country^^}"
  local agent_harness="${AGENT_HARNESS:-claude}"
  trap cleanup_eiger_codex_runtime EXIT

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

  log INFO "Querying BigQuery to materialize the worklist (product_tier=Tier 1 + limit=${max_rows})..."
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
  local original_worklist_count="$worklist_count"

  local retrieval_file="/tmp/${tmp_tag}_worklist.jsonl"
  local candidates_file="/tmp/${tmp_tag}_candidates.jsonl"
  local residual_file="/tmp/${tmp_tag}_residual_worklist.jsonl"
  local auto_confirmation auto_confirmed
  jq -c '{id: (.product_id | tostring), product_id: (.product_id | tostring), ecommerce_platform: (.ecommerce_platform // ""), text: (.sku_name // "")}' "$worklist_file" > "$retrieval_file"
  if ! "$PYTHON_BIN" "$(dirname "$0")/non_niq_helper.py" retrieve \
    --input-file "$retrieval_file" --output-file "$candidates_file" \
    --meili-index "$MEILI_INDEX" --meili-url "$MEILI_URL"; then
    echo "Meilisearch retrieval failed before automatic confirmation." >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "eiger:${platform}" "FAILED" "Meilisearch retrieval failed"
    exit 1
  fi
  if ! auto_confirmation=$("$PYTHON_BIN" "$(dirname "$0")/non_niq_helper.py" auto-confirm \
    --input-file "$worklist_file" --candidates-file "$candidates_file" --residual-file "$residual_file" \
    --project "$PROJECT" --qa-table "$QA_TABLE" --qa-pk-col product_id \
    --extra-identity-fields mgh_2,mgh_3,mgh_4,product_type); then
    echo "Automatic exact-title confirmation failed." >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "eiger:${platform}" "FAILED" "Automatic exact-title confirmation failed"
    exit 1
  fi
  auto_confirmed=$(jq -r '.confirmed' <<< "$auto_confirmation")
  [[ "$auto_confirmed" =~ ^[0-9]+$ ]] || {
    echo "Automatic confirmation returned an invalid summary." >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "eiger:${platform}" "FAILED" "Automatic confirmation returned an invalid summary"
    exit 1
  }
  worklist_file="$residual_file"
  worklist_count=$(wc -l < "$worklist_file" | tr -d ' ')
  if (( original_worklist_count != auto_confirmed + worklist_count )); then
    echo "Automatic confirmation accounting does not cover the original worklist." >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "eiger:${platform}" "FAILED" "Automatic confirmation accounting mismatch"
    exit 1
  fi
  log INFO "Automatic exact-title confirmations: ${auto_confirmed}; agent residual: ${worklist_count}"
  if [[ "$worklist_count" == "0" ]]; then
    agent_output=$(jq -cn --argjson confirmed "$auto_confirmed" \
      '{status:"complete",rows_qa_confirmed:$confirmed,rows_qa_unconfident:0,rows_filtered:0,rows_created_in_dict:0,rows_unresolved:0,findings:["Confirmed by case-insensitive exact Meilisearch title match."],blockers:[]}')
    echo "$agent_output"
    format_result_summary "$agent_output"
    echo "QUEUE_SIGNAL: DONE"
    emit_result "eiger:${platform}" "DONE" "eiger QA session finished" "rows_auto_confirmed=$auto_confirmed"
    exit 0
  fi

  if ! require_eiger_harness "$agent_harness"; then
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "eiger:${platform}" "FAILED" "AGENT_HARNESS='${agent_harness}' unavailable or unsupported"
    exit 1
  fi
  log INFO "Agent harness resolved for residual worklist: ${agent_harness}"
  if [[ "$agent_harness" == "codex" ]] && ! codex_sandbox_preflight; then
    echo "QUEUE_SIGNAL: BLOCKED"
    emit_result "eiger:${platform}" "BLOCKED" "Codex Linux sandbox failed preflight"
    exit 0
  fi

  local image_manifest_file="" image_summary="" agent_meta_source="claude_code"
  local -a codex_image_args=() codex_sheet_paths=()
  if [[ "$agent_harness" == "codex" ]]; then
    agent_meta_source="codex"
    EIGER_CODEX_IMAGE_DIR=$(mktemp -d "/tmp/${tmp_tag}_image_sheets.XXXXXX")
    if ! image_summary=$("$PYTHON_BIN" "${REPO_ROOT}/script/non_niq/prepare_codex_image_sheets.py" \
      --worklist "$worklist_file" --output-dir "$EIGER_CODEX_IMAGE_DIR"); then
      echo "Could not prepare readable image attachments for Codex." >&2
      echo "QUEUE_SIGNAL: FAILED"
      emit_result "eiger:${platform}" "FAILED" "Could not prepare image attachments for Codex"
      exit 1
    fi
    image_manifest_file=$(jq -r '.manifest' <<< "$image_summary")
    mapfile -t codex_sheet_paths < <(jq -r '.sheets[]' <<< "$image_summary")
    if [[ ! -s "$image_manifest_file" || "${#codex_sheet_paths[@]}" -eq 0 ]]; then
      echo "Image preparation returned no readable manifest or image sheets." >&2
      echo "QUEUE_SIGNAL: FAILED"
      emit_result "eiger:${platform}" "FAILED" "Incomplete Codex image attachments"
      exit 1
    fi
    for sheet_path in "${codex_sheet_paths[@]}"; do
      codex_image_args+=(--image "$sheet_path")
    done
    log INFO "Image attachments prepared: ${#codex_sheet_paths[@]} sheet(s), $(jq -r '.readable' <<< "$image_summary") readable, $(jq -r '.failed' <<< "$image_summary") unavailable."
  fi

  local prompt agent_output=""
  prompt=$(build_qa_prompt "$platform" "$country" "$source_table" "$filter_table" "$worklist_file" \
    "$worklist_count" "$tmp_tag" "$agent_meta_source" "$image_manifest_file")

  if [[ "$agent_harness" == "codex" ]]; then
    local codex_final_file codex_stdout_file codex_runtime_paths codex_gcloud_config codex_adc_file
    local codex_model="${CODEX_QA_MODEL:-gpt-5.6-sol}"
    local codex_reasoning_effort="${CODEX_QA_REASONING_EFFORT:-high}"
    case "$codex_reasoning_effort" in
      low|medium|high|xhigh|max) ;;
      *) echo "Unsupported CODEX_QA_REASONING_EFFORT: ${codex_reasoning_effort}" >&2; exit 1 ;;
    esac
    codex_final_file=$(mktemp "/tmp/${tmp_tag}_codex_final.XXXXXX")
    codex_stdout_file=$(mktemp "/tmp/${tmp_tag}_codex_stdout.XXXXXX")
    EIGER_CODEX_RUNTIME_DIR=$(mktemp -d "/tmp/${tmp_tag}_codex_gcloud.XXXXXX")
    chmod 700 -- "$EIGER_CODEX_RUNTIME_DIR"
    if ! codex_runtime_paths=$(prepare_eiger_codex_gcloud_runtime "$EIGER_CODEX_RUNTIME_DIR"); then
      echo "BigQuery credentials could not be prepared for the Codex sandbox." >&2
      echo "QUEUE_SIGNAL: FAILED"
      emit_result "eiger:${platform}" "FAILED" "Could not prepare authenticated BigQuery runtime for Codex"
      exit 1
    fi
    codex_gcloud_config=$(sed -n '1p' <<< "$codex_runtime_paths")
    codex_adc_file=$(sed -n '2p' <<< "$codex_runtime_paths")
    if [[ -z "$codex_gcloud_config" || -z "$codex_adc_file" ]]; then
      echo "BigQuery credential preparation returned an incomplete Codex runtime." >&2
      echo "QUEUE_SIGNAL: FAILED"
      emit_result "eiger:${platform}" "FAILED" "Incomplete BigQuery credential runtime for Codex"
      exit 1
    fi
    prompt+="

RUNTIME AUTHENTICATION (already prepared):
- CLOUDSDK_CONFIG and GOOGLE_APPLICATION_CREDENTIALS point to a writable, authenticated temporary
  runtime. Use bq and Python BigQuery normally.
- Do not run gcloud auth login, gcloud auth activate-service-account, or replace either variable.
- Do not copy, print, inspect, or persist credential files."
    local codex_attempt=1 codex_capacity_exhausted=false
    local max_codex_capacity_attempts="${CODEX_CAPACITY_MAX_ATTEMPTS:-4}"
    local codex_capacity_retry_delay="${CODEX_CAPACITY_RETRY_DELAY_SECONDS:-10}"
    [[ "$max_codex_capacity_attempts" =~ ^[1-9][0-9]*$ ]] || max_codex_capacity_attempts=4
    [[ "$codex_capacity_retry_delay" =~ ^[0-9]+$ ]] || codex_capacity_retry_delay=10
    (( max_codex_capacity_attempts > 10 )) && max_codex_capacity_attempts=10
    (( codex_capacity_retry_delay > 60 )) && codex_capacity_retry_delay=60
    log INFO "Delegating to Codex (${codex_model}, reasoning=${codex_reasoning_effort}) -- automatic approval with workspace-write (network enabled); MAX_TURNS is a Claude-only CLI setting."
    while :; do
      : > "$codex_final_file"
      : > "$codex_stdout_file"
      CLOUDSDK_CONFIG="$codex_gcloud_config" \
      GOOGLE_APPLICATION_CREDENTIALS="$codex_adc_file" \
      codex exec --cd "$REPO_ROOT" --approve-for-me --model "$codex_model" \
        -c "model_reasoning_effort=\"${codex_reasoning_effort}\"" \
        "${codex_image_args[@]}" --add-dir "$EIGER_CODEX_RUNTIME_DIR" \
        -c sandbox_workspace_write.network_access=true \
        -c 'shell_environment_policy.include_only=["PATH","HOME","TMPDIR","LANG","LC_ALL","CLOUDSDK_CONFIG","GOOGLE_APPLICATION_CREDENTIALS"]' \
        -c hide_agent_reasoning=true --json \
        --output-schema "${REPO_ROOT}/script/non_niq/codex_qa_result_schema.json" \
        --output-last-message "$codex_final_file" "$prompt" \
        | tee "$codex_stdout_file" \
        | jq --unbuffered -r '
            select(.type == "error" or .type == "turn.failed")
            | "Codex error: \(.error.message // .message // .error // "Unknown error")"
          ' >&2 || true
      if ! is_eiger_codex_startup_capacity_failure "$codex_stdout_file" "$codex_final_file"; then
        break
      fi
      if (( codex_attempt >= max_codex_capacity_attempts )); then
        codex_capacity_exhausted=true
        break
      fi
      log WARN "Codex was at capacity before any tool or agent work; retrying startup ($((codex_attempt + 1))/${max_codex_capacity_attempts})..."
      sleep "$codex_capacity_retry_delay"
      codex_attempt=$((codex_attempt + 1))
    done
    if [[ -s "$codex_final_file" ]]; then
      agent_output=$(<"$codex_final_file")
    elif [[ "$codex_capacity_exhausted" == "true" ]]; then
      agent_output='{"status":"failed","rows_qa_confirmed":0,"rows_qa_unconfident":0,"rows_filtered":0,"rows_created_in_dict":0,"rows_unresolved":0,"findings":[],"blockers":["Codex remained at capacity through all startup attempts; no agent work or production writes occurred."]}'
    else
      agent_output=$(jq -sr '[.[] | select(.type == "item.completed" and .item.type == "agent_message") | .item.text] | last // empty' "$codex_stdout_file") || true
    fi
  else
    log INFO "Delegating to claude (max_turns=${max_turns}) -- embeds+retrieves via Meilisearch, then runs the per-product QA loop. No further progress output until it returns."
    agent_output=$(claude -p --output-format json --permission-mode bypassPermissions --max-turns "$max_turns" "$prompt") || true
  fi
  log INFO "${agent_harness} subprocess returned, formatting summary..."
  local result_json residual_valid=true ledger_invalid=false
  result_json=$(extract_result_json "$agent_output")
  if ! residual_ledger_covers_worklist "$worklist_file" "/tmp/${tmp_tag}_eiger_decisions.jsonl"; then
    ledger_invalid=true
  fi
  if [[ -n "$result_json" ]] && {
    ! residual_counts_cover_worklist "$result_json" "$worklist_count" ||
    [[ "$ledger_invalid" == true ]];
  }; then
    residual_valid=false
    log ERROR "Agent result does not account for every residual row with a valid per-product evidence ledger."
    agent_output=$(jq -c '
      .status = "blocked" |
      .blockers = ((.blockers // []) + ["Post-run validation found incomplete residual row accounting or a missing/invalid per-product decision ledger; automatic totals were not merged."])
    ' <<< "$result_json")
  fi
  if (( auto_confirmed > 0 )) && [[ "$residual_valid" == true ]]; then
    local auto_result_json
    auto_result_json=$(extract_result_json "$agent_output")
    if echo "$auto_result_json" | jq -e . >/dev/null 2>&1; then
      agent_output=$(jq -c --argjson confirmed "$auto_confirmed" \
        '.rows_qa_confirmed += $confirmed |
         .findings += ["Confirmed by case-insensitive exact Meilisearch title match."]' \
        <<< "$auto_result_json")
    fi
  fi
  echo "$agent_output"
  format_result_summary "$agent_output"

  local signal
  signal=$(decide_queue_signal "$agent_output")
  echo "QUEUE_SIGNAL: ${signal}"
  emit_result "eiger:${platform}" "$signal" "eiger QA session finished" "rows_auto_confirmed=$auto_confirmed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
