# Headless Taxonomy V2 — Cross-Market Candidate Retrieval Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `script/niq/headless_taxonomy_v2.sh` — a new sibling to `headless_taxonomy.sh` that pre-fetches
a candidate-enriched worklist (like `targeted_qa_fix_v2.sh` already does) before `claude -p` runs, with
candidates pulled from both the current table and fuzzy-matched sibling category tables in other countries.

**Architecture:** One new pure Python module (`script/niq/headless_v2_worklist.py`) does all SQL/BigQuery
work and zero LLM calls: discovers sibling tables by table-name Jaccard similarity, selects the worklist
(reusing V1's exact top_up query; a new official-store-excluded query for first_run), retrieves ranked
candidates via one static SQL file, and prints a JSON worklist to stdout. A new bash wrapper
(`script/niq/headless_taxonomy_v2.sh`) reuses V1's scenario-detection/block-size/SKU-block/queue-signal
logic verbatim, pipes the Python-built worklist JSON into a modified prompt via stdin, same as
`targeted_qa_fix_v2.sh`.

**Tech Stack:** Bash (`bq` CLI, `claude -p`), Python 3.9+ (`google-cloud-bigquery`), BigQuery Standard SQL
(`EDIT_DISTANCE`, `QUALIFY`). No new dependencies — `google-cloud-bigquery` is already in `pyproject.toml`.

**Spec:** `docs/superpowers/specs/2026-08-21-headless-taxonomy-v2-cross-market-candidates-design.md`

## Global Constraints

- `PROJECT = "sincere-hearth-273704"` everywhere (matches every existing script in `script/niq/`).
- No embeddings, no ML matcher — plain `EDIT_DISTANCE` only (spec Non-goals).
- Every candidate is reference-only; the agent must independently verify against `sku_name`/image before
  writing anything (spec Non-goals).
- Sibling discovery: same platform, different country only; Jaccard threshold `>= 0.5` on stopword-stripped
  (`for`, `and`, `or`, `of`, `the`, `a`) underscore-tokenized category slugs (spec §1).
- Candidate query: Tier A (brand-scoped via `product_brand_map`) preferred, Tier B (text-only) fills
  remaining slots per worklist product, top 5 total (spec §2).
- No pytest / unittest — this repo's Python tests are plain `assert`-based scripts with a
  `if __name__ == "__main__"` runner (see `tests/niq/test_qa_v2_worklist.py`). Follow that convention, not a
  test framework.
- Write via `bq query` DML only inside any generated prompt text — never the streaming API (existing V1
  convention, carries over unchanged).
- V1 (`headless_taxonomy.sh`) is not modified by this plan at all.

---

### Task 1: Sibling-table discovery (pure functions)

**Files:**
- Create: `script/niq/headless_v2_worklist.py` (this task starts the file; later tasks append to it)
- Test: `tests/niq/test_headless_v2_worklist.py` (this task starts the file; later tasks append to it)

**Interfaces:**
- Produces: `parse_table_name(table_name: str) -> tuple[str, str, frozenset[str]]` (platform, country,
  category_tokens), `jaccard_similarity(a: frozenset, b: frozenset) -> float`,
  `find_sibling_tables(this_table: str, all_tables: list[str], threshold: float = 0.5) -> list[tuple[str, float]]`
  (sorted by score descending)

- [ ] **Step 1: Write the failing tests**

Create `tests/niq/test_headless_v2_worklist.py`:

```python
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "script" / "niq"))
from headless_v2_worklist import parse_table_name, jaccard_similarity, find_sibling_tables


def test_parse_table_name_splits_platform_country_category():
    platform, country, tokens = parse_table_name("shopee_id_adult_diapers")
    assert platform == "shopee"
    assert country == "id"
    assert tokens == frozenset({"adult", "diapers"})


def test_parse_table_name_strips_stopwords_from_category_tokens():
    _, _, tokens = parse_table_name("shopee_id_hand_and_body_lotion")
    assert tokens == frozenset({"hand", "body", "lotion"})


def test_jaccard_similarity_identical_sets_is_one():
    assert jaccard_similarity(frozenset({"a", "b"}), frozenset({"a", "b"})) == 1.0


def test_jaccard_similarity_disjoint_sets_is_zero():
    assert jaccard_similarity(frozenset({"a"}), frozenset({"b"})) == 0.0


def test_jaccard_similarity_diapers_vs_adult_diapers_matches_at_half():
    score = jaccard_similarity(frozenset({"diapers"}), frozenset({"adult", "diapers"}))
    assert score == 0.5


def test_jaccard_similarity_baby_vs_adult_diapers_excluded_below_half():
    score = jaccard_similarity(frozenset({"baby", "diapers"}), frozenset({"adult", "diapers"}))
    assert round(score, 2) == 0.33
    assert score < 0.5


def test_jaccard_similarity_hand_and_body_lotion_vs_moisturiser_matches():
    _, _, a = parse_table_name("shopee_id_hand_and_body_lotion")
    _, _, b = parse_table_name("shopee_sg_hand_and_body_moisturiser")
    assert jaccard_similarity(a, b) == 0.5


def test_find_sibling_tables_matches_adult_diapers_across_countries():
    all_tables = [
        "shopee_id_adult_diapers", "shopee_th_adult_diapers", "shopee_sg_diapers",
        "shopee_id_baby_diapers", "shopee_th_baby_diapers", "shopee_id_toothpaste",
    ]
    siblings = find_sibling_tables("shopee_id_adult_diapers", all_tables)
    sibling_names = {name for name, score in siblings}
    assert sibling_names == {"shopee_th_adult_diapers", "shopee_sg_diapers"}


def test_find_sibling_tables_excludes_self():
    all_tables = ["shopee_id_adult_diapers", "shopee_th_adult_diapers"]
    siblings = find_sibling_tables("shopee_id_adult_diapers", all_tables)
    assert "shopee_id_adult_diapers" not in {name for name, score in siblings}


def test_find_sibling_tables_excludes_same_country():
    all_tables = ["shopee_id_adult_diapers", "shopee_id_baby_diapers"]
    siblings = find_sibling_tables("shopee_id_adult_diapers", all_tables)
    assert siblings == []


def test_find_sibling_tables_excludes_different_platform():
    all_tables = ["shopee_id_adult_diapers", "lazada_th_adult_diapers"]
    siblings = find_sibling_tables("shopee_id_adult_diapers", all_tables)
    assert siblings == []


def test_find_sibling_tables_sorts_by_score_descending():
    all_tables = ["shopee_id_adult_diapers", "shopee_th_adult_diapers", "shopee_sg_diapers"]
    siblings = find_sibling_tables("shopee_id_adult_diapers", all_tables)
    scores = [score for name, score in siblings]
    assert scores == sorted(scores, reverse=True)


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print(f"PASS: {name}")
    print("ALL TESTS PASSED")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 tests/niq/test_headless_v2_worklist.py`
Expected: `ModuleNotFoundError: No module named 'headless_v2_worklist'` (file doesn't exist yet)

- [ ] **Step 3: Write the minimal implementation**

Create `script/niq/headless_v2_worklist.py`:

```python
#!/usr/bin/env python3
"""Builds the candidate-enriched worklist for headless_taxonomy_v2.sh -- all pure SQL/Python, no LLM calls.
Candidates come from the current table AND fuzzy-matched sibling category tables in other countries. See
docs/superpowers/specs/2026-08-21-headless-taxonomy-v2-cross-market-candidates-design.md."""
import re

PROJECT = "sincere-hearth-273704"
_SAFE_TABLE_NAME = re.compile(r"^[a-zA-Z0-9_]+$")
_STOPWORDS = {"for", "and", "or", "of", "the", "a"}


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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 tests/niq/test_headless_v2_worklist.py`
Expected: `ALL TESTS PASSED`

- [ ] **Step 5: Commit**

```bash
git add script/niq/headless_v2_worklist.py tests/niq/test_headless_v2_worklist.py
git commit -m "Add sibling-table discovery for headless_taxonomy_v2.sh"
```

---

### Task 2: Candidate retrieval SQL + query builder

**Files:**
- Create: `sql/queries/headless_v2_candidate_products.sql`
- Modify: `script/niq/headless_v2_worklist.py` (append)
- Modify: `tests/niq/test_headless_v2_worklist.py` (append)

**Interfaces:**
- Consumes: nothing from Task 1 directly (independent query), but shares the file with Task 1's functions
- Produces: `build_candidate_products_query(product_ids: list[str], sku_names: list[str], this_table: str, scope_tables: list[str], n: int = 5) -> tuple[str, list]`

- [ ] **Step 1: Write the failing tests**

Append to `tests/niq/test_headless_v2_worklist.py` (add the import and new test functions; keep the existing
`if __name__ == "__main__"` block as the last thing in the file):

```python
from headless_v2_worklist import build_candidate_products_query  # add to the existing import line


def test_build_candidate_products_query_binds_all_params():
    sql, params = build_candidate_products_query(
        product_ids=["P1", "P2"], sku_names=["Sku One", "Sku Two"],
        this_table="shopee_id_adult_diapers", scope_tables=["shopee_id_adult_diapers", "shopee_th_adult_diapers"],
    )
    param_names = {p.name for p in params}
    assert param_names == {"product_ids", "sku_names", "this_table", "scope_tables", "n"}
    n_param = next(p for p in params if p.name == "n")
    assert n_param.value == 5


def test_build_candidate_products_query_sql_covers_both_tiers():
    sql, params = build_candidate_products_query(["P1"], ["Sku"], "t", ["t"])
    assert "brand_match" in sql
    assert "text_only" in sql
    assert "review_confidence" in sql
    assert "source_table" in sql
    assert "EDIT_DISTANCE" in sql
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 tests/niq/test_headless_v2_worklist.py`
Expected: `ImportError: cannot import name 'build_candidate_products_query'`

- [ ] **Step 3: Write the SQL file**

Create `sql/queries/headless_v2_candidate_products.sql`:

```sql
-- sql/queries/headless_v2_candidate_products.sql
-- For each worklist product (raw, unmapped -- no product_taxonomy row exists for it yet), the top @n
-- reference candidates from product_taxonomy rows scoped to @scope_tables (this table + fuzzy-matched
-- sibling tables), review_confidence='confident' only. Tier A (brand-scoped, via product_brand_map)
-- preferred; Tier B (pure text) fills remaining slots for a product with no Tier A rows. Reference/format
-- context only -- never a basis for an autonomous write. See
-- docs/superpowers/specs/2026-08-21-headless-taxonomy-v2-cross-market-candidates-design.md.
-- Params: @product_ids ARRAY<STRING>, @sku_names ARRAY<STRING> (parallel, same order as @product_ids),
--         @this_table STRING, @scope_tables ARRAY<STRING>, @n INT64

WITH worklist AS (
  SELECT product_id, sku_name
  FROM UNNEST(@product_ids) AS product_id WITH OFFSET pid_pos
  JOIN UNNEST(@sku_names) AS sku_name WITH OFFSET sku_pos ON pid_pos = sku_pos
),
worklist_brand AS (
  SELECT product_id, brand_id
  FROM `sincere-hearth-273704.magpie_reference.product_brand_map`
  WHERE master_table = @this_table AND product_id IN UNNEST(@product_ids)
),
candidate_pool AS (
  SELECT DISTINCT pt.taxonomy_id, pt.brand_id, pt.canonical_name, m.master_table AS source_table
  FROM `sincere-hearth-273704.magpie_reference.product_taxonomy` pt
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m ON m.taxonomy_id = pt.taxonomy_id
  WHERE m.master_table IN UNNEST(@scope_tables)
    AND JSON_VALUE(pt._meta, '$.review_confidence') = 'confident'
),
tier_a AS (
  SELECT w.product_id AS worklist_product_id, c.taxonomy_id AS candidate_taxonomy_id,
    c.canonical_name AS candidate_canonical_name, c.source_table,
    SAFE_DIVIDE(EDIT_DISTANCE(w.sku_name, c.canonical_name), GREATEST(LENGTH(w.sku_name), LENGTH(c.canonical_name))) AS normalized_distance,
    'brand_match' AS match_tier
  FROM worklist w
  JOIN worklist_brand wb ON wb.product_id = w.product_id
  JOIN candidate_pool c ON c.brand_id = wb.brand_id
),
tier_b AS (
  SELECT w.product_id AS worklist_product_id, c.taxonomy_id AS candidate_taxonomy_id,
    c.canonical_name AS candidate_canonical_name, c.source_table,
    SAFE_DIVIDE(EDIT_DISTANCE(w.sku_name, c.canonical_name), GREATEST(LENGTH(w.sku_name), LENGTH(c.canonical_name))) AS normalized_distance,
    'text_only' AS match_tier
  FROM worklist w
  CROSS JOIN candidate_pool c
  WHERE w.product_id NOT IN (SELECT worklist_product_id FROM tier_a)
)
SELECT worklist_product_id, candidate_taxonomy_id, candidate_canonical_name, source_table, match_tier, normalized_distance
FROM (SELECT * FROM tier_a UNION ALL SELECT * FROM tier_b)
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY worklist_product_id ORDER BY (match_tier != 'brand_match'), normalized_distance ASC
) <= @n
```

- [ ] **Step 4: Add the query builder function**

Append to `script/niq/headless_v2_worklist.py` (add near the top, after the existing imports):

```python
from pathlib import Path

from google.cloud import bigquery

_SQL_DIR = Path(__file__).parent.parent.parent / "sql" / "queries"


def _load_sql(filename):
    return (_SQL_DIR / filename).read_text()
```

(Note: `import re` already exists at the top of the file from Task 1 — leave it, just add the two new
imports and `_SQL_DIR`/`_load_sql` above/below it.)

Then append the builder function:

```python
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `python3 tests/niq/test_headless_v2_worklist.py`
Expected: `ALL TESTS PASSED`

- [ ] **Step 6: Dry-run the SQL against real BigQuery (open verification item from the spec)**

This is required before trusting the query — not optional. Run manually:

```bash
python3 -c "
from google.cloud import bigquery
import sys
sys.path.insert(0, 'script/niq')
from headless_v2_worklist import build_candidate_products_query

client = bigquery.Client(project='sincere-hearth-273704')
sql, params = build_candidate_products_query(
    product_ids=['24537579760'], sku_names=['LIVELY Underpad PREMIUM Perlak Bayi 60cm X 90cm'],
    this_table='shopee_id_adult_diapers', scope_tables=['shopee_id_adult_diapers', 'shopee_th_adult_diapers'],
)
job = client.query(sql, job_config=bigquery.QueryJobConfig(query_parameters=params))
for row in job.result():
    print(dict(row.items()))
"
```

Expected: runs without a SQL error and returns 0 or more candidate rows (0 is fine if
`shopee_th_adult_diapers` has no `review_confidence='confident'` rows yet — not a bug, just means nothing
there has passed a QA pass). If this errors, fix the SQL before continuing to Task 3.

- [ ] **Step 7: Commit**

```bash
git add sql/queries/headless_v2_candidate_products.sql script/niq/headless_v2_worklist.py tests/niq/test_headless_v2_worklist.py
git commit -m "Add cross-market candidate retrieval query for headless_taxonomy_v2.sh"
```

---

### Task 3: Worklist selection queries (top_up, first_run, brief parsing)

**Files:**
- Modify: `script/niq/headless_v2_worklist.py` (append)
- Modify: `tests/niq/test_headless_v2_worklist.py` (append)

**Interfaces:**
- Produces: `build_topup_worklist_query(table: str, month: str, block_size: int) -> tuple[str, list]`,
  `extract_official_store_merchants(brief_markdown: str) -> list[str]`,
  `build_first_run_candidate_pool_query(table: str, month: str, exclude_merchants: list[str], block_size: int) -> tuple[str, list]`,
  `build_brief_markdown_query(category_key: str) -> tuple[str, list]`

- [ ] **Step 1: Write the failing tests**

Append to `tests/niq/test_headless_v2_worklist.py` (extend the import line with the new names):

```python
from headless_v2_worklist import (
    build_topup_worklist_query, extract_official_store_merchants,
    build_first_run_candidate_pool_query, build_brief_markdown_query,
)

_SAMPLE_BRIEF_EXCERPT = """
## Official Store Allowlist (Pass 1)

| Brand | brand_id | Official Store Merchant Name |
|-------|----------|------------------------------|
| Lifree | `BRD-GLOBAL-00024` | `Lifree Official Store` |
| Lifree / Certainty / CHARM (parent co.) | — | `Unicharm Official Shop`, `Unicharm Authorized Partner Jawa Tengah` |
| Confidence | `BRD-TH-03303` | `Confidence Official Shop` |

**Excluded multi-brand retailers (never Pass 1, regardless of Mall badge)** — confirmed by sampling:
- **Pharmacy chains:** every `Apotek *` store

---

## Scale
"""


def test_build_topup_worklist_query_reuses_v1_shape():
    sql, params = build_topup_worklist_query("shopee_th_suncare", "2026-06", 500)
    assert "master_clean_niq.shopee_th_suncare" in sql
    assert "cumulative_gmv_pct <= 95" in sql
    assert "canonical_name IS NULL" in sql
    assert "CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END" in sql
    param_names = {p.name for p in params}
    assert param_names == {"month", "block_size"}


def test_extract_official_store_merchants_gets_pass1_column_only():
    merchants = extract_official_store_merchants(_SAMPLE_BRIEF_EXCERPT)
    assert "Lifree Official Store" in merchants
    assert "Unicharm Official Shop" in merchants
    assert "Unicharm Authorized Partner Jawa Tengah" in merchants
    assert "Confidence Official Shop" in merchants
    # brand_id backtick tokens and the excluded-retailer bullet list must NOT leak in
    assert "BRD-GLOBAL-00024" not in merchants
    assert "Apotek *" not in merchants


def test_extract_official_store_merchants_empty_when_section_missing():
    assert extract_official_store_merchants("# Some other doc\nNo allowlist here.") == []


def test_build_first_run_candidate_pool_query_excludes_official_stores():
    sql, params = build_first_run_candidate_pool_query(
        "shopee_id_adult_diapers", "2026-06", ["Lifree Official Store"], 2000,
    )
    assert "master_clean_niq.shopee_id_adult_diapers" in sql
    assert "NOT IN UNNEST(@exclude_merchants)" in sql
    assert "cumulative_gmv_pct <= 95" in sql
    param_names = {p.name for p in params}
    assert param_names == {"month", "exclude_merchants", "block_size"}


def test_build_brief_markdown_query_scopes_to_brief_task_type():
    sql, params = build_brief_markdown_query("master_clean_niq.shopee_id_adult_diapers")
    assert "task_type = 'BRIEF'" in sql
    assert {p.name for p in params} == {"category_key"}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 tests/niq/test_headless_v2_worklist.py`
Expected: `ImportError: cannot import name 'build_topup_worklist_query'`

- [ ] **Step 3: Write the implementation**

Append to `script/niq/headless_v2_worklist.py`:

```python
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 tests/niq/test_headless_v2_worklist.py`
Expected: `ALL TESTS PASSED`

- [ ] **Step 5: Commit**

```bash
git add script/niq/headless_v2_worklist.py tests/niq/test_headless_v2_worklist.py
git commit -m "Add worklist-selection queries and brief-parsing for headless_taxonomy_v2.sh"
```

---

### Task 4: Assemble `headless_v2_worklist.py`'s `main()`

**Files:**
- Modify: `script/niq/headless_v2_worklist.py` (append)
- Modify: `tests/niq/test_headless_v2_worklist.py` (append)

**Interfaces:**
- Consumes: every builder function from Tasks 1-3
- Produces: `run_query(client, sql, params) -> list[dict]`, `fetch_brief_markdown(client, table) -> str`,
  `assemble_worklist_json(rows: list[dict], candidates_by_id: dict) -> list[dict]`, CLI entry point

- [ ] **Step 1: Write the failing test**

Append to `tests/niq/test_headless_v2_worklist.py` (extend the import line):

```python
from headless_v2_worklist import assemble_worklist_json


def test_assemble_worklist_json_defaults_missing_candidates_to_empty():
    rows = [{"product_id": "P1", "sku_name": "Sku One", "merchant_name": "Store A", "gmv_monthly": 5000}]
    result = assemble_worklist_json(rows, {})
    assert result == [{
        "product_id": "P1", "sku_name": "Sku One", "merchant_name": "Store A", "gmv": 5000, "candidates": [],
    }]


def test_assemble_worklist_json_attaches_candidates_by_product_id():
    rows = [{"product_id": "P1", "sku_name": "Sku One", "merchant_name": None, "gmv_monthly": 100}]
    candidates_by_id = {"P1": [{"taxonomy_id": "SKU-1", "canonical_name": "X", "source_table": "t",
                                 "match_tier": "brand_match", "normalized_distance": 0.1}]}
    result = assemble_worklist_json(rows, candidates_by_id)
    assert result[0]["candidates"] == candidates_by_id["P1"]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 tests/niq/test_headless_v2_worklist.py`
Expected: `ImportError: cannot import name 'assemble_worklist_json'`

- [ ] **Step 3: Write the implementation**

Append to `script/niq/headless_v2_worklist.py` (add `import argparse`, `import json`, and `import sys` to the
top-of-file imports alongside the existing `import re`):

```python
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 tests/niq/test_headless_v2_worklist.py`
Expected: `ALL TESTS PASSED`

- [ ] **Step 5: Manual end-to-end smoke test against real BigQuery**

```bash
python3 script/niq/headless_v2_worklist.py --table shopee_id_adult_diapers --scenario top_up --month 2026-06 --block-size 10
```

Expected: stderr prints the sibling-table list (should include `shopee_th_adult_diapers`), stdout prints a
JSON array of up to 10 worklist products each with a `candidates` list (possibly empty per-product, that's
fine). If this errors, fix before continuing.

- [ ] **Step 6: Commit**

```bash
git add script/niq/headless_v2_worklist.py tests/niq/test_headless_v2_worklist.py
git commit -m "Wire headless_v2_worklist.py main() -- sibling discovery + worklist + candidates -> JSON"
```

---

### Task 5: `headless_taxonomy_v2.sh` wrapper

**Files:**
- Create: `script/niq/headless_taxonomy_v2.sh`
- Create: `tests/niq/test_headless_taxonomy_v2.sh`
- Modify: `docs/headless-runbook.md` (add a pointer note)

**Interfaces:**
- Consumes: `script/niq/headless_v2_worklist.py`'s CLI (`--table --scenario --month --block-size`), stdout
  contract (JSON array or `[]`)
- Produces: `./script/niq/headless_taxonomy_v2.sh <TABLE> [MONTH] [MAX_TURNS]` CLI, same
  `QUEUE_SIGNAL: <...>` stdout contract as V1

- [ ] **Step 1: Write the failing tests**

Create `tests/niq/test_headless_taxonomy_v2.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Self-test for script/niq/headless_taxonomy_v2.sh's pure helper functions.
# No network, BQ, or claude calls -- mirrors tests/niq/test_headless_taxonomy.sh's convention.
# Run: bash tests/niq/test_headless_taxonomy_v2.sh

cd "$(dirname "$0")/../.."
source script/niq/headless_taxonomy_v2.sh

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- decide_scenario / compute_block_size (ported verbatim from V1 -- same behavior expected) ---
[[ "$(decide_scenario 0)" == "first_run" ]] || fail "0 existing rows -> first_run"
[[ "$(decide_scenario 5000)" == "top_up" ]] || fail "nonzero existing rows -> top_up"
[[ "$(compute_block_size first_run 0)" == "2000" ]] || fail "first_run always claims 2000"
[[ "$(compute_block_size top_up 50)" == "200" ]] || fail "top_up floors the block size at 200"
[[ "$(compute_block_size top_up 500)" == "500" ]] || fail "top_up scales the block size with gap_count"
[[ "$(compute_block_size top_up 5000)" == "2000" ]] || fail "top_up caps the block size at 2000"
echo "PASS: decide_scenario / compute_block_size"

# --- build_topup_prompt_v2 ---
sample_worklist='[{"product_id":"P1","sku_name":"Sweety Silver Pants M","merchant_name":"Some Reseller","gmv":500000,"candidates":[{"taxonomy_id":"SKU-000001","canonical_name":"Sweety Silver Pants M x8","source_table":"shopee_id_adult_diapers","match_tier":"brand_match","normalized_distance":0.12}]}]'
prompt=$(build_topup_prompt_v2 "shopee_id_adult_diapers" "2026-06" "500" "412" "$sample_worklist")
echo "$prompt" | grep -q "shopee_id_adult_diapers" || fail "build_topup_prompt_v2 should mention the table"
echo "$prompt" | grep -qF "$sample_worklist" || fail "build_topup_prompt_v2 must embed the worklist JSON verbatim"
echo "$prompt" | grep -q "pre-fetched" || fail "build_topup_prompt_v2 must tell the agent the worklist is pre-fetched, not something to query itself"
echo "$prompt" | grep -q "source_table" || fail "build_topup_prompt_v2 must explain the source_table field"
echo "$prompt" | grep -q "never map a product directly to a cross-market taxonomy_id" || fail "build_topup_prompt_v2 must forbid direct cross-market mapping"
echo "$prompt" | grep -q "taxonomy_topup" || fail "build_topup_prompt_v2 should claim a taxonomy_topup-scenario SKU block"
echo "$prompt" | grep -q "status='blocked'" || fail "build_topup_prompt_v2 should document the blocked outcome"
echo "PASS: build_topup_prompt_v2"

# --- build_first_run_prompt_v2 ---
sample_pool='[{"product_id":"P2","sku_name":"Lively Underpad 60x90","merchant_name":"Reseller B","gmv":90000,"candidates":[{"taxonomy_id":"SKU-000099","canonical_name":"Lively Underpad 60x90cm x12","source_table":"shopee_th_adult_diapers","match_tier":"text_only","normalized_distance":0.2}]}]'
prompt=$(build_first_run_prompt_v2 "shopee_id_adult_diapers" "2026-06" "2000" "$sample_pool")
echo "$prompt" | grep -q "shopee_id_adult_diapers" || fail "build_first_run_prompt_v2 should mention the table"
echo "$prompt" | grep -qF "$sample_pool" || fail "build_first_run_prompt_v2 must embed the cross-market candidate JSON verbatim"
echo "$prompt" | grep -q "CASE WHEN flag_GWP THEN 0 ELSE" || fail "build_first_run_prompt_v2's brand-scope step must still zero GWP gmv"
echo "$prompt" | grep -q "never be used to decide whether an individual product gets extracted" || fail "build_first_run_prompt_v2 must forbid keyword pre-filtering of individual products"
echo "$prompt" | grep -q "pattern.*reference" || fail "build_first_run_prompt_v2 must frame sibling-table candidates as pattern reference, not direct-map targets"
echo "$prompt" | grep -q "status='blocked'" || fail "build_first_run_prompt_v2 should document the blocked outcome"
echo "PASS: build_first_run_prompt_v2"

# --- decide_queue_signal (ported verbatim from V1) ---
complete_output='{"result": "{\"status\": \"complete\", \"rows_created\": 5}"}'
[[ "$(decide_queue_signal "$complete_output")" == "DONE" ]] || fail "status=complete -> DONE"
blocked_output='{"result": "{\"status\": \"blocked\", \"blockers\": [\"x\"]}"}'
[[ "$(decide_queue_signal "$blocked_output")" == "BLOCKED" ]] || fail "status=blocked -> BLOCKED"
malformed_output='not json at all'
[[ "$(decide_queue_signal "$malformed_output")" == "FAILED" ]] || fail "unparseable output -> FAILED"
echo "PASS: decide_queue_signal"

# --- main() wiring (static check -- live bq/python/claude calls are out of scope here) ---
script_src=$(cat script/niq/headless_taxonomy_v2.sh)
grep -qF 'python3 script/niq/headless_v2_worklist.py --table "$table" --scenario "$scenario" --month "$month" --block-size "$block_size"' <<< "$script_src" || fail "main() must build the worklist via headless_v2_worklist.py with all four flags"
grep -qF 'if [[ "$worklist_json" == "[]" ]]; then' <<< "$script_src" || fail "main() must detect an empty worklist"
grep -qF 'echo "QUEUE_SIGNAL: NOTHING_TO_DO"' <<< "$script_src" || fail "main() must emit NOTHING_TO_DO when gap_count==0 or the worklist is empty"
grep -qF '<<< "$prompt"' <<< "$script_src" || fail "main() must pipe the prompt into claude -p via stdin, not argv (worklist JSON can exceed argv limits)"
grep -qF 'echo "QUEUE_SIGNAL: $(decide_queue_signal "$claude_output")"' <<< "$script_src" || fail "main() must emit the post-run signal derived from decide_queue_signal"
echo "PASS: main() wiring (static check)"

echo "ALL TESTS PASSED"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/niq/test_headless_taxonomy_v2.sh`
Expected: fails at `source script/niq/headless_taxonomy_v2.sh` — file doesn't exist yet

- [ ] **Step 3: Write `script/niq/headless_taxonomy_v2.sh`**

Create `script/niq/headless_taxonomy_v2.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: ./script/niq/headless_taxonomy_v2.sh <TABLE> [MONTH] [MAX_TURNS]
# Same scenario auto-detection as headless_taxonomy.sh (V1), but the worklist -- for BOTH scenarios -- is
# fully pre-built by script/niq/headless_v2_worklist.py before claude -p is ever invoked, with each product
# enriched with up to 5 reference candidates pulled from this table AND fuzzy-matched sibling category
# tables in other countries. See
# docs/superpowers/specs/2026-08-21-headless-taxonomy-v2-cross-market-candidates-design.md.
#
# V1 (headless_taxonomy.sh) is unmodified and still works exactly as before -- this is a new sibling script,
# not a replacement.

PROJECT="sincere-hearth-273704"

gap_count_query() {
  local table="$1" month="$2"
  cat <<SQL
SELECT COUNT(*) FROM (
  SELECT s.product_id
  FROM \`${PROJECT}.master_clean_niq.${table}\` s
  LEFT JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` ptm
    ON ptm.product_id = s.product_id AND ptm.master_table = '${table}'
  LEFT JOIN \`${PROJECT}.magpie_reference.product_taxonomy\` pt ON pt.taxonomy_id = ptm.taxonomy_id
  LEFT JOIN \`${PROJECT}.magpie_reference.category_scope_exceptions\` exc
    ON exc.product_id = s.product_id AND exc.master_table = '${table}'
  WHERE FORMAT_DATE('%Y-%m', s.month) = '${month}' AND pt.canonical_name IS NULL AND exc.product_id IS NULL
)
SQL
}

existing_llm_rows_query() {
  local table="$1"
  echo "SELECT COUNT(*) FROM \`${PROJECT}.magpie_reference.product_taxonomy_map\` WHERE master_table = '${table}' AND source = 'LLM'"
}

default_month_query() {
  local table="$1"
  echo "SELECT FORMAT_DATE('%Y-%m', MAX(month)) FROM \`${PROJECT}.master_clean_niq.${table}\`"
}

decide_scenario() {
  local existing_llm_rows="$1"
  if [[ "$existing_llm_rows" =~ ^[0-9]+$ ]] && [[ "$existing_llm_rows" -eq 0 ]]; then
    echo "first_run"
  else
    echo "top_up"
  fi
}

compute_block_size() {
  local scenario="$1" gap_count="$2"
  if [[ "$scenario" == "first_run" ]]; then
    echo 2000
    return
  fi
  local size="$gap_count"
  [[ "$size" =~ ^[0-9]+$ ]] || size=200
  [[ "$size" -lt 200 ]] && size=200
  [[ "$size" -gt 2000 ]] && size=2000
  echo "$size"
}

build_first_run_prompt_v2() {
  local table="$1" month="$2" block_size="$3" cross_market_json="$4"
  local slot_offset=$((block_size - 1))
  cat <<PROMPT
Full Rebuild session (V2) for ${table}, month ${month}. This is a first-run invocation — the wrapper's live
pre-check found 0 existing \`product_taxonomy_map\` rows for this table. No category context file exists yet
for this table — you are creating one as part of this run, not reading a pre-existing one.

BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/data-dictionary.md, docs/llm-extraction-rules.md, docs/quality-standards.md, docs/headless-runbook.md, docs/brand-extraction.md, and docs/categories/_TEMPLATE.md (the last one because you are about to fill it in — not in the original doc list, but required for this run specifically). Also run: SELECT status, updated_at FROM \`${PROJECT}.magpie_reference.category_brief\` WHERE category_key = 'master_clean_niq.${table}' AND task_type = 'BRIEF' to confirm ${table} hasn't already been completed by someone else since this prompt was written. No row, or a row with status IN ('not_started', 'reset_pending_redo'), means proceeding as a first run is still correct.

You perform extraction yourself, directly, using your own multimodal reading of product images and text. You do not invoke external scripts or subprocesses and do not need any API key beyond your own session auth — CLAUDE.md's ANTHROPIC_API_KEY note is about a different, external pipeline that does not exist in this repo.

STEP 0 — Verify the source table actually exists where you expect it, before anything else:
Run: SELECT COUNT(*) FROM \`${PROJECT}.master_clean_niq.${table}\` LIMIT 1
This pipeline is proven end-to-end for NIQ tables (master_clean_niq → marketshare_universe_niq). If ${table} isn't there, do NOT guess at intrepid_pipeline_clean_product_level or any other dataset — that data path is
unconfirmed and was the source of real problems in an earlier session. Treat 'source table not found where expected' as a genuine blocker: stop, status='blocked', explain what you found instead.

STEP 1 — Re-verify existing state before assuming anything about it (the wrapper's pre-check is a hint, not a fact — re-query live):
Run: SELECT source, COUNT(*) FROM \`${PROJECT}.magpie_reference.product_taxonomy_map\`
WHERE master_table = '${table}' GROUP BY source
Existing HUMAN rows here are normal and expected for a first LLM pass — most categories start with keyword-seed coverage before Phase 5 ever runs; do not treat their presence alone as a blocker. If you find any existing LLM rows, however, that means the wrapper's scenario detection was wrong (a genuine Phase 5 pass already happened on this table) — stop and report the discrepancy in findings rather than silently proceeding as a first run.

STEP 2 — Research and write docs/categories/${table}.md, following _TEMPLATE.md's structure:
- Brand Scope: compute the REAL cumulative-GMV 95% threshold for month = '${month}' — ORDER BY brand GMV DESC, running SUM, find where cumulative/total >= 0.95. Zero out flag_GWP=TRUE products' GMV in this cumulative calculation (CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END) — GWP products still get extracted like any other in-scope product, they just must not inflate the brand-GMV ranking. Do NOT just list the top 15-20 brands by magnitude and call that the 95% scope — that undercounted a real category's true brand universe by roughly 6x in an earlier session (~20 claimed vs. ~190 actual). List every brand in the real threshold, not a fixed-size snapshot.
- Official Store Allowlist: query DISTINCT merchant_name WHERE merchant_badge = 'Shopee Mall', per brand in scope. Exclude known multi-brand retailers per docs/llm-extraction-rules.md §4 (Sasa, Watsons, Boots, BEAUTRIUM, Tsuruha for beauty; BigC, Lotuss, Tops, Villa Market for grocery; check the full list in that doc for this category's vertical). Note parent-company stores (P&G, Unilever, Lion-style) as Pass-1-eligible for all brands they carry, not excluded as multi-brand. **This exact table is what a later V2 top-up/re-run session's worklist builder parses out of your markdown to exclude Pass-1-covered products from its candidate pool — keep it a real, well-formed markdown table (Brand | brand_id | Official Store Merchant Name columns, backtick-wrapped merchant names), not free text.**
- Scale: total row count, official-store row count, distinct product count. If official-store row count alone is large (tens of thousands+), say so explicitly — Pass 1 must still scope to the allowlist only, not the full Mall-badged pool.
- Existing map rows (from Step 1): document the real counts, not an assumption.
- Write your markdown to a local BRIEF row in \`${PROJECT}.magpie_reference.category_brief\` — never inline the markdown into a SQL string literal (it will contain backticks, quotes, and pipe characters that break a literal). Instead:
  1. Write it to /tmp/${table}_brief.ndjson as a single-line JSON object: {"category_key": "master_clean_niq.${table}", "task_type": "BRIEF", "source_dataset": "master_clean_niq", "master_table": "${table}", "country": "<2-3 letter country code parsed from ${table}>", "status": "active", "brief_markdown": "<your full markdown, JSON-string-escaped>", "updated_at": "<CURRENT_TIMESTAMP in ISO 8601 UTC>", "meta_agent": "CLAUDE_CODE"}
  2. Load it into a staging table: bq load --source_format=NEWLINE_DELIMITED_JSON --replace \`${PROJECT}:magpie_reference._stage_category_brief_${table}\` /tmp/${table}_brief.ndjson category_key:STRING,task_type:STRING,source_dataset:STRING,master_table:STRING,country:STRING,status:STRING,brief_markdown:STRING,updated_at:TIMESTAMP,meta_agent:STRING
  3. Merge it in: bq query --use_legacy_sql=false "MERGE \`${PROJECT}.magpie_reference.category_brief\` t USING \`${PROJECT}.magpie_reference._stage_category_brief_${table}\` s ON t.category_key = s.category_key AND t.task_type = 'BRIEF' WHEN MATCHED THEN UPDATE SET source_dataset=s.source_dataset, master_table=s.master_table, country=s.country, status=s.status, brief_markdown=s.brief_markdown, updated_at=s.updated_at, meta_agent=s.meta_agent WHEN NOT MATCHED THEN INSERT (category_key, task_type, source_dataset, master_table, country, status, brief_markdown, updated_at, meta_agent) VALUES (s.category_key, s.task_type, s.source_dataset, s.master_table, s.country, s.status, s.brief_markdown, s.updated_at, s.meta_agent)"
  4. Drop the staging table: bq rm -f -t \`${PROJECT}:magpie_reference._stage_category_brief_${table}\`
  Never use the streaming API (insert_rows_json) for this — CLAUDE.md's 90-minute streaming buffer rule.

STEP 3 — Claim your SKU block atomically. Query the real current ceiling first, then use this exact pattern (DECLARE before BEGIN TRANSACTION — reversing that order is a real syntax error in BigQuery scripting, found
the hard way in an earlier session):
BEGIN
  DECLARE next_start INT64;
  BEGIN TRANSACTION;
  SET next_start = (SELECT COALESCE(MAX(block_end), 69000) + 1 FROM \`${PROJECT}.magpie_reference.sku_block_registry\`);
  INSERT INTO \`${PROJECT}.magpie_reference.sku_block_registry\`
    (block_start, block_end, master_table, scenario, claimed_at, status)
  VALUES (next_start, next_start + ${slot_offset}, '${table}', 'full_rebuild', CURRENT_TIMESTAMP(), 'ACTIVE');
  COMMIT TRANSACTION;
END;
Claim ${block_size} slots — sized by the wrapper for a first-run category (products fragment into many near-unique SKUs, so a generous block avoids needing a supplemental claim mid-run). Never query MAX(taxonomy_id) directly and assume it's safe to use — the atomic claim is what prevents two sessions colliding on the same ID range.

STEP 4 — Pass 1: build taxonomy ONLY from the Official Store Allowlist merchant names you just wrote into the category file — not the full Mall-badged pool.

STEP 5 — Pass 2: the priority for Pass 2 is closing the coverage gap quickly, not per-row precision — quality correctness (exact product_line wording, variant capture, pack-count edge cases, D1-D5 of docs/quality-standards.md) is a separate, later concern owned by script/targeted_qa_fix.sh, scoped by GMV impact; do not spend this session's turns chasing it.

Below is your pre-fetched, GMV-sorted candidate pool for Pass 2 — every non-official-store product in the 95%-cumulative-GMV in-scope set, each enriched with up to 5 reference candidates pulled from OTHER already-QA'd category tables in different countries (this table has zero taxonomy entries at precompute time by definition, so every candidate here is cross-market — "source_table" names which sibling table it came from). These candidates are pattern/format reference only — how a same-brand product was typically split into product_line/sub_line/variant/size/pack_count in a sibling market — never a direct map target. A candidate's taxonomy_id belongs to a different country's category table; never write a product_taxonomy_map row pointing at it. Use it to inform how you mint or match against the entries YOUR Pass 1 just built in THIS session, not as a routing shortcut. Every product below is still subject to your own category/type match-or-create gate (docs/product-lifecycle.md §4.2) — a cross-market candidate never overrides that:

${cross_market_json}

Route these products in BULK via SQL text-matching of sku_name against the Pass 1 taxonomy you just built — group by brand+line pattern and write statements that map many products per statement, not one row at a time. Only read product images for individual products where text matching is genuinely ambiguous — do not vision-read the full candidate pool. This keyword/text-matching step is a routing convenience, never a scope filter: this keyword gate must never be used to decide whether an individual product gets extracted. Every product in the 95%-cumulative-GMV-or-official-store in-scope set (docs/quality-standards.md §2) must be considered — only your own category/type match-or-create gate (docs/product-lifecycle.md §4.2), applied after reading a product, may conclude it doesn't belong here and leave it NULL. This matters most for high-GMV Mall-seller listings that are genuinely miscategorized (their sku_name doesn't match the category's expected keywords even though the product itself belongs) — a text pre-filter would silently drop them before you ever looked. Hard gates G1 (no dual-mapping), G2 (no HUMAN+LLM coexistence), G4 (no cross-category mapping), and G5 (provenance) are structural invariants and must still pass regardless of this speed-first approach — never skip or relax those.

When your match-or-create gate concludes a product genuinely doesn't belong in this category — wrong product type, not a size/variant/pack ambiguity — don't just leave it NULL and move on: record that determination in bulk (one statement per reason-group, not per row) so it stops re-entering every future session's live worklist and coverage-gap count:
INSERT INTO \`${PROJECT}.magpie_reference.category_scope_exceptions\` (master_table, product_id, reason, confirmed_at, meta_agent)
SELECT '${table}', new_id, '<why it does not belong, e.g. wrong product type: cocoa powder listed under this liquid-milk table>', CURRENT_TIMESTAMP(), 'CLAUDE_CODE'
FROM UNNEST(['<product_id>', '<product_id>']) AS new_id  -- product_id is STRING — quote every element
WHERE new_id NOT IN (SELECT product_id FROM \`${PROJECT}.magpie_reference.category_scope_exceptions\` WHERE master_table = '${table}');
Only use this for products you are confident are the wrong type/category for this table — never for ones you simply didn't get to this session, and never to paper over a real coverage shortfall.

STEP 6 — For every taxonomy entry, populate product_line, sub_line, and variant as their own structured columns — do NOT leave them NULL while folding that same information into canonical_name as free text. product_line is close to mandatory (populate it whenever a real on-label line name exists, per docs/llm-extraction-rules.md §3); sub_line and variant are optional — populate only where a real signal exists, leave NULL rather than guess when the text doesn't clearly support a split. This was gotten wrong before: 934 entries once shipped with product_line NULL on 100% of them because the extraction wrote good canonical_name text but never decomposed it into the structured fields.

Write via bq query DML only, never the streaming API.

STEP 7 — Before declaring status, self-check using the exact QA-gate queries from docs/headless-runbook.md's QA-gate-as-code section, run with --skip-coexistence semantics (dual-mapped scoped to source='LLM', and placeholder-leak). Report the actual numbers in findings — do not just assert 'gates passed' without the figures.

If you hit a genuine blocker at any step — something wrong with these instructions, missing data, the source table not existing where expected, anything that would make proceeding unsafe — stop, write nothing further, and output status='blocked' with the blockers array populated. That is a valid, expected outcome, not a failure.

Output ONLY this JSON when done, nothing else:
{status: complete|partial|failed|blocked, rows_created, rows_mapped, taxonomy_id_range_used, findings, blockers}.
PROMPT
}

build_topup_prompt_v2() {
  local table="$1" month="$2" block_size="$3" gap_count="$4" worklist_json="$5"
  local slot_offset=$((block_size - 1))
  cat <<PROMPT
Top-up coverage session (V2) for ${table}, month ${month}. This category already has taxonomy coverage from a
prior run — the wrapper's live pre-check just found ${gap_count} products still within the 95%-cumulative-GMV
(GWP-zeroed) threshold with no taxonomy_id. Unlike V1, this number and the worklist itself are NOT something
you re-query yourself — both are pre-fetched below, GMV-sorted highest-priority-first.

BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/llm-extraction-rules.md, docs/quality-standards.md, docs/headless-runbook.md, docs/brand-extraction.md, and the existing category brief — run: SELECT brief_markdown FROM \`${PROJECT}.magpie_reference.category_brief\` WHERE category_key = 'master_clean_niq.${table}' AND task_type = 'BRIEF' (its brand scope, official store allowlist, and scope rules are already documented there; do not rediscover them from scratch).

You perform extraction yourself, directly, using your own multimodal reading of product images and text. You do not invoke external scripts or subprocesses and do not need any API key beyond your own session auth — CLAUDE.md's ANTHROPIC_API_KEY note is about a different, external pipeline that does not exist in this repo.

STEP 0 — Your worklist, pre-fetched below (do not re-run STEP 0's SQL yourself — this IS the live worklist, already pulled fresh by the wrapper's Python builder before this session started). Each product carries up to 5 reference candidates, ranked by text similarity, each tagged with a source_table and a match_tier:
- "source_table" equal to '${table}' itself = a direct reuse candidate, an existing entry in THIS category you can map straight to if it's a genuine match.
- "source_table" from a different table = a cross-market candidate (sibling category, different country). Pattern/format reference only — never map a product directly to a cross-market taxonomy_id.
- "match_tier": "brand_match" means the candidate shares a resolved brand_id with this product (stronger signal); "text_only" means no brand could be resolved and it's ranked by raw text similarity alone (weaker — verify more carefully).
Never trust a candidate without checking sku_name/image yourself when there's any doubt — these are reference context, never a basis for an autonomous decision.

${worklist_json}

STEP 1 — Bulk-first reuse-before-mint. The priority for this session is closing the coverage gap quickly, not per-row precision — quality correctness (exact product_line wording, variant capture, pack-count edge cases, D1-D5 of docs/quality-standards.md) is a separate, later concern: script/targeted_qa_fix.sh is the dedicated follow-up tool for that, scoped by GMV impact. Do not spend this session's turns chasing it.

Do NOT process the live worklist one product at a time — that under-uses this session's budget. Instead:
(a) For each worklist product, check its pre-attached candidates first. If an in-table candidate (source_table == '${table}') is an unambiguous match — same brand+line+size+pack, confirmed via sku_name/image if there's any doubt — bulk-map it: group worklist products by their matched candidate's taxonomy_id and write ONE UPDATE/INSERT per taxonomy_id covering every matching product, never per-row. Cross-market candidates never resolve a match directly — they inform (b) below.
(b) For worklist products with no unambiguous in-table candidate: group by brand+line pattern (via product_brand_map/brand_dict and sku_name) and mint ONE new taxonomy entry per group, mapping every matching product to it in one bulk statement — never process that group's products one by one. Use any cross-market candidates attached to these products as pattern/format reference (how was this brand/line typically split into product_line/sub_line/variant/size/pack_count in a sibling market) to keep your new entry's structure consistent with the sibling market's, not as something to copy the taxonomy_id from.
(c) Only read an individual product's image when text signals (sku_name, product_specification, product_description) are genuinely insufficient to identify brand or product line for minting a new entry. Even then, look for other unresolved worklist rows with a similar sku_name pattern and batch them under the same new entry rather than reading and minting one at a time. This is a routing convenience, never a scope filter: this keyword gate must never be used to decide whether an individual product gets extracted — every product in the live worklist gets considered. Only your own category/type match-or-create gate may conclude a product doesn't belong here and leave it NULL. This matters most for high-GMV Mall-seller listings that are genuinely miscategorized (their sku_name doesn't match the category's expected keywords even though the product itself belongs) — a text pre-filter would silently drop them before you ever looked.
(d) Attempt to resolve the ENTIRE live worklist within your available turn budget this session — do not self-limit to a small sample or match this category's older QA History session sizes. Stop early only when you are genuinely running low on turns, and say so honestly in findings — never as a strategic choice to work only the top of the list.
(e) When your match-or-create gate concludes a product genuinely doesn't belong in this category — wrong product type, not a size/variant/pack ambiguity — don't just leave it NULL and move on: record that determination in bulk (one statement per reason-group, not per row) so it stops re-entering every future session's live worklist and coverage-gap count:
INSERT INTO \`${PROJECT}.magpie_reference.category_scope_exceptions\` (master_table, product_id, reason, confirmed_at, meta_agent)
SELECT '${table}', new_id, '<why it does not belong, e.g. wrong product type: anti-hair-loss tonic listed under this conditioner table>', CURRENT_TIMESTAMP(), 'CLAUDE_CODE'
FROM UNNEST(['<product_id>', '<product_id>']) AS new_id  -- product_id is STRING — quote every element
WHERE new_id NOT IN (SELECT product_id FROM \`${PROJECT}.magpie_reference.category_scope_exceptions\` WHERE master_table = '${table}');
Only use this for products you are confident are the wrong type/category for this table — never for ones you simply didn't get to this session, and never to paper over a real coverage shortfall. If the scope call itself is genuinely ambiguous (could plausibly belong depending on a judgment call, not a clear-cut wrong type), don't except it — leave it NULL and escalate the ambiguity in findings instead, same as before.

Hard gates G1 (no dual-mapping), G2 (no HUMAN+LLM coexistence), G4 (no cross-category mapping), and G5 (provenance) are structural invariants and must still pass regardless of this speed-first approach — never skip or relax those.

STEP 2 — Claim a ${block_size}-slot SKU block atomically (DECLARE before BEGIN TRANSACTION — reversing that order is a real BigQuery scripting syntax error):
BEGIN
  DECLARE next_start INT64;
  BEGIN TRANSACTION;
  SET next_start = (SELECT COALESCE(MAX(block_end), 69000) + 1 FROM \`${PROJECT}.magpie_reference.sku_block_registry\`);
  INSERT INTO \`${PROJECT}.magpie_reference.sku_block_registry\`
    (block_start, block_end, master_table, scenario, claimed_at, status)
  VALUES (next_start, next_start + ${block_size} - 1, '${table}', 'taxonomy_topup', CURRENT_TIMESTAMP(), 'ACTIVE');
  COMMIT TRANSACTION;
END;
Never query MAX(taxonomy_id) directly and assume it's safe to use — this atomic claim against the registry table is what prevents two sessions colliding on the same ID range.

STEP 3 — Write via bq query DML only, never the streaming API. Set meta_agent='CLAUDE_CODE' on every row you write or update. Never delete an existing row.

STEP 4 — Record a dated run-log entry summarizing what you did and found this session, via a single parameterized INSERT (never build the SQL string by concatenating your own finding text into it directly — that breaks on quotes/backticks; use --parameter so bq handles escaping):
bq query --use_legacy_sql=false --project_id=${PROJECT} \
  --parameter="category_key:STRING:master_clean_niq.${table}" \
  --parameter="task_date:DATE:<today, YYYY-MM-DD>" \
  --parameter="brief_markdown:STRING:<your summary of what you did and found this session>" \
  "INSERT INTO \`${PROJECT}.magpie_reference.category_brief\` (category_key, task_type, task_date, brief_markdown, updated_at, meta_agent) VALUES (@category_key, 'TAXONOMY', @task_date, @brief_markdown, CURRENT_TIMESTAMP(), 'CLAUDE_CODE')"

STEP 5 — Before declaring status, self-check using the exact QA-gate queries from docs/headless-runbook.md's QA-gate-as-code section, run WITHOUT --skip-coexistence (HUMAN+LLM coexistence should be a genuine bug at this point, not an expected mid-rebuild state, since this category already shipped once). Report the actual numbers in findings.

Do NOT run the universe refresh yourself — that is a separate step, run only after independent QA verification, not something this session does.

If you hit a genuine blocker at any step — something wrong with these instructions, missing data, anything that would make proceeding unsafe — stop, write nothing further, and output status='blocked' with the blockers array populated. That is a valid, expected outcome, not a failure.

Output ONLY this JSON when done, nothing else:
{status: complete|partial|failed|blocked, rows_created, rows_mapped, taxonomy_id_range_used, findings, blockers}.
PROMPT
}

extract_json_object() {
  local text="$1"
  printf '%s' "$text" | grep -Pzo '(?s)\{.*\}' | tr -d '\0'
}

decide_queue_signal() {
  local claude_output="$1"
  local result_json
  result_json=$(echo "$claude_output" | jq -r '.result // empty') || result_json=""
  if [[ -z "$result_json" ]]; then
    echo "FAILED"
    return
  fi
  if ! echo "$result_json" | jq -e . >/dev/null 2>&1; then
    local extracted
    extracted=$(extract_json_object "$result_json")
    if [[ -n "$extracted" ]] && echo "$extracted" | jq -e . >/dev/null 2>&1; then
      result_json="$extracted"
    fi
  fi
  local status
  status=$(echo "$result_json" | jq -r '.status // empty' 2>/dev/null) || status=""
  case "$status" in
    blocked) echo "BLOCKED" ;;
    complete|partial) echo "DONE" ;;
    *) echo "FAILED" ;;
  esac
}

main() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <TABLE> [MONTH] [MAX_TURNS]" >&2
    exit 1
  fi
  local table="$1"
  local month="${2:-}"
  local max_turns="${3:-300}"

  if [[ -z "$month" ]]; then
    month=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
      "$(default_month_query "$table")" | tail -1)
  fi

  echo "${table}"
  echo "Resolved month: ${month}"

  local gap_count
  gap_count=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "$(gap_count_query "$table" "$month")" | tail -1)

  if [[ "$gap_count" == "0" ]]; then
    echo "No in-scope coverage gap for ${table}/${month} — nothing to do."
    echo "QUEUE_SIGNAL: NOTHING_TO_DO"
    exit 0
  fi

  local existing_llm_rows
  existing_llm_rows=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "$(existing_llm_rows_query "$table")" | tail -1)

  local scenario
  scenario=$(decide_scenario "$existing_llm_rows")

  local block_size
  block_size=$(compute_block_size "$scenario" "$gap_count")

  echo "Scenario: ${scenario} (existing_llm_rows=${existing_llm_rows}, gap_count=${gap_count}, block_size=${block_size}, max_turns=${max_turns})"
  echo "Building candidate-enriched worklist for ${table}..."

  local worklist_json
  worklist_json=$(python3 script/niq/headless_v2_worklist.py --table "$table" --scenario "$scenario" --month "$month" --block-size "$block_size")

  if [[ "$worklist_json" == "[]" ]]; then
    echo "No worklist products for ${table} after candidate build — nothing to do."
    echo "QUEUE_SIGNAL: NOTHING_TO_DO"
    exit 0
  fi

  echo "TAXONOMY EXTRACTION STARTED (V2)"
  echo "==========================="

  local prompt
  if [[ "$scenario" == "first_run" ]]; then
    prompt=$(build_first_run_prompt_v2 "$table" "$month" "$block_size" "$worklist_json")
  else
    prompt=$(build_topup_prompt_v2 "$table" "$month" "$block_size" "$gap_count" "$worklist_json")
  fi

  local claude_output
  # Piped via stdin, not passed as a CLI argument: this prompt embeds the full candidate-enriched worklist
  # JSON and can exceed the kernel's argv size limit (E2BIG) well before it gets near a real token-budget
  # concern — same reasoning as targeted_qa_fix_v2.sh.
  claude_output=$(claude -p --output-format json --permission-mode bypassPermissions --max-turns "$max_turns" <<< "$prompt")
  echo "$claude_output"

  echo "============================"
  echo "TAXONOMY EXTRACTION FINISHED (V2)"
  echo "QUEUE_SIGNAL: $(decide_queue_signal "$claude_output")"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/niq/test_headless_taxonomy_v2.sh`
Expected: `ALL TESTS PASSED`

- [ ] **Step 5: Add a pointer note to `docs/headless-runbook.md`**

Read `docs/headless-runbook.md` first to find its script-listing section (likely near the top, alongside
where `headless_taxonomy.sh` and `targeted_qa_fix.sh` are introduced), then add one short paragraph there:

```markdown
**V2 available:** `script/niq/headless_taxonomy_v2.sh` is a newer sibling that pre-fetches a
candidate-enriched worklist (including reference candidates from sibling category tables in other
countries) before `claude -p` runs, same pattern as `targeted_qa_fix_v2.sh`. See
`docs/superpowers/specs/2026-08-21-headless-taxonomy-v2-cross-market-candidates-design.md`. V1
(`headless_taxonomy.sh`, documented below) still works unchanged; V2 is not yet the default.
```

- [ ] **Step 6: Manual end-to-end smoke test against real BigQuery**

```bash
./script/niq/headless_taxonomy_v2.sh shopee_id_adult_diapers 2026-06 20
```

Expected: prints the resolved scenario (`top_up`, since this table has existing LLM coverage from the
earlier session), builds the worklist via `headless_v2_worklist.py`, then runs a real (small, `max_turns=20`)
`claude -p` session. This will make real writes if the gap is nonzero — run it, watch the output, and
confirm it doesn't error before considering this task done. `Ctrl-C` after the worklist prints if you only
want to confirm wiring without spending a real session's turns.

- [ ] **Step 7: Commit**

```bash
git add script/niq/headless_taxonomy_v2.sh tests/niq/test_headless_taxonomy_v2.sh docs/headless-runbook.md
git commit -m "Add headless_taxonomy_v2.sh wrapper with cross-market candidate-enriched prompts"
```

---

## Plan Self-Review Notes

- **Spec coverage:** §1 sibling discovery → Task 1. §2 candidate query → Task 2. §3 worklist builder → Tasks
  1-4 combined (matches spec's single-file convention). §4 wrapper + prompt changes → Task 5. §5 testing →
  each task's own test file, matching the spec's named test files exactly. Open verification items (Jaccard
  threshold, `EDIT_DISTANCE` behavior, brief-parsing robustness) → Task 2 Step 6 (dry-run) and Task 4 Step 5
  (end-to-end smoke test) exercise these against real data before the plan is considered done.
- **Deferred items** (manual sibling override, cross-platform matching, maintained mapping table) are
  correctly out of scope — no task references them.
