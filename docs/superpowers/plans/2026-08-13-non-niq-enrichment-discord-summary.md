# Non-NIQ Enrichment, Discord Notification & Result Summary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three improvements to the Non-NIQ QA harness: Shopee description/specs enrichment in the worklist query, a Discord "AI QA" notification on every new taxonomy entry, and a human-readable summary of the final `claude -p` session result.

**Architecture:** All three are additive changes to the two existing files (`script/non_niq/non_niq_qa.sh`, `script/non_niq/non_niq_helper.py`) plus one new `.env.example` line — no new files, no new architecture. Enrichment is a plain SQL `LEFT JOIN` (bash owns it, per explicit decision — no model/embedding involved). The Discord notification is Python-driven (reads the row back from BigQuery after Claude writes it, so the message reflects what's actually persisted, not a self-report) and non-fatal by construction. The result summary reads two layers of the same `claude -p` JSON output (the outer envelope for cost/turns, the inner `.result` for status/counts) through one shared extraction helper.

**Tech Stack:** Bash (`jq`, `bq`), Python (`google-cloud-bigquery`, stdlib `urllib` — no new dependencies).

## Global Constraints

- Every claim about live schemas/behavior in this plan was verified against real BigQuery data or a real `claude -p` call during design — not assumed. Treat any place this plan's code diverges from what you observe live as a signal to stop and check, not to silently "fix" by matching the plan.
- `item_description`/`product_attributes_attrs` enrichment is **Shopee-only** — confirmed live that non-Shopee `0_pipeline_*` tables (e.g. Blibli) have a completely different schema with no description/specs columns. Never attempt the join for a non-Shopee platform.
- The Discord webhook URL is a bearer credential — **never hardcoded into any committed file**. It lives in the user's local, gitignored `.env` as `DISCORD_WEBHOOK_URL`, read via `os.environ`.
- The `notify-discord` command **must never exit non-zero and must never raise past its own boundary** — a Discord/BigQuery hiccup must never fail or block the QA session that calls it. This applies to every failure mode: missing webhook URL, invalid identity column, no matching row, BigQuery error, HTTP error.
- Discord's message content hard limit is 2000 characters — `_format_discord_table` must respect it, truncating individual long cell values (not dropping whole rows/columns) as the first line of defense, with a last-resort whole-table truncation if that still isn't enough.
- `identity_col` in `notify-discord` must be validated against `DICT_IDENTITY_CANDIDATES` (`["sku_type_complete", "sku_type"]`) before being interpolated into a SQL string as a column identifier — it can only ever come from this project's own resolved config, but validate anyway.
- `format_result_summary`'s output is printed **alongside** the existing raw `claude_output` echo in `main()`, never replacing it — `non_niq_queue_worker.sh`'s `persist_final_status()` stores whatever `non_niq_qa.sh` prints, and the raw envelope carries metadata the summary doesn't surface.
- Real, live-verified field names for the `claude -p --output-format json` envelope: `total_cost_usd` (top-level float), `modelUsage` (object keyed by model name, each with `costUSD`, `inputTokens`, `outputTokens`, `cacheReadInputTokens`, `cacheCreationInputTokens`), `num_turns`, `duration_ms`. Do not invent different field names.
- This plan touches only `script/non_niq/non_niq_qa.sh`, `script/non_niq/non_niq_helper.py`, `tests/non_niq/test_non_niq_qa.sh`, `tests/non_niq/test_non_niq_helper.py`, and `.env.example`. No other file changes.

---

## File Structure

```
script/non_niq/non_niq_qa.sh        # Task 1: worklist_query() enrichment param + join.
                                     # Task 3: build_qa_prompt() Step C + main() sources load_env.sh.
                                     # Task 4: extract_result_json(), format_result_summary(), main() prints it.
script/non_niq/non_niq_helper.py    # Task 1: ROW_FIELDS gets "0".
                                     # Task 2: _format_discord_table(), notify_discord_new_entry(),
                                     #         _http_post_json(), notify-discord CLI subcommand.
tests/non_niq/test_non_niq_qa.sh    # Tasks 1, 3, 4: new assertions.
tests/non_niq/test_non_niq_helper.py # Tasks 1, 2: fixture fix + new tests.
.env.example                        # Task 2: DISCORD_WEBHOOK_URL= placeholder.
```

---

### Task 1: Description/specs enrichment in `worklist_query()`

**Files:**
- Modify: `script/non_niq/non_niq_helper.py` (`ROW_FIELDS`)
- Modify: `script/non_niq/non_niq_qa.sh` (`worklist_query()`, `build_qa_prompt()`'s STEP 2a text, `main()`)
- Test: `tests/non_niq/test_non_niq_helper.py`, `tests/non_niq/test_non_niq_qa.sh`

**Interfaces:**
- Produces: `worklist_query()` gains a 6th, optional parameter `enrichment_table` (defaults to empty string when omitted — existing 5-arg callers keep working unchanged). Output rows now always include `item_description` and `product_attributes_attrs` columns (real values on Shopee when an enrichment table is given, `NULL` otherwise).
- Produces: `parse_categories()`'s output dicts now include a `"0"` key (the Sheet's literal column name, kept as-is — no renaming layer) holding the enrichment table's short name (e.g. `"0_pipeline_babybath_shopee_id"`), or `""` if the Sheet cell is empty.

- [ ] **Step 1: Write the failing tests**

In `tests/non_niq/test_non_niq_helper.py`, replace the existing `SAMPLE_CSV` constant (the current one has a pre-existing field-alignment bug — `table` resolves to the wrong column value, just never asserted on) with this corrected, position-verified version, and update `test_row_shape` to also assert on `table` and the new `"0"` field:

```python
SAMPLE_CSV = """country,category_1,category_2,category,dataset,is_active,ecommerce_platform,raw_table,children,filter_column,filter_value,,0,exclude_tiktok,variant,filter_variant,phasing,1,2-1,2-2,2-3,5,9,double_date,is_daily,10,9_table,table,master_table_prod,product_id_dict_qa,product_id_dict,product_id_dict_image_qa,product_id_image_taxonomy,dict,filter_table,sku_type_complete,PIC,isDoubleDate,keywords,taxonomy_url ,taxonomy_spreadsheet_id, taxonomy_sheet_name,labelling_config,last_active_month,qa_ai_labelling
ID,Mom & Baby,Baby Care,Baby Bath & Shampoo,babybath,TRUE,shopee,babybath.raw_babybath_shopee,,,,,0_pipeline_babybath_shopee_id,,,,,,,,,,,,,,,babybath.master_babybath_id_dev,,babybath.product_id_dict_qa,babybath.product_id_dict,,,babybath.babybath_dict,babybath.filter_babybath,sku_type_complete,David,-,,,,,,,
ID,Mom & Baby,Baby Care,Baby Bath & Shampoo,babybath,FALSE,lazada,babybath.raw_babybath_lazada,,,,,,,,,,,,,,,,,,,,babybath.master_babybath_id_dev,,babybath.product_id_dict_qa,babybath.product_id_dict,,,babybath.babybath_dict,babybath.filter_babybath,sku_type_complete,David,-,,,,,,,
US,Mom & Baby,Baby Care,Baby Bath & Shampoo,babybath,TRUE,shopee,babybath.raw_babybath_shopee_us,,,,,0_pipeline_babybath_shopee_us,,,,,,,,,,,,,,,babybath.master_babybath_us_dev,,babybath.product_id_dict_qa,babybath.product_id_dict,,,babybath.babybath_dict,babybath.filter_babybath,sku_type_complete,David,-,,,,,,,
ID,Beauty,Skincare,Facial Serum,facialserum,TRUE,shopee,facialserum.raw_facialserum_shopee,,,,,0_pipeline_facialserum_shopee_id,,,,,,,,,,,,,,,facialserum.master_facialserum_id_dev,,facialserum.product_id_dict_qa,-,,,facialserum.facialserum_dict,facialserum.filter_facialserum,sku_type_complete,David,-,,,,,,,
"""
```

```python
def test_row_shape():
    rows = parse_categories(SAMPLE_CSV, country="ID")
    babybath = next(r for r in rows if r["dataset"] == "babybath")
    assert babybath["category"] == "Baby Bath & Shampoo"
    assert babybath["ecommerce_platform"] == "shopee"
    assert babybath["product_id_dict_qa"] == "babybath.product_id_dict_qa"
    assert babybath["product_id_dict"] == "babybath.product_id_dict"
    assert babybath["dict"] == "babybath.babybath_dict"
    assert babybath["filter_table"] == "babybath.filter_babybath"
    assert babybath["table"] == "babybath.master_babybath_id_dev"
    assert babybath["0"] == "0_pipeline_babybath_shopee_id"

def test_row_enrichment_table_empty_when_sheet_cell_blank():
    rows = parse_categories(SAMPLE_CSV, country="ID")
    facialserum = next(r for r in rows if r["dataset"] == "facialserum")
    # facialserum row DOES have a "0" value in this fixture -- assert it's carried through too,
    # covering the "present" case for a second dataset (not just babybath).
    assert facialserum["0"] == "0_pipeline_facialserum_shopee_id"
```

In `tests/non_niq/test_non_niq_qa.sh`, add after the existing `worklist_query` block (after the `echo "PASS: worklist_query"` line, before `# --- primary_filter_table ---`):

```bash
# --- worklist_query enrichment (item_description/product_attributes_attrs) ---
# Shopee + a real enrichment table name -> conditional LEFT JOIN present.
q_enriched=$(worklist_query "babybath.master_babybath_id_dev" "babybath.product_id_dict_qa" "prod_id" "2026-07" "shopee" "0_pipeline_babybath_shopee_id")
echo "$q_enriched" | grep -q "LEFT JOIN \`sincere-hearth-273704.babybath.0_pipeline_babybath_shopee_id\` e" || fail "worklist_query must LEFT JOIN the Shopee enrichment table when given one"
echo "$q_enriched" | grep -q "CAST(e.item_itemid AS STRING) = s.product_id" || fail "worklist_query must join the enrichment table on item_itemid = product_id"
echo "$q_enriched" | grep -q "e.item_description, e.product_attributes_attrs" || fail "worklist_query must select item_description/product_attributes_attrs from the enrichment table when joined"
echo "$q_enriched" | grep -q "sc.item_description, sc.product_attributes_attrs" || fail "worklist_query must carry item_description/product_attributes_attrs through to the final SELECT"

# Non-Shopee platform -> no join, NULL columns instead, even if an enrichment_table value is passed
# (confirmed live: non-Shopee 0_pipeline_* tables have a different schema with no description/specs).
q_noenrich=$(worklist_query "babybath.master_babybath_id_dev" "babybath.product_id_dict_qa" "prod_id" "2026-07" "lazada" "0_pipeline_babybath_lazada_id")
if echo "$q_noenrich" | grep -q "LEFT JOIN"; then
  fail "worklist_query must never join the enrichment table for a non-Shopee platform"
fi
echo "$q_noenrich" | grep -q "NULL AS item_description, NULL AS product_attributes_attrs" || fail "worklist_query must select NULL item_description/product_attributes_attrs for non-Shopee platforms"

# No enrichment table given at all (Sheet's "0" column empty) -> same NULL fallback, even for Shopee.
q_missing=$(worklist_query "babybath.master_babybath_id_dev" "babybath.product_id_dict_qa" "prod_id" "2026-07" "shopee")
if echo "$q_missing" | grep -q "LEFT JOIN"; then
  fail "worklist_query must not attempt a join when no enrichment_table is given"
fi
echo "PASS: worklist_query enrichment"
```

Add one line to the existing `build_qa_prompt` assertion block (anywhere after the `prompt=$(build_qa_prompt ...)` call):

```bash
echo "$prompt" | grep -q "product_attributes_attrs" || fail "STEP 2a must mention product_attributes_attrs as additional signal alongside item_description"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/non_niq/test_non_niq_qa.sh 2>&1 | tail -20` and `.venv/bin/python3 tests/non_niq/test_non_niq_helper.py 2>&1 | tail -20`
Expected: FAIL — `worklist_query` doesn't accept a 6th argument's join yet, `"0"` isn't in `ROW_FIELDS` yet.

- [ ] **Step 3: Implement**

In `script/non_niq/non_niq_helper.py`, change:
```python
ROW_FIELDS = ["category", "dataset", "ecommerce_platform", "table", "product_id_dict_qa",
              "product_id_dict", "dict", "filter_table"]
```
to:
```python
ROW_FIELDS = ["category", "dataset", "ecommerce_platform", "table", "product_id_dict_qa",
              "product_id_dict", "dict", "filter_table", "0"]
```

In `script/non_niq/non_niq_qa.sh`, replace the entire `worklist_query()` function with:

```bash
worklist_query() {
  local source_table="$1" qa_table="$2" qa_pk_col="$3" month="$4" platform="$5" enrichment_table="${6:-}"
  local platform_titlecase="${platform^}"
  # item_description/product_attributes_attrs enrichment is Shopee-only by data availability, not
  # a scoping choice: confirmed live that non-Shopee 0_pipeline_* tables (e.g. Blibli) have an
  # entirely different schema with no description/specs columns at all. dataset is derived from
  # source_table (already "{dataset}.master_..._dev") rather than a separate parameter.
  local dataset="${source_table%%.*}"
  local enrichment_join="" enrichment_select="NULL AS item_description, NULL AS product_attributes_attrs"
  if [[ "$platform_titlecase" == "Shopee" && -n "$enrichment_table" && "$enrichment_table" != "-" ]]; then
    enrichment_join="LEFT JOIN \`${PROJECT}.${dataset}.${enrichment_table}\` e ON CAST(e.item_itemid AS STRING) = s.product_id"
    enrichment_select="e.item_description, e.product_attributes_attrs"
  fi
  cat <<SQL
WITH base AS (
  SELECT s.product_id, s.sku_name, s.image, s.ecommerce_platform, s.qa_status,
         COALESCE(s.flag_GWP, FALSE) OR REGEXP_CONTAINS(UPPER(s.sku_name), r'\[NOT FOR SALE\]|\[GWP\]') AS flag_GWP,
         s.gmv_monthly, ${enrichment_select}
  FROM \`${PROJECT}.${source_table}\` s
  ${enrichment_join}
  WHERE FORMAT_DATE('%Y-%m', s.month) = '${month}' AND s.ecommerce_platform = '${platform_titlecase}'
),
with_cumulative AS (
  SELECT *,
    ROUND(100.0 * SUM(CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END)
            OVER (ORDER BY gmv_monthly DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
          / NULLIF(SUM(CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END) OVER (), 0), 2) AS cumulative_gmv_pct
  FROM base
),
scoped AS (
  SELECT * FROM with_cumulative WHERE cumulative_gmv_pct <= 90
),
qa_state AS (
  SELECT ${qa_pk_col} AS product_id,
         JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.qa_confidence') AS qa_confidence,
         JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.human_review') AS human_review
  FROM \`${PROJECT}.${qa_table}\`
),
prioritized AS (
  SELECT sc.product_id, sc.sku_name, sc.image, sc.gmv_monthly, sc.ecommerce_platform,
         sc.item_description, sc.product_attributes_attrs,
    CASE
      WHEN qs.product_id IS NULL AND sc.qa_status = 'Not Reviewed' THEN 0
      WHEN qs.qa_confidence = 'unconfident' AND COALESCE(qs.human_review, 'false') != 'true' THEN 1
      ELSE NULL
    END AS priority
  FROM scoped sc
  LEFT JOIN qa_state qs ON qs.product_id = sc.product_id
)
SELECT * FROM prioritized
WHERE priority IS NOT NULL
ORDER BY priority ASC, gmv_monthly DESC
SQL
}
```

In `build_qa_prompt()`, find the line:
```
      Then, with the image + sku_name + item_description together --
```
and replace it with:
```
      Then, with the image + sku_name + item_description + product_attributes_attrs together (the
      worklist's own columns; item_description/product_attributes_attrs are Shopee-only signal and
      NULL on other platforms -- treat NULL as simply having no extra signal, not as a problem) --
```

In `main()`, find:
```bash
  local source_table qa_table dict_table filter_table_config product_id_dict
  source_table=$(echo "$category_json" | jq -r '.table')
  qa_table=$(echo "$category_json" | jq -r '.product_id_dict_qa')
  dict_table=$(echo "$category_json" | jq -r '.dict')
  filter_table_config=$(echo "$category_json" | jq -r '.filter_table')
  product_id_dict=$(echo "$category_json" | jq -r '.product_id_dict')
```
and add one line after it:
```bash
  local source_table qa_table dict_table filter_table_config product_id_dict enrichment_table
  source_table=$(echo "$category_json" | jq -r '.table')
  qa_table=$(echo "$category_json" | jq -r '.product_id_dict_qa')
  dict_table=$(echo "$category_json" | jq -r '.dict')
  filter_table_config=$(echo "$category_json" | jq -r '.filter_table')
  product_id_dict=$(echo "$category_json" | jq -r '.product_id_dict')
  enrichment_table=$(echo "$category_json" | jq -r '."0"')
```

Then find:
```bash
  local query
  query=$(worklist_query "$source_table" "$qa_table" "$qa_pk_col" "$month" "$platform")
```
and change to:
```bash
  local query
  query=$(worklist_query "$source_table" "$qa_table" "$qa_pk_col" "$month" "$platform" "$enrichment_table")
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/non_niq/test_non_niq_qa.sh 2>&1 | tail -20` and `.venv/bin/python3 tests/non_niq/test_non_niq_helper.py 2>&1 | tail -20`
Expected: `ALL TESTS PASSED` for both.

- [ ] **Step 5: Verify against live BigQuery (not just grep-tested SQL)**

This project has already shipped one bug (`SAFE.JSON_VALUE`) that passed every grep-based test but failed live. Confirm the new join actually executes:

```bash
source script/non_niq/non_niq_qa.sh
q=$(worklist_query "babybath.master_babybath_id_dev" "babybath.product_id_dict_qa" "prod_id" "2026-08" "shopee" "0_pipeline_babybath_shopee_id")
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=csv "SELECT COUNT(*), COUNTIF(item_description IS NOT NULL) FROM ($q)"
```
Expected: no BigQuery error, and `COUNTIF(item_description IS NOT NULL)` is greater than 0 (some Shopee products in scope actually have a description).

- [ ] **Step 6: Commit**

```bash
git add script/non_niq/non_niq_qa.sh script/non_niq/non_niq_helper.py tests/non_niq/test_non_niq_qa.sh tests/non_niq/test_non_niq_helper.py
git commit -m "Add Shopee item_description/product_attributes_attrs enrichment to worklist_query"
```

---

### Task 2: Discord notification command in `non_niq_helper.py`

**Files:**
- Modify: `script/non_niq/non_niq_helper.py`
- Modify: `.env.example`
- Test: `tests/non_niq/test_non_niq_helper.py`

**Interfaces:**
- Consumes: `DICT_IDENTITY_CANDIDATES` (already defined in this file, Task 1 doesn't change it).
- Produces:
  - `DISCORD_CONTENT_LIMIT = 2000`, `DISCORD_CELL_TRUNCATE = 200` (module-level constants).
  - `_format_discord_table(row: dict, dataset: str) -> str` — pure function, no I/O.
  - `_http_post_json(url: str, body: dict) -> None`.
  - `notify_discord_new_entry(project, dict_table, brand, identity_col, identity_value, dataset, client=None, webhook_url=None, post=None) -> None` — never raises.
  - CLI: `non_niq_helper.py notify-discord --project P --dict-table dataset.dict --brand B --identity-col C --identity-value V --dataset D`.

- [ ] **Step 1: Write the failing tests**

Add to `tests/non_niq/test_non_niq_helper.py` (after the existing `retrieve_candidates` tests, before the `# --- categories CLI ---` section):

```python
# --- _format_discord_table ---

def test_format_discord_table_includes_all_nonnull_columns():
    row = {"brand": "Acme", "sku_type_complete": "Acme Baby Wash 200ml", "packsize": "200 ml", "empty_col": None}
    msg = non_niq_helper._format_discord_table(row, "babybath")
    assert "**AI QA**" in msg
    assert "babybath" in msg
    assert "brand" in msg and "Acme" in msg
    assert "sku_type_complete" in msg and "Acme Baby Wash 200ml" in msg
    assert "packsize" in msg and "200 ml" in msg
    assert "empty_col" not in msg

def test_format_discord_table_truncates_long_cell_not_whole_row():
    long_value = "x" * 500
    row = {"brand": "Acme", "ingredients": long_value}
    msg = non_niq_helper._format_discord_table(row, "babybath")
    assert "brand" in msg
    assert "ingredients" in msg
    assert long_value not in msg
    assert "..." in msg

def test_format_discord_table_respects_discord_content_limit():
    row = {f"col_{i}": "y" * 100 for i in range(50)}
    msg = non_niq_helper._format_discord_table(row, "babybath")
    assert len(msg) <= non_niq_helper.DISCORD_CONTENT_LIMIT

# --- notify_discord_new_entry ---

class _FakeRow:
    def __init__(self, d):
        self._d = d
    def items(self):
        return self._d.items()

class _FakeQueryResult:
    def __init__(self, rows):
        self._rows = rows
    def result(self):
        return self._rows

class _FakeBQClient:
    def __init__(self, rows):
        self._rows = rows
    def query(self, query, job_config=None):
        return _FakeQueryResult(self._rows)

def test_notify_discord_posts_formatted_table():
    posted = {}
    def fake_post(url, body):
        posted["url"] = url
        posted["body"] = body
    client = _FakeBQClient([_FakeRow({"brand": "Acme", "sku_type_complete": "Acme Wash 200ml"})])
    non_niq_helper.notify_discord_new_entry(
        "proj", "babybath.babybath_dict", "Acme", "sku_type_complete", "Acme Wash 200ml", "babybath",
        client=client, webhook_url="https://discord.example/webhook", post=fake_post,
    )
    assert posted["url"] == "https://discord.example/webhook"
    assert "Acme Wash 200ml" in posted["body"]["content"]
    assert "**AI QA**" in posted["body"]["content"]

def test_notify_discord_rejects_unknown_identity_col():
    posted = []
    def fake_post(url, body):
        posted.append(body)
    client = _FakeBQClient([_FakeRow({"brand": "Acme"})])
    # 'brand' is not a valid dict-identity candidate -- must be refused before ever building SQL.
    non_niq_helper.notify_discord_new_entry(
        "proj", "babybath.babybath_dict", "Acme", "brand", "Acme", "babybath",
        client=client, webhook_url="https://discord.example/webhook", post=fake_post,
    )
    assert posted == []

def test_notify_discord_missing_webhook_url_is_non_fatal(monkeypatch):
    monkeypatch.setattr(non_niq_helper.os, "environ", {})
    client = _FakeBQClient([_FakeRow({"brand": "Acme", "sku_type": "X"})])

    def should_not_post(*a):
        raise AssertionError("must not post when no webhook URL is configured")

    # Must not raise -- caller (Claude, via bash) must never see this fail the session.
    non_niq_helper.notify_discord_new_entry(
        "proj", "babybath.babybath_dict", "Acme", "sku_type", "X", "babybath",
        client=client, webhook_url=None, post=should_not_post,
    )

def test_notify_discord_post_failure_is_non_fatal():
    def failing_post(url, body):
        raise RuntimeError("Discord is down")
    client = _FakeBQClient([_FakeRow({"brand": "Acme", "sku_type": "X"})])
    # Must not raise past this call -- this is the whole point of the function.
    non_niq_helper.notify_discord_new_entry(
        "proj", "babybath.babybath_dict", "Acme", "sku_type", "X", "babybath",
        client=client, webhook_url="https://discord.example/webhook", post=failing_post,
    )

def test_notify_discord_no_matching_row_is_non_fatal():
    client = _FakeBQClient([])
    posted = []
    non_niq_helper.notify_discord_new_entry(
        "proj", "babybath.babybath_dict", "Acme", "sku_type", "X", "babybath",
        client=client, webhook_url="https://discord.example/webhook", post=lambda u, b: posted.append(b),
    )
    assert posted == []
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `.venv/bin/python3 tests/non_niq/test_non_niq_helper.py 2>&1 | tail -30`
Expected: FAIL — `AttributeError: module 'non_niq_helper' has no attribute '_format_discord_table'` (and similarly for `notify_discord_new_entry`, `non_niq_helper.os`).

- [ ] **Step 3: Implement**

In `script/non_niq/non_niq_helper.py`, add `import os` to the top-level imports (currently `argparse, csv, io, json, urllib.error, urllib.request`):

```python
import argparse
import csv
import io
import json
import os
import urllib.error
import urllib.request
```

Add these constants near the top, alongside `MEILI_URL`/`MODEL_NAME`/`BATCH_SIZE`:

```python
DISCORD_CONTENT_LIMIT = 2000
DISCORD_CELL_TRUNCATE = 200
```

Add a new section (after the "Retrieval" section, before "CLI"):

```python
# ---------------------------------------------------------------------------
# Discord notification on new taxonomy entry creation
# ---------------------------------------------------------------------------

def _format_discord_table(row, dataset):
    """row: dict of column_name -> value, already read back from BigQuery. Formats every non-null
    column into an aligned monospace table inside a code fence (Discord doesn't render pipe-table
    markdown as an actual table -- a code block is what's actually legible), preceded by an AI QA
    header. Individual long cell values are truncated (not whole rows/columns) to respect
    Discord's 2000-char content limit while keeping every column's presence visible."""
    pairs = [(k, str(v)) for k, v in row.items() if v is not None]
    if not pairs:
        pairs = [("(no columns)", "")]
    key_width = max(len(k) for k, _ in pairs)
    lines = []
    for k, v in pairs:
        v_trunc = v if len(v) <= DISCORD_CELL_TRUNCATE else v[:DISCORD_CELL_TRUNCATE - 3] + "..."
        lines.append(f"{k.ljust(key_width)} : {v_trunc}")
    header = f"**AI QA** — new taxonomy entry created (`{dataset}`)"
    message = f"{header}\n```\n" + "\n".join(lines) + "\n```"
    if len(message) > DISCORD_CONTENT_LIMIT:
        # Still over budget even after per-cell truncation (very many columns) -- hard-truncate the
        # whole table as a last resort, never silently drop the header.
        fence_overhead = len(header) + len("\n```\n") + len("\n...(truncated)\n```")
        budget = max(DISCORD_CONTENT_LIMIT - fence_overhead, 0)
        table_body = "\n".join(lines)[:budget]
        message = f"{header}\n```\n{table_body}\n...(truncated)\n```"
    return message


def _http_post_json(url, body):
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, method="POST", headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        resp.read()


def notify_discord_new_entry(project, dict_table, brand, identity_col, identity_value, dataset,
                              client=None, webhook_url=None, post=None):
    """Reads the just-created row back from BigQuery (never trusts Claude's self-report of what it
    wrote), formats it, and posts to Discord. Never raises past this function and never exits
    non-zero via its CLI wrapper -- a Discord/BigQuery hiccup must never fail or block the QA
    session that called it."""
    post = post or _http_post_json
    try:
        if identity_col not in DICT_IDENTITY_CANDIDATES:
            raise ValueError(f"Refusing to interpolate unexpected identity_col into SQL: {identity_col!r}")
        webhook_url = webhook_url or os.environ.get("DISCORD_WEBHOOK_URL")
        if not webhook_url:
            raise RuntimeError("DISCORD_WEBHOOK_URL is not set")
        client = client or bigquery.Client(project=project)
        query = f"""
            SELECT * FROM `{project}.{dict_table}`
            WHERE brand = @brand AND {identity_col} = @identity_value
            LIMIT 1
        """
        job_config = bigquery.QueryJobConfig(query_parameters=[
            bigquery.ScalarQueryParameter("brand", "STRING", brand),
            bigquery.ScalarQueryParameter("identity_value", "STRING", identity_value),
        ])
        rows = list(client.query(query, job_config=job_config).result())
        if not rows:
            print(f"  WARNING: notify-discord found no row for brand={brand!r} {identity_col}={identity_value!r} in {dict_table} -- skipping notification")
            return
        row = dict(rows[0].items())
        message = _format_discord_table(row, dataset)
        post(webhook_url, {"content": message})
        print(f"  Discord notified: {dict_table} brand={brand!r} {identity_col}={identity_value!r}")
    except Exception as e:
        print(f"  WARNING: notify-discord failed (non-fatal): {type(e).__name__}: {e}")
```

Add the CLI wrapper, in the "CLI" section, after `_cmd_retrieve`:

```python
def _cmd_notify_discord(args):
    notify_discord_new_entry(args.project, args.dict_table, args.brand, args.identity_col,
                              args.identity_value, args.dataset)
```

In `main()`, add the subparser (after the `ret_p` block, before `args = parser.parse_args()`):

```python
    notify_p = sub.add_parser("notify-discord")
    notify_p.add_argument("--project", required=True)
    notify_p.add_argument("--dict-table", required=True)
    notify_p.add_argument("--brand", required=True)
    notify_p.add_argument("--identity-col", required=True)
    notify_p.add_argument("--identity-value", required=True)
    notify_p.add_argument("--dataset", required=True)
```

And add the dispatch branch (after the `elif args.command == "retrieve":` block):
```python
    elif args.command == "notify-discord":
        _cmd_notify_discord(args)
```

In `.env.example`, add one line (after the existing `LEASE_TIMEOUT_HOURS=4` line):
```
# Discord webhook for "AI QA" notifications when non_niq_qa.sh mints a new taxonomy entry.
# Get the real URL from your Discord server's channel settings -- never commit the real value.
DISCORD_WEBHOOK_URL=
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `.venv/bin/python3 tests/non_niq/test_non_niq_helper.py 2>&1 | tail -30`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add script/non_niq/non_niq_helper.py tests/non_niq/test_non_niq_helper.py .env.example
git commit -m "Add notify-discord command: post AI QA table on new taxonomy entries, non-fatal"
```

---

### Task 3: Wire Discord notification into the prompt + source `load_env.sh`

**Files:**
- Modify: `script/non_niq/non_niq_qa.sh` (`build_qa_prompt()`, `main()`)
- Test: `tests/non_niq/test_non_niq_qa.sh`

**Interfaces:**
- Consumes: `notify-discord` CLI (Task 2), `$PYTHON_BIN`/`$REPO_ROOT` (already defined at the top of `non_niq_qa.sh`).
- Produces: no new functions -- this task only changes prompt text and adds one `source` line to `main()`.

- [ ] **Step 1: Write the failing tests**

Add to `tests/non_niq/test_non_niq_qa.sh`, in the `build_qa_prompt` assertion block (anywhere after the `prompt=$(build_qa_prompt ...)` call and before `echo "PASS: build_qa_prompt"`):

```bash
echo "$prompt" | grep -q "Step C: notify Discord" || fail "STEP 2c's mint-new-entry branch must notify Discord after Step B, before the QA-table write"
echo "$prompt" | grep -q "non_niq_helper.py notify-discord" || fail "prompt must instruct calling the notify-discord command"
echo "$prompt" | grep -q -- "--identity-col sku_type " || fail "notify-discord call must use the resolved dict_identity_col"
echo "$prompt" | grep -q -- "--dataset babybath" || fail "notify-discord call must pass the dataset"
echo "$prompt" | grep -q "never fails the session even if Discord is unreachable" || fail "prompt must tell Claude this call is non-blocking, don't wait/retry"
```

Add to the "main() wiring" block near the end of the file (after the existing `script_src=$(cat script/non_niq/non_niq_qa.sh)` line, alongside the other `grep -qF ... <<< "$script_src"` checks):

```bash
grep -qF 'source "${REPO_ROOT}/script/load_env.sh"' <<< "$script_src" || fail "main() must source load_env.sh so DISCORD_WEBHOOK_URL (and other .env values) are available whether invoked directly or via the queue worker"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/non_niq/test_non_niq_qa.sh 2>&1 | tail -20`
Expected: FAIL on the new "Step C" and `load_env.sh` assertions.

- [ ] **Step 3: Implement**

In `build_qa_prompt()`, find:
```
      NO  -> two-step create in \`${PROJECT}.${dict_table}\`:
             Step A: insert brand + ${dict_identity_col} + keywords (+ ${dict_typo_col} if you
                     have common misspellings), _meta='claude_code' stamped here.
             Step B: populate the remaining attribute columns for this dict's schema, GROUNDED on
                     existing dict rows' actual vocabulary and formatting -- query
                     \`SELECT DISTINCT <column> FROM ${PROJECT}.${dict_table}\` per attribute column
                     before writing a new value, prefer an existing value over inventing one, and
                     match existing formatting exactly (e.g. "150 ml" not "150ml").
             Then write brand/${qa_identity_col} values pointing at the new entry to
             \`${PROJECT}.${qa_table}\`.
```
and replace it with:
```
      NO  -> two-step create in \`${PROJECT}.${dict_table}\`:
             Step A: insert brand + ${dict_identity_col} + keywords (+ ${dict_typo_col} if you
                     have common misspellings), _meta='claude_code' stamped here.
             Step B: populate the remaining attribute columns for this dict's schema, GROUNDED on
                     existing dict rows' actual vocabulary and formatting -- query
                     \`SELECT DISTINCT <column> FROM ${PROJECT}.${dict_table}\` per attribute column
                     before writing a new value, prefer an existing value over inventing one, and
                     match existing formatting exactly (e.g. "150 ml" not "150ml").
             Step C: notify Discord this entry was created -- run:
                     ${PYTHON_BIN} ${REPO_ROOT}/script/non_niq/non_niq_helper.py notify-discord \\
                       --project ${PROJECT} --dict-table ${dict_table} --brand "<brand you just wrote>" \\
                       --identity-col ${dict_identity_col} --identity-value "<${dict_identity_col} value you just wrote>" \\
                       --dataset ${dataset}
                     This reads the row back from BigQuery itself and posts to Discord -- it never
                     fails the session even if Discord is unreachable, so don't wait for or retry
                     it beyond running the command once.
             Then write brand/${qa_identity_col} values pointing at the new entry to
             \`${PROJECT}.${qa_table}\`.
```

In `main()`, find:
```bash
main() {
  if [[ $# -lt 2 ]]; then
```
and change to:
```bash
main() {
  source "${REPO_ROOT}/script/load_env.sh"
  if [[ $# -lt 2 ]]; then
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/non_niq/test_non_niq_qa.sh 2>&1 | tail -20`
Expected: `ALL TESTS PASSED (part 1: SQL builders)` and `ALL TESTS PASSED (part 2: prompt + main)`.

- [ ] **Step 5: Commit**

```bash
git add script/non_niq/non_niq_qa.sh tests/non_niq/test_non_niq_qa.sh
git commit -m "Wire notify-discord into STEP 2c's mint-new-entry branch, source load_env.sh in main()"
```

---

### Task 4: Human-readable final session result summary

**Files:**
- Modify: `script/non_niq/non_niq_qa.sh` (`decide_queue_signal()`, new `extract_result_json()` and `format_result_summary()`, `main()`)
- Test: `tests/non_niq/test_non_niq_qa.sh`

**Interfaces:**
- Consumes: `extract_json_object()` (already defined in this file).
- Produces:
  - `extract_result_json(claude_output: string) -> string` — returns the inner `.result` JSON (after regex-fallback extraction if Claude wrapped it in prose), or `""` if `.result` itself was empty/absent.
  - `format_result_summary(claude_output: string) -> string` (printed via heredoc, not returned as a variable in practice, but behaves as a function that prints to stdout when called).
  - `decide_queue_signal()`'s behavior is unchanged (verified equivalent to the pre-refactor version) -- it now calls `extract_result_json()` instead of duplicating the extraction logic.

- [ ] **Step 1: Write the failing tests**

Add to `tests/non_niq/test_non_niq_qa.sh`, right before the existing `# --- extract_json_object / decide_queue_signal ...` block:

```bash
# --- extract_result_json ---
[[ "$(extract_result_json '{"result":"{\"status\":\"complete\"}"}')" == '{"status":"complete"}' ]] || fail "extract_result_json should pull the inner result JSON out of the envelope"
[[ "$(extract_result_json '{"result":""}')" == "" ]] || fail "extract_result_json should return empty when .result itself is empty"
[[ "$(extract_result_json 'garbage')" == "" ]] || fail "extract_result_json should return empty when the whole envelope is unparseable"
echo "PASS: extract_result_json"
```

Add after the existing `echo "PASS: decide_queue_signal"` line:

```bash
# --- format_result_summary ---
# Fields verified against a real `claude -p --output-format json` call during design -- not guessed.
fake_envelope='{"result":"{\"status\":\"complete\",\"rows_qa_confirmed\":12,\"rows_qa_unconfident\":3,\"rows_filtered\":2,\"rows_created_in_dict\":1,\"findings\":\"all good\",\"blockers\":[]}","total_cost_usd":0.1284843,"num_turns":47,"duration_ms":182340,"modelUsage":{"claude-sonnet-5":{"costUSD":0.1284843,"inputTokens":2,"outputTokens":7,"cacheReadInputTokens":25151,"cacheCreationInputTokens":20138}}}'
summary=$(format_result_summary "$fake_envelope")
echo "$summary" | grep -q "Status: complete" || fail "format_result_summary must show the status"
echo "$summary" | grep -q "Confirmed: 12" || fail "format_result_summary must show rows_qa_confirmed"
echo "$summary" | grep -q "Unconfident: 3" || fail "format_result_summary must show rows_qa_unconfident"
echo "$summary" | grep -q "Filtered: 2" || fail "format_result_summary must show rows_filtered"
echo "$summary" | grep -q "Created: 1" || fail "format_result_summary must show rows_created_in_dict"
echo "$summary" | grep -q "Turns used: 47" || fail "format_result_summary must show num_turns from the envelope"
echo "$summary" | grep -q "Duration: 182340ms" || fail "format_result_summary must show duration_ms from the envelope"
echo "$summary" | grep -q "Total cost: \$0.1284843" || fail "format_result_summary must show total_cost_usd from the envelope"
echo "$summary" | grep -q "claude-sonnet-5: \$0.1284843" || fail "format_result_summary must show per-model cost from modelUsage"
echo "$summary" | grep -q "in: 2 tok, out: 7 tok" || fail "format_result_summary must show per-model token usage"
echo "$summary" | grep -q "all good" || fail "format_result_summary must show findings in full"
echo "$summary" | grep -q "(none)" || fail "format_result_summary must show (none) for an empty blockers array"

fake_envelope_with_blockers='{"result":"{\"status\":\"blocked\",\"rows_qa_confirmed\":0,\"rows_qa_unconfident\":0,\"rows_filtered\":0,\"rows_created_in_dict\":0,\"findings\":\"none yet\",\"blockers\":[\"missing dict table\",\"auth expired\"]}","total_cost_usd":0.02,"num_turns\":3,"duration_ms":5000,"modelUsage":{}}'
summary2=$(format_result_summary "$fake_envelope_with_blockers")
echo "$summary2" | grep -q "missing dict table" || fail "format_result_summary must list blockers in full when present"
echo "$summary2" | grep -q "auth expired" || fail "format_result_summary must list every blocker, not just the first"
echo "$summary2" | grep -q "no model usage reported" || fail "format_result_summary must handle an empty modelUsage object gracefully"
echo "PASS: format_result_summary"
```

Add to the existing "main() wiring" `script_src` assertion block:

```bash
grep -qF 'format_result_summary "$claude_output"' <<< "$script_src" || fail "main() must print the human-readable summary"
grep -qF 'echo "$claude_output"' <<< "$script_src" || fail "main() must still echo the raw envelope -- the summary is additive, not a replacement"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/non_niq/test_non_niq_qa.sh 2>&1 | tail -30`
Expected: FAIL — `extract_result_json`/`format_result_summary` not defined.

- [ ] **Step 3: Implement**

Replace the existing `decide_queue_signal()` function with this (adds `extract_result_json()` above it, refactors `decide_queue_signal()` to use it -- behaviorally identical to the original, verified: both return `FAILED` whenever `.result` is empty or unparseable, `BLOCKED`/`DONE` otherwise):

```bash
# Shared by decide_queue_signal and format_result_summary -- both need Claude's own inner result
# JSON (the {status, rows_qa_confirmed, ...} object the prompt's output contract specifies), not
# the outer claude -p envelope. Claude's .result field is USUALLY that JSON directly, but
# sometimes wraps it in prose -- extract_json_object is the regex fallback for that case.
extract_result_json() {
  local claude_output="$1"
  local result_json
  result_json=$(echo "$claude_output" | jq -r '.result // empty' 2>/dev/null) || result_json=""
  if [[ -z "$result_json" ]]; then
    echo ""
    return
  fi
  if ! echo "$result_json" | jq -e . >/dev/null 2>&1; then
    local extracted
    extracted=$(extract_json_object "$result_json")
    if [[ -n "$extracted" ]] && echo "$extracted" | jq -e . >/dev/null 2>&1; then
      result_json="$extracted"
    fi
  fi
  echo "$result_json"
}

decide_queue_signal() {
  local claude_output="$1"
  local result_json
  result_json=$(extract_result_json "$claude_output")
  if [[ -z "$result_json" ]]; then
    echo "FAILED"
    return
  fi
  local status
  status=$(echo "$result_json" | jq -r '.status // empty' 2>/dev/null) || status=""
  case "$status" in
    blocked) echo "BLOCKED" ;;
    complete|partial) echo "DONE" ;;
    *) echo "FAILED" ;;
  esac
}

# Reads BOTH layers: the outer claude -p envelope (total_cost_usd, modelUsage, num_turns,
# duration_ms -- confirmed live via a real `claude -p --output-format json` call) and the inner
# result JSON (status, rows_*, findings, blockers) via the same extract_result_json used by
# decide_queue_signal. Printed alongside the raw claude_output echo in main(), never replacing it.
format_result_summary() {
  local claude_output="$1"
  local result_json
  result_json=$(extract_result_json "$claude_output")

  local status rows_confirmed rows_unconfident rows_filtered rows_created findings blockers
  status=$(echo "$result_json" | jq -r '.status // "unknown"' 2>/dev/null) || status="unknown"
  rows_confirmed=$(echo "$result_json" | jq -r '.rows_qa_confirmed // "?"' 2>/dev/null) || rows_confirmed="?"
  rows_unconfident=$(echo "$result_json" | jq -r '.rows_qa_unconfident // "?"' 2>/dev/null) || rows_unconfident="?"
  rows_filtered=$(echo "$result_json" | jq -r '.rows_filtered // "?"' 2>/dev/null) || rows_filtered="?"
  rows_created=$(echo "$result_json" | jq -r '.rows_created_in_dict // "?"' 2>/dev/null) || rows_created="?"
  findings=$(echo "$result_json" | jq -r '
    if .findings == null then "(none)"
    elif (.findings | type) == "array" then (.findings | join("\n"))
    else (.findings | tostring) end' 2>/dev/null) || findings="(unparseable)"
  blockers=$(echo "$result_json" | jq -r '
    if .blockers == null or (.blockers | length) == 0 then "(none)"
    elif (.blockers | type) == "array" then (.blockers | join("\n"))
    else (.blockers | tostring) end' 2>/dev/null) || blockers="(unparseable)"

  local num_turns duration_ms total_cost
  num_turns=$(echo "$claude_output" | jq -r '.num_turns // "?"' 2>/dev/null) || num_turns="?"
  duration_ms=$(echo "$claude_output" | jq -r '.duration_ms // "?"' 2>/dev/null) || duration_ms="?"
  total_cost=$(echo "$claude_output" | jq -r '.total_cost_usd // "?"' 2>/dev/null) || total_cost="?"

  local per_model
  per_model=$(echo "$claude_output" | jq -r '
    (.modelUsage // {}) | to_entries[] |
    "  \(.key): $\(.value.costUSD) (in: \(.value.inputTokens) tok, out: \(.value.outputTokens) tok, cache_read: \(.value.cacheReadInputTokens) tok, cache_creation: \(.value.cacheCreationInputTokens) tok)"
  ' 2>/dev/null) || per_model=""
  [[ -z "$per_model" ]] && per_model="  (no model usage reported)"

  cat <<SUMMARY

=== QA Session Result ===
Status: ${status}
Confirmed: ${rows_confirmed} | Unconfident: ${rows_unconfident} | Filtered: ${rows_filtered} | Created: ${rows_created}

Turns used: ${num_turns} | Duration: ${duration_ms}ms | Total cost: \$${total_cost}

Per-model cost:
${per_model}

Findings:
${findings}

Blockers:
${blockers}
SUMMARY
}
```

In `main()`, find:
```bash
  local claude_output
  claude_output=$(claude -p --output-format json --permission-mode bypassPermissions --max-turns "$max_turns" "$prompt") || true
  echo "$claude_output"

  echo "QUEUE_SIGNAL: $(decide_queue_signal "$claude_output")"
```
and change to:
```bash
  local claude_output
  claude_output=$(claude -p --output-format json --permission-mode bypassPermissions --max-turns "$max_turns" "$prompt") || true
  echo "$claude_output"
  format_result_summary "$claude_output"

  echo "QUEUE_SIGNAL: $(decide_queue_signal "$claude_output")"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/non_niq/test_non_niq_qa.sh 2>&1 | tail -40`
Expected: `ALL TESTS PASSED (part 1: SQL builders)` and `ALL TESTS PASSED (part 2: prompt + main)`.

- [ ] **Step 5: Commit**

```bash
git add script/non_niq/non_niq_qa.sh tests/non_niq/test_non_niq_qa.sh
git commit -m "Add human-readable QA session summary (status, counts, turns, cost, per-model cost)"
```

---

## Self-Review

**Spec coverage:** Improvement 1 (enrichment JOIN, Shopee-only, NULL fallback, prompt mention) → Task 1 ✓. Improvement 2 (Discord notify: Python read-back, code-fenced table, `**AI QA**` header, 2000-char truncation, non-fatal, `.env.example`/`load_env.sh` secret handling, wired after Step B before the QA-table write) → Tasks 2+3 ✓. Improvement 3 (`extract_result_json` shared helper, `format_result_summary` with envelope + inner-result fields, printed alongside not instead of the raw echo) → Task 4 ✓.

**Placeholder scan:** no TBD/TODO; every code block is complete, runnable code. The pre-existing `SAMPLE_CSV` fixture bug (Task 1, Step 1) is fixed with a programmatically-verified replacement, not patched around.

**Type consistency:** `worklist_query()`'s new 6th parameter (`enrichment_table`, optional, `${6:-}"`) is used consistently in Task 1's implementation and its `main()` call site (Task 1) — Tasks 3 and 4 don't touch this call site again. `notify_discord_new_entry`'s parameter order and names (`project, dict_table, brand, identity_col, identity_value, dataset, client=None, webhook_url=None, post=None`) match between Task 2's implementation, its tests, and Task 3's prompt-text CLI invocation (`--project`, `--dict-table`, `--brand`, `--identity-col`, `--identity-value`, `--dataset` — same six, same order of concepts even though CLI flags are named args not positional). `extract_result_json`'s signature and empty-string-on-failure contract is used identically by both `decide_queue_signal` (Task 4, refactored) and `format_result_summary` (Task 4, new) — no divergence.
