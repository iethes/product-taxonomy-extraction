-- magpie_reference.product_taxonomy_embeddings
-- One embedding vector per product_taxonomy row, computed externally (Hetzner worker, see
-- docs/superpowers/specs/2026-07-17-embedding-nn-match-design.md) and loaded via batch load — never streamed.
-- Populated incrementally: the worker only ever inserts taxonomy_ids not yet present here.

CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.product_taxonomy_embeddings` (
  taxonomy_id    STRING         NOT NULL,  -- FK -> product_taxonomy.taxonomy_id
  embedding      ARRAY<FLOAT64>,            -- multilingual-e5-small output, 384 dims
  model_version  STRING         NOT NULL,  -- e.g. 'intfloat/multilingual-e5-small'
  computed_at    TIMESTAMP      NOT NULL
)
OPTIONS (
  description = "Embeddings of product_taxonomy.canonical_name, computed by the self-hosted Hetzner worker. One row per taxonomy_id. See docs/superpowers/specs/2026-07-17-embedding-nn-match-design.md."
);
