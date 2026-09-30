# non_niq update-labelling sync — design

## Context

`script/non_niq/*` QA scripts (v2.sh, v3.py, and siblings) write only to
`{dataset}_qa` / `{dataset}_dict` / `filter_table`. They are deliberately
read-only against `{dataset}.master_table_prod` — several carry a hard rule:
"Never write to `qa_status` on the source table... a separate QA-labelling
update process reads the QA table independently and flips `qa_status`."

That separate process is `update-labelling-pipeline` (`_pipeline.py` +
`pages/0_Update_Labelling.py`), a human-operated Streamlit tool. It:

- Blocks (does not auto-fix) on duplicate `sku_type_complete` rows in the
  dict table — pure `GROUP BY ... HAVING COUNT(*) > 1`, no resolution logic.
- Rewrites the entire `(country, category, ecommerce_platform, month)`
  partition of `master_table_prod` via a single destination-table query
  (`WRITE_TRUNCATE`), never row-level DML.
- Recomputes `product_tier` for that whole partition every run via a
  cumulative-GMV-share window (`<=80% -> Tier 1, <=90% -> Tier 2, else
  Tier 3`), because removing one row reshuffles the ranking of every row
  below it.
- Sets `qa_status = 'Reviewed'` whenever the winning source for a product's
  row is any QA table (`source_pid LIKE '%qa%'`) — regardless of QA
  confidence. Quote (`_pipeline.py build_update_query`):
  `CASE WHEN pid.source_pid LIKE "%qa%" THEN 'Reviewed' ELSE 'Not Reviewed' END`

This spec ports an equivalent (not identical — see Decisions) capability
directly into the agentic non_niq QA scripts, so a QA session's writes to
`{dataset}_qa` propagate into `master_table_prod` without waiting on the
separate manual tool.

## Decisions (settled via user Q&A)

1. **Duplicate scope**: QA table only (`{dataset}_qa` / the resolved
   `qa_table`), not the dict table. Reference tool's dict-duplicate check is
   out of scope here.
2. **Write shape**: scoped per-row `UPDATE`, not a partition rewrite. These
   scripts process 10-100 row worklists, run many times a day — a full
   `WRITE_TRUNCATE` per session is the wrong cost profile and conflicts with
   the "DML only, no streaming API" convention these scripts already follow.
3. **Tier recalc**: only when this session newly filtered a product (inserted
   into `filter_table`). Runs the reference tool's full-partition cumulative-
   GMV window for that one `(country, category, ecommerce_platform, month)`
   slice, scoped narrowly to keep this rare and cheap.
4. **`qa_status` rule**: matches the reference tool exactly — any QA-table
   row for the identity flips it to `'Reviewed'`, confident or unconfident,
   pending or terminal. (Corrects an earlier draft of this spec that
   restricted this to terminal dispositions only.)
5. **Rollout**: `non_niq_qa_v2.sh` and `non_niq_qa_v3.py` first. v1,
   `non_niq_qa_v2_merchant_list.sh`, `non_niq_qa_v2_waterheater_multi.sh`,
   `susubayi_qa.sh`, `eiger_qa.sh` are out of scope for this change —
   follow-up once this is proven.

## New logic: `sync_labelling` (non_niq_helper.py)

One function, `sync_labelling(...)`, plus a CLI subcommand `sync-labelling`
wrapping it. Implemented once in Python (bigquery.Client, parameterized
queries — the pattern `_table_columns`/`confirm_casefold_matches` already
use), reused two ways:

- `non_niq_qa_v2.sh` shells out to `non_niq_helper.py sync-labelling`.
- `non_niq_qa_v3.py` imports and calls the function in-process.

This is deterministic bookkeeping, not a judgment call — it is code, never
agent-authored SQL, matching the existing precedent of
`apply_taxonomy_insert_log_backstop` (code-side verification) and v3.py's
`apply_chunk`/`verify_chunk_commit` (code-side transactional DML).

Scope: every call is bounded to *this session's own worklist* (the
product_id/ecommerce_platform/sku_name identities just processed) — never a
full-table scan. Consistent with every other cost-bounded step in these
scripts.

Inputs: `project`, `qa_table`, `qa_pk_col`, `qa_platform_col`,
`master_table` (`source_table`/`master_table_prod` ref), `filter_table`,
`worklist_file` (the session's materialized worklist JSONL — supplies the
identity set to scope all three steps to), `month`, `platform`, `country`,
`category`.

### Step 1 — Duplicate resolution (QA table)

For each `(qa_pk_col, qa_platform_col, normalized sku_name)` identity present
in the worklist:

```sql
SELECT * FROM `{qa_table}`
WHERE {qa_pk_col} = @product_id AND {qa_platform_col} = @platform
  AND REGEXP_REPLACE(TRIM(sku_name), r'\s+', ' ') = @normalized_sku_name
```

If more than one row comes back: rank by (a) count of non-NULL/non-empty
columns descending, (b) `_meta.timestamp` (parsed via
`JSON_VALUE(SAFE.PARSE_JSON(_meta), '$.timestamp')`) descending as tie-break.
Keep the top row, `DELETE` the rest via parameterized DML matching on the
full row's primary key columns (`{qa_pk_col}`, `{qa_platform_col}`, exact
`sku_name`, and `_meta` if needed for uniqueness — never a bare
`DELETE ... WHERE product_id = X` that could remove more than the intended
duplicate rows). Since QA tables are normally insert-only and this is the
first code path that ever deletes from one, log every delete's full row JSON
to `magpie_reference.non_niq_taxonomy_insert_log`-style audit trail: reuse
the existing `magpie_reference.non_niq_taxonomy_insert_log` table with
`target_table` set to `{qa_table}` and `row_json` wrapping
`{"action":"dedup_delete","deleted_row": {...}}` so an accidental
over-delete is forensically recoverable. This is the one piece of net-new
audit-trail plumbing this spec adds.

