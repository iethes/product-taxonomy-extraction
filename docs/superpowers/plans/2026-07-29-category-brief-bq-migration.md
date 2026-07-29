# Category Brief BQ Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move `docs/categories/*.md` (42 category context files) into a new BigQuery `category_brief` table, reality-checking each category against live `product_taxonomy_map` before migrating, and cut over all four headless pipeline scripts to read/write that table instead of local files.

**Architecture:** One new BQ table (`category_brief`, single-table with a `task_type` discriminator: `BRIEF` | `TAXONOMY` | `QA_HISTORY`). A one-off Python migration script reality-checks and loads the 42 existing files. `headless_taxonomy.sh` / `custom_headless_taxonomy.sh` keep their existing pattern of having the agent perform the write itself (temp file + `bq load` + `MERGE` for the big `BRIEF` blob; a plain parameterized `bq query INSERT` for `TAXONOMY` run-log rows) — this requires prompt-text-only changes, no new bash logic. `targeted_qa_fix.sh` / `custom_targeted_qa_fix.sh` keep their existing wrapper-controlled pattern (the wrapper, not the agent, performs the `QA_HISTORY` insert) — this requires new bash functions replacing `resolve_category_file`/`append_qa_history_row`. Docs are deleted only after scripts + tests are updated and verified, and only once no live `queue_worker.sh` session is running.

