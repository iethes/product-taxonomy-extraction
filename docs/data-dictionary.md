# Data Dictionary

## Source Layer — `master_clean_niq.*`

> Granularity: one row = `(product_id, model_id, month)`
> This layer is **read-only** — never modified by any pipeline stage.

| Column | Type | Description |
|--------|------|-------------|
| `product_id` | STRING | Shopee product (listing) ID. Not globally unique — composite key with `master_table` |
| `model_id` | STRING | Shopee model (variant) ID e.g. size, colour |
| `sku_name` | STRING | Full product title as listed by the seller |
| `brand` | STRING | Brand from Shopee product specs. Often blank, inconsistently cased, or contains Thai parenthetical suffix e.g. `Vaseline(วาสลีน)` |
| `gmv_monthly` | FLOAT | Total GMV (SGD/THB) for this model in this month |
| `month` | DATE | First day of month e.g. `2026-04-01` |
| `category_1–5` | STRING | Shopee BE category hierarchy (local language) |
| `category_1_EN–5_EN` | STRING | Shopee BE category hierarchy (English) |

**Critical notes:**
- `brand` column quality varies widely — do not use directly for analytics without going through `product_brand_map`.
- `product_id` is NOT globally unique across tables. Always use `(product_id, master_table)` as the composite key.
- BE (backend) categories differ from FE (frontend) categories. SG BE ≈ FE. TH oral care is BE=Health, FE=Beauty & Personal Care (fixed in `niq_category_mapping`).

---

## Reference Layer — `magpie_reference.brand_dict`

> Granularity: one row = one canonical brand entry
> Built by: `pipeline/02_taxonomy_build/build_brand_dict.py`
> ~19,700 rows as of Jun 2026

| Column | Type | Values / Format | Description |
|--------|------|----------------|-------------|
| `brand_id` | STRING | `BRD-{SCOPE}-{5digits}` | Primary key. SCOPE = `GLOBAL`, `SG`, or `TH` |
| `canonical_name` | STRING | Properly cased | Single authoritative brand name e.g. `Vaseline`, `Kérastase` |
| `parent_brand_id` | STRING | NULL or brand_id | For sub-brand hierarchy (Phase 5, currently NULL) |
| `brand_level` | INT64 | 1, 2, 3 | 1=company, 2=brand, 3=sub-brand |
| `country_scope` | STRING | `SG`, `TH`, `GLOBAL` | Markets where this brand appears |
| `status` | STRING | `ACTIVE`, `DEPRECATED` | |
| `deprecated_at` | TIMESTAMP | | NULL if still active |
| `superseded_by` | STRING | brand_id | FK to replacement if deprecated |
| `created_at` | TIMESTAMP | | |
| `updated_at` | TIMESTAMP | | |

**brand_id format:**
- `BRD-GLOBAL-*` → brand appears in both SG and TH markets, sorted by GMV desc
- `BRD-SG-*` → SG-only brand
- `BRD-TH-*` → TH-only brand

**Reserved brand_ids (always present):**
| brand_id | canonical_name | Use when |
|----------|---------------|----------|
| `BRD-UNDEFINED` | Undefined | Brand could not be determined from any signal |
| `BRD-UNBRANDED` | Unbranded | Product is intentionally generic / white-label |

---

## Reference Layer — `magpie_reference.product_brand_map`

> Granularity: one row = one unique `(product_id, master_table)` combination
> Built by: `pipeline/03_product_mapping/build_product_brand_map.py`
> Clustered by: `master_table, product_id`

