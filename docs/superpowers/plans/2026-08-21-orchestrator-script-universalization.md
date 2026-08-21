# Orchestrator Script Universalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the three V2 QA/taxonomy orchestrator scripts and the two postgres queue workers shared, consistent logging, error handling, and a structured JSON result — without touching the existing `QUEUE_SIGNAL:` control-flow contract.

**Architecture:** Two new bash libraries (`script/lib/common.sh` for logging/error/JSON-emit, `script/lib/queue_common.sh` for the postgres claim/heartbeat/persist logic both queue workers duplicate) plus one stdlib-only Python formatter (`script/lib/format_result.py`). The three orchestrators and two queue workers source/call these instead of their own ad hoc copies. `QUEUE_SIGNAL: X` stays exactly as-is; a new `emit_result` JSON line is added alongside it.

**Tech Stack:** bash (`set -euo pipefail`, existing repo convention), `jq`, Python 3 stdlib only (`json`, `sys`) via the repo's `.venv/bin/python3`.

**Spec:** `docs/superpowers/specs/2026-08-21-orchestrator-script-universalization-design.md`

## Global Constraints

- JSON output is additive only — `echo "QUEUE_SIGNAL: X"` lines are never removed, reworded, or replaced. Queue workers keep grepping them exactly as today.
- All logging goes to **stderr** via a shared `log()` — stdout stays reserved for `QUEUE_SIGNAL:` and the new `emit_result` JSON line. Queue workers capture `2>&1` already, so this changes nothing about what gets captured.
- Scope is exactly: `script/niq/headless_taxonomy_v2.sh`, `script/niq/targeted_qa_fix_v2.sh`, `script/non_niq/non_niq_qa_v2.sh`, `script/niq/queue_worker.sh`, `script/non_niq/queue_worker.sh`, `script/niq/queue_ctl.sh` (new `show` subcommand only). V1 scripts (`headless_taxonomy.sh`, `targeted_qa_fix.sh`, `non_niq_qa.sh`) and `custom_*` variants are never touched.
- No new dependencies. `jq` is already a hard dependency of every script in scope. The Python formatter uses stdlib only.
- No test framework (no bats, no pytest fixtures) — each lib file gets a `--self-test` flag guarded by `[[ "${BASH_SOURCE[0]}" == "${0}" ]]`, run directly, asserting with plain `[[ ... ]]` / `jq -e`.

---

## Task 1: `script/lib/common.sh` — logging, error exit, JSON result

**Files:**
- Create: `script/lib/common.sh`

**Interfaces:**
- Produces: `log(level, ...msg)` → writes `[YYYY-MM-DD HH:MM:SS] [LEVEL] msg` to stderr.
- Produces: `die(...msg)` → `log ERROR "$*"; exit 1`.
- Produces: `emit_result(table, signal, message, [key=value ...])` → prints one JSON object to stdout: `{"timestamp","table","signal","message", ...extra}`.

- [ ] **Step 1: Create the library file**

```bash
#!/usr/bin/env bash
# Shared helpers for the niq/non_niq V2 orchestrator scripts: logging, error exit, and one
# structured JSON summary line per run. Source, don't execute:
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
# See docs/superpowers/specs/2026-08-21-orchestrator-script-universalization-design.md.
#
# All logging goes to stderr -- stdout stays reserved for the existing `QUEUE_SIGNAL: X` line and
# the emit_result JSON line below. Queue workers capture stdout+stderr together (`2>&1`) already,
# so this is purely a stream-discipline change, not a capture change.
log() {
  local level="$1"
  shift
  echo "[$(date -u '+%Y-%m-%d %H:%M:%S')] [${level}] $*" >&2
}

die() {
  log ERROR "$*"
  exit 1
}

# emit_result <table> <signal> <message> [key=value ...]
# Prints one JSON object to stdout -- additive to (never replacing) the existing
# `echo "QUEUE_SIGNAL: X"` line callers already print. Extra key=value pairs become extra string
# fields (e.g. `emit_result "$table" DONE "ok" iterations=3 rows_created=12`).
emit_result() {
  local table="$1" signal="$2" message="$3"
  shift 3
  local jq_args=(--arg timestamp "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --arg table "$table" \
    --arg signal "$signal" --arg message "$message")
  local filter='{timestamp: $timestamp, table: $table, signal: $signal, message: $message}'
  local kv k v
  for kv in "$@"; do
    k="${kv%%=*}"
    v="${kv#*=}"
    jq_args+=(--arg "$k" "$v")
    filter="${filter} + {${k}: \$${k}}"
  done
  jq -n "${jq_args[@]}" "$filter"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    --self-test)
      out=$(emit_result "shopee_th_test" "DONE" "ok" "iterations=3")
      echo "$out" | jq -e '
        .table == "shopee_th_test" and .signal == "DONE" and .message == "ok" and .iterations == "3"
      ' >/dev/null || { echo "FAIL: emit_result -> $out"; exit 1; }
      echo "$out" | jq -e '.timestamp | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")' >/dev/null \
        || { echo "FAIL: emit_result timestamp format -> $out"; exit 1; }
      echo "self-test OK: common.sh"
      ;;
    *)
      echo "Usage: $0 --self-test" >&2
      exit 1
      ;;
  esac
fi
```

- [ ] **Step 2: Make it executable and run the self-test**

Run: `chmod +x script/lib/common.sh && bash script/lib/common.sh --self-test`
Expected: `self-test OK: common.sh`

- [ ] **Step 3: Commit**

```bash
git add script/lib/common.sh
git commit -m "Add script/lib/common.sh: shared log/die/emit_result for V2 orchestrators"
```

---

## Task 2: `script/lib/queue_common.sh` — postgres queue wrapper

**Files:**
- Create: `script/lib/queue_common.sh`

**Interfaces:**
- Consumes: `queue_psql(sql, [psql flags...])` (from `script/load_env.sh`, already sourced by callers before this file is used) and a `QUEUE_TABLE` variable already set by the caller.
- Produces: `parse_queue_signal`, `is_duplicate_key_error`, `queue_signal_to_status`, `should_stop_looping`, `_sql_quote`, `reclaim_stale_leases_query(script_type)`, `reclaim_stale_leases(script_type)`, `claim_next_task_query(worker_id, script_type)`, `claim_next_task(worker_id, script_type)`, `heartbeat(id)`, `extract_last_result_json(output)`, `persist_final_status(id, status, iterations_run, output)`, `queue_main_loop(script_type_filter, worker_id, run_task_fn)`.
- `script_type` args: empty string = unscoped (matches niq's original behavior); a non-empty value scopes to that `script_type` (matches non_niq's original behavior).

This extracts the ~90%-duplicate logic currently copy-pasted between `script/niq/queue_worker.sh` and `script/non_niq/queue_worker.sh`, adopting `non_niq/queue_worker.sh`'s existing pattern of separating pure SQL-builder functions (`*_query`) from the functions that actually call `queue_psql` — that separation is what makes Step 2's self-test possible without a live database.

- [ ] **Step 1: Create the library file**

