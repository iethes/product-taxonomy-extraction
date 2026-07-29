"""
One-off migration: docs/categories/*.md -> BigQuery magpie_reference.category_brief.

Run once. Not wired into the live pipeline (headless_taxonomy.sh / targeted_qa_fix.sh
read/write category_brief directly after their own cutover, per
docs/superpowers/specs/2026-07-29-category-brief-bq-migration-design.md).

Usage: python3 script/migrate_category_docs_to_bq_2026_07_29.py [--dry-run]
"""
import json
import re
import subprocess
import sys

PROJECT = "sincere-hearth-273704"
DATASET = "magpie_reference"
TABLE = "category_brief"

# (filename stem in docs/categories/, source_dataset, master_table, source_table_fqn or None)
CATEGORY_MAP = [
    ("shopee_sg_breakfast_cereals", "master_clean_niq", "shopee_sg_breakfast_cereals", None),
    ("shopee_sg_facial_cleanser", "master_clean_niq", "shopee_sg_facial_cleanser", None),
    ("shopee_sg_facial_moisturiser", "master_clean_niq", "shopee_sg_facial_moisturiser", None),
    ("shopee_sg_hair_conditioner_or_treatment", "master_clean_niq", "shopee_sg_hair_conditioner_or_treatment", None),
    ("shopee_sg_shampoo", "master_clean_niq", "shopee_sg_shampoo", None),
    ("shopee_sg_toothpaste", "master_clean_niq", "shopee_sg_toothpaste", None),
    ("shopee_id_baby_diapers", "master_clean_niq", "shopee_id_baby_diapers", None),
    ("shopee_id_makeup_face", "master_clean_niq", "shopee_id_makeup_face", None),
    ("shopee_sg_beer_and_lager", "master_clean_niq", "shopee_sg_beer_and_lager", None),
    ("shopee_sg_carbonated_drink", "master_clean_niq", "shopee_sg_carbonated_drink", None),
    ("shopee_sg_coffee", "master_clean_niq", "shopee_sg_coffee", None),
    ("shopee_sg_diapers", "master_clean_niq", "shopee_sg_diapers", None),
    ("shopee_sg_hand_and_body_moisturiser", "master_clean_niq", "shopee_sg_hand_and_body_moisturiser", None),
    ("shopee_sg_liquid_soap", "master_clean_niq", "shopee_sg_liquid_soap", None),
    ("shopee_sg_pet_food", "master_clean_niq", "shopee_sg_pet_food", None),
    ("shopee_sg_spirits", "master_clean_niq", "shopee_sg_spirits", None),
    ("shopee_sg_toilet_rolls", "master_clean_niq", "shopee_sg_toilet_rolls", None),
    ("shopee_sg_vitamin_mineral_health_supplements", "master_clean_niq", "shopee_sg_vitamin_mineral_health_supplements", None),
    ("shopee_th_adult_diapers", "master_clean_niq", "shopee_th_adult_diapers", None),
    ("shopee_th_baby_diapers", "master_clean_niq", "shopee_th_baby_diapers", None),
    ("shopee_th_body_wash", "master_clean_niq", "shopee_th_body_wash", None),
    ("shopee_th_cleanser", "master_clean_niq", "shopee_th_cleanser", None),
    ("shopee_th_coffee", "master_clean_niq", "shopee_th_coffee", None),
    ("shopee_th_conditioner", "master_clean_niq", "shopee_th_conditioner", None),
    ("shopee_th_detergent", "master_clean_niq", "shopee_th_detergent", None),
    ("shopee_th_drinking_water", "master_clean_niq", "shopee_th_drinking_water", None),
    ("shopee_th_fabric_softener", "master_clean_niq", "shopee_th_fabric_softener", None),
    ("shopee_th_liquid_milk", "master_clean_niq", "shopee_th_liquid_milk", None),
    ("shopee_th_make_up_face", "master_clean_niq", "shopee_th_make_up_face", None),
    ("shopee_th_milk_powder", "master_clean_niq", "shopee_th_milk_powder", None),
    ("shopee_th_moisturizer_for_body", "master_clean_niq", "shopee_th_moisturizer_for_body", None),
    ("shopee_th_moisturizer_for_face", "master_clean_niq", "shopee_th_moisturizer_for_face", None),
    ("shopee_th_pet_food", "master_clean_niq", "shopee_th_pet_food", None),
    ("shopee_th_shampoo", "master_clean_niq", "shopee_th_shampoo", None),
    ("shopee_th_softdrink", "master_clean_niq", "shopee_th_softdrink", None),
    ("shopee_th_suncare", "master_clean_niq", "shopee_th_suncare", None),
    ("shopee_th_toothbrush", "master_clean_niq", "shopee_th_toothbrush", None),
    ("shopee_th_toothpaste", "master_clean_niq", "shopee_th_toothpaste", None),
    ("makanananjing_my", "makanananjing", "makanananjing_my",
     f"{PROJECT}.makanananjing.9_makanananjing_my_daily"),
    ("makanananjing_sg", "makanananjing", "makanananjing_sg",
     f"{PROJECT}.makanananjing.9_makanananjing_sg_daily"),
    ("makanankucing_my", "makanankucing", "makanankucing_my",
     f"{PROJECT}.makanankucing.9_makanankucing_my_daily"),
    ("makanankucing_sg", "makanankucing", "makanankucing_sg",
     f"{PROJECT}.makanankucing.9_makanankucing_sg_daily"),
]