| Column | Type | Values | Description |
|--------|------|--------|-------------|
| `product_id` | STRING | | Shopee product ID |
| `master_table` | STRING | `shopee_sg_*`, `shopee_th_*` | Source table. Composite PK with `product_id` |
| `brand_id` | STRING | `BRD-*` | FK → `brand_dict.brand_id` |
| `brand_raw` | STRING | | Original `brand` column value from source — **never modified**, preserved for audit |
| `matched_token` | STRING | | For `PRODUCT_NAME_SCAN`: the brand token found in `sku_name` |
| `confidence` | STRING | See below | Reliability of this brand assignment |
| `source` | STRING | See below | Which method assigned the brand |
| `variant_label` | STRING | NULL (Phase 5) | e.g. `Intensive Care`, `Sensitive` |
| `size_label` | STRING | NULL (Phase 5) | e.g. `200ml`, `1kg` |
| `pack_type` | STRING | NULL (Phase 5) | e.g. `Tube`, `Pump`, `Sachet` |
| `segment` | STRING | NULL (Phase 5) | e.g. `Premium`, `Mass`, `Economy` |
| `mapped_at` | TIMESTAMP | | First written |
| `updated_at` | TIMESTAMP | | Last updated |

### Brand assignment method — priority order

Three methods are tried in order, stopping at first success:

```
1. BRAND_FIELD          brand column is filled → lookup in brand_dict
2. PRODUCT_NAME_SCAN    brand column is NULL   → scan sku_name for known brands
3. FALLBACK             nothing found          → BRD-UNDEFINED or BRD-UNBRANDED
```

### Source and confidence values

| source | confidence | How it works |
|--------|-----------|-------------|
| `BRAND_FIELD` | `HIGH` | `brand` column cleaned and normalized → looked up in brand lookup map |
| `PRODUCT_NAME_SCAN` | `HIGH` | Brand name found at **start of sku_name** (first token position) |
| `PRODUCT_NAME_SCAN` | `MEDIUM` | Brand name found **anywhere in sku_name** (word boundary match) |
| `HUMAN` | `HIGH` | Manually assigned or corrected |
| `FALLBACK` | `UNRESOLVED` | `BRD-UNDEFINED` if brand unknown; `BRD-UNBRANDED` if explicitly generic |

### How BRAND_FIELD matching works

The brand lookup map is built at runtime from:
1. All `canonical_name` values in `brand_dict` (normalized: lowercase, punctuation stripped)
2. All raw variant names from MERGE groups in `brand_review` (both auto and manual decisions)

Example: raw brand `"VASELINE"` matches because:
```
normalize("VASELINE") → "vaseline"
brand_lookup["vaseline"] → BRD-GLOBAL-XXXXX ✓
```

Example: raw brand `"Kérastase"` and `"Kerastase"` both match the same entry because the merge map contains both variants pointing to the same `brand_id`.

### How PRODUCT_NAME_SCAN works

When `brand` is NULL, the sku_name is scanned for known brand names:

1. Normalize `sku_name`: lowercase, strip punctuation, tokenize by whitespace
2. Try all n-gram windows (1 to max_brand_words tokens)
3. Match against all normalized brand names — **longest patterns first** (avoids partial matches)
4. Token position 0 → `HIGH` confidence; any other position → `MEDIUM`

**What normalization handles automatically:**
- Case: `VASELINE` = `vaseline` = `Vaseline`
- Hyphens/spaces: `Oral-B` = `Oral B` = `OralB` → `oralb`
- Apostrophes: `Kiehl's` = `Kiehls` → `kiehls`
- Zero-width characters (U+200B etc.) and Thai parenthetical suffixes: stripped in pre-cleaning

**What normalization does NOT handle:**
- Genuine typos in sku_name (e.g. `"Vaselne"` will not match `"Vaseline"`)
- Fuzzy matching is intentionally excluded — a wrong brand assignment corrupts market share; `BRD-UNDEFINED` is safer than a false match

### Typical coverage benchmarks (Feb–Apr 2026, 43 tables)

| source | approx % of products |
|--------|---------------------|
| `BRAND_FIELD` | 30–45% |
| `PRODUCT_NAME_SCAN` HIGH | 10–15% |
| `PRODUCT_NAME_SCAN` MEDIUM | 35–45% |
| `FALLBACK` | 5–10% |

