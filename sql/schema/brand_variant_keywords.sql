-- sql/schema/brand_variant_keywords.sql
-- Per-brand vocabulary of known variant/flavor names, mined from product_taxonomy.variant. Extends Tier 0's
-- deterministic-lookup pattern (brand_dict) into variant matching. Feeds the classifier as a feature, not a
-- hard filter. Real coverage is limited (variant is populated on ~19% of product_taxonomy rows) - that's
-- expected, this is one signal among several, not a gate.

CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.brand_variant_keywords` (
  brand_id       STRING    NOT NULL,
  variant        STRING    NOT NULL,
  product_count  INT64     NOT NULL,
  computed_at    TIMESTAMP NOT NULL
)
OPTIONS (
  description = "Per-brand variant/flavor vocabulary mined from product_taxonomy.variant. See docs/superpowers/specs/2026-07-18-taxonomy-match-classifier-design.md."
);
