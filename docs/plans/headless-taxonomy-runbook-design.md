# Design: Headless Taxonomy Runbook (Full Rebuild / Assessment / Targeted QA Fix)

> Status: approved design, not yet implemented.
> Companion to [`docs/claude-code-headless-orchestration.md`](../claude-code-headless-orchestration.md) and
> [`docs/cheaper-reliable-execution-model.md`](../cheaper-reliable-execution-model.md). Those two docs establish
> that headless `claude -p` is officially supported for unattended runs, and that it's viable across this whole
> pipeline — not just for occasional read-only checks — provided each invocation stays scoped to a
> judgment-only step with deterministic scaffolding around it. What those docs left as an interactive-only step
> was **writes**, not "everything except one narrow audit scenario": the documented headless case so far
> happened to be read-only by design, so it never had to answer the write question. This design is the
> write-scenario case — it applies the same judgment-only-`-p`-plus-deterministic-wrapper pattern to two
> scenario types that write to BigQuery (Full Rebuild, Targeted QA Fix), and additionally removes the human
> review checkpoint that write operations would otherwise keep (explicit decision below), replacing it with the
> deterministic infra defined here.

---

## Problem

`docs/categories/STATUS.md` shows all 20 TH categories complete but 0/23 SG categories LLM-extracted. Every
Phase 5 session today — regardless of scenario type (Full Rebuild, Assessment Only, Targeted QA Fix, per the
three session-brief examples in the team's Notion doc) — assumes an *interactive* Claude Code session on a
specific Mac, with a human present to catch SKU-block races, QA gate failures, and free-text extraction errors
before they reach `marketshare_universe`. There is no documented, runnable way to execute any of the three
scenario types unattended.

## Decision: run all three scenarios fully headless, no human checkpoint

Considered and rejected: headless-propose + separate human-approved apply step (the discipline the existing
read-only category-audit script uses, because that scenario happens to be read-only by design — not because
writes are categorically excluded from headless operation). Explicitly chosen instead: **full headless writes**
— `claude -p` runs each scenario to completion, including BigQuery inserts/updates and the universe refresh,
with no human review gate.

This is a real departure from every *existing, documented* headless use case in this repo, all of which have
been read-only so far (the category-health-audit scenario). Removing the human checkpoint means the specific
risks that checkpoint used to catch — SKU block collisions and QA gate failures — must now be caught by
deterministic code instead. See "Execution model" below.

## Deliverable scope

Markdown-only, matching this repo's existing role (no `pipeline/*.py` lives here — see
`docs/claude-code-headless-orchestration.md` for why). One new consolidated doc,
**`docs/headless-runbook.md`**, holding shared mechanics plus all three scenario templates as sections (not
split into per-scenario files — reduces file-jumping for what's fundamentally one procedure with three
parameter sets).

Two exceptions to "markdown-only": new schema migrations, **`sql/migrations/002_add_sku_block_registry.sql`**
(the registry table the atomic SKU claim depends on) and **`sql/migrations/003_add_universe_taxonomy_overlay.sql`**
(added per the Addendum below — a new overlay table for universe-refresh state, not an `ALTER TABLE` on the
real universe-refresh target table). Both are schema, in the same category as the existing
`sql/migrations/001_add_platform_country_columns.sql` — not wrapper scripts — so they stay in scope. No other
new script files are committed; the bash/SQL needed to run each scenario is embedded inline in the markdown as
copy-pasteable snippets, the same pattern `claude-code-headless-orchestration.md` already uses for its
`audit_category.sh` reference implementation.

## Execution model: deterministic wrapper, `claude -p` scoped to judgment only

Considered:
- **A — prompt does everything.** Single self-contained `claude -p` prompt per scenario, agent executes the SKU
  claim, QA gates, and refresh itself via free-text-directed BQ tool calls. Rejected: this is exactly the
  failure mode `cheaper-reliable-execution-model.md` already diagnosed — unattended free-text reasoning
  deciding infra sequencing, with no human left to catch a wrong turn.
- **B — deterministic wrapper, LLM only for judgment. (chosen)**
- **C — chained narrow `claude -p` calls per phase.** Rejected: 3x invocation cost/latency, and state handoff
  between calls is its own new failure surface.

**Chosen (B):** a bash+SQL block, embedded in the runbook, does the mechanical steps outside the LLM:

1. Atomically claim a SKU block (BQ multi-statement transaction against the new registry table — real
   isolation, so two concurrent claims can't both read the same `MAX(block_end)` before either commits; this is
   the direct fix for the collision already seen in production, drinking_water/toothpaste both grabbing
   `SKU-045000`).
2. Invoke `claude -p` with the claimed block passed in as a literal prompt parameter — the agent never queries
   `MAX(taxonomy_id)` itself.
