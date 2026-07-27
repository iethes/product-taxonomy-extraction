# Design: Priority Task Queue for `headless_taxonomy.sh` / `targeted_qa_fix.sh`

> Status: approved design, not yet implemented.
> Companion to [`script/headless_taxonomy.sh`](../../../script/headless_taxonomy.sh) and
> [`script/targeted_qa_fix.sh`](../../../script/targeted_qa_fix.sh).

---

## Problem

Today, running these two scripts against a category is a manual, one-at-a-time action: someone picks a
table, runs the script, waits, and picks the next one. There's no way to queue up work ahead of time,
change what runs next based on shifting priorities, or run several categories concurrently without someone
manually avoiding collisions on the same table.

This design adds a priority queue: submit `(table, script_type, params)` tasks, reprioritize or cancel
queued ones, and have one or more worker processes pull the highest-priority task and run it — looping the
underlying script up to `loop_count` times per task, since one `headless_taxonomy.sh` invocation is
frequently not enough to close a category's coverage gap.

The queue UI (submit / reprioritize / view) is built separately in Windmill; this repo owns the storage
schema, the worker, and a CLI stopgap for using the queue before that UI exists.

---

## Deliverable scope

| File | Change |
|------|--------|
| `sql/postgres/001_task_queue.sql` | New: `task_queue` table + mandatory partial unique index |
| `script/queue_worker.sh` | New: poll/claim/run/heartbeat loop |
| `script/queue_ctl.sh` | New: `submit`/`list`/`priority`/`cancel` CLI |
| `script/test_queue_worker.sh` | New: self-test for pure helpers (signal parsing, claim-race handling), no-network style matching `script/test_targeted_qa_fix.sh` |
| `script/headless_taxonomy.sh` | Append a `QUEUE_SIGNAL:` line at existing exit points |
| `script/targeted_qa_fix.sh` | Add an auto-discovery-mode pre-check; append a `QUEUE_SIGNAL:` line at existing exit points |
| `script/load_env.sh` | New: sourced by `queue_worker.sh`/`queue_ctl.sh` to export `.env` into the process environment |
| `.env.example` | New: template for `QUEUE_DATABASE_URL`, `POLL_INTERVAL_SECONDS`, `LEASE_TIMEOUT_HOURS` |
| `.gitignore` | Add `.env` (holds a live DB connection string — must never be committed) |
| `docs/headless-runbook.md` | New "Queue mode" section: `QUEUE_DATABASE_URL`, running N workers, brief-mode `loop_count` caveat |

---

## 1. Storage: Postgres

Requirements: mutable priority (editable after submission), a browsable/auditable queue, strict per-table
mutual exclusion (two workers must never run the same table concurrently — both scripts write to the same
category doc, git-commit it, and claim SKU blocks for that table), and crash recovery.

- **Postgres (chosen)**: the `UPDATE ... WHERE id = (SELECT ... FOR UPDATE SKIP LOCKED) RETURNING ...`
  pattern is the standard concurrency-safe claim. Priority/cancel are plain `UPDATE`s. The queue table
  itself is directly browsable/editable by Windmill — no separate audit log needed.
- **Redis**: a sorted set gives priority ordering, but "browse and edit an item already in the queue" plus
  "keep history" both mean building a persistence layer on top anyway.
- **RabbitMQ**: push/consume, not "peek and edit items already enqueued" — messages aren't individually
  addressable once enqueued. Wrong shape for user-editable priority.
- **BigQuery**: already the pipeline's output store, not suited to an operational queue needing frequent
  small transactional updates — no real row locking, and CLAUDE.md documents BQ's streaming-buffer/DML
  quirks as a repeated source of past bugs. Keep it out of the operational path entirely.

---

## 2. Schema

