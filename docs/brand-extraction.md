# Brand Extraction — How Products Get Their Brand Assignment

This document explains Stage 03 of the pipeline: how every product in `product_brand_map` gets a `brand_id`, and how Phase 5 LLM extraction corrects errors.

---

## Where Brand Assignment Lives

```
magpie_reference.product_brand_map
  composite key: (product_id, platform, country)
  one row per physical product per platform-country
```

A product has exactly one brand assignment. The same product_id appearing in multiple source tables (different categories, different pipelines) resolves to the same brand.

---

## Stage 03: Automated Brand Resolution Cascade

Built by `pipeline/03_product_mapping/build_product_brand_map.py`.

Three methods are tried in order, stopping at the first successful match:

```
1. BRAND_FIELD
   └─ brand_name column in source is filled → normalize → lookup in brand_dict
   └─ Result: source='BRAND_FIELD', confidence='HIGH'
   └─ Not available for TikTok (brand_name always NULL for TikTok)

2. PRODUCT_NAME_SCAN
   └─ brand_name is NULL → scan product_name/sku_name for known brand tokens
   └─ Start of title match → source='PRODUCT_NAME_SCAN', confidence='HIGH'
   └─ Mid-title match (word boundary) → confidence='MEDIUM'

3. FALLBACK
   └─ No signal found → assign BRD-UNDEFINED (cannot determine) or BRD-UNBRANDED (generic)
   └─ source='FALLBACK', confidence='UNRESOLVED'
```

### Source value terminology note

`source='HUMAN'` in this table does **not** mean a person reviewed the row. It is a legacy label for automated keyword-routing scripts from the Phase 5 seed phase. As of Jun 2026, no actual human review has been incorporated into the brand assignment pipeline.

Priority for conflict resolution (highest accuracy first):
```
LLM > BRAND_FIELD > HUMAN > PRODUCT_NAME_SCAN > FALLBACK
```

---

## How BRAND_FIELD Matching Works

`brand_name` from source data is cleaned and looked up in `brand_dict`:

1. **Normalize:** strip Thai parenthetical suffix `(วาสลีน)`, strip unicode zero-width spaces, lowercase, strip whitespace
2. **Exact match:** check brand lookup map (built from brand_dict canonical_name + alias list)
3. **Parent match:** if no direct hit, try stripping last word (handles "Vaseline Body" → "Vaseline")
4. **No match:** fall through to PRODUCT_NAME_SCAN

Fill rates by platform:
| Platform | brand_name fill rate |
|----------|---------------------|
| Lazada | 100% — enforced by Lazada listing requirements |
| Shopee | ~89% — optional field |
| TikTok | **0%** — column exists but always NULL |

---

## Phase 5: LLM Brand Correction

Phase 5 taxonomy extraction (Claude multimodal) reads every product image and captures `brand_from_image`. This is compared against the Stage 03 assignment:

```python
brand_mismatch = True
  if brand_from_image != brand_dict.canonical_name
  AND source IN ('PRODUCT_NAME_SCAN', 'FALLBACK')
  # BRAND_FIELD and HUMAN sources are trusted; mismatch not flagged for them
```

When `brand_mismatch = True`:
1. LLM-confirmed mismatches update `brand_dict` (correct canonical name)
2. `product_brand_map` row is updated with the correct `brand_id`
3. A partial universe re-run is triggered for the affected products

### Brand mismatch quality (as of Jun 2026)

| Metric | Value |
|--------|-------|
| Total LLM-mapped products | ~89,800 |
| True mismatches confirmed | 13 (0.015%) |
| False positives (body_wash API bug) | 75 |

The 0.015% true error rate means Stage 03 text extraction is highly accurate. The remaining error categories text cannot fix: cross-brand store contamination (brand A selling brand B) and structurally absent brand fields (TikTok).

---

## Platform Differences

| Feature | Shopee | Lazada | TikTok |
|---------|--------|--------|--------|
| brand_name fill | ~89% | 100% | 0% |
| Official store tier | `seller_type = 'Shopee Mall'` | `seller_type = 'Lazada Mall'` | No tier |
| Pass 1 strategy (Phase 5) | Official Mall stores | Official Mall stores | Skip — go to LLM Pass 2 directly |
| Brand extraction start | BRAND_FIELD | BRAND_FIELD | PRODUCT_NAME_SCAN |

---

## Key Rules

- **One brand per product.** Composite key `(product_id, platform, country)` → one `brand_id`. Multiple rows for the same physical product are a dedup error.
- **brand_raw is immutable.** The original `brand_name` from source is stored in `brand_raw` and never overwritten, even if later corrected by LLM.
- **BRD-UNDEFINED ≠ BRD-UNBRANDED.** UNDEFINED = couldn't determine brand (data gap). UNBRANDED = product is explicitly generic/white-label (intentional).
- **brand_dict is shared across all platforms and pipelines.** Nivea is Nivea whether found on Shopee TH or Lazada ID. No per-platform duplication of brand entries.

---

## Files

| File | Purpose |
|------|---------|
| `pipeline/03_product_mapping/build_product_brand_map.py` | Stage 03 extraction script |
| `pipeline/02_taxonomy_build/build_brand_dict.py` | Builds brand_dict from brand audit |
| `sql/schema/product_brand_map.sql` | Table DDL |
| `sql/migrations/001_add_platform_country_columns.sql` | Migration: NIQ → Intrepid key normalization |
