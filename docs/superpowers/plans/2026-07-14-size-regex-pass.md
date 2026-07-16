# Deterministic Size Regex Pass — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a BigQuery-native regex pass that fills `product_taxonomy.size` for rows where it's currently
NULL, using only `sku_name` text — no LLM call, no external pipeline repo dependency.

**Architecture:** One persistent SQL UDF (`parse_size`) is the single source of truth for the regex/keyword
logic. One UPDATE query joins `product_taxonomy` → `product_taxonomy_map` → `marketshare_universe` (which
already has `sku_name` denormalized across whatever this table currently covers) and calls the UDF, guarded by
`size IS NULL AND is_multi_size IS NOT TRUE AND is_bundle IS NOT TRUE` so it never overwrites a real or
intentionally-blank value. The same query runs once now (backfill) and later on a BigQuery-native scheduled
query (recurring) — not two separate implementations.

**Tech Stack:** BigQuery Standard SQL (persistent UDF, scripting, scheduled queries via `bq mk
--transfer_config`). No Python, no new schema columns, no external repo changes.

## Global Constraints

- Locale scope is TH confirmed; ID scope is **gated on Task 1's findings**, not assumed (see
  `docs/plans/size-regex-pass-design.md` Addendum — the source bug report explicitly could not determine
  whether Indonesian-language rows are genuine `country='ID'` data or mislabeled TH/SG listings).
- Field scope is **size only** — pack_count is out of scope (image-tiebreaker + false-positive-pattern
  complexity documented in `docs/llm-extraction-rules.md` §1 makes it a separate, harder problem).
- Every query that touches `magpie.marketshare_universe` **must be dry-run first** (`bq query --dry_run`) before
  running for real — the table is 718M rows / 700GB live per `docs/sku-taxonomy-quality-scan-2026-04.md`, not
  the ~9.96M `ARCHITECTURE.md` describes. Treat every estimate as unverified until dry-run confirms it.
- The overwrite guard is `WHERE size IS NULL AND is_multi_size IS NOT TRUE AND is_bundle IS NOT TRUE` on every
  fill query — never just `size IS NULL` (this was a bug in the original design, fixed before this plan).
- No new columns on `product_taxonomy` or `product_taxonomy_map`. No changes to the external Python pipeline
  repo. No MY/PH/VN keyword support (no reported bug there yet).
- Credentials/environment: use whatever `bq` binary and BQ project (`sincere-hearth-273704`) access the
  executing environment has configured — see `CLAUDE.md` / `docs/runbook.md` for the documented Mac paths if
  running there; on any other machine, use `bq` on PATH after `gcloud components install bq` and a service
  account with at least BigQuery Data Viewer on `magpie_reference`/`magpie` and Data Editor on
  `magpie_reference.product_taxonomy` for Task 3 onward.

---

### Task 1: Discovery — confirm ID scope and get real NULL-size counts

**Files:**
- Create: `sql/queries/00_discovery_id_scope_check.sql`
- Create: `docs/plans/size-regex-pass-findings.md`

**Interfaces:**
- Consumes: nothing (first task, read-only)
- Produces: `docs/plans/size-regex-pass-findings.md` with a filled-in `ID_SCOPE_CONFIRMED: yes|no` line that
  Task 3 reads before writing its country filter.

- [x] **Step 1: Write the discovery SQL file**

```sql
-- sql/queries/00_discovery_id_scope_check.sql
-- Read-only. Run each SELECT below in order; dry-run first.

-- 1a. Cheap: latest month partition present in marketshare_universe.
SELECT MAX(month) AS latest_month
FROM `sincere-hearth-273704.magpie.marketshare_universe`;

-- 1b. Country breakdown for that one month partition only (narrow columns, partition-filtered).
--     Replace @latest_month with the literal DATE from 1a before running (BigQuery scripting DECLARE
--     shown in 1b-script below is the version to actually execute).
DECLARE latest_month DATE;
SET latest_month = (SELECT MAX(month) FROM `sincere-hearth-273704.magpie.marketshare_universe`);

SELECT
  country,
  COUNT(*) AS row_count,
  COUNTIF(sku_name IS NOT NULL) AS sku_name_populated
FROM `sincere-hearth-273704.magpie.marketshare_universe`
WHERE month = latest_month
GROUP BY country
ORDER BY row_count DESC;

-- 1c. If 'ID' appeared in 1b: sample 20 sku_names to eyeball language plausibility.
SELECT product_id, master_table, sku_name
FROM `sincere-hearth-273704.magpie.marketshare_universe`
WHERE month = latest_month AND country = 'ID'
LIMIT 20;

-- 1d. Eligible NULL-size taxonomy rows by country (cheap — reference tables only, no universe join).
SELECT
  m.country,
  COUNT(DISTINCT pt.taxonomy_id) AS eligible_null_size_taxonomy_ids
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy` pt
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
  ON m.taxonomy_id = pt.taxonomy_id
