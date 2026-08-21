# Orchestrator script universalization — design

Date: 2026-08-21

## Problem

Three bash orchestrator scripts drive `claude -p` agentic sessions against
BigQuery and each grew its own conventions independently:

| Script | Logging | Error handling | Final result |
|---|---|---|---|
| `script/niq/headless_taxonomy_v2.sh` | none | bare `echo ... >&2` | `echo "QUEUE_SIGNAL: X"` only |
| `script/niq/targeted_qa_fix_v2.sh` | none | bare `echo ... >&2` | `echo "QUEUE_SIGNAL: X"` only |
| `script/non_niq/non_niq_qa_v2.sh` | `log()` with `HH:MM:SS` only | bare `echo ... >&2` | `echo "QUEUE_SIGNAL: X"` only |

Two queue workers poll postgres and drive these scripts, and are ~90%
byte-identical:

- `script/niq/queue_worker.sh`
- `script/non_niq/queue_worker.sh`

Both duplicate `parse_queue_signal`, `is_duplicate_key_error`,
`queue_signal_to_status`, `should_stop_looping`, `heartbeat`, `_sql_quote`,
`persist_final_status`, `claim_next_task`, `reclaim_stale_leases` almost
verbatim — `non_niq`'s versions differ only by an added
`script_type='non_niq_qa'` filter.

`persist_final_status` stores the *entire raw stdout blob* of a run into
postgres's `last_result` column as `{"raw_output": "<everything>"}` — there is
no structured, greppable/renderable summary of what a run actually did.

## Scope

In scope: the 3 orchestrators above + both `queue_worker.sh`.

