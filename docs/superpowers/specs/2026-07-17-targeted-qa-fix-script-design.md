# Design: Targeted QA Fix Script (`script/targeted_qa_fix.sh`)

> Status: approved design, not yet implemented.
> Companion to [`docs/headless-runbook.md`](../../headless-runbook.md) (defines the "Scenario: Targeted QA Fix"
> procedure this script implements) and [`script/headless_taxonomy.sh`](../../../script/headless_taxonomy.sh)
> (the Full Rebuild reference script this one matches in style). Reuses
> [`script/qa_report.sh`](../../../script/qa_report.sh) as-is for gating.

---

## Problem

`docs/headless-runbook.md` documents a "Scenario: Targeted QA Fix" procedure (claim a small SKU block → run
`claude -p` against a specific fix list → gate → refresh) as a 5-step manual runbook, but — unlike Full Rebuild,
which has `script/headless_taxonomy.sh` — there is no script that actually runs it. A concrete trigger: a
detailed Targeted QA Fix brief for `shopee_th_detergent` (pack-count multiplier expansion, wrong-size reroutes,
bundle tagging, NULL-coverage pass) needs a repeatable way to execute, and the next category that needs a
targeted fix shouldn't require hand-typing the whole runbook procedure again.

## Deliverable scope

One new script, **`script/targeted_qa_fix.sh`**, plus a new `## Targeted QA Fix Brief` section added to
`docs/categories/th_detergent.md` holding the TH detergent brief as the first real input the script can run
against. No other files change. No `pipeline/*.py` — matches this repo's existing markdown/bash-only pattern for
headless orchestration (`docs/claude-code-headless-orchestration.md`).

## Execution model: same split as the Full Rebuild design, applied to Targeted QA Fix

`docs/superpowers/specs/2026-07-14-headless-taxonomy-runbook-design.md` already decided (for this whole headless
system) that `claude -p` should be scoped to judgment only, with QA gates and universe refresh run as
*deterministic wrapper steps*, not self-certified by the agent. This design applies that same split to Targeted
QA Fix specifically:

- **Agent-side** (inside the single `claude -p` call, `--max-turns 30` per the runbook): claim the SKU block
  (the atomic transactional claim against `sku_block_registry` — safe regardless of whether bash or the agent
  issues it, since the atomicity comes from the BigQuery transaction, not the caller; `headless_taxonomy.sh`'s
  actual Full Rebuild implementation does this agent-side too), execute the fixes described in the brief, write
  via DML only, append its own findings to the category file's `QA History` table, and self-report the required
  JSON contract.
- **Wrapper-side** (bash, after `claude -p` returns): parse the JSON status, and — critically — do **not** trust
  a `complete`/`partial` self-report on its own. Independently re-run the QA gates via the already-existing
  `script/qa_report.sh`, and only run the universe refresh if that independent check passes. This is the one
  place this design goes further than `headless_taxonomy.sh` (which has no wrapper-side gate/refresh at all) —
  because a Targeted QA Fix's whole purpose is correctness on a table that's already live in production, self-
  certification before touching the shared overlay table is the wrong tradeoff here.

## Input: the brief lives in the category file, not a script argument

The fix brief (context, current-state snapshot, Fix A/B/C, NULL-coverage pass, category-specific QA gates) is
written into `docs/categories/<table>.md` under a new `## Targeted QA Fix Brief` heading — the same file
`headless_taxonomy.sh` already reads/writes for Full Rebuild, and the same file the existing `## QA History`
table convention (already used by `sg_shampoo.md`, `shopee_sg_breakfast_cereals.md`, `sg_toothpaste.md`) lives
in. Keeping the brief there — instead of a separate `docs/qa-fixes/` directory or a script argument — means:

- The script's call signature stays `targeted_qa_fix.sh <TABLE>`, identical in shape to `headless_taxonomy.sh
  <TABLE>`.
- The brief and the resulting QA History entry live next to each other and next to the category's brand
  scope / scope-exclusion rules the agent needs anyway — one file to read, one file to update.
- A category with no Brief section yet is a legitimate `blocked` outcome (nothing to execute), not a script
  error.

**File resolution:** existing category files inconsistently drop the `shopee_` prefix (`th_detergent.md`, not
`shopee_th_detergent.md`; but `shopee_sg_breakfast_cereals.md` keeps it). The script tries
`docs/categories/<TABLE>.md`, then `docs/categories/<TABLE#shopee_>.md`, and errors out before invoking `claude
-p` if neither exists — a Targeted QA Fix (unlike Full Rebuild) always targets an already-documented category.

## `claude -p` prompt contract

Boilerplate reads: `CLAUDE.md`, `ARCHITECTURE.md`, `docs/llm-extraction-rules.md`, `docs/headless-runbook.md`,
`docs/quality-standards.md`, and the resolved category file in full (including its `Targeted QA Fix Brief`
section — the actual per-table instructions).

Steps, matching `docs/headless-runbook.md` § Scenario: Targeted QA Fix:

1. Sanity-check the brief's "current state" claims (map row counts, existing SKU range) against a live query —
   flag drift in `findings` rather than silently trusting stale numbers, same caution `headless_taxonomy.sh`
   applies to Full Rebuild's Step 1.
2. Claim a 200-slot block atomically (`scenario='targeted_qa_fix'`, DECLARE-before-BEGIN-TRANSACTION order —
   reversing that order is a real BigQuery scripting syntax error, already hit once per
   `headless_taxonomy.sh`'s own comment).
3. Execute exactly the fixes described in the brief section — this is where the table-specific content (pack
   multiplier parsing, wrong-size reroutes, bundle tagging, NULL coverage) lives; the script has no hardcoded
   knowledge of any category's specific fixes.
4. DML only (never the streaming API), `meta_agent='CLAUDE_CODE'` on every touched row, never delete existing
   rows unless the brief explicitly instructs it.
5. Do **not** run the universe refresh — that's the wrapper's job, after independent gate verification.
6. Append a dated row to the category file's `## QA History` table (create the section, using the `_TEMPLATE.md`
   column shape `Date | Pass | Finding | Resolution`, if the file doesn't have one yet) and commit the updated
   category file.
7. Output only the standard JSON contract: `{status, rows_created, rows_mapped, taxonomy_id_range_used,
   findings, blockers}`. `status='blocked'` (missing Brief section, genuine ambiguity, infeasible scope) is a
   valid, expected outcome — not a failure.

## Wrapper-side control flow (after `claude -p` returns)

```
parse `.result` from the --output-format json envelope → parse `status`

status == blocked           → print blockers, exit 0. Block stays ACTIVE (nothing written, safe to reuse).
malformed / non-zero exit / unrecognized status
                             → mark the table's most recent ACTIVE targeted_qa_fix block FAILED_QA, exit 1.
status == failed             → mark block FAILED_QA, exit 1.
status in (complete, partial) with rows_created > 0
                             → run `./script/qa_report.sh <TABLE>` (no --skip-coexistence — for a
                               Targeted QA Fix, HUMAN+LLM coexistence is always a genuine bug, never an
                               expected mid-rebuild state).
    gate exit 0             → run the universe-refresh MERGE (inlined bq query, the exact statement from
                               headless-runbook.md § Universe refresh, sincere-hearth-273704
                               `universe_taxonomy_overlay` only — see Farsight note below). exit 0.
    gate exit non-zero      → mark block FAILED_QA, exit 1.
```

`FAILED_QA` marking looks up the block via `sku_block_registry WHERE master_table = <TABLE> AND
scenario = 'targeted_qa_fix' AND status = 'ACTIVE' ORDER BY claimed_at DESC LIMIT 1` rather than parsing
`taxonomy_id_range_used` out of the agent's JSON — one less thing that can be malformed and break the wrapper.

**Farsight is intentionally dropped**, even though the pasted brief said "refresh both sincere + farsight."
`docs/headless-runbook.md` (which supersedes `CLAUDE.md` here — it says explicitly "the target table isn't what
`CLAUDE.md` says") retired the farsight refresh entirely: there's no farsight equivalent of the
`universe_taxonomy_overlay` table this design writes to, and the underlying `marketshare_universe_niq` table is
never altered directly. The script follows `headless-runbook.md`, not the brief's now-outdated instruction.

## Error handling

Same three failure classes as `docs/headless-runbook.md` § Error handling, applied via the control-flow table
above: `blocked` (not a failure, block stays reusable), malformed/crashed `claude -p` output (abort before any
gate/refresh, mark `FAILED_QA`), and QA gate failure post-run (new rows stay in `product_taxonomy`/
`product_taxonomy_map` — inert, never reach `universe_taxonomy_overlay` — mark `FAILED_QA`).

## Testing

This is an orchestration wrapper around two external calls (`claude -p`, `bq`) — there's no unit worth mocking.
The one runnable check is a syntax/argument-validation smoke test: `bash -n script/targeted_qa_fix.sh` (catches
shell syntax errors) plus running the script with a bad/missing `TABLE` and confirming it fails fast with a
clear message before attempting any `claude -p` or `bq` call. No BQ-hitting test is in scope — actually running
this script against `shopee_th_detergent` is a real, costly production write, a separate decision from building
the script (same caveat `headless-runbook.md` gives for Full Rebuild).
