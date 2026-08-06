# Non-NIQ Agentic QA (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `script/non_niq/` — a config-Sheet-driven agentic QA harness that replaces human QA for the Non-NIQ pipeline (issue #2), using Meilisearch hybrid retrieval for brand/sku_type grounding instead of the POC's brute keyword matching.

**Architecture:** A bash wrapper (`non_niq_qa.sh`, following `headless_taxonomy.sh`'s proven shape) computes worklist scope deterministically via BigQuery, builds one large prompt embedding the decision tree from issue #2, and hands it to `claude -p`. The spawned Claude subprocess does the actual multimodal reasoning and BigQuery writes itself, using two Python CLI helpers (`non_niq_sheet.py` for config/column resolution, `non_niq_embed.py` for batch embedding) and `curl` against Meilisearch directly. A separate queue worker (`non_niq_queue_worker.sh`) runs the harness on Hetzner via the existing shared `task_queue` table, on its own `script_type` lane.

**Tech Stack:** Bash, Python 3 (`google-cloud-bigquery`, `sentence-transformers` — both already repo dependencies), BigQuery, Meilisearch REST API (`http://34.124.146.29:7700`, `vectorStore` now enabled), Postgres (`p4ct2g2urhzcfnz.task_queue` via `queue_psql`), Windmill (script deployment only, no scheduling).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-06-non-niq-agentic-qa-design.md` — every task implements a section of it; deviate only if this plan says so explicitly.
- `PROJECT = "sincere-hearth-273704"`, `MEILI_URL = "http://34.124.146.29:7700"` — no API key required (verified live: writes and hybrid search both work unauthenticated).
- `MODEL_NAME = "intfloat/multilingual-e5-large"` via `sentence-transformers` — same model as `script/embedding_worker.py`, already in `requirements.txt`.
- `table_name` in `task_queue` is encoded as **`{dataset}:{platform}`** (e.g. `babybath:shopee`) for every non_niq row — this exact format is shared by `queue_ctl.sh submit`, `non_niq_queue_worker.sh`'s claim/split logic, and `non_niq_qa.sh`'s argument parsing. Never deviate from this format in any task.
- **Every read of a `_meta` column in SQL uses `SAFE.JSON_VALUE`, never bare `JSON_VALUE`** — `_meta` is not always valid JSON in production (empty strings, literal `"nan"` both observed live); bare `JSON_VALUE` raises on malformed input in BigQuery.
- **All BigQuery writes use `bq query` DML, never the Streaming API** — CLAUDE.md's 90-minute streaming-buffer rule. This project's retry-cap logic depends on reliably reading back a just-written QA row on the very next run.
- Dict/QA-table column names (`sku_type` vs `sku_type_complete`, `prod_id` vs `product_id`, `keywords_typo` vs `keyword_typo`) are **resolved live per dataset** via `INFORMATION_SCHEMA.COLUMNS`, never hardcoded — see Task 1.
- Every row this project writes (`product_id_dict_qa`, `{dataset}_dict`, filter tables) stamps `_meta` per the JSON shapes in the spec's "Confidence loop" section — never leave `_meta` NULL on a written row.
- `script/non_niq/` is the only directory this plan touches. Every existing file (`script/headless_taxonomy.sh`, `script/queue_worker.sh`, `script/embedding_worker.py`, etc.) stays exactly where it is and is never modified.

---

## File Structure

```
script/non_niq/
  non_niq_sheet.py           # Task 1: config Sheet CSV reader + per-category column resolution
  non_niq_embed.py           # Task 2: Meilisearch sync (Windmill main()) + batch query-embedding CLI
  non_niq_queue_worker.sh    # Task 3: queue lane, claims script_type='non_niq_qa' from shared task_queue
  non_niq_qa.sh              # Task 4 + Task 5: worklist/scope SQL, decision-tree prompt, main()
  test_non_niq_sheet.py      # Task 1
  test_non_niq_embed.py      # Task 2
  test_non_niq_queue_worker.sh  # Task 3
  test_non_niq_qa.sh         # Task 4 + Task 5
```

---

### Task 1: `non_niq_sheet.py` — config Sheet reader + column resolution

**Files:**
- Create: `script/non_niq/non_niq_sheet.py`
- Test: `script/non_niq/test_non_niq_sheet.py`

**Interfaces:**
- Consumes: nothing from other tasks (first task).
- Produces:
  - `parse_categories(csv_text: str, country: str = "ID", target_categories: list[str] | None = None) -> list[dict]` — each dict has keys `category, dataset, ecommerce_platform, table, product_id_dict_qa, product_id_dict, dict, filter_table`.
  - `pick_column(existing_columns: set[str], candidates: list[str], field_label: str) -> str` — raises `ValueError` if none of `candidates` is in `existing_columns`.
  - `resolve_category_columns(client, project: str, qa_table: str, dict_table: str) -> dict` — returns `{"qa_pk_col": str, "dict_identity_col": str, "dict_typo_col": str}`.
  - `QA_PK_CANDIDATES = ["product_id", "prod_id"]`, `DICT_IDENTITY_CANDIDATES = ["sku_type_complete", "sku_type"]`, `DICT_TYPO_CANDIDATES = ["keywords_typo", "keyword_typo"]` (module-level constants, used by later tasks' code/tests too).
  - CLI: `python3 non_niq_sheet.py categories [--country ID] [--categories "Baby Bath & Shampoo,Facial Serum"]` → prints the resolved category list as JSON to stdout.
  - CLI: `python3 non_niq_sheet.py columns --project P --qa-table dataset.qa --dict-table dataset.dict` → prints `resolve_category_columns` output as JSON to stdout.

- [ ] **Step 1: Write the failing tests for `parse_categories`**

```python
# script/non_niq/test_non_niq_sheet.py
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from non_niq_sheet import parse_categories, pick_column, QA_PK_CANDIDATES, DICT_IDENTITY_CANDIDATES, DICT_TYPO_CANDIDATES

SAMPLE_CSV = """country,category_1,category_2,category,dataset,is_active,ecommerce_platform,raw_table,children,filter_column,filter_value,,0,exclude_tiktok,variant,filter_variant,phasing,1,2-1,2-2,2-3,5,9,double_date,is_daily,10,9_table,table,master_table_prod,product_id_dict_qa,product_id_dict,product_id_dict_image_qa,product_id_image_taxonomy,dict,filter_table,sku_type_complete,PIC,isDoubleDate,keywords,taxonomy_url ,taxonomy_spreadsheet_id, taxonomy_sheet_name,labelling_config,last_active_month,qa_ai_labelling
ID,Mom & Baby,Baby Care,Baby Bath & Shampoo,babybath,TRUE,shopee,babybath.raw_babybath_shopee,,,,,,,,,,,,,,,,,,,,master_babybath_id_dev,babybath.9_babybath_id,babybath.master_babybath_id,babybath.product_id_dict_qa,babybath.product_id_dict,-,-,babybath.babybath_dict,babybath.filter_babybath,sku_type_complete,David,-,,,,,,,
ID,Mom & Baby,Baby Care,Baby Bath & Shampoo,babybath,FALSE,lazada,babybath.raw_babybath_lazada,,,,,,,,,,,,,,,,,,,,master_babybath_id_dev,babybath.9_babybath_id,babybath.master_babybath_id,babybath.product_id_dict_qa,babybath.product_id_dict,-,-,babybath.babybath_dict,babybath.filter_babybath,sku_type_complete,David,-,,,,,,,
US,Mom & Baby,Baby Care,Baby Bath & Shampoo,babybath,TRUE,shopee,babybath.raw_babybath_shopee_us,,,,,,,,,,,,,,,,,,,,master_babybath_us_dev,babybath.9_babybath_us,babybath.master_babybath_us,babybath.product_id_dict_qa,babybath.product_id_dict,-,-,babybath.babybath_dict,babybath.filter_babybath,sku_type_complete,David,-,,,,,,,
ID,Beauty,Skincare,Facial Serum,facialserum,TRUE,shopee,facialserum.raw_facialserum_shopee,,,,,,,,,,,,,,,,,,,,master_facialserum_id_dev,facialserum.9_facialserum_id,facialserum.master_facialserum_id,facialserum.product_id_dict_qa,-,-,-,facialserum.facialserum_dict,facialserum.filter_facialserum,sku_type_complete,David,-,,,,,,,
"""

def test_filters_to_active_id_rows_only():
    rows = parse_categories(SAMPLE_CSV, country="ID")
    # excludes the FALSE is_active row and the US row; keeps the two active ID rows
    assert len(rows) == 2
    assert all(r["country"] if "country" in r else True for r in rows)  # country not carried in output dict

def test_row_shape():
    rows = parse_categories(SAMPLE_CSV, country="ID")
    babybath = next(r for r in rows if r["dataset"] == "babybath")
    assert babybath["category"] == "Baby Bath & Shampoo"
    assert babybath["ecommerce_platform"] == "shopee"
    assert babybath["product_id_dict_qa"] == "babybath.product_id_dict_qa"
    assert babybath["product_id_dict"] == "babybath.product_id_dict"
    assert babybath["dict"] == "babybath.babybath_dict"
    assert babybath["filter_table"] == "babybath.filter_babybath"

def test_dash_means_not_configured():
    rows = parse_categories(SAMPLE_CSV, country="ID")
    facialserum = next(r for r in rows if r["dataset"] == "facialserum")
    assert facialserum["product_id_dict"] == "-"

def test_target_categories_filter():
    rows = parse_categories(SAMPLE_CSV, country="ID", target_categories=["Facial Serum"])
    assert len(rows) == 1
    assert rows[0]["dataset"] == "facialserum"

def test_pick_column_first_match_wins():
    assert pick_column({"product_id", "sku_name"}, QA_PK_CANDIDATES, "qa pk") == "product_id"
    assert pick_column({"prod_id", "sku_name"}, QA_PK_CANDIDATES, "qa pk") == "prod_id"

def test_pick_column_raises_when_no_candidate_present():
    try:
        pick_column({"totally_different_col"}, QA_PK_CANDIDATES, "qa pk")
        assert False, "should have raised"
    except ValueError as e:
        assert "qa pk" in str(e)

def test_dict_identity_candidates_prefer_complete():
    assert pick_column({"sku_type", "sku_type_complete"}, DICT_IDENTITY_CANDIDATES, "dict identity") == "sku_type_complete"
    assert pick_column({"sku_type"}, DICT_IDENTITY_CANDIDATES, "dict identity") == "sku_type"

def test_dict_typo_candidates():
    assert pick_column({"keyword_typo"}, DICT_TYPO_CANDIDATES, "dict typo") == "keyword_typo"
    assert pick_column({"keywords_typo"}, DICT_TYPO_CANDIDATES, "dict typo") == "keywords_typo"

def test_cli_categories_prints_json():
    # exercises the CLI wrapper against a local sample file, no network
    import tempfile, os
    with tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False) as f:
        f.write(SAMPLE_CSV)
        path = f.name
    try:
        out = subprocess.run(
            [sys.executable, str(Path(__file__).parent / "non_niq_sheet.py"), "categories",
             "--country", "ID", "--csv-file", path],
            capture_output=True, text=True, check=True,
        )
        rows = json.loads(out.stdout)
        assert len(rows) == 2
    finally:
        os.unlink(path)

