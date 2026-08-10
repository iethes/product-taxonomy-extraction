#!/usr/bin/env python3
"""Builds the candidate-enriched, strict-tier GMV-sorted QA worklist for targeted_qa_fix_v2.sh -- all pure
SQL/Python, no LLM calls. See docs/superpowers/specs/2026-08-10-targeted-qa-fix-v2-design.md."""
import argparse
import json
import re
import sys
from pathlib import Path

from google.cloud import bigquery

PROJECT = "sincere-hearth-273704"
_SAFE_TABLE_NAME = re.compile(r"^[a-zA-Z0-9_]+$")
_SQL_DIR = Path(__file__).parent.parent.parent / "sql" / "queries"

TIER1_FLAG_COLUMNS = [
    "stub_leak", "duplicate_brand", "wrong_field_order", "brand_casing_mismatch", "excess_content",
    "canonical_field_mismatch", "null_size", "garbage_brand", "count_as_size", "provenance_leak",
]


def _validate_table(table):
    if not _SAFE_TABLE_NAME.match(table):
        raise ValueError(f"Unsafe table value for table-name interpolation: {table!r}")


def _load_sql(filename):
    return (_SQL_DIR / filename).read_text()


def build_worklist_query(table, block_size):
    _validate_table(table)
    sql = f"""
    WITH never_reviewed AS (
      SELECT pt.taxonomy_id, pt.canonical_name, 0 AS tier_rank, 'unlabelled' AS tier,
             CAST(SUM(mast.gmv_monthly) AS INT64) AS gmv
      FROM `{PROJECT}.magpie_reference.product_taxonomy` pt
      JOIN `{PROJECT}.magpie_reference.product_taxonomy_map` m ON m.taxonomy_id = pt.taxonomy_id
      JOIN `{PROJECT}.master_clean_niq.{table}` mast ON mast.product_id = m.product_id
      WHERE m.master_table = @table AND pt._meta IS NULL
      GROUP BY 1, 2
    ),
    unconfident AS (
      SELECT pt.taxonomy_id, pt.canonical_name, 1 AS tier_rank, 'unconfident' AS tier,
             CAST(SUM(mast.gmv_monthly) AS INT64) AS gmv
      FROM `{PROJECT}.magpie_reference.product_taxonomy` pt
      JOIN `{PROJECT}.magpie_reference.product_taxonomy_map` m ON m.taxonomy_id = pt.taxonomy_id
      JOIN `{PROJECT}.master_clean_niq.{table}` mast ON mast.product_id = m.product_id
      WHERE m.master_table = @table AND pt._meta IS NOT NULL
        AND IFNULL(JSON_VALUE(pt._meta, '$.review_confidence'), 'unreviewed') != 'confident'
      GROUP BY 1, 2
    )
    SELECT taxonomy_id, canonical_name, tier, gmv
    FROM (SELECT * FROM never_reviewed UNION ALL SELECT * FROM unconfident)
    ORDER BY tier_rank ASC, gmv DESC
    LIMIT @block_size
    """
    params = [
        bigquery.ScalarQueryParameter("table", "STRING", table),
        bigquery.ScalarQueryParameter("block_size", "INT64", block_size),
    ]
    return sql, params


def build_pending_recheck_query(table):
    _validate_table(table)
    sql = f"""
    SELECT DISTINCT pt.taxonomy_id
    FROM `{PROJECT}.magpie_reference.product_taxonomy` pt
    JOIN `{PROJECT}.magpie_reference.product_taxonomy_map` m ON m.taxonomy_id = pt.taxonomy_id
    WHERE m.master_table = @table
      AND pt._meta IS NOT NULL
      AND JSON_VALUE(pt._meta, '$.review_confidence') IS NULL
    """
    params = [bigquery.ScalarQueryParameter("table", "STRING", table)]
    return sql, params


def build_tier1_sweep_query(taxonomy_ids):
    sql = _load_sql("qa_v2_tier1_sweep.sql")
    params = [bigquery.ArrayQueryParameter("taxonomy_ids", "STRING", taxonomy_ids)]
    return sql, params


def build_taxonomy_candidates_query(taxonomy_ids, n=5):
    sql = _load_sql("qa_v2_taxonomy_candidates.sql")
    params = [
        bigquery.ArrayQueryParameter("taxonomy_ids", "STRING", taxonomy_ids),
        bigquery.ScalarQueryParameter("n", "INT64", n),
    ]
    return sql, params


def build_brand_candidates_query(taxonomy_ids, n=3):
    sql = _load_sql("qa_v2_brand_candidates.sql")
    params = [
        bigquery.ArrayQueryParameter("taxonomy_ids", "STRING", taxonomy_ids),
        bigquery.ScalarQueryParameter("n", "INT64", n),
    ]
    return sql, params


def build_sample_sku_names_query(table, taxonomy_ids):
    _validate_table(table)
    sql = f"""
    SELECT m.taxonomy_id, ARRAY_AGG(DISTINCT s.sku_name IGNORE NULLS LIMIT 3) AS sample_sku_names
    FROM `{PROJECT}.magpie_reference.product_taxonomy_map` m
    JOIN `{PROJECT}.master_clean_niq.{table}` s ON s.product_id = m.product_id
    WHERE m.master_table = @table AND m.taxonomy_id IN UNNEST(@taxonomy_ids)
    GROUP BY 1
    """
    params = [
        bigquery.ScalarQueryParameter("table", "STRING", table),
        bigquery.ArrayQueryParameter("taxonomy_ids", "STRING", taxonomy_ids),
    ]
    return sql, params


