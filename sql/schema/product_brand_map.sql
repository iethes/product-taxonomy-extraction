-- magpie_reference.product_brand_map
-- Maps every (product_id, platform, country) to a canonical brand via brand_id.
-- Covers both NIQ (Shopee SG/TH) and Intrepid (Shopee/Lazada/TikTok × 6 countries).
-- Large table (~1-2M rows, growing with each pipeline run).
-- See ARCHITECTURE.md and docs/decisions/ADR-006 for design rationale.
--
-- Composite key: (product_id, platform, country) — one row per physical product.
-- master_table is metadata only (the source table where this product was first seen).
-- Logically unique on (product_id, platform, country) — enforced by pipeline code, not BQ.
--
-- Phase 5 columns (variant_label, size_label, pack_type, segment) are nullable
-- placeholders — populated in Stage 05 after brand mapping is complete.

CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.product_brand_map` (
  -- ── Identity (composite PK) ──────────────────────────────────────────────────
  product_id      STRING    NOT NULL,  -- Platform product ID. Unique within (platform, country).
  platform        STRING    NOT NULL,  -- 'Shopee', 'Lazada', 'TikTok Shop'
  country         STRING    NOT NULL,  -- 'SG', 'TH', 'ID', 'MY', 'PH', 'VN'

  -- ── Source trace (metadata) ──────────────────────────────────────────────────
  master_table    STRING,              -- First source table this product was seen in
                                       -- e.g. 'shopee_th_suncare', 'lazada_th_sunscreen'

  -- ── Brand resolution ─────────────────────────────────────────────────────────
  brand_id        STRING    NOT NULL,  -- FK → brand_dict.brand_id
  brand_raw       STRING,              -- Original brand_name value from source — never modified
  matched_token   STRING,              -- For PRODUCT_NAME_SCAN: the brand token matched in product_name
  confidence      STRING    NOT NULL,  -- 'HIGH', 'MEDIUM', 'LOW', 'UNRESOLVED'
  source          STRING    NOT NULL,  -- See source values below

  -- ── LLM correction signal (Phase 5) ─────────────────────────────────────────
  brand_from_image STRING,             -- Brand as read from product image by LLM
  brand_mismatch   BOOL,               -- TRUE if brand_from_image ≠ brand_id canonical name
                                       -- Only flagged for PRODUCT_NAME_SCAN + FALLBACK sources

  -- ── Product attributes (Phase 5) — all nullable until populated ─────────────
  variant_label   STRING,              -- e.g. 'Intensive Care', 'Sensitive', 'Original'
  size_label      STRING,              -- e.g. '200ml', '1kg', '6-pack'
  pack_type       STRING,              -- e.g. 'Tube', 'Pump', 'Sachet', 'Bundle'
  segment         STRING,              -- e.g. 'Premium', 'Mass', 'Economy'

  -- ── Audit ────────────────────────────────────────────────────────────────────
  mapped_at       TIMESTAMP NOT NULL,
  updated_at      TIMESTAMP NOT NULL
)
CLUSTER BY platform, country, product_id
OPTIONS (
  description = "Product-to-brand mapping. Composite key: (product_id, platform, country). One row per physical product per platform-country. master_table is metadata (first source table seen). Covers NIQ (Shopee SG/TH) and Intrepid (Shopee/Lazada/TikTok × 6 countries). brand_raw is original source value, never modified."
);

-- ── source values ────────────────────────────────────────────────────────────────────
--   BRAND_FIELD         = brand_name column was filled in source — looked up in brand_dict
--   PRODUCT_NAME_SCAN   = automated scan of product_name/sku_name for known brand tokens
--   HUMAN               = automated keyword-routing script (legacy name — NOT actual human review)
--   LLM                 = Claude multimodal extraction — reads product image + title text
--   FALLBACK            = no signal found — assigned BRD-UNDEFINED or BRD-UNBRANDED
--
-- Priority order (highest accuracy first): LLM > BRAND_FIELD > HUMAN > PRODUCT_NAME_SCAN > FALLBACK

-- ── confidence values ────────────────────────────────────────────────────────────────
--   HIGH        = BRAND_FIELD exact match, PRODUCT_NAME_SCAN start-of-title, LLM high-conf
--   MEDIUM      = PRODUCT_NAME_SCAN anywhere in title (word boundary match)
--   LOW         = fuzzy match — requires review before promoting
--   UNRESOLVED  = FALLBACK — no brand signal found

-- ── platform ─────────────────────────────────────────────────────────────────────────
--   'Shopee'       = Shopee marketplace (NIQ master_clean_niq + Intrepid shopee_* tables)
--   'Lazada'       = Lazada marketplace (Intrepid lazada_* tables)
--   'TikTok Shop'  = TikTok Shop (Intrepid tiktok_* tables)
--   Note: TikTok brand_name is always NULL — BRAND_FIELD step skipped for TikTok products

-- ── country ──────────────────────────────────────────────────────────────────────────
--   'SG' = Singapore   'TH' = Thailand    'ID' = Indonesia
--   'MY' = Malaysia    'PH' = Philippines  'VN' = Vietnam
