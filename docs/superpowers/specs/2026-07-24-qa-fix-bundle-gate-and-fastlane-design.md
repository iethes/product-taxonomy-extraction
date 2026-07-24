# Design: Bundle-Naming Gate Fix + Fast-Lane Recheck for `targeted_qa_fix.sh`

> Status: approved design, not yet implemented.
> Companion to [`script/targeted_qa_fix.sh`](../../../script/targeted_qa_fix.sh),
> [`script/qa_report.sh`](../../../script/qa_report.sh), and
> [`docs/superpowers/specs/2026-07-23-qa-fix-throughput-diagnosis-design.md`](2026-07-23-qa-fix-throughput-diagnosis-design.md)
> (the `qa_gate_exceptions` mechanism and the `fixed_pending_recheck` coverage bucket this design builds on).

---

## Problem

Four consecutive `targeted_qa_fix.sh shopee_sg_facial_cleanser 1000 300` auto-discovery sessions
(2026-07-23/24) each ended `QA gates failed — marking block FAILED_QA, skipping universe refresh`, every
single run, driven by the `canonical_name fields` gate. Reading the session's own QA History (not just the
gate counts) surfaced two distinct, independent problems:

**1. A genuine, recurring gate false positive on multi-item bundles.** `qa_report.sh`'s `canonical_name
fields` gate requires `pack_count > 1` entries to contain a literal `xN` substring in `canonical_name`. That
assumption is correct for "N identical units" packs but wrong for a documented, legitimate naming
convention: a bundle of *distinct* products/sizes, each written out by name (e.g. `SKU-141640`: "Torriden
DIVE IN Daily & Moisturizing 3-Piece Set (Toner 300ml + Serum 50ml + Cream 80ml)", `pack_count=3`, no literal
`x3` anywhere because each component is a single unit). Every one of the confirmed false-positive instances
(`SKU-141640`, `SKU-159829`, `SKU-160288/289/291/292`) has `is_bundle = true` in BigQuery — the schema already
has a purpose-built, correctly-populated field for exactly this case; the gate just doesn't check it. Because
new bundle products keep entering the review pool as more of the category's ~2,800 never-reviewed rows get
touched, this recurs on a fresh set of `taxonomy_id`s almost every session — `qa_gate_exceptions` (built for
one-off entities like the "888" brand) whack-a-moles this forever instead of closing it, since each new
bundle instance needs its own two-session confirmation cycle before it can be excepted.

**2. Confirmed-fixed rows compete with fresh rows for the same expensive judgment budget.** A row that was
fixed in a prior session has its `_meta` reset to `{"is_reviewed": false}` and needs one more clean review to
reach `confident` (per the two-agreeing-reviews rule). Today, that confirmation only happens if the row wins
a slot in STEP 3's GMV-prioritized Tier 2 sample — the same ~30-35-row-per-session budget that also has to
cover every genuinely new never-reviewed row. On `shopee_sg_facial_cleanser`, 250-285 rows are sitting in
`fixed_pending_recheck` per the last few runs, and only ~15-20 reach `confident` per session — most of that
backlog isn't stuck because it's wrong, it's stuck waiting for a Tier 2 slot it doesn't actually need, since
confirming a mechanical fix held is exactly what the cheap, always-runs-to-completion Tier 1 SQL sweep can
already check.

These are independent: fixing #1 only affects whether `GATE_AND_REFRESH` can succeed; fixing #2 only affects
how fast the `confident` count grows. Both are in scope for this design.

**Explicitly out of scope:** the underlying ceiling on Tier 2 throughput (~30-35 careful multimodal judgments
per session) is a real precision-vs-speed tradeoff, not a bug, and is not addressed here — this design only
removes the *unnecessary* competition for that budget from rows that don't need fresh judgment at all.

---

## Deliverable scope

| File | Change |
|------|--------|
| `script/qa_report.sh` | `canonical_name fields` gate's pack_count/xN clause gains an `is_bundle IS NOT TRUE` guard |
| `script/targeted_qa_fix.sh` | `build_auto_discovery_prompt`'s Tier 1 `canonical_field_mismatch` check gets the same guard (kept in sync, per existing "mirrors qa_report.sh exactly" precedent); new STEP 1C fast-lane recheck inserted before STEP 3; STEP 3 excludes rows STEP 1C already resolved |
| `script/test_targeted_qa_fix.sh` | New assertions for the `is_bundle` guard text and the STEP 1C fast-lane block |

---

## 1. Bundle-naming gate fix

### `qa_report.sh`

In the `CANON_FIELDS` query, change:

```sql
OR (pack_count > 1 AND NOT LOWER(canonical_name) LIKE CONCAT('%x', CAST(pack_count AS STRING), '%'))
```

to:

```sql
OR (pack_count > 1 AND is_bundle IS NOT TRUE AND NOT LOWER(canonical_name) LIKE CONCAT('%x', CAST(pack_count AS STRING), '%'))
```

This needs `is_bundle` selected in that query's inner `SELECT DISTINCT` (currently: `taxonomy_id,
canonical_name, product_line, sub_line, variant, size, pack_count` — add `is_bundle`).

Same guard, same precedent as the existing `is_multi_size IS NOT TRUE` guard on the `null_size` check —
a structured boolean field taking precedence over a generic text-pattern assumption.

### `build_auto_discovery_prompt`'s Tier 1 sweep (`canonical_field_mismatch`)

The mirroring clause inside the big `canonical_field_mismatch` boolean expression:

```sql
OR (pt.pack_count > 1 AND NOT LOWER(pt.canonical_name) LIKE CONCAT('%x', CAST(pt.pack_count AS STRING), '%'))
```

gets the same guard:

```sql
OR (pt.pack_count > 1 AND pt.is_bundle IS NOT TRUE AND NOT LOWER(pt.canonical_name) LIKE CONCAT('%x', CAST(pt.pack_count AS STRING), '%'))
```

Both queries already select `pt.*`-equivalent columns by alias, so `pt.is_bundle` is available without
further query changes beyond adding it to the `GROUP BY` list (the query already groups by every selected
non-aggregate column).

---

## 2. Fast-lane recheck for `fixed_pending_recheck` rows (new STEP 1C)

Inserted after STEP 1B (gate-exception handling) and before STEP 2 (Tier 1 sweep over the full worklist) —
following the existing precedent of inserting lettered sub-steps (STEP 1B, STEP 2b) rather than renumbering
the whole prompt.

```
STEP 1C — Fast-lane recheck for rows that were fixed in a prior session and are only waiting on one more
clean confirmation to become confident (identifiable as: _meta IS NOT NULL AND JSON_VALUE(_meta,
'$.review_confidence') IS NULL — the "fixed pending recheck" bucket qa_coverage_report.sh reports
separately). Run the exact same Tier 1 SQL sweep as STEP 2 below, scoped to just this subset:

SELECT pt.taxonomy_id, <same flag columns as STEP 2's Tier 1 sweep>
FROM `${PROJECT}.magpie_reference.product_taxonomy` pt
JOIN `${PROJECT}.magpie_reference.product_taxonomy_map` m ON m.taxonomy_id = pt.taxonomy_id
JOIN `${PROJECT}.magpie_reference.brand_dict` bd ON bd.brand_id = pt.brand_id
WHERE m.master_table = '${table}'
  AND pt._meta IS NOT NULL AND JSON_VALUE(pt._meta, '$.review_confidence') IS NULL
GROUP BY 1, <same GROUP BY columns as STEP 2>

For every row where every flag comes back FALSE, bulk-promote it directly — no LLM judgment, no image read,
no Tier 2 sample slot spent — using the exact same promotion logic as STEP 5:

UPDATE `${PROJECT}.magpie_reference.product_taxonomy` pt
SET _meta = TO_JSON_STRING(STRUCT(
  true AS is_reviewed,
  CURRENT_TIMESTAMP() AS last_reviewed_at,
  IF(JSON_VALUE(pt._meta, '$.last_verdict') = 'correct', 'confident', 'unconfident') AS review_confidence,
  'correct' AS last_verdict
))
WHERE pt.taxonomy_id IN ('SKU-XXXXXX', /* every fixed_pending_recheck row that came back Tier-1-clean this pass */)

