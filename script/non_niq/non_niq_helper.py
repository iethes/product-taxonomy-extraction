#!/usr/bin/env python3
"""Local helper for non_niq_qa.sh -- config Sheet resolution, per-category column resolution, and
batch embed+retrieve against Meilisearch. Runs on the same Hetzner box as non_niq_qa.sh itself, via
this repo's own .venv (uv-managed -- CPU-only torch is already correctly pinned there through
pyproject.toml's [tool.uv.sources], no Windmill-specific dependency handling needed here).

Meilisearch: this helper both reads (the `retrieve` command, used every QA session) and writes
(the `index` command, called once at the end of a v2 QA session for newly-minted taxonomy entries
-- see non_niq_qa_v2.sh's STEP 3). Windmill's non_niq_embed.py (docs/windmill-non-niq-embed-prompt.md)
remains a separate, manual-trigger whole-corpus resync -- the two write paths don't conflict,
Meilisearch upserts are idempotent by product_id (the index's declared primaryKey).

Plain CLI (no Windmill involved, so no reason for the kwargs-only calling convention the deployed
script needs) -- subcommands, called directly from non_niq_qa.sh/non_niq_qa_v2.sh's bash:

  categories --country ID [--categories "A,B"] [--csv-file PATH]
      Reads the pipeline config Sheet (published CSV export) -> JSON list of active categories.

  columns --project P --qa-table dataset.qa --dict-table dataset.dict
      Resolves the handful of column names that vary per category's dict/QA table schema
      (sku_type vs sku_type_complete, prod_id vs product_id, keywords_typo vs keyword_typo) live
      via INFORMATION_SCHEMA.COLUMNS -> JSON.

  retrieve --input-file WORKLIST.jsonl --meili-index IDX --output-file OUT.jsonl [--limit 10]
      Batch-embeds the WHOLE worklist's sku_name text in one model call, then runs one Meilisearch
      hybrid search per product -- both mechanical, repetitive steps done here instead of inside
      the Claude subprocess, so non_niq_qa.sh's per-product loop never spends a tool call just to
      construct a search request. Input: one {"id": product_id, "text": sku_name} per line.
      Output: one {"id": product_id, "candidates": [...]} per line, same order, where each
      candidate is a Meilisearch hit shaped like the indexed corpus (product_id, sku_name, brand,
      sku_type_complete). A single product's search failure doesn't abort the batch -- it gets
      empty candidates and a warning is printed, so one Meilisearch hiccup doesn't cost the whole
      worklist's retrieval.

  index --input-file DOCS.jsonl --meili-index IDX [--meili-url URL]
      Embeds each product's sku_name as an E5 passage (asymmetric retrieval -- corpus side, not
      query side) and upserts into Meilisearch, creating/configuring the index first if it
      doesn't exist yet. Input: one {"product_id","sku_name","sku_type_complete","brand"} per
      line. Batched at BATCH_SIZE per POST (a 1024-dim vector serialises to ~20KB of JSON, so a
      single POST would blow past Meilisearch's 100MB payload limit above a few thousand rows).
"""
import argparse
import csv
import io
import json
import os
import urllib.error
import urllib.request

from google.cloud import bigquery
from sentence_transformers import SentenceTransformer

MEILI_URL = "http://34.124.146.29:7700"
MODEL_NAME = "intfloat/multilingual-e5-large"
BATCH_SIZE = 256
EMBED_DIM = 1024

DISCORD_CONTENT_LIMIT = 2000
DISCORD_CELL_TRUNCATE = 200

CONFIG_CSV_URL = (
    "https://docs.google.com/spreadsheets/d/e/2PACX-1vQfqTVdo1ubO40dBBGzECaXVruIefLZpfX6KSFVHzY2gXv2dE-VHDofMC2Q_1tY5LwOmYJPG0kwwxN4"
    "/pub?gid=149787162&single=true&output=csv"
)

ROW_FIELDS = ["category", "dataset", "ecommerce_platform", "table", "master_table_prod",
              "product_id_dict_qa", "product_id_dict", "dict", "filter_table", "0"]

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
# Retrieval: batch embed + batch Meilisearch hybrid search
# ---------------------------------------------------------------------------

def _format_query_text(text):
    """Format text for the search query side (E5 asymmetric retrieval) -- the indexed corpus side
    ('passage: ' prefix) lives in non_niq_embed.py's Windmill deploy, not here."""
    return f"query: {text}"


def _format_passage_text(text):
    """Format text for the indexed corpus side (E5 asymmetric retrieval) -- mirrors
    non_niq_embed.py's Windmill-deployed version, kept in sync by convention (both index the same
    Meilisearch corpus, so both must embed with the same asymmetric prefix)."""
    return f"passage: {text}"


def _meili_request(meili_url, method, path, body=None):
    url = f"{meili_url}{path}"
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
        raise RuntimeError(f"Meilisearch {method} {path} unreachable: {e.reason}") from e


