# Running the non-NIQ QA scripts

Practical "how do I run this" reference for the four scripts below, with every CLI arg and env
var each one reads, and worked examples. For the *design* (decision tree, confidence loop, _meta
conventions), see
[`docs/superpowers/specs/2026-08-06-non-niq-agentic-qa-design.md`](superpowers/specs/2026-08-06-non-niq-agentic-qa-design.md).
For first-time machine setup (installing `bq`/`claude`/`.venv`, auth), see
[`docs/how-to-deploy-non-niq-qa.md`](how-to-deploy-non-niq-qa.md).

All four assume you're in the repo root with `.venv` built (`uv sync`) and `bq`/`claude`
authenticated.

| Script | Scope |
|---|---|
| `script/non_niq/non_niq_qa_v2.sh` | Generic, config-Sheet-driven QA for any dataset/platform/country |
| `script/non_niq/eiger_qa.sh` | Dedicated to `eiger` (fixed enumerated taxonomy tree, no dict table) |
| `script/non_niq/susubayi_qa.sh` | Dedicated to `susubayi` (Blibli sellout-feed union, Formula-Milk merchant allowlist, Official Store force-include) |
| `script/non_niq/queue_worker.sh` | Polls the shared Postgres task queue and runs `non_niq_qa_v2.sh` (or a swapped-in override) unattended |

---

## 1. `non_niq_qa_v2.sh`

```
script/non_niq/non_niq_qa_v2.sh <DATASET> <PLATFORM> [COUNTRY] [MAX_TURNS] [MAX_ROWS] [KATEGORI]
```

### Args

| # | Arg | Required | Default | Notes |
|---|---|---|---|---|
| 1 | `DATASET` | yes | — | e.g. `cookiesbiscuit` |
| 2 | `PLATFORM` | yes | — | e.g. `shopee`; `tokopedia` also covers the `'Tokopedia \| Shop'` channel |
| 3 | `COUNTRY` | no | `ID` | uppercased before use |
| 4 | `MAX_TURNS` | no | `500` | passed to `claude -p --max-turns` |
| 5 | `MAX_ROWS` | no | `300` | worklist row cap |
| 6 | `KATEGORI` | no | `""` | exact-match filter on `source_table`'s own `kategori` column — only some datasets have it |

### Env vars

