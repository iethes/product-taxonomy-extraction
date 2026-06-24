# Quality Standards — Product Taxonomy Extraction

## What "Good" Looks Like

A category is considered production-quality when ALL of the following pass:

| Check | Gate | Why |
|-------|------|-----|
| GMV Coverage | ≥ 85% of category GMV has a taxonomy_id | Below 85% means major brands are missing |
| Dual-mapped products | 0 | A product must route to exactly one taxonomy entry |
| HUMAN+LLM co-existence | 0 | LLM supersedes HUMAN; any co-existence is a cleanup failure |
| NULL size in LLM entries | 0 (non-multi-size entries) | Size is extractable for virtually all products |
| TYPE_CONFLICT | 0 | Wet food in dry entry, lotion in oil entry = wrong routing |
| Tier-1 Mall NULLs | 0 | Official store products from scoped brands must always be mapped |

## GMV Coverage Targets by Stage

| Stage | Source | Target Coverage | Notes |
|-------|--------|-----------------|-------|
| Keyword seed (HUMAN) | Text matching | 50–70% | Baseline; acceptable before LLM |
| LLM Pass 1 (OFFICIAL) | Multimodal | +15–25% | Official store products: near-100% of official GMV |
| LLM Pass 2 (RESELLER) | Multimodal | Total ≥ 85% | Resellers in 95% GMV brand scope |
| NULL coverage pass | Multimodal | Total ≥ 90% | Top-100 NULL products mapped individually |

## QA Gate SQL Queries

Run after every category session, before universe refresh:

```sql
-- Q1: Zero dual-mapped products
SELECT product_id, master_table, COUNT(*) ct
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
WHERE master_table = '{table}'
GROUP BY 1, 2
HAVING ct > 1;
-- EXPECT: 0 rows

-- Q2: Zero HUMAN+LLM co-existence for same product
SELECT product_id FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
WHERE master_table = '{table}'
GROUP BY product_id
HAVING COUNTIF(source='LLM') > 0 AND COUNTIF(source='HUMAN') > 0;
-- EXPECT: 0 rows

-- Q3: LLM taxonomy entries with NULL size (excluding is_multi_size=TRUE)
SELECT COUNT(*) null_size_ct
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy` pt
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
  ON m.taxonomy_id = pt.taxonomy_id
WHERE m.master_table = '{table}'
  AND m.source = 'LLM'
  AND pt.size IS NULL
  AND pt.is_multi_size IS NOT TRUE;
-- EXPECT: 0 (or document each legitimate NULL)

-- Q4: Tier-1 Mall products without taxonomy (should be 0 for scoped brands)
SELECT b.canonical_name brand, COUNT(*) null_ct
FROM `sincere-hearth-273704.magpie.marketshare_universe` u
JOIN `sincere-hearth-273704.magpie_reference.brand_dict` b ON u.brand_id = b.brand_id
WHERE u.master_table = '{table}'
  AND u.month = '2026-04-01'
  AND u.merchant_badge = 'Shopee Mall'
  AND u.taxonomy_id IS NULL
GROUP BY 1
ORDER BY null_ct DESC;
-- EXPECT: 0 for all brands in the official store allowlist

-- Q5: Pack-count suspects (LLM rows with pack_count=1 but promo language in sku_name)
SELECT m.product_id, s.sku_name, pt.canonical_name
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt ON m.taxonomy_id = pt.taxonomy_id
JOIN `sincere-hearth-273704.master_clean_niq.{table}` s ON s.product_id = m.product_id
WHERE m.master_table = '{table}'
  AND m.source = 'LLM'
  AND pt.pack_count = 1
  AND REGEXP_CONTAINS(s.sku_name, r'แถม|1\+1|free|ฟรี|ซื้อ \d+ แถม|\[แพ็คคู่\]')
  AND s.month = '2026-04-01'
GROUP BY 1, 2, 3;
-- REVIEW: check each — most are GWP (correct), but some may be missed multipacks

-- Q6: TYPE_CONFLICT check (example for pet food — adapt per category)
SELECT m.product_id, s.sku_name, pt.canonical_name
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt ON m.taxonomy_id = pt.taxonomy_id
JOIN `sincere-hearth-273704.master_clean_niq.{table}` s ON s.product_id = m.product_id
WHERE m.master_table = '{table}'
  AND REGEXP_CONTAINS(LOWER(s.sku_name), r'wet|เปียก|ซอง|pouch|can|กระป๋อง')
  AND REGEXP_CONTAINS(LOWER(pt.canonical_name), r'dry|เม็ด|kibble')
  AND s.month = '2026-04-01'
GROUP BY 1, 2, 3;
-- EXPECT: 0 rows for any TYPE_CONFLICT
```

## Common QA Failures and Fixes

| Failure | Root Cause | Fix |
|---------|-----------|-----|
| NULL size across all entries | `size` column not populated in insertion script | Rebuild: always extract size before building taxonomy dict |
| Generic canonical names ("All Variants", "Body Lotion") | API auth error → text fallback; or text-only extraction | Rebuild with real LLM calls; verify ANTHROPIC_API_KEY in env |
| Wrong-category entries in map | Seed/Pass 2 scripts used global taxonomy search without category filter | Pre-sweep: `DELETE FROM product_taxonomy_map WHERE master_table='{table}' AND taxonomy_id NOT IN (correct-category SKUs)` |
| Dual-mapped products | Streaming buffer + duplicate inserts; or multi-option source rows | Dedup: keep most-specific (has_size=1 > pack_count DESC) entry; delete others |
| Pack_count=1 for ยกลัง listings | Thai bulk pattern not in pack-count parser | Add regex: `r'ยกลัง\s*(\d+)(?:\s*[กกร][ระล])'` etc. |
| HUMAN rows not cleaned up | Cleanup deferred past 90-min streaming buffer | Re-run cleanup script once buffer clears |
| Farsight DML error "match at most one source row" | Multi-model products have multiple rows per (product_id, category_3, month) | Add `QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id, category_3, month ORDER BY taxonomy_id) = 1` to src subquery |

## Coverage Calculation

```sql
-- Category GMV coverage (Apr 2026)
SELECT
  COUNTIF(taxonomy_id IS NOT NULL) mapped_products,
  COUNT(*) total_products,
  SUM(CASE WHEN taxonomy_id IS NOT NULL THEN gmv_monthly ELSE 0 END) mapped_gmv,
  SUM(gmv_monthly) total_gmv,
  ROUND(SUM(CASE WHEN taxonomy_id IS NOT NULL THEN gmv_monthly ELSE 0 END) 
        / SUM(gmv_monthly) * 100, 1) gmv_coverage_pct
FROM `sincere-hearth-273704.magpie.marketshare_universe`
WHERE master_table = '{table}'
  AND month = '2026-04-01'
  AND ecommerce_platform = 'Shopee';
```
