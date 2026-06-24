# Architecture — Marketshare Universe

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Shopee Raw Data                               │
│              master_clean_niq.shopee_{country}_{category}        │
│         43 tables · ~200M rows · model/variant grain             │
└────────────────────────────┬────────────────────────────────────┘
                             │
              ┌──────────────▼──────────────┐
              │      Stage 01: Brand Audit   │
              │  10.8M unique brand strings  │
              │  Exported to Google Sheets   │
              └──────────────┬──────────────┘
                             │
              ┌──────────────▼──────────────┐
              │   Stage 02: Taxonomy Build   │
              │  brand_dict: 19,714 brands   │
              │  Dedup + canonical names     │
              └──────────────┬──────────────┘
                             │
              ┌──────────────▼──────────────┐
              │  Stage 03: Product Mapping   │
              │  product_brand_map: 1.2M     │
              │  Every product → brand_id    │
              └──────────────┬──────────────┘
                             │
              ┌──────────────▼──────────────┐
              │  Stage 04: Universe Append   │
              │  marketshare_universe: 9.96M │
              │  Jun 2025 – Apr 2026         │
              └──────────────┬──────────────┘
                             │
              ┌──────────────▼──────────────┐
              │ Stage 05: Product Taxonomy   │
              │  LLM multimodal extraction   │
              │  product_taxonomy: ~15K SKUs │
              │  product_taxonomy_map: 140K  │
              └─────────────────────────────┘
```

---

## BigQuery Layout

### Project: `sincere-hearth-273704` (primary)

```
sincere-hearth-273704
├── master_clean_niq/          ← Source (read-only)
│   └── shopee_{country}_{category}   (43 tables)
│
├── raw_niq_history/           ← Source with full product spec/description
│   └── shopee_{country}_{category}   (product_specification, product_description columns)
│
├── magpie_reference/          ← Reference layer (pipeline writes here)
│   ├── brand_dict
│   ├── product_brand_map
│   ├── niq_category_mapping
│   ├── product_taxonomy
│   └── product_taxonomy_map
│
└── magpie/                    ← Output layer
    ├── marketshare_universe
    ├── meta_universe
    ├── summary_brand_monthly
    └── summary_merchant_monthly
```

### Project: `magpie-farsight` (downstream mirror)

```
magpie-farsight
└── universe/
    ├── marketshare_universe   ← Mirror of sincere.magpie.marketshare_universe
    ├── meta_universe
    ├── summary_brand_monthly
    └── summary_merchant_monthly
