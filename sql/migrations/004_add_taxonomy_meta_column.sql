-- sql/migrations/004_add_taxonomy_meta_column.sql
-- Adds a review-tracking column for the automated taxonomy review loop
-- (docs/superpowers/specs/2026-07-21-taxonomy-review-loop-design.md).
-- Additive and non-breaking: existing rows get _meta = NULL, meaning "never reviewed."
--
-- STRING, not JSON: stores serialized JSON text, read/written via JSON_VALUE()/TO_JSON_STRING()
-- rather than the JSON '...' literal or TO_JSON(). (Deliberate choice, not a JSON-type limitation.)

ALTER TABLE `sincere-hearth-273704.magpie_reference.product_taxonomy`
ADD COLUMN IF NOT EXISTS _meta STRING;
