# ADR-003: Brand Cleaning and Labelling Pipeline

**Date:** 2026-05-30
**Status:** Accepted

---

## Context

The brand column in `master_clean_niq` has three types of quality issues:
1. **Inconsistent naming** — same brand in different cases/spellings
2. **Populated but noisy** — Thai parenthetical suffixes, unicode zero-width spaces, escape characters
3. **Blank** — brand field not filled by seller, but brand may be visible in `product_name`

We need a pipeline that resolves all products to a `taxonomy_id` before appending to the universe.

---

## Decision

A three-phase sequential pipeline, each writing to `magpie_reference.product_brand_map`:

### Phase 1 — Brand Field Match (`source = BRAND_FIELD`)

For products where `brand` is not blank:
1. Apply brand cleaning: `re.sub(r'\s*[\(\（][^\)\）]*[\)\）]\s*$', '', brand).strip()` — removes Thai suffixes
2. Normalise: strip unicode zero-width chars, collapse whitespace, lowercase for comparison
3. Exact match against known variants in `brand_dict`
4. → Match found: write with `confidence = HIGH`
5. → No match: write with `confidence = LOW`, flag for human review queue

### Phase 2 — Product Name Scan (`source = PRODUCT_NAME_SCAN`)

Only for products that were blank in Phase 1. Requires `product_name` column in source tables.

1. Tokenize `product_name` (split on spaces, punctuation)
2. For each canonical name in `brand_dict`, check:
   - **Tier A:** Canonical name found in first 2 tokens → `confidence = HIGH` (for PRODUCT_NAME_SCAN)
   - **Tier B:** Canonical name found anywhere, word-boundary match → `confidence = MEDIUM`
   - **Tier C:** Fuzzy match (≥ 0.85 similarity) anywhere → `confidence = LOW`, queue for review
3. Short brand names (≤ 3 chars: QV, EOS, 3M) require word-boundary match only to avoid false positives

### Phase 3 — Fallback (`source = FALLBACK`)

For products still unresolved after Phases 1 and 2:
- Assign `BRD-UNBRANDED` if product characteristics suggest generic (e.g. no brand field ever populated across all models, generic category name in product title)
- Assign `BRD-UNDEFINED` for everything else
- `confidence = UNRESOLVED`

---

## The Two Fallback Labels

| taxonomy_id | canonical_name | Meaning | Why different |
|-------------|---------------|---------|---------------|
| `BRD-UNBRANDED` | Unbranded | Product is genuinely generic/white-label | Analytically meaningful — represents commoditisation |
| `BRD-UNDEFINED` | Undefined | Brand cannot be determined from available data | Data quality gap — should not be counted in brand share |

Mixing these would show inflated "unbranded" market share in categories where it's actually a data gap.

---

## Confidence Levels

| confidence | Meaning |
|-----------|---------|
| `HIGH` | BRAND_FIELD exact match, or PRODUCT_NAME_SCAN start-of-title, or HUMAN |
| `MEDIUM` | PRODUCT_NAME_SCAN anywhere in title |
| `LOW` | Fuzzy match — should be reviewed before promoting to MEDIUM |
| `UNRESOLVED` | FALLBACK — no brand signal found anywhere |

---

## Alternatives Considered

**Single-pass regex on brand field only:** Too many blanks remain — Phase 1 alone leaves ~30–40% of products without a brand in some TH categories.

**LLM-based brand extraction from product_name:** Higher accuracy but higher cost and latency. Deferred to a future phase. The current token-scan approach covers the easy cases (brand clearly in title) cheaply.

**Fuzzy match brand field against taxonomy:** Risk of false merges at scale. Only applied as a LOW-confidence fallback with human review gate.

---

## Consequences

- Every product in the universe has a `taxonomy_id` — no NULLs
- Confidence column lets analysts filter to only HIGH/MEDIUM when doing brand share analysis
- `brand_raw` always preserved — any Phase 1-3 result can be audited and corrected
- Phase 2 is blocked until we confirm `product_name` column exists in `master_clean_niq` schema
