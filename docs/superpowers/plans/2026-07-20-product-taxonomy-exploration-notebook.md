# Product Taxonomy Exploration Notebook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `notebooks/product_taxonomy_exploration.ipynb`, a Colab notebook giving an analyst view of
`product_taxonomy` + `product_taxonomy_map` results across all extracted categories (TH+SG combined).

**Architecture:** Single notebook, five markdown-delimited sections, each with its own SQL query (as a
named `..._SQL` string constant), a `client.query(...).to_dataframe()` load cell, and one or more
`matplotlib` chart cells. Two shared dataframes (`primary_df`, `sku_df`) computed once near the top and
reused via pandas filtering across sections, to avoid re-querying BigQuery per chart. Read-only.

**Tech Stack:** BigQuery (`google-cloud-bigquery` via Colab auth), `pandas`, `matplotlib`. No new
dependencies beyond what `notebooks/taxonomy_match_exploration.ipynb` already uses.

## Global Constraints

- Project: `sincere-hearth-273704`. All table refs fully qualified.
- Colab auth pattern only (`google.colab.auth.authenticate_user()` then `bigquery.Client(project=...)`) —
  no local-credentials fallback in the committed notebook.
- `matplotlib` only for charts — no plotly/seaborn, to stay consistent with the existing notebook.
- Read-only: no DML, no writes to any table.
- No saved cell outputs in the committed `.ipynb` (matches `taxonomy_match_exploration.ipynb` — outputs are
  stripped before commit; the notebook is meant to be run fresh in Colab).
- Every SQL query in this plan has already been run against live BigQuery data during design research —
  use the exact queries given, don't re-derive them.

**Verified live-schema corrections (differ from `ARCHITECTURE.md`, which is stale in these spots — do not
"fix" the queries below to match `ARCHITECTURE.md`, the queries are correct against the real tables):**
- `product_taxonomy_map.confidence` is `STRING`, not `FLOAT` — cast with `SAFE_CAST(confidence AS FLOAT64)`.
- `product_taxonomy_map` DOES have `platform`/`country` columns (ADR-006 composite key), even though
  `ARCHITECTURE.md`'s table lists neither.
- `brand_dict` live columns are `brand_id, canonical_name, parent_brand_id, brand_level, country_scope,
  status, deprecated_at, superseded_by, created_at, updated_at` — no `scope`/`category` columns as
  `ARCHITECTURE.md` claims.
