# Design: Agentic Multimodal Taxonomy POC

Status: APPROVED | Date: 2026-08-04

## Background

Issue #1 requests a config-driven, multi-platform match-or-create pipeline for a new set of source/target tables (Intrepid data, not NIQ). Before building the full feature, a POC validates the agentic multimodal approach against existing human QA results.

## POC Scope

**Category:** `babycologne` (Baby & Kids Cologne) — ID market, Shopee platform  
**Month:** 2026-07-01 (latest available)  
**Mode:** Match-only — no new taxonomy records created

### Inputs

| Table | Purpose | Rows |
|---|---|---|
| `babycologne.master_babycologne_id_dev` | Source products (`qa_status = 'Reviewed'`, Shopee, July 2026) | 2,163 |
| `babycologne.babycologne_dict` | Taxonomy dict to match against | 628 |
| `babycologne.0_pipeline_babycologne_shopee_id` | Shopee enrichment (item_description, product_attributes_attrs) | — |
| `babycologne.product_id_dict_qa` | Human QA results (ground truth comparison) | 8,949 |

### Non-goals

- No writing to `product_id_dict` or `product_id_dict_qa`
- No creating new dict entries (match-only)
- No universe refresh, SKU block claims, category briefs
- No multi-platform — Shopee only for the POC

## Architecture

### Why existing scripts don't fit

The NIQ pipeline scripts (`headless_taxonomy.sh`, `targeted_qa_fix.sh`) are hardcoded to:

| | NIQ scripts | This pipeline |
|---|---|---|
| Source | `master_clean_niq.{table}` with `model_id`, `merchant_name`, `merchant_badge` | `{dataset}.master_{category}_{country}_dev` with `ecommerce_platform`, category-specific columns |
| Dict | `product_taxonomy` — uniform schema: `taxonomy_id`, `brand_id`, `product_line`, `canonical_name` | `{category}_dict` — category-specific: `keywords`, `keyword_typo`, `brand`, `sku_type` + custom columns |
| Match target | `product_taxonomy_map` → `product_taxonomy` | `product_id_dict{_image}` — flat: `product_id`, `brand`, `sku_type_complete` |
| QA | `product_taxonomy` based with Tier 1/2 gates + `_meta` | `product_id_dict_qa` — separate table, human-reviewed |
| Enrichment | None | `0_pipeline_{category}_shopee_{country}` — `item_description`, `product_attributes_attrs` |
| SKU management | `sku_block_registry`, `category_brief`, atomic claims | Not applicable to this pipeline |

The POC is a standalone script (~150 lines bash + SQL). Not an adaptation of existing scripts.

## Matching Logic

### Data flow

```
master_babycologne_id_dev (2,163 reviewed products)
    │
    ├─ LEFT JOIN 0_pipeline_babycologne_shopee_id (enrichment)
    │
    ▼
Product tokens: sku_name + item_description + product_attributes_attrs
    │
    ├── Tier 1: SQL keyword match against babycologne_dict.keywords/keywords_typo
    │       └─ match_score ≥ 2 → auto-assigned
    │
    └── Tier 2: Claude multimodal (image + text + dict subset)
            └─ Returns dict row index or -1 (unmatched)
    │
    ▼
_poc_match_20260804 (temp table)
    │
    ├─ Compare vs product_id_dict_qa (human QA)
    │
    ▼
Comparison report: brand match %, exact SKU match %, by match source
```

### Tier 1 — SQL text match (expected: ~85% coverage)

Single query, no iteration:

- Tokenize product `sku_name + item_description + product_attributes_attrs`
- Cross-join with `babycologne_dict.keywords` + `keywords_typo`
- Score by count of dict keyword tokens present in product text
- Products with `match_score >= 2` → assigned to that dict entry
- Products with `match_score < 2` → escalate to Tier 2

### Tier 2 — LLM multimodal (expected: ~15% = ~325 products)

One Claude call per product:

- Input: product image URL + `sku_name` + `item_description` + `product_attributes_attrs`
- Context: subset of dict entries (brand-filtered by sku_name text if possible, otherwise full dict)
- Output: 0-based dict row index, or -1 (no match)

Match rules:
1. Brand first — wrong brand = no match
2. Product type / sub-category / variant
3. Size / packaging
4. Scent / age_group are tiebreakers only

### Estimated cost

- Tier 1: 1 SQL query (~5s)
- Tier 2: ~325 products × ~20s each = ~2 hours total

## Output & Comparison

### Temp output table

```sql
CREATE TEMP TABLE `babycologne._poc_match_20260804` (
  product_id       STRING,
  sku_name         STRING,
  image            STRING,
  poc_brand        STRING,   -- POC matched brand
  poc_sku_type     STRING,   -- POC matched sku_type
  match_source     STRING,   -- 'TEXT' or 'LLM'
  match_score      INT64,    -- keyword overlap score
  existing_brand   STRING,   -- existing mapping brand
  existing_sku     STRING,   -- existing mapping sku_type
  qa_brand         STRING,   -- human QA brand
  qa_sku_type      STRING    -- human QA sku_type
);
```

### Comparison query

```sql
SELECT
  COUNT(*) AS total,
  COUNTIF(poc_brand = qa_brand) AS brand_match,
  COUNTIF(poc_sku_type = qa_sku_type) AS exact_sku_match,
  COUNTIF(poc_brand = qa_brand AND poc_sku_type = qa_sku_type) AS full_match,
  COUNTIF(match_source = 'TEXT') AS text_matched,
  COUNTIF(match_source = 'LLM') AS llm_matched,
  COUNTIF(match_source = 'TEXT' AND poc_sku_type = qa_sku_type) AS text_exact,
  COUNTIF(match_source = 'LLM' AND poc_sku_type = qa_sku_type) AS llm_exact,
  COUNTIF(poc_sku_type IS NULL) AS unmatched
FROM `babycologne._poc_match_20260804`;
```

### Debug: mismatches

```sql
SELECT product_id, sku_name, poc_sku_type, qa_sku_type, match_source
FROM `babycologne._poc_match_20260804`
WHERE poc_sku_type != qa_sku_type AND poc_sku_type IS NOT NULL
LIMIT 50;
```

### Success criteria

| Gate | Pass threshold |
|---|---|
| Products matched to dict | ≥ 95% |
| Exact `sku_type_complete` match with QA | ≥ 70% |
| Brand match with QA | ≥ 95% |

## Implementation Plan

1. Write `script/poc_multimodal_match.sh` — standalone bash script
   - `poc_worklist_query()` — Tier 1 SQL
   - `poc_tier2_match()` — calls Claude for ambiguous products
   - Comparison queries inline
2. Run against babycologne ID Shopee, July 2026
3. Report results

The POC script is intentionally self-contained. It does NOT reuse `headless_taxonomy.sh` or `targeted_qa_fix.sh`. If the POC validates the approach, the full feature (Issue #1) gets its own design doc with proper parameterization, config-sheet integration, and multi-platform support.
