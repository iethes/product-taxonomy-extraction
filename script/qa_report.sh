#!/usr/bin/env bash
set -euo pipefail

# Usage: ./script/qa_report.sh <master_table> [--skip-coexistence]
# Runs the QA gates from docs/headless-runbook.md § QA-gate-as-code plus the canonical_name /
# duplicate-map checks from docs/llm-extraction-rules.md, and prints a full report —
# unlike run_qa_gates() (which aborts on the first failure, for gating a pipeline step), this always
# runs every gate and reports every result, for standalone auditing of any table at any time.

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
     AND REGEXP_CONTAINS(LOWER(pt.canonical_name), r'\b(undefined|null|n/a|tbd)\b')
     AND pt.taxonomy_id NOT IN (
       SELECT entity_id FROM \`${PROJECT}.magpie_reference.qa_gate_exceptions\`
       WHERE gate_name = 'placeholder-leak' AND master_table = '${TABLE}'
     )" | tail -1)
if [ "$PLACEHOLDER" = "0" ]; then echo "[PASS] placeholder-leak:         0"
else echo "[FAIL] placeholder-leak:         ${PLACEHOLDER}"; FAIL=1; fi

STRUCT_MISSING=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
  "SELECT CAST(ROUND(100 * COUNTIF(product_line IS NULL) / COUNT(*)) AS INT64)
   FROM (
     SELECT DISTINCT pt.taxonomy_id, pt.product_line, pt.is_multi_size
     FROM \`${PROJECT}.magpie_reference.product_taxonomy\` pt
     JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
     WHERE m.master_table = '${TABLE}' AND m.source = 'LLM'
       AND pt.taxonomy_id NOT IN (
         SELECT entity_id FROM \`${PROJECT}.magpie_reference.qa_gate_exceptions\`
         WHERE gate_name = 'structured-fields NULL%' AND master_table = '${TABLE}'
       )
   )
   WHERE is_multi_size IS NOT TRUE" | tail -1)
if [ -z "$STRUCT_MISSING" ]; then echo "[SKIP] structured-fields:        (no LLM entries for this table)"
elif [ "$STRUCT_MISSING" -le 50 ]; then echo "[PASS] structured-fields NULL%:  ${STRUCT_MISSING}%"
else echo "[FAIL] structured-fields NULL%:  ${STRUCT_MISSING}%"; FAIL=1; fi

DUP_PID=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
  "SELECT COUNT(*) FROM (
     SELECT product_id FROM \`${PROJECT}.magpie_reference.product_taxonomy_map\`
     WHERE master_table = '${TABLE}' GROUP BY product_id HAVING COUNT(*) > 1
   )" | tail -1)
if [ "$DUP_PID" = "0" ]; then echo "[PASS] duplicate product_id:     0"
else echo "[FAIL] duplicate product_id:     ${DUP_PID}"; FAIL=1; fi

DUP_PAIR=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
  "SELECT COUNT(*) FROM (
     SELECT product_id, taxonomy_id FROM \`${PROJECT}.magpie_reference.product_taxonomy_map\`
     WHERE master_table = '${TABLE}' GROUP BY product_id, taxonomy_id HAVING COUNT(*) > 1
   )" | tail -1)
if [ "$DUP_PAIR" = "0" ]; then echo "[PASS] duplicate product+taxon:  0"
else echo "[FAIL] duplicate product+taxon:  ${DUP_PAIR}"; FAIL=1; fi

# Requires "variant(s)"/"size(s)" to directly follow "(all" or "multiple" — not just any "(all ...)"
# parenthetical. The looser r'\(all[\s)]' pattern (used until 2026-07-21) false-positived on real product
# descriptors like "(All Skin Types)" or "(All Natural)", which are legitimate label text, not a
# generic-stub marker. "Multiple Sizes"/"Multiple Variants" added 2026-07-22: despite being sanctioned in
# an earlier th_softdrink precedent (paired with is_multi_size/is_multi_variant=TRUE), it's banned here
# unconditionally, flag or no flag — the is_multi_size/is_multi_variant column already conveys that
# semantic; redundantly restating it as generic text in canonical_name is the same ungrounded-stub problem
# as "All variant"/"All size". Existing entries using this text must be corrected to drop it, not exempted.
ALL_VARIANT=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
  "SELECT COUNT(*) FROM (
     SELECT DISTINCT pt.taxonomy_id
     FROM \`${PROJECT}.magpie_reference.product_taxonomy\` pt
     JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
     WHERE m.master_table = '${TABLE}'
       AND REGEXP_CONTAINS(LOWER(pt.canonical_name), r'\(all\s+(variants?|sizes?)\b|\bmultiple\s+(variants?|sizes?)\b')
       AND pt.taxonomy_id NOT IN (
         SELECT entity_id FROM \`${PROJECT}.magpie_reference.qa_gate_exceptions\`
         WHERE gate_name = 'all variant/size name' AND master_table = '${TABLE}'
       )
   )" | tail -1)
if [ "$ALL_VARIANT" = "0" ]; then echo "[PASS] 'all variant/size' name:   0"
else echo "[FAIL] 'all variant/size' name:   ${ALL_VARIANT}"; FAIL=1; fi

# canonical_name must contain product_line, sub_line, variant, size (when set), and xN (when pack_count>1)
# per docs/llm-extraction-rules.md §2/§3 — per-word match (not whole-phrase substring), since a size or
# variant clause is often inserted mid-name and splits product_line/sub_line into non-contiguous chunks
# (e.g. product_line "Milk + Rice Bath Refill" vs canonical_name "...Milk + Rice Bath 400ml Refill").
# Catch-all "(all ...)" entries are excluded here since they're already caught by the gate above and their
# sub_line often holds a slash-separated candidate list ("Sensitive / Whitening") not meant to appear verbatim.
CANON_FIELDS=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
  "SELECT COUNT(*) FROM (
     SELECT DISTINCT pt.taxonomy_id, pt.canonical_name, pt.product_line, pt.sub_line,
            pt.variant, pt.size, pt.pack_count
     FROM \`${PROJECT}.magpie_reference.product_taxonomy\` pt
     JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
     WHERE m.master_table = '${TABLE}'
   )
   WHERE (
       (SELECT LOGICAL_OR(LOWER(canonical_name) NOT LIKE CONCAT('%', w, '%'))
        FROM UNNEST(SPLIT(LOWER(product_line), ' ')) w WHERE w != '')
    OR (sub_line IS NOT NULL AND (SELECT LOGICAL_OR(LOWER(canonical_name) NOT LIKE CONCAT('%', w, '%'))
        FROM UNNEST(SPLIT(LOWER(sub_line), ' ')) w WHERE w != ''))
    OR (variant IS NOT NULL AND (SELECT LOGICAL_OR(LOWER(canonical_name) NOT LIKE CONCAT('%', w, '%'))
        FROM UNNEST(SPLIT(LOWER(variant), ' ')) w WHERE w != ''))
    OR (size IS NOT NULL AND NOT LOWER(canonical_name) LIKE CONCAT('%', LOWER(size), '%'))
    OR (pack_count > 1 AND NOT LOWER(canonical_name) LIKE CONCAT('%x', CAST(pack_count AS STRING), '%'))
   )
   AND NOT REGEXP_CONTAINS(LOWER(canonical_name), r'\(all\s+(variants?|sizes?)\b|\bmultiple\s+(variants?|sizes?)\b')
   AND taxonomy_id NOT IN (
     SELECT entity_id FROM \`${PROJECT}.magpie_reference.qa_gate_exceptions\`
     WHERE gate_name = 'canonical_name fields' AND master_table = '${TABLE}'
   )" | tail -1)
if [ "$CANON_FIELDS" = "0" ]; then echo "[PASS] canonical_name fields:    0"
else echo "[FAIL] canonical_name fields:    ${CANON_FIELDS}"; FAIL=1; fi

# Resolved brand (brand_dict.canonical_name via product_taxonomy.brand_id) contains no letters at all --
# catches garbled/anomalous brand text (e.g. "12/+＝", found via product 7155345414) without
# false-positiving on legitimate alphanumeric brands ("3M", "7-Eleven", "L'Oreal" all contain a letter).
# \p{L} matches any Unicode letter (Latin, Thai, etc.) -- verify this is supported by BigQuery's RE2 engine
# with a live test query before the first real run touches this gate; if it errors instead of returning a
# boolean, fall back to an explicit range like r'[a-zA-Zก-ฮ]'.
GARBAGE_BRAND=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
  "SELECT COUNT(*) FROM (
     SELECT DISTINCT pt.taxonomy_id
     FROM \`${PROJECT}.magpie_reference.product_taxonomy\` pt
     JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
     JOIN \`${PROJECT}.magpie_reference.brand_dict\` bd ON bd.brand_id = pt.brand_id
     WHERE m.master_table = '${TABLE}'
       AND NOT REGEXP_CONTAINS(bd.canonical_name, r'[\p{L}]')
       AND bd.brand_id NOT IN (
         SELECT entity_id FROM \`${PROJECT}.magpie_reference.qa_gate_exceptions\`
         WHERE gate_name = 'garbled brand text' AND master_table = '${TABLE}'
       )
   )" | tail -1)
if [ "$GARBAGE_BRAND" = "0" ]; then echo "[PASS] garbled brand text:       0"
else echo "[FAIL] garbled brand text:       ${GARBAGE_BRAND}"; FAIL=1; fi

echo "==============================="
if [ "$FAIL" = "0" ]; then echo "RESULT: all gates pass"; else echo "RESULT: one or more gates failed"; fi
exit "$FAIL"
