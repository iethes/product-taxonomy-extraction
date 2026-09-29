-- Durable post-commit delivery events for script/non_niq/non_niq_qa_v3.py.
-- BigQuery does not enforce primary keys; the driver conditionally inserts event_id
-- inside the same transaction as its QA, dictionary, and filter writes.

CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.non_niq_qa_outbox` (
  event_id STRING NOT NULL,
  attempt_id STRING NOT NULL,
  decision_id STRING NOT NULL,
  dataset STRING NOT NULL,
  platform STRING NOT NULL,
  country STRING NOT NULL,
  event_type STRING NOT NULL,
  payload STRING NOT NULL,
  status STRING NOT NULL,
  attempts INT64 NOT NULL,
  last_error STRING,
  created_at TIMESTAMP NOT NULL,
  completed_at TIMESTAMP
)
PARTITION BY DATE(created_at)
CLUSTER BY status, dataset, platform, country
OPTIONS (
  description = "Durable post-commit Meilisearch and Sheets delivery events for non_niq_qa_v3.py. event_id is conditionally unique in driver DML."
);
