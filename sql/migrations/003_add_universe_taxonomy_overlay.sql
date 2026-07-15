-- sql/migrations/003_add_universe_taxonomy_overlay.sql
--
-- The real FMCG universe table (magpie.marketshare_universe_niq — see
-- docs/plans/headless-taxonomy-runbook-design.md Addendum for why it's this table and not
-- magpie.marketshare_universe) has no taxonomy columns and, being a shared 10.9M-row production
-- table, isn't a good ALTER TABLE target. Same pattern product_taxonomy_map already uses for
-- brand_dict/product_taxonomy: a separate overlay table keyed the same way as the source, joined
-- at query time rather than mutating the source table's schema.

CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.universe_taxonomy_overlay` (
  product_id           STRING    NOT NULL,
  platform             STRING    NOT NULL,
  country              STRING    NOT NULL,
  master_table         STRING    NOT NULL,
  taxonomy_id          STRING,
  sku_type_complete    STRING,
  taxonomy_source      STRING,
  taxonomy_confidence  STRING,
  taxonomy_meta_agent  STRING,
  updated_at           TIMESTAMP NOT NULL
)
CLUSTER BY platform, country, product_id
OPTIONS (
  description = "Taxonomy overlay for magpie.marketshare_universe_niq, keyed by (product_id, platform, country, master_table) — avoids ALTER TABLE on the shared production table. Join to marketshare_universe_niq on the same key to get combined data. See docs/headless-runbook.md § Universe refresh."
);
