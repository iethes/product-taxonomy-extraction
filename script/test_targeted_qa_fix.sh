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

# --- has_real_brief ---
tmpdir=$(mktemp -d)

cat > "$tmpdir/no_brief.md" <<'EOF'
# Category
## QA History
EOF
[[ "$(has_real_brief "$tmpdir/no_brief.md")" == "false" ]] || fail "no Brief section -> false"

cat > "$tmpdir/template_brief.md" <<'EOF'
## Targeted QA Fix Brief

> Scope note here.

**Verdict:** {defect class, e.g. "D1 Tier-C generic stubs"}

{Fix description}
EOF
[[ "$(has_real_brief "$tmpdir/template_brief.md")" == "false" ]] || fail "unfilled template Verdict -> false"

cat > "$tmpdir/real_brief.md" <<'EOF'
## Targeted QA Fix Brief

> Scope note here.

**Verdict:** D5 pack-count errors on 12 products

Fix these specific pack-count mistakes...
EOF
[[ "$(has_real_brief "$tmpdir/real_brief.md")" == "true" ]] || fail "filled Verdict -> true"

rm -rf "$tmpdir"
echo "PASS: has_real_brief"

# --- append_qa_history_row ---
tmpdir=$(mktemp -d)
cat > "$tmpdir/cat.md" <<'EOF'
# Category

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-20 | Pass 1 | old finding | old resolution |

---

## Other section
EOF

append_qa_history_row "$tmpdir/cat.md" 'new finding with a | pipe
and a newline' "new resolution" "2026-07-23 12:00 UTC" || fail "append_qa_history_row should succeed on a well-formed file"

grep -qF "| 2026-07-20 | Pass 1 | old finding | old resolution |" "$tmpdir/cat.md" || fail "prior row must survive untouched"
grep -qF "2026-07-23 12:00 UTC" "$tmpdir/cat.md" || fail "new row must be inserted"
grep -qF 'new finding with a \| pipe and a newline' "$tmpdir/cat.md" || fail "pipe must be escaped and newline collapsed to a space"

new_row_line=$(grep -n "2026-07-23 12:00 UTC" "$tmpdir/cat.md" | cut -d: -f1)
divider_line=$(grep -n '^---$' "$tmpdir/cat.md" | head -1 | cut -d: -f1)
[[ "$new_row_line" -lt "$divider_line" ]] || fail "new row must land before the QA History divider, not after"

rm -rf "$tmpdir"
echo "PASS: append_qa_history_row"

tmpdir=$(mktemp -d)
cat > "$tmpdir/no_history.md" <<'EOF'
# Category
No history section here.
EOF
if append_qa_history_row "$tmpdir/no_history.md" "f" "r" "2026-07-23 12:00 UTC"; then
  fail "append_qa_history_row should fail when there's no '## QA History' heading"
fi
rm -rf "$tmpdir"
echo "PASS: append_qa_history_row missing heading"

# --- build_prompt ---
prompt=$(build_prompt "shopee_th_detergent" "docs/categories/th_detergent.md")
grep -q "shopee_th_detergent" <<< "$prompt" || fail "build_prompt should mention the table name"
grep -q "docs/categories/th_detergent.md" <<< "$prompt" || fail "build_prompt should mention the category file path"
grep -q "'targeted_qa_fix'" <<< "$prompt" || fail "build_prompt should claim a targeted_qa_fix block"
grep -q "status='blocked'" <<< "$prompt" || fail "build_prompt should document the blocked outcome"
grep -q "Do NOT run the universe refresh yourself" <<< "$prompt" || fail "build_prompt should forbid self-refresh"
grep -q "never creates coverage for products with" <<< "$prompt" || fail "build_prompt must state this script never creates coverage for taxonomy_id IS NULL products"
grep -q "headless_taxonomy.sh" <<< "$prompt" || fail "build_prompt should point NULL-coverage work at headless_taxonomy.sh instead"
grep -q "qa_history_entry" <<< "$prompt" || fail "build_prompt output schema must include qa_history_entry"
grep -q "Do not edit docs/categories/th_detergent.md or run git yourself" <<< "$prompt" || fail "build_prompt STEP 6 must not have the agent edit the file or commit directly"
echo "PASS: build_prompt"

# --- build_prompt: gate_report parameter (STEP 1B) ---
prompt=$(build_prompt "shopee_th_detergent" "docs/categories/th_detergent.md" "200" "[FAIL] canonical_name fields:    5")
grep -q "STEP 1B" <<< "$prompt" || fail "build_prompt should insert a STEP 1B pre-fix gate report block"
grep -qF "[FAIL] canonical_name fields:    5" <<< "$prompt" || fail "build_prompt must interpolate the passed gate_report verbatim"
grep -q "informational only" <<< "$prompt" || fail "build_prompt's STEP 1B must frame the gate report as informational, not scope-expanding"
grep -q "this session does exactly what the Brief says, nothing more" <<< "$prompt" || fail "build_prompt's STEP 1B must not let gate failures expand Brief-mode scope"
echo "PASS: build_prompt gate_report (STEP 1B)"

