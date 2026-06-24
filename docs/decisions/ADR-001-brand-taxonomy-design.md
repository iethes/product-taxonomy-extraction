# ADR-001: Brand Taxonomy Design

**Date:** 2026-05-30
**Status:** Accepted

---

## Context

Brand data in `master_clean_niq` comes from Shopee product specs and has significant quality issues:
- Same brand written in multiple cases/spellings (Vaseline, VASELINE, vaselíne)
- Thai brands with parenthetical Thai-language suffixes: `"Eucerin(ยูเซอรีน)"`
- Many blank brand fields — especially in TH categories
- No canonical brand identifier — just a free-text string

We need a system to resolve these to canonical brands before building a market share universe, so that brand market share figures are accurate.

---

## Decision

Build a **two-table taxonomy system** in BigQuery:

1. **`magpie_reference.brand_dict`** — canonical brand master
2. **`magpie_reference.product_brand_map`** — maps `(product_id, master_table)` to a `taxonomy_id`

The taxonomy is **global** (not per-category). One entry for Vaseline serves all 43 categories. Category context lives on the mapping side via `master_table`.

**taxonomy_id format:** `BRD-{SCOPE}-{5digits}`
- `BRD-GLOBAL-*` for brands in both SG and TH
- `BRD-SG-*` for SG-only
- `BRD-TH-*` for TH-only
- `BRD-UNDEFINED` reserved for unresolvable blanks
- `BRD-UNBRANDED` reserved for genuinely generic/white-label products

---

## Alternatives Considered

**Per-category taxonomy:** One brand_dict per end category. Rejected — creates 94+ Vaseline entries, makes cross-category brand analytics impossible.

**Fix brand column in-place in BQ:** Update the `brand` column in `master_clean_niq` tables directly. Rejected — DML on large partitioned BQ tables is expensive; destroys original data; irreversible.

**Store taxonomy in Google Sheets only:** Rejected — product_brand_map will be millions of rows, far beyond Sheets' limits.

---

## Consequences

- Product market share analysis can group all Vaseline variants correctly
- Cross-category brand totals become possible (Nivea total GMV across shampoo + body lotion + facial care)
- Original `brand_raw` is preserved in `product_brand_map` — always auditable
- New products added to the universe need a mapping pipeline run to get a `taxonomy_id`
- Requires a curation process to keep `brand_dict` current
