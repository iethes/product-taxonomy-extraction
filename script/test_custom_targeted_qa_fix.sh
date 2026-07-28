#!/usr/bin/env bash
set -euo pipefail

# Self-test for script/custom_targeted_qa_fix.sh's pure helper functions.
# No network, BQ, or claude calls — mirrors script/test_targeted_qa_fix.sh's convention.
# Run: bash script/test_custom_targeted_qa_fix.sh

cd "$(dirname "$0")/.."
source script/custom_targeted_qa_fix.sh

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- resolve_category_file (no shopee_ stripping — CATEGORY is the exact filename) ---
tmpdir=$(mktemp -d)
mkdir -p "$tmpdir/docs/categories"
touch "$tmpdir/docs/categories/makanankucing_my.md"
pushd "$tmpdir" >/dev/null

result=$(resolve_category_file "makanankucing_my") || fail "should find makanankucing_my.md directly"
[[ "$result" == "docs/categories/makanankucing_my.md" ]] || fail "expected docs/categories/makanankucing_my.md, got $result"

if resolve_category_file "no_such_category" >/dev/null 2>&1; then
  fail "should fail for a category with no category file"
fi

popd >/dev/null
rm -rf "$tmpdir"
echo "PASS: resolve_category_file"

# --- has_real_brief ---
tmpdir=$(mktemp -d)
cat > "$tmpdir/real_brief.md" <<'EOF'
## Targeted QA Fix Brief

**Verdict:** D5 pack-count errors on 12 products

Fix these specific pack-count mistakes...
EOF
[[ "$(has_real_brief "$tmpdir/real_brief.md")" == "true" ]] || fail "filled Verdict -> true"

# Live bug (2026-07-28, makanananjing_my run): custom_headless_taxonomy.sh writes this section
# post-hoc as a future-work punch list, opening with this exact disclaimer, across all 4 custom
# categories. A non-templated Verdict line alone still read as "real" and sent a session into brief
# mode against un-executable items (NULL-coverage backfill, cross-master_table re-routing), burning a
# whole session on status=blocked instead of falling through to auto-discovery.
cat > "$tmpdir/future_scope_brief.md" <<'EOF'
## Targeted QA Fix Brief

> Scope for a future `targeted_qa_fix.sh` / NULL-coverage session — not executed this session.

**Verdict:** D6 in-scope NULL coverage gap + a cross-category re-routing task + a D1/D2 precision pass.

- Coverage gap (~137 products): ...
EOF
[[ "$(has_real_brief "$tmpdir/future_scope_brief.md")" == "false" ]] || fail "'not executed this session' disclaimer must be treated as no-real-brief, even with a filled Verdict line"

# The disclaimer check must be scoped to the Brief section only, not the whole file — a QA History
# row mentioning the same phrase elsewhere in the doc must not suppress an otherwise-real brief.
cat > "$tmpdir/scoped_brief.md" <<'EOF'
## Targeted QA Fix Brief

**Verdict:** D5 pack-count errors on 12 products

Fix these specific pack-count mistakes...

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-20 | Pass 1 | prior brief was not executed this session | deferred |
EOF
[[ "$(has_real_brief "$tmpdir/scoped_brief.md")" == "true" ]] || fail "disclaimer text outside the Brief section must not suppress a real brief"

rm -rf "$tmpdir"
echo "PASS: has_real_brief"

# --- scope_note ---
note=$(scope_note "makanankucing" "9_makanankucing_my_daily")
grep -q "ecommerce_platform IN ('Shopee', 'Tiktok')" <<< "$note" || fail "scope_note must state both platforms are in scope"
grep -q "makanankucing.9_makanankucing_my_daily" <<< "$note" || fail "scope_note must reference the dataset.table"
grep -q "do not re-litigate or block on it" <<< "$note" || fail "scope_note must forbid re-litigating the scope decision"
grep -q "do not fix, do not block on it" <<< "$note" || fail "scope_note must forbid fixing/blocking on the known GMV corruption"
echo "PASS: scope_note"

# --- build_prompt ---
prompt=$(build_prompt "makanankucing" "9_makanankucing_my_daily" "makanankucing_my" "docs/categories/makanankucing_my.md")
grep -q "master_table='makanankucing_my'" <<< "$prompt" || fail "build_prompt should key on CATEGORY, not the source table name"
grep -q "makanankucing.9_makanankucing_my_daily" <<< "$prompt" || fail "build_prompt should mention the custom source table"
grep -q "not master_clean_niq" <<< "$prompt" || fail "build_prompt should flag this as a non-NIQ source"
grep -q "'custom_targeted_qa_fix'" <<< "$prompt" || fail "build_prompt should claim a custom_targeted_qa_fix-scenario block"
grep -q "ecommerce_platform IN ('Shopee', 'Tiktok')" <<< "$prompt" || fail "build_prompt should inline the platform-mixing scope note"
grep -q "custom_headless_taxonomy.sh's top-up scenario" <<< "$prompt" || fail "build_prompt must point NULL-coverage work at custom_headless_taxonomy.sh instead"
grep -q "qa_history_entry" <<< "$prompt" || fail "build_prompt output schema must include qa_history_entry"
echo "PASS: build_prompt"

# --- build_prompt: gate_report parameter (STEP 1B) ---
prompt=$(build_prompt "makanankucing" "9_makanankucing_my_daily" "makanankucing_my" "docs/categories/makanankucing_my.md" "200" "[FAIL] canonical_name fields:    5")
grep -q "STEP 1B" <<< "$prompt" || fail "build_prompt should insert a STEP 1B pre-fix gate report block"
grep -qF "[FAIL] canonical_name fields:    5" <<< "$prompt" || fail "build_prompt must interpolate the passed gate_report verbatim"
echo "PASS: build_prompt gate_report (STEP 1B)"

