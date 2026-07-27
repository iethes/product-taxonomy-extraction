-- sql/postgres/001_task_queue.sql
-- Reference DDL -- shown here against the bare table name for readability. Applied once by hand
-- against the REAL, schema-qualified table (never against a bare, unqualified name -- see Global
-- Constraints on why no SET search_path is ever used in this design):
--   source script/load_env.sh
--   queue_psql "CREATE UNIQUE INDEX IF NOT EXISTS one_running_task_per_table ON ${QUEUE_TABLE} (table_name) WHERE status = 'running';"
--
-- task_queue already exists (created via NocoDB's UI) with the columns this design needs, plus
-- NocoDB's own audit columns (created_at, updated_at, created_by, updated_by, nc_order, __nc_deleted,
-- nc_row_meta, title) -- left untouched. This is the ONLY schema change this design makes: an
-- additive, idempotent index. See docs/superpowers/specs/2026-07-27-task-queue-design.md section 3
-- for why SKIP LOCKED alone does not enforce "one worker per table" -- this index is what actually
-- does.
CREATE UNIQUE INDEX IF NOT EXISTS one_running_task_per_table
  ON task_queue (table_name) WHERE status = 'running';
