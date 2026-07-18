# Embedding + Nearest-Neighbor Taxonomy Match Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a Tier 3 embedding-match layer — auto-match new products to existing taxonomy entries (skipping
the LLM entirely when confident) and flag disagreements on already-mapped `source='LLM'` rows (audit mode,
never auto-fixing) — wired into `script/headless_taxonomy.sh` as a pre-step before every `claude -p` call.

**Architecture:** Embeddings are generated externally by a Python worker on the existing Hetzner VM
(`intfloat/multilingual-e5-large` via `sentence-transformers`, cron'd) and batch-loaded into two new BigQuery
tables. All matching logic — brand/size filtering, nearest-neighbor ranking, thresholds, and both auto-match and
audit modes — is pure BigQuery SQL (`ML.DISTANCE` over the precomputed vectors, `JOIN` + `QUALIFY
ROW_NUMBER()` for top-1 selection). This split is what keeps a future move to BigQuery-native Vertex AI
embeddings (`ML.GENERATE_EMBEDDING`) an isolated swap of the worker only.

**Tech Stack:** BigQuery Standard SQL (native `ML.DISTANCE`, no remote connection needed), Python 3
(`google-cloud-bigquery`, `sentence-transformers`) running on the Hetzner VM, bash (`script/headless_taxonomy.sh`).

## Global Constraints

- Source spec: [`docs/superpowers/specs/2026-07-17-embedding-nn-match-design.md`](../specs/2026-07-17-embedding-nn-match-design.md) — read it before starting; this plan implements it and does not re-derive its reasoning.
- Brand filter is a **hard requirement** for both modes: `u.brand_confidence IN ('HIGH', 'MEDIUM') AND
  u.brand_id NOT IN ('BRD-UNDEFINED', 'BRD-UNBRANDED')` on `magpie.marketshare_universe_niq` — no fallback when
  brand isn't resolved; the product just falls through to Tier 5 as it does today.
- Size filter (`parse_size`, already live at `` `sincere-hearth-273704.magpie_reference.parse_size` ``) is a
  **soft fallback** — apply it when non-NULL, skip it otherwise. Never require it.
- **The incoming-product source table is `magpie.marketshare_universe_niq`, not `magpie.marketshare_universe`.**
  The latter is a separate Intrepid/appliance universe with no FMCG data and no `master_table`/`brand_id`
  columns at all — confirmed live during design (see the design doc's two-round correction). Every query in
  this plan against "the universe" means `marketshare_universe_niq`.
- **No `LATERAL` keyword and no `AS alias(column)` column-alias-list syntax** — both confirmed absent from
  BigQuery during design. Use `JOIN` + `QUALIFY ROW_NUMBER() OVER (PARTITION BY ... ORDER BY distance) = 1` for
  top-1-per-group selection, and `UNNEST([scalar_expr]) AS alias` (alias used directly, not `alias.field`) to
  bring a computed scalar into scope as a joinable column.
- Auto-match only ever `INSERT`s into `product_taxonomy_map` where `taxonomy_id IS NULL` for that product — never
  `UPDATE`s. Audit mode only ever `INSERT`s into the new `taxonomy_match_audit_flags` table — never touches
  `product_taxonomy_map`.
- Every inserted `product_taxonomy_map` row sets `meta_agent` (never NULL, per `AGENTS.md`) and
  `source = 'EMBEDDING_MATCH'`. `confidence` is written as a formatted **STRING** (e.g. `'0.87'`) — the live
  column is STRING, not FLOAT64, despite what `sql/schema/product_taxonomy_map.sql` says.
- Dry-run (`bq query --dry_run --use_legacy_sql=false`) every query touching `marketshare_universe_niq` before
  running it for real.
- Batch load only (`bq load` / `client.load_table_from_json`) for writing embeddings — never the streaming API
  (90-minute streaming-buffer rule, same as everywhere else in this pipeline).
- Project: `sincere-hearth-273704`. All table references below use the fully-qualified form.

---

### Task 1: Create the three new BigQuery tables

**Files:**
- Create: `sql/schema/product_taxonomy_embeddings.sql`
- Create: `sql/schema/universe_sku_embeddings.sql`
- Create: `sql/schema/taxonomy_match_audit_flags.sql`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: three empty tables. Task 2 writes to `product_taxonomy_embeddings` and `universe_sku_embeddings`.
  Task 4 writes to `taxonomy_match_audit_flags`. Task 3 reads from the first two. Column names/types below are
  exact and used verbatim by every later task — there is no other definition of these tables anywhere.

- [ ] **Step 1: Write the three schema files**

```sql
-- sql/schema/product_taxonomy_embeddings.sql
-- One embedding vector per product_taxonomy row, computed externally (Hetzner worker, see
-- docs/superpowers/specs/2026-07-17-embedding-nn-match-design.md) and loaded via batch load — never streamed.
-- Populated incrementally: the worker only ever inserts taxonomy_ids not yet present here.

CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.product_taxonomy_embeddings` (
  taxonomy_id    STRING         NOT NULL,  -- FK -> product_taxonomy.taxonomy_id
  embedding      ARRAY<FLOAT64> NOT NULL,  -- multilingual-e5-large output, 1024 dims
  model_version  STRING         NOT NULL,  -- e.g. 'intfloat/multilingual-e5-large'
  computed_at    TIMESTAMP      NOT NULL
)
OPTIONS (
  description = "Embeddings of product_taxonomy.canonical_name, computed by the self-hosted Hetzner worker. One row per taxonomy_id. See docs/superpowers/specs/2026-07-17-embedding-nn-match-design.md."
);
```

```sql
-- sql/schema/universe_sku_embeddings.sql
-- One embedding vector per (product_id, platform, country) — the ADR-006 composite key — computed externally
-- (Hetzner worker) from marketshare_universe_niq.sku_name, loaded via batch load, never streamed.

CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.universe_sku_embeddings` (
  product_id     STRING         NOT NULL,
  platform       STRING         NOT NULL,  -- matches marketshare_universe_niq.ecommerce_platform
  country        STRING         NOT NULL,
  embedding      ARRAY<FLOAT64> NOT NULL,  -- multilingual-e5-large output, 1024 dims
  model_version  STRING         NOT NULL,
  computed_at    TIMESTAMP      NOT NULL
)
CLUSTER BY platform, country, product_id
OPTIONS (
  description = "Embeddings of marketshare_universe_niq.sku_name, keyed by the ADR-006 composite key. Computed by the self-hosted Hetzner worker. See docs/superpowers/specs/2026-07-17-embedding-nn-match-design.md."
);
```

```sql
-- sql/schema/taxonomy_match_audit_flags.sql
-- Flag-only output of embedding-match audit mode: cases where the embedding matcher's independent top-1
-- disagrees with an existing source='LLM' taxonomy_map row. Never consumed automatically — a queue for
-- human/LLM QA review (feeds the Targeted QA Fix scenario in docs/headless-runbook.md).

CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.taxonomy_match_audit_flags` (
  product_id            STRING    NOT NULL,
  platform              STRING    NOT NULL,
  country               STRING    NOT NULL,
  current_taxonomy_id   STRING    NOT NULL,  -- what product_taxonomy_map currently says
  suggested_taxonomy_id STRING    NOT NULL,  -- the embedding matcher's disagreeing top-1
  distance              FLOAT64   NOT NULL,
  flagged_at            TIMESTAMP NOT NULL
)
CLUSTER BY platform, country, product_id
OPTIONS (
  description = "Flag-only audit output: embedding-match disagreements with existing LLM taxonomy mappings. Never written to product_taxonomy_map. See docs/superpowers/specs/2026-07-17-embedding-nn-match-design.md."
);
```

- [ ] **Step 2: Create the tables**

Run each:
```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 < sql/schema/product_taxonomy_embeddings.sql
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 < sql/schema/universe_sku_embeddings.sql
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 < sql/schema/taxonomy_match_audit_flags.sql
```

- [ ] **Step 3: Verify all three exist with the right columns**

```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=pretty \
  "SELECT table_name, column_name, data_type FROM \`sincere-hearth-273704.magpie_reference.INFORMATION_SCHEMA.COLUMNS\` WHERE table_name IN ('product_taxonomy_embeddings', 'universe_sku_embeddings', 'taxonomy_match_audit_flags') ORDER BY table_name, ordinal_position"
```

Expected: 4 columns for `product_taxonomy_embeddings`, 6 for `universe_sku_embeddings`, 7 for
`taxonomy_match_audit_flags`, matching Step 1 exactly.

- [ ] **Step 4: Commit**

```bash
git add sql/schema/product_taxonomy_embeddings.sql sql/schema/universe_sku_embeddings.sql sql/schema/taxonomy_match_audit_flags.sql
git commit -m "Add BigQuery tables for embedding-match: two embedding stores + audit-flag queue"
```

---

### Task 2: Build and smoke-test the Hetzner embedding worker

**Files:**
- Create: `script/embedding_worker.py`
- Create: `script/embedding_worker_requirements.txt`

**Interfaces:**
- Consumes: `magpie_reference.product_taxonomy` (`taxonomy_id`, `canonical_name`), `magpie.marketshare_universe_niq`
  (`product_id`, `ecommerce_platform`, `country`, `sku_name`, `master_table`, `month`) — read-only.
- Produces: rows in `magpie_reference.product_taxonomy_embeddings` and `magpie_reference.universe_sku_embeddings`
  (schemas from Task 1). Task 3/4/5 depend on these tables being populated before their queries return anything.
  CLI interface later tasks rely on: `python3 script/embedding_worker.py [--master-table TABLE] [--limit N]`.

- [ ] **Step 1: Write the requirements file**

```
# script/embedding_worker_requirements.txt
google-cloud-bigquery>=3.11
sentence-transformers>=2.7
```

- [ ] **Step 2: Write the worker script**

```python
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
        SELECT DISTINCT u.product_id, u.ecommerce_platform AS platform, u.country, u.sku_name
        FROM `{PROJECT}.magpie.marketshare_universe_niq` u
        LEFT JOIN `{PROJECT}.magpie_reference.universe_sku_embeddings` ue
          ON ue.product_id = u.product_id AND ue.platform = u.ecommerce_platform AND ue.country = u.country
        WHERE u.month = (SELECT MAX(month) FROM `{PROJECT}.magpie.marketshare_universe_niq`)
          AND ue.product_id IS NULL
          AND u.sku_name IS NOT NULL
        {scope_clause}
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
```

- [ ] **Step 3: Install dependencies on the Hetzner VM**

```bash
pip install -r script/embedding_worker_requirements.txt
```

Expected: installs `google-cloud-bigquery`, `sentence-transformers`, and `torch` (CPU build) as a transitive
dependency — no GPU present on this VM (AMD Ryzen 7 7700, 8-core, 128GB RAM), which is fine; the model is small
enough (560M params) for CPU inference to not be a bottleneck at this data volume.

- [ ] **Step 4: Authenticate to BigQuery from the Hetzner VM**

Ensure a service-account credential with BigQuery Data Editor on `magpie_reference` and BigQuery Data Viewer on
`magpie` is available, and export it:

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service_account.json
```

(Same pattern as `CLAUDE.md`'s `CREDS_FILE` convention, but this credential lives on the Hetzner VM, not the Mac
environment `CLAUDE.md` otherwise describes.)

- [ ] **Step 5: Smoke-test with a small real run**

```bash
python3 script/embedding_worker.py --master-table shopee_th_toothpaste --limit 5
```

Expected output: `Embedded 5 product_taxonomy rows` and `Embedded 5 marketshare_universe_niq rows` (or fewer, if
fewer than 5 rows are eligible — that's fine, just confirm it's not 0 for both).

- [ ] **Step 6: Verify the smoke-test rows landed correctly**

```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=pretty \
  "SELECT COUNT(*) AS n, ARRAY_LENGTH(ANY_VALUE(embedding)) AS dims, ANY_VALUE(model_version) AS model \
   FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy_embeddings\`"
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=pretty \
  "SELECT COUNT(*) AS n, ARRAY_LENGTH(ANY_VALUE(embedding)) AS dims, ANY_VALUE(model_version) AS model \
   FROM \`sincere-hearth-273704.magpie_reference.universe_sku_embeddings\`"
```

Expected: `n` matches Step 5's output, `dims = 1024`, `model = 'intfloat/multilingual-e5-large'` for both.

- [ ] **Step 7: Set up the recurring cron job**

```bash
crontab -e
# Add this line (adjust the repo path to wherever this repo is cloned on the Hetzner VM):
0 * * * * cd /path/to/product-taxonomy-extraction && GOOGLE_APPLICATION_CREDENTIALS=/path/to/service_account.json /usr/bin/python3 script/embedding_worker.py >> /var/log/embedding_worker.log 2>&1
```

This runs a full, unscoped sweep (`--master-table` omitted) hourly — it only ever embeds rows not already
present in the two embedding tables, so re-running it costs nothing extra on already-embedded rows.

- [ ] **Step 8: Commit**

```bash
git add script/embedding_worker.py script/embedding_worker_requirements.txt
git commit -m "Add self-hosted embedding worker for taxonomy/universe sku_name text"
```

---

### Task 3: Write and dry-run the auto-match query

**Files:**
- Create: `sql/queries/embedding_match_auto.sql`

**Interfaces:**
- Consumes: `magpie_reference.product_taxonomy_embeddings`, `magpie_reference.universe_sku_embeddings` (Task 2),
  `magpie_reference.parse_size` (already live), `magpie.marketshare_universe_niq`, `magpie_reference.product_taxonomy`,
  `magpie_reference.product_taxonomy_map`.
- Produces: new `product_taxonomy_map` rows with `source = 'EMBEDDING_MATCH'`. Query parameters:
  `@table` (STRING), `@auto_match_max_distance` (FLOAT64), `@meta_agent` (STRING) — Task 5 determines the real
  value for `@auto_match_max_distance`; Task 6 passes it at invocation time.

- [ ] **Step 1: Write the query**

```sql
-- sql/queries/embedding_match_auto.sql
-- Auto-match: for a given master_table's currently-unmapped products, find a confident brand+size-filtered
-- nearest-neighbor match against the existing taxonomy and write it directly — skipping Tier 5 (LLM) for
-- that product. Never touches an already-mapped product (m.taxonomy_id IS NULL guard).
-- Params: @table STRING, @auto_match_max_distance FLOAT64, @meta_agent STRING

INSERT INTO `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
  (product_id, master_table, platform, country, taxonomy_id, source, confidence, meta_agent, mapped_at)
SELECT
  u.product_id, u.master_table, u.ecommerce_platform, u.country,
  pt.taxonomy_id, 'EMBEDDING_MATCH', FORMAT('%.2f', 1 - dist), @meta_agent, CURRENT_TIMESTAMP()
FROM `sincere-hearth-273704.magpie.marketshare_universe_niq` u
JOIN `sincere-hearth-273704.magpie_reference.universe_sku_embeddings` ue
  ON ue.product_id = u.product_id AND ue.platform = u.ecommerce_platform AND ue.country = u.country
LEFT JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
  ON m.product_id = u.product_id AND m.platform = u.ecommerce_platform AND m.country = u.country
CROSS JOIN UNNEST([`sincere-hearth-273704.magpie_reference.parse_size`(u.sku_name)]) AS parsed
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt
  ON pt.brand_id = u.brand_id
  AND (parsed.size_text IS NULL OR pt.size = parsed.size_text)
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_embeddings` pte
  ON pte.taxonomy_id = pt.taxonomy_id
CROSS JOIN UNNEST([ML.DISTANCE(ue.embedding, pte.embedding, 'COSINE')]) AS dist
WHERE u.brand_confidence IN ('HIGH', 'MEDIUM')
  AND u.brand_id NOT IN ('BRD-UNDEFINED', 'BRD-UNBRANDED')
  AND u.master_table = @table
  AND u.month = (SELECT MAX(month) FROM `sincere-hearth-273704.magpie.marketshare_universe_niq`)
  AND m.taxonomy_id IS NULL
QUALIFY ROW_NUMBER() OVER (PARTITION BY u.product_id, u.ecommerce_platform, u.country ORDER BY dist ASC) = 1
  AND dist <= @auto_match_max_distance;
```

- [ ] **Step 2: Dry-run against a real table with placeholder threshold values**

```bash
bq query --dry_run --use_legacy_sql=false --project_id=sincere-hearth-273704 \
  --parameter=table:STRING:shopee_th_toothpaste \
  --parameter=auto_match_max_distance:FLOAT64:0.15 \
  --parameter=meta_agent:STRING:CLAUDE_CODE \
  < sql/queries/embedding_match_auto.sql
```

Expected: "Query successfully validated. This query will process X bytes." (not a syntax error) — confirms the
query is structurally valid even though `universe_sku_embeddings`/`product_taxonomy_embeddings` may still be
sparsely populated at this point (Task 2 only smoke-tested 5 rows so far; a full worker sweep happens in Task 5).

- [ ] **Step 3: Commit**

```bash
git add sql/queries/embedding_match_auto.sql
git commit -m "Add embedding auto-match query"
```

---

### Task 4: Write and dry-run the audit-flag query

**Files:**
- Create: `sql/queries/embedding_match_audit.sql`

**Interfaces:**
- Consumes: same tables as Task 3, plus reads (not writes) existing `source = 'LLM'` rows in
  `product_taxonomy_map`.
- Produces: rows in `taxonomy_match_audit_flags` (Task 1) — never writes to `product_taxonomy_map`. Params:
  `@table` (STRING), `@audit_flag_max_distance` (FLOAT64).

- [ ] **Step 1: Write the query**

The candidate ranking must happen *before* filtering for disagreement — ranking only among already-disagreeing
candidates would flag a runner-up as "the match" even when the true nearest neighbor actually agrees with the
current mapping. The inner subquery computes the real top-1 per product first; the outer `WHERE` then checks
disagreement on that result.

```sql
-- sql/queries/embedding_match_audit.sql
-- Audit: for a given master_table's already-LLM-mapped products, find each product's true top-1 brand+size-
-- filtered nearest neighbor, then flag (never auto-fix) any case where that top-1 disagrees with the existing
-- mapping. Params: @table STRING, @audit_flag_max_distance FLOAT64

INSERT INTO `sincere-hearth-273704.magpie_reference.taxonomy_match_audit_flags`
  (product_id, platform, country, current_taxonomy_id, suggested_taxonomy_id, distance, flagged_at)
SELECT product_id, platform, country, current_taxonomy_id, suggested_taxonomy_id, distance, CURRENT_TIMESTAMP()
FROM (
  SELECT
    u.product_id, u.ecommerce_platform AS platform, u.country,
    m.taxonomy_id AS current_taxonomy_id, pt.taxonomy_id AS suggested_taxonomy_id, dist AS distance
  FROM `sincere-hearth-273704.magpie.marketshare_universe_niq` u
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
    ON m.product_id = u.product_id AND m.platform = u.ecommerce_platform AND m.country = u.country
  JOIN `sincere-hearth-273704.magpie_reference.universe_sku_embeddings` ue
    ON ue.product_id = u.product_id AND ue.platform = u.ecommerce_platform AND ue.country = u.country
  CROSS JOIN UNNEST([`sincere-hearth-273704.magpie_reference.parse_size`(u.sku_name)]) AS parsed
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt
    ON pt.brand_id = u.brand_id
    AND (parsed.size_text IS NULL OR pt.size = parsed.size_text)
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_embeddings` pte
    ON pte.taxonomy_id = pt.taxonomy_id
  CROSS JOIN UNNEST([ML.DISTANCE(ue.embedding, pte.embedding, 'COSINE')]) AS dist
  WHERE u.brand_confidence IN ('HIGH', 'MEDIUM')
    AND u.brand_id NOT IN ('BRD-UNDEFINED', 'BRD-UNBRANDED')
    AND u.master_table = @table
    AND u.month = (SELECT MAX(month) FROM `sincere-hearth-273704.magpie.marketshare_universe_niq`)
    AND m.source = 'LLM'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY u.product_id, u.ecommerce_platform, u.country ORDER BY dist ASC) = 1
)
WHERE suggested_taxonomy_id != current_taxonomy_id
  AND distance <= @audit_flag_max_distance;
