# Running the Task Queue Worker

A practical, step-by-step guide to submitting tasks and running `script/queue_worker.sh` /
`script/queue_ctl.sh`. For the design rationale (why Postgres, why the schema-qualification rule,
why the lease/heartbeat mechanism), see
[`docs/superpowers/specs/2026-07-27-task-queue-design.md`](superpowers/specs/2026-07-27-task-queue-design.md).
This guide is the "how do I actually run it" companion.

---

## 1. One-time setup

**1a. `psql`** must be on `$PATH`. If you don't want to install it:

```bash
mkdir -p /tmp/psql-shim
cat > /tmp/psql-shim/psql <<'EOF'
#!/usr/bin/env bash
exec docker run --rm -i postgres:16 psql "$@"
EOF
chmod +x /tmp/psql-shim/psql
export PATH="/tmp/psql-shim:$PATH"
```

**1b. `.env`** — copy the template and fill in real values:

```bash
cp .env.example .env
```

```bash
# .env
QUEUE_DATABASE_URL=postgres://user:password@host:port/dbname
QUEUE_SCHEMA=p4ct2g2urhzcfnz   # this deployment's real schema -- leave unset for "public"
POLL_INTERVAL_SECONDS=30       # how often an idle worker checks for new work
LEASE_TIMEOUT_HOURS=4          # see § 6 below before raising task-level max-turns
```

`.env` is gitignored — it holds a live credential, never commit it.

**1c. The migration** (only needs running once per database, and has almost certainly already been
run for the shared deployment — check with `script/queue_ctl.sh list` first; if it errors with
"relation does not exist" or "index does not exist," apply it):

```bash
source script/load_env.sh
QUEUE_TABLE="${QUEUE_SCHEMA:-public}.task_queue"
queue_psql "CREATE UNIQUE INDEX IF NOT EXISTS one_running_task_per_table ON ${QUEUE_TABLE} (table_name) WHERE status = 'running';"
```

**1d. `bq`/`gcloud` auth, if you don't want to (or can't) do an interactive `gcloud auth login`.**

The worker's Postgres access (above) is only half the picture — the underlying scripts it runs
(`headless_taxonomy.sh`, `targeted_qa_fix.sh`) also need `bq`/`gcloud` authenticated against BigQuery
(per `docs/headless-runbook.md`'s Prerequisites: project `sincere-hearth-273704`, BigQuery Data Editor
on `magpie_reference` and `magpie`). `gcloud auth login` needs an interactive browser, which doesn't
exist on a headless machine (a systemd service, a CI runner, a remote box you're SSH'd into) — use a
service account key instead.

*Getting the key:* this repo's existing convention (see `CLAUDE.md`'s Environment Setup) uses the
service account `openclaw@magpie-openclaw.iam.gserviceaccount.com`. Get a JSON key for it from
whoever administers that service account (Google Cloud Console → IAM & Admin → Service Accounts → your
account → Keys → Add Key, or ask a teammate who already has one) — don't create a new service account
just for this unless you have a specific reason to.

*Activating it* — two mechanisms, and you generally want both, since different tools resolve
credentials differently:

```bash
# 1. Activates the key for the gcloud CLI itself (and everything that shares its config, incl. `bq`
#    and any nested `bq`/`gcloud` calls a `claude -p` session makes as its own tool use) --
#    persists in ~/.config/gcloud until you switch or revoke it, so this is a one-time step per host.
gcloud auth activate-service-account openclaw@magpie-openclaw.iam.gserviceaccount.com \
  --key-file=/path/to/your/key.json \
  --project=sincere-hearth-273704

# 2. Export this too -- some tools (Google client libraries, not the gcloud/bq CLI itself) resolve
#    credentials via Application Default Credentials (ADC) and look for this env var specifically,
#    ignoring step 1's gcloud config entirely. Put it in .env (loaded by script/load_env.sh, same as
#    the Postgres vars) or your systemd unit's EnvironmentFile so it's set for the whole worker
#    process tree, not just one shell.
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/your/key.json
```

*Verify it worked:*

```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=csv "SELECT 1"
```

If that returns `1` instead of a permission/auth error, you're set.

