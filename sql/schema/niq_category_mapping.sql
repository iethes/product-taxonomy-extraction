-- magpie_reference.niq_category_mapping
-- Source-to-Magpie category mapping.
-- Source of truth: 'niq_category_mapping' tab in the working Google Sheet.
-- Loaded and uploaded by: pipeline/04_universe_append/build_marketshare_universe.py
--
-- The table is pre-expanded to include partial-key fallback rows:
--   - Full key:       (master_table, cat1, cat2, cat3, cat4, cat5)
--   - Partial key -1: (master_table, cat1, cat2, cat3, cat4, '')    when cat5 was non-empty
--   - Partial key -2: (master_table, cat1, cat2, cat3, '', '')      when cat4 was non-empty
--
-- This allows exact-match JOINs in BQ that automatically fall back to
-- less specific keys when a source product's category_4/5 don't match any row.
--
-- Write strategy: TRUNCATE + INSERT each pipeline run (239 source rows → ~500 expanded rows).

CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.niq_category_mapping`
(
  master_table       STRING   NOT NULL,   -- e.g. 'shopee_sg_shampoo'
  category_1         STRING   NOT NULL,   -- Shopee BE category level 1 (may be empty string for wildcard)
  category_2         STRING   NOT NULL,   -- Shopee BE category level 2
  category_3         STRING   NOT NULL,   -- Shopee BE category level 3
  category_4         STRING   NOT NULL,   -- Shopee BE category level 4 ('' = match any)
  category_5         STRING   NOT NULL,   -- Shopee BE category level 5 ('' = match any)
  magpie_category_1  STRING   NOT NULL,   -- e.g. 'Beauty & Personal Care'
  magpie_category_2  STRING   NOT NULL,   -- e.g. 'Hair Care'
  magpie_category_3  STRING   NOT NULL    -- e.g. 'Shampoo' — end category for market share
)
OPTIONS (
  description = "Source-to-Magpie category mapping. Pre-expanded with partial-key fallback rows. Source: niq_category_mapping tab in working Sheet. Refreshed on each Stage 04 run."
);
