# Design: Pre-Fix QA Gate Direction + End-of-Run Coverage Report for `targeted_qa_fix.sh`

> Status: approved design, not yet implemented.
> Companion to [`script/targeted_qa_fix.sh`](../../../script/targeted_qa_fix.sh),
> [`script/qa_report.sh`](../../../script/qa_report.sh), [`docs/headless-runbook.md`](../../headless-runbook.md),
> and [`docs/superpowers/specs/2026-07-21-taxonomy-review-loop-design.md`](2026-07-21-taxonomy-review-loop-design.md)
> (the auto-discovery worklist and `_meta` semantics this design builds on, unchanged here).

---

## Problem

`script/qa_report.sh` today only runs **after** a `targeted_qa_fix.sh` session, as the independent gate that
decides whether to run the universe refresh or mark the claimed SKU block `FAILED_QA`. Nothing runs it
*before* a session starts, so a session's own scope (Brief mode: exactly what a human wrote; auto-discovery
mode: the `_meta` never-reviewed/unconfident worklist) never gets to see which gates are *currently* failing
for the table — even though `qa_report.sh` already knows, cheaply, in a few seconds of BigQuery queries.

Separately, nothing reports how much of a table's taxonomy is still unreviewed. The auto-discovery worklist
count is computed live inside the `claude -p` subprocess each session (STEP 1 of
`build_auto_discovery_prompt`) but never surfaced back to the wrapper or a human — there's no way to check
"how much of this category is left to review" without launching a full session or hand-writing the query.

---

## Deliverable scope

| File | Change |
|------|--------|
| `script/targeted_qa_fix.sh` | Capture `qa_report.sh` output before building the prompt; new `gate_report` parameter on `build_prompt` / `build_auto_discovery_prompt`; new STEP 1B in both; `EXIT` trap calling the new coverage script on every exit path once a table is resolved |
| `script/qa_coverage_report.sh` | New standalone script — reports never-reviewed / unconfident / confident counts for a table, same `_meta` criteria the auto-discovery worklist already uses |
| `script/test_targeted_qa_fix.sh` | New assertions for the `gate_report` parameter and STEP 1B content in both prompt builders |
| `docs/headless-runbook.md` | "Scenario: Targeted QA Fix" section updated: pre-fix gate report and end-of-run coverage report added to the numbered procedure |

No changes to `script/qa_report.sh` itself — it's reused as-is, called twice (before and, on the success path,
after).

---

## 1. Pre-fix gate report

`main()` currently resolves `table` → `category_file` → picks a prompt builder → invokes `claude -p`. This
adds one step between resolving the table and building the prompt:

```bash
local gate_report
gate_report=$(./script/qa_report.sh "$table") || true
```