# --- build_auto_discovery_prompt ---
prompt=$(build_auto_discovery_prompt "makanankucing" "9_makanankucing_my_daily" "makanankucing_my" "docs/categories/makanankucing_my.md" "200")
grep -q "master_table='makanankucing_my'" <<< "$prompt" || fail "build_auto_discovery_prompt should key on CATEGORY"
grep -q "makanankucing.9_makanankucing_my_daily" <<< "$prompt" || fail "build_auto_discovery_prompt should mention the custom source table"
grep -q "ecommerce_platform IN ('Shopee', 'Tiktok')" <<< "$prompt" || fail "build_auto_discovery_prompt should inline the platform-mixing scope note"
grep -q "s.ecommerce_platform = m.platform" <<< "$prompt" || fail "build_auto_discovery_prompt's STEP 2b/2c source joins must match on platform, not product_id alone"
grep -q "'custom_targeted_qa_fix'" <<< "$prompt" || fail "build_auto_discovery_prompt should claim a custom_targeted_qa_fix-scenario block when minting"
grep -q "unreliable for Tiktok rows specifically" <<< "$prompt" || fail "STEP 3's GMV-prioritized sample must flag the Tiktok GMV-corruption caveat"
grep -q "precision is this script's job, not custom_headless_taxonomy.sh's" <<< "$prompt" || fail "build_auto_discovery_prompt must state the precision-first priority against the right sibling script"
echo "PASS: build_auto_discovery_prompt"

# --- build_auto_discovery_prompt: one-pass confidence promotion (STEP 4 / STEP 5), mirrors targeted_qa_fix.sh ---
prompt=$(build_auto_discovery_prompt "makanankucing" "9_makanankucing_my_daily" "makanankucing_my" "docs/categories/makanankucing_my.md" "200")
grep -qF "Same-session gate-verify" <<< "$prompt" || fail "STEP 4 must add the immediate post-fix Tier 1 recheck instruction"
grep -qF "do not wait for a future session's STEP 1C" <<< "$prompt" || fail "STEP 4's recheck must run this session, not a future one"
grep -qF "PATH 1 (new, 2026-07-28)" <<< "$prompt" || fail "STEP 5 must add the new one-pass promotion path"
grep -qF "PATH 2 (existing, unchanged)" <<< "$prompt" || fail "STEP 5 must keep the existing prior-verdict comparison path, labeled unchanged"
grep -qF "IF(JSON_VALUE(pt._meta, '\$.last_verdict') = 'correct', 'confident', 'unconfident')" <<< "$prompt" || fail "STEP 5 Path 2 must retain the exact prior-verdict IF() comparison verbatim"
grep -qF "fully clean on Tier 1" <<< "$prompt" || fail "STEP 5 Path 1(a) must define the never-reviewed promotion condition"
grep -qF "qa_gate_exceptions\` for (gate_name = '<the tripped flag's name" <<< "$prompt" || fail "STEP 5 Path 1 must extend qa_gate_exceptions to Tier 1 flag names"
grep -qF "master_table = 'makanankucing_my'" <<< "$prompt" || fail "STEP 5 Path 1(a)'s qa_gate_exceptions lookup must use \${category}, not \${table}, in this script"
grep -qF "never double-count a taxonomy_id in both Path 1 and Path 2" <<< "$prompt" || fail "STEP 5 must warn against double-counting a taxonomy_id across both paths"
echo "PASS: build_auto_discovery_prompt one-pass confidence promotion (custom)"

# --- decide_next_step (unchanged logic, sanity-check it still works after the copy) ---
[[ "$(decide_next_step '{"status":"blocked","blockers":["x"]}')" == "BLOCKED" ]] || fail "blocked status"
[[ "$(decide_next_step '{"status":"failed"}')" == "MARK_FAILED" ]] || fail "failed status"
[[ "$(decide_next_step '{"status":"complete","rows_created":5}')" == "GATE_AND_REFRESH" ]] || fail "complete with rows"
[[ "$(decide_next_step '{"status":"complete","rows_created":0}')" == "NOOP" ]] || fail "complete with zero rows"
[[ "$(decide_next_step 'not json at all')" == "MARK_FAILED" ]] || fail "malformed json"
echo "PASS: decide_next_step"

# --- review_worklist_count_query ---
q=$(review_worklist_count_query "makanankucing_my")
echo "$q" | grep -q "master_table = 'makanankucing_my'" || fail "review_worklist_count_query should scope by CATEGORY"
echo "PASS: review_worklist_count_query"

# --- main(): DATASET/SOURCE_TABLE/CATEGORY wiring + coverage EXIT trap ---
script_src=$(cat script/custom_targeted_qa_fix.sh)
grep -qF 'QA_FIX_CATEGORY="$category"' <<< "$script_src" || fail "main() must set QA_FIX_CATEGORY as a global for the EXIT trap to see"
grep -q 'trap.*qa_coverage_report\.sh.*EXIT' <<< "$script_src" || fail "main() must set an EXIT trap invoking qa_coverage_report.sh"
grep -qF 'build_prompt "$dataset" "$table" "$category" "$category_file" "$block_size" "$gate_report"' <<< "$script_src" || fail "brief-mode call site must pass dataset/table/category in that order"
grep -qF 'build_auto_discovery_prompt "$dataset" "$table" "$category" "$category_file" "$block_size" "$gate_report"' <<< "$script_src" || fail "auto-discovery call site must pass dataset/table/category in that order"
echo "PASS: main() DATASET/SOURCE_TABLE/CATEGORY wiring"

echo "ALL TESTS PASSED"
