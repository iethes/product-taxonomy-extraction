-- Migration 001: Add platform + country columns to product_brand_map and product_taxonomy_map
-- Normalizes composite key from (product_id, master_table) to (product_id, platform, country)
-- See docs/decisions/ADR-006 for rationale.
--
-- Run steps IN ORDER. Do NOT skip the verification queries.
-- Project: sincere-hearth-273704

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 1: Add new columns (safe — non-destructive, existing rows get NULL)
-- ══════════════════════════════════════════════════════════════════════════════

ALTER TABLE `sincere-hearth-273704.magpie_reference.product_brand_map`
ADD COLUMN IF NOT EXISTS platform STRING,
ADD COLUMN IF NOT EXISTS country  STRING,
ADD COLUMN IF NOT EXISTS brand_from_image STRING,
ADD COLUMN IF NOT EXISTS brand_mismatch   BOOL;

ALTER TABLE `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
ADD COLUMN IF NOT EXISTS platform STRING,
ADD COLUMN IF NOT EXISTS country  STRING;

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 2: Backfill NIQ rows (all Shopee, country from master_table)
-- NIQ master_table format: shopee_{country}_{category}
-- ══════════════════════════════════════════════════════════════════════════════

UPDATE `sincere-hearth-273704.magpie_reference.product_brand_map`
SET
  platform = 'Shopee',
  country  = UPPER(SPLIT(master_table, '_')[SAFE_OFFSET(1)])
WHERE platform IS NULL
  AND master_table IS NOT NULL;

UPDATE `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
SET
  platform = 'Shopee',
  country  = UPPER(SPLIT(master_table, '_')[SAFE_OFFSET(1)])
WHERE platform IS NULL
  AND master_table IS NOT NULL;

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 3: Verify backfill — check for any rows still NULL
-- Expected: 0 rows
-- ══════════════════════════════════════════════════════════════════════════════

SELECT COUNT(*) as still_null
FROM `sincere-hearth-273704.magpie_reference.product_brand_map`
WHERE platform IS NULL OR country IS NULL;

SELECT COUNT(*) as still_null
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
WHERE platform IS NULL OR country IS NULL;

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 4: Measure collision count before dedup
-- Collisions = same product across multiple NIQ source tables
-- ══════════════════════════════════════════════════════════════════════════════

SELECT
  COUNT(*)                                                     AS total_rows,
  COUNT(DISTINCT CONCAT(product_id,'|',platform,'|',country))  AS unique_product_keys,
  COUNT(*) - COUNT(DISTINCT CONCAT(product_id,'|',platform,'|',country)) AS rows_to_drop_in_dedup
FROM `sincere-hearth-273704.magpie_reference.product_brand_map`;

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 5: Dedup product_brand_map to (product_id, platform, country) grain
-- Priority: LLM > BRAND_FIELD > HUMAN > PRODUCT_NAME_SCAN > FALLBACK
-- Within same source: higher confidence wins; tiebreaker: earlier mapped_at
--
-- CAUTION: This recreates the table. Back up first if needed.
-- Cost estimate: ~1.2M rows × 14 columns ≈ <$0.05 on BQ
-- ══════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE TABLE `sincere-hearth-273704.magpie_reference.product_brand_map`
CLUSTER BY platform, country, product_id
OPTIONS (description = "Product-to-brand mapping. Composite key: (product_id, platform, country). One row per physical product per platform-country. master_table is metadata. Covers NIQ and Intrepid.")
AS
SELECT * EXCEPT (rn)
FROM (
  SELECT *,
    ROW_NUMBER() OVER (
      PARTITION BY product_id, platform, country
      ORDER BY
        CASE source
          WHEN 'LLM'               THEN 1
          WHEN 'BRAND_FIELD'       THEN 2
          WHEN 'HUMAN'             THEN 3
          WHEN 'PRODUCT_NAME_SCAN' THEN 4
          WHEN 'FALLBACK'          THEN 5
          ELSE                          6
        END ASC,
        CASE confidence
          WHEN 'HIGH'       THEN 1
          WHEN 'MEDIUM'     THEN 2
          WHEN 'LOW'        THEN 3
          WHEN 'UNRESOLVED' THEN 4
          ELSE                   5
        END ASC,
        mapped_at ASC   -- earlier = first encountered = tiebreaker
    ) AS rn
  FROM `sincere-hearth-273704.magpie_reference.product_brand_map`
)
WHERE rn = 1;

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 6: Dedup product_taxonomy_map to (product_id, platform, country) grain
-- Priority: LLM > HUMAN; higher confidence wins; tiebreaker: lower taxonomy_id
-- ══════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE TABLE `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
CLUSTER BY platform, country, product_id
OPTIONS (description = "Product-to-taxonomy mapping. Composite key: (product_id, platform, country). One row per product. Dual-mapped is a bug. master_table is metadata.")
AS
SELECT * EXCEPT (rn)
FROM (
  SELECT *,
    ROW_NUMBER() OVER (
      PARTITION BY product_id, platform, country
      ORDER BY
        CASE source
          WHEN 'LLM'   THEN 1
          WHEN 'HUMAN' THEN 2
          ELSE              3
        END ASC,
        confidence DESC,
        taxonomy_id ASC   -- lower SKU = earlier, more deliberate assignment
    ) AS rn
  FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
)
WHERE rn = 1;

-- ══════════════════════════════════════════════════════════════════════════════
-- STEP 7: Post-migration verification
-- ══════════════════════════════════════════════════════════════════════════════

-- product_brand_map — confirm no duplicates on new key
SELECT COUNT(*) AS total, COUNT(DISTINCT CONCAT(product_id,'|',platform,'|',country)) AS unique_keys
FROM `sincere-hearth-273704.magpie_reference.product_brand_map`;
-- Expected: total = unique_keys

-- product_taxonomy_map — confirm no dual-mapped products
SELECT COUNT(*) AS total, COUNT(DISTINCT CONCAT(product_id,'|',platform,'|',country)) AS unique_keys
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map`;
-- Expected: total = unique_keys

-- Country distribution check
SELECT platform, country, COUNT(*) AS rows
FROM `sincere-hearth-273704.magpie_reference.product_brand_map`
GROUP BY 1, 2 ORDER BY 1, 2;
-- Expected: all rows show platform='Shopee', country IN ('SG','TH')
-- (Intrepid rows will appear here once extraction begins)