```

- [ ] **Step 2: Dry-run**

```bash
bq query --dry_run --use_legacy_sql=false --project_id=sincere-hearth-273704 \
  --parameter=table:STRING:shopee_th_toothpaste \
  --parameter=audit_flag_max_distance:FLOAT64:0.20 \
  < sql/queries/embedding_match_audit.sql
```

Expected: "Query successfully validated."

- [ ] **Step 3: Commit**

```bash
git add sql/queries/embedding_match_audit.sql
git commit -m "Add embedding audit-flag query"
```

---

### Task 5: Run the `th_toothpaste` pilot and determine the two thresholds

**Files:**
- Create: `sql/queries/pilot_validate_th_toothpaste.sql`
- Modify: this plan file (append findings to the Appendix at the bottom)

**Interfaces:**
- Consumes: Task 2's worker, Task 1's tables.
- Produces: the real `AUTO_MATCH_MAX_DISTANCE` and `AUDIT_FLAG_MAX_DISTANCE` values Task 6 reads from this
  plan's Appendix before wiring `script/headless_taxonomy.sh`.

- [ ] **Step 1: Run the worker against `th_toothpaste`'s full scope (no `--limit`)**

```bash
python3 script/embedding_worker.py --master-table shopee_th_toothpaste
```

This embeds every not-yet-embedded `product_taxonomy` row (cross-category — the worker has no category scope
for the taxonomy side by design) and every not-yet-embedded `shopee_th_toothpaste` row in
`marketshare_universe_niq`'s latest month partition. Expected: a real, nonzero count for both — the exact
numbers depend on what Task 2's smoke test already embedded.

- [ ] **Step 2: Write the precision-measurement query**

```sql
-- sql/queries/pilot_validate_th_toothpaste.sql
-- Read-only. For every shopee_th_toothpaste product already correctly mapped by an LLM session, find its
-- brand+size-filtered embedding top-1 and compare to the known-correct taxonomy_id. Since this ground truth
-- is already right, any mismatch here is a real false positive — this measures both auto-match precision and
-- audit-mode false-positive rate at once, across a range of candidate thresholds.

