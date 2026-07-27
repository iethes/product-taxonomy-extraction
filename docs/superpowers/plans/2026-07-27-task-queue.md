# Priority Task Queue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Postgres-backed priority queue that lets an operator submit, reprioritize, and cancel `headless_taxonomy.sh` / `targeted_qa_fix.sh` runs, with one or more `queue_worker.sh` processes pulling the highest-priority task and looping the underlying script up to `loop_count` times.

**Architecture:** A single Postgres table (`task_queue`) is the source of truth. Workers claim a task with `UPDATE ... FOR UPDATE SKIP LOCKED RETURNING ...`; a partial unique index on `(table_name) WHERE status='running'` is the actual mechanism preventing two workers from touching the same category table concurrently. Both underlying scripts gain a `QUEUE_SIGNAL:` output line so the worker can decide, after each loop iteration, whether to keep going (more work likely remains) or stop early (the script's own live pre-check found nothing left to do).

**Tech Stack:** Bash (matches the existing `script/*.sh` convention — no new language), Postgres via `psql`, `jq` for JSON parsing (already a dependency of `targeted_qa_fix.sh`).

## Global Constraints

- Storage is Postgres only — not Redis, RabbitMQ, or BigQuery — for `task_queue` (see `docs/superpowers/specs/2026-07-27-task-queue-design.md` §1).
- `QUEUE_DATABASE_URL` (a standard libpq connection string) is required by `queue_worker.sh` and `queue_ctl.sh`, loaded via `script/load_env.sh` sourcing `.env` if present.
- `task_queue.priority`: higher integer = higher priority; default `100`.
- `task_queue.status` enum: exactly `queued|running|done|failed|blocked|cancelled`.
- The partial unique index `one_running_task_per_table` on `task_queue(table_name) WHERE status='running'` is REQUIRED, not optional — it is the actual mechanism enforcing one-worker-per-table (`SKIP LOCKED` alone does not).
- `LEASE_TIMEOUT_HOURS` default `4` — sized to cover one loop iteration, refreshed via a heartbeat at every iteration boundary. Never size it to cover a whole `loop_count` task.
- `POLL_INTERVAL_SECONDS` default `15`.
- `loop_count` defaults to `3`; operators must set it to `1` for `targeted_qa_fix.sh` brief-mode tasks (brief mode cannot self-detect completion — documented, not code-enforced).
- `QUEUE_SIGNAL:` line values are exactly `NOTHING_TO_DO`, `DONE`, `BLOCKED`, `FAILED`. Early-stop is driven only by a script's own live worklist-emptiness pre-check (`gap_count` / worklist `COUNT(*)`), never by `rows_created`.
- New tool dependency: `psql` (PostgreSQL client) must be installed and on `$PATH`. `bq` and `jq` are already required by the existing scripts.
- No ORM, no new language/runtime — plain bash + raw SQL, matching `script/headless_taxonomy.sh` / `script/targeted_qa_fix.sh`.

---

### Task 1: `.env` plumbing

**Files:**
- Create: `.env.example`
- Create: `script/load_env.sh`
- Create: `script/test_load_env.sh`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `script/load_env.sh`, sourced (not executed) by `script/queue_worker.sh` and `script/queue_ctl.sh` in Tasks 4 and 5 — `source "$(dirname "$0")/load_env.sh"`. Exports every variable assigned while reading `.env` (if present) into the calling process's environment. No-op if `.env` doesn't exist.

- [ ] **Step 1: Write the failing test**

Create `script/test_load_env.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Self-test for script/load_env.sh.
# Run: bash script/test_load_env.sh

cd "$(dirname "$0")/.."
fail() { echo "FAIL: $1" >&2; exit 1; }

# --- loads and exports vars from .env ---
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/script"
cp script/load_env.sh "$tmpdir/script/"
cat > "$tmpdir/.env" <<'EOF'
QUEUE_DATABASE_URL=postgres://user:pass@localhost:5432/testdb
POLL_INTERVAL_SECONDS=30
EOF
output=$(cd "$tmpdir" && bash -c 'source script/load_env.sh; echo "$QUEUE_DATABASE_URL|$POLL_INTERVAL_SECONDS"')
[[ "$output" == "postgres://user:pass@localhost:5432/testdb|30" ]] || fail "load_env.sh should export vars from .env: got '$output'"
rm -rf "$tmpdir"
echo "PASS: load_env.sh exports vars from .env"

# --- no .env present is a silent no-op ---
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/script"
cp script/load_env.sh "$tmpdir/script/"
output=$(cd "$tmpdir" && bash -c 'source script/load_env.sh; echo "${QUEUE_DATABASE_URL:-unset}"')
[[ "$output" == "unset" ]] || fail "load_env.sh with no .env present should be a silent no-op: got '$output'"
rm -rf "$tmpdir"
echo "PASS: load_env.sh no-op when .env absent"

echo "ALL TESTS PASSED"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash script/test_load_env.sh`
Expected: FAIL — `cp: cannot stat 'script/load_env.sh': No such file or directory` (the file doesn't exist yet).

- [ ] **Step 3: Implement `script/load_env.sh`, `.env.example`, and the `.gitignore` entry**

Create `script/load_env.sh`:

```bash
#!/usr/bin/env bash
# Sourced (not executed) by script/queue_worker.sh and script/queue_ctl.sh to export .env into the
# process environment. Also usable standalone: `source script/load_env.sh` in an interactive shell.
# No-op if .env doesn't exist -- existing environment variables (CI, shell profile) are left as-is.
set -a
[[ -f "$(dirname "${BASH_SOURCE[0]}")/../.env" ]] && source "$(dirname "${BASH_SOURCE[0]}")/../.env"
set +a
```

Create `.env.example`:

```bash
# Copy to .env and fill in real values. .env itself is gitignored -- never commit real credentials.
QUEUE_DATABASE_URL=postgres://user:password@localhost:5432/taxonomy_queue
POLL_INTERVAL_SECONDS=15
LEASE_TIMEOUT_HOURS=4
```

Modify `.gitignore` — add this line (append to the existing file, which currently only contains `.venv-embedding/`):

```
.env
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash script/test_load_env.sh`
Expected: PASS
```
PASS: load_env.sh exports vars from .env
PASS: load_env.sh no-op when .env absent
ALL TESTS PASSED
```

- [ ] **Step 5: Commit**

```bash
chmod +x script/load_env.sh
git add script/load_env.sh script/test_load_env.sh .env.example .gitignore
git commit -m "Add .env loading for the task queue (load_env.sh, .env.example)"
```

---

### Task 2: Postgres schema

**Files:**
- Create: `sql/postgres/001_task_queue.sql`

**Interfaces:**
- Produces: the `task_queue` table and `one_running_task_per_table` unique index, consumed by every later task's SQL.
- Consumes: a reachable Postgres instance via `QUEUE_DATABASE_URL` (loaded via Task 1's `script/load_env.sh`).

This task has no bash logic to unit-test — its "test" is applying the DDL against a real Postgres and proving the load-bearing index actually enforces exclusion.

- [ ] **Step 1: Ensure a reachable Postgres for local development**

If you don't already have one:

```bash
docker run --rm -d --name taxonomy_queue_pg -p 5432:5432 -e POSTGRES_PASSWORD=postgres postgres:16
```

Add to your `.env` (copy from `.env.example` first if you haven't):

```
QUEUE_DATABASE_URL=postgres://postgres:postgres@localhost:5432/postgres
```

- [ ] **Step 2: Write `sql/postgres/001_task_queue.sql`**

```sql
-- sql/postgres/001_task_queue.sql
-- Applied once by hand: psql "$QUEUE_DATABASE_URL" -f sql/postgres/001_task_queue.sql
-- See docs/superpowers/specs/2026-07-27-task-queue-design.md for the full design.

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

-- REQUIRED, not optional -- this is what actually enforces "one table, one worker at a time."
-- SKIP LOCKED alone does not enforce this: it only skips rows a concurrent transaction has locked,
-- not other queued rows for the same table_name. This index is the real backstop.
CREATE UNIQUE INDEX IF NOT EXISTS one_running_task_per_table
  ON task_queue (table_name) WHERE status = 'running';
```

- [ ] **Step 3: Apply it**

```bash
source script/load_env.sh
psql "$QUEUE_DATABASE_URL" -f sql/postgres/001_task_queue.sql
```

Expected output:
```
CREATE TABLE
CREATE INDEX
```

- [ ] **Step 4: Verify the table and index exist**

```bash
psql "$QUEUE_DATABASE_URL" -c "\d task_queue"
```

Expected: a column listing showing all 13 columns above, and under `Indexes:` a line similar to:
```
"one_running_task_per_table" UNIQUE, btree (table_name) WHERE status = 'running'::text
```

- [ ] **Step 5: Prove the index is actually load-bearing**

```bash
psql "$QUEUE_DATABASE_URL" -c "
  INSERT INTO task_queue (table_name, script_type) VALUES
    ('test_table','headless_taxonomy'), ('test_table','headless_taxonomy') RETURNING id;"

psql "$QUEUE_DATABASE_URL" -c "
  UPDATE task_queue SET status='running'
  WHERE table_name='test_table' AND id = (SELECT MIN(id) FROM task_queue WHERE table_name='test_table');"

psql "$QUEUE_DATABASE_URL" -c "
  UPDATE task_queue SET status='running'
  WHERE table_name='test_table' AND id = (SELECT MAX(id) FROM task_queue WHERE table_name='test_table');"
```

Expected: the first `UPDATE` succeeds (`UPDATE 1`). The second fails:
```
ERROR:  duplicate key value violates unique constraint "one_running_task_per_table"
```

This is the exact error `script/queue_worker.sh` (Task 3/4) must treat as an expected race outcome, not a crash.

- [ ] **Step 6: Clean up test rows**

```bash
psql "$QUEUE_DATABASE_URL" -c "DELETE FROM task_queue WHERE table_name='test_table';"
```

- [ ] **Step 7: Commit**

```bash
git add sql/postgres/001_task_queue.sql
git commit -m "Add Postgres schema for the task queue"
```

---

### Task 3: `queue_worker.sh` — pure signal/decision helpers

**Files:**
- Create: `script/queue_worker.sh` (pure functions only in this task — no `main()` yet, added in Task 4)
- Create: `script/test_queue_worker.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `parse_queue_signal(output) -> string`, `is_duplicate_key_error(text) -> "true"|"false"`, `queue_signal_to_status(signal) -> "done"|"blocked"|"failed"`, `should_stop_looping(signal) -> "true"|"false"` — consumed by Task 4's `run_task()`/`claim_next_task()`.

- [ ] **Step 1: Write the failing test**

Create `script/test_queue_worker.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Self-test for script/queue_worker.sh's pure helper functions.
# No network, Postgres, or claude calls -- mirrors script/test_targeted_qa_fix.sh's convention.
# Run: bash script/test_queue_worker.sh

cd "$(dirname "$0")/.."
source script/queue_worker.sh

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- parse_queue_signal ---
mixed_output='some prose
QUEUE_SIGNAL: DONE
trailing prose'
[[ "$(parse_queue_signal "$mixed_output")" == "DONE" ]] || fail "should extract DONE from mixed output"

no_signal_output='no signal line here at all'
[[ "$(parse_queue_signal "$no_signal_output")" == "" ]] || fail "should return empty string when no QUEUE_SIGNAL line present"

two_signals_output='QUEUE_SIGNAL: DONE
some other line
QUEUE_SIGNAL: BLOCKED'
[[ "$(parse_queue_signal "$two_signals_output")" == "BLOCKED" ]] || fail "should take the LAST QUEUE_SIGNAL line, not the first"
echo "PASS: parse_queue_signal"

# --- is_duplicate_key_error ---
dup_error='ERROR:  duplicate key value violates unique constraint "one_running_task_per_table"'
[[ "$(is_duplicate_key_error "$dup_error")" == "true" ]] || fail "should detect a duplicate key constraint violation"

other_error='ERROR:  relation "task_queue" does not exist'
[[ "$(is_duplicate_key_error "$other_error")" == "false" ]] || fail "should not flag an unrelated SQL error as a duplicate key race"
echo "PASS: is_duplicate_key_error"

# --- queue_signal_to_status ---
[[ "$(queue_signal_to_status "NOTHING_TO_DO")" == "done" ]] || fail "NOTHING_TO_DO -> done"
[[ "$(queue_signal_to_status "DONE")" == "done" ]] || fail "DONE -> done"
[[ "$(queue_signal_to_status "BLOCKED")" == "blocked" ]] || fail "BLOCKED -> blocked"
[[ "$(queue_signal_to_status "FAILED")" == "failed" ]] || fail "FAILED -> failed"
[[ "$(queue_signal_to_status "")" == "failed" ]] || fail "missing/unparseable signal -> failed, not silently ignored"
[[ "$(queue_signal_to_status "GARBAGE")" == "failed" ]] || fail "unrecognized signal -> failed"
echo "PASS: queue_signal_to_status"

# --- should_stop_looping ---
[[ "$(should_stop_looping "DONE")" == "false" ]] || fail "DONE should NOT stop the loop -- more iterations may still find work"
[[ "$(should_stop_looping "NOTHING_TO_DO")" == "true" ]] || fail "NOTHING_TO_DO should stop the loop early"
[[ "$(should_stop_looping "BLOCKED")" == "true" ]] || fail "BLOCKED should stop the loop"
[[ "$(should_stop_looping "FAILED")" == "true" ]] || fail "FAILED should stop the loop"
[[ "$(should_stop_looping "")" == "true" ]] || fail "missing signal should stop the loop, not spin through remaining iterations"
echo "PASS: should_stop_looping"

echo "ALL TESTS PASSED"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash script/test_queue_worker.sh`
Expected: FAIL — `script/queue_worker.sh: No such file or directory` (nothing to source yet).

- [ ] **Step 3: Write minimal implementation**

Create `script/queue_worker.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Pulls the highest-priority queued task from Postgres, runs script/headless_taxonomy.sh or
# script/targeted_qa_fix.sh up to loop_count times, and persists the result.
# See docs/superpowers/specs/2026-07-27-task-queue-design.md for the full design.
#
# Usage: script/queue_worker.sh
# Requires QUEUE_DATABASE_URL (see script/load_env.sh / .env.example).

parse_queue_signal() {
  local output="$1"
  grep -o 'QUEUE_SIGNAL: [A-Z_]*' <<< "$output" | tail -1 | awk '{print $2}'
}

is_duplicate_key_error() {
  [[ "$1" == *"duplicate key value violates unique constraint"* ]] && echo "true" || echo "false"
}

queue_signal_to_status() {
  case "$1" in
    NOTHING_TO_DO|DONE) echo "done" ;;
    BLOCKED) echo "blocked" ;;
    *) echo "failed" ;;   # FAILED, missing, or unparseable -- never silently treated as success
  esac
}

should_stop_looping() {
  case "$1" in
    DONE) echo "false" ;;
    *) echo "true" ;;    # NOTHING_TO_DO, BLOCKED, FAILED, or unrecognized all stop the loop
  esac
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash script/test_queue_worker.sh`
Expected: PASS
```
PASS: parse_queue_signal
PASS: is_duplicate_key_error
PASS: queue_signal_to_status
PASS: should_stop_looping
ALL TESTS PASSED
```

- [ ] **Step 5: Commit**

```bash
git add script/queue_worker.sh script/test_queue_worker.sh
git commit -m "Add queue_worker.sh signal-parsing and status-decision helpers"
```

---

### Task 4: `queue_worker.sh` — claim/reclaim/heartbeat/orchestration

**Files:**
- Modify: `script/queue_worker.sh` (append orchestration functions + `main()`)

**Interfaces:**
- Consumes: `parse_queue_signal`, `is_duplicate_key_error`, `queue_signal_to_status`, `should_stop_looping` (Task 3); `script/load_env.sh` (Task 1); the `task_queue` table (Task 2).
- Produces: `main()`, run when the script is executed directly (`./script/queue_worker.sh`). Reads `HEADLESS_TAXONOMY_SCRIPT` / `TARGETED_QA_FIX_SCRIPT` env vars to override which script `run_underlying_script()` invokes (defaults to the real scripts; overridden by this task's smoke test to avoid needing live BQ/claude credentials).

No new pure functions here, so no `test_queue_worker.sh` additions — this task is verified with a manual smoke test against the real Postgres from Task 2, using a stub script standing in for `headless_taxonomy.sh`.

- [ ] **Step 1: Append the orchestration functions to `script/queue_worker.sh`**

Add to the end of `script/queue_worker.sh` (after the four functions from Task 3):

```bash

