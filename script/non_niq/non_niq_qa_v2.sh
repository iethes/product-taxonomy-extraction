#!/usr/bin/env bash
set -euo pipefail

# A QA run can stay alive for hours while another terminal/agent edits this shared checkout.
# Bash reads an executing script incrementally, so replacing the file mid-run can make the old
# process resume at a shifted byte offset and report a late syntax error after its DML completed.
# Execute direct invocations from an immutable per-run snapshot. Sourcing this file for tests still
# behaves normally and exposes the functions without re-execing.
if [[ "${BASH_SOURCE[0]}" == "${0}" && -z "${NON_NIQ_QA_V2_SNAPSHOT:-}" ]]; then
  NON_NIQ_QA_V2_ORIGINAL=$(readlink -f "${BASH_SOURCE[0]}")
  NON_NIQ_QA_V2_SNAPSHOT=$(mktemp "${TMPDIR:-/tmp}/non_niq_qa_v2_snapshot.XXXXXX.sh")
  cp -- "$NON_NIQ_QA_V2_ORIGINAL" "$NON_NIQ_QA_V2_SNAPSHOT"
  chmod 700 "$NON_NIQ_QA_V2_SNAPSHOT"
  export NON_NIQ_QA_V2_ORIGINAL NON_NIQ_QA_V2_SNAPSHOT
  exec bash "$NON_NIQ_QA_V2_SNAPSHOT" "$@"