def retrieve_candidates(lines, meili_url, meili_index, limit=10, model=None):
    model = model or SentenceTransformer(MODEL_NAME)
    texts = [_format_query_text(l["text"]) for l in lines]
    vectors = model.encode(texts, batch_size=BATCH_SIZE, show_progress_bar=False, normalize_embeddings=True)

    results = []
    for line, vec in zip(lines, vectors):
        try:
            hits = _meili_request(meili_url, "POST", f"/indexes/{meili_index}/search", {
                "q": line["text"],
                "vector": vec.tolist(),
                "hybrid": {"embedder": "default", "semanticRatio": 0.5},
                "limit": limit,
            })
            candidates = hits.get("hits", [])
        except RuntimeError as e:
            print(f"  WARNING: retrieval failed for product_id={line['id']}: {e}")
            candidates = []
        results.append({"id": line["id"], "candidates": candidates})
    return results


# ---------------------------------------------------------------------------
# Indexing: embed + upsert newly-minted taxonomy entries into Meilisearch
# ---------------------------------------------------------------------------

def ensure_index(meili_url, index_uid):
    """Create the index if it doesn't exist yet, then (re-)apply settings either way -- cheap and
    idempotent, so no need to branch on whether settings already match. Same conventions as
    non_niq_embed.py's Windmill-deployed version (docs/windmill-non-niq-embed-prompt.md), so a
    v2-created index and a Windmill-synced index are interchangeable."""
    existing = _meili_request(meili_url, "GET", "/indexes?limit=200")
    uids = {r["uid"] for r in existing.get("results", [])}
    if index_uid not in uids:
        _meili_request(meili_url, "POST", "/indexes", {"uid": index_uid, "primaryKey": "product_id"})
    _meili_request(meili_url, "PATCH", f"/indexes/{index_uid}/settings", {
        "searchableAttributes": ["sku_name", "sku_type_complete", "brand"],
        "embedders": {"default": {"source": "userProvided", "dimensions": EMBED_DIM}},
    })


def index_documents(lines, meili_url, meili_index, model=None):
    """lines: list of {"product_id","sku_name","sku_type_complete","brand"} -- the shape v2's
    STEP 3 batches up from its own session writes. Embeds sku_name as an E5 passage (corpus side),
    upserts into meili_index (creating/configuring it first if needed), batched at BATCH_SIZE -- a
    1024-dim vector serialises to ~20KB of JSON, so a single POST for a large batch would blow
    past Meilisearch's 100MB payload limit. Returns the number of documents submitted; a caller
    with zero qualifying products should simply not call this (STEP 3's prompt instructs that),
    but an empty list is handled as a no-op regardless."""
    if not lines:
        return 0
    model = model or SentenceTransformer(MODEL_NAME)
    ensure_index(meili_url, meili_index)
    texts = [_format_passage_text(l["sku_name"]) for l in lines]
    vectors = model.encode(texts, batch_size=BATCH_SIZE, show_progress_bar=False, normalize_embeddings=True)
    docs = [
        {
            "product_id": str(l["product_id"]),
            "sku_name": l["sku_name"],
            "sku_type_complete": l["sku_type_complete"],
            "brand": l["brand"],
            "_vectors": {"default": vec.tolist()},
        }
        for l, vec in zip(lines, vectors)
    ]
    for i in range(0, len(docs), BATCH_SIZE):
        _meili_request(meili_url, "POST", f"/indexes/{meili_index}/documents", docs[i:i + BATCH_SIZE])
    return len(docs)


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


def _cmd_retrieve(args):
    lines = [json.loads(l) for l in open(args.input_file) if l.strip()]
    results = retrieve_candidates(lines, args.meili_url, args.meili_index, limit=args.limit)
    with open(args.output_file, "w") as f:
        for r in results:
            f.write(json.dumps(r) + "\n")
    print(f"Retrieved candidates for {len(results)} products -> {args.output_file}")


def _cmd_index(args):
    lines = [json.loads(l) for l in open(args.input_file) if l.strip()]
    count = index_documents(lines, args.meili_url, args.meili_index)
    print(f"Indexed {count} products -> {args.meili_index}")


def _cmd_notify_discord(args):
    notify_discord_new_entry(args.project, args.dict_table, args.brand, args.identity_col,
                              args.identity_value, args.dataset)


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

    ret_p = sub.add_parser("retrieve")
    ret_p.add_argument("--input-file", required=True)
    ret_p.add_argument("--output-file", required=True)
    ret_p.add_argument("--meili-index", required=True)
    ret_p.add_argument("--meili-url", default=MEILI_URL)
    ret_p.add_argument("--limit", type=int, default=10)

    index_p = sub.add_parser("index")
    index_p.add_argument("--input-file", required=True)
    index_p.add_argument("--meili-index", required=True)
    index_p.add_argument("--meili-url", default=MEILI_URL)

    notify_p = sub.add_parser("notify-discord")
    notify_p.add_argument("--project", required=True)
    notify_p.add_argument("--dict-table", required=True)
    notify_p.add_argument("--brand", required=True)
    notify_p.add_argument("--identity-col", required=True)
    notify_p.add_argument("--identity-value", required=True)
    notify_p.add_argument("--dataset", required=True)

    args = parser.parse_args()
    if args.command == "categories":
        _cmd_categories(args)
    elif args.command == "columns":
        _cmd_columns(args)
    elif args.command == "retrieve":
        _cmd_retrieve(args)
    elif args.command == "index":
        _cmd_index(args)
    elif args.command == "notify-discord":
        _cmd_notify_discord(args)


if __name__ == "__main__":
    main()