reclaim_stale_leases() {
  psql "$QUEUE_DATABASE_URL" -t -A -c "
    UPDATE task_queue SET status='queued', claimed_by=NULL, claimed_at=NULL
    WHERE status='running' AND claimed_at < now() - interval '${LEASE_TIMEOUT_HOURS:-4} hours';" >/dev/null
}

# REQUIRED, not optional -- see sql/postgres/001_task_queue.sql: SKIP LOCKED alone does not give
# per-table exclusion (it only skips locked rows, not other queued rows for the same table_name).
# The one_running_task_per_table unique index is what actually blocks a second concurrent claim, by
# raising a duplicate-key error on commit -- which this function must treat as "lost the race, no
# task claimed this round," not a crash.
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
    [[ "$(is_duplicate_key_error "$out")" == "true" ]] && { echo ""; return 0; }
    echo "$out" >&2
    return 1
  fi
  echo "$out"
}

heartbeat() {
  local id="$1"
  psql "$QUEUE_DATABASE_URL" -t -A -c \
    "UPDATE task_queue SET claimed_at=now() WHERE id=${id} AND status='running';" >/dev/null
}

run_underlying_script() {
  local script_type="$1" table="$2" month="$3" max_turns="$4" block_size="$5"
  case "$script_type" in
    headless_taxonomy)
      "${HEADLESS_TAXONOMY_SCRIPT:-./script/headless_taxonomy.sh}" "$table" "$month" "$max_turns"
      ;;
    targeted_qa_fix)
      "${TARGETED_QA_FIX_SCRIPT:-./script/targeted_qa_fix.sh}" "$table" "$block_size" "$max_turns"
      ;;
    *)
      echo "Unknown script_type: $script_type" >&2
      echo "QUEUE_SIGNAL: FAILED"
      ;;
  esac
}

