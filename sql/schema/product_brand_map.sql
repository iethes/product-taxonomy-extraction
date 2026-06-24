-- magpie_reference.product_brand_map
-- Maps every (product_id, master_table) to a canonical brand via brand_id.
-- Large table (~1-2M rows, growing with each universe append cycle).
-- See ARCHITECTURE.md for design rationale.
--
-- Phase 5 columns (variant_label, size_label, pack_type, segment) are nullable
-- placeholders — populated in Stage 05 after brand mapping is complete.

CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.product_brand_map` (
  -- ── Identity ────────────────────────────────────────────────────────────────
  product_id      STRING    NOT NULL,  -- Shopee product ID. Composite PK with master_table.
  master_table    STRING    NOT NULL,  -- e.g. 'shopee_sg_hand_and_body_moisturiser'

  -- ── Brand resolution (Phase 2–4) ────────────────────────────────────────────
  brand_id        STRING    NOT NULL,  -- FK → brand_dict.brand_id
  brand_raw       STRING,              -- Original value from master_clean_niq.brand — never modified
  matched_token   STRING,              -- For PRODUCT_NAME_SCAN: the token/substring that matched
  confidence      STRING    NOT NULL,  -- 'HIGH', 'MEDIUM', 'LOW', 'UNRESOLVED'
  source          STRING    NOT NULL,  -- 'BRAND_FIELD', 'PRODUCT_NAME_SCAN', 'HUMAN', 'FALLBACK'

  -- ── Product attributes (Phase 5) — all nullable until populated ─────────────
  variant_label   STRING,              -- e.g. 'Intensive Care', 'Sensitive', 'Original'
  size_label      STRING,              -- e.g. '200ml', '1kg', '6-pack'
  pack_type       STRING,              -- e.g. 'Tube', 'Pump', 'Sachet', 'Bundle'
  segment         STRING,              -- e.g. 'Premium', 'Mass', 'Economy'

  -- ── Audit ────────────────────────────────────────────────────────────────────
  mapped_at       TIMESTAMP NOT NULL,
  updated_at      TIMESTAMP NOT NULL
)
CLUSTER BY master_table, product_id
OPTIONS (
  description = "Product-to-brand mapping. Composite PK: (product_id, master_table). brand_id joins to brand_dict. brand_raw is the original Shopee value, never modified. Phase 5 columns (variant_label, size_label, pack_type, segment) are populated after brand mapping is complete."
);

-- confidence values:
--   HIGH        = BRAND_FIELD exact match, PRODUCT_NAME_SCAN start-of-title, or HUMAN
--   MEDIUM      = PRODUCT_NAME_SCAN anywhere in title (word boundary)
--   LOW         = fuzzy match — requires human review before promoting
--   UNRESOLVED  = FALLBACK — no brand signal found

-- source values:
--   BRAND_FIELD         = matched from brand column in master_clean_niq
--   PRODUCT_NAME_SCAN   = inferred from product_name (brand field was blank)
--   HUMAN               = manually assigned or corrected
--   FALLBACK            = assigned BRD-UNDEFINED or BRD-UNBRANDED
