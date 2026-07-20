# Headless Taxonomy Runbook — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce `docs/headless-runbook.md` — a runnable guide for executing Full Rebuild, Assessment Only,
and Targeted QA Fix taxonomy sessions via headless `claude -p`, with no human checkpoint on writes, backed by
deterministic wrapper infra (atomic SKU claim, QA-gate-as-code, universe refresh) that's actually been proven
against live BigQuery.

**Architecture:** A new `sku_block_registry` table gives atomic, race-free SKU block allocation (BQ
multi-statement transaction). A new set of taxonomy columns on `magpie.marketshare_universe_niq` (the real FMCG
output table — see Global Constraints) gives the refresh step somewhere correct to write. `docs/headless-runbook.md`
documents the full procedure: claim → narrowly-scoped `claude -p` judgment call → QA gates (code, not LLM) →
refresh (code, not LLM). Three scenario sections plug into this shared shape with different parameters.

**Tech Stack:** BigQuery Standard SQL (DDL, scripting/transactions, DML), bash (wrapper snippets embedded in
the runbook), `claude -p` CLI invocation patterns. No new Python, no changes to the external pipeline repo.

## Global Constraints

- **The universe-refresh target is `sincere-hearth-273704.magpie.marketshare_universe_niq`, not
  `magpie.marketshare_universe`.** Verified live 2026-07-14: `marketshare_universe` has been repurposed by a
  different (consumer electronics/appliance) business line — no `master_table`/`taxonomy_id` columns, and a
  real toothpaste product is mis-tagged there as `Electronics > Small Appliances > Grooming`.
  `marketshare_universe_niq` (10.9M rows) has the real FMCG data (confirmed: TH `category_3` values are Face
  Moisturizer, Shampoo, Body Wash, Toothpaste, etc.) but has **no taxonomy columns at all** — Task 2 adds them.
  Full detail: `docs/superpowers/specs/2026-07-14-headless-taxonomy-runbook-design.md` Addendum.
- **Farsight refresh is out of scope.** `magpie-farsight.universe.marketshare_universe` mirrors the *repurposed*
  table (same broken schema, no `_niq` equivalent exists in that project at all). Not fixed here — separate
  decision needed on whether farsight needs an `_niq` mirror.
- **Always query `MAX(taxonomy_id)` / `MAX(block_end)` live before any claim** — never trust a number in
  `CLAUDE.md` or this plan. Verified live 2026-07-14: `MAX(taxonomy_id) = SKU-068015`, already ~10,000 higher
  than `CLAUDE.md`'s documented `SKU-058455`.
- `product_taxonomy` and `product_taxonomy_map` schemas are confirmed accurate against docs (verified during the
  size-regex-pass plan this session) — no surprises expected there. `product_taxonomy_map.confidence` is
  `STRING` not `FLOAT64` as `CLAUDE.md` implies, but no query in this plan does numeric comparison on it.
- Markdown-only deliverable for the runbook itself (matches `docs/claude-code-headless-orchestration.md`'s
  existing pattern) — the two schema changes (Tasks 1–2) are the only non-doc artifacts, and both are additive
  (`CREATE TABLE IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS`), never destructive.
- No human checkpoint on writes is the explicit, already-approved design decision — SKU collisions and QA
  failures must be caught by the deterministic wrapper (claim transaction, QA-gate SQL), not a person watching.
- Credentials/environment: `bq`/`gcloud` on PATH, authenticated against `sincere-hearth-273704` with at least
  BigQuery Data Editor on `magpie_reference` and `magpie` datasets.

---

### Task 1: SKU block registry migration

**Files:**
- Create: `sql/migrations/002_add_sku_block_registry.sql`

**Interfaces:**
- Consumes: nothing
- Produces: table `sincere-hearth-273704.magpie_reference.sku_block_registry` (columns: `block_start INT64,
  block_end INT64, master_table STRING, scenario STRING, claimed_at TIMESTAMP, status STRING`) — Task 3's
  atomic-claim snippet and Task 6's worked example both write to this table by this exact name.

- [ ] **Step 1: Write the migration**