```

---

## Table Schemas

### `master_clean_niq.shopee_{country}_{category}`

Source data. **Read-only.** Never modified by the pipeline.

| Column | Type | Notes |
|--------|------|-------|
| `product_id` | STRING | Shopee listing ID. NOT globally unique — use `(product_id, master_table)` |
| `model_id` | STRING | Shopee variant/model ID |
| `sku_name` | STRING | Full product title as listed by seller |
| `brand` | STRING | Brand from Shopee specs — often blank, inconsistently cased |
| `gmv_monthly` | FLOAT | GMV in SGD (SG) or THB (TH) for this model in this month |
| `sold_monthly` | INT | Units sold |
| `month` | DATE | First day of month e.g. `2026-04-01` |
| `category_1–5` | STRING | Shopee BE category hierarchy (local language) |
| `category_1_EN–5_EN` | STRING | Shopee BE category hierarchy (English) |
| `merchant_name` | STRING | Seller display name |
| `merchant_badge` | STRING | `'Shopee Mall'` for official/mall stores, else NULL |

**Grain:** `(product_id, model_id, month)` — one row per variant per month.  
**Aggregation:** Always `SUM(gmv_monthly) GROUP BY product_id, month` before joining to universe.

### `raw_niq_history.shopee_{country}_{category}`

Extended source with full product specifications. Used for size/pack extraction fallback.

| Column | Type | Notes |
|--------|------|-------|
| `product_id` | STRING | Same as master_clean_niq |
| `product_specification` | STRING | Structured spec fields (weight, volume, etc.) |
| `product_description` | STRING | Full merchant description text |
| All other columns | — | Same as master_clean_niq |

**Size extraction priority:** sku_name text → product image (LLM) → product_specification → product_description

---

### `magpie_reference.brand_dict`

Canonical brand registry. One row per brand entity.

| Column | Type | Description |
|--------|------|-------------|
| `brand_id` | STRING PK | Format: `BRD-{SCOPE}-{5digits}` e.g. `BRD-TH-03644` |
| `canonical_name` | STRING | Proper-cased brand name e.g. `"La Roche-Posay"` |
| `scope` | STRING | `GLOBAL`, `SG`, or `TH` |
| `category` | STRING | Primary product category |
| `parent_brand_id` | STRING | NULL (Phase 5 extension, not yet populated) |

**Reserved IDs:**
- `BRD-UNDEFINED` — brand cannot be determined from available data
- `BRD-UNBRANDED` — product is intentionally generic/unbranded

**Scope rules:**
- `GLOBAL` — brand appears in both SG and TH data
- `SG` — brand seen only in SG data
- `TH` — brand seen only in TH data
- Same real-world brand may have multiple IDs if detected separately per market; dedup is an ongoing process

---

### `magpie_reference.product_brand_map`

Maps every product to a canonical brand. The join table for universe append.

| Column | Type | Description |
|--------|------|-------------|
| `product_id` | STRING | Shopee product ID |
| `master_table` | STRING | Source table e.g. `shopee_th_body_wash` |
| `brand_id` | STRING FK | → `brand_dict.brand_id` |
| `confidence` | FLOAT | 0.0–1.0 confidence in brand assignment |
| `source` | STRING | Assignment method (see values below) |
| `created_at` | TIMESTAMP | |

**Source values:**
| Value | Meaning |
|-------|---------|
| `BRAND_FIELD` | Matched directly from Shopee brand field (highest trust) |
| `PRODUCT_NAME_SCAN` | Extracted from product title by string matching |
| `FALLBACK` | Assigned to BRD-UNDEFINED when no match found |
| `HUMAN` | Manually assigned |
| `LLM` | Assigned during Phase 5 LLM extraction (brand_mismatch correction) |

---

### `magpie_reference.product_taxonomy` ⭐ Phase 5

Canonical product entries. Each SKU represents one specific product (brand × line × size × pack_count).

| Column | Type | Description |
|--------|------|-------------|
| `taxonomy_id` | STRING PK | Format: `SKU-{6digits}` e.g. `SKU-000001` |
| `canonical_name` | STRING | Full product name: `{Brand} {Product Line} {Variant} {Size} [x{N}]` |
| `brand_id` | STRING FK | → `brand_dict.brand_id` |
| `size` | STRING | e.g. `200ml`, `400g`, `1L` — NULL only if genuinely multi-size |
| `pack_count` | INT | Units per listing (1 = single, 2+ = multipack) |
| `is_multi_size` | BOOL | TRUE if this entry covers multiple sizes legitimately |
| `is_multi_variant` | BOOL | TRUE if this entry covers multiple formula/flavor variants |
| `is_bundle` | BOOL | TRUE if cross-brand bundle (e.g. Coke + Fanta pack) |
| `meta_agent` | STRING | `CLAUDE_CODE`, `CODEX`, or `HUMAN` |
| `created_at` | TIMESTAMP | |

**Canonical name format:** `{Brand} {Product Line} {Sub-line} {Size} [x{N}]`  
Examples:
- `"Vaseline Gluta-Hya UV Serum Body Lotion 400ml x2"`
- `"Head & Shoulders Cool Menthol Anti-Dandruff Shampoo 450ml"`
- `"Coca-Cola Less Sugar 1.5L x12"`

**SKU block allocation (never reuse or overlap):**  
See [`docs/categories/STATUS.md`](docs/categories/STATUS.md) for full SKU range map per category.

---

### `magpie_reference.product_taxonomy_map` ⭐ Phase 5

Maps every product to a taxonomy entry. One row per product (deduplicated).

| Column | Type | Description |
|--------|------|-------------|
| `product_id` | STRING | Shopee product ID |
| `master_table` | STRING | Source table |
| `taxonomy_id` | STRING FK | → `product_taxonomy.taxonomy_id` |
| `source` | STRING | `LLM` (Phase 5 extraction) or `HUMAN` (keyword seed) |
| `confidence` | FLOAT | Extraction confidence (0.55–1.0) |
| `brand_from_image` | STRING | Brand name as read from product image by LLM |
| `brand_mismatch` | BOOL | TRUE if brand_from_image ≠ product_brand_map.brand canonical |
| `meta_agent` | STRING | `CLAUDE_CODE` or `CODEX` |
| `mapped_at` | TIMESTAMP | |

**Dedup rule:** Each product_id has exactly ONE row. LLM source takes precedence over HUMAN.

---

### `magpie.marketshare_universe`

The final output table. Analysts query this directly.

| Column | Type | Description |
|--------|------|-------------|
| `product_id` | STRING | Shopee product ID |
| `master_table` | STRING | Source table (used as composite key with product_id) |
| `month` | DATE | |
| `ecommerce_platform` | STRING | `'Shopee'` (capital S) |
| `country` | STRING | `'SG'` or `'TH'` (uppercase) |
| `category_1–5` | STRING | NIQ category hierarchy |
| `magpie_cat_1–3` | STRING | Magpie category hierarchy (cleaner, from niq_category_mapping) |
| `brand_id` | STRING | From product_brand_map |
| `brand` | STRING | Canonical brand name from brand_dict |
| `gmv_monthly` | FLOAT | Product-level GMV (SUM of model-level, aggregated) |
| `sold_monthly` | INT | Units sold |
| `taxonomy_id` | STRING | From product_taxonomy_map (NULL if not yet extracted) |
| `sku_type_complete` | STRING | = `product_taxonomy.canonical_name` |
| `taxonomy_source` | STRING | `'LLM'` or `'HUMAN'` |
| `taxonomy_confidence` | FLOAT | |
| `taxonomy_meta_agent` | STRING | |
| `merchant_name` | STRING | |
| `merchant_badge` | STRING | `'Shopee Mall'` for official stores |

---

## Data Granularity

```
Source: (product_id, model_id, month) — one row per variant
Universe: (product_id, master_table, month) — one row per product per month