WHERE pt.size IS NULL
  AND pt.is_multi_size IS NOT TRUE
  AND pt.is_bundle IS NOT TRUE
  AND m.country IN ('TH', 'ID')
GROUP BY m.country;

-- 1e. Of those, how many resolve to a real sku_name via marketshare_universe (confirms Task 3's join
--     actually works before committing to it). Partition-filtered to latest_month.
SELECT
  m.country,
  COUNT(DISTINCT pt.taxonomy_id) AS eligible,
  COUNT(DISTINCT IF(u.sku_name IS NOT NULL, pt.taxonomy_id, NULL)) AS resolvable_via_universe
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy` pt
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
  ON m.taxonomy_id = pt.taxonomy_id
LEFT JOIN `sincere-hearth-273704.magpie.marketshare_universe` u
  ON u.product_id = m.product_id
  AND u.master_table = m.master_table
  AND u.month = latest_month
WHERE pt.size IS NULL
  AND pt.is_multi_size IS NOT TRUE
  AND pt.is_bundle IS NOT TRUE
  AND m.country IN ('TH', 'ID')
GROUP BY m.country;
```

- [x] **Step 2: Dry-run every query before running for real**

Run: `bq query --dry_run --nouse_legacy_sql --project_id=sincere-hearth-273704 < sql/queries/00_discovery_id_scope_check.sql`
(or paste each numbered block individually — `--dry_run` only works on one statement at a time for scripts with
`DECLARE`/`SET`, so run 1a standalone first, then 1b-1e as one scripted block with `--dry_run`).

Expected: a "Query successfully validated. This query will process X bytes" message for each. If any single
block reports more than ~5GB estimated, add `TABLESAMPLE SYSTEM (10 PERCENT)` right after the
`marketshare_universe` table reference in that block and re-dry-run — note in the findings file that the count
is now an estimate, not exact.

- [x] **Step 3: Run for real and record results**

Run: `bq query --nouse_legacy_sql --project_id=sincere-hearth-273704 --format=pretty < sql/queries/00_discovery_id_scope_check.sql`

- [x] **Step 4: Write the findings file**

```markdown
<!-- docs/plans/size-regex-pass-findings.md -->
# Size Regex Pass — Discovery Findings

Run date: <fill in actual date>
Latest month partition found (1a): <fill in>
Bytes processed (largest single block, from dry-run): <fill in>

## Country breakdown (1b)
<paste table: country, row_count, sku_name_populated>

## ID sample plausibility (1c) — only if 'ID' appeared in 1b
<paste 5-10 sample sku_names, note whether they read as genuine Indonesian marketplace listings
 vs. Thai/SG listings with untranslated manufacturer text>

## Eligible NULL-size counts (1d)
<paste: country, eligible_null_size_taxonomy_ids>

## Join resolvability (1e)
<paste: country, eligible, resolvable_via_universe>

## Decision

ID_SCOPE_CONFIRMED: <yes|no>

<one sentence: why. E.g. "yes — 'ID' rows present in 1b with plausible Indonesian sku_names in 1c and
resolvable_via_universe > 0 in 1e" or "no — zero 'ID' rows found in 1b at the latest month partition;
proceeding TH-only, ID keyword support in the UDF stays unused until this is re-checked.">
```

- [x] **Step 5: Commit**

```bash
git add sql/queries/00_discovery_id_scope_check.sql docs/plans/size-regex-pass-findings.md
git commit -m "Add discovery query + findings for size-regex-pass ID scope gate"
```