3. Parse the agent's required JSON output.
4. Run QA gates (existing `CLAUDE.md` SQL + the G7 placeholder-leak check from
   `taxonomy-pipeline-improvement-recommendations.md`) as a blocking script step.
5. If gates pass, run the universe refresh DML (NULLIFY + UPDATE, both `sincere-hearth-273704` and
   `magpie-farsight`).

This applies the same principle `cheaper-reliable-execution-model.md` already argued for per-product extraction
(harness does deterministic steps, LLM does judgment) to session orchestration instead.

## Shared mechanics (all going into `docs/headless-runbook.md`)

**Atomic SKU block claim.** New table `magpie_reference.sku_block_registry`:

| column | type | notes |
|---|---|---|
| `block_start` | INT64 | |
| `block_end` | INT64 | |
| `master_table` | STRING | |
| `scenario` | STRING | `full_rebuild` \| `assessment` \| `targeted_qa_fix` |
| `claimed_at` | TIMESTAMP | |
| `status` | STRING | `ACTIVE` \| `FAILED_QA` \| `ABANDONED` \| `COMPLETE` |

Claim pattern (embedded in the runbook):

```sql
BEGIN
  BEGIN TRANSACTION;
  DECLARE next_start INT64;
  SET next_start = (SELECT COALESCE(MAX(block_end), 58455) + 1 FROM `magpie_reference.sku_block_registry`);
  INSERT INTO `magpie_reference.sku_block_registry`
    (block_start, block_end, master_table, scenario, claimed_at, status)
  VALUES (next_start, next_start + @block_size - 1, @table, @scenario, CURRENT_TIMESTAMP(), 'ACTIVE');
  COMMIT TRANSACTION;
END;
```