if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print(f"PASS: {name}")
    print("ALL TESTS PASSED")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 script/non_niq/test_non_niq_sheet.py`
Expected: `ModuleNotFoundError: No module named 'non_niq_sheet'` (file doesn't exist yet)

- [ ] **Step 3: Write `non_niq_sheet.py`**

```python
#!/usr/bin/env python3
"""Config Sheet reader and per-category column resolver for the Non-NIQ QA harness.

Reads the pipeline config Sheet (published CSV export, read-only -- this project never writes
back to the Sheet itself) to resolve which BQ tables belong to which category, and resolves the
handful of column names that genuinely vary per category's dict/QA table schema (sku_type vs
sku_type_complete, prod_id vs product_id, keywords_typo vs keyword_typo) live via
INFORMATION_SCHEMA.COLUMNS rather than hardcoding a static, already-stale mapping.

CLI:
  python3 non_niq_sheet.py categories [--country ID] [--categories "Baby Bath & Shampoo,..."] [--csv-file PATH]
  python3 non_niq_sheet.py columns --project P --qa-table dataset.qa_table --dict-table dataset.dict_table
"""
import argparse
import csv
import io
import json
import sys
import urllib.request

CONFIG_CSV_URL = (
    "https://docs.google.com/spreadsheets/d/e/2PACX-1vQfqTVdo1ubO40dBBGzECaXVruIefLZpfX6KSFVHzY2gXv2dE-VHDofMC2Q_1tY5LwOmYJPG0kwwxN4"
    "/pub?gid=149787162&single=true&output=csv"
)

ROW_FIELDS = ["category", "dataset", "ecommerce_platform", "table", "product_id_dict_qa",
              "product_id_dict", "dict", "filter_table"]

QA_PK_CANDIDATES = ["product_id", "prod_id"]
DICT_IDENTITY_CANDIDATES = ["sku_type_complete", "sku_type"]
DICT_TYPO_CANDIDATES = ["keywords_typo", "keyword_typo"]


def fetch_config_csv(url=CONFIG_CSV_URL):
    with urllib.request.urlopen(url, timeout=30) as resp:
        return resp.read().decode("utf-8")


def parse_categories(csv_text, country="ID", target_categories=None):
    target_lower = {c.strip().lower() for c in target_categories} if target_categories else None
    seen = set()
    out = []
    reader = csv.DictReader(io.StringIO(csv_text))
    for row in reader:
        if row.get("country", "").strip() != country:
            continue
        if row.get("is_active", "").strip().upper() != "TRUE":
            continue
        category = row.get("category", "").strip()
        if target_lower is not None and category.lower() not in target_lower:
            continue
        dataset = row.get("dataset", "").strip()
        platform = row.get("ecommerce_platform", "").strip()
        key = (dataset, platform)
        if key in seen:
            continue
        seen.add(key)
        out.append({field: row.get(field, "").strip() for field in ROW_FIELDS})
    return out


def pick_column(existing_columns, candidates, field_label):
    for c in candidates:
        if c in existing_columns:
            return c
    raise ValueError(f"None of {candidates} found for {field_label} (have: {sorted(existing_columns)})")


def _table_columns(client, project, dataset_dot_table):
    dataset, table = dataset_dot_table.split(".", 1)
    query = f"""
        SELECT column_name FROM `{project}.{dataset}.INFORMATION_SCHEMA.COLUMNS`
        WHERE table_name = @table
    """
    from google.cloud import bigquery
    job_config = bigquery.QueryJobConfig(
        query_parameters=[bigquery.ScalarQueryParameter("table", "STRING", table)]
    )
    return {r.column_name for r in client.query(query, job_config=job_config).result()}


def resolve_category_columns(client, project, qa_table, dict_table):
    qa_cols = _table_columns(client, project, qa_table)
    dict_cols = _table_columns(client, project, dict_table)
    return {
        "qa_pk_col": pick_column(qa_cols, QA_PK_CANDIDATES, f"{qa_table} primary key"),
        "dict_identity_col": pick_column(dict_cols, DICT_IDENTITY_CANDIDATES, f"{dict_table} identity"),
        "dict_typo_col": pick_column(dict_cols, DICT_TYPO_CANDIDATES, f"{dict_table} typo"),
    }


def _cmd_categories(args):
    csv_text = open(args.csv_file).read() if args.csv_file else fetch_config_csv()
    targets = [c.strip() for c in args.categories.split(",")] if args.categories else None
    rows = parse_categories(csv_text, country=args.country, target_categories=targets)
    print(json.dumps(rows))


