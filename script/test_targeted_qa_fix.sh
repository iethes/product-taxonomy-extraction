#!/usr/bin/env bash
set -euo pipefail

# Self-test for script/targeted_qa_fix.sh's pure helper functions.
# No network, BQ, or claude calls — see docs/superpowers/specs/2026-07-17-targeted-qa-fix-script-design.md
# "Testing" section for why those are out of scope for an automated check.
# Run: bash script/test_targeted_qa_fix.sh

cd "$(dirname "$0")/.."
source script/targeted_qa_fix.sh

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- category_key_for ---
[[ "$(category_key_for "shopee_th_widget")" == "master_clean_niq.shopee_th_widget" ]] || fail "category_key_for should prefix with master_clean_niq"
echo "PASS: category_key_for"

# --- has_real_brief ---
no_brief='# Category
## QA History'
[[ "$(has_real_brief "$no_brief")" == "false" ]] || fail "no Brief section -> false"

template_brief='## Targeted QA Fix Brief

> Scope note here.

**Verdict:** {defect class, e.g. "D1 Tier-C generic stubs"}

{Fix description}'
[[ "$(has_real_brief "$template_brief")" == "false" ]] || fail "unfilled template Verdict -> false"

real_brief='## Targeted QA Fix Brief

> Scope note here.

**Verdict:** D5 pack-count errors on 12 products

Fix these specific pack-count mistakes...'
[[ "$(has_real_brief "$real_brief")" == "true" ]] || fail "filled Verdict -> true"

deferred_brief='## Targeted QA Fix Brief

**Verdict:** not yet assessed — this run was coverage-first, precision work deferred to auto-discovery.

Highest-value first targets: ...'
[[ "$(has_real_brief "$deferred_brief")" == "false" ]] || fail "'not yet assessed' disclaimer must be treated as no-real-brief, even with a filled Verdict line"

none_written_brief='## Targeted QA Fix Brief

**Verdict:** *(none written yet — auto-discovery mode is correct for the next run.)*

Known, expected precision debt: ...'
[[ "$(has_real_brief "$none_written_brief")" == "false" ]] || fail "'none written yet' disclaimer must be treated as no-real-brief"
echo "PASS: has_real_brief"

# --- qa_history_insert_query ---
q=$(qa_history_insert_query "master_clean_niq.shopee_th_detergent")
echo "$q" | grep -q "INSERT INTO" || fail "qa_history_insert_query should build an INSERT statement"
echo "$q" | grep -q "'QA_HISTORY'" || fail "qa_history_insert_query should tag the row task_type='QA_HISTORY'"
echo "$q" | grep -q "@category_key" || fail "qa_history_insert_query should use a bound parameter for category_key, not string interpolation"
echo "$q" | grep -q "@task_date" || fail "qa_history_insert_query should use a bound parameter for task_date"
echo "$q" | grep -q "@brief_markdown" || fail "qa_history_insert_query should use a bound parameter for the finding/resolution text"
echo "$q" | grep -q "'CLAUDE_CODE'" || fail "qa_history_insert_query should hardcode meta_agent='CLAUDE_CODE'"
echo "PASS: qa_history_insert_query"

# --- build_prompt ---
prompt=$(build_prompt "shopee_th_detergent" "master_clean_niq.shopee_th_detergent")
grep -q "shopee_th_detergent" <<< "$prompt" || fail "build_prompt should mention the table name"
grep -q "master_clean_niq.shopee_th_detergent" <<< "$prompt" || fail "build_prompt should mention the category_key"
grep -q "'targeted_qa_fix'" <<< "$prompt" || fail "build_prompt should claim a targeted_qa_fix block"
grep -q "status='blocked'" <<< "$prompt" || fail "build_prompt should document the blocked outcome"
grep -q "Do NOT run the universe refresh yourself" <<< "$prompt" || fail "build_prompt should forbid self-refresh"
grep -q "never creates coverage for products with" <<< "$prompt" || fail "build_prompt must state this script never creates coverage for taxonomy_id IS NULL products"
grep -q "headless_taxonomy.sh" <<< "$prompt" || fail "build_prompt should point NULL-coverage work at headless_taxonomy.sh instead"
grep -q "qa_history_entry" <<< "$prompt" || fail "build_prompt output schema must include qa_history_entry"
grep -q "Do not write to.*category_brief.*yourself" <<< "$prompt" || fail "build_prompt STEP 6 must not have the agent write to category_brief directly"
echo "PASS: build_prompt"

# --- build_prompt: gate_report parameter (STEP 1B) ---
prompt=$(build_prompt "shopee_th_detergent" "master_clean_niq.shopee_th_detergent" "200" "[FAIL] canonical_name fields:    5")
grep -q "STEP 1B" <<< "$prompt" || fail "build_prompt should insert a STEP 1B pre-fix gate report block"
grep -qF "[FAIL] canonical_name fields:    5" <<< "$prompt" || fail "build_prompt must interpolate the passed gate_report verbatim"
grep -q "informational only" <<< "$prompt" || fail "build_prompt's STEP 1B must frame the gate report as informational, not scope-expanding"
grep -q "this session does exactly what the Brief says, nothing more" <<< "$prompt" || fail "build_prompt's STEP 1B must not let gate failures expand Brief-mode scope"
echo "PASS: build_prompt gate_report (STEP 1B)"

# --- build_auto_discovery_prompt ---
prompt=$(build_auto_discovery_prompt "shopee_th_suncare" "master_clean_niq.shopee_th_suncare" "200")
grep -q "shopee_th_suncare" <<< "$prompt" || fail "build_auto_discovery_prompt should mention the table"
grep -q "master_clean_niq.shopee_th_suncare" <<< "$prompt" || fail "build_auto_discovery_prompt should mention the category_key"
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
# Found live (2026-07-22): "Multiple Sizes"/"Multiple Variants" was an earlier shopee_th_softdrink precedent
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
grep -q "Do not write to.*category_brief.*yourself" <<< "$prompt" || fail "build_auto_discovery_prompt STEP 9 must not have the agent write to category_brief directly"
echo "PASS: build_auto_discovery_prompt"

