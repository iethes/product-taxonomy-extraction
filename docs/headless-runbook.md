# Headless Taxonomy Runbook

Runnable procedure for Full Rebuild, Assessment Only, and Targeted QA Fix taxonomy sessions via headless
`claude -p`, with no human checkpoint on writes. Companion to
[`docs/claude-code-headless-orchestration.md`](claude-code-headless-orchestration.md) (general headless
mechanics) and [`docs/plans/headless-taxonomy-runbook-design.md`](plans/headless-taxonomy-runbook-design.md)
(the design this implements — read its Addendum before touching universe refresh, the target table isn't what
`CLAUDE.md` says).

## Prerequisites

- `bq`/`gcloud` on PATH, authenticated against `sincere-hearth-273704` with BigQuery Data Editor on
  `magpie_reference` and `magpie`.
- `claude` CLI installed and authenticated (headless runs bill against a separate API-rate credit pool as of
  2026-06-15 — see `docs/claude-code-headless-orchestration.md`).
- `sql/migrations/002_add_sku_block_registry.sql` and
  `sql/migrations/003_add_universe_taxonomy_overlay.sql` have been run once
  (`docs/plans/headless-taxonomy-runbook-implementation-plan.md` Tasks 1–2).

## Shared mechanics

### Atomic SKU block claim

Never query `MAX(taxonomy_id)` directly and assume it's still current by the time you insert — two sessions
racing on that read is exactly what caused the SKU-045000 collision recorded in `docs/llm-extraction-rules.md`'s
changelog. Claim atomically instead:

```sql
BEGIN
  DECLARE next_start INT64;
  BEGIN TRANSACTION;
  SET next_start = (SELECT COALESCE(MAX(block_end), 69000) + 1 FROM `sincere-hearth-273704.magpie_reference.sku_block_registry`);
  INSERT INTO `sincere-hearth-273704.magpie_reference.sku_block_registry`
    (block_start, block_end, master_table, scenario, claimed_at, status)
  VALUES (next_start, next_start + @block_size - 1, @table, @scenario, CURRENT_TIMESTAMP(), 'ACTIVE');
  COMMIT TRANSACTION;
END;
```

Block sizes by scenario: Assessment Only claims none (read-only). Targeted QA Fix claims ~200. Full Rebuild
claims ~1,000. `claude -p` receives the claimed `[block_start, block_end]` range as a literal prompt parameter
— it never queries `MAX(taxonomy_id)` itself.

### DML-not-streaming rule

