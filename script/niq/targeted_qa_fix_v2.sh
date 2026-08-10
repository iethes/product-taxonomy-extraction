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
