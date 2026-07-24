# Bundle Gate Fix + Fast-Lane Recheck Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix a genuine gate false positive on multi-item bundles (blocking universe refresh every run on
categories with bundle products) and add a cheap SQL-only fast lane that confirms already-fixed rows without
competing for Tier 2's expensive judgment budget.

**Architecture:** Two independent, surgical changes to existing bash/BigQuery scripts. (1) Add an
`is_bundle IS NOT TRUE` guard to the pack_count/xN check in both `qa_report.sh`'s gate query and
`targeted_qa_fix.sh`'s mirroring Tier 1 sweep query. (2) Insert a new STEP 1C into
`build_auto_discovery_prompt` that reruns the existing Tier 1 sweep scoped to `fixed_pending_recheck` rows
and bulk-promotes any that come back clean, reusing STEP 5's exact promotion SQL; STEP 3 is updated to
exclude whatever STEP 1C already resolved.

**Tech Stack:** bash (`set -euo pipefail`), BigQuery (`bq query --use_legacy_sql=false`).

## Global Constraints

- BigQuery project: `sincere-hearth-273704`. Reference dataset: `magpie_reference`.
- Companion spec: [`docs/superpowers/specs/2026-07-24-qa-fix-bundle-gate-and-fastlane-design.md`](../specs/2026-07-24-qa-fix-bundle-gate-and-fastlane-design.md).
- Test convention: `script/test_targeted_qa_fix.sh` sources `script/targeted_qa_fix.sh` and asserts via
  `grep ... <<< "$var"` (here-strings, not `echo | grep` — that pattern was fixed for flakiness in the prior
  cycle; do not reintroduce `echo "$x" | grep`). `qa_report.sh` has no pure functions and carries a standing
  exemption from unit tests — syntax check + one real manual run against a live table is the precedent.
- Every `_meta` write remains a plain JSON string (never `TO_JSON()`/JSON literal prefix), per existing
  convention throughout this script.

---

### Task 1: Bundle-naming gate fix (`is_bundle` guard)