def _cmd_columns(args):
    from google.cloud import bigquery
    client = bigquery.Client(project=args.project)
    result = resolve_category_columns(client, args.project, args.qa_table, args.dict_table)
    print(json.dumps(result))


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    cat_p = sub.add_parser("categories")
    cat_p.add_argument("--country", default="ID")
    cat_p.add_argument("--categories", default=None)
    cat_p.add_argument("--csv-file", default=None)

    col_p = sub.add_parser("columns")
    col_p.add_argument("--project", required=True)
    col_p.add_argument("--qa-table", required=True)
    col_p.add_argument("--dict-table", required=True)

    args = parser.parse_args()
    if args.command == "categories":
        _cmd_categories(args)
    elif args.command == "columns":
        _cmd_columns(args)


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 script/non_niq/test_non_niq_sheet.py`
Expected: `ALL TESTS PASSED`

- [ ] **Step 5: Commit**

```bash
git add script/non_niq/non_niq_sheet.py script/non_niq/test_non_niq_sheet.py
git commit -m "Add non_niq_sheet.py: config Sheet reader + per-category column resolution"
```

---

### Task 2: `non_niq_embed.py` — Meilisearch sync + batch query embedding

**Files:**
- Create: `script/non_niq/non_niq_embed.py`
- Test: `script/non_niq/test_non_niq_embed.py`

**Interfaces:**
- Consumes: `non_niq_sheet.parse_categories`, `non_niq_sheet.QA_PK_CANDIDATES` (imports `non_niq_sheet` — same directory).
- Produces:
  - `is_confirmed(meta_raw: str) -> bool` — pure, no I/O.
  - `ensure_index(meili_url: str, index_uid: str)` — idempotent: creates the index (if missing) with `primaryKey="product_id"`, sets `searchableAttributes=["sku_name","sku_type_complete","brand"]` and `embedders={"default":{"source":"userProvided","dimensions":1024}}` (multilingual-e5-large's output dimension).
  - `sync_category(client, meili_url, project, dataset, qa_table, model) -> int` — returns count synced.
  - `main(mode: str = "sync", dataset: str | None = None)` — Windmill entrypoint.
  - CLI: `python3 non_niq_embed.py sync [--dataset D]`, `python3 non_niq_embed.py embed-query --input-file IN.jsonl --output-file OUT.jsonl` (batch: one line `{"id":"...","text":"..."}` in, one line `{"id":"...","embedding":[...]}` out, per input line).

- [ ] **Step 1: Write the failing tests**

```python
# script/non_niq/test_non_niq_embed.py
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from non_niq_embed import is_confirmed

def test_confirmed_when_meta_is_labeling_source():
    assert is_confirmed('{"source": "labeling"}') is True

def test_confirmed_when_meta_is_human_qa():
    assert is_confirmed('{"name":"Aditya","email":"a@b.com","role":"ANALYST","timestamp":"2025-10-13T16:09:31.747Z"}') is True

def test_confirmed_when_meta_empty():
    assert is_confirmed("") is True  # legacy empty _meta rows are still confirmed human/original data

def test_confirmed_when_meta_is_nan_literal():
    assert is_confirmed("nan") is True  # malformed legacy value, not one of ours -- treat as confirmed, not excluded

def test_unconfident_agent_row_excluded():
    assert is_confirmed('{"source":"claude_code","qa_confidence":"unconfident","human_review":false}') is False

def test_confident_agent_row_confirmed():
    assert is_confirmed('{"source":"claude_code","qa_confidence":"confident"}') is True

def test_unconfident_terminal_human_review_still_excluded():
    assert is_confirmed('{"source":"claude_code","qa_confidence":"unconfident","human_review":true}') is False

if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print(f"PASS: {name}")
    print("ALL TESTS PASSED")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 script/non_niq/test_non_niq_embed.py`
Expected: `ModuleNotFoundError: No module named 'non_niq_embed'`

- [ ] **Step 3: Write `non_niq_embed.py`**

```python
#!/usr/bin/env python3
"""Meilisearch sync + batch query-embedding for the Non-NIQ QA harness.

Two responsibilities in one file (kept together deliberately -- both need the same model-loading
code, and splitting them means loading multilingual-e5-large twice for what is otherwise one
concern: "turn text into a vector, get it into or out of Meilisearch"):

1. main() / `sync` -- Windmill-deployable batch job. For each active category (or one, via
   --dataset), reads product_id_dict_qa, keeps only CONFIRMED rows (excludes our own agent's
   unconfident guesses -- see is_confirmed), embeds sku_name, upserts into the category's
   `{dataset}_taxonomy_qa` Meilisearch index as userProvided vectors. Manual trigger only, no
   schedule -- run on demand from Windmill's UI or `python3 non_niq_embed.py sync`.

2. `embed-query` CLI -- called by non_niq_qa.sh's Claude subprocess to embed a whole worklist
   batch's sku_names in ONE process invocation (not one call per product -- a fresh process per
   product would mean a ~2GB model cold-load per product).

Runs on the Hetzner box (embedding compute must not run on a laptop -- see design spec).
"""
import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from non_niq_sheet import parse_categories, fetch_config_csv, QA_PK_CANDIDATES, pick_column

PROJECT = "sincere-hearth-273704"
MEILI_URL = "http://34.124.146.29:7700"
MODEL_NAME = "intfloat/multilingual-e5-large"
EMBED_DIM = 1024
BATCH_SIZE = 256


def is_confirmed(meta_raw):
    """True unless _meta explicitly marks this as OUR agent's unconfident guess. Empty/malformed
    (legacy) _meta values are treated as confirmed -- they predate this project and are exactly
    the human/original exemplar data the RAG corpus should include."""
    if not meta_raw:
        return True
    try:
        meta = json.loads(meta_raw)
    except (json.JSONDecodeError, TypeError):
        return True
    if not isinstance(meta, dict):
        return True
    return meta.get("qa_confidence") != "unconfident"


def _meili_request(method, path, body=None):
    url = f"{MEILI_URL}{path}"
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                  headers={"Content-Type": "application/json"} if data else {})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8") or "{}")
    except urllib.error.HTTPError as e:
        body_text = e.read().decode("utf-8")
        raise RuntimeError(f"Meilisearch {method} {path} failed: {e.code} {body_text}") from e


def ensure_index(meili_url, index_uid):
    global MEILI_URL
    MEILI_URL = meili_url
    existing = _meili_request("GET", "/indexes?limit=200")
    uids = {r["uid"] for r in existing.get("results", [])}
    if index_uid not in uids:
        _meili_request("POST", "/indexes", {"uid": index_uid, "primaryKey": "product_id"})
    _meili_request("PATCH", f"/indexes/{index_uid}/settings", {
        "searchableAttributes": ["sku_name", "sku_type_complete", "brand"],
        "embedders": {"default": {"source": "userProvided", "dimensions": EMBED_DIM}},
    })


def _load_model():
    from sentence_transformers import SentenceTransformer
    return SentenceTransformer(MODEL_NAME)


def sync_category(client, meili_url, project, dataset, qa_table, model):
    qa_cols = {f.name for f in client.get_table(f"{project}.{qa_table}").schema}
    pk_col = pick_column(qa_cols, QA_PK_CANDIDATES, f"{qa_table} primary key")

    query = f"""
        SELECT {pk_col} AS product_id, sku_name, sku_type_complete, brand, _meta
        FROM `{project}.{qa_table}`
        WHERE sku_name IS NOT NULL AND brand IS NOT NULL
    """
    rows = [r for r in client.query(query).result() if is_confirmed(r._meta)]
    if not rows:
        return 0

    index_uid = f"{dataset}_taxonomy_qa"
    ensure_index(meili_url, index_uid)

    texts = [f"query: {r.sku_name}" for r in rows]
    vectors = model.encode(texts, batch_size=BATCH_SIZE, show_progress_bar=False, normalize_embeddings=True)

    docs = [
        {
            "product_id": str(r.product_id),
            "sku_name": r.sku_name,
            "sku_type_complete": r.sku_type_complete,
            "brand": r.brand,
            "_vectors": {"default": vec.tolist()},
        }
        for r, vec in zip(rows, vectors)
    ]
    _meili_request("POST", f"/indexes/{index_uid}/documents", docs)
    return len(docs)


