#!/usr/bin/env python3
"""Builds the candidate-enriched worklist for headless_taxonomy_v2.sh -- all pure SQL/Python, no LLM calls.
Candidates come from the current table AND fuzzy-matched sibling category tables in other countries. See
docs/superpowers/specs/2026-08-21-headless-taxonomy-v2-cross-market-candidates-design.md."""
import argparse
import json
import re
import sys
from pathlib import Path

from google.cloud import bigquery

PROJECT = "sincere-hearth-273704"
_SAFE_TABLE_NAME = re.compile(r"^[a-zA-Z0-9_]+$")
_STOPWORDS = {"for", "and", "or", "of", "the", "a"}
_SQL_DIR = Path(__file__).parent.parent.parent / "sql" / "queries"


def _load_sql(filename):
    return (_SQL_DIR / filename).read_text()


def _validate_table(table):
    if not _SAFE_TABLE_NAME.match(table):
        raise ValueError(f"Unsafe table value for table-name interpolation: {table!r}")


def parse_table_name(table_name):
    """table_name like 'shopee_id_adult_diapers' -> ('shopee', 'id', frozenset({'adult', 'diapers'}))."""
    parts = table_name.split("_")
    platform, country = parts[0], parts[1]
    category_tokens = frozenset(p for p in parts[2:] if p not in _STOPWORDS)
    return platform, country, category_tokens


def jaccard_similarity(a, b):
    if not a and not b:
        return 0.0
    union = a | b
    if not union:
        return 0.0
    return len(a & b) / len(union)


def find_sibling_tables(this_table, all_tables, threshold=0.5):
    """Same platform, different country, category-slug Jaccard similarity >= threshold. Returns
    [(table_name, score), ...] sorted by score descending."""
    platform, country, tokens = parse_table_name(this_table)
    siblings = []
    for other in all_tables:
        if other == this_table:
            continue
        o_platform, o_country, o_tokens = parse_table_name(other)
        if o_platform != platform or o_country == country:
            continue
        score = jaccard_similarity(tokens, o_tokens)
        if score >= threshold:
            siblings.append((other, score))
    siblings.sort(key=lambda pair: -pair[1])
    return siblings


def build_candidate_products_query(product_ids, sku_names, this_table, scope_tables, n=5):
    sql = _load_sql("headless_v2_candidate_products.sql")
    params = [
        bigquery.ArrayQueryParameter("product_ids", "STRING", product_ids),
        bigquery.ArrayQueryParameter("sku_names", "STRING", sku_names),
        bigquery.ScalarQueryParameter("this_table", "STRING", this_table),
        bigquery.ArrayQueryParameter("scope_tables", "STRING", scope_tables),
        bigquery.ScalarQueryParameter("n", "INT64", n),
    ]
    return sql, params


def build_topup_worklist_query(table, month, block_size):
    """Same worklist definition as V1's headless_taxonomy.sh worklist_query() -- 95%-cumulative-GMV
    (GWP-zeroed), unmapped, category_scope_exceptions-excluded gap -- ported to a parameterized query."""
    _validate_table(table)
    sql = f"""
    WITH base AS (
      SELECT s.product_id, s.merchant_name, s.sku_name, s.gmv_monthly, s.flag_GWP,
             pt.canonical_name AS canonical_name, exc.product_id AS excepted_product_id
      FROM `{PROJECT}.master_clean_niq.{table}` s
      LEFT JOIN `{PROJECT}.magpie_reference.product_taxonomy_map` ptm
        ON ptm.product_id = s.product_id AND ptm.master_table = '{table}'
      LEFT JOIN `{PROJECT}.magpie_reference.product_taxonomy` pt ON pt.taxonomy_id = ptm.taxonomy_id
      LEFT JOIN `{PROJECT}.magpie_reference.category_scope_exceptions` exc
        ON exc.product_id = s.product_id AND exc.master_table = '{table}'
      WHERE FORMAT_DATE('%Y-%m', s.month) = @month
      QUALIFY ROW_NUMBER() OVER (
        PARTITION BY s.product_id, s.model_id
        ORDER BY CASE ptm.source WHEN 'LLM' THEN 1 WHEN 'HUMAN' THEN 2 ELSE 3 END, ptm.taxonomy_id ASC
      ) = 1
    ),
    with_cumulative AS (
      SELECT *,
        ROUND(100.0 * SUM(CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END)
                OVER (ORDER BY gmv_monthly DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
              / NULLIF(SUM(CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END) OVER (), 0), 2) AS cumulative_gmv_pct
      FROM base
    )
    SELECT product_id, merchant_name, sku_name, gmv_monthly
    FROM with_cumulative
    WHERE cumulative_gmv_pct <= 95 AND canonical_name IS NULL AND excepted_product_id IS NULL
    ORDER BY gmv_monthly DESC
    LIMIT @block_size
    """
    params = [
        bigquery.ScalarQueryParameter("month", "STRING", month),
        bigquery.ScalarQueryParameter("block_size", "INT64", block_size),
    ]
    return sql, params


_OFFICIAL_STORE_SECTION_RE = re.compile(r"## Official Store Allowlist.*?(?=\n## |\n---\n|\Z)", re.DOTALL)
_MERCHANT_NAME_RE = re.compile(r"`([^`]+)`")


