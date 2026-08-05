-- sql/migrations/005_add_category_scope_exceptions.sql
-- Durable record of products confirmed wrong-type/wrong-category for a given master_table, so
-- script/headless_taxonomy.sh's live coverage-gap query stops re-flagging the same permanently
-- out-of-scope products every top-up session. See docs/headless-runbook.md's "Confirmed out-of-scope
-- products" and docs/quality-standards.md §2 for the rationale.
--
-- Only a confirmed, per-product determination belongs here — never a blanket keyword/category carve-out.

CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.category_scope_exceptions` (
  master_table STRING    NOT NULL,
  product_id   STRING    NOT NULL,
  reason       STRING,
  confirmed_at TIMESTAMP,
  meta_agent   STRING
)
OPTIONS (
  description = "Products confirmed out-of-scope (wrong type/category) for a master_table, excluded from headless_taxonomy.sh's live coverage-gap count. See docs/headless-runbook.md."
);
