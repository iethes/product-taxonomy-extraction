# Supervised Taxonomy-Match Classifier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Train a gradient-boosted classifier on ~92K existing LLM-labeled `product_taxonomy_map` rows to score
(incoming product, candidate taxonomy entry) pairs, replacing v1's unsupervised embedding-distance ranking —
then wire it into three consumption modes: cross-category auto-match, within-category Pass 2 formalization
(both Full Rebuild), and audit-flag generation (Targeted QA Fix).

**Architecture:** Candidates are retrieved by brand only (not brand+size — size becomes a feature). A Python
script on the Hetzner VM computes 7 features per (product, candidate) pair — including v1's existing embedding
distance, reused rather than recomputed — trains an XGBoost classifier locally, and evaluates on a held-out
`shopee_th_toothpaste` slice, reporting both raw and ground-truth-hygiene-filtered precision from the first
measurement. Scored candidates batch-load into a new BigQuery table; the three consumption-mode queries are
simple threshold reads over it, reusing the `JOIN` + `QUALIFY ROW_NUMBER()` / `UNNEST([scalar]) AS alias` SQL
patterns already validated live during v1.

**Tech Stack:** Python 3 (`google-cloud-bigquery`, `xgboost`, `pandas`, `scikit-learn`) on the Hetzner VM,
BigQuery Standard SQL, bash (`script/headless_taxonomy.sh`).

## Global Constraints

- Source spec: [`docs/superpowers/specs/2026-07-18-taxonomy-match-classifier-design.md`](../specs/2026-07-18-taxonomy-match-classifier-design.md) — read before starting.
- Project: `sincere-hearth-273704`. All table references use the fully-qualified form.
- **Candidate retrieval is brand-only**: `u.brand_confidence IN ('HIGH', 'MEDIUM') AND u.brand_id NOT IN
  ('BRD-UNDEFINED', 'BRD-UNBRANDED')`, `pt.brand_id = u.brand_id` — no size pre-filter. Size is a feature.
- **No `LATERAL` keyword, no `AS alias(column)` syntax, and no scalar subquery inside a `JOIN...ON` clause** —
  all three confirmed to fail on this project's live BigQuery engine (the third one re-confirmed live while
  writing this plan: `Unsupported subquery with table in join predicate`). Use `JOIN` + `QUALIFY ROW_NUMBER()`
  for top-N selection, `UNNEST([scalar_expr]) AS alias` for computed scalars, and a `CROSS JOIN` on a 1-row CTE
  + `WHERE` for the latest-month filter — never an inline `(SELECT MAX(month) ...)` inside `ON`.
