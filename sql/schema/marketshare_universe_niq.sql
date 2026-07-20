-- magpie.marketshare_universe_niq
-- Staging table for universe append, promoted to marketshare_universe after review.
-- 15 columns: month, country, master_table, product_id, sku_name, brand_raw,
--   brand_id, brand_canonical, brand_confidence, brand_source,
--   magpie_category_1, magpie_category_2, magpie_category_3, gmv, model_count
-- See docs/runbook.md § Stage 04 — Universe Append for review queries.
--
-- Built by: pipeline/04_universe_append/build_marketshare_universe.py

CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie.marketshare_universe_niq`
(
  month              DATE     NOT NULL,
  country            STRING   NOT NULL,
  master_table       STRING   NOT NULL,
  product_id         STRING   NOT NULL,
  sku_name           STRING,
  brand_raw          STRING,
  brand_id           STRING,
  brand_canonical    STRING,
  brand_confidence   STRING,
  brand_source       STRING,
  magpie_category_1  STRING,
  magpie_category_2  STRING,
  magpie_category_3  STRING,
  gmv                FLOAT64,
  model_count        INT64
)
OPTIONS (
  description = "Staging table for magpie.marketshare_universe. Promoted via INSERT ... SELECT after review. See docs/runbook.md."
);