persist_final_status() {
  local id="$1" status="$2" iterations_run="$3" output="$4"
  local last_result_json
  last_result_json=$(printf '%s' "$output" | jq -Rs '{raw_output: .}')
  psql "$QUEUE_DATABASE_URL" \
    -v id="$id" -v status="$status" -v iterations_run="$iterations_run" -v last_result="$last_result_json" \
    -t -A -c "
      UPDATE task_queue
      SET status = :'status', iterations_run = :iterations_run, updated_at = now(),
          last_result = :'last_result'::jsonb
      WHERE id = :id;" >/dev/null
}

run_task() {
  local id="$1" table="$2" script_type="$3" month="$4" max_turns="$5" block_size="$6" loop_count="$7"
  local iterations_run=0 final_status="failed" last_output="" signal=""
  local i
  for ((i = 1; i <= loop_count; i++)); do
    heartbeat "$id"
    last_output=$(run_underlying_script "$script_type" "$table" "$month" "$max_turns" "$block_size" 2>&1) || true
    echo "$last_output"
    iterations_run=$((iterations_run + 1))
    signal=$(parse_queue_signal "$last_output")
    final_status=$(queue_signal_to_status "$signal")
    [[ "$(should_stop_looping "$signal")" == "true" ]] && break
  done
  persist_final_status "$id" "$final_status" "$iterations_run" "$last_output"
}