def embed_query_file(input_path, output_path, model=None):
    model = model or _load_model()
    lines = [json.loads(l) for l in Path(input_path).read_text().splitlines() if l.strip()]
    texts = [f"query: {l['text']}" for l in lines]
    vectors = model.encode(texts, batch_size=BATCH_SIZE, show_progress_bar=False, normalize_embeddings=True)
    with open(output_path, "w") as f:
        for line, vec in zip(lines, vectors):
            f.write(json.dumps({"id": line["id"], "embedding": vec.tolist()}) + "\n")


def main(mode="sync", dataset=None):
    """Windmill entrypoint."""
    from google.cloud import bigquery
    client = bigquery.Client(project=PROJECT)
    model = _load_model()

    categories = parse_categories(fetch_config_csv(), country="ID")
    if dataset:
        categories = [c for c in categories if c["dataset"] == dataset]

    seen_datasets = set()
    total = 0
    for cat in categories:
        ds = cat["dataset"]
        qa_table = cat["product_id_dict_qa"]
        if ds in seen_datasets or qa_table == "-":
            continue
        seen_datasets.add(ds)
        n = sync_category(client, MEILI_URL, PROJECT, ds, qa_table, model)
        print(f"{ds}: synced {n} rows")
        total += n
    print(f"Total synced: {total}")
    return total


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    sync_p = sub.add_parser("sync")
    sync_p.add_argument("--dataset", default=None)

    eq_p = sub.add_parser("embed-query")
    eq_p.add_argument("--input-file", required=True)
    eq_p.add_argument("--output-file", required=True)

    args = parser.parse_args()
    if args.command == "sync":
        main(mode="sync", dataset=args.dataset)
    elif args.command == "embed-query":
        embed_query_file(args.input_file, args.output_file)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 script/non_niq/test_non_niq_embed.py`
Expected: `ALL TESTS PASSED`

- [ ] **Step 5: Commit**

```bash
git add script/non_niq/non_niq_embed.py script/non_niq/test_non_niq_embed.py
git commit -m "Add non_niq_embed.py: Meilisearch sync + batch query embedding, Windmill-format"
```

---

### Task 3: `non_niq_queue_worker.sh` — queue lane

**Files:**
- Create: `script/non_niq/non_niq_queue_worker.sh`
- Test: `script/non_niq/test_non_niq_queue_worker.sh`

**Interfaces:**
- Consumes: `script/load_env.sh` (sourced, unmodified, for `QUEUE_DATABASE_URL`/`queue_psql`); `p4ct2g2urhzcfnz.task_queue` schema (unmodified).
- Produces: a running worker process; no functions consumed by later tasks except that `non_niq_qa.sh` (Task 4/5) is invoked by this worker with two positional args `<dataset> <platform>` (split from `table_name` on `:`).

- [ ] **Step 1: Write the failing tests**

```bash
#!/usr/bin/env bash
set -euo pipefail
# Self-test for script/non_niq/non_niq_queue_worker.sh's pure helper functions.
# No network, Postgres, or claude calls -- mirrors script/test_queue_worker.sh's convention.
# Run: bash script/non_niq/test_non_niq_queue_worker.sh

cd "$(dirname "$0")/../.."
source script/non_niq/non_niq_queue_worker.sh

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- split_table_name ---
read -r ds pl <<< "$(split_table_name "babybath:shopee")"
[[ "$ds" == "babybath" && "$pl" == "shopee" ]] || fail "split_table_name should split dataset:platform on the colon"
echo "PASS: split_table_name"

# --- reclaim query is script_type-scoped ---
q="$(reclaim_stale_leases_query)"
echo "$q" | grep -q "script_type" || fail "reclaim query must be scoped to script_type -- an unscoped reclaim can un-claim a still-running NIQ row"
echo "$q" | grep -q "non_niq_qa" || fail "reclaim query must scope specifically to script_type='non_niq_qa'"
echo "PASS: reclaim_stale_leases_query is script_type-scoped"

# --- claim query is script_type-scoped ---
q="$(claim_next_task_query "test-worker-1")"
echo "$q" | grep -q "script_type='non_niq_qa'" || fail "claim query must only claim non_niq_qa rows, never NIQ rows"
echo "PASS: claim_next_task_query is script_type-scoped"

echo "ALL TESTS PASSED"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash script/non_niq/test_non_niq_queue_worker.sh`
Expected: `non_niq_queue_worker.sh: No such file or directory`

- [ ] **Step 3: Write `non_niq_queue_worker.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Separate polling loop from script/queue_worker.sh -- claims only script_type='non_niq_qa' rows
# from the SAME shared p4ct2g2urhzcfnz.task_queue Postgres table. table_name is encoded as
# "{dataset}:{platform}" for every row this worker claims (e.g. "babybath:shopee") -- see the
# Global Constraints in docs/superpowers/plans/2026-08-06-non-niq-agentic-qa.md.
#
# Usage: script/non_niq/non_niq_queue_worker.sh
# Requires QUEUE_DATABASE_URL (see script/load_env.sh / .env.example).

QUEUE_TABLE="${QUEUE_SCHEMA:-public}.task_queue"

split_table_name() {
  local table_name="$1"
  local dataset="${table_name%%:*}"
  local platform="${table_name#*:}"
  echo "${dataset} ${platform}"
}

parse_queue_signal() {
  local output="$1"
  grep -o 'QUEUE_SIGNAL: [A-Z_]*' <<< "$output" | tail -1 | awk '{print $2}'
}

is_duplicate_key_error() {
  [[ "$1" == *"duplicate key value violates unique constraint"* ]] && echo "true" || echo "false"
}

queue_signal_to_status() {
  case "$1" in
    NOTHING_TO_DO|DONE) echo "done" ;;
    BLOCKED) echo "blocked" ;;
    *) echo "failed" ;;
  esac
}

should_stop_looping() {
  case "$1" in
    DONE) echo "false" ;;
    *) echo "true" ;;
  esac
}

# Scoped to script_type='non_niq_qa' -- an unscoped version (like NIQ's own queue_worker.sh, which
# is intentionally left as-is per this plan's Global Constraints) would reset a still-running NIQ
# row back to 'queued' if that row's lease happened to look stale, defeating
# one_running_task_per_table and risking two concurrent NIQ sessions on the same table mid
# SKU-block-allocation.
reclaim_stale_leases_query() {
  echo "UPDATE ${QUEUE_TABLE} SET status='queued', claimed_by=NULL, claimed_at=NULL
    WHERE status='running' AND script_type='non_niq_qa'
      AND claimed_at < now() - interval '${LEASE_TIMEOUT_HOURS:-4} hours';"
}

reclaim_stale_leases() {
  queue_psql "$(reclaim_stale_leases_query)" -t -A >/dev/null
}

claim_next_task_query() {
  local worker_id="$1"
  echo "UPDATE ${QUEUE_TABLE} SET status='running', claimed_by='${worker_id}', claimed_at=now()
    WHERE id = (
      SELECT id FROM ${QUEUE_TABLE}
      WHERE status='queued' AND script_type='non_niq_qa'
        AND table_name NOT IN (SELECT table_name FROM ${QUEUE_TABLE} WHERE status='running')
      ORDER BY priority DESC, submitted_at ASC
      FOR UPDATE SKIP LOCKED LIMIT 1
    )
    RETURNING id, table_name, script_type, month, max_turns, block_size, loop_count;"
}

claim_next_task() {
  local out
  if ! out=$(queue_psql "$(claim_next_task_query "$WORKER_ID")" -t -A -F'|' 2>&1); then
    [[ "$(is_duplicate_key_error "$out")" == "true" ]] && { echo ""; return 0; }
    echo "$out" >&2
    return 1
  fi
  grep '|' <<< "$out" || true
}

heartbeat() {
  local id="$1"
  queue_psql "UPDATE ${QUEUE_TABLE} SET claimed_at=now() WHERE id=${id} AND status='running';" -t -A >/dev/null
}

_sql_quote() {
  local s="$1"
  echo "'${s//\'/\'\'}'"
}

persist_final_status() {
  local id="$1" status="$2" iterations_run="$3" output="$4"
  local last_result_json
  last_result_json=$(printf '%s' "$output" | jq -Rs '{raw_output: .}')
  queue_psql "
      UPDATE ${QUEUE_TABLE}
      SET status = $(_sql_quote "$status"), iterations_run = ${iterations_run}, updated_at = now(),
          last_result = $(_sql_quote "$last_result_json")::json
      WHERE id = ${id};" \
    -t -A >/dev/null
}

