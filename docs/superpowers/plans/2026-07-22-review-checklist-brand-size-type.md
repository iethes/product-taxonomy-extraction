# Review Checklist Round 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three new automated checks to the taxonomy review loop (D4 size coverage, garbled/anomalous
brand detection, and sharper Tier 2 type-conflict judgment) plus fix-guidance for a brand_id/canonical_name
mismatch the existing `wrong_field_order` flag already catches but mislabels.

**Architecture:** Two new Tier 1 SQL flags (`null_size`, `garbage_brand`) join the existing 7-flag sweep in
`script/targeted_qa_fix.sh`'s `build_auto_discovery_prompt`. `garbage_brand` also becomes a `qa_report.sh` hard
gate (deterministic, zero-tolerance); `null_size` does not (D-dimension score, not a G-gate, matching the
existing precedent). STEP 3/STEP 4 prose gets extended, no new functions.

**Tech Stack:** Bash (`set -euo pipefail`), `bq` CLI (BigQuery `REGEXP_CONTAINS` with `\p{L}` Unicode
property class), `claude -p --output-format json`.

## Global Constraints

- BigQuery project: `sincere-hearth-273704`.
- Every write to `product_taxonomy`/`product_taxonomy_map` is DML, never the streaming API.
- Every touched row gets `meta_agent='CLAUDE_CODE'`.
- Any row whose `product_line`/`size`/`pack_count`/`canonical_name` (or, per Task 3, `brand_id`) is changed
  by a fix must have its `_meta` reset to `{"is_reviewed": false}` in the same session (`_meta` is
  `STRING`-typed — always a plain string, never the `JSON '...'` literal or `TO_JSON()`).
- D-dimension checks (D1–D6, scores with targets) do not become `qa_report.sh` hard gates; only
  deterministic, zero-tolerance defects do (matches the existing precedent: `structured-fields NULL%` uses a
  50% threshold, not zero, and D5's pack-count-promo check was deliberately kept out of `qa_report.sh` in the
  prior round for the same reason).
- No changes to `headless_taxonomy.sh` — both its prompts already read `docs/llm-extraction-rules.md` in
  full, so the new §11 rule (Task 1) reaches it automatically.

---

### Task 1: Add the seller-watermark rule and D4 cross-reference to the docs

**Files:**
- Modify: `docs/llm-extraction-rules.md` (new §11 rule + changelog row)
- Modify: `docs/quality-standards.md` (D4 cross-reference note)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: the rule text Task 3's `garbage_brand` fix-guidance references by name ("§11").

- [ ] **Step 1: Add the new §11 rule**

In `docs/llm-extraction-rules.md`, find:

```markdown
**Cross-validate short or ambiguous size matches before accepting them.** A size extracted from `sku_name`
that is 1-2 digits + unit, or that sits inside what reads as a brand/product-line token rather than being
clearly delimited (e.g., a brand like "G2G"/"Glad2Glow" contains digits a naive scan could misread as a size
"2g"), must be confirmed against `product_specification` or the image before being accepted. If the
`sku_name`-derived size doesn't independently confirm, prefer the confirmed source over the naive text match.

---

## Changelog
```

Replace with:

```markdown
**Cross-validate short or ambiguous size matches before accepting them.** A size extracted from `sku_name`
that is 1-2 digits + unit, or that sits inside what reads as a brand/product-line token rather than being
clearly delimited (e.g., a brand like "G2G"/"Glad2Glow" contains digits a naive scan could misread as a size
"2g"), must be confirmed against `product_specification` or the image before being accepted. If the
`sku_name`-derived size doesn't independently confirm, prefer the confirmed source over the naive text match.

**A reseller's own watermark, logo overlay, or store-branding stamp on a product photo is never the
product's brand, regardless of how large or prominent it is in the frame relative to the actual packaging
text.** Only text/logo that is part of the original product packaging design counts as a brand signal. If
the packaging's own brand text is small, partially obscured, or ambiguous, prefer `sku_name` or
`product_specification` over guessing from a prominent overlay — never resolve a brand from the most
visually dominant text in the image without confirming it's actually printed on the product itself.

---

## Changelog
```

- [ ] **Step 2: Add a changelog row**

In `docs/llm-extraction-rules.md`, find the last row of the `## Changelog` table:

```markdown
| Jul 22 2026 | universal | **"Multiple Sizes"/"Multiple Variants" banned unconditionally, superseding the th_softdrink precedent above.** That precedent sanctioned this phrasing when paired with `is_multi_size=TRUE`/`is_multi_variant=TRUE`; corrected same-day after review — the flag column already conveys that semantic, so the text is the same ungrounded-stub defect as "All variant"/"All size" regardless of whether the flag is set. Existing entries using this phrasing (including any from the th_softdrink category) need correcting, not exempting. Also: `docs/quality-standards.md`'s D5 pack-count-mismatch query never actually checked for English "buy N get M" phrasing despite this doc's own §1 table listing "buy 1 get 1" as pack_count=2 — found via product `16254994627`, whose "Buy 1 Get 1" sku_name text was missed because only Thai patterns and the digit form `1\+1` were in the regex. Fixed the regex (also added `LOWER()` — sku_name casing varies and the pattern is case-sensitive without it) and operationalized both checks into `script/targeted_qa_fix.sh`'s Tier 1 sweep, which had never actually run either check before (D5's query existed only as a manual snippet in quality-standards.md). |
```

Add a new row directly after it:

```markdown
| Jul 22 2026 | universal | **§11 extended: seller watermark is never the brand.** Found via product `7155345414`, resolved brand `"12/+＝"` — stakeholder diagnosis: a reseller's own watermark/logo was visually larger than the actual packaging brand text and got misread as the brand. Never resolve brand from the most visually dominant text in a photo without confirming it's printed on the product itself. |
```

- [ ] **Step 3: Add the D4 cross-reference note**

In `docs/quality-standards.md`, the target region currently reads exactly:

````markdown
### D4 — Size Coverage

```sql
-- In-scope LLM entries with NULL size that are NOT legitimately multi-size
SELECT pt.taxonomy_id, pt.canonical_name, SUM(u.gmv_monthly) gmv
FROM in_scope s
JOIN `sincere-hearth-273704.magpie.marketshare_universe` u USING (product_id, master_table)
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt ON u.taxonomy_id = pt.taxonomy_id
WHERE u.month = '2026-04-01' AND pt.size IS NULL AND pt.is_multi_size IS NOT TRUE
GROUP BY 1,2 ORDER BY gmv DESC;
```
````

(the fence above is 4 backticks purely so this plan can quote a block that itself contains a real 3-backtick
fence — use the literal 3-backtick fence when matching/writing the real file.)

`old_string` = everything from `### D4 — Size Coverage` through the closing ` ``` ` (inclusive).
`new_string` = the same content with one new paragraph inserted between the heading and the SQL fence — the
closing fence must stay exactly where it is, immediately after `GROUP BY 1,2 ORDER BY gmv DESC;`:

````markdown
### D4 — Size Coverage

Since 2026-07-22, `script/targeted_qa_fix.sh`'s Tier 1 sweep runs this check automatically (`null_size` flag)
— found via product `16254994627`, whose image-visible 400ml size was never extracted; this query previously
existed only as a manual snippet here, the same gap D5's pack-count check had before the prior round.

```sql
-- In-scope LLM entries with NULL size that are NOT legitimately multi-size
SELECT pt.taxonomy_id, pt.canonical_name, SUM(u.gmv_monthly) gmv
FROM in_scope s
JOIN `sincere-hearth-273704.magpie.marketshare_universe` u USING (product_id, master_table)
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt ON u.taxonomy_id = pt.taxonomy_id
WHERE u.month = '2026-04-01' AND pt.size IS NULL AND pt.is_multi_size IS NOT TRUE
GROUP BY 1,2 ORDER BY gmv DESC;
```
````

- [ ] **Step 4: Verify all three edits**

Run: `grep -n "reseller's own watermark, logo overlay" docs/llm-extraction-rules.md`
Expected: one match.

Run: `grep -n "^| Jul 22 2026 | universal | \*\*§11 extended" docs/llm-extraction-rules.md`
Expected: one match.

Run: `grep -n "Tier 1 sweep runs this check automatically" docs/quality-standards.md`
Expected: one match.

- [ ] **Step 5: Commit**

```bash
git add docs/llm-extraction-rules.md docs/quality-standards.md
git commit -m "Add seller-watermark brand rule (§11) and D4 cross-reference note"
```

---

### Task 2: Add `GARBAGE_BRAND` hard gate to `qa_report.sh`

**Files:**
- Modify: `script/qa_report.sh`

**Interfaces:**
- Consumes: nothing from other tasks (independent of Task 1's doc changes and Task 3's script changes).
- Produces: nothing consumed elsewhere — this is a standalone gate in the existing `qa_report.sh` report
  loop, following the same pattern as `ALL_VARIANT`/`CANON_FIELDS` immediately above it.

- [ ] **Step 1: Insert the new gate**

In `script/qa_report.sh`, find:

```bash
   AND NOT REGEXP_CONTAINS(LOWER(canonical_name), r'\(all\s+(variants?|sizes?)\b|\bmultiple\s+(variants?|sizes?)\b')" | tail -1)