### Step 2 — Master-table sync (scoped UPDATE)

Resolve column names dynamically via `_table_columns`/
`resolve_category_columns` (`master_table`'s real schema) — never assume
`sku_type_complete` vs `sku_type`, or that `qa_status`/`source_pid` exist.
Columns that don't exist on `master_table` are skipped, not errored (same
graceful-degradation pattern as `dict_has_meta`).

For every identity in the worklist that now has exactly one QA row
(post-dedup) and is NOT present in `filter_table`:

```sql
UPDATE `{master_table}` m
SET m.{sku_col} = @sku_type_complete,
    m.brand = @brand
    -- , m.qa_status = 'Reviewed'      -- only if column exists
    -- , m.source_pid = @qa_table_ref  -- only if column exists
WHERE m.product_id = @product_id
  AND m.ecommerce_platform = @platform
  AND m.month = @month
  AND REGEXP_REPLACE(TRIM(m.sku_name), r'\s+', ' ') = @normalized_sku_name
```

`qa_status = 'Reviewed'` unconditionally whenever a QA row exists for the
identity (see Decision 4) — no confidence check. `source_pid` set to the
literal `{qa_table}` ref, matching the reference tool's convention of
storing which source table won.

Identities present in `filter_table` this session are skipped here (no
taxonomy values to write) and instead feed Step 3.

### Step 3 — Tier recalc (only on newly-filtered products)

Trigger: this session's worklist contains at least one identity that is now
present in `filter_table` (i.e., got filtered during this run — detected by
diffing the worklist's product_ids against `filter_table` after the agent's
writes, same anti-join style used elsewhere in these scripts).

If triggered, once per distinct `(country, category, ecommerce_platform,
month)` combination touched:

```sql
UPDATE `{master_table}` m
SET m.product_tier = t.new_tier
FROM (
  SELECT product_id,
    CASE
      WHEN cum_share <= 0.8 THEN 'Tier 1'
      WHEN cum_share <= 0.9 THEN 'Tier 2'
      ELSE 'Tier 3'
    END AS new_tier
  FROM (
    SELECT product_id, gmv_monthly,
      SUM(gmv_monthly) OVER (
        ORDER BY gmv_monthly DESC, product_id ASC
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ) / NULLIF(SUM(gmv_monthly) OVER (), 0) AS cum_share
    FROM `{master_table}`
    WHERE month = @month AND country = @country AND category = @category
      AND ecommerce_platform = @platform
      AND product_id NOT IN (SELECT product_id FROM `{filter_table}`)
  )
) t
WHERE m.product_id = t.product_id AND m.month = @month
  AND m.country = @country AND m.category = @category
  AND m.ecommerce_platform = @platform
```

Then, separately, set `product_tier = NULL` for every product_id in
`filter_table` within that same partition (they're excluded from tiering
entirely, not assigned a bucket).

`Tokopedia` vs `Tokopedia | Shop` stay distinct `ecommerce_platform`
populations — never combined in one window, per the existing warning in
`non_niq_qa_v2.sh:232-234`.

## Integration points

**`non_niq_qa_v2.sh`** (`main()`): call right after
`apply_taxonomy_insert_log_backstop`, before the Sheet write-back
(`v2.sh` main() ~line 1370-1415). Non-fatal — a `sync-labelling` failure is
logged and surfaced via a new `sync_labelling` key on `emit_result`'s JSON,
but does not change the run's own QUEUE_SIGNAL/status (the QA writes
already succeeded; this is best-effort downstream propagation, same
tolerance as the Sheet write-back step next to it).

**`non_niq_qa_v3.py`** (`run()`): call `sync_labelling(...)` directly
in-process after the chunked worklist loop completes, before the final
`emit_result` call (~line 2655).

**Out of scope for this change** (follow-up later): v1 (`non_niq_qa.sh`),
`non_niq_qa_v2_merchant_list.sh`, `non_niq_qa_v2_waterheater_multi.sh`,
`susubayi_qa.sh`, `eiger_qa.sh`. All five share `common.sh` already, so
wiring them in later is expected to be a small follow-up once
`sync_labelling` is proven on v2/v3.

## Testing

New `test_non_niq_helper_sync_labelling.py` (mirrors the existing
`test_non_niq_helper_sheet.py` pattern — no live BigQuery), asserting the
pure-logic pieces in isolation:

- Duplicate tie-break: given rows with varying NULL counts and `_meta`
  timestamps, the correct "keeper" row is selected.
- Tier bucket boundaries: cumulative-share values exactly at/around 0.8 and
  0.9 land in the correct tier.
- Column-skip behavior: when `qa_status`/`source_pid` are absent from a
  fake schema, the generated UPDATE omits them without erroring.

## Out of scope / non-goals

- Dict-table duplicate detection/resolution (stays a reference-tool-only,
  human-blocked concern).
- Any change to the dict-table matching used to produce `sku_type_complete`
  from `est_prodName`/dict identity lookups.
- Wiring this into v1 / merchant_list / waterheater_multi / susubayi /
  eiger scripts (explicit follow-up).
- Running `sync_labelling` outside the context of a QA session (e.g. as a
  standalone periodic job) — always invoked at the tail of a QA run, scoped
  to that run's own worklist.
