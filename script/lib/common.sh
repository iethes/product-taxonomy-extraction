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
