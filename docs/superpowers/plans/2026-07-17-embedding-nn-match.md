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

_To be filled in by Task 5, Step 5 — following the same convention as
[`docs/superpowers/plans/2026-07-14-size-regex-pass.md`](2026-07-14-size-regex-pass.md)'s Appendix._

- Worker run row counts (Task 5 Step 1):
- Precision table (Task 5 Step 3):
- Chosen `AUTO_MATCH_MAX_DISTANCE`:
- Chosen `AUDIT_FLAG_MAX_DISTANCE`:
- Pack_count-confusion observations (Task 5 Step 4):
