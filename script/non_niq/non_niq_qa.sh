#!/usr/bin/env bash
set -euo pipefail

# Usage: script/non_niq/non_niq_qa.sh <DATASET> <PLATFORM> [MAX_TURNS] [MAX_ROWS]
# e.g.  script/non_niq/non_niq_qa.sh babybath shopee
#       script/non_niq/non_niq_qa.sh babybath shopee 400
#       script/non_niq/non_niq_qa.sh cookiesbiscuit shopee 300 150
#
# Agentic QA harness for one (dataset, platform) pair -- issue #2's decision tree (relevance ->
# correct/re-point -> match-or-create), Meilisearch hybrid retrieval instead of the POC's brute
# keyword scoring, confidence loop encoded in product_id_dict_qa's existing _meta JSON.
# See docs/superpowers/specs/2026-08-06-non-niq-agentic-qa-design.md for the full design.

PROJECT="sincere-hearth-273704"
MEILI_URL="http://34.124.146.29:7700"

# Resolves regardless of cwd -- non_niq_helper.py needs google-cloud-bigquery and
# sentence-transformers for real (columns/retrieve), so this must be an interpreter that actually
# has them: this repo's own uv-managed .venv, not bare `python3` off PATH.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PYTHON_BIN="${REPO_ROOT}/.venv/bin/python3"

default_month_query() {
  local source_table="$1"
  echo "SELECT FORMAT_DATE('%Y-%m', MAX(month)) FROM \`${PROJECT}.${source_table}\`"
}

