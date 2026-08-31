# Handoff: `non_niq_qa` support for the task queue submitter UI

> For whoever maintains the Windmill queue app built from
> [`docs/windmill-app-prompt.md`](windmill-app-prompt.md) (or any other UI submitting rows to
> `task_queue`). That doc's "Submit form" only offers `script_type` = `headless_taxonomy` /
> `targeted_qa_fix` — this is an addendum describing what's needed to also submit
> `non_niq_qa` tasks, which `script/non_niq/queue_worker.sh` now claims and runs.

## What changed in the repo

`script/non_niq/queue_worker.sh` now runs `script/non_niq/non_niq_qa_v2.sh`, whose full signature
is:

```
non_niq_qa_v2.sh <DATASET> <PLATFORM> [COUNTRY] [MAX_TURNS] [MAX_ROWS] [KATEGORI]
```

`task_queue`'s existing generic columns don't have a slot for every one of those, so this maps
onto the schema as follows — **no columns were added except `extra_args`** (migration below):

| v2 arg | Where it comes from | Notes |
|---|---|---|
| `DATASET` | `table_name`, 1st `:`-segment | e.g. `cookiesbiscuit` |
| `PLATFORM` | `table_name`, 2nd `:`-segment | e.g. `shopee` |
| `COUNTRY` | `table_name`, 3rd `:`-segment, **optional** | defaults to `ID` if omitted |
| `MAX_TURNS` | `max_turns` column | same as the other script types |
| `MAX_ROWS` | `block_size` column | reused — for `script_type='non_niq_qa'`, `block_size` means max worklist rows, not the `targeted_qa_fix` batch size it means elsewhere |
| `KATEGORI` | `extra_args` column, `.kategori` key | optional per-category sub-scope filter (e.g. lighting's `"Connected Light"`); most categories don't have this and should omit it |

So `table_name` for `non_niq_qa` rows is `"{dataset}:{platform}"` or
`"{dataset}:{platform}:{country}"` — **not** the BigQuery table name `headless_taxonomy`/
`targeted_qa_fix` rows use. This also means the `one_running_task_per_table` lock is
country-scoped for non_niq_qa: two rows for the same dataset/platform but different countries can
run concurrently.

`extra_args` is a generic JSON column (any per-`script_type` param that doesn't fit the existing
generic columns lands here) — deliberately not a one-off `kategori` column, so a future new param
doesn't need its own migration. Right now the only key any `script_type` reads from it is
`non_niq_qa`'s `kategori`.

## Required migration (apply before enabling non_niq_qa submission)

`extra_args` doesn't exist on the live table yet. Additive, idempotent, same low-risk shape as the
existing `one_running_task_per_table` index migration — see
[`sql/postgres/002_task_queue_extra_args.sql`](../sql/postgres/002_task_queue_extra_args.sql):

```sql
ALTER TABLE p4ct2g2urhzcfnz.task_queue ADD COLUMN IF NOT EXISTS extra_args JSON;
```

Apply it the same way the original index migration was applied (`queue_psql`, real schema-qualified
name, never `SET search_path` — see `docs/windmill-app-prompt.md`'s rule on why). This is a schema
change to a shared, in-production table — get sign-off before running it, same as any other prod
DDL.

## Submit form changes

- Add `non_niq_qa` to the `script_type` select.
- When `script_type = non_niq_qa`:
  - `table_name`: label as "dataset:platform" or "dataset:platform:country", not the BigQuery
    table name field the other two types use. Validate at least one `:` is present.
  - `month`: hide/disable — non_niq_qa resolves its own latest month internally, this field is
    ignored for this `script_type`.
  - `max_turns`: same field, same meaning.
  - `block_size`: relabel to "max rows" when `script_type = non_niq_qa` (same underlying column,
    different meaning — same pattern the form should already use to hide it for `headless_taxonomy`).
  - Add a new optional `kategori` text field, shown only for `non_niq_qa`. On submit, if non-empty,
    write it as `extra_args = json_build_object('kategori', $kategori)`; if empty, write
    `extra_args = NULL`.

Example insert:

```sql
INSERT INTO p4ct2g2urhzcfnz.task_queue
  (table_name, script_type, month, max_turns, block_size, loop_count, priority, extra_args,
   status, submitted_at, iterations_run)
VALUES
  ('cookiesbiscuit:shopee:ID', 'non_niq_qa', NULL, $1, $2, $3, $4,
   CASE WHEN $5::text IS NULL OR $5 = '' THEN NULL ELSE json_build_object('kategori', $5) END,
   'queued', now(), 0)
```

Everything else in `docs/windmill-app-prompt.md` (queue list screen, reprioritize/cancel screen,
the "never `SET search_path`" rule, the "never delete via NocoDB's grid" warning) applies unchanged
to `non_niq_qa` rows — they're the same table, same status lifecycle, just a third `script_type`
value.
