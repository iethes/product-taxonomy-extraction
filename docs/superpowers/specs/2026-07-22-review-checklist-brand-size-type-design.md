# Design: Review Checklist Round 3 — Size Coverage, Garbled Brands, and Type-Conflict Judgment

> Status: approved design, not yet implemented.
> Companion to [`docs/superpowers/specs/2026-07-21-taxonomy-review-loop-design.md`](2026-07-21-taxonomy-review-loop-design.md)
> (the review loop this extends), [`script/targeted_qa_fix.sh`](../../../script/targeted_qa_fix.sh),
> [`docs/quality-standards.md`](../../quality-standards.md), [`docs/llm-extraction-rules.md`](../../llm-extraction-rules.md),
> [`docs/product-lifecycle.md`](../../product-lifecycle.md) §4 (match-or-create gates), and
> [`docs/brand-extraction.md`](../../brand-extraction.md).

---

## Problem

Stakeholder review (2026-07-22) of four products found four distinct defect classes, none of which the
current Tier 1/Tier 2 checklist catches:

- **`22501764599`** — a baby *shampoo* listing mapped to a *Body Wash / Shower Gel* taxonomy entry
  (`"Perfect Body Wash / Shower Gel Multiple Variants"`), not a naming defect but a wrong-entry-type routing
  defect. Also carries a stale "Multiple Variants" stub and a missed size that's sitting in *both*
  `product_specification` and `product_description` — not even an image-only miss.
- **`16254994627`** — size visible on the product image (400ml), never extracted.
- **`7155345414`** — brand resolved to garbled text (`"12/+＝"`). Stakeholder's own diagnosis: the
  reseller's own watermark/logo is visually larger than the actual on-package brand text in the photo.
- **`26143837772`** — `canonical_name` correctly says "Enfant," but `product_taxonomy.brand_id` resolves to
  `BRD-UNDEFINED`.

This is Round 3 of the same Tier 1 SQL + Tier 2 LLM checklist extension pattern from the two prior rounds
(canonical-field-mismatch, multi-text/flag consistency, pack-count-promo detection) — most of these fit the
same mechanism. One (the type-conflict routing defect) deliberately does not get a new SQL heuristic, per
explicit direction during brainstorming: a new keyword-based filter risks the same "silently drop what
doesn't match a pattern" trap already fixed once this engagement (the coverage-scan keyword-prefilter
problem). Tier 2 judgment gets sharper instead of Tier 1 gaining a new heuristic.

---

## Deliverable scope

| File | Change |
|------|--------|
| `docs/llm-extraction-rules.md` | New §11 rule: reseller watermark/logo must never be read as the product's brand, regardless of relative size in the photo. Changelog entry. |
| `docs/quality-standards.md` | Cross-reference note: D4 is now wired into Tier 1 (mirrors the existing D5/D3 notes from Round 2). |
| `script/qa_report.sh` | New `GARBAGE_BRAND` hard gate (deterministic, zero-tolerance — same class as placeholder-leak). `null_size` (D4) is **not** added here — see §2 below for why. |
| `script/targeted_qa_fix.sh` | Two new Tier 1 flags (`null_size`, `garbage_brand`) in the main sweep; STEP 3 gains an explicit type-conflict judgment requirement; STEP 4 gains branching guidance for `wrong_field_order` (reorder text vs. fix `brand_id` — two different root causes, two different fixes). |
| `script/test_targeted_qa_fix.sh` | Tests for all of the above. |

No changes to `headless_taxonomy.sh` — the new §11 rule reaches it automatically (both its prompts read
`docs/llm-extraction-rules.md` in full, same reasoning as every prior rule addition this engagement).

---

## 1. Type-conflict routing — Tier 2 judgment gets explicit, no new SQL check

**Why no Tier 1 heuristic:** a SQL keyword-clash check (e.g. `canonical_name` has "shower gel"/"body wash"
tokens while `sku_name` has "shampoo") would need a category-specific keyword taxonomy maintained
indefinitely, and — critically — if implemented as a *scope filter* rather than a pure flag, risks silently
excluding exactly the miscategorized products it should catch (the same failure shape `headless_taxonomy.sh`'s
keyword-prefilter bug had). Rejected per explicit direction.

