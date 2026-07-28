# Design: One-Pass Confidence Classification for `targeted_qa_fix.sh` / `custom_targeted_qa_fix.sh`

> Status: approved design, not yet implemented.
> Companion to [`script/targeted_qa_fix.sh`](../../../script/targeted_qa_fix.sh),
> [`script/custom_targeted_qa_fix.sh`](../../../script/custom_targeted_qa_fix.sh),
> [`script/qa_coverage_report.sh`](../../../script/qa_coverage_report.sh), and
> [`docs/superpowers/specs/2026-07-21-taxonomy-review-loop-design.md`](2026-07-21-taxonomy-review-loop-design.md)
> (introduced the `_meta`/`review_confidence` model and the two-agreeing-reviews rule this design revises) and
> [`docs/superpowers/specs/2026-07-24-qa-fix-bundle-gate-and-fastlane-design.md`](2026-07-24-qa-fix-bundle-gate-and-fastlane-design.md)
> (built the STEP 1C fast-lane mechanism this design extends earlier into the same session).

---

## Problem

Reaching `review_confidence = 'confident'` today always costs **two agreeing reviews across two separate
sessions**, regardless of how the row is reviewed:

- A never-reviewed row's first-ever Tier 2 "correct" verdict lands on `unconfident` — by design (07-21 spec:
  "one data point is not confidence") — and needs a *second*, later session's Tier 2 judgment to agree before
  becoming `confident`.
- A row fixed this session has its `_meta` reset to `{"is_reviewed": false}`; even though STEP 1C (07-24 spec)
  can confirm the fix held using only a cheap Tier 1 SQL recheck (no LLM judgment needed), that confirmation
  only runs in a *future* session's STEP 1C pass, never the same session as the fix.

Both cases spend a full extra session-cycle to reach `confident` for a row that a cheap, already-available
signal could have confirmed immediately. Live numbers (`shopee_sg_facial_moisturiser`, 2026-07-28):
2,632 never-reviewed, 386 `fixed_pending_recheck`, 554 `unconfident`, only 264 `confident` of 3,836 total — the
majority of the backlog is rows waiting on a second pass, not rows nobody has looked at.