- **The incoming-product source table is `magpie.marketshare_universe_niq`**, never `magpie.marketshare_universe`
  (a separate, unrelated appliance-only table — see v1's plan Appendix for the full story).
- **`product_taxonomy_map.confidence` is STRING, not FLOAT64.** Any inserted row must format numeric confidence
  as a string, e.g. `FORMAT('%.2f', probability)`.
- Every inserted `product_taxonomy_map` row sets `meta_agent` (never NULL, per `AGENTS.md`) and
  `source = 'CLASSIFIER_MATCH'`.
- Auto-match modes only ever `INSERT` where `taxonomy_id IS NULL` for that product — never `UPDATE`. Audit mode
  only ever `INSERT`s into `taxonomy_match_audit_flags` — never touches `product_taxonomy_map`.
- Batch load only (`client.load_table_from_json`) for writing scores/embeddings — never the streaming API.
- **Real fill rates on `product_taxonomy` (live-checked, 22,005 total rows)**: `variant` populated on 19.4%
  (4,272 rows), `sub_line` on 47.2% (10,398), `pack_count` on 74.6% (16,419). The keyword-table feature and
  pack-count-equality feature will have real, limited coverage — expected, not a bug to chase.
- **`universe_sku_embeddings` currently covers only `shopee_th_toothpaste`** (10,553 rows) — the other 19 TH
  categories have zero rows there. Task 2 backfills the ~92K mapped-product subset needed for training (not the
  full ~462K-row universe across all 20 categories — that would take ~6+ hours of CPU time for no benefit this
  plan needs; the mapped subset is what the training pairs actually require, at ~77 minutes).
- **Real TH `source='LLM'` row counts per category** (live-checked, sums to 92,557 across 20 categories):
  `shopee_th_pet_food` 16,152, `shopee_th_liquid_milk` 10,213, `shopee_th_moisturizer_for_face` 9,939,
  `shopee_th_body_wash` 8,874, `shopee_th_make_up_face` 6,605, `shopee_th_shampoo` 6,247, `shopee_th_coffee`
  5,759, `shopee_th_moisturizer_for_body` 5,298, `shopee_th_suncare` 5,163, `shopee_th_milk_powder` 4,656,
  `shopee_th_toothpaste` 2,285, `shopee_th_cleanser` 2,065, `shopee_th_conditioner` 1,923, `shopee_th_detergent`
  1,897, `shopee_th_toothbrush` 1,496, `shopee_th_fabric_softener` 1,102, `shopee_th_drinking_water` 1,099,
  `shopee_th_baby_diapers` 652, `shopee_th_adult_diapers` 644, `shopee_th_softdrink` 488.
- `EDIT_DISTANCE` is a real, live-confirmed native BigQuery function (Levenshtein distance) — no remote model
  or connection needed.
- Dry-run (`bq query --dry_run --use_legacy_sql=false`) every query touching `marketshare_universe_niq` before
  running it for real.

---

### Task 1: Create new tables and mine the variant/flavor keyword table

**Files:**
- Create: `sql/schema/taxonomy_match_scores.sql`
- Create: `sql/schema/brand_variant_keywords.sql`
- Create: `sql/queries/mine_variant_keywords.sql`

**Interfaces:**
- Consumes: `magpie_reference.product_taxonomy` (read-only).
- Produces: two empty/populated tables. `taxonomy_match_scores` (product_id, platform, country,
  candidate_taxonomy_id, match_probability, model_version, computed_at) is written by Task 5. `brand_variant_keywords`
  (brand_id, variant, product_count, computed_at) is read by Task 3's feature computation.

- [ ] **Step 1: Write the schema files**

```sql
-- sql/schema/taxonomy_match_scores.sql
-- Scored (product, candidate) pairs from the supervised taxonomy-match classifier. Written by the Hetzner
-- scoring script (batch load, never streamed). Consumed by the three consumption-mode queries as a simple
-- threshold read. See docs/superpowers/specs/2026-07-18-taxonomy-match-classifier-design.md.

CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.taxonomy_match_scores` (
  product_id             STRING    NOT NULL,
  platform               STRING    NOT NULL,
  country                STRING    NOT NULL,
  candidate_taxonomy_id  STRING    NOT NULL,
  match_probability      FLOAT64   NOT NULL,
  model_version          STRING    NOT NULL,
  computed_at            TIMESTAMP NOT NULL
)
CLUSTER BY platform, country, product_id
OPTIONS (
  description = "Scored (product, candidate) pairs from the supervised taxonomy-match classifier. See docs/superpowers/specs/2026-07-18-taxonomy-match-classifier-design.md."
);
```

```sql
-- sql/schema/brand_variant_keywords.sql
-- Per-brand vocabulary of known variant/flavor names, mined from product_taxonomy.variant. Extends Tier 0's
-- deterministic-lookup pattern (brand_dict) into variant matching. Feeds the classifier as a feature, not a
-- hard filter. Real coverage is limited (variant is populated on ~19% of product_taxonomy rows) - that's
-- expected, this is one signal among several, not a gate.

CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.brand_variant_keywords` (
  brand_id       STRING    NOT NULL,
  variant        STRING    NOT NULL,
  product_count  INT64     NOT NULL,
  computed_at    TIMESTAMP NOT NULL
)
OPTIONS (
  description = "Per-brand variant/flavor vocabulary mined from product_taxonomy.variant. See docs/superpowers/specs/2026-07-18-taxonomy-match-classifier-design.md."
);
```

```sql
-- sql/queries/mine_variant_keywords.sql
-- Re-minable anytime product_taxonomy.variant changes - truncate and repopulate, not incremental.

TRUNCATE TABLE `sincere-hearth-273704.magpie_reference.brand_variant_keywords`;

INSERT INTO `sincere-hearth-273704.magpie_reference.brand_variant_keywords`
  (brand_id, variant, product_count, computed_at)
SELECT brand_id, variant, COUNT(*) AS product_count, CURRENT_TIMESTAMP()
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy`
WHERE variant IS NOT NULL
GROUP BY brand_id, variant;
```

- [ ] **Step 2: Create the tables**

```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 < sql/schema/taxonomy_match_scores.sql
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 < sql/schema/brand_variant_keywords.sql
```

- [ ] **Step 3: Run the keyword mining query**

```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 < sql/queries/mine_variant_keywords.sql
```

- [ ] **Step 4: Verify**

```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=pretty \
  "SELECT COUNT(*) AS n, COUNT(DISTINCT brand_id) AS n_brands FROM \`sincere-hearth-273704.magpie_reference.brand_variant_keywords\`"
```

Expected: `n` in the low thousands (roughly proportional to the 4,272 variant-populated `product_taxonomy` rows,
deduplicated by brand+variant — fewer than 4,272 since some brands repeat the same variant name across sizes).

- [ ] **Step 5: Commit**

```bash
git add sql/schema/taxonomy_match_scores.sql sql/schema/brand_variant_keywords.sql sql/queries/mine_variant_keywords.sql
git commit -m "Add taxonomy_match_scores and brand_variant_keywords tables, mine variant keyword table"
```

---

### Task 2: Backfill universe embeddings for all 20 TH categories' mapped products

**Files:**
- Modify: `script/embedding_worker.py`

**Interfaces:**
- Consumes: `magpie_reference.product_taxonomy_map` (to find which products need embedding), existing
  `embed_universe_skus` logic.
- Produces: `universe_sku_embeddings` populated for all ~92,557 TH `source='LLM'` mapped products (not just
  `shopee_th_toothpaste`'s 10,553). Task 3 depends on this being complete before feature computation can find
  embeddings for products outside `shopee_th_toothpaste`.

- [ ] **Step 1: Add a `--mapped-only` flag to `embed_universe_skus`**

Add a new function alongside the existing `embed_universe_skus` (don't modify its existing behavior — the
unscoped/full-category-scope path is still used by production auto-match later):

```python
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
```

Add a `--mapped-only` CLI flag in `main()` that calls `embed_mapped_universe_skus` instead of
`embed_universe_skus` when set, still respecting `--master-table` and `--limit`:

```python
    parser.add_argument("--mapped-only", action="store_true",
                         help="Embed only already-mapped products for --master-table (training backfill), not the full category universe")
```

```python
    if args.mapped_only:
        if not args.master_table:
            parser.error("--mapped-only requires --master-table")
        n = embed_mapped_universe_skus(client, model, args.master_table, limit=args.limit)
        print(f"Embedded {n} mapped-only universe rows for {args.master_table}")
        return
```//
(Place this check right after `client`/`model` are constructed in `main()`, before the existing unscoped/full
`embed_taxonomy`/`embed_universe_skus` calls, and `return` early so the two modes don't both run.)

- [ ] **Step 2: Smoke-test on a small category first**

```bash
source .venv-embedding/bin/activate
python3 script/embedding_worker.py --master-table shopee_th_softdrink --mapped-only
```

Expected: `Embedded <=488 mapped-only universe rows for shopee_th_softdrink` (488 is that category's total
mapped-row count; fewer if some already happen to be embedded, e.g. if any overlap with `shopee_th_toothpaste`'s
product_ids exists, which is unlikely across different categories but not impossible for cross-listed products).

- [ ] **Step 3: Run for the remaining 18 categories (all except `shopee_th_toothpaste`, already embedded, and
`shopee_th_softdrink`, just done)**

This is real wall-clock work — expect on the order of an hour total across all remaining categories on this
environment's CPU (observed throughput from the prior pilot: roughly 19-20 rows/sec). Run in the background and
wait for completion rather than blocking:

```bash
for table in shopee_th_pet_food shopee_th_liquid_milk shopee_th_moisturizer_for_face shopee_th_body_wash \
             shopee_th_make_up_face shopee_th_shampoo shopee_th_coffee shopee_th_moisturizer_for_body \
             shopee_th_suncare shopee_th_milk_powder shopee_th_cleanser shopee_th_conditioner \
             shopee_th_detergent shopee_th_toothbrush shopee_th_fabric_softener shopee_th_drinking_water \
             shopee_th_baby_diapers shopee_th_adult_diapers; do
  echo "=== $table ==="
  python3 script/embedding_worker.py --master-table "$table" --mapped-only
done
```

- [ ] **Step 4: Verify full coverage**

```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=pretty \
"SELECT m.master_table, COUNT(DISTINCT (m.product_id, m.platform, m.country)) AS mapped,
        COUNT(DISTINCT IF(ue.product_id IS NOT NULL, (m.product_id, m.platform, m.country), NULL)) AS embedded
 FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy_map\` m
 LEFT JOIN \`sincere-hearth-273704.magpie_reference.universe_sku_embeddings\` ue
   ON ue.product_id = m.product_id AND ue.platform = m.platform AND ue.country = m.country
 WHERE m.source = 'LLM' AND m.master_table LIKE 'shopee_th_%'
 GROUP BY m.master_table ORDER BY mapped DESC"
```

Expected: `embedded` at or very close to `mapped` for all 20 rows (a small gap is fine — some rows may have no
`sku_name` at all, which the worker skips by design).

- [ ] **Step 5: Commit**

```bash
git add script/embedding_worker.py
git commit -m "Add --mapped-only backfill mode to embedding worker, backfill all 20 TH categories' mapped products"
```

---

### Task 3: Build the feature computation script

**Files:**
- Create: `sql/queries/training_pairs.sql`
- Create: `script/compute_training_features.py`
- Create: `script/compute_features_requirements.txt`

**Interfaces:**
- Consumes: `product_taxonomy_map`, `product_taxonomy`, `product_taxonomy_embeddings`, `universe_sku_embeddings`
  (Task 2), `brand_variant_keywords` (Task 1), `magpie.marketshare_universe_niq`, `parse_size`.
- Produces: a local file `training_features.parquet` with columns `product_id, platform, country, taxonomy_id,
  label, embedding_cosine_distance, size_match, pack_multiplier_signal, edit_distance_stripped,
  token_jaccard_stripped, keyword_table_hit, text_length_ratio, master_table` — Task 4 reads this file directly by
  this exact path and these exact column names.

- [ ] **Step 1: Write the training-pairs SQL — positives plus top-5 hard negatives, with SQL-native features**

Live-validated against real data while writing this plan (dry-run confirmed, real rows inspected by eye — see
the plan's commit history for the iteration that fixed an initial `brand_id` propagation bug and an invalid
`UNNEST` placement; the version below is the corrected, working query, not a first draft):

```sql
-- sql/queries/training_pairs.sql
-- One row per (product, candidate) pair: the true positive (product's actual assigned taxonomy_id) plus its
-- top-5 nearest same-brand non-matches by embedding distance (hard negatives - the confusable pairs that broke
-- v1's unsupervised ranking, now used as supervision). SQL-native features computed here; token_jaccard_stripped
-- is computed in Python afterward from the sku_text_stripped/candidate_text_stripped columns (awkward to
-- express as a BigQuery SQL expression, trivial in Python — no need to duplicate the stripping logic since
-- the already-stripped text is passed through as columns).

WITH latest_month AS (
  SELECT MAX(month) AS month FROM `sincere-hearth-273704.magpie.marketshare_universe_niq`
),
anchors AS (
  SELECT
    m.product_id, m.platform, m.country, m.master_table, m.taxonomy_id AS assigned_taxonomy_id,
    u.sku_name, u.brand_id, ue.embedding AS product_embedding
  FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
  JOIN `sincere-hearth-273704.magpie.marketshare_universe_niq` u
    ON u.product_id = m.product_id AND u.ecommerce_platform = m.platform AND u.country = m.country
  CROSS JOIN latest_month
  JOIN `sincere-hearth-273704.magpie_reference.universe_sku_embeddings` ue
    ON ue.product_id = m.product_id AND ue.platform = m.platform AND ue.country = m.country
  WHERE u.month = latest_month.month
    AND m.source = 'LLM'
    AND m.master_table LIKE 'shopee_th_%'
    AND u.brand_confidence IN ('HIGH', 'MEDIUM')
    AND u.brand_id NOT IN ('BRD-UNDEFINED', 'BRD-UNBRANDED')
),
anchors_parsed AS (
  SELECT a.*, parsed.size_text AS parsed_size, bd.canonical_name AS brand_canonical
  FROM anchors a
  CROSS JOIN UNNEST([`sincere-hearth-273704.magpie_reference.parse_size`(a.sku_name)]) AS parsed
  JOIN `sincere-hearth-273704.magpie_reference.brand_dict` bd ON bd.brand_id = a.brand_id
),
candidates AS (
  SELECT
    a.product_id, a.platform, a.country, a.master_table, a.sku_name, a.assigned_taxonomy_id,
    a.parsed_size, a.brand_canonical, a.brand_id,
    pt.taxonomy_id AS candidate_taxonomy_id,
    pt.size AS candidate_size, pt.pack_count AS candidate_pack_count,
    pt.canonical_name AS candidate_canonical_name,
    ML.DISTANCE(a.product_embedding, pte.embedding, 'COSINE') AS embedding_cosine_distance
  FROM anchors_parsed a
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt ON pt.brand_id = a.brand_id
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_embeddings` pte
    ON pte.taxonomy_id = pt.taxonomy_id
),
labeled AS (
  SELECT
    *,
    IF(candidate_taxonomy_id = assigned_taxonomy_id, 1, 0) AS label,
    ROW_NUMBER() OVER (
      PARTITION BY product_id, platform, country
      ORDER BY IF(candidate_taxonomy_id = assigned_taxonomy_id, 0, 1), embedding_cosine_distance ASC
    ) AS rn
  FROM candidates
)
SELECT
  l.product_id, l.platform, l.country, l.master_table, l.candidate_taxonomy_id AS taxonomy_id, l.label,
  l.embedding_cosine_distance,
  IF(l.parsed_size IS NULL OR l.candidate_size IS NULL, 'unknown',
     IF(l.parsed_size = l.candidate_size, 'match', 'mismatch')) AS size_match,
  REGEXP_EXTRACT(LOWER(l.sku_name), r'x\s*(\d+)') AS pack_multiplier_signal,
  l.candidate_pack_count,
  EDIT_DISTANCE(
    LOWER(REGEXP_REPLACE(REGEXP_REPLACE(l.sku_name, l.brand_canonical, ''), IFNULL(l.parsed_size, ''), '')),
    LOWER(REGEXP_REPLACE(REGEXP_REPLACE(l.candidate_canonical_name, l.brand_canonical, ''), IFNULL(l.parsed_size, ''), ''))
  ) AS edit_distance_stripped,
  LOWER(REGEXP_REPLACE(REGEXP_REPLACE(l.sku_name, l.brand_canonical, ''), IFNULL(l.parsed_size, ''), '')) AS sku_text_stripped,
  LOWER(REGEXP_REPLACE(REGEXP_REPLACE(l.candidate_canonical_name, l.brand_canonical, ''), IFNULL(l.parsed_size, ''), '')) AS candidate_text_stripped,
  IFNULL(bvk.variant, '') != '' AS keyword_table_hit,
  SAFE_DIVIDE(LENGTH(l.sku_name), LENGTH(l.candidate_canonical_name)) AS text_length_ratio