def extract_official_store_merchants(brief_markdown):
    """Pulls merchant names out of the category brief's '## Official Store Allowlist' markdown table (the
    3rd pipe-delimited column, per docs/categories/_TEMPLATE.md's fixed format) -- not the brand or
    brand_id columns, and not the free-text excluded-retailer bullet list below the table."""
    section_match = _OFFICIAL_STORE_SECTION_RE.search(brief_markdown)
    if not section_match:
        return []
    merchants = []
    for line in section_match.group(0).splitlines():
        if not line.strip().startswith("|"):
            continue
        cols = line.split("|")
        if len(cols) < 4:
            continue
        merchant_col = cols[3]
        merchants.extend(_MERCHANT_NAME_RE.findall(merchant_col))
    return merchants


def build_first_run_candidate_pool_query(table, month, exclude_merchants, block_size):
    """The first_run Pass 2 target pool: 95%-cumulative-GMV in-scope products, excluding Official Store
    Allowlist merchants (Pass 1 covers those directly via multimodal read -- they don't need text-candidate
    reference)."""
    _validate_table(table)
    sql = f"""
    WITH base AS (
      SELECT s.product_id, s.merchant_name, s.sku_name, s.gmv_monthly, s.flag_GWP
      FROM `{PROJECT}.master_clean_niq.{table}` s
      WHERE FORMAT_DATE('%Y-%m', s.month) = @month
        AND s.merchant_name NOT IN UNNEST(@exclude_merchants)
      QUALIFY ROW_NUMBER() OVER (PARTITION BY s.product_id ORDER BY s.gmv_monthly DESC) = 1
    ),
    with_cumulative AS (
      SELECT *,
        ROUND(100.0 * SUM(CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END)
                OVER (ORDER BY gmv_monthly DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
              / NULLIF(SUM(CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END) OVER (), 0), 2) AS cumulative_gmv_pct
      FROM base
    )
    SELECT product_id, merchant_name, sku_name, gmv_monthly
    FROM with_cumulative
    WHERE cumulative_gmv_pct <= 95
    ORDER BY gmv_monthly DESC
    LIMIT @block_size
    """
    params = [
        bigquery.ScalarQueryParameter("month", "STRING", month),
        bigquery.ArrayQueryParameter("exclude_merchants", "STRING", exclude_merchants),
        bigquery.ScalarQueryParameter("block_size", "INT64", block_size),
    ]
    return sql, params


def build_brief_markdown_query(category_key):
    sql = f"""
    SELECT brief_markdown FROM `{PROJECT}.magpie_reference.category_brief`
    WHERE category_key = @category_key AND task_type = 'BRIEF'
    """
    params = [bigquery.ScalarQueryParameter("category_key", "STRING", category_key)]
    return sql, params


def run_query(client, sql, params):
    job_config = bigquery.QueryJobConfig(query_parameters=params)
    return [dict(row.items()) for row in client.query(sql, job_config=job_config).result()]


def fetch_brief_markdown(client, table):
    category_key = f"master_clean_niq.{table}"
    sql, params = build_brief_markdown_query(category_key)
    rows = run_query(client, sql, params)
    return rows[0]["brief_markdown"] if rows else ""


def assemble_worklist_json(rows, candidates_by_id):
    worklist = []
    for row in rows:
        pid = row["product_id"]
        worklist.append({
            "product_id": pid,
            "sku_name": row["sku_name"],
            "merchant_name": row.get("merchant_name"),
            "gmv": row["gmv_monthly"],
            "candidates": candidates_by_id.get(pid, []),
        })
    return worklist


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--table", required=True)
    parser.add_argument("--scenario", required=True, choices=["first_run", "top_up"])
    parser.add_argument("--month", required=True)
    parser.add_argument("--block-size", type=int, default=200)
    args = parser.parse_args()

    client = bigquery.Client(project=PROJECT)

    all_tables_sql = f"SELECT table_name FROM `{PROJECT}.master_clean_niq.INFORMATION_SCHEMA.TABLES`"
    all_tables = [r["table_name"] for r in run_query(client, all_tables_sql, [])]
    siblings = find_sibling_tables(args.table, all_tables)
    print(f"Sibling tables for {args.table}: {siblings}", file=sys.stderr)
    scope_tables = [args.table] + [name for name, score in siblings]

    if args.scenario == "top_up":
        sql, params = build_topup_worklist_query(args.table, args.month, args.block_size)
    else:
        brief_markdown = fetch_brief_markdown(client, args.table)
        exclude_merchants = extract_official_store_merchants(brief_markdown)
        print(f"Excluding {len(exclude_merchants)} official-store merchants from Pass 2 pool", file=sys.stderr)
        sql, params = build_first_run_candidate_pool_query(args.table, args.month, exclude_merchants, args.block_size)

    rows = run_query(client, sql, params)
    if not rows:
        print("[]")
        return

    product_ids = [r["product_id"] for r in rows]
    sku_names = [r["sku_name"] for r in rows]
    cand_sql, cand_params = build_candidate_products_query(product_ids, sku_names, args.table, scope_tables)
    cand_rows = run_query(client, cand_sql, cand_params)

    candidates_by_id = {}
    for r in cand_rows:
        candidates_by_id.setdefault(r["worklist_product_id"], []).append({
            "taxonomy_id": r["candidate_taxonomy_id"],
            "canonical_name": r["candidate_canonical_name"],
            "source_table": r["source_table"],
            "match_tier": r["match_tier"],
            "normalized_distance": r["normalized_distance"],
        })

    print(json.dumps(assemble_worklist_json(rows, candidates_by_id)))


if __name__ == "__main__":
    main()
