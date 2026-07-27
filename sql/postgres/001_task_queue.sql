-- sql/postgres/001_task_queue.sql
-- Applied once by hand:
--   source script/load_env.sh
--   queue_psql "$(cat sql/postgres/001_task_queue.sql)"
--
-- task_queue already exists (created via NocoDB's UI) with the columns this design needs, plus
-- NocoDB's own audit columns (created_at, updated_at, created_by, updated_by, nc_order, __nc_deleted,
-- nc_row_meta, title) -- left untouched. This is the ONLY schema change this design makes: an
-- additive, idempotent index. See docs/superpowers/specs/2026-07-27-task-queue-design.md section 3
-- for why SKIP LOCKED alone does not enforce "one worker per table" -- this index is what actually
-- does.
CREATE UNIQUE INDEX IF NOT EXISTS one_running_task_per_table
  ON task_queue (table_name) WHERE status = 'running';
