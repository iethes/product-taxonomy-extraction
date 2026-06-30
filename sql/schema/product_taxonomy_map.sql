-- magpie_reference.product_taxonomy_map
-- Maps every (product_id, platform, country) to exactly one taxonomy_id.
-- Covers both NIQ (Shopee SG/TH) and Intrepid (Shopee/Lazada/TikTok × 6 countries).
-- See ARCHITECTURE.md and docs/decisions/ADR-006 for design rationale.
--
-- Composite key: (product_id, platform, country) — one row per physical product.
-- master_table is metadata only (the source table this product was processed in).
-- INVARIANT: each (product_id, platform, country) maps to at most one taxonomy_id.
-- Dual-mapped products (two taxonomy_ids for the same product) are a bug.
-- Enforced by pipeline code via QUALIFY dedup before universe refresh.
--
-- source='HUMAN' means automated keyword-routing — NOT actual human review.
-- LLM rows supersede HUMAN rows; HUMAN rows are deleted after 90-min streaming buffer.

CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.product_taxonomy_map` (
  -- ── Identity (composite PK) ──────────────────────────────────────────────────
  product_id      STRING    NOT NULL,  -- Platform product ID. Unique within (platform, country).
  platform        STRING    NOT NULL,  -- 'Shopee', 'Lazada', 'TikTok Shop'
  country         STRING    NOT NULL,  -- 'SG', 'TH', 'ID', 'MY', 'PH', 'VN'

  -- ── Source trace (metadata) ──────────────────────────────────────────────────
  master_table    STRING,              -- Source table this product was processed in
                                       -- e.g. 'shopee_th_suncare', 'lazada_id_sunscreen'

  -- ── Taxonomy assignment ───────────────────────────────────────────────────────
  taxonomy_id     STRING    NOT NULL,  -- FK → product_taxonomy.taxonomy_id (e.g. SKU-003353)
  source          STRING    NOT NULL,  -- 'LLM' or 'HUMAN' (see note above)
  confidence      FLOAT64   NOT NULL,  -- 0.55–1.0. LLM high: 0.85–0.99; catch-all: 0.55–0.65

  -- ── LLM brand verification ────────────────────────────────────────────────────
  brand_from_image STRING,             -- Brand as read from product image
  brand_mismatch   BOOL,               -- TRUE if brand_from_image ≠ taxonomy brand
  meta_agent       STRING   NOT NULL,  -- 'CLAUDE_CODE', 'CODEX', or 'HUMAN'. Never NULL.

  -- ── Audit ────────────────────────────────────────────────────────────────────
  mapped_at       TIMESTAMP NOT NULL
)
CLUSTER BY platform, country, product_id
OPTIONS (
  description = "Product-to-taxonomy mapping. Composite key: (product_id, platform, country). INVARIANT: one row per product-platform-country — one taxonomy_id per product. Dual-mapped is a bug. master_table is metadata. Covers NIQ and Intrepid. source=HUMAN means automated keyword routing, NOT actual human review."
);

-- ── source values ─────────────────────────────────────────────────────────────────────
--   LLM    = Claude multimodal extraction (Phase 5). Takes precedence over HUMAN.
--   HUMAN  = automated keyword seed script (legacy name; NOT actual human review).
--            HUMAN rows are deleted once superseded by LLM (after 90-min streaming buffer).

-- ── confidence ranges ─────────────────────────────────────────────────────────────────
--   0.85–1.00  = LLM high-confidence (specific product line + size matched)
--   0.65–0.85  = LLM medium (good match, minor ambiguity)
--   0.55–0.65  = catch-all entries (brand-level fallback, no specific line taxonomy)

-- ── meta_agent values ─────────────────────────────────────────────────────────────────
--   CLAUDE_CODE = interactive Claude Code session (this pipeline)
--   CODEX       = automated script run via Codex
--   HUMAN       = manually authored (not the same as source='HUMAN' above)
