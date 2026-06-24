-- magpie_reference.product_taxonomy
-- Canonical product/SKU master built during Phase 5.

CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.product_taxonomy` (
  taxonomy_id      STRING    NOT NULL,
  brand_id         STRING    NOT NULL,
  product_line     STRING    NOT NULL,
  sub_line         STRING,
  variant          STRING,
  size             STRING,
  pack_count       INT64,
  canonical_name   STRING    NOT NULL,
  is_bundle        BOOL,
  is_multi_variant BOOL,
  is_multi_size    BOOL,
  meta_agent       STRING,   -- CLAUDE_CODE, CODEX, or a future agent identifier
  created_at       TIMESTAMP NOT NULL,
  updated_at       TIMESTAMP NOT NULL
)
OPTIONS (
  description = "Canonical product taxonomy. meta_agent records which agent created or curated each row."
);
