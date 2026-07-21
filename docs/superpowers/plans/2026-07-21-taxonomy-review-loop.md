# Automated Taxonomy Review Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `script/targeted_qa_fix.sh` a default auto-discovery mode that finds and fixes taxonomy
quality defects on its own (via a new `product_taxonomy._meta` column and a two-tier SQL+LLM review
checklist), instead of requiring a human to hand-write a `## Targeted QA Fix Brief` every time.

**Architecture:** New `_meta JSON` column tracks per-entry review state. `targeted_qa_fix.sh` gains a second
prompt-builder function, `build_auto_discovery_prompt`, used whenever a category file has no *filled-in*
Brief section — mirrors the existing `resolve_category_file`/`build_prompt`/`decide_next_step` function
shape already in this script, and the two-prompt-builder split already proven in `headless_taxonomy.sh`.

**Tech Stack:** Bash (`set -euo pipefail`), `bq` CLI (BigQuery `JSON` column type, `JSON_VALUE`,
`REGEXP_EXTRACT_ALL`), `claude -p --output-format json`, `jq`.

## Global Constraints

- BigQuery project: `sincere-hearth-273704`.
- Every write to `product_taxonomy`/`product_taxonomy_map` is DML, never the streaming API.
- Every touched row gets `meta_agent='CLAUDE_CODE'`.
- SKU block claims: atomic transaction, `DECLARE next_start INT64;` before `BEGIN TRANSACTION;`.
- `status='blocked'` is a valid, expected outcome, never a failure.
- Never delete an existing row unless explicitly instructed.
- Hard gates G1/G2/G4/G5 (dual-mapped, HUMAN+LLM coexistence, cross-category, provenance) must pass before
  any universe refresh — this review loop does not relax them, only changes how work is discovered.
- Any row whose `product_line`/`size`/`pack_count`/`canonical_name` is changed by a fix must have its `_meta`
  reset to `{"is_reviewed": false}` in the same session — stale confidence on changed data is invalid.
- No changes to `headless_taxonomy.sh` in this plan — both its prompts already read
  `docs/llm-extraction-rules.md` in full, so the new §11 rules (Task 2) reach it for free.

---

### Task 1: Add `product_taxonomy._meta` column

**Files:**
- Create: `sql/migrations/004_add_taxonomy_meta_column.sql`
- Modify: `sql/schema/product_taxonomy.sql`
- Modify: `docs/data-dictionary.md` (the `product_taxonomy` column table, ~line 202-217)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: the `_meta` column shape `{"is_reviewed": bool, "last_reviewed_at": timestamp string,
  "review_confidence": "unreviewed"|"unconfident"|"confident", "last_verdict": "correct"|"wrong"}` that
  Task 4's queries read and write.

- [ ] **Step 1: Write the migration file**

```sql
-- sql/migrations/004_add_taxonomy_meta_column.sql
-- Adds a review-tracking column for the automated taxonomy review loop
-- (docs/superpowers/specs/2026-07-21-taxonomy-review-loop-design.md).
-- Additive and non-breaking: existing rows get _meta = NULL, meaning "never reviewed."

ALTER TABLE `sincere-hearth-273704.magpie_reference.product_taxonomy`
ADD COLUMN IF NOT EXISTS _meta JSON;
```

- [ ] **Step 2: Update the schema file to match**

In `sql/schema/product_taxonomy.sql`, find:

```sql
  meta_agent       STRING    NOT NULL,  -- 'CLAUDE_CODE', 'CODEX', or 'HUMAN'
  created_at       TIMESTAMP NOT NULL,
  updated_at       TIMESTAMP NOT NULL
)
```

Replace with:

```sql
  meta_agent       STRING    NOT NULL,  -- 'CLAUDE_CODE', 'CODEX', or 'HUMAN'
  created_at       TIMESTAMP NOT NULL,
  updated_at       TIMESTAMP NOT NULL,
  _meta            JSON                 -- review-loop state; see sql/migrations/004_add_taxonomy_meta_column.sql
)
```

- [ ] **Step 3: Document the column in the data dictionary**