Any row where a flag still trips is a regression or an incomplete prior fix, not a clean confirmation —
leave its _meta untouched here (STEP 2's worklist-wide sweep will flag it again the normal way, and it flows
into STEP 4's real fix path like any other flagged row). Do not spend Tier 2 judgment on a row this step
already promoted — STEP 3 below excludes it.
```

STEP 3's opening line gets one clause appended: "excluding any taxonomy_id STEP 1C already bulk-promoted this
session — they're resolved, don't spend judgment budget re-confirming them."

### Why this preserves the two-agreeing-reviews rule

STEP 1C reuses STEP 5's exact `UPDATE` shape unmodified: a row's *first* clean pass after a fix (prior
`_meta` has no `last_verdict` — STEP 4 wiped it) still lands on `unconfident` with `last_verdict='correct'`;
only a *second* consecutive clean pass — whether that's another STEP 1C fast-lane hit or a Tier 2 judgment —
promotes it to `confident`. Fast-laning doesn't skip the rule, it just makes both confirming passes cheap
instead of requiring a Tier 2 sample win.

### Precision tradeoff, stated plainly

A row promoted via STEP 1C never gets a fresh multimodal/text judgment — only confirmation that the same
mechanical checks Tier 1 already runs are clean. This is a deliberate, explicit choice (this cycle's own
scoping decision): it trades a small chance of missing a defect Tier 1's SQL can't detect (e.g. a subtle
wrong-type match) for materially faster convergence on the large `fixed_pending_recheck` backlog. Tier 1's
checks are the same ones already trusted repo-wide to auto-apply fixes without LLM judgment (STEP 2's own
framing: "no LLM judgment needed to detect it"), so this is consistent with the existing trust boundary, not
a new one.

---

## 3. Testing / Verification

- `bash -n script/qa_report.sh` and `bash -n script/targeted_qa_fix.sh` — syntax check.
- `bash script/test_targeted_qa_fix.sh` — extend with:
  - `build_auto_discovery_prompt`'s Tier 1 sweep text contains `is_bundle IS NOT TRUE` paired with the
    `pack_count > 1` xN check.
  - `build_auto_discovery_prompt`'s output contains `STEP 1C` and the `fixed_pending_recheck` bucket's exact
    SQL predicate (`JSON_VALUE(_meta, '$.review_confidence') IS NULL`).
  - STEP 3's text contains "STEP 1C already bulk-promoted" (the exclusion clause).
- `script/qa_report.sh` structural check (same convention as the prior design's Task 2): grep for
  `is_bundle IS NOT TRUE` in the `CANON_FIELDS` query block specifically (not just anywhere in the file).
- Manual, against a live table with a known bundle false positive: run `./script/qa_report.sh
  shopee_sg_facial_cleanser` before and after, confirm `canonical_name fields`'s failing count drops by
  exactly the number of `is_bundle=true` rows it was previously flagging (cross-check via a direct query
  before applying, so the drop is attributable to this fix and not a coincidental prior session's cleanup).
- Manual: after a live `targeted_qa_fix.sh` run, compare `qa_coverage_report.sh`'s `fixed_pending_recheck`
  count before and after — confirm it drops by roughly the number of Tier-1-clean rows STEP 1C found, and
  that `confident` grows by more than the historical ~15-20/session baseline.

---

## Open Follow-ups (explicitly out of scope for this change)

- Raising Tier 2's per-session sample size or turn budget to increase judgment throughput on genuinely new
  never-reviewed rows — a scope/cost tradeoff for the user to decide separately, not an engineering fix.
- The `null_size` backlog (665-716 rows re-flagged and deferred every session on this category, zero
  extractable signal in `sku_name`) and STEP 2b's promo-sweep overhead (13,661 raw hits / 278 distinct,
  re-derived from scratch every run) — both real, both contribute to the Tier 2 budget being thin, neither
  addressed here since the user scoped this cycle to the bundle gate and the fast lane specifically.
- Whether a whole-category clean-bill gate is the right model for triggering universe refresh on a category
  that's still mostly unreviewed (vs. propagating only `confident` rows incrementally) — a bigger
  architectural question flagged during brainstorming but not part of what the user asked this cycle to fix.