**DML-not-streaming rule.** Every headless-triggered insert into `product_taxonomy`/`product_taxonomy_map` must
use `bq query` DML (`INSERT INTO ... VALUES` or `INSERT ... SELECT`), never the streaming `insert_rows_json`
API. DML rows are immediately queryable (already noted in `AGENTS.md`'s Streaming Buffer Rule) — this is what
makes a single unattended run (claim → extract → QA gate → refresh, no 90-minute pause) possible at all.

**QA-gate-as-code.** Bash function running the existing 3 SQL checks from `CLAUDE.md`'s QA Gates section
(dual-mapped products, HUMAN+LLM co-existence, NULL size) plus the G7 placeholder-leak check (`REGEXP_CONTAINS`
for `undefined|null|n/a|tbd` in `canonical_name`, from `taxonomy-pipeline-improvement-recommendations.md`
Recommendation 1). Non-zero exit blocks the refresh step.

**`claude -p` invocation contract:**
- `--output-format json`
- `--permission-mode bypassPermissions`
- `--max-turns N` (cap; value documented per scenario in `docs/headless-runbook.md`)
- Prompt receives the pre-claimed block range as a literal parameter.
- Required output shape:
  ```json
  {
    "status": "complete | partial | failed",
    "rows_created": 0,
    "rows_mapped": 0,
    "taxonomy_id_range_used": "SKU-XXXXXX-SKU-YYYYYY",
    "findings": []
  }
  ```
  The wrapper parses this before deciding whether to proceed to QA gates.

## Per-scenario differences

| | Assessment Only | Targeted QA Fix | Full Rebuild |
|---|---|---|---|
| SKU block claim | None (read-only) | Small (~200 slots) | Full (~1,000 slots) |
| Prompt basis | Notion Example B, adapted for JSON-only output | Notion Example C, adapted with pre-claimed block param | Notion Example A, adapted with pre-claimed block param |
| Writes | None — decision JSON only | Reroute/create rows for flagged products only | Delete old category rows, rebuild taxonomy + map from scratch |
| QA gates | N/A | Scoped to affected `product_id`s | Full category scope |
| Universe refresh | N/A | Yes (NULLIFY + UPDATE, both projects) | Yes (NULLIFY + UPDATE, both projects) |

Assessment Only reuses the existing read-only category-audit pattern from `claude-code-headless-orchestration.md`
almost verbatim — it's already read-only and already headless-safe. Its runbook section is short: a pointer to
the existing doc plus the block-claim-skip note.

## Error handling

- `claude -p` exits non-zero, hits `--max-turns` without completing, or returns malformed/missing-field JSON →
  wrapper aborts **before** QA gates and refresh. Claimed block is marked `FAILED_QA` in the registry (never
  reused, never deleted — a burned 1,000-slot block is free; a reused one is a collision). Raw output logged for
  follow-up.
- QA gates fail post-run → same abort-before-refresh behavior. New rows stay in `product_taxonomy` /
  `product_taxonomy_map` but never reach `marketshare_universe` — a bad run is inert, not silently live.

## Worked example

One full walkthrough in the runbook for `shopee_sg_shampoo` (flagged as next priority in `STATUS.md`) run as a
Full Rebuild: the actual claim transaction, a realistic `claude -p` prompt, sample JSON output, the QA gate run,
the refresh DML. This doubles as the guide's own correctness check — if the worked example doesn't run clean
against real BQ, the guide is wrong, not just under-explained.

The Full Rebuild prompt requires a category context file (`docs/categories/sg_shampoo.md`, per the existing
`_TEMPLATE.md`) to exist before it can run. Since the worked example is the guide's own runnability check,
authoring that one file (official-store allowlist, scope in/out, edge cases) is **in scope** as part of writing
the worked example — it's the minimum needed to make the example real rather than illustrative. Other SG
category context files remain out of scope (see below).

## Addendum (found during plan-writing, 2026-07-14)

Live BigQuery discovery (same session that ran the size-regex-pass plan) found the universe-refresh step as
designed is broken against the real environment — corrected here before task-by-task planning:

1. **`magpie.marketshare_universe` is not the FMCG output table anymore.** Its live schema has no
   `master_table`, `taxonomy_id`, or `magpie_category_*` columns, and its TH data is 100% consumer
   electronics/appliance categories (Lighting, TV, Washing Machine, Refrigerator, ...) — a different business
   line now occupies that table name. Confirmed directly: a real toothpaste product (`"Master rabbit coco tooth
   mouth paste ยาสีฟัน"`) is mis-tagged there as `Electronics > Small Appliances > Grooming`.
2. **The real FMCG table is `magpie.marketshare_universe_niq`** (10.9M rows, Jun 2025–May 2026, clustered by
   `country, category_3, brand_id`) — confirmed via live query: TH `category_3` values are Face Moisturizer,
   Shampoo, Body Wash, Toothpaste, Laundry Detergent, Baby Diapers, etc., matching the documented 43-category
   scope exactly. It has `master_table`, `brand_id`, `category_1/2/3` — but **no taxonomy columns at all**
   (`taxonomy_id`, `sku_type_complete`, `taxonomy_source`, `taxonomy_confidence`, `taxonomy_meta_agent` are all
   absent). The `CLAUDE.md` refresh pattern's `SET taxonomy_id = ..., sku_type_complete = ...` assumes these
   columns exist; they don't, on the table that actually holds current FMCG data.
3. **Fix (revised):** rather than `ALTER TABLE` on the shared 10.9M-row `marketshare_universe_niq`, taxonomy
   state lives in a new overlay table, `magpie_reference.universe_taxonomy_overlay`, keyed identically to
   `product_taxonomy_map` — the same overlay-not-mutate pattern this pipeline already uses everywhere else
   (`product_taxonomy_map` is itself an overlay on source data, not a column added to source tables). The
   universe-refresh step is a single `MERGE` into this table (insert/update/stale-delete in one statement,
   replacing `CLAUDE.md`'s two-step NULLIFY+UPDATE, which doesn't apply here — a stale row is removed outright,
   not nulled). Implemented in the plan, not re-litigated here — see
   `docs/plans/headless-taxonomy-runbook-implementation-plan.md`.
4. **Farsight mirror is affected the same way.** Checked live: `magpie-farsight.universe.marketshare_universe`
   has the exact same schema as the repurposed `sincere-hearth-273704.magpie.marketshare_universe` (no
   `master_table`/taxonomy columns), and there is **no `_niq` equivalent in the farsight project at all**. The
   farsight refresh step is dropped from this plan's scope — it would be refreshing a table that was already
   wrong before this design existed, and fixing that is a separate decision (does farsight need an `_niq`
   mirror at all?), not something to bolt onto this plan.
5. **Not resolved, not blocking:** why/when `marketshare_universe` got repurposed, whether `marketshare_universe_niq`
   is still being promoted anywhere downstream, and what `marketshare_universe_new` /
   `master_magpie_universe` (which does have a `sku_type_complete`-clustered variant) are for — out of scope for
   this design; flagged for whoever owns the broader BQ project's table sprawl.

## Out of scope

- No new Python/bash script files committed to this repo (see Deliverable scope above).
- No changes to the interactive-session workflow — this is an additional, parallel path, not a replacement.
- Batch API / prompt-caching cost optimizations from `cheaper-reliable-execution-model.md` are not part of this
  design; this design is about *unattended execution*, not *cost*. Could layer on later.
- SG-specific category context files for categories **other than** `sg_shampoo` (`docs/categories/sg_*.md`) are
  a prerequisite for running those categories through this runbook but are not authored as part of this design
  — separate effort, tracked implicitly by `STATUS.md`'s remaining SG rows showing "Keyword only."