In `docs/data-dictionary.md`, find (inside the `magpie_reference.product_taxonomy` table's column list):

```markdown
| `meta_agent` | STRING | `CLAUDE_CODE`, `CODEX`, or `HUMAN` — never NULL |
| `created_at` | TIMESTAMP | |
| `updated_at` | TIMESTAMP | |
```

Replace with:

```markdown
| `meta_agent` | STRING | `CLAUDE_CODE`, `CODEX`, or `HUMAN` — never NULL |
| `created_at` | TIMESTAMP | |
| `updated_at` | TIMESTAMP | |
| `_meta` | JSON | Review-loop state, written by `script/targeted_qa_fix.sh`'s auto-discovery mode. `NULL` = never reviewed. Shape: `{is_reviewed, last_reviewed_at, review_confidence: "unreviewed"\|"unconfident"\|"confident", last_verdict: "correct"\|"wrong"}`. Any session that changes `product_line`/`size`/`pack_count`/`canonical_name` must reset this to `{"is_reviewed": false}` on that row — see [docs/superpowers/specs/2026-07-21-taxonomy-review-loop-design.md](superpowers/specs/2026-07-21-taxonomy-review-loop-design.md). |
```

- [ ] **Step 4: Verify the edits**

Run: `grep -n "_meta" sql/schema/product_taxonomy.sql docs/data-dictionary.md`
Expected: at least one match in each file.

Run: `cat sql/migrations/004_add_taxonomy_meta_column.sql`
Expected: the `ALTER TABLE ... ADD COLUMN IF NOT EXISTS _meta JSON;` statement, unchanged from Step 1.

This migration is not applied against BigQuery as part of this task — running DDL against the production
project is a separate, deliberate operational step (same standing caveat every schema change in this repo
carries). Once applied, confirm with: `bq query --use_legacy_sql=false --project_id=sincere-hearth-273704
"SELECT _meta FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy\` LIMIT 1"` — expect no error and
`_meta` either NULL or absent from output (additive, non-breaking on existing rows).

- [ ] **Step 5: Commit**

```bash
git add sql/migrations/004_add_taxonomy_meta_column.sql sql/schema/product_taxonomy.sql docs/data-dictionary.md
git commit -m "Add product_taxonomy._meta column for the automated review loop"
```

---

### Task 2: Add signal-provenance and size-cross-validation rules to `llm-extraction-rules.md`

**Files:**
- Modify: `docs/llm-extraction-rules.md` (append new `## 11.` section after the existing `## 10. QA Checks`
  section, before `## Changelog`)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: the two rules Task 4's Tier 2 LLM review prompt instructs the agent to check entries against —
  "never derive naming from `merchant_name`" and "cross-validate short/ambiguous sizes." Also read in full by
  `headless_taxonomy.sh`'s existing prompts (no code change needed there — see Global Constraints).

- [ ] **Step 1: Add a changelog row**

In `docs/llm-extraction-rules.md`, find the last row of the `## Changelog` table:

```markdown
| Jun 24 2026 | universal | **Explicit extraction priority chains added to §1 and §2.** Size: `sku_name` text → image → `product_specification` → `product_description`; **text wins** over image (never override a stated size). Pack_count: `sku_name` text → image → spec → description; **image wins** over text (image is the tiebreaker — title can miscount, pack shot shows actual units). Previously the chain lived only in ARCHITECTURE.md/data-dictionary.md and was absent from the operative rulebook; the pack_count fallback order was undocumented. |
```

Add a new row directly after it:

```markdown
| Jul 21 2026 | universal | **§11 added: signal provenance + size cross-validation.** Found via stakeholder review of `shopee_sg_diapers` (reseller/merchant name leaking into `product_line`) and `shopee_id_makeup_face` (product `52351401583`'s size read as "2g" from digits embedded in the brand name "G2G"/"Glad2Glow" rather than the real size in `product_specification`). Never use `merchant_name` as a naming signal; cross-validate short/ambiguous sku_name-derived sizes against `product_specification`/image before accepting. |
```

- [ ] **Step 2: Insert the new §11 section**

In `docs/llm-extraction-rules.md`, the target region (§10's closing fence, followed by the existing `---` /
`## Changelog` boundary) currently reads exactly:

````markdown
-- F. Tier-1 NULL coverage: top-GMV brands with official stores should have zero NULLs
-- SELECT brand_id, COUNT(*) null_ct
-- FROM marketshare_universe WHERE taxonomy_id IS NULL AND country='{country}'
--   AND category_3='{cat}' AND month='2026-04-01'
--   AND merchant_badge='Shopee Mall'
-- GROUP BY brand_id HAVING COUNT(*) > 0
-- expect 0 rows — any Mall product from a scoped brand without taxonomy is an extraction miss
```

---

## Changelog
````

(the fence above is 4 backticks purely so this plan can quote a block that itself contains a real 3-backtick
fence — use the literal 3-backtick fence when matching/writing the real file.)

Use `old_string` = everything from `-- F. Tier-1 NULL coverage` through `## Changelog` (inclusive of the
closing ` ``` `, the `---`, and the `## Changelog` line) and `new_string` = the same content with a new `##
11.` section inserted between the closing ` ``` ` and the `## Changelog` line — i.e. the closing fence for
§10's SQL block must stay exactly where it is, immediately after the `-- expect 0 rows...` line:

````markdown
-- F. Tier-1 NULL coverage: top-GMV brands with official stores should have zero NULLs
-- SELECT brand_id, COUNT(*) null_ct
-- FROM marketshare_universe WHERE taxonomy_id IS NULL AND country='{country}'
--   AND category_3='{cat}' AND month='2026-04-01'
--   AND merchant_badge='Shopee Mall'
-- GROUP BY brand_id HAVING COUNT(*) > 0
-- expect 0 rows — any Mall product from a scoped brand without taxonomy is an extraction miss
```

---

## 11. Signal Provenance & Cross-Validation

**Never derive `brand`, `product_line`, or any part of `canonical_name` from `merchant_name`** (the seller's
store display name). Only `sku_name` (product title) and the product image are valid naming signals. A
reseller's shop name appearing anywhere in `canonical_name` is always a defect — re-derive from the product's
own title and image, never the store name.

**Cross-validate short or ambiguous size matches before accepting them.** A size extracted from `sku_name`
that is 1-2 digits + unit, or that sits inside what reads as a brand/product-line token rather than being
clearly delimited (e.g., a brand like "G2G"/"Glad2Glow" contains digits a naive scan could misread as a size
"2g"), must be confirmed against `product_specification` or the image before being accepted. If the
`sku_name`-derived size doesn't independently confirm, prefer the confirmed source over the naive text match.

---

## Changelog
````

- [ ] **Step 3: Verify both edits**

Run: `grep -n "^## 11. Signal Provenance" docs/llm-extraction-rules.md`
Expected: one match.

Run: `grep -n "Jul 21 2026" docs/llm-extraction-rules.md`
Expected: one match, inside the Changelog table.

- [ ] **Step 4: Commit**

```bash
git add docs/llm-extraction-rules.md
git commit -m "Add §11 signal-provenance and size-cross-validation rules"
```

---

### Task 3: Extend the placeholder-leak gate; document the review loop in `quality-standards.md`

**Files:**
- Modify: `docs/headless-runbook.md:90-98` (the `run_qa_gates()` function's `placeholder_leak` check)
- Modify: `docs/quality-standards.md` (new subsection in `## 1. The Review Loop`)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: nothing consumed elsewhere — the extended gate is a defense-in-depth safety net (also checked at
  the end of Task 4's auto-discovery prompt); the doc subsection is reference material only.

- [ ] **Step 1: Extend the placeholder-leak regex**

In `docs/headless-runbook.md`, find:

```bash
  local placeholder_leak
  placeholder_leak=$(bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=csv \
    "SELECT COUNT(*) FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy\` pt
     JOIN \`sincere-hearth-273704.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
     WHERE m.master_table = '${table}'
       AND REGEXP_CONTAINS(LOWER(pt.canonical_name), r'\\b(undefined|null|n/a|tbd)\\b')" | tail -1)
  if [ "$placeholder_leak" != "0" ]; then
    echo "QA GATE FAILED: ${placeholder_leak} placeholder-leak canonical names for ${table}"; return 1
  fi
```

Replace with:

```bash
  local placeholder_leak
  placeholder_leak=$(bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=csv \
    "SELECT COUNT(*) FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy\` pt
     JOIN \`sincere-hearth-273704.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
     WHERE m.master_table = '${table}'
       AND REGEXP_CONTAINS(LOWER(pt.canonical_name), r'\\b(undefined|null|n/a|tbd|all variants?|all sizes?)\\b')" | tail -1)
  if [ "$placeholder_leak" != "0" ]; then
    echo "QA GATE FAILED: ${placeholder_leak} placeholder-leak canonical names for ${table}"; return 1
  fi
```

(Extends the existing check — added 2026-07-21 after "(all variants)"-style stubs were found in stakeholder
review despite `docs/llm-extraction-rules.md` §2 already forbidding that exact phrasing; the hard gate never
mechanically enforced it before now.)

- [ ] **Step 2: Document the review loop in `quality-standards.md`**

In `docs/quality-standards.md`, find:

```markdown
**Triage rule:** always rank gaps by **GMV impact**, not row count. A single 7M-THB
product mapped to a generic stub matters more than 200 long-tail rows. Fix the
highest-GMV defects first; the long tail can remain `UNRESOLVED`.

---

## 2. The Review Scope (the denominator)
```

Replace with:

```markdown
**Triage rule:** always rank gaps by **GMV impact**, not row count. A single 7M-THB
product mapped to a generic stub matters more than 200 long-tail rows. Fix the
highest-GMV defects first; the long tail can remain `UNRESOLVED`.

### Automated review loop (`targeted_qa_fix.sh` auto-discovery mode)

Since 2026-07-21, `script/targeted_qa_fix.sh` can run this loop on its own for the FIX/RE-MEASURE half — see
[docs/superpowers/specs/2026-07-21-taxonomy-review-loop-design.md](superpowers/specs/2026-07-21-taxonomy-review-loop-design.md).
`product_taxonomy._meta` tracks review state per entry (`review_confidence`: `unreviewed` → `unconfident` →
`confident`, reached by two consecutive reviews agreeing on the same verdict). Each run reviews only
never-reviewed or `unconfident` entries (incremental scope, not a full re-scan) via a two-tier checklist: Tier
1 SQL regex (duplicate brand tokens, placeholder/stub leaks, field-order violations, brand casing, excess
content) flags cheaply; Tier 2 LLM judgment (checked against §3's D1-D5 dimensions and
`llm-extraction-rules.md` in full, including §11's signal-provenance and size-cross-validation rules) covers
what regex can't. A `## Targeted QA Fix Brief` written by a human still works and takes priority when present
— auto-discovery is the default when one isn't.

---

## 2. The Review Scope (the denominator)
```

- [ ] **Step 3: Verify both edits**

Run: `grep -n "all variants?|all sizes?" docs/headless-runbook.md`
Expected: one match.

Run: `grep -n "Automated review loop" docs/quality-standards.md`
Expected: one match.

- [ ] **Step 4: Commit**

```bash
git add docs/headless-runbook.md docs/quality-standards.md
git commit -m "Extend placeholder-leak gate; document the automated review loop in quality-standards.md"
```

---

### Task 4: `targeted_qa_fix.sh` auto-discovery mode

**Files:**
- Modify: `script/targeted_qa_fix.sh`
- Modify: `script/test_targeted_qa_fix.sh`

**Interfaces:**
- Consumes: `docs/llm-extraction-rules.md` §11 (Task 2), the extended placeholder-leak gate (Task 3), the
  `_meta` column (Task 1) — all referenced by name/path in the new prompt text, no code-level dependency.
- Produces: `has_real_brief(category_file) -> "true"|"false"`, `build_auto_discovery_prompt(table,
  category_file, block_size) -> prompt string`. `main()` now branches between the existing `build_prompt`
  (Brief mode) and the new `build_auto_discovery_prompt` (default when no real Brief exists).

- [ ] **Step 1: Add failing tests for `has_real_brief`**

In `script/test_targeted_qa_fix.sh`, find:

```bash
# --- build_prompt ---
```

Insert directly before it:

```bash
# --- has_real_brief ---
tmpdir=$(mktemp -d)

cat > "$tmpdir/no_brief.md" <<'EOF'
# Category
## QA History
EOF
[[ "$(has_real_brief "$tmpdir/no_brief.md")" == "false" ]] || fail "no Brief section -> false"

cat > "$tmpdir/template_brief.md" <<'EOF'
## Targeted QA Fix Brief

> Scope note here.

**Verdict:** {defect class, e.g. "D1 Tier-C generic stubs"}

{Fix description}
EOF
[[ "$(has_real_brief "$tmpdir/template_brief.md")" == "false" ]] || fail "unfilled template Verdict -> false"

cat > "$tmpdir/real_brief.md" <<'EOF'
## Targeted QA Fix Brief

> Scope note here.

**Verdict:** D5 pack-count errors on 12 products

Fix these specific pack-count mistakes...
EOF
[[ "$(has_real_brief "$tmpdir/real_brief.md")" == "true" ]] || fail "filled Verdict -> true"

rm -rf "$tmpdir"
echo "PASS: has_real_brief"

# --- build_prompt ---
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: FAIL — `has_real_brief: command not found`.

- [ ] **Step 3: Implement `has_real_brief`**

In `script/targeted_qa_fix.sh`, find:

```bash
build_prompt() {
```

Insert directly before it:

```bash
has_real_brief() {
  local category_file="$1"
  if ! grep -q "^## Targeted QA Fix Brief" "$category_file" 2>/dev/null; then
    echo "false"
    return
  fi
  local verdict_line
  verdict_line=$(grep "^\*\*Verdict:\*\*" "$category_file" | head -1)
  if [[ -z "$verdict_line" ]] || [[ "$verdict_line" == *"{"* ]]; then
    echo "false"
  else
    echo "true"
  fi
}

build_prompt() {
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: `PASS: has_real_brief`, then continues into the existing `build_prompt` tests.

- [ ] **Step 5: Add failing tests for `build_auto_discovery_prompt`**

In `script/test_targeted_qa_fix.sh`, find:

```bash
echo "$prompt" | grep -q "headless_taxonomy.sh" || fail "build_prompt should point NULL-coverage work at headless_taxonomy.sh instead"
echo "PASS: build_prompt"
```

Replace with:

```bash
echo "$prompt" | grep -q "headless_taxonomy.sh" || fail "build_prompt should point NULL-coverage work at headless_taxonomy.sh instead"
echo "PASS: build_prompt"

# --- build_auto_discovery_prompt ---
prompt=$(build_auto_discovery_prompt "shopee_th_suncare" "docs/categories/th_suncare.md" "200")
echo "$prompt" | grep -q "shopee_th_suncare" || fail "build_auto_discovery_prompt should mention the table"
echo "$prompt" | grep -q "docs/categories/th_suncare.md" || fail "build_auto_discovery_prompt should mention the category file"
echo "$prompt" | grep -q "review_confidence" || fail "build_auto_discovery_prompt must reference the _meta review_confidence field"
echo "$prompt" | grep -q "all variants?|all sizes?" || fail "build_auto_discovery_prompt's Tier 1 sweep must include the extended stub-leak regex"
echo "$prompt" | grep -q "docs/llm-extraction-rules.md" || fail "build_auto_discovery_prompt must instruct reading the extraction rules (incl. new §11)"
echo "$prompt" | grep -q "precision is this script's job, not headless_taxonomy.sh's" || fail "build_auto_discovery_prompt must state the precision-first priority"
echo "$prompt" | grep -q "'targeted_qa_fix'" || fail "build_auto_discovery_prompt should claim a targeted_qa_fix-scenario SKU block when minting"
echo "$prompt" | grep -q "status='blocked'" || fail "build_auto_discovery_prompt should document the blocked outcome"
echo "$prompt" | grep -q "Do NOT run the universe refresh yourself" || fail "build_auto_discovery_prompt must forbid self-refresh"
echo "PASS: build_auto_discovery_prompt"
```

- [ ] **Step 6: Run the test to verify it fails**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: FAIL — `build_auto_discovery_prompt: command not found`.

- [ ] **Step 7: Implement `build_auto_discovery_prompt`**

In `script/targeted_qa_fix.sh`, find the end of `build_prompt` and the comment block that follows it:

```bash
Output ONLY this JSON when done, nothing else:
{status: complete|partial|failed|blocked, rows_created, rows_mapped, taxonomy_id_range_used, findings, blockers}.
PROMPT
}

