#!/usr/bin/env python3
"""Embeds product_taxonomy.canonical_name and marketshare_universe_niq.sku_name text that
isn't in the embeddings tables yet, using a local multilingual-e5-large model. Runs on the
Hetzner VM via cron. Only ever INSERTs into product_taxonomy_embeddings/universe_sku_embeddings
- never touches product_taxonomy, product_taxonomy_map, or marketshare_universe_niq itself.
"""
import argparse
from datetime import datetime, timezone

from google.cloud import bigquery
from sentence_transformers import SentenceTransformer

PROJECT = "sincere-hearth-273704"
MODEL_NAME = "intfloat/multilingual-e5-large"
BATCH_SIZE = 256


def load_model():
    return SentenceTransformer(MODEL_NAME)


def _load_rows(client, rows, target_table):
    if not rows:
        return 0
    table_ref = f"{PROJECT}.{target_table}"
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
    )
    load_job = client.load_table_from_json(rows, table_ref, job_config=job_config)
    load_job.result()
    return len(rows)


def embed_taxonomy(client, model, limit=None):
    limit_clause = "LIMIT @row_limit" if limit else ""
    query = f"""
        SELECT pt.taxonomy_id, pt.canonical_name
        FROM `{PROJECT}.magpie_reference.product_taxonomy` pt
        LEFT JOIN `{PROJECT}.magpie_reference.product_taxonomy_embeddings` pte
          ON pte.taxonomy_id = pt.taxonomy_id
        WHERE pte.taxonomy_id IS NULL
        {limit_clause}
    """
    params = [bigquery.ScalarQueryParameter("row_limit", "INT64", limit)] if limit else []
    job_config = bigquery.QueryJobConfig(query_parameters=params)
    rows = list(client.query(query, job_config=job_config).result())
    if not rows:
        return 0

    texts = [f"passage: {r.canonical_name}" for r in rows]
    vectors = model.encode(texts, batch_size=BATCH_SIZE, show_progress_bar=False, normalize_embeddings=True)
    now = datetime.now(timezone.utc).isoformat()
    json_rows = [
        {
            "taxonomy_id": r.taxonomy_id,
            "embedding": vec.tolist(),
            "model_version": MODEL_NAME,
            "computed_at": now,
        }
        for r, vec in zip(rows, vectors)
    ]
    return _load_rows(client, json_rows, "magpie_reference.product_taxonomy_embeddings")


def embed_universe_skus(client, model, master_table=None, limit=None):
    scope_clause = "AND u.master_table = @master_table" if master_table else ""
    limit_clause = "LIMIT @row_limit" if limit else ""
    query = f"""
        SELECT u.product_id, u.ecommerce_platform AS platform, u.country, ANY_VALUE(u.sku_name) AS sku_name
        FROM `{PROJECT}.magpie.marketshare_universe_niq` u
        LEFT JOIN `{PROJECT}.magpie_reference.universe_sku_embeddings` ue
          ON ue.product_id = u.product_id AND ue.platform = u.ecommerce_platform AND ue.country = u.country
        WHERE u.month = (SELECT MAX(month) FROM `{PROJECT}.magpie.marketshare_universe_niq`)
          AND ue.product_id IS NULL
          AND u.sku_name IS NOT NULL
        {scope_clause}
        GROUP BY u.product_id, u.ecommerce_platform, u.country
        {limit_clause}
    """
    params = []
    if master_table:
        params.append(bigquery.ScalarQueryParameter("master_table", "STRING", master_table))
    if limit:
        params.append(bigquery.ScalarQueryParameter("row_limit", "INT64", limit))
    job_config = bigquery.QueryJobConfig(query_parameters=params)
    rows = list(client.query(query, job_config=job_config).result())
    if not rows:
        return 0

    texts = [f"query: {r.sku_name}" for r in rows]
    vectors = model.encode(texts, batch_size=BATCH_SIZE, show_progress_bar=False, normalize_embeddings=True)
    now = datetime.now(timezone.utc).isoformat()
    json_rows = [
        {
            "product_id": r.product_id,
            "platform": r.platform,
            "country": r.country,
            "embedding": vec.tolist(),
            "model_version": MODEL_NAME,
            "computed_at": now,
        }
        for r, vec in zip(rows, vectors)
    ]
    return _load_rows(client, json_rows, "magpie_reference.universe_sku_embeddings")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--master-table", default=None,
                         help="Scope universe embedding to one master_table (e.g. shopee_th_toothpaste); omit for full sweep")
    parser.add_argument("--limit", type=int, default=None,
                         help="Cap rows processed this run (smoke-test/pilot use)")
    args = parser.parse_args()

    client = bigquery.Client(project=PROJECT)
    model = load_model()

    n_taxonomy = embed_taxonomy(client, model, limit=args.limit)
    print(f"Embedded {n_taxonomy} product_taxonomy rows")

    n_universe = embed_universe_skus(client, model, master_table=args.master_table, limit=args.limit)
    print(f"Embedded {n_universe} marketshare_universe_niq rows")


if __name__ == "__main__":
    main()