# --- build_auto_discovery_prompt ---
prompt=$(build_auto_discovery_prompt "shopee_th_suncare" "docs/categories/th_suncare.md" "200")
grep -q "shopee_th_suncare" <<< "$prompt" || fail "build_auto_discovery_prompt should mention the table"
grep -q "docs/categories/th_suncare.md" <<< "$prompt" || fail "build_auto_discovery_prompt should mention the category file"
grep -q "review_confidence" <<< "$prompt" || fail "build_auto_discovery_prompt must reference the _meta review_confidence field"
grep -q "all variants?|all sizes?" <<< "$prompt" || fail "build_auto_discovery_prompt's Tier 1 sweep must include the extended stub-leak regex"
grep -q "docs/llm-extraction-rules.md" <<< "$prompt" || fail "build_auto_discovery_prompt must instruct reading the extraction rules (incl. new §11)"
grep -q "precision is this script's job, not headless_taxonomy.sh's" <<< "$prompt" || fail "build_auto_discovery_prompt must state the precision-first priority"
grep -q "'targeted_qa_fix'" <<< "$prompt" || fail "build_auto_discovery_prompt should claim a targeted_qa_fix-scenario SKU block when minting"
grep -q "status='blocked'" <<< "$prompt" || fail "build_auto_discovery_prompt should document the blocked outcome"
grep -q "Do NOT run the universe refresh yourself" <<< "$prompt" || fail "build_auto_discovery_prompt must forbid self-refresh"
# Found live (2026-07-21, shopee_th_suncare run): qa_report.sh's independent "canonical_name fields" gate
# failed 81 rows post-run — a defect class (canonical_name missing a product_line/sub_line/variant/size/xN
# word) that Tier 1's sweep never checked for, so auto-discovery marked things "reviewed" that still failed
# the wrapper's own gate. Same run also only reviewed 133 of ~5,812 rows in one session (one UPDATE per
# taxonomy_id for _meta bookkeeping was the bottleneck) - fixed by bulk-marking the whole clean set at once.
grep -q "canonical_field_mismatch" <<< "$prompt" || fail "build_auto_discovery_prompt's Tier 1 sweep must add the canonical_name/structured-field consistency check"
grep -q "not one UPDATE per row" <<< "$prompt" || fail "build_auto_discovery_prompt's STEP 5 must bulk-mark Tier-2-judged rows in one UPDATE, not one per taxonomy_id"
grep -q "never bulk-mark a Tier-1-clean row you" <<< "$prompt" || fail "build_auto_discovery_prompt must forbid fabricating a review for rows that were never actually judged"
grep -q "bounded, GMV-prioritized sample" <<< "$prompt" || fail "build_auto_discovery_prompt's Tier 2 must be an explicitly bounded sample, not implicitly exhaustive"
# Found live (2026-07-22): "Multiple Sizes"/"Multiple Variants" was an earlier th_softdrink precedent
# (paired with is_multi_size/is_multi_variant=TRUE) but is now banned unconditionally, same as
# "All variant"/"All size" -- the is_multi_size/is_multi_variant column already conveys that semantic,
# so the text itself is the defect regardless of the flag. Also product 16254994627's "Buy 1 Get 1"
# sku_name was missed by the pack-count-promo check because that check (quality-standards.md D5) was
# never actually wired into any automated gate before now.
grep -q "multiple variants?|multiple sizes?" <<< "$prompt" || fail "build_auto_discovery_prompt's stub_leak check must also catch 'multiple variants/sizes' text unconditionally"
grep -qF 'buy\s*\d+\s*get\s*\d+' <<< "$prompt" || fail "build_auto_discovery_prompt must check for English 'buy N get M' pack-count promo phrasing"
grep -q "most .ฟรี./.free. hits are GWP" <<< "$prompt" || fail "the pack-count-promo check must carry the GWP-confirmation caveat, not auto-assume wrong"
# Round 3 (2026-07-22 stakeholder review): product 22501764599 was a shampoo mapped to a body-wash entry
# (type-conflict routing, not a naming defect -- Tier 2 judgment must explicitly check this, no new SQL
# heuristic per explicit direction, since a keyword filter risks silently dropping exactly what it should
# catch). Product 16254994627 had an image-visible 400ml size never extracted (D4, never wired before now).
# Product 7155345414 resolved to garbled brand text "12/+＝" (seller watermark misread as brand). Product
# 26143837772 had canonical_name correctly saying "Enfant" while brand_id resolved to BRD-UNDEFINED --
# already caught by wrong_field_order, but the existing fix guidance assumed the wrong root cause (reorder
# text) instead of the real one (fix brand_id).
grep -q "null_size" <<< "$prompt" || fail "build_auto_discovery_prompt's Tier 1 sweep must add the D4 size-coverage check"
grep -qF "r'[\p{L}]'" <<< "$prompt" || fail "build_auto_discovery_prompt's Tier 1 sweep must add the garbage_brand check"
grep -qF "pt.is_bundle IS NOT TRUE" <<< "$prompt" || fail "build_auto_discovery_prompt's canonical_field_mismatch check must exempt is_bundle=true rows from the literal-xN requirement"
grep -q "product type genuinely matches" <<< "$prompt" || fail "STEP 3 must require an explicit type-conflict check, not just naming/structure judgment"
grep -q "brand_id resolves to BRD-UNDEFINED/BRD-UNBRANDED while canonical_name clearly states a real" <<< "$prompt" || fail "STEP 4 must branch wrong_field_order's fix between reordering text and correcting brand_id"
grep -q "qa_history_entry" <<< "$prompt" || fail "build_auto_discovery_prompt output schema must include qa_history_entry"
grep -q "Do not edit docs/categories/th_suncare.md or run git yourself" <<< "$prompt" || fail "build_auto_discovery_prompt STEP 9 must not have the agent edit the file or commit directly"
echo "PASS: build_auto_discovery_prompt"

