-- magpie.marketshare_universe
-- Denormalized product-month market share universe.
-- Built by: pipeline/04_universe_append/build_marketshare_universe.py
-- Partitioned by month, clustered by (country, magpie_category_3, brand_id).
--
-- Grain: one row = one unique (product_id, master_table, month).
--        Model variants are collapsed: GMV is summed, model_count is a variant count.
--
-- Write strategy: DELETE month partition, then INSERT. Idempotent per month.

CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie.marketshare_universe`
(
  -- Time + source
  month              DATE     NOT NULL,   -- Partition key. First day of month e.g. 2026-04-01
  country            STRING   NOT NULL,   -- 'SG' or 'TH' — derived from master_table name
  master_table       STRING   NOT NULL,   -- e.g. 'shopee_sg_shampoo' — part of composite PK

  -- Product
  product_id         STRING   NOT NULL,   -- Shopee product ID. Composite PK: (product_id, master_table, month)
  sku_name           STRING,              -- Product title as listed by seller

  -- Brand (raw)
  brand_raw          STRING,              -- Original brand column from master_clean_niq. Never modified. For audit.

  -- Brand (resolved)
  brand_id           STRING,              -- FK → magpie_reference.brand_dict.brand_id. Format: BRD-{SCOPE}-{5digits}
                                          -- Special: 'BRD-UNDEFINED' (unknown), 'BRD-UNBRANDED' (generic/white-label)
  brand_canonical    STRING,              -- Canonical brand name from brand_dict e.g. 'Vaseline', 'Kérastase'
  brand_confidence   STRING,             -- 'HIGH' | 'MEDIUM' | 'UNRESOLVED'
  brand_source       STRING,             -- 'BRAND_FIELD' | 'PRODUCT_NAME_SCAN' | 'FALLBACK'

  -- Magpie category (3-level hierarchy)
  magpie_category_1  STRING,              -- e.g. 'Beauty & Personal Care'
  magpie_category_2  STRING,              -- e.g. 'Hair Care'
  magpie_category_3  STRING,              -- e.g. 'Shampoo' — Cluster key. End category for market share.

  -- Metrics
  gmv                FLOAT64,             -- SUM(gmv_monthly) across all model variants for this product-month (SGD/THB)
  model_count        INT64                -- COUNT(DISTINCT model_id) — number of variant SKUs under this product
)
PARTITION BY month
CLUSTER BY country, magpie_category_3, brand_id
OPTIONS (
  description = "Denormalized market share universe. Grain: product-month. Partitioned by month, clustered by (country, magpie_category_3, brand_id). Built by pipeline/04_universe_append/build_marketshare_universe.py. Standard market share filter: WHERE brand_confidence IN ('HIGH','MEDIUM') AND brand_id NOT IN ('BRD-UNDEFINED','BRD-UNBRANDED')."
);