main() {
  source "$(dirname "$0")/load_env.sh"
  : "${QUEUE_DATABASE_URL:?QUEUE_DATABASE_URL must be set (via .env or the environment)}"
  WORKER_ID="$(hostname)-$$"
  echo "Worker ${WORKER_ID} starting, polling every ${POLL_INTERVAL_SECONDS:-15}s"
  while true; do
    reclaim_stale_leases
    local row
    row=$(claim_next_task) || { sleep "${POLL_INTERVAL_SECONDS:-15}"; continue; }
    if [[ -z "$row" ]]; then
      sleep "${POLL_INTERVAL_SECONDS:-15}"
      continue
    fi
    local id table_name script_type month max_turns block_size loop_count
    IFS='|' read -r id table_name script_type month max_turns block_size loop_count <<< "$row"
    echo "Claimed task ${id}: ${table_name} (${script_type})"
    run_task "$id" "$table_name" "$script_type" "$month" "$max_turns" "$block_size" "$loop_count"
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
```

- [ ] **Step 2: Confirm the existing pure-function tests still pass (no regression)**

Run: `bash script/test_queue_worker.sh`
Expected: PASS (unchanged) — sourcing the file still doesn't execute `main()`, since `BASH_SOURCE[0] != $0` when sourced.

- [ ] **Step 3: Manual smoke test — early-stop loop behavior against a real Postgres**

Requires `QUEUE_DATABASE_URL` set (Task 2's Postgres, with the schema applied) and `psql`/`jq` installed.

```bash
source script/load_env.sh

mkdir -p /tmp/queue_worker_smoke
rm -f /tmp/queue_worker_smoke/counter
cat > /tmp/queue_worker_smoke/fake_headless.sh <<'EOF'
#!/usr/bin/env bash
counter_file="/tmp/queue_worker_smoke/counter"
count=$(cat "$counter_file" 2>/dev/null || echo 0)
count=$((count + 1))
echo "$count" > "$counter_file"
if [[ "$count" -ge 2 ]]; then
  echo "QUEUE_SIGNAL: NOTHING_TO_DO"
else
  echo "QUEUE_SIGNAL: DONE"
fi
EOF
chmod +x /tmp/queue_worker_smoke/fake_headless.sh

psql "$QUEUE_DATABASE_URL" -c "
  INSERT INTO task_queue (table_name, script_type, loop_count, priority)
  VALUES ('smoke_test_table', 'headless_taxonomy', 3, 500);"

HEADLESS_TAXONOMY_SCRIPT=/tmp/queue_worker_smoke/fake_headless.sh bash -c '
  source script/queue_worker.sh
  source script/load_env.sh
  WORKER_ID="smoke-test"
  row=$(claim_next_task)
  IFS="|" read -r id table_name script_type month max_turns block_size loop_count <<< "$row"
  run_task "$id" "$table_name" "$script_type" "$month" "$max_turns" "$block_size" "$loop_count"
'

psql "$QUEUE_DATABASE_URL" -c "SELECT id, table_name, status, iterations_run FROM task_queue WHERE table_name='smoke_test_table';"
```

Expected final query output: `status = done`, `iterations_run = 2` — the loop ran a second iteration because the first returned `DONE` (keep going), then stopped early on the second's `NOTHING_TO_DO`, never using the third of `loop_count=3`.

- [ ] **Step 4: Clean up**

```bash
psql "$QUEUE_DATABASE_URL" -c "DELETE FROM task_queue WHERE table_name='smoke_test_table';"
rm -rf /tmp/queue_worker_smoke
```

- [ ] **Step 5: Commit**

```bash
chmod +x script/queue_worker.sh
git add script/queue_worker.sh
git commit -m "Add queue_worker.sh claim/reclaim/heartbeat orchestration and main loop"
```

---

### Task 5: `queue_ctl.sh` — submit/list/priority/cancel CLI

**Files:**
- Create: `script/queue_ctl.sh`
- Create: `script/test_queue_ctl.sh`

**Interfaces:**
- Consumes: `script/load_env.sh` (Task 1); the `task_queue` table (Task 2).
- Produces: `sql_quote(s)`, `build_submit_sql(...)`, `build_list_sql(status_filter)`, `build_priority_sql(task_id, new_priority)`, `build_cancel_sql(task_id)` — pure SQL-building functions, unit-tested directly; not consumed by any other file.

- [ ] **Step 1: Write the failing test**

Create `script/test_queue_ctl.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Self-test for script/queue_ctl.sh's pure SQL-building functions.
# No network or Postgres calls -- mirrors script/test_targeted_qa_fix.sh's convention.
# Run: bash script/test_queue_ctl.sh

cd "$(dirname "$0")/.."
source script/queue_ctl.sh

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- sql_quote ---
[[ "$(sql_quote "shopee_th_shampoo")" == "'shopee_th_shampoo'" ]] || fail "plain string should just be quoted"
[[ "$(sql_quote "o'brien")" == "'o''brien'" ]] || fail "embedded single quote must be doubled, not left to break the statement"
echo "PASS: sql_quote"

# --- build_submit_sql ---
sql=$(build_submit_sql "shopee_th_shampoo" "headless_taxonomy" "" "" "" "3" "100")
grep -qF "'shopee_th_shampoo'" <<< "$sql" || fail "should quote the table name"
grep -qF "'headless_taxonomy'" <<< "$sql" || fail "should quote the script_type"
grep -qF "NULL, NULL, NULL" <<< "$sql" || fail "omitted month/max_turns/block_size should become SQL NULL"
grep -qF "3, 100" <<< "$sql" || fail "loop_count and priority should be raw numeric literals"

sql=$(build_submit_sql "shopee_th_shampoo" "targeted_qa_fix" "2026-06" "500" "300" "1" "999")
grep -qF "'2026-06'" <<< "$sql" || fail "provided month should be quoted, not NULL"
grep -qF "500, 300" <<< "$sql" || fail "provided max_turns/block_size should be raw numeric literals, not quoted"
echo "PASS: build_submit_sql"

# --- build_list_sql ---
sql=$(build_list_sql "")
[[ "$sql" != *"WHERE"* ]] || fail "no status filter should mean no WHERE clause"

sql=$(build_list_sql "queued")
grep -qF "WHERE status = 'queued'" <<< "$sql" || fail "status filter should produce a quoted WHERE clause"
echo "PASS: build_list_sql"

# --- build_priority_sql ---
sql=$(build_priority_sql "42" "500")
grep -qF "SET priority = 500" <<< "$sql" || fail "should set the new priority"
grep -qF "WHERE id = 42 AND status = 'queued'" <<< "$sql" || fail "must guard the UPDATE to status='queued' only"
echo "PASS: build_priority_sql"

# --- build_cancel_sql ---
sql=$(build_cancel_sql "42")
grep -qF "SET status = 'cancelled'" <<< "$sql" || fail "should set status to cancelled"
grep -qF "WHERE id = 42 AND status = 'queued'" <<< "$sql" || fail "must guard the UPDATE to status='queued' only"
echo "PASS: build_cancel_sql"

echo "ALL TESTS PASSED"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash script/test_queue_ctl.sh`
Expected: FAIL — `script/queue_ctl.sh: No such file or directory`.

- [ ] **Step 3: Write the implementation**

Create `script/queue_ctl.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   script/queue_ctl.sh submit <table> <headless_taxonomy|targeted_qa_fix> \
#       [--month YYYY-MM] [--max-turns N] [--block-size N] [--loop-count N] [--priority N]
#   script/queue_ctl.sh list [--status queued|running|done|failed|blocked|cancelled]
#   script/queue_ctl.sh priority <task_id> <new_priority>
#   script/queue_ctl.sh cancel <task_id>
#
# NOTE on loop_count: for targeted_qa_fix tasks in brief mode (a hand-written '## Targeted QA Fix
# Brief' section in the category doc, not auto-discovery), the underlying script has no way to
# self-detect "nothing left to do." Set --loop-count 1 for those unless you know the brief needs
# multiple passes. See docs/superpowers/specs/2026-07-27-task-queue-design.md section 4.
#
# Requires QUEUE_DATABASE_URL (see script/load_env.sh / .env.example).

sql_quote() {
  local s="$1"
  echo "'${s//\'/\'\'}'"
}

build_submit_sql() {
  local table="$1" script_type="$2" month="$3" max_turns="$4" block_size="$5" loop_count="$6" priority="$7"
  local month_sql max_turns_sql block_size_sql
  [[ -z "$month" ]] && month_sql="NULL" || month_sql=$(sql_quote "$month")
  [[ -z "$max_turns" ]] && max_turns_sql="NULL" || max_turns_sql="$max_turns"
  [[ -z "$block_size" ]] && block_size_sql="NULL" || block_size_sql="$block_size"
  cat <<SQL
INSERT INTO task_queue (table_name, script_type, month, max_turns, block_size, loop_count, priority)
VALUES ($(sql_quote "$table"), $(sql_quote "$script_type"), ${month_sql}, ${max_turns_sql}, ${block_size_sql}, ${loop_count}, ${priority})
RETURNING id;
SQL
}

build_list_sql() {
  local status_filter="$1"
  if [[ -z "$status_filter" ]]; then
    echo "SELECT id, table_name, script_type, status, priority, iterations_run, loop_count, submitted_at FROM task_queue ORDER BY status, priority DESC, submitted_at ASC;"
  else
    echo "SELECT id, table_name, script_type, status, priority, iterations_run, loop_count, submitted_at FROM task_queue WHERE status = $(sql_quote "$status_filter") ORDER BY priority DESC, submitted_at ASC;"
  fi
}

build_priority_sql() {
  local task_id="$1" new_priority="$2"
  echo "UPDATE task_queue SET priority = ${new_priority}, updated_at = now() WHERE id = ${task_id} AND status = 'queued' RETURNING id;"
}

build_cancel_sql() {
  local task_id="$1"
  echo "UPDATE task_queue SET status = 'cancelled', updated_at = now() WHERE id = ${task_id} AND status = 'queued' RETURNING id;"
}

cmd_submit() {
  local table="$1" script_type="$2"
  shift 2
  local month="" max_turns="" block_size="" loop_count=3 priority=100
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --month) month="$2"; shift 2 ;;
      --max-turns) max_turns="$2"; shift 2 ;;
      --block-size) block_size="$2"; shift 2 ;;
      --loop-count) loop_count="$2"; shift 2 ;;
      --priority) priority="$2"; shift 2 ;;
      *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
  done
  psql "$QUEUE_DATABASE_URL" -c "$(build_submit_sql "$table" "$script_type" "$month" "$max_turns" "$block_size" "$loop_count" "$priority")"
}