Out of scope: V1 scripts (`headless_taxonomy.sh`, `targeted_qa_fix.sh`,
`non_niq_qa.sh`) and the `custom_*` variants — existing repo convention is
that V1 stays untouched when a V2 sibling is added
(`headless_taxonomy_v2.sh`'s own header comment states this explicitly).
`queue_ctl.sh` is touched only to add a `show` subcommand that pipes a
task's `last_result` through the new formatter.

## Design

### 1. `script/lib/common.sh`

Sourced by all 3 orchestrators (not the queue workers — they get
`queue_common.sh` below, which sources this in turn).

- `log() { local level="$1"; shift; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*" >&2; }`
  — always stderr, so stdout stays reserved for the `QUEUE_SIGNAL:` line and
  the new JSON result line (existing convention already puts errors on
  stderr; this just gives all 3 scripts one shared, timestamped `log()`
  instead of `non_niq_qa_v2.sh`'s local one-off and the other two having
  none).
- `die() { log ERROR "$*"; exit 1; }` — one call site instead of the
  `echo ... >&2; echo "QUEUE_SIGNAL: FAILED"; exit` copies scattered through
  all three scripts today. `die` does NOT print `QUEUE_SIGNAL: FAILED` itself
  — callers that need that signal keep printing it explicitly, same as today,
  since some failure paths intentionally emit `BLOCKED` or `NOTHING_TO_DO`
  instead of `FAILED`.
- `emit_result() { local status="$1" table="$2"; shift 2; ...}` — builds one
  `jq -n` JSON object and prints it to stdout as the LAST line of a run:
  `{"timestamp": "...", "status": "...", "table": "...", "signal": "...",
  "message": "..."}`. Additional `key=value` args become extra JSON fields
  (e.g. `iterations=3`). Called immediately after the existing
  `echo "QUEUE_SIGNAL: X"` line — does not replace it, queue workers keep
  grepping `QUEUE_SIGNAL:` exactly as today (confirmed additive-only per
  design decision below).

### 2. `script/lib/queue_common.sh`

The postgres queue wrapper. Sourced by both `queue_worker.sh`, which in turn
sources `script/load_env.sh` for `queue_psql()` (unchanged, still the single
point of truth for the connection string).

Extracted, now-shared functions: `parse_queue_signal`,
`is_duplicate_key_error`, `queue_signal_to_status`, `should_stop_looping`,
`heartbeat`, `_sql_quote`, `persist_final_status`, `claim_next_task`,
`reclaim_stale_leases`.

`claim_next_task` and `reclaim_stale_leases` take an optional `script_type`
filter argument (empty string = unscoped, matches today's `niq` behavior;
`'non_niq_qa'` = scoped, matches today's `non_niq` behavior) — this is the one
real behavioral difference between the two workers today, so it becomes a
parameter instead of duplicated SQL.

`persist_final_status` changes what it stores: instead of
`printf '%s' "$output" | jq -Rs '{raw_output: .}'`, it takes the JSON line
`emit_result` printed (the last line of `$output`) and stores that directly
as `last_result` — falling back to the old `{raw_output: ...}` wrapping only
if no valid JSON line is found (defensive: a run that crashes before
reaching its `emit_result` call still gets *something* stored, not a
DB write failure).

Each `queue_worker.sh` shrinks to: source `queue_common.sh`, define its own
`run_task`/dispatch function (the genuinely different part — which
underlying script to invoke and how to parse its args from `table_name`),
and call a shared `queue_main_loop <script_type_filter> <worker_id_prefix>`.

### 3. `script/lib/format_result.py`

Stdlib-only (`json`, `sys`, `argparse`) — no new dependency, run via the
existing `${REPO_ROOT}/.venv/bin/python3` convention.

Reads one JSON object (the `emit_result` shape) from stdin, prints a
human-readable block: table, status, signal, timestamp, message, plus any
extra fields present. Used two ways:

- `queue_ctl.sh show <task_id>` (new subcommand) — fetches `last_result` for
  a task and pipes it through the formatter, so a human checking on a queued
  run sees a readable summary instead of a raw JSON blob or a wall of
  captured stdout.
- Ad hoc: `./script/niq/headless_taxonomy_v2.sh ... | tail -1 | .venv/bin/python3 script/lib/format_result.py`
  for a human running a script directly at a terminal.

## Data flow (after)

```
orchestrator script
  ├─ log() -> stderr, timestamped, all 3 scripts consistent
  ├─ echo "QUEUE_SIGNAL: X"   -> stdout, UNCHANGED, queue workers still grep this
  └─ emit_result ...          -> stdout, LAST line, structured JSON

queue_worker.sh
  ├─ captures full stdout+stderr (unchanged)
  ├─ parse_queue_signal(): greps QUEUE_SIGNAL: X (unchanged, from queue_common.sh)
  └─ persist_final_status(): stores the emit_result JSON line as last_result
       (falls back to {raw_output: ...} if none found)

queue_ctl.sh show <id>
  └─ fetches last_result, pipes through format_result.py -> human-readable
```

## Error handling

No new error-handling mechanism beyond what's already in place
(`set -euo pipefail` in every script, extensive existing defensive comments
around `set -e` pitfalls in the queue workers). `die()` in `common.sh` is a
convenience wrapper over the existing `log ...; exit 1` pattern, not a new
trap/signal mechanism — scope stays to what's asked, not a rewrite of the
scripts' actual control flow.

## Testing

Per-lib self-check (`ponytail` bar — smallest thing that fails if the logic
breaks, no framework):

- `script/lib/common.sh`: a `demo()`/assert block (run via
  `bash script/lib/common.sh --self-test` or similar) verifying `emit_result`
  produces valid JSON with the expected keys.
- `script/lib/queue_common.sh`: assert block verifying `claim_next_task`'s
  and `reclaim_stale_leases`'s generated SQL differs correctly with/without a
  `script_type` filter (pure string-building check, no live DB needed —
  matches the existing pure-function testing style already used for
  `build_submit_sql` etc. in `queue_ctl.sh`).
- `script/lib/format_result.py`: `python3 script/lib/format_result.py --self-test`
  or a `test_format_result.py` — feed it a known JSON object, assert the
  printed output contains the expected fields.

No changes to the 3 orchestrators' or queue workers' existing behavior are
expected to require new integration tests — this is additive (new log
lines, one new trailing JSON line, DRY'd-up queue logic with identical
resulting SQL) and existing `QUEUE_SIGNAL:` control flow is untouched.

## Open questions / decisions already made

- **JSON is additive, not a replacement for `QUEUE_SIGNAL:`.** Decided
  2026-08-21: keep the grep-based signal contract as-is (battle-tested,
  heavily commented, zero blast radius on queue control flow); JSON is a new
  final summary line only.