Every headless-triggered insert into `product_taxonomy`/`product_taxonomy_map` must use `bq query` DML
(`INSERT INTO ... VALUES` or `INSERT ... SELECT`), never the streaming `insert_rows_json` API. DML rows are
immediately queryable (`docs/llm-extraction-rules.md`'s Streaming Buffer rule) — this is what makes a single
unattended run (claim → extract → QA gate → refresh, no 90-minute pause) possible at all.

### QA-gate-as-code

Bash function running these checks, non-zero exit blocks the refresh step:

```bash
# Usage: run_qa_gates <table> [--skip-coexistence]
# --skip-coexistence: use for the pre-delete pass in Full Rebuild (Scenario: Full Rebuild, step 4) —
# HUMAN+LLM coexistence is EXPECTED and correct at that point (old rows not deleted yet), not a real
# failure. Omit the flag for the post-delete pass (step 6) and for Targeted QA Fix, where coexistence
# is always a genuine bug.
run_qa_gates() {
  local table="$1"
  local skip_coexistence="${2:-}"

  local dual_mapped
  dual_mapped=$(bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=csv \
    "SELECT COUNT(*) FROM (
       SELECT product_id FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy_map\`
       WHERE master_table = '${table}' AND source = 'LLM' GROUP BY product_id HAVING COUNT(*) > 1
     )" | tail -1)
  if [ "$dual_mapped" != "0" ]; then
    echo "QA GATE FAILED: ${dual_mapped} dual-mapped LLM products for ${table}"; return 1
  fi

  if [ "$skip_coexistence" != "--skip-coexistence" ]; then
    local human_llm_coexist
    human_llm_coexist=$(bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=csv \
      "SELECT COUNT(*) FROM (
         SELECT product_id FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy_map\`
         WHERE master_table = '${table}'
         GROUP BY product_id HAVING COUNTIF(source='LLM') > 0 AND COUNTIF(source='HUMAN') > 0
       )" | tail -1)
    if [ "$human_llm_coexist" != "0" ]; then
      echo "QA GATE FAILED: ${human_llm_coexist} products with HUMAN+LLM co-existence for ${table}"; return 1
    fi
  fi

  local placeholder_leak
  placeholder_leak=$(bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=csv \
    "SELECT COUNT(*) FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy\` pt
     JOIN \`sincere-hearth-273704.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
     WHERE m.master_table = '${table}'
       AND REGEXP_CONTAINS(LOWER(pt.canonical_name), r'\\b(undefined|null|n/a|tbd)\\b')" | tail -1)
  if [ "$placeholder_leak" != "0" ]; then
    echo "QA GATE FAILED: ${placeholder_leak} placeholder-leak canonical names for ${table}"; return 1
  fi

  echo "QA gates passed for ${table}"
  return 0
}
```

**Found via the `shopee_sg_shampoo` attempt #2 report (2026-07-15):** the dual-mapped check was originally
unscoped (no `source = 'LLM'` filter), so it double-counted the same legitimate HUMAN+LLM mid-rebuild
coexistence the second gate already exists to check — 847 products, not a real bug, but the unscoped query
couldn't tell the difference and would have blocked a wrapper that ran it naively. Scoped now. The
`--skip-coexistence` flag is the second half of the same fix — without it, `run_qa_gates()` as a single
all-or-nothing function couldn't express "coexistence is fine right now, check again after the delete,"
even though the Full Rebuild scenario's own prose already assumed that two-phase behavior.

(3 checks from `CLAUDE.md`'s QA Gates section, minus the NULL-size gate — that one needs manual judgment per
row per `CLAUDE.md`'s own caveat "or document why each NULL is legitimate," not a hard pass/fail — plus the G7
placeholder-leak check from `docs/taxonomy-pipeline-improvement-recommendations.md` Recommendation 1.)

### `claude -p` invocation contract

- `--output-format json`
- `--permission-mode bypassPermissions`
- `--max-turns N` (cap; documented per scenario below)
- Prompt receives the claimed `[block_start, block_end]` range as a literal parameter
- Required output shape:
  ```json
  {
    "status": "complete | partial | failed | blocked",
    "rows_created": 0,
    "rows_mapped": 0,
    "taxonomy_id_range_used": "SKU-XXXXXX-SKU-YYYYYY",
    "findings": [],
    "blockers": []
  }
  ```

**`blocked` is a distinct, legitimate outcome, not a failure** — added after the `shopee_sg_shampoo` attempt
2026-07-15, where the agent found real blockers (undocumented existing rows, ambiguous scope, infeasible scale
for a single session) and correctly stopped before writing anything, but had no schema slot for "stopped for a
real reason" and returned free-text prose instead of JSON. `status='blocked'` with a populated `blockers` array
lets the wrapper tell "asked a legitimate question" apart from "tried and failed" — see Error handling below for
how each is handled differently (a `blocked` outcome with zero rows written means the claimed block is still
valid and reusable for a retry; `failed`/`partial` should burn the block).

**The prompt must tell the agent it performs extraction itself.** The `shopee_sg_shampoo` attempt stalled
partly because the prompt didn't say this explicitly, and the agent pattern-matched to `CLAUDE.md`'s documented
"`ANTHROPIC_API_KEY` not set in subprocess" pitfall — which is about the *external Python pipeline's*
subprocess-based LLM calls, not applicable here. Every Full Rebuild / Targeted QA Fix prompt must state
plainly: *you* read product images and text directly with your own multimodal capabilities; you do not invoke
external scripts or need any API key beyond your own session auth.

### Universe refresh

**No `ALTER TABLE` on `marketshare_universe_niq`.** That table (the real FMCG output table — see
`docs/plans/headless-taxonomy-runbook-design.md` Addendum for why it's this one, not
`magpie.marketshare_universe`) is a shared, 10.9M-row production table. Instead of adding taxonomy columns to
it directly, taxonomy state lives in a separate overlay table,
`magpie_reference.universe_taxonomy_overlay` (`sql/migrations/003_add_universe_taxonomy_overlay.sql`), keyed
identically to `product_taxonomy_map`. This is the same pattern the pipeline already uses everywhere else —
`product_taxonomy_map` itself is an overlay on source data, not a column added to the source tables. Anyone
wanting combined data joins the two tables at query time on `(product_id, platform, country)`; the production
table's schema never changes. Farsight refresh is dropped (see the Addendum — same table-repurposing problem,
no `_niq` equivalent exists there).