# The prompt instructs the model to output ONLY JSON, but sessions sometimes wrap it in prose
```

Replace with:

```bash
Output ONLY this JSON when done, nothing else:
{status: complete|partial|failed|blocked, rows_created, rows_mapped, taxonomy_id_range_used, findings, blockers}.
PROMPT
}

build_auto_discovery_prompt() {
  local table="$1"
  local category_file="$2"
  local block_size="${3:-200}"
  local slot_offset=$((block_size - 1))
  cat <<PROMPT
Automated Taxonomy Review session for ${table}. No '## Targeted QA Fix Brief' section with real content
exists in ${category_file} — this session auto-discovers its own scope instead of executing a hand-written
brief. See docs/superpowers/specs/2026-07-21-taxonomy-review-loop-design.md for the full design.

BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/llm-extraction-rules.md (including §11,
Signal Provenance & Cross-Validation), docs/quality-standards.md, docs/brand-extraction.md,
docs/headless-runbook.md, and ${category_file} (brand scope, allowlist, and scope rules are already
documented there — do not rediscover them from scratch).

You perform every review and fix yourself, directly, using your own multimodal reading of product images and
text where needed. You do not invoke external scripts or subprocesses and do not need any API key beyond your
own session auth — CLAUDE.md's ANTHROPIC_API_KEY note is about a different, external pipeline that does not
exist in this repo.

Known pitfalls from prior sessions, apply generally: (1) \`bq query\` silently truncates displayed results to
100 rows unless you pass --max_rows=100000 or --format=csv — always use one of those on any query where you
need the complete result set. (2) You are a one-shot, non-interactive process — do NOT use the Agent/Task
tool, ScheduleWakeup, or any background/async dispatch mechanism; work through your list directly and
sequentially.

STEP 1 — Get your review worklist (incremental scope: never-reviewed or previously-unconfident entries only,
never a full re-scan of the category):
SELECT DISTINCT pt.taxonomy_id, pt.canonical_name, bd.canonical_name AS brand, pt.product_line, pt.size,
       pt.pack_count, pt._meta
FROM \`${PROJECT}.magpie_reference.product_taxonomy\` pt
JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
JOIN \`${PROJECT}.magpie_reference.brand_dict\` bd ON bd.brand_id = pt.brand_id
WHERE m.master_table = '${table}'
  AND (pt._meta IS NULL OR JSON_VALUE(pt._meta, '$.review_confidence') != 'confident')

STEP 2 — Tier 1: run this SQL sweep over that same worklist to flag mechanical defects cheaply, before
spending any LLM judgment:
SELECT pt.taxonomy_id, pt.canonical_name, bd.canonical_name AS brand,
  REGEXP_CONTAINS(LOWER(pt.canonical_name), r'\b(undefined|null|n/a|tbd|all variants?|all sizes?)\b') AS stub_leak,
  (LENGTH(pt.canonical_name) - LENGTH(REPLACE(pt.canonical_name, bd.canonical_name, ''))) / GREATEST(LENGTH(bd.canonical_name),1) >= 2 AS duplicate_brand,
  NOT STARTS_WITH(LOWER(TRIM(pt.canonical_name)), LOWER(bd.canonical_name)) AS wrong_field_order,
  (STARTS_WITH(LOWER(pt.canonical_name), LOWER(bd.canonical_name)) AND NOT STARTS_WITH(pt.canonical_name, bd.canonical_name)) AS brand_casing_mismatch,
  (ARRAY_LENGTH(REGEXP_EXTRACT_ALL(pt.canonical_name, r'\d+\s*(?:ml|g|kg|l|L)\b')) > 1 OR ARRAY_LENGTH(REGEXP_EXTRACT_ALL(pt.canonical_name, r'x\d+\b')) > 1) AS excess_content
FROM \`${PROJECT}.magpie_reference.product_taxonomy\` pt
JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
JOIN \`${PROJECT}.magpie_reference.brand_dict\` bd ON bd.brand_id = pt.brand_id
WHERE m.master_table = '${table}'
  AND (pt._meta IS NULL OR JSON_VALUE(pt._meta, '$.review_confidence') != 'confident')
GROUP BY 1,2,3
Every TRUE flag here is an automatic last_verdict='wrong' candidate — no LLM judgment needed to detect these,
only to decide and apply the fix in STEP 4.

STEP 3 — Tier 2: for worklist rows Tier 1 didn't flag, judge a genuine sample against
docs/llm-extraction-rules.md in full (product_line §3, size §2, the new §11 signal-provenance and
size-cross-validation rules) and docs/quality-standards.md §3's D1-D5 dimensions. This is the one script in
this pipeline where per-entry LLM judgment is the right tool, not a shortcut to avoid — precision is this
script's job, not headless_taxonomy.sh's.

STEP 4 — Apply fixes. Prefer bulk SQL per defect class over one-row-at-a-time corrections wherever the fix
is mechanical — e.g. a single REGEXP_REPLACE UPDATE can strip a duplicated brand substring across every
affected row in one statement (this repo has precedent: docs/categories/th_moisturizer_for_face.md's
"Brand-Brand naming bug" fix used exactly this pattern). Read an individual product's image only when the fix
itself requires re-deriving a value (e.g. confirming the real size after a G2G-style false match). Every row
you change must have its _meta reset in the same session:
UPDATE \`${PROJECT}.magpie_reference.product_taxonomy\`
SET _meta = JSON '{"is_reviewed": false}'
WHERE taxonomy_id IN (/* the taxonomy_ids you just fixed */)

STEP 5 — For every worklist row you judged correct (no fix applied), update its _meta by comparing this
review's verdict against the stored previous verdict — agreement promotes to confident; disagreement, or a
first-ever review, lands on unconfident:
UPDATE \`${PROJECT}.magpie_reference.product_taxonomy\`
SET _meta = TO_JSON(STRUCT(
  true AS is_reviewed,
  CURRENT_TIMESTAMP() AS last_reviewed_at,
  IF(JSON_VALUE(_meta, '$.last_verdict') = 'correct', 'confident', 'unconfident') AS review_confidence,
  'correct' AS last_verdict
))
WHERE taxonomy_id = '<SKU-XXXXXX>'
(one UPDATE per taxonomy_id is fine here — this is metadata bookkeeping, not the expensive part of the
session.)

STEP 6 — If, and only if, a fix genuinely requires minting a new taxonomy entry (e.g. splitting a bad
multi-size stub into distinct real entries), claim a ${block_size}-slot SKU block atomically first (DECLARE
before BEGIN TRANSACTION — reversing that order is a real BigQuery scripting syntax error):
BEGIN
  DECLARE next_start INT64;
  BEGIN TRANSACTION;
  SET next_start = (SELECT COALESCE(MAX(block_end), 69000) + 1 FROM \`${PROJECT}.magpie_reference.sku_block_registry\`);
  INSERT INTO \`${PROJECT}.magpie_reference.sku_block_registry\`
    (block_start, block_end, master_table, scenario, claimed_at, status)
  VALUES (next_start, next_start + ${slot_offset}, '${table}', 'targeted_qa_fix', CURRENT_TIMESTAMP(), 'ACTIVE');
  COMMIT TRANSACTION;
END;
Never query MAX(taxonomy_id) directly — this atomic claim is what prevents two sessions colliding on the same
ID range. Most review sessions fix existing entries in place and need no new SKU at all; only claim a block
when you actually mint one.

STEP 7 — Write via bq query DML only, never the streaming API. Set meta_agent='CLAUDE_CODE' on every row you
write or update. Never delete an existing row.

STEP 8 — Do NOT run the universe refresh yourself. That step runs after this session, only if independent QA
gates pass — it is not something you do.

STEP 9 — Append a dated row to ${category_file}'s '## QA History' table (columns: Date | Pass | Finding |
Resolution) summarizing what you reviewed, what you fixed, and the confidence distribution you left behind.
Commit the updated file:
git add ${category_file} && git commit -m 'Automated review session for ${table}: update QA History'

STEP 10 — Before declaring status, self-check the hard gates from docs/headless-runbook.md's QA-gate-as-code
section, WITHOUT --skip-coexistence (this category already shipped once — coexistence is always a genuine bug
at this point). Report the actual numbers in findings.

STEP 11 — If you hit a genuine blocker at any step — something wrong with these instructions, missing data,
anything that would make proceeding unsafe — stop, write nothing further, and output status='blocked' with
the blockers array populated. That is a valid, expected outcome, not a failure.

Output ONLY this JSON when done, nothing else:
{status: complete|partial|failed|blocked, rows_created, rows_mapped, taxonomy_id_range_used, findings, blockers}.
PROMPT
}

# The prompt instructs the model to output ONLY JSON, but sessions sometimes wrap it in prose
```

- [ ] **Step 8: Run the test to verify it passes**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: `PASS: build_auto_discovery_prompt`, then `ALL TESTS PASSED`.

- [ ] **Step 9: Wire `main()` to branch on `has_real_brief`**

In `script/targeted_qa_fix.sh`, find:

```bash
  echo "${table}"
  echo "TARGETED QA FIX STARTED (brief: ${category_file}, block_size=${block_size}, max_turns=${max_turns})"
  echo "==========================="

  local prompt
  prompt=$(build_prompt "$table" "$category_file" "$block_size")
```

Replace with:

```bash
  echo "${table}"

  local prompt
  if [[ "$(has_real_brief "$category_file")" == "true" ]]; then
    echo "TARGETED QA FIX STARTED (brief mode: ${category_file}, block_size=${block_size}, max_turns=${max_turns})"
    echo "==========================="
    prompt=$(build_prompt "$table" "$category_file" "$block_size")
  else
    echo "TARGETED QA FIX STARTED (auto-discovery mode: ${category_file}, block_size=${block_size}, max_turns=${max_turns})"
    echo "==========================="
    prompt=$(build_auto_discovery_prompt "$table" "$category_file" "$block_size")
  fi
```

- [ ] **Step 10: Update the file's top-of-file usage comment**

In `script/targeted_qa_fix.sh`, find:

```bash
# Usage: ./script/targeted_qa_fix.sh <TABLE>
# e.g.  ./script/targeted_qa_fix.sh shopee_th_detergent
#
# Runs the "Scenario: Targeted QA Fix" procedure from docs/headless-runbook.md: claim a small SKU
# block, run claude -p against the fix brief in docs/categories/<table>.md's '## Targeted QA Fix
# Brief' section, then independently re-verify via script/qa_report.sh before refreshing the
# universe overlay. Never trusts the agent's own self-report to gate a production write.
#
# See docs/superpowers/specs/2026-07-17-targeted-qa-fix-script-design.md for the full design.
```

Replace with:

```bash
# Usage: ./script/targeted_qa_fix.sh <TABLE> [BLOCK_SIZE] [MAX_TURNS]
# e.g.  ./script/targeted_qa_fix.sh shopee_th_detergent
#
# Runs the "Scenario: Targeted QA Fix" procedure from docs/headless-runbook.md: claim a small SKU
# block, run claude -p, then independently re-verify via script/qa_report.sh before refreshing the
# universe overlay. Never trusts the agent's own self-report to gate a production write.
#
# Two modes, chosen automatically per category file:
#   - Brief mode: docs/categories/<table>.md has a filled-in '## Targeted QA Fix Brief' section
#     (a real Verdict line, not the _TEMPLATE.md placeholder) -> executes exactly what it specifies.
#   - Auto-discovery mode (default otherwise): reviews product_taxonomy entries the category hasn't
#     confidently reviewed yet (product_taxonomy._meta), fixes what it finds wrong. No human-written
#     brief needed. See docs/superpowers/specs/2026-07-21-taxonomy-review-loop-design.md.
#
# See docs/superpowers/specs/2026-07-17-targeted-qa-fix-script-design.md for the original design and
# docs/superpowers/specs/2026-07-21-taxonomy-review-loop-design.md for the auto-discovery mode design.
```

- [ ] **Step 11: Full verification**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: `ALL TESTS PASSED`.

Run: `bash -n script/targeted_qa_fix.sh`
Expected: no output, exit 0.

- [ ] **Step 12: Commit**

```bash
git add script/targeted_qa_fix.sh script/test_targeted_qa_fix.sh
git commit -m "Add auto-discovery review mode to targeted_qa_fix.sh, default when no Brief exists"
```

---

### Task 5: Document the two-mode split in `headless-runbook.md` and `headless-scripts-flow.md`

**Files:**
- Modify: `docs/headless-runbook.md:259-269`
- Modify: `docs/headless-scripts-flow.md:105-109`

**Interfaces:**
- Consumes: nothing from other tasks (prose only).
- Produces: nothing consumed elsewhere — documentation only.

- [ ] **Step 1: Update `docs/headless-runbook.md`'s "Scenario: Targeted QA Fix" section**

Find:

```markdown
## Scenario: Targeted QA Fix

Small SKU block (~200), narrow prompt scope (specific flagged products, not a full category rebuild), QA gates
scoped to affected `product_id`s only, universe refresh runs but only touches the products actually rerouted.

**Scope boundary:** this scenario fixes existing-row quality defects only — `docs/quality-standards.md`
§3's D1–D5 dimensions (generic-stub product lines, missing size/variant/pack-count, wrong product line) and
§4's hard gates G1/G2/G3/G5/G6, plus `brand_mismatch` review per `docs/brand-extraction.md`.
Coverage gaps (products with `taxonomy_id IS NULL`) are explicitly out of scope for this script — see
"Scenario: Full Rebuild" below, which now also covers re-running against an already-complete category to
close a live coverage gap.
```

Replace with:

```markdown
## Scenario: Targeted QA Fix

Small SKU block (~200), narrow prompt scope (specific flagged products, not a full category rebuild), QA gates
scoped to affected `product_id`s only, universe refresh runs but only touches the products actually rerouted.

**Scope boundary:** this scenario fixes existing-row quality defects only — `docs/quality-standards.md`
§3's D1–D5 dimensions (generic-stub product lines, missing size/variant/pack-count, wrong product line) and
§4's hard gates G1/G2/G3/G5/G6, plus `brand_mismatch` review per `docs/brand-extraction.md`.
Coverage gaps (products with `taxonomy_id IS NULL`) are explicitly out of scope for this script — see
"Scenario: Full Rebuild" below, which now also covers re-running against an already-complete category to
close a live coverage gap.

**Since 2026-07-21, this scenario has two modes** (`script/targeted_qa_fix.sh` picks automatically):
- **Brief mode** (unchanged): `docs/categories/<table>.md` has a filled-in `## Targeted QA Fix Brief` section
  — executes exactly what it specifies.
- **Auto-discovery mode** (new default when no real Brief exists): reviews `product_taxonomy` entries the
  category hasn't confidently reviewed yet, tracked via `product_taxonomy._meta`, against a two-tier SQL +
  LLM checklist, and fixes what it finds — no human-written Brief required. See
  [docs/superpowers/specs/2026-07-21-taxonomy-review-loop-design.md](superpowers/specs/2026-07-21-taxonomy-review-loop-design.md)
  for the full mechanics.
```

- [ ] **Step 2: Update `docs/headless-scripts-flow.md`'s `targeted_qa_fix.sh` intro**

Find:

```markdown
## `script/targeted_qa_fix.sh` — Targeted QA Fix

Scope is existing-row quality defects only (`docs/quality-standards.md` D1–D5, hard gates G1/G2/G3/G5/G6,
`brand_mismatch` review). Coverage gaps (`taxonomy_id IS NULL`) are out of scope for this script — see
`script/headless_taxonomy.sh`'s top-up scenario above.
```

Replace with:

```markdown
## `script/targeted_qa_fix.sh` — Targeted QA Fix

Scope is existing-row quality defects only (`docs/quality-standards.md` D1–D5, hard gates G1/G2/G3/G5/G6,
`brand_mismatch` review). Coverage gaps (`taxonomy_id IS NULL`) are out of scope for this script — see
`script/headless_taxonomy.sh`'s top-up scenario above.

Two modes, chosen by `has_real_brief()`: **Brief mode** executes a human-written `## Targeted QA Fix Brief`
section verbatim (original behavior). **Auto-discovery mode** (default when no real Brief exists) finds its
own work — a live, incremental review of `product_taxonomy` entries not yet confidently reviewed
(`product_taxonomy._meta`), via Tier 1 SQL regex checks (duplicate brand tokens, stub/placeholder leaks,
field-order violations, brand casing, excess content) and Tier 2 LLM judgment for what regex can't catch.
```

- [ ] **Step 3: Verify both edits**

Run: `grep -n "Auto-discovery mode" docs/headless-runbook.md docs/headless-scripts-flow.md`
Expected: at least one match in each file.

- [ ] **Step 4: Commit**

```bash
git add docs/headless-runbook.md docs/headless-scripts-flow.md
git commit -m "Document the two-mode (Brief / auto-discovery) split for targeted_qa_fix.sh"
```

---

## Post-plan note (not a task)

Retroactively running auto-discovery against every already-shipped category (starting with the six the
stakeholder reviewed — especially `shopee_th_body_wash`'s pre-existing "(all variants)" entries and
`shopee_sg_coffee`'s zero-GMV tail catch-alls) is a follow-up operational step once this ships, not part of
building it. Applying `sql/migrations/004_add_taxonomy_meta_column.sql` against the real
`sincere-hearth-273704` project is also a deliberate, separate step — Task 1 writes the migration file but
does not run it.