QA_HISTORY_ROW_RE = re.compile(
    r"^\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*$", re.MULTILINE
)


def derive_country(master_table):
    if master_table.startswith("shopee_sg_"):
        return "SG"
    if master_table.startswith("shopee_th_"):
        return "TH"
    if master_table.startswith("shopee_id_"):
        return "ID"
    if master_table.endswith("_my"):
        return "MY"
    if master_table.endswith("_sg"):
        return "SG"
    raise ValueError(f"cannot derive country for {master_table!r}")


def classify_status(live_rows, orphan_rows, doc_claims_complete):
    all_orphaned = live_rows > 0 and orphan_rows >= live_rows
    if doc_claims_complete and (live_rows == 0 or all_orphaned):
        return "reset_pending_redo"
    if doc_claims_complete and orphan_rows > 0 and live_rows > 0:
        return "partial_loss"
    if not doc_claims_complete:
        return "not_started"
    return "active"


def parse_qa_history_table(markdown):
    history_heading = re.search(r"^## QA History\s*$", markdown, re.MULTILINE)
    if not history_heading:
        return []
    rest = markdown[history_heading.end():]
    end = re.search(r"^---\s*$", rest, re.MULTILINE)
    section = rest[: end.start()] if end else rest
    rows = []
    for date, pass_name, finding, resolution in QA_HISTORY_ROW_RE.findall(section):
        if date.strip() in ("Date", "------") or set(date.strip()) <= {"-"}:
            continue
        if finding.strip().startswith("{") or "YYYY-MM-DD" in date:
            continue
        rows.append({
            "date": date.strip(), "pass_name": pass_name.strip(),
            "finding": finding.strip(), "resolution": resolution.strip(),
        })
    return rows


def build_reality_note(status, live_rows, orphan_rows):
    if status not in ("reset_pending_redo", "partial_loss"):
        return ""
    verdict = "reset for redo" if status == "reset_pending_redo" else "partially recovered"
    return (
        f"## Data Reality Check (2026-07-29)\n"
        f"Live `product_taxonomy_map`: {live_rows} rows ({orphan_rows} orphaned). Category doc below claims "
        f"completion — live state does not match. Treat as {verdict}; the prose below is historical context, "
        f"not current status.\n\n---\n\n"
    )


def bq_query_json(sql):
    result = subprocess.run(
        ["bq", "query", "--use_legacy_sql=false", "--project_id", PROJECT, "--format=json", sql],
        capture_output=True, text=True, check=True,
    )
    return json.loads(result.stdout)


def live_map_counts(master_table):
    rows = bq_query_json(
        f"SELECT source, COUNT(*) AS c FROM `{PROJECT}.{DATASET}.product_taxonomy_map` "
        f"WHERE master_table = '{master_table}' GROUP BY source"
    )
    live_rows = sum(int(r["c"]) for r in rows)
    orphan_rows_result = bq_query_json(
        f"SELECT COUNT(*) AS c FROM `{PROJECT}.{DATASET}.product_taxonomy_map` m "
        f"LEFT JOIN `{PROJECT}.{DATASET}.product_taxonomy` pt ON m.taxonomy_id = pt.taxonomy_id "
        f"WHERE m.master_table = '{master_table}' AND pt.taxonomy_id IS NULL"
    )
    orphan_rows = int(orphan_rows_result[0]["c"]) if orphan_rows_result else 0
    return live_rows, orphan_rows


def doc_claims_complete(markdown):
    return bool(re.search(r"Complete", markdown, re.IGNORECASE)) and not bool(
        re.search(r"Keyword only|Not started", markdown, re.IGNORECASE)
    )


