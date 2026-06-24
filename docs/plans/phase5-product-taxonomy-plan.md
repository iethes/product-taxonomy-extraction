# Phase 5 — Product Taxonomy Plan

**Date:** June 2026
**Status:** Strategy confirmed — execution in progress (shopee_th_suncare Apr 2026 next)
**Author:** Magpie Analytics
**Reviewers:** CDO, Market Insight
**Last updated:** Jun 20 2026 — LLM strategy locked, text similarity removed, see Decision Log below

---

## Executive Summary

Phase 5 adds a product-level taxonomy layer on top of the existing brand layer. The goal is to consolidate the same physical product across multiple Shopee listings (different merchants, same product) into a single canonical identifier. Extraction uses multimodal LLM (image + original listing text), scoped to the top 10 brands by GMV, processed in two passes — official/brand stores first, then other sellers. The canonical name follows the structure `Brand · Product Line · Sub-line · Variant · Size`, with NULL fields and boolean flags when a listing covers multiple variants or sizes. Two new BQ tables: `product_taxonomy` (canonical master) and `product_taxonomy_map` (product_id → taxonomy_id).

---

## Problem Statement

The same physical product is listed by multiple merchants on Shopee, each with a different listing title, product_id, and image. Without SKU consolidation:

- "How many units of Senka Perfect Whip Original 120g sold on Shopee TH in April?" — uncountable
- "What is La Roche-Posay Anthelios UVMUNE 400 Oil Control's share vs. Anti-Dark Spots?" — impossible
- "What is the price spread of MizuMi UV Water Serum 40g across merchants?" — broken

**Illustrative example — 3 listings, 1 physical product:**

| product_id | sku_name (truncated) | merchant |
|------------|---------------------|----------|
| 111 | Ready Stock! Senka Perfect Whip (100g/120g) Original / Fresh / Acne Care... | TopSecret Shop |
| 222 | [In Stock] Senka Perfect Whip Face Wash Deep Cleansing 120g Multiple Range | Merchant B |
| 333 | SG In Stock Senka Perfect Whip Facial Cleanser 120g Deep Cleansing Face Wash | Merchant C |

All three map to the same taxonomy_id: **`Senka Perfect Whip`** (is_multi_variant=TRUE, is_multi_size=TRUE due to listing-level ambiguity).

---

## Goals & Success Criteria

| Goal | Success Metric |
|------|---------------|
| Consolidate top-brand products across merchant listings | ≥ 80% of top 10 brand GMV has a taxonomy_id |
| Clean canonical name per entry | Zero duplicate taxonomy entries for the same physical product |
| Auditable extraction | Every mapping row has `confidence` + `llm_raw` audit field |
| Precision over recall | UNRESOLVED is safer than a wrong assignment |

---

## Method

### Input Preparation — Brand-First Filtering

The pipeline starts from the existing Phase 3 output, not from raw `master_clean_niq`:

```sql
-- Step 1: Brand ranking (GMV threshold — GWP zeroed)
SELECT
  pbm.brand_id,
  bd.canonical_name                                               AS brand_canonical,
  SUM(CASE WHEN t.flag_GWP = FALSE THEN t.gmv_monthly ELSE 0 END) AS gmv_total_excl_gwp
FROM master_clean_niq.{table} t
JOIN magpie_reference.product_brand_map pbm
  ON t.product_id = pbm.product_id AND pbm.master_table = '{table}'
JOIN magpie_reference.brand_dict bd
  ON pbm.brand_id = bd.brand_id
WHERE t.month = '{month}'
GROUP BY pbm.brand_id, bd.canonical_name
ORDER BY gmv_total_excl_gwp DESC
-- → user confirms which brands are in scope

-- Step 2: Product-level fetch for in-scope brands
-- GWP products excluded entirely; GWP GMV zeroed in cumulative for threshold calc
SELECT
  t.product_id,
  t.merchant_badge,
  t.merchant_name,
  pbm.brand_id,
  bd.canonical_name                                               AS brand_canonical,
  pbm.source                                                      AS brand_source,
  MIN(t.sku_name)                                                 AS sku_name,
  ARRAY_AGG(DISTINCT t.option_name IGNORE NULLS ORDER BY t.option_name) AS option_names,
  REPLACE(REPLACE(MIN(t.image), '"', ''), ' ', '')                AS image_url,
  SUM(CASE WHEN t.flag_GWP = FALSE THEN t.gmv_monthly ELSE 0 END) AS gmv_total
FROM master_clean_niq.{table} t
JOIN magpie_reference.product_brand_map pbm
  ON t.product_id = pbm.product_id AND pbm.master_table = '{table}'
JOIN magpie_reference.brand_dict bd
  ON pbm.brand_id = bd.brand_id
WHERE t.month = '{month}'
  AND t.flag_GWP = FALSE               -- exclude GWP products entirely from all passes
  AND t.flag_discontinued = FALSE
  AND pbm.brand_id IN ({confirmed_brand_ids})
  -- Pass 1 only: add AND t.merchant_name IN ({brand_official_store_names})
  -- ⚠️  Do NOT use LIKE '%official%' — catches multi-brand retailers (Watsons, BEAUTRIUM, Sasa, etc.)
  -- ⚠️  Do NOT use LIKE '%{brand}%'  — misses parent-company stores (Biore → 'KAO Beauty & Personal Care')
  -- Build allowlist first: SELECT DISTINCT merchant_name WHERE merchant_badge='Shopee Mall' AND brand_id=...
GROUP BY t.product_id, t.merchant_badge, t.merchant_name,
         pbm.brand_id, bd.canonical_name, pbm.source
ORDER BY gmv_total DESC
```