```bash
#!/usr/bin/env bash
# Shared postgres task-queue wrapper for script/niq/queue_worker.sh and
# script/non_niq/queue_worker.sh -- both duplicated this ~90% verbatim before this file existed.
# See docs/superpowers/specs/2026-08-21-orchestrator-script-universalization-design.md.
#
# Requires queue_psql() (script/load_env.sh) and QUEUE_TABLE to already be set by the caller
# before any function here is actually called (source order doesn't matter for function
# *definitions*, only for the values they read at call time).

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

_sql_quote() {
  local s="$1"
  echo "'${s//\'/\'\'}'"
}

# reclaim_stale_leases_query [script_type]
# Empty/omitted script_type = unscoped. A scoped worker (non_niq) MUST pass its script_type --
# an unscoped reclaim run by a scoped worker would reset a still-running row belonging to a
# DIFFERENT worker (e.g. niq's) back to 'queued' if that row's lease merely looked stale to this
# worker, defeating one_running_task_per_table for a table this worker doesn't even own.
reclaim_stale_leases_query() {
  local script_type="${1:-}"
  local type_filter=""
  [[ -n "$script_type" ]] && type_filter=" AND script_type=$(_sql_quote "$script_type")"
  echo "UPDATE ${QUEUE_TABLE} SET status='queued', claimed_by=NULL, claimed_at=NULL
    WHERE status='running'${type_filter}
      AND claimed_at < now() - interval '${LEASE_TIMEOUT_HOURS:-4} hours';"
}

reclaim_stale_leases() {
  queue_psql "$(reclaim_stale_leases_query "${1:-}")" -t -A >/dev/null
}

# claim_next_task_query <worker_id> [script_type]
# REQUIRED, not optional -- see sql/postgres/001_task_queue.sql: SKIP LOCKED alone does not give
# per-table exclusion. The one_running_task_per_table unique index is what actually blocks a
# second concurrent claim, by raising a duplicate-key error on commit -- which claim_next_task
# must treat as "lost the race, no task claimed this round," not a crash.
claim_next_task_query() {
  local worker_id="$1" script_type="${2:-}"
  local type_filter=""
  [[ -n "$script_type" ]] && type_filter=" AND script_type=$(_sql_quote "$script_type")"
  echo "UPDATE ${QUEUE_TABLE} SET status='running', claimed_by='${worker_id}', claimed_at=now()
    WHERE id = (
      SELECT id FROM ${QUEUE_TABLE}
      WHERE status='queued'${type_filter}
        AND table_name NOT IN (SELECT table_name FROM ${QUEUE_TABLE} WHERE status='running')
      ORDER BY priority DESC, submitted_at ASC
      FOR UPDATE SKIP LOCKED LIMIT 1
    )
    RETURNING id, table_name, script_type, month, max_turns, block_size, loop_count;"
}

claim_next_task() {
  local worker_id="$1" script_type="${2:-}"
  local out
  if ! out=$(queue_psql "$(claim_next_task_query "$worker_id" "$script_type")" -t -A -F'|' 2>&1); then
    [[ "$(is_duplicate_key_error "$out")" == "true" ]] && { echo ""; return 0; }
    echo "$out" >&2
    return 1
  fi
  # $out is polluted with the "UPDATE 1" command-completion tag psql always prints regardless of
  # -t/-A. `|| true` is required: grep exits 1 on the legitimate "no row claimed" case (empty
  # $out), which under `set -e` would otherwise be treated as this function failing.
  grep '|' <<< "$out" || true
}

heartbeat() {
  local id="$1"
  queue_psql "UPDATE ${QUEUE_TABLE} SET claimed_at=now() WHERE id=${id} AND status='running';" -t -A >/dev/null
}

# extract_last_result_json <output>
# Scans $output for the LAST line that parses as JSON with a "signal" key (i.e. an emit_result
# line from the underlying orchestrator) and prints that. Falls back to the old
# {raw_output: ...} wrapping if no such line is found -- a run that crashed before reaching its
# emit_result call still gets *something* stored, not a DB write failure. Pulled out of
# persist_final_status as its own pure function so it's testable without a live database.
extract_last_result_json() {
  local output="$1"
  local last_result_json="" line
  while IFS= read -r line; do
    if echo "$line" | jq -e '.signal' >/dev/null 2>&1; then
      last_result_json="$line"
    fi
  done <<< "$output"
  if [[ -z "$last_result_json" ]]; then
    last_result_json=$(printf '%s' "$output" | jq -Rs '{raw_output: .}')
  fi
  echo "$last_result_json"
}

# persist_final_status <id> <status> <iterations_run> <output>
# Stores a structured result as last_result instead of the whole raw output blob -- see
# extract_last_result_json above for how that's derived.
persist_final_status() {
  local id="$1" status="$2" iterations_run="$3" output="$4"
  local last_result_json
  last_result_json=$(extract_last_result_json "$output")
  queue_psql "
      UPDATE ${QUEUE_TABLE}
      SET status = $(_sql_quote "$status"), iterations_run = ${iterations_run}, updated_at = now(),
          last_result = $(_sql_quote "$last_result_json")::json
      WHERE id = ${id};" \
    -t -A >/dev/null
}

# queue_main_loop <script_type_filter> <worker_id> <run_task_fn>
# run_task_fn must already be defined by the caller; it's invoked as:
#   "$run_task_fn" <id> <table_name> <script_type> <month> <max_turns> <block_size> <loop_count>
queue_main_loop() {
  local script_type_filter="$1" worker_id="$2" run_task_fn="$3"
  echo "Worker ${worker_id} starting, polling every ${POLL_INTERVAL_SECONDS:-15}s"
  while true; do
    reclaim_stale_leases "$script_type_filter"
    local row
    row=$(claim_next_task "$worker_id" "$script_type_filter") || { sleep "${POLL_INTERVAL_SECONDS:-15}"; continue; }
    if [[ -z "$row" ]]; then
      sleep "${POLL_INTERVAL_SECONDS:-15}"
      continue
    fi
    local id table_name script_type month max_turns block_size loop_count
    IFS='|' read -r id table_name script_type month max_turns block_size loop_count <<< "$row"
    echo "Claimed task ${id}: ${table_name} (${script_type})"
    "$run_task_fn" "$id" "$table_name" "$script_type" "$month" "$max_turns" "$block_size" "$loop_count"
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    --self-test)
      QUEUE_TABLE="public.task_queue"
      unscoped_reclaim=$(reclaim_stale_leases_query "")
      [[ "$unscoped_reclaim" != *"script_type"* ]] \
        || { echo "FAIL: unscoped reclaim query should not filter by script_type -> $unscoped_reclaim"; exit 1; }
      scoped_reclaim=$(reclaim_stale_leases_query "non_niq_qa")
      [[ "$scoped_reclaim" == *"script_type='non_niq_qa'"* ]] \
        || { echo "FAIL: scoped reclaim query missing filter -> $scoped_reclaim"; exit 1; }
      unscoped_claim=$(claim_next_task_query "worker-1" "")
      [[ "$unscoped_claim" != *"script_type="* ]] \
        || { echo "FAIL: unscoped claim query should not filter -> $unscoped_claim"; exit 1; }
      scoped_claim=$(claim_next_task_query "worker-1" "headless_taxonomy")
      [[ "$scoped_claim" == *"script_type='headless_taxonomy'"* ]] \
        || { echo "FAIL: scoped claim query missing filter -> $scoped_claim"; exit 1; }
      [[ "$(is_duplicate_key_error "duplicate key value violates unique constraint foo")" == "true" ]] \
        || { echo "FAIL: is_duplicate_key_error true case"; exit 1; }
      [[ "$(is_duplicate_key_error "some other error")" == "false" ]] \
        || { echo "FAIL: is_duplicate_key_error false case"; exit 1; }
      [[ "$(queue_signal_to_status "DONE")" == "done" ]] || { echo "FAIL: queue_signal_to_status DONE"; exit 1; }
      [[ "$(queue_signal_to_status "BLOCKED")" == "blocked" ]] || { echo "FAIL: queue_signal_to_status BLOCKED"; exit 1; }
      [[ "$(queue_signal_to_status "FAILED")" == "failed" ]] || { echo "FAIL: queue_signal_to_status FAILED"; exit 1; }
      [[ "$(should_stop_looping "DONE")" == "false" ]] || { echo "FAIL: should_stop_looping DONE"; exit 1; }
      [[ "$(should_stop_looping "BLOCKED")" == "true" ]] || { echo "FAIL: should_stop_looping BLOCKED"; exit 1; }
      found=$(extract_last_result_json "$(printf 'some noise\n{"timestamp":"t","table":"x","signal":"DONE","message":"ok"}\nQUEUE_SIGNAL: DONE')")
      [[ "$found" == '{"timestamp":"t","table":"x","signal":"DONE","message":"ok"}' ]] \
        || { echo "FAIL: extract_last_result_json found-case -> $found"; exit 1; }
      fallback=$(extract_last_result_json "$(printf 'plain crash output\nno json here')")
      echo "$fallback" | jq -e '.raw_output | test("plain crash output")' >/dev/null \
        || { echo "FAIL: extract_last_result_json fallback-case -> $fallback"; exit 1; }
      echo "self-test OK: queue_common.sh"
      ;;
    *)
      echo "Usage: $0 --self-test" >&2
      exit 1
      ;;
  esac
fi
```

