# Design: Automated Taxonomy Review Loop (`targeted_qa_fix.sh` Auto-Discovery Mode)

> Status: approved design, not yet implemented.
> Companion to [`script/targeted_qa_fix.sh`](../../../script/targeted_qa_fix.sh),
> [`docs/quality-standards.md`](../../quality-standards.md), [`docs/llm-extraction-rules.md`](../../llm-extraction-rules.md),
> [`docs/brand-extraction.md`](../../brand-extraction.md), and
> [`docs/superpowers/specs/2026-07-20-headless-script-scope-refinement-design.md`](2026-07-20-headless-script-scope-refinement-design.md)
> (established the coverage-vs-quality split this design completes the "quality" half of).

---

## Problem

Stakeholder review of six freshly-run categories (`shopee_th_baby_diapers`, `shopee_sg_diapers`,
`shopee_id_baby_diapers`, `shopee_id_makeup_face`, `shopee_sg_coffee`, `shopee_th_body_wash`) found real,
varied defects: duplicate brand tokens in `canonical_name` ("Time Phoria" / "L'Oreal" written twice), a
misplaced/duplicated "BB Tint" token, brand casing errors ("o.two.onya" instead of the `brand_dict`
casing), a canonical-name field-order violation specific to the first Indonesia category (`Size Type
Multiplier` instead of `Brand Product-Line Size xN`), reseller/store names leaking into `product_line`, a
false-positive size extraction (`G2G`/`Glad2Glow`'s embedded digits read as "2g"), and generic
"(all variants)"-style stubs in two categories.

None of this was caught automatically. `headless_taxonomy.sh` (per the companion spec) only ever looks for
products with **no** `taxonomy_id` — it never re-examines entries it or a prior session already wrote.
`targeted_qa_fix.sh` can fix defects, but only ones a human has already found and written into a
`## Targeted QA Fix Brief` by hand. The stakeholder's own question — "does every run need to wipe everything
and start fresh?" — is really asking for a detection mechanism, not a purge: nothing currently re-scans
*existing* taxonomy for quality regressions, so defects sit invisible until someone happens to eyeball the
data.

This design makes `targeted_qa_fix.sh` capable of finding its own work: a live, `_meta`-tracked review loop
over `product_taxonomy` that replaces the hand-written Brief as the default trigger, while leaving Brief mode
available for genuinely custom, human-directed fixes.

---

## Deliverable scope

| File | Change |
|------|--------|
| `sql/migrations/004_add_taxonomy_meta_column.sql` | New: adds `_meta STRING` to `product_taxonomy` |
| `sql/schema/product_taxonomy.sql` | Updated to include `_meta STRING` in the `CREATE TABLE` definition |
| `docs/data-dictionary.md` | `product_taxonomy` table row list gets the new `_meta` column documented |
| `docs/llm-extraction-rules.md` | Two new rules: reseller-name-leak prohibition, size cross-validation |
| `script/targeted_qa_fix.sh` | New auto-discovery mode (default when no Brief section exists); Brief mode preserved as override |
| `script/test_targeted_qa_fix.sh` | Tests for the new prompt-building path |
| `docs/quality-standards.md` | D1 stub detector regex extended; new §9 documenting the review-loop mechanics and `_meta` semantics |
| `docs/headless-runbook.md` | "Scenario: Targeted QA Fix" section updated: auto-discovery is now the default entry point |
| `docs/headless-scripts-flow.md` | `targeted_qa_fix.sh` flow diagram updated for the new branch |

No changes to `headless_taxonomy.sh` — both its prompts already instruct reading `docs/llm-extraction-rules.md`
in full, so the two new extraction rules propagate to future first-run/top-up sessions automatically, with no
prompt edit needed there.

---

## 1. Data model: `product_taxonomy._meta`

**Type: `STRING`, not BigQuery's native `JSON` type** (deliberate choice, made when this migration was
actually applied) — `_meta` stores serialized JSON text. Read via `JSON_VALUE()` (which accepts `STRING`
input directly, no cast needed) and write via `TO_JSON_STRING()` — never the `JSON '...'` literal or
`TO_JSON()`, both of which produce a native `JSON`-typed value that a `STRING` column will reject.

```sql
-- sql/migrations/004_add_taxonomy_meta_column.sql
ALTER TABLE `sincere-hearth-273704.magpie_reference.product_taxonomy`
ADD COLUMN IF NOT EXISTS _meta STRING;
```

Shape (all fields optional/nullable until first reviewed — `_meta IS NULL` means never reviewed):

```json
{
  "is_reviewed": true,
  "last_reviewed_at": "2026-07-21T08:00:00Z",
  "review_confidence": "confident",
  "last_verdict": "correct"
}
```