Key points:
- **`flag_GWP = TRUE` → GMV zeroed in all cumulative calculations** — GWP products never count toward brand GMV rank or product threshold eligibility; excluded from all passes entirely
- **`brand_canonical`** (from `brand_dict`) is the brand input to the LLM — already clean, no Thai suffix stripping needed
- **`source`** (from `product_brand_map`) is included to determine whether brand mismatch check applies
- **`sku_name`** is the original listing title (not `sku_name_EN` which is machine-translated)
- **`option_name`** values are collected as a list per product_id — the column in `master_clean_niq` is `option_name` (Shopee's term for model/variant option), not `model_name`
- If `option_names` has one distinct value → single variant. If multiple → multi-variant input to LLM.

---

### Brand Scope

**Not a fixed list.** Brands in scope for each run are determined by GMV threshold query for the target category and month. This produces a ranked list; all brands above the threshold are in scope.

The "official store" step is only performed for brands that appear in this GMV threshold list — not for all brands in the category.

---

### Two-Pass Extraction Pipeline

Extraction is ordered by source quality, not filtered. **Both passes use full LLM multimodal — there is no text similarity step.**

> **Why no text similarity in Pass 2:** Text similarity matching is the same failure mode as keyword routing — it matches on surface text without image signal, produces wrong assignments when product names are similar (e.g. "Oil Control Fluid" vs "Oil Control Gel Cream"), and creates temporal lock-in when a wrong match prevents correct LLM extraction later. We proved this with 1,783 rows needing correction in Jun 2026. Full LLM multimodal for both passes is the only approach that uses the same quality signal consistently.

**Pass 1 — Official / Brand Stores (taxonomy anchoring)**

Filter: `merchant_badge = 'Shopee Mall'` AND `merchant_name IN ({brand_official_store_names})`

> **Why not `LIKE '%official%'`:** Tested on shopee_th_suncare (Jun 2026). `%official%` catches multi-brand authorized retailers — Watsons Official Store, BEAUTRIUM Official Store, Tsuruha_Official, Matsukiyo Official, Sasa Official Shop, Lotuss_official, SAVE DRUG OFFICIAL STORE — none of which are brand-own curated catalogs. These are resellers with Shopee Mall certification, not the brand's own shelf. Using `%official%` would pollute Pass 1 with multi-brand retailer listings.
>
> **Why not `LIKE '%{brand_name}%'`:** Some brands operate their official store under a parent company or house-of-brands name. Biore's official store on Shopee TH is "KAO Beauty & Personal Care" — contains neither "biore" nor "official", so a keyword filter misses it entirely.
>
> **Correct approach: explicit per-brand store name allowlist.** Before each category run, query distinct `merchant_name` values for `merchant_badge = 'Shopee Mall'` products for each in-scope brand, identify the brand-own store (single curated shelf, not multi-brand), and build the allowlist. This is a one-time lookup per brand; store names are stable.

Scope: **ALL listings** from the confirmed brand-own store — no GMV threshold applied here. The brand's own store is the ground truth catalog; a product with low GMV today may launch strongly next month and should already be in taxonomy.

These listings build and anchor `product_taxonomy`. Official store listings have:
- Pack-shot images (clean product view, not lifestyle/promotional)
- Brand-convention listing names (not keyword-stuffed)
- Consistent variant naming following the brand's own product naming

Full multimodal LLM extraction is run on every Pass 1 product.
Output: seeded `product_taxonomy` entries with `source_listing = 'OFFICIAL'`

**Fallback — No official store found**

If a brand has no Shopee Mall store (no `merchant_badge = 'Shopee Mall'` rows for that brand), skip Pass 1 for that brand and treat all its products as Pass 2.

**Pass 2 — Reseller Listings (GMV threshold)**

Remaining product_ids for in-scope brands, filtered by GMV threshold, **excluding any product_id already mapped in Pass 1** (deduplication by product_id, not text similarity).

For each product: full multimodal LLM extraction — same method as Pass 1, no shortcuts.

Output: `product_taxonomy_map` entries with `source_listing = 'RESELLER'`

> **Dedup rule:** A product_id mapped in Pass 1 is skipped in Pass 2. This is a simple set exclusion — not a similarity check.

---

### Multimodal LLM Extraction

**Images are used for ALL seller types in BOTH passes.** The two-pass distinction is about source quality and scope (official store = exhaustive, reseller = GMV threshold) — not about the extraction method. Official store images tend to be pack shots (higher confidence output); reseller images may be lifestyle shots (may produce MEDIUM confidence), but images are always sent when available.

**LLM processor:** Initial taxonomy build runs via Claude Code (Claude processes images directly in session). Monthly refresh automation uses `pipeline/05_product_taxonomy/build_product_taxonomy.py` with `ANTHROPIC_API_KEY`. Both produce identical output schema.

**Model selection:**
- **Claude Sonnet** — use for both Pass 1 and Pass 2. Strong multimodal, reliable Thai language, accurate structured JSON extraction at ~3x less cost than Opus.
- **Claude Opus** — do NOT use as the default. Reserve only for targeted retry of specific products that Sonnet returned `UNRESOLVED` on and a human believes should be determinable.
- **Claude Haiku** — do NOT use. Insufficient reliability on Thai text, sub-line disambiguation from images, and multi-variant detection. Error rate too high for a dataset that feeds client deliverables.

Input to each LLM call:

| Field | Source | Notes |
|-------|--------|-------|
| `brand_canonical` | `brand_dict.canonical_name` (via Phase 3 join) | Clean brand anchor — replaces dirty `brand_raw` |
| `sku_name` | `master_clean_niq.sku_name` | **Original text — not `sku_name_EN`** |
| `option_names` | Aggregated `option_name` values per product_id | List of all variant options; signals multi-variant |
| `image` | `master_clean_niq.image` | Used for ALL sellers; confidence reflects image quality |

> **Why `brand_canonical`, not `brand_raw`:** Phase 3 has already resolved brands to their canonical form. Feeding the clean canonical name into Phase 5 avoids redundant cleaning and gives the LLM a consistent, unambiguous brand anchor.

> **Why original `sku_name` / `option_name`, not `_EN` variants:** Machine-translated fields introduce errors. Claude handles Thai natively; original text is always more reliable.

**How text clarity determines canonical name completeness:**
- `sku_name` is clear and unambiguous → text is sufficient → image acts as **validator** → HIGH confidence
- `sku_name` is ambiguous (Thai-only, multi-variant listed, sub-line unclear) → image is **primary signal** → HIGH/MEDIUM depending on image quality
- Neither clear → UNRESOLVED

The canonical name is as specific as what the listing can tell us. `Nivea Facial Wash 60ml` is a complete canonical name if that's what the listing clearly states. `Senka Perfect Whip` is also complete if the listing covers multiple variants — it's the maximum specificity determinable at product_id grain.

**Why multimodal (not text-only):**
Image sampling on 5 Shopee Mall TH suncare products confirmed images provide signals text alone cannot supply reliably:

1. **Sub-line disambiguation** — La Roche-Posay Anthelios `UVMUNE 400` vs `UVAIR` have visually distinct bottle shapes; parsing from Thai+English sku_name alone is error-prone
2. **Bundle/pair pack detection** — 2 bottles in image = unambiguous; Thai-only sku_name ("แพ็ก 2") requires Thai parsing
3. **Size confirmation** — Mall listing images consistently have a size banner at the bottom ("50 ml.")
4. **Brand verification** — Image shows clean `LA ROCHE-POSAY`; enables brand_canonical cross-check

**Why top 10 brands, not all brands:**
LLM knows major brand product lines well. Bounded scope makes human review feasible. Long tail brands have noisier listings and higher hallucination risk.

---

### Brand Correction Feedback Loop (Phase 5 → Phase 3)

The LLM always extracts the brand visible on the product image (`brand_from_image`). Whether this triggers a correction flag depends on the **source** in `product_brand_map`:

| `product_brand_map.source` | `brand_mismatch` check? | Reasoning |
|---------------------------|------------------------|-----------|
| `BRAND_FIELD` | ❌ No | Seller explicitly declared the brand — authoritative |
| `HUMAN` | ❌ No | Already manually verified |
| `PRODUCT_NAME_SCAN` | ✅ Yes | Brand was inferred from product name — could be wrong |
| `FALLBACK` | ✅ Yes | Brand was undetermined — image may now resolve it |

`brand_from_image` is always stored in `product_taxonomy_map` for audit purposes. The `brand_mismatch` flag is only set to TRUE for `PRODUCT_NAME_SCAN` and `FALLBACK` sources.

```
For source IN ('PRODUCT_NAME_SCAN', 'FALLBACK'):
  LLM extracts brand_from_image (e.g., "Cetaphil")
  Compare vs. brand_canonical (e.g., "La Roche-Posay")
    └─ MATCH   → proceed normally
    └─ MISMATCH → brand_mismatch = TRUE
                → queue for human review
                → confirmed wrong → update brand_dict + product_brand_map
                                  → re-run universe append for affected products

For source IN ('BRAND_FIELD', 'HUMAN'):
  brand_from_image stored for audit only
  brand_mismatch = FALSE (no correction triggered)
```

Brand corrections from confirmed mismatches propagate retroactively into `marketshare_universe` because a wrong brand assignment corrupts market share calculations. This is a Phase 5 quality gate on Phase 3's inferred mappings — the image provides an independent brand signal that text-only Phase 3 extraction did not have.

---

## Canonical Name Structure

```
{Brand} {Product Line} {Sub-line} {Variant} {Size}
```

Only non-NULL fields are concatenated. When a listing is ambiguous (multi-variant or multi-size), the uncertain field is set to NULL and a boolean flag is set.

| Component | Definition | Required | Example |
|-----------|-----------|----------|---------|
| Brand | Canonical name from brand_dict | Yes | `La Roche-Posay` |
| Product Line | Named product family | Yes | `Anthelios` |
| Sub-line | Sub-family within product line | No (NULL if absent) | `UVMUNE 400` |
| Variant | Specific formulation | No | `Oil Control Fluid` |
| Size | Volume/weight, normalised | No | `50ml` |

### Multi-variant / Multi-size Rule

**Do NOT use "Multi Size", "Multi Variant", or similar strings in the canonical name.** These are data quality annotations, not product attributes — they corrupt downstream reports and confuse clients.

**Rule: extract what IS determinable; NULL what is NOT; flag with booleans.**

| Listing type | Canonical name | is_multi_variant | is_multi_size |
|-------------|---------------|-----------------|--------------|
| Single variant, single size (clean) | `Wardah White Series Facial Wash 100ml` | FALSE | FALSE |
| Multi-variant, single size | `Wardah White Series Facial Wash 100ml` | **TRUE** | FALSE |
| Single variant, multi-size | `Nivea Facial Wash` | FALSE | **TRUE** |
| Multi-variant, multi-size | `Senka Perfect Whip` | **TRUE** | **TRUE** |

**Analyst usage:**
- Brand / product_line market share → include all taxonomy_ids regardless of flags (GMV is correct at listing level)
- Variant-level analysis → filter `is_multi_variant = FALSE`
- Size-level pricing → filter `is_multi_size = FALSE`
- Phase 6 (model_id grain) → properly resolves all flagged entries

### Additional naming rules

- Brand always uses `brand_dict.canonical_name` (not raw brand field)
- **Bundles: canonical name explicitly includes the multiplier** — `x2`, `x3`, etc. A 2-pack and a single unit are different taxonomy_ids with different canonical names, not the same entry with a flag.
- Bundle count unknown (detected but N unclear) → `is_bundle = TRUE`, `pack_count = NULL`, no suffix in canonical name
- SPF / PA rating is NOT part of canonical name — it's a product attribute, not a name differentiator
- Size refers to the single-unit size even for bundles (the `x2` suffix encodes the multiplier)
- Size normalisation: `ml` not `ML` or `mL`; `g` not `gm`; `L` not `ltr`

### Canonical name examples

| Raw sku_name (original) | Canonical name | pack_count | Notes |
|------------------------|---------------|-----------|-------|
| `ลา โรช-โพเซย์ Anthelios UVMUNE400 Oil Control Fluid 50ml.` | `La Roche-Posay Anthelios UVMUNE 400 Oil Control Fluid 50ml` | 1 | Single, clean |
| `[แพ็กคู่] L'Oréal Paris UV Defender Invisible Resist SPF50+ 50ml` | `L'Oreal Paris UV Defender Invisible Resist 50ml x2` | 2 | 2-pack, multiplier in name |
| `Senka Perfect Whip 120g x3 Value Pack` | `Senka Perfect Whip Original 120g x3` | 3 | 3-pack |
| `LA ROCHE-POSAY ANTHELIOS UVAIR SERUM SUNSCREEN 50ml` | `La Roche-Posay Anthelios UVAIR Serum Sunscreen 50ml` | 1 | Different sub-line |
| `Senka Perfect Whip (100g/120g) Original / Fresh / Acne Care...` | `Senka Perfect Whip` | 1 | is_multi_variant=TRUE, is_multi_size=TRUE |
| `Wardah White Series Anti-Acne / Brightening Facial Wash 100ml` | `Wardah White Series Facial Wash 100ml` | 1 | is_multi_variant=TRUE, size determinable |
| `Nivea Facial Wash 60ml / 100ml / 150ml` | `Nivea Facial Wash` | 1 | is_multi_size=TRUE |

---

## Data Architecture

### Pattern — mirrors the brand layer

```
brand_dict           →   product_taxonomy       (canonical master)
product_brand_map    →   product_taxonomy_map   (mapping table)
```

### Grain

`product_taxonomy_map` maps at **product_id** grain — same grain as `product_brand_map` and the universe itself.

Model_id grain (for full variant/size resolution) is deferred to **Phase 6**.

---

### `magpie_reference.product_taxonomy`

Canonical product master. Human-reviewed before entries are finalised.

| Column | Type | Notes |
|--------|------|-------|
| `taxonomy_id` | STRING PK | Format: `SKU-{6digits}` e.g. `SKU-000001` |
| `brand_id` | STRING FK | → `brand_dict.brand_id` |
| `product_line` | STRING | e.g. `Anthelios`, `UV Defender`, `Perfect Whip` |
| `sub_line` | STRING | e.g. `UVMUNE 400`, `UVAIR` — NULL if absent |
| `variant` | STRING | e.g. `Oil Control Fluid` — NULL if multi-variant or unknown |
| `size` | STRING | Normalised e.g. `50ml` — NULL if multi-size or unknown |
| `canonical_name` | STRING | Non-NULL fields joined: `{brand} {product_line} {sub_line} {variant} {size}` — appends ` x{pack_count}` when pack_count > 1 |
| `pack_count` | INT64 | 1 = single unit; 2/3/etc. = bundle size; NULL = bundle detected but count unclear |
| `is_bundle` | BOOL | Derived: TRUE when bundle detected (pack_count > 1 or pack_count IS NULL but flagged) — stored for query convenience |
| `is_multi_variant` | BOOL | TRUE when listing covers multiple formulations — variant field is NULL |
| `is_multi_size` | BOOL | TRUE when listing covers multiple sizes — size field is NULL |
| `meta_agent` | STRING | Agent responsible for creating or curating the row, currently `CLAUDE_CODE` or `CODEX` |
| `created_at` | TIMESTAMP | |
| `updated_at` | TIMESTAMP | |

---

### `magpie_reference.product_taxonomy_map`

Maps every Shopee product_id to a taxonomy_id.

| Column | Type | Notes |
|--------|------|-------|
| `product_id` | STRING | Composite PK part 1 |
| `master_table` | STRING | Composite PK part 2 e.g. `shopee_th_suncare` |
| `taxonomy_id` | STRING FK | → `product_taxonomy.taxonomy_id` — NULL if UNRESOLVED |
| `confidence` | STRING | `HIGH`, `MEDIUM`, `UNRESOLVED` |
| `source` | STRING | `LLM`, `MATCH`, `HUMAN`, `FALLBACK` |
| `source_listing` | STRING | `OFFICIAL` (Shopee Mall + brand merchant) or `RESELLER` |
| `brand_from_image` | STRING | Brand name extracted from product image by LLM |
| `brand_mismatch` | BOOL | TRUE if `brand_from_image` ≠ `brand_canonical` from Phase 3 — triggers Phase 3 review |
| `llm_raw` | STRING | Raw LLM JSON output — audit + reprocessing |
| `meta_agent` | STRING | Agent responsible for creating or curating the mapping, currently `CLAUDE_CODE` or `CODEX` |
| `mapped_at` | TIMESTAMP | |

**PK:** `(product_id, master_table)`
**Clustering:** `CLUSTER BY master_table, taxonomy_id`

---

## Build Pipeline

```
product_brand_map + brand_dict (Phase 3 output)
        │
        │  Step 0 — Backup
        │  CREATE TABLE product_taxonomy_backup_YYYYMMDD         AS SELECT * FROM product_taxonomy
        │  CREATE TABLE product_taxonomy_map_backup_YYYYMMDD     AS SELECT * FROM product_taxonomy_map
        │
        │  Step 1 — Brand ranking
        │  JOIN master_clean_niq → GROUP BY brand → ORDER BY SUM(gmv_monthly) DESC
        │  Apply GMV threshold → confirm brands in scope for this run
        │
        │  Step 2 — Input preparation
        │  JOIN master_clean_niq → filter by brand_id IN (confirmed brands)
        │  GROUP BY product_id, master_table → deduplicate to product_id grain
        │  Collect: brand_canonical, sku_name, option_names[], image_url, merchant_badge, merchant_name
        │
        ├─── PASS 1: Official / Brand Store listings
        │    Filter: merchant_badge = 'Shopee Mall'
        │            AND merchant_name IN ({brand_official_store_allowlist})
        │            -- build allowlist before run: query distinct merchant_names per brand
        │            -- NOT LIKE '%official%' → catches multi-brand retailers (Watsons, BEAUTRIUM, Sasa...)
        │            -- NOT LIKE '%{brand}%'  → misses parent-company stores (Biore → 'KAO Beauty & Personal Care')
        │    Scope: ALL products in official store — no GMV threshold
        │
        │    Per product_id → [Multimodal LLM — Claude Code / build_product_taxonomy.py]
        │    Input:  brand_canonical + source + sku_name + option_names[] + image
        │    Output: brand_from_image,
        │            brand_mismatch (only set if source IN PRODUCT_NAME_SCAN/FALLBACK),
        │            product_line, sub_line, variant, size,
        │            pack_count, is_multi_variant, is_multi_size,
        │            confidence, extraction_basis
        │    ▼
        │    [Brand Mismatch Check]
        │    brand_mismatch=TRUE → flag for Phase 3 review (separate queue)
        │    ▼
        │    [Dedup / Lookup]
        │    Normalise fields → match against product_taxonomy
        │      exists → reuse taxonomy_id
        │      new    → stage for human review → approve → insert
        │    ▼
        │    Write product_taxonomy_map
        │    (source='LLM', source_listing='OFFICIAL')
        │
        ├─── FALLBACK: No official store found for brand
        │    All brand products treated as Pass 2
        │
        └─── PASS 2: Reseller listings (GMV threshold)
             Product_ids for in-scope brands above GMV threshold
             EXCLUDE product_ids already mapped in Pass 1 (set exclusion, not text match)

             Per product_id:
             [Multimodal LLM — same method as Pass 1, no text similarity]
             Input:  brand_canonical + source + sku_name + option_names[] + image
             → same extraction → dedup → write (source='LLM')

             All Pass 2: source_listing='RESELLER'
             Brand mismatch check applies here too

        ─── After all passes complete ──────────────────────────────────────────
        DELETE old keyword-routed rows from product_taxonomy_map
          WHERE master_table = '{target_table}' AND source = 'HUMAN' (keyword rows)
        (Do this AFTER verifying LLM coverage ≥ keyword row count)
```

### LLM Output Schema (JSON)

```json
{
  "brand_from_image": "La Roche-Posay",
  "brand_mismatch": false,
  "product_line": "Anthelios",
  "sub_line": "UVMUNE 400",
  "variant": "Oil Control Fluid",
  "size": "50ml",
  "pack_count": 1,
  "is_multi_variant": false,
  "is_multi_size": false,
  "confidence": "HIGH",
  "extraction_basis": "image_primary"
}
```

`extraction_basis` values:
- `text_sufficient` — sku_name was clear enough; image used as validator only
- `image_primary` — sku_name was ambiguous; image was the primary signal
- `text_only` — image unavailable; extraction from sku_name + option_names only

`confidence` rules:
- `HIGH` — product_line clearly determinable (from text or image), brand verified
- `MEDIUM` — text ambiguous AND image was low quality (lifestyle shot, no pack visible)
- `UNRESOLVED` — LLM could not determine product_line reliably

`brand_mismatch = TRUE` → always flag for human review, regardless of other confidence fields

---

## Scope & Phasing

### Brand Scope — GMV Threshold, Not Fixed List

Brands are determined per-category per-run by GMV threshold query. There is no fixed "top 10" list — the threshold is applied dynamically so the scope automatically tracks market shifts.

**Execution order (decided Jun 20 2026):**
1. `shopee_th_suncare` — Apr 2026 (first LLM run, validation)
2. Remaining months backfill for shopee_th_suncare (Jun 2025–Mar 2026)
3. Expand to other TH categories, then SG categories

**Indicative brands that will appear at GMV threshold across TH categories:**

| Brand | Likely categories |
|-------|-----------------|
| La Roche-Posay | Suncare, Moisturizer, Cleanser |
| L'Oreal Paris | Suncare, Moisturizer |
| Senka | Cleanser, Moisturizer |
| Vaseline | Body moisturizer |
| Nivea | Body moisturizer, Face |
| Cetaphil | Cleanser, Moisturizer |
| Neutrogena | Suncare, Cleanser |
| Dove | Body wash, Shampoo |
| MizuMi | Suncare (TH) |
| Her Hyness | Suncare (TH) |

> Run GMV query per target category before each session to confirm actual scope.

### Phase 5 — Current scope (product_id grain)
- GMV threshold brands, category by category, starting TH then SG
- Full LLM multimodal two-pass pipeline (official store exhaustive → reseller GMV threshold)
- No text similarity at any stage
- Claude Code for initial build; Python script for monthly automation
- Tables: `product_taxonomy` + `product_taxonomy_map`
- Multi-variant / multi-size handled with flags, not strings
- All new rows: `source='LLM'`, `meta_agent='CLAUDE_CODE'`

### Phase 6 — Deferred (model_id grain)
- Resolve multi-variant and multi-size listings at model_id level
- New table: `product_model_map` at `(product_id, model_id, master_table)` grain
- Prerequisite: Phase 5 taxonomy established and validated

---

## Pre-Build Checklist

- [ ] **Confirm top 10 brands by GMV** — query across SG + TH, Apr 2026
- [x] **Define "official store" filter** — explicit per-brand allowlist of brand-own store names (NOT LIKE '%official%' which catches multi-brand retailers; NOT LIKE '%brand%' which misses parent-company stores). Build allowlist by querying Mall merchants per brand before each run.
- [ ] **Audit option_name quality** — for top 10 brands, what % are non-null / non-"Default"?
- [ ] **Audit image URL availability** — what % of top-brand products have a non-null `image`?
- [ ] **Estimate taxonomy size** — count unique (product_line, sub_line) combos per brand; should be in hundreds, not thousands
- [ ] **Define human review workflow** — Sheets tab (like brand_review) or separate tool?
- [ ] **Confirm primary analytical use case** — drives which canonical name components are required

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Duplicate taxonomy entries from LLM inconsistency | High | High | Normalised dedup before insert; human review gate |
| option_name quality worse than expected | Medium | High | Audit first; fall back to image + sku_name |
| Taxonomy maintenance burden (new variants quarterly) | High | Medium | Monthly re-run for Pass 1 (official stores only) |
| LLM hallucinates product line for unknown brand | Low | High | Hard scope to top 10 brands |
| Bundle packs inflate GMV if is_bundle not flagged | Medium | High | Image detection in Pass 1; image is reliable for mall listings |
| Image URL CDN failure | Low | Medium | Log + fall back to text-only with confidence=MEDIUM |
| "Multi Variant" strings polluting canonical names | Medium | High | Strict naming rule: NULL + flag, never descriptive strings |
| Pass 2 text matching producing false positives | Medium | Medium | Match threshold tuning; fallback to LLM when confidence low |

---

## CDO Assessment

### Strategic value: High ✅

Phase 5 is the prerequisite for every SKU-level insight clients ask for: variant share, price benchmarking, new product tracking. Brand-level data answers "who owns the market?". Product taxonomy answers "which specific products are winning?".

### Source prioritization: Strong addition ✅

Processing official/brand store listings first is not just a quality heuristic — it changes the architecture in a valuable way. The official store catalog becomes the ground truth for taxonomy entries. Reseller listings are then matched against it rather than re-extracted. This reduces cost, improves consistency, and reflects how brand data is structured in practice.

### Multi-variant handling: Omit + flag is correct ✅

"Multi Variant" and "Multi Size" strings in canonical names would be a mistake. They are data quality metadata, not product attributes. Clients reading reports would not understand them. Analysts filtering for specific variants would exclude them inconsistently. The NULL + boolean flag approach is analytically clean, queryable, and honest about what the data can and cannot tell us at product_id grain.

### Grain alignment: Correct ✅

Mapping at product_id grain aligns with the universe grain. Phase 6 (model_id) resolves the remaining ambiguity for multi-variant/multi-size flagged entries when that precision is needed.

### Remaining concern: Taxonomy maintenance ownership ⚠️

A taxonomy built in June 2026 will have gaps by Q3 (new product launches, new variants). Monthly re-run cadence on Pass 1 (official store only — small volume, low cost) is the minimum. A named owner must be assigned before Phase 5 ships.

### Greenlight: Phase 5 ✅ | Phase 6: revisit after Phase 5 coverage validated

---

## Market Insight Assessment

### The two-pass architecture maps to a real market structure

The Pass 1 / Pass 2 split is not just a technical convenience — it reflects how the market actually works:

- **Official brand stores** = brand's curated shelf. One canonical listing per SKU. This is the brand's intended product catalog.
- **Resellers** = market distribution. Multiple listings, same product, varying price and name. This is market penetration data.

Treating these as separate extraction tiers means the taxonomy is grounded in the brand's own naming conventions, not the most popular reseller's keyword-stuffed title. That matters for client-facing reports where product names need to match what the brand actually calls their product.

### The canonical name will be used in client deliverables

This is the most important practical constraint. Every decision about canonical name structure (including the NULL + flag approach for multi-variant listings) should be evaluated against: "would a client brand manager understand this in a slide?" `Senka Perfect Whip` in a market share table = yes. `Senka Perfect Whip Multi Size` = no. The NULL approach wins on client-readiness.

### Phase 5 coverage unlocks a new deliverable tier

With product_taxonomy in place, Magpie can deliver:
1. Product-line share within a brand (which Anthelios variant is gaining share?)
2. Cross-merchant price consistency (same SKU, different merchants — what's the price spread?)
3. New variant launch detection (first month a taxonomy_id appears = launch date)

None of these are possible today. Phase 5 is the unlock.

---

## Open Questions

| # | Question | Owner | Needed by |
|---|----------|-------|----------|
| 1 | Confirmed top 10 brands by GMV? | Analytics | Before build |
| 2 | "Official store" filter — which keywords per brand? | Analytics | Before build |
| 3 | Target coverage rate for Phase 5? | CDO | Before build |
| 4 | Who owns monthly taxonomy maintenance run? | Team lead | Before build |
| 5 | Human review workflow — Sheets or separate tool? | CTO | Before build |
| 6 | Include SG and TH in Phase 5, or one market first? | CDO | Before build |
| 7 | At what match score threshold does Pass 2 fall back to LLM? | CTO | During build |

---

## Appendix — Image Sampling Evidence

**Sample:** 5 Shopee Mall TH suncare products, Apr 2026, ranked by GMV

| # | Brand | Canonical name (extracted from image) | Sub-line in image? | Size in image? | Bundle detected? |
|---|-------|--------------------------------------|--------------------|---------------|-----------------|
| 1 | L'Oreal Paris | `L'Oreal Paris UV Defender Invisible Resist 50ml` | N/A | No | ✅ Yes (2-pack) |
| 2 | La Roche-Posay | `La Roche-Posay Anthelios UVMUNE 400 Anti-Dark Spots Fluid 50ml` | ✅ Yes | ✅ Yes | No |
| 3 | La Roche-Posay | `La Roche-Posay Anthelios UVMUNE 400 Oil Control Fluid 50ml` | ✅ Yes | ✅ Yes | No |
| 4 | ISDIN | `ISDIN Fotoultra 100 Active Unify` | N/A | ❌ No | No |
| 5 | La Roche-Posay | `La Roche-Posay Anthelios UVAIR Serum Sunscreen 50ml` | ✅ Yes | ✅ Yes | No |

**Key finding:** All 5 products were identifiable at product_id grain (single SKU per listing — these are official store listings). Sub-line was image-critical for 3/5. Bundle detection caught the L'Oreal pair pack. This validates both the multimodal approach and the official-store-first prioritization.