run_task() {
  local id="$1" table_name="$2" max_turns="$3" loop_count="$4"
  local dataset platform
  read -r dataset platform <<< "$(split_table_name "$table_name")"
  local iterations_run=0 final_status="failed" last_output="" signal=""
  local i
  for ((i = 1; i <= loop_count; i++)); do
    heartbeat "$id"
    last_output=$("${NON_NIQ_QA_SCRIPT:-./script/non_niq/non_niq_qa.sh}" "$dataset" "$platform" "$max_turns" 2>&1) || true
    echo "$last_output"
    iterations_run=$((iterations_run + 1))
    signal=$(parse_queue_signal "$last_output") || true
    final_status=$(queue_signal_to_status "$signal")
    [[ "$(should_stop_looping "$signal")" == "true" ]] && break
  done
  persist_final_status "$id" "$final_status" "$iterations_run" "$last_output"
}

main() {
  source "$(dirname "$0")/../load_env.sh"
  QUEUE_TABLE="${QUEUE_SCHEMA:-public}.task_queue"
  : "${QUEUE_DATABASE_URL:?QUEUE_DATABASE_URL must be set (via .env or the environment)}"
  WORKER_ID="non-niq-$(hostname)-$$"
  echo "Non-NIQ worker ${WORKER_ID} starting, polling every ${POLL_INTERVAL_SECONDS:-15}s"
  while true; do
    reclaim_stale_leases
    local row
    row=$(claim_next_task) || { sleep "${POLL_INTERVAL_SECONDS:-15}"; continue; }
    if [[ -z "$row" ]]; then
      sleep "${POLL_INTERVAL_SECONDS:-15}"
      continue
    fi
    local id table_name script_type month max_turns block_size loop_count
    IFS='|' read -r id table_name script_type month max_turns block_size loop_count <<< "$row"
    echo "Claimed task ${id}: ${table_name} (${script_type})"
    run_task "$id" "$table_name" "$max_turns" "$loop_count"
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash script/non_niq/test_non_niq_queue_worker.sh`
Expected: `ALL TESTS PASSED`

- [ ] **Step 5: Commit**

```bash
git add script/non_niq/non_niq_queue_worker.sh script/non_niq/test_non_niq_queue_worker.sh
git commit -m "Add non_niq_queue_worker.sh: separate script_type-scoped lane on the shared task_queue"
```

---

### Task 4: `non_niq_qa.sh` — scope/worklist SQL builders

**Files:**
- Create: `script/non_niq/non_niq_qa.sh` (this task writes the SQL-builder half; Task 5 appends the prompt/main half to the same file)
- Test: `script/non_niq/test_non_niq_qa.sh` (this task writes the first section; Task 5 appends more)

**Interfaces:**
- Consumes: `non_niq_sheet.py`'s CLI (`categories`, `columns` subcommands) via `python3` calls from bash.
- Produces:
  - `default_month_query(source_table) -> SQL string`
  - `worklist_query(source_table, qa_table, qa_pk_col, month, platform) -> SQL string` — scope: top 90% cumulative GMV per platform (per issue #2, not the epic's 95%), priority order (unreviewed first, then unconfident-not-yet-human-reviewed, using `SAFE.JSON_VALUE`), `ORDER BY priority ASC, gmv_monthly DESC`.
  - `primary_filter_table(filter_table_config, dataset) -> string` — given the Sheet's raw `filter_table` cell (possibly `;`-separated), returns the one table living in `dataset`'s own namespace (the write target); other semicolon-separated entries are read-only reference, never returned by this function.

- [ ] **Step 1: Write the failing tests**

```bash
#!/usr/bin/env bash
set -euo pipefail
# Self-test for script/non_niq/non_niq_qa.sh's pure helper functions.
# No network, BQ, or claude calls -- mirrors script/test_headless_taxonomy.sh's convention.
# Run: bash script/non_niq/test_non_niq_qa.sh

cd "$(dirname "$0")/../.."
source script/non_niq/non_niq_qa.sh

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- default_month_query ---
q=$(default_month_query "babybath.master_babybath_id_dev")
echo "$q" | grep -q "MAX(month)" || fail "default_month_query should find the latest month"
echo "$q" | grep -q "babybath.master_babybath_id_dev" || fail "default_month_query should reference the source table"
echo "PASS: default_month_query"

# --- worklist_query ---
q=$(worklist_query "babybath.master_babybath_id_dev" "babybath.product_id_dict_qa" "prod_id" "2026-07" "shopee")
echo "$q" | grep -q "babybath.master_babybath_id_dev" || fail "worklist_query should reference the source table"
echo "$q" | grep -q "babybath.product_id_dict_qa" || fail "worklist_query should reference the QA table"
echo "$q" | grep -q "prod_id" || fail "worklist_query should use the resolved QA primary-key column, not a hardcoded one"
echo "$q" | grep -q "cumulative_gmv_pct <= 90" || fail "worklist_query must use the 90% threshold (issue #2), not the epic's 95%"
echo "$q" | grep -q "SAFE.JSON_VALUE" || fail "worklist_query must use SAFE.JSON_VALUE, never bare JSON_VALUE, when reading _meta"
if echo "$q" | grep -qE '(^|[^.])JSON_VALUE'; then
  fail "worklist_query must never call bare JSON_VALUE (only SAFE.JSON_VALUE) on _meta"
fi
echo "$q" | grep -q "ORDER BY priority ASC, gmv_monthly DESC" || fail "worklist_query must order unreviewed before unconfident, then by GMV"
echo "PASS: worklist_query"

# --- primary_filter_table ---
single="babybath.filter_babybath"
[[ "$(primary_filter_table "$single" "babybath")" == "babybath.filter_babybath" ]] || fail "single-value filter_table should return as-is"

multi="babysunscreen.filter_babysunscreen;sunscreen.filter_sunscreen_hanasui"
[[ "$(primary_filter_table "$multi" "babysunscreen")" == "babysunscreen.filter_babysunscreen" ]] || fail "should return the table in the row's own dataset, never the cross-dataset one"
echo "PASS: primary_filter_table"

echo "ALL TESTS PASSED (part 1: SQL builders)"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash script/non_niq/test_non_niq_qa.sh`
Expected: `non_niq_qa.sh: No such file or directory`

- [ ] **Step 3: Write the SQL-builder half of `non_niq_qa.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: script/non_niq/non_niq_qa.sh <DATASET> <PLATFORM> [MAX_TURNS]
# e.g.  script/non_niq/non_niq_qa.sh babybath shopee
#       script/non_niq/non_niq_qa.sh babybath shopee 400
#
# Agentic QA harness for one (dataset, platform) pair -- issue #2's decision tree (relevance ->
# correct/re-point -> match-or-create), Meilisearch hybrid retrieval instead of the POC's brute
# keyword scoring, confidence loop encoded in product_id_dict_qa's existing _meta JSON.
# See docs/superpowers/specs/2026-08-06-non-niq-agentic-qa-design.md for the full design.

PROJECT="sincere-hearth-273704"
MEILI_URL="http://34.124.146.29:7700"

default_month_query() {
  local source_table="$1"
  echo "SELECT FORMAT_DATE('%Y-%m', MAX(month)) FROM \`${PROJECT}.${source_table}\`"
}

# Scope per issue #2: latest month, top 90% cumulative GMV per ecommerce_platform (NOT the epic's
# general 95% -- QA uses a different threshold on purpose). Priority: rows with no QA-table entry
# yet come first (priority 0), then rows the agent already marked unconfident but hasn't yet
# capped out on retry (priority 1) -- human_review=true rows are excluded entirely, they're
# terminal. Every _meta read uses SAFE.JSON_VALUE -- _meta is not always valid JSON in production
# (empty strings, literal "nan" both observed live) and bare JSON_VALUE raises on malformed input.
worklist_query() {
  local source_table="$1" qa_table="$2" qa_pk_col="$3" month="$4" platform="$5"
  cat <<SQL
WITH base AS (
  SELECT s.product_id, s.sku_name, s.image, s.ecommerce_platform,
         COALESCE(s.flag_GWP, FALSE) OR REGEXP_CONTAINS(UPPER(s.sku_name), r'\[NOT FOR SALE\]|\[GWP\]') AS flag_GWP,
         s.gmv_monthly
  FROM \`${PROJECT}.${source_table}\` s
  WHERE FORMAT_DATE('%Y-%m', s.month) = '${month}' AND s.ecommerce_platform = '${platform}'
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
         SAFE.JSON_VALUE(_meta, '\$.qa_confidence') AS qa_confidence,
         SAFE.JSON_VALUE(_meta, '\$.human_review') AS human_review
  FROM \`${PROJECT}.${qa_table}\`
)
SELECT sc.product_id, sc.sku_name, sc.image, sc.gmv_monthly,
  CASE
    WHEN qs.product_id IS NULL THEN 0
    WHEN qs.qa_confidence = 'unconfident' AND COALESCE(qs.human_review, 'false') != 'true' THEN 1
    ELSE NULL
  END AS priority
FROM scoped sc
LEFT JOIN qa_state qs ON qs.product_id = sc.product_id
WHERE (qs.product_id IS NULL)
   OR (qs.qa_confidence = 'unconfident' AND COALESCE(qs.human_review, 'false') != 'true')
ORDER BY priority ASC, gmv_monthly DESC
SQL
}

# Given the Sheet's raw filter_table cell (possibly ";"-separated, e.g. a category cross-
# referencing another category's filter table), returns the ONE table living in this row's own
# dataset -- the only one this harness ever writes to. Any other semicolon-separated entry is
# read-only reference (checked before flagging, per the spec, but never written to) and is
# intentionally not returned by this function.
primary_filter_table() {
  local filter_table_config="$1" dataset="$2"
  local entry
  IFS=';' read -ra entries <<< "$filter_table_config"
  for entry in "${entries[@]}"; do
    if [[ "$entry" == "${dataset}."* ]]; then
      echo "$entry"
      return 0
    fi
  done
  echo "${entries[0]}"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash script/non_niq/test_non_niq_qa.sh`
Expected: `ALL TESTS PASSED (part 1: SQL builders)`

- [ ] **Step 5: Commit**

```bash
git add script/non_niq/non_niq_qa.sh script/non_niq/test_non_niq_qa.sh
git commit -m "Add non_niq_qa.sh scope/worklist SQL builders (90% GMV, confidence-based priority)"
```

---

### Task 5: `non_niq_qa.sh` — decision-tree prompt + main()

**Files:**
- Modify: `script/non_niq/non_niq_qa.sh` (append to the file Task 4 created)
- Modify: `script/non_niq/test_non_niq_qa.sh` (append)

**Interfaces:**
- Consumes: `worklist_query`, `default_month_query`, `primary_filter_table` (Task 4, same file); `python3 script/non_niq/non_niq_sheet.py categories`/`columns` CLI (Task 1); `python3 script/non_niq/non_niq_embed.py embed-query` CLI (Task 2); Meilisearch REST at `$MEILI_URL` (Task 2's `ensure_index` already created `{dataset}_taxonomy_qa`).
- Produces: `build_qa_prompt(...)`, `extract_json_object`, `decide_queue_signal`, `main()` — the full runnable `non_niq_qa.sh <DATASET> <PLATFORM> [MAX_TURNS]` entrypoint that `non_niq_queue_worker.sh` (Task 3) invokes.

- [ ] **Step 1: Write the failing tests (append to `test_non_niq_qa.sh`)**

```bash
# --- build_qa_prompt ---
prompt=$(build_qa_prompt "babybath" "shopee" "babybath.master_babybath_id_dev" \
  "babybath.product_id_dict_qa" "babybath.babybath_dict" "babybath.filter_babybath" \
  "prod_id" "sku_type" "keywords_typo" "babybath_taxonomy_qa" "SELECT 1 /* worklist */")

echo "$prompt" | grep -q "RELEVANT to this category" || fail "prompt must state the relevance-check step first"
echo "$prompt" | grep -q "do NOT create a taxonomy entry" || fail "prompt must state irrelevant products are dropped, never routed elsewhere"
echo "$prompt" | grep -q "babybath.filter_babybath" || fail "prompt must name the correct write-target filter table"
echo "$prompt" | grep -q "babybath_taxonomy_qa" || fail "prompt must name the Meilisearch index to search"
echo "$prompt" | grep -q "non_niq_embed.py embed-query" || fail "prompt must instruct batch embedding via the CLI helper, not per-product"
echo "$prompt" | grep -q -- "--input-file" || fail "prompt must instruct the batch (--input-file/--output-file) embed-query contract, not a per-product call"
echo "$prompt" | grep -q "sku_type" || fail "prompt must reference the resolved dict identity column"
echo "$prompt" | grep -q "keywords_typo" || fail "prompt must reference the resolved dict typo column"
echo "$prompt" | grep -q "prod_id" || fail "prompt must reference the resolved QA primary-key column"
echo "$prompt" | grep -q "never the streaming API" || fail "prompt must repeat the DML-only / no-streaming-API constraint"
echo "$prompt" | grep -q "qa_confidence" || fail "prompt must instruct writing the qa_confidence _meta field"
echo "$prompt" | grep -q "human_review" || fail "prompt must instruct writing the human_review _meta field on the retry path"
echo "$prompt" | grep -q "Mapping table" || fail "prompt must state the mapping table is never modified"
echo "PASS: build_qa_prompt"

# --- extract_json_object / decide_queue_signal (local duplicates, same contract as headless_taxonomy.sh) ---
[[ "$(extract_json_object 'prose {"status":"complete"} trailing')" == '{"status":"complete"}' ]] || fail "extract_json_object should pull the JSON object out of mixed text"
echo "PASS: extract_json_object"

complete_output='{"result":"{\"status\":\"complete\"}"}'
[[ "$(decide_queue_signal "$complete_output")" == "DONE" ]] || fail "complete status should map to DONE"
blocked_output='{"result":"{\"status\":\"blocked\"}"}'
[[ "$(decide_queue_signal "$blocked_output")" == "BLOCKED" ]] || fail "blocked status should map to BLOCKED"
garbage_output='not json at all'
[[ "$(decide_queue_signal "$garbage_output")" == "FAILED" ]] || fail "unparseable output should map to FAILED, never silently succeed"
echo "PASS: decide_queue_signal"

# --- main() wiring (grep the script source, no execution) ---
script_src=$(cat script/non_niq/non_niq_qa.sh)
grep -qF 'echo "QUEUE_SIGNAL: NOTHING_TO_DO"' <<< "$script_src" || fail "main() must emit NOTHING_TO_DO when the worklist is empty, before spending a claude -p call"
grep -qF 'echo "QUEUE_SIGNAL: $(decide_queue_signal "$claude_output")"' <<< "$script_src" || fail "main() must emit the post-run signal derived from decide_queue_signal"
echo "PASS: main() QUEUE_SIGNAL wiring"

echo "ALL TESTS PASSED (part 2: prompt + main)"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash script/non_niq/test_non_niq_qa.sh`
Expected: FAIL — `build_qa_prompt: command not found`

- [ ] **Step 3: Append the prompt builder + main() to `non_niq_qa.sh`**

```bash

build_qa_prompt() {
  local dataset="$1" platform="$2" source_table="$3" qa_table="$4" dict_table="$5" filter_table="$6"
  local qa_pk_col="$7" dict_identity_col="$8" dict_typo_col="$9" meili_index="${10}" worklist_query="${11}"
  cat <<PROMPT
Non-NIQ Agentic QA session for dataset=${dataset}, platform=${platform}. See
docs/superpowers/specs/2026-08-06-non-niq-agentic-qa-design.md for the full design this
implements -- read it in full before starting.

Resolved for this run: source_table=${PROJECT}.${source_table}, qa_table=${PROJECT}.${qa_table},
dict_table=${PROJECT}.${dict_table}, filter_table (write target)=${PROJECT}.${filter_table},
qa_pk_col=${qa_pk_col}, dict_identity_col=${dict_identity_col}, dict_typo_col=${dict_typo_col},
meilisearch_index=${meili_index} (at ${MEILI_URL}).

STEP 0 -- Get the live worklist (do not trust any cached number, re-run this yourself):
${worklist_query}
This is already scoped to top 90% cumulative GMV per platform and prioritized (unreviewed rows
before agent-flagged-unconfident retry rows, both by gmv_monthly descending) -- process it in
that order.

STEP 1 -- Batch-embed the WHOLE worklist's sku_name text in ONE call, never one call per product
(a fresh process per product means a ~2GB multilingual-e5-large model reload per product):
  1. Write /tmp/${dataset}_${platform}_worklist.jsonl -- one line per worklist product:
     {"id": "<product_id>", "text": "<sku_name>"}
  2. Run: python3 script/non_niq/non_niq_embed.py embed-query --input-file /tmp/${dataset}_${platform}_worklist.jsonl --output-file /tmp/${dataset}_${platform}_vectors.jsonl
  3. Read back /tmp/${dataset}_${platform}_vectors.jsonl -- one {"id":..., "embedding":[...]} per input line.

STEP 2 -- For each product in the worklist, in order:

  2a. RELEVANT to this category? Read the product image and sku_name/item_description together --
      does this product genuinely belong in "${dataset}"?
      NO  -> write {product_id, ecommerce_platform, sku_name, reason} to \`${PROJECT}.${filter_table}\`
             (this dataset's OWN filter table -- never write to a different dataset's filter table
             even if the Sheet cross-references one for read context), _meta stamped
             '{"source":"claude_code"}', do NOT create a taxonomy entry. Move to the next product.
      YES -> continue to 2b.

  2b. Does \`${PROJECT}.${qa_table}\` already have a row for this product_id (via ${qa_pk_col})
      with a value that came from a prior engine, not from you? If a value exists: is it CORRECT?
      YES -> write the SAME brand/${dict_identity_col} values to \`${PROJECT}.${qa_table}\`, go to 2d.
      NO, or no existing value at all -> continue to 2c.

  2c. Hybrid retrieval: using this product's vector from STEP 1 and its sku_name text, query
      Meilisearch for candidates:
        curl -s -X POST "${MEILI_URL}/indexes/${meili_index}/search" -H "Content-Type: application/json" \\
          -d "{\\"q\\": \\"<sku_name>\\", \\"vector\\": <embedding from STEP 1>, \\"hybrid\\": {\\"embedder\\": \\"default\\", \\"semanticRatio\\": 0.5}, \\"limit\\": 10}"
      This returns confirmed exemplars (product_id, sku_name, brand, sku_type_complete of similar
      past-QA'd products), not raw dict rows -- use them as grounding context, then check the
      candidates' implied dict entries against \`${PROJECT}.${dict_table}\` for the real match.
      Does a TRUE matching taxonomy record exist in ${dict_table}?
      YES -> write CORRECTED (re-pointed) brand/${dict_identity_col} values to
             \`${PROJECT}.${qa_table}\`.
      NO  -> two-step create in \`${PROJECT}.${dict_table}\`:
             Step A: insert brand + ${dict_identity_col} + keywords (+ ${dict_typo_col} if you
                     have common misspellings), _meta='claude_code' stamped here.
             Step B: populate the remaining attribute columns for this dict's schema, GROUNDED on
                     existing dict rows' actual vocabulary and formatting -- query
                     \`SELECT DISTINCT <column> FROM ${PROJECT}.${dict_table}\` per attribute column
                     before writing a new value, prefer an existing value over inventing one, and
                     match existing formatting exactly (e.g. "150 ml" not "150ml").
             Then write brand/${dict_identity_col} values pointing at the new entry to
             \`${PROJECT}.${qa_table}\`.

  2d. Self-QA: as an explicit, separate judgment (not folded into 2a-2c's reasoning), state how
      confident you are in the decision you just made for this product. Then:
      - If this is the product's FIRST time being processed this session (no qa_confidence value
        existed for it before this run): write _meta =
        '{"source":"claude_code","qa_confidence":"confident","timestamp":"<now, ISO 8601 UTC>"}' if
        confident, or
        '{"source":"claude_code","qa_confidence":"unconfident","human_review":false,"timestamp":"<now>"}'
        if not.
      - If this product ALREADY had a qa_confidence:'unconfident', human_review:false row before
        this run (i.e. this is its one allowed retry): and you are STILL unconfident after
        redoing 2a-2c with full multimodal effort, write _meta =
        '{"source":"claude_code","qa_confidence":"unconfident","human_review":true,"timestamp":"<now>"}'
        -- this is terminal, the product will not re-enter future worklists for this harness.
        If you ARE confident on this retry, write the confident shape as above.

Hard rules, never relaxed:
- Mapping table (any product_id_dict / prior-engine table) is NEVER modified by this harness --
  corrections only ever land in \`${PROJECT}.${qa_table}\`.
- All writes use bq query DML, never the streaming API -- CLAUDE.md's 90-minute streaming-buffer
  rule. The very next run's retry-cap logic depends on reading back this run's QA rows reliably.
- Every _meta read you do yourself (e.g. checking whether a product already has an unconfident
  row) must use SAFE.JSON_VALUE, never bare JSON_VALUE -- some existing _meta values are empty
  strings or the literal text "nan", and bare JSON_VALUE raises on those.
- Attempt to resolve the ENTIRE worklist within your turn budget this session -- do not
  self-limit to a small sample. Stop early only when genuinely low on turns, and say so honestly
  in findings.

If you hit a genuine blocker -- something wrong with these instructions, missing data, anything
that would make proceeding unsafe -- stop and output status='blocked' with the blockers array
populated. That is a valid, expected outcome.

Output ONLY this JSON when done, nothing else:
{status: complete|partial|failed|blocked, rows_qa_confirmed, rows_qa_unconfident, rows_filtered, rows_created_in_dict, findings, blockers}.
PROMPT
}

extract_json_object() {
  local text="$1"
  printf '%s' "$text" | grep -Pzo '(?s)\{.*\}' | tr -d '\0'
}

decide_queue_signal() {
  local claude_output="$1"
  local result_json
  result_json=$(echo "$claude_output" | jq -r '.result // empty' 2>/dev/null) || result_json=""
  if [[ -z "$result_json" ]]; then
    echo "FAILED"
    return
  fi
  if ! echo "$result_json" | jq -e . >/dev/null 2>&1; then
    local extracted
    extracted=$(extract_json_object "$result_json")
    if [[ -n "$extracted" ]] && echo "$extracted" | jq -e . >/dev/null 2>&1; then
      result_json="$extracted"
    fi
  fi
  local status
  status=$(echo "$result_json" | jq -r '.status // empty' 2>/dev/null) || status=""
  case "$status" in
    blocked) echo "BLOCKED" ;;
    complete|partial) echo "DONE" ;;
    *) echo "FAILED" ;;
  esac
}

main() {
  if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <DATASET> <PLATFORM> [MAX_TURNS]" >&2
    exit 1
  fi
  local dataset="$1" platform="$2" max_turns="${3:-300}"

  local category_json
  category_json=$(python3 "$(dirname "$0")/non_niq_sheet.py" categories --country ID \
    | jq -c --arg ds "$dataset" --arg pl "$platform" '.[] | select(.dataset == $ds and .ecommerce_platform == $pl)')
  if [[ -z "$category_json" ]]; then
    echo "No active config Sheet row for dataset=${dataset} platform=${platform}" >&2
    echo "QUEUE_SIGNAL: FAILED"
    exit 1
  fi

  local source_table qa_table dict_table filter_table_config
  source_table=$(echo "$category_json" | jq -r '.table')
  qa_table=$(echo "$category_json" | jq -r '.product_id_dict_qa')
  dict_table=$(echo "$category_json" | jq -r '.dict')
  filter_table_config=$(echo "$category_json" | jq -r '.filter_table')
  local filter_table
  filter_table=$(primary_filter_table "$filter_table_config" "$dataset")

  local columns_json qa_pk_col dict_identity_col dict_typo_col
  columns_json=$(python3 "$(dirname "$0")/non_niq_sheet.py" columns --project "$PROJECT" \
    --qa-table "$qa_table" --dict-table "$dict_table")
  qa_pk_col=$(echo "$columns_json" | jq -r '.qa_pk_col')
  dict_identity_col=$(echo "$columns_json" | jq -r '.dict_identity_col')
  dict_typo_col=$(echo "$columns_json" | jq -r '.dict_typo_col')

  local month
  month=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "$(default_month_query "$source_table")" | tail -1)

  local meili_index="${dataset}_taxonomy_qa"
  local query
  query=$(worklist_query "$source_table" "$qa_table" "$qa_pk_col" "$month" "$platform")

  local worklist_count
  worklist_count=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "SELECT COUNT(*) FROM ($query)" | tail -1)

  if [[ "$worklist_count" == "0" ]]; then
    echo "No in-scope worklist for ${dataset}/${platform}/${month} -- nothing to do."
    echo "QUEUE_SIGNAL: NOTHING_TO_DO"
    exit 0
  fi

  echo "${dataset}/${platform}, month=${month}, worklist_count=${worklist_count}"

  local prompt
  prompt=$(build_qa_prompt "$dataset" "$platform" "$source_table" "$qa_table" "$dict_table" \
    "$filter_table" "$qa_pk_col" "$dict_identity_col" "$dict_typo_col" "$meili_index" "$query")

  local claude_output
  claude_output=$(claude -p --output-format json --permission-mode bypassPermissions --max-turns "$max_turns" "$prompt")
  echo "$claude_output"

  echo "QUEUE_SIGNAL: $(decide_queue_signal "$claude_output")"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash script/non_niq/test_non_niq_qa.sh`
Expected: `ALL TESTS PASSED (part 1: SQL builders)` followed by `ALL TESTS PASSED (part 2: prompt + main)`

- [ ] **Step 5: Commit**

```bash
git add script/non_niq/non_niq_qa.sh script/non_niq/test_non_niq_qa.sh
git commit -m "Add non_niq_qa.sh decision-tree prompt + main(): full issue #2 QA harness"
```

---

### Task 6: End-to-end smoke verification against `telonoil`

**Files:** none created — this task is a manual verification run, not new code. `telonoil` is chosen because it's the smallest target category (248 dict rows, 2,695 QA rows) — cheapest real end-to-end check before trusting the harness against larger categories.

**Interfaces:**
- Consumes: everything from Tasks 1-5, run together for the first time against real BigQuery/Meilisearch data.
- Produces: nothing consumed by later tasks — this is the plan's final verification gate before rollout.

- [ ] **Step 1: Deploy `non_niq_embed.py` to Windmill and run a manual sync for `telonoil`**

Follow the existing Windmill git-sync workflow (same as `docs/windmill-app-prompt.md`'s app, but for a script, not a full app) to deploy `script/non_niq/non_niq_embed.py`. Then, from Windmill's UI, run it once with `dataset="telonoil"`.

Expected: Windmill run succeeds, prints `telonoil: synced <N> rows` where N > 0 (telonoil has 2,695 QA rows, most should be confirmed and synced).

- [ ] **Step 2: Verify the Meilisearch index was actually populated**

Run:
```bash
curl -s "http://34.124.146.29:7700/indexes/telonoil_taxonomy_qa/stats"
```
Expected: `numberOfDocuments` roughly matches the confirmed-row count from Step 1's output (not zero, not wildly higher than the source table's row count).

- [ ] **Step 3: Submit one `non_niq_qa` task via the existing `queue_ctl.sh`**

Run:
```bash
source script/load_env.sh
script/queue_ctl.sh submit "telonoil:shopee" non_niq_qa --max-turns 100 --loop-count 1 --priority 100
```

Expected: prints a new `id`. Confirm the row exists and is `queued`:
```bash
script/queue_ctl.sh list --status queued
```

- [ ] **Step 4: Run the non_niq worker once, by hand, in the foreground (not the infinite loop)**

Run:
```bash
source script/load_env.sh
script/non_niq/non_niq_qa.sh telonoil shopee 100
```

Expected: the script prints the resolved month, worklist_count, the full `claude -p` transcript, and ends with a `QUEUE_SIGNAL:` line (`DONE`, `BLOCKED`, or `FAILED` — `NOTHING_TO_DO` would mean the worklist came back empty, which is unexpected for telonoil's first run and worth investigating rather than treating as success).

- [ ] **Step 5: Verify at least one real row landed correctly**

Run:
```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=prettyjson \
  "SELECT prod_id, sku_name, brand, sku_type_complete, _meta FROM \`sincere-hearth-273704.telonoil.product_id_dict_qa\`
   WHERE SAFE.JSON_VALUE(_meta, '\$.source') = 'claude_code' ORDER BY prod_id LIMIT 5"
```

Expected: at least one row with `_meta` containing `"source":"claude_code"` and a valid `"qa_confidence"` value (`"confident"` or `"unconfident"`), `brand`/`sku_type_complete` populated (not NULL/empty).

- [ ] **Step 6: Verify the mapping table was never touched**

Run:
```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=csv \
  "SELECT COUNT(*) FROM \`sincere-hearth-273704.telonoil.product_id_dict\`"
```
Compare against the row count from before Step 4 (capture it beforehand). Expected: identical — this harness must never write to `product_id_dict`.

- [ ] **Step 7: Report against issue #2's success criteria**

Manually compare a sample of the run's `product_id_dict_qa` writes (Step 5) against telonoil's pre-existing human QA history for the same products, if any overlap exists in this sample. Report: QA agreement rate, disagreement triage (agent wrong vs. human wrong), filter precision/recall on any filtered rows, and whether created dict entries (if any) are genuinely new vs. a retrieval miss. This is the same reporting shape as the Phase 0 POC comment on issue #1 — use it as the template.

---

## Self-Review

**Spec coverage:** Decision tree (Task 5) ✓. Filter-table dataset-ownership rule (Task 4's `primary_filter_table`, tested against the exact `babysunscreen` case from the spec) ✓. Confidence loop / `_meta` JSON shapes (Task 5's `build_qa_prompt` 2d, tested) ✓. Per-category column resolution (Task 1) ✓. Meilisearch hybrid retrieval, `userProvided` embedder, `{dataset}_taxonomy_qa` naming (Task 2) ✓. Confirmed-rows-only sync corpus (Task 2's `is_confirmed`, tested against all `_meta` shapes seen live including empty/`"nan"`) ✓. Batch-first query embedding, not per-product (Task 2's `embed_query_file` contract + Task 5's prompt asserting `--input-file`) ✓. `task_queue` shared-table, separate lane, `script_type`-scoped reclaim (Task 3) ✓. DML-only / no streaming API (Task 5's prompt, tested) ✓. `SAFE.JSON_VALUE` everywhere (Task 4's `worklist_query`, tested; Task 5's prompt, tested) ✓. Windmill-format single-file embed script, manual trigger only, no schedule (Task 2 — `main()` is the only Windmill-called function, no cron anywhere in this plan) ✓. Rollout order and 90%-GMV/latest-month scope (Task 4) ✓.

**Placeholder scan:** no TBD/TODO; every code block is complete, runnable code, not a description of code.

**Type consistency:** `worklist_query`'s 5 positional args (`source_table, qa_table, qa_pk_col, month, platform`) match the call site in `main()` and in the test. `build_qa_prompt`'s 11 positional args match its call site in `main()` and its test invocation. `primary_filter_table(filter_table_config, dataset)` signature matches both its test and its `main()` call site. `is_confirmed(meta_raw)` matches between `non_niq_embed.py` and its test. `resolve_category_columns` / `pick_column` signatures match between `non_niq_sheet.py`, its test, and Task 2's `sync_category` (which calls `pick_column` directly on QA-table columns fetched via `client.get_table(...).schema`, not through `resolve_category_columns` — this is intentional, `sync_category` only needs the QA PK column, not the dict columns, so it doesn't pay for a dict-table lookup it doesn't use).
