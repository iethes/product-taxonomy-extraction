#!/usr/bin/env bash
set -euo pipefail

# Usage: script/non_niq/non_niq_qa.sh <DATASET> <PLATFORM> [MAX_TURNS]
# e.g.  script/non_niq/non_niq_qa.sh babybath shopee
#       script/non_niq/non_niq_qa.sh babybath shopee 400
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
# Every _meta read uses SAFE.JSON_VALUE -- _meta is not always valid JSON in production
# (empty strings, literal "nan" both observed live) and bare JSON_VALUE raises on malformed input.
worklist_query() {
  local source_table="$1" qa_table="$2" qa_pk_col="$3" month="$4" platform="$5"
  cat <<SQL
WITH base AS (
  SELECT s.product_id, s.sku_name, s.image, s.ecommerce_platform, s.qa_status,
         COALESCE(s.flag_GWP, FALSE) OR REGEXP_CONTAINS(UPPER(s.sku_name), r'\[NOT FOR SALE\]|\[GWP\]') AS flag_GWP,
         s.gmv_monthly
  FROM \`${PROJECT}.${source_table}\` s
  WHERE FORMAT_DATE('%Y-%m', s.month) = '${month}' AND s.ecommerce_platform = '${platform}'
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
         SAFE.JSON_VALUE(_meta, '\$.qa_confidence') AS qa_confidence,
         SAFE.JSON_VALUE(_meta, '\$.human_review') AS human_review
  FROM \`${PROJECT}.${qa_table}\`
),
prioritized AS (
  SELECT sc.product_id, sc.sku_name, sc.image, sc.gmv_monthly,
    CASE
      WHEN qs.product_id IS NULL AND sc.qa_status = 'Not Reviewed' THEN 0
      WHEN qs.qa_confidence = 'unconfident' AND COALESCE(qs.human_review, 'false') != 'true' THEN 1
      ELSE NULL
    END AS priority
  FROM scoped sc
  LEFT JOIN qa_state qs ON qs.product_id = sc.product_id
)
SELECT * FROM prioritized
WHERE priority IS NOT NULL
ORDER BY priority ASC, gmv_monthly DESC
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
  local qa_pk_col="$7" dict_identity_col="$8" dict_typo_col="$9" meili_index="${10}" worklist_query="${11}"
  local product_id_dict="${12}"

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
      YES -> write those SAME brand/${qa_identity_col} values to \`${PROJECT}.${qa_table}\`, then go to 2d.
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

STEP 0 -- Get the live worklist (do not trust any cached number, re-run this yourself):
${worklist_query}
This is already scoped to top 90% cumulative GMV per platform and prioritized (unreviewed rows
before agent-flagged-unconfident retry rows, both by gmv_monthly descending) -- process it in
that order.

STEP 1 -- Retrieve Meilisearch candidates for the WHOLE worklist in ONE batch call, never one call
per product. Embedding and searching are both mechanical, repetitive work -- they are done here in
Python, not by you, so your per-product loop in STEP 2 never spends a tool call constructing a
search request:
  1. Write /tmp/${dataset}_${platform}_worklist.jsonl -- one line per worklist product:
     {"id": "<product_id>", "text": "<sku_name>"}
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
      Then, with the image + sku_name + item_description together --
      does this product genuinely belong in "${dataset}"?
      NO  -> write {product_id, ecommerce_platform, sku_name, reason} to \`${PROJECT}.${filter_table}\`
             (this dataset's OWN filter table -- never write to a different dataset's filter table
             even if the Sheet cross-references one for read context), _meta stamped
             '{"source":"claude_code"}', do NOT create a taxonomy entry. Move to the next product.
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
                     have common misspellings), _meta='claude_code' stamped here.
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
- Every _meta read you do yourself (e.g. checking whether a product already has an unconfident
  row) must use SAFE.JSON_VALUE, never bare JSON_VALUE -- some existing _meta values are empty
  strings or the literal text "nan", and bare JSON_VALUE raises on those.
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

decide_queue_signal() {
  local claude_output="$1"
  local result_json
  result_json=$(echo "$claude_output" | jq -r '.result // empty' 2>/dev/null) || result_json=""
  if [[ -z "$result_json" ]]; then
    echo "FAILED"
    return
  fi
  if ! echo "$result_json" | jq -e . >/dev/null 2>&1; then
    local extracted
    extracted=$(extract_json_object "$result_json")
    if [[ -n "$extracted" ]] && echo "$extracted" | jq -e . >/dev/null 2>&1; then
      result_json="$extracted"
    fi
  fi
  local status
  status=$(echo "$result_json" | jq -r '.status // empty' 2>/dev/null) || status=""
  case "$status" in
    blocked) echo "BLOCKED" ;;
    complete|partial) echo "DONE" ;;
    *) echo "FAILED" ;;
  esac
}

main() {
  if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <DATASET> <PLATFORM> [MAX_TURNS]" >&2
    exit 1
  fi
  local dataset="$1" platform="$2" max_turns="${3:-300}"

  local category_json
  category_json=$("$PYTHON_BIN" "$(dirname "$0")/non_niq_helper.py" categories --country ID \
    | jq -c --arg ds "$dataset" --arg pl "$platform" '.[] | select(.dataset == $ds and .ecommerce_platform == $pl)')
  if [[ -z "$category_json" ]]; then
    echo "No active config Sheet row for dataset=${dataset} platform=${platform}" >&2
    echo "QUEUE_SIGNAL: FAILED"
    exit 1
  fi

  local source_table qa_table dict_table filter_table_config product_id_dict
  source_table=$(echo "$category_json" | jq -r '.table')
  qa_table=$(echo "$category_json" | jq -r '.product_id_dict_qa')
  dict_table=$(echo "$category_json" | jq -r '.dict')
  filter_table_config=$(echo "$category_json" | jq -r '.filter_table')
  product_id_dict=$(echo "$category_json" | jq -r '.product_id_dict')
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

  local month
  month=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "$(default_month_query "$source_table")" | tail -1)

  local meili_index="${dataset}_taxonomy_qa"
  local query
  query=$(worklist_query "$source_table" "$qa_table" "$qa_pk_col" "$month" "$platform")

  local worklist_count
  worklist_count=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "SELECT COUNT(*) FROM ($query)" | tail -1)

  if [[ "$worklist_count" == "0" ]]; then
    echo "No in-scope worklist for ${dataset}/${platform}/${month} -- nothing to do."
    echo "QUEUE_SIGNAL: NOTHING_TO_DO"
    exit 0
  fi

  echo "${dataset}/${platform}, month=${month}, worklist_count=${worklist_count}"

  local prompt
  prompt=$(build_qa_prompt "$dataset" "$platform" "$source_table" "$qa_table" "$dict_table" \
    "$filter_table" "$qa_pk_col" "$dict_identity_col" "$dict_typo_col" "$meili_index" "$query" \
    "$product_id_dict")

  # `|| true` is load-bearing under `set -e`: a non-zero claude exit (turn-limit kill, transport
  # error) can still follow real BigQuery writes, and dying here would swallow the transcript that
  # says what was written. Echo it, then let decide_queue_signal return FAILED on unparseable output.
  local claude_output
  claude_output=$(claude -p --output-format json --permission-mode bypassPermissions --max-turns "$max_turns" "$prompt") || true
  echo "$claude_output"

  echo "QUEUE_SIGNAL: $(decide_queue_signal "$claude_output")"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