cmd_list() {
  local status_filter=""
  [[ "${1:-}" == "--status" ]] && status_filter="${2:-}"
  psql "$QUEUE_DATABASE_URL" -c "$(build_list_sql "$status_filter")"
}

cmd_priority() {
  local task_id="$1" new_priority="$2"
  local result
  result=$(psql "$QUEUE_DATABASE_URL" -t -A -c "$(build_priority_sql "$task_id" "$new_priority")")
  if [[ -z "$result" ]]; then
    echo "Task ${task_id} already started (or doesn't exist) -- priority can no longer be changed." >&2
    exit 1
  fi
  echo "Task ${task_id} priority set to ${new_priority}."
}

cmd_cancel() {
  local task_id="$1"
  local result
  result=$(psql "$QUEUE_DATABASE_URL" -t -A -c "$(build_cancel_sql "$task_id")")
  if [[ -z "$result" ]]; then
    echo "Task ${task_id} already started (or doesn't exist) -- can no longer be cancelled." >&2
    exit 1
  fi
  echo "Task ${task_id} cancelled."
}

main() {
  source "$(dirname "$0")/load_env.sh"
  : "${QUEUE_DATABASE_URL:?QUEUE_DATABASE_URL must be set (via .env or the environment)}"
  local cmd="${1:-}"
  case "$cmd" in
    submit) shift; cmd_submit "$@" ;;
    list) shift; cmd_list "$@" ;;
    priority) shift; cmd_priority "$@" ;;
    cancel) shift; cmd_cancel "$@" ;;
    *)
      echo "Usage: $0 submit|list|priority|cancel ..." >&2
      exit 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash script/test_queue_ctl.sh`
Expected: PASS
```
PASS: sql_quote
PASS: build_submit_sql
PASS: build_list_sql
PASS: build_priority_sql
PASS: build_cancel_sql
ALL TESTS PASSED
```

- [ ] **Step 5: Manual smoke test — full submit/list/priority/cancel roundtrip against a real Postgres**

```bash
source script/load_env.sh
chmod +x script/queue_ctl.sh

script/queue_ctl.sh submit shopee_th_smoke_ctl headless_taxonomy --priority 250
script/queue_ctl.sh list --status queued
# Note the id printed by `submit`'s RETURNING id, then:
script/queue_ctl.sh priority <id> 999
script/queue_ctl.sh list --status queued   # priority column should now read 999
script/queue_ctl.sh cancel <id>
script/queue_ctl.sh list --status cancelled   # the row should now appear here