```sql
-- sql/migrations/002_add_sku_block_registry.sql
CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.sku_block_registry` (
  block_start  INT64     NOT NULL,
  block_end    INT64     NOT NULL,
  master_table STRING    NOT NULL,
  scenario     STRING    NOT NULL,  -- 'full_rebuild' | 'assessment' | 'targeted_qa_fix'
  claimed_at   TIMESTAMP NOT NULL,
  status       STRING    NOT NULL   -- 'ACTIVE' | 'FAILED_QA' | 'ABANDONED' | 'COMPLETE'
)
OPTIONS (
  description = "Atomic SKU block allocation for headless taxonomy sessions. See docs/headless-runbook.md."
);
```

- [ ] **Step 2: Run the migration**

Run: `bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 < sql/migrations/002_add_sku_block_registry.sql`

Expected: no output (DDL success) or a message confirming table creation.

- [ ] **Step 3: Verify the table exists with the right schema**

Run:
```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=pretty \
  "SELECT column_name, data_type FROM \`sincere-hearth-273704.magpie_reference.INFORMATION_SCHEMA.COLUMNS\` WHERE table_name = 'sku_block_registry' ORDER BY ordinal_position"
```
Expected: 6 rows matching Step 1's column list exactly.

- [ ] **Step 4: Test the atomic claim pattern — run twice sequentially, confirm non-overlapping blocks**

First, get the real current ceiling (never trust a hardcoded number):

```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=pretty \
  "SELECT MAX(taxonomy_id) AS current_max FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy\`"
```

Then run the claim transaction twice (simulating two sessions), using the seed only on the very first-ever
claim:

```sql
-- claim_test_1.sql
BEGIN
  DECLARE next_start INT64;
  BEGIN TRANSACTION;
  SET next_start = (SELECT COALESCE(MAX(block_end), 69000) + 1 FROM `sincere-hearth-273704.magpie_reference.sku_block_registry`);
  INSERT INTO `sincere-hearth-273704.magpie_reference.sku_block_registry`
    (block_start, block_end, master_table, scenario, claimed_at, status)
  VALUES (next_start, next_start + 999, 'shopee_th_test_claim_1', 'assessment', CURRENT_TIMESTAMP(), 'ACTIVE');
  COMMIT TRANSACTION;
END;
```

Run it: `bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 < claim_test_1.sql`

Then run the same script again with `master_table = 'shopee_th_test_claim_2'` (copy the file, change that one
literal). Run:
```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=pretty \
  "SELECT block_start, block_end, master_table FROM \`sincere-hearth-273704.magpie_reference.sku_block_registry\` WHERE master_table LIKE 'shopee_th_test_claim%' ORDER BY block_start"
```
Expected: two rows, `test_claim_1` at `[69001, 70000]` and `test_claim_2` at `[70001, 71000]` (or wherever the
real current ceiling puts them) — **non-overlapping**, second block starting exactly where the first ends + 1.
If the ranges overlap, the transaction isolation isn't working — stop and investigate before Task 3 depends on
this pattern.

- [ ] **Step 5: Clean up the test rows**

```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 \
  "DELETE FROM \`sincere-hearth-273704.magpie_reference.sku_block_registry\` WHERE master_table LIKE 'shopee_th_test_claim%'"
