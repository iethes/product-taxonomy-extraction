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
# Returns a two-statement BigQuery SCRIPT (one `bq query` call, same convention as the agent's own
# "BEGIN TRANSACTION; INSERT ...; INSERT ...; COMMIT;" writes) whose final SELECT is a scalar
# COUNT(*): rows in <target_table_ref> that exist now, did NOT exist as of <run_start> (via
# BigQuery time travel -- works even on a table with no _meta/timestamp column, e.g. a dict table),
# and have no matching `non_niq_taxonomy_insert_log` row per <log_match_predicate>. A nonzero count
# means an agent-driven script (eiger_qa.sh, susubayi_qa.sh) wrote a new taxonomy row but skipped
# its mandatory same-transaction log write -- those scripts' "same BigQuery transaction"
# instruction is agent-trusted prompt text, not code-enforced like non_niq_qa_v3.py's builder, so
# this is the code-side backstop. Relies on $PROJECT being set by the caller (every script that
# sources this file defines it as a top-level constant).
#
# MUST snapshot the FOR SYSTEM_TIME AS OF read into its own CREATE TEMP TABLE statement first,
# never join/NOT-EXISTS it against a plain (non-time-travel) reference to the SAME table in one
# statement -- confirmed live 2026-09-30 that BigQuery rejects that with "Table ... is referenced
# with and without 'FOR SYSTEM_TIME AS OF' expression", even through a CTE. That syntax error made
# `bq query`'s stdout empty, so the caller's `gap_count` regex match failed and the fail-closed
# path force-blocked an otherwise-clean run (5/5 new dict rows had real matching log rows -- see
# lighting/ID 2026-09-30 13:46 session). The temp table is a genuinely separate table name, so the
# final SELECT only ever references <target_table_ref> plainly.
#
# Also appends a literal 'Z' to <run_start> -- confirmed live that bare
# `TIMESTAMP('2026-09-30T13:26:20')` (no offset) parses as plain UTC in an ordinary SELECT, but
# FOR SYSTEM_TIME AS OF evaluated that exact same literal 7 hours into the future, rejecting it
# with "'FOR SYSTEM_TIME AS OF' expression ... evaluates to a TIMESTAMP value in the future". An
# explicit 'Z'/offset sidesteps whatever default-time-zone FOR SYSTEM_TIME AS OF applies to an
# unqualified timestamp string. <run_start> callers already produce (via `date -u`) has no
# trailing 'Z' -- do not double-append if that ever changes.
#
# <target_table_ref>: backticked three-part table, e.g. `project.dataset.table`
# <target_table_plain>: the same table with no backticks (matches how
#   non_niq_taxonomy_insert_log.target_table is stored)
# <run_start>: ISO 8601 UTC timestamp (no trailing Z) captured before the agent subprocess started
# <log_match_predicate>: SQL fragment referencing `cur` (the live row) and `log` (a
#   non_niq_taxonomy_insert_log row), e.g. "JSON_VALUE(log.row_json, '$.product_id') = cur.product_id"
# <scope_predicate>: optional extra WHERE clause on `cur` to narrow the scan (default: no narrowing)
taxonomy_insert_log_gap_query() {
  local target_table_ref="$1" target_table_plain="$2" run_start="$3" log_match_predicate="$4"
  local scope_predicate="${5:-TRUE}"
  # Idempotent -- callers pass a bare `date -u` value with no offset, but tolerate an
  # already-Z-suffixed value too rather than double-appending.
  [[ "$run_start" == *Z ]] || run_start="${run_start}Z"
  cat <<SQL
CREATE TEMP TABLE prior_snapshot AS
SELECT * FROM ${target_table_ref} FOR SYSTEM_TIME AS OF TIMESTAMP('${run_start}');

SELECT COUNT(*)
FROM ${target_table_ref} cur
WHERE (${scope_predicate})
  AND NOT EXISTS (
    SELECT 1 FROM prior_snapshot prior
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

# apply_taxonomy_insert_log_backstop <agent_output> <target_table_ref> <target_table_plain> <run_start> <log_match_predicate> <label>
#
# The one shared implementation of the code-side backstop for the "same BigQuery transaction"
# insert-log contract (2c.1/2d.1) that eiger_qa.sh, susubayi_qa.sh, non_niq_qa_v2.sh, and its
# merchant/waterheater/dev-forced-merchants variants ask their agent to honor as prompt text only
# -- runs taxonomy_insert_log_gap_query, and on a nonzero (or unreadable, fail-closed) count
# annotates <agent_output> with a finding. Deliberately never forces status to "blocked" here --
# a queue BLOCKED signal stops queue_worker.sh's whole per-task iteration loop early (even when
# iterations_run < loop_count) and parks the task, which is far too disruptive a consequence for
# "this verification query couldn't confirm a provenance row" (which is itself sometimes a false
# positive -- see the 2026-09-30 lighting/ID incident where a bug in this very query's SQL made
# gap_count unreadable and force-blocked an otherwise-clean 296-row session). The underlying
# dict/QA row writes this run made already happened regardless of what this check finds; this is
# a provenance-audit signal for findings, not a gate on whether the run's work counts as done.
#
# Merges via `. * (...)`, never by discarding the original envelope: for the Claude harness the
# real result fields live inside a stringified `.result`, and extract_result_json() short-circuits
# on any top-level `.status` key, so replacing agent_output with a flat object here would silently
# break every downstream extract_result_json()/extract_rows_created() call on the very run where
# the backstop actually fired. Relies on the caller's own extract_result_json() being defined
# (every script that sources this file defines its own copy).
#
# Prints the (possibly annotated) agent_output to stdout. Returns 1 when a gap was found (or the
# verification query itself couldn't be read) purely so the caller can log/branch on it; callers
# must NOT treat that as a reason to withhold sync/merge steps or to block the queue task.
apply_taxonomy_insert_log_backstop() {
  local agent_output="$1" target_table_ref="$2" target_table_plain="$3" run_start="$4"
  local log_match_predicate="$5" label="$6"
  local gap_count
  gap_count=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "$(taxonomy_insert_log_gap_query "$target_table_ref" "$target_table_plain" "$run_start" "$log_match_predicate")" \
    2>/dev/null | tail -1)
  if [[ "$gap_count" =~ ^[0-9]+$ ]] && [[ "$gap_count" == "0" ]]; then
    echo "$agent_output"
    return 0
  fi
  log ERROR "Post-run insert-log verification found ${gap_count:-an unreadable count} of new ${label} row(s) with no matching non_niq_taxonomy_insert_log entry."
  jq -c --argjson result "$(extract_result_json "$agent_output")" '
    . * ($result
      | .findings = ((.findings // []) + ["Post-run validation found a new taxonomy row with no matching non_niq_taxonomy_insert_log entry; the mandatory same-transaction log write was skipped or failed, or this verification query itself could not be read -- see logs."]))
  ' <<< "$agent_output"
  return 1
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
      echo "$gap_sql" | grep -qF 'CREATE TEMP TABLE prior_snapshot AS' \
        || { echo "FAIL: gap query must snapshot into a distinct temp table, never join a plain and a FOR SYSTEM_TIME AS OF reference to the same table in one statement (BigQuery rejects that live)"; exit 1; }
      echo "$gap_sql" | grep -qF 'FROM prior_snapshot prior' \
        || { echo "FAIL: gap query's NOT EXISTS must read the temp table, not FOR SYSTEM_TIME AS OF the target table again"; exit 1; }
      echo "$gap_sql" | grep -qF "log.target_table = 'proj.eiger.qa'" \
        || { echo "FAIL: gap query missing plain target_table match"; exit 1; }
      echo "$gap_sql" | grep -qF "JSON_VALUE(log.row_json, '\$.product_id') = cur.product_id" \
        || { echo "FAIL: gap query missing caller's log_match_predicate"; exit 1; }
      # Idempotent Z-append: a run_start already ending in Z must not become "...ZZ".
      no_z_sql=$(taxonomy_insert_log_gap_query '`proj.eiger.qa`' 'proj.eiger.qa' '2026-01-01T00:00:00' \
        "JSON_VALUE(log.row_json, '\$.product_id') = cur.product_id")
      echo "$no_z_sql" | grep -qF "TIMESTAMP('2026-01-01T00:00:00Z')" \
        || { echo "FAIL: gap query must append Z to a bare run_start with no offset"; exit 1; }
      echo "$gap_sql" | grep -qF 'ZZ' && { echo "FAIL: gap query double-appended Z onto an already-Z-suffixed run_start"; exit 1; }
      if command -v bq >/dev/null 2>&1 && [[ -z "${SKIP_LIVE_BQ_SELFTEST:-}" ]]; then
        # Best-effort live syntax check -- this exact class of bug (valid-looking SQL that
        # BigQuery rejects, e.g. mixing a plain and a FOR SYSTEM_TIME AS OF reference to the same
        # table) is invisible to the mocked-bq assertions above; only a real dry_run catches it.
        # Never fails the self-test on auth/network trouble, only on an actual syntax/semantic
        # rejection from BigQuery.
        live_project="$PROJECT"; PROJECT="sincere-hearth-273704"
        live_sql=$(taxonomy_insert_log_gap_query '`bigquery-public-data.samples.shakespeare`' \
          'bigquery-public-data.samples.shakespeare' "$(date -u '+%Y-%m-%dT%H:%M:%S')" \
          "JSON_VALUE(log.row_json, '\$.word') = cur.word")
        PROJECT="$live_project"
        if live_dry_run_err=$(bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --dry_run "$live_sql" 2>&1 >/dev/null); then
          :
        elif echo "$live_dry_run_err" | grep -qi 'not authenticated\|not authorized\|permission\|credential\|login'; then
          echo "SKIP: live BQ self-test (no usable credentials): ${live_dry_run_err}" >&2
        else
          echo "FAIL: gap query rejected by live BigQuery dry_run -> ${live_dry_run_err}"; exit 1
        fi
      fi
      extract_result_json() { echo "$1"; }
      mock_bin=$(mktemp -d)
      cat > "$mock_bin/bq" <<'MOCK'
#!/usr/bin/env bash
printf 'f0_\n%s\n' "${MOCK_GAP_COUNT:-0}"
MOCK
      chmod +x "$mock_bin/bq"
      PATH="$mock_bin:$PATH"
      if ! clean_output=$(MOCK_GAP_COUNT=0 apply_taxonomy_insert_log_backstop \
        '{"status":"complete"}' '`proj.eiger.qa`' 'proj.eiger.qa' '2026-01-01T00:00:00Z' 'TRUE' 'eiger.qa'); then
        echo "FAIL: backstop must return 0 (success) when gap_count is 0"; exit 1
      fi
      [[ "$clean_output" == '{"status":"complete"}' ]] \
        || { echo "FAIL: backstop must pass agent_output through unchanged when gap_count is 0 -> $clean_output"; exit 1; }
      if gap_output=$(MOCK_GAP_COUNT=1 apply_taxonomy_insert_log_backstop \
        '{"status":"complete","rows_qa_confirmed":1}' '`proj.eiger.qa`' 'proj.eiger.qa' '2026-01-01T00:00:00Z' 'TRUE' 'eiger.qa'); then
        echo "FAIL: backstop must return nonzero when gap_count is nonzero"; exit 1
      fi
      echo "$gap_output" | jq -e '.status == "complete" and .rows_qa_confirmed == 1 and (.findings | length) == 1' >/dev/null \
        || { echo "FAIL: backstop must append a finding, never force status to blocked, while preserving the caller's other fields -> $gap_output"; exit 1; }
      rm -rf "$mock_bin"
      echo "self-test OK: common.sh"
      ;;
    *)
      echo "Usage: $0 --self-test" >&2
      exit 1
      ;;
  esac
fi