# Scope per issue #2: latest month, top 90% cumulative GMV per ecommerce_platform (NOT the epic's
# general 95% -- QA uses a different threshold on purpose). Priority: rows with no QA-table entry
# yet come first (priority 0), then rows the agent already marked unconfident but hasn't yet
# capped out on retry (priority 1) -- human_review=true rows are excluded entirely, they're
# terminal. Priority is computed exactly ONCE, in the `prioritized` CTE, and the outer WHERE is
# just `priority IS NOT NULL` -- do not re-state the priority predicates in the WHERE clause.
# BigQuery sorts NULL first under ORDER BY priority ASC, so a duplicated predicate that drifts
# out of sync would sort excluded rows AHEAD of real priority-0 rows instead of dropping them.
# Every _meta read uses JSON_VALUE(SAFE.PARSE_JSON(_meta), ...) -- _meta is not always valid JSON
# in production (empty strings, literal "nan" both observed live), and bare JSON_VALUE raises on
# malformed input. `SAFE.JSON_VALUE(...)` looks like the obvious fix but is NOT valid BigQuery
# syntax -- confirmed live: "SAFE with function json_value is not supported." SAFE only composes
# with PARSE_JSON here; JSON_VALUE then runs on the (possibly NULL, on parse failure) JSON value,
# which is safe on its own.
worklist_query() {
  local source_table="$1" qa_table="$2" qa_pk_col="$3" month="$4" platform="$5" enrichment_table="${6:-}"
  # LIMIT keeps a single session's worklist bounded -- live-observed that categories with
  # thousands of in-scope rows (e.g. cookiesbiscuit: 6143 rows) blow the turn budget long before
  # finishing, at roughly 1.3 tool calls/product. 300 is a safe default; ORDER BY already runs
  # priority-then-gmv, so LIMIT keeps the highest-priority, highest-revenue rows either way and
  # unprocessed rows simply reappear (still priority 0) on the next queue-worker iteration.
  local row_limit="${7:-300}"
  local filter_table="${8:-}"
  local platform_titlecase="${platform^}"
  # item_description/product_attributes_attrs enrichment is Shopee-only by data availability, not
  # a scoping choice: confirmed live that non-Shopee 0_pipeline_* tables (e.g. Blibli) have an
  # entirely different schema with no description/specs columns at all. dataset is derived from
  # source_table (already "{dataset}.master_..._dev") rather than a separate parameter.
  local dataset="${source_table%%.*}"
  local enrichment_cte_and_join="" enrichment_join="" enrichment_select="NULL AS item_description, NULL AS product_attributes_attrs"
  if [[ "$platform_titlecase" == "Shopee" && -n "$enrichment_table" && "$enrichment_table" != "-" && "$enrichment_table" != "null" ]]; then
    # enrichment_table is a history table with multiple rows per item_itemid (confirmed live: ~108 rows
    # per item avg). Dedupe to latest row per item before joining to avoid fan-out that corrupts
    # cumulative GMV scoping (which must run post-join, not pre-join).
    # product_attributes_attrs is raw Shopee attribute JSON -- confirmed live it carries ~13
    # mostly-null fields per attribute entry around one real {name, value} pair (e.g. "Merek":
    # "CUSSONS"). Project down to a compact "name=value; name=value" string here so the worklist
    # this harness ships (to a file Claude reads, not BigQuery) carries only the real signal.
    # Confirmed live on the FULL (untruncated) enrichment table that the majority (~94% of rows
    # with a non-null value, measured on babybath/shopee: 88280/94086) store it as Python repr
    # (single-quoted, None/True/False) rather than valid JSON -- bare SAFE.PARSE_JSON on the raw
    # string nulls out almost the entire signal, not just an edge case. COALESCE tries the raw
    # string first (so already-valid JSON, and any row containing a literal apostrophe that would
    # be corrupted by the quote-swap, is never touched), and only falls back to a None/True/False
    # -> null/true/false + '->" normalized parse when the raw parse fails. Spot-checked ~90k
    # recovered rows live: no structural corruption, only benign literal \n/\t sequences surviving
    # into a few values.
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
  # image carries a live-observed, upstream CSV-quoting artifact: literal double-quote characters
  # either embedded mid-URL (e.g. .../file/"sg-11134201-..."<) or wrapping the whole real URL --
  # a real session confirmed this breaks STEP 2a's curl download (every quoted URL 404s) unless
  # stripped first. REPLACE removes every literal '"' regardless of which shape it takes, leaving
  # the real URL either way -- do this here, once, rather than relying on the prompt telling Claude
  # to strip it per-product.
  #
  # filter_table exclusion: STEP 2a's NO branch writes ONLY to the filter table, never to
  # product_id_dict_qa -- so a product already confirmed out-of-scope leaves no trace in qa_state
  # (the only table priority was computed from) and looks identical to a never-processed row on
  # every future run. Live-confirmed repeatedly (up to 100% of a freshly materialized worklist)
  # that already-filtered products keep resurfacing as priority-0 rows, burning a full session on
  # already-resolved work. SELECT DISTINCT also absorbs filter_table's own known duplicate-row
  # issue (the same gap causes a product to get independently re-filtered in a later session) --
  # existence is all that matters here, not row count.
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
WITH ${enrichment_cte_and_join}base AS (
  SELECT s.product_id, s.sku_name, REPLACE(s.image, '"', '') AS image, s.ecommerce_platform, s.qa_status,
         COALESCE(s.flag_GWP, FALSE) OR REGEXP_CONTAINS(UPPER(s.sku_name), r'\[NOT FOR SALE\]|\[GWP\]') AS flag_GWP,
         s.gmv_monthly, ${enrichment_select}
  FROM \`${PROJECT}.${source_table}\` s
  ${enrichment_join}
  WHERE FORMAT_DATE('%Y-%m', s.month) = '${month}' AND s.ecommerce_platform = '${platform_titlecase}'
),
with_cumulative AS (
  SELECT *,
    ROUND(100.0 * SUM(CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END)
            OVER (ORDER BY gmv_monthly DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
          / NULLIF(SUM(CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END) OVER (), 0), 2) AS cumulative_gmv_pct
  FROM base
),
scoped AS (
  SELECT * FROM with_cumulative WHERE cumulative_gmv_pct <= 90
),
qa_state AS (
  SELECT ${qa_pk_col} AS product_id,
         JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.qa_confidence') AS qa_confidence,
         JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.human_review') AS human_review
  FROM \`${PROJECT}.${qa_table}\`
),
${filter_cte}prioritized AS (
  SELECT sc.product_id, sc.sku_name, sc.image, sc.gmv_monthly, sc.ecommerce_platform,
         sc.item_description, sc.product_attributes_attrs,
    CASE
      ${filter_priority_check}WHEN qs.product_id IS NULL AND sc.qa_status = 'Not Reviewed' THEN 0
      WHEN qs.qa_confidence = 'unconfident' AND COALESCE(qs.human_review, 'false') != 'true' THEN 1
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
# read-only reference (checked before flagging, per the spec, but never written to) and is
# intentionally not returned by this function.
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

  # The QA table's identity column is `sku_type_complete` on ALL 10 categories -- it needs no
  # live resolution (the Windmill-deployed non_niq_embed.py's sync_category reads it directly for
  # the same reason -- see docs/windmill-non-niq-embed-prompt.md). Only the {dataset}_dict table's
  # identity column varies (sku_type vs sku_type_complete), which is what $dict_identity_col
  # resolves. Never use $dict_identity_col for a QA-table write: on
  # babybath/babycreamlotion/babysunscreen/telonoil it resolves to `sku_type`, a column the QA
  # table does not have.
  local qa_identity_col="sku_type_complete"

  # Decision-tree step 2 exists only for the 4 categories with a populated product_id_dict
  # mapping table (susubayi, multivitamin, telonoil, kidsuplement); the Sheet has '-' for the
  # rest. That table's schema was NOT resolved by non_niq_helper.py's column resolver and varies
  # per category, so the prompt tells Claude to discover its shape before querying it.
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
      YES -> write those SAME brand/${qa_identity_col} values to \`${PROJECT}.${qa_table}\`, THEN
             run the qa_status UPDATE (see Hard rules below -- do not skip this), then go to 2d.
      NO, or no mapping row for this product -> continue to 2c."
  fi

  cat <<PROMPT
Non-NIQ Agentic QA session for dataset=${dataset}, platform=${platform}. See
docs/superpowers/specs/2026-08-06-non-niq-agentic-qa-design.md for the full design this
implements -- read it in full before starting.

Resolved for this run: source_table=${PROJECT}.${source_table}, qa_table=${PROJECT}.${qa_table},
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
(in slices if it's too large for one Read) rather than querying BigQuery for it. Each line has the
same column shape the worklist query produces: product_id, sku_name, image, gmv_monthly,
ecommerce_platform, item_description, product_attributes_attrs, priority. It is already scoped to
top 90% cumulative GMV per platform and prioritized (unreviewed rows before agent-flagged-
unconfident retry rows, both by gmv_monthly descending) -- process it in that order. If you cannot
account for all ${worklist_count} rows by the end of your turn budget, explicitly report
status: partial (or status: blocked if you cannot proceed at all) -- never silently process a
subset and report status: complete.

STEP 1 -- Retrieve Meilisearch candidates for the WHOLE worklist in ONE batch call, never one call
per product. Embedding and searching are both mechanical, repetitive work -- they are done here in
Python, not by you, so your per-product loop in STEP 2 never spends a tool call constructing a
search request:
  1. Derive /tmp/${dataset}_${platform}_worklist.jsonl from ${worklist_file} (STEP 0's file) --
     one line per worklist product: {"id": "<product_id>", "text": "<sku_name>"}. This is itself
     mechanical -- don't hand-transcribe rows, run:
       jq -c '{id: .product_id, text: .sku_name}' ${worklist_file} > /tmp/${dataset}_${platform}_worklist.jsonl
  2. Run:
     ${PYTHON_BIN} ${REPO_ROOT}/script/non_niq/non_niq_helper.py retrieve \\
       --input-file /tmp/${dataset}_${platform}_worklist.jsonl \\
       --output-file /tmp/${dataset}_${platform}_candidates.jsonl \\
       --meili-index ${meili_index}
  3. Read back /tmp/${dataset}_${platform}_candidates.jsonl -- one line per product:
     {"id": "<product_id>", "candidates": [{"product_id","sku_name","brand","sku_type_complete"}, ...]}
     Each product's candidates are already the top hybrid-search results (confirmed exemplars from
     ${meili_index}) -- this is STEP 2c's retrieval, already done. Do not construct your own
     Meilisearch search request for any product; just read this file.

STEP 2 -- For each product in the worklist, in order:

  2a. RELEVANT to this category? This judgment is MULTIMODAL -- you must actually LOOK at the
      product image, not just read its URL. The image URL is the worklist's \`image\` column.
      For each product, download it to a local file and then open that file with the Read tool:
        curl -sSL --max-time 30 "<image_url>" -o /tmp/${dataset}_<product_id>.jpg
        (then: Read /tmp/${dataset}_<product_id>.jpg)
      Do this BEFORE making any relevance / brand / sku_type judgment for the product. Text-only
      reasoning on sku_name is exactly the failure mode this harness exists to fix -- do not skip
      the download and infer from the URL or the name.
      If the download fails, or the downloaded file is not a readable image (curl happily writes
      a 404 HTML body into a .jpg), say so explicitly in your reasoning for that product and
      treat it as TEXT-ONLY -- which is by itself grounds to mark it unconfident in 2d.
      Then, with the image + sku_name + item_description + product_attributes_attrs together (the
      worklist's own columns; product_attributes_attrs is a compact "name=value; name=value" string
      of the product's real Shopee attributes, e.g. brand/size -- not raw JSON;
      item_description/product_attributes_attrs are Shopee-only signal and NULL on other platforms
      -- treat NULL as simply having no extra signal, not as a problem) --
      does this product genuinely belong in "${dataset}"?
      NO  -> write {product_id, ecommerce_platform, sku_name, reason} to \`${PROJECT}.${filter_table}\`
             (this dataset's OWN filter table -- never write to a different dataset's filter table
             even if the Sheet cross-references one for read context), _meta stamped
             '{"source":"claude_code"}', do NOT create a taxonomy entry. THEN run the qa_status UPDATE
             (see Hard rules below -- do not skip this, filtered-out products count as reviewed
             too). Move to the next product.
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
             \`${PROJECT}.${qa_table}\`, THEN run the qa_status UPDATE (see Hard rules below -- do
             not skip this).
      NO  -> two-step create in \`${PROJECT}.${dict_table}\`:
             Step A: insert brand + ${dict_identity_col} + keywords (+ ${dict_typo_col} if you
                     have common misspellings), _meta='claude_code' stamped here.
             Step B: populate the remaining attribute columns for this dict's schema, GROUNDED on
                     existing dict rows' actual vocabulary and formatting -- query
                     \`SELECT DISTINCT <column> FROM ${PROJECT}.${dict_table}\` per attribute column
                     before writing a new value, prefer an existing value over inventing one, and
                     match existing formatting exactly (e.g. "150 ml" not "150ml").
             Then write brand/${qa_identity_col} values pointing at the new entry to
             \`${PROJECT}.${qa_table}\`, THEN run the qa_status UPDATE (see Hard rules below -- do
             not skip this).

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
- The "qa_status UPDATE" referenced at every write branch in STEP 2 above is this exact statement
  -- run it EVERY time you write a product to \`${filter_table}\` (2a) OR to \`${qa_table}\`
  (2b/2c, any confidence outcome, no exceptions), once per product:
    UPDATE \`${PROJECT}.${source_table}\` SET qa_status = 'Reviewed'
    WHERE product_id = '<this product's product_id>'
      AND month >= DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL 1 MONTH)
  This updates this month's AND last month's row for that product_id only -- not the product's
  entire history, and not just the current month's row. \`qa_status\` tracks "has this product been
  reviewed recently", scoped to match the one-time historical backfill already run for this same
  gap (limited to the same this-month/last-month window, not all history). Confirmed live that
  this harness previously never wrote \`qa_status\` back at all -- every product it had ever
  confidently reviewed still showed \`qa_status = 'Not Reviewed'\` on the source table, even though
  \`qa_status\` is a real field other processes write and read (230k+ 'Reviewed' rows exist from
  elsewhere) -- this is exactly what caused analysts to keep asking why "reviewed" products still
  showed as unreviewed. Getting this wrong (or skipping it) reproduces that same complaint. This
  UPDATE is independent of the retry-eligibility logic (that's driven entirely by
  \`${qa_table}\`'s own \`_meta.qa_confidence\`/\`human_review\`, never by \`qa_status\`) -- so update
  it even on an unconfident-first-attempt row, not just on confident/terminal outcomes.
- Every _meta read you do yourself (e.g. checking whether a product already has an unconfident
  row) must use JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.field'), never bare JSON_VALUE(_meta, ...)
  and never SAFE.JSON_VALUE(...) -- the latter LOOKS right but is not valid BigQuery syntax
  ("SAFE with function json_value is not supported"). Some existing _meta values are empty
  strings or the literal text "nan"; SAFE.PARSE_JSON returns NULL on those instead of raising, and
  JSON_VALUE on a NULL JSON value is itself safe.
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

# Shared by decide_queue_signal and format_result_summary -- both need Claude's own inner result
# JSON (the {status, rows_qa_confirmed, ...} object the prompt's output contract specifies), not
# the outer claude -p envelope. Claude's .result field is USUALLY that JSON directly, but
# sometimes wraps it in prose -- extract_json_object is the regex fallback for that case.
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

# Reads BOTH layers: the outer claude -p envelope (total_cost_usd, modelUsage, num_turns,
# duration_ms -- confirmed live via a real `claude -p --output-format json` call) and the inner
# result JSON (status, rows_*, findings, blockers) via the same extract_result_json used by
# decide_queue_signal. Printed alongside the raw claude_output echo in main(), never replacing it.
format_result_summary() {
  local claude_output="$1"
  local result_json
  result_json=$(extract_result_json "$claude_output")

  local status rows_confirmed rows_unconfident rows_filtered rows_created findings blockers
  # When result_json is empty (envelope unparseable), jq on empty input produces no output, not
  # an error -- so the || fallback never fires. Fast-path the empty case explicitly.
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

=== QA Session Result ===
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

  local source_table qa_table dict_table filter_table_config product_id_dict enrichment_table
  source_table=$(echo "$category_json" | jq -r '.table')
  qa_table=$(echo "$category_json" | jq -r '.product_id_dict_qa')
  dict_table=$(echo "$category_json" | jq -r '.dict')
  filter_table_config=$(echo "$category_json" | jq -r '.filter_table')
  product_id_dict=$(echo "$category_json" | jq -r '.product_id_dict')
  enrichment_table=$(echo "$category_json" | jq -r '."0"')
  local filter_table
  filter_table=$(primary_filter_table "$filter_table_config" "$dataset")

  # '-' is the Sheet's "not configured" marker. It is LEGAL for product_id_dict (6 of 10
  # categories have no prior mapping table -- build_qa_prompt's step2_block handles that), but
  # fatal for the three tables this harness actually reads and writes: proceeding would build a
  # prompt naming `sincere-hearth-273704.-`.
  local t
  for t in "qa_table=$qa_table" "dict_table=$dict_table" "filter_table=$filter_table"; do
    if [[ "${t#*=}" == "-" || "${t#*=}" == "null" || -z "${t#*=}" ]]; then
      echo "Config Sheet row for dataset=${dataset} platform=${platform} has unconfigured ${t%%=*} ('${t#*=}') -- cannot run QA." >&2
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

  # Explicit failure checks, not bare `set -e` reliance: a bare `var=$(bq query | tail -1)`
  # reassignment DOES propagate a pipefail'd bq failure and kill the script under set -e, but
  # silently -- bq's own error text goes straight to stderr, past this function's own stdout, and
  # nothing here ever prints "this is why we stopped." That silence is exactly what made a real
  # bug (SAFE.JSON_VALUE(...) is not valid BigQuery syntax) look like a hang instead of an error.
  local month
  if ! month=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "$(default_month_query "$source_table")" | tail -1); then
    echo "bq query failed while resolving the latest month for ${source_table} -- see bq's error above." >&2
    echo "QUEUE_SIGNAL: FAILED"
    exit 1
  fi

  local meili_index="${dataset}_taxonomy_qa"
  local query
  query=$(worklist_query "$source_table" "$qa_table" "$qa_pk_col" "$month" "$platform" "$enrichment_table" "$max_rows" "$filter_table")

  # Materialize the FULL worklist to a file for Claude to Read, instead of handing Claude the raw
  # SQL to re-run itself -- with item_description/product_attributes_attrs enrichment, the raw
  # query output is 18-320x larger than before enrichment, and Claude re-running it and only
  # seeing a truncated slice (while still honestly reporting status=partial) was getting recorded
  # as QUEUE_SIGNAL: DONE with most of the worklist never actually looked at. See
  # docs/superpowers/specs/2026-08-06-non-niq-agentic-qa-design.md.
  # --max_rows is NOT optional here: `bq query` silently defaults to --max_rows=100 (confirmed
  # live -- a 140-row worklist came back as exactly 100 rows without it), which would reproduce
  # the exact truncation bug this materialization step exists to fix. 1000000 is comfortably above
  # any real worklist size (top-90%-cumulative-GMV already caps these to low thousands at most).
  local worklist_file="/tmp/${dataset}_${platform}_full_worklist.jsonl"
  if ! bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=json --max_rows=1000000 \
    "$query" | jq -c '.[]' > "$worklist_file"; then
    echo "bq query failed while materializing the worklist for ${dataset}/${platform} -- see bq's error above." >&2
    echo "QUEUE_SIGNAL: FAILED"
    exit 1
  fi

  local worklist_count
  worklist_count=$(wc -l < "$worklist_file" | tr -d ' ')

  if [[ "$worklist_count" == "0" ]]; then
    echo "No in-scope worklist for ${dataset}/${platform}/${month} -- nothing to do."
    rm -f "$worklist_file"
    echo "QUEUE_SIGNAL: NOTHING_TO_DO"
    exit 0
  fi

  echo "${dataset}/${platform}, month=${month}, worklist_count=${worklist_count}"

  local prompt
  prompt=$(build_qa_prompt "$dataset" "$platform" "$source_table" "$qa_table" "$dict_table" \
    "$filter_table" "$qa_pk_col" "$dict_identity_col" "$dict_typo_col" "$meili_index" "$worklist_file" \
    "$worklist_count" "$product_id_dict")

  # `|| true` is load-bearing under `set -e`: a non-zero claude exit (turn-limit kill, transport
  # error) can still follow real BigQuery writes, and dying here would swallow the transcript that
  # says what was written. Echo it, then let decide_queue_signal return FAILED on unparseable output.
  local claude_output
  claude_output=$(claude -p --output-format json --permission-mode bypassPermissions --max-turns "$max_turns" "$prompt") || true
  echo "$claude_output"
  format_result_summary "$claude_output"

  echo "QUEUE_SIGNAL: $(decide_queue_signal "$claude_output")"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