WITH candidates AS (
  SELECT
    m.product_id, m.platform, m.country, m.taxonomy_id AS actual_taxonomy_id,
    pt.taxonomy_id AS candidate_taxonomy_id, dist
  FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
  JOIN `sincere-hearth-273704.magpie.marketshare_universe_niq` u
    ON u.product_id = m.product_id AND u.ecommerce_platform = m.platform AND u.country = m.country
    AND u.month = (SELECT MAX(month) FROM `sincere-hearth-273704.magpie.marketshare_universe_niq`)
  JOIN `sincere-hearth-273704.magpie_reference.universe_sku_embeddings` ue
    ON ue.product_id = m.product_id AND ue.platform = m.platform AND ue.country = m.country
  CROSS JOIN UNNEST([`sincere-hearth-273704.magpie_reference.parse_size`(u.sku_name)]) AS parsed
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt
    ON pt.brand_id = u.brand_id
    AND (parsed.size_text IS NULL OR pt.size = parsed.size_text)
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_embeddings` pte
    ON pte.taxonomy_id = pt.taxonomy_id
  CROSS JOIN UNNEST([ML.DISTANCE(ue.embedding, pte.embedding, 'COSINE')]) AS dist
  WHERE m.master_table = 'shopee_th_toothpaste'
    AND m.source = 'LLM'
    AND u.brand_confidence IN ('HIGH', 'MEDIUM')
    AND u.brand_id NOT IN ('BRD-UNDEFINED', 'BRD-UNBRANDED')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY m.product_id, m.platform, m.country ORDER BY dist ASC) = 1
)
SELECT
  threshold,
  COUNT(*) AS candidates_under_threshold,
  COUNTIF(candidate_taxonomy_id = actual_taxonomy_id) AS correct,
  SAFE_DIVIDE(COUNTIF(candidate_taxonomy_id = actual_taxonomy_id), COUNT(*)) AS precision
FROM candidates, UNNEST([0.05, 0.10, 0.15, 0.20, 0.25, 0.30]) AS threshold
WHERE dist <= threshold
GROUP BY threshold
ORDER BY threshold;
```

- [ ] **Step 3: Run it for real**

```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=pretty < sql/queries/pilot_validate_th_toothpaste.sql
```

- [ ] **Step 4: Pick the two thresholds**

- `AUTO_MATCH_MAX_DISTANCE` = the largest threshold value in the results where `precision >= 0.98`. If none
  clears 0.98, do not proceed to Task 6 with auto-match enabled — record that finding instead and treat it as a
  genuine blocker to raise, not something to route around by lowering the bar.
- `AUDIT_FLAG_MAX_DISTANCE` = a looser threshold (e.g. one step up from the auto-match value) — false positives
  here only cost a wasted QA look, not a bad write, so this can tolerate lower precision than the auto-match
  threshold.
- While reviewing results, specifically eyeball any incorrect matches for the pack_count-confusion shape flagged
  in the design doc (a single-unit product matching its bulk-pack sibling) — note whether this shows up in
  practice or not.

- [ ] **Step 5: Record findings in this plan's Appendix**

Append a filled-in version of the Appendix template at the bottom of this file with: the real row counts from
Step 1, the full precision table from Step 3, the chosen `AUTO_MATCH_MAX_DISTANCE` and `AUDIT_FLAG_MAX_DISTANCE`
values, and any pack_count-confusion observations from Step 4.

- [ ] **Step 6: Commit**

```bash
git add sql/queries/pilot_validate_th_toothpaste.sql docs/superpowers/plans/2026-07-17-embedding-nn-match.md
git commit -m "Run embedding-match pilot against th_toothpaste, record chosen thresholds"
```

---

### Task 6: Wire into `script/headless_taxonomy.sh`

**Files:**
- Modify: `script/headless_taxonomy.sh`

**Interfaces:**
- Consumes: `sql/queries/embedding_match_auto.sql` (Task 3), `AUTO_MATCH_MAX_DISTANCE` from this plan's Appendix
  (Task 5).
- Produces: nothing new for later tasks — this is the integration point, terminal for the SQL/worker side.

- [ ] **Step 1: Read this plan's Appendix (written by Task 5) for the chosen `AUTO_MATCH_MAX_DISTANCE` value**

- [ ] **Step 2: Add the pre-step before the `claude -p` call**

In `script/headless_taxonomy.sh`, insert this block between the existing `echo "==========================="`
line and the `claude -p --output-format json ...` line (substitute `<VALUE>` with the real number from Step 1 —
do not leave it as a literal placeholder in the committed script):

```bash
echo "Running embedding pre-match for ${TABLE}..."
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 \
  --parameter=table:STRING:"${TABLE}" \
  --parameter=auto_match_max_distance:FLOAT64:<VALUE> \
  --parameter=meta_agent:STRING:"CLAUDE_CODE" \
  < sql/queries/embedding_match_auto.sql \
  || echo "Embedding pre-match failed or found nothing — continuing to claude -p unfiltered."
echo "==========================="
```

- [ ] **Step 3: Add one line to the existing `claude -p` prompt's STEP 1**

Find this existing text in the prompt (STEP 1's paragraph):

```
Do not assume this is 0/0. A prior run building against this exact table with an unverified 'this category has never been touched' assumption was wrong — it had 2,255 undocumented rows. Whatever you find, record it in the category file you're about to write.
```

Append immediately after it (same paragraph):

```
If you see source='EMBEDDING_MATCH' rows, those came from an automated pre-match step that ran before this session started — do not re-extract or re-map those products; Pass 1/Pass 2 should scope to products with no existing map row at all.
```

- [ ] **Step 4: Validate the new bash block in isolation**

Don't run the full script (that triggers a real, costly `claude -p` session). Instead check the script still
parses and the new pre-step block runs standalone against a real table:

```bash
bash -n script/headless_taxonomy.sh   # syntax check only
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 \
  --parameter=table:STRING:shopee_th_toothpaste \
  --parameter=auto_match_max_distance:FLOAT64:<VALUE> \
  --parameter=meta_agent:STRING:"CLAUDE_CODE" \
  < sql/queries/embedding_match_auto.sql
```

Expected: `bash -n` exits 0 (no syntax error); the `bq query` runs without error (it may insert 0 rows if
`shopee_th_toothpaste` has no unmapped products left after Task 5's pilot run — that's fine, confirms the guard
works, not a failure).

- [ ] **Step 5: Commit**

```bash
git add script/headless_taxonomy.sh
git commit -m "Wire embedding auto-match as a pre-step in headless_taxonomy.sh, before claude -p"
```

---

### Task 7: Document the pre-mapping step

**Files:**
- Modify: `docs/llm-extraction-rules.md`

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing consumed by other tasks — documentation-only, terminal task.

- [ ] **Step 1: Add a subsection near the existing "Regex pre-pass" note in `docs/llm-extraction-rules.md` §2**

Insert after the existing "Regex pre-pass" paragraph (the one added for the size-regex-pass work):

```markdown

**Embedding pre-match (added 2026-07-17):** before `claude -p` runs in `script/headless_taxonomy.sh`, a
brand+size-filtered nearest-neighbor match against the existing taxonomy may have already mapped some products
— see `sql/queries/embedding_match_auto.sql` and
`docs/superpowers/specs/2026-07-17-embedding-nn-match-design.md`. These show up as `source='EMBEDDING_MATCH'` in
`product_taxonomy_map` — do not re-extract or re-map them. A separate audit pass
(`sql/queries/embedding_match_audit.sql`) also flags disagreements between this matcher and existing
`source='LLM'` rows into `magpie_reference.taxonomy_match_audit_flags`, as an input queue for Targeted QA Fix
runs (`docs/headless-runbook.md`) — never an automatic correction.
```

- [ ] **Step 2: Verify it renders in the right place**

```bash
grep -n "Embedding pre-match" docs/llm-extraction-rules.md
```

Expected: exactly one match, inside §2, after the existing "Regex pre-pass" paragraph.

- [ ] **Step 3: Commit**

```bash
git add docs/llm-extraction-rules.md
git commit -m "Document embedding pre-match step in llm-extraction-rules.md"
```

---

## Appendix: Task 5 pilot findings

**Status: BLOCKED.** Precision never clears the 0.98 bar at any candidate threshold — it plateaus around 0.59.
Per this plan's own Step 4 instruction, this is recorded as a genuine blocker rather than routed around by
lowering the bar. `AUTO_MATCH_MAX_DISTANCE` and `AUDIT_FLAG_MAX_DISTANCE` are **not set**. Task 6 should not wire
auto-match into `script/headless_taxonomy.sh` until this is resolved (design change, e.g. a stricter candidate
key beyond brand+size, or a different embedding input schema) and a re-run of this pilot clears 0.98 at some
threshold.

- **Worker run row counts (Task 5 Step 1):** Ran `python3 script/embedding_worker.py --master-table
  shopee_th_toothpaste` (no `--limit`) against a fresh Python 3.12 venv (`.venv-embedding/`, created via
  `python3 -m venv --without-pip` + `get-pip.py` bootstrap, since `python3.12-venv`'s `ensurepip` wasn't
  installed and no sudo was available; then `pip install -r script/embedding_worker_requirements.txt`, which
  pulled `torch==2.13.0+cpu` and `sentence-transformers==5.6.0` cleanly). Output: `Embedded 21992
  product_taxonomy rows` and `Embedded 10540 marketshare_universe_niq rows`. Post-run table totals confirmed via
  `bq`: `product_taxonomy_embeddings` = 22005 rows (100% of `product_taxonomy`'s 22005 rows — full coverage, up
  from 10 embedded by Task 2's smoke test), `universe_sku_embeddings` = 10553 rows (matches the full
  `shopee_th_toothpaste` latest-month-partition scope of 10553 distinct products).

- **Precision table (Task 5 Step 3):** Ground-truth pool: 2166 `source='LLM'` map rows for
  `shopee_th_toothpaste`, 2126 after the brand-confidence/brand-not-undefined filters, 2069 of those actually
  produced a brand+size-filtered embedding candidate (the other 57 had no matching brand+size taxonomy row or no
  embedding — a separate, smaller structural gap, not counted below). Minimum observed distance across all 2069
  rows was 0.070 — above the brief's 0.05 threshold, so that bucket is empty by construction, not a bug (verified
  directly: `COUNTIF(dist <= 0.05) = 0`).

  | threshold | candidates_under_threshold | correct | precision |
  |-----------|-----------------------------|---------|-----------|
  | 0.05      | 0                           | —       | —         |
  | 0.10      | 48                          | 29      | 0.6042    |
  | 0.15      | 1674                        | 996     | 0.5950    |
  | 0.20      | 2064                        | 1222    | 0.5921    |
  | 0.25      | 2069                        | 1223    | 0.5911    |
  | 0.30      | 2069                        | 1223    | 0.5911    |

  (Note: re-running the identical query produces `correct` counts that wobble by ±1-2 rows run-to-run, e.g. 1220
  vs 1222 at the 0.20 bucket seen across two runs. Root cause: `QUALIFY ROW_NUMBER() OVER (... ORDER BY dist
  ASC)` has no tiebreaker, so exact-tied distances resolve nondeterministically. Immaterial to the conclusion —
  precision stays in the high-50s/low-60s regardless.)

  Precision caps around 59-60% and is essentially flat across thresholds from 0.15 up — widening the threshold
  mostly adds more candidates at the same hit rate, it does not find a "sweet spot" band of high precision at any
  distance cutoff. **No threshold clears 0.98.** The single highest-precision bucket (0.10, precision 0.604) is
  both far below the bar and built on only 48 candidates — too thin to trust even if it had cleared 0.98.

  Root-cause check: of the 846-847 incorrect top-1 matches, 743 (~88%) had the *actually-correct* taxonomy_id
  present somewhere in that product's brand+size candidate pool — the embedding distance simply ranked a
  different, wrong entry closer. Only ~104 (~12%) were structural misses where the correct entry wasn't even a
  candidate. This means the dominant failure mode is a **ranking/discrimination problem inherent to the
  embedding approach as scoped** (brand+size filter, whole-name embedding), not a filter-coverage gap that a
  different SQL join could fix.

- **Chosen `AUTO_MATCH_MAX_DISTANCE`:** Not set — blocked, see above.

- **Chosen `AUDIT_FLAG_MAX_DISTANCE`:** Not set — this value is defined as "one step looser than the auto-match
  value," which is undefined when auto-match itself is blocked. Separately, even if a value were chosen, the
  implied audit-mode false-positive rate here (~40-41%) is high enough to be a real design question in its own
  right (a large fraction of `taxonomy_match_audit_flags` rows would be noise for the QA queue), not just a
  "wasted look" as the brief characterizes acceptable audit-mode cost.

- **Pack_count-confusion observations (Task 5 Step 4):** The design doc's flagged failure shape — a single-unit
  product matching its bulk-pack sibling — does show up in practice, and is a meaningful contributor, but is
  **not the dominant one**. Of 846 incorrect top-1 matches: 210 (~25%) were single-unit products (`pack_count =
  1`) matched to a bulk-pack candidate (`pack_count > 1`); 90 (~11%) were the inverse (bulk matched to single);
  338 (~40%) had the *same* `pack_count` on both sides but a different flavor/formulation/product-line variant
  (e.g. "Dentiste Ultra Sensitive 100g" vs. "Dentiste 100% Natural Toothpaste 100g" — same brand, same size, same
  pack count, different product). The remaining ~208 had mismatched-but-not-1-vs-N pack counts (e.g. 2 vs 6).
  So pack-count confusion (both directions combined) accounts for ~36% of all errors — real and worth a
  structural fix (e.g. requiring pack_count to match, not just size) — but same-brand/same-size/same-pack
  *variant* confusion is the larger single bucket, suggesting the embedding text (`canonical_name` alone) isn't
  discriminative enough between close product-line siblings even before pack count is considered.

- **SQL deviation note:** the committed `sql/queries/pilot_validate_th_toothpaste.sql` differs from this
  section's Step 2 text in one respect: the inline `AND u.month = (SELECT MAX(month) FROM ...)` inside the
  universe JOIN's `ON` clause errors on this project's live BigQuery engine (`Unsupported subquery with table in
  join predicate`). Restructured as a 1-row `latest_month` CTE cross-joined in, with the month comparison moved
  to `WHERE` — a semantics-preserving change for an inner join. All precision numbers above were produced by the
  committed (working) version of the file.

---

## Appendix update: 2026-07-18 — `sku_name_EN` fix + unambiguous-bucket carve-out (Task 5b)

**Status: STILL BLOCKED for the ambiguous bucket. Unresolved judgment call for the plan owner on the
unambiguous (candidate_count = 1) fast path — see Recommendation below.** This section does not delete or
supersede the 2026-07-17 findings above; it records what changed and re-measures against the same ground-truth
pool (2069 eligible rows), so the two sections are directly comparable.

### Motivation

The human plan owner inspected two of the original pilot's mismatches directly and found the embedding worker
was embedding `marketshare_universe_niq.sku_name` — often untranslated/mixed Thai-English/garbled text (e.g.
`"Tepthai เทพไทย ยาสีฟันสมุนไพร สูตรเข้มข้น 30/70กรัม"`) — against `product_taxonomy.canonical_name`, which is
clean English (e.g. `"Tepthai Concentrated Formula Toothpaste 70g"`). Hypothesis: this language/register
mismatch, not a fundamental embedding-quality problem, was degrading the ranking.
`master_clean_niq.shopee_th_toothpaste.sku_name_EN` (machine-translated English) is 99.99%-filled and was
proposed as the fix. Decision (verbatim): **"continue with alternative 1 combined with 2, and fix the query to
include sku_name_EN"** — alternative 1 = auto-match only when brand+size uniquely identifies one taxonomy entry
(no embedding ranking needed), alternative 2 = re-embed `sku_name_EN` instead of raw `sku_name` for the
incoming side.

### Worker change

`script/embedding_worker.py`'s `embed_universe_skus` now, when `--master-table` is given, joins
`master_clean_niq.{master_table}` (deduplicated per `product_id` via `ARRAY_AGG(sku_name_EN ORDER BY month
DESC, created_date DESC LIMIT 1)[OFFSET(0)]`, since `master_clean_niq` is the raw per-listing source table, not
deduplicated to product-month grain like `marketshare_universe_niq`) and prefers `sku_name_EN` over raw
`sku_name` per row via `COALESCE(NULLIF(en.sku_name_en, ''), universe.sku_name)`. Verified before the real run:
all 10,553 `shopee_th_toothpaste` products matched a `master_clean_niq` row 1:1 (no dropped/duplicated rows
relative to the `marketshare_universe_niq`-driven candidate list), and 100% got a non-empty `sku_name_EN` (0
fell back to raw `sku_name`). Table name is interpolated via f-string (BigQuery cannot parameterize table
identifiers) — guarded with a `^[a-zA-Z0-9_]+$` regex check on `--master-table` before interpolation, since this
is now a second injection surface beyond the existing `@master_table` query parameter use.

**Scope limitation (disclosed, not papered over):** this preference only applies when `--master-table` is
passed. An unscoped full sweep (`--master-table` omitted) has no single `master_clean_niq` table to join
against — each row in that sweep can belong to a different category's master table — so unscoped runs still
embed raw `sku_name` only, unchanged from before. The hourly cron job described in Task 2 Step 7 runs unscoped,
so this fix does **not** apply automatically to future incremental embeddings unless the cron invocation is
changed to iterate `--master-table` per category (out of scope for this task; noted here for whoever picks that
up).

### Recompute (Task 5b Step 2)

The existing 10,553 `universe_sku_embeddings` rows for `shopee_th_toothpaste` were computed from raw
`sku_name`. Deleted via a `DELETE ... WHERE EXISTS (SELECT 1 FROM marketshare_universe_niq WHERE master_table =
'shopee_th_toothpaste' AND <key match>)` (join-scoped, not a blanket truncate — `universe_sku_embeddings` has no
`master_table` column of its own by design). Verified before deleting that all 10,553 existing rows belonged to
this scope (no other `master_table` had been embedded yet), so the delete was a clean full-table clear in
practice, but done via the scoped join query as a matter of process discipline for when that stops being true.
`product_taxonomy_embeddings` (canonical-name side) was not touched, per the brief.

| step | row count |
|---|---|
| `universe_sku_embeddings` before delete | 10,553 |
| `universe_sku_embeddings` after delete | 0 |
| Smoke test (`--limit 5`) after worker fix | 5 embedded |
| Full recompute (`--master-table shopee_th_toothpaste`, no limit) | 10,548 embedded |
| `universe_sku_embeddings` after recompute | 10,553 (matches pre-delete count exactly) |

Both runs used the reused `.venv-embedding/` venv from the original Task 5 pilot (same `torch==2.13.0+cpu`,
`sentence-transformers==5.6.0`, `google-cloud-bigquery` versions) — no reinstall needed. `product_taxonomy_embeddings`
was untouched and remained at 22,005 rows (100% coverage of `product_taxonomy`'s current 22,005 rows — confirmed
unchanged before/after, and `embed_taxonomy` correctly returned 0 new rows both times since coverage was already
complete).

### Updated pilot query (`sql/queries/pilot_validate_th_toothpaste.sql`)

Edited in place (not forked) per the brief's preference. Additions beyond the 2026-07-17 version:

- A `candidate_count` dimension (via a `brand_size_pool` CTE counting distinct `taxonomy_id`s passing the
  brand+size filter, before any embedding ranking) splits every row into `unambiguous` (`candidate_count = 1`)
  or `ambiguous` (`candidate_count > 1`), via `GROUP BY GROUPING SETS ((bucket, threshold), (threshold))` so the
  per-bucket and overall rows come out of one query.
- A deterministic tiebreaker (`ORDER BY dist ASC, pt.taxonomy_id ASC` in the top-1 `QUALIFY`) — the original
  query's `correct` counts wobbled ±1-2 rows run-to-run on exact-tied distances; this pins it down.
- A sentinel threshold `2.0` (COSINE distance's theoretical max, i.e. "ungated") added to the threshold array,
  on advisor review of an earlier draft of this task: the unambiguous fast path (alternative 1) auto-matches its
  single candidate regardless of embedding distance, so measuring its precision/volume at a distance-gated
  threshold would understate it. The `2.0` row reports the true ungated precision/volume for each bucket, and
  the true ungated overall precision.
- Finer low-end threshold steps (`0.02` increments from `0.02`–`0.12`, vs. the original `0.05` increments) to
  pinpoint the ambiguous-bucket 0.98 crossover, if any — the original run's low-end buckets were too coarse to
  localize a crossover, and EN-translated text was expected to compress distances toward zero.

### Precision table (Task 5b, ground truth pool: same 2,069 eligible rows as the 2026-07-17 run)

Same ground-truth derivation as before: 2,166 `source='LLM'` map rows for `shopee_th_toothpaste` → 2,126 after
brand-confidence/brand-not-undefined filters → 2,069 that produced a brand+size-filtered candidate. Of those,
**1,871 (90.4%) are ambiguous** (candidate_count > 1) and **198 (9.6%) are unambiguous** (candidate_count = 1).

| bucket | threshold | candidates_under_threshold | correct | precision |
|---|---|---|---|---|
| overall | 0.08 | 32 | 20 | 0.6250 |
| overall | 0.10 | 207 | 77 | 0.3720 |
| overall | 0.12 | 759 | 376 | 0.4954 |
| overall | 0.15 | 1842 | 1018 | 0.5527 |
| overall | 0.20 | 2066 | 1148 | 0.5557 |
| overall | 0.25 | 2068 | 1148 | 0.5551 |
| overall | 0.30 | 2069 | 1148 | 0.5549 |
| **overall** | **2.0 (ungated)** | **2069** | **1148** | **0.5549** |
| ambiguous | 0.08 | 32 | 20 | 0.6250 |
| ambiguous | 0.10 | 203 | 73 | 0.3596 |
| ambiguous | 0.12 | 715 | 336 | 0.4699 |
| ambiguous | 0.15 | 1676 | 870 | 0.5191 |
| ambiguous | 0.20 | 1868 | 979 | 0.5241 |
| ambiguous | 0.25 | 1870 | 979 | 0.5235 |
| ambiguous | 0.30 | 1871 | 979 | 0.5232 |
| **ambiguous** | **2.0 (ungated)** | **1871** | **979** | **0.5232** |
| unambiguous | 0.10 | 4 | 4 | 1.0000 |
| unambiguous | 0.12 | 44 | 40 | 0.9091 |
| unambiguous | 0.15 | 166 | 148 | 0.8916 |
| unambiguous | 0.20 | 198 | 169 | 0.8535 |
| unambiguous | 0.25 | 198 | 169 | 0.8535 |
| unambiguous | 0.30 | 198 | 169 | 0.8535 |
| **unambiguous** | **2.0 (ungated)** | **198** | **169** | **0.8535** |

(Thresholds 0.02, 0.04, 0.06 are omitted — 0 candidates at those cutoffs; ambiguous-bucket minimum observed
distance is 0.0631, unambiguous-bucket minimum is 0.0877.)

**Headline result: the `sku_name_EN` fix did not improve raw precision-against-recorded-ground-truth — it is
essentially flat-to-slightly-worse than the original raw-`sku_name` run** (overall ungated 0.5549 here vs. the
original's flat ~0.591 plateau at thresholds ≥0.15). This was verified as a real result, not a bug: same
2,069-row ground-truth pool both times, embeddings confirmed freshly computed today with 100% `sku_name_EN`
coverage (0 fallback-to-raw), correct join keys, `product_taxonomy_embeddings` unchanged between runs. This
contradicts the motivating hypothesis taken at face value — see the qualitative spot-check below for why the
raw number alone is misleading here.

The **unambiguous bucket** (alternative 1's fast path) measures at **0.8535 ungated precision on 198 rows (9.6%
of the eligible pool)** — well above the ambiguous bucket's 0.5232, but *not* the ~100%-by-construction outcome
the brief's design intuition suggested. `candidate_count = 1` only guarantees there's nothing to rank between —
it does not guarantee the one candidate is the ground-truth answer, since the ground-truth `taxonomy_id` can
still be excluded from the brand+size pool entirely (the original pilot's ~12% "structural miss" category
applies here too).

**This 0.8535 figure is embedding-independent.** When `candidate_count = 1` there is exactly one
`product_taxonomy` row in the brand+size pool, so top-1 selection trivially returns that row regardless of
embedding distance — no vector comparison influences the outcome. This number would be identical whether
`universe_sku_embeddings` had been computed from raw `sku_name`, `sku_name_EN`, or not recomputed at all; its
ceiling is set entirely by brand+size filter coverage and recorded-ground-truth quality, not by anything the
`sku_name_EN` change touched. Reported here because it's part of the alternative-1 carve-out this task measured,
not because the fix produced it.

**Root-cause reassessment — why the fix didn't move the ambiguous bucket:** `intfloat/multilingual-e5-large` is
a multilingual model purpose-built for cross-lingual matching, so comparing Thai `sku_name` against English
`canonical_name` was likely never really a language-mismatch problem at the embedding level — that was the
motivating hypothesis, but the measured result doesn't support it. Translating to `sku_name_EN` instead
measurably introduced its own noise: the spot-check found literal translation errors that actively hurt matching
(e.g. the Thai brand name "ดอกบัวคู่" — properly "Dokbuaku" in the taxonomy — translated to the generic phrase
"Lotus Pair," discarding the brand token; "PREMIO" translated to the generic "PREMIUM"). Practical implication:
further input-text engineering is likely not the lever — the residual ambiguous-bucket precision looks like a
variant/pack-discrimination problem (same-brand-same-size-different-flavor/pack-count siblings) that no change
to either side's input text is likely to fix. This reinforces the pack-count-equality candidate-key tightening
(Recommendation #1, both here and in the original 2026-07-17 pilot) as the more promising next lever.

**A/B cleanliness:** `parse_size` still runs against raw `sku_name` in both the original and this run — only the
*embedded ranking text* changed, not candidate-pool construction — so the ~73-row swing in `correct` counts is
attributable to the embedding-text change itself, not a query-restructuring artifact, and is well outside the
±1-2 row tie-break wobble the original pilot noted.

### Qualitative spot-check (Task 5b Step 4)

Two independent samples were pulled and read row-by-row (`sku_name_EN`, actual `canonical_name`, candidate
`canonical_name`), each categorized as **(a)** candidate genuinely wrong, **(b)** candidate arguably
as-good-or-better than the recorded ground truth, or **(c)** genuinely ambiguous/unclear:

- **Sample 1 — 30 random rows from all disagreements** (dominated by the ambiguous bucket, since only 29 of 921
  total disagreements are unambiguous, so a 30-row uniform random sample was very unlikely to include any —
  and did not): **(a) 7/30 (~23%)**, **(b) 10/30 (~33%)**, **(c) 13/30 (~43%)**.
- **Sample 2 — all 29 unambiguous-bucket disagreements** (the full population, not a sample, since it's small):
  **(a) 4/29 (~14%)**, **(b) 16/29 (~55%)**, **(c) 9/29 (~31%)**.

Concrete examples:

- **(b) example (strong):** product `28826577969`, `sku_name_EN` = `"[1 piece] Colgate Total Plaque Release
  Toothpaste ... ขนาด 95 กรัม (1 ชิ้น)"` (explicitly 95g, 1 piece). Actual ground truth =
  `"Colgate Total 150g"` — **wrong size** (150g vs. the stated 95g). Candidate =
  `"Colgate Total Plaque Release Toothpaste RevivingCool 95g"` — exact size and product-line match. The
  candidate is clearly correct and the recorded ground truth is clearly wrong here.
- **(b) example (taxonomy-gap flavor):** product `10390380966`, `sku_name_EN` = `"Colgate Toothpaste MaxFresh
  Pepper Mint Ice 155g Pack of 2"`. Actual = `"Colgate Toothpaste 150g"` (wrong size, generic, no line).
  Candidate = `"Colgate MaxFresh Toothpaste 155g x2"` — matches size, product line, and pack count exactly.
- **(a) example:** product `28927991365`, `sku_name_EN` = `"[Systema] Systema Toothpaste 80 grams x 6 tubes"` —
  a generic listing naming no specific product line. Actual = `"Systema Toothpaste"` (a plausible generic
  match for a generic listing). Candidate = `"Systema Ultra Care & Protect Toothpaste"` — introduces a specific
  line not supported anywhere in the text. Here the candidate is the one overreaching.
- **(a) example (bundle-text confusion):** product `41350139292`, `sku_name_EN` = `"Veldent Extra Bright Smile
  Mouthwash 250ml & CHIC SMILE Toothpaste Veldent 100g (Free! Toothpaste Pump)"` — a bundle listing containing
  both a mouthwash and a toothpaste. Actual = `"Veldent Toothpaste 100g"` (correctly picks the toothpaste
  component's size). Candidate = `"Veldent Toothpaste 250ml"` — the `parse_size` filter apparently grabbed the
  *mouthwash's* size token (250ml) from the bundle text instead of the toothpaste's own 100g, steering the
  brand+size candidate pool wrong before ranking ever ran. A structural (filter-input) failure, not a ranking
  failure.
- **(c) example:** product `54756259132`, `sku_name_EN` = `"Colgate Toothpaste, Herbs & Salt Formula, 75 g"`.
  Actual = `"Colgate Salt Herbal Toothpaste 150g"` — matches the stated flavor family exactly but the **wrong
  size** (150g vs. 75g). Candidate = `"Colgate Toothpaste 75g"` — matches the size exactly but is generic,
  losing the "Herbs & Salt" specificity. Neither is a clean win; genuinely a toss-up.

**Recurring pattern worth flagging:** a large share of both the (a)-wrong and (b)-better cases hinge on whether
a pack-count/multiplier phrase in the source text ("Twin Pack", "4 tubes", "Buy 1 Get 1", "12 Pieces", "Set of
4") was captured correctly — sometimes the candidate captures it and the recorded ground truth doesn't (→ (b)),
sometimes the reverse (→ (a)). This echoes the original 2026-07-17 pilot's finding that ~36% of errors were
pack-count confusion, and reinforces its Recommendation #1 (tighten the candidate key to also require
`pack_count` equality, not just `size`) as a promising next lever — not attempted in this task, out of scope,
noted here for whoever picks up Task 5c.

**Interpretation:** raw precision-against-recorded-ground-truth substantially understates real-world matcher
quality here — in the unambiguous bucket, only 4/29 (~14%) of "disagreements" are unambiguous candidate errors;
the rest are either arguably-correct candidates exposing ground-truth gaps (55%) or genuinely ambiguous (31%).
This is exactly the phenomenon the human plan owner flagged from their own two manual spot-checks, now
confirmed at a larger sample size. It does not, however, change the measured number against the *recorded*
ground truth, which is what the formal 0.98 bar is defined against.

**Objective corroboration:** a follow-up query checked, for all 29 unambiguous-bucket disagreements, how many
have a recorded ground-truth `product_taxonomy.size` that literally contradicts the `parse_size`-parsed size
from the product's own `sku_name` (e.g. ground truth says `150g` but the product's own name says `95g`).
Result: **16 of 29 (55%)** — an exact match to the hand-categorized (b) count, on a purely structural criterion
rather than a judgment call. Strong, checkable evidence that most of this bucket's "errors" are recorded-
ground-truth size mistakes, not matcher failures (there is no ranking to fail in this bucket — see above).

### Threshold determination (Task 5b Step 5)

**Ambiguous bucket (candidate_count > 1):** No threshold clears 0.98. The tightest/best bucket is `dist ≤ 0.08`
at 0.6250 precision, and it rests on only 32 candidates — too thin to trust even before considering it's still
36 points short of the bar. This is the same conclusion as the original 2026-07-17 pilot (which similarly found
no threshold clearing 0.98, best case ~0.60 on a thin 48-row bucket). **`AUTO_MATCH_MAX_DISTANCE` remains
unset. The ambiguous bucket remains BLOCKED**, per the brief's explicit instruction not to lower the bar
unilaterally — this is reported as the measured number, with the ground-truth-quality confound above flagged
as context, not as grounds for a different conclusion.

**Unambiguous bucket (candidate_count = 1, alternative 1's fast path):** measured ungated precision is 0.8535
(169/198) against recorded ground truth — also short of 0.98 on the raw number. However: (1) this bucket
requires no embedding-distance threshold at all by design (alternative 1's premise is "skip ranking when
brand+size uniquely identifies one candidate"), so there is no threshold to tune here — it's a binary
apply-or-don't-apply decision on the whole bucket; and (2) the qualitative spot-check found the *majority*
(16/29, ~55%) of this bucket's disagreements have a candidate that is arguably as-good-or-better than the
recorded ground truth, versus only ~14% genuine candidate errors — a materially stronger version of the
ground-truth-quality confound than the ambiguous bucket shows. **This is the real judgment call for the
controller, not resolved here per the brief's explicit instruction**: the measured number (0.8535) does not
clear 0.98, but the qualitative composition of that gap looks meaningfully different from a "the matcher is
bad" story — it looks more like "the recorded ground truth itself has real gaps in exactly the size/pack-count
dimension this bucket depends on."

### Recommendation

1. **Do not enable auto-match for the ambiguous bucket** (candidate_count > 1) at any threshold — this
   conclusion is unchanged from 2026-07-17 and the `sku_name_EN` fix did not move it. If a future pass wants to
   revisit this, the pack-count-equality candidate-key tightening flagged above (echoing the original report's
   Recommendation #1) is the most evidence-backed next lever, not another embedding-input change.
2. **The unambiguous bucket (candidate_count = 1) is a genuine open decision for the controller**, not
   something this task resolves: 0.8535 measured precision is below the formal 0.98 bar, but ~55% of its
   measured "errors" look like ground-truth gaps rather than matcher errors on manual inspection, and the bucket
   is small (9.6% of volume) with no threshold to tune — it's an all-or-nothing carve-out. Options for the
   controller: (i) hold the line at 0.98 measured-against-recorded-ground-truth and leave this bucket to Tier 5
   (LLM) as today, consistent with the brief's "don't lower the bar unilaterally" instruction; (ii) spend
   analyst time correcting the ~16 identified likely-wrong ground-truth rows in this bucket and re-measure
   before deciding; or (iii) accept a lower empirical bar for this specific low-volume, low-risk carve-out given
   the qualitative evidence, which is the option this task was explicitly told not to pick unilaterally.
3. **Unscoped-sweep scope gap:** the `sku_name_EN` preference only applies when a worker run is `--master-table`-
   scoped. The hourly cron job (Task 2 Step 7) runs unscoped and will keep embedding raw `sku_name` for any
   category not explicitly re-run with `--master-table`. If this fix is judged worth keeping, the cron
   invocation should be changed to loop over categories with `--master-table` set (or the worker extended with
   a dynamic per-row `master_clean_niq` join) — not attempted here, out of scope for this task.

---

## Appendix update: 2026-07-18 — fix objectively-wrong ground-truth rows, re-measure unambiguous bucket (Task 5c)

**Status: DONE. Corrected unambiguous-bucket precision is 87.37% (173/198), up from 85.35% (169/198) — still
short of 0.98. Recommendation: do not enable the unambiguous-bucket auto-match carve-out.** This section does
not delete or supersede the 2026-07-18 (Task 5b) section above; it records the follow-up the human plan owner
directed after reading that section's option (ii).

### Motivation

Task 5b's qualitative spot-check found that of the unambiguous bucket's 29 disagreements against recorded
`product_taxonomy_map` ground truth, 16 had a recorded `product_taxonomy.size` that objectively contradicts the
product's own `parse_size(sku_name)` output — a purely mechanical criterion, not a judgment call. The plan
owner directed: fix those rows, then re-measure (option (ii) from Task 5b's Recommendation section).

### Re-derivation and spot-check (Task 5c Steps 1-2)

The 16-row list was re-derived from a live query (`sql/queries/task5c_unambiguous_disagreements.sql`, new
file) rather than trusted from the prior report — it reproduced the same 16/29 count, confirming the underlying
data hadn't shifted. Each of the 16 was then spot-checked by eye (brand, size, and any product-line/pack-count
claim in the correction candidate's `canonical_name`, against the product's own `sku_name`) before being
applied. **Only 4 of the 16 held up**; the other 12 were rejected:

- 5 products ("ริ้วใสเย็นสดชื่น"/Clear Cool Refreshing 90g Colgate listings) would have been repointed to
  SKU-072016 "Colgate Miracle Repair Gum Revival Toothpaste 90g x2" — a specific, different product line never
  mentioned in any of the listings, and a different pack count. It's the *only* 90g Colgate taxonomy row, which
  is exactly why it looked "unambiguous" — not because it's actually the right answer.
- 5 products (generic "Colgate 35g pack of 12" listings, no "Optic White" mention) would have been repointed to
  SKU-047025 "Colgate Optic White O2 35g" — the only 35g Colgate row, same failure pattern.
- 1 product (Sparkle, "Coffee&Tea Drinker 50g" with a buy-1-get-1 promo) would have been repointed to the only
  50g Sparkle row, "Sparkle Toothpaste 50g x3" — a specific 3-pack claim that doesn't clearly match a 2-unit
  promo. Genuinely uncertain; skipped per the brief's instruction to leave anything that doesn't clearly hold up
  alone.
- 1 product (Veldent, product_id `41350139292`) is the bundle-text case already flagged in Task 5b's qualitative
  spot-check as category (a) "candidate genuinely wrong": a mouthwash+toothpaste bundle listing where
  `parse_size` grabbed the mouthwash's 250ml token, producing a spuriously unambiguous 250ml candidate for what
  is actually, correctly, a 100g toothpaste. The currently recorded mapping is right; left untouched.

**This is the most important finding of Task 5c:** of the candidates that passed the purely mechanical
"ground truth size is wrong" filter, 75% (12/16) failed a basic sanity check of whether the *correction*
candidate itself was trustworthy. All 12 share one structural cause — the taxonomy has only one SKU at that
brand+size, and that SKU happens to name a specific product line or pack count the product's own text never
claims. `candidate_count = 1` was being produced by sparse taxonomy coverage at that size, not by the product
genuinely, uniquely matching that row. This is a sharper, more concrete version of the "candidate key too
loose" finding already flagged as the top recommendation in both the 2026-07-17 and 2026-07-18 sections above.

### Fix applied (Task 5c Step 3)

4 rows in `product_taxonomy_map` (`master_table = 'shopee_th_toothpaste'`) were updated via guarded `UPDATE`
statements (`sql/queries/task5c_fix_ground_truth.sql`, new file — each `WHERE` clause matches the exact
pre-verified old `taxonomy_id`, so it's a no-op rather than a silent overwrite under a race):

| product_id | old taxonomy_id (size) | new taxonomy_id (size) |
|---|---|---|
| 10390380966 | SKU-047039 (150g) | SKU-055000 (155g, "Colgate MaxFresh Toothpaste 155g x2") |
| 21024306852 | SKU-001044 (150g) | SKU-047037 (135g, "Colgate Toothpaste 135g") |
| 47754649733 | SKU-055011 (150g) | SKU-047038 (140g, "Colgate Toothpaste 140g") |
| 54756259132 | SKU-055001 (150g) | SKU-047033 (75g, "Colgate Toothpaste 75g") |

`confidence` was bumped 0.75-0.80 → 0.95 (not 1.00, since 3 of 4 candidates lose some flavor specificity even
though the size is now correct); `source` was left as `'LLM'` (the brand identification itself wasn't wrong,
only the downstream size/candidate resolution); `meta_agent` re-asserted as `'CLAUDE_CODE'`; `llm_raw` set to a
`{"method": "task5c_ground_truth_size_fix", "reason": "..."}` JSON note per the existing convention used
elsewhere in that column; `mapped_at` set to the correction timestamp. Full before/after values in
`.superpowers/sdd/task-5c-report.md`.

### Re-measured precision (Task 5c Step 4, same `pilot_validate_th_toothpaste.sql`, unmodified)

| bucket | threshold | candidates | correct | precision |
|---|---|---|---|---|
| unambiguous | 2.0 (ungated) | 198 | **173** | **0.8737** (was 169/198 = 0.8535) |
| ambiguous | 2.0 (ungated) | 1871 | 979 | 0.5232 (unchanged, bit-for-bit) |
| overall | 2.0 (ungated) | 2069 | 1152 | 0.5568 (was 1148/2069 = 0.5549) |

Exactly +4 more `correct` in the unambiguous bucket, matching the 4 rows fixed; the ambiguous bucket is
unchanged, confirming the fix stayed scoped as intended with no side effects elsewhere.

### Reassessment of option 3 (Task 5c Step 5)

**Recommendation: still do not enable the unambiguous-bucket auto-match carve-out. Hold option (i) — leave
this bucket to Tier 5 (LLM), as today.** Two reasons:

1. 87.37% still doesn't clear 0.98 — the ground-truth fix closed only part of the gap.
2. More importantly, the spot-check process itself is evidence against the carve-out: 75% (12/16) of the
   candidates that looked like "ground truth is objectively wrong" were themselves untrustworthy, for a
   structural reason (sparse taxonomy coverage at a given brand+size manufactures false "unambiguous" matches).
   This means Task 5b's qualitative estimate that "55% of this bucket's disagreements are arguably as good or
   better than ground truth" was measuring something weaker than it looked — many of those candidates only look
   reasonable until you check whether the taxonomy actually has the right row on offer. This directly reinforces
   the standing recommendation (both here and in 2026-07-17/2026-07-18) that the real next lever is tightening
   the candidate key (`pack_count` equality, and plausibly a minimal product-line/flavor token check) — not
   further ground-truth auditing, which has now been shown to only account for a modest, bounded slice of this
   bucket's measured gap.