def build_promote_query(taxonomy_ids):
    sql = f"""
    UPDATE `{PROJECT}.magpie_reference.product_taxonomy`
    SET _meta = TO_JSON_STRING(STRUCT(
      true AS is_reviewed,
      CURRENT_TIMESTAMP() AS last_reviewed_at,
      'confident' AS review_confidence,
      'correct' AS last_verdict
    ))
    WHERE taxonomy_id IN UNNEST(@taxonomy_ids)
    """
    params = [bigquery.ArrayQueryParameter("taxonomy_ids", "STRING", taxonomy_ids)]
    return sql, params


def clean_taxonomy_ids(flag_rows):
    """flag_rows: list of dict with 'taxonomy_id' + TIER1_FLAG_COLUMNS keys. Returns ids where every flag is
    False -- these are the fast-lane promotion candidates (STEP 1C's judgment-free bulk-promote case)."""
    return [r["taxonomy_id"] for r in flag_rows if not any(r[f] for f in TIER1_FLAG_COLUMNS)]


def assemble_worklist_json(rows, flags_by_id, tax_cands_by_id, brand_cands_by_id, samples_by_id):
    worklist = []
    for row in rows:
        tid = row["taxonomy_id"]
        worklist.append({
            "taxonomy_id": tid,
            "canonical_name": row["canonical_name"],
            "tier": row["tier"],
            "gmv": row["gmv"],
            "tier1_flags": flags_by_id.get(tid, {}),
            "taxonomy_candidates": tax_cands_by_id.get(tid, []),
            "brand_candidates": brand_cands_by_id.get(tid, []),
            "sample_sku_names": samples_by_id.get(tid, []),
        })
    return worklist


def run_query(client, sql, params):
    job_config = bigquery.QueryJobConfig(query_parameters=params)
    return [dict(row.items()) for row in client.query(sql, job_config=job_config).result()]


def fastlane_promote(client, table):
    """STEP 1C-equivalent: bulk-promote fixed-pending-recheck rows that come back Tier-1-clean. No LLM
    judgment -- this is a direct cost removal, these rows never reach claude -p at all."""
    sql, params = build_pending_recheck_query(table)
    pending_ids = [r["taxonomy_id"] for r in run_query(client, sql, params)]
    if not pending_ids:
        return 0
    sql, params = build_tier1_sweep_query(pending_ids)
    flag_rows = run_query(client, sql, params)
    clean_ids = clean_taxonomy_ids(flag_rows)
    if not clean_ids:
        return 0
    sql, params = build_promote_query(clean_ids)
    client.query(sql, job_config=bigquery.QueryJobConfig(query_parameters=params)).result()
    return len(clean_ids)


def fetch_worklist_rows(client, table, block_size):
    sql, params = build_worklist_query(table, block_size)
    return run_query(client, sql, params)


def fetch_tier1_flags(client, taxonomy_ids):
    if not taxonomy_ids:
        return {}
    sql, params = build_tier1_sweep_query(taxonomy_ids)
    rows = run_query(client, sql, params)
    return {r["taxonomy_id"]: {f: r[f] for f in TIER1_FLAG_COLUMNS} for r in rows}


def fetch_taxonomy_candidates(client, taxonomy_ids):
    if not taxonomy_ids:
        return {}
    sql, params = build_taxonomy_candidates_query(taxonomy_ids)
    rows = run_query(client, sql, params)
    result = {}
    for r in rows:
        result.setdefault(r["worklist_taxonomy_id"], []).append({
            "taxonomy_id": r["candidate_taxonomy_id"],
            "canonical_name": r["candidate_canonical_name"],
            "normalized_distance": r["normalized_distance"],
        })
    return result


def fetch_brand_candidates(client, taxonomy_ids):
    if not taxonomy_ids:
        return {}
    sql, params = build_brand_candidates_query(taxonomy_ids)
    rows = run_query(client, sql, params)
    result = {}
    for r in rows:
        result.setdefault(r["worklist_taxonomy_id"], []).append({
            "brand_id": r["candidate_brand_id"],
            "canonical_name": r["candidate_canonical_name"],
            "normalized_distance": r["normalized_distance"],
        })
    return result


def fetch_sample_sku_names(client, table, taxonomy_ids):
    if not taxonomy_ids:
        return {}
    sql, params = build_sample_sku_names_query(table, taxonomy_ids)
    rows = run_query(client, sql, params)
    return {r["taxonomy_id"]: list(r["sample_sku_names"]) for r in rows}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--table", required=True)
    parser.add_argument("--block-size", type=int, default=200)
    args = parser.parse_args()

    client = bigquery.Client(project=PROJECT)

    n_promoted = fastlane_promote(client, args.table)
    print(f"Fast-lane promoted {n_promoted} rows to confident (Tier-1-clean on recheck)", file=sys.stderr)

    rows = fetch_worklist_rows(client, args.table, args.block_size)
    if not rows:
        print("[]")
        return

    taxonomy_ids = [r["taxonomy_id"] for r in rows]
    flags_by_id = fetch_tier1_flags(client, taxonomy_ids)
    tax_cands_by_id = fetch_taxonomy_candidates(client, taxonomy_ids)
    brand_cands_by_id = fetch_brand_candidates(client, taxonomy_ids)
    samples_by_id = fetch_sample_sku_names(client, args.table, taxonomy_ids)

    worklist = assemble_worklist_json(rows, flags_by_id, tax_cands_by_id, brand_cands_by_id, samples_by_id)
    print(json.dumps(worklist))


if __name__ == "__main__":
    main()