*Security:* treat the key file exactly like `.env` — `chmod 600` it, never commit it, don't put it
somewhere world-readable. If a key is ever exposed, revoke it from the Cloud Console (Service Accounts
→ Keys → Delete) and mint a new one; `gcloud auth revoke openclaw@magpie-openclaw.iam.gserviceaccount.com`
locally removes it from your gcloud config, but doesn't invalidate the key itself — that only happens
server-side.

---

## 2. Submit a task

```bash
source script/load_env.sh
script/queue_ctl.sh submit shopee_th_shampoo headless_taxonomy --priority 200
```

Full flag reference:

```
script/queue_ctl.sh submit <table> <headless_taxonomy|targeted_qa_fix> \
    [--month YYYY-MM] [--max-turns N] [--block-size N] [--loop-count N] [--priority N]
```

| Flag | Applies to | Default | Notes |
|---|---|---|---|
| `--month` | `headless_taxonomy` only | live-latest | Explicit `YYYY-MM` instead of resolving the newest month automatically. |
| `--max-turns` | both | the underlying script's own default | Raise for a category with a large gap. |
| `--block-size` | `targeted_qa_fix` only | 200 | Ignored (stored but unused) if `script_type=headless_taxonomy`. |
| `--loop-count` | both | 3 | **See the warning below before trusting the default.** |
| `--priority` | both | 100 | Higher number = runs first. |

### `--loop-count`: read this before submitting a `targeted_qa_fix` task

- `headless_taxonomy` and `targeted_qa_fix` **auto-discovery mode** (the default — no hand-written
  brief exists yet for the category) can tell for themselves when they're out of work. `--loop-count 3`
  is safe; the worker stops early once the category's live gap/worklist actually hits zero.