- `review_confidence`: `"unreviewed"` (default/absent) | `"unconfident"` | `"confident"`.
- `last_verdict`: `"correct"` | `"wrong"` — the most recent review's finding, independent of confidence.
- **Reset rule:** any session that changes an entry's `product_line`/`size`/`pack_count`/`canonical_name`
  (i.e., applies a fix) must reset `_meta` to `{"is_reviewed": false}` on that row in the same transaction —
  stale confidence on since-changed data is worse than no confidence.

Lives on `product_taxonomy`, not `product_taxonomy_map`: every defect found so far (duplicate token, stub
leak, casing, field order, wrong size) is a property of the canonical entry itself, not of any one product
mapped to it — fixing the entry fixes it for every product that reuses it. `product_taxonomy_map` already has
`brand_mismatch` for the one review dimension that's genuinely per-product; no new column needed there. (If a
real per-mapping review need shows up later, add it then — not speculatively now.)

---

## 2. Review checklist

Two tiers, matching the pattern `quality-standards.md` §3's D1 stub detector already uses ("pure SQL can flag
candidates; final tier assignment of ambiguous cases is an LLM-assisted review of the flagged list") — this
design generalizes that existing pattern into the review loop's structure rather than inventing a new one.

### Tier 1 — SQL, cheap, mechanical, runs first

```sql
-- Extends the existing placeholder-leak gate (docs/headless-runbook.md's run_qa_gates) to the exact
-- forbidden phrasing docs/llm-extraction-rules.md §2 already documents but never mechanically enforced:
REGEXP_CONTAINS(LOWER(pt.canonical_name), r'\b(undefined|null|n/a|tbd|all variants?|all sizes?)\b')

-- Duplicate brand substring (catches "Time Phoria ... Time Phoria", "L'Oreal ... L'Oreal"):
(LENGTH(pt.canonical_name) - LENGTH(REPLACE(pt.canonical_name, bd.canonical_name, '')))
  / GREATEST(LENGTH(bd.canonical_name), 1) >= 2

-- canonical_name doesn't start with the brand (catches shopee_id_baby_diapers' Size-Type-Multiplier order bug):
NOT STARTS_WITH(LOWER(TRIM(pt.canonical_name)), LOWER(bd.canonical_name))

-- Brand casing mismatch (structurally starts with the brand, but casing is wrong — catches "o.two.onya"):
STARTS_WITH(LOWER(pt.canonical_name), LOWER(bd.canonical_name))
  AND NOT STARTS_WITH(pt.canonical_name, bd.canonical_name)

-- Duplicated size/pack info ("kelebihan" — excess content squeezed into one canonical_name):
ARRAY_LENGTH(REGEXP_EXTRACT_ALL(pt.canonical_name, r'\d+\s*(?:ml|g|kg|l|L)\b')) > 1
  OR ARRAY_LENGTH(REGEXP_EXTRACT_ALL(pt.canonical_name, r'x\d+\b')) > 1
```

Every Tier 1 hit is an automatic `last_verdict = "wrong"` candidate — no LLM call needed to flag these, only
to decide and apply the fix (STEP 3 below).

### Tier 2 — LLM judgment, only for rows Tier 1 doesn't cleanly clear

Reads each remaining candidate against `docs/llm-extraction-rules.md` (full read, already part of the
prompt) and `docs/quality-standards.md` §3 D1-D5. Two rules are new — added to `llm-extraction-rules.md` as
part of this change, because Tier 2 needs them written down to check against (and because both scripts
already read that file in full, this is also how the fix propagates to *future* first-run/top-up extractions
for free, no prompt edit needed):

```markdown
## 11. Signal Provenance & Cross-Validation

**Never derive `brand`, `product_line`, or any part of `canonical_name` from `merchant_name` (the seller's
store display name).** Only `sku_name` (product title) and the product image are valid naming signals. A
reseller's shop name appearing anywhere in `canonical_name` is always a defect — re-derive from the product's
own title and image, never the store name.

**Cross-validate short or ambiguous size matches before accepting them.** A size extracted from `sku_name`
that is 1-2 digits + unit, or that sits inside what reads as a brand/product-line token rather than being
clearly delimited (e.g., a brand like "G2G"/"Glad2Glow" contains digits a naive scan could misread as a size
"2g"), must be confirmed against `product_specification` or the image before being accepted. If the
`sku_name`-derived size doesn't independently confirm, prefer the confirmed source.
```

### Confidence: comparing against the stored previous verdict

```sql
UPDATE `sincere-hearth-273704.magpie_reference.product_taxonomy`
SET _meta = TO_JSON_STRING(STRUCT(
  true AS is_reviewed,
  CURRENT_TIMESTAMP() AS last_reviewed_at,
  IF(JSON_VALUE(_meta, '$.last_verdict') = @new_verdict, 'confident', 'unconfident') AS review_confidence,
  @new_verdict AS last_verdict
))
WHERE taxonomy_id = @taxonomy_id
```

