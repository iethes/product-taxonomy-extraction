#!/usr/bin/env bash
set -euo pipefail

# Usage: script/non_niq/non_niq_qa_v2.sh <DATASET> <PLATFORM> [MAX_TURNS] [MAX_ROWS]
# e.g.  script/non_niq/non_niq_qa_v2.sh cookiesbiscuit shopee
#       script/non_niq/non_niq_qa_v2.sh cookiesbiscuit shopee 500 400
#
# v2 differs from non_niq_qa.sh (v1) in exactly one respect: how the worklist is SOURCED.
# v1 reads the Sheet's `table` (AB, "..._dev") column and computes top-90%-cumulative-GMV itself
# via a window function. v2 reads the Sheet's `master_table_prod` (AC, no "_dev" suffix) column
# and trusts that table's own precomputed `product_tier` column ('Tier 1' = in scope) instead of
# recomputing GMV ranking -- confirmed live this is a genuinely different table with its own
# qa_status column, not a view/alias of the _dev table. Everything downstream (decision tree,
# retry-once confidence loop, filter-table exclusion, result summary) is unchanged from v1 --
# only the worklist source differs. Neither script writes qa_status -- a separate external
# QA-labelling update process reads product_id_dict_qa and flips it independently.
# See docs/superpowers/specs/2026-08-06-non-niq-agentic-qa-design.md for the shared design this
# still implements (decision tree, confidence loop, _meta stamping).

PROJECT="sincere-hearth-273704"
MEILI_URL="http://34.124.146.29:7700"

# Resolves regardless of cwd -- non_niq_helper.py needs google-cloud-bigquery and
# sentence-transformers for real (columns/retrieve), so this must be an interpreter that actually
# has them: this repo's own uv-managed .venv, not bare `python3` off PATH.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PYTHON_BIN="${REPO_ROOT}/.venv/bin/python3"

# Confirmed live: BigQuery's ecommerce_platform has a distinct 'Tokopedia | Shop' value
# (Tokopedia's own first-party channel) alongside plain 'Tokopedia', with NO separate config
# Sheet row -- 'tokopedia' as a CLI platform arg is meant to cover both under the one Sheet row's
# config (same qa_table/dict_table/filter_table/master_table_prod). Shared by
# default_month_query() and worklist_query() so the two never drift out of sync on this.
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