```sql
-- sql/postgres/001_task_queue.sql
-- Applied once by hand: psql "$QUEUE_DATABASE_URL" -f sql/postgres/001_task_queue.sql

CREATE TABLE IF NOT EXISTS task_queue (
  id             SERIAL PRIMARY KEY,
  table_name     TEXT NOT NULL,
  script_type    TEXT NOT NULL CHECK (script_type IN ('headless_taxonomy','targeted_qa_fix')),
  month          TEXT,               -- headless_taxonomy only; NULL = live-latest
  max_turns      INTEGER,            -- NULL = script's own default
  block_size     INTEGER,            -- targeted_qa_fix only; NULL = script's own default (200)
  loop_count     INTEGER NOT NULL DEFAULT 3,
  priority       INTEGER NOT NULL DEFAULT 100,   -- higher = runs first
  status         TEXT NOT NULL DEFAULT 'queued'
                   CHECK (status IN ('queued','running','done','failed','blocked','cancelled')),
  claimed_by     TEXT,
  claimed_at     TIMESTAMPTZ,
  submitted_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  iterations_run INTEGER NOT NULL DEFAULT 0,
  last_result    JSONB
);

-- REQUIRED, not optional — see "Mutual exclusion" below for why SKIP LOCKED alone doesn't enforce
-- "one worker per table," and why this index is what actually does.
CREATE UNIQUE INDEX IF NOT EXISTS one_running_task_per_table
  ON task_queue (table_name) WHERE status = 'running';
```

Config: one new env var, `QUEUE_DATABASE_URL` (standard libpq connection string), read by
`queue_worker.sh` and `queue_ctl.sh`.

---

## 3. Mutual exclusion — the fragile part

**SKIP LOCKED alone does not give per-table exclusion.** If table X has two queued rows and two workers
claim concurrently: Worker A locks row 1; Worker B's `SELECT` doesn't see a *running* row for X yet, so
SKIP LOCKED only skips the *locked row* (row 1) and happily picks row 2 — same table, two workers, both
think they won. The `one_running_task_per_table` unique index is what actually blocks the second
`UPDATE` (raises `23505` on commit). This means the claim function must treat that error as an expected
race outcome, not a crash:

```bash
# script/queue_worker.sh (excerpt)
claim_next_task() {
  local out
  if ! out=$(psql "$QUEUE_DATABASE_URL" -t -A -F'|' -c "
    UPDATE task_queue SET status='running', claimed_by='${WORKER_ID}', claimed_at=now()
    WHERE id = (
      SELECT id FROM task_queue
      WHERE status='queued'
        AND table_name NOT IN (SELECT table_name FROM task_queue WHERE status='running')
      ORDER BY priority DESC, submitted_at ASC
      FOR UPDATE SKIP LOCKED LIMIT 1
    )
    RETURNING id, table_name, script_type, month, max_turns, block_size, loop_count;" 2>&1)
  then
    [[ "$out" == *"duplicate key value violates unique constraint"* ]] && { echo ""; return 0; }
    echo "$out" >&2; return 1   # a genuine SQL error should not crash the worker loop
  fi
  echo "$out"
}
```

Under `set -euo pipefail`, an uncaught non-zero exit from this function inside `row=$(claim_next_task)`
would kill the worker — so the race-loss case must return 0 with empty output, treated identically to
"no task available right now."

**Lease timeout must be per-iteration, not per-task.** A task can run `loop_count` sessions back to back
(hours each); a lease sized for the whole task is either too short (steals a live task — and that
reclaim path does *not* go through the unique index, since it's a status transition on the same row, so a
stolen-but-still-running task produces a silent double-run) or too long (slow to notice a real crash).
Fix: refresh `claimed_at` at every iteration boundary, and size `LEASE_TIMEOUT_HOURS` to comfortably cover
one iteration:

```bash
# heartbeat, at the start of each loop_count iteration:
psql "$QUEUE_DATABASE_URL" -c "UPDATE task_queue SET claimed_at=now() WHERE id=$id AND status='running';"

# reclaim pass, run at the top of every poll cycle:
psql "$QUEUE_DATABASE_URL" -c "
  UPDATE task_queue SET status='queued', claimed_by=NULL, claimed_at=NULL
  WHERE status='running' AND claimed_at < now() - interval '${LEASE_TIMEOUT_HOURS:-4} hours';"
```

---

## 4. Early-stop signal: worklist-empty, not rows-created

`rows_created == 0` does **not** mean "nothing to do" — `targeted_qa_fix.sh`'s auto-discovery mode can
legitimately update `_meta` in place, find everything correct, and report zero rows created while
thousands of entries remain unreviewed. The real "stop looping" signal has to come from each script's own
live worklist check, not from the agent's self-reported row counts:

- **`headless_taxonomy.sh`** already re-queries `gap_count` at the top of every invocation. Add one line
  to the existing `gap_count == 0` branch (before the `exit 0`):
  ```bash
  echo "QUEUE_SIGNAL: NOTHING_TO_DO"
  ```
  Because the wrapper re-invokes this script fresh each loop iteration, this is already correct without
  further changes: if iteration 1 closes the gap, iteration 2's own pre-check finds `gap_count == 0` and
  stops itself before ever calling `claude -p` again.

- **`targeted_qa_fix.sh` auto-discovery mode** currently has no pre-check before calling `claude -p`. Add
  one: a cheap `COUNT(*)` of STEP 1's own worklist query (never-reviewed or previously-unconfident
  entries). If 0, emit `QUEUE_SIGNAL: NOTHING_TO_DO` and skip the `claude -p` call entirely — same pattern
  as `headless_taxonomy.sh`.

- **`targeted_qa_fix.sh` brief mode** has no queryable "remaining count" — a brief is a fixed, hand-written
  scope. No pre-check is possible, so brief-mode runs always signal `DONE` on success and never
  self-detect completion. **Operator responsibility, documented in the CLI help and runbook: set
  `loop_count = 1` for brief-mode tasks** unless the brief is known to need multiple passes.

- Post-run status mapping (both scripts, after the JSON result is parsed): `blocked → BLOCKED`,
  `failed`/unparseable → `FAILED`, everything else (`complete`/`partial`, regardless of `rows_created`) →
  `DONE`. `BLOCKED` and `FAILED` both stop the loop immediately. `DONE` continues to the next iteration,
  where the script's own pre-check decides whether there's still work.

Wrapper's per-iteration decision:

```bash
for i in $(seq 1 "$loop_count"); do
  heartbeat "$id"
  output=$(run_underlying_script ...)          # headless_taxonomy.sh or targeted_qa_fix.sh
  signal=$(grep -o 'QUEUE_SIGNAL: [A-Z_]*' <<<"$output" | tail -1 | cut -d' ' -f2)
  iterations_run=$((iterations_run + 1))
  case "$signal" in
    NOTHING_TO_DO) final_status=done;    break ;;
    BLOCKED)       final_status=blocked; break ;;
    FAILED)        final_status=failed;  break ;;
    DONE)          final_status=done ;;             # keep looping unless this was the last iteration
    *)             final_status=failed;  break ;;   # missing/unparseable signal is a failure, not a silent no-op
  esac
done
# persist: status=final_status, iterations_run, last_result=output's parsed JSON (or raw tail on parse failure)
```

Failure handling (confirmed): `FAILED` and `BLOCKED` are both terminal for the task — the wrapper does not
retry within the same task. A human investigates and resubmits via `queue_ctl.sh submit` (or Windmill).

---

## 5. `script/queue_worker.sh` — outline

```bash
source "$(dirname "$0")/load_env.sh"   # exports QUEUE_DATABASE_URL etc. from .env, if present

WORKER_ID="$(hostname)-$$"

main() {
  while true; do
    reclaim_stale_leases
    row=$(claim_next_task) || { sleep "${POLL_INTERVAL_SECONDS:-15}"; continue; }
    [[ -z "$row" ]] && { sleep "${POLL_INTERVAL_SECONDS:-15}"; continue; }
    run_task "$row"     # the per-iteration loop from Section 4, then a final status UPDATE
  done
}
```

Running N workers = starting `script/queue_worker.sh` N times (tmux/nohup/systemd/etc — the same kind of
manual process-management already used for `claude -p` sessions today; not something this repo builds).

### `.env` loading

Both `queue_worker.sh` and `queue_ctl.sh` need `QUEUE_DATABASE_URL` (and optionally
`POLL_INTERVAL_SECONDS` / `LEASE_TIMEOUT_HOURS`) in their process environment. Rather than requiring the
operator to `export` these by hand every session, both scripts source a small shared helper at startup:

```bash
# script/load_env.sh — sourced, not executed directly, by queue_worker.sh / queue_ctl.sh.
# Also usable standalone: `source script/load_env.sh` in an interactive shell.
set -a
[[ -f "$(dirname "${BASH_SOURCE[0]}")/../.env" ]] && source "$(dirname "${BASH_SOURCE[0]}")/../.env"
set +a
```

