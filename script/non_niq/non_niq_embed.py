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


def _format_passage_text(text):
    """Format text for the indexed corpus side (E5 asymmetric retrieval)."""
    return f"passage: {text}"


def _format_query_text(text):
    """Format text for the search query side (E5 asymmetric retrieval)."""
    return f"query: {text}"


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
    _meili_request("POST", f"/indexes/{index_uid}/documents", docs)
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
        try:
            n = sync_category(client, MEILI_URL, PROJECT, ds, qa_table, model)
            print(f"{ds}: synced {n} rows")
            total += n
        except Exception as e:
            print(f"{ds}: ERROR - {type(e).__name__}: {e}")
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
