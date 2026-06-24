# ADR-004 — Brand Matching Algorithm for product_brand_map

**Date:** June 2026
**Status:** Accepted
**Decided by:** Magpie Analytics

---

## Context

Every product in `master_clean_niq` needs a `brand_id` from `brand_dict` for market share analysis. The source `brand` column is:
- Blank for ~40–60% of products (sellers don't fill it)
- Inconsistently cased (`VASELINE`, `Vaseline`, `vaseline`)
- Contains noise (`Vaseline(วาสลีน)`, zero-width spaces, trailing tabs)
- Occasionally misspelled

We need a mapping strategy that is **correct over complete** — a wrong brand assignment corrupts market share calculations, while an unresolved product (`BRD-UNDEFINED`) is safely excluded from share calculations.

---

## Decision

Use a **three-method cascade** in priority order:

### Method 1 — BRAND_FIELD (confidence: HIGH)

When the `brand` column is filled:
1. Strip control characters, zero-width chars, Thai parenthetical suffixes
2. Lowercase, strip all punctuation, collapse whitespace
3. Look up in `brand_lookup` map

The `brand_lookup` map includes:
- All `canonical_name` values from `brand_dict`
- All raw brand variants from `MERGE` groups in `brand_review` (AUTO and manual decisions)

This means known variant forms (`"VASELINE"`, `"vaseline"`, `"Vaseline(วาสลีน)"`) all resolve to the same `brand_id` without fuzzy matching.

### Method 2 — PRODUCT_NAME_SCAN (confidence: HIGH or MEDIUM)

When `brand` is NULL, scan `sku_name` for known brand names:
1. Normalize `sku_name` same way as brand names
2. Try all n-gram windows (1 to N tokens, N = longest brand name in brand_dict)
3. **Longest patterns first** — prevents "Oral" matching before "Oral-B"
4. Position 0 → `HIGH`; any other position → `MEDIUM`

### Method 3 — FALLBACK (confidence: UNRESOLVED)

- `BRD-UNBRANDED`: sku_name or brand explicitly signals generic product
- `BRD-UNDEFINED`: brand could not be determined

---

## Why NOT fuzzy matching for PRODUCT_NAME_SCAN

Fuzzy matching on sku_name would increase recall but introduces false positives:
- `"baseline"` → fuzzy-matches `"Vaseline"` (edit distance 2)
- `"gasoline"` → fuzzy-matches `"Vaseline"` (edit distance 2)
- Product descriptions often reference competitors: `"better than Vaseline"`

A product assigned to the wrong brand has worse analytical impact than `BRD-UNDEFINED`. Analysts can exclude UNRESOLVED from share calculations; they cannot easily detect incorrect assignments.

Known brand variant typos are handled **at the brand_dict build stage** (Stage 02 duplicate detection), not at the product mapping stage.

---

## Why NOT exact match only (without normalization)

Pure exact match would fail on:
- `"VASELINE"` vs `"Vaseline"` (same brand, different casing)
- `"Oral-B"` vs `"Oral B"` (hyphen vs space)
- `"Kérastase"` vs `"Kerastase"` (sellers strip accents)
- `"Vaseline(วาสลีน)"` (Thai suffix appended)

Normalization resolves all of these without any ambiguity risk.

---

## Confidence framework for downstream use

| confidence | Recommended use |
|-----------|----------------|
| `HIGH` | Include in all market share calculations |
| `MEDIUM` | Include by default; exclude for high-stakes analysis requiring precision |
| `UNRESOLVED` | Always exclude from share denominator and numerator |

**Standard market share filter:**
```sql
WHERE confidence IN ('HIGH', 'MEDIUM')
  AND brand_id NOT IN ('BRD-UNDEFINED', 'BRD-UNBRANDED')
```

---

## Trade-offs accepted

| Trade-off | Accepted because |
|-----------|-----------------|
| ~5–10% of products → FALLBACK | These are low-quality listings; GMV impact is small |
| MEDIUM confidence may include some wrong assignments | Analyst can filter to HIGH-only if needed |
| No fuzzy matching → some typos in sku_name unresolved | Wrong match is worse than no match |
| Re-running Stage 03 required when brand_dict changes | Full replace per table is idempotent and fast enough |

---

## Alternatives considered

| Option | Rejected because |
|--------|-----------------|
| Fuzzy match on sku_name | Too many false positives; corrupts market share |
| LLM-based brand extraction | Expensive, latency, not auditable, hallucination risk |
| Manual mapping for blank brands | 40–60% of products × 43 tables = millions of rows |
| Per-category brand lists | Brands appear across categories; global brand_dict is more maintainable |