One `MERGE` handles insert, update, and stale-row cleanup atomically (replaces the two-step NULLIFY+UPDATE
pattern from `CLAUDE.md`, which doesn't apply here since there's no column-nulling to do — a stale row is
removed from the overlay table outright):

```sql
MERGE `sincere-hearth-273704.magpie_reference.universe_taxonomy_overlay` t
USING (
  SELECT m.product_id, m.platform, m.country, m.master_table,
         pt.taxonomy_id, pt.canonical_name, m.source, m.confidence, m.meta_agent
  FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt ON m.taxonomy_id = pt.taxonomy_id
  WHERE m.master_table = @table
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY m.product_id, m.platform, m.country
    ORDER BY CASE m.source WHEN 'LLM' THEN 0 ELSE 1 END, m.taxonomy_id
  ) = 1
) src
ON t.product_id = src.product_id AND t.platform = src.platform AND t.country = src.country
  AND t.master_table = @table
WHEN MATCHED THEN UPDATE SET
  taxonomy_id = src.taxonomy_id,
  sku_type_complete = src.canonical_name,
  taxonomy_source = src.source,
  taxonomy_confidence = src.confidence,
  taxonomy_meta_agent = src.meta_agent,
  updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED BY SOURCE AND t.master_table = @table THEN DELETE
WHEN NOT MATCHED BY TARGET THEN INSERT
  (product_id, platform, country, master_table, taxonomy_id, sku_type_complete,
   taxonomy_source, taxonomy_confidence, taxonomy_meta_agent, updated_at)
  VALUES (src.product_id, src.platform, src.country, src.master_table, src.taxonomy_id, src.canonical_name,
          src.source, src.confidence, src.meta_agent, CURRENT_TIMESTAMP());
```

The `AND t.master_table = @table` condition on the `WHEN NOT MATCHED BY SOURCE` branch is load-bearing — this
overlay table holds rows for every category, and without that condition BigQuery would try to delete every
other category's rows too (they're also "not matched" by a `src` that's filtered to just `@table`).

(Join key is `product_id + platform + country` — the real ADR-006 composite key, not `master_table` alone,
matching the correction already proven in `docs/plans/size-regex-pass-implementation-plan.md`'s backfill query
this same session.)

## Scenario: Assessment Only

Read-only — no SKU claim, no writes, no QA gates, no universe refresh. This is the existing pattern from
[`docs/claude-code-headless-orchestration.md`](claude-code-headless-orchestration.md)'s reference
implementation almost verbatim; this section is a pointer, not a re-implementation.

```bash
GOOGLE_APPLICATION_CREDENTIALS=/tmp/audit_readonly_creds.json \
claude -p --output-format json --permission-mode bypassPermissions "
Quality assessment for ${TABLE} — sample top 50 products by GMV ${MONTH}, review current taxonomy mapping
against magpie_reference.product_taxonomy_map and product_taxonomy.
Output ONLY this JSON, nothing else: {category, decision: patch|fresh_run|healthy, confidence, findings: [...], proposed_patch_sql: null|string}.
Do NOT run any UPDATE/INSERT/DELETE. Read-only assessment only.
" > "audits/${TABLE}/$(date +%Y-%m-%d).json"
```

