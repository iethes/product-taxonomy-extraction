# ADR-006 — Normalize product_brand_map and product_taxonomy_map to (product_id, platform, country) composite key

**Status:** Accepted  
**Date:** 2026-06-30  
**Deciders:** Magpie Analytics

---

## Context

The NIQ pipeline (`master_clean_niq`) encodes all three identifiers — platform, country, and category — into a single `master_table` column (e.g. `shopee_th_suncare`). This was used as the composite key: `(product_id, master_table)`.

The Intrepid pipeline (`intrepid_pipeline_clean_product_level`) expands coverage to three platforms (Shopee, Lazada, TikTok Shop) and six countries (ID, MY, PH, SG, TH, VN). Critically:

1. **Intrepid source tables already carry explicit `platform` and `country` columns** — they are first-class fields, not embedded in the table name.
2. **The same physical product** (same product_id, same platform, same country) can appear in multiple source category tables (e.g. a product in both `shopee_th_suncare` in NIQ and `shopee_th_sunscreen` in Intrepid). Under the old key these look like different rows but represent the same product — causing duplicate brand assignments and wasted LLM extraction work.
3. **TikTok brand_name is 0% filled** — `brand_name` column exists in TikTok source tables but is always NULL. The BRAND_FIELD extraction step cannot fire for TikTok at all.
4. **A product has exactly one brand.** Storing multiple brand rows for the same physical product (across different source tables) is a data model defect, not a feature.
5. **A product has exactly one taxonomy classification.** The "dual-mapped" bug we have manually fixed throughout Phase 5 is the same defect — two taxonomy rows for one product.

---

## Decision

### 1. Change composite key to `(product_id, platform, country)`

In both `product_brand_map` and `product_taxonomy_map`:

| Column | Old role | New role |
|--------|---------|---------|
| `product_id` | PK component | PK component (unchanged) |
| `master_table` | PK component | Metadata — "first source table this product was seen in" |
| `platform` | (not in table) | **New PK component** |
| `country` | (not in table) | **New PK component** |

Logical unique constraint (enforced by pipeline code, not BQ schema):
- `product_brand_map`: one `brand_id` per `(product_id, platform, country)`
- `product_taxonomy_map`: one `taxonomy_id` per `(product_id, platform, country)`

### 2. Add explicit `platform` and `country` columns

Both tables get two new columns:
- `platform STRING` — `'Shopee'`, `'Lazada'`, `'TikTok Shop'`
- `country STRING` — `'SG'`, `'TH'`, `'ID'`, `'MY'`, `'PH'`, `'VN'`

### 3. Keep `master_table` column (demoted to metadata)

`master_table` remains in both tables as the name of the source table the product was first encountered in. It is still useful for debugging and tracing a row back to its origin.

### 4. Backfill existing NIQ rows

All NIQ rows have `master_table LIKE 'shopee_{country}_{category}'`. Backfill:
```sql
UPDATE product_brand_map
SET platform = 'Shopee',
    country  = UPPER(SPLIT(master_table, '_')[SAFE_OFFSET(1)])
WHERE platform IS NULL;
```

### 5. Dedup NIQ rows to the new key

Some products appear in multiple NIQ source tables (e.g. same product_id in both `shopee_th_shampoo` and `shopee_th_conditioner`). After backfill, deduplicate to one row per `(product_id, platform, country)` using this priority:

```
LLM > BRAND_FIELD > HUMAN > PRODUCT_NAME_SCAN > FALLBACK
Within same source: higher confidence wins
Tiebreaker: earlier mapped_at (first encountered)
```

### 6. Intrepid uses the same tables

No separate `intrepid_product_brand_map`. The shared `magpie_reference.product_brand_map` covers both pipelines. When processing an Intrepid table, check for existing `(product_id, platform, country)` rows first — if already mapped from NIQ, skip extraction entirely.

---

## Source value clarification

The `source` column in both tables uses these values:

| source | What it actually means |
|--------|----------------------|
| `BRAND_FIELD` | `brand_name` column was filled in source data — looked up directly in brand_dict |
| `PRODUCT_NAME_SCAN` | Automated regex scan of `product_name`/`sku_name` for known brand tokens |
| `HUMAN` | Automated keyword-routing script (legacy name — **no actual human review has occurred**) |
| `LLM` | Claude multimodal extraction — reads product image + text |
| `FALLBACK` | No signal found — assigned `BRD-UNDEFINED` or `BRD-UNBRANDED` |

**Important:** `source='HUMAN'` does NOT mean a person reviewed the row. It is an automated text-matching method from the keyword seed scripts. It is labelled 'HUMAN' as a legacy name from when these scripts were distinguished from the algorithmic BRAND_FIELD/PRODUCT_NAME_SCAN cascade. No actual human review has been incorporated into the pipeline as of Jun 2026.

Priority order for dedup (highest accuracy first): `LLM > BRAND_FIELD > HUMAN > PRODUCT_NAME_SCAN > FALLBACK`

---

## TikTok-specific design

TikTok's `brand_name` is always NULL. The extraction cascade is shorter:

```
Standard (Shopee/Lazada):  BRAND_FIELD → PRODUCT_NAME_SCAN → LLM → FALLBACK
TikTok:                     PRODUCT_NAME_SCAN → LLM → FALLBACK
```

TikTok also has no official-store tier (all listings are `seller_type = 'TikTok Shop'`). For Phase 5 taxonomy extraction, skip Pass 1 (official stores) and go directly to LLM Pass 2 for top-GMV brands.

---

## brand_dict scope expansion

The `country_scope` field in `brand_dict` currently uses `GLOBAL`, `SG`, `TH`. Add new country codes as Intrepid brands are encountered: `ID`, `MY`, `PH`, `VN`. No schema change required — column is already STRING.

---

## Consequences

**Positive:**
- NIQ brand assignments (1.2M rows) are reused for Intrepid products — no re-extraction for already-known products
- Dual-mapped is a structural violation at the data model level, not a manual audit task
- Cross-platform analytics work with `WHERE platform = 'TikTok Shop' AND country = 'ID'` without string parsing
- BigQuery clustering on `(platform, country)` gives efficient filtering at Intrepid scale

**Negative:**
- Migration required before running Intrepid extraction
- All pipeline scripts that insert into `product_brand_map` must pass `platform` and `country` — NIQ scripts need updating
- All queries that filter by `master_table` should add `platform`/`country` filters instead where performance matters
