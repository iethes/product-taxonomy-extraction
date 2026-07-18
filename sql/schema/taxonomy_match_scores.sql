-- sql/schema/taxonomy_match_scores.sql
-- Scored (product, candidate) pairs from the supervised taxonomy-match classifier. Written by the Hetzner
-- scoring script (batch load, never streamed). Consumed by the three consumption-mode queries as a simple
-- threshold read. See docs/superpowers/specs/2026-07-18-taxonomy-match-classifier-design.md.

CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.taxonomy_match_scores` (
  product_id             STRING    NOT NULL,
  platform               STRING    NOT NULL,
  country                STRING    NOT NULL,
  candidate_taxonomy_id  STRING    NOT NULL,
  match_probability      FLOAT64   NOT NULL,
  model_version          STRING    NOT NULL,
  computed_at            TIMESTAMP NOT NULL
)
CLUSTER BY platform, country, product_id
OPTIONS (
  description = "Scored (product, candidate) pairs from the supervised taxonomy-match classifier. See docs/superpowers/specs/2026-07-18-taxonomy-match-classifier-design.md."
);
