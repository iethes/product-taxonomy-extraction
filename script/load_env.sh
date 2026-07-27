#!/usr/bin/env bash
# Sourced (not executed) by script/queue_worker.sh and script/queue_ctl.sh to export .env into the
# process environment. Also usable standalone: `source script/load_env.sh` in an interactive shell.
# No-op if .env doesn't exist -- existing environment variables (CI, shell profile) are left as-is.
set -a
[[ -f "$(dirname "${BASH_SOURCE[0]:-$0}")/../.env" ]] && source "$(dirname "${BASH_SOURCE[0]:-$0}")/../.env"
set +a

# Wraps `psql "$QUEUE_DATABASE_URL"` -- the single point of truth for the connection string. Does NOT
# select a schema (no `SET search_path`, no `options=-csearch_path=...`). An earlier version of this
# helper prefixed a `SET search_path TO ${QUEUE_SCHEMA}` onto every query's -c string -- found live,
# empirically, to leak: this deployment's PgBouncer runs in transaction-pooling mode, where a plain
# (session-scoped) SET does NOT reset when the backend connection returns to the pool, so it silently
# carries over onto whatever OTHER client (including NocoDB's own app, sharing this database) gets
# handed that backend next. Confirmed: one connection ran the SET, and ten separate fresh connections
# afterward all inherited it instead of the correct default. Schema selection is instead done by
# fully-qualifying the table name in every query ($QUEUE_TABLE, computed in queue_worker.sh/
# queue_ctl.sh -- see those files) -- this removes the need for any SET at all, so the leak is
# structurally impossible rather than merely patched.
# Usage: queue_psql "<sql>" [extra psql flags...]
queue_psql() {
  local sql="$1"
  shift
  psql "$QUEUE_DATABASE_URL" "$@" -c "$sql"
}
