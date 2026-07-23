# Design: Fix Three Throughput/Integrity Bugs Found in `targeted_qa_fix.sh` Auto-Discovery Sessions

> Status: approved design, not yet implemented.
> Companion to [`script/targeted_qa_fix.sh`](../../../script/targeted_qa_fix.sh),
> [`script/qa_report.sh`](../../../script/qa_report.sh), [`script/qa_coverage_report.sh`](../../../script/qa_coverage_report.sh),
> and [`docs/superpowers/specs/2026-07-23-qa-fix-gate-direction-and-coverage-design.md`](2026-07-23-qa-fix-gate-direction-and-coverage-design.md)
> (the STEP 1B gate-direction text and coverage report this design modifies).

---

## Problem

Six consecutive `targeted_qa_fix.sh shopee_sg_coffee` auto-discovery sessions (2026-07-23, passes #16–#21)
showed apparent throughput collapsing from ~160–490 rows touched per session down to ~20–35. Reading the
sessions' own QA History records (not just the coverage-report deltas) surfaced three distinct, independently
fixable problems, none of which is "the agent got lazier":

1. **`qa_coverage_report.sh` hides real work.** A freshly-fixed row's `_meta` is reset to
   `{"is_reviewed": false}`, which lands in the same `unconfident` bucket as a row that failed a genuine
   re-review. Pass #19 fixed 66 rows and confirmed 50 more correct (116 real `_meta` writes) but the bucket
   delta the wrapper printed only showed ~40 rows moving — the visible number understates real throughput.

2. **STEP 1B (added in the gate-direction design) has no way to permanently close a confirmed false
   positive.** The `garbled brand text` gate flags brand `BRD-SG-06081` ("888") every single run because the
   gate's `NOT REGEXP_CONTAINS(bd.canonical_name, r'[\p{L}]')` check structurally cannot express "a real brand
   can be all-digits." This has now been re-confirmed as a non-defect **9 consecutive sessions in a row**,
   burning turn budget on identical re-verification with zero possible resolution. This also isn't
   cosmetic: `qa_report.sh` `exit`s non-zero whenever any gate fails (including this one), and
   `targeted_qa_fix.sh`'s `GATE_AND_REFRESH` branch treats non-zero exit as "mark FAILED_QA, skip universe
   refresh" — so any *other* session against this category that creates rows (top-up, brief-mode) would have
   its universe refresh silently and permanently blocked by this one unfixable gate.

3. **QA History is not append-only in practice.** `git show b9ae0eb` (pass #20's commit) is a clean
   1-insertion/1-deletion diff — pass #20 overwrote pass #19's entire QA History row instead of adding a new
   one below it. Pass #19's 116-row session record is gone from `docs/categories/shopee_sg_coffee.md`. This
   silently breaks the "read QA History first to avoid rediscovering the same defect" pattern every session
   is instructed to rely on.

A fourth factor — early passes (#17, #18) found large systemic bugs fixable in one bulk `UPDATE` (a 281-row
size-parsing defect, a 52-row brand reroute), while later passes are left with `null_size` rows that have zero
extractable text signal and can only be resolved by image reads one at a time — is a real and expected
diminishing-returns curve, not a bug. It is explicitly out of scope below.

---

## Deliverable scope

| File | Change |
|------|--------|
| `script/qa_coverage_report.sh` | Split `unconfident` into `fixed_pending_recheck` vs `unconfident`, read-side only |
| `magpie_reference.qa_gate_exceptions` (new BQ table) | Stores confirmed permanent false positives per gate/table |
| `script/qa_report.sh` | Each gate query excludes rows already covered by an exception |
| `script/targeted_qa_fix.sh` | STEP 1B text updated to consult/write exceptions; QA History append moved from agent-driven `Edit`+`git commit` to deterministic bash in `main()`; final JSON schema gains `qa_history_entry` |
| `script/test_targeted_qa_fix.sh` | New assertions for the exception-aware STEP 1B text and the JSON-driven append |

---

## 1. Coverage report: split `unconfident` into two buckets

No `_meta` schema change. The two cases are already distinguishable by what's present:

- Freshly fixed, awaiting re-review: `_meta` is non-null, has `is_reviewed: false`, and **no**
  `review_confidence` key.
- Genuinely reviewed at least once: `_meta` has a `review_confidence` key (`'unconfident'` or `'confident'`) —
  STEP 5 always writes this for every row it judges.

```sql
SELECT
  COUNT(*) AS total,
  COUNTIF(_meta IS NULL) AS never_reviewed,
  COUNTIF(_meta IS NOT NULL AND JSON_VALUE(_meta, '$.review_confidence') IS NULL) AS fixed_pending_recheck,
  COUNTIF(JSON_VALUE(_meta, '$.review_confidence') = 'unconfident') AS unconfident,
  COUNTIF(JSON_VALUE(_meta, '$.review_confidence') = 'confident') AS confident
FROM distinct_entries
```

Output gains a fourth line:

```
Pending QA (never-reviewed, fixed-pending-recheck, or unconfident): ... / ... (...%)
  never reviewed:        ...
  fixed pending recheck: ...
  unconfident:           ...
  confident:             ...
```

`pending` for the headline percentage still includes all three non-confident buckets — this is a
transparency change, not a redefinition of "done."

---

## 2. `qa_gate_exceptions` table + gate-aware `qa_report.sh`

### Schema

```sql
CREATE TABLE `sincere-hearth-273704.magpie_reference.qa_gate_exceptions` (
  gate_name STRING NOT NULL,      -- e.g. 'garbled brand text', matches qa_report.sh's [PASS]/[FAIL] label
  master_table STRING NOT NULL,
  entity_id STRING NOT NULL,      -- the id column that gate's query groups by (brand_id, taxonomy_id, ...)
  reason STRING,
  confirmed_at TIMESTAMP,
  meta_agent STRING
);
```

One generic table, not one per gate — same precedent as `sku_block_registry` being one table reused across
scenarios. `entity_id` is whatever id that gate's own query already selects (`brand_id` for `garbled brand
text`/`garbage_brand`, `taxonomy_id` for the rest), stored as `STRING` so every gate's exclusion clause is the
same shape regardless of the underlying column's real type.

### `qa_report.sh` change

Each gate query gets one added clause, e.g. for `garbled brand text`:

```sql
WHERE m.master_table = '${TABLE}'
  AND NOT REGEXP_CONTAINS(bd.canonical_name, r'[\p{L}]')
  AND bd.brand_id NOT IN (
    SELECT entity_id FROM `${PROJECT}.magpie_reference.qa_gate_exceptions`
    WHERE gate_name = 'garbled brand text' AND master_table = '${TABLE}'
  )
```

Applied identically to the other 4 entry-level gates (map-level gates — dual-mapped, coexistence, duplicate
product_id, duplicate product+taxon — are never a "confirmed false positive" by nature; they're real
duplicates or they aren't, so no exception clause is added to those 4).

### STEP 1B prompt change (`build_auto_discovery_prompt` only)

`build_prompt`'s (Brief mode) STEP 1B is already informational-only ("treat it as corroborating signal") and
never instructs re-verifying a gate as an automatic-fix candidate, so there's nothing to replace there. Only
`build_auto_discovery_prompt`'s STEP 1B says "treat every row it flags as an automatic candidate needing a
fix" — replace that with:

> For any FAILing entry-level gate, first check whether its rows already carry a confirmed exception
> (`SELECT * FROM qa_gate_exceptions WHERE gate_name = '<gate>' AND master_table = '${table}'`) — if so, skip
> re-verifying them entirely, they're closed. For rows without an existing exception: investigate as before
> (a gate can still false-positive — sanity-check, don't blind-apply). If you confirm a row is a genuine,
> structural false positive (not a data defect, not something a fix could ever resolve) **and this is not the
> first time** — check the category's QA History for a prior session reaching the same conclusion on the same
> entity — insert a `qa_gate_exceptions` row so no future session re-spends turns on it. A single confirmation
> is not enough to close it permanently; requiring at least one repeat mirrors the existing
> confident-after-two-agreeing-reviews rule for regular rows.

### One-time backfill (not part of the script change, an operational follow-up)

`BRD-SG-06081` ("888") already has 9 consecutive confirmations in `shopee_sg_coffee`'s QA History — past the
bar this design sets. Insert its exception row once the table exists, rather than waiting for a 10th session
to trip the "not the first time" check.

---

## 3. Deterministic QA History append

### Why script-side, not prompt-side

The failure mode is a full-row `Edit` replacing the wrong span instead of inserting after it — a mistake in
*how* the agent edits the file, not in what it's told to do. STEP 6/STEP 9 already say "append a dated row";
a stronger instruction still depends on the model executing a find-and-replace correctly every time. Moving
the write to five lines of deterministic bash removes the failure mode instead of asking more carefully.

### JSON output schema change

The final JSON the agent outputs gains one field:

```
{status, rows_created, rows_mapped, taxonomy_id_range_used, qa_history_entry: {finding, resolution}, findings, blockers}
```

`finding` and `resolution` are exactly the two prose fields that already go into the QA History table's
existing `Finding` / `Resolution` columns — no new content requirement, just structured instead of freehand
markdown-table-editing.

### `main()` change

After parsing `result_json` (where `decide_next_step` already runs), before the STATUS branches:

```bash
local qa_finding qa_resolution qa_timestamp
qa_finding=$(echo "$result_json" | jq -r '.qa_history_entry.finding // empty')
qa_resolution=$(echo "$result_json" | jq -r '.qa_history_entry.resolution // empty')

if [[ -n "$qa_finding" ]]; then
  qa_timestamp=$(date -u +'%Y-%m-%d %H:%M UTC')
  local new_row="| ${qa_timestamp} | Automated review session (auto-discovery) | ${qa_finding} | ${qa_resolution} |"
  # Insert immediately before the '---' that closes the QA History table (the anchor is the first '---'
  # line at or after the '## QA History' heading — grep -n twice to find it, sed to insert before it).
  local qa_history_line divider_line
  qa_history_line=$(grep -n '^## QA History' "$category_file" | head -1 | cut -d: -f1)
  divider_line=$(awk -v start="$qa_history_line" 'NR > start && /^---$/ { print NR; exit }' "$category_file")
  sed -i "${divider_line}i ${new_row}" "$category_file"
  git add "$category_file"
  git commit -m "Automated review session for ${table}: update QA History"
fi
```

STEP 6 (Brief mode) and STEP 9 (auto-discovery mode) in both prompt builders change from "append a dated row
... commit" to "report your finding and resolution in the JSON output's `qa_history_entry` field — do not
edit `${category_file}` or run `git commit` yourself, the wrapper does this after you finish."

This also drops the "17th"/"21st pass" self-numbering the agent currently does by reading — and miscounting,
per problem #3 — prior history. A real UTC timestamp uniquely orders same-day sessions without requiring the
wrapper (or the agent) to count or trust any prior row at all; the exact ordinal label existing rows use is
cosmetic and isn't relied on by any script logic today.

### Blocked/failed sessions

`qa_history_entry` is only present (and only acted on) when the agent actually did reviewable work — a
`blocked` or `failed` session naturally omits it (`// empty` guards this), so no row is written and no commit
happens, matching current behavior of those two exit paths.

---

## 4. Testing / Verification

- `bash -n script/targeted_qa_fix.sh`, `bash -n script/qa_report.sh`, `bash -n script/qa_coverage_report.sh` —
  syntax check.
- `bash script/test_targeted_qa_fix.sh` — extend with:
  - Both prompt builders' STEP 1B text mentions checking `qa_gate_exceptions` before re-verifying, and the
    "not the first time" bar before inserting one.
  - Both prompt builders' STEP 6/STEP 9 text says to report `qa_history_entry` in the JSON, not to edit the
    file or commit directly.
  - A fake `result_json` with `qa_history_entry` set, fed through the (now-extracted) append logic as a pure
    function, asserts: the new row lands *before* the divider line, and the *previous* rows are untouched
    byte-for-byte.
  - A fake `result_json` with no `qa_history_entry` asserts no file write and no `git commit` call happen.
- `script/qa_coverage_report.sh`: verify the four counts (`never_reviewed`, `fixed_pending_recheck`,
  `unconfident`, `confident`) sum to `total` against a real table.
- Manual, one-time: after creating `qa_gate_exceptions` and backfilling the `shopee_sg_coffee` / "888"
  row, run `./script/qa_report.sh shopee_sg_coffee` and confirm `garbled brand text` now shows `[PASS]`.
- Manual: run `targeted_qa_fix.sh` once end-to-end against a table with a pending fix, confirm the new QA
  History row appears after the *previous* last row (not replacing it) and that the previous row's text is
  byte-identical to before the run.

---

## Open Follow-ups (explicitly out of scope for this change)

- The Tier-1-exhausted / Tier-2-inherently-slower diminishing-returns curve itself — not a bug, no design
  proposed here to change it (e.g. increasing per-session Tier 2 sample size is a scope/budget call, not an
  engineering fix).
- Retroactively recovering pass #19's lost QA History content from `b9ae0eb`'s parent commit — a one-time
  manual `git show 07e9a1a:docs/categories/shopee_sg_coffee.md` recovery, not a script change, and not blocking
  this design.
- Extending `qa_gate_exceptions` to the 4 map-level gates — deliberately excluded above; a "confirmed
  duplicate that's fine actually" concept doesn't fit this repo's no-delete stance and isn't requested.
- A generalized "exception audit" report (e.g. listing all exceptions across all categories) — no concrete
  consumer identified yet.
