#!/usr/bin/env bash
set -euo pipefail

# Self-test for script/niq/targeted_qa_fix_v2.sh's pure helper functions. No network, BQ, or claude calls --
# same scope discipline as tests/niq/test_targeted_qa_fix.sh.
# Run: bash tests/niq/test_targeted_qa_fix_v2.sh

cd "$(dirname "$0")/../.."
source script/niq/targeted_qa_fix_v2.sh

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- category_key_for ---
[[ "$(category_key_for "shopee_th_widget")" == "master_clean_niq.shopee_th_widget" ]] || fail "category_key_for should prefix with master_clean_niq"
echo "PASS: category_key_for"

# --- decide_next_step ---
[[ "$(decide_next_step '{"status":"blocked","blockers":["x"]}')" == "BLOCKED" ]] || fail "blocked status"
[[ "$(decide_next_step '{"status":"failed"}')" == "MARK_FAILED" ]] || fail "failed status"
[[ "$(decide_next_step '{"status":"complete","rows_created":5}')" == "GATE_AND_REFRESH" ]] || fail "complete with rows"
[[ "$(decide_next_step '{"status":"partial","rows_created":1}')" == "GATE_AND_REFRESH" ]] || fail "partial with rows"
[[ "$(decide_next_step '{"status":"complete","rows_created":0}')" == "NOOP" ]] || fail "complete with zero rows"
[[ "$(decide_next_step 'not json at all')" == "MARK_FAILED" ]] || fail "malformed json"
echo "PASS: decide_next_step"

echo "ALL TESTS PASSED"
