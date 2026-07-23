# QA Fix Gate Direction + Coverage Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `script/targeted_qa_fix.sh` run `script/qa_report.sh` *before* a fix session (not just after) and feed its failures into the prompt as fix direction, and add a standalone coverage-count script that reports on every exit path how much of a table is still unreviewed.

**Architecture:** `qa_report.sh` is reused unmodified, called twice from `main()` — once pre-fix (output captured and threaded into both prompt builders as a new `gate_report` parameter) and once post-fix (unchanged, existing gate-before-refresh check). A new `script/qa_coverage_report.sh` mirrors `qa_report.sh`'s shape and is wired in via a bash `EXIT` trap so it fires on every exit path.

**Tech Stack:** Bash (`set -euo pipefail`), `bq` CLI, `jq`. No new dependencies.

## Global Constraints

- `_meta` is `STRING`-typed JSON text — read via `JSON_VALUE()`, write via `TO_JSON_STRING()`, never the `JSON '...'` literal (per `docs/superpowers/specs/2026-07-21-taxonomy-review-loop-design.md`; unchanged by this plan, just a constraint any query in these scripts must respect).
- `bq query` truncates displayed results to 100 rows unless `--max_rows=100000` or `--format=csv` is passed. All new/modified queries in this plan use `--format=csv`.
- Never delete a `product_taxonomy_map` row from `targeted_qa_fix.sh` — this is why map-level gate failures (dual-mapped, coexistence, duplicate product_id, duplicate product+taxon) are report-only fix direction, never apply-a-fix direction, in this plan.
- New scripts get the executable bit (`chmod +x`), matching every existing script in `script/`.
- Every `bq query` call in this repo project-qualifies with `--project_id=sincere-hearth-273704`.

---

## File Structure

| File | Change |
|------|--------|
| `script/qa_coverage_report.sh` | New. Standalone `<master_table>` coverage report, same shape as `qa_report.sh`. |
| `script/targeted_qa_fix.sh` | Modified. `build_prompt`/`build_auto_discovery_prompt` gain a `gate_report` parameter and a STEP 1B block; `main()` captures the pre-fix gate report and sets an `EXIT` trap. |
| `script/test_targeted_qa_fix.sh` | Modified. New assertions for the `gate_report` parameter, STEP 1B content, and the new `main()` wiring. |
| `docs/headless-runbook.md` | Modified. "Scenario: Targeted QA Fix" procedure gets the new pre-fix and end-of-run steps. |

---

### Task 1: `script/qa_coverage_report.sh`

**Files:**
- Create: `script/qa_coverage_report.sh`

**Interfaces:**
- Produces: a standalone CLI, `./script/qa_coverage_report.sh <master_table>` → prints coverage counts to stdout, exits 0. Consumed by Task 4's `EXIT` trap in `targeted_qa_fix.sh` as `./script/qa_coverage_report.sh "$QA_FIX_TABLE"`.

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: ./script/qa_coverage_report.sh <master_table>
# Reports how many product_taxonomy entries for a table are NOT confidently reviewed yet — the exact
# _meta criteria targeted_qa_fix.sh's auto-discovery worklist uses (_meta IS NULL OR review_confidence !=
# 'confident'). Standalone-runnable for any table at any time; also called by targeted_qa_fix.sh at the end
# of every run via an EXIT trap, regardless of that run's outcome. See
# docs/superpowers/specs/2026-07-23-qa-fix-gate-direction-and-coverage-design.md.

TABLE="${1:?Usage: $0 <master_table>}"
PROJECT="sincere-hearth-273704"

echo "=== QA coverage: ${TABLE} ==="

bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
  "WITH distinct_entries AS (
     SELECT DISTINCT pt.taxonomy_id, pt._meta
     FROM \`${PROJECT}.magpie_reference.product_taxonomy\` pt
     JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
     WHERE m.master_table = '${TABLE}'
   )
   SELECT
     COUNT(*) AS total,
     COUNTIF(_meta IS NULL) AS never_reviewed,
     COUNTIF(_meta IS NOT NULL AND IFNULL(JSON_VALUE(_meta, '\$.review_confidence'), 'unreviewed') != 'confident') AS unconfident,
     COUNTIF(_meta IS NOT NULL AND JSON_VALUE(_meta, '\$.review_confidence') = 'confident') AS confident
   FROM distinct_entries" | tail -1 | \
while IFS=',' read -r total never_reviewed unconfident confident; do
  pending=$((never_reviewed + unconfident))
  pct=0
  [ "$total" -gt 0 ] && pct=$(( 100 * pending / total ))
  echo "Pending QA (never-reviewed or unconfident): ${pending} / ${total} (${pct}%)"
  echo "  never reviewed: ${never_reviewed}"
  echo "  unconfident:    ${unconfident}"
  echo "  confident:      ${confident}"
done
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x script/qa_coverage_report.sh
```