FALLBACK products are typically long-tail listings with poor data quality. High-GMV products resolve via `BRAND_FIELD` at ~95%+ rate.

---

## Reference Layer — `magpie_reference.brand_review`

> Intermediate audit table — input to brand_dict build, not used in downstream analytics
> Built by: `pipeline/02_taxonomy_build/detect_duplicates.py`

Records duplicate brand group detection results and merge decisions.

| Column | Description |
|--------|-------------|
| `run_id` | Timestamp-based run identifier for idempotent re-runs |
| `confidence` | `RED` = same brand after full normalization; `YELLOW` = fuzzy match above threshold |
| `decision_source` | `AUTO-RED` / `AUTO-YELLOW` / `NEEDS-REVIEW` / `PATTERN-SKIP` |
| `merge_decision` | `MERGE` or `SKIP` |
| `final_canonical` | Canonical name to use if MERGE |
| `variants` | Pipe-separated raw brand names in this group |
| `fuzzy_ratio` | SequenceMatcher ratio (0–1). YELLOW threshold = 0.82; auto-merge threshold = 0.90 |

---

## Analytics Layer — `magpie.marketshare_universe`

> Granularity: product-month level
> Built by: `pipeline/04_universe_append/` (Stage 04)

All source columns from `master_clean_niq` plus:

| Column | Type | Source | Description |
|--------|------|--------|-------------|
| `brand_id` | STRING | product_brand_map | Join key to brand_dict |
| `brand_canonical` | STRING | brand_dict | Clean, merged brand name for reporting |
| `brand_confidence` | STRING | product_brand_map | `HIGH` / `MEDIUM` / `UNRESOLVED` |
| `brand_raw` | STRING | master_clean_niq | Original value, never overwritten |
| `magpie_category_1` | STRING | niq_category_mapping | e.g. `Beauty & Personal Care` |
| `magpie_category_2` | STRING | niq_category_mapping | e.g. `Body Care` |
| `magpie_category_3` | STRING | niq_category_mapping | End category e.g. `Body Lotion` |
| `country` | STRING | derived from master_table | `SG` or `TH` |

**Recommended filter for market share queries:**
```sql
WHERE brand_confidence IN ('HIGH', 'MEDIUM')
  AND brand_id NOT IN ('BRD-UNDEFINED', 'BRD-UNBRANDED')
```

---

## Reference Layer — `magpie_reference.product_taxonomy` ⭐ Phase 5

> Granularity: one row = one canonical product entry (SKU)
> Built by: Phase 5 LLM extraction sessions (Claude Code)

| Column | Type | Description |
|--------|------|-------------|
| `taxonomy_id` | STRING PK | Format: `SKU-{6digits}` e.g. `SKU-000001`. Never reuse. Allocated in 1000-slot blocks per category. |
| `canonical_name` | STRING | Full product name: `{Brand} {Line} {Variant} {Size} [x{N}]` e.g. `"Vaseline Gluta-Hya UV Serum 400ml x2"` |
| `brand_id` | STRING FK | → `brand_dict.brand_id` |
| `size` | STRING | e.g. `200ml`, `400g`, `1L`. NULL only if genuinely multi-size (is_multi_size=TRUE) |
| `pack_count` | INT | Units per listing. 1 = single; ≥2 = multipack |
| `is_multi_size` | BOOL | TRUE = this entry covers multiple sizes legitimately |
| `is_multi_variant` | BOOL | TRUE = covers multiple formula/flavor variants |
| `is_bundle` | BOOL | TRUE = cross-brand bundle (e.g. Coke + Fanta pack) |
| `meta_agent` | STRING | `CLAUDE_CODE`, `CODEX`, or `HUMAN` — never NULL |
| `created_at` | TIMESTAMP | |

**Canonical name format:** `{Brand} {Product Line} {Sub-line/Variant} {Size} [x{N}]`