**The fix:** STEP 3's judgment instructions currently just say "judge against the rules" — too vague to
reliably catch a type mismatch introduced by bulk text-matching (Pass 2's efficiency mechanism can produce a
false type-match when text overlaps but the actual product differs, e.g. a brand with both a body-wash line
and a shampoo line). Add an explicit, mandatory check to every Tier 2-sampled row:

> For every row you judge, explicitly check whether the matched/reused entry's product **type** genuinely
> matches `sku_name` and the image — not just whether the name/structure looks right. This is the same
> conflict class as hard gate G3 (`docs/quality-standards.md` §4 — wet↔dry, lotion↔oil, paste↔wash) and the
> TYPE GATE in `docs/product-lifecycle.md` §4.2's match-or-create decision tree, just for this category's own
> product types (e.g. shampoo vs. body wash/shower gel). Bulk text-matching can produce a superficially
> plausible but wrong-type match when a brand carries multiple product lines with overlapping vocabulary — a
> match that "sounds right" from a text diff is not verified until the type is confirmed. A wrong-type match
> is never a partial credit — reroute to the correct existing entry, or mint a new one; do not rename in place.

This is additive prose only — no new query, no new column, no change to what gets sampled.

---

## 2. D4 size coverage (`null_size`) — new Tier 1 flag, Tier-1-sweep only

`docs/quality-standards.md`'s D4 dimension already documents the exact check (`size IS NULL AND is_multi_size
IS NOT TRUE`) but — like D5 before it — was never wired into any automated check. Add as an 8th flag in the
main Tier 1 sweep (taxonomy-grain, no new join needed — `pt.size`/`pt.is_multi_size` are already in scope):

```sql
(pt.size IS NULL AND pt.is_multi_size IS NOT TRUE) AS null_size
```

Requires re-adding `pt.is_multi_size` to the `GROUP BY` list (removed in the prior round when the
flag-conditional multi-text check was reverted; needed again now for this flag).

**Not added to `qa_report.sh` as a hard gate.** `docs/quality-standards.md` §3 frames D1–D6 as *scores with
targets* ("≥95%"), not zero-tolerance invariants like G1–G6 — the one existing threshold-style check in
`qa_report.sh` (`structured-fields NULL% ≤ 50`) already reflects this distinction. `null_size`'s *detection*
is deterministic (cheap to flag), but its *fix* requires genuine per-product signal-reading (text → image →
spec → description per §2's priority chain) and isn't something that should block a universe refresh outright
the way a structural defect like placeholder-leak or a garbled brand does. Same reasoning already applied to
pack-count-promo (D5) in Round 2 — stays a Tier 1 discovery mechanism, not a hard gate.

---

## 3. Garbled/anomalous brand entries (`garbage_brand`) — new Tier 1 flag + `qa_report.sh` hard gate

Detects when the *resolved brand* (`brand_dict.canonical_name`, via `product_taxonomy.brand_id`) contains no
letters at all — catches `"12/+＝"`-style noise without false-positiving on legitimate alphanumeric brands
(`"3M"`, `"7-Eleven"`, `"L'Oreal"` all contain a letter and correctly pass):

```sql
NOT REGEXP_CONTAINS(bd.canonical_name, r'[\p{L}]') AS garbage_brand
```

Verified the logic locally (PCRE, close enough to BigQuery's RE2 for the character-class semantics — `\p{L}`
matches any Unicode letter, Thai or Latin): correctly flags `"12/+＝"`, correctly clears `"3M"`, `"7-Eleven"`,
`"L'Oreal"`. **`\p{L}` support in BigQuery's actual RE2 engine needs a live confirmation query before this
ships** — same standing caveat every regex in this engagement carries for untestable-from-sandbox behavior; if
`\p{L}` turns out unsupported, fall back to an explicit range (`[a-zA-Zก-ฮ]`, Latin + Thai consonants).

Unlike `null_size`, this **is** added to `qa_report.sh` as a hard gate — a nonsensical brand string is never
acceptable (no legitimate exception scenario, unlike GWP-ambiguous pack-count language), the same class of
deterministic, zero-tolerance defect as placeholder-leak.

**Root cause and prevention:** the stakeholder's own diagnosis — a reseller's watermark/logo overlay,
visually larger than the actual on-package brand text — being misread as the brand. New rule in
`docs/llm-extraction-rules.md` §11:

> **A reseller's own watermark, logo overlay, or store-branding stamp on a product photo is never the
> product's brand, regardless of how large or prominent it is in the frame relative to the actual packaging
> text.** Only text/logo that is part of the original product packaging design counts as a brand signal. If
> the packaging's own brand text is small, partially obscured, or ambiguous, prefer `sku_name` or
> `product_specification` over guessing from a prominent overlay — never resolve a brand from the most
> visually dominant text in the image without confirming it's actually printed on the product itself.

**Fix guidance (STEP 4):** re-read the image applying the new §11 discipline, find or create the correct
`brand_dict` entry, update `product_taxonomy.brand_id`, and correct `canonical_name` to start with the real
brand (unlike the `wrong_field_order` branch below, both fields are wrong here and both need fixing).

---

## 4. `brand_id` → reserved placeholder while `canonical_name` has real content — fix-guidance branch, no new check

**Not a detection gap.** The existing `wrong_field_order` flag (`NOT STARTS_WITH(LOWER(TRIM(pt.canonical_name)),
LOWER(bd.canonical_name))`) already fires here: `brand_dict.canonical_name` for `BRD-UNDEFINED` is literally
`"Undefined"` (`docs/data-dictionary.md`'s reserved brand_ids table), and `"Enfant Baby Wipes..."` doesn't
start with `"undefined"`. The gap is in the *fix guidance*, which currently assumes the reorder-text case
(e.g. the Indonesia first-category field-order bug). Add a branch to STEP 4:

> `wrong_field_order` has two different root causes needing two different fixes — check which one before
> acting:
> - **Text is genuinely out of order** (e.g. `"Size Type Multiplier"` instead of `"Brand Product-Line Size
>   xN"`): reorder `canonical_name` to match the established template. `brand_id` itself is correct.
> - **`brand_id` resolves to `BRD-UNDEFINED`/`BRD-UNBRANDED` while `canonical_name` clearly states a real,
>   identifiable brand name** (e.g. `brand_id` → "Undefined" but `canonical_name` says "Enfant..."):
>   `canonical_name` is already correct — do **not** touch it. The defect is `brand_id`: look up the correct
>   brand in `brand_dict` (exact or close name match against the brand already stated in `canonical_name`),
>   or create a new `brand_dict` entry if it genuinely doesn't exist yet, and update `product_taxonomy.brand_id`
>   to point there instead.

