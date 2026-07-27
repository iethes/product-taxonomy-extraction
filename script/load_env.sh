#!/usr/bin/env bash
# Sourced (not executed) by script/queue_worker.sh and script/queue_ctl.sh to export .env into the
# process environment. Also usable standalone: `source script/load_env.sh` in an interactive shell.
# No-op if .env doesn't exist -- existing environment variables (CI, shell profile) are left as-is.
set -a
[[ -f "$(dirname "${BASH_SOURCE[0]}")/../.env" ]] && source "$(dirname "${BASH_SOURCE[0]}")/../.env"
set +a

# Wraps `psql "$QUEUE_DATABASE_URL"`, transparently selecting QUEUE_SCHEMA (if set) via a
# `SET search_path` issued as the first statement in the SAME -c string as the query. Required
# because some deployments (e.g. a PgBouncer-fronted instance in transaction-pooling mode) reject the
# `options=-csearch_path=...` connection-string parameter, and a separate `-c "SET ..."` call is not
# safe either -- PgBouncer can hand a transaction-pooled client a different backend connection between
# two separate -c calls, silently losing the SET. A single -c string is one implicit transaction on
# one backend connection, so the SET reliably applies to the query that follows it.
# Usage: queue_psql "<sql>" [extra psql flags...]
queue_psql() {
  local sql="$1"
  shift
  psql "$QUEUE_DATABASE_URL" "$@" -c "${QUEUE_SCHEMA:+SET search_path TO ${QUEUE_SCHEMA}; }${sql}"
}
