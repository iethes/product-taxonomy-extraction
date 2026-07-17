-- magpie_reference.taxonomy_match_audit_flags
-- Flag-only output of embedding-match audit mode: cases where the embedding matcher's independent top-1
-- disagrees with an existing source='LLM' taxonomy_map row. Never consumed automatically — a queue for
-- human/LLM QA review (feeds the Targeted QA Fix scenario in docs/headless-runbook.md).

CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.taxonomy_match_audit_flags` (
  product_id            STRING    NOT NULL,
  platform              STRING    NOT NULL,
  country               STRING    NOT NULL,
  current_taxonomy_id   STRING    NOT NULL,  -- what product_taxonomy_map currently says
  suggested_taxonomy_id STRING    NOT NULL,  -- the embedding matcher's disagreeing top-1
  distance              FLOAT64   NOT NULL,
  flagged_at            TIMESTAMP NOT NULL
)
CLUSTER BY platform, country, product_id
OPTIONS (
  description = "Flag-only audit output: embedding-match disagreements with existing LLM taxonomy mappings. Never written to product_taxonomy_map. See docs/superpowers/specs/2026-07-17-embedding-nn-match-design.md."
);