**Actually run, 2026-07-14:** live schema didn't match the plan's assumptions in two ways — see
`docs/plans/size-regex-pass-findings.md` for full detail. Summary: `marketshare_universe` has no
`master_table` column at all (corrected join to `product_id + ecommerce_platform=platform + country`, the
real ADR-006 composite key); all 6 Intrepid countries are already live in that table (ID = 5.17M rows, genuine
Indonesian data), but `product_taxonomy_map` has **zero** `country='ID'` rows — so ID_SCOPE_CONFIRMED: no, not
because ID data doesn't exist, but because this plan's mechanism has nothing to join to for it. TH: 2,454
eligible, 1,549 resolvable. Proceeding TH-only per user decision.

---

### Task 2: Build and test the `parse_size` UDF

**Files:**
- Create: `sql/functions/parse_size.sql`

**Interfaces:**
- Consumes: nothing (pure function over a `STRING` input, no table dependency)
- Produces: `` `sincere-hearth-273704.magpie_reference.parse_size`(sku_name STRING) RETURNS STRUCT<size_value FLOAT64, size_unit STRING, size_text STRING> ``
  — Task 3 calls this exact function by this exact name and signature.

Not gated by Task 1 — this is a pure text function, safe to build with both TH and ID keyword support
regardless of the discovery outcome (unused ID patterns simply never match if Task 1 finds no ID data).

- [x] **Step 1: Write the UDF with its embedded test block as one file**

```sql
-- sql/functions/parse_size.sql
--
-- Deterministic size extractor. TH + ID unit keywords. Comma-as-decimal normalized only when it
-- precedes a unit keyword within 1-2 digits (distinguishes "2,5kg" from "1,000" thousands grouping).
-- Never guesses — returns NULL fields when no confident number+unit pair is found.

CREATE OR REPLACE FUNCTION `sincere-hearth-273704.magpie_reference.parse_size`(sku_name STRING)
RETURNS STRUCT<size_value FLOAT64, size_unit STRING, size_text STRING>
AS ((
  WITH normalized AS (
    SELECT REGEXP_REPLACE(
      sku_name,
      r'(\d+),(\d{1,2})(?=\s*(?:kg|g|ml|l|กรัม|ก\.|มล\.?|ลิตร))',
      r'\1.\2'
    ) AS s
  ),
  extracted AS (
    SELECT
      REGEXP_EXTRACT(LOWER(s), r'(\d+(?:\.\d+)?)\s*(kg|g|ml|l|กรัม|ก\.|มล\.?|ลิตร)') AS raw_num,
      REGEXP_EXTRACT(LOWER(s), r'\d+(?:\.\d+)?\s*(kg|g|ml|l|กรัม|ก\.|มล\.?|ลิตร)') AS raw_unit
    FROM normalized
  )
  SELECT AS STRUCT
    SAFE_CAST(raw_num AS FLOAT64) AS size_value,
    raw_unit AS size_unit,
    CASE WHEN raw_num IS NOT NULL THEN CONCAT(raw_num, raw_unit) ELSE NULL END AS size_text
  FROM extracted
));

-- ── Runnable check — run this block after creating the function above, before Task 3 depends on it ──
WITH cases AS (
  SELECT * FROM UNNEST([
    STRUCT('KAPASITAS 2,5kg Mesin Cuci Mini' AS sku_name, '2.5kg' AS expected),
    STRUCT('Sabun Mandi Cair 250ml' AS sku_name, '250ml' AS expected),
    STRUCT('โฟมล้างหน้า 100 มล.' AS sku_name, '100ml' AS expected),
    STRUCT('สบู่ก้อน 105ก.' AS sku_name, '105g' AS expected),
    STRUCT('Harga Promo Rp 1,000,000' AS sku_name, CAST(NULL AS STRING) AS expected)
  ])
)
SELECT
  sku_name,
  expected,
  `sincere-hearth-273704.magpie_reference.parse_size`(sku_name).size_text AS actual,
  expected IS NOT DISTINCT FROM `sincere-hearth-273704.magpie_reference.parse_size`(sku_name).size_text AS pass
FROM cases;
```

- [x] **Step 2: Create the function**

Run: `bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 < sql/functions/parse_size.sql`

This executes both the `CREATE OR REPLACE FUNCTION` and the test block in one script run (BigQuery runs
multi-statement `.sql` files top to bottom in one job).

