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

# --- build_prompt ---
prompt=$(build_prompt "shopee_th_detergent" "docs/categories/th_detergent.md")
echo "$prompt" | grep -q "shopee_th_detergent" || fail "build_prompt should mention the table name"
echo "$prompt" | grep -q "docs/categories/th_detergent.md" || fail "build_prompt should mention the category file path"
echo "$prompt" | grep -q "'targeted_qa_fix'" || fail "build_prompt should claim a targeted_qa_fix block"
echo "$prompt" | grep -q "status='blocked'" || fail "build_prompt should document the blocked outcome"
echo "$prompt" | grep -q "Do NOT run the universe refresh yourself" || fail "build_prompt should forbid self-refresh"
echo "$prompt" | grep -q "never creates coverage for products with" || fail "build_prompt must state this script never creates coverage for taxonomy_id IS NULL products"
echo "$prompt" | grep -q "headless_taxonomy.sh" || fail "build_prompt should point NULL-coverage work at headless_taxonomy.sh instead"
echo "PASS: build_prompt"

# --- build_auto_discovery_prompt ---
prompt=$(build_auto_discovery_prompt "shopee_th_suncare" "docs/categories/th_suncare.md" "200")
echo "$prompt" | grep -q "shopee_th_suncare" || fail "build_auto_discovery_prompt should mention the table"
echo "$prompt" | grep -q "docs/categories/th_suncare.md" || fail "build_auto_discovery_prompt should mention the category file"
echo "$prompt" | grep -q "review_confidence" || fail "build_auto_discovery_prompt must reference the _meta review_confidence field"
echo "$prompt" | grep -q "all variants?|all sizes?" || fail "build_auto_discovery_prompt's Tier 1 sweep must include the extended stub-leak regex"
echo "$prompt" | grep -q "docs/llm-extraction-rules.md" || fail "build_auto_discovery_prompt must instruct reading the extraction rules (incl. new §11)"
echo "$prompt" | grep -q "precision is this script's job, not headless_taxonomy.sh's" || fail "build_auto_discovery_prompt must state the precision-first priority"
echo "$prompt" | grep -q "'targeted_qa_fix'" || fail "build_auto_discovery_prompt should claim a targeted_qa_fix-scenario SKU block when minting"
echo "$prompt" | grep -q "status='blocked'" || fail "build_auto_discovery_prompt should document the blocked outcome"
echo "$prompt" | grep -q "Do NOT run the universe refresh yourself" || fail "build_auto_discovery_prompt must forbid self-refresh"
# Found live (2026-07-21, shopee_th_suncare run): qa_report.sh's independent "canonical_name fields" gate
# failed 81 rows post-run — a defect class (canonical_name missing a product_line/sub_line/variant/size/xN
# word) that Tier 1's sweep never checked for, so auto-discovery marked things "reviewed" that still failed
# the wrapper's own gate. Same run also only reviewed 133 of ~5,812 rows in one session (one UPDATE per
# taxonomy_id for _meta bookkeeping was the bottleneck) - fixed by bulk-marking the whole clean set at once.
echo "$prompt" | grep -q "canonical_field_mismatch" || fail "build_auto_discovery_prompt's Tier 1 sweep must add the canonical_name/structured-field consistency check"
echo "$prompt" | grep -q "not one UPDATE per row" || fail "build_auto_discovery_prompt's STEP 5 must bulk-mark Tier-2-judged rows in one UPDATE, not one per taxonomy_id"
echo "$prompt" | grep -q "never bulk-mark a Tier-1-clean row you" || fail "build_auto_discovery_prompt must forbid fabricating a review for rows that were never actually judged"
echo "$prompt" | grep -q "bounded, GMV-prioritized sample" || fail "build_auto_discovery_prompt's Tier 2 must be an explicitly bounded sample, not implicitly exhaustive"
# Found live (2026-07-22): "Multiple Sizes"/"Multiple Variants" was an earlier th_softdrink precedent
# (paired with is_multi_size/is_multi_variant=TRUE) but is now banned unconditionally, same as
# "All variant"/"All size" -- the is_multi_size/is_multi_variant column already conveys that semantic,
# so the text itself is the defect regardless of the flag. Also product 16254994627's "Buy 1 Get 1"
# sku_name was missed by the pack-count-promo check because that check (quality-standards.md D5) was
# never actually wired into any automated gate before now.
echo "$prompt" | grep -q "multiple variants?|multiple sizes?" || fail "build_auto_discovery_prompt's stub_leak check must also catch 'multiple variants/sizes' text unconditionally"
echo "$prompt" | grep -qF 'buy\s*\d+\s*get\s*\d+' || fail "build_auto_discovery_prompt must check for English 'buy N get M' pack-count promo phrasing"
echo "$prompt" | grep -q "most .ฟรี./.free. hits are GWP" || fail "the pack-count-promo check must carry the GWP-confirmation caveat, not auto-assume wrong"
# Round 3 (2026-07-22 stakeholder review): product 22501764599 was a shampoo mapped to a body-wash entry
# (type-conflict routing, not a naming defect -- Tier 2 judgment must explicitly check this, no new SQL
# heuristic per explicit direction, since a keyword filter risks silently dropping exactly what it should
# catch). Product 16254994627 had an image-visible 400ml size never extracted (D4, never wired before now).
# Product 7155345414 resolved to garbled brand text "12/+＝" (seller watermark misread as brand). Product
# 26143837772 had canonical_name correctly saying "Enfant" while brand_id resolved to BRD-UNDEFINED --
# already caught by wrong_field_order, but the existing fix guidance assumed the wrong root cause (reorder
# text) instead of the real one (fix brand_id).
echo "$prompt" | grep -q "null_size" || fail "build_auto_discovery_prompt's Tier 1 sweep must add the D4 size-coverage check"
echo "$prompt" | grep -qF "r'[\p{L}]'" || fail "build_auto_discovery_prompt's Tier 1 sweep must add the garbage_brand check"
echo "$prompt" | grep -q "product type genuinely matches" || fail "STEP 3 must require an explicit type-conflict check, not just naming/structure judgment"
echo "$prompt" | grep -q "brand_id resolves to BRD-UNDEFINED/BRD-UNBRANDED while canonical_name clearly states a real" || fail "STEP 4 must branch wrong_field_order's fix between reordering text and correcting brand_id"
echo "PASS: build_auto_discovery_prompt"

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
