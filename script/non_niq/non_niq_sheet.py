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