## Scenario: Targeted QA Fix

Small SKU block (~200), narrow prompt scope (specific flagged products, not a full category rebuild), QA gates
scoped to affected `product_id`s only, universe refresh runs but only touches the products actually rerouted.

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

## Scenario: Full Rebuild

Full SKU block (~1,000 slots), rebuilds a category's taxonomy from scratch — supersedes old map rows (delete
*after* the new taxonomy is built and QA'd, never before — see step 4), re-extracts via Pass 1 (official
stores) + Pass 2 (reseller routing), then QA gates + universe refresh across the whole category.

**Worked example: `shopee_sg_shampoo`.** Attempt #1 (2026-07-15) claimed a real block (`SKU-069001`–
`SKU-070000`, still `ACTIVE`, zero rows written) and correctly stopped itself before writing anything — see
`docs/categories/sg_shampoo.md`'s QA History for what it found (2,255 undocumented existing `HUMAN` rows,
ambiguous extraction-ownership instructions, a 187,902-row official-store pool too large to vision-read in one
session). The category file and the prompt below are both corrected as a result. **Do not run the `claude -p`
step without deciding to actually kick off SG's first taxonomy extraction** — it's a real, costly LLM session
that writes to production once it starts.

1. The block is already claimed — reuse it, don't claim a new one (verify first, don't just trust this doc):
   ```bash
   bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=pretty \
     "SELECT block_start, block_end, status FROM \`sincere-hearth-273704.magpie_reference.sku_block_registry\` WHERE master_table = 'shopee_sg_shampoo'"
   ```
   Expected: `69001, 70000, ACTIVE`. If it shows `FAILED_QA`/`COMPLETE` instead, claim a fresh block per Shared
   mechanics § Atomic SKU block claim before proceeding.
2. Invoke `claude -p` — corrected prompt, addressing all three blockers attempt #1 found:
   ```bash
   claude -p --output-format json --permission-mode bypassPermissions --max-turns 200 "
   Full Rebuild session for shopee_sg_shampoo. Read docs/categories/sg_shampoo.md in full, including the Scale
   and 'Existing HUMAN rows' sections — both are load-bearing, not background.

   You perform extraction yourself, directly, using your own multimodal reading of product images and text.
   You do not invoke external scripts or subprocesses and do not need any API key beyond your own session
   auth — CLAUDE.md's ANTHROPIC_API_KEY note is about a different, external pipeline that does not exist here.

   You have been pre-assigned SKU block SKU-069001–SKU-070000 (already claimed in sku_block_registry, status
   ACTIVE) — use only this range, never query MAX(taxonomy_id) yourself.

   Pass 1: build taxonomy ONLY from the Official Store Allowlist merchant names listed in sg_shampoo.md — not
   all 187,902 Shopee-Mall-badged rows, just those specific merchant names.

   Pass 2: route the remaining official-store-eligible-but-unmatched and reseller products primarily via bulk
   SQL text-matching of sku_name against the Pass 1 taxonomy you just built. Only read product images for
   individual products where text matching is genuinely ambiguous — do not vision-read the full candidate pool.

   2,255 existing source='HUMAN' rows exist in product_taxonomy_map for this category. Do NOT delete them
   yourself. Leave them in place; the wrapper deletes them after your run, once QA gates confirm your new LLM
   taxonomy is good (see sg_shampoo.md's disposition policy for why the ordering matters).

   Write via bq query DML only, never the streaming API.

   If you hit a genuine blocker (something wrong with the instructions above, missing data, anything that
   would make proceeding unsafe) — stop, do not write anything, and output status='blocked' with the blockers
   array populated. That is a valid, expected outcome, not a failure.

   Output ONLY this JSON when done, nothing else:
   {status: complete|partial|failed|blocked, rows_created, rows_mapped, taxonomy_id_range_used, findings, blockers}.
   "
   ```
