#!/usr/bin/env bash
set -euo pipefail

# Self-test for script/targeted_qa_fix.sh's pure helper functions.
# No network, BQ, or claude calls — see docs/superpowers/specs/2026-07-17-targeted-qa-fix-script-design.md
# "Testing" section for why those are out of scope for an automated check.
# Run: bash script/test_targeted_qa_fix.sh

cd "$(dirname "$0")/.."
source script/targeted_qa_fix.sh

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- resolve_category_file ---
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/docs/categories"
touch "$tmpdir/docs/categories/th_widget.md"
pushd "$tmpdir" >/dev/null

result=$(resolve_category_file "shopee_th_widget") || fail "should find th_widget.md via shopee_ stripping"
[[ "$result" == "docs/categories/th_widget.md" ]] || fail "expected docs/categories/th_widget.md, got $result"

touch "docs/categories/shopee_sg_widget.md"
result=$(resolve_category_file "shopee_sg_widget") || fail "should find an exact match first"
[[ "$result" == "docs/categories/shopee_sg_widget.md" ]] || fail "expected exact match, got $result"

if resolve_category_file "no_such_table" >/dev/null 2>&1; then
  fail "should fail for a table with no category file"
fi

popd >/dev/null
rm -rf "$tmpdir"
echo "PASS: resolve_category_file"

# --- build_prompt ---
prompt=$(build_prompt "shopee_th_detergent" "docs/categories/th_detergent.md")
echo "$prompt" | grep -q "shopee_th_detergent" || fail "build_prompt should mention the table name"
echo "$prompt" | grep -q "docs/categories/th_detergent.md" || fail "build_prompt should mention the category file path"
echo "$prompt" | grep -q "'targeted_qa_fix'" || fail "build_prompt should claim a targeted_qa_fix block"
echo "$prompt" | grep -q "status='blocked'" || fail "build_prompt should document the blocked outcome"
echo "$prompt" | grep -q "Do NOT run the universe refresh yourself" || fail "build_prompt should forbid self-refresh"
echo "PASS: build_prompt"

# --- decide_next_step ---
[[ "$(decide_next_step '{"status":"blocked","blockers":["x"]}')" == "BLOCKED" ]] || fail "blocked status"
[[ "$(decide_next_step '{"status":"failed"}')" == "MARK_FAILED" ]] || fail "failed status"
[[ "$(decide_next_step '{"status":"complete","rows_created":5}')" == "GATE_AND_REFRESH" ]] || fail "complete with rows"
[[ "$(decide_next_step '{"status":"partial","rows_created":1}')" == "GATE_AND_REFRESH" ]] || fail "partial with rows"
[[ "$(decide_next_step '{"status":"complete","rows_created":0}')" == "NOOP" ]] || fail "complete with zero rows"
[[ "$(decide_next_step 'not json at all')" == "MARK_FAILED" ]] || fail "malformed json"
[[ "$(decide_next_step '{}')" == "MARK_FAILED" ]] || fail "empty json"

# Live bug (2026-07-17, shopee_th_suncare targeted_qa_fix run): the model wrapped a valid
# status='partial' JSON result in prose commentary despite being told to output ONLY JSON,
# which silently fell through to MARK_FAILED and skipped the independent QA-gate-before-refresh
# check. extract_json_object must recover the embedded object so decide_next_step still routes
# it correctly.
prose_wrapped='QA gates all pass. Final wrap-up.
```json
{"status":"partial","rows_created":6,"rows_mapped":8,"findings":["a {nested} note"]}
```
**Summary:** done.'
[[ "$(decide_next_step "$prose_wrapped")" == "GATE_AND_REFRESH" ]] || fail "prose-wrapped JSON should still route to GATE_AND_REFRESH"
echo "PASS: decide_next_step"

echo "ALL TESTS PASSED"