- Correct: `"Head & Shoulders Cool Menthol Anti-Dandruff Shampoo 450ml"`
- Correct: `"Coca-Cola Less Sugar 1.5L x12"`
- Wrong: `"Head & Shoulders Shampoo"` (no product line or size)
- Wrong: `"Shampoo 450ml"` (brand name missing from canonical)
- Wrong: `"Vaseline Body Lotion All Variants"` (never use "All Variants")
- Wrong: `"Crystal Drinking Water 1.5L x90 (15 packs of 6)"` (no breakdown suffix)

**Current MAX taxonomy_id:** SKU-058455. See [`docs/categories/STATUS.md`](categories/STATUS.md) for full SKU allocation map.

---

## Reference Layer — `magpie_reference.product_taxonomy_map` ⭐ Phase 5

> Granularity: one row = one product → one taxonomy entry mapping
> Deduplicated: exactly ONE row per product_id per master_table (LLM preferred over HUMAN)
> Built by: Phase 5 LLM extraction sessions

| Column | Type | Description |
|--------|------|-------------|
| `product_id` | STRING | Shopee product ID |
| `master_table` | STRING | Source table e.g. `shopee_th_body_wash` |
| `taxonomy_id` | STRING FK | → `product_taxonomy.taxonomy_id` |
| `source` | STRING | `LLM` (Phase 5) or `HUMAN` (keyword seed). LLM takes precedence. |
| `confidence` | FLOAT | Extraction confidence 0.55–1.0 |
| `brand_from_image` | STRING | Brand as read from product image by LLM (for mismatch detection) |
| `brand_mismatch` | BOOL | TRUE if brand_from_image ≠ canonical brand from product_brand_map |
| `meta_agent` | STRING | `CLAUDE_CODE`, `CODEX`, or `HUMAN` |
| `mapped_at` | TIMESTAMP | |

**Dedup rule:** When both LLM and HUMAN rows exist for the same product, the universe refresh uses LLM. HUMAN rows should be deleted once superseded (after 90-min streaming buffer).

**Confidence ranges:**
- 0.85–1.0: High confidence — product clearly matches taxonomy entry
- 0.65–0.85: Medium — good text/image match but some ambiguity
- 0.55–0.65: Low — catch-all entries for brands with no specific taxonomy

---

## Source Layer — `raw_niq_history.shopee_{country}_{category}`

Extended source with full product specifications. Use when sku_name and product image don't contain enough size/spec information.

| Column | Type | Description |
|--------|------|-------------|
| `product_id` | STRING | Same as master_clean_niq |
| `product_specification` | STRING | Structured spec fields (weight, volume, dimensions, etc.) |
| `product_description` | STRING | Full merchant description text |
| All other columns | — | Same as master_clean_niq |

**Size extraction priority order:**
1. `sku_name` text (most reliable — seller always fills this)
2. Product image (LLM multimodal)
3. `product_specification` (structured but often empty for personal care)
4. `product_description` (last resort, often marketing copy)

**Note:** For toothpaste specifically, `product_specification` contains only Stock/Brand/Oral Care Benefits/Shelf Life — no size attributes. Check category-specific notes before assuming spec data exists.

---

## Magpie Category Taxonomy

Three-level hierarchy for market share reporting:

```
magpie_category_1
├── Beauty & Personal Care
│   ├── Body Care          → Body Lotion, Body Wash, Hand Cream, ...
│   ├── Hair Care          → Shampoo, Conditioner, Hair Treatment, ...
│   ├── Face Care          → Face Cleanser, Face Moisturizer, Serum, ...
│   └── Makeup             → Foundation, Blush, Concealer, ...
├── F&B                    → Coffee, Soft Drink, Chocolate Drink, ...
├── Household Supplies     → Laundry Detergent, Fabric Softener, ...
├── Mom & Baby             → Baby Diapers, Formula Milk, ...
├── Health & Wellness      → Health Supplement, General Wellness, ...
└── Pet Care               → Cat Food, Dog Food, Pet Vitamins, ...
```

Mapping source: `niq_category_mapping` tab in working Sheet (239 rows as of May 2026).
