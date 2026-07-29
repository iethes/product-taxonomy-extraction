# Design: Move `docs/categories/*.md` into a BigQuery `category_brief` table

> Status: approved design, not yet implemented.
> Companion to [`script/headless_taxonomy.sh`](../../../script/headless_taxonomy.sh),
> [`script/custom_headless_taxonomy.sh`](../../../script/custom_headless_taxonomy.sh),
> [`script/targeted_qa_fix.sh`](../../../script/targeted_qa_fix.sh),
> [`script/custom_targeted_qa_fix.sh`](../../../script/custom_targeted_qa_fix.sh), and
> [`docs/categories/STATUS.md`](../../categories/STATUS.md) / [`_TEMPLATE.md`](../../categories/_TEMPLATE.md).

---

## Problem

`docs/categories/*.md` (44 files, ~10.5k lines) is the pipeline's per-category context store: brand scope,
official-store allowlists, scope rules, SKU blocks, and a running QA History log. It's read and written
directly by four headless shell scripts as part of every automated session, and git-committed on every run.

Three problems with the current state:

1. **It's the wrong medium.** Long markdown blobs, read rarely per-row but written on every session, belong in
   a queryable table, not files that bloat git history with automated commits.
2. **Filenames don't match the pipeline's real join key.** Every NIQ-sourced file's actual `master_table` (used
   everywhere else — `product_taxonomy_map`, `sku_block_registry`, `universe_taxonomy_overlay`) includes a
   `shopee_` prefix the filename drops (`th_shampoo.md`'s own H1 says `shopee_th_shampoo`). This is already a
   live source of confusion: multiple headless-session transcripts (recorded in
   [memory](../../../../.claude/projects/-home-wikan-Documents-work-product-taxonomy-extraction/memory/project_th_baby_diapers_data_loss.md))
   show prompts referencing a nonexistent `docs/categories/shopee_th_coffee.md` when the real file is
   `th_coffee.md`. `targeted_qa_fix.sh`'s `resolve_category_file()` exists solely to paper over this with a
   guess-both-and-see fallback.
3. **Some categories' data was reset outside this pipeline.** Live `product_taxonomy_map` row counts for
   several `th_*` categories are far below what their docs claim (documented in the data-loss memory above).
   Migrating those docs' "✅ Complete" claims into BQ as if still true would be wrong — the migration must
   check live reality per category and annotate accordingly, not just copy text over.

Separately, `docs/categories/*.md` is read/written by four **currently-running, automated** shell scripts
(a live `queue_worker.sh` process was observed mid-session during design, actively writing to one of these
files) — the rollout must not corrupt or race against in-flight sessions.

---

## Deliverable scope

| File / resource | Change |
|---|---|
| `sincere-hearth-273704.magpie_reference.category_brief` (new) | New BQ table — single-table schema, see §1 |
| One-off migration script (Python, run once, not checked in as a repeated tool) | Reads all 42 category files, reality-checks each against live BQ, loads via `bq load` + `MERGE` |
| `script/headless_taxonomy.sh` | Read/write of `docs/categories/${table}.md` → BQ; STATUS.md race-guard → BQ query |
| `script/custom_headless_taxonomy.sh` | Same, dataset already an explicit arg |
| `script/targeted_qa_fix.sh` | `resolve_category_file()` deleted; brief fetch + QA History append → BQ |
| `script/custom_targeted_qa_fix.sh` | Same |
| `script/test_headless_taxonomy.sh`, `test_custom_headless_taxonomy.sh`, `test_targeted_qa_fix.sh`, `test_custom_targeted_qa_fix.sh` | Updated to assert against the new BQ-based logic |
| `docs/categories/*.md` (42 of 44 — all except `STATUS.md`, `_TEMPLATE.md`) | Deleted, in a commit separate from and after the script changes |
| `docs/categories/STATUS.md` | Kept as a frozen historical snapshot + pointer note; its two race-guard script references are what get rewired, not the file itself |
| `docs/categories/_TEMPLATE.md` | Unchanged — still defines the structure written into `brief_markdown` |
| `.claude/.../memory/project_th_baby_diapers_data_loss.md` | Updated post-migration with which categories are confirmed deliberate resets vs. still-open incidents |

Not in scope: changing how sessions *decide* what to extract (worklist queries, QA gates, SKU block claiming)
— only where the category context text lives and how it's read/written.

---

## 1. Schema — single table, `task_type` discriminator

```sql
CREATE TABLE `sincere-hearth-273704.magpie_reference.category_brief` (
  category_key       STRING NOT NULL,  -- 'master_clean_niq.shopee_sg_shampoo' / 'makanankucing.makanankucing_my'
  task_type            STRING NOT NULL,  -- 'BRIEF' | 'TAXONOMY' | 'QA_HISTORY'

  -- BRIEF rows only (exactly one live row per category_key — the current-state doc):
  source_dataset          STRING,   -- 'master_clean_niq' | 'makanankucing' | 'makanananjing'
  master_table               STRING,   -- literal join key used elsewhere in the pipeline
  source_table_fqn              STRING,  -- set only when it differs from source_dataset.master_table
                                          -- (e.g. makanankucing.9_makanankucing_my_daily)
  country                          STRING,
  status                              STRING,  -- active | partial_loss | reset_pending_redo | not_started
  live_map_rows                         INT64,  -- snapshot from the reality check that produced this row
  orphan_map_rows                          INT64,
  reality_checked_at                          TIMESTAMP,

  -- TAXONOMY rows (headless_taxonomy.sh full-rebuild/top-up runs) and
  -- QA_HISTORY rows (targeted_qa_fix.sh runs) — many rows per category_key, append-only:
  task_date                                      DATE,

  brief_markdown       STRING NOT NULL,  -- BRIEF: full doc body. TAXONOMY/QA_HISTORY: freeform note on that run.
  updated_at           TIMESTAMP NOT NULL,
  meta_agent            STRING NOT NULL   -- CLAUDE_CODE | CODEX | HUMAN, per CLAUDE.md's meta_agent rule
);
```

`category_key = source_dataset.master_table` is an **identifier**, not a resolvable path — it names no real
BQ table for the custom-sourced categories, hence `source_table_fqn` as a separate column for the cases where
it matters (currently only the four `makanan*` categories).

`task_type='TAXONOMY'` vs. `'QA_HISTORY'` split by *which script wrote the row* (`headless_taxonomy.sh` runs vs.
`targeted_qa_fix.sh` runs) — mirrors today's `.md` files, where both scripts already append to the same shared
"## QA History" table; this just tags which kind of session produced each entry instead of losing that
distinction in one shared log.

**Lookups:**
- Current brief: `SELECT brief_markdown, status, live_map_rows FROM category_brief WHERE category_key=@k AND task_type='BRIEF'`
- Run log: `SELECT task_date, brief_markdown FROM category_brief WHERE category_key=@k AND task_type IN ('TAXONOMY','QA_HISTORY') ORDER BY task_date`

No BQ-enforced primary key (BQ doesn't have one); the `BRIEF`-row-uniqueness-per-`category_key` invariant is
maintained by always writing `BRIEF` rows via `MERGE` (never plain `INSERT`), and `TAXONOMY`/`QA_HISTORY` rows
via plain `INSERT` (append-only, never updated).

---

## 2. Category key derivation (all 42 categories)

Dataset is deterministic per script, not guessed per file:

| Source | `source_dataset` | Categories |
|---|---|---|
| `headless_taxonomy.sh` / `targeted_qa_fix.sh` (NIQ) | `master_clean_niq` | 38 categories: all `th_*`, `sg_*`, `shopee_sg_*`, `shopee_id_*` files |
| `custom_headless_taxonomy.sh` / `custom_targeted_qa_fix.sh` (custom) | argv[1], currently `makanankucing` or `makanananjing` | `makanankucing_my`, `makanankucing_sg`, `makanananjing_my`, `makanananjing_sg` |

`master_table` = each file's actual `master_table` value (already confirmed per-file via each doc's own H1 /
body text during design exploration — e.g. `sg_shampoo.md` → `shopee_sg_shampoo`, `makanankucing_my.md` →
`makanankucing_my`). The migration script hardcodes this 42-row mapping rather than re-deriving it from
filenames, since the filename-to-master_table relationship is exactly the inconsistency being fixed.

`source_table_fqn` is set (non-null) only for the four custom categories, e.g.
`sincere-hearth-273704.makanankucing.9_makanankucing_my_daily`; null for NIQ categories where
`source_dataset.master_table` already resolves to the real table.

---

## 3. Reality check (per category, at migration time)

For each of the 42 categories, live-query — never trust the markdown's documented counts:

```sql
SELECT source, COUNT(*) AS rows
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
WHERE master_table = @master_table
GROUP BY source;

-- orphan check, per the data-loss memory's prescription:
SELECT COUNT(*) AS orphan_rows
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
LEFT JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt
  ON m.taxonomy_id = pt.taxonomy_id
WHERE m.master_table = @master_table AND pt.taxonomy_id IS NULL;
```

Status assignment:
- `live rows ≈ 0` (or all remaining rows orphaned) **and** the doc claims completion → `reset_pending_redo`
- `live rows` present but well below what the doc's "Map Row Counts" section claims, with orphans found →
  `partial_loss`
- `live rows` roughly match, or the doc was already marked keyword-only/not-started → `active` / `not_started`

Where status is `reset_pending_redo` or `partial_loss`, prepend one short dated note to `brief_markdown`:

```markdown
## Data Reality Check (2026-07-29)
Live `product_taxonomy_map`: N rows (M orphaned). Category doc below claims completion as of
<date> — live state does not match. Treat as [reset for redo | partially recovered]; the prose
below is historical context, not current status.
```

The rest of the file's content is preserved verbatim below that note — no rewriting, no deletion of history.

This also directly answers the "respect the user's judgment to redo" instruction: `reset_pending_redo` *is*
that judgment being respected and recorded, rather than escalated as an unexplained incident. Once the
migration classifies every category, update `project_th_baby_diapers_data_loss.md` to reflect which
categories are now understood as deliberate resets vs. which remain open (e.g. `th_baby_diapers`'s
dictionary-block deletion has no redo signal and stays flagged as an open incident).

Each category's existing "## QA History" markdown table (where present and non-placeholder) is parsed and
loaded as individual `QA_HISTORY` rows (one per dated table row); `_TEMPLATE.md`'s placeholder rows are
skipped, not migrated.

---

## 4. Write path (both migration and live scripts)

**Never** an inline `bq query` with the full markdown as a string literal (breaks on quotes, backticks, `|`
table pipes, Thai script) and **never** the streaming API (90-minute buffer rule, CLAUDE.md).

- **`BRIEF` row write** (migration; and live, on `headless_taxonomy.sh` full-rebuild / STATUS-changing runs):
  content → temp NDJSON file → `bq load` into a staging table → `MERGE` into `category_brief` keyed on
  `(category_key, task_type='BRIEF')`.
- **`TAXONOMY` / `QA_HISTORY` row write** (the high-frequency path — every top-up and QA-fix session): a plain
  parameterized `bq query` `INSERT` of one row. Small enough (a few text fields, one row) that this is safe
  without the load-and-merge machinery — no blob involved.

---

## 5. Script cutover

**`headless_taxonomy.sh` / `custom_headless_taxonomy.sh`:**
- STATUS.md completion race-guard ("check docs/categories/STATUS.md to confirm `${table}` hasn't already been
  completed") → `SELECT status, updated_at FROM category_brief WHERE category_key=@k AND task_type='BRIEF'`.
- "read the existing category file" (top-up prompt) → `bq query` fetching `brief_markdown` by key.
- "Write the file, then commit it: `git add ... && git commit`" (full-rebuild prompt) → the load/MERGE
  mechanism in §4, `MERGE`d as `task_type='BRIEF'`.
- "Append a dated row to `${table}.md`'s QA History table, commit" (top-up prompt) → single `INSERT` with
  `task_type='TAXONOMY'`.

**`targeted_qa_fix.sh` / `custom_targeted_qa_fix.sh`:**
- `resolve_category_file()` (the `${table}.md` / `${table#shopee_}.md` guess-both fallback) — **deleted**. The
  deterministic `category_key` removes the ambiguity it existed to paper over.
- `has_real_brief()` — same logic, now checked against the fetched `brief_markdown` string instead of a file's
  contents.
- QA History append → single `INSERT` with `task_type='QA_HISTORY'`.
- Existing "do not edit the file / run git yourself" constraints on the agent carry over unchanged in spirit:
  the agent still must not perform the `category_brief` write itself outside the prescribed `INSERT`/MERGE
  pattern the prompt gives it.

**Tests:** all four `test_*.sh` files get their file-existence/content assertions replaced with equivalent
assertions against the new `bq query`/`INSERT` string construction (mocking `bq` the same way the current
tests mock file presence via `mkdir`/`touch` in a tmpdir).

---

## 6. `STATUS.md` and `_TEMPLATE.md`

Neither is a per-category brief, so neither is migrated as `category_brief` data:

- **`STATUS.md`**: its two race-guard script references are rewired to the BQ query in §5. The file itself is
  left in place as a frozen snapshot as of the migration date, with a one-line pointer note added at the top
  ("Live status: `SELECT category_key, status, live_map_rows FROM category_brief WHERE task_type='BRIEF'`").
  Its SKU Block Registry section was already superseded by the live `sku_block_registry` table before this
  design.
- **`_TEMPLATE.md`**: unchanged. Still referenced by `headless_taxonomy.sh`/`custom_headless_taxonomy.sh` to
  tell the agent what structure to write into `brief_markdown` for a new `BRIEF` row.

---

## 7. Rollout order

Sequenced specifically because of the live `queue_worker.sh` process observed during design:

1. Create `category_brief` in BQ.
2. Run the one-off migration (reality-check + load) — `docs/categories/*.md` files untouched, still the live
   source scripts read.
3. Update the four scripts + four test files. Run tests.
4. Manually dry-run a prompt build for one `headless_taxonomy.sh` and one `targeted_qa_fix.sh` invocation,
   eyeball the generated prompt text.
5. Confirm no `queue_worker.sh` / `claude -p` session is currently running (or coordinate pausing it) before
   the next step — an in-flight session still expects the old file-based prompts and file paths.
6. Delete `docs/categories/*.md` (all except `STATUS.md`, `_TEMPLATE.md`) as its own commit, separate from the
   script changes.
7. Update `project_th_baby_diapers_data_loss.md` per §3.
8. Resume `queue_worker.sh` if it was paused.

Any file mid-write by an in-flight session at design time (observed:
`shopee_sg_vitamin_mineral_health_supplements.md`) is left alone — its content will be picked up correctly by
step 2's reality check regardless of whether that session finishes before or after the migration runs, since
the reality check reads live `product_taxonomy_map`, not the file.