- [ ] **Step 2: Make it executable and run the self-test**

Run: `chmod +x script/lib/queue_common.sh && bash script/lib/queue_common.sh --self-test`
Expected: `self-test OK: queue_common.sh`

- [ ] **Step 3: Commit**

```bash
git add script/lib/queue_common.sh
git commit -m "Add script/lib/queue_common.sh: shared postgres queue wrapper"
```

---

## Task 3: Refactor `script/niq/queue_worker.sh` to use `queue_common.sh`

**Files:**
- Modify: `script/niq/queue_worker.sh` (full rewrite of the file body — logic is unchanged, only DRY'd against Task 2)

**Interfaces:**
- Consumes: everything from Task 2 (`queue_main_loop`, `heartbeat`, `parse_queue_signal`, `queue_signal_to_status`, `should_stop_looping`, `persist_final_status`).
- Produces: unchanged external behavior — still a `main()` polling loop, still reads `HEADLESS_TAXONOMY_SCRIPT`/`TARGETED_QA_FIX_SCRIPT` env overrides.

- [ ] **Step 1: Replace the file contents**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Pulls the highest-priority queued task from Postgres, runs script/headless_taxonomy.sh or
# script/targeted_qa_fix.sh up to loop_count times, and persists the result.
# See docs/superpowers/specs/2026-07-27-task-queue-design.md for the full design and
# docs/superpowers/specs/2026-08-21-orchestrator-script-universalization-design.md for the shared
# queue_common.sh wrapper this now uses.
#
# Usage: script/queue_worker.sh
# Requires QUEUE_DATABASE_URL (see script/load_env.sh / .env.example).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/queue_common.sh"

QUEUE_TABLE="${QUEUE_SCHEMA:-public}.task_queue"

run_underlying_script() {
  local script_type="$1" table="$2" month="$3" max_turns="$4" block_size="$5"
  case "$script_type" in
    headless_taxonomy)
      "${HEADLESS_TAXONOMY_SCRIPT:-./script/niq/headless_taxonomy.sh}" "$table" "$month" "$max_turns"
      ;;
    targeted_qa_fix)
      "${TARGETED_QA_FIX_SCRIPT:-./script/niq/targeted_qa_fix.sh}" "$table" "$block_size" "$max_turns"
      ;;
    *)
      echo "Unknown script_type: $script_type" >&2
      echo "QUEUE_SIGNAL: FAILED"
      ;;
  esac
}

# See queue_common.sh's persist_final_status comment for the `|| true` rationale on `signal=`:
# parse_queue_signal's pipeline exits non-zero whenever no QUEUE_SIGNAL line is found (e.g. the
# underlying script crashed before printing one) -- without `|| true` here, that would silently
# kill the whole worker loop instead of falling through to queue_signal_to_status's own
# "unparseable -> failed" handling.
run_task() {
  local id="$1" table="$2" script_type="$3" month="$4" max_turns="$5" block_size="$6" loop_count="$7"
  local iterations_run=0 final_status="failed" last_output="" signal=""
  local i
  for ((i = 1; i <= loop_count; i++)); do
    heartbeat "$id"
    last_output=$(run_underlying_script "$script_type" "$table" "$month" "$max_turns" "$block_size" 2>&1) || true
    echo "$last_output"
    iterations_run=$((iterations_run + 1))
    signal=$(parse_queue_signal "$last_output") || true
    final_status=$(queue_signal_to_status "$signal")
    [[ "$(should_stop_looping "$signal")" == "true" ]] && break
  done
  persist_final_status "$id" "$final_status" "$iterations_run" "$last_output"
}

