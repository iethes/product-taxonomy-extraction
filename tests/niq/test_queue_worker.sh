#!/usr/bin/env bash
set -euo pipefail

# Self-test for script/niq/queue_worker.sh's pure helper functions.
# No network, Postgres, or claude calls -- mirrors tests/niq/test_targeted_qa_fix.sh's convention.
# Run: bash tests/niq/test_queue_worker.sh

cd "$(dirname "$0")/../.."
source script/niq/queue_worker.sh

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- parse_queue_signal ---
mixed_output='some prose
QUEUE_SIGNAL: DONE
trailing prose'
[[ "$(parse_queue_signal "$mixed_output")" == "DONE" ]] || fail "should extract DONE from mixed output"

no_signal_output='no signal line here at all'
[[ "$(parse_queue_signal "$no_signal_output")" == "" ]] || fail "should return empty string when no QUEUE_SIGNAL line present"

two_signals_output='QUEUE_SIGNAL: DONE
some other line
QUEUE_SIGNAL: BLOCKED'
[[ "$(parse_queue_signal "$two_signals_output")" == "BLOCKED" ]] || fail "should take the LAST QUEUE_SIGNAL line, not the first"
echo "PASS: parse_queue_signal"

# --- is_duplicate_key_error ---
dup_error='ERROR:  duplicate key value violates unique constraint "one_running_task_per_table"'
[[ "$(is_duplicate_key_error "$dup_error")" == "true" ]] || fail "should detect a duplicate key constraint violation"

other_error='ERROR:  relation "task_queue" does not exist'
[[ "$(is_duplicate_key_error "$other_error")" == "false" ]] || fail "should not flag an unrelated SQL error as a duplicate key race"
echo "PASS: is_duplicate_key_error"

# --- queue_signal_to_status ---
[[ "$(queue_signal_to_status "NOTHING_TO_DO")" == "done" ]] || fail "NOTHING_TO_DO -> done"
[[ "$(queue_signal_to_status "DONE")" == "done" ]] || fail "DONE -> done"
[[ "$(queue_signal_to_status "BLOCKED")" == "blocked" ]] || fail "BLOCKED -> blocked"
[[ "$(queue_signal_to_status "FAILED")" == "failed" ]] || fail "FAILED -> failed"
[[ "$(queue_signal_to_status "")" == "failed" ]] || fail "missing/unparseable signal -> failed, not silently ignored"
[[ "$(queue_signal_to_status "GARBAGE")" == "failed" ]] || fail "unrecognized signal -> failed"
echo "PASS: queue_signal_to_status"

# --- should_stop_looping ---
[[ "$(should_stop_looping "DONE")" == "false" ]] || fail "DONE should NOT stop the loop -- more iterations may still find work"
[[ "$(should_stop_looping "NOTHING_TO_DO")" == "true" ]] || fail "NOTHING_TO_DO should stop the loop early"
[[ "$(should_stop_looping "BLOCKED")" == "true" ]] || fail "BLOCKED should stop the loop"
[[ "$(should_stop_looping "FAILED")" == "true" ]] || fail "FAILED should stop the loop"
[[ "$(should_stop_looping "")" == "true" ]] || fail "missing signal should stop the loop, not spin through remaining iterations"
echo "PASS: should_stop_looping"

echo "ALL TESTS PASSED"
