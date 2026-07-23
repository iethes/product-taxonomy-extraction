# QA Fix Throughput Diagnosis Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix three independent bugs found in `targeted_qa_fix.sh` auto-discovery sessions: a coverage-report
metric that hides real fix work, a permanent-false-positive tax with no way to close it, and a QA History
append that can silently overwrite a prior session's record instead of adding to it.

**Architecture:** Three surgical changes to existing bash/BigQuery scripts, no new services: (1) a read-only
query change in `qa_coverage_report.sh`, (2) a new BigQuery exceptions table plus one added `WHERE` clause per
gate in `qa_report.sh`, (3) a new pure bash function plus a JSON schema field that moves QA History writes
from agent-driven `Edit`+`git commit` to deterministic script-side `sed`+`git commit`.

**Tech Stack:** bash (`set -euo pipefail`), BigQuery (`bq query --use_legacy_sql=false`), `jq`, `claude -p`.

## Global Constraints

- BigQuery project: `sincere-hearth-273704`. Reference dataset: `magpie_reference`.
- Every new/updated row written to any `magpie_reference` table must set `meta_agent = 'CLAUDE_CODE'` when
  written by an agent session (per `CLAUDE.md`'s meta_agent rule) — applies to `qa_gate_exceptions` inserts.
- All modified scripts keep `set -euo pipefail` and the existing `bq query --use_legacy_sql=false
  --project_id="${PROJECT}"` invocation style already used throughout this repo.
- Companion spec: [`docs/superpowers/specs/2026-07-23-qa-fix-throughput-diagnosis-design.md`](../specs/2026-07-23-qa-fix-throughput-diagnosis-design.md).
- Test convention: `script/test_targeted_qa_fix.sh` sources `script/targeted_qa_fix.sh` and asserts via
  `grep` on generated prompt strings and on the raw script source (`script_src=$(cat script/targeted_qa_fix.sh)`)
  — no test framework, no mocked BigQuery. `qa_report.sh` / `qa_coverage_report.sh` have no pure functions and
  carry a standing exemption from unit tests (syntax check + one real manual run against a live table is the
  existing precedent — do not invent a mocking layer for them).

---

### Task 1: Split `qa_coverage_report.sh`'s `unconfident` bucket

**Files:**
- Modify: `script/qa_coverage_report.sh:16-37`

**Interfaces:**
- Produces: four-bucket coverage output (`never_reviewed`, `fixed_pending_recheck`, `unconfident`,
  `confident`) — consumed by nothing else programmatically (it's terminal human/log output), so no other
  file needs to change for this task.

- [ ] **Step 1: Replace the query and print block**

Replace lines 16–37 of `script/qa_coverage_report.sh` (the `bq query ... | while IFS=',' read ...` block)
with:

```bash
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
     COUNTIF(_meta IS NOT NULL AND JSON_VALUE(_meta, '\$.review_confidence') IS NULL) AS fixed_pending_recheck,
     COUNTIF(JSON_VALUE(_meta, '\$.review_confidence') = 'unconfident') AS unconfident,
     COUNTIF(JSON_VALUE(_meta, '\$.review_confidence') = 'confident') AS confident
   FROM distinct_entries" | tail -1 | \
while IFS=',' read -r total never_reviewed fixed_pending_recheck unconfident confident; do
  pending=$((never_reviewed + fixed_pending_recheck + unconfident))
  pct=0
  [ "$total" -gt 0 ] && pct=$(( 100 * pending / total ))
  echo "Pending QA (never-reviewed, fixed-pending-recheck, or unconfident): ${pending} / ${total} (${pct}%)"
  echo "  never reviewed:        ${never_reviewed}"
  echo "  fixed pending recheck: ${fixed_pending_recheck}"
  echo "  unconfident:           ${unconfident}"
  echo "  confident:              ${confident}"
done
```

- [ ] **Step 2: Update the file's header comment**

The comment at the top of `script/qa_coverage_report.sh` (currently "Reports how many product_taxonomy
entries for a table are NOT confidently reviewed yet — the exact _meta criteria targeted_qa_fix.sh's
auto-discovery worklist uses (_meta IS NULL OR review_confidence != 'confident')") gets one sentence appended:

```
# A freshly-fixed row's _meta has no review_confidence key at all (just {"is_reviewed": false}), distinct
# from a row that has been genuinely reviewed at least once (always has a review_confidence key per STEP 5) —
# reported as its own "fixed pending recheck" bucket so real fix throughput isn't hidden inside "unconfident".
```

- [ ] **Step 3: Syntax check**

Run: `bash -n script/qa_coverage_report.sh`
Expected: no output, exit code 0.

- [ ] **Step 4: Manual verification against a live table**

Run: `./script/qa_coverage_report.sh shopee_sg_coffee`
Expected: four lines print (`never reviewed`, `fixed pending recheck`, `unconfident`, `confident`); manually
confirm `never_reviewed + fixed_pending_recheck + unconfident + confident == total` (the `pending` line's
first number over the total shown in parentheses) by re-running with `--format=csv` piped to `cat` if the
arithmetic isn't obviously self-consistent from the printed lines alone.

- [ ] **Step 5: Commit**

```bash
git add script/qa_coverage_report.sh
git commit -m "qa_coverage_report.sh: split unconfident into fixed-pending-recheck vs genuinely-unconfident"
```

---

### Task 2: `qa_gate_exceptions` table + exclusion clauses in `qa_report.sh`

**Files:**
- Modify: `script/qa_report.sh` (all 5 entry-level gate queries)

**Interfaces:**
- Produces: BigQuery table `sincere-hearth-273704.magpie_reference.qa_gate_exceptions` with columns
  `gate_name STRING, master_table STRING, entity_id STRING, reason STRING, confirmed_at TIMESTAMP, meta_agent STRING`.
  Consumed by Task 3's STEP 1B prompt text (which instructs the agent to `SELECT`/`INSERT` against it) and by
  this task's own 5 gate queries.
- Gate name constants used as the `gate_name` value (must match exactly, used again in Task 3):
  `'placeholder-leak'`, `'structured-fields NULL%'`, `'all variant/size name'`, `'canonical_name fields'`,
  `'garbled brand text'`.

- [ ] **Step 1: Create the table**

Run:
```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 \
"CREATE TABLE IF NOT EXISTS \`sincere-hearth-273704.magpie_reference.qa_gate_exceptions\` (
  gate_name STRING NOT NULL,
  master_table STRING NOT NULL,
  entity_id STRING NOT NULL,
  reason STRING,
  confirmed_at TIMESTAMP,
  meta_agent STRING
)"
```
Expected: query succeeds (either creates the table or is a no-op if it already exists from a prior attempt).

- [ ] **Step 2: Verify the table exists with the right schema**

Run: `bq show --format=prettyjson sincere-hearth-273704:magpie_reference.qa_gate_exceptions`
Expected: JSON output listing all 6 fields with the types above.

- [ ] **Step 3: Add the exclusion clause to `PLACEHOLDER` (placeholder-leak)**

In `script/qa_report.sh`, replace:
```sql
   WHERE m.master_table = '${TABLE}'
     AND REGEXP_CONTAINS(LOWER(pt.canonical_name), r'\b(undefined|null|n/a|tbd)\b')" | tail -1)
```
with:
```sql
   WHERE m.master_table = '${TABLE}'
     AND REGEXP_CONTAINS(LOWER(pt.canonical_name), r'\b(undefined|null|n/a|tbd)\b')
     AND pt.taxonomy_id NOT IN (
       SELECT entity_id FROM \`${PROJECT}.magpie_reference.qa_gate_exceptions\`
       WHERE gate_name = 'placeholder-leak' AND master_table = '${TABLE}'
     )" | tail -1)
```

- [ ] **Step 4: Add the exclusion clause to `STRUCT_MISSING` (structured-fields NULL%)**

Replace:
```sql
   FROM (
     SELECT DISTINCT pt.taxonomy_id, pt.product_line, pt.is_multi_size
     FROM \`${PROJECT}.magpie_reference.product_taxonomy\` pt
     JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
     WHERE m.master_table = '${TABLE}' AND m.source = 'LLM'
   )
   WHERE is_multi_size IS NOT TRUE" | tail -1)
```
with:
```sql
   FROM (
     SELECT DISTINCT pt.taxonomy_id, pt.product_line, pt.is_multi_size
     FROM \`${PROJECT}.magpie_reference.product_taxonomy\` pt
     JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
     WHERE m.master_table = '${TABLE}' AND m.source = 'LLM'
       AND pt.taxonomy_id NOT IN (
         SELECT entity_id FROM \`${PROJECT}.magpie_reference.qa_gate_exceptions\`
         WHERE gate_name = 'structured-fields NULL%' AND master_table = '${TABLE}'
       )
   )
   WHERE is_multi_size IS NOT TRUE" | tail -1)
```

- [ ] **Step 5: Add the exclusion clause to `ALL_VARIANT` ('all variant/size' name)**

Replace:
```sql
     WHERE m.master_table = '${TABLE}'
       AND REGEXP_CONTAINS(LOWER(pt.canonical_name), r'\(all\s+(variants?|sizes?)\b|\bmultiple\s+(variants?|sizes?)\b')
   )" | tail -1)
```
with:
```sql
     WHERE m.master_table = '${TABLE}'
       AND REGEXP_CONTAINS(LOWER(pt.canonical_name), r'\(all\s+(variants?|sizes?)\b|\bmultiple\s+(variants?|sizes?)\b')
       AND pt.taxonomy_id NOT IN (
         SELECT entity_id FROM \`${PROJECT}.magpie_reference.qa_gate_exceptions\`
         WHERE gate_name = 'all variant/size name' AND master_table = '${TABLE}'
       )
   )" | tail -1)
```

- [ ] **Step 6: Add the exclusion clause to `CANON_FIELDS` (canonical_name fields)**

Replace the final two lines of that query:
```sql
   AND NOT REGEXP_CONTAINS(LOWER(canonical_name), r'\(all\s+(variants?|sizes?)\b|\bmultiple\s+(variants?|sizes?)\b')" | tail -1)
```
with:
```sql
   AND NOT REGEXP_CONTAINS(LOWER(canonical_name), r'\(all\s+(variants?|sizes?)\b|\bmultiple\s+(variants?|sizes?)\b')
   AND taxonomy_id NOT IN (
     SELECT entity_id FROM \`${PROJECT}.magpie_reference.qa_gate_exceptions\`
     WHERE gate_name = 'canonical_name fields' AND master_table = '${TABLE}'
   )" | tail -1)
```

- [ ] **Step 7: Add the exclusion clause to `GARBAGE_BRAND` (garbled brand text)**

Replace:
```sql
     WHERE m.master_table = '${TABLE}'
       AND NOT REGEXP_CONTAINS(bd.canonical_name, r'[\p{L}]')
   )" | tail -1)
```
with:
```sql
     WHERE m.master_table = '${TABLE}'
       AND NOT REGEXP_CONTAINS(bd.canonical_name, r'[\p{L}]')
       AND bd.brand_id NOT IN (
         SELECT entity_id FROM \`${PROJECT}.magpie_reference.qa_gate_exceptions\`
         WHERE gate_name = 'garbled brand text' AND master_table = '${TABLE}'
       )
   )" | tail -1)
```

- [ ] **Step 8: Syntax check**

Run: `bash -n script/qa_report.sh`
Expected: no output, exit code 0.

- [ ] **Step 9: Structural check — every entry-level gate references the exceptions table**

Run:
```bash
for gate in "placeholder-leak" "structured-fields NULL%" "all variant/size name" "canonical_name fields" "garbled brand text"; do
  grep -qF "gate_name = '${gate}'" script/qa_report.sh || { echo "MISSING: $gate"; exit 1; }
done
echo "all 5 entry-level gates reference qa_gate_exceptions"
```
Expected: `all 5 entry-level gates reference qa_gate_exceptions`, no `MISSING` lines.

- [ ] **Step 10: Manual verification against a live table (no exceptions yet — should be a no-op)**

Run: `./script/qa_report.sh shopee_sg_coffee`
Expected: identical `[PASS]`/`[FAIL]` results to before this change (an empty `qa_gate_exceptions` table
excludes nothing) — `canonical_name fields` and `garbled brand text` still show their pre-existing `[FAIL]`
counts. This confirms the added clauses are syntactically valid and behave as a no-op until Task 5 inserts a
real exception row.

- [ ] **Step 11: Commit**

```bash
git add script/qa_report.sh
git commit -m "Add qa_gate_exceptions table and wire exclusion clauses into qa_report.sh's 5 entry-level gates"
```

---

### Task 3: Exception-aware STEP 1B in `build_auto_discovery_prompt`

**Files:**
- Modify: `script/targeted_qa_fix.sh` (inside `build_auto_discovery_prompt`, the STEP 1B block)
- Test: `script/test_targeted_qa_fix.sh`

**Interfaces:**
- Consumes: `qa_gate_exceptions` table from Task 2 (same `gate_name` string constants).
- Produces: no new bash interface — this only changes prompt text, not function signatures.

- [ ] **Step 1: Write the failing test**

Add to `script/test_targeted_qa_fix.sh`, inside the existing "build_auto_discovery_prompt: gate_report
parameter (STEP 1B, fix-direction)" block (after the existing `for gate in ...` loop and before its final
`echo "PASS: ..."` line):

```bash
echo "$prompt" | grep -q "qa_gate_exceptions" || fail "STEP 1B must have the agent check qa_gate_exceptions before re-verifying a gate"
echo "$prompt" | grep -q "skip re-verifying it entirely" || fail "STEP 1B must tell the agent to skip rows already covered by a confirmed exception"
echo "$prompt" | grep -q "not enough to close it permanently" || fail "STEP 1B must require more than one confirmation before writing a new exception"
```

- [ ] **Step 2: Run the test suite to confirm it fails**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: `FAIL: STEP 1B must have the agent check qa_gate_exceptions before re-verifying a gate` (or similar —
whichever new assertion the current prompt text doesn't satisfy yet).

- [ ] **Step 3: Replace the STEP 1B fix-direction paragraph**

In `build_auto_discovery_prompt` (in `script/targeted_qa_fix.sh`), the current text reads:

```
The gates above split into two classes. For any FAILing gate in this list — placeholder-leak,
structured-fields NULL%, 'all variant/size' name, canonical_name fields, garbled brand text — treat every row
it flags as an automatic candidate needing a fix, the same way a Tier 1 SQL hit below does:
no LLM judgment needed to detect it, only to decide and apply the correct fix (a gate can still
false-positive — e.g. the 'all variant/size' gate flagging legitimate text like "All Skin Types" —
sanity-check before applying, don't blind-apply). Get the actual affected rows by adapting that gate's own
query from docs/headless-runbook.md's QA-gate-as-code section (drop the outer COUNT(*), select the
underlying columns instead) — do not guess which rows failed from the count alone.
```

Replace it with:

```
The gates above split into two classes. For any FAILing gate in this list — placeholder-leak,
structured-fields NULL%, 'all variant/size' name, canonical_name fields, garbled brand text — first check
whether its rows already carry a confirmed exception:
SELECT * FROM \`${PROJECT}.magpie_reference.qa_gate_exceptions\` WHERE gate_name = '<the gate's exact name>' AND master_table = '${table}'.
If an exception already covers a row, skip re-verifying it entirely — it's closed, not a fresh finding. For
rows without an existing exception, treat the flag as an automatic candidate needing a fix, the same way a
Tier 1 SQL hit below does: no LLM judgment needed to detect it, only to decide and apply the correct fix (a
gate can still false-positive — e.g. the 'all variant/size' gate flagging legitimate text like "All Skin
Types" — sanity-check before applying, don't blind-apply). Get the actual affected rows by adapting that
gate's own query from docs/headless-runbook.md's QA-gate-as-code section (drop the outer COUNT(*), select the
underlying columns instead) — do not guess which rows failed from the count alone. If you confirm a row is a
genuine, structural false positive (not a data defect, nothing a fix could ever resolve) — check this
category's QA History for a prior session reaching the same conclusion on the same entity first, since a
single confirmation is not enough to close it permanently, mirroring the existing
confident-after-two-agreeing-reviews rule for regular rows. Once a second (or later) confirmation lands,
insert a row: INSERT INTO \`${PROJECT}.magpie_reference.qa_gate_exceptions\`
(gate_name, master_table, entity_id, reason, confirmed_at, meta_agent) VALUES
('<gate name>', '${table}', '<the brand_id or taxonomy_id>', '<why this is permanent, not a defect>', CURRENT_TIMESTAMP(), 'CLAUDE_CODE')
so no future session re-spends turns on it.
```

Note: `${PROJECT}` and `${table}` are real bash variables already in scope inside `build_auto_discovery_prompt`
(same pattern used throughout the rest of this function's heredoc) — they interpolate to the real project id
and table name when the prompt is built, exactly like the SQL in STEP 1/STEP 2 already does.

- [ ] **Step 4: Run the test suite to confirm the new assertions pass**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: `PASS: build_auto_discovery_prompt gate_report (STEP 1B)` and `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add script/targeted_qa_fix.sh script/test_targeted_qa_fix.sh
git commit -m "build_auto_discovery_prompt: make STEP 1B check/write qa_gate_exceptions instead of re-verifying permanent false positives every session"
```

---

### Task 4: Deterministic QA History append

**Files:**
- Modify: `script/targeted_qa_fix.sh` (new `append_qa_history_row` function; `main()`; STEP 6 in `build_prompt`;
  STEP 9 in `build_auto_discovery_prompt`; the final JSON schema line in both)
- Test: `script/test_targeted_qa_fix.sh`

**Interfaces:**
- Produces: `append_qa_history_row(category_file, finding, resolution, timestamp) -> 0|1` — a pure bash
  function (only touches the one file path passed to it, no globals, no git calls) that inserts a new
  4-column markdown table row immediately before the first `---` line following `## QA History` in
  `category_file`. Returns 1 (and makes no changes) if the file has no `## QA History` heading or no `---`
  after it. Escapes literal `|` in `finding`/`resolution` as `\|` and collapses embedded newlines to spaces
  before inserting, so a malformed agent-supplied string can't corrupt the table's column count.
- Consumes: nothing new — called from `main()` with values pulled from `result_json.qa_history_entry`.

- [ ] **Step 1: Write the failing tests**

Add a new section to `script/test_targeted_qa_fix.sh`, after the existing `has_real_brief` block (before
`build_prompt`'s tests):

```bash
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
```

Also add, inside the existing "build_prompt" and "build_auto_discovery_prompt" test blocks (before their
`echo "PASS: ..."` lines):

```bash
echo "$prompt" | grep -q "qa_history_entry" || fail "build_prompt output schema must include qa_history_entry"
echo "$prompt" | grep -q "Do not edit docs/categories/th_detergent.md or run git yourself" || fail "build_prompt STEP 6 must not have the agent edit the file or commit directly"
```

```bash
echo "$prompt" | grep -q "qa_history_entry" || fail "build_auto_discovery_prompt output schema must include qa_history_entry"
echo "$prompt" | grep -q "Do not edit docs/categories/th_suncare.md or run git yourself" || fail "build_auto_discovery_prompt STEP 9 must not have the agent edit the file or commit directly"
```

(Use the first `prompt=$(build_prompt ...)` / `prompt=$(build_auto_discovery_prompt ...)` calls already in
the file — `th_detergent.md` and `th_suncare.md` respectively — so the interpolated path matches.)

And in the existing "main(): pre-fix gate capture + coverage EXIT trap wiring" block:

```bash
echo "$script_src" | grep -qF 'qa_history_entry' || fail "main() must read qa_history_entry from result_json"
echo "$script_src" | grep -q 'append_qa_history_row' || fail "main() must call append_qa_history_row"
```

- [ ] **Step 2: Run the test suite to confirm it fails**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: fails at `append_qa_history_row: command not found` (function doesn't exist yet).

- [ ] **Step 3: Add the `append_qa_history_row` function**

Add to `script/targeted_qa_fix.sh`, right after the `has_real_brief` function definition and before
`build_prompt`:

```bash
append_qa_history_row() {
  local category_file="$1"
  local finding="$2"
  local resolution="$3"
  local timestamp="$4"
  local qa_history_line divider_line
  qa_history_line=$(grep -n '^## QA History' "$category_file" | head -1 | cut -d: -f1)
  [[ -z "$qa_history_line" ]] && return 1
  divider_line=$(awk -v start="$qa_history_line" 'NR > start && /^---$/ { print NR; exit }' "$category_file")
  [[ -z "$divider_line" ]] && return 1
  finding=$(printf '%s' "$finding" | tr '\n' ' ' | sed 's/|/\\|/g')
  resolution=$(printf '%s' "$resolution" | tr '\n' ' ' | sed 's/|/\\|/g')
  local new_row="| ${timestamp} | Automated review session (auto-discovery) | ${finding} | ${resolution} |"
  sed -i "${divider_line}i ${new_row}" "$category_file"
}
```

- [ ] **Step 4: Run the test suite to confirm the new function's tests pass**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: `PASS: append_qa_history_row`, `PASS: append_qa_history_row missing heading`, then failures on the
`qa_history_entry` prompt-text assertions (not written yet) — that's expected at this point.

- [ ] **Step 5: Update the output JSON schema and STEP 6 in `build_prompt`**

Replace:
```
STEP 6 — Append a dated row to ${category_file}'s '## QA History' table (columns: Date | Pass | Finding | Resolution) summarizing what you did and found this session. Commit the updated file:
git add ${category_file} && git commit -m 'Targeted QA Fix session for ${table}: update QA History'
```
with:
```
STEP 6 — Do not edit ${category_file} or run git yourself. Instead, set the final JSON output's
qa_history_entry field to {finding: "...", resolution: "..."} summarizing what you did and found this
session — the same content that used to go directly into the QA History table's Finding/Resolution columns.
The wrapper appends it to ${category_file} and commits on your behalf after you finish.
```

Replace:
```
Output ONLY this JSON when done, nothing else:
{status: complete|partial|failed|blocked, rows_created, rows_mapped, taxonomy_id_range_used, findings, blockers}.
PROMPT
}

build_auto_discovery_prompt() {
```
with:
```
Output ONLY this JSON when done, nothing else:
{status: complete|partial|failed|blocked, rows_created, rows_mapped, taxonomy_id_range_used, qa_history_entry: null|{finding, resolution}, findings, blockers}.
PROMPT
}

build_auto_discovery_prompt() {
```

(This edits the shared boundary between the two functions in one pass — the `Output ONLY this JSON...` line
is `build_prompt`'s; `build_auto_discovery_prompt`'s own copy is a separate occurrence, handled in Step 6.)

- [ ] **Step 6: Update the output JSON schema and STEP 9 in `build_auto_discovery_prompt`**

Replace:
```
STEP 9 — Append a dated row to ${category_file}'s '## QA History' table (columns: Date | Pass | Finding |
Resolution) summarizing what you reviewed, what you fixed, and the confidence distribution you left behind.
Commit the updated file:
git add ${category_file} && git commit -m 'Automated review session for ${table}: update QA History'
```
with:
```
STEP 9 — Do not edit ${category_file} or run git yourself. Instead, set the final JSON output's
qa_history_entry field to {finding: "...", resolution: "..."} summarizing what you reviewed, what you fixed,
and the confidence distribution you left behind — the same content that used to go directly into the QA
History table's Finding/Resolution columns. The wrapper appends it to ${category_file} and commits on your
behalf after you finish.
```

Replace this function's own copy of:
```
Output ONLY this JSON when done, nothing else:
{status: complete|partial|failed|blocked, rows_created, rows_mapped, taxonomy_id_range_used, findings, blockers}.
PROMPT
}

# The prompt instructs the model to output ONLY JSON,
```
with:
```
Output ONLY this JSON when done, nothing else:
{status: complete|partial|failed|blocked, rows_created, rows_mapped, taxonomy_id_range_used, qa_history_entry: null|{finding, resolution}, findings, blockers}.
PROMPT
}

# The prompt instructs the model to output ONLY JSON,
```

- [ ] **Step 7: Wire `append_qa_history_row` into `main()`**

In `main()`, right after the existing JSON-normalization block (the `if ! echo "$result_json" | jq -e . ...`
block) and before `local decision; decision=$(decide_next_step "$result_json")`, insert:

```bash
  local qa_finding qa_resolution
  qa_finding=$(echo "$result_json" | jq -r '.qa_history_entry.finding // empty')
  qa_resolution=$(echo "$result_json" | jq -r '.qa_history_entry.resolution // empty')
  if [[ -n "$qa_finding" ]]; then
    local qa_timestamp
    qa_timestamp=$(date -u +'%Y-%m-%d %H:%M UTC')
    if append_qa_history_row "$category_file" "$qa_finding" "$qa_resolution" "$qa_timestamp"; then
      echo "Appending QA History row and committing..."
      git add "$category_file"
      git commit -m "Automated review session for ${table}: update QA History"
    else
      echo "WARNING: could not append QA History row (no '## QA History' heading or closing '---' found in ${category_file}) — skipping commit." >&2
    fi
  fi
```

- [ ] **Step 8: Run the full test suite**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 9: Commit**

```bash
git add script/targeted_qa_fix.sh script/test_targeted_qa_fix.sh
git commit -m "targeted_qa_fix.sh: move QA History append from agent-driven Edit+commit to deterministic script-side append"
```

---

### Task 5: Backfill the "888" exception and update the runbook

**Files:**
- Modify: `docs/headless-runbook.md:271-301` (Scenario: Targeted QA Fix, steps 2 and 7)

**Interfaces:** none — documentation and one-time data backfill, no code interfaces.

- [ ] **Step 1: Confirm the current brand_id for the "888" false positive**

Run:
```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=csv \
"SELECT brand_id, canonical_name FROM \`sincere-hearth-273704.magpie_reference.brand_dict\` WHERE canonical_name = '888'"
```
Expected: one row, `brand_id = BRD-SG-06081` (per 9 consecutive confirmations already recorded in
`docs/categories/shopee_sg_coffee.md`'s QA History — passes #7, #8, #9, #10, #13, #16, and #19's "9th
consecutive confirmation").

- [ ] **Step 2: Insert the backfilled exception row**

Run:
```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 \
"INSERT INTO \`sincere-hearth-273704.magpie_reference.qa_gate_exceptions\`
 (gate_name, master_table, entity_id, reason, confirmed_at, meta_agent)
 VALUES ('garbled brand text', 'shopee_sg_coffee', 'BRD-SG-06081',
 'Real, self-stated all-numeral brand (888) appearing on its own products packaging — the letters-only regex r[\\\\p{L}] structurally cannot express this; reconfirmed as a non-defect 9 consecutive sessions (passes #7-#19)',
 CURRENT_TIMESTAMP(), 'CLAUDE_CODE')"
```

- [ ] **Step 3: Verify the gate now passes**

Run: `./script/qa_report.sh shopee_sg_coffee`
Expected: `[PASS] garbled brand text:       0` (previously `[FAIL] garbled brand text:       16`).

- [ ] **Step 4: Update `docs/headless-runbook.md` step 2**

In the "Scenario: Targeted QA Fix" numbered procedure, step 2 currently ends with a link to the
2026-07-23 gate-direction design. Append one sentence after that link (still inside step 2):

```
Since [docs/superpowers/specs/2026-07-23-qa-fix-throughput-diagnosis-design.md](superpowers/specs/2026-07-23-qa-fix-throughput-diagnosis-design.md),
a confirmed permanent false positive on an entry-level gate (e.g. an all-numeral brand tripping the
letters-only `garbled brand text` check) can be recorded once in `magpie_reference.qa_gate_exceptions` so
later sessions stop re-verifying it every run.
```

- [ ] **Step 5: Update `docs/headless-runbook.md` step 7**

Replace:
```
7. Regardless of outcome (blocked, failed, noop, or refreshed), run `qa_coverage_report.sh @table` and report
   the pending-review count — this always fires, via an `EXIT` trap in `script/targeted_qa_fix.sh`, not a
   conditional step an operator has to remember to run.
```
with:
```
7. Regardless of outcome (blocked, failed, noop, or refreshed), run `qa_coverage_report.sh @table` and report
   the pending-review count — this always fires, via an `EXIT` trap in `script/targeted_qa_fix.sh`, not a
   conditional step an operator has to remember to run. Since
   [docs/superpowers/specs/2026-07-23-qa-fix-throughput-diagnosis-design.md](superpowers/specs/2026-07-23-qa-fix-throughput-diagnosis-design.md),
   this report splits into four buckets, not three — a freshly-fixed row awaiting its next re-review
   ("fixed pending recheck") is reported separately from a row that has been genuinely reviewed and still
   isn't confident, so real fix throughput within a session is visible instead of hidden inside a single
   "unconfident" number.
```

- [ ] **Step 6: Commit**

```bash
git add docs/headless-runbook.md
git commit -m "headless-runbook.md: document qa_gate_exceptions and the 4-bucket coverage report"
```

---

## Plan self-review notes

- **Spec coverage:** Section 1 (coverage split) → Task 1. Section 2 (exceptions table + gate exclusions +
  STEP 1B) → Tasks 2–3. Section 3 (deterministic append) → Task 4. The design's "one-time backfill" and
  runbook cross-reference → Task 5. All four spec sections have a task.
- **Type consistency:** `append_qa_history_row`'s 4 positional args (`category_file, finding, resolution,
  timestamp`) are used identically in its Task 4 Step 1 test calls and its Step 7 `main()` call site.
  `qa_gate_exceptions`'s 6 columns (Task 2 Step 1) are referenced with the same names in every `INSERT`/
  `SELECT` in Tasks 3 and 5 — no renamed columns between tasks.
- **No placeholders:** every SQL/bash block above is complete, copy-pasteable text, not a description of what
  to write.