main() {
  source "$(dirname "$0")/../load_env.sh"
  QUEUE_TABLE="${QUEUE_SCHEMA:-public}.task_queue"   # recompute now that .env is actually loaded
  : "${QUEUE_DATABASE_URL:?QUEUE_DATABASE_URL must be set (via .env or the environment)}"
  WORKER_ID="$(hostname)-$$"
  queue_main_loop "" "$WORKER_ID" run_task
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
```

- [ ] **Step 2: Syntax-check and confirm behavior-preserving functions are gone from this file**

Run: `bash -n script/niq/queue_worker.sh && echo SYNTAX_OK`
Expected: `SYNTAX_OK`

Run: `grep -c 'claim_next_task_query\|reclaim_stale_leases_query\|^persist_final_status()' script/niq/queue_worker.sh`
Expected: `0` (these now live only in `queue_common.sh`)

- [ ] **Step 3: Commit**

```bash
git add script/niq/queue_worker.sh
git commit -m "Refactor script/niq/queue_worker.sh onto shared queue_common.sh"
```

---

## Task 4: Refactor `script/non_niq/queue_worker.sh` to use `queue_common.sh`

**Files:**
- Modify: `script/non_niq/queue_worker.sh` (full rewrite of the file body)

**Interfaces:**
- Consumes: everything from Task 2, passing `"non_niq_qa"` as the `script_type_filter` (its original scoped behavior).
- Produces: unchanged external behavior — still reads `NON_NIQ_QA_SCRIPT` env override, still splits `table_name` on `:` into dataset/platform.

- [ ] **Step 1: Replace the file contents**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Separate polling loop from script/niq/queue_worker.sh -- claims only script_type='non_niq_qa' rows
# from the SAME shared p4ct2g2urhzcfnz.task_queue Postgres table. table_name is encoded as
# "{dataset}:{platform}" for every row this worker claims (e.g. "babybath:shopee") -- see the
# Global Constraints in docs/superpowers/plans/2026-08-06-non-niq-agentic-qa.md.
# See docs/superpowers/specs/2026-08-21-orchestrator-script-universalization-design.md for the
# shared queue_common.sh wrapper this now uses.
#
# Usage: script/non_niq/queue_worker.sh
# Requires QUEUE_DATABASE_URL (see script/load_env.sh / .env.example).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/queue_common.sh"

QUEUE_TABLE="${QUEUE_SCHEMA:-public}.task_queue"

split_table_name() {
  local table_name="$1"
  local dataset="${table_name%%:*}"
  local platform="${table_name#*:}"
  echo "${dataset} ${platform}"
}

run_task() {
  local id="$1" table_name="$2" script_type="$3" month="$4" max_turns="$5" block_size="$6" loop_count="$7"
  local dataset platform
  read -r dataset platform <<< "$(split_table_name "$table_name")"
  local iterations_run=0 final_status="failed" last_output="" signal=""
  local i
  for ((i = 1; i <= loop_count; i++)); do
    heartbeat "$id"
    last_output=$("${NON_NIQ_QA_SCRIPT:-./script/non_niq/non_niq_qa.sh}" "$dataset" "$platform" "$max_turns" 2>&1) || true
    echo "$last_output"
    iterations_run=$((iterations_run + 1))
    signal=$(parse_queue_signal "$last_output") || true
    final_status=$(queue_signal_to_status "$signal")
    [[ "$(should_stop_looping "$signal")" == "true" ]] && break
  done
  persist_final_status "$id" "$final_status" "$iterations_run" "$last_output"
}

main() {
  source "$(dirname "$0")/../load_env.sh"
  QUEUE_TABLE="${QUEUE_SCHEMA:-public}.task_queue"
  : "${QUEUE_DATABASE_URL:?QUEUE_DATABASE_URL must be set (via .env or the environment)}"
  WORKER_ID="non-niq-$(hostname)-$$"
  queue_main_loop "non_niq_qa" "$WORKER_ID" run_task
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
```

- [ ] **Step 2: Syntax-check and confirm behavior-preserving functions are gone from this file**

Run: `bash -n script/non_niq/queue_worker.sh && echo SYNTAX_OK`
Expected: `SYNTAX_OK`

Run: `grep -c 'claim_next_task_query\|reclaim_stale_leases_query\|^persist_final_status()' script/non_niq/queue_worker.sh`
Expected: `0`

- [ ] **Step 3: Commit**

```bash
git add script/non_niq/queue_worker.sh
git commit -m "Refactor script/non_niq/queue_worker.sh onto shared queue_common.sh"
```

---

## Task 5: `script/lib/format_result.py` — human-readable formatter

**Files:**
- Create: `script/lib/format_result.py`

**Interfaces:**
- Produces: `format_result(obj: dict) -> str` (pure function, importable and self-testable).
- CLI: reads one JSON object from stdin, prints the formatted block, exit 0. On empty/unparseable stdin, prints a `(...)` diagnostic line and exits 1. On a `{"raw_output": "..."}` fallback blob (no `signal` key — see Task 2's `persist_final_status` fallback), prints the raw text as-is instead of the structured block.

- [ ] **Step 1: Create the file**

```python
#!/usr/bin/env python3
"""Pretty-prints an emit_result JSON object (table/signal/timestamp/message + extras) for a
human -- reads one JSON object from stdin. Used by queue_ctl.sh's `show` subcommand and ad hoc
at a terminal: `some_script.sh ... | tail -1 | .venv/bin/python3 script/lib/format_result.py`.
See docs/superpowers/specs/2026-08-21-orchestrator-script-universalization-design.md.
"""
import json
import sys

CORE_FIELDS = ("table", "signal", "timestamp", "message")


def format_result(obj):
    lines = [
        f"Table:   {obj.get('table', '?')}",
        f"Signal:  {obj.get('signal', '?')}",
        f"Time:    {obj.get('timestamp', '?')}",
        f"Message: {obj.get('message', '?')}",
    ]
    extra = {k: v for k, v in obj.items() if k not in CORE_FIELDS}
    if extra:
        lines.append("Extra:")
        lines.extend(f"  {k}: {v}" for k, v in extra.items())
    return "\n".join(lines)


def main():
    raw = sys.stdin.read().strip()
    if not raw:
        print("(empty result)")
        return 1
    try:
        obj = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"(unparseable result: {e})")
        print(raw)
        return 1
    if "signal" not in obj and "raw_output" in obj:
        print("(no structured result -- raw fallback stored)")
        print(obj["raw_output"])
        return 0
    print(format_result(obj))
    return 0


def _self_test():
    demo = {
        "timestamp": "2026-08-21T00:00:00Z",
        "table": "shopee_th_test",
        "signal": "DONE",
        "message": "ok",
        "iterations": "3",
    }
    out = format_result(demo)
    assert "Table:   shopee_th_test" in out, out
    assert "Signal:  DONE" in out, out
    assert "iterations: 3" in out, out
    print("self-test OK: format_result.py")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        _self_test()
        sys.exit(0)
    sys.exit(main())
```

- [ ] **Step 2: Make it executable and run the self-test**

Run: `chmod +x script/lib/format_result.py && ./.venv/bin/python3 script/lib/format_result.py --self-test`
Expected: `self-test OK: format_result.py`

- [ ] **Step 3: Run the CLI path against a sample JSON object**

Run: `echo '{"timestamp":"2026-08-21T00:00:00Z","table":"shopee_th_detergent","signal":"DONE","message":"universe refreshed","iterations":"2"}' | ./.venv/bin/python3 script/lib/format_result.py`
Expected:
```
Table:   shopee_th_detergent
Signal:  DONE
Time:    2026-08-21T00:00:00Z
Message: universe refreshed
Extra:
  iterations: 2
```

- [ ] **Step 4: Commit**

```bash
git add script/lib/format_result.py
git commit -m "Add script/lib/format_result.py: human-readable emit_result formatter"
```

---

## Task 6: `queue_ctl.sh show <task_id>` — pipe a task's result through the formatter

**Files:**
- Modify: `script/niq/queue_ctl.sh:1-138`

**Interfaces:**
- Consumes: `script/lib/format_result.py` (Task 5).
- Produces: new `show` subcommand alongside `submit`/`list`/`priority`/`cancel`.

- [ ] **Step 1: Add `build_show_sql` next to the other builders**

Edit `script/niq/queue_ctl.sh`. Replace:

```bash
build_cancel_sql() {
  local task_id="$1"
  echo "UPDATE ${QUEUE_TABLE} SET status = 'cancelled', updated_at = now() WHERE id = ${task_id} AND status = 'queued' RETURNING id;"
}
```

with:

```bash
build_cancel_sql() {
  local task_id="$1"
  echo "UPDATE ${QUEUE_TABLE} SET status = 'cancelled', updated_at = now() WHERE id = ${task_id} AND status = 'queued' RETURNING id;"
}

build_show_sql() {
  local task_id="$1"
  echo "SELECT last_result FROM ${QUEUE_TABLE} WHERE id = ${task_id};"
}
```

- [ ] **Step 2: Add `cmd_show`**

Replace:

```bash
cmd_cancel() {
  local task_id="$1"
  local out id_line
  out=$(queue_psql "$(build_cancel_sql "$task_id")" -t -A)
  # See cmd_priority above for why a bare `-z "$out"` check is wrong -- the UPDATE-N tag is always
  # present, so filter down to the bare numeric id line RETURNING emits on an actual match.
  id_line=$(grep -E '^[0-9]+$' <<< "$out" || true)
  if [[ -z "$id_line" ]]; then
    echo "Task ${task_id} already started (or doesn't exist) -- can no longer be cancelled." >&2
    exit 1
  fi
  echo "Task ${task_id} cancelled."
}
```

with:

```bash
cmd_cancel() {
  local task_id="$1"
  local out id_line
  out=$(queue_psql "$(build_cancel_sql "$task_id")" -t -A)
  # See cmd_priority above for why a bare `-z "$out"` check is wrong -- the UPDATE-N tag is always
  # present, so filter down to the bare numeric id line RETURNING emits on an actual match.
  id_line=$(grep -E '^[0-9]+$' <<< "$out" || true)
  if [[ -z "$id_line" ]]; then
    echo "Task ${task_id} already started (or doesn't exist) -- can no longer be cancelled." >&2
    exit 1
  fi
  echo "Task ${task_id} cancelled."
}

cmd_show() {
  local task_id="$1"
  local raw
  raw=$(queue_psql "$(build_show_sql "$task_id")" -t -A)
  if [[ -z "$raw" ]]; then
    echo "Task ${task_id} not found or has no result yet." >&2
    exit 1
  fi
  local repo_root
  repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
  "${repo_root}/.venv/bin/python3" "${repo_root}/script/lib/format_result.py" <<< "$raw"
}
```

- [ ] **Step 3: Wire it into `main()`'s dispatch and usage comment**

Replace:

```bash
# Usage:
#   script/queue_ctl.sh submit <table> <headless_taxonomy|targeted_qa_fix> \
#       [--month YYYY-MM] [--max-turns N] [--block-size N] [--loop-count N] [--priority N]
#   script/queue_ctl.sh list [--status queued|running|done|failed|blocked|cancelled]
#   script/queue_ctl.sh priority <task_id> <new_priority>
#   script/queue_ctl.sh cancel <task_id>
```

with:

```bash
# Usage:
#   script/queue_ctl.sh submit <table> <headless_taxonomy|targeted_qa_fix> \
#       [--month YYYY-MM] [--max-turns N] [--block-size N] [--loop-count N] [--priority N]
#   script/queue_ctl.sh list [--status queued|running|done|failed|blocked|cancelled]
#   script/queue_ctl.sh priority <task_id> <new_priority>
#   script/queue_ctl.sh cancel <task_id>
#   script/queue_ctl.sh show <task_id>
```

Replace:

```bash
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
```

with:

```bash
  local cmd="${1:-}"
  case "$cmd" in
    submit) shift; cmd_submit "$@" ;;
    list) shift; cmd_list "$@" ;;
    priority) shift; cmd_priority "$@" ;;
    cancel) shift; cmd_cancel "$@" ;;
    show) shift; cmd_show "$@" ;;
    *)
      echo "Usage: $0 submit|list|priority|cancel|show ..." >&2
      exit 1
      ;;
  esac
```

- [ ] **Step 4: Syntax-check and verify the pure `build_show_sql` function**

Run: `bash -n script/niq/queue_ctl.sh && echo SYNTAX_OK`
Expected: `SYNTAX_OK`

Run: `source script/niq/queue_ctl.sh 2>/dev/null; QUEUE_TABLE="public.task_queue"; build_show_sql 42`

(Sourcing is safe here — `queue_ctl.sh` only runs `main()` when executed directly, guarded by the `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` check at the bottom of the file.)

Expected: `SELECT last_result FROM public.task_queue WHERE id = 42;`

- [ ] **Step 5: Commit**

```bash
git add script/niq/queue_ctl.sh
git commit -m "Add queue_ctl.sh show subcommand, pipes last_result through format_result.py"
```

---

## Task 7: Integrate `common.sh` into `script/niq/headless_taxonomy_v2.sh`

**Files:**
- Modify: `script/niq/headless_taxonomy_v2.sh:1-313`

**Interfaces:**
- Consumes: `log`, `emit_result` from Task 1.

- [ ] **Step 1: Source `common.sh` at the top of the file**

Replace:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: ./script/niq/headless_taxonomy_v2.sh <TABLE> [MONTH] [MAX_TURNS]
```

with:

```bash
#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

# Usage: ./script/niq/headless_taxonomy_v2.sh <TABLE> [MONTH] [MAX_TURNS]
```

- [ ] **Step 2: Convert `main()`'s informational echoes to `log`, and add `emit_result` next to every `QUEUE_SIGNAL:` line**

Replace:

```bash
  echo "${table}"
  echo "Resolved month: ${month}"

  local gap_count
  gap_count=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "$(gap_count_query "$table" "$month")" | tail -1)

  if [[ "$gap_count" == "0" ]]; then
    echo "No in-scope coverage gap for ${table}/${month} — nothing to do."
    echo "QUEUE_SIGNAL: NOTHING_TO_DO"
    exit 0
  fi

  local existing_llm_rows
  existing_llm_rows=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "$(existing_llm_rows_query "$table")" | tail -1)

  local scenario
  scenario=$(decide_scenario "$existing_llm_rows")

  local block_size
  block_size=$(compute_block_size "$scenario" "$gap_count")

  echo "Scenario: ${scenario} (existing_llm_rows=${existing_llm_rows}, gap_count=${gap_count}, block_size=${block_size}, max_turns=${max_turns})"
  echo "Building candidate-enriched worklist for ${table}..."

  local worklist_json
  worklist_json=$(python3 script/niq/headless_v2_worklist.py --table "$table" --scenario "$scenario" --month "$month" --block-size "$block_size")

  if [[ "$worklist_json" == "[]" ]]; then
    echo "No worklist products for ${table} after candidate build — nothing to do."
    echo "QUEUE_SIGNAL: NOTHING_TO_DO"
    exit 0
  fi

  echo "TAXONOMY EXTRACTION STARTED (V2)"
  echo "==========================="