| Var | Default | Effect |
|---|---|---|
| `MONTHLY_REVERIFY` | unset (off) | Set (e.g. `=1`) to force re-review of a product_id whose `sku_name`/`kategori` changed since its own prior-month row (merchant reused the product_id for a different listing) |
| `AGENT_HARNESS` | `claude` | Selects the coding-agent CLI. Checked for availability (`command -v`) before any BigQuery work — unknown name or missing binary exits with `QUEUE_SIGNAL: FAILED`. **Only `claude` actually runs today** — `codex`/`pi`/`omp`/`opencode` are recognized names but error as "not wired up" even if the binary is present, since the script's output parsing is written against `claude -p`'s JSON schema specifically |
| `LEASE_TIMEOUT_HOURS` | `4` | Not specific to this script (shared with `queue_worker.sh`'s stale-lease reclaim) — used here only to cap the claude-session-limit retry sleep at half the lease window before giving up `BLOCKED` |

### Examples

```bash
# Basic run, all defaults (COUNTRY=ID, MAX_TURNS=500, MAX_ROWS=300)
script/non_niq/non_niq_qa_v2.sh cookiesbiscuit shopee

# Different country
script/non_niq/non_niq_qa_v2.sh lighting shopee TH

# Custom turn/row budget (e.g. a small smoke test before trusting a full run)
script/non_niq/non_niq_qa_v2.sh cookiesbiscuit shopee ID 50 20

# KATEGORI sub-scope (only for datasets whose source_table has a kategori column)
script/non_niq/non_niq_qa_v2.sh lighting shopee ID 300 300 "Connected Light"

# MONTHLY_REVERIFY: force re-review of listings that changed under the same product_id
MONTHLY_REVERIFY=1 script/non_niq/non_niq_qa_v2.sh lighting shopee ID 300 100

# AGENT_HARNESS: explicit default, equivalent to leaving it unset
AGENT_HARNESS=claude script/non_niq/non_niq_qa_v2.sh cookiesbiscuit shopee

# AGENT_HARNESS: an unavailable/unsupported harness fails fast, before any BigQuery work --
# useful to confirm the gate itself works, or when scripting around it
AGENT_HARNESS=codex script/non_niq/non_niq_qa_v2.sh cookiesbiscuit shopee
# -> "AGENT_HARNESS='codex' found on PATH, but its invocation/output-parsing isn't implemented
#     in this script yet -- only 'claude' is wired up."
#    QUEUE_SIGNAL: FAILED

# Combine an env var with positional args
MONTHLY_REVERIFY=1 AGENT_HARNESS=claude script/non_niq/non_niq_qa_v2.sh lighting shopee ID 300 100
```

---

## 2. `eiger_qa.sh`

Dedicated script, not a config variant of `non_niq_qa_v2.sh` — eiger has no free-text taxonomy
dict table, so it doesn't take a `DATASET` arg (always `eiger`) and reads no custom env vars.

```
script/non_niq/eiger_qa.sh <PLATFORM> [COUNTRY] [MAX_TURNS] [MAX_ROWS]
```

| # | Arg | Required | Default |
|---|---|---|---|
| 1 | `PLATFORM` | yes | — |
| 2 | `COUNTRY` | no | `ID` |
| 3 | `MAX_TURNS` | no | `300` |
| 4 | `MAX_ROWS` | no | `300` |

No env vars beyond what every script implicitly relies on (`bq`/`claude` auth already set up).

### Examples

```bash
# Basic run, all defaults
script/non_niq/eiger_qa.sh shopee

# Different platform + country + explicit budget
script/non_niq/eiger_qa.sh tokopedia ID 300 300
```

---

## 3. `susubayi_qa.sh`

Dedicated script for `susubayi` (Formula Milk). Like `eiger_qa.sh`, no `DATASET` arg (always
`susubayi`) and no custom env vars — its three category-specific behaviors (Blibli sellout-feed
union, Formula-Milk merchant-allowlist force-include, Official Store force-include) are hardcoded,
not configurable via args or env vars.

```
script/non_niq/susubayi_qa.sh <PLATFORM> [COUNTRY] [MAX_TURNS] [MAX_ROWS]
```

| # | Arg | Required | Default |
|---|---|---|---|
| 1 | `PLATFORM` | yes | — |
| 2 | `COUNTRY` | no | `ID` |
| 3 | `MAX_TURNS` | no | `500` |
| 4 | `MAX_ROWS` | no | `300` |

### Examples

```bash
# Basic run
script/non_niq/susubayi_qa.sh shopee

# Blibli specifically -- triggers the sellout-feed UNION described in the script's header comment
script/non_niq/susubayi_qa.sh blibli ID 500 300
```

---

## 4. `queue_worker.sh`

Long-running poller: claims `script_type='non_niq_qa'` rows from the shared
`p4ct2g2urhzcfnz.task_queue` Postgres table and runs `non_niq_qa_v2.sh` for each, up to
`loop_count` times per task. Takes **no CLI args** — everything is env vars, loaded via
`script/load_env.sh` (which sources `.env` if present).

```
script/non_niq/queue_worker.sh
```

### Env vars

| Var | Default | Required | Effect |
|---|---|---|---|
| `QUEUE_DATABASE_URL` | — | **yes** | Postgres connection string; the script refuses to start without it |
| `QUEUE_SCHEMA` | `public` | no | Schema `task_queue` lives in (production uses `p4ct2g2urhzcfnz`) |
| `POLL_INTERVAL_SECONDS` | `15` | no | Idle-loop sleep between claim attempts |
| `LEASE_TIMEOUT_HOURS` | `4` | no | How long a claimed row can go without a heartbeat before another worker reclaims it |
| `NON_NIQ_QA_SCRIPT` | `./script/non_niq/non_niq_qa_v2.sh` | no | Override which script gets invoked. **Only safe for a script sharing `non_niq_qa_v2.sh`'s exact positional signature** (`dataset platform country max_turns max_rows kategori`) — `eiger_qa.sh`/`susubayi_qa.sh` take a different, shorter arg list (no `dataset`/`kategori`) and will silently misalign if pointed at from here |

### Examples

```bash
# Standard run against the production queue
source script/load_env.sh   # loads .env: QUEUE_DATABASE_URL, QUEUE_SCHEMA, etc.
script/non_niq/queue_worker.sh

# One-off override without touching .env
QUEUE_DATABASE_URL=postgres://user:pass@host:5432/db QUEUE_SCHEMA=p4ct2g2urhzcfnz \
  script/non_niq/queue_worker.sh

# Poll more aggressively (e.g. after bulk-submitting many tasks and wanting quick pickup)
POLL_INTERVAL_SECONDS=5 script/non_niq/queue_worker.sh

# Wider lease window for tasks with a large MAX_TURNS budget expected to run for hours
LEASE_TIMEOUT_HOURS=8 script/non_niq/queue_worker.sh

# Point at a fork/staging copy of the script instead of the checked-out one
NON_NIQ_QA_SCRIPT=/path/to/non_niq_qa_v2.sh script/non_niq/queue_worker.sh

# Running it unattended (tmux)
tmux new -s non-niq-worker -d 'source script/load_env.sh && script/non_niq/queue_worker.sh'

# Running it unattended (nohup)
source script/load_env.sh
nohup script/non_niq/queue_worker.sh > /tmp/non_niq_queue_worker.log 2>&1 &
```

### Getting a task into the queue first

`queue_worker.sh` only runs a task once one exists with `status='queued'`. There's no
`queue_ctl.sh` for `non_niq_qa` (unlike the general `script/queue_worker.sh`) — submit directly
via SQL, `table_name` encoded as `"{dataset}:{platform}"` or `"{dataset}:{platform}:{country}"`:

```bash
source script/load_env.sh
QUEUE_TABLE="${QUEUE_SCHEMA:-public}.task_queue"
queue_psql "INSERT INTO ${QUEUE_TABLE}
  (table_name, script_type, max_turns, block_size, loop_count, priority, extra_args, status, submitted_at, iterations_run)
  VALUES ('cookiesbiscuit:shopee:ID', 'non_niq_qa', 500, 300, 3, 100, NULL, 'queued', now(), 0);"

# with a kategori sub-scope (extra_args.kategori)
queue_psql "INSERT INTO ${QUEUE_TABLE}
  (table_name, script_type, max_turns, block_size, loop_count, priority, extra_args, status, submitted_at, iterations_run)
  VALUES ('lighting:shopee:ID', 'non_niq_qa', 300, 300, 3, 100, json_build_object('kategori', 'Connected Light'), 'queued', now(), 0);"
```

See [`docs/non-niq-queue-submitter-handoff.md`](non-niq-queue-submitter-handoff.md) for the full
column mapping if you're building a submitter UI instead of inserting by hand.

`queue_worker.sh` itself has no `AGENT_HARNESS`/`MONTHLY_REVERIFY` passthrough — it always invokes
`non_niq_qa_v2.sh` (or `NON_NIQ_QA_SCRIPT`'s override) with its own default env, so set those in
the worker process's environment (e.g. its systemd unit's `Environment=`) if you need them applied
to every task it runs, not per-task.

---

## Quick troubleshooting

| Symptom | Cause |
|---|---|
| `AGENT_HARNESS='X' unavailable or unsupported` | Unknown harness name, missing binary, or a recognized-but-unwired harness (anything but `claude` today) — see § 1's `AGENT_HARNESS` row |
| `No active config Sheet row for dataset=... platform=... country=...` | The dataset/platform/country combo isn't configured (or active) in the categories config Sheet |
| `Config Sheet row ... has unconfigured <field>` | That Sheet row exists but one of `source_table`/`qa_table`/`dict_table`/`filter_table` is `-`/empty |
| `QUEUE_DATABASE_URL must be set` (queue_worker.sh) | `.env` missing or not sourced — `cp .env.example .env`, fill it in, `source script/load_env.sh` |
| Task in `queued` never gets picked up | No worker running, or `table_name`'s dataset/platform/country already has a `running` row (one-task-per-table lock) |
