# extra_requirements:
# google-cloud-bigquery
# google-cloud-bigquery-storage
# --extra-index-url https://download.pytorch.org/whl/cpu
# torch
# sentence-transformers>=2.7

"""Config Sheet + Meilisearch sync + batch query-embedding for the Non-NIQ QA harness.

Single file, deliberately -- Windmill deploys one script at a time and doesn't bundle local
imports, so a second local module (this used to be split into non_niq_sheet.py) can't be deployed
alongside it. The pytorch-cpu extra-index-url above mirrors this repo's own pyproject.toml
[[tool.uv.index]] entry: without it, a plain `pip install torch` can resolve the CUDA-bundled
default-PyPI build (multi-GB) instead of the ~200MB CPU-only build this Hetzner box actually needs.

Three responsibilities in one file:

1. `categories`/`columns` CLI -- reads the pipeline config Sheet (published CSV export, read-only)
   to resolve which BQ tables belong to which category, and resolves the handful of column names
   that genuinely vary per category's dict/QA table schema (sku_type vs sku_type_complete, prod_id
   vs product_id, keywords_typo vs keyword_typo) live via INFORMATION_SCHEMA.COLUMNS rather than
   hardcoding a static, already-stale mapping. Called by non_niq_qa.sh's Claude subprocess.

2. main() / `sync` -- Windmill-deployable batch job. For each active category (or one, via
   --dataset), reads product_id_dict_qa, keeps only CONFIRMED rows (excludes our own agent's
   unconfident guesses -- see is_confirmed), embeds sku_name, upserts into the category's
   `{dataset}_taxonomy_qa` Meilisearch index as userProvided vectors. Manual trigger only, no
   schedule -- run on demand from Windmill's UI or `python3 non_niq_embed.py sync`.

3. `embed-query` CLI -- called by non_niq_qa.sh's Claude subprocess to embed a whole worklist
   batch's sku_names in ONE process invocation (not one call per product -- a fresh process per
   product would mean a ~2GB model cold-load per product).

All three share the same model-loading code (splitting them would mean loading
multilingual-e5-large twice) and now the same Sheet-reading code. Runs on the Hetzner box
(embedding compute must not run on a laptop -- see design spec).
"""
import argparse
import csv
import io
import json
import urllib.error
import urllib.request
from pathlib import Path

from google.cloud import bigquery
from sentence_transformers import SentenceTransformer

PROJECT = "sincere-hearth-273704"
MEILI_URL = "http://34.124.146.29:7700"
MODEL_NAME = "intfloat/multilingual-e5-large"
EMBED_DIM = 1024
BATCH_SIZE = 256

CONFIG_CSV_URL = (
    "https://docs.google.com/spreadsheets/d/e/2PACX-1vQfqTVdo1ubO40dBBGzECaXVruIefLZpfX6KSFVHzY2gXv2dE-VHDofMC2Q_1tY5LwOmYJPG0kwwxN4"
    "/pub?gid=149787162&single=true&output=csv"
)

ROW_FIELDS = ["category", "dataset", "ecommerce_platform", "table", "product_id_dict_qa",
              "product_id_dict", "dict", "filter_table"]

QA_PK_CANDIDATES = ["product_id", "prod_id"]
DICT_IDENTITY_CANDIDATES = ["sku_type_complete", "sku_type"]
DICT_TYPO_CANDIDATES = ["keywords_typo", "keyword_typo"]


# ---------------------------------------------------------------------------
# Config Sheet + per-category column resolution
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# Meilisearch sync + query embedding
# ---------------------------------------------------------------------------

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
    except urllib.error.URLError as e:
        # Meilisearch down / DNS / timeout -- same RuntimeError shape so callers need one except.
        raise RuntimeError(f"Meilisearch {method} {path} unreachable: {e.reason}") from e


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


def _format_passage_text(text):
    """Format text for the indexed corpus side (E5 asymmetric retrieval)."""
    return f"passage: {text}"


def _format_query_text(text):
    """Format text for the search query side (E5 asymmetric retrieval)."""
    return f"query: {text}"


def _load_model():
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

    texts = [_format_passage_text(r.sku_name) for r in rows]
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
    # One POST per BATCH_SIZE docs. A 1024-dim vector serialises to ~20KB of JSON, so the whole
    # corpus in a single POST blows past Meilisearch's 100MB payload limit above ~5k rows.
    # Ingestion is async: print each batch's taskUid so a failure that happens after the 202 is at
    # least traceable from this job's log (no polling -- the sync is manual-trigger only).
    for i in range(0, len(docs), BATCH_SIZE):
        task = _meili_request("POST", f"/indexes/{index_uid}/documents", docs[i:i + BATCH_SIZE])
        print(f"  {dataset}: submitted batch task {task.get('taskUid')} ({len(docs[i:i + BATCH_SIZE])} docs)")
    return len(docs)


def embed_query_file(input_path, output_path, model=None):
    model = model or _load_model()
    lines = [json.loads(l) for l in Path(input_path).read_text().splitlines() if l.strip()]
    texts = [_format_query_text(l['text']) for l in lines]
    vectors = model.encode(texts, batch_size=BATCH_SIZE, show_progress_bar=False, normalize_embeddings=True)
    with open(output_path, "w") as f:
        for line, vec in zip(lines, vectors):
            f.write(json.dumps({"id": line["id"], "embedding": vec.tolist()}) + "\n")


def main(mode="sync", dataset=None):
    """Windmill entrypoint.

    `mode` is deliberately unread: Windmill builds the job's input form by introspecting this
    signature, so dropping the parameter is a deploy-surface change to the already-deployed job
    for zero code benefit. Sync is the only mode; give it a second meaning before branching on it.
    """
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
        try:
            n = sync_category(client, MEILI_URL, PROJECT, ds, qa_table, model)
            print(f"{ds}: synced {n} rows")
            total += n
        except Exception as e:
            print(f"{ds}: ERROR - {type(e).__name__}: {e}")
    print(f"Total synced: {total}")
    return total


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _cmd_categories(args):
    csv_text = open(args.csv_file).read() if args.csv_file else fetch_config_csv()
    targets = [c.strip() for c in args.categories.split(",")] if args.categories else None
    rows = parse_categories(csv_text, country=args.country, target_categories=targets)
    print(json.dumps(rows))


def _cmd_columns(args):
    client = bigquery.Client(project=args.project)
    result = resolve_category_columns(client, args.project, args.qa_table, args.dict_table)
    print(json.dumps(result))


if __name__ == "__main__":
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

    sync_p = sub.add_parser("sync")
    sync_p.add_argument("--dataset", default=None)

    eq_p = sub.add_parser("embed-query")
    eq_p.add_argument("--input-file", required=True)
    eq_p.add_argument("--output-file", required=True)

    args = parser.parse_args()
    if args.command == "categories":
        _cmd_categories(args)
    elif args.command == "columns":
        _cmd_columns(args)
    elif args.command == "sync":
        main(mode="sync", dataset=args.dataset)
    elif args.command == "embed-query":
        embed_query_file(args.input_file, args.output_file)