if [ "$CANON_FIELDS" = "0" ]; then echo "[PASS] canonical_name fields:    0"
else echo "[FAIL] canonical_name fields:    ${CANON_FIELDS}"; FAIL=1; fi

echo "==============================="
```

Replace with:

```bash
   AND NOT REGEXP_CONTAINS(LOWER(canonical_name), r'\(all\s+(variants?|sizes?)\b|\bmultiple\s+(variants?|sizes?)\b')" | tail -1)
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
   )" | tail -1)
if [ "$GARBAGE_BRAND" = "0" ]; then echo "[PASS] garbled brand text:       0"
else echo "[FAIL] garbled brand text:       ${GARBAGE_BRAND}"; FAIL=1; fi

echo "==============================="
```

- [ ] **Step 2: Verify the edit**

Run: `bash -n script/qa_report.sh`
Expected: no output, exit 0.

Run: `grep -n "GARBAGE_BRAND=" script/qa_report.sh`
Expected: one match.

- [ ] **Step 3: Commit**

```bash
git add script/qa_report.sh
git commit -m "Add GARBAGE_BRAND hard gate to qa_report.sh"
```

---

### Task 3: `targeted_qa_fix.sh` — `null_size`/`garbage_brand` Tier 1 flags, type-conflict judgment, brand_id fix-branch

**Files:**
- Modify: `script/targeted_qa_fix.sh`
- Modify: `script/test_targeted_qa_fix.sh`

**Interfaces:**
- Consumes: the §11 rule text (Task 1, referenced by name in the new fix guidance — no code dependency).
- Produces: nothing consumed elsewhere — extends `build_auto_discovery_prompt`'s existing STEP 2/3/4 text,
  same function signature.

- [ ] **Step 1: Add failing tests for the two new Tier 1 flags and the STEP 3/4 additions**

In `script/test_targeted_qa_fix.sh`, find:

```bash
echo "$prompt" | grep -q "multiple variants?|multiple sizes?" || fail "build_auto_discovery_prompt's stub_leak check must also catch 'multiple variants/sizes' text unconditionally"
echo "PASS: build_auto_discovery_prompt"
```

Replace with:

```bash
echo "$prompt" | grep -q "multiple variants?|multiple sizes?" || fail "build_auto_discovery_prompt's stub_leak check must also catch 'multiple variants/sizes' text unconditionally"
# Round 3 (2026-07-22 stakeholder review): product 22501764599 was a shampoo mapped to a body-wash entry
# (type-conflict routing, not a naming defect -- Tier 2 judgment must explicitly check this, no new SQL
# heuristic per explicit direction, since a keyword filter risks silently dropping exactly what it should
# catch). Product 16254994627 had an image-visible 400ml size never extracted (D4, never wired before now).
# Product 7155345414 resolved to garbled brand text "12/+＝" (seller watermark misread as brand). Product
# 26143837772 had canonical_name correctly saying "Enfant" while brand_id resolved to BRD-UNDEFINED --
# already caught by wrong_field_order, but the existing fix guidance assumed the wrong root cause (reorder
# text) instead of the real one (fix brand_id).
echo "$prompt" | grep -q "null_size" || fail "build_auto_discovery_prompt's Tier 1 sweep must add the D4 size-coverage check"
echo "$prompt" | grep -qF "r'[\p{L}]'" || fail "build_auto_discovery_prompt's Tier 1 sweep must add the garbage_brand check"
echo "$prompt" | grep -q "product type genuinely matches" || fail "STEP 3 must require an explicit type-conflict check, not just naming/structure judgment"
echo "$prompt" | grep -q "brand_id resolves to \`BRD-UNDEFINED\`/\`BRD-UNBRANDED\` while \`canonical_name\` clearly states a real" || fail "STEP 4 must branch wrong_field_order's fix between reordering text and correcting brand_id"
echo "PASS: build_auto_discovery_prompt"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: FAIL — `build_auto_discovery_prompt's Tier 1 sweep must add the D4 size-coverage check` (the first
new assertion, since none of the new content exists yet).