# Cleanup
psql "$QUEUE_DATABASE_URL" -c "DELETE FROM task_queue WHERE table_name='shopee_th_smoke_ctl';"
```

- [ ] **Step 6: Commit**

```bash
git add script/queue_ctl.sh script/test_queue_ctl.sh
git commit -m "Add queue_ctl.sh submit/list/priority/cancel CLI"
```

---

### Task 6: `headless_taxonomy.sh` — `QUEUE_SIGNAL` wiring

**Files:**
- Modify: `script/headless_taxonomy.sh`
- Modify: `script/test_headless_taxonomy.sh`

**Interfaces:**
- Produces: `extract_json_object(text)`, `decide_queue_signal(claude_output) -> "DONE"|"BLOCKED"|"FAILED"`; the script now also emits a `QUEUE_SIGNAL: NOTHING_TO_DO`/`DONE`/`BLOCKED`/`FAILED` line at every exit path, consumed by `queue_worker.sh`'s `parse_queue_signal` (Task 3/4).

- [ ] **Step 1: Write the failing tests**

Open `script/test_headless_taxonomy.sh` and insert the following block immediately before the final `echo "ALL TESTS PASSED (part 1)"` line (currently the last line of the file):

```bash
# --- decide_queue_signal ---
complete_output='{"result": "{\"status\": \"complete\", \"rows_created\": 5}"}'
[[ "$(decide_queue_signal "$complete_output")" == "DONE" ]] || fail "status=complete -> DONE"

partial_zero_rows_output='{"result": "{\"status\": \"partial\", \"rows_created\": 0}"}'
[[ "$(decide_queue_signal "$partial_zero_rows_output")" == "DONE" ]] || fail "status=partial with rows_created=0 must still be DONE -- only the live gap_count pre-check may claim NOTHING_TO_DO, never rows_created"

blocked_output='{"result": "{\"status\": \"blocked\", \"blockers\": [\"x\"]}"}'
[[ "$(decide_queue_signal "$blocked_output")" == "BLOCKED" ]] || fail "status=blocked -> BLOCKED"

failed_output='{"result": "{\"status\": \"failed\"}"}'
[[ "$(decide_queue_signal "$failed_output")" == "FAILED" ]] || fail "status=failed -> FAILED"

malformed_output='not json at all'
[[ "$(decide_queue_signal "$malformed_output")" == "FAILED" ]] || fail "unparseable output -> FAILED, not silently ignored"

prose_wrapped_output='{"result": "prose before {\"status\": \"complete\"} prose after"}'
[[ "$(decide_queue_signal "$prose_wrapped_output")" == "DONE" ]] || fail "prose-wrapped JSON should still be extracted via extract_json_object"
echo "PASS: decide_queue_signal"

# --- QUEUE_SIGNAL wiring in main() (static check -- gap_count/claude -p require live BQ, out of scope here) ---
script_src=$(cat script/headless_taxonomy.sh)
grep -qF 'echo "QUEUE_SIGNAL: NOTHING_TO_DO"' <<< "$script_src" || fail "main() must emit NOTHING_TO_DO when gap_count==0, before the early exit"
grep -qF 'echo "QUEUE_SIGNAL: $(decide_queue_signal "$claude_output")"' <<< "$script_src" || fail "main() must emit the post-run signal derived from decide_queue_signal"
echo "PASS: main() QUEUE_SIGNAL wiring"

echo "ALL TESTS PASSED (part 1)"
```

(Remove the now-duplicated final `echo "ALL TESTS PASSED (part 1)"` that was already at the end of the file, keeping only the one shown above.)

- [ ] **Step 2: Run test to verify it fails**

Run: `bash script/test_headless_taxonomy.sh`
Expected: FAIL — `decide_queue_signal: command not found` (function doesn't exist yet).

- [ ] **Step 3: Implement the changes in `script/headless_taxonomy.sh`**

Insert `extract_json_object` and `decide_queue_signal` between `build_topup_prompt()`'s closing brace and `main()`. Find:

```bash
}

main() {
```

(this is the boundary right after `build_topup_prompt()` ends) and replace with:

```bash
}

extract_json_object() {
  local text="$1"
  printf '%s' "$text" | grep -Pzo '(?s)\{.*\}' | tr -d '\0'
}

decide_queue_signal() {
  local claude_output="$1"
  local result_json
  result_json=$(echo "$claude_output" | jq -r '.result // empty' 2>/dev/null) || result_json=""
  if [[ -z "$result_json" ]]; then
    echo "FAILED"
    return
  fi
  if ! echo "$result_json" | jq -e . >/dev/null 2>&1; then
    local extracted
    extracted=$(extract_json_object "$result_json")
    if [[ -n "$extracted" ]] && echo "$extracted" | jq -e . >/dev/null 2>&1; then
      result_json="$extracted"
    fi
  fi
  local status
  status=$(echo "$result_json" | jq -r '.status // empty' 2>/dev/null) || status=""
  case "$status" in
    blocked) echo "BLOCKED" ;;
    complete|partial) echo "DONE" ;;
    *) echo "FAILED" ;;
  esac
}

