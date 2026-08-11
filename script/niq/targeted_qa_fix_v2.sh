#!/usr/bin/env bash
set -euo pipefail

# Usage: ./script/niq/targeted_qa_fix_v2.sh <TABLE> [BLOCK_SIZE] [MAX_TURNS]
# e.g.  ./script/niq/targeted_qa_fix_v2.sh shopee_th_detergent
#
# Auto-discovery only (no brief-mode branch -- that stays on script/niq/targeted_qa_fix.sh). The worklist --
# strict-tier GMV-sorted, Tier-1-flagged, candidate-enriched -- is fully pre-built by
# script/niq/qa_v2_worklist.py before claude -p is ever invoked, so this session's job is judgment-and-fix
# only, not discovery. See docs/superpowers/specs/2026-08-10-targeted-qa-fix-v2-design.md.

PROJECT="sincere-hearth-273704"

category_key_for() {
  local table="$1"
  echo "master_clean_niq.${table}"
}

qa_history_insert_query() {
  local category_key="$1"
  echo "INSERT INTO \`${PROJECT}.magpie_reference.category_brief\` (category_key, task_type, task_date, brief_markdown, updated_at, meta_agent) VALUES (@category_key, 'QA_HISTORY', @task_date, @brief_markdown, CURRENT_TIMESTAMP(), 'CLAUDE_CODE')"
}

insert_qa_history_row() {
  local category_key="$1" finding="$2" resolution="$3" task_date="$4"
  local note
  note=$(printf 'Finding: %s\nResolution: %s' "$finding" "$resolution")
  bq query --use_legacy_sql=false --project_id="${PROJECT}" \
    --parameter="category_key:STRING:${category_key}" \
    --parameter="task_date:DATE:${task_date}" \
    --parameter="brief_markdown:STRING:${note}" \
    "$(qa_history_insert_query "$category_key")"
}

extract_json_object() {
  local text="$1"
  printf '%s' "$text" | grep -Pzo '(?s)\{.*\}' | tr -d '\0'
}

decide_next_step() {
  local result_json="$1"
  local status rows_created
  if ! echo "$result_json" | jq -e . >/dev/null 2>&1; then
    local extracted
    extracted=$(extract_json_object "$result_json")
    if [[ -n "$extracted" ]] && echo "$extracted" | jq -e . >/dev/null 2>&1; then
      result_json="$extracted"
    fi
  fi
  status=$(echo "$result_json" | jq -r '.status // empty' 2>/dev/null) || status=""
  case "$status" in
    blocked)
      echo "BLOCKED"
      ;;
    failed)
      echo "MARK_FAILED"
      ;;
    complete|partial)
      rows_created=$(echo "$result_json" | jq -r '.rows_created // 0' 2>/dev/null) || rows_created="0"
      if [[ "$rows_created" =~ ^[0-9]+$ ]] && [[ "$rows_created" -gt 0 ]]; then
        echo "GATE_AND_REFRESH"
      else
        echo "NOOP"
      fi
      ;;
    *)
      echo "MARK_FAILED"
      ;;
  esac
}

