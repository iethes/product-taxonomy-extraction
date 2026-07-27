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

# --- queue_psql passes the query through unmodified, and never touches search_path ---
# queue_psql shells out to the real `psql` binary, so stub PATH with a fake one that just echoes its
# args back -- no real Postgres connection needed to test this.
#
# NOTE: queue_psql does NOT select a schema. An earlier version prefixed a `SET search_path` onto the
# query -- found live, empirically, to leak across this PgBouncer's transaction-pooled connection reuse
# onto OTHER clients (confirmed: a SET from one connection was still visible on ten separate fresh
# connections afterward, since transaction pooling does not run a reset query between every hand-off).
# Schema selection is instead done via $QUEUE_TABLE (a fully-qualified table name, see Tasks 4/5) --
# queue_psql itself must never emit a SET statement of any kind. This test asserts the negative: no
# `search_path` string ever appears in what queue_psql sends to psql, regardless of QUEUE_SCHEMA.
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/bin"
cat > "$tmpdir/bin/psql" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@"
EOF
chmod +x "$tmpdir/bin/psql"

output=$(PATH="$tmpdir/bin:$PATH" QUEUE_DATABASE_URL="postgres://fake" QUEUE_SCHEMA="myschema" bash -c '
  source script/load_env.sh
  queue_psql "SELECT 1;" -t -A
')
grep -qF "SELECT 1;" <<< "$output" || fail "queue_psql should pass the SQL through unmodified"
grep -qF -- "-t" <<< "$output" || fail "queue_psql should still pass through extra psql flags"
[[ "$output" != *"search_path"* ]] || fail "queue_psql must NEVER inject a SET search_path, even when QUEUE_SCHEMA is set -- that leaked across PgBouncer's pooled connections in production"

output=$(PATH="$tmpdir/bin:$PATH" QUEUE_DATABASE_URL="postgres://fake" bash -c '
  source script/load_env.sh
  queue_psql "SELECT 1;" -t -A
')
grep -qF "SELECT 1;" <<< "$output" || fail "queue_psql should pass the SQL through unmodified when QUEUE_SCHEMA is unset"
[[ "$output" != *"search_path"* ]] || fail "queue_psql must not inject a SET search_path when QUEUE_SCHEMA is unset"
rm -rf "$tmpdir"
echo "PASS: queue_psql"

echo "ALL TESTS PASSED"