First-ever review of a row always lands on `unconfident` (no prior verdict to agree with) — that's correct:
one data point is not confidence. A second review (a later run, since scope is incremental and confident rows
get skipped) that reaches the same verdict promotes it to `confident`. A review that flips the verdict stays
`unconfident` and — per the reset rule above — if the row was actually fixed as a result, `_meta` resets to
unreviewed anyway, so this branch mainly matters for the "reviewed twice, still uncertain, not obviously
wrong enough to auto-fix" case.

---

## 3. `targeted_qa_fix.sh` flow change

Today, `main()` hard-errors if no `docs/categories/<table>.md` exists, and `build_prompt`'s STEP 3 always
assumes a `## Targeted QA Fix Brief` section is present. New behavior:

```
resolve_category_file(table)
        │
   not found? ──yes──▶ ERROR, exit 1   (unchanged — can't get brand scope/context with no file at all;
        │                               by the time a category reaches review, headless_taxonomy.sh's
        │                               first_run has already created this file)
        │ found
        ▼
  does the file have a non-empty '## Targeted QA Fix Brief' section?
        │
   yes ─┴─▶ BRIEF MODE (unchanged): execute exactly what the Brief specifies
        │
   no ──┴─▶ AUTO-DISCOVERY MODE (new): Tier 1 SQL sweep + Tier 2 LLM review over
             product_taxonomy rows WHERE master_table = <table> AND
             (_meta IS NULL OR JSON_VALUE(_meta,'$.review_confidence') != 'confident')
```

Auto-discovery mode's prompt (STEP 3 replacement when no Brief exists):

1. Run the Tier 1 SQL sweep (above) scoped to the incremental `_meta` filter — cheap, no LLM needed for this
   part.
2. For every Tier 1 hit, and for a judgment sample of rows Tier 1 didn't flag (reading `sku_name` + image
   against `llm-extraction-rules.md`/`quality-standards.md` D1-D5, applying the two new §11 rules), decide
   `correct` or `wrong`.
3. `wrong` → fix directly (existing bulk-first behavior: bulk SQL correction where the fix is mechanical —
   e.g., strip a duplicated brand substring, fix casing, reorder fields — image-verified individual correction
   only where the fix itself requires re-reading the product). Reset `_meta` on the fixed row per the reset
   rule.
4. `correct` → update `_meta` per the confidence-comparison logic above. No row write beyond `_meta`.
5. Hard gates (G1, G2, G4, G5 — unchanged from today's `run_qa_gates`) still run at the end and still block
   the wrapper's independent `qa_report.sh` re-check before any universe refresh. This review pass does not
   relax those; it only changes *how work is found*, not the safety floor on what ships.

This is deliberately **not** bulk-first/coverage-first the way `headless_taxonomy.sh` now is — that script's
job is speed, this script's job is precision (the priority split already established: "quality is targeted
QA fix's most urgent priority... headless_taxonomy.sh's priority is to fill the gap"). Per-entry LLM judgment
in Tier 2 is appropriate here, not a shortcut to avoid.

`BLOCK_SIZE`/`MAX_TURNS` remain the existing 2nd/3rd CLI arguments (already supported) — no new argument
needed. A first-ever auto-discovery run against a large, never-reviewed category should raise `MAX_TURNS`
explicitly, same guidance already given for `headless_taxonomy.sh`'s large gaps.

---

## 4. Testing / Verification

- `bash -n script/targeted_qa_fix.sh` — syntax check.
- `bash script/test_targeted_qa_fix.sh` — extend with assertions on the new prompt-building branch: given a
  category file with no Brief section, `build_prompt` (or a new `build_auto_discovery_prompt` function,
  mirroring `headless_taxonomy.sh`'s two-prompt-builder split) must mention the Tier 1 SQL patterns, the
  `_meta` incremental-scope filter, and the confidence-comparison logic — same grep-assertion style used
  throughout this repo's test files.
- The migration itself: `bq query` a `SELECT _meta FROM product_taxonomy LIMIT 1` against a real project
  after applying it, confirm no error and `_meta IS NULL` on pre-existing rows (additive, non-breaking).
- No BQ-write-hitting test in scope for the review logic itself — same standing caveat every script design in
  this repo carries (real, costly production writes are a separate decision from building/reviewing the
  script).

---

## Open Follow-ups (explicitly out of scope for this change)

- Multi-judge-per-session voting for same-day confidence (considered, deferred — confirmed in brainstorming;
  cross-run verdict comparison is the cheaper v1).
- `_meta` on `product_taxonomy_map` for per-product-mapping review (no concrete need identified yet beyond
  the existing `brand_mismatch` column).
- Cross-category global sweep mode (`targeted_qa_fix.sh` stays `<TABLE>`-scoped, matching every other script
  in this repo).
- Retroactively running auto-discovery against every already-shipped category (`th_body_wash`'s pre-existing
  "(all variants)" entries, `sg_coffee`'s zero-GMV tail catch-alls) is an operational follow-up once this
  ships, not part of building it.