3. **If `status='blocked'`:** stop. Do not run QA gates or refresh. Report the `blockers` array to a human —
   this is a real question, not an error to route around. The claimed block stays `ACTIVE` (nothing was
   written) and is safe to reuse once the blocker is resolved — do not mark it `FAILED_QA`.
4. **If `status='complete'` or `'partial'` with `rows_created > 0`:** run `run_qa_gates shopee_sg_shampoo
   --skip-coexistence` (Shared mechanics § QA-gate-as-code). Coexistence is *expected* to still be true at this
   point (HUMAN rows not deleted yet) — the flag skips that specific check rather than having it fail on
   purpose, so a real dual-mapped or placeholder-leak bug isn't masked by an expected condition.
5. **STOP — manual human QA required before deleting anything.** Deleting the stale HUMAN rows is the one step
   in this scenario that isn't automatic, by design: creating new LLM taxonomy is inert if wrong (it just sits
   there, caught by the next QA pass), but deleting existing rows is much harder to reverse. Pull the new
   taxonomy and review it directly (see `docs/categories/sg_shampoo.md`'s "Reviewing this run's output" section
   for the tables and queries) before deciding to proceed. This is a deliberate exception to the "no human
   checkpoint" design for writes generally — destructive deletes get a checkpoint even when everything else
   doesn't.
6. Once a human has reviewed and approved, delete the stale HUMAN rows:
   ```sql
   DELETE FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
   WHERE master_table = 'shopee_sg_shampoo' AND source = 'HUMAN';
   ```
7. Run `run_qa_gates shopee_sg_shampoo` (no flag this time) — all 3 checks should now pass, including
   coexistence.
8. If gates pass, run universe refresh for `shopee_sg_shampoo` (Shared mechanics § Universe refresh).
9. On any real failure (non-`blocked` bad output, persistent QA gate failure after step 7), mark the block
   `FAILED_QA` — same pattern as Targeted QA Fix step 5. Don't do this for a `blocked` outcome with zero rows
   written (step 3) — that block is still good.

## Error handling

- **`status='blocked'` is not a failure.** Confirmed live 2026-07-15 (`shopee_sg_shampoo` attempt #1): a
  careful agent can find real, legitimate reasons to stop before writing anything — undocumented existing
  state, ambiguous instructions, infeasible scope for one session. Zero rows written means the claimed block
  is still valid and unused — **do not mark it `FAILED_QA`**, leave it `ACTIVE` and reuse it once the blocker
  is resolved. Report the `blockers` array to a human; this is a real question needing an answer, not an error
  to route around.
- `claude -p` exits non-zero, hits `--max-turns` without completing, or returns genuinely malformed/missing-field
  JSON (not a well-formed `status='blocked'` response) → abort **before** QA gates and refresh. Mark the
  claimed block `FAILED_QA`:
  ```sql
  UPDATE `sincere-hearth-273704.magpie_reference.sku_block_registry`
  SET status = 'FAILED_QA' WHERE block_start = @claimed_block_start AND master_table = @table;
  ```
  Never reused, never deleted — a burned block is free, a reused one is a collision. Log the raw `claude -p`
  output for follow-up.
- QA gates fail post-run → same abort-before-refresh behavior. New rows stay in `product_taxonomy` /
  `product_taxonomy_map` but never reach `universe_taxonomy_overlay` — a bad run is inert, not silently live to
  analysts.
- The refresh `MERGE` itself fails (BQ error, e.g. "must match at most one source row for each target row") →
  the `QUALIFY ROW_NUMBER()` clause in the `USING` subquery already guards against the multi-model-variant
  version of this error (the same fix `CLAUDE.md`'s farsight troubleshooting entry documents for the old
  NULLIFY+UPDATE pattern — same root cause, applies equally to `MERGE`'s `USING` subquery).
