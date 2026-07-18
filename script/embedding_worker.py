#!/usr/bin/env python3
"""Embeds product_taxonomy.canonical_name and marketshare_universe_niq.sku_name text that
isn't in the embeddings tables yet, using a local multilingual-e5-large model. Runs on the
Hetzner VM via cron. Only ever INSERTs into product_taxonomy_embeddings/universe_sku_embeddings
- never touches product_taxonomy, product_taxonomy_map, or marketshare_universe_niq itself.

sku_name_EN preference (added 2026-07-18, task 5b): marketshare_universe_niq.sku_name is often
untranslated/mixed-language/garbled source text (e.g. Thai + English mashed together), which
dilutes the embedding signal against product_taxonomy.canonical_name (clean English). When
--master-table is given, embed_universe_skus instead prefers
master_clean_niq.{master_table}.sku_name_EN (machine-translated English), falling back to raw
marketshare_universe_niq.sku_name per-row when sku_name_EN is NULL/empty. This preference is
scoped to the --master-table case only: an unscoped full sweep has no single master_clean_niq
table to join against (each row could belong to a different category's table), so unscoped runs
keep embedding raw sku_name as before. See docs/superpowers/plans/2026-07-17-embedding-nn-match.md
Appendix, "2026-07-18 update" for the pilot numbers that motivated this.
"""
import argparse
import re
from datetime import datetime, timezone

from google.cloud import bigquery
from sentence_transformers import SentenceTransformer

PROJECT = "sincere-hearth-273704"
MODEL_NAME = "intfloat/multilingual-e5-large"
BATCH_SIZE = 256
_SAFE_TABLE_NAME = re.compile(r"^[a-zA-Z0-9_]+$")


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
    """Embeds unembedded marketshare_universe_niq rows.

    When master_table is given, prefers master_clean_niq.{master_table}.sku_name_EN
    (machine-translated English) over the raw marketshare_universe_niq.sku_name, falling back to
    the raw value per-row when sku_name_EN is NULL/empty. master_clean_niq is the raw per-listing
    source (not deduplicated to product-month grain like marketshare_universe_niq), so we pick one
    sku_name_EN per product via the most recent (month, created_date).

    Unscoped sweeps (master_table=None) keep embedding raw sku_name only — there is no single
    master_clean_niq table to join against when rows can belong to any category.
    """
    limit_clause = "LIMIT @row_limit" if limit else ""
    params = []
    if limit:
        params.append(bigquery.ScalarQueryParameter("row_limit", "INT64", limit))

    if master_table:
        if not _SAFE_TABLE_NAME.match(master_table):
            raise ValueError(f"Unsafe --master-table value for table-name interpolation: {master_table!r}")
        query = f"""
            WITH universe AS (
                SELECT u.product_id, u.ecommerce_platform AS platform, u.country,
                       ANY_VALUE(u.sku_name) AS sku_name
                FROM `{PROJECT}.magpie.marketshare_universe_niq` u
                LEFT JOIN `{PROJECT}.magpie_reference.universe_sku_embeddings` ue
                  ON ue.product_id = u.product_id AND ue.platform = u.ecommerce_platform
                  AND ue.country = u.country
                WHERE u.month = (SELECT MAX(month) FROM `{PROJECT}.magpie.marketshare_universe_niq`)
                  AND ue.product_id IS NULL
                  AND u.sku_name IS NOT NULL
                  AND u.master_table = @master_table
                GROUP BY u.product_id, u.ecommerce_platform, u.country
            ),
            sku_name_en AS (
                SELECT
                    product_id,
                    ARRAY_AGG(sku_name_EN ORDER BY month DESC, created_date DESC LIMIT 1)[OFFSET(0)] AS sku_name_en
                FROM `{PROJECT}.master_clean_niq.{master_table}`
                WHERE sku_name_EN IS NOT NULL AND sku_name_EN != ''
                GROUP BY product_id
            )
            SELECT
                universe.product_id, universe.platform, universe.country,
                COALESCE(NULLIF(en.sku_name_en, ''), universe.sku_name) AS sku_name
            FROM universe
            LEFT JOIN sku_name_en en ON en.product_id = universe.product_id
            {limit_clause}
        """
        params.append(bigquery.ScalarQueryParameter("master_table", "STRING", master_table))
    else:
        query = f"""
            SELECT u.product_id, u.ecommerce_platform AS platform, u.country, ANY_VALUE(u.sku_name) AS sku_name
            FROM `{PROJECT}.magpie.marketshare_universe_niq` u
            LEFT JOIN `{PROJECT}.magpie_reference.universe_sku_embeddings` ue
              ON ue.product_id = u.product_id AND ue.platform = u.ecommerce_platform AND ue.country = u.country
            WHERE u.month = (SELECT MAX(month) FROM `{PROJECT}.magpie.marketshare_universe_niq`)
              AND ue.product_id IS NULL
              AND u.sku_name IS NOT NULL
            GROUP BY u.product_id, u.ecommerce_platform, u.country
            {limit_clause}
        """

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


def embed_mapped_universe_skus(client, model, master_table, limit=None):
    """Embeds only sku_name for products that already have a product_taxonomy_map row for master_table -
    the training-anchor subset, not the full category universe. Used for classifier training backfill."""
    limit_clause = "LIMIT @row_limit" if limit else ""
    query = f"""
        SELECT DISTINCT u.product_id, u.ecommerce_platform AS platform, u.country, u.sku_name
        FROM `{PROJECT}.magpie.marketshare_universe_niq` u
        JOIN `{PROJECT}.magpie_reference.product_taxonomy_map` m
          ON m.product_id = u.product_id AND m.platform = u.ecommerce_platform AND m.country = u.country
        LEFT JOIN `{PROJECT}.magpie_reference.universe_sku_embeddings` ue
          ON ue.product_id = u.product_id AND ue.platform = u.ecommerce_platform AND ue.country = u.country
        WHERE u.month = (SELECT MAX(month) FROM `{PROJECT}.magpie.marketshare_universe_niq`)
          AND u.master_table = @master_table
          AND m.master_table = @master_table
          AND m.source = 'LLM'
          AND ue.product_id IS NULL
          AND u.sku_name IS NOT NULL
        {limit_clause}
    """
    params = [bigquery.ScalarQueryParameter("master_table", "STRING", master_table)]
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
    parser.add_argument("--mapped-only", action="store_true",
                         help="Embed only already-mapped products for --master-table (training backfill), not the full category universe")
    args = parser.parse_args()

    client = bigquery.Client(project=PROJECT)
    model = load_model()

    if args.mapped_only:
        if not args.master_table:
            parser.error("--mapped-only requires --master-table")
        n = embed_mapped_universe_skus(client, model, args.master_table, limit=args.limit)
        print(f"Embedded {n} mapped-only universe rows for {args.master_table}")
        return

    n_taxonomy = embed_taxonomy(client, model, limit=args.limit)
    print(f"Embedded {n_taxonomy} product_taxonomy rows")

    n_universe = embed_universe_skus(client, model, master_table=args.master_table, limit=args.limit)
    print(f"Embedded {n_universe} marketshare_universe_niq rows")


if __name__ == "__main__":
    main()