`|| true` is required — `qa_report.sh` exits non-zero whenever any gate fails, which is the *expected*,
common case pre-fix (a table with nothing wrong wouldn't need a fix session), and `targeted_qa_fix.sh` runs
under `set -euo pipefail`.

`gate_report` (the raw `[PASS]`/`[FAIL]` text, ~9 lines) is passed as a new trailing parameter to both prompt
builders:

```bash
prompt=$(build_prompt "$table" "$category_file" "$block_size" "$gate_report")
# or
prompt=$(build_auto_discovery_prompt "$table" "$category_file" "$block_size" "$gate_report")
```

### Why the nine gates split into two classes

`qa_report.sh`'s gates are not uniformly fixable by this script. Five are **entry-level** — a defect in
`product_taxonomy` fixable by `UPDATE`ing the row: placeholder-leak, structured-fields NULL%, `'all
variant/size' name`, `canonical_name fields`, garbled brand text. Four are **map-level** — a defect only
fixable by deleting or re-mapping a `product_taxonomy_map` row: dual-mapped (LLM), HUMAN+LLM coexistence,
duplicate product_id, duplicate product+taxon. Both prompt builders already forbid deletion ("Never delete an
existing row unless the brief explicitly instructs you to" / STEP 7's "Never delete an existing row") — so
"use gate failures as fix direction" can only safely apply to the entry-level five. Telling the agent to also
"fix" a map-level failure would hand it two contradictory instructions in the same prompt.

This split is static (the nine gate names never change at runtime), so it's written directly into both
prompts' STEP 1B text rather than computed by the wrapper — no new bash classification logic needed.

### Auto-discovery mode: STEP 1B (inserted after STEP 1's worklist query, before STEP 2's Tier 1 sweep)

```
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
```

This supplements, not replaces, the existing `_meta`-driven worklist and Tier 1/Tier 2 sweep — a gate failure
on a row already marked `confident` is exactly the kind of regression the `_meta` worklist alone would never
re-surface, since `confident` rows are excluded from it.

### Brief mode: STEP 1B (inserted after STEP 1's live-count sanity check)

```
STEP 1B — Pre-fix QA gate report (already run before this session, informational only — this is a Brief-mode
session, so your scope is exactly what STEP 3's Brief section specifies, not expanded by this report):
${gate_report}
If any FAILing gate above touches rows your Brief already covers, treat it as corroborating signal. If a
FAILing gate touches rows outside the Brief's stated scope, do not act on it — note it in findings so a future
session can pick it up; this session does exactly what the Brief says, nothing more.
```

Brief mode's scope is human-authored and intentionally narrow; the gate report is visibility, not a scope
expansion, consistent with STEP 1's existing "record the discrepancy, don't silently proceed" pattern for the
live-count sanity check.

---

## 2. `script/qa_coverage_report.sh` — end-of-run coverage count

New standalone script, same shape as `qa_report.sh` (a `bq query` wrapper, no pure functions to unit test):

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: ./script/qa_coverage_report.sh <master_table>
# Reports how many product_taxonomy entries for a table are NOT confidently reviewed yet — the exact
# _meta criteria targeted_qa_fix.sh's auto-discovery worklist uses (_meta IS NULL OR review_confidence !=
# 'confident'). Standalone-runnable for any table at any time; also called by targeted_qa_fix.sh at the end
# of every run via an EXIT trap, regardless of that run's outcome.

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

### Wiring into `targeted_qa_fix.sh`: `EXIT` trap, not restructured `case` branches

The count must print on every exit path — `BLOCKED`, `NOOP`, `MARK_FAILED`, and the success path — without
touching the four `exit`/`case` branches already in `main()`. An `EXIT` trap set right after `category_file`
resolves does this cleanly:

```bash
local table="$1"
...
if ! category_file=$(resolve_category_file "$table"); then
  ... exit 1   # unchanged — no table resolved yet, nothing to report
fi

# Global, not local: an EXIT trap fires after main() itself may have returned, when a `local` would already
# be out of scope. Every exit from here on (blocked/failed/noop/success) reports coverage for this table.
QA_FIX_TABLE="$table"
trap './script/qa_coverage_report.sh "$QA_FIX_TABLE" || true' EXIT
```

The two exits that happen before this point (usage error, no category file found) skip the trap entirely — a
deliberate carve-out, since no table has been confirmed to exist yet at that stage.

---

## 3. `docs/headless-runbook.md` update

"Scenario: Targeted QA Fix" (currently lines 259–291) gets two additions to its numbered procedure: a new
step 2 ("Run `qa_report.sh` before invoking `claude -p`; pass its output into the prompt as gate-directed
scope — entry-level gate failures become fix targets, map-level failures are report-only, see
[this design](2026-07-23-qa-fix-gate-direction-and-coverage-design.md)"), renumbering the existing steps 2–5
to 3–6, and a new final step ("Regardless of outcome, run `qa_coverage_report.sh` for `@table` and report the
pending-review count").

---

## 4. Testing / Verification

- `bash -n script/targeted_qa_fix.sh` and `bash -n script/qa_coverage_report.sh` — syntax check.
- `bash script/test_targeted_qa_fix.sh` — extend with:
  - `build_prompt`/`build_auto_discovery_prompt` called with a fake `gate_report` string; assert the returned
    prompt contains that exact string (STEP 1B interpolates it verbatim).
  - Assert both prompts name all five entry-level gates ("placeholder-leak", "structured-fields NULL%",
    "'all variant/size' name", "canonical_name fields", "garbled brand text") paired with fix-direction
    language, and all four map-level gates ("dual-mapped (LLM)", "HUMAN+LLM coexistence", "duplicate
    product_id", "duplicate product+taxon") paired with "do NOT attempt a fix".
  - Assert `build_prompt`'s STEP 1B explicitly says the Brief's scope is not expanded by the gate report
    (the informational-only framing, distinct from auto-discovery's fix-direction framing).
- `script/qa_coverage_report.sh`: no pure functions to unit test (same standing exemption `qa_report.sh`
  already carries — a straight-line `bq query` wrapper). Verify once against a real table after landing:
  `./script/qa_coverage_report.sh shopee_sg_shampoo` and confirm the three counts sum to `total`.
- Manual: run `targeted_qa_fix.sh` once against a table with at least one known-failing gate, confirm STEP 1B
  appears in the actual prompt sent to `claude -p` (visible via `--output-format json`'s logged input, or a
  temporary `echo "$prompt"` before the `claude -p` call), and confirm the coverage line prints even when the
  session returns `status='blocked'`.

---

## Open Follow-ups (explicitly out of scope for this change)

- Extending the same pre-fix-gate-report pattern to `headless_taxonomy.sh` (Full Rebuild / top-up) — that
  script's priority is coverage speed, not precision; not requested, not designed here.
- A `--json` output mode for `qa_coverage_report.sh` for programmatic consumption beyond the wrapper's
  `EXIT` trap — no concrete consumer identified yet.
- Auto-claiming a deletion-authorized follow-up session when map-level gates fail — this design only reports
  them into `findings`; acting on that report is a human/operator decision, not automated here.