- [ ] **Step 3: Add `null_size` and `garbage_brand` to the Tier 1 sweep (STEP 2)**

In `script/targeted_qa_fix.sh`, find:

```
  ) AND NOT REGEXP_CONTAINS(LOWER(pt.canonical_name), r'\(all\s+(variants?|sizes?)\b|\bmultiple\s+(variants?|sizes?)\b') AS canonical_field_mismatch
FROM \`${PROJECT}.magpie_reference.product_taxonomy\` pt
JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
JOIN \`${PROJECT}.magpie_reference.brand_dict\` bd ON bd.brand_id = pt.brand_id
WHERE m.master_table = '${table}'
  AND (pt._meta IS NULL OR IFNULL(JSON_VALUE(pt._meta, '$.review_confidence'), 'unreviewed') != 'confident')
GROUP BY 1,2,3,pt.product_line,pt.sub_line,pt.variant,pt.size,pt.pack_count
Every TRUE flag here is an automatic last_verdict='wrong' candidate — no LLM judgment needed to detect these,
only to decide and apply the fix in STEP 4.
```

Replace with:

```
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
only to decide and apply the fix in STEP 4. null_size (D4, docs/quality-standards.md) was never wired into
any automated check before now, same gap D5 had — found via product 16254994627's image-visible 400ml size
that was never extracted. garbage_brand catches a resolved brand (brand_dict.canonical_name via
product_taxonomy.brand_id) with no letters at all (e.g. "12/+＝") — see docs/llm-extraction-rules.md §11 for
the root cause (a reseller's watermark/logo overlay misread as the product's brand) and STEP 4 for the fix.
```

- [ ] **Step 4: Run the tests to verify `null_size`/`garbage_brand` assertions pass, confirm the next one fails**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: `null_size` and `garbage_brand` assertions pass; FAIL at `STEP 3 must require an explicit
type-conflict check`.

- [ ] **Step 5: Add the type-conflict judgment requirement to STEP 3**

In `script/targeted_qa_fix.sh`, find:

```
STEP 3 — Tier 2: a bounded, GMV-prioritized sample only, not every un-flagged row. Order the rows Tier 1
didn't flag by GMV (join master_clean_niq for gmv_monthly) and judge the top slice your remaining turn budget
allows against docs/llm-extraction-rules.md in full (product_line §3, size §2, the new §11 signal-provenance
and size-cross-validation rules) and docs/quality-standards.md §3's D1-D5 dimensions. This is the one script in
this pipeline where per-entry LLM judgment is the right tool, not a shortcut to avoid — precision is this script's job, not headless_taxonomy.sh's.
But exhaustively re-judging every Tier-1-clean row one by one is
```

Replace with:

```
STEP 3 — Tier 2: a bounded, GMV-prioritized sample only, not every un-flagged row. Order the rows Tier 1
didn't flag by GMV (join master_clean_niq for gmv_monthly) and judge the top slice your remaining turn budget
allows against docs/llm-extraction-rules.md in full (product_line §3, size §2, the new §11 signal-provenance
and size-cross-validation rules) and docs/quality-standards.md §3's D1-D5 dimensions. This is the one script in
this pipeline where per-entry LLM judgment is the right tool, not a shortcut to avoid — precision is this script's job, not headless_taxonomy.sh's.

For every row you judge, explicitly check whether the matched/reused entry's product type genuinely matches
sku_name and the image — not just whether the name/structure looks right. This is the same conflict class as
hard gate G3 (docs/quality-standards.md §4 — wet vs dry, lotion vs oil, paste vs wash) and the TYPE GATE in
docs/product-lifecycle.md §4.2's match-or-create decision tree, just for this category's own product types
(e.g. shampoo vs body wash/shower gel, found via product 22501764599). Bulk text-matching (used during
coverage runs for speed) can produce a superficially plausible but wrong-type match when a brand carries
multiple product lines with overlapping vocabulary — a match that "sounds right" from a text diff is not
verified until the type is confirmed against sku_name/image. A wrong-type match is never partial credit —
reroute to the correct existing entry, or mint a new one; do not rename in place.

But exhaustively re-judging every Tier-1-clean row one by one is
```