- [ ] **Step 3: Syntax-check it**

Run: `bash -n script/qa_coverage_report.sh`
Expected: no output, exit code 0.

- [ ] **Step 4: Commit**

```bash
git add script/qa_coverage_report.sh
git commit -m "Add script/qa_coverage_report.sh: standalone unreviewed-count report per table"
```

---

### Task 2: `build_prompt` gains `gate_report` (Brief mode STEP 1B)

**Files:**
- Modify: `script/targeted_qa_fix.sh:54-100` (the `build_prompt` function)
- Test: `script/test_targeted_qa_fix.sh`

**Interfaces:**
- Consumes: nothing new from other tasks.
- Produces: `build_prompt(table, category_file, block_size, gate_report)` — 4th positional arg, defaults to
  empty string. Task 4's `main()` will call this with all four args.

- [ ] **Step 1: Write the failing test**

Open `script/test_targeted_qa_fix.sh` and add this block directly after the existing `# --- build_prompt ---`
section (after the line `echo "PASS: build_prompt"`, i.e. after line 78 in the current file):

```bash
# --- build_prompt: gate_report parameter (STEP 1B) ---
prompt=$(build_prompt "shopee_th_detergent" "docs/categories/th_detergent.md" "200" "[FAIL] canonical_name fields:    5")
echo "$prompt" | grep -q "STEP 1B" || fail "build_prompt should insert a STEP 1B pre-fix gate report block"
echo "$prompt" | grep -qF "[FAIL] canonical_name fields:    5" || fail "build_prompt must interpolate the passed gate_report verbatim"
echo "$prompt" | grep -q "informational only" || fail "build_prompt's STEP 1B must frame the gate report as informational, not scope-expanding"
echo "$prompt" | grep -q "this session does exactly what the Brief says, nothing more" || fail "build_prompt's STEP 1B must not let gate failures expand Brief-mode scope"
echo "PASS: build_prompt gate_report (STEP 1B)"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: `FAIL: build_prompt should insert a STEP 1B pre-fix gate report block` (build_prompt currently only
takes 3 args and has no STEP 1B — the 4th arg is silently ignored by bash, so `$gate_report` is never used).

- [ ] **Step 3: Implement — add the 4th parameter**

In `script/targeted_qa_fix.sh`, find:

```bash
build_prompt() {
  local table="$1"
  local category_file="$2"
  local block_size="${3:-200}"
  local slot_offset=$((block_size - 1))
  cat <<PROMPT
```

Replace with:

```bash
build_prompt() {
  local table="$1"
  local category_file="$2"
  local block_size="${3:-200}"
  local gate_report="${4:-}"
  local slot_offset=$((block_size - 1))
  cat <<PROMPT
```

- [ ] **Step 4: Implement — insert STEP 1B**

In the same function, find:

```
STEP 1 — Sanity-check the brief's stated current-state numbers against a live query before trusting them:
Run: SELECT source, COUNT(*) FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy_map\` WHERE master_table = '${table}' GROUP BY source
If the live counts disagree with what the brief claims, record the discrepancy in findings — do not silently proceed as if the brief were current.

STEP 2 — Claim a ${block_size}-slot SKU block atomically (DECLARE before BEGIN TRANSACTION — reversing that order is a real BigQuery scripting syntax error):
```

Replace with:

```
STEP 1 — Sanity-check the brief's stated current-state numbers against a live query before trusting them:
Run: SELECT source, COUNT(*) FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy_map\` WHERE master_table = '${table}' GROUP BY source
If the live counts disagree with what the brief claims, record the discrepancy in findings — do not silently proceed as if the brief were current.

STEP 1B — Pre-fix QA gate report (already run before this session, informational only — this is a Brief-mode
session, so your scope is exactly what STEP 3's Brief section specifies, not expanded by this report):
${gate_report}
If any FAILing gate above touches rows your Brief already covers, treat it as corroborating signal. If a
FAILing gate touches rows outside the Brief's stated scope, do not act on it — note it in findings so a future
session can pick it up; this session does exactly what the Brief says, nothing more.

STEP 2 — Claim a ${block_size}-slot SKU block atomically (DECLARE before BEGIN TRANSACTION — reversing that order is a real BigQuery scripting syntax error):
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: `PASS: build_prompt gate_report (STEP 1B)`, and every earlier `PASS:` line still prints (the file
runs top to bottom and `set -e`-exits on the first failure, so seeing later PASS lines confirms nothing
earlier broke).

- [ ] **Step 6: Commit**

```bash
git add script/targeted_qa_fix.sh script/test_targeted_qa_fix.sh
git commit -m "build_prompt: add gate_report param, insert informational STEP 1B (Brief mode)"
```

---

### Task 3: `build_auto_discovery_prompt` gains `gate_report` (auto-discovery mode STEP 1B, fix-direction)

**Files:**
- Modify: `script/targeted_qa_fix.sh:102-303` (the `build_auto_discovery_prompt` function)
- Test: `script/test_targeted_qa_fix.sh`

**Interfaces:**
- Consumes: nothing new from other tasks.
- Produces: `build_auto_discovery_prompt(table, category_file, block_size, gate_report)` — 4th positional
  arg, defaults to empty string. Task 4's `main()` will call this with all four args.

- [ ] **Step 1: Write the failing test**

Open `script/test_targeted_qa_fix.sh` and add this block directly after the existing
`# --- build_auto_discovery_prompt ---` section (after the line `echo "PASS: build_auto_discovery_prompt"`,
i.e. after line 121 in the current file):

```bash
# --- build_auto_discovery_prompt: gate_report parameter (STEP 1B, fix-direction) ---
prompt=$(build_auto_discovery_prompt "shopee_th_suncare" "docs/categories/th_suncare.md" "200" "[FAIL] garbled brand text:       4")
echo "$prompt" | grep -q "STEP 1B" || fail "build_auto_discovery_prompt should insert a STEP 1B pre-fix gate report block"
echo "$prompt" | grep -qF "[FAIL] garbled brand text:       4" || fail "build_auto_discovery_prompt must interpolate the passed gate_report verbatim"
for gate in "placeholder-leak" "structured-fields NULL%" "'all variant/size' name" "canonical_name fields" "garbled brand text"; do
  echo "$prompt" | grep -qF "$gate" || fail "build_auto_discovery_prompt STEP 1B must name entry-level gate: $gate"
done
echo "$prompt" | grep -q "no LLM judgment needed to detect it, only to decide and apply the correct fix" || fail "STEP 1B must give entry-level gates fix-direction language"
for gate in "dual-mapped (LLM)" "HUMAN+LLM coexistence" "duplicate product_id" "duplicate product+taxon"; do
  echo "$prompt" | grep -qF "$gate" || fail "build_auto_discovery_prompt STEP 1B must name map-level gate: $gate"
done
echo "$prompt" | grep -q "do NOT attempt a fix" || fail "STEP 1B must mark map-level gates report-only"
echo "$prompt" | grep -q "flagged as needing a deletion-authorized session" || fail "STEP 1B must flag map-level failures for a deletion-authorized session"
echo "PASS: build_auto_discovery_prompt gate_report (STEP 1B)"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: `FAIL: build_auto_discovery_prompt should insert a STEP 1B pre-fix gate report block`

- [ ] **Step 3: Implement — add the 4th parameter**

In `script/targeted_qa_fix.sh`, find:

```bash
build_auto_discovery_prompt() {
  local table="$1"
  local category_file="$2"
  local block_size="${3:-200}"
  local slot_offset=$((block_size - 1))
  cat <<PROMPT
```

Replace with:

```bash
build_auto_discovery_prompt() {
  local table="$1"
  local category_file="$2"
  local block_size="${3:-200}"
  local gate_report="${4:-}"
  local slot_offset=$((block_size - 1))
  cat <<PROMPT
```

- [ ] **Step 4: Implement — insert STEP 1B**

In the same function, find (this is the end of STEP 1's worklist query, immediately followed by STEP 2):

```
WHERE m.master_table = '${table}'
  AND (pt._meta IS NULL OR IFNULL(JSON_VALUE(pt._meta, '$.review_confidence'), 'unreviewed') != 'confident')

STEP 2 — Tier 1: run this SQL sweep over that same worklist to flag mechanical defects cheaply, before
spending any LLM judgment. canonical_field_mismatch mirrors script/qa_report.sh's independent
```

Replace with:

```
WHERE m.master_table = '${table}'
  AND (pt._meta IS NULL OR IFNULL(JSON_VALUE(pt._meta, '$.review_confidence'), 'unreviewed') != 'confident')

STEP 1B — Pre-fix QA gate report (already run before this session):
${gate_report}

The gates above split into two classes. For any FAILing gate in this list — placeholder-leak,
structured-fields NULL%, 'all variant/size' name, canonical_name fields, garbled brand text — treat every row
it flags as an automatic candidate needing a fix, the same way a Tier 1 SQL hit below does: no LLM judgment
needed to detect it, only to decide and apply the correct fix (a gate can still false-positive — e.g. the
'all variant/size' gate flagging legitimate text like "All Skin Types" — sanity-check before applying, don't
blind-apply). Get the actual affected rows by adapting that gate's own query from
docs/headless-runbook.md's QA-gate-as-code section (drop the outer COUNT(*), select the underlying columns
instead) — do not guess which rows failed from the count alone.

For any FAILing gate in this list instead — dual-mapped (LLM), HUMAN+LLM coexistence, duplicate product_id,
duplicate product+taxon — do NOT attempt a fix: every one of these can only be resolved by deleting or
re-mapping a product_taxonomy_map row, and this session never deletes an existing row (STEP 7). Record the
gate name and count in findings instead, flagged as needing a deletion-authorized session. Note also: the
post-fix independent qa_report.sh re-check (STEP 10) re-runs these same gates — if one is failing here, it
will fail there too regardless of how well this session's fixes go, so a FAILED_QA outcome driven by a gate
this session was never able to touch is expected, not a sign the session did anything wrong.

STEP 2 — Tier 1: run this SQL sweep over that same worklist to flag mechanical defects cheaply, before
spending any LLM judgment. canonical_field_mismatch mirrors script/qa_report.sh's independent
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: `PASS: build_auto_discovery_prompt gate_report (STEP 1B)`, and every earlier `PASS:` line still
prints.

- [ ] **Step 6: Commit**

```bash
git add script/targeted_qa_fix.sh script/test_targeted_qa_fix.sh
git commit -m "build_auto_discovery_prompt: add gate_report param, insert fix-direction STEP 1B"
```

---

### Task 4: Wire pre-fix gate capture + end-of-run coverage trap into `main()`

**Files:**
- Modify: `script/targeted_qa_fix.sh:393-483` (the `main` function)
- Test: `script/test_targeted_qa_fix.sh`

**Interfaces:**
- Consumes: `build_prompt(table, category_file, block_size, gate_report)` and
  `build_auto_discovery_prompt(table, category_file, block_size, gate_report)` from Tasks 2–3.
  `./script/qa_coverage_report.sh <master_table>` from Task 1.
- Produces: nothing consumed by a later task — this is the last code task.

- [ ] **Step 1: Write the failing test**

`main()` calls `bq`/`claude` directly, so it can't be exercised end-to-end without live credentials (same
standing exemption `qa_report.sh` and `main()`'s existing untested paths carry). Test the wiring by asserting
on the script's own source text instead — the same style this file already uses for `resolve_category_file`
being called correctly from the two branches. Add this block to the end of `script/test_targeted_qa_fix.sh`,
directly before the final `echo "ALL TESTS PASSED"` line:

```bash
# --- main(): pre-fix gate capture + coverage EXIT trap wiring ---
script_src=$(cat script/targeted_qa_fix.sh)
echo "$script_src" | grep -qF 'gate_report=$(./script/qa_report.sh "$table")' || fail "main() must capture qa_report.sh output before building the prompt"
echo "$script_src" | grep -qF 'QA_FIX_TABLE="$table"' || fail "main() must set QA_FIX_TABLE as a global for the EXIT trap to see"
echo "$script_src" | grep -q 'trap.*qa_coverage_report\.sh.*EXIT' || fail "main() must set an EXIT trap invoking qa_coverage_report.sh"
echo "$script_src" | grep -qF 'build_prompt "$table" "$category_file" "$block_size" "$gate_report"' || fail "brief-mode call site must pass gate_report to build_prompt"
echo "$script_src" | grep -qF 'build_auto_discovery_prompt "$table" "$category_file" "$block_size" "$gate_report"' || fail "auto-discovery call site must pass gate_report to build_auto_discovery_prompt"
echo "PASS: main() gate report capture + coverage trap wiring"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: `FAIL: main() must capture qa_report.sh output before building the prompt`

- [ ] **Step 3: Implement**

In `script/targeted_qa_fix.sh`, find:

```bash
  local category_file
  if ! category_file=$(resolve_category_file "$table"); then
    echo "ERROR: no category file found at docs/categories/${table}.md or docs/categories/${table#shopee_}.md" >&2
    echo "A Targeted QA Fix requires an existing, documented category — write the category file (and its '## Targeted QA Fix Brief' section) first." >&2
    exit 1
  fi

  echo "${table}"

  local prompt
  if [[ "$(has_real_brief "$category_file")" == "true" ]]; then
    echo "TARGETED QA FIX STARTED (brief mode: ${category_file}, block_size=${block_size}, max_turns=${max_turns})"
    echo "==========================="
    prompt=$(build_prompt "$table" "$category_file" "$block_size")
  else
    echo "TARGETED QA FIX STARTED (auto-discovery mode: ${category_file}, block_size=${block_size}, max_turns=${max_turns})"
    echo "==========================="
    prompt=$(build_auto_discovery_prompt "$table" "$category_file" "$block_size")
  fi
```

Replace with:

```bash
  local category_file
  if ! category_file=$(resolve_category_file "$table"); then
    echo "ERROR: no category file found at docs/categories/${table}.md or docs/categories/${table#shopee_}.md" >&2
    echo "A Targeted QA Fix requires an existing, documented category — write the category file (and its '## Targeted QA Fix Brief' section) first." >&2
    exit 1
  fi

  # Global, not local: this EXIT trap fires after main() itself may have returned, when a `local` would
  # already be out of scope. Every exit from here on (blocked/failed/noop/success) reports coverage.
  QA_FIX_TABLE="$table"
  trap './script/qa_coverage_report.sh "$QA_FIX_TABLE" || true' EXIT

  echo "${table}"

  echo "Running pre-fix QA gate report..."
  local gate_report
  gate_report=$(./script/qa_report.sh "$table") || true

  local prompt
  if [[ "$(has_real_brief "$category_file")" == "true" ]]; then
    echo "TARGETED QA FIX STARTED (brief mode: ${category_file}, block_size=${block_size}, max_turns=${max_turns})"
    echo "==========================="
    prompt=$(build_prompt "$table" "$category_file" "$block_size" "$gate_report")
  else
    echo "TARGETED QA FIX STARTED (auto-discovery mode: ${category_file}, block_size=${block_size}, max_turns=${max_turns})"
    echo "==========================="
    prompt=$(build_auto_discovery_prompt "$table" "$category_file" "$block_size" "$gate_report")
  fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: `PASS: main() gate report capture + coverage trap wiring`, followed by `ALL TESTS PASSED`.

- [ ] **Step 5: Syntax-check the full script once more**

Run: `bash -n script/targeted_qa_fix.sh`
Expected: no output, exit code 0.

- [ ] **Step 6: Commit**

```bash
git add script/targeted_qa_fix.sh script/test_targeted_qa_fix.sh
git commit -m "main(): capture pre-fix qa_report.sh output, add EXIT trap reporting coverage every run"
```

---

### Task 5: Update `docs/headless-runbook.md`

**Files:**
- Modify: `docs/headless-runbook.md` (the "Scenario: Targeted QA Fix" section)

**Interfaces:**
- Consumes: nothing (documentation only).
- Produces: nothing consumed by another task.

- [ ] **Step 1: Implement**

Find this block (the numbered procedure under "## Scenario: Targeted QA Fix"):

```
1. Claim a ~200-slot block (Shared mechanics § Atomic SKU block claim, `@block_size = 200`, `@scenario =
   'targeted_qa_fix'`).
2. Invoke `claude -p` with the claimed range and the specific fix list (pack-count corrections, wrong-size
   reroutes, bundle tagging — see the Notion doc's Example C pattern), `--max-turns 30`.
3. Run QA gates (Shared mechanics § QA-gate-as-code) scoped to `master_table = @table` — the gate queries
   already scope by `master_table`, no change needed for the narrower fix scope.
4. If gates pass, run universe refresh (Shared mechanics § Universe refresh) for `@table`.
5. If `claude -p` fails or gates fail, mark the claimed block `FAILED_QA` in `sku_block_registry`:
   ```sql
   UPDATE `sincere-hearth-273704.magpie_reference.sku_block_registry`
   SET status = 'FAILED_QA' WHERE block_start = @claimed_block_start AND master_table = @table;
   ```
```

Replace with:

```
1. Claim a ~200-slot block (Shared mechanics § Atomic SKU block claim, `@block_size = 200`, `@scenario =
   'targeted_qa_fix'`).
2. Run `qa_report.sh @table` *before* invoking `claude -p` and pass its output into the prompt as
   gate-directed scope: entry-level gate failures (placeholder-leak, structured-fields NULL%, 'all
   variant/size' name, canonical_name fields, garbled brand text) become explicit fix targets; map-level
   failures (dual-mapped, HUMAN+LLM coexistence, duplicate product_id, duplicate product+taxon) are
   report-only, since this scenario never deletes a `product_taxonomy_map` row. See
   [docs/superpowers/specs/2026-07-23-qa-fix-gate-direction-and-coverage-design.md](superpowers/specs/2026-07-23-qa-fix-gate-direction-and-coverage-design.md)
   for the full mechanics.
3. Invoke `claude -p` with the claimed range and the specific fix list (pack-count corrections, wrong-size
   reroutes, bundle tagging — see the Notion doc's Example C pattern), `--max-turns 30`.
4. Run QA gates (Shared mechanics § QA-gate-as-code) scoped to `master_table = @table` — the gate queries
   already scope by `master_table`, no change needed for the narrower fix scope.
5. If gates pass, run universe refresh (Shared mechanics § Universe refresh) for `@table`.
6. If `claude -p` fails or gates fail, mark the claimed block `FAILED_QA` in `sku_block_registry`:
   ```sql
   UPDATE `sincere-hearth-273704.magpie_reference.sku_block_registry`
   SET status = 'FAILED_QA' WHERE block_start = @claimed_block_start AND master_table = @table;
   ```
7. Regardless of outcome (blocked, failed, noop, or refreshed), run `qa_coverage_report.sh @table` and report
   the pending-review count — this always fires, via an `EXIT` trap in `script/targeted_qa_fix.sh`, not a
   conditional step an operator has to remember to run.
```

- [ ] **Step 2: Verify the edit**

Run: `grep -n "qa_coverage_report.sh\|Run \`qa_report.sh @table\` \*before\*" docs/headless-runbook.md`
Expected: both new lines print with their line numbers — confirms the edit landed.

- [ ] **Step 3: Commit**

```bash
git add docs/headless-runbook.md
git commit -m "docs: update Targeted QA Fix runbook for pre-fix gate direction + coverage report"
```

---

## Self-Review Notes

- **Spec coverage:** §1 (pre-fix gate, entry/map split, both modes) → Tasks 2–4. §2 (`qa_coverage_report.sh`,
  `EXIT` trap) → Tasks 1 and 4. §3 (runbook doc update) → Task 5. §4 (testing) → each task's own Steps 1–2 plus
  Task 4's source-grep tests for `main()`. No spec section without a task.
- **Placeholder scan:** no TBD/TODO; every step has literal code, not a description of code.
- **Type consistency:** `build_prompt`/`build_auto_discovery_prompt` both go from 3 to 4 positional params in
  the same order (`table, category_file, block_size, gate_report`) across Tasks 2–4; `main()`'s call sites in
  Task 4 match that exact order. `QA_FIX_TABLE` is the one deliberately-global (non-`local`) variable, used
  consistently between its assignment and the trap in Task 4.