- `targeted_qa_fix` **brief mode** (the category's doc already has a filled-in `## Targeted QA Fix
  Brief` section) **cannot detect completion on its own** and will simply re-run the same brief
  `loop_count` times. Use `--loop-count 1` for these unless you specifically know the brief needs
  multiple passes.

If you're not sure which mode a category is in: `grep -A2 "^## Targeted QA Fix Brief"
docs/categories/<table>.md` — a real `**Verdict:**` line (not the `_TEMPLATE.md` placeholder) means
brief mode.

---

## 3. Run a worker

```bash
source script/load_env.sh
script/queue_worker.sh
```

This is a **long-running foreground process** — it polls forever (`Ctrl+C` to stop). Each cycle:

1. Reclaims any task whose lease has gone stale (see § 6).
2. Claims the highest-priority `queued` task for a table no other worker currently holds.
3. If nothing's claimable, sleeps `POLL_INTERVAL_SECONDS` and checks again.
4. Otherwise runs the appropriate script (`headless_taxonomy.sh` or `targeted_qa_fix.sh`) up to
   `loop_count` times, stopping early if the script's own live pre-check finds nothing left to do.
5. Persists the final `status`/`iterations_run`/`last_result`, then goes back to step 1.

### Running it unattended

Pick whichever process-management tool you're already using. A few common options:

**tmux** (simplest for a single ad-hoc worker on a machine you're logged into):
```bash
tmux new -s queue-worker -d 'source script/load_env.sh && script/queue_worker.sh'
tmux attach -t queue-worker   # to watch it
```

**nohup:**
```bash
source script/load_env.sh
nohup script/queue_worker.sh > /tmp/queue_worker.log 2>&1 &
```

**systemd** (for a persistent service on a dedicated machine) — a minimal unit:
```ini
# /etc/systemd/system/queue-worker.service
[Unit]
Description=Task queue worker

[Service]
WorkingDirectory=/path/to/product-taxonomy-extraction
EnvironmentFile=/path/to/product-taxonomy-extraction/.env
ExecStart=/path/to/product-taxonomy-extraction/script/queue_worker.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
```
`queue_worker.sh` reads its own `.env` via `script/load_env.sh` regardless of how it's launched, so a
clean systemd environment works correctly — you don't need `EnvironmentFile` for it to find `.env`,
though it doesn't hurt to have it for visibility in `systemctl status`.

### Running multiple workers

Just start `script/queue_worker.sh` more than once (any of the methods above, repeated). Two workers
will **never** claim the same `table_name` at once — that's enforced at the database level (a unique
index), not by coordination between the worker processes — so it's always safe to add more workers to
process several categories in parallel.

---

## 4. Check on the queue

```bash
source script/load_env.sh
script/queue_ctl.sh list                    # everything, sorted by status/priority
script/queue_ctl.sh list --status queued    # just what's waiting
script/queue_ctl.sh list --status running   # what's actively being worked
script/queue_ctl.sh list --status failed    # what needs attention
```

Columns: `id, table_name, script_type, status, priority, iterations_run, loop_count, submitted_at`.
`iterations_run / loop_count` tells you how far into its loop budget a task got before stopping.

For the full detail on a specific task (including `last_result`, the raw output of its last run):

```bash
QUEUE_TABLE="${QUEUE_SCHEMA:-public}.task_queue"
queue_psql "SELECT * FROM ${QUEUE_TABLE} WHERE id = <id>;"
```

---

## 5. Reprioritize or cancel

Both only work while a task is still `queued` — once a worker has claimed it, neither command has
any effect (and will tell you so).

```bash
script/queue_ctl.sh priority <id> 999   # bump to the front of the line
script/queue_ctl.sh cancel <id>         # remove from the queue
```

**Never cancel or edit a row through NocoDB's own grid UI**, if you have access to it. NocoDB
soft-deletes (flips its own `__nc_deleted` flag) without touching `status` — a row "deleted" that way
still reads `status='queued'` and a worker will still claim and run it. Always use `queue_ctl.sh
cancel`.

---

## 6. Tuning `LEASE_TIMEOUT_HOURS` for large tasks

A worker sends a heartbeat only between loop iterations, not while a single `claude -p` session is
actually running. If one iteration's `--max-turns` is large enough that a single run genuinely takes
longer than `LEASE_TIMEOUT_HOURS` (default 4), another worker can decide the lease is stale and
reclaim the row — resulting in two workers processing the same table at once.

**Rule of thumb:** if you submit a task with `--max-turns` large enough that you'd expect a single
run to take several hours (a first-run/full-rebuild on a big category is the usual case), raise
`LEASE_TIMEOUT_HOURS` in `.env` to comfortably exceed that, before starting the worker.

---

## 7. Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `psql: command not found` | See § 1a — install it or use the Docker shim. |
| A task fails immediately with a `bq`/BigQuery permission or auth error (not a Postgres error) | `bq`/`gcloud` isn't authenticated on this machine (common on a fresh systemd host). See § 1d — `gcloud auth activate-service-account` with a service account key, no interactive login needed. |
| `QUEUE_DATABASE_URL must be set` | `.env` missing or not sourced — `cp .env.example .env`, fill it in, `source script/load_env.sh`. |
| `relation "task_queue" does not exist` (or similar) | Wrong `QUEUE_SCHEMA`, or the migration (§ 1c) hasn't been applied to this database yet. |
| A task sits at `status='running'` long after you'd expect it to finish, and no worker is visibly running | The worker that claimed it probably died. It'll self-heal once `claimed_at` exceeds `LEASE_TIMEOUT_HOURS` — another worker (or the same one, restarted) will reclaim it automatically. To force it sooner, lower `LEASE_TIMEOUT_HOURS` temporarily, or manually: `queue_psql "UPDATE ${QUEUE_TABLE} SET status='queued', claimed_by=NULL, claimed_at=NULL WHERE id=<id>;"`. |
| A `targeted_qa_fix` task keeps re-running the same fix over and over | It's in brief mode — see § 2's `--loop-count` warning. Cancel it and resubmit with `--loop-count 1`. |
| Priority/cancel says "already started, can no longer be changed" | Correct behavior — a worker claimed it between your last `list` and the command. Check `script/queue_ctl.sh list --status running`. |
| You need to know why a task ended up `failed` or `blocked` | `last_result` (§ 4) has the raw output — it's what the underlying script printed, including any `findings`/`blockers` it reported. |

---

## 8. Safety notes

- A task only ever triggers a real, irreversible write (`claude -p` with `--permission-mode
  bypassPermissions`, writing to `product_taxonomy`) when the category actually has a nonzero
  coverage gap or unreviewed worklist. Submitting a task for an already-fully-covered category is
  safe and cheap — the underlying script's own live pre-check exits before ever calling `claude -p`.
- Don't submit a `targeted_qa_fix` task for a category with `taxonomy_id IS NULL` coverage gaps —
  that's `headless_taxonomy`'s job. `targeted_qa_fix` only fixes existing entries; a mismatched
  submission will come back `status='blocked'` explaining the scope mismatch, not silently do the
  wrong thing.