# Scope: product_tier = 'Tier 1' (precomputed upstream on master_table_prod -- confirmed live,
# populated per platform, e.g. cookiesbiscuit/Shopee/2026-07: 5043 Tier 1 rows) INSTEAD OF v1's
# self-computed top-90%-cumulative-GMV window function. Explicit user decision: v2 trusts this
# table's own tiering rather than recomputing it. Priority tiers (0 = never QA'd, 1 = unconfident
# retry-eligible) and the filter_table exclusion are otherwise identical to v1's worklist_query --
# same qa_state/filter_state join shape, same confidence-loop semantics.
worklist_query() {
  local source_table="$1" qa_table="$2" qa_pk_col="$3" month="$4" platform="$5"
  # Same LIMIT rationale as v1: a single agent session's turn budget can't process an unbounded
  # worklist. 300 is the same safe default.
  local row_limit="${6:-300}"
  local filter_table="${7:-}"
  local platform_titlecase="${platform^}"
  # image carries the same live-observed embedded-double-quote artifact v1 found and fixed --
  # stripping here, once, rather than relying on the prompt to strip it per-product.
  #
  # filter_table exclusion: same rationale as v1 -- STEP 2a's NO branch writes ONLY to the filter
  # table, never to qa_table, so a product already confirmed out-of-scope must be excluded here
  # explicitly (qa_status alone can't be relied on for this -- this harness never writes it; a
  # separate external process owns that). SELECT DISTINCT absorbs filter_table's own known
  # duplicate-row issue -- existence is all that matters, not row count.
  local filter_cte="" filter_join="" filter_priority_check=""
  if [[ -n "$filter_table" && "$filter_table" != "-" && "$filter_table" != "null" ]]; then
    filter_cte="filter_state AS (
  SELECT DISTINCT product_id FROM \`${PROJECT}.${filter_table}\`
),
"
    filter_join="LEFT JOIN filter_state fs ON fs.product_id = sc.product_id"
    filter_priority_check="WHEN fs.product_id IS NOT NULL THEN NULL
      "
  fi
  cat <<SQL
WITH scoped AS (
  SELECT product_id, sku_name, REPLACE(image, '"', '') AS image, ecommerce_platform, qa_status, gmv_monthly
  FROM \`${PROJECT}.${source_table}\`
  WHERE product_tier = 'Tier 1'
    AND FORMAT_DATE('%Y-%m', month) = '${month}'
    AND ecommerce_platform $(platform_match_clause "$platform_titlecase")
),
qa_state AS (
  -- product_id_dict_qa is INSERT-ONLY -- a product can have many historical rows, not one. A raw
  -- SELECT (no dedup) fans out the LEFT JOIN below: a product with an OLD unconfident row and a
  -- NEWER confident row would match on the old row too, leaking a resolved product back into the
  -- worklist as priority=1 forever. Confirmed live (project memory
  -- project_non_niq_qa_state_fanout_bug.md): a 380-row v2 worklist was 100% already-resolved this
  -- way (332 confident, 48 terminal, 0 genuinely retry-eligible). Deduping to the "latest row by
  -- timestamp" is NOT the fix -- also confirmed live (same memory): product_id_dict_qa has no
  -- timestamp COLUMN (only inside _meta JSON, absent entirely on legacy rows), and "latest row"
  -- ordering was caught silently UN-TERMINATING products whenever a later write landed after a
  -- human_review:true row. The correct fix is order-independent aggregate flags over the WHOLE
  -- history per product: has this product EVER been confident, EVER gone terminal, EVER had a
  -- still-pending unconfident row -- gate priority 1 on pending-and-never-resolved, not on
  -- whichever row happens to sort last.
  SELECT
    ${qa_pk_col} AS product_id,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.qa_confidence') = 'unconfident'
               AND COALESCE(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.human_review'), 'false') != 'true') AS has_unconfident_pending,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.qa_confidence') = 'confident') AS has_confident,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.human_review') = 'true') AS has_terminal
  FROM \`${PROJECT}.${qa_table}\`
  GROUP BY ${qa_pk_col}
),
${filter_cte}prioritized AS (
  SELECT sc.product_id, sc.sku_name, sc.image, sc.gmv_monthly, sc.ecommerce_platform,
    CASE
      ${filter_priority_check}WHEN qs.product_id IS NULL AND sc.qa_status = 'Not Reviewed' THEN 0
      WHEN qs.has_unconfident_pending AND NOT qs.has_confident AND NOT qs.has_terminal THEN 1
      ELSE NULL
    END AS priority
  FROM scoped sc
  LEFT JOIN qa_state qs ON qs.product_id = sc.product_id
  ${filter_join}
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
  echo "${entries[0]}"
}

build_qa_prompt() {
  local dataset="$1" platform="$2" source_table="$3" qa_table="$4" dict_table="$5" filter_table="$6"
  local qa_pk_col="$7" dict_identity_col="$8" dict_typo_col="$9" meili_index="${10}" worklist_file="${11}"
  local worklist_count="${12}" product_id_dict="${13}"

  # The QA table's identity column is `sku_type_complete` -- same resolution as v1.
  local qa_identity_col="sku_type_complete"

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
      YES -> write those SAME brand/${qa_identity_col} values to \`${PROJECT}.${qa_table}\`, then go to 2d.
      NO, or no mapping row for this product -> continue to 2c."
  fi

  cat <<PROMPT
Non-NIQ Agentic QA session (v2 -- product_tier-based worklist) for dataset=${dataset},
platform=${platform}. See docs/superpowers/specs/2026-08-06-non-niq-agentic-qa-design.md for the
decision tree, confidence loop, and _meta conventions this still implements -- read it in full
before starting. The only difference from the original design: the worklist below comes from
master_table_prod's precomputed product_tier column, not a self-computed GMV percentile.

Resolved for this run: source_table=${PROJECT}.${source_table} (master_table_prod, NOT the _dev
table -- confirmed a separate table with its own qa_status column), qa_table=${PROJECT}.${qa_table},
dict_table=${PROJECT}.${dict_table}, filter_table (write target)=${PROJECT}.${filter_table},
qa_pk_col=${qa_pk_col}, dict_identity_col=${dict_identity_col}, dict_typo_col=${dict_typo_col},
product_id_dict (prior mapping table, read-only)=${product_id_dict},
meilisearch_index=${meili_index} (at ${MEILI_URL}).

Identity columns -- do not mix these up:
- The QA table's identity column is ${qa_identity_col}. It is the same on every category and is
  what you write in every QA-table write below. Never write ${dict_identity_col} to the QA table.
- ${dict_identity_col} is the {dataset}_dict table's identity column, resolved live for this
  category. Use it ONLY when reading/matching against, or minting a new row in, the dict table.

STEP 0 -- The full worklist has ALREADY been materialized for you at
${worklist_file}, exactly ${worklist_count} rows, one JSON object per line (JSONL) -- do NOT query
BigQuery to re-fetch it, and do NOT trust any other row count than ${worklist_count}. Read the file
(in slices if it's too large for one Read) rather than querying BigQuery for it. Each line has:
product_id, sku_name, image, gmv_monthly, ecommerce_platform, priority. It is already scoped to
product_tier = 'Tier 1' and prioritized (unreviewed rows before agent-flagged-unconfident retry
rows, both by gmv_monthly descending) -- process it in that order. If you cannot account for all
${worklist_count} rows by the end of your turn budget, explicitly report status: partial (or
status: blocked if you cannot proceed at all) -- never silently process a subset and report
status: complete.

STEP 1 -- Retrieve Meilisearch candidates for the WHOLE worklist in ONE batch call, never one call
per product. Embedding and searching are both mechanical, repetitive work -- they are done here in
Python, not by you, so your per-product loop in STEP 2 never spends a tool call constructing a
search request:
  1. Derive /tmp/${dataset}_${platform}_v2_worklist.jsonl from ${worklist_file} (STEP 0's file) --
     one line per worklist product: {"id": "<product_id>", "text": "<sku_name>"}. This is itself
     mechanical -- don't hand-transcribe rows, run:
       jq -c '{id: .product_id, text: .sku_name}' ${worklist_file} > /tmp/${dataset}_${platform}_v2_worklist.jsonl
  2. Run:
     ${PYTHON_BIN} ${REPO_ROOT}/script/non_niq/non_niq_helper.py retrieve \\
       --input-file /tmp/${dataset}_${platform}_v2_worklist.jsonl \\
       --output-file /tmp/${dataset}_${platform}_v2_candidates.jsonl \\
       --meili-index ${meili_index}
  3. Read back /tmp/${dataset}_${platform}_v2_candidates.jsonl -- one line per product:
     {"id": "<product_id>", "candidates": [{"product_id","sku_name","brand","sku_type_complete"}, ...]}
     Each product's candidates are already the top hybrid-search results (confirmed exemplars from
     ${meili_index}) -- this is STEP 2c's retrieval, already done. Do not construct your own
     Meilisearch search request for any product; just read this file.

STEP 2 -- For each product in the worklist, in order:

  2a. RELEVANT to this category? This judgment is MULTIMODAL -- you must actually LOOK at the
      product image, not just read its URL. The image URL is the worklist's \`image\` column.
      For each product, download it to a local file and then open that file with the Read tool:
        curl -sSL --max-time 30 "<image_url>" -o /tmp/${dataset}_v2_<product_id>.jpg
        (then: Read /tmp/${dataset}_v2_<product_id>.jpg)
      Do this BEFORE making any relevance / brand / sku_type judgment for the product. Text-only
      reasoning on sku_name is exactly the failure mode this harness exists to fix -- do not skip
      the download and infer from the URL or the name.
      If the download fails, or the downloaded file is not a readable image (curl happily writes
      a 404 HTML body into a .jpg), say so explicitly in your reasoning for that product and
      treat it as TEXT-ONLY -- which is by itself grounds to mark it unconfident in 2d.
      Then, with the image + sku_name together -- does this product genuinely belong in
      "${dataset}"?
      NO  -> write {product_id, ecommerce_platform, sku_name, reason} to \`${PROJECT}.${filter_table}\`
             (this dataset's OWN filter table -- never write to a different dataset's filter table
             even if the Sheet cross-references one for read context), _meta stamped
             '{"source":"claude_code","timestamp":"<now, ISO 8601 UTC>"}' (see the _meta format
             rule below), do NOT create a taxonomy entry. Move to the next product.
             Use the worklist row's OWN \`ecommerce_platform\` value verbatim (it's the source
             table's real, Title-Case value, e.g. "Shopee"/"Lazada" -- do not lowercase it or
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
             Step A: insert brand + ${dict_identity_col} + keywords (+ ${dict_typo_col} if you
                     have common misspellings), _meta stamped
                     '{"source":"claude_code","timestamp":"<now, ISO 8601 UTC>"}' here (see the
                     _meta format rule below -- NOT the bare string "claude_code", that is not
                     valid JSON).
             Step B: populate the remaining attribute columns for this dict's schema, GROUNDED on
                     existing dict rows' actual vocabulary and formatting -- query
                     \`SELECT DISTINCT <column> FROM ${PROJECT}.${dict_table}\` per attribute column
                     before writing a new value, prefer an existing value over inventing one, and
                     match existing formatting exactly (e.g. "150 ml" not "150ml").
             Then write brand/${qa_identity_col} values pointing at the new entry to
             \`${PROJECT}.${qa_table}\`.

  2d. Self-QA: as an explicit, separate judgment (not folded into 2a-2c's reasoning), state how
      confident you are in the decision you just made for this product. Then:
      - If this is the product's FIRST time being processed this session (no qa_confidence value
        existed for it before this run): write _meta =
        '{"source":"claude_code","qa_confidence":"confident","timestamp":"<now, ISO 8601 UTC>"}' if
        confident, or
        '{"source":"claude_code","qa_confidence":"unconfident","human_review":false,"timestamp":"<now>"}'
        if not.
      - If this product ALREADY had a qa_confidence:'unconfident', human_review:false row before
        this run (i.e. this is its one allowed retry): and you are STILL unconfident after
        redoing 2a-2c with full multimodal effort, write _meta =
        '{"source":"claude_code","qa_confidence":"unconfident","human_review":true,"timestamp":"<now>"}'
        -- this is terminal, the product will not re-enter future worklists for this harness.
        If you ARE confident on this retry, write the confident shape as above.

Hard rules, never relaxed:
- Mapping table (any product_id_dict / prior-engine table) is NEVER modified by this harness --
  corrections only ever land in \`${PROJECT}.${qa_table}\`.
- All writes use bq query DML, never the streaming API -- CLAUDE.md's 90-minute streaming-buffer
  rule. The very next run's retry-cap logic depends on reading back this run's QA rows reliably.
- Never write to \`qa_status\` on the source table (master_table_prod). A separate QA-labelling
  update process reads \`${qa_table}\` independently and flips \`qa_status\` to 'Reviewed' once a
  product has a row there -- this harness's job is only to write
  \`${qa_table}\`/\`${dict_table}\`/\`${filter_table}\`, never \`qa_status\` itself.
- Every _meta read you do yourself (e.g. checking whether a product already has an unconfident
  row) must use JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.field'), never bare JSON_VALUE(_meta, ...)
  and never SAFE.JSON_VALUE(...) -- the latter LOOKS right but is not valid BigQuery syntax
  ("SAFE with function json_value is not supported"). Some existing _meta values are empty
  strings or the literal text "nan"; SAFE.PARSE_JSON returns NULL on those instead of raising, and
  JSON_VALUE on a NULL JSON value is itself safe.
- Every _meta WRITE must be a JSON string, never a bare string. Baseline format, used for every
  _meta write in this session unless a step above specifies a richer shape (2d's self-QA write
  adds qa_confidence/human_review on top of this same base):
    {"source":"claude_code","timestamp":"<now, ISO 8601 UTC>"}
  e.g. {"source":"claude_code","timestamp":"2026-08-16T19:19:06Z"}. A bare string like
  "claude_code" (no braces/quotes-as-JSON) is NOT valid JSON -- SAFE.PARSE_JSON on it returns
  NULL, silently losing source/timestamp on every future read of that row.
- Attempt to resolve the ENTIRE worklist within your turn budget this session -- do not
  self-limit to a small sample. Stop early only when genuinely low on turns, and say so honestly
  in findings.

If you hit a genuine blocker -- something wrong with these instructions, missing data, anything
that would make proceeding unsafe -- stop and output status='blocked' with the blockers array
populated. That is a valid, expected outcome.

Output ONLY this JSON when done, nothing else:
{status: complete|partial|failed|blocked, rows_qa_confirmed, rows_qa_unconfident, rows_filtered, rows_created_in_dict, findings, blockers}.
PROMPT
}

extract_json_object() {
  local text="$1"
  printf '%s' "$text" | grep -Pzo '(?s)\{.*\}' | tr -d '\0'
}

# Identical to v1's -- shared contract, not shared code (self-contained script, same as v1).
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

=== QA Session Result (v2) ===
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
  if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <DATASET> <PLATFORM> [MAX_TURNS] [MAX_ROWS]" >&2
    exit 1
  fi
  local dataset="$1" platform="$2" max_turns="${3:-300}" max_rows="${4:-300}"

  local category_json
  category_json=$("$PYTHON_BIN" "$(dirname "$0")/non_niq_helper.py" categories --country ID \
    | jq -c --arg ds "$dataset" --arg pl "$platform" '.[] | select(.dataset == $ds and .ecommerce_platform == $pl)')
  if [[ -z "$category_json" ]]; then
    echo "No active config Sheet row for dataset=${dataset} platform=${platform}" >&2
    echo "QUEUE_SIGNAL: FAILED"
    exit 1
  fi

  # source_table here is master_table_prod (Sheet column AC, no "_dev" suffix) -- the ONLY
  # difference in table resolution vs v1, which uses `table` (AB). Everything else is identical.
  local source_table qa_table dict_table filter_table_config product_id_dict
  source_table=$(echo "$category_json" | jq -r '.master_table_prod')
  qa_table=$(echo "$category_json" | jq -r '.product_id_dict_qa')
  dict_table=$(echo "$category_json" | jq -r '.dict')
  filter_table_config=$(echo "$category_json" | jq -r '.filter_table')
  product_id_dict=$(echo "$category_json" | jq -r '.product_id_dict')
  local filter_table
  filter_table=$(primary_filter_table "$filter_table_config" "$dataset")

  # '-' is the Sheet's "not configured" marker -- fatal for every table this v2 harness reads or
  # writes (source_table now included, since v2's worklist depends entirely on it).
  local t
  for t in "source_table=$source_table" "qa_table=$qa_table" "dict_table=$dict_table" "filter_table=$filter_table"; do
    if [[ "${t#*=}" == "-" || "${t#*=}" == "null" || -z "${t#*=}" ]]; then
      echo "Config Sheet row for dataset=${dataset} platform=${platform} has unconfigured ${t%%=*} ('${t#*=}') -- cannot run QA v2." >&2
      echo "QUEUE_SIGNAL: FAILED"
      exit 1
    fi
  done

  # Plain CLI args, not string-interpolated into a python -c source -- a table name can never
  # break out of anything, it's just an argv element.
  local columns_json qa_pk_col dict_identity_col dict_typo_col
  columns_json=$("$PYTHON_BIN" "$(dirname "$0")/non_niq_helper.py" columns --project "$PROJECT" \
    --qa-table "$qa_table" --dict-table "$dict_table")
  qa_pk_col=$(echo "$columns_json" | jq -r '.qa_pk_col')
  dict_identity_col=$(echo "$columns_json" | jq -r '.dict_identity_col')
  dict_typo_col=$(echo "$columns_json" | jq -r '.dict_typo_col')

  # Explicit failure checks, not bare `set -e` reliance -- same rationale as v1: a silent bq
  # failure inside a `var=$(...)` reassignment looks like a hang, not an error, under set -e alone.
  local month
  if ! month=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "$(default_month_query "$source_table" "$platform")" | tail -1); then
    echo "bq query failed while resolving the latest month for ${source_table}/${platform} -- see bq's error above." >&2
    echo "QUEUE_SIGNAL: FAILED"
    exit 1
  fi

  local meili_index="${dataset}_taxonomy_qa"
  local query
  query=$(worklist_query "$source_table" "$qa_table" "$qa_pk_col" "$month" "$platform" "$max_rows" "$filter_table")

  # Materialize the FULL worklist to a file for Claude to Read -- same rationale as v1: handing
  # Claude raw SQL to re-run risks output truncation on large worklists silently passing as
  # status: partial -> QUEUE_SIGNAL: DONE. --max_rows=1000000 is NOT optional -- bq query silently
  # defaults to --max_rows=100 otherwise (v1 confirmed this live).
  local worklist_file="/tmp/${dataset}_${platform}_v2_full_worklist.jsonl"
  if ! bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=json --max_rows=1000000 \
    "$query" | jq -c '.[]' > "$worklist_file"; then
    echo "bq query failed while materializing the worklist for ${dataset}/${platform} (v2) -- see bq's error above." >&2
    echo "QUEUE_SIGNAL: FAILED"
    exit 1
  fi

  local worklist_count
  worklist_count=$(wc -l < "$worklist_file" | tr -d ' ')

  if [[ "$worklist_count" == "0" ]]; then
    echo "No in-scope worklist for ${dataset}/${platform}/${month} (v2, product_tier=Tier 1) -- nothing to do."
    rm -f "$worklist_file"
    echo "QUEUE_SIGNAL: NOTHING_TO_DO"
    exit 0
  fi

  echo "${dataset}/${platform} (v2), month=${month}, worklist_count=${worklist_count}"

  local prompt
  prompt=$(build_qa_prompt "$dataset" "$platform" "$source_table" "$qa_table" "$dict_table" \
    "$filter_table" "$qa_pk_col" "$dict_identity_col" "$dict_typo_col" "$meili_index" "$worklist_file" \
    "$worklist_count" "$product_id_dict")

  # `|| true` is load-bearing under `set -e` -- same rationale as v1: a non-zero claude exit can
  # still follow real BigQuery writes, and dying here would swallow the transcript that says what
  # was written.
  local claude_output
  claude_output=$(claude -p --output-format json --permission-mode bypassPermissions --max-turns "$max_turns" "$prompt") || true
  echo "$claude_output"
  format_result_summary "$claude_output"

  echo "QUEUE_SIGNAL: $(decide_queue_signal "$claude_output")"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
