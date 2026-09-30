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
      (sku_type vs sku_type_complete, prod_id vs product_id, ecommerce_platform vs ecommerce,
      keywords_typo vs keyword_typo), plus whether the dict table has an optional `_meta` column, live via
      INFORMATION_SCHEMA.COLUMNS -> JSON.

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
      line. Batched at BATCH_SIZE per POST (a 384-dim vector serialises to ~7.5KB of JSON, so a
      single POST would blow past Meilisearch's 100MB payload limit above ~10k rows).

  append-sheet --input-file DOCS.jsonl --dict-table dataset.dict --project P --dataset D
      --identity-col COL --sheet-url URL
      Called from non_niq_qa_v2.sh itself (not from inside the Claude subprocess) once Claude's
      turn ends, using the same STEP 3 JSONL file the index command reads. Re-reads each entry's
      row from BigQuery by (brand, identity_col=identity_value) -- trusts Claude only for WHICH
      row to look up, never for the row's field values -- then appends it to the category's
      taxonomy_url Google Sheet (from the config Sheet's taxonomy_url column), matching cells to
      the target Sheet's own header row by column NAME rather than assuming the same column order
      as the BigQuery table (confirmed live these differ, e.g. susububuk_dict vs its Sheet). A
      missing/empty taxonomy_url for a category is a no-op, not an error.

  forced-merchants --country ID --category "Cookies Biscuit" --platform Shopee
      Called from non_niq_qa_v2.sh's main() to force-include specific merchant_ids in the worklist
      even when they're not product_tier='Tier 1' -- known client-owned/competitor stores worth
      tracking regardless of GMV rank. Reads the "Client OS Only" + "Competitor OS" tabs of a
      fixed reference Sheet (MERCHANT_REFERENCE_SPREADSHEET_ID) via the same _sheets_service() as
      append-sheet, matches rows on (Country, Category Pipeline, Platform), unions merchant_id
      across both tabs. Never raises -- a Sheets hiccup yields an empty list, never blocks a QA run.
"""
from dataclasses import dataclass
from datetime import datetime, timezone
from hashlib import sha256
from typing import Dict, Mapping, Optional, Sequence, Tuple

import argparse
import csv
import io
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

from google.cloud import bigquery
from google.oauth2 import service_account
from googleapiclient.discovery import build
from sentence_transformers import SentenceTransformer

MEILI_URL = "http://34.124.146.29:7700"
MODEL_NAME = "intfloat/multilingual-e5-small"
BATCH_SIZE = 256
EMBED_DIM = 384

SHEETS_SCOPES = ["https://www.googleapis.com/auth/spreadsheets"]
# client-util@sincere-hearth-273704.iam.gserviceaccount.com -- ADC (gcloud user credentials)
# can't be used here: gcloud's own OAuth client isn't Google-verified for the spreadsheets scope
# and the consent screen hard-blocks the request (confirmed live 2026-08-20). Service accounts
# don't hit that wall -- scopes are requested at token-mint time, not baked into a one-time
# interactive consent grant.
SHEET_KEY_FILE = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "keys", "client-util.json",
)

CONFIG_CSV_URL = (
    "https://docs.google.com/spreadsheets/d/e/2PACX-1vQfqTVdo1ubO40dBBGzECaXVruIefLZpfX6KSFVHzY2gXv2dE-VHDofMC2Q_1tY5LwOmYJPG0kwwxN4"
    "/pub?gid=149787162&single=true&output=csv"
)

# Merchant force-include reference Sheet -- not published to web (unlike CONFIG_CSV_URL), and CSV
# export only covers one tab per URL anyway, so this reads live via the Sheets API instead
# (confirmed live: client-util already has read access, no new sharing needed).
MERCHANT_REFERENCE_SPREADSHEET_ID = "1Nf7TbmRhViS_vN-PNTXXSFEoGMoW4eKzYXHQEQjk--U"
MERCHANT_REFERENCE_TABS = ["Client OS Only", "Competitor OS"]

# Country column on that Sheet is a full name (confirmed live: Indonesia/Thailand/Singapore/
# Malaysia/Vietnam/Philippines) -- non_niq_qa_v2.sh's own --country arg is the 2-letter code.
COUNTRY_NAME_TO_CODE = {
    "Indonesia": "ID", "Thailand": "TH", "Singapore": "SG",
    "Malaysia": "MY", "Vietnam": "VN", "Philippines": "PH",
}

ROW_FIELDS = ["category", "dataset", "ecommerce_platform", "table", "master_table_prod",
              "product_id_dict_qa", "product_id_dict", "dict", "filter_table", "0", "taxonomy_url"]

QA_PK_CANDIDATES = ["product_id", "prod_id"]
QA_PLATFORM_CANDIDATES = ["ecommerce_platform", "ecommerce"]
DICT_IDENTITY_CANDIDATES = ["sku_type_complete", "sku_type"]
DICT_TYPO_CANDIDATES = ["keywords_typo", "keyword_typo"]
# (QA column, dictionary column) pairs casefold auto-confirm copies from the matched dictionary row.
CASEFOLD_COPY_COLUMNS = (
    ("sku_type_abbott", "sku_type_abbott"),
    ("keywords", "keywords"),
    ("lookup", "keywords"),
)


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
        "qa_platform_col": pick_column(
            qa_cols, QA_PLATFORM_CANDIDATES, f"{qa_table} platform"
        ),
        "dict_identity_col": pick_column(dict_cols, DICT_IDENTITY_CANDIDATES, f"{dict_table} identity"),
        "dict_typo_col": pick_column(dict_cols, DICT_TYPO_CANDIDATES, f"{dict_table} typo"),
        "dict_has_meta": "_meta" in dict_cols,
    }


# ---------------------------------------------------------------------------
# Update-labelling sync: duplicate resolution + tier bucket logic (pure)
# ---------------------------------------------------------------------------

def build_worklist_identity(row):
    """Returns (product_id, platform, normalized_sku_name) for a worklist row, or None if the row
    has no usable product_id/sku_name -- a blank identity must never become a wildcard match
    against every blank-titled QA row."""
    product_id, platform, sku_name = worklist_row_key(row)
    normalized = re.sub(r"\s+", " ", sku_name.strip())
    if not product_id or not normalized:
        return None
    return (product_id, platform, normalized)


def _non_null_count(row):
    """Count of row's fields that are non-null and non-blank (ignoring the literal 'nan' string
    some legacy exports use for missing values)."""
    count = 0
    for value in row.values():
        if value is None:
            continue
        text = str(value).strip()
        if text and text.lower() != "nan":
            count += 1
    return count


def _dedup_sort_key(row):
    meta_raw = row.get("_meta") or row.get("meta") or "{}"
    try:
        meta = json.loads(meta_raw)
    except (TypeError, ValueError):
        meta = {}
    return (_non_null_count(row), str(meta.get("timestamp", "")))


def select_duplicates_to_delete(qa_rows_by_identity):
    """qa_rows_by_identity: {(product_id, platform, normalized_sku_name): [row_dict, ...]}.
    Returns a flat list of row dicts to DELETE -- every row in a >1-row group except the one with
    the most non-null fields (ties broken by the latest _meta.timestamp)."""
    to_delete = []
    for rows in qa_rows_by_identity.values():
        if len(rows) <= 1:
            continue
        ordered = sorted(rows, key=_dedup_sort_key, reverse=True)
        to_delete.extend(ordered[1:])
    return to_delete


def tier_for_share(cumulative_share):
    """Reference tool's cumulative-GMV-share bucket rule (_pipeline.py build_update_query)."""
    if cumulative_share <= 0.8:
        return "Tier 1"
    if cumulative_share <= 0.9:
        return "Tier 2"
    return "Tier 3"


# ---------------------------------------------------------------------------
# Update-labelling sync: SQL builders (pure -- return SQL text, no execution)
# ---------------------------------------------------------------------------

def _platform_filter_sql(platform):
    """Python port of the bash `platform_match_clause` / v3.py `_platform_match_sql` -- Tokopedia's
    own first-party channel ('Tokopedia | Shop') must stay in the same population as 'Tokopedia'
    for GMV/tier purposes; every other platform matches its exact value."""
    if platform == "Tokopedia":
        return "IN ('Tokopedia', 'Tokopedia | Shop')"
    return "= @platform"


def build_dedupe_lookup_sql(qa_table, qa_pk_col, qa_platform_col):
    return """
WITH identities AS (
  SELECT product_id, platform, normalized_sku_name FROM UNNEST(@identities)
)
SELECT TO_JSON_STRING(q) AS row_json, i.product_id, i.platform, i.normalized_sku_name
FROM `%s` q
JOIN identities i
  ON q.%s = i.product_id AND q.%s = i.platform
  AND REGEXP_REPLACE(TRIM(q.sku_name), r'\\s+', ' ') = i.normalized_sku_name
""" % (qa_table, qa_pk_col, qa_platform_col)


def build_dedupe_delete_sql(qa_table, qa_pk_col, qa_platform_col):
    return """
DELETE FROM `%s`
WHERE STRUCT(%s AS pid, %s AS platform, sku_name AS sku_name, _meta AS meta)
  IN UNNEST(@to_delete)
""" % (qa_table, qa_pk_col, qa_platform_col)


def build_master_sync_sql(master_table, sku_col, set_qa_status, set_source_pid):
    extra_sets = ""
    if set_qa_status:
        extra_sets += ",\n  m.qa_status = 'Reviewed'"
    if set_source_pid:
        extra_sets += ",\n  m.source_pid = s.source_pid"
    return """
UPDATE `%s` m
SET
  m.%s = s.sku_type_complete,
  m.brand = s.brand%s
FROM (SELECT * FROM UNNEST(@records)) s
WHERE m.product_id = s.product_id
  AND m.ecommerce_platform = s.ecommerce_platform
  AND FORMAT_DATE('%%Y-%%m', m.month) = @month
  AND REGEXP_REPLACE(TRIM(m.sku_name), r'\\s+', ' ') = s.normalized_sku_name
""" % (master_table, sku_col, extra_sets)


def build_tier_recalc_sql(master_table, filter_table, platform_filter):
    return """
UPDATE `%s` m
SET m.product_tier = t.new_tier
FROM (
  SELECT product_id,
    CASE
      WHEN cum_share <= 0.8 THEN 'Tier 1'
      WHEN cum_share <= 0.9 THEN 'Tier 2'
      ELSE 'Tier 3'
    END AS new_tier
  FROM (
    SELECT product_id, gmv_monthly,
      SUM(gmv_monthly) OVER (
        ORDER BY gmv_monthly DESC, product_id ASC
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ) / NULLIF(SUM(gmv_monthly) OVER (), 0) AS cum_share
    FROM `%s`
    WHERE FORMAT_DATE('%%Y-%%m', month) = @month AND country = @country AND category = @category
      AND ecommerce_platform %s
      AND product_id NOT IN (SELECT product_id FROM `%s`)
  )
) t
WHERE m.product_id = t.product_id
  AND FORMAT_DATE('%%Y-%%m', m.month) = @month AND m.country = @country AND m.category = @category
  AND m.ecommerce_platform %s
""" % (master_table, master_table, platform_filter, filter_table, platform_filter)


def build_tier_null_sql(master_table, filter_table, platform_filter):
    return """
UPDATE `%s` m
SET m.product_tier = NULL
WHERE FORMAT_DATE('%%Y-%%m', m.month) = @month AND m.country = @country AND m.category = @category
  AND m.ecommerce_platform %s
  AND m.product_id IN (SELECT product_id FROM `%s`)
""" % (master_table, platform_filter, filter_table)


# ---------------------------------------------------------------------------
# Update-labelling sync: Step 1 -- QA-table duplicate resolution (BigQuery)
# ---------------------------------------------------------------------------

def fetch_qa_rows_for_identities(client, project, qa_table, qa_pk_col, qa_platform_col, identities):
    """identities: iterable of (product_id, platform, normalized_sku_name). Returns
    {(product_id, platform, normalized_sku_name): [row_dict, ...]} for every QA row matching one
    of those identities. An identity with zero matching rows is simply absent from the result --
    callers must not assume every requested identity comes back."""
    identities = list(identities)
    if not identities:
        return {}
    fqtn = "%s.%s" % (project, qa_table)
    identity_param = bigquery.ArrayQueryParameter(
        "identities", "STRUCT", [
            bigquery.StructQueryParameter(
                None,
                bigquery.ScalarQueryParameter("product_id", "STRING", pid),
                bigquery.ScalarQueryParameter("platform", "STRING", platform),
                bigquery.ScalarQueryParameter("normalized_sku_name", "STRING", sku),
            )
            for pid, platform, sku in identities
        ],
    )
    sql = build_dedupe_lookup_sql(fqtn, qa_pk_col, qa_platform_col)
    rows = client.query(
        sql, job_config=bigquery.QueryJobConfig(query_parameters=[identity_param]),
    ).result()
    grouped = {}
    for row in rows:
        key = (row.product_id, row.platform, row.normalized_sku_name)
        grouped.setdefault(key, []).append(json.loads(row.row_json))
    return grouped


def delete_qa_duplicate_rows(client, project, qa_table, qa_pk_col, qa_platform_col, rows_to_delete):
    """Deletes each row in rows_to_delete (full QA-table row dicts) and logs it to
    magpie_reference.non_niq_taxonomy_insert_log in the same BigQuery script -- QA tables are
    otherwise insert-only, so every delete here needs the same forensic trail as a new taxonomy
    row."""
    if not rows_to_delete:
        return 0
    fqtn = "%s.%s" % (project, qa_table)
    delete_param = bigquery.ArrayQueryParameter(
        "to_delete", "STRUCT", [
            bigquery.StructQueryParameter(
                None,
                bigquery.ScalarQueryParameter("pid", "STRING", str(row.get(qa_pk_col, ""))),
                bigquery.ScalarQueryParameter("platform", "STRING", str(row.get(qa_platform_col, ""))),
                bigquery.ScalarQueryParameter("sku_name", "STRING", str(row.get("sku_name", ""))),
                bigquery.ScalarQueryParameter("meta", "STRING", str(row.get("_meta", ""))),
            )
            for row in rows_to_delete
        ],
    )
    log_param = bigquery.ArrayQueryParameter(
        "log_rows", "STRUCT", [
            bigquery.StructQueryParameter(
                None,
                bigquery.ScalarQueryParameter("target_table", "STRING", fqtn),
                bigquery.ScalarQueryParameter(
                    "created_at", "TIMESTAMP",
                    datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
                ),
                bigquery.ScalarQueryParameter(
                    "row_json", "STRING",
                    json.dumps({"action": "dedup_delete", "deleted_row": row}, default=str),
                ),
            )
            for row in rows_to_delete
        ],
    )
    script = "\n".join([
        "BEGIN TRANSACTION;",
        build_dedupe_delete_sql(fqtn, qa_pk_col, qa_platform_col) + ";",
        "INSERT INTO `%s.magpie_reference.non_niq_taxonomy_insert_log`"
        " (target_table, created_at, row_json)" % project,
        "SELECT target_table, created_at, PARSE_JSON(row_json) FROM UNNEST(@log_rows);",
        "COMMIT;",
    ])
    client.query(
        script,
        job_config=bigquery.QueryJobConfig(query_parameters=[delete_param, log_param]),
    ).result()
    return len(rows_to_delete)


def dedupe_qa_table(client, project, qa_table, qa_pk_col, qa_platform_col, identities):
    """Full Step 1: fetch QA rows for these identities, resolve duplicates, delete the losers
    (logged), return ({identity: kept_row_dict}, duplicates_deleted_count). An identity with no QA
    row at all (unresolved/blocked this session) is simply absent from the returned map."""
    grouped = fetch_qa_rows_for_identities(
        client, project, qa_table, qa_pk_col, qa_platform_col, identities,
    )
    to_delete = select_duplicates_to_delete(grouped)
    if to_delete:
        delete_qa_duplicate_rows(client, project, qa_table, qa_pk_col, qa_platform_col, to_delete)
    kept = {}
    for identity, group_rows in grouped.items():
        remaining = [r for r in group_rows if r not in to_delete]
        if remaining:
            kept[identity] = remaining[0]
    return kept, len(to_delete)


# ---------------------------------------------------------------------------
# Update-labelling sync: Step 2 -- master-table sync (BigQuery)
# ---------------------------------------------------------------------------

def resolve_master_sync_columns(client, project, master_table):
    cols = _table_columns(client, project, master_table)
    if "sku_type_complete" in cols:
        sku_col = "sku_type_complete"
    elif "sku_type" in cols:
        sku_col = "sku_type"
    else:
        sku_col = None
    return {
        "sku_col": sku_col,
        "has_qa_status": "qa_status" in cols,
        "has_source_pid": "source_pid" in cols,
        "has_product_tier": "product_tier" in cols,
    }


def sync_master_table(client, project, master_table, qa_table, kept_rows_by_identity,
                       excluded_product_ids, month, master_columns, qa_identity_col):
    """kept_rows_by_identity: {(product_id, platform, normalized_sku_name): row_dict} -- the single
    QA row (post-dedup) for each identity. excluded_product_ids: product_ids to skip entirely
    (filtered this session -- there is no taxonomy to write for them, see Step 3 instead)."""
    sku_col = master_columns["sku_col"]
    if sku_col is None:
        return 0
    records = []
    for (product_id, platform, normalized_sku_name), row in kept_rows_by_identity.items():
        if product_id in excluded_product_ids:
            continue
        identity_value = str(row.get(qa_identity_col, "")).strip()
        brand = str(row.get("brand", "")).strip()
        if not identity_value or not brand:
            continue
        records.append({
            "product_id": product_id,
            "ecommerce_platform": platform,
            "normalized_sku_name": normalized_sku_name,
            "sku_type_complete": identity_value,
            "brand": brand,
            "source_pid": "%s.%s" % (project, qa_table),
        })
    if not records:
        return 0
    fqtn = "%s.%s" % (project, master_table)
    record_fields = (
        "product_id", "ecommerce_platform", "normalized_sku_name",
        "sku_type_complete", "brand", "source_pid",
    )
    record_param = bigquery.ArrayQueryParameter(
        "records", "STRUCT", [
            bigquery.StructQueryParameter(
                None,
                *[bigquery.ScalarQueryParameter(field, "STRING", record[field]) for field in record_fields],
            )
            for record in records
        ],
    )
    month_param = bigquery.ScalarQueryParameter("month", "STRING", month)
    sql = build_master_sync_sql(
        fqtn, sku_col, master_columns["has_qa_status"], master_columns["has_source_pid"],
    )
    job = client.query(
        sql, job_config=bigquery.QueryJobConfig(query_parameters=[record_param, month_param]),
    )
    job.result()
    return job.num_dml_affected_rows or 0


# ---------------------------------------------------------------------------
# Update-labelling sync: Step 3 -- tier recalculation (BigQuery)
# ---------------------------------------------------------------------------

def filtered_product_ids(client, project, filter_table, product_ids):
    product_ids = sorted({str(p) for p in product_ids if p})
    if not product_ids:
        return set()
    fqtn = "%s.%s" % (project, filter_table)
    param = bigquery.ArrayQueryParameter("product_ids", "STRING", product_ids)
    sql = "SELECT DISTINCT product_id FROM `%s` WHERE product_id IN UNNEST(@product_ids)" % fqtn
    rows = client.query(
        sql, job_config=bigquery.QueryJobConfig(query_parameters=[param]),
    ).result()
    return {row.product_id for row in rows}


def recalc_tier_if_needed(client, project, master_table, filter_table, month, platform,
                           country, category, filtered_ids):
    """Step 3: only runs the (expensive, whole-partition) tier recompute when filtered_ids is
    non-empty -- i.e. this session's worklist touches at least one currently-filtered product.
    Idempotent -- safe to call even when nothing actually changed this session, since recomputing
    an unchanged partition reproduces the same tier values it already has."""
    if not filtered_ids:
        return {"ran": False, "filtered_count": 0}
    platform_filter = _platform_filter_sql(platform)
    master_fqtn = "%s.%s" % (project, master_table)
    filter_fqtn = "%s.%s" % (project, filter_table)
    params = [
        bigquery.ScalarQueryParameter("month", "STRING", month),
        bigquery.ScalarQueryParameter("country", "STRING", country),
        bigquery.ScalarQueryParameter("category", "STRING", category),
    ]
    if platform_filter == "= @platform":
        params.append(bigquery.ScalarQueryParameter("platform", "STRING", platform))
    recalc_sql = build_tier_recalc_sql(master_fqtn, filter_fqtn, platform_filter)
    client.query(recalc_sql, job_config=bigquery.QueryJobConfig(query_parameters=params)).result()
    null_sql = build_tier_null_sql(master_fqtn, filter_fqtn, platform_filter)
    client.query(null_sql, job_config=bigquery.QueryJobConfig(query_parameters=params)).result()
    return {"ran": True, "filtered_count": len(filtered_ids)}


# ---------------------------------------------------------------------------
# Update-labelling sync: top-level entry point
# ---------------------------------------------------------------------------

def sync_labelling(client, project, qa_table, qa_pk_col, qa_platform_col, master_table,
                    filter_table, rows, month, platform, country, category,
                    qa_identity_col="sku_type_complete"):
    """Scoped to one QA session's own worklist rows. Runs, in order:
      1. dedupe_qa_table -- resolve duplicate QA rows for this worklist's identities.
      2. sync_master_table -- propagate the kept QA rows into master_table's taxonomy columns.
      3. recalc_tier_if_needed -- only if this worklist touches a currently-filtered product.
    Never raises for a worklist with no usable identities."""
    identities = set()
    product_ids = set()
    for row in rows:
        identity = build_worklist_identity(row)
        if identity is None:
            continue
        identities.add(identity)
        product_ids.add(identity[0])
    if not identities:
        return {
            "duplicates_removed": 0, "master_rows_updated": 0,
            "tier_recalc": {"ran": False, "filtered_count": 0},
        }

    kept, duplicates_removed = dedupe_qa_table(
        client, project, qa_table, qa_pk_col, qa_platform_col, identities,
    )
    excluded = filtered_product_ids(client, project, filter_table, product_ids)
    master_columns = resolve_master_sync_columns(client, project, master_table)
    updated = sync_master_table(
        client, project, master_table, qa_table, kept, excluded, month,
        master_columns, qa_identity_col,
    )
    tier_result = recalc_tier_if_needed(
        client, project, master_table, filter_table, month, platform, country, category, excluded,
    )
    return {
        "duplicates_removed": duplicates_removed,
        "master_rows_updated": updated,
        "tier_recalc": tier_result,
    }


def _cmd_sync_labelling(args):
    rows = [json.loads(line) for line in open(args.input_file) if line.strip()]
    client = bigquery.Client(project=args.project)
    result = sync_labelling(
        client, args.project, args.qa_table, args.qa_pk_col, args.qa_platform_col,
        args.master_table, args.filter_table, rows, args.month, args.platform,
        args.country, args.category, qa_identity_col=args.qa_identity_col,
    )
    print(json.dumps(result))


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


def worklist_row_key(row):
    """Return the product/platform/title identity used throughout a QA run."""
    return (
        str(row.get("product_id", "")),
        str(row.get("ecommerce_platform", "")),
        str(row.get("sku_name", row.get("query_sku_name", ""))),
    )


def casefold_title_matches(rows, hits, identity_fields):
    """Return unambiguous candidates whose non-empty titles match case-insensitively."""
    hits_by_key = {}
    for hit in hits:
        if not isinstance(hit, Mapping):
            continue
        platform = hit.get("ecommerce_platform")
        product_id = str(hit.get("product_id", hit.get("id", "")))
        platform = str(platform) if isinstance(platform, str) else None
        query_sku_name = hit.get("query_sku_name")
        key = (
            product_id,
            platform,
            str(query_sku_name),
        ) if isinstance(query_sku_name, str) else (product_id, platform)
        candidates = hit.get("candidates", [])
        hits_by_key[key] = candidates if isinstance(candidates, list) else []
    matches = {}
    for row in rows:
        title = row.get("sku_name")
        if not isinstance(title, str) or not title.strip():
            continue
        row_key = worklist_row_key(row)
        candidates = hits_by_key.get(
            row_key,
            hits_by_key.get(
                (row_key[0], row_key[1]),
                hits_by_key.get((row_key[0], None), []),
            ),
        )
        matched_candidate = None
        matched_identity = None
        for candidate in candidates:
            if (
                not isinstance(candidate, Mapping)
                or not isinstance(candidate.get("sku_name"), str)
                or not candidate["sku_name"].strip()
                or candidate["sku_name"].casefold() != title.casefold()
                or not all(
                    isinstance(candidate.get(field), str) and candidate[field].strip()
                    for field in identity_fields
                )
            ):
                continue
            candidate_identity = tuple(candidate[field].strip() for field in identity_fields)
            if matched_candidate is None:
                matched_candidate = candidate
                matched_identity = candidate_identity
            elif candidate_identity != matched_identity:
                matched_candidate = None
                break
        if matched_candidate is not None:
            matches[row_key] = matched_candidate
    return matches


def confirm_casefold_matches(
    client, project, qa_table, qa_pk_col, qa_platform_col, rows, hits,
    *, qa_identity_col="sku_type_complete", dict_table=None, dict_identity_col=None,
    extra_identity_fields=(),
):
    """Write idempotent confident QA rows for casefold-exact Meilisearch matches."""
    extra_identity_fields = tuple(extra_identity_fields)
    if bool(dict_table) != bool(dict_identity_col):
        raise ValueError("dictionary table and identity column must be configured together")
    if not dict_table and not extra_identity_fields:
        raise ValueError("a live dictionary or full taxonomy fields are required")
    if not qa_identity_col:
        raise ValueError("QA identity column is required")
    identity_fields = ("brand", "sku_type_complete") + extra_identity_fields
    matches = casefold_title_matches(rows, hits, identity_fields)
    if not matches:
        return set()
    if dict_table:
        pairs = {
            (
                str(candidate["brand"]).strip(),
                str(candidate.get(dict_identity_col, candidate["sku_type_complete"])).strip(),
            )
            for candidate in matches.values()
        }
        pair_parameter = bigquery.ArrayQueryParameter(
            "requested", "STRUCT", [
                bigquery.StructQueryParameter(
                    None,
                    bigquery.ScalarQueryParameter("brand", "STRING", brand),
                    bigquery.ScalarQueryParameter("identity_value", "STRING", identity),
                )
                for brand, identity in sorted(pairs)
            ],
        )
        live_rows = client.query(
            """WITH requested AS (
  SELECT brand, identity_value FROM UNNEST(@requested)
)
SELECT d.brand, d.`%s` AS identity_value
FROM `%s.%s` d
JOIN requested r ON d.brand = r.brand AND d.`%s` = r.identity_value""" % (
                dict_identity_col, project, dict_table, dict_identity_col,
            ),
            job_config=bigquery.QueryJobConfig(query_parameters=[pair_parameter]),
        ).result()
        live = set()
        for row in live_rows:
            values = dict(row.items())
            live.add((str(values["brand"]), str(values["identity_value"])))
    else:
        live = None
    now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    records = []
    record_keys = set()
    for row in rows:
        row_key = worklist_row_key(row)
        candidate = matches.get(row_key)
        if candidate is None:
            continue
        product_id, platform, sku_name = row_key
        brand = str(candidate["brand"]).strip()
        identity = str(candidate["sku_type_complete"]).strip()
        if dict_table:
            dictionary_identity = str(
                candidate.get(dict_identity_col, identity)
            ).strip()
            if (brand, dictionary_identity) not in live:
                continue
        if row_key in record_keys:
            continue
        taxonomy = {field: str(candidate[field]).strip() for field in extra_identity_fields}
        auto_match_id = sha256(json.dumps({
            "product_id": product_id,
            "ecommerce_platform": platform,
            "sku_name": sku_name,
            **{field: str(candidate[field]).strip() for field in identity_fields},
        }, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        record = {
            "product_id": product_id,
            "ecommerce_platform": platform,
            "sku_name": sku_name,
            "brand": brand,
            qa_identity_col: identity,
            "auto_match_id": auto_match_id,
            "meta": json.dumps({
                "source": "meilisearch_casefold_exact",
                "qa_confidence": "confident",
                "timestamp": now,
                "candidate_product_id": str(candidate.get("product_id", "")),
                "auto_match_id": auto_match_id,
            }, separators=(",", ":")),
            **taxonomy,
        }
        if extra_identity_fields:
            record["image"] = str(row.get("image", ""))
        if dict_table:
            record["dictionary_identity"] = dictionary_identity
        records.append(record)
        record_keys.add(row_key)
    if not records:
        return set()
    record_fields = (
        "product_id", "ecommerce_platform", "sku_name", "brand", qa_identity_col,
        *(("dictionary_identity",) if dict_table else ()),
        *extra_identity_fields,
        *(("image",) if extra_identity_fields else ()),
        "auto_match_id", "meta",
    )
    parameter = bigquery.ArrayQueryParameter(
        "matches", "STRUCT", [
            bigquery.StructQueryParameter(
                None,
                *[
                    bigquery.ScalarQueryParameter(field, "STRING", record[field])
                    for field in record_fields
                ],
            )
            for record in records
        ],
    )
    table = "`%s.%s`" % (project, qa_table)
    dictionary_join = ""
    if dict_table:
        dictionary_join = "JOIN `%s.%s` d ON d.brand = m.brand AND d.`%s` = m.dictionary_identity" % (
            project, dict_table, dict_identity_col,
        )
    qa_identity_match = (
        "\n AND q.brand = m.brand\n AND q.`%s` = m.%s" % (
            qa_identity_col, qa_identity_col,
        )
    )
    qa_identity_match += "".join(
        "\n AND q.%s = m.%s" % (field, field)
        for field in extra_identity_fields
    )
    if extra_identity_fields:
        insert_columns = (
            "`%s`, `%s`, brand, sku_name, `%s`, %s, image, keywords, "
            "timestamp, _meta"
        ) % (
            qa_pk_col, qa_platform_col, qa_identity_col,
            ", ".join(extra_identity_fields),
        )
        select_columns = (
            "m.product_id, m.ecommerce_platform, m.brand, m.sku_name, "
            "m.%s, %s, m.image, m.%s, CURRENT_TIMESTAMP(), m.meta"
        ) % (
            qa_identity_col,
            ", ".join("m.%s" % field for field in extra_identity_fields),
            qa_identity_col,
        )
    else:
        # Copy the matched dictionary row's derived columns too (only where both tables have them);
        # without this susubayi rows landed with NULL sku_type_abbott/keywords/lookup.
        copy_cols = []
        if dict_table:
            qa_cols = _table_columns(client, project, qa_table)
            dict_cols = _table_columns(client, project, dict_table)
            copy_cols = [
                (qa_col, dict_col) for qa_col, dict_col in CASEFOLD_COPY_COLUMNS
                if qa_col in qa_cols and dict_col in dict_cols and qa_col != qa_identity_col
            ]
        insert_columns = "`%s`, `%s`, brand, sku_name, `%s`, %s_meta" % (
            qa_pk_col, qa_platform_col, qa_identity_col,
            "".join("`%s`, " % qa_col for qa_col, _ in copy_cols),
        )
        select_columns = (
            "m.product_id, m.ecommerce_platform, m.brand, m.sku_name, "
            "m.%s, %sm.meta" % (
                qa_identity_col, "".join("d.`%s`, " % dict_col for _, dict_col in copy_cols),
            )
        )
    # The dictionary key (brand + identity) is not always unique (bundle vs single-pack rows), so
    # the join can fan out. Ambiguous matches are skipped and stay residual for the agent.
    unique_match = (
        "\nQUALIFY COUNT(*) OVER (PARTITION BY m.product_id, m.ecommerce_platform, m.sku_name) = 1"
        if dict_table else ""
    )
    client.query(
        """BEGIN TRANSACTION;
INSERT INTO %s (%s)
SELECT %s
FROM UNNEST(@matches) m
%s
WHERE NOT EXISTS (
  SELECT 1 FROM %s q
  WHERE q.`%s` = m.product_id
    AND q.`%s` = m.ecommerce_platform
    AND q.sku_name = m.sku_name
)%s;
COMMIT TRANSACTION;""" % (
            table, insert_columns, select_columns, dictionary_join,
            table, qa_pk_col, qa_platform_col, unique_match,
        ),
        job_config=bigquery.QueryJobConfig(query_parameters=[parameter]),
    ).result()
    readback = client.query(
        """SELECT DISTINCT m.product_id, m.ecommerce_platform, m.sku_name
FROM UNNEST(@matches) m
JOIN %s q
  ON q.`%s` = m.product_id
 AND q.`%s` = m.ecommerce_platform
 AND q.sku_name = m.sku_name%s
%s""" % (
            table, qa_pk_col, qa_platform_col, qa_identity_match, dictionary_join,
        ),
        job_config=bigquery.QueryJobConfig(query_parameters=[parameter]),
    ).result()
    return {worklist_row_key(dict(row.items())) for row in readback}


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
        result = {
            "id": line["id"],
            "product_id": str(line.get("product_id", line["id"])),
            "query_sku_name": str(line.get("text", "")),
            "candidates": candidates,
        }
        if "ecommerce_platform" in line:
            result["ecommerce_platform"] = str(line["ecommerce_platform"])
        results.append(result)
    return results


# ---------------------------------------------------------------------------
# Indexing: embed + upsert newly-minted taxonomy entries into Meilisearch
# ---------------------------------------------------------------------------

def _ensure_index(meili_url, index_uid, strict=False):
    """Create/configure an index and optionally return setup task UIDs."""
    task_uids = []
    existing = _meili_request(meili_url, "GET", "/indexes?limit=200")
    uids = {r["uid"] for r in existing.get("results", [])}
    if index_uid not in uids:
        response = _meili_request(
            meili_url, "POST", "/indexes", {"uid": index_uid, "primaryKey": "product_id"},
        )
        if strict:
            task_uids.append(response.get("taskUid"))
    response = _meili_request(meili_url, "PATCH", f"/indexes/{index_uid}/settings", {
        "searchableAttributes": ["sku_name", "sku_type_complete", "brand", "product_type"],
        "embedders": {"default": {"source": "userProvided", "dimensions": EMBED_DIM}},
    })
    if strict:
        task_uids.append(response.get("taskUid"))
    if strict and any(task_uid is None for task_uid in task_uids):
        raise RuntimeError("Meilisearch index setup did not return taskUid")
    return tuple(task_uids)


def ensure_index(meili_url, index_uid):
    """Create/configure an index for legacy v2 callers."""
    _ensure_index(meili_url, index_uid)


def _prepare_index_documents(lines, meili_url, meili_index, model=None, strict_setup=False):
    if not lines:
        return []
    model = model or SentenceTransformer(MODEL_NAME)
    setup_tasks = _ensure_index(meili_url, meili_index, strict=strict_setup)
    if strict_setup:
        for task_uid in setup_tasks:
            _wait_for_meili_task(meili_url, task_uid, 60, 0.25)
    texts = [_format_passage_text(line["sku_name"]) for line in lines]
    vectors = model.encode(
        texts,
        batch_size=BATCH_SIZE,
        show_progress_bar=False,
        normalize_embeddings=True,
    )
    return [
        {**line, "product_id": str(line["product_id"]), "_vectors": {"default": vector.tolist()}}
        for line, vector in zip(lines, vectors)
    ]



def index_documents(lines, meili_url, meili_index, model=None):
    """Submit document upserts and return their count for legacy v2 callers."""
    docs = _prepare_index_documents(lines, meili_url, meili_index, model)
    for index in range(0, len(docs), BATCH_SIZE):
        _meili_request(meili_url, "POST", f"/indexes/{meili_index}/documents", docs[index:index + BATCH_SIZE])
    return len(docs)


def _wait_for_meili_task(meili_url, task_uid, timeout, poll_interval):
    deadline = time.monotonic() + timeout
    while True:
        task = _meili_request(meili_url, "GET", f"/tasks/{task_uid}")
        status = task.get("status")
        if status == "succeeded":
            return
        if status in {"failed", "canceled"}:
            error = task.get("error")
            message = error.get("message") if isinstance(error, Mapping) else str(error or status)
            raise RuntimeError(f"Meilisearch task {task_uid} {status}: {message}")
        if time.monotonic() >= deadline:
            raise RuntimeError(f"Meilisearch task {task_uid} did not finish before timeout")
        time.sleep(poll_interval)


def index_documents_strict(
    lines, meili_url, meili_index, model=None, timeout=60, poll_interval=0.25,
):
    """Submit document upserts and require every asynchronous Meilisearch task to succeed."""
    docs = _prepare_index_documents(lines, meili_url, meili_index, model, strict_setup=True)
    for index in range(0, len(docs), BATCH_SIZE):
        response = _meili_request(
            meili_url,
            "POST",
            f"/indexes/{meili_index}/documents",
            docs[index:index + BATCH_SIZE],
        )
        task_uid = response.get("taskUid")
        if task_uid is None:
            raise RuntimeError("Meilisearch document upsert did not return taskUid")
        _wait_for_meili_task(meili_url, task_uid, timeout, poll_interval)
    return len(docs)


# ---------------------------------------------------------------------------
# Google Sheets write-back for newly-minted taxonomy entries
# ---------------------------------------------------------------------------

def _parse_sheet_url(url):
    """Extract (spreadsheet_id, gid) from an edit-URL like .../d/<ID>/edit?gid=<GID>#gid=<GID>.
    Confirmed live not every taxonomy_url has a gid (e.g. .../edit?usp=sharing) -- those default
    to gid=0, the first tab, same as Sheets itself does when gid is omitted."""
    id_match = re.search(r"/d/([a-zA-Z0-9_-]+)", url)
    if not id_match:
        raise ValueError(f"Could not parse spreadsheet ID from taxonomy_url: {url!r}")
    gid_match = re.search(r"[?&#]gid=(\d+)", url)
    return id_match.group(1), int(gid_match.group(1)) if gid_match else 0


def _sheets_service():
    """Loads the client-util service account key directly (see SHEET_KEY_FILE) rather than ADC --
    client-util@sincere-hearth-273704.iam.gserviceaccount.com must be shared as Editor on every
    target taxonomy_url Sheet."""
    creds = service_account.Credentials.from_service_account_file(SHEET_KEY_FILE, scopes=SHEETS_SCOPES)
    return build("sheets", "v4", credentials=creds, cache_discovery=False)


def _tab_title_for_gid(service, spreadsheet_id, gid):
    meta = service.spreadsheets().get(
        spreadsheetId=spreadsheet_id, fields="sheets.properties"
    ).execute()
    for sheet in meta.get("sheets", []):
        if sheet["properties"]["sheetId"] == gid:
            return sheet["properties"]["title"]
    raise ValueError(f"No tab with gid={gid} in spreadsheet {spreadsheet_id}")


def _map_row_to_header(row, header):
    """row: dict of BigQuery column_name -> value, already read back from BigQuery. header: the
    Sheet's row-1 cell values, in the Sheet's own order. Matches case-insensitively by name --
    confirmed live a dict table's column ORDER and capitalization don't match its Sheet's (e.g.
    susububuk_dict is keywords/keyword_typo/sku_type_complete by ordinal position, its Sheet is
    Keyword_Typo/SKU_type_complete/Keywords). A header cell with no matching BigQuery column
    (e.g. the Sheet's own _meta column) is left blank; a BigQuery column absent from the header
    is simply not written."""
    lower_row = {k.lower(): v for k, v in row.items()}
    out = []
    for cell in header:
        value = lower_row.get(cell.strip().lower())
        out.append("" if value is None else str(value))
    return out


@dataclass(frozen=True)
class SheetAppendOutcome:
    status: str
    error: Optional[str] = None


SheetEntryKey = Tuple[str, str, str]


def _sheet_entry_key(entry: Mapping[str, str]) -> SheetEntryKey:
    return tuple(str(entry.get(field, "")).strip() for field in (
        "brand", "identity_col", "identity_value",
    ))


def append_sheet_new_entries_strict(
    project: str,
    dict_table: str,
    sheet_url: str,
    entries: Sequence[Mapping[str, str]],
    client=None,
    service=None,
) -> Dict[SheetEntryKey, SheetAppendOutcome]:
    """Return an explicit append result for every supplied dictionary identity."""
    entries_by_key = {_sheet_entry_key(entry): entry for entry in entries}
    outcomes = {}
    valid_entries = {}
    for key, entry in entries_by_key.items():
        if not all(key) or key[1] not in DICT_IDENTITY_CANDIDATES:
            outcomes[key] = SheetAppendOutcome("failed", "invalid dictionary identity")
        else:
            valid_entries[key] = entry
    if not valid_entries:
        return outcomes

    def fail_remaining(error):
        message = "%s: %s" % (type(error).__name__, error)
        for key in valid_entries:
            if key not in outcomes:
                outcomes[key] = SheetAppendOutcome("failed", message)
        return outcomes

    try:
        sheet_url = (sheet_url or "").strip()
        if not sheet_url or sheet_url == "-":
            raise ValueError("taxonomy_url is not configured")
        spreadsheet_id, gid = _parse_sheet_url(sheet_url)
        service = service or _sheets_service()
        tab_title = _tab_title_for_gid(service, spreadsheet_id, gid)
        sheet_values = service.spreadsheets().values().get(
            spreadsheetId=spreadsheet_id, range=f"'{tab_title}'!A:ZZ"
        ).execute().get("values", [])
        header = sheet_values[0] if sheet_values else []
        # Case-insensitive, like _map_row_to_header: some Sheets use "Brand"/"SKU_type_complete".
        header_index = {name.strip().lower(): i for i, name in enumerate(header)}
        if "brand" not in header_index:
            raise ValueError("Sheet is missing brand header")
        unsupported = {
            key[1] for key in valid_entries if key[1].lower() not in header_index
        }
        if unsupported:
            raise ValueError(
                "Sheet is missing identity header(s): %s" % ", ".join(sorted(unsupported))
            )
    except Exception as error:
        return fail_remaining(error)

    existing_keys = set()
    brand_index = header_index["brand"]
    for key in valid_entries:
        identity_index = header_index[key[1].lower()]
        for row in sheet_values[1:]:
            brand = row[brand_index] if brand_index < len(row) else ""
            identity = row[identity_index] if identity_index < len(row) else ""
            # strip: hand-edited Sheet cells carry stray leading/trailing \r\n; keys are stripped.
            existing_keys.add((brand.strip(), key[1], identity.strip()))

    client = client or bigquery.Client(project=project)
    rows_to_append = []
    for key in valid_entries:
        if key in existing_keys:
            outcomes[key] = SheetAppendOutcome("already_present")
            continue
        try:
            query = f"""
                SELECT * FROM `{project}.{dict_table}`
                WHERE brand = @brand AND {key[1]} = @identity_value
                LIMIT 1
            """
            job_config = bigquery.QueryJobConfig(query_parameters=[
                bigquery.ScalarQueryParameter("brand", "STRING", key[0]),
                bigquery.ScalarQueryParameter("identity_value", "STRING", key[2]),
            ])
            rows = list(client.query(query, job_config=job_config).result())
            if not rows:
                outcomes[key] = SheetAppendOutcome("failed", "authoritative dictionary row not found")
                continue
            rows_to_append.append((key, _map_row_to_header(dict(rows[0].items()), header)))
        except Exception as error:
            outcomes[key] = SheetAppendOutcome(
                "failed", "%s: %s" % (type(error).__name__, error)
            )

    if not rows_to_append:
        return outcomes
    try:
        service.spreadsheets().values().append(
            spreadsheetId=spreadsheet_id,
            range=f"'{tab_title}'!A1",
            valueInputOption="RAW",
            insertDataOption="INSERT_ROWS",
            body={"values": [row for _, row in rows_to_append]},
        ).execute()
    except Exception as error:
        message = "%s: %s" % (type(error).__name__, error)
        for key, _ in rows_to_append:
            outcomes[key] = SheetAppendOutcome("failed", message)
        return outcomes

    for key, _ in rows_to_append:
        outcomes[key] = SheetAppendOutcome("appended")
    return outcomes


def append_sheet_new_entries(project, dict_table, dataset, sheet_url, entries, client=None, service=None):
    """Legacy non-fatal wrapper for v2 callers."""
    try:
        outcomes = append_sheet_new_entries_strict(
            project, dict_table, sheet_url, entries, client=client, service=service,
        )
    except Exception as error:
        print(f"  WARNING: append-sheet failed (non-fatal): {type(error).__name__}: {error}")
        return 0
    failure = next(
        (outcome.error for outcome in outcomes.values() if outcome.status == "failed"),
        None,
    )
    if failure:
        print(f"  WARNING: append-sheet failed (non-fatal): {failure}")
    return sum(outcome.status == "appended" for outcome in outcomes.values())


# ---------------------------------------------------------------------------
# Merchant force-include allowlist (non_niq_qa_v2.sh only)
# ---------------------------------------------------------------------------

def _read_tab_rows(service, spreadsheet_id, tab_title):
    """(header, data_rows) for a tab via the values API. Sheets omits trailing empty cells, so a
    row's length can be shorter than the header -- callers must index defensively, never assume
    len(row) covers every column."""
    values = service.spreadsheets().values().get(
        spreadsheetId=spreadsheet_id, range=f"'{tab_title}'!A:Z"
    ).execute().get("values", [])
    if not values:
        return [], []
    return values[0], values[1:]


def _row_cell(row, idx):
    return row[idx].strip() if idx < len(row) and row[idx] else ""


def fetch_forced_merchant_ids(country, category, platform_titlecase, service=None):
    """Merchant IDs from the Client OS Only / Competitor OS reference Sheet that must be QA'd
    regardless of product_tier -- known client-owned or competitor stores worth tracking even at
    low GMV. Matches each row on (Country, Category Pipeline, Platform):
    - Country cell is a full name -- normalized via COUNTRY_NAME_TO_CODE; an already-bare code
      falls back to itself uppercased.
    - Category Pipeline cell is sometimes multi-valued ("Men Perfume / Women Perfume / Unisex
      Perfume", confirmed live for ambiguous merchant-sheet categories) -- split on "/" and match
      membership, never exact-equality.
    - Platform: Tokopedia gets the same two-value alias non_niq_qa_v2.sh's own
      platform_match_clause() uses (confirmed live one row is "Tokopedia | Shop"); every value is
      also stripped (confirmed live one row is "Tiktok " with a trailing space).
    Never raises past this function -- a Sheets hiccup must not block a QA run that doesn't
    otherwise depend on this Sheet; caller gets an empty list and logs its own warning."""
    platform_aliases = {"Tokopedia", "Tokopedia | Shop"} if platform_titlecase == "Tokopedia" else {platform_titlecase}
    service = service or _sheets_service()
    required = ["Country", "Category Pipeline", "Platform", "Merchant ID"]
    merchant_ids = set()
    for tab_title in MERCHANT_REFERENCE_TABS:
        header, rows = _read_tab_rows(service, MERCHANT_REFERENCE_SPREADSHEET_ID, tab_title)
        idx = {name.strip(): i for i, name in enumerate(header)}
        if not all(r in idx for r in required):
            print(f"  WARNING: forced-merchants tab {tab_title!r} missing expected column(s) {required} -- skipping", file=sys.stderr)
            continue
        for row in rows:
            country_cell = _row_cell(row, idx["Country"])
            mapped_country = COUNTRY_NAME_TO_CODE.get(country_cell, country_cell.upper())
            if mapped_country != country:
                continue
            categories = {c.strip() for c in _row_cell(row, idx["Category Pipeline"]).split("/") if c.strip()}
            if category not in categories:
                continue
            if _row_cell(row, idx["Platform"]) not in platform_aliases:
                continue
            merchant_id = _row_cell(row, idx["Merchant ID"])
            if merchant_id:
                merchant_ids.add(merchant_id)
    return sorted(merchant_ids)


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



def _cmd_auto_confirm(args):
    rows = [json.loads(line) for line in open(args.input_file) if line.strip()]
    hits = [json.loads(line) for line in open(args.candidates_file) if line.strip()]
    confirmed = confirm_casefold_matches(
        bigquery.Client(project=args.project),
        args.project,
        args.qa_table,
        args.qa_pk_col,
        args.qa_platform_col,
        rows,
        hits,
        qa_identity_col=getattr(args, "qa_identity_col", "sku_type_complete"),
        dict_table=args.dict_table,
        dict_identity_col=args.identity_col,
        extra_identity_fields=tuple(
            field for field in args.extra_identity_fields.split(",") if field
        ),
    )
    residual_count = 0
    with open(args.residual_file, "w") as output:
        for row in rows:
            if worklist_row_key(row) not in confirmed:
                output.write(json.dumps(row) + "\n")
                residual_count += 1
    print(json.dumps({"confirmed": len(rows) - residual_count, "residual": residual_count}))

def _cmd_index(args):
    lines = [json.loads(l) for l in open(args.input_file) if l.strip()]
    count = index_documents(lines, args.meili_url, args.meili_index)
    print(f"Indexed {count} products -> {args.meili_index}")


def _cmd_append_sheet(args):
    lines = [json.loads(l) for l in open(args.input_file) if l.strip()]
    entries = [
        {"brand": l["brand"], "identity_col": args.identity_col, "identity_value": l["sku_type_complete"]}
        for l in lines
    ]
    count = append_sheet_new_entries(args.project, args.dict_table, args.dataset, args.sheet_url, entries)
    print(f"Appended {count} row(s) to Sheet for {args.dataset}")


def _cmd_forced_merchants(args):
    try:
        ids = fetch_forced_merchant_ids(args.country, args.category, args.platform)
    except Exception as e:
        print(f"  WARNING: forced-merchants failed (non-fatal): {type(e).__name__}: {e}", file=sys.stderr)
        ids = []
    print(json.dumps(ids))


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

    auto_p = sub.add_parser("auto-confirm")
    auto_p.add_argument("--input-file", required=True)
    auto_p.add_argument("--candidates-file", required=True)
    auto_p.add_argument("--residual-file", required=True)
    auto_p.add_argument("--project", required=True)
    auto_p.add_argument("--qa-table", required=True)
    auto_p.add_argument("--qa-pk-col", required=True)
    auto_p.add_argument("--qa-platform-col", default="ecommerce_platform")
    auto_p.add_argument("--qa-identity-col", default="sku_type_complete")
    auto_p.add_argument("--dict-table", default=None)
    auto_p.add_argument("--identity-col", default=None)
    auto_p.add_argument("--extra-identity-fields", default="")

    index_p = sub.add_parser("index")
    index_p.add_argument("--input-file", required=True)
    index_p.add_argument("--meili-index", required=True)
    index_p.add_argument("--meili-url", default=MEILI_URL)

    append_p = sub.add_parser("append-sheet")
    append_p.add_argument("--input-file", required=True)
    append_p.add_argument("--dict-table", required=True)
    append_p.add_argument("--project", required=True)
    append_p.add_argument("--dataset", required=True)
    append_p.add_argument("--identity-col", required=True)
    append_p.add_argument("--sheet-url", required=True)

    forced_p = sub.add_parser("forced-merchants")
    forced_p.add_argument("--country", required=True)
    forced_p.add_argument("--category", required=True)
    forced_p.add_argument("--platform", required=True)

    sync_p = sub.add_parser("sync-labelling")
    sync_p.add_argument("--input-file", required=True)
    sync_p.add_argument("--project", required=True)
    sync_p.add_argument("--qa-table", required=True)
    sync_p.add_argument("--qa-pk-col", required=True)
    sync_p.add_argument("--qa-platform-col", required=True)
    sync_p.add_argument("--qa-identity-col", default="sku_type_complete")
    sync_p.add_argument("--master-table", required=True)
    sync_p.add_argument("--filter-table", required=True)
    sync_p.add_argument("--month", required=True)
    sync_p.add_argument("--platform", required=True)
    sync_p.add_argument("--country", required=True)
    sync_p.add_argument("--category", required=True)

    args = parser.parse_args()
    if args.command == "categories":
        _cmd_categories(args)
    elif args.command == "columns":
        _cmd_columns(args)
    elif args.command == "retrieve":
        _cmd_retrieve(args)
    elif args.command == "index":
        _cmd_index(args)
    elif args.command == "append-sheet":
        _cmd_append_sheet(args)
    elif args.command == "auto-confirm":
        _cmd_auto_confirm(args)
    elif args.command == "forced-merchants":
        _cmd_forced_merchants(args)
    elif args.command == "sync-labelling":
        _cmd_sync_labelling(args)


if __name__ == "__main__":
    main()