- `magpie.marketshare_universe_niq` live columns do NOT match `sql/schema/marketshare_universe_niq.sql`
  (that schema file is aspirational, same situation as `marketshare_universe.sql` documented in
  `docs/superpowers/plans/2026-07-14-size-regex-pass.md`'s appendix). Real columns used here: `product_id`,
  `master_table`, `ecommerce_platform`, `country`, `month`, `gmv_monthly`.
- `magpie_reference.universe_taxonomy_overlay` currently has rows for exactly ONE category
  (`shopee_th_suncare`, 5,174 rows) — the overlay refresh (Migration 003 pattern) has only been run once so
  far. **Do not join through the overlay for GMV coverage** — it would show data for 1 of 43 categories.
  Instead, join `product_taxonomy_map` directly to `marketshare_universe_niq` on
  `(product_id, platform=ecommerce_platform, country, master_table)`, deduped (see Task 2) — this covers all
  43 categories and matches how `docs/categories/STATUS.md`'s own "GMV Coverage" column is computed.
- `product_taxonomy_map` has 1,450 dual-mapped products (same `(product_id, master_table)` appearing more
  than once — a QA Gate G1 violation per `docs/quality-standards.md`). Any query joining
  `product_taxonomy_map` to a GMV source MUST dedup first (see Task 2's `dedup_map` CTE) or GMV coverage
  will exceed 100% for affected categories (confirmed live: `shopee_sg_facial_moisturiser` showed 111%
  coverage undeduped). The dual-mapped count itself is also surfaced as a quality signal in Task 5.
- `product_taxonomy_map.country` has 17 NULL rows (out of ~190k) — `sorted(...unique())` on that column
  throws `TypeError: '<' not supported between instances of 'float' and 'str'` unless you `.dropna()`
  first (confirmed live — every task's code that sorts/lists `country` values does this).
- `product_taxonomy` itself has at least one duplicate `taxonomy_id` primary key (`SKU-040096`, two rows
  with different `created_at` values, confirmed live: 22,005 raw rows but only 22,004 distinct
  `taxonomy_id`). `sku_df` (Task 2) MUST dedup with `QUALIFY ROW_NUMBER() ... = 1` or every section that
  uses it (composition, quality signals, growth-over-time) silently double-counts that one row.

**Reference counts as of this design session** (use to sanity-check task output, will drift over time —
don't hardcode these as assertions, just use them as the "does this look right" ballpark):
`product_taxonomy` = 22,005 raw rows / 22,004 distinct SKUs (see duplicate-PK note above);
`product_taxonomy_map` = 189,916 rows across 43 `master_table` values; dual-mapped products = 1,450;
1,276 SKUs have `NULL created_at`; `universe_taxonomy_overlay` = 5,174 rows (suncare only); latest
`marketshare_universe_niq` month = `2026-05-01`.

---

## Validation approach (read before starting)

This environment has live BigQuery access via Application Default Credentials (`bq` CLI and
`google-cloud-bigquery` both work against `sincere-hearth-273704` right now — confirmed working). There is
no Colab session available here, so the committed notebook's `google.colab.auth` cell can't be executed
directly in this environment. Each task instead validates its cells with a **throwaway local script** that:

1. Uses `.venv-embedding/bin/python3` (already has `google-cloud-bigquery`, `pandas`; `matplotlib` and
   `nbformat` were installed into it during design research — confirmed present).
2. Builds a BigQuery client via ADC instead of `google.colab.auth` — the only difference from the
   notebook's own setup cell — everything else (queries, dataframe code, chart code) is copy-identical to
   what gets written into the notebook.
3. Saves any chart to a PNG under the scratchpad directory and prints summary stats, so you can eyeball
   both.

Each task's steps write cells directly into `notebooks/product_taxonomy_exploration.ipynb` using
`nbformat` (Task 1 creates the file; later tasks load-append-save it) — there is no separate generator
script committed to the repo, the notebook file itself is the only deliverable.

Use your own scratchpad directory for the throwaway validation scripts and PNGs (do not commit them). If
you don't know your scratchpad path, create and use `/tmp/product-taxonomy-notebook-validation/`.

---

### Task 1: Notebook scaffold + BigQuery setup section

**Files:**
- Create: `notebooks/product_taxonomy_exploration.ipynb`

**Interfaces:**
- Produces: a notebook file with a title markdown cell and a "## 1. Setup" section (pip install cell, Colab
  auth cell, BigQuery client cell). Later tasks load this file, append cells, and save it back.

- [ ] **Step 1: Write the notebook-creation script**

Save as `/tmp/product-taxonomy-notebook-validation/task1_build.py`:

```python
import nbformat as nbf

nb = nbf.v4.new_notebook()
nb.metadata = {"kernelspec": {"display_name": "Python 3", "name": "python3"}}

cells = [
    nbf.v4.new_markdown_cell(
        "# Product Taxonomy Exploration — Coverage, Composition & Quality\n"
        "\n"
        "Analyst/stakeholder view of `magpie_reference.product_taxonomy` + `product_taxonomy_map` results "
        "across every extracted category (TH + SG combined). Answers: how much of the business does the "
        "taxonomy cover, what does it look like, and are there any completeness signals worth a second "
        "look.\n"
        "\n"
        "**Not a QA gate tool** — for pass/fail hard-gate checks (dual-mapped products, brand mismatches, "
        "etc.) see `script/qa_report.sh`. This notebook is descriptive/exploratory, read-only."
    ),
    nbf.v4.new_markdown_cell("## 1. Setup"),
    nbf.v4.new_code_cell("!pip install -q google-cloud-bigquery db-dtypes"),
    nbf.v4.new_code_cell(
        "from google.colab import auth\n"
        "auth.authenticate_user()\n"
        "print('Authenticated. Next cell creates the BigQuery client.')"
    ),
    nbf.v4.new_code_cell(
        'PROJECT = "sincere-hearth-273704"\n'
        "\n"
        "from google.cloud import bigquery\n"
        "client = bigquery.Client(project=PROJECT)\n"
        'print(f"BigQuery client ready for project {PROJECT}")'
    ),
]
nb["cells"] = cells

with open("notebooks/product_taxonomy_exploration.ipynb", "w") as f:
    nbf.write(nb, f)
print("wrote notebook with", len(cells), "cells")
```

- [ ] **Step 2: Run it from the repo root**

Run: `cd /home/wikan/Documents/work/product-taxonomy-extraction && .venv-embedding/bin/python3 /tmp/product-taxonomy-notebook-validation/task1_build.py`
Expected: `wrote notebook with 5 cells`

- [ ] **Step 3: Validate the notebook JSON is well-formed**

Run: `.venv-embedding/bin/python3 -c "import nbformat; nb = nbformat.read('notebooks/product_taxonomy_exploration.ipynb', as_version=4); nbformat.validate(nb); print('valid,', len(nb.cells), 'cells')"`
Expected: `valid, 5 cells`

- [ ] **Step 4: Validate the setup logic actually connects (ADC substitute for Colab auth)**

Run:
```bash
.venv-embedding/bin/python3 -c "
from google.cloud import bigquery
client = bigquery.Client(project='sincere-hearth-273704')
df = client.query('SELECT 1 AS ok').to_dataframe()
print(df)
"
```
Expected: prints a one-row dataframe with `ok = 1` (confirms ADC works the way Colab auth will in
production — the client-construction code itself is identical, only the auth cell above it differs).

- [ ] **Step 5: Commit**

```bash
git add notebooks/product_taxonomy_exploration.ipynb
git commit -m "Scaffold product taxonomy exploration notebook"
```

---

### Task 2: Shared data-loading queries (primary_df, sku_df, gmv_df)

**Files:**
- Modify: `notebooks/product_taxonomy_exploration.ipynb` (append cells)

**Interfaces:**
- Consumes: nothing beyond Task 1's `client` variable (same notebook kernel state).
- Produces three dataframes every later section reuses — exact column names:
  - `primary_df`: `product_id, master_table, country, platform, source, confidence, brand_mismatch, map_meta_agent, taxonomy_id, brand_id, brand_name, canonical_name, size, pack_count, is_multi_size, is_multi_variant, is_bundle, sku_meta_agent, created_at` — one row per mapped product.
  - `sku_df`: `taxonomy_id, brand_id, brand_name, product_line, sub_line, variant, canonical_name, size, pack_count, is_multi_size, is_multi_variant, is_bundle, meta_agent, created_at` — one row per SKU (all of `product_taxonomy`, not just currently-mapped ones).
  - `gmv_df`: `master_table, mapped_gmv, total_gmv, coverage` — one row per category, `coverage` is `mapped_gmv / total_gmv` in `[0, 1]` (already deduped, see below).

- [ ] **Step 1: Write the append script**

Save as `/tmp/product-taxonomy-notebook-validation/task2_build.py`:

```python
import nbformat as nbf

path = "notebooks/product_taxonomy_exploration.ipynb"
nb = nbf.read(path, as_version=4)

cells = [
    nbf.v4.new_markdown_cell(
        "## 2. Load shared data\n"
        "\n"
        "Three queries reused across every section below, so BigQuery is only hit once each:\n"
        "- `primary_df` — every mapped product joined to its SKU and brand (one row per product)\n"
        "- `sku_df` — every SKU entry directly from `product_taxonomy` (one row per SKU, not just mapped ones)\n"
        "- `gmv_df` — GMV coverage per category, joining the (deduped) map directly against "
        "`marketshare_universe_niq`'s latest month — NOT via `universe_taxonomy_overlay`, which only has "
        "one category's rows so far"
    ),
    nbf.v4.new_code_cell(
        'PRIMARY_SQL = """\n'
        "SELECT\n"
        "  m.product_id, m.master_table, m.country, m.platform, m.source,\n"
        "  SAFE_CAST(m.confidence AS FLOAT64) AS confidence, m.brand_mismatch, m.meta_agent AS map_meta_agent,\n"
        "  t.taxonomy_id, t.brand_id, b.canonical_name AS brand_name, t.canonical_name, t.size, t.pack_count,\n"
        "  t.is_multi_size, t.is_multi_variant, t.is_bundle, t.meta_agent AS sku_meta_agent, t.created_at\n"
        "FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m\n"
        "JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` t ON m.taxonomy_id = t.taxonomy_id\n"
        "LEFT JOIN `sincere-hearth-273704.magpie_reference.brand_dict` b ON t.brand_id = b.brand_id\n"
        '"""\n'
        "primary_df = client.query(PRIMARY_SQL).to_dataframe()\n"
        'print("primary_df:", primary_df.shape)'
    ),
    nbf.v4.new_code_cell(
        'SKU_SQL = """\n'
        "SELECT t.taxonomy_id, t.brand_id, b.canonical_name AS brand_name, t.product_line, t.sub_line,\n"
        "       t.variant, t.canonical_name, t.size, t.pack_count, t.is_multi_size, t.is_multi_variant,\n"
        "       t.is_bundle, t.meta_agent, t.created_at\n"
        "FROM `sincere-hearth-273704.magpie_reference.product_taxonomy` t\n"
        "LEFT JOIN `sincere-hearth-273704.magpie_reference.brand_dict` b ON t.brand_id = b.brand_id\n"
        "-- product_taxonomy has at least one duplicate taxonomy_id (SKU-040096, confirmed live) — dedup\n"
        "-- so every downstream section counts each SKU exactly once\n"
        "QUALIFY ROW_NUMBER() OVER (PARTITION BY t.taxonomy_id ORDER BY t.updated_at DESC) = 1\n"
        '"""\n'
        "sku_df = client.query(SKU_SQL).to_dataframe()\n"
        'print("sku_df:", sku_df.shape)'
    ),
    nbf.v4.new_code_cell(
        'GMV_SQL = """\n'
        "WITH latest AS (\n"
        "  SELECT MAX(month) AS m FROM `sincere-hearth-273704.magpie.marketshare_universe_niq`\n"
        "),\n"
        "dedup_map AS (\n"
        "  -- product_taxonomy_map has ~1,450 dual-mapped products (QA Gate G1 violation) — dedup the same\n"
        "  -- way AGENTS.md's Universe Refresh Pattern does, or GMV coverage exceeds 100% for affected categories\n"
        "  SELECT * FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map`\n"
        "  QUALIFY ROW_NUMBER() OVER (\n"
        "    PARTITION BY product_id, platform, country, master_table\n"
        "    ORDER BY CASE source WHEN 'LLM' THEN 0 ELSE 1 END, taxonomy_id\n"
        "  ) = 1\n"
        "),\n"
        "mapped AS (\n"
        "  SELECT u.master_table, SUM(u.gmv_monthly) AS mapped_gmv\n"
        "  FROM `sincere-hearth-273704.magpie.marketshare_universe_niq` u, latest\n"
        "  JOIN dedup_map m\n"
        "    ON m.product_id = u.product_id AND m.platform = u.ecommerce_platform\n"
        "    AND m.country = u.country AND m.master_table = u.master_table\n"
        "  WHERE u.month = latest.m\n"
        "  GROUP BY 1\n"
        "),\n"
        "total AS (\n"
        "  SELECT master_table, SUM(gmv_monthly) AS total_gmv\n"
        "  FROM `sincere-hearth-273704.magpie.marketshare_universe_niq`, latest\n"
        "  WHERE month = latest.m\n"
        "  GROUP BY 1\n"
        ")\n"
        "SELECT t.master_table, COALESCE(mapped.mapped_gmv, 0) AS mapped_gmv, t.total_gmv,\n"
        "       SAFE_DIVIDE(COALESCE(mapped.mapped_gmv, 0), t.total_gmv) AS coverage\n"
        "FROM total t LEFT JOIN mapped USING(master_table)\n"
        '"""\n'
        "gmv_df = client.query(GMV_SQL).to_dataframe()\n"
        'print("gmv_df:", gmv_df.shape)\n'
        'print("coverage range:", gmv_df["coverage"].min(), "-", gmv_df["coverage"].max())'
    ),
]
nb["cells"].extend(cells)

with open(path, "w") as f:
    nbf.write(nb, f)
print("notebook now has", len(nb["cells"]), "cells")
```

- [ ] **Step 2: Run it**

Run: `.venv-embedding/bin/python3 /tmp/product-taxonomy-notebook-validation/task2_build.py`
Expected: `notebook now has 9 cells`

- [ ] **Step 3: Validate the three queries against live data (ADC client)**

Run:
```bash
.venv-embedding/bin/python3 -c "
from google.cloud import bigquery
client = bigquery.Client(project='sincere-hearth-273704')

primary_df = client.query('''
SELECT
  m.product_id, m.master_table, m.country, m.platform, m.source,
  SAFE_CAST(m.confidence AS FLOAT64) AS confidence, m.brand_mismatch, m.meta_agent AS map_meta_agent,
  t.taxonomy_id, t.brand_id, b.canonical_name AS brand_name, t.canonical_name, t.size, t.pack_count,
  t.is_multi_size, t.is_multi_variant, t.is_bundle, t.meta_agent AS sku_meta_agent, t.created_at
FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy_map\` m
JOIN \`sincere-hearth-273704.magpie_reference.product_taxonomy\` t ON m.taxonomy_id = t.taxonomy_id
LEFT JOIN \`sincere-hearth-273704.magpie_reference.brand_dict\` b ON t.brand_id = b.brand_id
''').to_dataframe()
print('primary_df', primary_df.shape)
assert primary_df.shape[0] > 100000

sku_df = client.query('''
SELECT t.taxonomy_id, t.brand_id, b.canonical_name AS brand_name, t.product_line, t.sub_line,
       t.variant, t.canonical_name, t.size, t.pack_count, t.is_multi_size, t.is_multi_variant,
       t.is_bundle, t.meta_agent, t.created_at
FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy\` t
LEFT JOIN \`sincere-hearth-273704.magpie_reference.brand_dict\` b ON t.brand_id = b.brand_id
QUALIFY ROW_NUMBER() OVER (PARTITION BY t.taxonomy_id ORDER BY t.updated_at DESC) = 1
''').to_dataframe()
print('sku_df', sku_df.shape)
assert sku_df.shape[0] > 10000
assert sku_df.shape[0] == sku_df['taxonomy_id'].nunique()

gmv_df = client.query('''
WITH latest AS (SELECT MAX(month) AS m FROM \`sincere-hearth-273704.magpie.marketshare_universe_niq\`),
dedup_map AS (
  SELECT * FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy_map\`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id, platform, country, master_table
    ORDER BY CASE source WHEN \"LLM\" THEN 0 ELSE 1 END, taxonomy_id) = 1
),
mapped AS (
  SELECT u.master_table, SUM(u.gmv_monthly) AS mapped_gmv
  FROM \`sincere-hearth-273704.magpie.marketshare_universe_niq\` u, latest
  JOIN dedup_map m ON m.product_id = u.product_id AND m.platform = u.ecommerce_platform
    AND m.country = u.country AND m.master_table = u.master_table
  WHERE u.month = latest.m GROUP BY 1
),
total AS (
  SELECT master_table, SUM(gmv_monthly) AS total_gmv
  FROM \`sincere-hearth-273704.magpie.marketshare_universe_niq\`, latest WHERE month = latest.m GROUP BY 1
)
SELECT t.master_table, COALESCE(mapped.mapped_gmv, 0) AS mapped_gmv, t.total_gmv,
       SAFE_DIVIDE(COALESCE(mapped.mapped_gmv, 0), t.total_gmv) AS coverage
FROM total t LEFT JOIN mapped USING(master_table)
''').to_dataframe()
print('gmv_df', gmv_df.shape)
print('coverage min/max:', gmv_df['coverage'].min(), gmv_df['coverage'].max())
assert gmv_df['coverage'].max() <= 1.0001
"
```
Expected: three shape lines, `primary_df` > 100,000 rows, `sku_df` > 10,000 rows with row count exactly
equal to its distinct `taxonomy_id` count (confirms the QUALIFY dedup handled the live duplicate
`SKU-040096` row — `product_taxonomy` has 22,005 raw rows but only 22,004 distinct `taxonomy_id`), `gmv_df`
has ~43 rows with `coverage min/max` both within `[0, 1]` (dedup confirmed working, no assertion errors).

- [ ] **Step 4: Commit**

```bash
git add notebooks/product_taxonomy_exploration.ipynb
git commit -m "Add shared data-loading queries to taxonomy exploration notebook"
```

---

### Task 3: Section 1 — Headline dashboard

**Files:**
- Modify: `notebooks/product_taxonomy_exploration.ipynb` (append cells)

**Interfaces:**
- Consumes: `primary_df`, `sku_df`, `gmv_df` (Task 2).
- Produces: no new shared variables — this section only prints/plots.

- [ ] **Step 1: Write the append script**

Save as `/tmp/product-taxonomy-notebook-validation/task3_build.py`:

```python
import nbformat as nbf

path = "notebooks/product_taxonomy_exploration.ipynb"
nb = nbf.read(path, as_version=4)

cells = [
    nbf.v4.new_markdown_cell(
        "## 3. Headline dashboard\n"
        "\n"
        "The two numbers that matter most: how many categories are extracted, and how much of the "
        "business (by GMV) the taxonomy actually covers."
    ),
    nbf.v4.new_code_cell(
        "n_skus = sku_df['taxonomy_id'].nunique()\n"
        "n_mapped = primary_df['product_id'].nunique()\n"
        "n_categories = primary_df['master_table'].nunique()\n"
        "countries = sorted(primary_df['country'].dropna().unique())\n"
        "overall_coverage = gmv_df['mapped_gmv'].sum() / gmv_df['total_gmv'].sum()\n"
        "\n"
        "print(f'Total SKUs: {n_skus:,}')\n"
        "print(f'Total mapped products: {n_mapped:,}')\n"
        "print(f'Categories extracted: {n_categories}')\n"
        "print(f'Countries: {countries}')\n"
        "print(f'Overall GMV coverage (latest month): {overall_coverage:.1%}')"
    ),
    nbf.v4.new_code_cell(
        "import matplotlib.pyplot as plt\n"
        "\n"
        "plot_df = gmv_df.sort_values('coverage', ascending=False).copy()\n"
        "plot_df['country'] = plot_df['master_table'].str.extract(r'shopee_([a-z]{2})_')\n"
        "colors = plot_df['country'].map({'th': '#4C72B0', 'sg': '#DD8452'})\n"
        "\n"
        "fig, ax = plt.subplots(figsize=(14, 5))\n"
        "ax.bar(plot_df['master_table'], plot_df['coverage'] * 100, color=colors)\n"
        "ax.set_ylabel('GMV coverage (%)')\n"
        "ax.set_title('GMV coverage by category (latest month), TH=blue SG=orange')\n"
        "ax.tick_params(axis='x', rotation=90)\n"
        "plt.tight_layout()\n"
        "plt.show()"
    ),
    nbf.v4.new_code_cell(
        "sku_counts = primary_df.groupby('master_table')['taxonomy_id'].nunique().sort_values(ascending=False)\n"
        "\n"
        "fig, ax = plt.subplots(figsize=(14, 5))\n"
        "sku_counts.plot(kind='bar', ax=ax, color='#55A868')\n"
        "ax.set_ylabel('Distinct SKUs')\n"
        "ax.set_title('SKU count by category')\n"
        "plt.tight_layout()\n"
        "plt.show()"
    ),
]
nb["cells"].extend(cells)

with open(path, "w") as f:
    nbf.write(nb, f)
print("notebook now has", len(nb["cells"]), "cells")
```

- [ ] **Step 2: Run it**

Run: `.venv-embedding/bin/python3 /tmp/product-taxonomy-notebook-validation/task3_build.py`
Expected: `notebook now has 13 cells`

- [ ] **Step 3: Validate against live data and save chart PNGs for inspection**

Run:
```bash
mkdir -p /tmp/product-taxonomy-notebook-validation/charts
.venv-embedding/bin/python3 << 'PY'
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from google.cloud import bigquery

client = bigquery.Client(project='sincere-hearth-273704')

primary_df = client.query('''
SELECT m.product_id, m.master_table, m.country, m.platform, t.taxonomy_id
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` t ON m.taxonomy_id = t.taxonomy_id
''').to_dataframe()

sku_df = client.query('SELECT taxonomy_id FROM `sincere-hearth-273704.magpie_reference.product_taxonomy`').to_dataframe()

gmv_df = client.query('''
WITH latest AS (SELECT MAX(month) AS m FROM `sincere-hearth-273704.magpie.marketshare_universe_niq`),
dedup_map AS (
  SELECT * FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id, platform, country, master_table
    ORDER BY CASE source WHEN 'LLM' THEN 0 ELSE 1 END, taxonomy_id) = 1
),
mapped AS (
  SELECT u.master_table, SUM(u.gmv_monthly) AS mapped_gmv
  FROM `sincere-hearth-273704.magpie.marketshare_universe_niq` u, latest
  JOIN dedup_map m ON m.product_id = u.product_id AND m.platform = u.ecommerce_platform
    AND m.country = u.country AND m.master_table = u.master_table
  WHERE u.month = latest.m GROUP BY 1
),
total AS (
  SELECT master_table, SUM(gmv_monthly) AS total_gmv
  FROM `sincere-hearth-273704.magpie.marketshare_universe_niq`, latest WHERE month = latest.m GROUP BY 1
)
SELECT t.master_table, COALESCE(mapped.mapped_gmv, 0) AS mapped_gmv, t.total_gmv,
       SAFE_DIVIDE(COALESCE(mapped.mapped_gmv, 0), t.total_gmv) AS coverage
FROM total t LEFT JOIN mapped USING(master_table)
''').to_dataframe()

print('SKUs:', sku_df['taxonomy_id'].nunique(), 'mapped products:', primary_df['product_id'].nunique())
print('categories:', primary_df['master_table'].nunique(), 'countries:', sorted(primary_df['country'].dropna().unique()))
print('overall coverage:', gmv_df['mapped_gmv'].sum() / gmv_df['total_gmv'].sum())

plot_df = gmv_df.sort_values('coverage', ascending=False).copy()
plot_df['country'] = plot_df['master_table'].str.extract(r'shopee_([a-z]{2})_')
colors = plot_df['country'].map({'th': '#4C72B0', 'sg': '#DD8452'})
fig, ax = plt.subplots(figsize=(14, 5))
ax.bar(plot_df['master_table'], plot_df['coverage'] * 100, color=colors)
ax.tick_params(axis='x', rotation=90)
plt.tight_layout()
plt.savefig('/tmp/product-taxonomy-notebook-validation/charts/coverage.png')

sku_counts = primary_df.groupby('master_table')['taxonomy_id'].nunique().sort_values(ascending=False)
fig, ax = plt.subplots(figsize=(14, 5))
sku_counts.plot(kind='bar', ax=ax, color='#55A868')
plt.tight_layout()
plt.savefig('/tmp/product-taxonomy-notebook-validation/charts/sku_counts.png')
print('charts saved')
PY
```
Expected: prints SKU/product/category counts consistent with the ballparks in Global Constraints, no
exceptions, `charts saved`. Then view both PNGs with the Read tool and confirm the coverage chart shows
bars mostly under 100% (a bar over 100% means the dedup didn't take — stop and re-check the query if so)
and the SKU-count chart shows a reasonable spread across ~40+ category labels.

- [ ] **Step 4: Commit**

```bash
git add notebooks/product_taxonomy_exploration.ipynb
git commit -m "Add headline dashboard section to taxonomy exploration notebook"
```

---

### Task 4: Section 2 — Taxonomy composition

**Files:**
- Modify: `notebooks/product_taxonomy_exploration.ipynb` (append cells)

**Interfaces:**
- Consumes: `primary_df`, `sku_df` (Task 2).
- Produces: nothing shared.

- [ ] **Step 1: Write the append script**

Save as `/tmp/product-taxonomy-notebook-validation/task4_build.py`:

```python
import nbformat as nbf

path = "notebooks/product_taxonomy_exploration.ipynb"
nb = nbf.read(path, as_version=4)

cells = [
    nbf.v4.new_markdown_cell(
        "## 4. Taxonomy composition\n"
        "\n"
        "How much consolidation is happening (many listings -> one SKU), which brands dominate, and who's "
        "been doing the extraction."
    ),
    nbf.v4.new_code_cell(
        "products_per_sku = primary_df.groupby('taxonomy_id')['product_id'].nunique()\n"
        "print(f'Products per SKU — mean {products_per_sku.mean():.1f}, median {products_per_sku.median():.0f}, '\n"
        "      f'max {products_per_sku.max()}')\n"
        "\n"
        "fig, ax = plt.subplots(figsize=(8, 4))\n"
        "products_per_sku.clip(upper=20).value_counts().sort_index().plot(kind='bar', ax=ax, color='#4C72B0')\n"
        "ax.set_xlabel('Products mapped to one SKU (20+ clipped)')\n"
        "ax.set_ylabel('Number of SKUs')\n"
        "ax.set_title('Products-per-SKU distribution')\n"
        "plt.tight_layout()\n"
        "plt.show()"
    ),
    nbf.v4.new_code_cell(
        "top_brands_by_sku = sku_df.groupby('brand_name')['taxonomy_id'].nunique().sort_values(ascending=False).head(20)\n"
        "top_brands_by_products = primary_df.groupby('brand_name')['product_id'].nunique().sort_values(ascending=False).head(20)\n"
        "\n"
        "fig, axes = plt.subplots(1, 2, figsize=(14, 6))\n"
        "top_brands_by_sku.sort_values().plot(kind='barh', ax=axes[0], color='#4C72B0')\n"
        "axes[0].set_title('Top 20 brands by SKU count')\n"
        "top_brands_by_products.sort_values().plot(kind='barh', ax=axes[1], color='#DD8452')\n"
        "axes[1].set_title('Top 20 brands by mapped-product count')\n"
        "plt.tight_layout()\n"
        "plt.show()"
    ),
    nbf.v4.new_code_cell(
        "fig, axes = plt.subplots(1, 2, figsize=(12, 4))\n"
        "sku_df['meta_agent'].value_counts().plot(kind='bar', ax=axes[0], color='#55A868')\n"
        "axes[0].set_title('SKUs by meta_agent')\n"
        "primary_df['source'].value_counts().plot(kind='bar', ax=axes[1], color='#C44E52')\n"
        "axes[1].set_title('Mapped products by source')\n"
        "plt.tight_layout()\n"
        "plt.show()"
    ),
]
nb["cells"].extend(cells)

with open(path, "w") as f:
    nbf.write(nb, f)
print("notebook now has", len(nb["cells"]), "cells")
```

- [ ] **Step 2: Run it**

Run: `.venv-embedding/bin/python3 /tmp/product-taxonomy-notebook-validation/task4_build.py`
Expected: `notebook now has 17 cells`

- [ ] **Step 3: Validate against live data**

Run:
```bash
.venv-embedding/bin/python3 << 'PY'
from google.cloud import bigquery

client = bigquery.Client(project='sincere-hearth-273704')

primary_df = client.query('''
SELECT
  m.product_id, m.master_table, m.country, m.platform, m.source,
  SAFE_CAST(m.confidence AS FLOAT64) AS confidence, m.brand_mismatch, m.meta_agent AS map_meta_agent,
  t.taxonomy_id, t.brand_id, b.canonical_name AS brand_name, t.canonical_name, t.size, t.pack_count,
  t.is_multi_size, t.is_multi_variant, t.is_bundle, t.meta_agent AS sku_meta_agent, t.created_at
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` t ON m.taxonomy_id = t.taxonomy_id
LEFT JOIN `sincere-hearth-273704.magpie_reference.brand_dict` b ON t.brand_id = b.brand_id
''').to_dataframe()

sku_df = client.query('''
SELECT t.taxonomy_id, t.brand_id, b.canonical_name AS brand_name, t.product_line, t.sub_line,
       t.variant, t.canonical_name, t.size, t.pack_count, t.is_multi_size, t.is_multi_variant,
       t.is_bundle, t.meta_agent, t.created_at
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy` t
LEFT JOIN `sincere-hearth-273704.magpie_reference.brand_dict` b ON t.brand_id = b.brand_id
QUALIFY ROW_NUMBER() OVER (PARTITION BY t.taxonomy_id ORDER BY t.updated_at DESC) = 1
''').to_dataframe()

products_per_sku = primary_df.groupby('taxonomy_id')['product_id'].nunique()
print('mean', products_per_sku.mean(), 'median', products_per_sku.median(), 'max', products_per_sku.max())
assert products_per_sku.min() >= 1

top_brands_by_sku = sku_df.groupby('brand_name')['taxonomy_id'].nunique().sort_values(ascending=False).head(20)
print(top_brands_by_sku)
assert len(top_brands_by_sku) > 0

print(sku_df['meta_agent'].value_counts())
print(primary_df['source'].value_counts())
PY
```

Expected: no exceptions, `products_per_sku.mean()` is a small positive number (a handful, not thousands —
if it's huge something is wrong with the join), top brands list is non-empty and brand names look real
(not all `None`/`NaN`), `meta_agent`/`source` value counts show `CLAUDE_CODE`/`LLM` as the dominant values.

- [ ] **Step 4: Commit**

```bash
git add notebooks/product_taxonomy_exploration.ipynb
git commit -m "Add taxonomy composition section to taxonomy exploration notebook"
```

---

### Task 5: Section 3 — Quality signals (incl. canonical_name word-count check)

**Files:**
- Modify: `notebooks/product_taxonomy_exploration.ipynb` (append cells)

**Interfaces:**
- Consumes: `primary_df`, `sku_df` (Task 2).
- Produces: nothing shared.

- [ ] **Step 1: Write the append script**

Save as `/tmp/product-taxonomy-notebook-validation/task5_build.py`:

```python
import nbformat as nbf

path = "notebooks/product_taxonomy_exploration.ipynb"
nb = nbf.read(path, as_version=4)

cells = [
    nbf.v4.new_markdown_cell(
        "## 5. Quality signals\n"
        "\n"
        "Descriptive completeness checks — NOT the QA hard gates (`script/qa_report.sh` owns those). "
        "These are early-warning signals worth a look, not pass/fail."
    ),
    nbf.v4.new_code_cell(
        "conf = primary_df.loc[primary_df['source'] == 'LLM', 'confidence'].dropna()\n"
        "\n"
        "fig, ax = plt.subplots(figsize=(8, 4))\n"
        "ax.hist(conf, bins=30, color='#4C72B0')\n"
        "ax.set_xlabel('Confidence')\n"
        "ax.set_ylabel('Mapped products')\n"
        "ax.set_title(f'LLM extraction confidence distribution (n={len(conf):,})')\n"
        "plt.tight_layout()\n"
        "plt.show()"
    ),
    nbf.v4.new_code_cell(
        "flags = {\n"
        "    'is_multi_size': sku_df['is_multi_size'].mean(),\n"
        "    'is_multi_variant': sku_df['is_multi_variant'].mean(),\n"
        "    'is_bundle': sku_df['is_bundle'].mean(),\n"
        "    'pack_count > 1': (sku_df['pack_count'].fillna(1) > 1).mean(),\n"
        "    'size is NULL': sku_df['size'].isna().mean(),\n"
        "}\n"
        "flags_series = __import__('pandas').Series(flags).sort_values()\n"
        "\n"
        "fig, ax = plt.subplots(figsize=(8, 4))\n"
        "(flags_series * 100).plot(kind='barh', ax=ax, color='#DD8452')\n"
        "ax.set_xlabel('% of SKUs')\n"
        "ax.set_title('SKU flag prevalence')\n"
        "plt.tight_layout()\n"
        "plt.show()"
    ),
    nbf.v4.new_code_cell(
        "mismatch_rate = primary_df['brand_mismatch'].mean()\n"
        "print(f'brand_mismatch rate: {mismatch_rate:.1%} ({primary_df[\"brand_mismatch\"].sum():,} of {len(primary_df):,})')\n"
        "\n"
        "dual_mapped = primary_df.groupby(['product_id', 'master_table']).size()\n"
        "n_dual_mapped = (dual_mapped > 1).sum()\n"
        "print(f'Dual-mapped products (QA Gate G1 violation): {n_dual_mapped:,}')"
    ),
    nbf.v4.new_code_cell(
        "word_counts = sku_df['canonical_name'].str.split().str.len()\n"
        "\n"
        "fig, ax = plt.subplots(figsize=(8, 4))\n"
        "word_counts.clip(upper=15).value_counts().sort_index().plot(kind='bar', ax=ax, color='#55A868')\n"
        "ax.set_xlabel('Words in canonical_name (15+ clipped)')\n"
        "ax.set_ylabel('SKUs')\n"
        "ax.set_title('canonical_name word-count distribution')\n"
        "plt.tight_layout()\n"
        "plt.show()"
    ),
    nbf.v4.new_code_cell(
        "import pandas as pd\n"
        "\n"
        "cumulative = pd.Series({n: (word_counts <= n).sum() for n in range(1, 11)})\n"
        "\n"
        "fig, ax = plt.subplots(figsize=(8, 4))\n"
        "cumulative.plot(kind='bar', ax=ax, color='#C44E52')\n"
        "ax.set_xlabel('n (word-count threshold)')\n"
        "ax.set_ylabel('SKUs with canonical_name word count <= n')\n"
        "ax.set_title('Cumulative short canonical_name count — a short name often means a dropped field')\n"
        "plt.tight_layout()\n"
        "plt.show()\n"
        "cumulative"
    ),
]
nb["cells"].extend(cells)

with open(path, "w") as f:
    nbf.write(nb, f)
print("notebook now has", len(nb["cells"]), "cells")
```

- [ ] **Step 2: Run it**

Run: `.venv-embedding/bin/python3 /tmp/product-taxonomy-notebook-validation/task5_build.py`
Expected: `notebook now has 23 cells`

- [ ] **Step 3: Validate against live data**

Run:
```bash
.venv-embedding/bin/python3 << 'PY'
from google.cloud import bigquery

client = bigquery.Client(project='sincere-hearth-273704')

primary_df = client.query('''
SELECT
  m.product_id, m.master_table, m.country, m.platform, m.source,
  SAFE_CAST(m.confidence AS FLOAT64) AS confidence, m.brand_mismatch, m.meta_agent AS map_meta_agent,
  t.taxonomy_id, t.brand_id, b.canonical_name AS brand_name, t.canonical_name, t.size, t.pack_count,
  t.is_multi_size, t.is_multi_variant, t.is_bundle, t.meta_agent AS sku_meta_agent, t.created_at
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` t ON m.taxonomy_id = t.taxonomy_id
LEFT JOIN `sincere-hearth-273704.magpie_reference.brand_dict` b ON t.brand_id = b.brand_id
''').to_dataframe()

sku_df = client.query('''
SELECT t.taxonomy_id, t.brand_id, b.canonical_name AS brand_name, t.product_line, t.sub_line,
       t.variant, t.canonical_name, t.size, t.pack_count, t.is_multi_size, t.is_multi_variant,
       t.is_bundle, t.meta_agent, t.created_at
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy` t
LEFT JOIN `sincere-hearth-273704.magpie_reference.brand_dict` b ON t.brand_id = b.brand_id
QUALIFY ROW_NUMBER() OVER (PARTITION BY t.taxonomy_id ORDER BY t.updated_at DESC) = 1
''').to_dataframe()

conf = primary_df.loc[primary_df['source'] == 'LLM', 'confidence'].dropna()
print('confidence n=', len(conf), 'range', conf.min(), conf.max())
assert conf.between(0, 1).all()

flags = {
    'is_multi_size': sku_df['is_multi_size'].mean(),
    'is_multi_variant': sku_df['is_multi_variant'].mean(),
    'is_bundle': sku_df['is_bundle'].mean(),
    'pack_count > 1': (sku_df['pack_count'].fillna(1) > 1).mean(),
    'size is NULL': sku_df['size'].isna().mean(),
}
print(flags)

print('brand_mismatch rate:', primary_df['brand_mismatch'].mean())

dual_mapped = primary_df.groupby(['product_id', 'master_table']).size()
print('dual-mapped:', (dual_mapped > 1).sum())
# expect ballpark 1,450 per Global Constraints — exact number will drift, just confirm it's nonzero and
# not wildly different (e.g. not in the hundreds of thousands)

word_counts = sku_df['canonical_name'].str.split().str.len()
print(word_counts.describe())
cumulative = {n: int((word_counts <= n).sum()) for n in range(1, 11)}
print(cumulative)
assert cumulative[10] > cumulative[1]
PY
```

Expected: confidence values all within `[0, 1]`, flag prevalences are all valid percentages (0-1 as
fractions), dual-mapped count in the same order of magnitude as the ~1,450 ballpark, word-count cumulative
values strictly increasing.

- [ ] **Step 4: Commit**

```bash
git add notebooks/product_taxonomy_exploration.ipynb
git commit -m "Add quality signals section (incl. canonical_name word-count check)"
```

---

### Task 6: Section 4 — Growth over time

**Files:**
- Modify: `notebooks/product_taxonomy_exploration.ipynb` (append cells)

**Interfaces:**
- Consumes: `sku_df` (Task 2).
- Produces: nothing shared.

- [ ] **Step 1: Write the append script**

Save as `/tmp/product-taxonomy-notebook-validation/task6_build.py`:

```python
import nbformat as nbf

path = "notebooks/product_taxonomy_exploration.ipynb"
nb = nbf.read(path, as_version=4)

cells = [
    nbf.v4.new_markdown_cell("## 6. Growth over time"),
    nbf.v4.new_code_cell(
        "import pandas as pd\n"
        "\n"
        "n_missing_created = sku_df['created_at'].isna().sum()\n"
        "print(f'{n_missing_created:,} of {len(sku_df):,} SKUs have no created_at and are excluded below')\n"
        "\n"
        "created = pd.to_datetime(sku_df['created_at'].dropna()).dt.date\n"
        "daily_new = created.value_counts().sort_index()\n"
        "cumulative_skus = daily_new.cumsum()\n"
        "\n"
        "fig, ax = plt.subplots(figsize=(12, 4))\n"
        "cumulative_skus.plot(ax=ax, color='#4C72B0')\n"
        "ax.set_ylabel('Cumulative SKUs (excludes NULL created_at)')\n"
        "ax.set_title('SKU count growth over time')\n"
        "plt.tight_layout()\n"
        "plt.show()"
    ),
]
nb["cells"].extend(cells)

with open(path, "w") as f:
    nbf.write(nb, f)
print("notebook now has", len(nb["cells"]), "cells")
```

- [ ] **Step 2: Run it**

Run: `.venv-embedding/bin/python3 /tmp/product-taxonomy-notebook-validation/task6_build.py`
Expected: `notebook now has 25 cells`

- [ ] **Step 3: Validate against live data**

```python
import pandas as pd
n_missing_created = sku_df['created_at'].isna().sum()
print(f'{n_missing_created:,} of {len(sku_df):,} SKUs have no created_at and are excluded below')

created = pd.to_datetime(sku_df['created_at'].dropna()).dt.date
daily_new = created.value_counts().sort_index()
cumulative_skus = daily_new.cumsum()
print(cumulative_skus.tail())
assert cumulative_skus.is_monotonic_increasing
assert cumulative_skus.iloc[-1] == sku_df['taxonomy_id'].nunique() - n_missing_created
```

Expected: no exceptions — prints a nonzero `n_missing_created` count (confirmed live: ~1,276 of 22,005 SKUs
have `NULL created_at` — a real gap, not a bug in this query; the chart explicitly discloses the exclusion
rather than silently under-counting), and the final cumulative value must exactly equal
`total distinct SKUs - n_missing_created` (sanity check that the cumsum didn't drop or double-count any of
the remaining rows).

- [ ] **Step 4: Commit**

```bash
git add notebooks/product_taxonomy_exploration.ipynb
git commit -m "Add growth-over-time section to taxonomy exploration notebook"
```

---

### Task 7: Section 5 — Per-category comparison table

**Files:**
- Modify: `notebooks/product_taxonomy_exploration.ipynb` (append cells)

**Interfaces:**
- Consumes: `primary_df`, `sku_df`, `gmv_df` (Task 2).
- Produces: nothing shared (last content section).

- [ ] **Step 1: Write the append script**

Save as `/tmp/product-taxonomy-notebook-validation/task7_build.py`:

```python
import nbformat as nbf

path = "notebooks/product_taxonomy_exploration.ipynb"
nb = nbf.read(path, as_version=4)

cells = [
    nbf.v4.new_markdown_cell(
        "## 7. Per-category comparison table\n"
        "\n"
        "Data-driven counterpart to `docs/categories/STATUS.md` — one row per category."
    ),
    nbf.v4.new_code_cell(
        "import pandas as pd\n"
        "\n"
        "per_cat = primary_df.groupby('master_table').agg(\n"
        "    sku_count=('taxonomy_id', 'nunique'),\n"
        "    mapped_products=('product_id', 'nunique'),\n"
        "    avg_confidence=('confidence', 'mean'),\n"
        "    distinct_brands=('brand_name', 'nunique'),\n"
        ").reset_index()\n"
        "\n"
        "top_brand = (\n"
        "    primary_df.groupby(['master_table', 'brand_name'])['product_id'].nunique()\n"
        "    .reset_index()\n"
        "    .sort_values('product_id', ascending=False)\n"
        "    .drop_duplicates('master_table')\n"
        "    .rename(columns={'brand_name': 'top_brand'})\n"
        "    [['master_table', 'top_brand']]\n"
        ")\n"
        "\n"
        "comparison = (\n"
        "    per_cat.merge(gmv_df[['master_table', 'coverage']], on='master_table', how='left')\n"
        "    .merge(top_brand, on='master_table', how='left')\n"
        "    .sort_values('mapped_products', ascending=False)\n"
        ")\n"
        "comparison['coverage'] = (comparison['coverage'] * 100).round(1)\n"
        "comparison['avg_confidence'] = comparison['avg_confidence'].round(3)\n"
        "comparison"
    ),
]
nb["cells"].extend(cells)

with open(path, "w") as f:
    nbf.write(nb, f)
print("notebook now has", len(nb["cells"]), "cells")
```

- [ ] **Step 2: Run it**

Run: `.venv-embedding/bin/python3 /tmp/product-taxonomy-notebook-validation/task7_build.py`
Expected: `notebook now has 27 cells`

- [ ] **Step 3: Validate against live data**

Run:
```bash
.venv-embedding/bin/python3 << 'PY'
from google.cloud import bigquery

client = bigquery.Client(project='sincere-hearth-273704')

primary_df = client.query('''
SELECT
  m.product_id, m.master_table, m.country, m.platform, m.source,
  SAFE_CAST(m.confidence AS FLOAT64) AS confidence, m.brand_mismatch, m.meta_agent AS map_meta_agent,
  t.taxonomy_id, t.brand_id, b.canonical_name AS brand_name, t.canonical_name, t.size, t.pack_count,
  t.is_multi_size, t.is_multi_variant, t.is_bundle, t.meta_agent AS sku_meta_agent, t.created_at
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` t ON m.taxonomy_id = t.taxonomy_id
LEFT JOIN `sincere-hearth-273704.magpie_reference.brand_dict` b ON t.brand_id = b.brand_id
''').to_dataframe()

gmv_df = client.query('''
WITH latest AS (SELECT MAX(month) AS m FROM `sincere-hearth-273704.magpie.marketshare_universe_niq`),
dedup_map AS (
  SELECT * FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id, platform, country, master_table
    ORDER BY CASE source WHEN 'LLM' THEN 0 ELSE 1 END, taxonomy_id) = 1
),
mapped AS (
  SELECT u.master_table, SUM(u.gmv_monthly) AS mapped_gmv
  FROM `sincere-hearth-273704.magpie.marketshare_universe_niq` u, latest
  JOIN dedup_map m ON m.product_id = u.product_id AND m.platform = u.ecommerce_platform
    AND m.country = u.country AND m.master_table = u.master_table
  WHERE u.month = latest.m GROUP BY 1
),
total AS (
  SELECT master_table, SUM(gmv_monthly) AS total_gmv
  FROM `sincere-hearth-273704.magpie.marketshare_universe_niq`, latest WHERE month = latest.m GROUP BY 1
)
SELECT t.master_table, COALESCE(mapped.mapped_gmv, 0) AS mapped_gmv, t.total_gmv,
       SAFE_DIVIDE(COALESCE(mapped.mapped_gmv, 0), t.total_gmv) AS coverage
FROM total t LEFT JOIN mapped USING(master_table)
''').to_dataframe()

per_cat = primary_df.groupby('master_table').agg(
    sku_count=('taxonomy_id', 'nunique'),
    mapped_products=('product_id', 'nunique'),
    avg_confidence=('confidence', 'mean'),
    distinct_brands=('brand_name', 'nunique'),
).reset_index()

top_brand = (
    primary_df.groupby(['master_table', 'brand_name'])['product_id'].nunique()
    .reset_index()
    .sort_values('product_id', ascending=False)
    .drop_duplicates('master_table')
    .rename(columns={'brand_name': 'top_brand'})
    [['master_table', 'top_brand']]
)

comparison = (
    per_cat.merge(gmv_df[['master_table', 'coverage']], on='master_table', how='left')
    .merge(top_brand, on='master_table', how='left')
    .sort_values('mapped_products', ascending=False)
)
print(comparison.shape)
print(comparison.head(10).to_string())
assert comparison['master_table'].is_unique
assert len(comparison) == primary_df['master_table'].nunique()
PY
```

Expected: one row per category (~43), no duplicate `master_table` values, `top_brand` populated for every
row, printed head looks like real category/brand names.

- [ ] **Step 4: Commit**

```bash
git add notebooks/product_taxonomy_exploration.ipynb
git commit -m "Add per-category comparison table to taxonomy exploration notebook"
```

---

### Task 8: Final review — strip outputs, validate, read through

**Files:**
- Modify: `notebooks/product_taxonomy_exploration.ipynb`

**Interfaces:**
- Consumes: the complete notebook from Tasks 1-7.
- Produces: the final committed deliverable.

- [ ] **Step 1: Confirm no cell has saved outputs**

Run:
```bash
.venv-embedding/bin/python3 -c "
import nbformat
nb = nbformat.read('notebooks/product_taxonomy_exploration.ipynb', as_version=4)
has_output = any(c.get('outputs') for c in nb.cells if c.cell_type == 'code')
print('has_output:', has_output)
"
```
Expected: `has_output: False` (every validation ran against a throwaway ADC-auth script, never executed the
committed notebook's own Colab-auth cells, so no outputs should have been written to it — this just
confirms that).

- [ ] **Step 2: Validate full notebook JSON**

Run: `.venv-embedding/bin/python3 -c "import nbformat; nb = nbformat.read('notebooks/product_taxonomy_exploration.ipynb', as_version=4); nbformat.validate(nb); print('valid,', len(nb.cells), 'cells')"`
Expected: `valid, 27 cells`

- [ ] **Step 3: Read through the notebook once, section by section, checking against the design spec**

Run: `.venv-embedding/bin/python3 -c "
import nbformat
nb = nbformat.read('notebooks/product_taxonomy_exploration.ipynb', as_version=4)
for c in nb.cells:
    if c.cell_type == 'markdown' and c.source.startswith('#'):
        print(c.source.splitlines()[0])
"`
Expected output lists all 7 headers in order: the title, `## 1. Setup`, `## 2. Load shared data`,
`## 3. Headline dashboard`, `## 4. Taxonomy composition`, `## 5. Quality signals`,
`## 6. Growth over time`, `## 7. Per-category comparison table`. Cross-check this against
`docs/superpowers/specs/2026-07-20-product-taxonomy-exploration-notebook-design.md`'s 5 sections (Setup and
Load-shared-data are infrastructure, not counted in the spec's 5) — confirm all 5 are present.

- [ ] **Step 4: Clean up scratch validation files**

Run: `rm -rf /tmp/product-taxonomy-notebook-validation`

- [ ] **Step 5: Commit**

```bash
git add notebooks/product_taxonomy_exploration.ipynb
git status
```
If Step 1-3 made no changes (they're read-only checks), there's nothing new to commit — Task 7's commit is
the final state. If Step 1 had found saved outputs, this is where you'd strip them (`jupyter nbconvert
--clear-output --inplace notebooks/product_taxonomy_exploration.ipynb` if available, otherwise a small
`nbformat` script setting `cell.outputs = []` and `cell.execution_count = None` on every code cell) and
commit that separately.