```

with:

```bash
  log INFO "Processing table: ${table}"
  log INFO "Resolved month: ${month}"

  local gap_count
  gap_count=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "$(gap_count_query "$table" "$month")" | tail -1)

  if [[ "$gap_count" == "0" ]]; then
    log INFO "No in-scope coverage gap for ${table}/${month} — nothing to do."
    echo "QUEUE_SIGNAL: NOTHING_TO_DO"
    emit_result "$table" "NOTHING_TO_DO" "No in-scope coverage gap for ${table}/${month}"
    exit 0
  fi

  local existing_llm_rows
  existing_llm_rows=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "$(existing_llm_rows_query "$table")" | tail -1)

  local scenario
  scenario=$(decide_scenario "$existing_llm_rows")

  local block_size
  block_size=$(compute_block_size "$scenario" "$gap_count")

  log INFO "Scenario: ${scenario} (existing_llm_rows=${existing_llm_rows}, gap_count=${gap_count}, block_size=${block_size}, max_turns=${max_turns})"
  log INFO "Building candidate-enriched worklist for ${table}..."

  local worklist_json
  worklist_json=$(python3 script/niq/headless_v2_worklist.py --table "$table" --scenario "$scenario" --month "$month" --block-size "$block_size")

  if [[ "$worklist_json" == "[]" ]]; then
    log INFO "No worklist products for ${table} after candidate build — nothing to do."
    echo "QUEUE_SIGNAL: NOTHING_TO_DO"
    emit_result "$table" "NOTHING_TO_DO" "No worklist products for ${table} after candidate build"
    exit 0
  fi

  log INFO "TAXONOMY EXTRACTION STARTED (V2, scenario=${scenario})"
