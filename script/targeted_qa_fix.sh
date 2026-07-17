#!/usr/bin/env bash
set -euo pipefail

# Usage: ./script/targeted_qa_fix.sh <TABLE>
# e.g.  ./script/targeted_qa_fix.sh shopee_th_detergent
#
# Runs the "Scenario: Targeted QA Fix" procedure from docs/headless-runbook.md: claim a small SKU
# block, run claude -p against the fix brief in docs/categories/<table>.md's '## Targeted QA Fix
# Brief' section, then independently re-verify via script/qa_report.sh before refreshing the
# universe overlay. Never trusts the agent's own self-report to gate a production write.
#
# See docs/superpowers/specs/2026-07-17-targeted-qa-fix-script-design.md for the full design.

PROJECT="sincere-hearth-273704"

resolve_category_file() {
  local table="$1"
  local candidate="docs/categories/${table}.md"
  if [[ -f "$candidate" ]]; then
    echo "$candidate"
    return 0
  fi
  local stripped="${table#shopee_}"
  candidate="docs/categories/${stripped}.md"
  if [[ -f "$candidate" ]]; then
    echo "$candidate"
    return 0
  fi
  return 1
}

build_prompt() {
  local table="$1"
  local category_file="$2"
  cat <<PROMPT
Targeted QA Fix session for ${table}.

BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/llm-extraction-rules.md, docs/headless-runbook.md, docs/quality-standards.md, and ${category_file} (your fix brief lives in that file's '## Targeted QA Fix Brief' section — read it in full, it is the specific work for this session, not background).

If ${category_file} has no '## Targeted QA Fix Brief' section, or the section has no concrete fixes to perform, that is a genuine blocker: stop, write nothing, output status='blocked'.

You perform every fix yourself, directly, using your own multimodal reading of product images and text where the brief calls for it. You do not invoke external scripts or subprocesses and do not need any API key beyond your own session auth — CLAUDE.md's ANTHROPIC_API_KEY note is about a different, external pipeline that does not exist in this repo.

STEP 1 — Sanity-check the brief's stated current-state numbers against a live query before trusting them:
Run: SELECT source, COUNT(*) FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy_map\` WHERE master_table = '${table}' GROUP BY source
If the live counts disagree with what the brief claims, record the discrepancy in findings — do not silently proceed as if the brief were current.

STEP 2 — Claim a 200-slot SKU block atomically (DECLARE before BEGIN TRANSACTION — reversing that order is a real BigQuery scripting syntax error):
BEGIN
  DECLARE next_start INT64;
  BEGIN TRANSACTION;
  SET next_start = (SELECT COALESCE(MAX(block_end), 69000) + 1 FROM \`sincere-hearth-273704.magpie_reference.sku_block_registry\`);
  INSERT INTO \`sincere-hearth-273704.magpie_reference.sku_block_registry\`
    (block_start, block_end, master_table, scenario, claimed_at, status)
  VALUES (next_start, next_start + 199, '${table}', 'targeted_qa_fix', CURRENT_TIMESTAMP(), 'ACTIVE');
  COMMIT TRANSACTION;
END;
Never query MAX(taxonomy_id) directly and assume it's safe to use — this atomic claim against the registry table is what prevents two sessions colliding on the same ID range.

STEP 3 — Execute exactly the fixes described in ${category_file}'s '## Targeted QA Fix Brief' section: pack-count / size / bundle corrections, the NULL-coverage pass, whatever that section specifies. That section is the actual scope of this session — this prompt does not restate it.

STEP 4 — Write via bq query DML only, never the streaming API. Set meta_agent='CLAUDE_CODE' on every row you write. Never delete an existing row unless the brief explicitly instructs you to.

STEP 5 — Do NOT run the universe refresh yourself. That step runs after this session, only if independent QA gates pass — it is not something you do.

STEP 6 — Append a dated row to ${category_file}'s '## QA History' table (columns: Date | Pass | Finding | Resolution) summarizing what you did and found this session. Commit the updated file:
git add ${category_file} && git commit -m 'Targeted QA Fix session for ${table}: update QA History'

STEP 7 — If you hit a genuine blocker at any step — something wrong with these instructions, missing data, anything that would make proceeding unsafe — stop, write nothing further, and output status='blocked' with the blockers array populated. That is a valid, expected outcome, not a failure.

Output ONLY this JSON when done, nothing else:
{status: complete|partial|failed|blocked, rows_created, rows_mapped, taxonomy_id_range_used, findings, blockers}.
PROMPT
}

decide_next_step() {
  local result_json="$1"
  local status rows_created
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

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "script/targeted_qa_fix.sh: main() not wired up yet (Task 3)." >&2
  exit 1
fi