def load_brief_row(category_key, source_dataset, master_table, source_table_fqn, country,
                    status, live_rows, orphan_rows, brief_markdown, dry_run):
    ndjson_line = json.dumps({
        "category_key": category_key, "task_type": "BRIEF",
        "source_dataset": source_dataset, "master_table": master_table,
        "source_table_fqn": source_table_fqn, "country": country, "status": status,
        "live_map_rows": live_rows, "orphan_map_rows": orphan_rows,
        "reality_checked_at": "2026-07-29T00:00:00Z",
        "brief_markdown": brief_markdown, "updated_at": "2026-07-29T00:00:00Z",
        "meta_agent": "CLAUDE_CODE",
    })
    if dry_run:
        print(f"[dry-run] would load BRIEF row for {category_key} (status={status})")
        return
    stage_table = f"_stage_category_brief_{master_table}"
    with open(f"/tmp/{master_table}_brief.ndjson", "w") as f:
        f.write(ndjson_line + "\n")
    subprocess.run(
        ["bq", "load", "--use_legacy_sql=false", "--source_format=NEWLINE_DELIMITED_JSON", "--replace",
         f"{PROJECT}:{DATASET}.{stage_table}", f"/tmp/{master_table}_brief.ndjson",
         "category_key:STRING,task_type:STRING,source_dataset:STRING,master_table:STRING,"
         "source_table_fqn:STRING,country:STRING,status:STRING,live_map_rows:INTEGER,"
         "orphan_map_rows:INTEGER,reality_checked_at:TIMESTAMP,brief_markdown:STRING,"
         "updated_at:TIMESTAMP,meta_agent:STRING"],
        check=True,
    )
    subprocess.run(
        ["bq", "query", "--use_legacy_sql=false", "--project_id", PROJECT, f"""
MERGE `{PROJECT}.{DATASET}.{TABLE}` t
USING `{PROJECT}.{DATASET}.{stage_table}` s
ON t.category_key = s.category_key AND t.task_type = 'BRIEF'
WHEN MATCHED THEN UPDATE SET
  source_dataset = s.source_dataset, master_table = s.master_table,
  source_table_fqn = s.source_table_fqn, country = s.country, status = s.status,
  live_map_rows = s.live_map_rows, orphan_map_rows = s.orphan_map_rows,
  reality_checked_at = s.reality_checked_at, brief_markdown = s.brief_markdown,
  updated_at = s.updated_at, meta_agent = s.meta_agent
WHEN NOT MATCHED THEN INSERT ROW
"""],
        check=True,
    )
    subprocess.run(["bq", "rm", "-f", "-t", f"{PROJECT}:{DATASET}.{stage_table}"], check=True)


def load_qa_history_rows(category_key, history_rows, dry_run):
    for row in history_rows:
        note = f"Pass: {row['pass_name']}\nFinding: {row['finding']}\nResolution: {row['resolution']}"
        if dry_run:
            print(f"[dry-run] would insert QA_HISTORY row for {category_key} dated {row['date']}")
            continue
        subprocess.run(
            ["bq", "query", "--use_legacy_sql=false", "--project_id", PROJECT,
             "--parameter", f"category_key::STRING:{category_key}",
             "--parameter", f"task_date::DATE:{row['date']}",
             "--parameter", f"brief_markdown::STRING:{note}",
             f"INSERT INTO `{PROJECT}.{DATASET}.{TABLE}` "
             f"(category_key, task_type, task_date, brief_markdown, updated_at, meta_agent) "
             f"VALUES (@category_key, 'QA_HISTORY', @task_date, @brief_markdown, CURRENT_TIMESTAMP(), 'CLAUDE_CODE')"],
            check=True,
        )


def main():
    dry_run = "--dry-run" in sys.argv
    for filename, source_dataset, master_table, source_table_fqn in CATEGORY_MAP:
        path = f"docs/categories/{filename}.md"
        with open(path) as f:
            markdown = f.read()
        country = derive_country(master_table)
        live_rows, orphan_rows = live_map_counts(master_table)
        status = classify_status(live_rows, orphan_rows, doc_claims_complete(markdown))
        note = build_reality_note(status, live_rows, orphan_rows)
        final_markdown = note + markdown if note else markdown
        category_key = f"{source_dataset}.{master_table}"
        print(f"{category_key}: status={status} live_rows={live_rows} orphan_rows={orphan_rows}")
        load_brief_row(category_key, source_dataset, master_table, source_table_fqn, country,
                        status, live_rows, orphan_rows, final_markdown, dry_run)
        history_rows = parse_qa_history_table(markdown)
        load_qa_history_rows(category_key, history_rows, dry_run)
        print(f"  -> {len(history_rows)} QA_HISTORY rows migrated")


if __name__ == "__main__":
    main()
