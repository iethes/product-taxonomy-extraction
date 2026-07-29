# Prompt: Build the Task Queue Windmill App

> Paste everything below the line into a fresh Claude session (or hand it to whoever is building
> this in Windmill). It's self-contained — the receiving session has none of the context from the
> repo work that produced it.

---

Build a Windmill full code app using React for a priority task queue that already exists and is already in production use. You are building a UI on top of it, not designing the queue itself — the schema, the worker process, and the CLI that also reads/writes it are already built and live in the `product-taxonomy-extraction` repo (`script/queue_worker.sh`, `script/queue_ctl.sh`, `sql/postgres/001_task_queue.sql`). Do not modify the schema.

## Reference

- https://www.windmill.dev/docs/full_code_apps
- https://www.windmill.dev/docs/getting_started/full_code_apps_quickstart
- @f/sqm/sqm_app.raw_app/ as UI, I prefer kanban UI since it represents the tasks status well

## The database

Postgres, reached through PgBouncer in **transaction pooling mode**, and — this is the one thing that will bite you if you skip it — **shared with a NocoDB instance**, not a dedicated database for this app alone.

- Host/port/database: use f/common_logic/nocodb-pgsql-1-via-pgbouncer-PROD-DANGER.
- **Schema: `p4ct2g2urhzcfnz`, not `public`.** The table is `p4ct2g2urhzcfnz.task_queue`.
- **Get the password from the user directly (or Windmill's own secret/resource store) — never put it in a prompt, a chat message, or a file that might get shared or committed.**

### The one mandatory rule: never use `SET search_path`, ever

This is not a style preference — it caused a real, live production bug. If your Postgres resource setup, connection string, or any query sets `search_path` (via `SET search_path`, a `search_path` connection parameter, or Windmill's own "default schema" field, if it issues one under the hood), **stop and use fully-qualified table names instead.**

Why: this PgBouncer runs in transaction-pooling mode, which reuses backend connections across *different, unrelated clients*. A `SET search_path` is session-scoped — it does NOT get reset when your query's transaction ends and the connection goes back into PgBouncer's pool. The next client to get that recycled connection (which could be NocoDB's own app, querying its own tables with no schema qualifier) silently inherits your `search_path` and starts hitting the wrong schema. This was confirmed live during this queue's implementation: one connection ran `SET search_path`, and ten separate fresh connections afterward all inherited it instead of the correct default.

**The fix, and the only pattern to use:** write every query with the schema qualifier baked directly into the table name — `p4ct2g2urhzcfnz.task_queue` — never bare `task_queue`. No `SET`, no connection-level schema/search_path setting, anywhere. If Windmill's Postgres resource UI offers a "schema" field that works by issuing a `SET search_path` per connection under the hood, leave it unset/default and qualify every query yourself instead.

## Schema

```sql
-- p4ct2g2urhzcfnz.task_queue (already exists, already has data, do not CREATE or ALTER)
id             SERIAL PRIMARY KEY
table_name     TEXT NOT NULL
script_type    TEXT NOT NULL  -- 'headless_taxonomy' | 'targeted_qa_fix'
month          TEXT           -- headless_taxonomy only; NULL = live-latest
max_turns      INTEGER        -- NULL = underlying script's own default
block_size     INTEGER        -- targeted_qa_fix only; NULL = underlying script's own default (200)
loop_count     INTEGER NOT NULL  -- default 3 when submitting; see note below
priority       INTEGER NOT NULL  -- higher = runs first; default 100 when submitting
status         TEXT NOT NULL  -- 'queued' | 'running' | 'done' | 'failed' | 'blocked' | 'cancelled'
claimed_by     TEXT
claimed_at     TIMESTAMPTZ
submitted_at   TIMESTAMPTZ NOT NULL
updated_at     TIMESTAMPTZ
iterations_run INTEGER NOT NULL
last_result    JSON           -- note: json, not jsonb -- matches the pre-existing column type, do not cast
```

The table also carries several NocoDB-created bookkeeping columns (`created_at`, `updated_at` overlap, `created_by`, `updated_by`, `nc_order`, `__nc_deleted`, `nc_row_meta`, `title`) — ignore them, don't display them, don't write to them.

**Never delete a row from this table through any UI other than the guarded "Cancel" action below** (including NocoDB's own grid, if anyone has access to it). NocoDB soft-deletes by setting `__nc_deleted = true` without touching `status`, so a row "deleted" that way would still read `status = 'queued'` and the worker would still claim and run it.

## Three screens

**1. Submit form**
- Fields: `table_name` (text), `script_type` (select: `headless_taxonomy` / `targeted_qa_fix`), `month` (optional text, only relevant for `headless_taxonomy`), `max_turns` (optional int), `block_size` (optional int, only relevant for `targeted_qa_fix`), `loop_count` (int, default `3`), `priority` (int, default `100`).
- **`loop_count` guidance to show the user**: `targeted_qa_fix` has two modes. "Auto-discovery" mode (the default — no manual brief written for the category yet) can tell for itself when it's out of work, so `loop_count = 3` is safe. "Brief mode" (a category that already has a hand-written `## Targeted QA Fix Brief` section) cannot detect completion on its own and will just repeat the same brief `loop_count` times — set it to `1` for those unless you specifically know the brief needs multiple passes. If you don't know which mode a category is in, default to suggesting `1` and let the user override.
- On submit:
  ```sql
  INSERT INTO p4ct2g2urhzcfnz.task_queue
    (table_name, script_type, month, max_turns, block_size, loop_count, priority, status, submitted_at, iterations_run)
  VALUES
    ($1, $2, $3, $4, $5, $6, $7, 'queued', now(), 0)
  ```
  Set `status`, `submitted_at`, and `iterations_run` explicitly, exactly as shown — this table has no database-level defaults for them (a deliberate choice made to avoid altering a table another system owns), so every writer must supply them.

**2. Queue list**
- Table view of all rows, default sort `status, priority DESC, submitted_at ASC`.
- Filterable by `status`.
- Poll-refresh every ~10s — no need for a realtime subscription.
- Show `iterations_run / loop_count` as a progress indicator.
- Clicking a row expands `last_result` (JSON) for post-mortem — it's the raw output of the last script run for that task.

**3. Reprioritize / cancel**
- An inline-editable `priority` number and a "Cancel" button per row, **both enabled only when `status = 'queued'`** — once a worker has claimed a row (`status = 'running'` or later), it can no longer be changed from here.
- Reprioritize:
  ```sql
  UPDATE p4ct2g2urhzcfnz.task_queue
  SET priority = $1, updated_at = now()
  WHERE id = $2 AND status = 'queued'
  ```
- Cancel:
  ```sql
  UPDATE p4ct2g2urhzcfnz.task_queue
  SET status = 'cancelled', updated_at = now()
  WHERE id = $1 AND status = 'queued'
  ```
- Both are guarded by the `status = 'queued'` condition on purpose — check the affected row count. If it's 0, the row was claimed between when you loaded the page and when you clicked the button; show "task already started, can no longer be changed" rather than silently doing nothing.

## Out of scope

Don't build any polling, claiming, or task-execution logic into Windmill. A separate long-running bash process (`script/queue_worker.sh`) owns claiming and running tasks — Windmill's job is purely the three screens above: insert a row, read rows, and two guarded updates. Nothing else touches this table from Windmill's side.