```

- [ ] **Step 3: Convert the finishing lines and emit the final result**

Replace:

```bash
  local claude_output
  # Piped via stdin, not passed as a CLI argument: this prompt embeds the full candidate-enriched worklist
  # JSON and can exceed the kernel's argv size limit (E2BIG) well before it gets near a real token-budget
  # concern — same reasoning as targeted_qa_fix_v2.sh.
  claude_output=$(claude -p --output-format json --permission-mode bypassPermissions --max-turns "$max_turns" <<< "$prompt")
  echo "$claude_output"

  echo "============================"
  echo "TAXONOMY EXTRACTION FINISHED (V2)"
  echo "QUEUE_SIGNAL: $(decide_queue_signal "$claude_output")"
}
```

with:

```bash
  local claude_output
  # Piped via stdin, not passed as a CLI argument: this prompt embeds the full candidate-enriched worklist
  # JSON and can exceed the kernel's argv size limit (E2BIG) well before it gets near a real token-budget
  # concern — same reasoning as targeted_qa_fix_v2.sh.
  claude_output=$(claude -p --output-format json --permission-mode bypassPermissions --max-turns "$max_turns" <<< "$prompt")
  echo "$claude_output"

  log INFO "TAXONOMY EXTRACTION FINISHED (V2)"
  local signal
  signal=$(decide_queue_signal "$claude_output")
  echo "QUEUE_SIGNAL: ${signal}"
  emit_result "$table" "$signal" "Taxonomy extraction v2 finished" "max_turns=${max_turns}"
}
```

- [ ] **Step 4: Syntax-check and verify every `QUEUE_SIGNAL:` line still has a matching `emit_result`**

Run: `bash -n script/niq/headless_taxonomy_v2.sh && echo SYNTAX_OK`
Expected: `SYNTAX_OK`

Run: `grep -c 'QUEUE_SIGNAL:' script/niq/headless_taxonomy_v2.sh; grep -c 'emit_result' script/niq/headless_taxonomy_v2.sh`
Expected: both counts `3` (1 in `decide_queue_signal`'s internal `echo "FAILED"` etc. don't count — this greps the literal `QUEUE_SIGNAL:` string, which appears exactly 3 times: two `NOTHING_TO_DO` early-exits + the final line; `emit_result` also appears exactly 3 times, once per site)

- [ ] **Step 5: Commit**

```bash
git add script/niq/headless_taxonomy_v2.sh
git commit -m "Integrate common.sh logging/emit_result into headless_taxonomy_v2.sh"
```

---

## Task 8: Integrate `common.sh` into `script/niq/targeted_qa_fix_v2.sh`

**Files:**
- Modify: `script/niq/targeted_qa_fix_v2.sh:1-315`

**Interfaces:**
- Consumes: `log`, `emit_result` from Task 1.

- [ ] **Step 1: Source `common.sh` at the top of the file**

Replace:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: ./script/niq/targeted_qa_fix_v2.sh <TABLE> [BLOCK_SIZE] [MAX_TURNS]
```

with:

```bash
#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

# Usage: ./script/niq/targeted_qa_fix_v2.sh <TABLE> [BLOCK_SIZE] [MAX_TURNS]
```

- [ ] **Step 2: Convert `mark_failed_qa` and `run_universe_refresh`'s echoes to `log`**

Replace:

```bash
mark_failed_qa() {
  local table="$1"
  echo "Marking most recent ACTIVE targeted_qa_fix_v2 block for ${table} as FAILED_QA..." >&2
```

with:

```bash
mark_failed_qa() {
  local table="$1"
  log WARN "Marking most recent ACTIVE targeted_qa_fix_v2 block for ${table} as FAILED_QA..."
```

Replace:

```bash
run_universe_refresh() {
  local table="$1"
  echo "Running universe refresh for ${table}..."
```

with:

```bash
run_universe_refresh() {
  local table="$1"
  log INFO "Running universe refresh for ${table}..."
```

- [ ] **Step 3: Convert `main()`'s worklist/start echoes and the NOTHING_TO_DO exit**

Replace:

```bash
  echo "Building candidate-enriched worklist for ${table}..."
  local worklist_json
  worklist_json=$(python3 script/niq/qa_v2_worklist.py --table "$table" --block-size "$block_size")

  if [[ "$worklist_json" == "[]" ]]; then
    echo "No unlabelled/unconfident taxonomy entries for ${table} after fast-lane promotion -- nothing to do."
    echo "QUEUE_SIGNAL: NOTHING_TO_DO"
    exit 0
  fi

  echo "TARGETED QA FIX V2 STARTED (${category_key}, block_size=${block_size}, max_turns=${max_turns})"
  echo "==========================="
```

with:

```bash
  log INFO "Building candidate-enriched worklist for ${table}..."
  local worklist_json
  worklist_json=$(python3 script/niq/qa_v2_worklist.py --table "$table" --block-size "$block_size")

  if [[ "$worklist_json" == "[]" ]]; then
    log INFO "No unlabelled/unconfident taxonomy entries for ${table} after fast-lane promotion -- nothing to do."
    echo "QUEUE_SIGNAL: NOTHING_TO_DO"
    emit_result "$table" "NOTHING_TO_DO" "No unlabelled/unconfident taxonomy entries after fast-lane promotion"
    exit 0
  fi

  log INFO "TARGETED QA FIX V2 STARTED (${category_key}, block_size=${block_size}, max_turns=${max_turns})"
```

- [ ] **Step 4: Convert the no-parseable-result error path**

Replace:

```bash
  if [[ -z "$result_json" ]]; then
    echo "ERROR: claude -p produced no parseable .result field. Raw output:" >&2
    echo "$claude_output" >&2
    mark_failed_qa "$table"
    exit 1
  fi
```

with:

```bash
  if [[ -z "$result_json" ]]; then
    log ERROR "claude -p produced no parseable .result field. Raw output:"
    echo "$claude_output" >&2
    mark_failed_qa "$table"
    emit_result "$table" "FAILED" "claude -p produced no parseable .result field"
    exit 1
  fi
```

- [ ] **Step 5: Convert every branch of the final `case "$decision"` block**

Replace:

```bash
  case "$decision" in
    BLOCKED)
      echo "STATUS: blocked. Claimed block left ACTIVE (nothing written) -- see blockers below."
      echo "$result_json" | jq -r '.blockers[]?' >&2
      echo "QUEUE_SIGNAL: BLOCKED"
      exit 0
      ;;
    NOOP)
      echo "STATUS: complete/partial with rows_created=0 -- nothing to gate or refresh. Block left ACTIVE."
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
      echo "STATUS: rows written -- running independent QA gates via script/niq/qa_report.sh..."
      if ./script/niq/qa_report.sh "$table"; then
        if run_universe_refresh "$table"; then
          echo "============================"
          echo "TARGETED QA FIX V2 FINISHED -- universe refreshed"
          echo "QUEUE_SIGNAL: DONE"
        else
          echo "Universe refresh failed -- marking block FAILED_QA." >&2
          mark_failed_qa "$table"
          echo "QUEUE_SIGNAL: FAILED"
          exit 1
        fi
      else
        echo "QA gates failed -- marking block FAILED_QA, skipping universe refresh." >&2
        mark_failed_qa "$table"
        echo "QUEUE_SIGNAL: FAILED"
        exit 1
      fi
      ;;
  esac
}
```

with:

```bash
  case "$decision" in
    BLOCKED)
      log INFO "STATUS: blocked. Claimed block left ACTIVE (nothing written) -- see blockers below."
      echo "$result_json" | jq -r '.blockers[]?' >&2
      echo "QUEUE_SIGNAL: BLOCKED"
      emit_result "$table" "BLOCKED" "Claimed block left ACTIVE, see blockers"
      exit 0
      ;;
    NOOP)
      log INFO "STATUS: complete/partial with rows_created=0 -- nothing to gate or refresh. Block left ACTIVE."
      echo "QUEUE_SIGNAL: DONE"
      emit_result "$table" "DONE" "complete/partial with rows_created=0, nothing to gate or refresh"
      exit 0
      ;;
    MARK_FAILED)
      log ERROR "STATUS: failed or malformed. Marking block FAILED_QA."
      echo "$result_json" >&2
      mark_failed_qa "$table"
      echo "QUEUE_SIGNAL: FAILED"
      emit_result "$table" "FAILED" "Session status failed or malformed, block marked FAILED_QA"
      exit 1
      ;;
    GATE_AND_REFRESH)
      log INFO "STATUS: rows written -- running independent QA gates via script/niq/qa_report.sh..."
      if ./script/niq/qa_report.sh "$table"; then
        if run_universe_refresh "$table"; then
          log INFO "TARGETED QA FIX V2 FINISHED -- universe refreshed"
          echo "QUEUE_SIGNAL: DONE"
          emit_result "$table" "DONE" "Universe refreshed"
        else
          log ERROR "Universe refresh failed -- marking block FAILED_QA."
          mark_failed_qa "$table"
          echo "QUEUE_SIGNAL: FAILED"
          emit_result "$table" "FAILED" "Universe refresh failed"
          exit 1
        fi
      else
        log ERROR "QA gates failed -- marking block FAILED_QA, skipping universe refresh."
        mark_failed_qa "$table"
        echo "QUEUE_SIGNAL: FAILED"
        emit_result "$table" "FAILED" "QA gates failed, block marked FAILED_QA"
        exit 1
      fi
      ;;
  esac
}
```

- [ ] **Step 6: Syntax-check and verify every `QUEUE_SIGNAL:` line has a matching `emit_result`**

Run: `bash -n script/niq/targeted_qa_fix_v2.sh && echo SYNTAX_OK`
Expected: `SYNTAX_OK`

Run: `grep -c 'QUEUE_SIGNAL:' script/niq/targeted_qa_fix_v2.sh; grep -c 'emit_result' script/niq/targeted_qa_fix_v2.sh`
Expected: both counts `7`

- [ ] **Step 7: Commit**

```bash
git add script/niq/targeted_qa_fix_v2.sh
git commit -m "Integrate common.sh logging/emit_result into targeted_qa_fix_v2.sh"
```

---

## Task 9: Integrate `common.sh` into `script/non_niq/non_niq_qa_v2.sh`

**Files:**
- Modify: `script/non_niq/non_niq_qa_v2.sh:1-686`

