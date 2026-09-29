-- Durable append-only recovery log for successful Non-NIQ taxonomy inserts.
-- The target row and this log row must be inserted in the same BigQuery transaction.

CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.non_niq_taxonomy_insert_log` (
  target_table STRING NOT NULL,
  created_at TIMESTAMP NOT NULL,
  row_json JSON NOT NULL
)
PARTITION BY DATE(created_at)
OPTIONS (
  description = "Append-only record of successful non-NIQ taxonomy target-table inserts."
);