Expected: the test block's output table shows `pass = true` on all 5 rows, including the last row (`Harga
Promo Rp 1,000,000` → `expected = NULL`, confirming the UDF does not mistake a price for a size).

**Actually run, 2026-07-14:** the original regex above didn't survive contact with BigQuery — RE2 (BQ's regex
engine) has no lookahead support, and `REGEXP_EXTRACT` errors on more than one capturing group. Fixed by
folding the unit into the replacement group instead of a lookahead, splitting `raw_num`/`raw_unit` into two
single-capture-group extractions, and adding an explicit Thai-unit-to-ASCII normalization step (`กรัม`/`ก.` →
`g`, `มล.`/`มล` → `ml`, `ลิตร` → `l`) since the two TH test cases initially failed by returning the raw Thai
token instead of the ASCII unit the test expected. Final deployed version (`sql/functions/parse_size.sql`) —
all 5 cases `pass = true`. Function is live at `sincere-hearth-273704.magpie_reference.parse_size`.

- [x] **Step 3: If any row shows `pass = false`, fix the regex and re-run Step 2**

Do not proceed to Task 3 until all 5 rows pass. If a real `sku_name` sample from Task 1's data surfaces a
pattern not covered by these 5 cases, add it as a 6th `STRUCT` row in the `cases` UNNEST before proceeding —
the test block is meant to grow as real edge cases are found, not stay frozen at 5.

- [x] **Step 4: Commit**

```bash
git add sql/functions/parse_size.sql
git commit -m "Add parse_size BigQuery UDF for TH+ID size extraction, with embedded test cases"
```

---

### Task 3: Build and run the fill-if-null backfill query

**Files:**
- Create: `sql/queries/backfill_size_regex.sql`

**Interfaces:**
- Consumes: `` `sincere-hearth-273704.magpie_reference.parse_size`(sku_name STRING) `` from Task 2 (exact
  signature above); `ID_SCOPE_CONFIRMED` from Task 1's findings file.
- Produces: updated rows in `magpie_reference.product_taxonomy.size` — no new interface for later tasks to
  consume (Task 4 is documentation-only and doesn't call this query directly).

- [x] **Step 1: Read `docs/plans/size-regex-pass-findings.md`'s `ID_SCOPE_CONFIRMED` line**

If `yes`: use the country filter `IN ('TH', 'ID')` in Step 2 below (as written).
If `no`: change `IN ('TH', 'ID')` to `= 'TH'` in Step 2 below, and add a one-line note to the findings file:
`"ID deferred — re-run Task 1's discovery query after Intrepid ID extraction status is confirmed."`

- [x] **Step 2: Write the backfill query**

```sql
-- sql/queries/backfill_size_regex.sql
-- Fill-if-null size backfill. Same query runs once now (backfill) and later on a BigQuery
-- scheduled query (recurring) — see docs/llm-extraction-rules.md §2 for the schedule command.
-- Country filter below is set by Task 1's discovery findings (docs/plans/size-regex-pass-findings.md).

DECLARE latest_month DATE;
SET latest_month = (SELECT MAX(month) FROM `sincere-hearth-273704.magpie.marketshare_universe`);

UPDATE `sincere-hearth-273704.magpie_reference.product_taxonomy` t
SET size = parsed.parsed.size_text, updated_at = CURRENT_TIMESTAMP()
FROM (
  SELECT
    pt.taxonomy_id,
    `sincere-hearth-273704.magpie_reference.parse_size`(ANY_VALUE(u.sku_name)) AS parsed
  FROM `sincere-hearth-273704.magpie_reference.product_taxonomy` pt
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
    ON m.taxonomy_id = pt.taxonomy_id
  JOIN `sincere-hearth-273704.magpie.marketshare_universe` u
    ON u.product_id = m.product_id
    AND u.master_table = m.master_table
    AND u.month = latest_month
  WHERE pt.size IS NULL
    AND pt.is_multi_size IS NOT TRUE
    AND pt.is_bundle IS NOT TRUE
    AND m.country IN ('TH', 'ID')  -- Task 1 gate: change to = 'TH' if ID_SCOPE_CONFIRMED: no
  GROUP BY pt.taxonomy_id
) parsed
WHERE t.taxonomy_id = parsed.taxonomy_id
  AND parsed.parsed.size_value IS NOT NULL;
