-- magpie_reference.brand_dict
-- Canonical brand taxonomy table.
-- Small table (~thousands of rows). Human-curated, mirrored from Google Sheets.
-- See ADR-001 and ARCHITECTURE.md for design rationale.

CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.brand_dict` (
  brand_id            STRING    NOT NULL,  -- PK. Format: BRD-{SCOPE}-{5digits}
                                           -- Reserved: BRD-UNDEFINED, BRD-UNBRANDED
  canonical_name      STRING    NOT NULL,  -- Properly cased brand name e.g. "Vaseline"
  parent_brand_id     STRING,              -- NULL for top-level; FK to this table for sub-brands
  brand_level         INT64     NOT NULL,  -- 1=company, 2=brand, 3=sub-brand
  country_scope       STRING    NOT NULL,  -- 'SG', 'TH', or 'GLOBAL'
  status              STRING    NOT NULL,  -- 'ACTIVE' or 'DEPRECATED'
  deprecated_at       TIMESTAMP,           -- NULL if still active
  superseded_by       STRING,              -- brand_id of replacement if deprecated
  created_at          TIMESTAMP NOT NULL,
  updated_at          TIMESTAMP NOT NULL
)
OPTIONS (
  description = "Canonical brand master. One row per canonical brand. brand_id is the join key used across product_brand_map and marketshare_universe. Reserved: BRD-UNDEFINED (brand unresolvable), BRD-UNBRANDED (intentionally generic/white-label)."
);

-- Reserved entries (insert once on table creation)
-- INSERT INTO `sincere-hearth-273704.magpie_reference.brand_dict`
-- VALUES
--   ('BRD-UNDEFINED', 'Undefined',  NULL, 1, 'GLOBAL', 'ACTIVE', NULL, NULL, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
--   ('BRD-UNBRANDED', 'Unbranded',  NULL, 1, 'GLOBAL', 'ACTIVE', NULL, NULL, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP());
