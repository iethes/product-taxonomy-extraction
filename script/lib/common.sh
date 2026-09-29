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

# taxonomy_insert_log_gap_query <target_table_ref> <target_table_plain> <run_start> <log_match_predicate> [scope_predicate]
#
# Returns a scalar COUNT(*) query: rows in <target_table_ref> that exist now, did NOT exist as of
# <run_start> (via BigQuery time travel -- works even on a table with no _meta/timestamp column,
# e.g. a dict table), and have no matching `non_niq_taxonomy_insert_log` row per
# <log_match_predicate>. A nonzero count means an agent-driven script (eiger_qa.sh, susubayi_qa.sh)
# wrote a new taxonomy row but skipped its mandatory same-transaction log write -- those scripts'
# "same BigQuery transaction" instruction is agent-trusted prompt text, not code-enforced like
# non_niq_qa_v3.py's builder, so this is the code-side backstop. Relies on $PROJECT being set by
# the caller (every script that sources this file defines it as a top-level constant).
#
# <target_table_ref>: backticked three-part table, e.g. `project.dataset.table`
# <target_table_plain>: the same table with no backticks (matches how
#   non_niq_taxonomy_insert_log.target_table is stored)
# <run_start>: ISO 8601 UTC timestamp captured before the agent subprocess was invoked
# <log_match_predicate>: SQL fragment referencing `cur` (the live row) and `log` (a
#   non_niq_taxonomy_insert_log row), e.g. "JSON_VALUE(log.row_json, '$.product_id') = cur.product_id"
# <scope_predicate>: optional extra WHERE clause on `cur` to narrow the scan (default: no narrowing)
taxonomy_insert_log_gap_query() {
  local target_table_ref="$1" target_table_plain="$2" run_start="$3" log_match_predicate="$4"
  local scope_predicate="${5:-TRUE}"
  cat <<SQL
SELECT COUNT(*)
FROM ${target_table_ref} cur
WHERE (${scope_predicate})
  AND NOT EXISTS (
    SELECT 1 FROM ${target_table_ref} FOR SYSTEM_TIME AS OF TIMESTAMP('${run_start}') AS prior
    WHERE TO_JSON_STRING(prior) = TO_JSON_STRING(cur)
  )
  AND NOT EXISTS (
    SELECT 1
    FROM \`${PROJECT}.magpie_reference.non_niq_taxonomy_insert_log\` log
    WHERE log.target_table = '${target_table_plain}'
      AND ${log_match_predicate}
  );
SQL
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
      PROJECT="proj"
      gap_sql=$(taxonomy_insert_log_gap_query '`proj.eiger.qa`' 'proj.eiger.qa' '2026-01-01T00:00:00Z' \
        "JSON_VALUE(log.row_json, '\$.product_id') = cur.product_id")
      echo "$gap_sql" | grep -qF 'FROM `proj.eiger.qa` cur' || { echo "FAIL: gap query missing target table"; exit 1; }
      echo "$gap_sql" | grep -qF "FOR SYSTEM_TIME AS OF TIMESTAMP('2026-01-01T00:00:00Z')" \
        || { echo "FAIL: gap query missing time-travel snapshot"; exit 1; }
      echo "$gap_sql" | grep -qF "log.target_table = 'proj.eiger.qa'" \
        || { echo "FAIL: gap query missing plain target_table match"; exit 1; }
      echo "$gap_sql" | grep -qF "JSON_VALUE(log.row_json, '\$.product_id') = cur.product_id" \
        || { echo "FAIL: gap query missing caller's log_match_predicate"; exit 1; }
      echo "self-test OK: common.sh"
      ;;
    *)
      echo "Usage: $0 --self-test" >&2
      exit 1
      ;;
  esac
fi