**Tech Stack:** Bash (existing scripts), Python 3 + pytest (migration script, shelling out to the `bq` CLI — never `google-cloud-bigquery`'s streaming insert API), BigQuery DDL/DML via `bq query`/`bq load`.

## Global Constraints

- Every row written to `category_brief` must have `meta_agent` set (`CLAUDE_CODE` for this migration and all live-script writes) — never `NULL`. (CLAUDE.md meta_agent rule)
- Writes to BigQuery use `bq query` DML or `bq load` only — **never** the streaming API (`insert_rows_json`). (CLAUDE.md 90-minute streaming buffer rule; spec §4)
- `category_key` format is `<source_dataset>.<master_table>` — e.g. `master_clean_niq.shopee_sg_shampoo`, `makanankucing.makanankucing_my`. Never strip or guess a `shopee_` prefix. (spec §1–2)
- No inline `bq query` ever embeds a full markdown blob as a string literal — big content always goes through a temp file + `bq load` + `MERGE`. Small per-row text (a QA History finding/resolution) always goes through `bq query --parameter=...`, never raw string concatenation into SQL. (spec §4)
- Before deleting any `docs/categories/*.md` file (Task 10), confirm no `queue_worker.sh` / `claude -p` process referencing that category is currently running. (spec §7)
- Project is always `sincere-hearth-273704`; dataset for the new table is `magpie_reference`.

---

## File Structure

| File | Responsibility |
|---|---|
| `script/migrate_category_docs_to_bq_2026_07_29.py` (new) | One-off migration: reality-check each of the 42 categories against live BQ, classify status, load `BRIEF` + `QA_HISTORY` rows. Committed for audit trail, never wired into the live pipeline. |
| `script/test_migrate_category_docs_to_bq_2026_07_29.py` (new) | pytest unit tests for the migration script's pure functions (status classification, QA History table parser, country derivation). |
| `script/headless_taxonomy.sh` (modify) | Prompt-text-only changes: BQ-based STATUS check, BQ-based brief read, `bq load`+`MERGE` write, `TAXONOMY` row insert instruction. No new bash functions. |
| `script/test_headless_taxonomy.sh` (modify) | Updated assertions for the new prompt text. |
| `script/custom_headless_taxonomy.sh` (modify) | Same shape as `headless_taxonomy.sh`, dataset already an explicit arg. |
| `script/test_custom_headless_taxonomy.sh` (modify) | Updated assertions. |
| `script/targeted_qa_fix.sh` (modify) | `resolve_category_file()` deleted; new `category_key_for()`, `fetch_brief_markdown_query()`, `qa_history_insert_query()`, `insert_qa_history_row()`; `has_real_brief()` takes a markdown string instead of a file path; `main()` fetches the brief via `bq query` instead of resolving a file, and calls `insert_qa_history_row` instead of `append_qa_history_row`+`git commit`. |
| `script/test_targeted_qa_fix.sh` (modify) | Updated/replaced assertions for the new functions and call sites. |
| `script/custom_targeted_qa_fix.sh` (modify) | Same shape as `targeted_qa_fix.sh`, `category_key_for(dataset, category)` instead of the fixed `master_clean_niq` prefix. |
| `script/test_custom_targeted_qa_fix.sh` (modify) | Updated assertions. |
| `docs/categories/STATUS.md` (modify) | One-line pointer note added at the top; no other content changes. |
| `docs/categories/*.md` (delete, 42 files) | Deleted in Task 10, its own commit, after everything above is verified. |
| `.claude/projects/-home-wikan-Documents-work-product-taxonomy-extraction/memory/project_th_baby_diapers_data_loss.md` (modify) | Updated with the migration's per-category reality-check classification. |

---

## Task 1: Create the `category_brief` BQ table

**Files:**
- No repo files — this is a live BQ DDL operation, verified via `bq show`.

**Interfaces:**
- Produces: the table `sincere-hearth-273704.magpie_reference.category_brief`, whose schema every later task depends on.

- [ ] **Step 1: Run the CREATE TABLE DDL**

Run:
```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 "
CREATE TABLE \`sincere-hearth-273704.magpie_reference.category_brief\` (
  category_key STRING NOT NULL,
  task_type STRING NOT NULL,
  source_dataset STRING,
  master_table STRING,
  source_table_fqn STRING,
  country STRING,
  status STRING,
  live_map_rows INT64,
  orphan_map_rows INT64,
  reality_checked_at TIMESTAMP,
  task_date DATE,
  brief_markdown STRING NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  meta_agent STRING NOT NULL
)"
```

- [ ] **Step 2: Verify the table exists with the expected schema**

Run: `bq show --format=prettyjson sincere-hearth-273704:magpie_reference.category_brief`
Expected: JSON output listing all 14 fields above, `NOT NULL` mode on `category_key`, `task_type`, `brief_markdown`, `updated_at`; `NULLABLE` on the rest.

- [ ] **Step 3: Verify it's empty**

Run: `bq query --use_legacy_sql=false --format=csv "SELECT COUNT(*) FROM \`sincere-hearth-273704.magpie_reference.category_brief\`"`
Expected: `0`

No commit for this task (no repo files changed) — proceed to Task 2.

---

## Task 2: Write the migration script's pure functions + pytest tests

**Files:**
- Create: `script/migrate_category_docs_to_bq_2026_07_29.py`
- Test: `script/test_migrate_category_docs_to_bq_2026_07_29.py`

**Interfaces:**
- Produces: `derive_country(master_table: str) -> str`, `classify_status(live_rows: int, orphan_rows: int, doc_claims_complete: bool) -> str`, `parse_qa_history_table(markdown: str) -> list[dict]` (each dict has keys `date`, `pass_name`, `finding`, `resolution`), `build_reality_note(status: str, live_rows: int, orphan_rows: int) -> str`. Task 3 (live run) calls these plus new I/O functions built on top of them.

- [ ] **Step 1: Write the failing tests**

Create `script/test_migrate_category_docs_to_bq_2026_07_29.py`:
```python
import sys
import os
sys.path.insert(0, os.path.dirname(__file__))
from migrate_category_docs_to_bq_2026_07_29 import (
    derive_country, classify_status, parse_qa_history_table, build_reality_note,
)


def test_derive_country_niq_prefixes():
    assert derive_country("shopee_sg_shampoo") == "SG"
    assert derive_country("shopee_th_coffee") == "TH"
    assert derive_country("shopee_id_baby_diapers") == "ID"


def test_derive_country_custom_suffixes():
    assert derive_country("makanankucing_my") == "MY"
    assert derive_country("makanankucing_sg") == "SG"
    assert derive_country("makanananjing_my") == "MY"


def test_derive_country_unrecognized_raises():
    try:
        derive_country("totally_unknown_table")
        assert False, "expected ValueError"
    except ValueError:
        pass


def test_classify_status_reset_pending_redo():
    # live rows near zero, doc claims completion -> reset_pending_redo
    assert classify_status(live_rows=0, orphan_rows=0, doc_claims_complete=True) == "reset_pending_redo"
    assert classify_status(live_rows=5, orphan_rows=5, doc_claims_complete=True) == "reset_pending_redo"


def test_classify_status_partial_loss():
    # live rows present, well below documented scale, with orphans -> partial_loss
    assert classify_status(live_rows=74, orphan_rows=10, doc_claims_complete=True) == "partial_loss"


def test_classify_status_active():
    # live rows present, no orphans -> active regardless of doc claim
    assert classify_status(live_rows=4527, orphan_rows=0, doc_claims_complete=True) == "active"


def test_classify_status_not_started():
    # doc never claimed completion, low/no live rows -> not_started, not reset_pending_redo
    assert classify_status(live_rows=0, orphan_rows=0, doc_claims_complete=False) == "not_started"


def test_parse_qa_history_table_extracts_rows():
    markdown = """# Category

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-06-21 | Pass 1 | old finding | old resolution |
| 2026-06-23 | QA Gate A | another finding | another resolution |

---

## Next section
"""
    rows = parse_qa_history_table(markdown)
    assert len(rows) == 2
    assert rows[0] == {
        "date": "2026-06-21", "pass_name": "Pass 1",
        "finding": "old finding", "resolution": "old resolution",
    }
    assert rows[1]["date"] == "2026-06-23"


def test_parse_qa_history_table_skips_template_placeholder():
    markdown = """## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| YYYY-MM-DD | Initial | {finding} | {fix} |
| YYYY-MM-DD | QA Gate A | {finding} | {fix} |

---
"""
    rows = parse_qa_history_table(markdown)
    assert rows == []


def test_parse_qa_history_table_no_section_returns_empty():
    assert parse_qa_history_table("# Category\nNo history section here.\n") == []


def test_build_reality_note_reset_pending_redo():
    note = build_reality_note("reset_pending_redo", live_rows=196, orphan_rows=59)
    assert "## Data Reality Check" in note
    assert "196" in note
    assert "59" in note
    assert "reset for redo" in note


def test_build_reality_note_partial_loss():
    note = build_reality_note("partial_loss", live_rows=74, orphan_rows=0)
    assert "partially recovered" in note


def test_build_reality_note_active_returns_empty():
    assert build_reality_note("active", live_rows=4527, orphan_rows=0) == ""
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd /home/wikan/Documents/work/product-taxonomy-extraction && python3 -m pytest script/test_migrate_category_docs_to_bq_2026_07_29.py -v`
Expected: `ModuleNotFoundError: No module named 'migrate_category_docs_to_bq_2026_07_29'` (the source file doesn't exist yet)

- [ ] **Step 3: Write the minimal implementation**

Create `script/migrate_category_docs_to_bq_2026_07_29.py`:
```python
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python3 -m pytest script/test_migrate_category_docs_to_bq_2026_07_29.py -v`
Expected: all tests PASS (the tests only import the pure functions — `main()`/`bq_query_json`/`load_brief_row`/`load_qa_history_rows` are not called, so no `bq` subprocess is invoked)

- [ ] **Step 5: Commit**

```bash
git add script/migrate_category_docs_to_bq_2026_07_29.py script/test_migrate_category_docs_to_bq_2026_07_29.py
git commit -m "Add one-off migration script: docs/categories/*.md -> category_brief BQ table

Pure functions (status classification, QA History table parser, country
derivation) are pytest-covered. The live-BQ orchestration (main()) is not
unit tested, matching this repo's convention of only unit-testing pure
logic and validating side-effecting calls via a real run.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 3: Run the migration and verify results

**Files:**
- No new files — this executes Task 2's script against live BQ.

**Interfaces:**
- Consumes: `script/migrate_category_docs_to_bq_2026_07_29.py`'s `main()`.
- Produces: 42 `BRIEF` rows and N `QA_HISTORY` rows in `category_brief`, which Tasks 4–7's live scripts will read.

- [ ] **Step 1: Dry-run first**

Run: `cd /home/wikan/Documents/work/product-taxonomy-extraction && python3 script/migrate_category_docs_to_bq_2026_07_29.py --dry-run`
Expected: 42 lines of `<category_key>: status=... live_rows=... orphan_rows=...`, each followed by `[dry-run] would load BRIEF row...` and `-> N QA_HISTORY rows migrated`. No BQ writes happen. Read the status column for every `shopee_th_*` category and cross-check against `project_th_baby_diapers_data_loss.md`'s existing table (`th_body_wash`/`th_conditioner`/`th_suncare` intact; others suspect) — this confirms `classify_status` is producing sane results before writing anything.

- [ ] **Step 2: Live run**

Run: `python3 script/migrate_category_docs_to_bq_2026_07_29.py`
Expected: same 42 lines, this time actually loading. No `subprocess.CalledProcessError`.

- [ ] **Step 3: Verify row counts**

Run: `bq query --use_legacy_sql=false --format=csv "SELECT task_type, COUNT(*) FROM \`sincere-hearth-273704.magpie_reference.category_brief\` GROUP BY 1"`
Expected: exactly one row with `task_type=BRIEF, COUNT=42`; one row with `task_type=QA_HISTORY, COUNT=<N>` where N > 0.

- [ ] **Step 4: Spot-check a known-reset category**

Run: `bq query --use_legacy_sql=false --format=prettyjson "SELECT category_key, status, live_map_rows, orphan_map_rows, SUBSTR(brief_markdown, 1, 300) FROM \`sincere-hearth-273704.magpie_reference.category_brief\` WHERE category_key = 'master_clean_niq.shopee_th_baby_diapers' AND task_type = 'BRIEF'"`
Expected: `status` is `reset_pending_redo` or `partial_loss` (matching the data-loss memory's finding that this category's map rows are mostly gone), and the `brief_markdown` prefix contains `## Data Reality Check (2026-07-29)`.

- [ ] **Step 5: Spot-check a known-intact category**

Run: `bq query --use_legacy_sql=false --format=prettyjson "SELECT category_key, status, live_map_rows FROM \`sincere-hearth-273704.magpie_reference.category_brief\` WHERE category_key = 'master_clean_niq.shopee_th_body_wash' AND task_type = 'BRIEF'"`
Expected: `status = 'active'`, `live_map_rows` in the thousands (matching the memory's "4,527 — intact" finding).

- [ ] **Step 6: No commit** (no repo files changed by running the script) — proceed to Task 4.

---

## Task 4: Cut over `headless_taxonomy.sh` to `category_brief`

**Files:**
- Modify: `script/headless_taxonomy.sh`
- Test: `script/test_headless_taxonomy.sh`

**Interfaces:**
- No new function signatures — `build_first_run_prompt(table, month, block_size)` and `build_topup_prompt(table, month, block_size, gap_count)` keep their existing signatures; only the heredoc text they return changes.

- [ ] **Step 1: Update the test file first (red)**

In `script/test_headless_taxonomy.sh`, in the `build_first_run_prompt` section, add these assertions right after the existing `echo "$prompt" | grep -q "existing LLM rows"` line (before `echo "PASS: build_first_run_prompt"`):
```bash
echo "$prompt" | grep -q "category_key = 'master_clean_niq.shopee_th_conditioner'" || fail "build_first_run_prompt's STATUS check must query category_brief by the correct category_key"
echo "$prompt" | grep -q "task_type = 'BRIEF'" || fail "build_first_run_prompt's STATUS check must scope to task_type='BRIEF'"
echo "$prompt" | grep -qF "bq load" || fail "build_first_run_prompt must instruct loading the brief via bq load, not an inline blob"
echo "$prompt" | grep -qF "MERGE \`\${PROJECT}.magpie_reference.category_brief\`" || fail "build_first_run_prompt must instruct MERGE-ing the staged brief into category_brief"
echo "$prompt" | grep -qF "Never use the streaming API" || fail "build_first_run_prompt must forbid the streaming API for the brief write"
echo "$prompt" | grep -qv "git add docs/categories" || fail "build_first_run_prompt must not instruct a git commit of a category file anymore"
```
Note the last assertion uses `grep -qv` (inverted) — the prompt as a whole should NOT contain that string.

In the `build_topup_prompt` section, add these assertions right before `echo "PASS: build_topup_prompt"`:
```bash
echo "$prompt" | grep -qF "category_key = 'master_clean_niq.shopee_th_suncare'" || fail "build_topup_prompt must read the brief by the correct category_key"
echo "$prompt" | grep -qF "task_type = 'BRIEF'" || fail "build_topup_prompt must scope its brief read to task_type='BRIEF'"
echo "$prompt" | grep -qF -- "--parameter=" || fail "build_topup_prompt's QA history insert must use bq query --parameter, not string concatenation"
echo "$prompt" | grep -qF "task_type = 'TAXONOMY'" || fail "build_topup_prompt's history insert must be tagged task_type='TAXONOMY'"
echo "$prompt" | grep -qv "git add docs/categories" || fail "build_topup_prompt must not instruct a git commit of a category file anymore"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash script/test_headless_taxonomy.sh`
Expected: `FAIL: build_first_run_prompt's STATUS check must query category_brief by the correct category_key` (or similar — the new assertions fail against the current, unmodified script)

- [ ] **Step 3: Edit `build_first_run_prompt` in `script/headless_taxonomy.sh`**

Replace:
```
BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/data-dictionary.md, docs/llm-extraction-rules.md, docs/quality-standards.md, docs/headless-runbook.md, docs/brand-extraction.md, and docs/categories/_TEMPLATE.md (the last one because you are about to fill it in — not in the original doc list, but required for this run specifically). Also check docs/categories/STATUS.md to confirm ${table} hasn't already been completed by someone else since this prompt was written.
```
with:
```
BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/data-dictionary.md, docs/llm-extraction-rules.md, docs/quality-standards.md, docs/headless-runbook.md, docs/brand-extraction.md, and docs/categories/_TEMPLATE.md (the last one because you are about to fill it in — not in the original doc list, but required for this run specifically). Also run: SELECT status, updated_at FROM \`${PROJECT}.magpie_reference.category_brief\` WHERE category_key = 'master_clean_niq.${table}' AND task_type = 'BRIEF' to confirm ${table} hasn't already been completed by someone else since this prompt was written. No row, or a row with status IN ('not_started', 'reset_pending_redo'), means proceeding as a first run is still correct.
```

Replace:
```
- Write the file, then commit it: git add docs/categories/${table}.md && git commit -m 'Add category context for ${table}, generated during headless Full Rebuild'
```
with:
```
- Write your markdown to a local BRIEF row in \`${PROJECT}.magpie_reference.category_brief\` — never inline the markdown into a SQL string literal (it will contain backticks, quotes, and pipe characters that break a literal). Instead:
  1. Write it to /tmp/${table}_brief.ndjson as a single-line JSON object: {"category_key": "master_clean_niq.${table}", "task_type": "BRIEF", "source_dataset": "master_clean_niq", "master_table": "${table}", "country": "<2-3 letter country code parsed from ${table}>", "status": "active", "brief_markdown": "<your full markdown, JSON-string-escaped>", "updated_at": "<CURRENT_TIMESTAMP in ISO 8601 UTC>", "meta_agent": "CLAUDE_CODE"}
  2. Load it into a staging table: bq load --use_legacy_sql=false --source_format=NEWLINE_DELIMITED_JSON --replace \`${PROJECT}:magpie_reference._stage_category_brief_${table}\` /tmp/${table}_brief.ndjson category_key:STRING,task_type:STRING,source_dataset:STRING,master_table:STRING,country:STRING,status:STRING,brief_markdown:STRING,updated_at:TIMESTAMP,meta_agent:STRING
  3. Merge it in: bq query --use_legacy_sql=false "MERGE \`${PROJECT}.magpie_reference.category_brief\` t USING \`${PROJECT}.magpie_reference._stage_category_brief_${table}\` s ON t.category_key = s.category_key AND t.task_type = 'BRIEF' WHEN MATCHED THEN UPDATE SET source_dataset=s.source_dataset, master_table=s.master_table, country=s.country, status=s.status, brief_markdown=s.brief_markdown, updated_at=s.updated_at, meta_agent=s.meta_agent WHEN NOT MATCHED THEN INSERT ROW"
  4. Drop the staging table: bq rm -f -t \`${PROJECT}:magpie_reference._stage_category_brief_${table}\`
  Never use the streaming API (insert_rows_json) for this — CLAUDE.md's 90-minute streaming buffer rule.
```

- [ ] **Step 4: Edit `build_topup_prompt` in `script/headless_taxonomy.sh`**

Replace:
```
BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/llm-extraction-rules.md, docs/quality-standards.md, docs/headless-runbook.md, docs/brand-extraction.md, and docs/categories/${table}.md (the existing category file — its brand scope, official store allowlist, and scope rules are already documented there; do not rediscover them from scratch).
```
with:
```
BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/llm-extraction-rules.md, docs/quality-standards.md, docs/headless-runbook.md, docs/brand-extraction.md, and the existing category brief — run: SELECT brief_markdown FROM \`${PROJECT}.magpie_reference.category_brief\` WHERE category_key = 'master_clean_niq.${table}' AND task_type = 'BRIEF' (its brand scope, official store allowlist, and scope rules are already documented there; do not rediscover them from scratch).
```

Replace:
```
STEP 0 — Get the live worklist (do not trust any number in this prompt or in ${table}.md):
```
with:
```
STEP 0 — Get the live worklist (do not trust any number in this prompt or in the category brief):
```

Replace:
```
A live product_taxonomy_map row count far below what ${table}.md's own documentation claims is not, by itself, a blocker.
Trust live BigQuery state as ground truth and proceed with the top-up as normal.
```
with:
```
A live product_taxonomy_map row count far below what the category brief's own documentation claims is not, by itself, a blocker.
Trust live BigQuery state as ground truth and proceed with the top-up as normal.
```

Replace:
```
STEP 4 — Append a dated row to ${table}.md's '## QA History' table (columns: Date | Pass | Finding | Resolution) summarizing what you did and found this session. Commit the updated file:
git add docs/categories/${table}.md && git commit -m 'Top-up coverage session for ${table}: update QA History'
```
with:
```
STEP 4 — Record a dated run-log entry summarizing what you did and found this session, via a single parameterized INSERT (never build the SQL string by concatenating your own finding text into it directly — that breaks on quotes/backticks; use --parameter so bq handles escaping):
bq query --use_legacy_sql=false --project_id=${PROJECT} \
  --parameter="category_key::STRING:master_clean_niq.${table}" \
  --parameter="task_date::DATE:<today, YYYY-MM-DD>" \
  --parameter="brief_markdown::STRING:<your summary of what you did and found this session>" \
  "INSERT INTO \`${PROJECT}.magpie_reference.category_brief\` (category_key, task_type, task_date, brief_markdown, updated_at, meta_agent) VALUES (@category_key, 'TAXONOMY', @task_date, @brief_markdown, CURRENT_TIMESTAMP(), 'CLAUDE_CODE')"
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash script/test_headless_taxonomy.sh`
Expected: `ALL TESTS PASSED (part 1)`

- [ ] **Step 6: Commit**

```bash
git add script/headless_taxonomy.sh script/test_headless_taxonomy.sh
git commit -m "Cut over headless_taxonomy.sh to category_brief (prompt text only)

Agent still performs the write itself (temp NDJSON -> bq load -> MERGE for
the BRIEF row; a parameterized bq query INSERT for the per-run TAXONOMY
log row), matching this script's existing self-write pattern. No new bash
functions or main() changes needed.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 5: Cut over `custom_headless_taxonomy.sh` to `category_brief`

**Files:**
- Modify: `script/custom_headless_taxonomy.sh`
- Test: `script/test_custom_headless_taxonomy.sh`

**Interfaces:**
- No signature changes — `build_first_run_prompt(dataset, table, category, block_size)` / `build_topup_prompt(dataset, table, category, block_size, gap_count)` unchanged.

- [ ] **Step 1: Update the test file first (red)**

In `script/test_custom_headless_taxonomy.sh`, add before `echo "PASS: build_first_run_prompt"`:
```bash
echo "$prompt" | grep -qF "category_key = 'makanananjing.makanananjing_my'" || fail "build_first_run_prompt should check category_brief by dataset.category, not a fixed master_clean_niq prefix"
echo "$prompt" | grep -qF "bq load" || fail "build_first_run_prompt must instruct bq load for the brief write"
echo "$prompt" | grep -qv "git add docs/categories" || fail "build_first_run_prompt must not instruct a git commit anymore"
```

Add before `echo "PASS: build_topup_prompt"`:
```bash
echo "$prompt" | grep -qF "category_key = 'makanankucing.makanankucing_my'" || fail "build_topup_prompt should read category_brief by dataset.category"
echo "$prompt" | grep -qF "task_type = 'TAXONOMY'" || fail "build_topup_prompt's history insert must be tagged TAXONOMY"
echo "$prompt" | grep -qv "git add docs/categories" || fail "build_topup_prompt must not instruct a git commit anymore"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash script/test_custom_headless_taxonomy.sh`
Expected: FAIL on the new `category_key = 'makanananjing.makanananjing_my'` assertion.

- [ ] **Step 3: Edit `build_first_run_prompt` in `script/custom_headless_taxonomy.sh`**

Replace:
```
BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/data-dictionary.md,
docs/llm-extraction-rules.md, docs/quality-standards.md, docs/headless-runbook.md,
docs/brand-extraction.md, and docs/categories/_TEMPLATE.md. Note: data-dictionary.md documents
master_clean_niq tables — \`${PROJECT}.${dataset}.${table}\` is NOT in that dataset and has a
different schema (daily grain summed to monthly here, no month/model_id/merchant columns). Treat its
column set as exactly what STEP 0's query below returns, not what data-dictionary.md describes. Also
check docs/categories/STATUS.md to confirm '${category}' hasn't already been completed by someone else
since this prompt was written.
```
with:
```
BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/data-dictionary.md,
docs/llm-extraction-rules.md, docs/quality-standards.md, docs/headless-runbook.md,
docs/brand-extraction.md, and docs/categories/_TEMPLATE.md. Note: data-dictionary.md documents
master_clean_niq tables — \`${PROJECT}.${dataset}.${table}\` is NOT in that dataset and has a
different schema (daily grain summed to monthly here, no month/model_id/merchant columns). Treat its
column set as exactly what STEP 0's query below returns, not what data-dictionary.md describes. Also
run: SELECT status, updated_at FROM \`${PROJECT}.magpie_reference.category_brief\` WHERE category_key = '${dataset}.${category}' AND task_type = 'BRIEF' to confirm '${category}' hasn't already been completed by someone else since this prompt was written.
```

Replace:
```
STEP 5 — Write docs/categories/${category}.md following _TEMPLATE.md's structure, documenting what you
actually found this session (brand scope, SKU blocks assigned, scale) — this is written post-hoc here
since there's no pre-existing brand/merchant data to research upfront. Then commit it:
git add docs/categories/${category}.md && git commit -m 'Add category context for ${category}, generated during custom Full Rebuild'
```
with:
```
STEP 5 — Write a BRIEF row into \`${PROJECT}.magpie_reference.category_brief\` following _TEMPLATE.md's
structure, documenting what you actually found this session (brand scope, SKU blocks assigned, scale) —
this is written post-hoc here since there's no pre-existing brand/merchant data to research upfront.
Never inline the markdown into a SQL string literal — it will contain backticks, quotes, and pipes.
Instead:
  1. Write it to /tmp/${category}_brief.ndjson as a single-line JSON object: {"category_key": "${dataset}.${category}", "task_type": "BRIEF", "source_dataset": "${dataset}", "master_table": "${category}", "source_table_fqn": "${PROJECT}.${dataset}.${table}", "country": "<2-3 letter country code>", "status": "active", "brief_markdown": "<your full markdown, JSON-string-escaped>", "updated_at": "<CURRENT_TIMESTAMP in ISO 8601 UTC>", "meta_agent": "CLAUDE_CODE"}
  2. Load it: bq load --use_legacy_sql=false --source_format=NEWLINE_DELIMITED_JSON --replace \`${PROJECT}:magpie_reference._stage_category_brief_${category}\` /tmp/${category}_brief.ndjson category_key:STRING,task_type:STRING,source_dataset:STRING,master_table:STRING,source_table_fqn:STRING,country:STRING,status:STRING,brief_markdown:STRING,updated_at:TIMESTAMP,meta_agent:STRING
  3. Merge it in: bq query --use_legacy_sql=false "MERGE \`${PROJECT}.magpie_reference.category_brief\` t USING \`${PROJECT}.magpie_reference._stage_category_brief_${category}\` s ON t.category_key = s.category_key AND t.task_type = 'BRIEF' WHEN MATCHED THEN UPDATE SET source_dataset=s.source_dataset, master_table=s.master_table, source_table_fqn=s.source_table_fqn, country=s.country, status=s.status, brief_markdown=s.brief_markdown, updated_at=s.updated_at, meta_agent=s.meta_agent WHEN NOT MATCHED THEN INSERT ROW"
  4. Drop the staging table: bq rm -f -t \`${PROJECT}:magpie_reference._stage_category_brief_${category}\`
  Never use the streaming API (insert_rows_json) — CLAUDE.md's 90-minute streaming buffer rule.
```

- [ ] **Step 4: Edit `build_topup_prompt` in `script/custom_headless_taxonomy.sh`**

Replace:
```
BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/llm-extraction-rules.md,
docs/quality-standards.md, docs/headless-runbook.md, docs/brand-extraction.md, and
docs/categories/${category}.md (the existing category file — its brand scope and scope rules are
already documented there; do not rediscover them from scratch). Note: \`${PROJECT}.${dataset}.${table}\`
is NOT in master_clean_niq and has a different schema (daily grain summed to monthly, no
month/model_id/merchant columns) — treat its column set as exactly what STEP 0's query below returns.
```
with:
```
BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/llm-extraction-rules.md,
docs/quality-standards.md, docs/headless-runbook.md, docs/brand-extraction.md, and the existing
category brief — run: SELECT brief_markdown FROM \`${PROJECT}.magpie_reference.category_brief\` WHERE
category_key = '${dataset}.${category}' AND task_type = 'BRIEF' (its brand scope and scope rules are
already documented there; do not rediscover them from scratch). Note: \`${PROJECT}.${dataset}.${table}\`
is NOT in master_clean_niq and has a different schema (daily grain summed to monthly, no
month/model_id/merchant columns) — treat its column set as exactly what STEP 0's query below returns.
```

Replace:
```
If ${category}.md still describes this category as Shopee-only,
that text is stale — treat Tiktok as in scope regardless, and feel free to update that section in STEP
4 while you're in the file for QA History.
```
with:
```
If the existing brief still describes this category as Shopee-only,
that text is stale — treat Tiktok as in scope regardless, and feel free to note the platform-scope
update in STEP 4's run-log entry.
```

Replace:
```
STEP 0 — Get the live worklist (do not trust any number in this prompt or in ${category}.md):
```
with:
```
STEP 0 — Get the live worklist (do not trust any number in this prompt or in the category brief):
```

Replace:
```
STEP 4 — Append a dated row to ${category}.md's '## QA History' table (columns: Date | Pass | Finding |
Resolution) summarizing what you did and found this session. Commit the updated file:
git add docs/categories/${category}.md && git commit -m 'Top-up coverage session for ${category}: update QA History'
```
with:
```
STEP 4 — Record a dated run-log entry summarizing what you did and found this session, via a single
parameterized INSERT (never build the SQL string by concatenating your own finding text into it
directly — that breaks on quotes/backticks; use --parameter so bq handles escaping):
bq query --use_legacy_sql=false --project_id=${PROJECT} \
  --parameter="category_key::STRING:${dataset}.${category}" \
  --parameter="task_date::DATE:<today, YYYY-MM-DD>" \
  --parameter="brief_markdown::STRING:<your summary of what you did and found this session>" \
  "INSERT INTO \`${PROJECT}.magpie_reference.category_brief\` (category_key, task_type, task_date, brief_markdown, updated_at, meta_agent) VALUES (@category_key, 'TAXONOMY', @task_date, @brief_markdown, CURRENT_TIMESTAMP(), 'CLAUDE_CODE')"
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash script/test_custom_headless_taxonomy.sh`
Expected: `ALL PASS`

- [ ] **Step 6: Commit**

```bash
git add script/custom_headless_taxonomy.sh script/test_custom_headless_taxonomy.sh
git commit -m "Cut over custom_headless_taxonomy.sh to category_brief (prompt text only)

Mirrors headless_taxonomy.sh's cutover; category_key uses the explicit
dataset argv instead of a fixed master_clean_niq prefix.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 6: Cut over `targeted_qa_fix.sh` to `category_brief`

**Files:**
- Modify: `script/targeted_qa_fix.sh`
- Test: `script/test_targeted_qa_fix.sh`

**Interfaces:**
- Removes: `resolve_category_file(table) -> path`
- Produces: `category_key_for(table) -> string`, `fetch_brief_markdown_query(category_key) -> SQL string`, `qa_history_insert_query(category_key) -> SQL string`, `insert_qa_history_row(category_key, finding, resolution, task_date)` (side-effecting, calls `bq query`).
- Changes: `has_real_brief(brief_markdown: string) -> "true"|"false"` (was `has_real_brief(category_file: path)`); `build_prompt(table, category_key, block_size, gate_report)` (was `build_prompt(table, category_file, ...)`); `build_auto_discovery_prompt(table, category_key, block_size, gate_report)` (same change).
- Consumes (Task 3's output): rows in `category_brief` — `main()` now fails loudly if no `BRIEF` row exists for the category, same as it previously failed if no file existed.

- [ ] **Step 1: Update the test file first (red)**

In `script/test_targeted_qa_fix.sh`, replace the entire `# --- resolve_category_file ---` block (lines 14–33 of the original) with:
```bash
# --- category_key_for ---
[[ "$(category_key_for "shopee_th_widget")" == "master_clean_niq.shopee_th_widget" ]] || fail "category_key_for should prefix with master_clean_niq"
echo "PASS: category_key_for"
```

Replace the entire `# --- has_real_brief ---` block with:
```bash
# --- has_real_brief ---
no_brief='# Category
## QA History'
[[ "$(has_real_brief "$no_brief")" == "false" ]] || fail "no Brief section -> false"

template_brief='## Targeted QA Fix Brief

> Scope note here.

**Verdict:** {defect class, e.g. "D1 Tier-C generic stubs"}

{Fix description}'
[[ "$(has_real_brief "$template_brief")" == "false" ]] || fail "unfilled template Verdict -> false"

real_brief='## Targeted QA Fix Brief

> Scope note here.

**Verdict:** D5 pack-count errors on 12 products

Fix these specific pack-count mistakes...'
[[ "$(has_real_brief "$real_brief")" == "true" ]] || fail "filled Verdict -> true"
echo "PASS: has_real_brief"
```

Replace the entire `# --- append_qa_history_row ---` block (including its "missing heading" sub-test) with:
```bash
# --- qa_history_insert_query ---
q=$(qa_history_insert_query "master_clean_niq.shopee_th_detergent")
echo "$q" | grep -q "INSERT INTO" || fail "qa_history_insert_query should build an INSERT statement"
echo "$q" | grep -q "'QA_HISTORY'" || fail "qa_history_insert_query should tag the row task_type='QA_HISTORY'"
echo "$q" | grep -q "@category_key" || fail "qa_history_insert_query should use a bound parameter for category_key, not string interpolation"
echo "$q" | grep -q "@task_date" || fail "qa_history_insert_query should use a bound parameter for task_date"
echo "$q" | grep -q "@brief_markdown" || fail "qa_history_insert_query should use a bound parameter for the finding/resolution text"
echo "$q" | grep -q "'CLAUDE_CODE'" || fail "qa_history_insert_query should hardcode meta_agent='CLAUDE_CODE'"
echo "PASS: qa_history_insert_query"
```

In the `# --- build_prompt ---` section, change the first two lines from:
```bash
prompt=$(build_prompt "shopee_th_detergent" "docs/categories/shopee_th_detergent.md")
grep -q "shopee_th_detergent" <<< "$prompt" || fail "build_prompt should mention the table name"
grep -q "docs/categories/shopee_th_detergent.md" <<< "$prompt" || fail "build_prompt should mention the category file path"
```
to:
```bash
prompt=$(build_prompt "shopee_th_detergent" "master_clean_niq.shopee_th_detergent")
grep -q "shopee_th_detergent" <<< "$prompt" || fail "build_prompt should mention the table name"
grep -q "master_clean_niq.shopee_th_detergent" <<< "$prompt" || fail "build_prompt should mention the category_key"
```
Change:
```bash
grep -q "Do not edit docs/categories/shopee_th_detergent.md or run git yourself" <<< "$prompt" || fail "build_prompt STEP 6 must not have the agent edit the file or commit directly"
```
to:
```bash
grep -q "Do not write to.*category_brief.*yourself" <<< "$prompt" || fail "build_prompt STEP 6 must not have the agent write to category_brief directly"
```

In the `# --- build_prompt: gate_report parameter (STEP 1B) ---` section, change:
```bash
prompt=$(build_prompt "shopee_th_detergent" "docs/categories/shopee_th_detergent.md" "200" "[FAIL] canonical_name fields:    5")
```
to:
```bash
prompt=$(build_prompt "shopee_th_detergent" "master_clean_niq.shopee_th_detergent" "200" "[FAIL] canonical_name fields:    5")
```

In every remaining `build_auto_discovery_prompt` call across the file (there are 4 occurrences, all of the form `build_auto_discovery_prompt "shopee_th_suncare" "docs/categories/shopee_th_suncare.md" ...`), replace `"docs/categories/shopee_th_suncare.md"` with `"master_clean_niq.shopee_th_suncare"`. Also change:
```bash
grep -q "docs/categories/shopee_th_suncare.md" <<< "$prompt" || fail "build_auto_discovery_prompt should mention the category file"
```
to:
```bash
grep -q "master_clean_niq.shopee_th_suncare" <<< "$prompt" || fail "build_auto_discovery_prompt should mention the category_key"
```
and:
```bash
grep -q "Do not edit docs/categories/shopee_th_suncare.md or run git yourself" <<< "$prompt" || fail "build_auto_discovery_prompt STEP 9 must not have the agent edit the file or commit directly"
```
to:
```bash
grep -q "Do not write to.*category_brief.*yourself" <<< "$prompt" || fail "build_auto_discovery_prompt STEP 9 must not have the agent write to category_brief directly"
```

In `# --- main(): pre-fix gate capture + coverage EXIT trap wiring ---`, replace:
```bash
grep -qF 'build_prompt "$table" "$category_file" "$block_size" "$gate_report"' <<< "$script_src" || fail "brief-mode call site must pass gate_report to build_prompt"
grep -qF 'build_auto_discovery_prompt "$table" "$category_file" "$block_size" "$gate_report"' <<< "$script_src" || fail "auto-discovery call site must pass gate_report to build_auto_discovery_prompt"
grep -qF 'qa_history_entry' <<< "$script_src" || fail "main() must read qa_history_entry from result_json"
grep -q 'append_qa_history_row' <<< "$script_src" || fail "main() must call append_qa_history_row"
```
with:
```bash
grep -qF 'build_prompt "$table" "$category_key" "$block_size" "$gate_report"' <<< "$script_src" || fail "brief-mode call site must pass category_key to build_prompt"
grep -qF 'build_auto_discovery_prompt "$table" "$category_key" "$block_size" "$gate_report"' <<< "$script_src" || fail "auto-discovery call site must pass category_key to build_auto_discovery_prompt"
grep -qF 'qa_history_entry' <<< "$script_src" || fail "main() must read qa_history_entry from result_json"
grep -q 'insert_qa_history_row' <<< "$script_src" || fail "main() must call insert_qa_history_row"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: FAIL at `category_key_for` (function doesn't exist yet)

- [ ] **Step 3: Add the new functions to `script/targeted_qa_fix.sh`**

Delete the entire `resolve_category_file()` function (lines 23–37).

Replace `has_real_brief()`'s body — change its parameter from a file path to a markdown string:
```bash
has_real_brief() {
  local category_file="$1"
  if ! grep -q "^## Targeted QA Fix Brief" "$category_file" 2>/dev/null; then
    echo "false"
    return
  fi
  local verdict_line
  verdict_line=$(grep "^\*\*Verdict:\*\*" "$category_file" | head -1)
  if [[ -z "$verdict_line" ]] || [[ "$verdict_line" == *"{"* ]]; then
    echo "false"
  else
    echo "true"
  fi
}
```
becomes:
```bash
has_real_brief() {
  local brief_markdown="$1"
  if ! grep -q "^## Targeted QA Fix Brief" <<< "$brief_markdown"; then
    echo "false"
    return
  fi
  local verdict_line
  verdict_line=$(grep "^\*\*Verdict:\*\*" <<< "$brief_markdown" | head -1)
  if [[ -z "$verdict_line" ]] || [[ "$verdict_line" == *"{"* ]]; then
    echo "false"
  else
    echo "true"
  fi
}
```

Replace `append_qa_history_row()` entirely (its whole body, lines 54–73) with:
```bash
category_key_for() {
  local table="$1"
  echo "master_clean_niq.${table}"
}

fetch_brief_markdown_query() {
  local category_key="$1"
  echo "SELECT brief_markdown FROM \`${PROJECT}.magpie_reference.category_brief\` WHERE category_key = '${category_key}' AND task_type = 'BRIEF'"
}

qa_history_insert_query() {
  local category_key="$1"
  echo "INSERT INTO \`${PROJECT}.magpie_reference.category_brief\` (category_key, task_type, task_date, brief_markdown, updated_at, meta_agent) VALUES (@category_key, 'QA_HISTORY', @task_date, @brief_markdown, CURRENT_TIMESTAMP(), 'CLAUDE_CODE')"
}

insert_qa_history_row() {
  local category_key="$1" finding="$2" resolution="$3" task_date="$4"
  local note
  note=$(printf 'Finding: %s\nResolution: %s' "$finding" "$resolution")
  bq query --use_legacy_sql=false --project_id="${PROJECT}" \
    --parameter="category_key::STRING:${category_key}" \
    --parameter="task_date::DATE:${task_date}" \
    --parameter="brief_markdown::STRING:${note}" \
    "$(qa_history_insert_query "$category_key")"
}
```

- [ ] **Step 4: Edit `build_prompt()` and `build_auto_discovery_prompt()`**

In both functions, change the parameter line from:
```bash
build_prompt() {
  local table="$1"
  local category_file="$2"
```
to:
```bash
build_prompt() {
  local table="$1"
  local category_key="$2"
```
(same change in `build_auto_discovery_prompt`)

In `build_prompt`, replace:
```
BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/llm-extraction-rules.md, docs/headless-runbook.md, docs/quality-standards.md, and ${category_file} (your fix brief lives in that file's '## Targeted QA Fix Brief' section — read it in full, it is the specific work for this session, not background).

If ${category_file} has no '## Targeted QA Fix Brief' section, or the section has no concrete fixes to perform, that is a genuine blocker: stop, write nothing, output status='blocked'.
```
with:
```
BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/llm-extraction-rules.md, docs/headless-runbook.md, docs/quality-standards.md, and the category brief — run: SELECT brief_markdown FROM \`${PROJECT}.magpie_reference.category_brief\` WHERE category_key = '${category_key}' AND task_type = 'BRIEF' (your fix brief lives in that content's '## Targeted QA Fix Brief' section — read it in full, it is the specific work for this session, not background).

If the category brief has no '## Targeted QA Fix Brief' section, or the section has no concrete fixes to perform, that is a genuine blocker: stop, write nothing, output status='blocked'.
```
Replace:
```
STEP 6 — Do not edit ${category_file} or run git yourself. Instead, set the final JSON output's
qa_history_entry field to {finding: "...", resolution: "..."} summarizing what you did and found this
session — the same content that used to go directly into the QA History table's Finding/Resolution columns.
The wrapper appends it to ${category_file} and commits on your behalf after you finish.
```
with:
```
STEP 6 — Do not write to \`${PROJECT}.magpie_reference.category_brief\` yourself. Instead, set the final
JSON output's qa_history_entry field to {finding: "...", resolution: "..."} summarizing what you did and
found this session. The wrapper inserts it as a QA_HISTORY row on your behalf after you finish.
```

In `build_auto_discovery_prompt`, replace:
```
Automated Taxonomy Review session for ${table}. No '## Targeted QA Fix Brief' section with real content
exists in ${category_file} — this session auto-discovers its own scope instead of executing a hand-written
brief. See docs/superpowers/specs/2026-07-21-taxonomy-review-loop-design.md for the full design.

BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/llm-extraction-rules.md (including §11,
Signal Provenance & Cross-Validation), docs/quality-standards.md, docs/brand-extraction.md,
docs/headless-runbook.md, and ${category_file} (brand scope, allowlist, and scope rules are already
documented there — do not rediscover them from scratch).
```
with:
```
Automated Taxonomy Review session for ${table}. No '## Targeted QA Fix Brief' section with real content
exists in the category brief — this session auto-discovers its own scope instead of executing a
hand-written brief. See docs/superpowers/specs/2026-07-21-taxonomy-review-loop-design.md for the full
design.

BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/llm-extraction-rules.md (including §11,
Signal Provenance & Cross-Validation), docs/quality-standards.md, docs/brand-extraction.md,
docs/headless-runbook.md, and the category brief — run: SELECT brief_markdown FROM
\`${PROJECT}.magpie_reference.category_brief\` WHERE category_key = '${category_key}' AND task_type =
'BRIEF' (brand scope, allowlist, and scope rules are already documented there — do not rediscover them
from scratch).
```
Replace:
```
STEP 9 — Do not edit ${category_file} or run git yourself. Instead, set the final JSON output's
qa_history_entry field to {finding: "...", resolution: "..."} summarizing what you reviewed, what you fixed,
and the confidence distribution you left behind — the same content that used to go directly into the QA
History table's Finding/Resolution columns. The wrapper appends it to ${category_file} and commits on your
behalf after you finish.
```
with:
```
STEP 9 — Do not write to \`${PROJECT}.magpie_reference.category_brief\` yourself. Instead, set the final
JSON output's qa_history_entry field to {finding: "...", resolution: "..."} summarizing what you reviewed,
what you fixed, and the confidence distribution you left behind. The wrapper inserts it as a QA_HISTORY
row on your behalf after you finish.
```
(All other `${category_file}` uses inside `qa_gate_exceptions` lookups etc. reference `master_table = '${table}'`, which is already correct and untouched — `${category_file}` no longer appears in the body of either function after these edits; `grep -n '\${category_file}' script/targeted_qa_fix.sh` should return nothing once done.)

- [ ] **Step 5: Edit `main()` in `script/targeted_qa_fix.sh`**

Replace:
```bash
  local category_file
  if ! category_file=$(resolve_category_file "$table"); then
    echo "ERROR: no category file found at docs/categories/${table}.md or docs/categories/${table#shopee_}.md" >&2
    echo "A Targeted QA Fix requires an existing, documented category — write the category file (and its '## Targeted QA Fix Brief' section) first." >&2
    exit 1
  fi
```
with:
```bash
  local category_key
  category_key=$(category_key_for "$table")

  local brief_markdown
  brief_markdown=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=json \
    "$(fetch_brief_markdown_query "$category_key")" | jq -r '.[0].brief_markdown // empty')
  if [[ -z "$brief_markdown" ]]; then
    echo "ERROR: no category_brief BRIEF row found for category_key=${category_key}" >&2
    echo "A Targeted QA Fix requires an existing, documented category — run headless_taxonomy.sh's Full Rebuild first." >&2
    exit 1
  fi
```

Replace:
```bash
  local prompt
  if [[ "$(has_real_brief "$category_file")" == "true" ]]; then
    echo "TARGETED QA FIX STARTED (brief mode: ${category_file}, block_size=${block_size}, max_turns=${max_turns})"
    echo "==========================="
    prompt=$(build_prompt "$table" "$category_file" "$block_size" "$gate_report")
  else
```
with:
```bash
  local prompt
  if [[ "$(has_real_brief "$brief_markdown")" == "true" ]]; then
    echo "TARGETED QA FIX STARTED (brief mode: ${category_key}, block_size=${block_size}, max_turns=${max_turns})"
    echo "==========================="
    prompt=$(build_prompt "$table" "$category_key" "$block_size" "$gate_report")
  else
```

Replace:
```bash
    echo "TARGETED QA FIX STARTED (auto-discovery mode: ${category_file}, block_size=${block_size}, max_turns=${max_turns}, review_worklist_count=${review_worklist_count})"
    echo "==========================="
    prompt=$(build_auto_discovery_prompt "$table" "$category_file" "$block_size" "$gate_report")
```
with:
```bash
    echo "TARGETED QA FIX STARTED (auto-discovery mode: ${category_key}, block_size=${block_size}, max_turns=${max_turns}, review_worklist_count=${review_worklist_count})"
    echo "==========================="
    prompt=$(build_auto_discovery_prompt "$table" "$category_key" "$block_size" "$gate_report")
```

Replace:
```bash
  if [[ -n "$qa_finding" ]]; then
    local qa_timestamp
    qa_timestamp=$(date -u +'%Y-%m-%d %H:%M UTC')
    if append_qa_history_row "$category_file" "$qa_finding" "$qa_resolution" "$qa_timestamp"; then
      echo "Appending QA History row and committing..."
      git add "$category_file"
      git commit -m "Automated review session for ${table}: update QA History"
    else
      echo "WARNING: could not append QA History row (no '## QA History' heading or closing '---' found in ${category_file}) — skipping commit." >&2
    fi
  fi
```
with:
```bash
  if [[ -n "$qa_finding" ]]; then
    local qa_task_date
    qa_task_date=$(date -u +'%Y-%m-%d')
    insert_qa_history_row "$category_key" "$qa_finding" "$qa_resolution" "$qa_task_date"
    echo "Inserted QA_HISTORY row for ${category_key}."
  fi
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: `ALL TESTS PASSED`

- [ ] **Step 7: Commit**

```bash
git add script/targeted_qa_fix.sh script/test_targeted_qa_fix.sh
git commit -m "Cut over targeted_qa_fix.sh to category_brief

resolve_category_file()'s guess-both-and-see fallback is deleted outright
-- the deterministic category_key removes the ambiguity it existed to
paper over. The wrapper (not the agent) still performs the QA_HISTORY
write, preserving the existing 'agent must not touch the shared doc
directly' safety boundary, now via a parameterized bq query INSERT
instead of file-append + git commit.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 7: Cut over `custom_targeted_qa_fix.sh` to `category_brief`

**Files:**
- Modify: `script/custom_targeted_qa_fix.sh`
- Test: `script/test_custom_targeted_qa_fix.sh`

**Interfaces:**
- Same shape as Task 6, but `category_key_for(dataset, category)` takes two arguments (dataset is an explicit script arg here, not a fixed prefix).

- [ ] **Step 1: Update the test file first (red)**

Replace the entire `# --- resolve_category_file (no shopee_ stripping — CATEGORY is the exact filename) ---` block with:
```bash
# --- category_key_for ---
[[ "$(category_key_for "makanankucing" "makanankucing_my")" == "makanankucing.makanankucing_my" ]] || fail "category_key_for should join dataset.category"
echo "PASS: category_key_for"
```

Keep the `# --- has_real_brief ---` block's content the same (it already passes markdown strings via `<tmpdir>/real_brief.md` etc.) but change every `has_real_brief "$tmpdir/....md"` call to pass the file's content directly instead of a path — replace:
```bash
cat > "$tmpdir/real_brief.md" <<'EOF'
## Targeted QA Fix Brief

**Verdict:** D5 pack-count errors on 12 products

Fix these specific pack-count mistakes...
EOF
[[ "$(has_real_brief "$tmpdir/real_brief.md")" == "true" ]] || fail "filled Verdict -> true"
```
with:
```bash
real_brief='## Targeted QA Fix Brief

**Verdict:** D5 pack-count errors on 12 products

Fix these specific pack-count mistakes...'
[[ "$(has_real_brief "$real_brief")" == "true" ]] || fail "filled Verdict -> true"
```
and similarly for `future_scope_brief` and `scoped_brief` (assign the heredoc content to a variable via `$(cat <<'EOF' ... EOF)` and pass the variable, instead of writing to a file first and passing the path). Remove the `tmpdir=$(mktemp -d)` / `rm -rf "$tmpdir"` lines from this block entirely (no longer needed since no files are created).

In `# --- build_prompt ---`, change:
```bash
prompt=$(build_prompt "makanankucing" "9_makanankucing_my_daily" "makanankucing_my" "docs/categories/makanankucing_my.md")
```
to:
```bash
prompt=$(build_prompt "makanankucing" "9_makanankucing_my_daily" "makanankucing_my" "makanankucing.makanankucing_my")
```

In `# --- build_prompt: gate_report parameter (STEP 1B) ---`, change:
```bash
prompt=$(build_prompt "makanankucing" "9_makanankucing_my_daily" "makanankucing_my" "docs/categories/makanankucing_my.md" "200" "[FAIL] canonical_name fields:    5")
```
to:
```bash
prompt=$(build_prompt "makanankucing" "9_makanankucing_my_daily" "makanankucing_my" "makanankucing.makanankucing_my" "200" "[FAIL] canonical_name fields:    5")
```

In every `build_auto_discovery_prompt` call (3 occurrences), change `"docs/categories/makanankucing_my.md"` to `"makanankucing.makanankucing_my"`.

In `# --- main(): DATASET/SOURCE_TABLE/CATEGORY wiring + coverage EXIT trap ---`, change:
```bash
grep -qF 'build_prompt "$dataset" "$table" "$category" "$category_file" "$block_size" "$gate_report"' <<< "$script_src" || fail "brief-mode call site must pass dataset/table/category in that order"
grep -qF 'build_auto_discovery_prompt "$dataset" "$table" "$category" "$category_file" "$block_size" "$gate_report"' <<< "$script_src" || fail "auto-discovery call site must pass dataset/table/category in that order"
```
to:
```bash
grep -qF 'build_prompt "$dataset" "$table" "$category" "$category_key" "$block_size" "$gate_report"' <<< "$script_src" || fail "brief-mode call site must pass category_key, not a file path"
grep -qF 'build_auto_discovery_prompt "$dataset" "$table" "$category" "$category_key" "$block_size" "$gate_report"' <<< "$script_src" || fail "auto-discovery call site must pass category_key, not a file path"
```
and add:
```bash
grep -q 'insert_qa_history_row' <<< "$script_src" || fail "main() must call insert_qa_history_row"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash script/test_custom_targeted_qa_fix.sh`
Expected: FAIL at `category_key_for` (function doesn't exist yet)

- [ ] **Step 3: Edit `script/custom_targeted_qa_fix.sh`**

Delete `resolve_category_file()` entirely (lines 33–41).

Change `has_real_brief()`'s parameter from a file path to a markdown string — replace every `"$category_file" 2>/dev/null` / `"$category_file"` read with `<<< "$brief_markdown"`:
```bash
has_real_brief() {
  local brief_markdown="$1"
  local brief_line
  brief_line=$(grep -n "^## Targeted QA Fix Brief" <<< "$brief_markdown" | head -1 | cut -d: -f1)
  if [[ -z "$brief_line" ]]; then
    echo "false"
    return
  fi
  local section
  section=$(awk -v start="$brief_line" 'NR > start && /^## / { exit } NR >= start { print }' <<< "$brief_markdown")
  if grep -qi "not executed this session" <<< "$section"; then
    echo "false"
    return
  fi
  local verdict_line
  verdict_line=$(grep "^\*\*Verdict:\*\*" <<< "$section" | head -1)
  if [[ -z "$verdict_line" ]] || [[ "$verdict_line" == *"{"* ]]; then
    echo "false"
  else
    echo "true"
  fi
}
```

Replace `append_qa_history_row()` entirely with:
```bash
category_key_for() {
  local dataset="$1" category="$2"
  echo "${dataset}.${category}"
}

fetch_brief_markdown_query() {
  local category_key="$1"
  echo "SELECT brief_markdown FROM \`${PROJECT}.magpie_reference.category_brief\` WHERE category_key = '${category_key}' AND task_type = 'BRIEF'"
}

qa_history_insert_query() {
  local category_key="$1"
  echo "INSERT INTO \`${PROJECT}.magpie_reference.category_brief\` (category_key, task_type, task_date, brief_markdown, updated_at, meta_agent) VALUES (@category_key, 'QA_HISTORY', @task_date, @brief_markdown, CURRENT_TIMESTAMP(), 'CLAUDE_CODE')"
}

insert_qa_history_row() {
  local category_key="$1" finding="$2" resolution="$3" task_date="$4"
  local note
  note=$(printf 'Finding: %s\nResolution: %s' "$finding" "$resolution")
  bq query --use_legacy_sql=false --project_id="${PROJECT}" \
    --parameter="category_key::STRING:${category_key}" \
    --parameter="task_date::DATE:${task_date}" \
    --parameter="brief_markdown::STRING:${note}" \
    "$(qa_history_insert_query "$category_key")"
}
```

- [ ] **Step 4: Edit `build_prompt()` and `build_auto_discovery_prompt()`**

Change the parameter line in both functions from:
```bash
build_prompt() {
  local dataset="$1" table="$2" category="$3" category_file="$4" block_size="${5:-200}" gate_report="${6:-}"
```
to:
```bash
build_prompt() {
  local dataset="$1" table="$2" category="$3" category_key="$4" block_size="${5:-200}" gate_report="${6:-}"
```
(same rename in `build_auto_discovery_prompt`)

In `build_prompt`, replace:
```
BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/llm-extraction-rules.md, docs/headless-runbook.md, docs/quality-standards.md, and ${category_file} (your fix brief lives in that file's '## Targeted QA Fix Brief' section — read it in full, it is the specific work for this session, not background).

If ${category_file} has no '## Targeted QA Fix Brief' section, or the section has no concrete fixes to perform, that is a genuine blocker: stop, write nothing, output status='blocked'.
```
with:
```
BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/llm-extraction-rules.md, docs/headless-runbook.md, docs/quality-standards.md, and the category brief — run: SELECT brief_markdown FROM \`${PROJECT}.magpie_reference.category_brief\` WHERE category_key = '${category_key}' AND task_type = 'BRIEF' (your fix brief lives in that content's '## Targeted QA Fix Brief' section — read it in full, it is the specific work for this session, not background).

If the category brief has no '## Targeted QA Fix Brief' section, or the section has no concrete fixes to perform, that is a genuine blocker: stop, write nothing, output status='blocked'.
```
Replace:
```
STEP 6 — Do not edit ${category_file} or run git yourself. Instead, set the final JSON output's
qa_history_entry field to {finding: "...", resolution: "..."} summarizing what you did and found this
session — the same content that used to go directly into the QA History table's Finding/Resolution columns.
The wrapper appends it to ${category_file} and commits on your behalf after you finish.
```
with:
```
STEP 6 — Do not write to \`${PROJECT}.magpie_reference.category_brief\` yourself. Instead, set the final
JSON output's qa_history_entry field to {finding: "...", resolution: "..."} summarizing what you did and
found this session. The wrapper inserts it as a QA_HISTORY row on your behalf after you finish.
```

In `build_auto_discovery_prompt`, replace:
```
Automated Taxonomy Review session for master_table='${category}' (custom source:
\`${PROJECT}.${dataset}.${table}\`, not master_clean_niq). No '## Targeted QA Fix Brief' section with
real content exists in ${category_file} — this session auto-discovers its own scope instead of
executing a hand-written brief. See docs/superpowers/specs/2026-07-21-taxonomy-review-loop-design.md
for the full design.

BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/llm-extraction-rules.md (including §11,
Signal Provenance & Cross-Validation), docs/quality-standards.md, docs/brand-extraction.md,
docs/headless-runbook.md, and ${category_file} (brand scope, allowlist, and scope rules are already
documented there — do not rediscover them from scratch).
```
with:
```
Automated Taxonomy Review session for master_table='${category}' (custom source:
\`${PROJECT}.${dataset}.${table}\`, not master_clean_niq). No '## Targeted QA Fix Brief' section with
real content exists in the category brief — this session auto-discovers its own scope instead of
executing a hand-written brief. See docs/superpowers/specs/2026-07-21-taxonomy-review-loop-design.md
for the full design.

BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/llm-extraction-rules.md (including §11,
Signal Provenance & Cross-Validation), docs/quality-standards.md, docs/brand-extraction.md,
docs/headless-runbook.md, and the category brief — run: SELECT brief_markdown FROM
\`${PROJECT}.magpie_reference.category_brief\` WHERE category_key = '${category_key}' AND task_type =
'BRIEF' (brand scope, allowlist, and scope rules are already documented there — do not rediscover them
from scratch).
```
Replace:
```
STEP 9 — Do not edit ${category_file} or run git yourself. Instead, set the final JSON output's
qa_history_entry field to {finding: "...", resolution: "..."} summarizing what you reviewed, what you fixed,
and the confidence distribution you left behind — the same content that used to go directly into the QA
History table's Finding/Resolution columns. The wrapper appends it to ${category_file} and commits on your
behalf after you finish.
```
with:
```
STEP 9 — Do not write to \`${PROJECT}.magpie_reference.category_brief\` yourself. Instead, set the final
JSON output's qa_history_entry field to {finding: "...", resolution: "..."} summarizing what you reviewed,
what you fixed, and the confidence distribution you left behind. The wrapper inserts it as a QA_HISTORY
row on your behalf after you finish.
```

- [ ] **Step 5: Edit `main()` in `script/custom_targeted_qa_fix.sh`**

Replace:
```bash
  local category_file
  if ! category_file=$(resolve_category_file "$category"); then
    echo "ERROR: no category file found at docs/categories/${category}.md" >&2
    echo "A Targeted QA Fix requires an existing, documented category — write the category file (and its '## Targeted QA Fix Brief' section) first, e.g. via script/custom_headless_taxonomy.sh." >&2
    exit 1
  fi
```
with:
```bash
  local category_key
  category_key=$(category_key_for "$dataset" "$category")

  local brief_markdown
  brief_markdown=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=json \
    "$(fetch_brief_markdown_query "$category_key")" | jq -r '.[0].brief_markdown // empty')
  if [[ -z "$brief_markdown" ]]; then
    echo "ERROR: no category_brief BRIEF row found for category_key=${category_key}" >&2
    echo "A Targeted QA Fix requires an existing, documented category — run custom_headless_taxonomy.sh's Full Rebuild first." >&2
    exit 1
  fi
```

Replace:
```bash
  local prompt
  if [[ "$(has_real_brief "$category_file")" == "true" ]]; then
    echo "TARGETED QA FIX STARTED (brief mode: ${category_file}, block_size=${block_size}, max_turns=${max_turns})"
    echo "==========================="
    prompt=$(build_prompt "$dataset" "$table" "$category" "$category_file" "$block_size" "$gate_report")
  else
```
with:
```bash
  local prompt
  if [[ "$(has_real_brief "$brief_markdown")" == "true" ]]; then
    echo "TARGETED QA FIX STARTED (brief mode: ${category_key}, block_size=${block_size}, max_turns=${max_turns})"
    echo "==========================="
    prompt=$(build_prompt "$dataset" "$table" "$category" "$category_key" "$block_size" "$gate_report")
  else
```

Replace:
```bash
    echo "TARGETED QA FIX STARTED (auto-discovery mode: ${category_file}, block_size=${block_size}, max_turns=${max_turns}, review_worklist_count=${review_worklist_count})"
    echo "==========================="
    prompt=$(build_auto_discovery_prompt "$dataset" "$table" "$category" "$category_file" "$block_size" "$gate_report")
```
with:
```bash
    echo "TARGETED QA FIX STARTED (auto-discovery mode: ${category_key}, block_size=${block_size}, max_turns=${max_turns}, review_worklist_count=${review_worklist_count})"
    echo "==========================="
    prompt=$(build_auto_discovery_prompt "$dataset" "$table" "$category" "$category_key" "$block_size" "$gate_report")
```

Replace:
```bash
  if [[ -n "$qa_finding" ]]; then
    local qa_timestamp
    qa_timestamp=$(date -u +'%Y-%m-%d %H:%M UTC')
    if append_qa_history_row "$category_file" "$qa_finding" "$qa_resolution" "$qa_timestamp"; then
      echo "Appending QA History row and committing..."
      git add "$category_file"
      git commit -m "Automated review session for ${category}: update QA History"
    else
      echo "WARNING: could not append QA History row (no '## QA History' heading or closing '---' found in ${category_file}) — skipping commit." >&2
    fi
  fi
```
with:
```bash
  if [[ -n "$qa_finding" ]]; then
    local qa_task_date
    qa_task_date=$(date -u +'%Y-%m-%d')
    insert_qa_history_row "$category_key" "$qa_finding" "$qa_resolution" "$qa_task_date"
    echo "Inserted QA_HISTORY row for ${category_key}."
  fi
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `bash script/test_custom_targeted_qa_fix.sh`
Expected: `ALL TESTS PASSED`

- [ ] **Step 7: Commit**

```bash
git add script/custom_targeted_qa_fix.sh script/test_custom_targeted_qa_fix.sh
git commit -m "Cut over custom_targeted_qa_fix.sh to category_brief

Mirrors targeted_qa_fix.sh's cutover; category_key_for takes the explicit
dataset arg instead of a fixed prefix.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 8: Add a pointer note to `docs/categories/STATUS.md`

**Files:**
- Modify: `docs/categories/STATUS.md`

**Interfaces:**
- None — this is a documentation-only change.

- [ ] **Step 1: Add the pointer note**

Replace:
```
# Category Extraction Status Dashboard

Last updated: Jun 24 2026

---
```
with:
```
# Category Extraction Status Dashboard

Last updated: Jun 24 2026

> **Frozen as of 2026-07-29.** Live per-category status now lives in BigQuery:
> `SELECT category_key, status, live_map_rows, orphan_map_rows FROM sincere-hearth-273704.magpie_reference.category_brief WHERE task_type = 'BRIEF'`.
> This file is a historical snapshot from before that migration — do not trust it for current state.

---
```

- [ ] **Step 2: Verify**

Run: `grep -A2 "Frozen as of 2026-07-29" docs/categories/STATUS.md`
Expected: the 3 new lines appear, followed by the SKU Block Registry section further down (unchanged).

- [ ] **Step 3: Commit**

```bash
git add docs/categories/STATUS.md
git commit -m "Add category_brief pointer note to docs/categories/STATUS.md

STATUS.md is not a per-category brief and isn't migrated as category_brief
data; it's frozen as a historical snapshot with a pointer to where live
status now lives.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 9: Dry-run verification + confirm no live session before deletion

**Files:**
- No file changes — verification only.

**Interfaces:**
- Consumes: Tasks 4–7's updated scripts.

- [ ] **Step 1: Dry-run a `headless_taxonomy.sh` prompt build**

Run:
```bash
cd /home/wikan/Documents/work/product-taxonomy-extraction
source script/headless_taxonomy.sh
build_topup_prompt "shopee_th_body_wash" "2026-06" "500" "10" | head -30
```
Expected: output includes `category_key = 'master_clean_niq.shopee_th_body_wash'` and `task_type = 'BRIEF'`, no `docs/categories/shopee_th_body_wash.md` reference. Eyeball the full output for coherence (read past `head -30` if anything looks off).

- [ ] **Step 2: Dry-run a `targeted_qa_fix.sh` prompt build**

Run:
```bash
source script/targeted_qa_fix.sh
build_auto_discovery_prompt "shopee_th_body_wash" "master_clean_niq.shopee_th_body_wash" "200" "" | head -30
```
Expected: output includes the `SELECT brief_markdown FROM ... category_brief ... WHERE category_key = 'master_clean_niq.shopee_th_body_wash'` line, no `docs/categories` reference anywhere in the full output (`... | grep -c "docs/categories"` should print `0`).

- [ ] **Step 3: Confirm no live queue worker or claude -p session is running**

Run: `ps aux | grep -iE "queue_worker\.sh|headless_taxonomy\.sh|targeted_qa_fix\.sh|claude -p" | grep -v grep`
Expected: empty output. If any process is listed, **stop this task** and either wait for it to finish or ask the user whether to pause `queue_worker.sh` before continuing to Task 10 — do not delete files while a session referencing them may still be running.

- [ ] **Step 4: No commit** (verification only) — proceed to Task 10 once Step 3 is confirmed empty.

---

## Task 10: Delete `docs/categories/*.md` (except STATUS.md and _TEMPLATE.md)

**Files:**
- Delete: all 42 files under `docs/categories/` except `STATUS.md` and `_TEMPLATE.md`.

**Interfaces:**
- None.

- [ ] **Step 1: Re-confirm no live session (repeat Task 9 Step 3 — state may have changed)**

Run: `ps aux | grep -iE "queue_worker\.sh|headless_taxonomy\.sh|targeted_qa_fix\.sh|claude -p" | grep -v grep`
Expected: empty output.

- [ ] **Step 2: Delete the files**

Run:
```bash
cd /home/wikan/Documents/work/product-taxonomy-extraction
find docs/categories -maxdepth 1 -name "*.md" ! -name "STATUS.md" ! -name "_TEMPLATE.md" -exec git rm {} +
```

- [ ] **Step 3: Verify only the two expected files remain**

Run: `ls docs/categories/`
Expected: exactly `STATUS.md` and `_TEMPLATE.md`.

- [ ] **Step 4: Re-run all four script test suites** (confirm no test still depends on a now-deleted file existing on disk)

Run:
```bash
bash script/test_headless_taxonomy.sh
bash script/test_custom_headless_taxonomy.sh
bash script/test_targeted_qa_fix.sh
bash script/test_custom_targeted_qa_fix.sh
```
Expected: all four print their `ALL TESTS PASSED` / `ALL PASS` line.

- [ ] **Step 5: Commit**

```bash
git commit -m "Delete docs/categories/*.md — migrated to BigQuery category_brief

All 42 category docs are now live in
sincere-hearth-273704.magpie_reference.category_brief (migrated in an
earlier commit, reality-checked against live product_taxonomy_map).
headless_taxonomy.sh / custom_headless_taxonomy.sh / targeted_qa_fix.sh /
custom_targeted_qa_fix.sh were cut over to read/write it in prior commits
on this branch. STATUS.md and _TEMPLATE.md are kept (frozen snapshot /
template respectively, neither is per-category brief data).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Task 11: Update the pipeline-wide TH data-loss memory

**Files:**
- Modify: `/home/wikan/.claude/projects/-home-wikan-Documents-work-product-taxonomy-extraction/memory/project_th_baby_diapers_data_loss.md`

**Interfaces:**
- Consumes: Task 3's per-category `status` classification (query `category_brief` for every `master_clean_niq.shopee_th_*` category_key).

- [ ] **Step 1: Gather the final classification**

Run:
```bash
bq query --use_legacy_sql=false --format=prettyjson "SELECT category_key, status, live_map_rows, orphan_map_rows FROM \`sincere-hearth-273704.magpie_reference.category_brief\` WHERE task_type = 'BRIEF' AND category_key LIKE 'master_clean_niq.shopee_th_%' ORDER BY category_key"
```

- [ ] **Step 2: Append an update section to the memory file**

Add a new `**UPDATE 2026-07-29 (category_brief migration — reality-check classification recorded):**` section at the end of the file (after the existing last `**UPDATE ...**` section), summarizing, per category, which are `active` (confirmed intact — no memory action needed), which are `reset_pending_redo` (this migration's `classify_status` treated the doc/live mismatch as a deliberate reset and recorded it structurally in `category_brief.status`, rather than requiring further escalation), and which are `partial_loss` (still worth flagging as unresolved, same as before). Use the actual query output from Step 1 to write this — do not guess at category names or counts; every value in this section must come from the live query result.

- [ ] **Step 3: Verify**

Read the file back and confirm the new section is present, dated 2026-07-29, and every category name mentioned matches a row from Step 1's query output.

(No git commit — this is a memory file outside the repo, not tracked by `git status` in `product-taxonomy-extraction`.)

---

## Self-Review Notes

- **Spec coverage:** §1 (schema) → Task 1. §2 (key derivation) → Task 2's `CATEGORY_MAP`/`derive_country`. §3 (reality check) → Task 2's `classify_status`/`build_reality_note` + Task 3's live run. §4 (write path) → Tasks 4–7's load+MERGE / parameterized INSERT split. §5 (script cutover) → Tasks 4–7. §6 (STATUS.md/_TEMPLATE.md) → Task 8 (STATUS.md); `_TEMPLATE.md` explicitly left unchanged, confirmed by no task touching it. §7 (rollout order) → Task ordering 1→2→3→(4-7)→8→9→10, with Task 9 gating Task 10 on the live-process check and Task 11 folded in after deletion per the spec's step 7.
- **Placeholder scan:** no `TBD`/`TODO` remain; every SQL/bash/Python snippet is complete and runnable as written; Task 11 explicitly requires using real query output rather than invented example values.
- **Type consistency:** `category_key_for` returns a plain string in both `targeted_qa_fix.sh` (1-arg) and `custom_targeted_qa_fix.sh` (2-arg) — deliberately different signatures per script, matching each script's existing `dataset` handling (fixed vs. explicit arg), not an inconsistency. `qa_history_insert_query`/`insert_qa_history_row`/`fetch_brief_markdown_query` have identical signatures and bodies across both `targeted_qa_fix.sh` and `custom_targeted_qa_fix.sh`, matching the existing convention of duplicating shared logic across the two scripts rather than a shared library (confirmed during exploration: `extract_json_object`/`decide_next_step`/`mark_failed_qa`/`run_universe_refresh` are already duplicated verbatim between the two files).