```

- [ ] **Step 6: Commit**

```bash
git add sql/migrations/002_add_sku_block_registry.sql
git commit -m "Add sku_block_registry migration for atomic headless SKU claims"
```

---

### Task 2: Create the universe taxonomy overlay table

**Files:**
- Create: `sql/migrations/003_add_universe_taxonomy_overlay.sql`

**Interfaces:**
- Consumes: nothing
- Produces: table `sincere-hearth-273704.magpie_reference.universe_taxonomy_overlay` (columns: `product_id
  STRING, platform STRING, country STRING, master_table STRING, taxonomy_id STRING, sku_type_complete STRING,
  taxonomy_source STRING, taxonomy_confidence STRING, taxonomy_meta_agent STRING, updated_at TIMESTAMP`) —
  Task 4's refresh `MERGE` writes to this exact table and these exact column names. (`taxonomy_confidence` is
  `STRING` to match `product_taxonomy_map.confidence`'s actual live type, not the `FLOAT64` `CLAUDE.md` implies.)

No `ALTER TABLE` on the shared 10.9M-row `marketshare_universe_niq` — this is a brand-new, empty table, same
overlay pattern `product_taxonomy_map` already uses on source data. Zero risk to the production table's schema
or any existing consumer of it.

- [ ] **Step 1: Write the migration**

```sql
-- sql/migrations/003_add_universe_taxonomy_overlay.sql
CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.universe_taxonomy_overlay` (
  product_id           STRING    NOT NULL,
  platform             STRING    NOT NULL,
  country              STRING    NOT NULL,
  master_table         STRING    NOT NULL,
  taxonomy_id          STRING,
  sku_type_complete    STRING,
  taxonomy_source      STRING,
  taxonomy_confidence  STRING,
  taxonomy_meta_agent  STRING,
  updated_at           TIMESTAMP NOT NULL
)
CLUSTER BY platform, country, product_id
OPTIONS (
  description = "Taxonomy overlay for magpie.marketshare_universe_niq, keyed by (product_id, platform, country, master_table). See docs/headless-runbook.md § Universe refresh."
);
```

- [ ] **Step 2: Run the migration**

Run: `bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 < sql/migrations/003_add_universe_taxonomy_overlay.sql`

- [ ] **Step 3: Verify the table exists with the right schema**

```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=pretty \
  "SELECT column_name, data_type FROM \`sincere-hearth-273704.magpie_reference.INFORMATION_SCHEMA.COLUMNS\` WHERE table_name = 'universe_taxonomy_overlay' ORDER BY ordinal_position"
```

Expected: 10 rows matching Step 1's column list exactly.

- [ ] **Step 4: Commit**

```bash
git add sql/migrations/003_add_universe_taxonomy_overlay.sql
git commit -m "Add universe_taxonomy_overlay table (overlay pattern, no ALTER TABLE on marketshare_universe_niq)"
```

---

### Task 3: Write shared mechanics section of `docs/headless-runbook.md`

**Files:**
- Create: `docs/headless-runbook.md`

**Interfaces:**
- Consumes: `sku_block_registry` schema from Task 1
- Produces: the file itself, which Tasks 4–7 append sections to. Establishes the doc's top-level structure —
  later tasks must not duplicate section headers.

- [ ] **Step 1: Write the file with its header and shared-mechanics sections**

```markdown
# Headless Taxonomy Runbook

Runnable procedure for Full Rebuild, Assessment Only, and Targeted QA Fix taxonomy sessions via headless
`claude -p`, with no human checkpoint on writes. Companion to
[`docs/claude-code-headless-orchestration.md`](claude-code-headless-orchestration.md) (general headless
mechanics) and [`docs/superpowers/specs/2026-07-14-headless-taxonomy-runbook-design.md`](superpowers/specs/2026-07-14-headless-taxonomy-runbook-design.md)
(the design this implements — read its Addendum before touching universe refresh, the target table isn't what
`CLAUDE.md` says).

## Prerequisites

- `bq`/`gcloud` on PATH, authenticated against `sincere-hearth-273704` with BigQuery Data Editor on
  `magpie_reference` and `magpie`.
- `claude` CLI installed and authenticated (headless runs bill against a separate API-rate credit pool as of
  2026-06-15 — see `docs/claude-code-headless-orchestration.md`).
- `sql/migrations/002_add_sku_block_registry.sql` and
  `sql/migrations/003_add_universe_taxonomy_overlay.sql` have been run once
  (`docs/superpowers/plans/2026-07-14-headless-taxonomy-runbook.md` Tasks 1–2).

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
`docs/superpowers/specs/2026-07-14-headless-taxonomy-runbook-design.md` Addendum for why it's this one, not
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
matching the correction already proven in `docs/superpowers/plans/2026-07-14-size-regex-pass.md`'s backfill query
this same session.)
```

- [ ] **Step 2: Verify the file was written with valid markdown structure**

Run: `grep -n "^## \|^### " docs/headless-runbook.md`

Expected: headings in order — `## Prerequisites`, `## Shared mechanics`, `### Atomic SKU block claim`, `### DML-not-streaming rule`, `### QA-gate-as-code`, `### claude -p invocation contract`, `### Universe refresh`.

