-- magpie_reference.product_taxonomy_map
-- Maps each source product to a canonical product taxonomy entry.

CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.product_taxonomy_map` (
  product_id       STRING    NOT NULL,
  master_table     STRING    NOT NULL,
  taxonomy_id      STRING,
  confidence       STRING,
  source           STRING,
  source_listing   STRING,
  brand_from_image STRING,
  brand_mismatch   BOOL,
  llm_raw          STRING,
  meta_agent       STRING,   -- CLAUDE_CODE, CODEX, or a future agent identifier
  mapped_at        TIMESTAMP NOT NULL
)
CLUSTER BY master_table, taxonomy_id
OPTIONS (
  description = "Product-to-taxonomy mapping. meta_agent records which agent created or curated each mapping."
);