# --- build_auto_discovery_prompt: gate_report parameter (STEP 1B, fix-direction) ---
prompt=$(build_auto_discovery_prompt "shopee_th_suncare" "master_clean_niq.shopee_th_suncare" "200" "[FAIL] garbled brand text:       4")
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
grep -qF "STEP 1C — Fast-lane recheck" <<< "$prompt" || fail "build_auto_discovery_prompt must add a STEP 1C fast-lane recheck for fixed_pending_recheck rows"
grep -qF "JSON_VALUE(_meta, '\$.review_confidence') IS NULL" <<< "$prompt" || fail "STEP 1C must scope its sweep to the fixed_pending_recheck predicate"
grep -qF "no Tier 2 sample slot spent" <<< "$prompt" || fail "STEP 1C must bulk-promote clean rows without spending Tier 2 judgment"
grep -qF "STEP 1C already bulk-promoted" <<< "$prompt" || fail "STEP 3 must exclude rows STEP 1C already resolved"
echo "PASS: build_auto_discovery_prompt gate_report (STEP 1B)"

# --- build_auto_discovery_prompt: one-pass confidence promotion (STEP 4 / STEP 5) ---
prompt=$(build_auto_discovery_prompt "shopee_th_suncare" "master_clean_niq.shopee_th_suncare" "200")
grep -qF "Same-session gate-verify" <<< "$prompt" || fail "STEP 4 must add the immediate post-fix Tier 1 recheck instruction"
grep -qF "do not wait for a future session's STEP 1C" <<< "$prompt" || fail "STEP 4's recheck must run this session, not a future one"
grep -qF "PATH 1 (new, 2026-07-28)" <<< "$prompt" || fail "STEP 5 must add the new one-pass promotion path"
grep -qF "PATH 2 (existing, unchanged)" <<< "$prompt" || fail "STEP 5 must keep the existing prior-verdict comparison path, labeled unchanged"
grep -qF "IF(JSON_VALUE(pt._meta, '\$.last_verdict') = 'correct', 'confident', 'unconfident')" <<< "$prompt" || fail "STEP 5 Path 2 must retain the exact prior-verdict IF() comparison verbatim"
grep -qF "fully clean on Tier 1" <<< "$prompt" || fail "STEP 5 Path 1(a) must define the never-reviewed promotion condition"
grep -qF "qa_gate_exceptions\` for (gate_name = '<the tripped flag's name" <<< "$prompt" || fail "STEP 5 Path 1 must extend qa_gate_exceptions to Tier 1 flag names, not just qa_report.sh's five named gates"
grep -qF "never double-count a taxonomy_id in both Path 1 and Path 2" <<< "$prompt" || fail "STEP 5 must warn against double-counting a taxonomy_id across both paths"
echo "PASS: build_auto_discovery_prompt one-pass confidence promotion"

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
grep -qF 'build_prompt "$table" "$category_key" "$block_size" "$gate_report"' <<< "$script_src" || fail "brief-mode call site must pass category_key to build_prompt"
grep -qF 'build_auto_discovery_prompt "$table" "$category_key" "$block_size" "$gate_report"' <<< "$script_src" || fail "auto-discovery call site must pass category_key to build_auto_discovery_prompt"
grep -qF 'qa_history_entry' <<< "$script_src" || fail "main() must read qa_history_entry from result_json"
grep -q 'insert_qa_history_row' <<< "$script_src" || fail "main() must call insert_qa_history_row"
echo "PASS: main() gate report capture + coverage trap wiring"

# --- review_worklist_count_query ---
q=$(review_worklist_count_query "shopee_th_suncare")
echo "$q" | grep -q "COUNT(DISTINCT pt.taxonomy_id)" || fail "review_worklist_count_query should count distinct taxonomy_id"
echo "$q" | grep -q "master_table = 'shopee_th_suncare'" || fail "review_worklist_count_query should scope by master_table"
echo "$q" | grep -q "review_confidence" || fail "review_worklist_count_query should mirror the auto-discovery worklist's _meta filter"
echo "PASS: review_worklist_count_query"

# --- QUEUE_SIGNAL wiring in main() (static check -- live bq/claude calls are out of scope here) ---
script_src=$(cat script/targeted_qa_fix.sh)
grep -qF 'review_worklist_count_query "$table"' <<< "$script_src" || fail "main() must run the pre-check worklist count before invoking claude -p in auto-discovery mode"
grep -qF 'echo "QUEUE_SIGNAL: NOTHING_TO_DO"' <<< "$script_src" || fail "main() must emit NOTHING_TO_DO when the auto-discovery worklist is empty"
grep -qF 'echo "QUEUE_SIGNAL: BLOCKED"' <<< "$script_src" || fail "main() must emit BLOCKED in the BLOCKED case branch"
grep -qF 'echo "QUEUE_SIGNAL: FAILED"' <<< "$script_src" || fail "main() must emit FAILED in both the MARK_FAILED case and the failed-gate branch"
signal_done_count=$(grep -cF 'echo "QUEUE_SIGNAL: DONE"' <<< "$script_src")
[[ "$signal_done_count" -eq 2 ]] || fail "main() must emit DONE in both the NOOP case (rows_created=0 is not nothing-to-do) and the successful GATE_AND_REFRESH case, got $signal_done_count occurrences"
echo "PASS: main() QUEUE_SIGNAL wiring"

echo "ALL TESTS PASSED"
