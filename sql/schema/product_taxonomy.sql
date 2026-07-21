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
  meta_agent       STRING    NOT NULL,  -- 'CLAUDE_CODE', 'CODEX', or 'HUMAN'
  created_at       TIMESTAMP NOT NULL,
  updated_at       TIMESTAMP NOT NULL,
  _meta            STRING               -- review-loop state (serialized JSON text); see sql/migrations/004_add_taxonomy_meta_column.sql
)
OPTIONS (
  description = "Canonical product taxonomy. meta_agent records which agent created or curated each row."
);
