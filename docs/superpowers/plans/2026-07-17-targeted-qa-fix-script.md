# Targeted QA Fix Script Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `script/targeted_qa_fix.sh <TABLE>` — a repeatable wrapper for the "Scenario: Targeted QA Fix"
procedure in `docs/headless-runbook.md` — and give it real input by adding the TH detergent fix brief to
`docs/categories/th_detergent.md`.

**Architecture:** A single bash script whose pure, side-effect-free helper functions (category-file resolution,
`claude -p` prompt construction, JSON-status decision logic) are unit-testable via a `source`-and-call self-test
script with no network/BQ/`claude` calls. Those helpers are then wired into a `main()` that makes the real
`claude -p`, `bq`, and `./script/qa_report.sh` calls — verified only by `bash -n` and argument-error smoke tests,
per the design spec's stated testing scope (no BQ-hitting or claude-invoking automated test is in scope; running
this script for real is a separate, costly production decision).

**Tech Stack:** bash, `jq` (present at `/usr/bin/jq`, already available — no new dependency), `bq` CLI,
`claude` CLI.

## Global Constraints

- Script call signature: `script/targeted_qa_fix.sh <TABLE>` — one positional argument, no flags (matches
  `script/headless_taxonomy.sh`'s shape).
- `--max-turns 30` for the `claude -p` call (per `docs/headless-runbook.md` § Scenario: Targeted QA Fix).
- SKU block size: 200 slots, `scenario = 'targeted_qa_fix'`.
- QA gating reuses `./script/qa_report.sh <TABLE>` as-is (no `--skip-coexistence` flag — for a Targeted QA Fix,
  HUMAN+LLM coexistence is always a genuine bug per the runbook, never an expected mid-rebuild state).
- Universe refresh targets `sincere-hearth-273704.magpie_reference.universe_taxonomy_overlay` only. No farsight
  refresh (see spec's "Farsight is intentionally dropped" note — `docs/headless-runbook.md` supersedes the
  farsight instruction in the original pasted brief).
- Never write a fake/placeholder test. The self-test file (`script/test_targeted_qa_fix.sh`) is the one runnable
  check for this script's logic, per this repo's lean-test convention already used by `script/qa_report.sh`
  (which has no test file at all, being pure BQ I/O) — we test what's testable without a live BQ/claude call and
  no more.
- Full spec: `docs/superpowers/specs/2026-07-17-targeted-qa-fix-script-design.md`.

---

### Task 1: TH detergent Targeted QA Fix Brief + QA History section

**Files:**
- Modify: `docs/categories/th_detergent.md`

**Interfaces:**
- Produces: a `## Targeted QA Fix Brief` section (read by the `claude -p` prompt built in Task 2) and an empty
  `## QA History` section (header row only, using `_TEMPLATE.md`'s `Date | Pass | Finding | Resolution` shape —
  the agent appends its own row here during a real run, this task just creates the table so appending is
  well-defined).

This is a documentation-only task — there's no code to unit test. The "test cycle" here is: the file must
contain both headings, in valid markdown, appended after the existing content (not replacing anything).

- [ ] **Step 1: Confirm current file end-state before editing**

Run: `tail -5 docs/categories/th_detergent.md`

Expected output (the file as it exists today, ending with the Map Row Counts table):
```
| Source | Count | Notes |
|--------|-------|-------|
| LLM/OFFICIAL | 949 | Pass 1 |
| LLM/RESELLER | 948 | Pass 2, keyword routing from sku_name |
| HUMAN | 1,584 | Deleted; 2,606 retained (long-tail) |
```

- [ ] **Step 2: Append the Targeted QA Fix Brief and QA History sections**

Append this exact content to the end of `docs/categories/th_detergent.md` (add a blank line after the existing
last line first, then this block):

```markdown

---

## Targeted QA Fix Brief

> Source: TH Detergent QA Fix session brief (brainstormed 2026-07-17). Read this whole section as the
> scope for the next `script/targeted_qa_fix.sh shopee_th_detergent` run — it is the actual work, not
> background.

**Verdict: TARGETED FIX (not full rebuild).** Product line names are good quality. The single structural
failure is `pack_count=1` on every entry. Three secondary issues: wrong sizes on range-listings, bundle
misclassification, and high-GMV NULLs.

### Fix A — Pack_count multiplier expansion (MAIN TASK)

Every taxonomy entry at SKU-010xxx has `pack_count=1`. But ~20 of the top 50 products are bulk/multipack
listings. Examples:

- product_id 7180456348: `"[ยกลัง] 1100ml x6"` → canonical shows ×1
- product_id 8079936096: `"[ยกลัง] 4000g x3"` → canonical shows ×1
- product_id 13622158377: `"(1+1) 1500ml"` → canonical shows ×1
- product_id 2416987716: `"9,000g 2 ถุง"` → canonical shows ×1
- product_id 19159538388: `"[3แถม1] 1.8L x4"` → canonical shows ×1

**Approach:**
1. Pre-flight: claim the SKU block via the atomic `sku_block_registry` transaction immediately before the
   first insert. Do not trust this brief's numbers — a parallel session may have run since it was written.
2. Scan all LLM map rows for `shopee_th_detergent`, parse the multiplier from `sku_name` using these patterns
   (most specific first):
   - `[ยกลัง] N ถุง` / `N แกลลอน` → pack_count = N
   - `×12` / `x12` / `X12` → pack_count = 12
   - `[แพ็ค N]` / `แพ็ค N ถุง` → pack_count = N
   - `N แถม N` (same product) → pack_count = first N + second N
   - `(1+1)` / `1+1` → pack_count = 2
   - `N ชิ้น` (where N > 1) → pack_count = N
   - Default → pack_count = 1 (skip, already correct)
3. For each `(taxonomy_id, target_pack_count)` pair: check whether a variant entry already exists
   (`canonical_name LIKE '% xN'`). If yes, reroute the product to the existing variant. If no, create a new
   entry: `canonical_name = base_canonical + ' x' + N`. Reroute = DELETE old map row + INSERT new map row.
4. Dedup: `GROUP BY product_id` when querying — one product can have multiple model rows. Always keep exactly
   one map row per product_id.

### Fix B — Wrong-size reroutes (~6 products)

- **Product 22777858052**: `"[ทั้งหมด 6 ถุง] 1200-1350ml"` → currently at SKU-010000 (wrong product + wrong
  size). Find the correct Breeze Excel entry, create a ×6 variant.
- **Product 42226467434**: `"3.2-3.4L (เลือกสูตรด้านใน)"` → currently at SKU-010021 (3200ml).
  `เลือกสูตรด้านใน` = "formula selector inside" — this is a multi-variant listing, not a size range. DML
  UPDATE: set `is_multi_variant=TRUE`, `size=NULL`.

### Fix C — Bundle + multi-variant tagging

- **Product 42601768145**: `"[Exclusive Set] Breeze Excel Cotton Candy 1100ml + Comfort Beauty Perfume
  1050ml"` → currently at SKU-010009 (Breeze only). Create a new entry: "Breeze Excel Signature + Comfort Set
  1100ml", `is_bundle=TRUE`. Reroute the product to the new bundle entry.
- **Product 29119882389**: `"[ซื้อคู่] Hygiene wash 2800ml + fabric softener 3300ml"` → create a bundle entry:
  "Hygiene Expert Wash + Fabric Softener Set", `is_bundle=TRUE`, `size=NULL`, `pack_count=1`.

### NULL coverage pass — top 100 NULL products

Re-query NULLs **after** Fix A completes — many will be auto-covered by the new xN variants. Then handle the
remaining high-value NULLs:

**Needs a new taxonomy entry:**
- 40368556782: Nancy Oxy powder 24 pcs/box → create "Nancy Oxy Powder 24-pack"
- 24422635034: Lion SUPER NANOX Anti-Bacteria → create a new product line entry
- 46802825229: P&G Bold Power Gel Ball 4D → create "Bold Power Gel Ball 4D"
- 26623461217: Haiter Color 800ml แพค 3 → create "Haiter Color Liquid 800ml x3"

**OOS / leave NULL (do not map):**
- 27834214127: fabric bleach powder (stain remover, not detergent)
- 4510907051: DIY raw chemicals kit
- 4235171948: pool chemical
- 22371042619: DMSO industrial chemical

### QA gates (run before universe refresh)

Handled by `script/qa_report.sh shopee_th_detergent` (no `--skip-coexistence` — coexistence must be a genuine
0 for a Targeted QA Fix). In addition to the standard 4 gates, spot-check:

```sql
-- Pack count distribution should now include x2/x3/x4/x6/x12 variants
SELECT pack_count, COUNT(*) n FROM product_taxonomy
WHERE taxonomy_id LIKE 'SKU-010%' GROUP BY 1 ORDER BY pack_count;

-- Confirm top-5 GMV products now have correct pack_count
-- product 7180456348  → expect pack_count=6
-- product 8079936096  → expect pack_count=3
-- product 13622158377 → expect pack_count=2
```

### Universe refresh

Runs after gates pass, scoped to `shopee_th_detergent` only, `sincere-hearth-273704` overlay table only (see
`docs/headless-runbook.md` § Universe refresh — farsight refresh is dropped for this design, no farsight
equivalent of `universe_taxonomy_overlay` exists). `shopee_th_detergent` maps to multiple `category_3` values
(Laundry Detergent + Baby Laundry Detergent at minimum) — the standard NIQ-join MERGE already handles this
correctly, no per-category_3 filter needed.

### Reference

- Extraction rules: `docs/llm-extraction-rules.md` §1 (pack) + §2 (size)
- Prior art (pack multiplier): th_liquid_milk, th_pet_food sessions (see `docs/llm-extraction-rules.md`
  changelog)
- Prior art (bundle): th_softdrink QA sessions
- SKU-010xxx = detergent block (191 entries used, 809 remain at 010191–010999) — new entries for this session
  go in a freshly claimed 200-slot block, never reuse 010191–010999 without re-verifying it's still free.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
```

- [ ] **Step 3: Verify the file is valid and both headings are present**

Run: `grep -n "^## Targeted QA Fix Brief$\|^## QA History$" docs/categories/th_detergent.md`

Expected output (two matches, in this order):
```
50:## Targeted QA Fix Brief
141:## QA History
```
(exact line numbers may differ slightly — what matters is both headings appear, in this order, after the
existing content.)

- [ ] **Step 4: Commit**

```bash
git add docs/categories/th_detergent.md
git commit -m "Add Targeted QA Fix Brief and QA History sections to th_detergent.md

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Pure helper functions + self-test

**Files:**
- Create: `script/targeted_qa_fix.sh`
- Create: `script/test_targeted_qa_fix.sh`

**Interfaces:**
- Produces:
  - `resolve_category_file(table) -> stdout: path, return 0` on success; `return 1`, no stdout, on failure.
    Tries `docs/categories/<table>.md` first, then `docs/categories/<table with leading "shopee_" stripped>.md`.
  - `build_prompt(table, category_file) -> stdout: the full claude -p prompt string`.
  - `decide_next_step(result_json_string) -> stdout: one of BLOCKED | NOOP | MARK_FAILED | GATE_AND_REFRESH`.
- Consumes: nothing from other tasks (this task's functions are pure — no BQ, no `claude`, no network).

This task writes the three testable helper functions and a self-test script that exercises all three via
canned inputs (temp files for `resolve_category_file`, canned JSON strings for `decide_next_step`, substring
checks for `build_prompt`). Task 3 wires these into a real `main()`.

- [ ] **Step 1: Write the failing self-test**

Create `script/test_targeted_qa_fix.sh`:

```bash
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
echo "$prompt" | grep -q "scenario = 'targeted_qa_fix'" || fail "build_prompt should claim a targeted_qa_fix block"
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
echo "PASS: decide_next_step"

echo "ALL TESTS PASSED"
```

- [ ] **Step 2: Run it to confirm it fails (script/targeted_qa_fix.sh doesn't exist yet)**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: FAIL — `source script/targeted_qa_fix.sh` errors with "No such file or directory".

- [ ] **Step 3: Create `script/targeted_qa_fix.sh` with the three helper functions**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: ./script/targeted_qa_fix.sh <TABLE>
# e.g.  ./script/targeted_qa_fix.sh shopee_th_detergent
#
# Runs the "Scenario: Targeted QA Fix" procedure from docs/headless-runbook.md: claim a small SKU
# block, run claude -p against the fix brief in docs/categories/<table>.md's '## Targeted QA Fix
# Brief' section, then independently re-verify via script/qa_report.sh before refreshing the
# universe overlay. Never trusts the agent's own self-report to gate a production write.
#
# See docs/superpowers/specs/2026-07-17-targeted-qa-fix-script-design.md for the full design.

PROJECT="sincere-hearth-273704"

resolve_category_file() {
  local table="$1"
  local candidate="docs/categories/${table}.md"
  if [[ -f "$candidate" ]]; then
    echo "$candidate"
    return 0
  fi
  local stripped="${table#shopee_}"
  candidate="docs/categories/${stripped}.md"
  if [[ -f "$candidate" ]]; then
    echo "$candidate"
    return 0
  fi
  return 1
}

build_prompt() {
  local table="$1"
  local category_file="$2"
  cat <<PROMPT
Targeted QA Fix session for ${table}.

BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/llm-extraction-rules.md, docs/headless-runbook.md, docs/quality-standards.md, and ${category_file} (your fix brief lives in that file's '## Targeted QA Fix Brief' section — read it in full, it is the specific work for this session, not background).

If ${category_file} has no '## Targeted QA Fix Brief' section, or the section has no concrete fixes to perform, that is a genuine blocker: stop, write nothing, output status='blocked'.

You perform every fix yourself, directly, using your own multimodal reading of product images and text where the brief calls for it. You do not invoke external scripts or subprocesses and do not need any API key beyond your own session auth — CLAUDE.md's ANTHROPIC_API_KEY note is about a different, external pipeline that does not exist in this repo.

STEP 1 — Sanity-check the brief's stated current-state numbers against a live query before trusting them:
Run: SELECT source, COUNT(*) FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy_map\` WHERE master_table = '${table}' GROUP BY source
If the live counts disagree with what the brief claims, record the discrepancy in findings — do not silently proceed as if the brief were current.

STEP 2 — Claim a 200-slot SKU block atomically (DECLARE before BEGIN TRANSACTION — reversing that order is a real BigQuery scripting syntax error):
BEGIN
  DECLARE next_start INT64;
  BEGIN TRANSACTION;
  SET next_start = (SELECT COALESCE(MAX(block_end), 69000) + 1 FROM \`sincere-hearth-273704.magpie_reference.sku_block_registry\`);
  INSERT INTO \`sincere-hearth-273704.magpie_reference.sku_block_registry\`
    (block_start, block_end, master_table, scenario, claimed_at, status)
  VALUES (next_start, next_start + 199, '${table}', 'targeted_qa_fix', CURRENT_TIMESTAMP(), 'ACTIVE');
  COMMIT TRANSACTION;
END;
Never query MAX(taxonomy_id) directly and assume it's safe to use — this atomic claim against the registry table is what prevents two sessions colliding on the same ID range.

STEP 3 — Execute exactly the fixes described in ${category_file}'s '## Targeted QA Fix Brief' section: pack-count / size / bundle corrections, the NULL-coverage pass, whatever that section specifies. That section is the actual scope of this session — this prompt does not restate it.

STEP 4 — Write via bq query DML only, never the streaming API. Set meta_agent='CLAUDE_CODE' on every row you write. Never delete an existing row unless the brief explicitly instructs you to.

STEP 5 — Do NOT run the universe refresh yourself. That step runs after this session, only if independent QA gates pass — it is not something you do.

STEP 6 — Append a dated row to ${category_file}'s '## QA History' table (columns: Date | Pass | Finding | Resolution) summarizing what you did and found this session. Commit the updated file:
git add ${category_file} && git commit -m 'Targeted QA Fix session for ${table}: update QA History'

STEP 7 — If you hit a genuine blocker at any step — something wrong with these instructions, missing data, anything that would make proceeding unsafe — stop, write nothing further, and output status='blocked' with the blockers array populated. That is a valid, expected outcome, not a failure.

Output ONLY this JSON when done, nothing else:
{status: complete|partial|failed|blocked, rows_created, rows_mapped, taxonomy_id_range_used, findings, blockers}.
PROMPT
}

decide_next_step() {
  local result_json="$1"
  local status rows_created
  status=$(echo "$result_json" | jq -r '.status // empty' 2>/dev/null) || status=""
  case "$status" in
    blocked)
      echo "BLOCKED"
      ;;
    failed)
      echo "MARK_FAILED"
      ;;
    complete|partial)
      rows_created=$(echo "$result_json" | jq -r '.rows_created // 0' 2>/dev/null) || rows_created="0"
      if [[ "$rows_created" =~ ^[0-9]+$ ]] && [[ "$rows_created" -gt 0 ]]; then
        echo "GATE_AND_REFRESH"
      else
        echo "NOOP"
      fi
      ;;
    *)
      echo "MARK_FAILED"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "script/targeted_qa_fix.sh: main() not wired up yet (Task 3)." >&2
  exit 1
fi
```

Then make it executable: `chmod +x script/targeted_qa_fix.sh`

- [ ] **Step 4: Run the self-test to confirm it passes**

Run: `bash script/test_targeted_qa_fix.sh`
Expected:
```
PASS: resolve_category_file
PASS: build_prompt
PASS: decide_next_step
ALL TESTS PASSED
```

- [ ] **Step 5: Commit**

```bash
chmod +x script/test_targeted_qa_fix.sh
git add script/targeted_qa_fix.sh script/test_targeted_qa_fix.sh
git commit -m "Add pure helper functions for targeted_qa_fix.sh with self-test

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Wire real invocations into main()

**Files:**
- Modify: `script/targeted_qa_fix.sh`

**Interfaces:**
- Consumes: `resolve_category_file`, `build_prompt`, `decide_next_step` from Task 2 (exact names/signatures
  above — do not rename).
- Produces: a working `script/targeted_qa_fix.sh <TABLE>` entry point. Nothing downstream depends on this
  task's additions (it's the final integration).

This task replaces the temporary `main() not wired up yet` stub with the real `mark_failed_qa`,
`run_universe_refresh`, and `main` functions that make actual `bq`/`claude`/`./script/qa_report.sh` calls. Per
the design spec's Testing section, these are **not** unit-tested (no BQ/claude in CI) — verified instead by
`bash -n` (syntax) and an argument-error smoke test (fails fast, before any external call, on bad input).

- [ ] **Step 1: Replace the stub at the bottom of `script/targeted_qa_fix.sh`**

Remove this block:
```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "script/targeted_qa_fix.sh: main() not wired up yet (Task 3)." >&2
  exit 1
fi
```

Replace it with:
```bash
mark_failed_qa() {
  local table="$1"
  echo "Marking most recent ACTIVE targeted_qa_fix block for ${table} as FAILED_QA..." >&2
  bq query --use_legacy_sql=false --project_id="${PROJECT}" \
    "UPDATE \`${PROJECT}.magpie_reference.sku_block_registry\`
     SET status = 'FAILED_QA'
     WHERE master_table = '${table}' AND scenario = 'targeted_qa_fix' AND status = 'ACTIVE'
       AND claimed_at = (
         SELECT MAX(claimed_at) FROM \`${PROJECT}.magpie_reference.sku_block_registry\`
         WHERE master_table = '${table}' AND scenario = 'targeted_qa_fix' AND status = 'ACTIVE'
       )"
}

run_universe_refresh() {
  local table="$1"
  echo "Running universe refresh for ${table}..."
  bq query --use_legacy_sql=false --project_id="${PROJECT}" \
    "MERGE \`${PROJECT}.magpie_reference.universe_taxonomy_overlay\` t
     USING (
       SELECT m.product_id, m.platform, m.country, m.master_table,
              pt.taxonomy_id, pt.canonical_name, m.source, m.confidence, m.meta_agent
       FROM \`${PROJECT}.magpie_reference.product_taxonomy_map\` m
       JOIN \`${PROJECT}.magpie_reference.product_taxonomy\` pt ON m.taxonomy_id = pt.taxonomy_id
       WHERE m.master_table = '${table}'
       QUALIFY ROW_NUMBER() OVER (
         PARTITION BY m.product_id, m.platform, m.country
         ORDER BY CASE m.source WHEN 'LLM' THEN 0 ELSE 1 END, m.taxonomy_id
       ) = 1
     ) src
     ON t.product_id = src.product_id AND t.platform = src.platform AND t.country = src.country
       AND t.master_table = '${table}'
     WHEN MATCHED THEN UPDATE SET
       taxonomy_id = src.taxonomy_id,
       sku_type_complete = src.canonical_name,
       taxonomy_source = src.source,
       taxonomy_confidence = src.confidence,
       taxonomy_meta_agent = src.meta_agent,
       updated_at = CURRENT_TIMESTAMP()
     WHEN NOT MATCHED BY SOURCE AND t.master_table = '${table}' THEN DELETE
     WHEN NOT MATCHED BY TARGET THEN INSERT
       (product_id, platform, country, master_table, taxonomy_id, sku_type_complete,
        taxonomy_source, taxonomy_confidence, taxonomy_meta_agent, updated_at)
       VALUES (src.product_id, src.platform, src.country, src.master_table, src.taxonomy_id, src.canonical_name,
               src.source, src.confidence, src.meta_agent, CURRENT_TIMESTAMP())"
}

main() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <TABLE>" >&2
    echo "  e.g. $0 shopee_th_detergent" >&2
    exit 1
  fi
  local table="$1"

  local category_file
  if ! category_file=$(resolve_category_file "$table"); then
    echo "ERROR: no category file found at docs/categories/${table}.md or docs/categories/${table#shopee_}.md" >&2
    echo "A Targeted QA Fix requires an existing, documented category — write the category file (and its '## Targeted QA Fix Brief' section) first." >&2
    exit 1
  fi

  echo "${table}"
  echo "TARGETED QA FIX STARTED (brief: ${category_file})"
  echo "==========================="

  local prompt
  prompt=$(build_prompt "$table" "$category_file")

  local claude_output
  claude_output=$(claude -p --output-format json --permission-mode bypassPermissions --max-turns 30 "$prompt")

  local result_json
  result_json=$(echo "$claude_output" | jq -r '.result // empty')

  if [[ -z "$result_json" ]]; then
    echo "ERROR: claude -p produced no parseable .result field. Raw output:" >&2
    echo "$claude_output" >&2
    mark_failed_qa "$table"
    exit 1
  fi

  local decision
  decision=$(decide_next_step "$result_json")

  case "$decision" in
    BLOCKED)
      echo "STATUS: blocked. Claimed block left ACTIVE (nothing written) — see blockers below."
      echo "$result_json" | jq -r '.blockers[]?' >&2
      exit 0
      ;;
    NOOP)
      echo "STATUS: complete/partial with rows_created=0 — nothing to gate or refresh. Block left ACTIVE."
      exit 0
      ;;
    MARK_FAILED)
      echo "STATUS: failed or malformed. Marking block FAILED_QA." >&2
      echo "$result_json" >&2
      mark_failed_qa "$table"
      exit 1
      ;;
    GATE_AND_REFRESH)
      echo "STATUS: rows written — running independent QA gates via script/qa_report.sh..."
      if ./script/qa_report.sh "$table"; then
        run_universe_refresh "$table"
        echo "============================"
        echo "TARGETED QA FIX FINISHED — universe refreshed"
      else
        echo "QA gates failed — marking block FAILED_QA, skipping universe refresh." >&2
        mark_failed_qa "$table"
        exit 1
      fi
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
```

- [ ] **Step 2: Syntax-check the script**

Run: `bash -n script/targeted_qa_fix.sh`
Expected: no output, exit code 0.

- [ ] **Step 3: Re-run the Task 2 self-test to confirm sourcing still works with main() present**

Run: `bash script/test_targeted_qa_fix.sh`
Expected:
```
PASS: resolve_category_file
PASS: build_prompt
PASS: decide_next_step
ALL TESTS PASSED
```
(This confirms `main()` being defined doesn't auto-run when the script is sourced — the
`BASH_SOURCE[0] == $0` guard is doing its job.)

- [ ] **Step 4: Smoke-test the argument-error path (no BQ/claude call should happen)**

Run: `./script/targeted_qa_fix.sh`
Expected: exits 1 immediately with:
```
Usage: ./script/targeted_qa_fix.sh <TABLE>
  e.g. ./script/targeted_qa_fix.sh shopee_th_detergent
```

Run: `./script/targeted_qa_fix.sh no_such_table_xyz`
Expected: exits 1 immediately with:
```
no_such_table_xyz
ERROR: no category file found at docs/categories/no_such_table_xyz.md or docs/categories/no_such_table_xyz.md
A Targeted QA Fix requires an existing, documented category — write the category file (and its '## Targeted QA Fix Brief' section) first.
```
(Confirms the script fails fast on bad input, before attempting any `claude`/`bq` call — matching the design
spec's stated testing scope.)

- [ ] **Step 5: Commit**

```bash
git add script/targeted_qa_fix.sh
git commit -m "Wire real claude -p / bq / qa_report.sh calls into targeted_qa_fix.sh main()

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- Brief lives in `docs/categories/<table>.md` under `## Targeted QA Fix Brief` → Task 1 (content) + Task 2/3
  `resolve_category_file`/`build_prompt` (consumption).
- File resolution with `shopee_` fallback → Task 2, tested.
- Agent-side steps 1–7 (sanity-check, atomic claim, execute brief, DML-only, no self-refresh, append QA
  History + commit, blocked handling, JSON contract) → Task 2 `build_prompt`, tested via substring checks.
- Wrapper-side control flow (blocked / malformed / failed / complete-partial-with-rows / noop) → Task 2
  `decide_next_step`, tested with 7 canned cases.
- Independent `qa_report.sh` gating before refresh, no `--skip-coexistence` → Task 3 `main()`.
- `FAILED_QA` marking via `sku_block_registry` lookup (not JSON parsing) → Task 3 `mark_failed_qa`.
- Universe refresh MERGE, sincere-only, no farsight → Task 3 `run_universe_refresh`.
- Testing scope limited to pure functions + smoke tests, no BQ/claude test → Tasks 2–3 step structure.

**Placeholder scan:** no TBD/TODO in final script content (Task 2's Step 3 stub is deliberately temporary and
labeled as such — it's the standard TDD-red-to-green pattern, replaced in Task 3 Step 1, not left in the final
file).

**Type/name consistency:** `resolve_category_file`, `build_prompt`, `decide_next_step`, `mark_failed_qa`,
`run_universe_refresh`, `main` — same names and argument order used consistently across Tasks 2 and 3 and in
the self-test.
