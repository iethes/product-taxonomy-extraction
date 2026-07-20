# Design: Product Taxonomy Exploration Notebook

> Status: approved design, not yet implemented.

## Purpose

A Colab notebook, `notebooks/product_taxonomy_exploration.ipynb`, giving an analyst/stakeholder view of
`product_taxonomy` + `product_taxonomy_map` results across **all extracted categories, TH and SG combined**.
Answers "what does the taxonomy look like overall, and how much of the business does it actually cover" —
not a QA pass/fail tool (that's `script/qa_report.sh`), but a descriptive/exploratory companion, same spirit
as the existing `notebooks/taxonomy_match_exploration.ipynb`.

## Environment & conventions

Follows `notebooks/taxonomy_match_exploration.ipynb`'s established pattern exactly:
- Colab, `google.colab.auth.authenticate_user()` then `bigquery.Client(project="sincere-hearth-273704")`
- `matplotlib` for charts (not plotly/seaborn — stay consistent with the existing notebook)
- One `## N. Section Title` markdown cell per section, SQL as a named `..._SQL` string constant in its own
  cell followed by a `client.query(...).to_dataframe()` cell, charts as their own cells with a one-line
  comment explaining what to look for
- Query the dataviz skill's guidance when actually styling charts (colors, axis labels, chart-type choice)
  during implementation — not re-litigated in this spec

## Data sources

- `magpie_reference.product_taxonomy` — SKU entries (brand_id, product_line, sub_line, variant, canonical_name,
  size, pack_count, is_multi_size, is_multi_variant, is_bundle, meta_agent, created_at)
- `magpie_reference.product_taxonomy_map` — product→SKU mappings (product_id, master_table, platform, country,
  taxonomy_id, source, confidence, brand_mismatch, meta_agent, mapped_at) — confirmed to carry `platform`/
  `country` columns per the ADR-006 composite key, even though `ARCHITECTURE.md`'s table doc omits them
- `magpie_reference.brand_dict` — brand_id → canonical brand name
- `magpie_reference.universe_taxonomy_overlay` joined to `magpie.marketshare_universe_niq` (latest month) —
  for GMV-coverage-by-category, following the same join pattern as `AGENTS.md`'s Universe Refresh Pattern

One primary query joins `product_taxonomy_map` → `product_taxonomy` → `brand_dict` and is reused (via pandas
filtering) across most sections, to avoid re-querying BigQuery per chart. GMV coverage uses a second, separate
query against the overlay + `marketshare_universe_niq`.

## Sections

**1. Headline dashboard**
- Printed summary: total SKUs, total mapped products, categories extracted, countries covered, overall GMV
  covered by taxonomy vs. total universe GMV (latest month)
- Bar chart: GMV coverage % per category (`master_table`), sorted descending, colored by country
- Bar chart: SKU count per category

**2. Taxonomy composition**
- Products-per-SKU ratio (mapped products ÷ distinct SKUs), overall and per category
- Histogram: products mapped per SKU (long-tail check)
- Bar charts: top-N brands by SKU count, and by mapped-product count
- Bar charts: `meta_agent` breakdown (CLAUDE_CODE / CODEX / HUMAN) and `source` breakdown (LLM / HUMAN)

**3. Quality signals** (descriptive, not pass/fail — `qa_report.sh` owns hard gates)
- Confidence score histogram for LLM-sourced rows
- Prevalence bar chart: `is_multi_size` / `is_multi_variant` / `is_bundle` / `pack_count > 1`
- NULL `size` rate, excluding legitimate multi-size entries
- `brand_mismatch = TRUE` rate
- **Canonical name word-count check:** histogram of `canonical_name` word counts (whitespace-split token
  count), plus a bar chart of cumulative count where `word_count <= n` for every `n` in 1..10 — a short name
  is a proxy for a dropped `product_line`/`variant`/`size` field, useful as an at-a-glance completeness signal
  without hardcoding one threshold

**4. Growth over time**
- Cumulative SKU count by `product_taxonomy.created_at` — pipeline velocity/history

**5. Per-category comparison table**
- One row per `master_table`: SKU count, mapped products, GMV coverage %, avg confidence, distinct brand
  count, top brand — a data-driven counterpart to `docs/categories/STATUS.md`

## Out of scope

- Replacing `script/qa_report.sh`'s hard-gate pass/fail checks
- Per-category deep-dives / parameterized single-category drill-down (may be a follow-up notebook)
- Writing back to BigQuery — read-only exploration only