`set -a` / `set +a` marks every variable assigned while sourcing `.env` for export, without needing an
`export` prefix on each line in `.env` itself. If `.env` doesn't exist (e.g. CI, or vars already exported
via shell profile), this is a silent no-op — existing environment variables win either way, since `.env`
values only apply if actually present in the file.

```bash
# .env.example — copy to .env and fill in real values; .env itself is gitignored.
QUEUE_DATABASE_URL=postgres://user:password@localhost:5432/taxonomy_queue
POLL_INTERVAL_SECONDS=15
LEASE_TIMEOUT_HOURS=4
```

---

## 6. `script/queue_ctl.sh` — CLI stopgap

Thin wrapper over raw SQL — no ORM, matches the repo's existing bash+CLI convention. Exists so the queue is
usable/testable before the Windmill UI is built.

```
script/queue_ctl.sh submit <table> <headless_taxonomy|targeted_qa_fix> \
    [--month YYYY-MM] [--max-turns N] [--block-size N] [--loop-count N] [--priority N]
script/queue_ctl.sh list [--status queued|running|done|failed|blocked|cancelled]
script/queue_ctl.sh priority <task_id> <new_priority>
script/queue_ctl.sh cancel <task_id>          # only affects status='queued' rows
```

---

## 7. Windmill UI — prompt for the implementing agent

> Build a Windmill app against an existing Postgres table `task_queue` (connection: a Windmill Postgres
> resource pointing at `QUEUE_DATABASE_URL`). Do not modify the schema — it's owned by another repo
> (`product-taxonomy-extraction`, `sql/postgres/001_task_queue.sql`). Columns: `id, table_name, script_type
> ('headless_taxonomy'|'targeted_qa_fix'), month, max_turns, block_size, loop_count, priority (int,
> higher=more urgent, default 100), status ('queued'|'running'|'done'|'failed'|'blocked'|'cancelled'),
> claimed_by, claimed_at, submitted_at, updated_at, iterations_run, last_result (jsonb)`.
>
> Three screens:
>
> 1. **Submit form** — fields: `table_name` (text), `script_type` (select), `month` (optional text, only
>    relevant for headless_taxonomy), `max_turns` (optional int), `block_size` (optional int, only relevant
>    for targeted_qa_fix), `loop_count` (int, default 3 — **default to 1 instead when
>    script_type=targeted_qa_fix and the task is brief-mode**, since brief-mode runs can't self-detect
>    completion and will just repeat the same brief), `priority` (int, default 100). On submit: `INSERT
>    INTO task_queue (...) VALUES (...)`.
> 2. **Queue list** — table view of all rows, default sorted `status, priority DESC, submitted_at ASC`.
>    Filterable by status. Poll-refresh every ~10s (no realtime subscription needed). Show `iterations_run
>    / loop_count` as progress. Clicking a row expands `last_result` (JSON) for post-mortem.
> 3. **Reprioritize / cancel** — inline-editable `priority` number and a "Cancel" button, **both only
>    enabled when `status = 'queued'`**. Reprioritize: `UPDATE task_queue SET priority = $new, updated_at =
>    now() WHERE id = $id AND status = 'queued'`. Cancel: `UPDATE task_queue SET status = 'cancelled',
>    updated_at = now() WHERE id = $id AND status = 'queued'`. Both guarded by the status check so a task
>    already claimed/running can't be edited out from under an active worker — if the guarded `UPDATE`
>    affects 0 rows, show "task already started, can no longer be changed" rather than a silent no-op.
>
> Do not add any polling/dequeue logic to Windmill itself — workers (a separate bash process,
> `script/queue_worker.sh`, running elsewhere) own claiming and running tasks. Windmill only reads and does
> the two guarded `UPDATE`s above.

---

## 8. Testing

`script/test_queue_worker.sh`, matching `script/test_targeted_qa_fix.sh`'s style: sources the script,
tests pure helper functions with no network/Postgres/claude calls. Covers: `QUEUE_SIGNAL:` line parsing
from mixed stdout, the claim-race duplicate-key detection (string match on a canned error, not a live DB),
and the per-iteration status decision table in Section 4.

`headless_taxonomy.sh` / `targeted_qa_fix.sh` changes are additive (a new pre-check branch, an appended
output line) and don't touch the pure-function logic already covered by their existing test files —
existing tests should keep passing unmodified.