mark_failed_qa() {
  local table="$1"
  echo "Marking most recent ACTIVE targeted_qa_fix_v2 block for ${table} as FAILED_QA..." >&2
  bq query --use_legacy_sql=false --project_id="${PROJECT}" \
    "UPDATE \`${PROJECT}.magpie_reference.sku_block_registry\`
     SET status = 'FAILED_QA'
     WHERE master_table = '${table}' AND scenario = 'targeted_qa_fix_v2' AND status = 'ACTIVE'
       AND claimed_at = (
         SELECT MAX(claimed_at) FROM \`${PROJECT}.magpie_reference.sku_block_registry\`
         WHERE master_table = '${table}' AND scenario = 'targeted_qa_fix_v2' AND status = 'ACTIVE'
       )"
}

run_universe_refresh() {
  local table="$1"
  echo "Running universe refresh for ${table}..."
  bq query --use_legacy_sql=false --project_id="${PROJECT}" \
    "MERGE \`${PROJECT}.magpie_reference.universe_taxonomy_overlay\` t
     USING (
       SELECT m.product_id, m.platform, m.country, m.master_table,
              pt.taxonomy_id, pt.canonical_name, m.source, m.confidence, m.meta_agent
       FROM \`${PROJECT}.magpie_reference.product_taxonomy_map\` m
       JOIN \`${PROJECT}.magpie_reference.product_taxonomy\` pt ON m.taxonomy_id = pt.taxonomy_id
       WHERE m.master_table = '${table}'
       QUALIFY ROW_NUMBER() OVER (
         PARTITION BY m.product_id, m.platform, m.country
         ORDER BY CASE m.source WHEN 'LLM' THEN 0 ELSE 1 END, m.taxonomy_id
       ) = 1
     ) src
     ON t.product_id = src.product_id AND t.platform = src.platform AND t.country = src.country
       AND t.master_table = '${table}'
     WHEN MATCHED THEN UPDATE SET
       taxonomy_id = src.taxonomy_id,
       sku_type_complete = src.canonical_name,
       taxonomy_source = src.source,
       taxonomy_confidence = src.confidence,
       taxonomy_meta_agent = src.meta_agent,
       updated_at = CURRENT_TIMESTAMP()
     WHEN NOT MATCHED BY SOURCE AND t.master_table = '${table}' THEN DELETE
     WHEN NOT MATCHED BY TARGET THEN INSERT
       (product_id, platform, country, master_table, taxonomy_id, sku_type_complete,
        taxonomy_source, taxonomy_confidence, taxonomy_meta_agent, updated_at)
       VALUES (src.product_id, src.platform, src.country, src.master_table, src.taxonomy_id, src.canonical_name,
               src.source, src.confidence, src.meta_agent, CURRENT_TIMESTAMP())"
}

build_auto_discovery_prompt_v2() {
  local table="$1"
  local category_key="$2"
  local worklist_json="$3"
  local block_size="${4:-200}"
  local slot_offset=$((block_size - 1))
  cat <<PROMPT
Targeted QA Fix V2 session for ${table}. This is a candidate-enriched, pre-built worklist -- unlike
script/niq/targeted_qa_fix.sh's auto-discovery mode, worklist discovery, the Tier-1 mechanical sweep, and
reference-candidate retrieval have already run in Python/SQL before this session started. See
docs/superpowers/specs/2026-08-10-targeted-qa-fix-v2-design.md for the full design.

BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/llm-extraction-rules.md,
docs/quality-standards.md, docs/brand-extraction.md, and the category brief -- run: SELECT brief_markdown FROM
\`${PROJECT}.magpie_reference.category_brief\` WHERE category_key = '${category_key}' AND task_type = 'BRIEF'.

You are a one-shot, non-interactive process -- do NOT use the Agent/Task tool, ScheduleWakeup, or any
background/async dispatch mechanism.

Your worklist for this session, in JSON, already ordered highest-priority first (every never-reviewed row
before any unconfident row, GMV descending within each tier -- never-reviewed rows before any unconfident row
regardless of relative GMV). Each row carries: tier1_flags (mechanical defects already detected by SQL regex --
you decide the correct fix, not whether the flag fired; a flag can still be a false positive, e.g.
"all variant/size" language on legitimately variant text), taxonomy_candidates (up to 5 same-brand
review_confidence='confident' entries, closest by edit distance -- reference/format context only, never assume
one is correct without checking sku_name/image yourself), brand_candidates (up to 3 similarly-named brand_dict
entries excluding this row's own brand -- for catching brand_id misattribution), and sample_sku_names (up to 3
real listing titles mapped to this taxonomy_id):

${worklist_json}

For every row: judge correct/wrong against docs/llm-extraction-rules.md and docs/quality-standards.md §3's
D1-D5 dimensions, using the pre-attached flags and candidates as a starting point, never as a verdict on their
own. Apply fixes directly via bq query DML.

STEP 4 (fix) -- prefer bulk SQL per defect class over one row at a time. Read a product's image only when the
fix itself requires re-deriving a value. Every row you change must have its _meta reset in the same session:
UPDATE \`${PROJECT}.magpie_reference.product_taxonomy\`
SET _meta = '{"is_reviewed": false}'
WHERE taxonomy_id IN (/* the taxonomy_ids you just fixed */)

STEP 5 -- promote reviewed rows' _meta using the same Path 1/Path 2 rules as script/niq/targeted_qa_fix.sh
(docs/superpowers/specs/2026-07-28-qa-fix-one-pass-confidence-design.md): a never-reviewed row you judge correct
AND that has no un-excepted Tier-1 flag promotes straight to 'confident'; a row you fixed this session that
comes back clean on an immediate Tier-1 recheck also promotes straight to 'confident'; every other row you
review gets its _meta updated by comparing this verdict against its stored prior verdict (agreement ->
confident, disagreement -> unconfident).

STEP 6 -- if a fix genuinely requires minting a new taxonomy entry, claim a ${block_size}-slot SKU block first
(DECLARE before BEGIN TRANSACTION -- reversing that order is a real BigQuery scripting syntax error):
BEGIN
  DECLARE next_start INT64;
  BEGIN TRANSACTION;
  SET next_start = (SELECT COALESCE(MAX(block_end), 69000) + 1 FROM \`${PROJECT}.magpie_reference.sku_block_registry\`);
  INSERT INTO \`${PROJECT}.magpie_reference.sku_block_registry\`
    (block_start, block_end, master_table, scenario, claimed_at, status)
  VALUES (next_start, next_start + ${slot_offset}, '${table}', 'targeted_qa_fix_v2', CURRENT_TIMESTAMP(), 'ACTIVE');
  COMMIT TRANSACTION;
END;
Most sessions fix existing entries in place and need no new SKU at all; only claim a block when you actually
mint one.

STEP 7 -- write via bq query DML only, never the streaming API. Set meta_agent='CLAUDE_CODE' on every row you
write or update. Never delete an existing row.

STEP 8 -- do NOT run the universe refresh yourself; that runs after this session, only if independent QA gates
pass.

STEP 9 -- do not write to \`${PROJECT}.magpie_reference.category_brief\` yourself. Instead, set the final JSON
output's qa_history_entry field to {finding: "...", resolution: "..."}; the wrapper inserts it as a QA_HISTORY
row on your behalf.

STEP 10 -- before declaring status, self-check the hard gates from docs/headless-runbook.md's QA-gate-as-code
section, WITHOUT --skip-coexistence (this category already shipped once -- coexistence is always a genuine bug
at this point). Report the actual numbers in findings.

STEP 11 -- if you hit a genuine blocker at any step, stop, write nothing further, and output status='blocked'
with the blockers array populated. That is a valid, expected outcome, not a failure.

Output ONLY this JSON when done, nothing else:
{status: complete|partial|failed|blocked, rows_created, rows_mapped, taxonomy_id_range_used, qa_history_entry: null|{finding, resolution}, findings, blockers}.
PROMPT
}

main() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <TABLE> [BLOCK_SIZE] [MAX_TURNS]" >&2
    echo "  e.g. $0 shopee_th_detergent            (defaults: BLOCK_SIZE=200, MAX_TURNS=300)" >&2
    exit 1
  fi
  local table="$1"
  local block_size="${2:-200}"
  local max_turns="${3:-300}"

  local category_key
  category_key=$(category_key_for "$table")

  QA_FIX_TABLE="$table"
  trap './script/niq/qa_coverage_report.sh "$QA_FIX_TABLE" || true' EXIT

  echo "Building candidate-enriched worklist for ${table}..."
  local worklist_json
  worklist_json=$(python3 script/niq/qa_v2_worklist.py --table "$table" --block-size "$block_size")

  if [[ "$worklist_json" == "[]" ]]; then
    echo "No unlabelled/unconfident taxonomy entries for ${table} after fast-lane promotion -- nothing to do."
    echo "QUEUE_SIGNAL: NOTHING_TO_DO"
    exit 0
  fi

  echo "TARGETED QA FIX V2 STARTED (${category_key}, block_size=${block_size}, max_turns=${max_turns})"
  echo "==========================="
  local prompt
  prompt=$(build_auto_discovery_prompt_v2 "$table" "$category_key" "$worklist_json" "$block_size")

  local claude_output
  # Piped via stdin, not passed as a CLI argument: this prompt embeds the full worklist JSON (candidates,
  # sample titles, etc. for up to $block_size rows) and can exceed the kernel's argv size limit (E2BIG,
  # "Argument list too long") well before it gets anywhere near a real token-budget concern.
  claude_output=$(claude -p --output-format json --permission-mode bypassPermissions --max-turns "$max_turns" <<< "$prompt")

  local result_json
  result_json=$(echo "$claude_output" | jq -r '.result // empty')

  if [[ -z "$result_json" ]]; then
    echo "ERROR: claude -p produced no parseable .result field. Raw output:" >&2
    echo "$claude_output" >&2
    mark_failed_qa "$table"
    exit 1
  fi

  if ! echo "$result_json" | jq -e . >/dev/null 2>&1; then
    local extracted
    extracted=$(extract_json_object "$result_json")
    if [[ -n "$extracted" ]] && echo "$extracted" | jq -e . >/dev/null 2>&1; then
      result_json="$extracted"
    fi
  fi

  local qa_finding qa_resolution
  qa_finding=$(echo "$result_json" | jq -r '.qa_history_entry.finding // empty')
  qa_resolution=$(echo "$result_json" | jq -r '.qa_history_entry.resolution // empty')
  if [[ -n "$qa_finding" ]]; then
    local qa_task_date
    qa_task_date=$(date -u +'%Y-%m-%d')
    insert_qa_history_row "$category_key" "$qa_finding" "$qa_resolution" "$qa_task_date"
    echo "Inserted QA_HISTORY row for ${category_key}."
  fi

  local decision
  decision=$(decide_next_step "$result_json")

  case "$decision" in
    BLOCKED)
      echo "STATUS: blocked. Claimed block left ACTIVE (nothing written) -- see blockers below."
      echo "$result_json" | jq -r '.blockers[]?' >&2
      echo "QUEUE_SIGNAL: BLOCKED"
      exit 0
      ;;
    NOOP)
      echo "STATUS: complete/partial with rows_created=0 -- nothing to gate or refresh. Block left ACTIVE."
      echo "QUEUE_SIGNAL: DONE"
      exit 0
      ;;
    MARK_FAILED)
      echo "STATUS: failed or malformed. Marking block FAILED_QA." >&2
      echo "$result_json" >&2
      mark_failed_qa "$table"
      echo "QUEUE_SIGNAL: FAILED"
      exit 1
      ;;
    GATE_AND_REFRESH)
      echo "STATUS: rows written -- running independent QA gates via script/niq/qa_report.sh..."
      if ./script/niq/qa_report.sh "$table"; then
        if run_universe_refresh "$table"; then
          echo "============================"
          echo "TARGETED QA FIX V2 FINISHED -- universe refreshed"
          echo "QUEUE_SIGNAL: DONE"
        else
          echo "Universe refresh failed -- marking block FAILED_QA." >&2
          mark_failed_qa "$table"
          echo "QUEUE_SIGNAL: FAILED"
          exit 1
        fi
      else
        echo "QA gates failed -- marking block FAILED_QA, skipping universe refresh." >&2
        mark_failed_qa "$table"
        echo "QUEUE_SIGNAL: FAILED"
        exit 1
      fi
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
