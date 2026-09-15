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
# Retries on connection-establishment failures (PgBouncer/network blips like "No route to host" --
# confirmed live) -- safe because the error fires before psql ever reaches the server, so the SQL
# provably never ran. Never retries on any other error (bad SQL, constraint violation, etc.) --
# those already reached the server and retrying could double-run a non-idempotent statement.
queue_psql() {
  local sql="$1"
  shift
  local attempt=1 max_attempts=5 rc errfile
  errfile=$(mktemp)
  while :; do
    if psql "$QUEUE_DATABASE_URL" "$@" -c "$sql" 2>"$errfile"; then
      cat "$errfile" >&2
      rm -f "$errfile"
      return 0
    fi
    rc=$?
    if ! grep -qiE 'no route to host|could not connect to server|connection refused|connection timed out' "$errfile" \
      || (( attempt >= max_attempts )); then
      cat "$errfile" >&2
      rm -f "$errfile"
      return "$rc"
    fi
    echo "[queue_psql] connection error (attempt ${attempt}/${max_attempts}), retrying in $((attempt * 5))s..." >&2
    sleep $((attempt * 5))
    attempt=$((attempt + 1))
  done
}
