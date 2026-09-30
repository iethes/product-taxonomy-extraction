# non_niq Update-Labelling Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After a non_niq QA session writes to its QA table, automatically dedupe any duplicate QA rows, sync the resolved taxonomy/qa_status/source_pid into `master_table_prod` for this session's own worklist, and recompute `product_tier` only when the session newly touches a filtered product.

**Architecture:** One new module in `script/non_niq/non_niq_helper.py` — pure logic functions (duplicate tie-break, tier bucket math, SQL string builders) each unit-tested without BigQuery, plus thin BigQuery-executing wrappers composed into a single `sync_labelling()` entry point. `non_niq_qa_v2.sh` calls it via a new `sync-labelling` CLI subcommand (subprocess); `non_niq_qa_v3.py` imports and calls the same Python function directly (no subprocess, it's already Python).

**Tech Stack:** Python 3.8 (`.venv` at repo root, `google-cloud-bigquery` client), Bash (`script/non_niq/non_niq_qa_v2.sh`, `script/lib/common.sh`), BigQuery parameterized DML (`ArrayQueryParameter`/`StructQueryParameter`, matching the existing `confirm_casefold_matches` pattern).

**Spec:** `docs/superpowers/specs/2026-09-30-non-niq-update-labelling-sync-design.md`

## Global Constraints

- Only `script/non_niq/non_niq_qa_v2.sh` and `script/non_niq/non_niq_qa_v3.py` get the new integration call; v1, `non_niq_qa_v2_merchant_list.sh`, `non_niq_qa_v2_waterheater_multi.sh`, `susubayi_qa.sh`, `eiger_qa.sh` are explicitly out of scope for this plan.
- Every new BigQuery write uses the `bigquery.Client` + parameterized query pattern already established in `non_niq_helper.py` (`confirm_casefold_matches`) — never raw `bq` CLI string interpolation, never the streaming insert API (`insert_rows_json`).
- Every dedupe `DELETE` from a QA table is logged to `magpie_reference.non_niq_taxonomy_insert_log` in the same BigQuery script (`BEGIN TRANSACTION; ...; COMMIT;`), matching the mandatory insert-log contract used elsewhere in this repo for taxonomy-table writes.
- `qa_status` is set to `'Reviewed'` whenever any QA row exists for an identity — no confidence check. This matches the reference tool's `_pipeline.py` exactly (`CASE WHEN pid.source_pid LIKE "%qa%" THEN 'Reviewed' ELSE 'Not Reviewed' END`).
- Master-table columns (`qa_status`, `source_pid`, `product_tier`) that don't exist on a given category's `master_table_prod` are skipped, never errored — resolved dynamically per-call via `INFORMATION_SCHEMA.COLUMNS` (`_table_columns`, already in `non_niq_helper.py`).
- Tier recalculation only runs when this session's own worklist contains at least one product_id currently present in `filter_table` — otherwise the whole (expensive) step is skipped.
- `Tokopedia` and `Tokopedia | Shop` must stay separate `ecommerce_platform` populations in any query that scopes by the umbrella platform value (tier recalc) — per the existing warning at `non_niq_qa_v2.sh:232-234`. Per-row QA/master matching (Steps 1–2) uses each row's own exact platform value directly, so this only matters for Step 3.
- New tests follow this repo's existing plain-`assert` self-check convention (`test_non_niq_helper_sheet.py`) — no pytest, no live BigQuery in any test.

## Review Focus

- A worklist row with a blank/missing `product_id` or `sku_name` must never become a wildcard-matching identity (an empty normalized sku_name would match every blank-titled QA row). Covered by Task 1's `build_worklist_identity` test.
- An identity with zero matching QA rows (e.g. the product ended up `unresolved`/`blocked` this session) must be silently skipped by the master sync, never error. Covered structurally by Task 3 (`dedupe_qa_table` only returns identities that have ≥1 surviving row) — verified by code review, not an automated test (BigQuery-touching).
- `master_table_prod` missing `qa_status`/`source_pid`/`product_tier` for a given category must degrade gracefully (omit those `SET` clauses / skip the tier step), never raise a BigQuery "unrecognized column" error. Covered by Task 2's `build_master_sync_sql` tests (asserts the extra clauses are entirely absent when the flags are false).
- Duplicate QA rows that tie on both non-null field count and `_meta.timestamp`, or have missing/malformed `_meta` JSON, must resolve deterministically and never raise on `json.loads`. Covered by Task 1's `select_duplicates_to_delete` tests.
- An empty or non-overlapping `filter_table` (nothing in this worklist is filtered) must skip tier recalculation entirely, with no malformed empty-array query. Covered structurally by Task 5's early-return guard (`if not filtered_ids: return`) — verified by code review.

---

## Task 1: Pure duplicate-resolution and tier logic

**Files:**
- Modify: `script/non_niq/non_niq_helper.py` (new section, append after `resolve_category_columns` around line 195)
- Create: `script/non_niq/test_non_niq_helper_sync_labelling.py`

**Interfaces:**
- Produces: `build_worklist_identity(row: dict) -> Optional[Tuple[str, str, str]]`, `_non_null_count(row: dict) -> int`, `select_duplicates_to_delete(qa_rows_by_identity: Dict[Tuple[str,str,str], List[dict]]) -> List[dict]`, `tier_for_share(cumulative_share: float) -> str`. All pure, no I/O.

- [ ] **Step 1: Write the failing test**

Create `script/non_niq/test_non_niq_helper_sync_labelling.py`:

```python
#!/usr/bin/env python3
"""Runnable self-check for non_niq_helper.py's update-labelling sync helpers -- no framework, no
network. Covers the tricky bits: worklist-identity normalization (never a wildcard-matching blank
identity), duplicate-row tie-breaking (most non-null fields, then latest _meta timestamp), and the
tier-bucket boundary math.
"""
from non_niq_helper import (
    build_worklist_identity, _non_null_count, select_duplicates_to_delete, tier_for_share,
)

# build_worklist_identity: normalizes whitespace, rejects blank product_id/sku_name.
assert build_worklist_identity(
    {"product_id": "1", "ecommerce_platform": "Shopee", "sku_name": "  Widget   A  "}
) == ("1", "Shopee", "Widget A")
assert build_worklist_identity(
    {"product_id": "", "ecommerce_platform": "Shopee", "sku_name": "Widget"}
) is None
assert build_worklist_identity(
    {"product_id": "1", "ecommerce_platform": "Shopee", "sku_name": "   "}
) is None

# _non_null_count ignores None, blank strings, and the literal "nan" text some legacy exports use.
assert _non_null_count({"a": "x", "b": None, "c": "", "d": "nan", "e": "y"}) == 2

# select_duplicates_to_delete: more complete row wins regardless of _meta timestamp.
sparse = {"product_id": "1", "brand": "A", "sku_type_complete": None,
          "_meta": '{"timestamp":"2026-09-29T00:00:00Z"}'}
complete = {"product_id": "1", "brand": "A", "sku_type_complete": "Widget",
            "_meta": '{"timestamp":"2026-09-01T00:00:00Z"}'}
assert select_duplicates_to_delete({("1", "Shopee", "widget"): [sparse, complete]}) == [sparse]

# Equal completeness -> latest _meta.timestamp wins, older one is deleted.
older = {"product_id": "2", "brand": "B", "_meta": '{"timestamp":"2026-09-01T00:00:00Z"}'}
newer = {"product_id": "2", "brand": "B", "_meta": '{"timestamp":"2026-09-29T00:00:00Z"}'}
assert select_duplicates_to_delete({("2", "Shopee", "widget"): [older, newer]}) == [older]

# Malformed/missing _meta must not raise -- treated as an empty timestamp, not a crash.
missing_meta = {"product_id": "3", "brand": "C"}
has_meta = {"product_id": "3", "brand": "C", "_meta": "not json"}
to_delete = select_duplicates_to_delete({("3", "Shopee", "widget"): [missing_meta, has_meta]})
assert len(to_delete) == 1

# A single row (no duplicate) is never touched.
assert select_duplicates_to_delete({("4", "Shopee", "widget"): [complete]}) == []

# tier_for_share: cumulative-GMV-share bucket boundaries.
assert tier_for_share(0.0) == "Tier 1"
assert tier_for_share(0.8) == "Tier 1"
assert tier_for_share(0.8000001) == "Tier 2"
assert tier_for_share(0.9) == "Tier 2"
assert tier_for_share(0.9000001) == "Tier 3"
assert tier_for_share(1.0) == "Tier 3"

print("OK")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd script/non_niq && ../../.venv/bin/python3 test_non_niq_helper_sync_labelling.py`
Expected: `ImportError: cannot import name 'build_worklist_identity' from 'non_niq_helper'`

- [ ] **Step 3: Write minimal implementation**

In `script/non_niq/non_niq_helper.py`, add after `resolve_category_columns` (after line 194):

```python
# ---------------------------------------------------------------------------
# Update-labelling sync: duplicate resolution + tier bucket logic (pure)
# ---------------------------------------------------------------------------

def build_worklist_identity(row):
    """Returns (product_id, platform, normalized_sku_name) for a worklist row, or None if the row
    has no usable product_id/sku_name -- a blank identity must never become a wildcard match
    against every blank-titled QA row."""
    product_id, platform, sku_name = worklist_row_key(row)
    normalized = re.sub(r"\s+", " ", sku_name.strip())
    if not product_id or not normalized:
        return None
    return (product_id, platform, normalized)


def _non_null_count(row):
    """Count of row's fields that are non-null and non-blank (ignoring the literal 'nan' string
    some legacy exports use for missing values)."""
    count = 0
    for value in row.values():
        if value is None:
            continue
        text = str(value).strip()
        if text and text.lower() != "nan":
            count += 1
    return count


def _dedup_sort_key(row):
    meta_raw = row.get("_meta") or row.get("meta") or "{}"
    try:
        meta = json.loads(meta_raw)
    except (TypeError, ValueError):
        meta = {}
    return (_non_null_count(row), str(meta.get("timestamp", "")))


def select_duplicates_to_delete(qa_rows_by_identity):
    """qa_rows_by_identity: {(product_id, platform, normalized_sku_name): [row_dict, ...]}.
    Returns a flat list of row dicts to DELETE -- every row in a >1-row group except the one with
    the most non-null fields (ties broken by the latest _meta.timestamp)."""
    to_delete = []
    for rows in qa_rows_by_identity.values():
        if len(rows) <= 1:
            continue
        ordered = sorted(rows, key=_dedup_sort_key, reverse=True)
        to_delete.extend(ordered[1:])
    return to_delete


def tier_for_share(cumulative_share):
    """Reference tool's cumulative-GMV-share bucket rule (_pipeline.py build_update_query)."""
    if cumulative_share <= 0.8:
        return "Tier 1"
    if cumulative_share <= 0.9:
        return "Tier 2"
    return "Tier 3"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd script/non_niq && ../../.venv/bin/python3 test_non_niq_helper_sync_labelling.py`
Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add script/non_niq/non_niq_helper.py script/non_niq/test_non_niq_helper_sync_labelling.py
git commit -m "feat(non_niq): add pure duplicate-resolution and tier-bucket logic"
```

---

## Task 2: SQL builder pure functions

**Files:**
- Modify: `script/non_niq/non_niq_helper.py`
- Modify: `script/non_niq/test_non_niq_helper_sync_labelling.py`

**Interfaces:**
- Consumes: nothing from Task 1 directly (independent pure functions).
- Produces: `_platform_filter_sql(platform: str) -> str`, `build_dedupe_lookup_sql(qa_table: str, qa_pk_col: str, qa_platform_col: str) -> str`, `build_dedupe_delete_sql(qa_table: str, qa_pk_col: str, qa_platform_col: str) -> str`, `build_master_sync_sql(master_table: str, sku_col: str, set_qa_status: bool, set_source_pid: bool) -> str`, `build_tier_recalc_sql(master_table: str, filter_table: str, platform_filter: str) -> str`, `build_tier_null_sql(master_table: str, filter_table: str, platform_filter: str) -> str`. All pure string builders, no BigQuery client involved — Task 3/4/5 execute these against a real client.

- [ ] **Step 1: Write the failing test**

Append to `script/non_niq/test_non_niq_helper_sync_labelling.py` (before the final `print("OK")`):

```python
from non_niq_helper import (
    _platform_filter_sql, build_dedupe_lookup_sql, build_dedupe_delete_sql,
    build_master_sync_sql, build_tier_recalc_sql, build_tier_null_sql,
)

# _platform_filter_sql: Tokopedia's own first-party channel stays in the same population.
assert _platform_filter_sql("Tokopedia") == "IN ('Tokopedia', 'Tokopedia | Shop')"
assert _platform_filter_sql("Shopee") == "= @platform"

lookup_sql = build_dedupe_lookup_sql("proj.ds.qa", "product_id", "ecommerce_platform")
assert "FROM `proj.ds.qa` q" in lookup_sql
assert "q.product_id = i.product_id" in lookup_sql
assert "q.ecommerce_platform = i.platform" in lookup_sql

delete_sql = build_dedupe_delete_sql("proj.ds.qa", "product_id", "ecommerce_platform")
assert "DELETE FROM `proj.ds.qa`" in delete_sql
assert "product_id AS pid" in delete_sql
assert "IN UNNEST(@to_delete)" in delete_sql

sync_sql = build_master_sync_sql("proj.ds.master", "sku_type_complete", True, True)
assert "m.sku_type_complete = s.sku_type_complete" in sync_sql
assert "m.qa_status = 'Reviewed'" in sync_sql
assert "m.source_pid = s.source_pid" in sync_sql
assert "FORMAT_DATE('%Y-%m', m.month) = @month" in sync_sql

sync_sql_no_extras = build_master_sync_sql("proj.ds.master", "sku_type", False, False)
assert "qa_status" not in sync_sql_no_extras
assert "source_pid" not in sync_sql_no_extras

tier_sql = build_tier_recalc_sql(
    "proj.ds.master", "proj.ds.filter", "IN ('Tokopedia', 'Tokopedia | Shop')",
)
assert "product_tier = t.new_tier" in tier_sql
assert "ecommerce_platform IN ('Tokopedia', 'Tokopedia | Shop')" in tier_sql
assert "NOT IN (SELECT product_id FROM `proj.ds.filter`)" in tier_sql
# The SQL's hardcoded CASE boundaries must match tier_for_share's thresholds exactly -- these two
# are independent representations of the same rule (one runs server-side over a whole partition,
# one is the pure Python mirror tested above), so a change to one without the other must fail here.
assert "cum_share <= 0.8 THEN 'Tier 1'" in tier_sql
assert "cum_share <= 0.9 THEN 'Tier 2'" in tier_sql

tier_null_sql = build_tier_null_sql("proj.ds.master", "proj.ds.filter", "= @platform")
assert "SET m.product_tier = NULL" in tier_null_sql
assert "ecommerce_platform = @platform" in tier_null_sql
assert "IN (SELECT product_id FROM `proj.ds.filter`)" in tier_null_sql
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd script/non_niq && ../../.venv/bin/python3 test_non_niq_helper_sync_labelling.py`
Expected: `ImportError: cannot import name '_platform_filter_sql' from 'non_niq_helper'`

- [ ] **Step 3: Write minimal implementation**

In `script/non_niq/non_niq_helper.py`, add after Task 1's block:

```python
# ---------------------------------------------------------------------------
# Update-labelling sync: SQL builders (pure -- return SQL text, no execution)
# ---------------------------------------------------------------------------

def _platform_filter_sql(platform):
    """Python port of the bash `platform_match_clause` / v3.py `_platform_match_sql` -- Tokopedia's
    own first-party channel ('Tokopedia | Shop') must stay in the same population as 'Tokopedia'
    for GMV/tier purposes; every other platform matches its exact value."""
    if platform == "Tokopedia":
        return "IN ('Tokopedia', 'Tokopedia | Shop')"
    return "= @platform"


def build_dedupe_lookup_sql(qa_table, qa_pk_col, qa_platform_col):
    return """
WITH identities AS (
  SELECT product_id, platform, normalized_sku_name FROM UNNEST(@identities)
)
SELECT TO_JSON_STRING(q) AS row_json, i.product_id, i.platform, i.normalized_sku_name
FROM `%s` q
JOIN identities i
  ON q.%s = i.product_id AND q.%s = i.platform
  AND REGEXP_REPLACE(TRIM(q.sku_name), r'\\s+', ' ') = i.normalized_sku_name
""" % (qa_table, qa_pk_col, qa_platform_col)


def build_dedupe_delete_sql(qa_table, qa_pk_col, qa_platform_col):
    return """
DELETE FROM `%s`
WHERE STRUCT(%s AS pid, %s AS platform, sku_name AS sku_name, _meta AS meta)
  IN UNNEST(@to_delete)
""" % (qa_table, qa_pk_col, qa_platform_col)


def build_master_sync_sql(master_table, sku_col, set_qa_status, set_source_pid):
    extra_sets = ""
    if set_qa_status:
        extra_sets += ",\n  m.qa_status = 'Reviewed'"
    if set_source_pid:
        extra_sets += ",\n  m.source_pid = s.source_pid"
    return """
UPDATE `%s` m
SET
  m.%s = s.sku_type_complete,
  m.brand = s.brand%s
FROM (SELECT * FROM UNNEST(@records)) s
WHERE m.product_id = s.product_id
  AND m.ecommerce_platform = s.ecommerce_platform
  AND FORMAT_DATE('%%Y-%%m', m.month) = @month
  AND REGEXP_REPLACE(TRIM(m.sku_name), r'\\s+', ' ') = s.normalized_sku_name
""" % (master_table, sku_col, extra_sets)


def build_tier_recalc_sql(master_table, filter_table, platform_filter):
    return """
UPDATE `%s` m
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
    FROM `%s`
    WHERE FORMAT_DATE('%%Y-%%m', month) = @month AND country = @country AND category = @category
      AND ecommerce_platform %s
      AND product_id NOT IN (SELECT product_id FROM `%s`)
  )
) t
WHERE m.product_id = t.product_id
  AND FORMAT_DATE('%%Y-%%m', m.month) = @month AND m.country = @country AND m.category = @category
  AND m.ecommerce_platform %s
""" % (master_table, master_table, platform_filter, filter_table, platform_filter)


def build_tier_null_sql(master_table, filter_table, platform_filter):
    return """
UPDATE `%s` m
SET m.product_tier = NULL
WHERE FORMAT_DATE('%%Y-%%m', m.month) = @month AND m.country = @country AND m.category = @category
  AND m.ecommerce_platform %s
  AND m.product_id IN (SELECT product_id FROM `%s`)
""" % (master_table, platform_filter, filter_table)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd script/non_niq && ../../.venv/bin/python3 test_non_niq_helper_sync_labelling.py`
Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add script/non_niq/non_niq_helper.py script/non_niq/test_non_niq_helper_sync_labelling.py
git commit -m "feat(non_niq): add SQL builders for update-labelling sync"
```

---

## Task 3: BigQuery executors for Step 1 (QA-table dedupe)

**Files:**
- Modify: `script/non_niq/non_niq_helper.py`

**Interfaces:**
- Consumes: `select_duplicates_to_delete` (Task 1), `build_dedupe_lookup_sql`, `build_dedupe_delete_sql` (Task 2).
- Produces: `fetch_qa_rows_for_identities(client, project, qa_table, qa_pk_col, qa_platform_col, identities: Iterable[Tuple[str,str,str]]) -> Dict[Tuple[str,str,str], List[dict]]`, `delete_qa_duplicate_rows(client, project, qa_table, qa_pk_col, qa_platform_col, rows_to_delete: List[dict]) -> int`, `dedupe_qa_table(client, project, qa_table, qa_pk_col, qa_platform_col, identities) -> Tuple[Dict[Tuple[str,str,str], dict], int]` (kept-row-per-identity map, count deleted). These consume a live `bigquery.Client` and are verified by code review + a manual dry-run (no BigQuery credentials in this repo's test environment) rather than an automated test, consistent with `confirm_casefold_matches` having no dedicated unit test either.

- [ ] **Step 1: Write the implementation**

In `script/non_niq/non_niq_helper.py`, add after Task 2's block:

```python
# ---------------------------------------------------------------------------
# Update-labelling sync: Step 1 -- QA-table duplicate resolution (BigQuery)
# ---------------------------------------------------------------------------

def fetch_qa_rows_for_identities(client, project, qa_table, qa_pk_col, qa_platform_col, identities):
    """identities: iterable of (product_id, platform, normalized_sku_name). Returns
    {(product_id, platform, normalized_sku_name): [row_dict, ...]} for every QA row matching one
    of those identities. An identity with zero matching rows is simply absent from the result --
    callers must not assume every requested identity comes back."""
    identities = list(identities)
    if not identities:
        return {}
    fqtn = "%s.%s" % (project, qa_table)
    identity_param = bigquery.ArrayQueryParameter(
        "identities", "STRUCT", [
            bigquery.StructQueryParameter(
                None,
                bigquery.ScalarQueryParameter("product_id", "STRING", pid),
                bigquery.ScalarQueryParameter("platform", "STRING", platform),
                bigquery.ScalarQueryParameter("normalized_sku_name", "STRING", sku),
            )
            for pid, platform, sku in identities
        ],
    )
    sql = build_dedupe_lookup_sql(fqtn, qa_pk_col, qa_platform_col)
    rows = client.query(
        sql, job_config=bigquery.QueryJobConfig(query_parameters=[identity_param]),
    ).result()
    grouped = {}
    for row in rows:
        key = (row.product_id, row.platform, row.normalized_sku_name)
        grouped.setdefault(key, []).append(json.loads(row.row_json))
    return grouped


def delete_qa_duplicate_rows(client, project, qa_table, qa_pk_col, qa_platform_col, rows_to_delete):
    """Deletes each row in rows_to_delete (full QA-table row dicts) and logs it to
    magpie_reference.non_niq_taxonomy_insert_log in the same BigQuery script -- QA tables are
    otherwise insert-only, so every delete here needs the same forensic trail as a new taxonomy
    row."""
    if not rows_to_delete:
        return 0
    fqtn = "%s.%s" % (project, qa_table)
    delete_param = bigquery.ArrayQueryParameter(
        "to_delete", "STRUCT", [
            bigquery.StructQueryParameter(
                None,
                bigquery.ScalarQueryParameter("pid", "STRING", str(row.get(qa_pk_col, ""))),
                bigquery.ScalarQueryParameter("platform", "STRING", str(row.get(qa_platform_col, ""))),
                bigquery.ScalarQueryParameter("sku_name", "STRING", str(row.get("sku_name", ""))),
                bigquery.ScalarQueryParameter("meta", "STRING", str(row.get("_meta", ""))),
            )
            for row in rows_to_delete
        ],
    )
    log_param = bigquery.ArrayQueryParameter(
        "log_rows", "STRUCT", [
            bigquery.StructQueryParameter(
                None,
                bigquery.ScalarQueryParameter("target_table", "STRING", fqtn),
                bigquery.ScalarQueryParameter(
                    "created_at", "TIMESTAMP",
                    datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
                ),
                bigquery.ScalarQueryParameter(
                    "row_json", "STRING",
                    json.dumps({"action": "dedup_delete", "deleted_row": row}, default=str),
                ),
            )
            for row in rows_to_delete
        ],
    )
    script = "\n".join([
        "BEGIN TRANSACTION;",
        build_dedupe_delete_sql(fqtn, qa_pk_col, qa_platform_col) + ";",
        "INSERT INTO `%s.magpie_reference.non_niq_taxonomy_insert_log`"
        " (target_table, created_at, row_json)" % project,
        "SELECT target_table, created_at, PARSE_JSON(row_json) FROM UNNEST(@log_rows);",
        "COMMIT;",
    ])
    client.query(
        script,
        job_config=bigquery.QueryJobConfig(query_parameters=[delete_param, log_param]),
    ).result()
    return len(rows_to_delete)


def dedupe_qa_table(client, project, qa_table, qa_pk_col, qa_platform_col, identities):
    """Full Step 1: fetch QA rows for these identities, resolve duplicates, delete the losers
    (logged), return ({identity: kept_row_dict}, duplicates_deleted_count). An identity with no QA
    row at all (unresolved/blocked this session) is simply absent from the returned map."""
    grouped = fetch_qa_rows_for_identities(
        client, project, qa_table, qa_pk_col, qa_platform_col, identities,
    )
    to_delete = select_duplicates_to_delete(grouped)
    if to_delete:
        delete_qa_duplicate_rows(client, project, qa_table, qa_pk_col, qa_platform_col, to_delete)
    kept = {}
    for identity, group_rows in grouped.items():
        remaining = [r for r in group_rows if r not in to_delete]
        if remaining:
            kept[identity] = remaining[0]
    return kept, len(to_delete)
```

- [ ] **Step 2: Verify by code review**

Read the new functions back and confirm: (a) `fetch_qa_rows_for_identities` returns `{}` immediately for an empty `identities` list without querying BigQuery, (b) `delete_qa_duplicate_rows` returns `0` immediately for an empty `rows_to_delete` list without querying BigQuery, (c) the delete script's DELETE and INSERT run inside one `BEGIN TRANSACTION; ... COMMIT;` block so a failed log write rolls back the delete.

- [ ] **Step 3: Commit**

```bash
git add script/non_niq/non_niq_helper.py
git commit -m "feat(non_niq): add BigQuery executors for QA-table dedupe"
```

---

## Task 4: BigQuery executor for Step 2 (master-table sync)

**Files:**
- Modify: `script/non_niq/non_niq_helper.py`

**Interfaces:**
- Consumes: `_table_columns` (existing, line 171), `build_master_sync_sql` (Task 2).
- Produces: `resolve_master_sync_columns(client, project, master_table) -> dict` (keys: `sku_col`, `has_qa_status`, `has_source_pid`, `has_product_tier`), `sync_master_table(client, project, master_table, qa_table, kept_rows_by_identity, excluded_product_ids, month, master_columns, qa_identity_col) -> int` (rows updated).

- [ ] **Step 1: Write the implementation**

In `script/non_niq/non_niq_helper.py`, add after Task 3's block:

```python
# ---------------------------------------------------------------------------
# Update-labelling sync: Step 2 -- master-table sync (BigQuery)
# ---------------------------------------------------------------------------

def resolve_master_sync_columns(client, project, master_table):
    cols = _table_columns(client, project, master_table)
    if "sku_type_complete" in cols:
        sku_col = "sku_type_complete"
    elif "sku_type" in cols:
        sku_col = "sku_type"
    else:
        sku_col = None
    return {
        "sku_col": sku_col,
        "has_qa_status": "qa_status" in cols,
        "has_source_pid": "source_pid" in cols,
        "has_product_tier": "product_tier" in cols,
    }


def sync_master_table(client, project, master_table, qa_table, kept_rows_by_identity,
                       excluded_product_ids, month, master_columns, qa_identity_col):
    """kept_rows_by_identity: {(product_id, platform, normalized_sku_name): row_dict} -- the single
    QA row (post-dedup) for each identity. excluded_product_ids: product_ids to skip entirely
    (filtered this session -- there is no taxonomy to write for them, see Step 3 instead)."""
    sku_col = master_columns["sku_col"]
    if sku_col is None:
        return 0
    records = []
    for (product_id, platform, normalized_sku_name), row in kept_rows_by_identity.items():
        if product_id in excluded_product_ids:
            continue
        identity_value = str(row.get(qa_identity_col, "")).strip()
        brand = str(row.get("brand", "")).strip()
        if not identity_value or not brand:
            continue
        records.append({
            "product_id": product_id,
            "ecommerce_platform": platform,
            "normalized_sku_name": normalized_sku_name,
            "sku_type_complete": identity_value,
            "brand": brand,
            "source_pid": "%s.%s" % (project, qa_table),
        })
    if not records:
        return 0
    fqtn = "%s.%s" % (project, master_table)
    record_fields = (
        "product_id", "ecommerce_platform", "normalized_sku_name",
        "sku_type_complete", "brand", "source_pid",
    )
    record_param = bigquery.ArrayQueryParameter(
        "records", "STRUCT", [
            bigquery.StructQueryParameter(
                None,
                *[bigquery.ScalarQueryParameter(field, "STRING", record[field]) for field in record_fields],
            )
            for record in records
        ],
    )
    month_param = bigquery.ScalarQueryParameter("month", "STRING", month)
    sql = build_master_sync_sql(
        fqtn, sku_col, master_columns["has_qa_status"], master_columns["has_source_pid"],
    )
    job = client.query(
        sql, job_config=bigquery.QueryJobConfig(query_parameters=[record_param, month_param]),
    )
    job.result()
    return job.num_dml_affected_rows or 0
```

- [ ] **Step 2: Verify by code review**

Confirm: (a) `sync_master_table` returns `0` immediately when `sku_col` is `None` (category's master table has neither `sku_type_complete` nor `sku_type`) without querying, (b) `excluded_product_ids` filtering happens before building `records`, so a filtered product never gets a taxonomy write here, (c) `record_fields` order matches the `STructQueryParameter` construction order exactly (a mismatch here would silently swap column values).

- [ ] **Step 3: Commit**

```bash
git add script/non_niq/non_niq_helper.py
git commit -m "feat(non_niq): add BigQuery executor for master-table sync"
```

---

## Task 5: BigQuery executor for Step 3 (tier recalc)

**Files:**
- Modify: `script/non_niq/non_niq_helper.py`

**Interfaces:**
- Consumes: `_platform_filter_sql`, `build_tier_recalc_sql`, `build_tier_null_sql` (Task 2).
- Produces: `filtered_product_ids(client, project, filter_table, product_ids: Iterable[str]) -> Set[str]`, `recalc_tier_if_needed(client, project, master_table, filter_table, month, platform, country, category, filtered_ids: Set[str]) -> dict` (keys: `ran`, `filtered_count`).

- [ ] **Step 1: Write the implementation**

In `script/non_niq/non_niq_helper.py`, add after Task 4's block:

```python
# ---------------------------------------------------------------------------
# Update-labelling sync: Step 3 -- tier recalculation (BigQuery)
# ---------------------------------------------------------------------------

def filtered_product_ids(client, project, filter_table, product_ids):
    product_ids = sorted({str(p) for p in product_ids if p})
    if not product_ids:
        return set()
    fqtn = "%s.%s" % (project, filter_table)
    param = bigquery.ArrayQueryParameter("product_ids", "STRING", product_ids)
    sql = "SELECT DISTINCT product_id FROM `%s` WHERE product_id IN UNNEST(@product_ids)" % fqtn
    rows = client.query(
        sql, job_config=bigquery.QueryJobConfig(query_parameters=[param]),
    ).result()
    return {row.product_id for row in rows}


def recalc_tier_if_needed(client, project, master_table, filter_table, month, platform,
                           country, category, filtered_ids):
    """Step 3: only runs the (expensive, whole-partition) tier recompute when filtered_ids is
    non-empty -- i.e. this session's worklist touches at least one currently-filtered product.
    Idempotent -- safe to call even when nothing actually changed this session, since recomputing
    an unchanged partition reproduces the same tier values it already has."""
    if not filtered_ids:
        return {"ran": False, "filtered_count": 0}
    platform_filter = _platform_filter_sql(platform)
    master_fqtn = "%s.%s" % (project, master_table)
    filter_fqtn = "%s.%s" % (project, filter_table)
    params = [
        bigquery.ScalarQueryParameter("month", "STRING", month),
        bigquery.ScalarQueryParameter("country", "STRING", country),
        bigquery.ScalarQueryParameter("category", "STRING", category),
    ]
    if platform_filter == "= @platform":
        params.append(bigquery.ScalarQueryParameter("platform", "STRING", platform))
    recalc_sql = build_tier_recalc_sql(master_fqtn, filter_fqtn, platform_filter)
    client.query(recalc_sql, job_config=bigquery.QueryJobConfig(query_parameters=params)).result()
    null_sql = build_tier_null_sql(master_fqtn, filter_fqtn, platform_filter)
    client.query(null_sql, job_config=bigquery.QueryJobConfig(query_parameters=params)).result()
    return {"ran": True, "filtered_count": len(filtered_ids)}
```

- [ ] **Step 2: Verify by code review**

Confirm: (a) `recalc_tier_if_needed` returns without querying BigQuery at all when `filtered_ids` is empty, (b) the `@platform` scalar parameter is only added when `platform_filter` actually references it (`"= @platform"`) — passing an unused parameter is harmless in BigQuery, but the `IN (...)` branch must not silently omit a parameter the query DOES reference, (c) both the recalc and null-out queries use identical `month`/`country`/`category`/`platform` scoping so they operate on the same partition.

- [ ] **Step 3: Commit**

```bash
git add script/non_niq/non_niq_helper.py
git commit -m "feat(non_niq): add BigQuery executor for tier recalculation"
```

---

## Task 6: Top-level `sync_labelling` orchestrator + CLI subcommand

**Files:**
- Modify: `script/non_niq/non_niq_helper.py`

**Interfaces:**
- Consumes: `build_worklist_identity` (Task 1), `dedupe_qa_table` (Task 3), `resolve_master_sync_columns`/`sync_master_table` (Task 4), `filtered_product_ids`/`recalc_tier_if_needed` (Task 5), `worklist_row_key` (existing).
- Produces: `sync_labelling(client, project, qa_table, qa_pk_col, qa_platform_col, master_table, filter_table, rows, month, platform, country, category, qa_identity_col="sku_type_complete") -> dict` (keys: `duplicates_removed`, `master_rows_updated`, `tier_recalc`). CLI subcommand `sync-labelling` exposing the same function to bash callers.

- [ ] **Step 1: Write the implementation**

In `script/non_niq/non_niq_helper.py`, add after Task 5's block (before the `# CLI` section comment):

```python
# ---------------------------------------------------------------------------
# Update-labelling sync: top-level entry point
# ---------------------------------------------------------------------------

def sync_labelling(client, project, qa_table, qa_pk_col, qa_platform_col, master_table,
                    filter_table, rows, month, platform, country, category,
                    qa_identity_col="sku_type_complete"):
    """Scoped to one QA session's own worklist rows. Runs, in order:
      1. dedupe_qa_table -- resolve duplicate QA rows for this worklist's identities.
      2. sync_master_table -- propagate the kept QA rows into master_table's taxonomy columns.
      3. recalc_tier_if_needed -- only if this worklist touches a currently-filtered product.
    Never raises for a worklist with no usable identities."""
    identities = set()
    product_ids = set()
    for row in rows:
        identity = build_worklist_identity(row)
        if identity is None:
            continue
        identities.add(identity)
        product_ids.add(identity[0])
    if not identities:
        return {
            "duplicates_removed": 0, "master_rows_updated": 0,
            "tier_recalc": {"ran": False, "filtered_count": 0},
        }

    kept, duplicates_removed = dedupe_qa_table(
        client, project, qa_table, qa_pk_col, qa_platform_col, identities,
    )
    excluded = filtered_product_ids(client, project, filter_table, product_ids)
    master_columns = resolve_master_sync_columns(client, project, master_table)
    updated = sync_master_table(
        client, project, master_table, qa_table, kept, excluded, month,
        master_columns, qa_identity_col,
    )
    tier_result = recalc_tier_if_needed(
        client, project, master_table, filter_table, month, platform, country, category, excluded,
    )
    return {
        "duplicates_removed": duplicates_removed,
        "master_rows_updated": updated,
        "tier_recalc": tier_result,
    }


def _cmd_sync_labelling(args):
    rows = [json.loads(line) for line in open(args.input_file) if line.strip()]
    client = bigquery.Client(project=args.project)
    result = sync_labelling(
        client, args.project, args.qa_table, args.qa_pk_col, args.qa_platform_col,
        args.master_table, args.filter_table, rows, args.month, args.platform,
        args.country, args.category, qa_identity_col=args.qa_identity_col,
    )
    print(json.dumps(result))
```

Then in `main()`, add the subparser (after the `forced_p` block, around line 1011):

```python
    sync_p = sub.add_parser("sync-labelling")
    sync_p.add_argument("--input-file", required=True)
    sync_p.add_argument("--project", required=True)
    sync_p.add_argument("--qa-table", required=True)
    sync_p.add_argument("--qa-pk-col", required=True)
    sync_p.add_argument("--qa-platform-col", required=True)
    sync_p.add_argument("--qa-identity-col", default="sku_type_complete")
    sync_p.add_argument("--master-table", required=True)
    sync_p.add_argument("--filter-table", required=True)
    sync_p.add_argument("--month", required=True)
    sync_p.add_argument("--platform", required=True)
    sync_p.add_argument("--country", required=True)
    sync_p.add_argument("--category", required=True)
```

And in the dispatch block (after `elif args.command == "forced-merchants":`):

```python
    elif args.command == "sync-labelling":
        _cmd_sync_labelling(args)
```

- [ ] **Step 2: Verify by code review + CLI smoke test**

Run: `cd script/non_niq && ../../.venv/bin/python3 non_niq_helper.py sync-labelling --help`
Expected: argparse help text listing all the flags above, no import error (confirms the new code parses and wires into `main()` correctly without needing real BigQuery credentials).

- [ ] **Step 3: Commit**

```bash
git add script/non_niq/non_niq_helper.py
git commit -m "feat(non_niq): add sync_labelling orchestrator and CLI subcommand"
```

---

## Task 7: Wire into `non_niq_qa_v2.sh`

**Files:**
- Modify: `script/non_niq/non_niq_qa_v2.sh:1387-1391`

**Interfaces:**
- Consumes: `non_niq_helper.py sync-labelling` CLI (Task 6). Reads existing `main()` locals: `dataset`, `platform_titlecase`, `country`, `category`, `source_table`, `qa_table`, `qa_pk_col`, `qa_platform_col`, `filter_table`, `month`, `tmp_tag`, `PROJECT`, `PYTHON_BIN`, `SCRIPT_SOURCE`, `residual_valid`.
- Produces: an extra `sync_labelling` key on the final `emit_result` call at line 1419 (now shifted by the inserted block).

- [ ] **Step 1: Insert the sync-labelling call**

In `script/non_niq/non_niq_qa_v2.sh`, between the existing lines:

```bash
  echo "$agent_output"
  format_result_summary "$agent_output"
```

and:

```bash
  # Sheet write-back: bash-invoked (not an agent tool call), reading STEP 3's complete artifact of
```

insert:

```bash

  # sync-labelling: propagate this session's QA-table writes into master_table_prod (dedupe
  # duplicate QA rows for this worklist's identities, sync taxonomy/qa_status/source_pid, recalc
  # product_tier only for identities newly filtered this session). Best-effort, same non-fatal
  # contract as the Sheet write-back next to it -- the QA writes already succeeded; this is
  # downstream propagation, not part of the QA session's own pass/fail. Uses the FULL original
  # worklist (before the auto-confirm/agent split), not the reassigned $worklist_file, since
  # auto-confirmed rows also need syncing.
  local sync_labelling_output="skipped"
  local full_worklist_file="/tmp/${tmp_tag}_v2_full_worklist.jsonl"
  if [[ "$residual_valid" == true && -s "$full_worklist_file" ]]; then
    log INFO "Syncing this session's QA writes into ${source_table}..."
    if sync_labelling_output=$("$PYTHON_BIN" "$(dirname "$SCRIPT_SOURCE")/non_niq_helper.py" sync-labelling \
      --project "$PROJECT" --qa-table "$qa_table" --qa-pk-col "$qa_pk_col" \
      --qa-platform-col "$qa_platform_col" --master-table "$source_table" --filter-table "$filter_table" \
      --input-file "$full_worklist_file" --month "$month" --platform "$platform_titlecase" \
      --country "$country" --category "$category" 2>&1); then
      log INFO "sync-labelling: ${sync_labelling_output}"
    else
      log WARN "sync-labelling failed (non-fatal): ${sync_labelling_output}"
      sync_labelling_output="failed"
    fi
  fi
```

Then update the final `emit_result` call (originally line 1419) to add the new field:

```bash
  emit_result "${dataset}:${platform}" "$signal" "QA v2 session finished" "rows_created=$(extract_rows_created "$agent_output")" "rows_auto_confirmed=$auto_confirmed" "sync_labelling=${sync_labelling_output}"
```

- [ ] **Step 2: Verify with a syntax check**

Run: `bash -n script/non_niq/non_niq_qa_v2.sh`
Expected: no output (valid syntax).

- [ ] **Step 3: Verify the insertion point manually**

Read back `script/non_niq/non_niq_qa_v2.sh` around the edited region and confirm: (a) the new block sits strictly between `format_result_summary "$agent_output"` and the `# Sheet write-back` comment, (b) `full_worklist_file` is declared `local` (this function already declares many locals this way — a missing `local` here would leak into the caller's shell if this script is ever sourced instead of executed), (c) the early snapshot-exec guard at the top of this file (`NON_NIQ_QA_V2_SNAPSHOT`) means this edit only takes effect on the *next* invocation of the script, not a currently-running session — expected, not a bug.

- [ ] **Step 4: Commit**

```bash
git add script/non_niq/non_niq_qa_v2.sh
git commit -m "feat(non_niq): call sync-labelling after QA v2 sessions"
```

---

## Task 8: Wire into `non_niq_qa_v3.py`

**Files:**
- Modify: `script/non_niq/non_niq_qa_v3.py:23-34` (imports), `script/non_niq/non_niq_qa_v3.py:2652-2661` (`run()`)

**Interfaces:**
- Consumes: `sync_labelling` (Task 6, imported directly — v3.py already imports several functions from `non_niq_helper`). Reads `RunContext` fields: `project`, `dataset`, `platform`, `country`, `category`, `source_table`, `qa_table`, `qa_pk_col`, `qa_identity_col`, `filter_table`, `month`; and the module function `_qa_platform_column(context)` for `qa_platform_col`.
- Produces: an extra `sync_labelling` field on the final `emit_result` call.

- [ ] **Step 1: Add the import**

In `script/non_niq/non_niq_qa_v3.py`, change the existing import block (lines 23-34):

```python
from non_niq_helper import (
    MEILI_URL,
    _table_columns,
    append_sheet_new_entries_strict,
    fetch_config_csv,
    fetch_forced_merchant_ids,
    index_documents_strict,
    parse_categories,
    retrieve_candidates,
    confirm_casefold_matches,
    worklist_row_key,
)
```

to:

```python
from non_niq_helper import (
    MEILI_URL,
    _table_columns,
    append_sheet_new_entries_strict,
    fetch_config_csv,
    fetch_forced_merchant_ids,
    index_documents_strict,
    parse_categories,
    retrieve_candidates,
    confirm_casefold_matches,
    sync_labelling,
    worklist_row_key,
)
```

- [ ] **Step 2: Call it after the chunk loop**

In `script/non_niq/non_niq_qa_v3.py`, change the existing tail of `run()` (lines 2656-2661):

```python
        signal = "BLOCKED" if blocked else "DONE"
        message = "QA v3 session blocked on deferred products" if blocked else "QA v3 session finished"
        emit_result(
            table, signal, message, rows=str(len(rows)),
            rows_auto_confirmed=str(auto_confirmed_rows),
        )
        return 0
```

to:

```python
        sync_summary = {"duplicates_removed": 0, "master_rows_updated": 0, "tier_recalc": {"ran": False, "filtered_count": 0}}
        if not args.dry_run:
            try:
                sync_summary = sync_labelling(
                    client, context.project, context.qa_table, context.qa_pk_col,
                    _qa_platform_column(context), context.source_table, context.filter_table,
                    rows, context.month, context.platform, context.country, context.category,
                    qa_identity_col=context.qa_identity_col,
                )
            except Exception as sync_error:
                # Best-effort, same non-fatal contract as the bash side's Sheet write-back --
                # the QA writes already succeeded; this is downstream propagation, not part of
                # the QA session's own pass/fail.
                sync_summary = {"error": "%s: %s" % (type(sync_error).__name__, sync_error)}

        signal = "BLOCKED" if blocked else "DONE"
        message = "QA v3 session blocked on deferred products" if blocked else "QA v3 session finished"
        emit_result(
            table, signal, message, rows=str(len(rows)),
            rows_auto_confirmed=str(auto_confirmed_rows),
            sync_labelling=json.dumps(sync_summary, sort_keys=True, separators=(",", ":")),
        )
        return 0
```

- [ ] **Step 3: Verify with a syntax check**

Run: `cd script/non_niq && ../../.venv/bin/python3 -c "import ast; ast.parse(open('non_niq_qa_v3.py').read())"`
Expected: no output (valid syntax).

- [ ] **Step 4: Verify by code review**

Confirm: (a) `sync_labelling` is called with the whole session's `rows` (the full worklist materialized before the chunk loop), not a partial chunk — matching the "scoped to this session's own worklist" design, since auto-confirmed and agent-processed rows both need syncing and both draw from the same `rows` list, (b) the call is guarded by `not args.dry_run` the same way `drain_outbox`/`apply_chunk` already are earlier in this function, so a `--dry-run` invocation never writes to `master_table_prod`, (c) `emit_result`'s `**fields` signature (line 2549) accepts arbitrary string keyword arguments, so passing `sync_labelling=...` works without changing `emit_result` itself.

- [ ] **Step 5: Commit**

```bash
git add script/non_niq/non_niq_qa_v3.py
git commit -m "feat(non_niq): call sync_labelling after QA v3 sessions"
```