Aggregation to get product-level: SUM(gmv_monthly) GROUP BY product_id, master_table, month
Never query universe at model grain — it's already aggregated.
```

**Critical: product_id is NOT globally unique.** `shopee_sg_shampoo` and `shopee_th_shampoo` can both have `product_id = '12345678'`. Always filter by `master_table` or `country`.

---

## Phase 5 LLM Extraction — How It Works

Phase 5 enriches the universe with granular product-level taxonomy using Claude's multimodal capabilities (reads product images + text).

> For the full per-product narrative — input signals in trust order, the
> match-or-create decision tree, UNRESOLVED handling, brand correction, and a
> worked end-to-end example — see [`docs/product-lifecycle.md`](docs/product-lifecycle.md).

### Two-Pass Strategy

**Pass 1 — Official Stores (OFFICIAL):**
- Fetch all products from brand-owned official Mall stores
- Read each product image + sku_name → extract `product_line`, `size`, `pack_count`, `brand_from_image`
- Build `product_taxonomy` entries (canonical names) + insert `product_taxonomy_map` rows
- Source = `LLM`, confidence = 0.85–0.99

**Pass 2 — Resellers (RESELLER):**
- Rank brands by GMV (GWP-adjusted) → keep brands in top-95% cumulative GMV
- Fetch reseller products for those brands
- Route each product to existing taxonomy via text matching or create new catch-all entries
- Source = `LLM`, confidence = 0.65–0.85

### Universe Refresh

After each category, run targeted DML UPDATE:
```sql
UPDATE marketshare_universe u
SET taxonomy_id = src.taxonomy_id, sku_type_complete = src.canonical_name, ...
FROM (
  SELECT m.product_id, m.master_table, pt.taxonomy_id, pt.canonical_name, ...
  FROM product_taxonomy_map m
  JOIN product_taxonomy pt ON m.taxonomy_id = pt.taxonomy_id
  JOIN niq_category_mapping nm ON nm.master_table = m.master_table
  WHERE nm.master_table = '{table}'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY m.product_id, m.master_table ORDER BY 
    CASE m.source WHEN 'LLM' THEN 0 ELSE 1 END, m.taxonomy_id) = 1
) src
WHERE u.product_id = src.product_id AND u.master_table = src.master_table
  AND u.ecommerce_platform = 'Shopee'
```

See [`docs/runbook.md`](docs/runbook.md) for full refresh script.

---

## Key Design Decisions

See [`docs/decisions/`](docs/decisions/) for full ADRs. Summary:

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Global taxonomy — one `brand_dict` across all categories | Brands appear across categories; dedup is easier with one canonical |
| 2 | BQ for all mappings | Scale: 1.2M products × 43 tables can't live in Sheets |
| 3 | `BRD-UNDEFINED` vs `BRD-UNBRANDED` | Two different failure modes — data gap vs. genuinely unbranded product |
| 5 | Phase 5: Full LLM multimodal for both passes | Text similarity had same failure modes as keyword matching |
| 7 | Phase 5: Official store = ALL listings, no GMV threshold | Completeness — official stores vouch for brand accuracy |
| 10 | Use Sonnet for both passes | Opus is overkill; Haiku unreliable for Thai + image disambiguation |
| 12 | Routing order: specific before generic | Prevents "Oil Control" catching "Oil Control Gel Cream" products |
| 14 | Official store allowlist = explicit per-brand query | LIKE '%official%' catches multi-brand retailers (Watsons etc.) |
| 15 | GWP GMV = 0 in threshold calculations | GWP inflates brand rank; only count products buyer actually pays for |
| 16 | Pre-assign SKU blocks before parallel agent runs | Race condition: two parallel sessions querying MAX() at the same time collide |