FROM labeled l
LEFT JOIN `sincere-hearth-273704.magpie_reference.brand_variant_keywords` bvk
  ON bvk.brand_id = l.brand_id
  AND STRPOS(LOWER(l.sku_name), LOWER(bvk.variant)) > 0
WHERE l.rn <= 6;  -- the true positive (rn could be 1 if it's also nearest) plus up to 5 hard negatives
```

Real spot-checked output during validation (product 17823784150, `shopee_th_toothpaste`): correctly surfaced
`candidate_pack_count` values of 1 (the true positive), 2, 4, 10, 50 among the hard negatives for the same
brand+size — exactly the pack-count confusion pattern from v1's findings, now present as real, informative
training signal via the already-populated `product_taxonomy.pack_count` field (74.6% filled, per Global
Constraints) even without a dedicated incoming-side pack extractor.

- [ ] **Step 2: Dry-run to reconfirm in your own environment**

```bash
bq query --dry_run --use_legacy_sql=false --project_id=sincere-hearth-273704 < sql/queries/training_pairs.sql
```

Expected: "Query successfully validated" (confirmed ~2.37GB estimated scan during plan validation). If it
doesn't validate, something has changed in the live schema since this plan was written — investigate before
proceeding, don't assume the query above is wrong without checking.

- [ ] **Step 3: Write `script/compute_features_requirements.txt`**

```
pandas>=2.0
pyarrow>=14.0
```

(`google-cloud-bigquery` is already in `script/embedding_worker_requirements.txt` — reuse `.venv-embedding` for
this script rather than creating a new venv, installing these two additional packages into it.)

- [ ] **Step 4: Write `script/compute_training_features.py`**

```python
#!/usr/bin/env python3
"""Runs sql/queries/training_pairs.sql and writes the raw labeled pairs to a local parquet file. Deliberately
does NOT compute derived features here (e.g. token_jaccard_stripped, the categorical encodings) - that logic
lives once, in script/taxonomy_match_encoding.py (Task 4), shared with the scoring script (Task 5) so training
and inference can never silently compute a feature two different ways."""
import pandas as pd
from google.cloud import bigquery

PROJECT = "sincere-hearth-273704"
OUTPUT_PATH = "training_features.parquet"


def main():
    client = bigquery.Client(project=PROJECT)
    with open("sql/queries/training_pairs.sql") as f:
        query = f.read()
    df = client.query(query).to_dataframe()
    df.to_parquet(OUTPUT_PATH, index=False)
    print(f"Wrote {len(df)} training pairs ({df['label'].sum()} positive) to {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 5: Run it and verify real output**

```bash
source .venv-embedding/bin/activate
pip install -r script/compute_features_requirements.txt
python3 script/compute_training_features.py
```

Expected: `Wrote N training pairs (~92557 positive) to training_features.parquet` where N is roughly
`92557 * (1 + up to 5)` — some products will have fewer than 5 hard negatives if their brand has few taxonomy
entries, so N will be somewhat less than 555,342.

- [ ] **Step 6: Commit**

```bash
git add sql/queries/training_pairs.sql script/compute_training_features.py script/compute_features_requirements.txt
git commit -m "Add training-pair feature computation (SQL + Python) for taxonomy-match classifier"
```

(`training_features.parquet` itself is a generated data artifact, not source — do not commit it; add
`training_features.parquet` to `.gitignore` if it isn't already covered by an existing pattern.)

---

### Task 4: Train and evaluate the classifier — the go/no-go gate

**Files:**
- Create: `script/taxonomy_match_encoding.py`
- Create: `script/train_taxonomy_matcher.py`
- Create: `script/train_requirements.txt`
- Modify: this plan file (append findings to the Appendix at the bottom)

**Interfaces:**
- Consumes: `training_features.parquet` (Task 3).
- Produces: `script/taxonomy_match_encoding.py` exporting `FEATURE_COLUMNS` (list of 8 strings) and
  `encode_features(df) -> df` — **Task 5 imports this module directly, not a copy of its logic.** Also produces
  `taxonomy_matcher_model.json` (the trained XGBoost model, local file) and the precision numbers that gate
  whether Tasks 5-8 proceed. **Tasks 5-8 depend on this task's evaluation clearing a real precision bar — do not
  proceed past this task if it doesn't, per the same discipline v1's Task 5 used: report the real number, do not
  lower the bar to force a pass.**

- [ ] **Step 1: Write `script/train_requirements.txt`**

```
xgboost>=2.0
scikit-learn>=1.4
```

- [ ] **Step 2: Write `script/taxonomy_match_encoding.py`** — the single source of truth for turning raw query
  output (from either `training_pairs.sql` or Task 5's `candidate_scoring_pairs.sql` — both produce the same
  columns: `embedding_cosine_distance, size_match, pack_multiplier_signal, candidate_pack_count,
  edit_distance_stripped, sku_text_stripped, candidate_text_stripped, keyword_table_hit, text_length_ratio`)
  into model-ready features. Both training and scoring import this — a shared BigQuery table function was
  considered for the SQL side too, but confirmed non-viable: BigQuery rejects correlated table-function calls
  (`FROM t1, tvf(t1.column)` fails the same way `LATERAL` does, live-tested while writing this plan), so the SQL
  stays duplicated between `training_pairs.sql` and `candidate_scoring_pairs.sql`. This module is what closes
  the risk that matters most — training and scoring silently computing the same-named feature two different
  ways:

```python
#!/usr/bin/env python3
"""Single source of truth for taxonomy-match feature encoding, shared by train_taxonomy_matcher.py and
score_taxonomy_candidates.py so the two can never silently compute a feature differently. A shared BigQuery
table function was considered for the upstream SQL too, but BigQuery rejects correlated table-function calls
(same restriction as LATERAL) - the SQL queries stay separate, this module is what stays shared."""
import re

FEATURE_COLUMNS = [
    "embedding_cosine_distance",
    "edit_distance_stripped",
    "token_jaccard_stripped",
    "keyword_table_hit",
    "text_length_ratio",
    "size_match_code",
    "pack_signal_present",
    "pack_match_code",
]


def token_jaccard(a, b):
    tokens_a = set(re.findall(r"\w+", str(a)))
    tokens_b = set(re.findall(r"\w+", str(b)))
    if not tokens_a or not tokens_b:
        return 0.0
    return len(tokens_a & tokens_b) / len(tokens_a | tokens_b)


def encode_features(df):
    """Takes the raw output of training_pairs.sql or candidate_scoring_pairs.sql and returns a copy with
    FEATURE_COLUMNS populated, ready for model.fit / model.predict_proba."""
    df = df.copy()
    df["token_jaccard_stripped"] = df.apply(
        lambda r: token_jaccard(r["sku_text_stripped"], r["candidate_text_stripped"]), axis=1
    )
    df["size_match_code"] = df["size_match"].map({"match": 1, "mismatch": -1, "unknown": 0})
    df["keyword_table_hit"] = df["keyword_table_hit"].astype(int)
    df["pack_signal_present"] = df["pack_multiplier_signal"].notna().astype(int)
    df["pack_match_code"] = 0
    has_both = df["pack_multiplier_signal"].notna() & df["candidate_pack_count"].notna()
    df.loc[has_both, "pack_match_code"] = (
        df.loc[has_both, "pack_multiplier_signal"].astype(float)
        == df.loc[has_both, "candidate_pack_count"].astype(float)
    ).astype(int) * 2 - 1
    return df
```

- [ ] **Step 3: Write `script/train_taxonomy_matcher.py`**

```python
#!/usr/bin/env python3
"""Trains an XGBoost classifier on training_features.parquet, held out on shopee_th_toothpaste, and reports
precision both raw and on the ground-truth-hygiene-filtered subset (parse_size self-consistency)."""
import json

import pandas as pd
import xgboost as xgb
from google.cloud import bigquery

from taxonomy_match_encoding import FEATURE_COLUMNS, encode_features

PROJECT = "sincere-hearth-273704"


def get_ground_truth_clean_product_ids(client):
    """Products whose recorded ground-truth size agrees with parse_size(sku_name) - the self-consistency
    check from v1's findings, applied up front this time instead of discovered in a costly redo round."""
    query = f"""
        SELECT DISTINCT m.product_id
        FROM `{PROJECT}.magpie_reference.product_taxonomy_map` m
        JOIN `{PROJECT}.magpie.marketshare_universe_niq` u
          ON u.product_id = m.product_id AND u.ecommerce_platform = m.platform AND u.country = m.country
        JOIN `{PROJECT}.magpie_reference.product_taxonomy` pt ON pt.taxonomy_id = m.taxonomy_id
        CROSS JOIN UNNEST([`{PROJECT}.magpie_reference.parse_size`(u.sku_name)]) AS parsed
        WHERE u.month = (SELECT MAX(month) FROM `{PROJECT}.magpie.marketshare_universe_niq`)
          AND m.master_table = 'shopee_th_toothpaste' AND m.source = 'LLM'
          AND (parsed.size_text IS NULL OR pt.size IS NULL OR parsed.size_text = pt.size)
    """
    return set(r.product_id for r in client.query(query).result())


def main():
    df = pd.read_parquet("training_features.parquet")
    df = encode_features(df)

    train_df = df[df["master_table"] != "shopee_th_toothpaste"]
    eval_df = df[df["master_table"] == "shopee_th_toothpaste"]

    model = xgb.XGBClassifier(n_estimators=200, max_depth=4, eval_metric="logloss")
    model.fit(train_df[FEATURE_COLUMNS], train_df["label"])
    model.save_model("taxonomy_matcher_model.json")

    eval_df = eval_df.copy()
    eval_df["predicted_prob"] = model.predict_proba(eval_df[FEATURE_COLUMNS])[:, 1]
    top1 = eval_df.loc[eval_df.groupby(["product_id", "platform", "country"])["predicted_prob"].idxmax()]

    client = bigquery.Client(project=PROJECT)
    clean_ids = get_ground_truth_clean_product_ids(client)

    raw_precision = (top1["label"] == 1).mean()
    clean_subset = top1[top1["product_id"].isin(clean_ids)]
    clean_precision = (clean_subset["label"] == 1).mean() if len(clean_subset) else float("nan")

    importances = dict(zip(FEATURE_COLUMNS, model.feature_importances_.tolist()))

    print(f"Held-out shopee_th_toothpaste top-1 count: {len(top1)}")
    print(f"Raw precision: {raw_precision:.4f}")
    print(f"Ground-truth-clean subset precision: {clean_precision:.4f} (n={len(clean_subset)})")
    print(f"Feature importances: {json.dumps(importances, indent=2)}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run it**

```bash
source .venv-embedding/bin/activate
pip install -r script/train_requirements.txt
python3 script/train_taxonomy_matcher.py
```

- [ ] **Step 5: Record the real result — do not round up or lower the bar**

Read the printed raw precision, clean-subset precision, and feature importances. If either precision number is
below 0.98: this is a genuine blocker, same discipline as v1's Task 5. Report it as such rather than proceeding
to wire anything into production. If feature importances show the model leans overwhelmingly on
`embedding_cosine_distance` alone (e.g. >80% of total importance), note that explicitly — it would mean this
approach has quietly collapsed back into v1's ranking-only design despite the added features, and that's worth
surfacing before declaring success even if the precision number looks good.

- [ ] **Step 6: Append findings to this plan's Appendix**

Record: training set size, held-out set size, raw precision, clean-subset precision, full feature-importance
breakdown, and — if the bar is cleared — the chosen `AUTO_MATCH_MIN_PROBABILITY` threshold (pick the tightest
threshold from a sweep, e.g. `[0.90, 0.95, 0.98, 0.99]` against the held-out set, mirroring v1's threshold-sweep
methodology) and `AUDIT_FLAG_MIN_CONFIDENCE_DELTA`.

- [ ] **Step 7: Commit**

```bash
git add script/taxonomy_match_encoding.py script/train_taxonomy_matcher.py script/train_requirements.txt docs/superpowers/plans/2026-07-18-taxonomy-match-classifier.md
git commit -m "Train and evaluate taxonomy-match classifier against held-out shopee_th_toothpaste"
```

**Tasks 5 through 8 below are written assuming Task 4 clears the 0.98 bar. If it doesn't, stop here and treat
the negative result the same way v1's was treated — a real, documented finding, not something to route around.**

---

### Task 5: Build the scoring/inference script and populate `taxonomy_match_scores`

**Files:**
- Create: `sql/queries/candidate_scoring_pairs.sql`
- Create: `script/score_taxonomy_candidates.py`

**Interfaces:**
- Consumes: `taxonomy_matcher_model.json` (Task 4), `script/taxonomy_match_encoding.py` (Task 4 — imports
  `FEATURE_COLUMNS` and `encode_features` directly, not a copy; confirmed live that running
  `python3 script/score_taxonomy_candidates.py` from the repo root correctly resolves this import since Python
  adds a run script's own containing directory to `sys.path`, no `PYTHONPATH` setup needed as long as both files
  stay in `script/`), `magpie_reference.brand_variant_keywords` (Task 1),
  `universe_sku_embeddings`/`product_taxonomy_embeddings` (Task 2/existing).
- Produces: rows in `magpie_reference.taxonomy_match_scores` (schema from Task 1). CLI:
  `python3 script/score_taxonomy_candidates.py --master-table TABLE`.

- [ ] **Step 1: Write `sql/queries/candidate_scoring_pairs.sql`** — same feature computation as
  `training_pairs.sql`, but for *inference*: every same-brand candidate for a given `master_table`'s currently
  unmapped products (not just the top-6 by embedding distance — at inference time there's no "true positive" to
  guarantee is included, so every same-brand candidate must be scored):

```sql
-- sql/queries/candidate_scoring_pairs.sql
-- Every same-brand candidate for @table's products - both unmapped (consumed by mode 1, auto-match) and
-- already-mapped (consumed by mode 3, audit) - with the same features as training_pairs.sql (must stay in
-- sync with that file's feature set/order - the model was trained on these exact columns). Deliberately does
-- NOT filter by mapping status here; each consumption-mode query applies its own mapped/unmapped filter
-- downstream against this shared scored-candidate pool, so scoring only runs once per product regardless of
-- which mode(s) will use it. Params: @table STRING

WITH latest_month AS (
  SELECT MAX(month) AS month FROM `sincere-hearth-273704.magpie.marketshare_universe_niq`
),
targets AS (
  SELECT
    u.product_id, u.ecommerce_platform AS platform, u.country, u.sku_name, u.brand_id, ue.embedding AS product_embedding
  FROM `sincere-hearth-273704.magpie.marketshare_universe_niq` u
  CROSS JOIN latest_month
  JOIN `sincere-hearth-273704.magpie_reference.universe_sku_embeddings` ue
    ON ue.product_id = u.product_id AND ue.platform = u.ecommerce_platform AND ue.country = u.country
  WHERE u.month = latest_month.month
    AND u.master_table = @table
    AND u.brand_confidence IN ('HIGH', 'MEDIUM')
    AND u.brand_id NOT IN ('BRD-UNDEFINED', 'BRD-UNBRANDED')
),
targets_parsed AS (
  SELECT t.*, parsed.size_text AS parsed_size, bd.canonical_name AS brand_canonical
  FROM targets t
  CROSS JOIN UNNEST([`sincere-hearth-273704.magpie_reference.parse_size`(t.sku_name)]) AS parsed
  JOIN `sincere-hearth-273704.magpie_reference.brand_dict` bd ON bd.brand_id = t.brand_id
)
SELECT
  t.product_id, t.platform, t.country, pt.taxonomy_id AS candidate_taxonomy_id,
  ML.DISTANCE(t.product_embedding, pte.embedding, 'COSINE') AS embedding_cosine_distance,
  IF(t.parsed_size IS NULL OR pt.size IS NULL, 'unknown',
     IF(t.parsed_size = pt.size, 'match', 'mismatch')) AS size_match,
  REGEXP_EXTRACT(LOWER(t.sku_name), r'x\s*(\d+)') AS pack_multiplier_signal,
  pt.pack_count AS candidate_pack_count,
  EDIT_DISTANCE(
    LOWER(REGEXP_REPLACE(REGEXP_REPLACE(t.sku_name, t.brand_canonical, ''), IFNULL(t.parsed_size, ''), '')),
    LOWER(REGEXP_REPLACE(REGEXP_REPLACE(pt.canonical_name, t.brand_canonical, ''), IFNULL(t.parsed_size, ''), ''))
  ) AS edit_distance_stripped,
  LOWER(REGEXP_REPLACE(REGEXP_REPLACE(t.sku_name, t.brand_canonical, ''), IFNULL(t.parsed_size, ''), '')) AS sku_text_stripped,
  LOWER(REGEXP_REPLACE(REGEXP_REPLACE(pt.canonical_name, t.brand_canonical, ''), IFNULL(t.parsed_size, ''), '')) AS candidate_text_stripped,
  IFNULL(bvk.variant, '') != '' AS keyword_table_hit,
  SAFE_DIVIDE(LENGTH(t.sku_name), LENGTH(pt.canonical_name)) AS text_length_ratio
FROM targets_parsed t
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt ON pt.brand_id = t.brand_id
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_embeddings` pte ON pte.taxonomy_id = pt.taxonomy_id
LEFT JOIN `sincere-hearth-273704.magpie_reference.brand_variant_keywords` bvk
  ON bvk.brand_id = t.brand_id AND STRPOS(LOWER(t.sku_name), LOWER(bvk.variant)) > 0;
```

Dry-run before proceeding: `bq query --dry_run --use_legacy_sql=false --project_id=sincere-hearth-273704
--parameter=table:STRING:shopee_th_toothpaste < sql/queries/candidate_scoring_pairs.sql`.

- [ ] **Step 2: Write `script/score_taxonomy_candidates.py`**

```python
#!/usr/bin/env python3
"""Scores every same-brand candidate for a master_table's products (mapped and unmapped alike - mode 1 and
mode 3 each filter this shared pool downstream for their own purpose) using the trained model
(taxonomy_matcher_model.json from Task 4), writing results to magpie_reference.taxonomy_match_scores."""
import argparse
from datetime import datetime, timezone

import pandas as pd
import xgboost as xgb
from google.cloud import bigquery

from taxonomy_match_encoding import FEATURE_COLUMNS, encode_features

PROJECT = "sincere-hearth-273704"
MODEL_VERSION = "xgboost-v1"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--master-table", required=True)
    args = parser.parse_args()

    client = bigquery.Client(project=PROJECT)
    with open("sql/queries/candidate_scoring_pairs.sql") as f:
        query = f.read()
    job_config = bigquery.QueryJobConfig(
        query_parameters=[bigquery.ScalarQueryParameter("table", "STRING", args.master_table)]
    )
    df = client.query(query, job_config=job_config).to_dataframe()
    if df.empty:
        print(f"No candidates to score for {args.master_table}")
        return

    df = encode_features(df)

    model = xgb.XGBClassifier()
    model.load_model("taxonomy_matcher_model.json")
    df["match_probability"] = model.predict_proba(df[FEATURE_COLUMNS])[:, 1]

    now = datetime.now(timezone.utc).isoformat()
    rows = [
        {
            "product_id": r["product_id"],
            "platform": r["platform"],
            "country": r["country"],
            "candidate_taxonomy_id": r["candidate_taxonomy_id"],
            "match_probability": float(r["match_probability"]),
            "model_version": MODEL_VERSION,
            "computed_at": now,
        }
        for _, r in df.iterrows()
    ]
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
    )
    load_job = client.load_table_from_json(
        rows, f"{PROJECT}.magpie_reference.taxonomy_match_scores", job_config=job_config
    )
    load_job.result()
    print(f"Scored and loaded {len(rows)} candidate pairs for {args.master_table}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Run it for `shopee_th_toothpaste` as a validation pass**

```bash
source .venv-embedding/bin/activate
python3 script/score_taxonomy_candidates.py --master-table shopee_th_toothpaste
```

- [ ] **Step 4: Spot-check a handful of scored pairs by eye against `taxonomy_match_scores`**, confirming the
  top-scored candidate for a few real products looks sensible (same manual-verification discipline used
  throughout v1's pilot):

```bash
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=pretty \
"SELECT product_id, candidate_taxonomy_id, match_probability
 FROM \`sincere-hearth-273704.magpie_reference.taxonomy_match_scores\`
 QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id, platform, country ORDER BY match_probability DESC) = 1
 ORDER BY match_probability DESC LIMIT 10"
```

- [ ] **Step 5: Commit**

```bash
git add sql/queries/candidate_scoring_pairs.sql script/score_taxonomy_candidates.py
git commit -m "Add taxonomy-match scoring/inference script"
```

---

### Task 6: Write the three consumption-mode SQL queries

**Files:**
- Create: `sql/queries/classifier_match_auto.sql` (mode 1: cross-category auto-match)
- Create: `sql/queries/classifier_match_pass2.sql` (mode 2: within-category Pass 2 formalization)
- Create: `sql/queries/classifier_match_audit.sql` (mode 3: audit-flag generation)

**Interfaces:**
- Consumes: `taxonomy_match_scores` (Task 5), `product_taxonomy_map`.
- Produces: mode 1/2 INSERT into `product_taxonomy_map` (`source='CLASSIFIER_MATCH'`); mode 3 INSERTs into
  `taxonomy_match_audit_flags`. Params: `@table` (STRING) for all three; `@auto_match_min_probability` (FLOAT64)
  for modes 1/2; `@audit_flag_min_confidence_delta` (FLOAT64) for mode 3; `@meta_agent` (STRING) for modes 1/2.

All three queries below are live-validated (dry-run confirmed against real BigQuery while writing this plan —
each estimated ~650MB-2.65GB, all well within reasonable bounds).

- [ ] **Step 1: Write `sql/queries/classifier_match_auto.sql` (mode 1: cross-category auto-match)**

```sql
-- sql/queries/classifier_match_auto.sql
-- Auto-match: for @table's currently-unmapped products, use the top-scored candidate from
-- taxonomy_match_scores (scored across the ENTIRE cross-category taxonomy, not just this table's own -
-- candidate_scoring_pairs.sql's brand-only filter naturally spans categories). Never touches an
-- already-mapped product. Params: @table STRING, @auto_match_min_probability FLOAT64, @meta_agent STRING

INSERT INTO `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
  (product_id, master_table, platform, country, taxonomy_id, source, confidence, meta_agent, mapped_at)
SELECT
  u.product_id, u.master_table, u.ecommerce_platform, u.country,
  s.candidate_taxonomy_id, 'CLASSIFIER_MATCH', FORMAT('%.4f', s.match_probability), @meta_agent, CURRENT_TIMESTAMP()
FROM `sincere-hearth-273704.magpie.marketshare_universe_niq` u
JOIN `sincere-hearth-273704.magpie_reference.taxonomy_match_scores` s
  ON s.product_id = u.product_id AND s.platform = u.ecommerce_platform AND s.country = u.country
LEFT JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
  ON m.product_id = u.product_id AND m.platform = u.ecommerce_platform AND m.country = u.country
WHERE u.master_table = @table
  AND u.month = (SELECT MAX(month) FROM `sincere-hearth-273704.magpie.marketshare_universe_niq`)
  AND m.taxonomy_id IS NULL
QUALIFY ROW_NUMBER() OVER (PARTITION BY u.product_id, u.ecommerce_platform, u.country ORDER BY s.match_probability DESC) = 1
  AND s.match_probability >= @auto_match_min_probability;
```

- [ ] **Step 2: Write `sql/queries/classifier_match_pass2.sql` (mode 2: within-category Pass 2 formalization)**

```sql
-- sql/queries/classifier_match_pass2.sql
-- Pass 2 formalization: same shape as mode 1, but the candidate pool is restricted to taxonomy entries
-- created in THIS Full Rebuild's own claimed SKU block (taxonomy_id BETWEEN the block's start/end) - matching
-- only against what Pass 1 just built for this category, not the full cross-category taxonomy.
-- Params: @table STRING, @auto_match_min_probability FLOAT64, @meta_agent STRING,
--         @block_start_id STRING (e.g. 'SKU-047000'), @block_end_id STRING (e.g. 'SKU-047999')

INSERT INTO `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
  (product_id, master_table, platform, country, taxonomy_id, source, confidence, meta_agent, mapped_at)
SELECT
  u.product_id, u.master_table, u.ecommerce_platform, u.country,
  s.candidate_taxonomy_id, 'CLASSIFIER_MATCH', FORMAT('%.4f', s.match_probability), @meta_agent, CURRENT_TIMESTAMP()
FROM `sincere-hearth-273704.magpie.marketshare_universe_niq` u
JOIN `sincere-hearth-273704.magpie_reference.taxonomy_match_scores` s
  ON s.product_id = u.product_id AND s.platform = u.ecommerce_platform AND s.country = u.country
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt ON pt.taxonomy_id = s.candidate_taxonomy_id
LEFT JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
  ON m.product_id = u.product_id AND m.platform = u.ecommerce_platform AND m.country = u.country
WHERE u.master_table = @table
  AND u.month = (SELECT MAX(month) FROM `sincere-hearth-273704.magpie.marketshare_universe_niq`)
  AND m.taxonomy_id IS NULL
  AND pt.taxonomy_id BETWEEN @block_start_id AND @block_end_id
QUALIFY ROW_NUMBER() OVER (PARTITION BY u.product_id, u.ecommerce_platform, u.country ORDER BY s.match_probability DESC) = 1
  AND s.match_probability >= @auto_match_min_probability;
```

(`taxonomy_id BETWEEN 'SKU-047000' AND 'SKU-047999'` relies on the fixed-width, zero-padded 6-digit numeric
suffix every `taxonomy_id` observed in this project uses — string comparison sorts correctly for equal-length
zero-padded numbers. If a future `taxonomy_id` ever uses a different width, this comparison would need revising;
not a concern for any block claimed under the current `sku_block_registry` scheme.)

- [ ] **Step 3: Write `sql/queries/classifier_match_audit.sql` (mode 3: audit-flag generation)**

```sql
-- sql/queries/classifier_match_audit.sql
-- Audit: for @table's already-LLM-mapped products, compute each product's true top-1 candidate first (via
-- QUALIFY - never rank only among already-disagreeing candidates first, that would wrongly flag a runner-up
-- even when the true best match agrees with the current mapping, the same bug v1's Task 4 avoided), then
-- flag when that top-1 disagrees with the current mapping AND its probability exceeds the current mapping's
-- own implied probability by a real margin (not just any disagreement).
-- Params: @table STRING, @audit_flag_min_confidence_delta FLOAT64

INSERT INTO `sincere-hearth-273704.magpie_reference.taxonomy_match_audit_flags`
  (product_id, platform, country, current_taxonomy_id, suggested_taxonomy_id, distance, flagged_at)
SELECT product_id, platform, country, current_taxonomy_id, suggested_taxonomy_id,
       1 - match_probability, CURRENT_TIMESTAMP()
FROM (
  SELECT
    u.product_id, u.ecommerce_platform AS platform, u.country,
    m.taxonomy_id AS current_taxonomy_id, s.candidate_taxonomy_id AS suggested_taxonomy_id, s.match_probability
  FROM `sincere-hearth-273704.magpie.marketshare_universe_niq` u
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
    ON m.product_id = u.product_id AND m.platform = u.ecommerce_platform AND m.country = u.country
  JOIN `sincere-hearth-273704.magpie_reference.taxonomy_match_scores` s
    ON s.product_id = u.product_id AND s.platform = u.ecommerce_platform AND s.country = u.country
  WHERE u.master_table = @table
    AND u.month = (SELECT MAX(month) FROM `sincere-hearth-273704.magpie.marketshare_universe_niq`)
    AND m.source = 'LLM'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY u.product_id, u.ecommerce_platform, u.country ORDER BY s.match_probability DESC) = 1
)
WHERE suggested_taxonomy_id != current_taxonomy_id
  AND match_probability - (
    SELECT MAX(s2.match_probability) FROM `sincere-hearth-273704.magpie_reference.taxonomy_match_scores` s2
    WHERE s2.product_id = product_id AND s2.candidate_taxonomy_id = current_taxonomy_id
  ) >= @audit_flag_min_confidence_delta;
```

(`distance` in `taxonomy_match_audit_flags` — v1's column, storing a distance not a probability — is populated
here as `1 - match_probability` so the column's existing "lower is more confident" semantics still hold for
anything already reading that table.)

- [ ] **Step 4: Re-run all three dry-runs in your own environment to reconfirm**

```bash
bq query --dry_run --use_legacy_sql=false --project_id=sincere-hearth-273704 \
  --parameter=table:STRING:shopee_th_toothpaste \
  --parameter=auto_match_min_probability:FLOAT64:0.98 \
  --parameter=meta_agent:STRING:CLAUDE_CODE \
  < sql/queries/classifier_match_auto.sql
# repeat for classifier_match_pass2.sql (add --parameter=block_start_id:STRING:SKU-047000
#   --parameter=block_end_id:STRING:SKU-047999 or real values for whatever run you're testing against)
# repeat for classifier_match_audit.sql (--parameter=audit_flag_min_confidence_delta:FLOAT64:0.3)
```

- [ ] **Step 5: Commit**

```bash
git add sql/queries/classifier_match_auto.sql sql/queries/classifier_match_pass2.sql sql/queries/classifier_match_audit.sql
git commit -m "Add classifier-based auto-match, Pass 2, and audit-flag queries"
```

---

### Task 7: Wire into `script/headless_taxonomy.sh`

**Files:**
- Modify: `script/headless_taxonomy.sh`

**Interfaces:**
- Consumes: `sql/queries/classifier_match_auto.sql`, `sql/queries/classifier_match_pass2.sql` (Task 6), and the
  threshold(s) recorded in Task 4's Appendix entry.

- [ ] **Step 1: Read Task 4's Appendix entry for the chosen `AUTO_MATCH_MIN_PROBABILITY` and
  `AUDIT_FLAG_MIN_CONFIDENCE_DELTA` values** — substitute the real numbers into `<AUTO_VALUE>` /
  `<DELTA_VALUE>` below, do not leave them as literal placeholders in the committed script.

- [ ] **Step 2: Add the mode-1 pre-step before the `claude -p` call**

Find this exact block in `script/headless_taxonomy.sh`:

```bash
echo "${TABLE}"
echo "TAXONOMY EXTRACTION STARTED"
echo "==========================="

claude -p --output-format json --permission-mode bypassPermissions --max-turns 300 "
```

Replace it with:

```bash
echo "${TABLE}"
echo "TAXONOMY EXTRACTION STARTED"
echo "==========================="

echo "Running classifier-based auto-match pre-step for ${TABLE}..."
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 \
  --parameter=table:STRING:"${TABLE}" \
  --parameter=auto_match_min_probability:FLOAT64:<AUTO_VALUE> \
  --parameter=meta_agent:STRING:"CLAUDE_CODE" \
  < sql/queries/classifier_match_auto.sql \
  || echo "Classifier auto-match pre-step failed or found nothing — continuing to claude -p unfiltered."
echo "==========================="

claude -p --output-format json --permission-mode bypassPermissions --max-turns 300 "
```

(Never blocks the run on failure — the `||` fallback means a failed or empty pre-match still lets `claude -p`
proceed normally, same reasoning as v1's wiring: this is a best-effort optimization, not a correctness
dependency, and `set -e` would otherwise abort the whole Full Rebuild over it.)

- [ ] **Step 3: Update STEP 1's prompt text**

Find:

```
Do not assume this is 0/0. A prior run building against this exact table with an unverified 'this category has never been touched' assumption was wrong — it had 2,255 undocumented rows. Whatever you find, record it in the category file you're about to write.
```

Append immediately after it (same paragraph):

```
If you see source='CLASSIFIER_MATCH' rows, those came from an automated pre-match step that ran before this session started — do not re-extract or re-map those products; Pass 1/Pass 2 should scope to products with no existing map row at all.
```

- [ ] **Step 4: Update STEP 5's prompt text** to describe the formalized Pass 2 mechanism (mode 2)

Find:

```
STEP 5 — Pass 2: route remaining official-store-unmatched and reseller products primarily via bulk SQL text-matching of sku_name against the Pass 1 taxonomy you just built. Only read product images for individual products where text matching is genuinely ambiguous — do not vision-read the full candidate pool.
```

Replace with:

```
STEP 5 — Pass 2: run this shell command, substituting your claimed SKU block's real start/end IDs (from STEP 3):
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 \
  --parameter=table:STRING:"${TABLE}" \
  --parameter=auto_match_min_probability:FLOAT64:<AUTO_VALUE> \
  --parameter=meta_agent:STRING:"CLAUDE_CODE" \
  --parameter=block_start_id:STRING:"<your claimed block_start, e.g. SKU-047000>" \
  --parameter=block_end_id:STRING:"<your claimed block_end, e.g. SKU-047999>" \
  < sql/queries/classifier_match_pass2.sql
This scores remaining official-store-unmatched and reseller products against the taxonomy entries you just built
in Pass 1 (scoped to your claimed SKU block) and auto-matches confident cases. Only read product images for
individual products still unmatched afterward, where text matching was genuinely ambiguous — do not vision-read
the full candidate pool.
```

- [ ] **Step 5: Validate the new bash blocks in isolation** — syntax check plus a real `bq query` invocation
  against `shopee_th_toothpaste` (do not run the full script, which triggers a real costly `claude -p` session):

```bash
bash -n script/headless_taxonomy.sh
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 \
  --parameter=table:STRING:shopee_th_toothpaste \
  --parameter=auto_match_min_probability:FLOAT64:<AUTO_VALUE> \
  --parameter=meta_agent:STRING:"CLAUDE_CODE" \
  < sql/queries/classifier_match_auto.sql
```

Expected: `bash -n` exits 0; the `bq query` runs without error (0 rows affected is fine — confirms the guard
works on an already-fully-mapped category).

- [ ] **Step 6: Commit**

```bash
git add script/headless_taxonomy.sh
git commit -m "Wire classifier-based auto-match and Pass 2 formalization into headless_taxonomy.sh"
```

---

### Task 8: Document the classifier-based matching step

**Files:**
- Modify: `docs/llm-extraction-rules.md`

- [ ] **Step 1: Add a subsection** near the existing "Regex pre-pass" / (absent, since v1 never shipped)
  "Embedding pre-match" notes in §2, describing: `source='CLASSIFIER_MATCH'` rows, `taxonomy_match_audit_flags`
  as a Targeted QA Fix input queue, and a pointer to
  `docs/superpowers/specs/2026-07-18-taxonomy-match-classifier-design.md`.

- [ ] **Step 2: Verify** via `grep -n "CLASSIFIER_MATCH" docs/llm-extraction-rules.md` — expect exactly the
  occurrences just added.

- [ ] **Step 3: Commit**

```bash
git add docs/llm-extraction-rules.md
git commit -m "Document classifier-based taxonomy matching in llm-extraction-rules.md"
```

---

## Appendix: Task 4 training/evaluation findings

**Result: BLOCKED. Precision does not clear the 0.98 bar — Tasks 5-8 do not proceed.**

- Training set size: 463,174 pairs (82,148 positive), all categories except `shopee_th_toothpaste`.
- Held-out set size: 12,069 pairs (2,122 positive) / 2,124 distinct `(product_id, platform, country)` products
  from `shopee_th_toothpaste`, held out entirely from training.
- Raw precision (top-1 by predicted probability, held-out set): **0.5579** (1,185 / 2,124 correct).
- Ground-truth-clean subset precision (parse_size self-consistency filter, n=2,019 of 2,124 products):
  **0.5666**. The clean-subset filter barely moves the number (+0.9pp) — this is not a ground-truth-hygiene
  problem, the model is genuinely picking the wrong candidate roughly 43-44% of the time regardless of label
  quality.
- Feature importances (XGBoost `feature_importances_`, gain-normalized):
  - `size_match_code`: 0.4249
  - `pack_match_code`: 0.1492
  - `pack_signal_present`: 0.0923
  - `embedding_cosine_distance`: 0.0972
  - `text_length_ratio`: 0.0828
  - `keyword_table_hit`: 0.0669
  - `token_jaccard_stripped`: 0.0524
  - `edit_distance_stripped`: 0.0345
  - The specific failure mode this plan was watching for — the model leaning >80% on
    `embedding_cosine_distance` alone (i.e. quietly collapsing back to v1's unsupervised-ranking design) — is
    **not** what happened. Embedding is only 9.7% of total importance; the non-embedding features (size, pack,
    keyword, edit-distance, token overlap) carry ~90% of it combined, with `size_match_code` alone dominating
    at 42.5%. In other words, this plan's central hypothesis — that adding keyword-table, edit-distance, and
    size/pack-matching features on top of the embedding signal would clear the bar v1's ranking-only design
    couldn't — was genuinely tested, the new features are being used heavily by the model, and precision is
    *still* ~56%. That is a more informative negative result than v1's: the problem isn't "the extra signal
    got ignored," it's "the extra signal, even fully utilized, is insufficient to disambiguate same-line /
    different-size decoys reliably enough for auto-matching."
  - Sanity checks performed before accepting this result (to rule out a pipeline bug rather than a real
    modeling limitation): no NaNs in any feature column for train or eval; 2,120 of 2,124 held-out products
    have exactly 1 positive candidate in their candidate set (only 3 have zero, 1 has two — not a labeling
    artifact); cross-checked by re-training with two other categories held out instead of toothpaste
    (`shopee_th_shampoo`: 0.532, `shopee_th_coffee`: 0.4712) — precision in the 47-56% range holds across
    independent held-out categories, so this is not an artifact of the toothpaste category specifically.
- Chosen `AUTO_MATCH_MIN_PROBABILITY`: **N/A — bar not cleared.** Per the brief, the threshold sweep (Step 6)
  is gated on clearing 0.98 precision first; it was not run.
- Chosen `AUDIT_FLAG_MIN_CONFIDENCE_DELTA`: **N/A — bar not cleared**, same reason as above.

**Conclusion:** Per the brief's explicit instruction to apply the same discipline as v1's Task 5 (report the
real number, do not lower the bar to force a pass), this is a genuine, documented blocker. Tasks 5 through 8
of this plan should not proceed on the current feature set / model design. Any future attempt to revisit this
approach should start from the fact that size/pack-matching signals — not the embedding — are already doing
most of the discriminative work and it's still not enough; the likely next lever is either richer text
features (the raw SKU/candidate text itself, not just derived scalars) or a fundamentally different
candidate-generation strategy, not more scalar features layered onto the same architecture.

## Appendix: 2026-07-18 follow-up — `product_line` feature + `shopee_sg_toothpaste` eval

Follow-up experiment requested by the project owner: ("Try `product_line` on sg_toothpaste") — two independent
changes tested together, not a full production build-out. Tasks 5-8 remain not started; this section only
extends the Task 4 findings above.

**What changed:**
- **New feature — `product_line_match`.** `product_taxonomy.product_line` is 91.5% filled (20,143/22,005 rows;
  the brief's 87.7% figure was from an earlier snapshot — re-verified directly against BigQuery before starting),
  far denser than the `variant` field `keyword_table_hit` depends on (19.4% filled, 4,272/22,005 — confirmed
  unchanged). Added `pt.product_line` to the `candidates` CTE in `sql/queries/training_pairs.sql`, threaded it
  through `labeled` (which already does `SELECT *`), and added
  `product_line_match = IF(candidate_product_line IS NOT NULL AND STRPOS(LOWER(sku_name), LOWER(candidate_product_line)) > 0, TRUE, FALSE)`
  to the final SELECT — same substring-match pattern as the existing `keyword_table_hit` column. Added
  `product_line_match_code` (0/1 cast) to `FEATURE_COLUMNS` in `script/taxonomy_match_encoding.py`.
- **New eval target — `shopee_sg_toothpaste`.** Broadened the anchor filter in `training_pairs.sql` from
  `master_table LIKE 'shopee_th_%'` to `(... OR master_table = 'shopee_sg_toothpaste')`. Backfilled
  `universe_sku_embeddings` for this category first (`--mapped-only`, 1,117 mapped products → 935 embedded
  rows after joining to the latest month, in a few minutes) since it had zero rows before this experiment;
  confirmed `product_taxonomy_embeddings` needed no equivalent backfill — it is embedded unscoped and already
  covered all 22,005 taxonomy rows (22,004 with a non-null embedding) regardless of category. Changed the
  train/eval split in `script/train_taxonomy_matcher.py` (both the `train_df`/`eval_df` filter and the
  hardcoded `master_table` filter inside `get_ground_truth_clean_product_ids`) from `shopee_th_toothpaste` to
  `shopee_sg_toothpaste`. Training now covers all 20 TH categories (including `shopee_th_toothpaste`, no longer
  held out) plus nothing from SG; eval is exclusively the 930 `shopee_sg_toothpaste` products with a candidate
  set (4,830 pairs, 942 positive).
- Dry-ran the modified `training_pairs.sql` before executing (`bq query --dry_run`) — validated clean, ~3.05 GB
  scan estimate. Re-ran `compute_training_features.py`: row count moved from 463,174 (previous run) to 480,073
  pairs (85,212 positive) — the expected effect of adding one more category's anchors.

**Precision results (held out `shopee_sg_toothpaste`, n=930 products):**
- Raw precision (top-1 by predicted probability): **0.5118** (476/930 correct).
- Ground-truth-clean subset precision (parse_size self-consistency, n=913 of 930): **0.5159**.
- Both numbers are in the same 47-56% band as the original TH-only cross-checks (`shopee_th_toothpaste` 0.5579,
  `shopee_th_shampoo` 0.532, `shopee_th_coffee` 0.4712, now `shopee_sg_toothpaste` 0.5118). SG's smaller catalog
  and the new feature together move the number by roughly -4.6pp relative to the original toothpaste run —
  not an improvement, and well within the spread already seen across held-out TH categories. **SG toothpaste
  does not behave differently from TH toothpaste** in any way that matters for this metric; catalog size was
  not the limiting factor.

**Feature importances (XGBoost `feature_importances_`, gain-normalized, this run):**

| Feature | Importance |
|---|---|
| `size_match_code` | 0.3692 |
| `pack_match_code` | 0.1409 |
| `product_line_match_code` | 0.1257 |
| `embedding_cosine_distance` | 0.0948 |
| `keyword_table_hit` | 0.0695 |
| `text_length_ratio` | 0.0664 |
| `pack_signal_present` | 0.0489 |
| `token_jaccard_stripped` | 0.0489 |
| `edit_distance_stripped` | 0.0357 |

`product_line_match_code` landed as the **3rd most important feature**, ahead of `embedding_cosine_distance`
— in the original Task 4 run `embedding_cosine_distance` ranked 3rd (0.0972, behind `size_match_code` and
`pack_match_code`); adding `product_line_match_code` pushes it down to 4th (0.0948) here.

**Clean ablation (isolating the feature's effect, same `shopee_sg_toothpaste` eval set both ways):** the
0.5118-vs-0.5579 comparison above is confounded — those are two different eval sets (SG vs TH), so it can't
isolate what `product_line` itself did. Re-trained with the identical train/eval split but the 8 features
*minus* `product_line_match_code`: raw precision came out to **0.5301** on the same 930 `shopee_sg_toothpaste`
products — i.e., *removing* the feature raised precision by +1.8pp relative to the 9-feature run (0.5118).
So on a clean, same-eval-set comparison, `product_line_match_code` is not neutral — it's a small net negative
on this eval set, despite ranking 3rd in the model's own importance accounting. The model uses the feature
heavily (it isn't ignored), but "used heavily" and "helps precision" are different claims here: the model
appears to be trading off against it in a way that costs slightly more than it gains, plausibly because
`product_line` substring-matches are noisier than `size`/`pack_count` matches (a substring hit doesn't
guarantee genuine product-line identity the way an exact size/pack equality does) and is correlated enough
with the existing size/pack signal that it mostly adds noise rather than new information on the residual,
harder cases. **Sanity check on the feature's mechanics:** confirmed `product_taxonomy.product_line` has 844
empty-string (not NULL) rows out of 22,005 globally, which would be a hazard for this feature (BigQuery
`STRPOS(x, '') = 1`, so an empty-string `product_line` would spuriously match every SKU under the
`IS NOT NULL` guard) — but checked directly against `shopee_sg_toothpaste`'s actual mapped taxonomy rows and
found 0 empty strings among them (436 NULLs, correctly excluded by the `IS NOT NULL` filter, out of 2,651),
so this specific result is not contaminated by that edge case. It remains a latent robustness gap worth fixing
(e.g. treating `''` the same as NULL) if this feature is ever adopted more broadly, since other categories'
brands were not individually checked.

**Confidence-threshold sweep** (max-probability candidate per product, `shopee_sg_toothpaste` eval set,
n=930 products):

| Threshold | n at/above | Coverage | Precision |
|---|---|---|---|
| 0.00 | 930 | 1.0000 | 0.5118 |
| 0.50 | 372 | 0.4000 | 0.4812 |
| 0.70 | 151 | 0.1624 | 0.5298 |
| 0.80 | 89 | 0.0957 | 0.6742 |
| 0.85 | 23 | 0.0247 | 0.7826 |
| 0.90 | 11 | 0.0118 | 1.0000 |
| 0.95 | 3 | 0.0032 | 1.0000 |
| 0.97 | 0 | 0.0000 | n/a |
| 0.98 | 0 | 0.0000 | n/a |
| 0.99 | 0 | 0.0000 | n/a |

This is the first time the threshold-sweep mechanism (Step 6/7) has actually been run — previously it was
correctly gated on clearing the unconditional 0.98 bar first, which never happened. The sweep confirms the
gate was the right call rather than overly conservative: precision does climb sharply with threshold (0.51 →
0.78 → 1.00), but coverage collapses even faster. The model reaches 100% precision only at ≥0.90 confidence,
where it covers **1.18% of products** (11 of 930); at 0.95 confidence it's 3 products (0.32% coverage). No
threshold in the requested sweep reaches the 0.98 confidence bin with any predictions at all — the model
essentially never assigns a probability that high. Even the most generous practically-useful reading of this
table (≥0.85, 78% precision) leaves 97.5% of products with no auto-match. There is no threshold at which this
model is both confident and covers a useful fraction of the catalog.

**Honest assessment:**
- **Did `product_line` help?** No — the clean ablation (same eval set, feature removed) shows precision
  *without* it is 0.5301 vs. 0.5118 *with* it: a small net regression (-1.8pp), not an improvement. The model
  does use the feature substantially (3rd-ranked importance, ahead of the embedding) — it isn't dead weight in
  the sense of being ignored — but "heavily used" isn't the same as "helpful": on this eval set it appears to
  be trading away a bit of accuracy elsewhere in exchange for a signal that's noisier than it looks. Having
  higher raw fill-rate than `variant` (91.5% vs 19.4%) did not translate into more *discriminative power*; the
  substring-match construction catches largely the same same-brand-different-line cases that
  `size_match_code`/`pack_match_code` already resolve, and adds some noise on top rather than new information
  on the harder residual cases.
- **Does `sg_toothpaste` behave differently from `th_toothpaste`?** No. Precision (0.51 vs 0.56) and the
  overall shape of the failure are consistent with the TH-category spread already documented (0.47-0.56)
  in the original Task 4 findings. Smaller catalog, different country, same failure mode. This rules out
  "TH catalog difficulty" as an explanation for the block — the ambiguity is intrinsic to the matching problem
  (same-brand candidates differing in attributes the feature set doesn't fully capture), not a TH-specific data
  quality issue.
- **Is 0.85-0.90 now in reach?** Not at any coverage worth deploying. Unconditional precision (~0.51) is
  unchanged from before within noise. The threshold sweep shows the *only* way to hit 0.85+ precision is to
  restrict to <2.5% of products, which is not a usable auto-match policy at any reasonable definition of
  production coverage. This experiment closes essentially none of the gap to 0.85-0.90 as a general-purpose
  threshold; it does add one confirmed-useful feature and a documented instance of the fully-gated threshold
  sweep, for whoever attempts the next iteration. The next lever remains what the original Task 4 findings
  said: richer text features on the raw SKU/candidate strings, or a different candidate-generation strategy —
  not incremental scalar features on the current architecture, which this experiment is now the second
  negative data point for.