main() {
```

Find the `gap_count == 0` branch:

```bash
  if [[ "$gap_count" == "0" ]]; then
    echo "No in-scope coverage gap for ${table}/${month} — nothing to do."
    exit 0
  fi
```

Replace with:

```bash
  if [[ "$gap_count" == "0" ]]; then
    echo "No in-scope coverage gap for ${table}/${month} — nothing to do."
    echo "QUEUE_SIGNAL: NOTHING_TO_DO"
    exit 0
  fi
```

Find the `claude -p` invocation and finish block:

```bash
  claude -p --output-format json --permission-mode bypassPermissions --max-turns "$max_turns" "$prompt"

  echo "============================"
  echo "TAXONOMY EXTRACTION FINISHED"
```

Replace with:

```bash
  local claude_output
  claude_output=$(claude -p --output-format json --permission-mode bypassPermissions --max-turns "$max_turns" "$prompt")
  echo "$claude_output"

  echo "============================"
  echo "TAXONOMY EXTRACTION FINISHED"
  echo "QUEUE_SIGNAL: $(decide_queue_signal "$claude_output")"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash script/test_headless_taxonomy.sh`
Expected: PASS — all prior test sections still pass, plus:
```
PASS: decide_queue_signal
PASS: main() QUEUE_SIGNAL wiring
ALL TESTS PASSED (part 1)
```

- [ ] **Step 5: Commit**

```bash
git add script/headless_taxonomy.sh script/test_headless_taxonomy.sh
git commit -m "Add QUEUE_SIGNAL output to headless_taxonomy.sh for queue mode"
```

---

### Task 7: `targeted_qa_fix.sh` — auto-discovery pre-check + `QUEUE_SIGNAL` wiring

**Files:**
- Modify: `script/targeted_qa_fix.sh`
- Modify: `script/test_targeted_qa_fix.sh`

**Interfaces:**
- Produces: `review_worklist_count_query(table) -> SQL string`; the script now emits a `QUEUE_SIGNAL:` line at every `main()` exit path, consumed by `queue_worker.sh`'s `parse_queue_signal` (Task 3/4).

- [ ] **Step 1: Write the failing tests**

Open `script/test_targeted_qa_fix.sh` and insert the following block immediately before the final `echo "ALL TESTS PASSED"` line (currently the last line of the file):

```bash
# --- review_worklist_count_query ---
q=$(review_worklist_count_query "shopee_th_suncare")
echo "$q" | grep -q "COUNT(DISTINCT pt.taxonomy_id)" || fail "review_worklist_count_query should count distinct taxonomy_id"
echo "$q" | grep -q "master_table = 'shopee_th_suncare'" || fail "review_worklist_count_query should scope by master_table"
echo "$q" | grep -q "review_confidence" || fail "review_worklist_count_query should mirror the auto-discovery worklist's _meta filter"
echo "PASS: review_worklist_count_query"

# --- QUEUE_SIGNAL wiring in main() (static check -- live bq/claude calls are out of scope here) ---
script_src=$(cat script/targeted_qa_fix.sh)
grep -qF 'review_worklist_count_query "$table"' <<< "$script_src" || fail "main() must run the pre-check worklist count before invoking claude -p in auto-discovery mode"
grep -qF 'echo "QUEUE_SIGNAL: NOTHING_TO_DO"' <<< "$script_src" || fail "main() must emit NOTHING_TO_DO when the auto-discovery worklist is empty"
grep -qF 'echo "QUEUE_SIGNAL: BLOCKED"' <<< "$script_src" || fail "main() must emit BLOCKED in the BLOCKED case branch"
grep -qF 'echo "QUEUE_SIGNAL: FAILED"' <<< "$script_src" || fail "main() must emit FAILED in both the MARK_FAILED case and the failed-gate branch"
signal_done_count=$(grep -cF 'echo "QUEUE_SIGNAL: DONE"' <<< "$script_src")
[[ "$signal_done_count" -eq 2 ]] || fail "main() must emit DONE in both the NOOP case (rows_created=0 is not nothing-to-do) and the successful GATE_AND_REFRESH case, got $signal_done_count occurrences"
echo "PASS: main() QUEUE_SIGNAL wiring"

echo "ALL TESTS PASSED"
```

(Remove the now-duplicated final `echo "ALL TESTS PASSED"` that was already at the end of the file, keeping only the one shown above.)

- [ ] **Step 2: Run test to verify it fails**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: FAIL — `review_worklist_count_query: command not found`.

- [ ] **Step 3: Implement the changes in `script/targeted_qa_fix.sh`**

Insert `review_worklist_count_query` between `append_qa_history_row()`'s closing brace and `build_prompt()`. Find:

```bash
  mv "$tmpfile" "$category_file"
}

build_prompt() {
```

Replace with:

```bash
  mv "$tmpfile" "$category_file"
}