This is one of several throughput levers identified in conversation (see also: sharding Tier 2 judgment across
parallel sessions, and fixing `brand_dict`'s missing atomic claim) — this spec covers only the confidence-model
change. The ~2x throughput gain here does not, by itself, get a multi-thousand-row category to 90% confident in
5 sessions; it is a prerequisite improvement, with sharding as the next, larger lever (separate spec, once this
ships).

---

## Deliverable scope

| File | Change |
|------|--------|
| `script/targeted_qa_fix.sh` | `build_auto_discovery_prompt`'s STEP 4 gains an inline recheck-and-fold instruction; STEP 5 gains a new, additional promotion path for never-reviewed rows (existing path for prior-verdict rows unchanged) |
| `script/custom_targeted_qa_fix.sh` | Same STEP 4 / STEP 5 changes, mirrored in the same commit (prompt-internal STEP logic is not one of this script's three deliberate-drift points from `targeted_qa_fix.sh`) |
| `script/test_targeted_qa_fix.sh` | New/updated assertions for both STEP 5 paths, the `qa_gate_exceptions` carve-out, and STEP 4's fold-in instruction |
| `script/test_custom_targeted_qa_fix.sh` | Same assertions, mirrored |
| `docs/quality-standards.md` | §9 (or wherever the `_meta`/review-loop mechanics are documented per the 07-21 spec) gets the new promotion rule documented alongside the existing one |

No changes to: `qa_coverage_report.sh` (bucket definitions — `never_reviewed` / `fixed_pending_recheck` /
`unconfident` / `confident` — are unchanged; only how fast a row moves between them changes), `qa_report.sh`
(hard gates, independent of `_meta`), the worklist query's `_meta IS NULL OR review_confidence != 'confident'`
predicate, or GMV-prioritized Tier 2 sampling order (STEP 3).

---

## 1. New `_meta` promotion logic (STEP 5)

Today's STEP 5 has one promotion rule, applied to every reviewed row uniformly:

```sql
UPDATE ... SET _meta = TO_JSON_STRING(STRUCT(
  true AS is_reviewed, CURRENT_TIMESTAMP() AS last_reviewed_at,
  IF(JSON_VALUE(pt._meta, '$.last_verdict') = 'correct', 'confident', 'unconfident') AS review_confidence,
  'correct' AS last_verdict
))
WHERE pt.taxonomy_id IN (...)
```

This rule reads a row's *own prior* `last_verdict` and only promotes to `confident` if the new verdict agrees
with it — correct behavior for a row that already has a stored prior verdict (a `fixed_pending_recheck` row,
or a genuinely-reviewed-once-already row). It is **kept, unchanged**, for that case.

**New, additional path — never-reviewed rows only (`_meta IS NULL` going into this session):**

A never-reviewed row reviewed this session promotes straight to `confident`, in one pass, when **both**:
1. Tier 2 verdict = "correct", **and**
2. Tier 1 is "fully clean" for that row — defined as: no Tier 1 flag trips, **or** every flag that does trip
   already has a matching row in `qa_gate_exceptions` (see §2 below).

If Tier 2 says "correct" but Tier 1 has an un-excepted flag, the row lands on `unconfident` (the two signal
types disagree — genuinely uncertain, not auto-promoted). If either tier says "wrong," the row goes through
STEP 4 (fix) as today.

This is a deliberate, explicit choice, stated plainly per this repo's existing precedent (07-24 spec, §"Precision
tradeoff, stated plainly"): a single Tier-2 judgment, corroborated by an independent Tier-1 mechanical check in
the same pass, is treated as sufficient — instead of requiring the *same* kind of judgment to independently
recur in a *later* session. The AND-gate (not a bare Tier-2-correct) was chosen specifically because it costs
nothing (Tier 1 already runs on every row regardless) and keeps a second, independent signal in the loop before
calling a row permanently confident.

Net effect: a correctly-extracted never-reviewed row consumes **one** Tier 2 judgment slot instead of two
(spread over two sessions) to reach `confident` — roughly 2x more never-reviewed rows reach `confident` per
unit of Tier 2 budget than today.

---

## 2. `qa_gate_exceptions` carve-out for structurally unfixable Tier 1 flags

Some Tier 1 flags can trip permanently with no possible fix — e.g. `null_size` on a row whose `sku_name` and
image genuinely carry no extractable size signal (`docs/quality-standards.md` §3 D4; ~665-716 such rows
re-flagged and deferred every session on `shopee_sg_facial_cleanser` alone). Under a strict AND-gate, such a
row could never reach `confident`, even though the old two-agreeing-reviews model *could* eventually confident
it via two independent Tier-2 "correct" verdicts. That would be a silent regression.

Fix: extend `qa_gate_exceptions` — already used for `qa_report.sh`'s five named category-level gates
(`placeholder-leak`, `structured-fields NULL%`, `all variant/size name`, `canonical_name fields`, `garbled
brand text`) — to also accept Tier 1's own per-row flag names (`null_size`, `stub_leak`, `duplicate_brand`,
etc.) as valid `gate_name` values, keyed the same way: `(gate_name, master_table, entity_id=taxonomy_id)`. This
is a documentation/prompt change only — `qa_gate_exceptions`' schema (`gate_name, master_table, entity_id,
reason, confirmed_at, meta_agent`) already supports arbitrary `gate_name` strings; no migration needed.

STEP 4's existing "confirmed structural false positive, needs a second confirming session before excepting"
process (already described in STEP 1B for `qa_report.sh`'s gates) applies identically here: a single session
judging a `null_size` row as unfixable is not enough to except it; a second (or later) session reaching the
same conclusion inserts the `qa_gate_exceptions` row. Until excepted, a `null_size`-flagged never-reviewed row
lands on `unconfident` under the new AND-gate rule (§1) — same outcome as today, just not permanently blocked
once an exception exists.

---

## 3. STEP 4 (apply fixes) — inline recheck-and-fold

Today, a row fixed via STEP 4 has its `_meta` reset to `{"is_reviewed": false}` and waits for a **future**
session's STEP 1C to confirm the fix held (via the same cheap Tier 1 SQL sweep) before reaching `confident`.

New instruction appended to STEP 4: immediately after applying a fix to a `taxonomy_id`, re-run the Tier 1 flag
check on that row inline (same flags, same query shape STEP 1C already uses) and fold the result into the
**same session's** STEP 5 UPDATE:
- Tier 1 clean on recheck → `confident`, this session (no waiting for STEP 1C next time).
- Tier 1 still flagged → leave `_meta` at `{"is_reviewed": false}` (today's reset rule, unchanged) — picked up
  again by STEP 2's worklist-wide sweep or a future STEP 1C pass, same as today.

STEP 1C itself is **unchanged** — it remains the fast-lane for rows fixed in a *prior* session that weren't
caught by this same-session fold-in (e.g. a fix applied near the end of a turn-budget-limited session, before
this STEP 4 addition existed for that row).

---

## 4. Testing / Verification

- `bash -n script/targeted_qa_fix.sh` and `bash -n script/custom_targeted_qa_fix.sh` — syntax check.
- `bash script/test_targeted_qa_fix.sh` / `test_custom_targeted_qa_fix.sh` — extend with:
  - STEP 5's prompt text contains **both** promotion paths: the existing `IF(JSON_VALUE(pt._meta,
    '$.last_verdict') = ...)` comparison (for prior-verdict rows) **and** the new unconditional
    never-reviewed-row promotion condition (Tier 2 correct + Tier 1 clean). Do **not** assert the old IF() text
    is absent — it must remain, verbatim, for the `fixed_pending_recheck` path.
  - Prompt text references `qa_gate_exceptions` as valid for Tier 1 flag names, not just `qa_report.sh`'s five
    named gates.
  - STEP 4's text contains the inline recheck-and-fold instruction (re-run Tier 1 flags on the just-fixed row,
    fold into the same STEP 5 UPDATE).
- Manual: run against a live category with a large never-reviewed count (e.g. `shopee_sg_shampoo`, 1,014
  never-reviewed as of 2026-07-28) and compare `qa_coverage_report.sh` before/after — expect confident-count
  growth meaningfully above the historical ~15-20/session baseline, since correctly-judged never-reviewed rows
  no longer wait a second session.
- Manual: confirm a `null_size`-flagged row with a confirmed `qa_gate_exceptions` entry is eligible for direct
  `confident` promotion under the new AND-gate (not silently excluded).

---

## Open Follow-ups (explicitly out of scope for this change)

- **Sharding Tier 2 judgment across parallel `claude -p` sessions** (wrapper-level, `MOD(FARM_FINGERPRINT(...))`
  worklist split, single `qa_report.sh` + universe refresh after all shards return) — the larger throughput
  lever (~10x+) needed alongside this change to reach 90%-confident-in-5-sessions on large categories. Separate
  spec.
- **`brand_dict` atomic claim** (mirroring `sku_block_registry`'s DECLARE/BEGIN TRANSACTION) — a prerequisite
  for the sharding spec above, since concurrent shards would otherwise race brand_dict inserts the way
  sequential sessions already have (`BRD-SG-13549`, `BRD-SG-14371`, "Cara and Co" collisions). Same separate
  spec.
- **A `deletion-authorized` scenario/script** — findings flagged as needing deletion or re-mapping
  (dual-mapped, HUMAN+LLM coexistence, duplicate product+taxon) currently have no tool to act on them and
  accumulate across sessions indefinitely (e.g. a mis-merged `sg_facial_cleanser` listing grew from ~$74K to
  ~$1.58M GMV, unfixed, across many sessions). Real gap, unrelated to the confidence-model mechanics this spec
  covers.
- **Stratified/quota-based Tier 2 sampling** (vs. pure GMV-first ordering) so long-tail/low-GMV rows are
  guaranteed a look within a bounded number of sessions — complements this change and the sharding follow-up,
  not part of either.
- **Bare Tier-2-correct (no Tier-1 AND-gate)** as an alternative, cheaper-but-riskier confident bar — considered
  and explicitly not chosen (see §1); revisit only if the AND-gate's cost (Tier 1 already runs regardless) is
  found to not hold in practice.