**Files:**
- Modify: `script/qa_report.sh:112-134` (the `CANON_FIELDS` query)
- Modify: `script/targeted_qa_fix.sh` (inside `build_auto_discovery_prompt`'s STEP 2 Tier 1 sweep query)
- Test: `script/test_targeted_qa_fix.sh`

**Interfaces:** none — this only changes SQL text inside existing query strings, no function signatures
change.

- [ ] **Step 1: Write the failing test**

Add to `script/test_targeted_qa_fix.sh`, inside the existing "build_auto_discovery_prompt" test block (find
the line `grep -qF "r'[\p{L}]'" <<< "$prompt" || fail "build_auto_discovery_prompt's Tier 1 sweep must add the garbage_brand check"` and add immediately after it):

```bash
grep -qF "pt.is_bundle IS NOT TRUE" <<< "$prompt" || fail "build_auto_discovery_prompt's canonical_field_mismatch check must exempt is_bundle=true rows from the literal-xN requirement"
```

- [ ] **Step 2: Run the test suite to confirm it fails**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: `FAIL: build_auto_discovery_prompt's canonical_field_mismatch check must exempt is_bundle=true rows from the literal-xN requirement`

- [ ] **Step 3: Fix `qa_report.sh`'s `CANON_FIELDS` query**

Replace:
```sql
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
```
with:
```sql
     SELECT DISTINCT pt.taxonomy_id, pt.canonical_name, pt.product_line, pt.sub_line,
            pt.variant, pt.size, pt.pack_count, pt.is_bundle
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
    OR (pack_count > 1 AND is_bundle IS NOT TRUE AND NOT LOWER(canonical_name) LIKE CONCAT('%x', CAST(pack_count AS STRING), '%'))
   )
```

- [ ] **Step 4: Fix `build_auto_discovery_prompt`'s Tier 1 sweep query**

Replace:
```sql
    OR (pt.pack_count > 1 AND NOT LOWER(pt.canonical_name) LIKE CONCAT('%x', CAST(pt.pack_count AS STRING), '%'))
  ) AND NOT REGEXP_CONTAINS(LOWER(pt.canonical_name), r'\(all\s+(variants?|sizes?)\b|\bmultiple\s+(variants?|sizes?)\b') AS canonical_field_mismatch,
  (pt.size IS NULL AND pt.is_multi_size IS NOT TRUE) AS null_size,
  NOT REGEXP_CONTAINS(bd.canonical_name, r'[\p{L}]') AS garbage_brand
FROM \`${PROJECT}.magpie_reference.product_taxonomy\` pt
JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
JOIN \`${PROJECT}.magpie_reference.brand_dict\` bd ON bd.brand_id = pt.brand_id
WHERE m.master_table = '${table}'
  AND (pt._meta IS NULL OR IFNULL(JSON_VALUE(pt._meta, '$.review_confidence'), 'unreviewed') != 'confident')
GROUP BY 1,2,3,pt.product_line,pt.sub_line,pt.variant,pt.size,pt.pack_count,pt.is_multi_size
Every TRUE flag here is an automatic last_verdict='wrong' candidate — no LLM judgment needed to detect these,
```
with:
```sql
    OR (pt.pack_count > 1 AND pt.is_bundle IS NOT TRUE AND NOT LOWER(pt.canonical_name) LIKE CONCAT('%x', CAST(pt.pack_count AS STRING), '%'))
  ) AND NOT REGEXP_CONTAINS(LOWER(pt.canonical_name), r'\(all\s+(variants?|sizes?)\b|\bmultiple\s+(variants?|sizes?)\b') AS canonical_field_mismatch,
  (pt.size IS NULL AND pt.is_multi_size IS NOT TRUE) AS null_size,
  NOT REGEXP_CONTAINS(bd.canonical_name, r'[\p{L}]') AS garbage_brand
FROM \`${PROJECT}.magpie_reference.product_taxonomy\` pt
JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
JOIN \`${PROJECT}.magpie_reference.brand_dict\` bd ON bd.brand_id = pt.brand_id
WHERE m.master_table = '${table}'
  AND (pt._meta IS NULL OR IFNULL(JSON_VALUE(pt._meta, '$.review_confidence'), 'unreviewed') != 'confident')
GROUP BY 1,2,3,pt.product_line,pt.sub_line,pt.variant,pt.size,pt.pack_count,pt.is_multi_size,pt.is_bundle
Every TRUE flag here is an automatic last_verdict='wrong' candidate — no LLM judgment needed to detect these,
```

- [ ] **Step 5: Syntax check**

Run: `bash -n script/qa_report.sh && bash -n script/targeted_qa_fix.sh && echo OK`
Expected: `OK`

- [ ] **Step 6: Run the test suite to confirm the new assertion passes**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: `ALL TESTS PASSED`

- [ ] **Step 7: Structural check on `qa_report.sh`**

Run:
```bash
grep -A 20 "CANON_FIELDS=" script/qa_report.sh | grep -qF "is_bundle IS NOT TRUE" && echo "found" || echo "MISSING"
```
Expected: `found`

- [ ] **Step 8: Manual verification against a live table with a known bundle false positive**

Run:
```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=csv \
"SELECT COUNT(*) FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy\` pt
 JOIN \`sincere-hearth-273704.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
 WHERE m.master_table = 'shopee_sg_facial_cleanser' AND pt.pack_count > 1 AND pt.is_bundle = true
   AND NOT LOWER(pt.canonical_name) LIKE CONCAT('%x', CAST(pt.pack_count AS STRING), '%')"
```
Note the count (the number of bundle rows currently mis-flagged), then run:
```bash
./script/qa_report.sh shopee_sg_facial_cleanser
```
Expected: `canonical_name fields`'s failing count is at least that many lower than the pre-fix count from the
session log (2-7, depending on which run it's compared against) — confirm via the two counts, not just that
the gate shows `[PASS]` (other, unrelated `canonical_name fields` defects may still exist independently).

- [ ] **Step 9: Commit**

```bash
git add script/qa_report.sh script/targeted_qa_fix.sh script/test_targeted_qa_fix.sh
git commit -m "Add is_bundle IS NOT TRUE guard to the canonical_name-fields/canonical_field_mismatch pack_count check"
```

---

### Task 2: Fast-lane recheck for `fixed_pending_recheck` rows (new STEP 1C)

**Files:**
- Modify: `script/targeted_qa_fix.sh` (inside `build_auto_discovery_prompt`, insert STEP 1C between STEP 1B
  and STEP 2; update STEP 3's opening text)
- Test: `script/test_targeted_qa_fix.sh`

**Interfaces:** none — this only changes prompt text, no function signatures change. Depends on Task 1's
`pt.is_bundle IS NOT TRUE` guard already being in STEP 2's query (STEP 1C's SQL below already includes it,
matching STEP 2's post-Task-1 state) — do this task after Task 1, not before.

- [ ] **Step 1: Write the failing test**

Add to `script/test_targeted_qa_fix.sh`, inside the existing "build_auto_discovery_prompt: gate_report
parameter (STEP 1B, fix-direction)" test block (after its existing assertions, before its
`echo "PASS: build_auto_discovery_prompt gate_report (STEP 1B)"` line):

```bash
grep -qF "STEP 1C — Fast-lane recheck" <<< "$prompt" || fail "build_auto_discovery_prompt must add a STEP 1C fast-lane recheck for fixed_pending_recheck rows"
grep -qF "JSON_VALUE(_meta, '\$.review_confidence') IS NULL" <<< "$prompt" || fail "STEP 1C must scope its sweep to the fixed_pending_recheck predicate"
grep -qF "no Tier 2 sample slot spent" <<< "$prompt" || fail "STEP 1C must bulk-promote clean rows without spending Tier 2 judgment"
grep -qF "STEP 1C already bulk-promoted" <<< "$prompt" || fail "STEP 3 must exclude rows STEP 1C already resolved"
```

- [ ] **Step 2: Run the test suite to confirm it fails**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: `FAIL: build_auto_discovery_prompt must add a STEP 1C fast-lane recheck for fixed_pending_recheck rows`

- [ ] **Step 3: Insert STEP 1C between STEP 1B and STEP 2**

Find this exact text (the end of STEP 1B, immediately before STEP 2's heading):
```
For any FAILing gate in this list instead — dual-mapped (LLM), HUMAN+LLM coexistence, duplicate product_id,
duplicate product+taxon — do NOT attempt a fix: every one of these can only be resolved by deleting or
re-mapping a product_taxonomy_map row, and this session never deletes an existing row (STEP 7). Record the
gate name and count in findings instead, flagged as needing a deletion-authorized session. Note also: the
post-fix independent qa_report.sh re-check (STEP 10) re-runs these same gates — if one is failing here, it
will fail there too regardless of how well this session's fixes go, so a FAILED_QA outcome driven by a gate
this session was never able to touch is expected, not a sign the session did anything wrong.

STEP 2 — Tier 1: run this SQL sweep over that same worklist to flag mechanical defects cheaply, before
```
Replace it with:
```
For any FAILing gate in this list instead — dual-mapped (LLM), HUMAN+LLM coexistence, duplicate product_id,
duplicate product+taxon — do NOT attempt a fix: every one of these can only be resolved by deleting or
re-mapping a product_taxonomy_map row, and this session never deletes an existing row (STEP 7). Record the
gate name and count in findings instead, flagged as needing a deletion-authorized session. Note also: the
post-fix independent qa_report.sh re-check (STEP 10) re-runs these same gates — if one is failing here, it
will fail there too regardless of how well this session's fixes go, so a FAILED_QA outcome driven by a gate
this session was never able to touch is expected, not a sign the session did anything wrong.

STEP 1C — Fast-lane recheck: before spending any Tier 2 judgment, resolve rows that were already fixed in a
prior session and are only waiting on one more clean confirmation to become confident — identifiable as
_meta IS NOT NULL AND JSON_VALUE(_meta, '$.review_confidence') IS NULL (the "fixed pending recheck" bucket
qa_coverage_report.sh reports separately from "unconfident"). Run the exact same Tier 1 SQL sweep as STEP 2
below, scoped to just this subset:
SELECT pt.taxonomy_id, pt.canonical_name, bd.canonical_name AS brand,
  REGEXP_CONTAINS(LOWER(pt.canonical_name), r'\b(undefined|null|n/a|tbd|all variants?|all sizes?|multiple variants?|multiple sizes?)\b') AS stub_leak,
  (LENGTH(pt.canonical_name) - LENGTH(REPLACE(pt.canonical_name, bd.canonical_name, ''))) / GREATEST(LENGTH(bd.canonical_name),1) >= 2 AS duplicate_brand,
  NOT STARTS_WITH(LOWER(TRIM(pt.canonical_name)), LOWER(bd.canonical_name)) AS wrong_field_order,
  (STARTS_WITH(LOWER(pt.canonical_name), LOWER(bd.canonical_name)) AND NOT STARTS_WITH(pt.canonical_name, bd.canonical_name)) AS brand_casing_mismatch,
  (ARRAY_LENGTH(REGEXP_EXTRACT_ALL(pt.canonical_name, r'\d+\s*(?:ml|g|kg|l|L)\b')) > 1 OR ARRAY_LENGTH(REGEXP_EXTRACT_ALL(pt.canonical_name, r'x\d+\b')) > 1) AS excess_content,
  (
    (SELECT LOGICAL_OR(LOWER(pt.canonical_name) NOT LIKE CONCAT('%', w, '%'))
     FROM UNNEST(SPLIT(LOWER(pt.product_line), ' ')) w WHERE w != '')
    OR (pt.sub_line IS NOT NULL AND (SELECT LOGICAL_OR(LOWER(pt.canonical_name) NOT LIKE CONCAT('%', w, '%'))
        FROM UNNEST(SPLIT(LOWER(pt.sub_line), ' ')) w WHERE w != ''))
    OR (pt.variant IS NOT NULL AND (SELECT LOGICAL_OR(LOWER(pt.canonical_name) NOT LIKE CONCAT('%', w, '%'))
        FROM UNNEST(SPLIT(LOWER(pt.variant), ' ')) w WHERE w != ''))
    OR (pt.size IS NOT NULL AND NOT LOWER(pt.canonical_name) LIKE CONCAT('%', LOWER(pt.size), '%'))
    OR (pt.pack_count > 1 AND pt.is_bundle IS NOT TRUE AND NOT LOWER(pt.canonical_name) LIKE CONCAT('%x', CAST(pt.pack_count AS STRING), '%'))
  ) AND NOT REGEXP_CONTAINS(LOWER(pt.canonical_name), r'\(all\s+(variants?|sizes?)\b|\bmultiple\s+(variants?|sizes?)\b') AS canonical_field_mismatch,
  (pt.size IS NULL AND pt.is_multi_size IS NOT TRUE) AS null_size,
  NOT REGEXP_CONTAINS(bd.canonical_name, r'[\p{L}]') AS garbage_brand
FROM \`${PROJECT}.magpie_reference.product_taxonomy\` pt
JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
JOIN \`${PROJECT}.magpie_reference.brand_dict\` bd ON bd.brand_id = pt.brand_id
WHERE m.master_table = '${table}'
  AND pt._meta IS NOT NULL AND JSON_VALUE(pt._meta, '$.review_confidence') IS NULL
GROUP BY 1,2,3,pt.product_line,pt.sub_line,pt.variant,pt.size,pt.pack_count,pt.is_multi_size,pt.is_bundle

For every row where every flag above comes back FALSE, bulk-promote it directly — no LLM judgment, no image
read, no Tier 2 sample slot spent — using the exact same promotion logic as STEP 5:
UPDATE \`${PROJECT}.magpie_reference.product_taxonomy\` pt
SET _meta = TO_JSON_STRING(STRUCT(
  true AS is_reviewed,
  CURRENT_TIMESTAMP() AS last_reviewed_at,
  IF(JSON_VALUE(pt._meta, '$.last_verdict') = 'correct', 'confident', 'unconfident') AS review_confidence,
  'correct' AS last_verdict
))
WHERE pt.taxonomy_id IN ('SKU-XXXXXX', /* every fixed_pending_recheck row that came back Tier-1-clean this pass */)

Any row where a flag still trips is a regression or an incomplete prior fix, not a clean confirmation — leave
its _meta untouched here (STEP 2's worklist-wide sweep will flag it again the normal way, and it flows into
STEP 4's real fix path like any other flagged row). Do not spend Tier 2 judgment on a row this step already
promoted — STEP 3 below excludes it.

STEP 2 — Tier 1: run this SQL sweep over that same worklist to flag mechanical defects cheaply, before
```

- [ ] **Step 4: Update STEP 3's opening text to exclude STEP 1C's resolved rows**

Replace:
```
STEP 3 — Tier 2: a bounded, GMV-prioritized sample only, not every un-flagged row. Order the rows Tier 1
didn't flag by GMV (join master_clean_niq for gmv_monthly) and judge the top slice your remaining turn budget
allows against docs/llm-extraction-rules.md in full (product_line §3, size §2, the new §11 signal-provenance
and size-cross-validation rules) and docs/quality-standards.md §3's D1-D5 dimensions. This is the one script in
this pipeline where per-entry LLM judgment is the right tool, not a shortcut to avoid — precision is this script's job, not headless_taxonomy.sh's.
```
with:
```
STEP 3 — Tier 2: a bounded, GMV-prioritized sample only, not every un-flagged row. Order the rows Tier 1
didn't flag by GMV (join master_clean_niq for gmv_monthly) and judge the top slice your remaining turn budget
allows against docs/llm-extraction-rules.md in full (product_line §3, size §2, the new §11 signal-provenance
and size-cross-validation rules) and docs/quality-standards.md §3's D1-D5 dimensions. This is the one script in
this pipeline where per-entry LLM judgment is the right tool, not a shortcut to avoid — precision is this script's job, not headless_taxonomy.sh's. Exclude any taxonomy_id STEP 1C already bulk-promoted this
session — they're resolved, don't spend judgment budget re-confirming them.
```

- [ ] **Step 5: Syntax check**

Run: `bash -n script/targeted_qa_fix.sh && echo OK`
Expected: `OK`

- [ ] **Step 6: Run the test suite to confirm it passes**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: `ALL TESTS PASSED`

- [ ] **Step 7: Commit**

```bash
git add script/targeted_qa_fix.sh script/test_targeted_qa_fix.sh
git commit -m "build_auto_discovery_prompt: add STEP 1C fast-lane recheck for fixed_pending_recheck rows, bypassing Tier 2 competition"
```

---

## Plan self-review notes

- **Spec coverage:** Design section 1 (bundle gate fix, both queries) → Task 1. Design section 2 (STEP 1C
  fast lane + STEP 3 exclusion) → Task 2. Both design sections have a task; no gaps.
- **Type consistency:** STEP 1C's SQL in Task 2 already includes `pt.is_bundle IS NOT TRUE` and
  `pt.is_bundle` in its `GROUP BY`, matching what Task 1 leaves STEP 2's query looking like — Task 2 depends
  on Task 1 landing first, called out explicitly in Task 2's Interfaces section.
- **No placeholders:** every SQL/bash block above is complete, copy-pasteable text. The `'SKU-XXXXXX', /* ... */`
  inside STEP 1C's `UPDATE` is intentional prompt-instruction text for the LLM to fill in at runtime — the
  exact same style STEP 5's existing `UPDATE` already uses in this file, not an unfinished plan step.
