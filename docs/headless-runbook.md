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
  BEGIN TRANSACTION;
  DECLARE next_start INT64;
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
run_qa_gates() {
  local table="$1"
  local dual_mapped
  dual_mapped=$(bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=csv \
    "SELECT COUNT(*) FROM (
       SELECT product_id FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy_map\`
       WHERE master_table = '${table}' GROUP BY product_id HAVING COUNT(*) > 1
     )" | tail -1)
  if [ "$dual_mapped" != "0" ]; then
    echo "QA GATE FAILED: ${dual_mapped} dual-mapped products for ${table}"; return 1
  fi

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
    "status": "complete | partial | failed",
    "rows_created": 0,
    "rows_mapped": 0,
    "taxonomy_id_range_used": "SKU-XXXXXX-SKU-YYYYYY",
    "findings": []
  }
  ```

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

Full SKU block (~1,000 slots), rebuilds a category's taxonomy from scratch — deletes old map rows, re-extracts
via Pass 1 (official stores) + Pass 2 (reseller routing), then QA gates + universe refresh across the whole
category.

**Worked example: `shopee_sg_shampoo`** (flagged as next SG priority in `docs/categories/STATUS.md`). This
category has never been extracted — 0 rows in `product_taxonomy_map` today. The commands below are real and
copy-pasteable; **do not run the `claude -p` step without deciding to actually kick off SG's first-ever
taxonomy extraction** — everything up through the claim is safe to run standalone (it only touches the new,
empty registry table).

1. Claim the block:
   ```sql
   BEGIN
     BEGIN TRANSACTION;
     DECLARE next_start INT64;
     SET next_start = (SELECT COALESCE(MAX(block_end), 69000) + 1 FROM `sincere-hearth-273704.magpie_reference.sku_block_registry`);
     INSERT INTO `sincere-hearth-273704.magpie_reference.sku_block_registry`
       (block_start, block_end, master_table, scenario, claimed_at, status)
     VALUES (next_start, next_start + 999, 'shopee_sg_shampoo', 'full_rebuild', CURRENT_TIMESTAMP(), 'ACTIVE');
     COMMIT TRANSACTION;
   END;
   ```
2. Invoke `claude -p` (illustrative — not run as part of this runbook's authoring):
   ```bash
   claude -p --output-format json --permission-mode bypassPermissions --max-turns 200 "
   Full Rebuild session for shopee_sg_shampoo. Read docs/categories/sg_shampoo.md for official-store allowlist
   and scope rules. You have been pre-assigned SKU block SKU-<block_start>–SKU-<block_end> — use only this
   range, never query MAX(taxonomy_id) yourself. Pass 1: build taxonomy from official-store listings. Pass 2:
   route reseller products via text-first matching (per docs/llm-extraction-rules.md §1/§2 priority chains).
   Write via bq query DML only, never the streaming API. Output ONLY this JSON when done:
   {status, rows_created, rows_mapped, taxonomy_id_range_used, findings}.
   "
   ```
3. Run QA gates for `shopee_sg_shampoo` (Shared mechanics § QA-gate-as-code).
4. If gates pass, run universe refresh for `shopee_sg_shampoo` (Shared mechanics § Universe refresh).
5. On any failure (bad `claude -p` output, QA gate failure), mark the block `FAILED_QA` — same pattern as
   Targeted QA Fix step 5.

**Claim step status:** documented above but **not yet run** — see
`docs/plans/headless-taxonomy-runbook-implementation-plan.md` Task 6 for the pending confirmation needed before
inserting a real row into `sku_block_registry`, even though that insert only touches the new, empty table.

## Error handling

- `claude -p` exits non-zero, hits `--max-turns` without completing, or returns malformed/missing-field JSON →
  abort **before** QA gates and refresh. Mark the claimed block `FAILED_QA`:
  ```sql
  UPDATE `sincere-hearth-273704.magpie_reference.sku_block_registry`
  SET status = 'FAILED_QA' WHERE block_start = @claimed_block_start AND master_table = @table;
  ```
  Never reused, never deleted — a burned block is free, a reused one is a collision. Log the raw `claude -p`
  output for follow-up.
- QA gates fail post-run → same abort-before-refresh behavior. New rows stay in `product_taxonomy` /
  `product_taxonomy_map` but never reach `marketshare_universe_niq` — a bad run is inert, not silently live to
  analysts.
- Refresh UPDATE itself fails (BQ error, e.g. "must match at most one source row") → the `QUALIFY ROW_NUMBER()`
  clause in the Universe refresh SQL already guards against the multi-model-variant version of this error (see
  `CLAUDE.md`'s farsight troubleshooting entry for the original failure mode this pattern fixes).