- [ ] **Step 6: Run the tests to verify the STEP 3 assertion passes, confirm the STEP 4 one fails**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: `product type genuinely matches` assertion passes; FAIL at `STEP 4 must branch wrong_field_order's
fix`.

- [ ] **Step 7: Add the `wrong_field_order` fix-branching guidance to STEP 4**

In `script/targeted_qa_fix.sh`, find:

```
STEP 4 — Apply fixes. Prefer bulk SQL per defect class over one-row-at-a-time corrections wherever the fix
is mechanical — e.g. a single REGEXP_REPLACE UPDATE can strip a duplicated brand substring across every
affected row in one statement (this repo has precedent: docs/categories/th_moisturizer_for_face.md's
"Brand-Brand naming bug" fix used exactly this pattern). Read an individual product's image only when the fix
itself requires re-deriving a value (e.g. confirming the real size after a G2G-style false match). Every row
you change must have its _meta reset in the same session (_meta is STRING-typed, storing serialized JSON text —
never use the JSON '...' literal prefix or TO_JSON(), always a plain string):
```

Replace with:

```
STEP 4 — Apply fixes. Prefer bulk SQL per defect class over one-row-at-a-time corrections wherever the fix
is mechanical — e.g. a single REGEXP_REPLACE UPDATE can strip a duplicated brand substring across every
affected row in one statement (this repo has precedent: docs/categories/th_moisturizer_for_face.md's
"Brand-Brand naming bug" fix used exactly this pattern). Read an individual product's image only when the fix
itself requires re-deriving a value (e.g. confirming the real size after a G2G-style false match). Every row
you change must have its _meta reset in the same session (_meta is STRING-typed, storing serialized JSON text —
never use the JSON '...' literal prefix or TO_JSON(), always a plain string):

wrong_field_order has two different root causes needing two different fixes — check which one before acting:
(a) text is genuinely out of order (e.g. "Size Type Multiplier" instead of "Brand Product-Line Size xN"):
reorder canonical_name to match the established template, brand_id itself is correct. (b) brand_id resolves
to `BRD-UNDEFINED`/`BRD-UNBRANDED` while canonical_name clearly states a real, identifiable brand name (found
via product 26143837772: brand_id resolved to "Undefined" but canonical_name correctly said "Enfant..."):
canonical_name is already correct, do NOT touch it — the defect is brand_id. Look up the correct brand in
brand_dict (exact or close name match against the brand already stated in canonical_name), or create a new
brand_dict entry if it genuinely doesn't exist yet, and update product_taxonomy.brand_id to point there.

garbage_brand's fix follows docs/llm-extraction-rules.md §11: re-read the image applying the seller-watermark
discipline (a reseller's overlay/logo, however large in the frame, is never the brand — only text printed on
the actual packaging counts), find or create the correct brand_dict entry, update product_taxonomy.brand_id,
and correct canonical_name to start with the real brand — unlike case (b) above, both fields are wrong here
and both need fixing.
```

- [ ] **Step 8: Run the full test suite and syntax check**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: `PASS: build_auto_discovery_prompt`, `ALL TESTS PASSED`.

Run: `bash -n script/targeted_qa_fix.sh`
Expected: no output, exit 0.

- [ ] **Step 9: Sanity-render the new SQL and prose to confirm no heredoc escaping bugs**

Run:
```bash
source script/targeted_qa_fix.sh
build_auto_discovery_prompt "shopee_th_suncare" "docs/categories/th_suncare.md" "200" | grep -A2 "null_size\|garbage_brand"
```
Expected: both lines render with the backtick-escaped table references intact (`` \` `` → `` ` ``) and no
"command not found" errors — this repo has hit unescaped-backtick heredoc bugs three times before in this
same file, so this check is not optional.

- [ ] **Step 10: Commit**

```bash
git add script/targeted_qa_fix.sh script/test_targeted_qa_fix.sh
git commit -m "Add D4/garbage-brand Tier 1 flags, type-conflict judgment, and brand_id fix-branching"
```

---

## Post-plan note (not a task)

Applying `GARBAGE_BRAND`'s `\p{L}` regex against real BigQuery (confirming RE2 support, per Task 2's inline
comment) is a live-environment verification step, not part of building this — the same standing caveat every
regex addition in this engagement has carried. Do this before the first real `targeted_qa_fix.sh`/`qa_report.sh`
run touches a category with this gate active.
