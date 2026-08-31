-- magpie_reference.universe_sku_embeddings
-- One embedding vector per (product_id, platform, country) — the ADR-006 composite key — computed externally
-- (Hetzner worker) from marketshare_universe_niq.sku_name, loaded via batch load, never streamed.

CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.universe_sku_embeddings` (
  product_id     STRING         NOT NULL,
  platform       STRING         NOT NULL,  -- matches marketshare_universe_niq.ecommerce_platform
  country        STRING         NOT NULL,
  embedding      ARRAY<FLOAT64>,            -- multilingual-e5-small output, 384 dims
  model_version  STRING         NOT NULL,
  computed_at    TIMESTAMP      NOT NULL
)
CLUSTER BY platform, country, product_id
OPTIONS (
  description = "Embeddings of marketshare_universe_niq.sku_name, keyed by the ADR-006 composite key. Computed by the self-hosted Hetzner worker. See docs/superpowers/specs/2026-07-17-embedding-nn-match-design.md."
);
