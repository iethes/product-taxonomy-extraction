#!/usr/bin/env bash
set -euo pipefail

# Usage: ./script/qa_coverage_report.sh <master_table>
# Reports how many product_taxonomy entries for a table are NOT confidently reviewed yet — the exact
# _meta criteria targeted_qa_fix.sh's auto-discovery worklist uses (_meta IS NULL OR review_confidence !=
# 'confident'). Standalone-runnable for any table at any time; also called by targeted_qa_fix.sh at the end
# of every run via an EXIT trap, regardless of that run's outcome. See
# docs/superpowers/specs/2026-07-23-qa-fix-gate-direction-and-coverage-design.md.

TABLE="${1:?Usage: $0 <master_table>}"
PROJECT="sincere-hearth-273704"

echo "=== QA coverage: ${TABLE} ==="

bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
  "WITH distinct_entries AS (
     SELECT DISTINCT pt.taxonomy_id, pt._meta
     FROM \`${PROJECT}.magpie_reference.product_taxonomy\` pt
     JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
     WHERE m.master_table = '${TABLE}'
   )
   SELECT
     COUNT(*) AS total,
     COUNTIF(_meta IS NULL) AS never_reviewed,
     COUNTIF(_meta IS NOT NULL AND IFNULL(JSON_VALUE(_meta, '\$.review_confidence'), 'unreviewed') != 'confident') AS unconfident,
     COUNTIF(_meta IS NOT NULL AND JSON_VALUE(_meta, '\$.review_confidence') = 'confident') AS confident
   FROM distinct_entries" | tail -1 | \
while IFS=',' read -r total never_reviewed unconfident confident; do
  pending=$((never_reviewed + unconfident))
  pct=0
  [ "$total" -gt 0 ] && pct=$(( 100 * pending / total ))
  echo "Pending QA (never-reviewed or unconfident): ${pending} / ${total} (${pct}%)"
  echo "  never reviewed: ${never_reviewed}"
  echo "  unconfident:    ${unconfident}"
  echo "  confident:      ${confident}"
done