fi
NON_NIQ_QA_V2_CODEX_RUNTIME_DIR=""
NON_NIQ_QA_V2_IMAGE_DIR=""
cleanup_non_niq_qa_v2_runtime() {
  if [[ -n "${NON_NIQ_QA_V2_SNAPSHOT:-}" ]]; then
    rm -f -- "$NON_NIQ_QA_V2_SNAPSHOT"
  fi
  if [[ "${NON_NIQ_QA_V2_CODEX_RUNTIME_DIR:-}" == /tmp/*_v2_codex_gcloud.* \
    && -d "$NON_NIQ_QA_V2_CODEX_RUNTIME_DIR" ]]; then
    rm -rf -- "$NON_NIQ_QA_V2_CODEX_RUNTIME_DIR"
  fi
  if [[ "${NON_NIQ_QA_V2_IMAGE_DIR:-}" == /tmp/*_v2_image_sheets.* \
    && -d "$NON_NIQ_QA_V2_IMAGE_DIR" ]]; then
    rm -rf -- "$NON_NIQ_QA_V2_IMAGE_DIR"
  fi
}
if [[ -n "${NON_NIQ_QA_V2_SNAPSHOT:-}" ]]; then
  trap cleanup_non_niq_qa_v2_runtime EXIT
fi

# Usage: script/non_niq/non_niq_qa_v2.sh <DATASET> <PLATFORM> [COUNTRY] [MAX_TURNS] [MAX_ROWS] [KATEGORI]
# e.g.  script/non_niq/non_niq_qa_v2.sh cookiesbiscuit shopee
#       script/non_niq/non_niq_qa_v2.sh lighting shopee TH
#       script/non_niq/non_niq_qa_v2.sh cookiesbiscuit shopee ID 500 400
#       script/non_niq/non_niq_qa_v2.sh lighting shopee ID 300 300 "Connected Light"
#       MONTHLY_REVERIFY=1 script/non_niq/non_niq_qa_v2.sh lighting shopee ID 300 100
#
# KATEGORI, if given, adds an exact-match filter on source_table's own `kategori` column (a
# per-category sub-scope some master_table_prod tables carry, e.g. lighting's "Connected Light")
# before the source-table product_tier filter -- optional because most datasets don't have
# this column at all.
#
# MONTHLY_REVERIFY=1 env var (optional, off by default): forces re-review of a product_id even if
# it already has a lifetime-confident QA row, whenever that product_id's sku_name/kategori differs
# from its most recent prior month's row on source_table -- i.e. the merchant swapped the listing
# under the same product_id (the reason this whole QA process has to run monthly, not once). Off by
# default so every other dataset's query is byte-identical to before. See worklist_query()'s
# listing_changed logic.
#
# AGENT_HARNESS env var (optional, defaults to "claude"): which coding-agent CLI drives the
# build_qa_prompt() session. Checked for availability (via `command -v`) before any BigQuery work
# starts -- an unavailable or unsupported harness fails fast with QUEUE_SIGNAL: FAILED rather than
# burning a worklist query first.
#       AGENT_HARNESS=codex script/non_niq/non_niq_qa_v2.sh cookiesbiscuit shopee
# Claude and Codex have separate adapters in main(): Claude returns its JSON envelope on stdout;
# Codex writes its schema-constrained final message to --output-last-message. Do not funnel a new
# harness through either adapter without implementing its own invocation and output contract.
# Codex progress/thinking events are captured in /tmp instead of printed; only errors and the
# final result are shown alongside this wrapper's phase/status messages.
#
# v2 reads the Sheet's `master_table_prod` (AC, no "_dev" suffix), which is a genuinely distinct
# table with its own qa_status column. Its normal worklist scope uses the source table's Tier 1 +
# Tier 2 product_tier values (the precomputed top-90%-GMV population), then requires an exact
# product_id + raw ecommerce_platform + whitespace-normalized sku_name QA match. Product-ID-only
# history is retained solely for the pending-unconfident retry safety loop. Neither script writes
# qa_status -- a separate external QA-labelling update process owns it.
# Client OS Only and Competitor OS merchant IDs bypass the GMV rank restriction; filter-table
# exclusions and current-title QA checks still apply.
# See docs/superpowers/specs/2026-08-06-non-niq-agentic-qa-design.md for the shared design this
# still implements (decision tree, confidence loop, _meta stamping).

PROJECT="sincere-hearth-273704"
MEILI_URL="http://34.124.146.29:7700"

# Resolves regardless of cwd -- non_niq_helper.py needs google-cloud-bigquery and
# sentence-transformers for real (columns/retrieve), so this must be an interpreter that actually
# has them: this repo's own uv-managed .venv, not bare `python3` off PATH.
SCRIPT_SOURCE="${NON_NIQ_QA_V2_ORIGINAL:-${BASH_SOURCE[0]}}"
REPO_ROOT="$(cd "$(dirname "$SCRIPT_SOURCE")/../.." && pwd)"
PYTHON_BIN="${REPO_ROOT}/.venv/bin/python3"

# One line per phase transition -- enough to tell (from outside) whether the script is still
# resolving config, waiting on a bq query, or has handed off to the claude subprocess, without
# spamming a line per row/product (that's claude's own transcript, not this wrapper's job). Now
# the shared log() (level + full timestamp, always stderr) instead of a local HH:MM:SS-only copy.
source "${REPO_ROOT}/script/lib/common.sh"
source "${REPO_ROOT}/script/non_niq/codex_sandbox_preflight.sh"

# Confirmed live: BigQuery's ecommerce_platform has a distinct 'Tokopedia | Shop' value
# (Tokopedia's own first-party channel) alongside plain 'Tokopedia', with NO separate config
# Sheet row. A 'tokopedia' run reads both raw values, but keeps them distinct for QA state and
# downstream writes: a review on one channel must never suppress the other channel's listing.
# Known harness name -> CLI binary. Claude and Codex have real adapters in main(); the remaining
# names let require_harness() distinguish "not installed" from "recognized but not wired yet".
declare -A HARNESS_BIN=(
  [claude]="claude"
  [codex]="codex"
  [pi]="pi"
  [omp]="omp"
  [opencode]="opencode"
)

# Fails fast immediately before agent work, after wrapper-side automatic confirmations have been
# considered. Returns 0 only for a harness this script can actually run.
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
  # MUST be scoped per-platform, not global -- v1 hit this exact bug (Blibli lagging other
  # platforms by a month on the _dev table). Confirmed live that on THIS table
  # (master_table_prod, no _dev) every cookiesbiscuit platform currently shares the same latest
  # month -- but that's a snapshot-in-time fact, not a guarantee, so this stays scoped per-platform
  # for the same reason v1's fix does.
  echo "SELECT FORMAT_DATE('%Y-%m', MAX(month)) FROM \`${PROJECT}.${source_table}\` WHERE ecommerce_platform $(platform_match_clause "$platform_titlecase")"
}

# Normal scope uses the source table's precomputed Tier 1 population (the top 90% GMV
# population). A product is normally covered only when product_id, raw ecommerce_platform, AND
# whitespace-normalized sku_name match a QA row; title changes under an existing product_id are
# therefore re-reviewed. The per-platform qa_state remains only for the pending-unconfident retry.
worklist_query() {
  local source_table="$1" qa_table="$2" qa_pk_col="$3" month="$4" platform="$5" enrichment_table="${6:-}"
  # Same LIMIT rationale as v1: a single agent session's turn budget can't process an unbounded
  # worklist. 100 is the safe default.
  local row_limit="${7:-100}"
  local filter_table="${8:-}"
  local kategori="${9:-}"
  local monthly_reverify="${10:-}"
  local forced_merchant_ids_sql="${11:-}"
  # Regional QA tables use `ecommerce`; most category QA tables use
  # `ecommerce_platform`. Resolve this from INFORMATION_SCHEMA in main() rather than baking one
  # schema into a cross-category query.
  local qa_platform_col="${12:-ecommerce_platform}"
  local dataset_name="${13:-}"
  local country="${14:-}"
  local platform_titlecase="${platform^}"
  # Null-image Tokopedia source rows retain the product page URL. Other source
  # schemas do not consistently expose this column, so do not reference it.
  local product_url_select="NULL AS product_url"
  if [[ "$platform_titlecase" == "Tokopedia" ]]; then
    product_url_select="s.url AS product_url"
  fi
  # item_description/product_attributes_attrs enrichment is Shopee-only by data availability --
  # ported VERBATIM from non_niq_qa.sh's worklist_query (v1), already debugged there (confirmed
  # live: non-Shopee 0_pipeline_* tables have a different schema with no description/specs
  # columns at all). dataset is derived from source_table (already "{dataset}.master_..." per
  # master_table_prod's own convention) rather than a separate parameter.
  local dataset="${source_table%%.*}"
  local enrichment_cte_and_join="" enrichment_join="" enrichment_select="NULL AS item_description, NULL AS product_attributes_attrs"
  if [[ "$platform_titlecase" == "Shopee" && -n "$enrichment_table" && "$enrichment_table" != "-" && "$enrichment_table" != "null" ]]; then
    # enrichment_table is a history table with multiple rows per item_itemid (confirmed live on
    # v1: ~108 rows per item avg). Dedupe to latest row per item before joining.
    # product_attributes_attrs is raw Shopee attribute JSON, projected down to a compact
    # "name=value; name=value" string -- same COALESCE-based Python-repr-vs-JSON fallback v1 uses
    # (confirmed live there: ~94% of populated rows are Python repr(), not valid JSON, so a bare
    # SAFE.PARSE_JSON alone would null out almost all real signal).
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

  # Exclude confirmed out-of-scope products. The config normally requires this table, but the
  # optional branch preserves the function's testable API.
  local filter_cte="" filter_join="" filter_where=""
  if [[ -n "$filter_table" && "$filter_table" != "-" && "$filter_table" != "null" ]]; then
    filter_cte="filter_state AS (
  SELECT DISTINCT product_id FROM \`${PROJECT}.${filter_table}\`
),
"
    filter_join="LEFT JOIN filter_state fs ON fs.product_id = sc.product_id"
    filter_where="WHERE fs.product_id IS NULL"
  fi

  local kategori_clause=""
  if [[ -n "$kategori" ]]; then
    kategori_clause="    AND s.kategori = '${kategori}'
"
  fi

  # Indonesia lighting QA is currently limited to the two in-scope brands. Keep this
  # dataset/country-specific so lighting runs for other markets retain their full scope.
  local brand_clause=""
  if [[ "$dataset_name" == "lighting" && "$country" == "ID" ]]; then
    log INFO "Filtering to Cahaya and Surya brand only"
    brand_clause="    AND s.brand IN ('Cahaya', 'Surya')
"
  fi

  # master_table_prod already assigns Tier 1 from the top-90%-GMV calculation. Do not
  # recalculate it here: a combined Tokopedia / Tokopedia | Shop GMV window would incorrectly
  # alter the two raw platform populations.
  local stakeholder_scope_clause="s.product_tier IN ('Tier 1')"
  if [[ -n "$forced_merchant_ids_sql" ]]; then
    stakeholder_scope_clause="(${stakeholder_scope_clause} OR s.merchant_id IN (${forced_merchant_ids_sql}))"
  fi

  # listing_changed remains an optional safety review for categories that explicitly opt in. The
  # normal title-mismatch path below already catches title changes relative to QA history.
  local scoped_kategori_select="" reverify_cte="" reverify_join=""
  local reverify_expr="FALSE" reverify_prior_select="NULL AS prior_sku_name, NULL AS prior_kategori"
  if [[ -n "$monthly_reverify" ]]; then
    scoped_kategori_select=", s.kategori AS current_kategori"
    reverify_cte="prior_snapshot AS (
  SELECT product_id, ecommerce_platform, sku_name AS prior_sku_name, kategori AS prior_kategori
  FROM \`${PROJECT}.${source_table}\`
  WHERE ecommerce_platform $(platform_match_clause "$platform_titlecase")
    AND FORMAT_DATE('%Y-%m', month) < '${month}'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id, ecommerce_platform ORDER BY month DESC) = 1
),
"
    reverify_join="LEFT JOIN prior_snapshot ps
    ON ps.product_id = sc.product_id
   AND ps.ecommerce_platform = sc.ecommerce_platform"
    # IS DISTINCT FROM, not != -- NULL-safe, so a prior/current value newly appearing or
    # disappearing (not just changing) still counts as a listing change.
    reverify_expr="(ps.product_id IS NOT NULL AND (ps.prior_sku_name IS DISTINCT FROM sc.sku_name OR ps.prior_kategori IS DISTINCT FROM sc.current_kategori))"
    reverify_prior_select="ps.prior_sku_name, ps.prior_kategori"
  fi

  cat <<SQL
WITH ${enrichment_cte_and_join}${filter_cte}scoped AS (
  SELECT s.product_id, s.sku_name, REPLACE(s.image, '"', '') AS image,
         ${product_url_select},
         s.ecommerce_platform,
         s.country, s.category, s.month, s.gmv_monthly, s.merchant_id,
         ${enrichment_select}${scoped_kategori_select}
  FROM \`${PROJECT}.${source_table}\` s
  ${enrichment_join}
  WHERE FORMAT_DATE('%Y-%m', s.month) = '${month}'
    AND s.ecommerce_platform $(platform_match_clause "$platform_titlecase")
    AND ${stakeholder_scope_clause}
${kategori_clause}${brand_clause}),
stakeholder_scope AS (
  SELECT sc.*
  FROM scoped sc
  ${filter_join}
  ${filter_where}
),
qa_title_state AS (
  SELECT DISTINCT ${qa_pk_col} AS product_id, ${qa_platform_col} AS ecommerce_platform,
    REGEXP_REPLACE(TRIM(sku_name), r'\\s+', ' ') AS normalized_sku_name
  FROM \`${PROJECT}.${qa_table}\`
  WHERE ${qa_platform_col} $(platform_match_clause "$platform_titlecase")
),
qa_state AS (
  -- product_id_dict_qa is INSERT-ONLY. Keep raw platforms distinct so a review on Tokopedia
  -- never suppresses the matching product/title on Tokopedia | Shop.
  SELECT
    ${qa_pk_col} AS product_id, ${qa_platform_col} AS ecommerce_platform,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.qa_confidence') = 'unconfident'
               AND COALESCE(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.human_review'), 'false') != 'true') AS has_unconfident_pending,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.qa_confidence') = 'confident') AS has_confident,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.human_review') = 'true') AS has_terminal
  FROM \`${PROJECT}.${qa_table}\`
  WHERE ${qa_platform_col} $(platform_match_clause "$platform_titlecase")
  GROUP BY 1, 2
),
${reverify_cte}prioritized AS (
  SELECT sc.product_id, sc.sku_name, sc.image, sc.product_url, sc.gmv_monthly, sc.ecommerce_platform, sc.merchant_id,
         sc.item_description, sc.product_attributes_attrs,
    ${reverify_expr} AS listing_changed, ${reverify_prior_select},
    CASE
      WHEN qts.product_id IS NULL THEN 0
      WHEN qs.has_unconfident_pending AND NOT qs.has_confident AND NOT qs.has_terminal THEN 1
      WHEN ${reverify_expr} THEN 0
      ELSE NULL
    END AS priority
  FROM stakeholder_scope sc
  LEFT JOIN qa_title_state qts
    ON qts.product_id = sc.product_id
   AND qts.ecommerce_platform = sc.ecommerce_platform
   AND qts.normalized_sku_name = REGEXP_REPLACE(TRIM(sc.sku_name), r'\\s+', ' ')
  LEFT JOIN qa_state qs
    ON qs.product_id = sc.product_id
   AND qs.ecommerce_platform = sc.ecommerce_platform
  ${reverify_join}
)
SELECT * FROM prioritized
WHERE priority IS NOT NULL
ORDER BY priority ASC, gmv_monthly DESC
LIMIT ${row_limit}
SQL
}

# Given the Sheet's raw filter_table cell (possibly ";"-separated, e.g. a category cross-
# referencing another category's filter table), returns the ONE table living in this row's own
# dataset -- the only one this harness ever writes to. Any other semicolon-separated entry is
# read-only reference and is intentionally not returned by this function. Identical to v1's.
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

build_qa_prompt() {
  local dataset="$1" platform="$2" country="$3" source_table="$4" qa_table="$5" dict_table="$6" filter_table="$7"
  local qa_pk_col="$8" dict_identity_col="$9" dict_typo_col="${10}" meili_index="${11}" worklist_file="${12}"
  local worklist_count="${13}" product_id_dict="${14}" tmp_tag="${15}" agent_meta_source="${16:-claude_code}"
  local dict_has_meta="${17:-false}"
  local image_manifest_file="${18:-}"

  # The QA table's identity column is `sku_type_complete` -- same resolution as v1.
  local qa_identity_col="sku_type_complete"

  # The dict and QA tables can legitimately use the same physical column name.  The old generic
  # warning interpolated dict_identity_col into "Never write ... to the QA table", which became
  # the self-contradictory "Never write sku_type_complete" for those categories.  Keep the strict
  # warning only when the physical names differ; otherwise explain that the shared name has a
  # separate role in each table.
  local identity_column_instruction
  if [[ "$dict_identity_col" == "$qa_identity_col" ]]; then
    identity_column_instruction="- Both tables intentionally name their identity column ${qa_identity_col}. Write
  ${qa_identity_col} to the QA table in every QA-table write, and use that same column name when
  reading/matching against or minting a row in the {dataset}_dict table. The identical column name
  is expected; the target table determines its role."
  else
    identity_column_instruction="- The QA table's identity column is ${qa_identity_col}. It is the same on every category and is
  what you write in every QA-table write below. Never write ${dict_identity_col} to the QA table.
- ${dict_identity_col} is the {dataset}_dict table's identity column, resolved live for this
  category. Use it ONLY when reading/matching against, or minting a new row in, the dict table."
  fi

  local dict_meta_instruction
  if [[ "$dict_has_meta" == "true" ]]; then
    dict_meta_instruction="Include the dict table's existing \`_meta\` column and stamp it with
                     the baseline source/timestamp JSON described in the _meta rule below."
  else
    dict_meta_instruction="The live schema resolution confirmed that this dict table has NO
                     \`_meta\` column. Do not include \`_meta\` in its INSERT, do not alter the
                     table schema, and do not block on the missing optional provenance column."
  fi

  local step2_block
  if [[ "$product_id_dict" == "-" || "$product_id_dict" == "null" || -z "$product_id_dict" ]]; then
    step2_block="  2b. SKIPPED for this category: product_id_dict is not configured (Sheet value '-'), so there is
      no prior mapping to check. Go straight to 2c for every product."
  else
    step2_block="  2b. Prior mapping check against \`${PROJECT}.${product_id_dict}\`. Its schema is NOT resolved for
      you and differs per category -- FIRST discover its real shape with
      \`SELECT * FROM \\\`${PROJECT}.${product_id_dict}\\\` LIMIT 1\` (or read its
      INFORMATION_SCHEMA.COLUMNS), then query it precisely for this product's row. Do NOT assume
      a column name. If a mapping row exists for this product: is that mapping CORRECT?
      YES -> select those SAME brand/${qa_identity_col} values for the decision ledger, then go to
             2d. Defer QA DML until the ledger is printed and self-QA is complete.
      NO, or no mapping row for this product -> continue to 2c."
  fi

  local image_inspection_instruction
  if [[ -n "$image_manifest_file" ]]; then
    image_inspection_instruction="The wrapper already downloaded and decoded the worklist images, and attached
      labelled contact sheets to your INITIAL Codex prompt with --image. The exact row-to-panel
      mapping and download status are in ${image_manifest_file} (JSONL). Each panel header says
      ROW <worklist row number> and product_id. Inspect that product's attached panel directly;
      write a concrete visual observation in its decision ledger. Do not call the sandboxed
      image-viewing/Read tool on a local image path: this host's bwrap image viewer fails while
      configuring loopback even when the JPEG exists. If the manifest says failed, or the panel
      is too small to establish a needed detail, record that limitation and use the text-only
      unconfident or unresolved path. Never claim a visual fact you cannot read from the panel."
  else
    image_inspection_instruction="For each product, download it to a local file and then open that
      file with the Read tool:
        curl -sSL --max-time 30 \"<image_url>\" -o /tmp/${tmp_tag}_v2_<product_id>.jpg
        (then: Read /tmp/${tmp_tag}_v2_<product_id>.jpg)
      Do this BEFORE making any relevance / brand / sku_type judgment for the product. Text-only
      reasoning on sku_name is exactly the failure mode this harness exists to fix -- do not skip
      the download and infer from the URL or the name.
      If the download fails, or the downloaded file is not a readable image (curl happily writes
      a 404 HTML body into a .jpg), say so explicitly in your reasoning for that product and
      treat it as TEXT-ONLY -- which is by itself grounds to mark it unconfident in 2d."
  fi

  cat <<PROMPT
Non-NIQ Agentic QA session (v2 -- current-title worklist) for dataset=${dataset},
platform=${platform}, country=${country}. See docs/superpowers/specs/2026-08-06-non-niq-agentic-qa-design.md for the
decision tree, confidence loop, and _meta conventions this still implements -- read it in full
before starting. The normal worklist filters confirmed out-of-scope products, then uses the source
table's precomputed Tier 1 product_tier values (the top-90%-GMV population). It includes
any current sku_name that has no matching QA row for the same product_id, raw ecommerce_platform,
and whitespace-normalized title. Client OS Only and Competitor OS merchants are included regardless
of tier or GMV, including zero-GMV products, but filter exclusions and the same QA checks still
apply. Pending-unconfident retries remain an explicit operational exception to that normal scope.

Resolved for this run: source_table=${PROJECT}.${source_table} (master_table_prod, NOT the _dev
table -- confirmed a separate table with its own qa_status column), qa_table=${PROJECT}.${qa_table},
dict_table=${PROJECT}.${dict_table}, filter_table (write target)=${PROJECT}.${filter_table},
qa_pk_col=${qa_pk_col}, dict_identity_col=${dict_identity_col}, dict_typo_col=${dict_typo_col},
dict_has_meta=${dict_has_meta},
product_id_dict (prior mapping table, read-only)=${product_id_dict},
meilisearch_index=${meili_index} (at ${MEILI_URL}).

Identity columns -- do not mix these up:
${identity_column_instruction}

STEP 0 -- The full worklist has ALREADY been materialized for you at
${worklist_file}, exactly ${worklist_count} rows, one JSON object per line (JSONL) -- do NOT query
BigQuery to re-fetch it, and do NOT trust any other row count than ${worklist_count}. Read the file
(in slices if it's too large for one Read) rather than querying BigQuery for it. Each line has:
product_id, sku_name, image, gmv_monthly, ecommerce_platform, merchant_id,
item_description, product_attributes_attrs, listing_changed, prior_sku_name, prior_kategori,
priority. It is already scoped to the post-filter source-table Tier 1 population
plus products from whitelisted Client OS Only and Competitor OS merchants regardless of GMV,
with a product considered reviewed only when its current whitespace-normalized sku_name matches a
QA row for the same product_id and raw ecommerce_platform. It is prioritized (current-title mismatches before
agent-flagged-unconfident retries, both by gmv_monthly descending) -- process it in that order. If you cannot account for all
${worklist_count} rows by the end of your turn budget, explicitly report status: partial (or
status: blocked if you cannot proceed at all) -- never silently process a subset and report
status: complete.

listing_changed is only ever true when this run has monthly re-verify enabled: it means this
product_id's sku_name or kategori differs from its own most recent PRIOR month's row on
source_table -- i.e. the merchant likely reused this product_id for a different listing since last
time (prior_sku_name/prior_kategori show what it WAS). Treat such a row as needing a completely
fresh judgment in 2a-2c -- do NOT assume any earlier confident QA verdict for this product_id still
applies, this may be a different product now. In 2d, write it using the FIRST-TIME _meta shape
(plain confident/unconfident) even if this product_id already has an older confident row -- a
listing swap is a new judgment, not a retry of a prior failure.

STEP 1 -- The wrapper already ran one batch Meilisearch retrieval and directly confirmed the
unambiguous case-insensitive exact-title matches. The remaining worklist contains only products
that did not qualify for that trusted fast path. Do NOT run retrieval yourself.

Read /tmp/${tmp_tag}_v2_candidates.jsonl when evaluating each remaining product:
{"id": "<product_id>", "product_id": "<product_id>", "ecommerce_platform": "<raw platform>",
 "candidates": [{"product_id","sku_name","brand","sku_type_complete"}, ...]}
Candidates are top hybrid-search exemplars from ${meili_index}; look up a product by its raw
product_id/ecommerce_platform pair. Do not construct another Meilisearch request.

STEP 2 -- For each product in the worklist, in order:

  Completion protocol for a large worklist:
  - Process rows in bounded chunks of at most 10 products. Use jq/Python to print only that
    chunk's compact product fields and candidates; never dump the entire worklist, candidate file,
    descriptions, or dictionary into the transcript. Large tool output wastes the context needed
    to finish later rows.
  - Before any write for a chunk, maintain exactly one CURRENT, individually authored JSON line
    per raw (product_id, ecommerce_platform, sku_name) identity in
    /tmp/${tmp_tag}_v2_decisions.jsonl. If you revise a decision, replace that
    row's line rather than appending a duplicate. Each object must contain product_id,
    ecommerce_platform, sku_name, image_panel, image_observation, title_evidence,
    description_evidence, prior_mapping, candidate_checked, dict_identity_checked,
    identity_rationale, decision, confidence, brand, sku_type_complete, and
    intended_table_values. decision must be qa_confident, qa_unconfident, filtered, or
    unresolved. Use null for inapplicable values; use an object for intended_table_values
    on writable decisions and null for unresolved decisions. Print
    that chunk's ledger lines in tool output BEFORE DML so the evidence is visible to automatic
    approval review; hidden reasoning or an unprinted file is not sufficient. Author decisions
    after inspecting each product, never generate the ledger or identity selection by token rules,
    string similarity, mass overrides, or invented labels.
  - Every new dictionary identity must be supported by that product's own image/text plus live
    sibling-row vocabulary. A generated-column pattern formats a validated identity; it does not
    validate which identity applies to a product.
  - Batch dictionary lookups for efficiency, but every DML statement may affect at most 10
    worklist products and at most 10 new dictionary identities. Use explicit values from the
    printed decision ledger. Never submit one combined DML statement for the whole worklist or
    generate a write payload from an unreviewed heuristic. Verify each small write before continuing.
  - Determine one honest disposition for every worklist row: QA confident, QA unconfident with a
    truthful existing identity, filtered with positive out-of-scope evidence, or unresolved. An
    unresolved row is one where image/text/candidates conflict or no real dictionary identity can
    be grounded. Record its product_id and reason in the ledger, make NO QA/dict/filter write for
    it, and continue with independent rows. Report rows_unresolved and status=partial at the end.
    Do not label an incorrect or invented identity as unconfident just to finish the worklist.
  - If automatic approval review rejects a write, do not retry the same outcome via smaller DML,
    another tool, or another account. Re-examine the underlying per-product decisions; proceed
    only with materially corrected, independently grounded rows. Leave the rejected rows
    unresolved when the evidence cannot support a safe correction.

  2a. RELEVANT to this category? This judgment is MULTIMODAL -- you must actually LOOK at the
      product image, not just read its URL. The image URL is the worklist's \`image\` column.
      ${image_inspection_instruction}
      Then, with the image + sku_name + item_description + product_attributes_attrs together (the
      worklist's own columns; product_attributes_attrs is a compact "name=value; name=value" string
      of the product's real Shopee attributes, e.g. brand/size -- not raw JSON;
      item_description/product_attributes_attrs are Shopee-only signal and NULL on other platforms
      -- treat NULL as simply having no extra signal, not as a problem) -- does this product
      genuinely belong in "${dataset}"?
      NO  -> FIRST read \`${PROJECT}.${filter_table}\`'s live schema. Its platform column is
             either \`ecommerce\` or \`ecommerce_platform\`; use whichever one actually exists and
             set it to the worklist row's \`ecommerce_platform\` value exactly as supplied. Plan to insert
             product_id and sku_name, plus merchant_id and _meta when those columns exist. Include
             reason only when the live table has a reason column. The live table schema is
             authoritative and supersedes any fixed filter schema in older design docs or prior
             instructions. A missing alternative platform column, reason, merchant_id, or _meta is
             not a blocker and must not trigger a schema change. This is the dataset's OWN filter
             table -- never write to a different dataset's
             filter table even if the Sheet cross-references one for read context. When _meta
             exists, stamp it as
             '{"source":"${agent_meta_source}","timestamp":"<now, ISO 8601 UTC>"}' (see the _meta format
             rule below). Print this product's evidence ledger before inserting the filter row;
             do NOT create a taxonomy entry. Move to the next product.
             Use the worklist row's raw \`ecommerce_platform\` value verbatim. \`Tokopedia\`
             and \`Tokopedia | Shop\` are distinct channels; do not collapse either value or
             reconstruct it from the Sheet's lowercase config value.
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
      YES -> select CORRECTED (re-pointed) brand/${qa_identity_col} values for the ledger and
             self-QA; defer QA DML until both are complete.
      NO  -> If the image/text and real sibling rows support one unambiguous new identity,
             proceed with the two-step create in \`${PROJECT}.${dict_table}\`. Otherwise mark
             this product unresolved and do not write a guessed dictionary or QA identity:
             Step A: FIRST resolve this category's generated-column pattern. Read
                     ${REPO_ROOT}/script/non_niq/dict_patterns/${dataset}.json.
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
                       ${REPO_ROOT}/script/non_niq/dict_patterns/${dataset}.json in the schema
                       above, so the next session for this dataset reads it instead of
                       re-inferring.
                     Prepare brand + ${dict_identity_col} + keywords (+ ${dict_typo_col} if you
                     have common misspellings) for the complete dict row; do not INSERT yet.
                     ${dict_meta_instruction}
             Step B: populate the remaining attribute columns for this dict's schema, GROUNDED on
                     existing dict rows' actual vocabulary and formatting -- query
                     \`SELECT DISTINCT <column> FROM ${PROJECT}.${dict_table}\` for authored
                     categorical values before writing them, prefer an existing value over
                     inventing one, and match existing formatting exactly (e.g. "150 ml" not
                     "150ml"). First inspect the live schema and representative sibling rows to
                     distinguish required identity/category fields from genuinely optional
                     attributes. Populate every value supported by the product signals, but leave
                     an optional attribute NULL when it is genuinely unknown and existing sibling
                     rows demonstrate that NULL is valid. Never invent a value merely to eliminate
                     NULL. After printing this product's complete ledger, INSERT the complete
                     dictionary row once, then verify the required brand, ${dict_identity_col},
                     keywords, generated-column sources, and every value you intended to write;
                     never trust bq's "affected rows" report alone.
             Create a new dictionary row only when its identity and required attributes are
             confident. Only after verifying that row, write brand/${qa_identity_col} values
             pointing at the new entry to \`${PROJECT}.${qa_table}\`.

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
      confident you are in the decision you just made for this product. Print the completed ledger
      before any QA or dictionary DML. If the selected identity is false or unsupported, mark the
      row unresolved and write nothing for it. Otherwise perform the planned write and stamp:
      - If this is the product's FIRST time being processed this session (no qa_confidence value
        existed for it before this run, OR this row's listing_changed is true -- see the
        listing_changed note in STEP 0, a listing swap under an old product_id is a fresh judgment,
        not a retry): write _meta =
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

STEP 3 -- Record all newly-minted dictionary rows, then write confident ones to Meilisearch.
  1. Build /tmp/${tmp_tag}_v2_created_dict_rows.jsonl with EVERY distinct new
     \`${dict_table}\` row minted this session. New dictionary identities require confident
     evidence and a confident QA decision. Use one line per
     distinct (brand, sku_type_complete) dictionary identity, not one line per mapped product:
     {"product_id": "<product_id>", "sku_name": "<sku_name>", "sku_type_complete": "<value written to qa_table>", "brand": "<value written to qa_table>"}
     This complete artifact is used by the wrapper's taxonomy-Sheet write-back; it must contain all
     newly-created dict rows, and its line count must equal
     rows_created_in_dict. If no rows were created, write no file (or an empty file).
  2. From that complete artifact, build /tmp/${tmp_tag}_v2_new_entries.jsonl containing only the
     newly-created products whose final qa_confidence is "confident". Re-points, filtered rows, and
     unconfident creations are excluded from this second file -- never index an unconfident guess.
     If there are zero confident new products, skip the index command entirely.
  3. Run ONE batch call (never one call per product -- same rationale as STEP 1, model load
     dominates cost, not the embedding itself):
     ${PYTHON_BIN} ${REPO_ROOT}/script/non_niq/non_niq_helper.py index \\
       --input-file /tmp/${tmp_tag}_v2_new_entries.jsonl \\
       --meili-index ${meili_index}
     Run this synchronously and wait for it to finish, same as every other tool call this session.

Hard rules, never relaxed:
- NEVER background any tool call (no async/background execution, of any command, at any step) and
  NEVER end your turn to wait for one to finish -- this is a single one-shot session with no way to
  resume and no notification will ever arrive. Always issue tool calls synchronously and wait for
  each one's real result before proceeding. Ending your turn before the full worklist is processed
  is not a valid outcome under any circumstance.
- Mapping table (any product_id_dict / prior-engine table) is NEVER modified by this harness --
  corrections only ever land in \`${PROJECT}.${qa_table}\`.
- All writes use bq query DML, never the streaming API -- CLAUDE.md's 90-minute streaming-buffer
  rule. The very next run's retry-cap logic depends on reading back this run's QA rows reliably.
- Never write to \`qa_status\` on the source table (master_table_prod). A separate QA-labelling
  update process reads \`${qa_table}\` independently and flips \`qa_status\` to 'Reviewed' once a
  product has a row there -- this harness's job is only to write
  \`${qa_table}\`/\`${dict_table}\`/\`${filter_table}\`, never \`qa_status\` itself.
- "This needs individual validation", "the remaining rows need grounded dictionary creation", or
  "a bulk heuristic was unsafe" are not reasons to fabricate a mapping. Continue the per-product
  decision tree. Use the unconfident QA path only when the chosen existing identity is still
  truthful; otherwise record an unresolved row and continue with independent products.
- Every _meta read you do yourself (e.g. checking whether a product already has an unconfident
  row) must use JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.field'), never bare JSON_VALUE(_meta, ...)
  and never SAFE.JSON_VALUE(...) -- the latter LOOKS right but is not valid BigQuery syntax
  ("SAFE with function json_value is not supported"). Some existing _meta values are empty
  strings or the literal text "nan"; SAFE.PARSE_JSON returns NULL on those instead of raising, and
  JSON_VALUE on a NULL JSON value is itself safe.
- Every _meta WRITE to a table that actually has an _meta column must be a JSON string, never a
  bare string. QA and filter tables have _meta; dict tables may not, as stated by dict_has_meta
  above. A missing optional dict _meta column is never a blocker and must not be added. Baseline
  format, used for every applicable _meta write unless a step above specifies a richer shape
  (2d's self-QA write adds qa_confidence/human_review on top of this same base):
    {"source":"${agent_meta_source}","timestamp":"<now, ISO 8601 UTC>"}
  e.g. {"source":"${agent_meta_source}","timestamp":"2026-08-16T19:19:06Z"}. A bare string like
  "${agent_meta_source}" (no braces/quotes-as-JSON) is NOT valid JSON -- SAFE.PARSE_JSON on it returns
  NULL, silently losing source/timestamp on every future read of that row.
- Attempt to resolve the ENTIRE worklist within your turn budget this session -- do not
  self-limit to a small sample. Stop early only when genuinely low on turns, and say so honestly
  in findings.

If you hit a global blocker -- something wrong with these instructions or an external failure
that makes the decision tree impossible for the worklist -- stop and output status='blocked' with
the blockers array populated. Isolated products with conflicting evidence are unresolved rows,
not a reason to stop evaluating independent products.

Output ONLY a valid JSON object when done, nothing else. Its status must be one of complete,
partial, failed, or blocked. It must have exactly these integer row-count fields, using these
exact names -- rows_qa_confirmed, rows_qa_unconfident, rows_filtered, rows_created_in_dict,
rows_unresolved -- and rows_qa_confirmed + rows_qa_unconfident + rows_filtered + rows_unresolved
must sum to exactly the number of worklist rows you were given. List unresolved product_ids in
findings; findings/blockers must be arrays of strings. status=complete requires all worklist rows
to be accounted for with zero unresolved rows.
PROMPT
}

# Detects claude -p's session-limit response, e.g.:
#   {"is_error":true,"num_turns":1,"api_error_status":429,"result":"You've hit your session limit
#    · resets 7:20pm (Asia/Jakarta)",...}
# Gated on api_error_status==429 AND num_turns<=1 ONLY -- never on a text/grep match anywhere in
# claude_output. claude_output is the full transcript blob; a real session that hit turns of real
# BigQuery writes and merely mentioned "429" or a connection error in its own findings must NEVER
# be treated as "no work done" and retried, or the retry would re-run STEP 2's writes a second
# time (the exact duplicate-write failure class documented across past sessions in memory). A
# 429 at num_turns<=1 fired before the prompt was ever acted on -- provably zero writes happened.
is_claude_rate_limited() {
  local claude_output="$1"
  jq -e '.api_error_status == 429 and (.num_turns // 0) <= 1' <<< "$claude_output" >/dev/null 2>&1
}

# Retry Codex only when its JSONL transcript proves the session failed at startup because the
# selected model was at capacity. A nonempty final message, a tool/item event, or malformed JSONL
# makes this return false: those cases may have produced side effects and must never be replayed.
is_codex_startup_capacity_failure() {
  local stdout_file="$1" final_file="$2"
  [[ ! -s "$final_file" && -s "$stdout_file" ]] || return 1
  jq -se '
    def event_message:
      (.error.message // .message // .error // "") | tostring;
    length > 0
    and any(.[];
      (.type == "error" or .type == "turn.failed")
      and (event_message | test("selected model is at capacity"; "i")))
    and all(.[];
      .type == "thread.started"
      or .type == "turn.started"
      or .type == "error"
      or .type == "turn.failed")
  ' "$stdout_file" >/dev/null 2>&1
}

# Codex's workspace-write sandbox can read the host gcloud configuration but cannot update it.
# `bq` then fails before doing any QA work because it tries to refresh tokens/write state. Clone
# the already-authenticated config into a per-run private directory and give the sandbox that
# directory as its writable CLOUDSDK_CONFIG. The copied ADC file is needed by Python BigQuery
# clients, which do not consult CLOUDSDK_CONFIG.
#
# Optional source arguments make this deterministic to test without touching host credentials.
prepare_codex_gcloud_runtime() {
  local runtime_dir="$1" source_config="${2:-}" adc_source="${3:-}"
  local gcloud_config_dir
  if [[ -z "$source_config" ]]; then
    source_config="${CLOUDSDK_CONFIG:-}"
  fi
  if [[ -z "$source_config" ]]; then
    command -v gcloud >/dev/null 2>&1 || {
      echo "gcloud is unavailable" >&2
      return 1
    }
    source_config=$(gcloud info --format='value(config.paths.global_config_dir)') || return 1
  fi
  if [[ ! -d "$source_config" || ! -r "$source_config/credentials.db" ]]; then
    echo "no readable active gcloud credential store at ${source_config}" >&2
    return 1
  fi

  gcloud_config_dir="${runtime_dir}/gcloud"
  mkdir -p -- "$gcloud_config_dir"
  cp -aL -- "${source_config}/." "$gcloud_config_dir/"
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
  printf '%s\n%s\n' "$gcloud_config_dir" "${runtime_dir}/application_default_credentials.json"
}

# Parses "resets 7:20pm (Asia/Jakarta)" out of claude's .result string into a unix epoch. Rolls
# forward to tomorrow if that clock time has already passed today (the reset is always in the
# future, never in the past). Echoes nothing and returns 1 if the string doesn't parse.
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
# all downstream queue logic has one result-object contract.
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
  # Unresolved products are explicitly reported for later review, but an otherwise
  # successful batch must release its queue lease rather than be retried forever.
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

=== QA Session Result (v2) ===
Status: ${status}
Confirmed: ${rows_confirmed} | Unconfident: ${rows_unconfident} | Filtered: ${rows_filtered} | Created: ${rows_created} | Unresolved: ${rows_unresolved}

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
  if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <DATASET> <PLATFORM> [COUNTRY] [MAX_TURNS] [MAX_ROWS] [KATEGORI]" >&2
    exit 1
  fi
  local dataset="$1" platform="$2" country="${3:-ID}" max_turns="${4:-500}" max_rows="${5:-100}" kategori="${6:-}"
  country="${country^^}"
  local monthly_reverify="${MONTHLY_REVERIFY:-}"
  [[ -n "$monthly_reverify" ]] && log INFO "MONTHLY_REVERIFY enabled -- worklist will force re-review of product_ids whose sku_name/kategori changed since their prior month's row."

  local agent_harness="${AGENT_HARNESS:-claude}"

  log INFO "Resolving config Sheet row for ${dataset}/${platform}/${country}..."
  local category_json
  category_json=$("$PYTHON_BIN" "$(dirname "$SCRIPT_SOURCE")/non_niq_helper.py" categories --country "$country" \
    | jq -c --arg ds "$dataset" --arg pl "$platform" '.[] | select(.dataset == $ds and .ecommerce_platform == $pl)')
  if [[ -z "$category_json" ]]; then
    echo "No active config Sheet row for dataset=${dataset} platform=${platform} country=${country}" >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "${dataset}:${platform}" "FAILED" "No active config Sheet row for country=${country}"
    exit 1
  fi

  # source_table here is master_table_prod (Sheet column AC, no "_dev" suffix) -- the ONLY
  # difference in table resolution vs v1, which uses `table` (AB). Everything else is identical.
  local source_table qa_table dict_table filter_table_config product_id_dict enrichment_table
  source_table=$(echo "$category_json" | jq -r '.master_table_prod')
  qa_table=$(echo "$category_json" | jq -r '.product_id_dict_qa')
  dict_table=$(echo "$category_json" | jq -r '.dict')
  filter_table_config=$(echo "$category_json" | jq -r '.filter_table')
  product_id_dict=$(echo "$category_json" | jq -r '.product_id_dict')
  enrichment_table=$(echo "$category_json" | jq -r '."0"')
  local filter_table
  filter_table=$(primary_filter_table "$filter_table_config" "$dataset")
  log INFO "Config resolved: source_table=${source_table}, qa_table=${qa_table}, dict_table=${dict_table}, filter_table=${filter_table}$( [[ -n "$kategori" ]] && echo ", kategori=${kategori}" )"

  # '-' is the Sheet's "not configured" marker -- fatal for every table this v2 harness reads or
  # writes (source_table now included, since v2's worklist depends entirely on it).
  local t
  for t in "source_table=$source_table" "qa_table=$qa_table" "dict_table=$dict_table" "filter_table=$filter_table"; do
    if [[ "${t#*=}" == "-" || "${t#*=}" == "null" || -z "${t#*=}" ]]; then
      echo "Config Sheet row for dataset=${dataset} platform=${platform} has unconfigured ${t%%=*} ('${t#*=}') -- cannot run QA v2." >&2
      echo "QUEUE_SIGNAL: FAILED"
      emit_result "${dataset}:${platform}" "FAILED" "Unconfigured ${t%%=*} in config Sheet row"
      exit 1
    fi
  done

  # Plain CLI args, not string-interpolated into a python -c source -- a table name can never
  # break out of anything, it's just an argv element.
  log INFO "Resolving qa/dict column names via BigQuery INFORMATION_SCHEMA..."
  local columns_json qa_pk_col qa_platform_col dict_identity_col dict_typo_col dict_has_meta
  columns_json=$("$PYTHON_BIN" "$(dirname "$SCRIPT_SOURCE")/non_niq_helper.py" columns --project "$PROJECT" \
    --qa-table "$qa_table" --dict-table "$dict_table")
  qa_pk_col=$(echo "$columns_json" | jq -r '.qa_pk_col')
  qa_platform_col=$(echo "$columns_json" | jq -r '.qa_platform_col')
  dict_identity_col=$(echo "$columns_json" | jq -r '.dict_identity_col')
  dict_typo_col=$(echo "$columns_json" | jq -r '.dict_typo_col')
  dict_has_meta=$(echo "$columns_json" | jq -r '.dict_has_meta')
  log INFO "Columns resolved: qa_pk_col=${qa_pk_col}, qa_platform_col=${qa_platform_col}, dict_identity_col=${dict_identity_col}, dict_typo_col=${dict_typo_col}, dict_has_meta=${dict_has_meta}"

  # Explicit failure checks, not bare `set -e` reliance -- same rationale as v1: a silent bq
  # failure inside a `var=$(...)` reassignment looks like a hang, not an error, under set -e alone.
  log INFO "Querying BigQuery for the latest month on ${source_table}/${platform}..."
  local month
  if ! month=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "$(default_month_query "$source_table" "$platform")" | tail -1); then
    echo "bq query failed while resolving the latest month for ${source_table}/${platform} -- see bq's error above." >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "${dataset}:${platform}" "FAILED" "bq query failed resolving latest month for ${source_table}/${platform}"
    exit 1
  fi
  log INFO "Latest month resolved: ${month}"

  # Match the reference Sheet's category label, not the dataset name. The helper handles
  # Tokopedia | Shop aliases. Lookup failures retain the existing non-fatal behavior.
  local platform_titlecase="${platform^}" category
  category=$(echo "$category_json" | jq -r '.category')
  log INFO "Checking merchant-allowlist Sheet (country=${country}, category=${category}, platform=${platform_titlecase})..."
  local forced_merchant_ids_json forced_merchant_ids_sql forced_merchant_count
  forced_merchant_ids_json=$("$PYTHON_BIN" "$(dirname "$SCRIPT_SOURCE")/non_niq_helper.py" forced-merchants \
    --country "$country" --category "$category" --platform "$platform_titlecase") || forced_merchant_ids_json="[]"
  forced_merchant_ids_sql=$(echo "$forced_merchant_ids_json" | jq -r '[.[] | @json] | join(",")') || forced_merchant_ids_sql=""
  forced_merchant_count=$(echo "$forced_merchant_ids_json" | jq 'length') || forced_merchant_count=0
  log INFO "Force-include merchants resolved: ${forced_merchant_count}"

  local meili_index="${dataset}_taxonomy_qa"

  # All of this run's /tmp scratch files are keyed off this tag. MUST include kategori when set --
  # without it, two concurrent kategori-sharded launches of the same dataset/platform/country (e.g.
  # lighting/shopee/ID kategori="LED Lamps" vs kategori="Luminaires") collide on the exact same
  # /tmp path and race-overwrite each other's worklist/candidates/new-entries files. Confirmed live:
  # a real run saw its worklist file's row count change mid-read (300 -> empty -> 215) from a
  # sibling shard's concurrent `bq query ... > "$worklist_file"` write. Sanitized because kategori
  # is free-text from the Sheet (e.g. "Connected Light" has a space).
  local tmp_tag="${dataset}_${platform}_${country}"
  if [[ -n "$kategori" ]]; then
    tmp_tag="${tmp_tag}_$(echo "$kategori" | tr -cs 'A-Za-z0-9' '_' | sed 's/^_//;s/_$//')"
  fi
  # STEP 3 artifacts have stable names so the agent and wrapper can agree on them. Remove leftovers
  # before this run; otherwise an agent that fails before producing its artifact could make the
  # wrapper append a previous run's identities.
  rm -f "/tmp/${tmp_tag}_v2_created_dict_rows.jsonl" "/tmp/${tmp_tag}_v2_new_entries.jsonl" \
    "/tmp/${tmp_tag}_v2_decisions.jsonl"

  local query
  query=$(worklist_query "$source_table" "$qa_table" "$qa_pk_col" "$month" "$platform" "$enrichment_table" "$max_rows" "$filter_table" "$kategori" "$monthly_reverify" "$forced_merchant_ids_sql" "$qa_platform_col" "$dataset" "$country")

  # Materialize the FULL worklist to a file for Claude to Read -- same rationale as v1: handing
  # Claude raw SQL to re-run risks output truncation on large worklists silently passing as
  # status: partial without unresolved rows -> QUEUE_SIGNAL: DONE; unresolved rows need review.
  # --max_rows=1000000 is NOT optional -- bq query silently
  # defaults to --max_rows=100 otherwise (v1 confirmed this live).
  log INFO "Querying BigQuery to materialize the worklist (post-filter Tier 1 + merchant whitelist, limit=${max_rows})..."
  local worklist_file="/tmp/${tmp_tag}_v2_full_worklist.jsonl"
  local worklist_json="/tmp/${tmp_tag}_v2_full_worklist.json"
  if ! bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=json --max_rows=1000000 \
    "$query" > "$worklist_json"; then
    # bq emits query errors on stdout in this environment. Surface that text directly instead of
    # piping it into jq and replacing the useful SQL error with "Invalid numeric literal".
    cat "$worklist_json" >&2
    rm -f "$worklist_json" "$worklist_file"
    echo "bq query failed while materializing the worklist for ${dataset}/${platform}/${country} (v2) -- see bq's error above." >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "${dataset}:${platform}" "FAILED" "bq query failed materializing worklist for ${dataset}/${platform}/${country}"
    exit 1
  fi
  if ! jq -c '.[]' "$worklist_json" > "$worklist_file"; then
    rm -f "$worklist_json" "$worklist_file"
    echo "bq returned non-JSON output while materializing the worklist for ${dataset}/${platform}/${country} (v2)." >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "${dataset}:${platform}" "FAILED" "bq returned invalid JSON materializing worklist for ${dataset}/${platform}/${country}"
    exit 1
  fi
  rm -f "$worklist_json"

  local worklist_count
  worklist_count=$(wc -l < "$worklist_file" | tr -d ' ')

  if [[ "$worklist_count" == "0" ]]; then
    echo "No in-scope worklist for ${dataset}/${platform}/${country}/${month} (v2, post-filter Tier 1 + merchant whitelist) -- nothing to do."
    rm -f "$worklist_file"
    echo "QUEUE_SIGNAL: NOTHING_TO_DO"
    emit_result "${dataset}:${platform}" "NOTHING_TO_DO" "No in-scope post-filter Tier 1 + merchant whitelist worklist for ${dataset}/${platform}/${country}/${month}"
    exit 0
  fi

  log INFO "Worklist materialized: ${worklist_count} rows (${dataset}/${platform}/${country}, month=${month})"
  local original_worklist_count="$worklist_count"

  local retrieval_file="/tmp/${tmp_tag}_v2_worklist.jsonl"
  local candidates_file="/tmp/${tmp_tag}_v2_candidates.jsonl"
  local residual_file="/tmp/${tmp_tag}_v2_residual_worklist.jsonl"
  local auto_confirmation auto_confirmed
  jq -c '{id: (.product_id | tostring), product_id: (.product_id | tostring), ecommerce_platform: (.ecommerce_platform // ""), text: (.sku_name // "")}' "$worklist_file" > "$retrieval_file"
  if ! "$PYTHON_BIN" "${REPO_ROOT}/script/non_niq/non_niq_helper.py" retrieve \
    --input-file "$retrieval_file" --output-file "$candidates_file" \
    --meili-index "$meili_index" --meili-url "$MEILI_URL"; then
    echo "Meilisearch retrieval failed before automatic confirmation." >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "${dataset}:${platform}" "FAILED" "Meilisearch retrieval failed"
    exit 1
  fi
  if ! auto_confirmation=$("$PYTHON_BIN" "${REPO_ROOT}/script/non_niq/non_niq_helper.py" auto-confirm \
    --input-file "$worklist_file" --candidates-file "$candidates_file" --residual-file "$residual_file" \
    --project "$PROJECT" --qa-table "$qa_table" --qa-pk-col "$qa_pk_col" \
    --qa-platform-col "$qa_platform_col" --dict-table "$dict_table" --identity-col "$dict_identity_col"); then
    echo "Automatic exact-title confirmation failed." >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "${dataset}:${platform}" "FAILED" "Automatic exact-title confirmation failed"
    exit 1
  fi
  auto_confirmed=$(jq -r '.confirmed' <<< "$auto_confirmation")
  [[ "$auto_confirmed" =~ ^[0-9]+$ ]] || {
    echo "Automatic confirmation returned an invalid summary." >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "${dataset}:${platform}" "FAILED" "Automatic confirmation returned an invalid summary"
    exit 1
  }
  worklist_file="$residual_file"
  worklist_count=$(wc -l < "$worklist_file" | tr -d ' ')
  if (( original_worklist_count != auto_confirmed + worklist_count )); then
    echo "Automatic confirmation accounting does not cover the original worklist." >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "${dataset}:${platform}" "FAILED" "Automatic confirmation accounting mismatch"
    exit 1
  fi
  log INFO "Automatic exact-title confirmations: ${auto_confirmed}; agent residual: ${worklist_count}"
  if [[ "$worklist_count" == "0" ]]; then
    agent_output=$(jq -cn --argjson confirmed "$auto_confirmed" \
      '{status:"complete",rows_qa_confirmed:$confirmed,rows_qa_unconfident:0,rows_filtered:0,rows_created_in_dict:0,rows_unresolved:0,findings:["Confirmed by case-insensitive exact Meilisearch title match."],blockers:[]}')
    echo "$agent_output"
    format_result_summary "$agent_output"
    echo "QUEUE_SIGNAL: DONE"
    emit_result "${dataset}:${platform}" "DONE" "QA v2 session finished" "rows_created=0" "rows_auto_confirmed=$auto_confirmed"
    exit 0
  fi

  if ! require_harness "$agent_harness"; then
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "${dataset}:${platform}" "FAILED" "AGENT_HARNESS='${agent_harness}' unavailable or unsupported"
    exit 1
  fi
  log INFO "Agent harness resolved for residual worklist: ${agent_harness}"
  if [[ "$agent_harness" == "codex" ]] && ! codex_sandbox_preflight; then
    echo "QUEUE_SIGNAL: BLOCKED"
    emit_result "${dataset}:${platform}" "BLOCKED" "Codex Linux sandbox failed preflight"
    exit 0
  fi

  local agent_meta_source
  case "$agent_harness" in
    claude) agent_meta_source="claude_code" ;;
    codex) agent_meta_source="codex" ;;
  esac

  local image_manifest_file="" image_summary="" codex_image_dir=""
  local -a codex_image_args=() codex_sheet_paths=()
  if [[ "$agent_harness" == "codex" ]]; then
    codex_image_dir=$(mktemp -d "/tmp/${tmp_tag}_v2_image_sheets.XXXXXX")
    NON_NIQ_QA_V2_IMAGE_DIR="$codex_image_dir"
    if ! image_summary=$("$PYTHON_BIN" "${REPO_ROOT}/script/non_niq/prepare_codex_image_sheets.py" \
      --worklist "$worklist_file" --output-dir "$codex_image_dir"); then
      echo "Could not prepare readable image attachments for Codex." >&2
      echo "QUEUE_SIGNAL: FAILED"
      emit_result "${dataset}:${platform}" "FAILED" "Could not prepare image attachments for Codex"
      exit 1
    fi
    image_manifest_file=$(jq -r '.manifest' <<< "$image_summary")
    mapfile -t codex_sheet_paths < <(jq -r '.sheets[]' <<< "$image_summary")
    if [[ ! -s "$image_manifest_file" || "${#codex_sheet_paths[@]}" -eq 0 ]]; then
      echo "Image preparation returned no readable manifest or image sheets." >&2
      echo "QUEUE_SIGNAL: FAILED"
      emit_result "${dataset}:${platform}" "FAILED" "Incomplete Codex image attachments"
      exit 1
    fi
    for sheet_path in "${codex_sheet_paths[@]}"; do
      codex_image_args+=(--image "$sheet_path")
    done
    log INFO "Image attachments prepared: ${#codex_sheet_paths[@]} sheet(s), $(jq -r '.readable' <<< "$image_summary") readable, $(jq -r '.failed' <<< "$image_summary") unavailable."
  fi

  local prompt
  prompt=$(build_qa_prompt "$dataset" "$platform" "$country" "$source_table" "$qa_table" "$dict_table" \
    "$filter_table" "$qa_pk_col" "$dict_identity_col" "$dict_typo_col" "$meili_index" "$worklist_file" \
    "$worklist_count" "$product_id_dict" "$tmp_tag" "$agent_meta_source" "$dict_has_meta" "$image_manifest_file")
  local run_start
  run_start=$(date -u '+%Y-%m-%dT%H:%M:%S')

  local agent_output=""
  if [[ "$agent_harness" == "codex" ]]; then
    # Codex's --output-last-message yields the final JSON object directly. Its --output-schema
    # makes that machine-readable contract explicit, rather than attempting to parse JSONL
    # progress events as though they were Claude's `.result` envelope.
    local codex_final_file codex_stdout_file codex_runtime_dir
    local codex_gcloud_config codex_adc_file
    local -a codex_runtime_paths
    codex_final_file=$(mktemp "/tmp/${tmp_tag}_v2_codex_final.XXXXXX")
    codex_stdout_file=$(mktemp "/tmp/${tmp_tag}_v2_codex_stdout.XXXXXX")
    codex_runtime_dir=$(mktemp -d "/tmp/${tmp_tag}_v2_codex_gcloud.XXXXXX")
    NON_NIQ_QA_V2_CODEX_RUNTIME_DIR="$codex_runtime_dir"
    chmod 700 -- "$codex_runtime_dir"
    if ! mapfile -t codex_runtime_paths < <(prepare_codex_gcloud_runtime "$codex_runtime_dir"); then
      rm -rf -- "$codex_runtime_dir"
      echo "BigQuery credentials could not be prepared for the Codex sandbox." >&2
      echo "QUEUE_SIGNAL: FAILED"
      emit_result "${dataset}:${platform}" "FAILED" "Could not prepare writable authenticated BigQuery runtime for Codex"
      exit 1
    fi
    codex_gcloud_config="${codex_runtime_paths[0]:-}"
    codex_adc_file="${codex_runtime_paths[1]:-}"
    if [[ -z "$codex_gcloud_config" || -z "$codex_adc_file" ]]; then
      rm -rf -- "$codex_runtime_dir"
      echo "BigQuery credential preparation returned an incomplete Codex runtime." >&2
      echo "QUEUE_SIGNAL: FAILED"
      emit_result "${dataset}:${platform}" "FAILED" "Incomplete BigQuery credential runtime for Codex"
      exit 1
    fi
    prompt+="

RUNTIME AUTHENTICATION (already prepared):
- CLOUDSDK_CONFIG and GOOGLE_APPLICATION_CREDENTIALS point to a writable, authenticated temporary
  runtime. Use bq and Python BigQuery normally.
- Do not run gcloud auth login, gcloud auth activate-service-account, or replace either variable.
- Do not copy, print, inspect, or persist credential files."
    # network_access=true is load-bearing -- workspace-write's sandbox blocks outbound network by
    # default regardless of --approve-for-me (confirmed against this Codex install's own docs:
    # ~/.codex/skills/.system/imagegen/references/codex-network.md -- an approval-bypass flag does
    # NOT itself enable network). Every step this prompt needs (bq query, curl image downloads,
    # Meilisearch HTTP calls) requires it; without this the session silently degrades every
    # product to the text-only/unconfident fallback instead of erroring loudly.
    local codex_attempt=1 codex_capacity_exhausted=false
    local codex_model="${CODEX_QA_MODEL:-gpt-5.6-sol}"
    local codex_reasoning_effort="${CODEX_QA_REASONING_EFFORT:-high}"
    case "$codex_reasoning_effort" in
      low|medium|high|xhigh|max) ;;
      *) echo "Unsupported CODEX_QA_REASONING_EFFORT: ${codex_reasoning_effort}" >&2; exit 1 ;;
    esac
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
        "${codex_image_args[@]}" --add-dir "$codex_runtime_dir" \
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
      if ! is_codex_startup_capacity_failure "$codex_stdout_file" "$codex_final_file"; then
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
      # JSONL progress is not a final result. Recover the last completed agent message if
      # Codex exited before writing --output-last-message; empty/malformed output fails below.
      agent_output=$(jq -sr '
        [.[] | select(.type == "item.completed" and .item.type == "agent_message")
         | .item.text] | last // empty
      ' "$codex_stdout_file") || true
    fi
    rm -rf -- "$codex_runtime_dir"
    NON_NIQ_QA_V2_CODEX_RUNTIME_DIR=""
    rm -rf -- "$codex_image_dir"
    NON_NIQ_QA_V2_IMAGE_DIR=""
  else
    # claude -p --output-format json buffers ALL of its output until the subprocess exits -- there is
  # no incremental progress from here until it returns, potentially several minutes for a large
  # worklist (it embeds+retrieves via Meilisearch, then works the per-product QA loop internally).
  # Logged explicitly so that gap reads as "expected, still running" rather than "hung".
  log INFO "Delegating to claude (max_turns=${max_turns}) -- embeds+retrieves via Meilisearch, then runs the per-product QA loop. No further progress output until it returns."

  # `|| true` is load-bearing under `set -e` -- same rationale as v1: a non-zero claude exit can
  # still follow real BigQuery writes, and dying here would swallow the transcript that says what
  # was written.
  #
  # Rate-limit retry: queue_worker.sh's heartbeat only fires ONCE per loop iteration, BEFORE this
  # subprocess starts (script/lib/queue_common.sh) -- there is no heartbeat while we sleep here.
  # Sleeping past LEASE_TIMEOUT_HOURS (default 4h, reclaim_stale_leases_query) would let another
  # worker reclaim this task mid-sleep and start a concurrent duplicate run on the same worklist --
  # the exact bug in project_non_niq_qa_concurrent_session_launch_gap.md. So the wait is capped at
  # half the lease window; a reset further out than that exits BLOCKED instead of sleeping through
  # the lease, so the task is safely reclaimed and retried later rather than raced.
  local claude_output claude_attempt=1 max_claude_attempts=10
  local lease_safe_cap=$(( (${LEASE_TIMEOUT_HOURS:-4} * 3600) / 2 ))
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
      emit_result "${dataset}:${platform}" "BLOCKED" "Claude session limit hit; reset further away than the safe lease window"
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
  log INFO "${agent_harness} subprocess returned, formatting summary..."
  local result_json residual_valid=true
  result_json=$(extract_result_json "$agent_output")
  if [[ -n "$result_json" ]] && {
    ! residual_counts_cover_worklist "$result_json" "$worklist_count" ||
    ! residual_ledger_covers_worklist "$worklist_file" "/tmp/${tmp_tag}_v2_decisions.jsonl";
  }; then
    residual_valid=false
    log ERROR "Agent result does not account for every residual row with a valid per-product evidence ledger."
    # Merge onto the original agent_output (not result_json alone) -- for the Claude harness,
    # result_json is only the inner object extracted from claude_output.result and never carried
    # num_turns/duration_ms/total_cost_usd/modelUsage; rebuilding agent_output from result_json
    # alone silently dropped those envelope fields from the summary printed below.
    agent_output=$(jq -c --argjson result "$result_json" '
      . * ($result
        | .status = "blocked"
        | .blockers = ((.blockers // []) + ["Post-run validation found incomplete residual row accounting or a missing/invalid per-product decision ledger; automatic totals were not merged."]))
    ' <<< "$agent_output")
  fi
  if [[ "$residual_valid" == true ]] && [[ "$(extract_rows_created "$agent_output")" != "0" ]]; then
    # 2c.1 in the prompt is agent-trusted text, not code-enforced (unlike non_niq_qa_v3.py's
    # builder) -- apply_taxonomy_insert_log_backstop is the code-side backstop: any dict row that
    # appeared since run_start with no matching insert-log row means the agent skipped or failed
    # its mandatory log write.
    if ! agent_output=$(apply_taxonomy_insert_log_backstop "$agent_output" \
      "\`${PROJECT}.${dict_table}\`" "${PROJECT}.${dict_table}" "$run_start" \
      "JSON_VALUE(log.row_json, '\$.inserted_row.brand') = cur.brand AND JSON_VALUE(log.row_json, '\$.inserted_row.${dict_identity_col}') = cur.\`${dict_identity_col}\`" \
      "$dict_table"); then
      residual_valid=false
    fi
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

  # Sheet write-back: bash-invoked (not an agent tool call), reading STEP 3's complete artifact of
  # newly-created dictionary identities. The separate Meilisearch artifact can omit unconfident
  # creations, so it must not drive Sheet synchronization. Non-fatal by design (`|| true`), same
  # contract the removed Discord notifier had: a Sheets/BigQuery hiccup here must never fail the QA
  # session or its QUEUE_SIGNAL.
  local sheet_url rows_created created_entries_file created_entries_count
  sheet_url=$(echo "$category_json" | jq -r '.taxonomy_url')
  rows_created=$(extract_rows_created "$agent_output")
  created_entries_file="/tmp/${tmp_tag}_v2_created_dict_rows.jsonl"
  created_entries_count=0
  [[ -s "$created_entries_file" ]] && created_entries_count=$(wc -l < "$created_entries_file" | tr -d ' ')
  if [[ "$rows_created" != "0" && "$created_entries_count" == "0" ]]; then
    log WARN "Agent reported ${rows_created} newly-created dict row(s) but did not produce ${created_entries_file}; skipping Sheet append rather than reusing the confidence-filtered Meilisearch artifact."
  fi
  if [[ "$created_entries_count" != "0" ]]; then
    if [[ -n "$sheet_url" && "$sheet_url" != "-" && "$sheet_url" != "null" ]]; then
      log INFO "Appending ${created_entries_count} newly-created dict row(s) to the taxonomy Sheet..."
      "$PYTHON_BIN" "$(dirname "$SCRIPT_SOURCE")/non_niq_helper.py" append-sheet \
        --input-file "$created_entries_file" --dict-table "$dict_table" --project "$PROJECT" \
        --dataset "$dataset" --identity-col "$dict_identity_col" --sheet-url "$sheet_url" || true
    else
      log INFO "No taxonomy_url configured for ${dataset} -- skipping Sheet write-back."
    fi
  fi

  local signal
  signal=$(decide_queue_signal "$agent_output")
  echo "QUEUE_SIGNAL: ${signal}"
  emit_result "${dataset}:${platform}" "$signal" "QA v2 session finished" "rows_created=$(extract_rows_created "$agent_output")" "rows_auto_confirmed=$auto_confirmed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