This is prose-only guidance attached to an existing flag — no new SQL, no new column, no new gate.

---

## Testing

- `bash script/test_targeted_qa_fix.sh` extended with assertions for: `null_size` present in the Tier 1 sweep;
  `garbage_brand` present with the `\p{L}` check; STEP 3 contains the type-conflict/G3 requirement; STEP 4
  contains the two-branch `wrong_field_order` guidance and the §11-referencing garbled-brand fix guidance.
- `bash -n script/targeted_qa_fix.sh` / `script/qa_report.sh` — syntax checks.
- `grep` verification on the two doc edits (new §11 rule present, D4 cross-reference note present).
- No BQ-hitting test in scope — same standing caveat every script change in this engagement carries. The
  `\p{L}` RE2-support question specifically should be confirmed with a throwaway `SELECT
  REGEXP_CONTAINS('12/+＝', r'[\p{L}]')` on a live BigQuery connection before the first real run touches this
  flag; if it returns an error rather than `false`, swap in the ASCII+Thai-range fallback noted in §3 before
  shipping.

---

## Open Follow-ups (explicitly out of scope for this change)

- No cross-category audit of existing entries for the type-conflict pattern (e.g., scanning all shampoo/body
  wash categories for suspicious bulk-matched entries) — Tier 2's sharpened judgment catches these as they're
  sampled, going forward; a dedicated backfill sweep is a separate decision.
- `product_brand_map` (Stage 03's brand assignment, a different table from `product_taxonomy.brand_id`) is
  untouched by this design — `26143837772`'s fix is scoped to `product_taxonomy.brand_id` only, per
  `product-lifecycle.md`'s explicit "these are deliberately separate" resolution design.