# --- build_auto_discovery_prompt: gate_report parameter (STEP 1B, fix-direction) ---
prompt=$(build_auto_discovery_prompt "shopee_th_suncare" "docs/categories/th_suncare.md" "200" "[FAIL] garbled brand text:       4")
grep -q "STEP 1B" <<< "$prompt" || fail "build_auto_discovery_prompt should insert a STEP 1B pre-fix gate report block"
grep -qF "[FAIL] garbled brand text:       4" <<< "$prompt" || fail "build_auto_discovery_prompt must interpolate the passed gate_report verbatim"
for gate in "placeholder-leak" "structured-fields NULL%" "'all variant/size' name" "canonical_name fields" "garbled brand text"; do
  grep -qF "$gate" <<< "$prompt" || fail "build_auto_discovery_prompt STEP 1B must name entry-level gate: $gate"
done
grep -q "no LLM judgment needed to detect it, only to decide and apply the correct fix" <<< "$prompt" || fail "STEP 1B must give entry-level gates fix-direction language"
for gate in "dual-mapped (LLM)" "HUMAN+LLM coexistence" "duplicate product_id" "duplicate product+taxon"; do
  grep -qF "$gate" <<< "$prompt" || fail "build_auto_discovery_prompt STEP 1B must name map-level gate: $gate"
done
grep -q "do NOT attempt a fix" <<< "$prompt" || fail "STEP 1B must mark map-level gates report-only"
grep -q "flagged as needing a deletion-authorized session" <<< "$prompt" || fail "STEP 1B must flag map-level failures for a deletion-authorized session"
grep -q "qa_gate_exceptions" <<< "$prompt" || fail "STEP 1B must have the agent check qa_gate_exceptions before re-verifying a gate"
grep -q "skip re-verifying it entirely" <<< "$prompt" || fail "STEP 1B must tell the agent to skip rows already covered by a confirmed exception"
grep -q "not enough to close it permanently" <<< "$prompt" || fail "STEP 1B must require more than one confirmation before writing a new exception"
echo "PASS: build_auto_discovery_prompt gate_report (STEP 1B)"

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

# --- main(): pre-fix gate capture + coverage EXIT trap wiring ---
script_src=$(cat script/targeted_qa_fix.sh)
grep -qF 'gate_report=$(./script/qa_report.sh "$table")' <<< "$script_src" || fail "main() must capture qa_report.sh output before building the prompt"
grep -qF 'QA_FIX_TABLE="$table"' <<< "$script_src" || fail "main() must set QA_FIX_TABLE as a global for the EXIT trap to see"
grep -q 'trap.*qa_coverage_report\.sh.*EXIT' <<< "$script_src" || fail "main() must set an EXIT trap invoking qa_coverage_report.sh"
grep -qF 'build_prompt "$table" "$category_file" "$block_size" "$gate_report"' <<< "$script_src" || fail "brief-mode call site must pass gate_report to build_prompt"
grep -qF 'build_auto_discovery_prompt "$table" "$category_file" "$block_size" "$gate_report"' <<< "$script_src" || fail "auto-discovery call site must pass gate_report to build_auto_discovery_prompt"
grep -qF 'qa_history_entry' <<< "$script_src" || fail "main() must read qa_history_entry from result_json"
grep -q 'append_qa_history_row' <<< "$script_src" || fail "main() must call append_qa_history_row"
echo "PASS: main() gate report capture + coverage trap wiring"

echo "ALL TESTS PASSED"
