#!/usr/bin/env bash
set -euo pipefail

# Usage: ./script/qa_report.sh <master_table> [--skip-coexistence]
# Runs all 4 QA gates from docs/headless-runbook.md § QA-gate-as-code and prints a full report —
# unlike run_qa_gates() (which aborts on the first failure, for gating a pipeline step), this always
# runs all 4 and reports every result, for standalone auditing of any table at any time.

TABLE="${1:?Usage: $0 <master_table> [--skip-coexistence]}"
SKIP_COEXISTENCE="${2:-}"
PROJECT="sincere-hearth-273704"
FAIL=0

echo "=== QA report: ${TABLE} ==="

DUAL_MAPPED=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
  "SELECT COUNT(*) FROM (
     SELECT product_id FROM \`${PROJECT}.magpie_reference.product_taxonomy_map\`
     WHERE master_table = '${TABLE}' AND source = 'LLM' GROUP BY product_id HAVING COUNT(*) > 1
   )" | tail -1)
if [ "$DUAL_MAPPED" = "0" ]; then echo "[PASS] dual-mapped (LLM):        0"
else echo "[FAIL] dual-mapped (LLM):        ${DUAL_MAPPED}"; FAIL=1; fi

if [ "$SKIP_COEXISTENCE" != "--skip-coexistence" ]; then
  COEXIST=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "SELECT COUNT(*) FROM (
       SELECT product_id FROM \`${PROJECT}.magpie_reference.product_taxonomy_map\`
       WHERE master_table = '${TABLE}'
       GROUP BY product_id HAVING COUNTIF(source='LLM') > 0 AND COUNTIF(source='HUMAN') > 0
     )" | tail -1)
  if [ "$COEXIST" = "0" ]; then echo "[PASS] HUMAN+LLM coexistence:    0"
  else echo "[FAIL] HUMAN+LLM coexistence:    ${COEXIST}"; FAIL=1; fi
else
  echo "[SKIP] HUMAN+LLM coexistence:    (--skip-coexistence passed)"
fi

PLACEHOLDER=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
  "SELECT COUNT(*) FROM \`${PROJECT}.magpie_reference.product_taxonomy\` pt
   JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
   WHERE m.master_table = '${TABLE}'
     AND REGEXP_CONTAINS(LOWER(pt.canonical_name), r'\b(undefined|null|n/a|tbd)\b')" | tail -1)
if [ "$PLACEHOLDER" = "0" ]; then echo "[PASS] placeholder-leak:         0"
else echo "[FAIL] placeholder-leak:         ${PLACEHOLDER}"; FAIL=1; fi

STRUCT_MISSING=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
  "SELECT CAST(ROUND(100 * COUNTIF(product_line IS NULL) / COUNT(*)) AS INT64)
   FROM (
     SELECT DISTINCT pt.taxonomy_id, pt.product_line, pt.is_multi_size
     FROM \`${PROJECT}.magpie_reference.product_taxonomy\` pt
     JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
     WHERE m.master_table = '${TABLE}' AND m.source = 'LLM'
   )
   WHERE is_multi_size IS NOT TRUE" | tail -1)
if [ -z "$STRUCT_MISSING" ]; then echo "[SKIP] structured-fields:        (no LLM entries for this table)"
elif [ "$STRUCT_MISSING" -le 50 ]; then echo "[PASS] structured-fields NULL%:  ${STRUCT_MISSING}%"
else echo "[FAIL] structured-fields NULL%:  ${STRUCT_MISSING}%"; FAIL=1; fi

echo "==============================="
if [ "$FAIL" = "0" ]; then echo "RESULT: all gates pass"; else echo "RESULT: one or more gates failed"; fi
exit "$FAIL"