```

- [x] **Step 3: Dry-run before running for real**

Run: `bq query --dry_run --use_legacy_sql=false --project_id=sincere-hearth-273704 < sql/queries/backfill_size_regex.sql`

Expected: "Query successfully validated. This query will process X bytes." If X exceeds ~5GB, add
`TABLESAMPLE SYSTEM (50 PERCENT)` is **not** safe here (this is an UPDATE, sampling would randomly skip
eligible rows and never retry them) — instead, note the byte estimate in the findings file and proceed; a
single-month-partition join on `marketshare_universe` should already be far below the full 700GB, since only
one partition is read.

- [x] **Step 4: Run for real**

Run: `bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 < sql/queries/backfill_size_regex.sql`

Expected: a "Number of affected rows" count in the job summary.

- [x] **Step 5: Sanity-check the result against Task 1's eligible count**

Run:
```sql
SELECT
  m.country,
  COUNT(DISTINCT pt.taxonomy_id) AS still_null
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy` pt
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
  ON m.taxonomy_id = pt.taxonomy_id
WHERE pt.size IS NULL
  AND pt.is_multi_size IS NOT TRUE
  AND pt.is_bundle IS NOT TRUE
  AND m.country IN ('TH', 'ID')
GROUP BY m.country;
```

Expected: `still_null` counts are lower than Task 1 Step 1d's `eligible_null_size_taxonomy_ids` counts (the gap
is rows where `sku_name` had no regex-extractable size — genuinely NULL, not a bug). If `still_null` equals the
original count exactly (zero rows filled), stop and re-check the UDF against real `sku_name` samples before
re-running — something is wrong with the join or the regex, not with the data.

- [x] **Step 6: Commit**

```bash
git add sql/queries/backfill_size_regex.sql docs/plans/size-regex-pass-findings.md
git commit -m "Add size backfill query, run against product_taxonomy"
```


**Actually run, 2026-07-14:** found and fixed a struct-alias bug at dry-run time (`SET size =
parsed.size_text` was ambiguous; needed `parsed.parsed.size_text`). Dry-run came in at 33.6GB (bounded, one
month partition — BQ couldn't prune by country since the filter lives in a JOIN condition). **Result: 562 of
2,454 eligible TH rows filled**, sanity-checked exactly against the pre/post counts. Full detail, including a
pre-backfill snapshot path and a QA observation about `is_multi_size` entries, in
`docs/plans/size-regex-pass-findings.md`.

---

### Task 4: Document the pass and set up the recurring schedule

**Files:**
- Modify: `docs/llm-extraction-rules.md` (add subsection after line 91, end of current §2 Size)

**Interfaces:**
- Consumes: nothing new (references Task 2/3's file paths by name)
- Produces: nothing consumed by other tasks — this is the terminal, documentation-only task

- [x] **Step 1: Add the subsection to `docs/llm-extraction-rules.md` §2**

Insert after the existing §2 Size content (after line 91, before the `---` separator that starts §3):

```markdown

**Regex pre-pass (added <fill in actual date>):** before any LLM extraction reaches a product, a deterministic
text-only pass may have already filled `size` — see `sql/functions/parse_size.sql` and
`sql/queries/backfill_size_regex.sql`. It never overwrites an existing value (`size IS NULL AND is_multi_size
IS NOT TRUE AND is_bundle IS NOT TRUE` guard) and only covers TH + ID unit keywords today. If a product's
`size` is already filled when a Phase 5 session starts, that came from either this pass or a prior LLM run —
check `product_taxonomy.updated_at` if the source matters for a specific investigation; there is no separate
provenance column.

Recurring schedule (BigQuery-native, not a committed script):

```bash
bq mk --transfer_config \
  --project_id=sincere-hearth-273704 \
  --data_source=scheduled_query \
  --display_name="size_regex_backfill_recurring" \
  --target_dataset=magpie_reference \
  --schedule="every 24 hours" \
  --params='{"query":"<contents of sql/queries/backfill_size_regex.sql as one line>","write_disposition":"WRITE_APPEND"}'
```
```

- [x] **Step 2: Verify the markdown renders correctly**

Run: `grep -n "Regex pre-pass" docs/llm-extraction-rules.md` — confirm exactly one match, inside §2, before the
`## 3. Product Line Naming` heading.

- [x] **Step 3: Commit**

```bash
git add docs/llm-extraction-rules.md
git commit -m "Document size regex pre-pass and recurring schedule in llm-extraction-rules.md"
```
