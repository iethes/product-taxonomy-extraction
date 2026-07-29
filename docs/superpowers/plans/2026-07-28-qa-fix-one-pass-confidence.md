# One-Pass Confidence Classification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a never-reviewed `product_taxonomy` row reach `review_confidence = 'confident'` in one session
(Tier-2 correct + Tier-1 clean) instead of two, and let a row fixed this session reach `confident` the same
session instead of waiting for a future STEP 1C pass — without touching the existing prior-verdict comparison
path that `fixed_pending_recheck` rows already rely on.

**Architecture:** Pure prompt-text edits to the `build_auto_discovery_prompt` bash functions in
`script/targeted_qa_fix.sh` and `script/custom_targeted_qa_fix.sh` (STEP 4 gains an inline recheck instruction;
STEP 5 gains a new promotion path alongside, not replacing, the existing one). No schema change, no new CLI
flag, no wrapper-level branching — this repo's existing test convention (source the script, call the bash
function directly, `grep` the returned heredoc string for exact substrings) is unchanged and extended.

**Tech Stack:** Bash, heredoc-templated LLM prompts, BigQuery Standard SQL (as string literals inside the
prompts — not executed by these tests), `grep`-based self-tests (no network/BQ/claude calls in tests, per
existing convention in `script/test_targeted_qa_fix.sh`'s own header comment).

## Global Constraints

- `_meta` is `STRING`-typed — always `TO_JSON_STRING(STRUCT(...))` to write, `JSON_VALUE(...)` to read; never
  the `JSON '...'` literal or `TO_JSON()` (spec: `docs/superpowers/specs/2026-07-28-qa-fix-one-pass-confidence-design.md` §1, inherited from the 2026-07-21 design).
- The existing prior-verdict comparison (`IF(JSON_VALUE(pt._meta, '$.last_verdict') = 'correct', 'confident', 'unconfident')`) must remain in the prompt text, verbatim, for the `_meta IS NOT NULL` case — do not delete it.
- `targeted_qa_fix.sh` and `custom_targeted_qa_fix.sh` must carry identical STEP 4/STEP 5 prompt text (prompt-internal STEP logic is not one of this pair's three deliberate-drift points) — only variable names differ (`${table}` vs `${category}`).
- Heredocs in both scripts use unquoted `cat <<PROMPT` (shell interpolation active) — any literal `$` meant for BigQuery (not shell) must be backslash-escaped (`\$.review_confidence`), matching existing text in both files.
- No `Date.now()`/live BQ/live `claude -p` calls in any test added by this plan — matches
  `script/test_targeted_qa_fix.sh`'s existing scope (grep-only, no network).

---

### Task 1: `targeted_qa_fix.sh` — same-session gate-verify promotion

**Files:**
- Modify: `script/targeted_qa_fix.sh` (the `build_auto_discovery_prompt` function — STEP 4's closing paragraph and all of STEP 5)
- Test: `script/test_targeted_qa_fix.sh` (append new assertions after the existing `build_auto_discovery_prompt gate_report (STEP 1B)` block, i.e. after today's line ~197)

**Interfaces:**
- Consumes: `build_auto_discovery_prompt(table, category_file, block_size, gate_report)` — signature unchanged, still returns a single string via bash `cat <<PROMPT`.
- Produces: the returned prompt string now contains the literal markers `PATH 1 (new, 2026-07-28)` and `PATH 2 (existing, unchanged)` inside STEP 5, and the phrase `Same-session gate-verify` inside STEP 4 — Task 2 greps for the same markers to confirm the mirror is exact, and Task 3's doc update references this path split by name.

- [ ] **Step 1: Write the failing test assertions**

Open `script/test_targeted_qa_fix.sh`. Immediately after the existing block that ends with:
```bash
grep -q "STEP 1C already bulk-promoted" <<< "$prompt" || fail "STEP 3 must exclude rows STEP 1C already resolved"
echo "PASS: build_auto_discovery_prompt gate_report (STEP 1B)"
```
insert a new block:
```bash
# --- build_auto_discovery_prompt: one-pass confidence promotion (STEP 4 / STEP 5) ---
prompt=$(build_auto_discovery_prompt "shopee_th_suncare" "docs/categories/th_suncare.md" "200")
grep -qF "Same-session gate-verify" <<< "$prompt" || fail "STEP 4 must add the immediate post-fix Tier 1 recheck instruction"
grep -qF "do not wait for a future session's STEP 1C" <<< "$prompt" || fail "STEP 4's recheck must run this session, not a future one"
grep -qF "PATH 1 (new, 2026-07-28)" <<< "$prompt" || fail "STEP 5 must add the new one-pass promotion path"
grep -qF "PATH 2 (existing, unchanged)" <<< "$prompt" || fail "STEP 5 must keep the existing prior-verdict comparison path, labeled unchanged"
grep -qF "IF(JSON_VALUE(pt._meta, '\$.last_verdict') = 'correct', 'confident', 'unconfident')" <<< "$prompt" || fail "STEP 5 Path 2 must retain the exact prior-verdict IF() comparison verbatim"
grep -qF "fully clean on Tier 1" <<< "$prompt" || fail "STEP 5 Path 1(a) must define the never-reviewed promotion condition"
grep -qF "qa_gate_exceptions\` for (gate_name = '<the tripped flag's name" <<< "$prompt" || fail "STEP 5 Path 1 must extend qa_gate_exceptions to Tier 1 flag names, not just qa_report.sh's five named gates"
grep -qF "never double-count a taxonomy_id in both Path 1 and Path 2" <<< "$prompt" || fail "STEP 5 must warn against double-counting a taxonomy_id across both paths"
echo "PASS: build_auto_discovery_prompt one-pass confidence promotion"
```

- [ ] **Step 2: Run the test suite to verify it fails**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: `FAIL: STEP 4 must add the immediate post-fix Tier 1 recheck instruction` (first new assertion to run, since none of this text exists in the script yet).

- [ ] **Step 3: Edit STEP 4's closing paragraph**

In `script/targeted_qa_fix.sh`, inside `build_auto_discovery_prompt`, find this exact existing text (STEP 4's last paragraph, immediately before `STEP 5 — For every row...`):

```
Reminder: the actual content-fixing UPDATE (the one that changes canonical_name/product_line/size/pack_count —
not shown as a template above since it varies per defect) must also set meta_agent='CLAUDE_CODE' in that same
statement. Don't wait until STEP 7 to remember this.
```

Replace it with (same text, plus one new paragraph appended):

```
Reminder: the actual content-fixing UPDATE (the one that changes canonical_name/product_line/size/pack_count —
not shown as a template above since it varies per defect) must also set meta_agent='CLAUDE_CODE' in that same
statement. Don't wait until STEP 7 to remember this.

Same-session gate-verify (2026-07-28): immediately after applying a fix and resetting a row's _meta to
{"is_reviewed": false}, re-run the same Tier 1 flag checks (stub_leak, duplicate_brand, wrong_field_order,
brand_casing_mismatch, excess_content, canonical_field_mismatch, null_size, garbage_brand) against that row's
new values, in this same session — do not wait for a future session's STEP 1C to confirm the fix held. A row
that comes back fully clean on this immediate recheck qualifies for STEP 5's Path 1(b) promotion below, this
session. A row that still trips a flag keeps _meta at {"is_reviewed": false}, unresolved — picked up again by
STEP 2's worklist-wide sweep or a future STEP 1C pass, same as today.
```

- [ ] **Step 4: Replace STEP 5 in full**

Find this exact existing block (all of STEP 5):

```
STEP 5 — For every row you gave a real Tier 2 judgment this session and found correct (no fix needed), update
its _meta by comparing this review's verdict against the stored previous verdict — agreement promotes to
confident; disagreement, or a first-ever review, lands on unconfident. Do this in ONE bulk statement covering
every such taxonomy_id, not one UPDATE per row — a prior session burned most of its turn budget on
one-UPDATE-per-taxonomy_id bookkeeping alone and only reviewed 133 of ~5,812 rows as a result:
UPDATE \`${PROJECT}.magpie_reference.product_taxonomy\` pt
SET _meta = TO_JSON_STRING(STRUCT(
  true AS is_reviewed,
  CURRENT_TIMESTAMP() AS last_reviewed_at,
  IF(JSON_VALUE(pt._meta, '\$.last_verdict') = 'correct', 'confident', 'unconfident') AS review_confidence,
  'correct' AS last_verdict
))
WHERE pt.taxonomy_id IN ('SKU-XXXXXX', 'SKU-YYYYYY', /* every taxonomy_id you Tier-2-judged as correct this session — the IF() expression re-reads each row's own prior _meta, so one statement handles all of them correctly even though their prior states differ */)
This is metadata bookkeeping for the rows you actually reviewed (Tier 2 sample size, not the whole worklist),
so the taxonomy_id list stays small enough to write out literally — never bulk-mark a Tier-1-clean row you
did NOT Tier-2-sample (see STEP 3). Note last_verdict only ever records 'correct' in practice: rows you judge
wrong either get fixed (STEP 4 resets their _meta to unreviewed so they're re-evaluated fresh next run) or, if
not fixed this session, are simply left with their _meta untouched so the next run re-reviews them — nothing
writes last_verdict='wrong' directly.
```

Replace it with:

```
STEP 5 — Promote reviewed rows' _meta. Two distinct promotion paths apply — run both; they cover different
rows and never conflict as long as you don't put the same taxonomy_id in both lists:

PATH 1 (new, 2026-07-28) — never-reviewed rows and freshly-fixed rows, promoted in ONE pass, no waiting for a
future session:
  (a) A never-reviewed row (pt._meta IS NULL going into this session) that you Tier-2-judged 'correct' this
      session AND that came back fully clean on Tier 1 (STEP 2's sweep) — where "fully clean" means no flag
      tripped, OR every flag that did trip already has a matching row in
      \`${PROJECT}.magpie_reference.qa_gate_exceptions\` for (gate_name = '<the tripped flag's name, e.g.
      null_size>', master_table = '${table}', entity_id = '<the taxonomy_id>') — promotes straight to
      'confident'. A never-reviewed row Tier-2-judged 'correct' but with an un-excepted Tier 1 flag instead
      lands on 'unconfident' (the two signal types disagree).
  (b) A row you fixed this session (STEP 4's same-session gate-verify): fully clean on the immediate post-fix
      Tier 1 recheck (same "fully clean" definition as (a), including the qa_gate_exceptions carve-out) →
      promotes straight to 'confident', this session. Still flagged on recheck → do not include it here (STEP
      4 already left its _meta at {"is_reviewed": false}, unresolved).
  Bulk statement for every taxonomy_id qualifying under (a) or (b) this session:
  UPDATE \`${PROJECT}.magpie_reference.product_taxonomy\`
  SET _meta = TO_JSON_STRING(STRUCT(
    true AS is_reviewed,
    CURRENT_TIMESTAMP() AS last_reviewed_at,
    'confident' AS review_confidence,
    'correct' AS last_verdict
  ))
  WHERE taxonomy_id IN ('SKU-XXXXXX', /* every taxonomy_id qualifying under (a) or (b) this session */)

PATH 2 (existing, unchanged) — every other row you gave a real Tier 2 judgment this session and found correct,
that is NOT already covered by Path 1 (i.e. rows with a prior stored verdict already in _meta, being reviewed
again — the fixed_pending_recheck-via-fresh-Tier-2-judgment case, or a previously unconfident row sampled
again). Update its _meta by comparing this review's verdict against the stored previous verdict — agreement
promotes to confident; disagreement lands on unconfident. Do this in ONE bulk statement covering every such
taxonomy_id, not one UPDATE per row — a prior session burned most of its turn budget on
one-UPDATE-per-taxonomy_id bookkeeping alone and only reviewed 133 of ~5,812 rows as a result:
  UPDATE \`${PROJECT}.magpie_reference.product_taxonomy\` pt
  SET _meta = TO_JSON_STRING(STRUCT(
    true AS is_reviewed,
    CURRENT_TIMESTAMP() AS last_reviewed_at,
    IF(JSON_VALUE(pt._meta, '\$.last_verdict') = 'correct', 'confident', 'unconfident') AS review_confidence,
    'correct' AS last_verdict
  ))
  WHERE pt.taxonomy_id IN ('SKU-XXXXXX', 'SKU-YYYYYY', /* every taxonomy_id you Tier-2-judged as correct this session under Path 2 — the IF() expression re-reads each row's own prior _meta, so one statement handles all of them correctly even though their prior states differ */)

This is metadata bookkeeping for the rows you actually reviewed (Tier 2 sample size, not the whole worklist),
so each path's taxonomy_id list stays small enough to write out literally — never bulk-mark a Tier-1-clean row
you did NOT Tier-2-sample (see STEP 3), and never double-count a taxonomy_id in both Path 1 and Path 2's lists.
Note last_verdict only ever records 'correct' in practice: rows you judge wrong either get fixed (STEP 4 resets
their _meta to unreviewed so they're re-evaluated fresh next run) or, if not fixed this session, are simply
left with their _meta untouched so the next run re-reviews them — nothing writes last_verdict='wrong' directly.
```

- [ ] **Step 5: Run the test suite to verify it passes**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: `PASS: build_auto_discovery_prompt one-pass confidence promotion` and `ALL TESTS PASSED` at the end.

- [ ] **Step 6: Commit**

```bash
git add script/targeted_qa_fix.sh script/test_targeted_qa_fix.sh
git commit -m "$(cat <<'EOF'
targeted_qa_fix.sh: one-pass confidence promotion for never-reviewed and fixed rows

STEP 5 gains a new Path 1 (never-reviewed row with Tier-2 correct + Tier-1
clean, or a row fixed this session with a clean immediate recheck -> confident
directly, no second-session wait). Path 2 (existing prior-verdict IF()
comparison) is unchanged for rows already carrying a stored verdict. STEP 4
gains the same-session recheck instruction that feeds Path 1(b).

See docs/superpowers/specs/2026-07-28-qa-fix-one-pass-confidence-design.md
EOF
)"
```

---

### Task 2: Mirror into `custom_targeted_qa_fix.sh`

**Files:**
- Modify: `script/custom_targeted_qa_fix.sh` (the `build_auto_discovery_prompt` function — same STEP 4 / STEP 5 text as Task 1, with `${table}` → `${category}`)
- Test: `script/test_custom_targeted_qa_fix.sh`

**Interfaces:**
- Consumes: Task 1's exact STEP 4/STEP 5 text as the source of truth to mirror — same literal markers (`Same-session gate-verify`, `PATH 1 (new, 2026-07-28)`, `PATH 2 (existing, unchanged)`) must appear, character-for-character identical except the one variable substitution below.
- Produces: `build_auto_discovery_prompt(dataset, table, category, category_file, block_size, gate_report)` (this script's existing, wider signature) still returns a string containing the same markers Task 1 established — nothing downstream of this task depends on new interfaces.

- [ ] **Step 1: Check the current test file's structure for this exact call signature**

Run: `grep -n 'build_auto_discovery_prompt "makanan\|build_auto_discovery_prompt "9_' script/test_custom_targeted_qa_fix.sh`
Note the exact `dataset`/`table`/`category`/`category_file` argument strings already used elsewhere in that test file — reuse the same ones for the new assertions below so the test file doesn't introduce a new, unexplained fixture category.

- [ ] **Step 2: Write the failing test assertions**

Append to `script/test_custom_targeted_qa_fix.sh`, using whatever fixture arguments Step 1 found (example below assumes the `makanankucing`/`9_makanankucing_my_daily`/`makanankucing_my` fixture used elsewhere in that file — substitute if different):

```bash
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
```

- [ ] **Step 3: Run the test suite to verify it fails**

Run: `bash script/test_custom_targeted_qa_fix.sh`
Expected: `FAIL: STEP 4 must add the immediate post-fix Tier 1 recheck instruction`.

- [ ] **Step 4: Apply the same STEP 4 / STEP 5 edits as Task 1, with one substitution**

Locate the identical existing STEP 4 closing paragraph and full STEP 5 block in `script/custom_targeted_qa_fix.sh`'s `build_auto_discovery_prompt` (character-for-character the same text Task 1 replaced in `targeted_qa_fix.sh` — confirmed identical between the two files as of 2026-07-28). Apply the exact same replacement text from Task 1, Steps 3 and 4, with exactly one change: in the new STEP 5 Path 1(a) text, replace

```
master_table = '${table}'
```

with

```
master_table = '${category}'
```

(matching this script's existing convention — every other `master_table = '...'` reference in this file already uses `${category}`, never `${table}`).

- [ ] **Step 5: Run the test suite to verify it passes**

Run: `bash script/test_custom_targeted_qa_fix.sh`
Expected: `PASS: build_auto_discovery_prompt one-pass confidence promotion (custom)` and the file's final all-tests-passed line.

- [ ] **Step 6: Commit**

```bash
git add script/custom_targeted_qa_fix.sh script/test_custom_targeted_qa_fix.sh
git commit -m "$(cat <<'EOF'
custom_targeted_qa_fix.sh: mirror one-pass confidence promotion from targeted_qa_fix.sh

Same STEP 4/STEP 5 text as targeted_qa_fix.sh's prior commit, with the one
expected variable substitution (\${table} -> \${category}) this script already
uses everywhere else for master_table references.

See docs/superpowers/specs/2026-07-28-qa-fix-one-pass-confidence-design.md
EOF
)"
```

---

### Task 3: Document the dual-path model in `quality-standards.md`

**Files:**
- Modify: `docs/quality-standards.md:50-52`

**Interfaces:**
- Consumes: the "PATH 1"/"PATH 2" naming and the `qa_gate_exceptions` Tier-1-flag carve-out established in Tasks 1-2 — this task only restates them in prose for human readers, no new mechanism.
- Produces: nothing further downstream depends on this task; it is documentation-only and has no test.

- [ ] **Step 1: Replace the existing paragraph**

Find this exact existing text at `docs/quality-standards.md:50-52`:

```
`product_taxonomy._meta` tracks review state per entry (`review_confidence`: `unreviewed` → `unconfident` →
`confident`, reached by two consecutive reviews agreeing on the same verdict). Each run reviews only
never-reviewed or `unconfident` entries (incremental scope, not a full re-scan) via a two-tier checklist: Tier
```

Replace the first sentence only (leave "Each run reviews only... Tier" and everything after it unchanged) with:

```
`product_taxonomy._meta` tracks review state per entry (`review_confidence`: `unreviewed` → `unconfident` →
`confident`). Since 2026-07-28, confidence is reached one of two ways: (1) a never-reviewed row's first Tier-2
"correct" verdict, if Tier 1 is also fully clean on that row (no flag tripped, or every tripped flag has a
matching `qa_gate_exceptions` entry) — promotes in one pass; or (2) two consecutive reviews on a row that
already carries a prior verdict agreeing on the same outcome — the original rule, unchanged, for rows re-reviewed
after being previously unconfident. A row fixed in a session is re-checked against Tier 1 immediately, in the
same session, rather than waiting for a future pass. See
[docs/superpowers/specs/2026-07-28-qa-fix-one-pass-confidence-design.md](superpowers/specs/2026-07-28-qa-fix-one-pass-confidence-design.md).
Each run reviews only
never-reviewed or `unconfident` entries (incremental scope, not a full re-scan) via a two-tier checklist: Tier
```

- [ ] **Step 2: Sanity-check the surrounding paragraph still reads correctly**

Run: `sed -n '46,58p' docs/quality-standards.md` and confirm the paragraph flows as one coherent block (no dangling half-sentence, no duplicated "Tier" line) — fix spacing/line-wrap by hand if the replacement above left an awkward break, since this is prose, not code that a test can check.

- [ ] **Step 3: Commit**

```bash
git add docs/quality-standards.md
git commit -m "$(cat <<'EOF'
docs: document one-pass confidence promotion in quality-standards.md

Restates the dual-path _meta promotion model (see the 2026-07-28 design
spec) for human readers of the QA-gate documentation.
EOF
)"
```

---

## Self-Review Notes

- **Spec coverage:** design spec §1 (new promotion path) → Task 1 Step 4 / Task 2 Step 4. §2 (`qa_gate_exceptions` carve-out for Tier 1 flags) → Task 1 Step 4's Path 1(a) text + its test assertion. §3 (STEP 4 inline recheck-and-fold) → Task 1 Step 3 / Task 2. Testing section → Tasks 1-2's grep assertions plus the design's own "manual, live category" checks are intentionally left as a post-merge operational step (not automatable without BQ/claude network access, consistent with this repo's existing test-scope convention). Documentation deliverable → Task 3.
- **Placeholder scan:** no TBD/TODO; every step shows literal before/after text, not a description of what to change.
- **Type consistency:** `build_auto_discovery_prompt`'s call signature is unchanged in both scripts (Task 1: 4 args; Task 2: 5 args, matching each script's existing convention) — no task introduces a new parameter.