**Interfaces:**
- Consumes: `emit_result` from Task 1. `log()` is replaced by the shared one (same signature shape as the file's existing local `log()`, now takes a level as its first arg — every existing call site is updated to match).

This file already has its own `log()` (no level, HH:MM:SS-only) and its own `format_result_summary()` (a rich human-readable dump built from `claude_output`, printed to stdout). Neither is removed — `format_result_summary` already does the "human readable" job Task 5's formatter does for the *other* two scripts; this task only swaps the timestamp/level convention to match the shared one and adds the new structured `emit_result` line.

- [ ] **Step 1: Source `common.sh` and delete the local `log()`**

Replace:

```bash
PROJECT="sincere-hearth-273704"
MEILI_URL="http://34.124.146.29:7700"

# One line per phase transition -- enough to tell (from outside) whether the script is still
# resolving config, waiting on a bq query, or has handed off to the claude subprocess, without
# spamming a line per row/product (that's claude's own transcript, not this wrapper's job).
log() {
  echo "[$(date '+%H:%M:%S')] $*"
}

# Resolves regardless of cwd -- non_niq_helper.py needs google-cloud-bigquery and
# sentence-transformers for real (columns/retrieve), so this must be an interpreter that actually
# has them: this repo's own uv-managed .venv, not bare `python3` off PATH.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PYTHON_BIN="${REPO_ROOT}/.venv/bin/python3"
```

with:

```bash
PROJECT="sincere-hearth-273704"
MEILI_URL="http://34.124.146.29:7700"

# Resolves regardless of cwd -- non_niq_helper.py needs google-cloud-bigquery and
# sentence-transformers for real (columns/retrieve), so this must be an interpreter that actually
# has them: this repo's own uv-managed .venv, not bare `python3` off PATH.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PYTHON_BIN="${REPO_ROOT}/.venv/bin/python3"

# One line per phase transition -- enough to tell (from outside) whether the script is still
# resolving config, waiting on a bq query, or has handed off to the claude subprocess, without
# spamming a line per row/product (that's claude's own transcript, not this wrapper's job). Now
# the shared log() (level + full timestamp, always stderr) instead of a local HH:MM:SS-only copy.
source "${REPO_ROOT}/script/lib/common.sh"
```

- [ ] **Step 2: Update every existing `log "..."` call site to the shared `log LEVEL "..."` shape**

All existing call sites in this file use bare `log "message"` (no level). Replace each with `log INFO "message"` — there are 8 call sites, all inside `main()`:

Replace:

```bash
  log "Resolving config Sheet row for ${dataset}/${platform}/${country}..."
```

with:

```bash
  log INFO "Resolving config Sheet row for ${dataset}/${platform}/${country}..."
```

Replace:

```bash
  log "Config resolved: source_table=${source_table}, qa_table=${qa_table}, dict_table=${dict_table}, filter_table=${filter_table}$( [[ -n "$kategori" ]] && echo ", kategori=${kategori}" )"
```

with:

```bash
  log INFO "Config resolved: source_table=${source_table}, qa_table=${qa_table}, dict_table=${dict_table}, filter_table=${filter_table}$( [[ -n "$kategori" ]] && echo ", kategori=${kategori}" )"
```

Replace:

```bash
  log "Resolving qa/dict column names via BigQuery INFORMATION_SCHEMA..."
```

with:

```bash
  log INFO "Resolving qa/dict column names via BigQuery INFORMATION_SCHEMA..."
```

Replace:

```bash
  log "Columns resolved: qa_pk_col=${qa_pk_col}, dict_identity_col=${dict_identity_col}, dict_typo_col=${dict_typo_col}"
```

with:

```bash
  log INFO "Columns resolved: qa_pk_col=${qa_pk_col}, dict_identity_col=${dict_identity_col}, dict_typo_col=${dict_typo_col}"
```

Replace:

```bash
  log "Querying BigQuery for the latest month on ${source_table}/${platform}..."
```

with:

```bash
  log INFO "Querying BigQuery for the latest month on ${source_table}/${platform}..."
```

Replace:

```bash
  log "Latest month resolved: ${month}"
```

with:

```bash
  log INFO "Latest month resolved: ${month}"
```

Replace:

```bash
  log "Querying BigQuery to materialize the worklist (product_tier=Tier 1, limit=${max_rows})..."
```

with:

```bash
  log INFO "Querying BigQuery to materialize the worklist (product_tier=Tier 1, limit=${max_rows})..."
```

Replace:

```bash
  log "Worklist materialized: ${worklist_count} rows (${dataset}/${platform}/${country}, month=${month})"
```

with:

```bash
  log INFO "Worklist materialized: ${worklist_count} rows (${dataset}/${platform}/${country}, month=${month})"
```

Replace:

```bash
  log "Delegating to claude (max_turns=${max_turns}) -- embeds+retrieves via Meilisearch, then runs the per-product QA loop. No further progress output until it returns."
```

with:

```bash
  log INFO "Delegating to claude (max_turns=${max_turns}) -- embeds+retrieves via Meilisearch, then runs the per-product QA loop. No further progress output until it returns."
```

Replace:

```bash
  log "claude subprocess returned, formatting summary..."
```

with:

```bash
  log INFO "claude subprocess returned, formatting summary..."
```

Replace (the two remaining sites, inside the Sheet write-back block):

```bash
      log "Appending ${rows_created} newly-created dict row(s) to the taxonomy Sheet..."
```

with:

```bash
      log INFO "Appending ${rows_created} newly-created dict row(s) to the taxonomy Sheet..."
```

Replace:

```bash
    else
      log "No taxonomy_url configured for ${dataset} -- skipping Sheet write-back."
    fi
```

with:

```bash
    else
      log INFO "No taxonomy_url configured for ${dataset} -- skipping Sheet write-back."
    fi
```

- [ ] **Step 3: Add `emit_result` to the four early `FAILED` exits**

Replace:

```bash
  if [[ -z "$category_json" ]]; then
    echo "No active config Sheet row for dataset=${dataset} platform=${platform} country=${country}" >&2
    echo "QUEUE_SIGNAL: FAILED"
    exit 1
  fi
```

with:

```bash
  if [[ -z "$category_json" ]]; then
    echo "No active config Sheet row for dataset=${dataset} platform=${platform} country=${country}" >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "${dataset}:${platform}" "FAILED" "No active config Sheet row for country=${country}"
    exit 1
  fi
```

Replace:

```bash
    if [[ "${t#*=}" == "-" || "${t#*=}" == "null" || -z "${t#*=}" ]]; then
      echo "Config Sheet row for dataset=${dataset} platform=${platform} has unconfigured ${t%%=*} ('${t#*=}') -- cannot run QA v2." >&2
      echo "QUEUE_SIGNAL: FAILED"
      exit 1
    fi
```

with:

```bash
    if [[ "${t#*=}" == "-" || "${t#*=}" == "null" || -z "${t#*=}" ]]; then
      echo "Config Sheet row for dataset=${dataset} platform=${platform} has unconfigured ${t%%=*} ('${t#*=}') -- cannot run QA v2." >&2
      echo "QUEUE_SIGNAL: FAILED"
      emit_result "${dataset}:${platform}" "FAILED" "Unconfigured ${t%%=*} in config Sheet row"
      exit 1
    fi
```

Replace:

```bash
  if ! month=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "$(default_month_query "$source_table" "$platform")" | tail -1); then
    echo "bq query failed while resolving the latest month for ${source_table}/${platform} -- see bq's error above." >&2
    echo "QUEUE_SIGNAL: FAILED"
    exit 1
  fi
```

with:

```bash
  if ! month=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "$(default_month_query "$source_table" "$platform")" | tail -1); then
    echo "bq query failed while resolving the latest month for ${source_table}/${platform} -- see bq's error above." >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "${dataset}:${platform}" "FAILED" "bq query failed resolving latest month for ${source_table}/${platform}"
    exit 1
  fi
```

Replace:

```bash
  if ! bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=json --max_rows=1000000 \
    "$query" | jq -c '.[]' > "$worklist_file"; then
    echo "bq query failed while materializing the worklist for ${dataset}/${platform}/${country} (v2) -- see bq's error above." >&2
    echo "QUEUE_SIGNAL: FAILED"
    exit 1
  fi
```

with:

```bash
  if ! bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=json --max_rows=1000000 \
    "$query" | jq -c '.[]' > "$worklist_file"; then
    echo "bq query failed while materializing the worklist for ${dataset}/${platform}/${country} (v2) -- see bq's error above." >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "${dataset}:${platform}" "FAILED" "bq query failed materializing worklist for ${dataset}/${platform}/${country}"
    exit 1
  fi
```

- [ ] **Step 4: Add `emit_result` to the `NOTHING_TO_DO` exit and the final `QUEUE_SIGNAL` line**

Replace:

```bash
  if [[ "$worklist_count" == "0" ]]; then
    echo "No in-scope worklist for ${dataset}/${platform}/${country}/${month} (v2, product_tier=Tier 1) -- nothing to do."
    rm -f "$worklist_file"
    echo "QUEUE_SIGNAL: NOTHING_TO_DO"
    exit 0
  fi
```

with:

```bash
  if [[ "$worklist_count" == "0" ]]; then
    echo "No in-scope worklist for ${dataset}/${platform}/${country}/${month} (v2, product_tier=Tier 1) -- nothing to do."
    rm -f "$worklist_file"
    echo "QUEUE_SIGNAL: NOTHING_TO_DO"
    emit_result "${dataset}:${platform}" "NOTHING_TO_DO" "No in-scope worklist for ${dataset}/${platform}/${country}/${month}"
    exit 0
  fi
```

Replace:

```bash
  echo "QUEUE_SIGNAL: $(decide_queue_signal "$claude_output")"
}
```

with:

```bash
  local signal
  signal=$(decide_queue_signal "$claude_output")
  echo "QUEUE_SIGNAL: ${signal}"
  emit_result "${dataset}:${platform}" "$signal" "QA v2 session finished" "rows_created=$(extract_rows_created "$claude_output")"
}
```

- [ ] **Step 5: Syntax-check and verify every `QUEUE_SIGNAL:` line has a matching `emit_result`, and that the local `log()` definition is gone**

Run: `bash -n script/non_niq/non_niq_qa_v2.sh && echo SYNTAX_OK`
Expected: `SYNTAX_OK`

Run: `grep -c 'QUEUE_SIGNAL:' script/non_niq/non_niq_qa_v2.sh; grep -c 'emit_result' script/non_niq/non_niq_qa_v2.sh`
Expected: both counts `6`

Run: `grep -c '^log() {' script/non_niq/non_niq_qa_v2.sh`
Expected: `0` (the local definition is gone — `log` now comes from `common.sh`)

- [ ] **Step 6: Commit**

```bash
git add script/non_niq/non_niq_qa_v2.sh
git commit -m "Integrate common.sh logging/emit_result into non_niq_qa_v2.sh, drop local log()"
```

---

## Self-Review Notes

- **Spec coverage:** "universal JSON output" → Task 1 (`emit_result`) + Tasks 7-9 (wired into all 3 orchestrators). "comprehensive logging with timestamp" → Task 1 (`log`) + Tasks 7-9. "error handling" → Task 1 (`die`, available though not force-used where existing `mark_failed_qa`/exit-code patterns already work — no behavior to fix, only a shared primitive to offer). "postgres queue wrapper script" → Task 2 (`queue_common.sh`) + Tasks 3-4 (both workers refactored onto it) + Task 6 (`queue_ctl.sh show` consumes the resulting structured `last_result`).
- **Placeholder scan:** none — every step has literal file contents or exact replace blocks.
- **Type/interface consistency:** `emit_result(table, signal, message, [k=v...])` signature is identical across Tasks 1, 7, 8, 9. `queue_main_loop(script_type_filter, worker_id, run_task_fn)` and the `run_task(id, table_name, script_type, month, max_turns, block_size, loop_count)` calling convention are identical across Tasks 2, 3, 4.
- **`die()` is defined but not force-integrated:** every current failure path in the 3 orchestrators already does its own cleanup before exiting (`mark_failed_qa`, `rm -f "$worklist_file"`, specific `QUEUE_SIGNAL:` values) — swapping those to a generic `die()` would either lose that cleanup or require restating it inside `die()` itself, which is scope creep beyond "add logging/JSON/error primitives." `die()` remains available in `common.sh` for genuinely unrecoverable cases with no cleanup, matching the spec's "convenience wrapper... not a new trap/signal mechanism."