review_worklist_count_query() {
  local table="$1"
  cat <<SQL
SELECT COUNT(DISTINCT pt.taxonomy_id)
FROM \`${PROJECT}.magpie_reference.product_taxonomy\` pt
JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
WHERE m.master_table = '${table}'
  AND (pt._meta IS NULL OR IFNULL(JSON_VALUE(pt._meta, '\$.review_confidence'), 'unreviewed') != 'confident')
SQL
}

build_prompt() {
```

Find the brief-mode/auto-discovery-mode branch in `main()`:

```bash
  local prompt
  if [[ "$(has_real_brief "$category_file")" == "true" ]]; then
    echo "TARGETED QA FIX STARTED (brief mode: ${category_file}, block_size=${block_size}, max_turns=${max_turns})"
    echo "==========================="
    prompt=$(build_prompt "$table" "$category_file" "$block_size" "$gate_report")
  else
    echo "TARGETED QA FIX STARTED (auto-discovery mode: ${category_file}, block_size=${block_size}, max_turns=${max_turns})"
    echo "==========================="
    prompt=$(build_auto_discovery_prompt "$table" "$category_file" "$block_size" "$gate_report")
  fi
```

Replace with:

```bash
  local prompt
  if [[ "$(has_real_brief "$category_file")" == "true" ]]; then
    echo "TARGETED QA FIX STARTED (brief mode: ${category_file}, block_size=${block_size}, max_turns=${max_turns})"
    echo "==========================="
    prompt=$(build_prompt "$table" "$category_file" "$block_size" "$gate_report")
  else
    local review_worklist_count
    review_worklist_count=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
      "$(review_worklist_count_query "$table")" | tail -1)
    if [[ "$review_worklist_count" == "0" ]]; then
      echo "No unreviewed/unconfident taxonomy entries for ${table} — nothing to do."
      echo "QUEUE_SIGNAL: NOTHING_TO_DO"
      exit 0
    fi
    echo "TARGETED QA FIX STARTED (auto-discovery mode: ${category_file}, block_size=${block_size}, max_turns=${max_turns}, review_worklist_count=${review_worklist_count})"
    echo "==========================="
    prompt=$(build_auto_discovery_prompt "$table" "$category_file" "$block_size" "$gate_report")
  fi
```

Find the final `case "$decision" in ... esac` block:

```bash
  case "$decision" in
    BLOCKED)
      echo "STATUS: blocked. Claimed block left ACTIVE (nothing written) — see blockers below."
      echo "$result_json" | jq -r '.blockers[]?' >&2
      exit 0
      ;;
    NOOP)
      echo "STATUS: complete/partial with rows_created=0 — nothing to gate or refresh. Block left ACTIVE."
      exit 0
      ;;
    MARK_FAILED)
      echo "STATUS: failed or malformed. Marking block FAILED_QA." >&2
      echo "$result_json" >&2
      mark_failed_qa "$table"
      exit 1
      ;;
    GATE_AND_REFRESH)
      echo "STATUS: rows written — running independent QA gates via script/qa_report.sh..."
      if ./script/qa_report.sh "$table"; then
        run_universe_refresh "$table"
        echo "============================"
        echo "TARGETED QA FIX FINISHED — universe refreshed"
      else
        echo "QA gates failed — marking block FAILED_QA, skipping universe refresh." >&2
        mark_failed_qa "$table"
        exit 1
      fi
      ;;
  esac
```

Replace with:

```bash
  case "$decision" in
    BLOCKED)
      echo "STATUS: blocked. Claimed block left ACTIVE (nothing written) — see blockers below."
      echo "$result_json" | jq -r '.blockers[]?' >&2
      echo "QUEUE_SIGNAL: BLOCKED"
      exit 0
      ;;
    NOOP)
      echo "STATUS: complete/partial with rows_created=0 — nothing to gate or refresh. Block left ACTIVE."
      echo "QUEUE_SIGNAL: DONE"
      exit 0
      ;;
    MARK_FAILED)
      echo "STATUS: failed or malformed. Marking block FAILED_QA." >&2
      echo "$result_json" >&2
      mark_failed_qa "$table"
      echo "QUEUE_SIGNAL: FAILED"
      exit 1
      ;;
    GATE_AND_REFRESH)
      echo "STATUS: rows written — running independent QA gates via script/qa_report.sh..."
      if ./script/qa_report.sh "$table"; then
        run_universe_refresh "$table"
        echo "============================"
        echo "TARGETED QA FIX FINISHED — universe refreshed"
        echo "QUEUE_SIGNAL: DONE"
      else
        echo "QA gates failed — marking block FAILED_QA, skipping universe refresh." >&2
        mark_failed_qa "$table"
        echo "QUEUE_SIGNAL: FAILED"
        exit 1
      fi
      ;;
  esac
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: PASS — all prior test sections still pass, plus:
```
PASS: review_worklist_count_query
PASS: main() QUEUE_SIGNAL wiring
ALL TESTS PASSED
```

- [ ] **Step 5: Commit**

```bash
git add script/targeted_qa_fix.sh script/test_targeted_qa_fix.sh
git commit -m "Add auto-discovery pre-check and QUEUE_SIGNAL output to targeted_qa_fix.sh for queue mode"
```

---

### Task 8: Documentation

**Files:**
- Modify: `docs/headless-runbook.md`

**Interfaces:**
- Consumes: nothing (documentation only).

- [ ] **Step 1: Append a "Queue Mode" section**

Append to the end of `docs/headless-runbook.md` (after the existing `## Error handling` section, which currently ends the file):

```markdown

## Queue Mode

An alternative to running `headless_taxonomy.sh` / `targeted_qa_fix.sh` by hand: submit them as
priority-queued tasks and let one or more `script/queue_worker.sh` processes pull and run them. See
`docs/superpowers/specs/2026-07-27-task-queue-design.md` for the full design.

### Setup

1. `psql` must be installed and on `$PATH`.
2. Copy `.env.example` to `.env` and set `QUEUE_DATABASE_URL` to a reachable Postgres instance.
3. Apply the schema once: `psql "$QUEUE_DATABASE_URL" -f sql/postgres/001_task_queue.sql`.

### Submitting and managing tasks

```bash
source script/load_env.sh
script/queue_ctl.sh submit shopee_th_shampoo headless_taxonomy --priority 200
script/queue_ctl.sh submit shopee_th_shampoo targeted_qa_fix --loop-count 1 --priority 100
script/queue_ctl.sh list --status queued
script/queue_ctl.sh priority <id> 500
script/queue_ctl.sh cancel <id>
```

The same operations are also exposed as a Windmill UI, built separately against the same Postgres
table — see the design spec's §7 for the UI's own build prompt.

### Running workers

```bash
source script/load_env.sh
script/queue_worker.sh
```

Each worker is a long-running loop: it claims the highest-priority queued task for a table no other
worker currently holds, runs the appropriate script up to `loop_count` times (stopping early if the
script's own live pre-check finds nothing left to do), and persists the result. Run multiple instances
(tmux, nohup, systemd — your choice) to process several categories concurrently; two workers will never
claim the same `table_name` at once — see the design spec's §3 for why.

### `loop_count` guidance

- `headless_taxonomy.sh` tasks and `targeted_qa_fix.sh` auto-discovery-mode tasks can self-detect
  "nothing left to do" (a live `gap_count`/worklist-count pre-check re-run at the start of every
  iteration) — `loop_count = 3` (the default) is safe and will stop itself early once the category is
  caught up.
- `targeted_qa_fix.sh` **brief-mode** tasks (a hand-written `## Targeted QA Fix Brief` section) cannot
  self-detect completion — set `--loop-count 1` for those unless you specifically know the brief needs
  multiple passes, or the wrapper will simply re-run the same brief redundantly.
```

- [ ] **Step 2: Commit**

```bash
git add docs/headless-runbook.md
git commit -m "Document queue mode in the headless runbook"
```

---

### Task 9: End-to-end manual verification

**Files:** none (no code changes — this is a verification checklist against the real scripts, requiring live BigQuery + `claude` credentials in addition to Postgres).

**Interfaces:**
- Consumes: everything from Tasks 1–8.

This task cannot be automated in CI (it needs live BQ/claude credentials, same limitation the existing `test_headless_taxonomy.sh`/`test_targeted_qa_fix.sh` already accept). Run it by hand once, against a real category, before relying on queue mode for real work.

- [ ] **Step 1: Pick a category with a genuinely empty or near-empty coverage gap** (to keep the real `claude -p` run cheap/fast — ideally one that's already fully covered, so the pre-check fires immediately)

```bash
source script/load_env.sh
script/queue_ctl.sh submit <a_mostly_covered_table> headless_taxonomy --loop-count 3 --priority 999
```

- [ ] **Step 2: Run one worker in the foreground and watch it**

```bash
script/queue_worker.sh
```

Expected: the worker claims the task, the underlying `headless_taxonomy.sh` invocation prints `No in-scope coverage gap for .../... — nothing to do.` and `QUEUE_SIGNAL: NOTHING_TO_DO` without ever calling `claude -p`, and the loop stops after 1 iteration even though `loop_count=3`.

- [ ] **Step 3: Confirm the persisted result**

```bash
psql "$QUEUE_DATABASE_URL" -c "SELECT id, table_name, status, iterations_run, last_result FROM task_queue WHERE table_name='<a_mostly_covered_table>';"
```

Expected: `status = done`, `iterations_run = 1`.

- [ ] **Step 4: Confirm mutual exclusion holds under real contention** — submit two tasks for the *same* table and start two workers; confirm (via `SELECT table_name, status, claimed_by FROM task_queue WHERE table_name = '<table>'`) that only one ever reaches `status='running'` at a time, never both simultaneously.

- [ ] **Step 5: Clean up test rows**

```bash
psql "$QUEUE_DATABASE_URL" -c "DELETE FROM task_queue WHERE table_name='<a_mostly_covered_table>';"
```

No commit for this task — it's verification only.