- [ ] **Step 3: Validate the QA-gate SQL against real data (not just syntax)**

Run each of the 3 embedded queries in `run_qa_gates()` against a real, already-complete category, e.g.
`shopee_th_body_wash`:

```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=pretty \
  "SELECT COUNT(*) FROM (
     SELECT product_id FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy_map\`
     WHERE master_table = 'shopee_th_body_wash' GROUP BY product_id HAVING COUNT(*) > 1
   )"
```

Expected: `0` (body_wash is a shipped, QA'd category per `docs/categories/STATUS.md`). If non-zero, the gate
logic itself is fine (it caught something real) — but note it in the runbook rather than assuming a bug.

- [ ] **Step 4: Commit**

```bash
git add docs/headless-runbook.md
git commit -m "Add docs/headless-runbook.md: prerequisites + shared mechanics, universe refresh retargeted to marketshare_universe_niq"
```

---

### Task 4: Populate the overlay table for real, for one already-complete TH category

**Files:**
- Modify: `docs/headless-runbook.md` (append a "Verified against live data" note to the Universe refresh
  subsection)

**Interfaces:**
- Consumes: Task 2's `universe_taxonomy_overlay` table, Task 3's refresh `MERGE`
- Produces: nothing new for later tasks — this is the mechanism's real-world proof, not a new interface

This is genuinely useful production work, not just testing: the overlay table starts empty, so even a
fully-shipped, QA'd category like `shopee_th_body_wash` has no taxonomy rows in it yet — this task is the first
real population. `marketshare_universe_niq` itself is never touched (that's the point of the overlay design).

- [ ] **Step 1: Run the QA gates for `shopee_th_body_wash` (must pass before refresh)**

```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=csv \
  "SELECT COUNT(*) FROM (
     SELECT product_id FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy_map\`
     WHERE master_table = 'shopee_th_body_wash' GROUP BY product_id HAVING COUNT(*) > 1
   )"
```
Expected: `0`. Repeat for the HUMAN+LLM co-existence and placeholder-leak checks from Task 3 Step 1 (same
pattern, `master_table = 'shopee_th_body_wash'`). All three must return `0` before proceeding.

- [ ] **Step 2: Dry-run the refresh MERGE**

```bash
bq query --dry_run --use_legacy_sql=false --project_id=sincere-hearth-273704 \
  "MERGE \`sincere-hearth-273704.magpie_reference.universe_taxonomy_overlay\` t
   USING (
     SELECT m.product_id, m.platform, m.country, m.master_table,
            pt.taxonomy_id, pt.canonical_name, m.source, m.confidence, m.meta_agent
     FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy_map\` m
     JOIN \`sincere-hearth-273704.magpie_reference.product_taxonomy\` pt ON m.taxonomy_id = pt.taxonomy_id
     WHERE m.master_table = 'shopee_th_body_wash'
     QUALIFY ROW_NUMBER() OVER (PARTITION BY m.product_id, m.platform, m.country ORDER BY CASE m.source WHEN 'LLM' THEN 0 ELSE 1 END, m.taxonomy_id) = 1
   ) src
   ON t.product_id = src.product_id AND t.platform = src.platform AND t.country = src.country
     AND t.master_table = 'shopee_th_body_wash'
   WHEN MATCHED THEN UPDATE SET
     taxonomy_id = src.taxonomy_id, sku_type_complete = src.canonical_name,
     taxonomy_source = src.source, taxonomy_confidence = src.confidence,
     taxonomy_meta_agent = src.meta_agent, updated_at = CURRENT_TIMESTAMP()
   WHEN NOT MATCHED BY SOURCE AND t.master_table = 'shopee_th_body_wash' THEN DELETE
   WHEN NOT MATCHED BY TARGET THEN INSERT
     (product_id, platform, country, master_table, taxonomy_id, sku_type_complete,
      taxonomy_source, taxonomy_confidence, taxonomy_meta_agent, updated_at)
     VALUES (src.product_id, src.platform, src.country, src.master_table, src.taxonomy_id, src.canonical_name,
             src.source, src.confidence, src.meta_agent, CURRENT_TIMESTAMP())"
```

Expected: a byte estimate. Should be small — this reads only `product_taxonomy`/`product_taxonomy_map` (both
small reference tables) and writes to the new, currently-empty overlay table; no scan of the 10.9M-row
`marketshare_universe_niq` at all.

- [ ] **Step 3: Run the refresh MERGE for real**

Same query as Step 2, without `--dry_run`. Expected: a row-count summary (BigQuery reports inserted/updated/
deleted counts for `MERGE`) — expect all inserts (0 updates, 0 deletes) since the overlay table starts empty.

- [ ] **Step 4: Verify the result**

```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=pretty \
  "SELECT sku_type_complete, taxonomy_source, taxonomy_confidence, COUNT(*) AS n
   FROM \`sincere-hearth-273704.magpie_reference.universe_taxonomy_overlay\`
   WHERE master_table = 'shopee_th_body_wash'
   GROUP BY 1, 2, 3 ORDER BY n DESC LIMIT 10"
```

Expected: real canonical names (not NULL, not empty), `taxonomy_source` mostly `LLM`, a mix of confidence
values. If `sku_type_complete` is NULL or empty across the board, something's wrong with the join — stop and
investigate before writing this up as working.

Also confirm the join back to `marketshare_universe_niq` actually resolves (proves the overlay is usable, not
just populated):

```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=pretty \
  "SELECT COUNT(*) AS matched
   FROM \`sincere-hearth-273704.magpie_reference.universe_taxonomy_overlay\` o
   JOIN \`sincere-hearth-273704.magpie.marketshare_universe_niq\` u
     ON u.product_id = o.product_id AND u.ecommerce_platform = o.platform AND u.country = o.country
   WHERE o.master_table = 'shopee_th_body_wash'
     AND u.month = (SELECT MAX(month) FROM \`sincere-hearth-273704.magpie.marketshare_universe_niq\`)"
```

Expected: a non-zero count.

- [ ] **Step 5: Append the result to the runbook as evidence**

Add one paragraph under the "Universe refresh" subsection in `docs/headless-runbook.md`: date run, category
used, row counts (inserted/updated/deleted), and the join-back confirmation count from Step 4.

- [ ] **Step 6: Commit**

```bash
git add docs/headless-runbook.md
git commit -m "Run universe refresh MERGE for shopee_th_body_wash: first real proof the overlay-table mechanism works"
```

---

### Task 5: Assessment Only and Targeted QA Fix scenario sections

**Files:**
- Modify: `docs/headless-runbook.md` (append two new `## Scenario:` sections)

**Interfaces:**
- Consumes: Task 3's shared mechanics (referenced, not repeated)
- Produces: nothing new for later tasks

- [ ] **Step 1: Append the Assessment Only section**

```markdown

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
```

- [ ] **Step 2: Verify no duplicate section headers**

Run: `grep -c "^## Scenario:" docs/headless-runbook.md`

Expected: `2` at this point (Assessment Only, Targeted QA Fix) — Task 6 adds the third.

- [ ] **Step 3: Commit**

```bash
git add docs/headless-runbook.md
git commit -m "Add Assessment Only and Targeted QA Fix scenario sections to headless-runbook.md"
```

---

### Task 6: Full Rebuild scenario + worked example

**Files:**
- Create: `docs/categories/sg_shampoo.md`
- Modify: `docs/headless-runbook.md` (append `## Scenario: Full Rebuild` with the worked example)

**Interfaces:**
- Consumes: Task 1's registry, Task 3's shared mechanics
- Produces: nothing new for later tasks

`sg_shampoo` has zero rows in `product_taxonomy_map` today (0/23 SG categories are LLM-extracted per
`docs/categories/STATUS.md`) — its Full Rebuild prompt is documented as a realistic, copy-pasteable example,
**not executed live** (a real run would be the first-ever SG taxonomy write, a genuine production event that
needs its own explicit go-ahead, not something to trigger as a plan-writing side effect). The wrapper mechanics
it depends on (claim, QA gates, refresh) are already proven for real in Tasks 1 and 4 against different,
already-populated data.

- [ ] **Step 1: Research real `sg_shampoo` brand/store data for the category context file**

```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=pretty --max_rows=20 \
  "SELECT brand, SUM(gmv_monthly) AS gmv, COUNT(DISTINCT product_id) AS n_products
   FROM \`sincere-hearth-273704.magpie.marketshare_universe_niq\`
   WHERE country = 'SG' AND category_3 = 'Shampoo'
     AND month = (SELECT MAX(month) FROM \`sincere-hearth-273704.magpie.marketshare_universe_niq\`)
   GROUP BY brand ORDER BY gmv DESC LIMIT 20"
```

Record the top-15-by-GMV brands (95% GMV threshold per `docs/llm-extraction-rules.md` §4) — this becomes the
category file's Brand Scope section.

```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=pretty --max_rows=30 \
  "SELECT merchant_name, brand, COUNT(*) AS n
   FROM \`sincere-hearth-273704.magpie.marketshare_universe_niq\`
   WHERE country = 'SG' AND category_3 = 'Shampoo' AND merchant_badge = 'Shopee Mall'
     AND month = (SELECT MAX(month) FROM \`sincere-hearth-273704.magpie.marketshare_universe_niq\`)
   GROUP BY merchant_name, brand ORDER BY n DESC LIMIT 30"
```

This is the category file's Official Store Allowlist section — exact merchant names, not a `LIKE '%official%'`
wildcard, per `docs/llm-extraction-rules.md` §4.

- [ ] **Step 2: Write `docs/categories/sg_shampoo.md`**

Copy `docs/categories/_TEMPLATE.md`'s structure. Fill in: Status (Pass 1/2 both ❌ Not started, 0% GMV
coverage, current MAX taxonomy_id from Task 1's live check), SKU Blocks Assigned (leave as "not yet claimed —
claim atomically per Shared mechanics § Atomic SKU block claim at run time, do not pre-assign statically"),
Brand Scope and Official Store Allowlist from Step 1's real query results, Scope (in scope: shampoo,
2-in-1 shampoo+conditioner; out of scope: standalone conditioner, dry shampoo unless category data shows it's
material — check Step 1's brand list for signal), Taxonomy Design Notes (empty — no extraction has run yet).

- [ ] **Step 3: Append the Full Rebuild scenario section to `docs/headless-runbook.md`**

```markdown

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
     DECLARE next_start INT64;
     BEGIN TRANSACTION;
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
```

- [ ] **Step 4: Verify the claim step is real and safe to run**

Run the Step 3 claim SQL for real (it only touches the new registry table, same safety profile as Task 1 Step
4's test claims):

```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=pretty \
  "SELECT block_start, block_end, master_table, status FROM \`sincere-hearth-273704.magpie_reference.sku_block_registry\` WHERE master_table = 'shopee_sg_shampoo'"
```

Expected: one row, `status = 'ACTIVE'`. This proves the claim step in the worked example is real and correct —
the `claude -p` step itself stays a documented-but-not-executed command per Step 3's note.

- [ ] **Step 5: Commit**

```bash
git add docs/categories/sg_shampoo.md docs/headless-runbook.md
git commit -m "Add Full Rebuild scenario + sg_shampoo worked example to headless-runbook.md"
```

---

### Task 7: Error handling section and final consistency pass

**Files:**
- Modify: `docs/headless-runbook.md` (append `## Error handling`, do a final read-through)

**Interfaces:**
- Consumes: all prior sections (this is the closing task)
- Produces: the finished `docs/headless-runbook.md`

- [ ] **Step 1: Append the error handling section**

```markdown

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
```

- [ ] **Step 2: Read the full file top to bottom, check for consistency**

Run: `grep -n "^## \|^### " docs/headless-runbook.md`

Expected order: `## Prerequisites`, `## Shared mechanics` (with 4 `###` subsections), `## Scenario: Assessment
Only`, `## Scenario: Targeted QA Fix`, `## Scenario: Full Rebuild`, `## Error handling`. No duplicate headers,
no orphaned references (every `@table`/`@scenario`/`@block_size` placeholder is explained in Shared mechanics
before first scenario use).

- [ ] **Step 3: Commit**

```bash
git add docs/headless-runbook.md
git commit -m "Add error handling section to headless-runbook.md; complete the headless taxonomy runbook"
```
