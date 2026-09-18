-- Serialize non-NIQ v3 dictionary natural-identity claims.
-- BigQuery does not enforce dictionary uniqueness; the driver mutates this
-- singleton row inside each create_dict transaction so concurrent writers
-- conflict instead of appending duplicate identities.

CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.non_niq_qa_identity_locks` (
  lock_scope STRING NOT NULL,
  touched_at TIMESTAMP NOT NULL
)
OPTIONS (
  description = "Singleton mutation lock for non-NIQ v3 dictionary identity claims."
);

MERGE `sincere-hearth-273704.magpie_reference.non_niq_qa_identity_locks` AS target
USING (SELECT 'non_niq_qa_global' AS lock_scope, CURRENT_TIMESTAMP() AS touched_at) AS source
ON target.lock_scope = source.lock_scope
WHEN NOT MATCHED THEN
  INSERT (lock_scope, touched_at) VALUES (source.lock_scope, source.touched_at);
