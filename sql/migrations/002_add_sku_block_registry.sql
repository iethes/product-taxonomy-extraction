-- sql/migrations/002_add_sku_block_registry.sql
CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.sku_block_registry` (
  block_start  INT64     NOT NULL,
  block_end    INT64     NOT NULL,
  master_table STRING    NOT NULL,
  scenario     STRING    NOT NULL,  -- 'full_rebuild' | 'assessment' | 'targeted_qa_fix'
  claimed_at   TIMESTAMP NOT NULL,
  status       STRING    NOT NULL   -- 'ACTIVE' | 'FAILED_QA' | 'ABANDONED' | 'COMPLETE'
)
OPTIONS (
  description = "Atomic SKU block allocation for headless taxonomy sessions. See docs/headless-runbook.md."
);
