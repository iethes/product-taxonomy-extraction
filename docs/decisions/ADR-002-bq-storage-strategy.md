# ADR-002: BigQuery Storage Strategy

**Date:** 2026-05-30
**Status:** Accepted

---

## Context

We need to decide where to store the taxonomy tables and the marketshare universe. The existing stack uses Google Sheets as a database for configuration and mapping data, and BigQuery for raw/processed tables.

---

## Decision

**Dataset layout in `sincere-hearth-273704`:**

| Dataset | Purpose | Tables |
|---------|---------|--------|
| `master_clean_niq` | Source layer (existing) | 43 shopee tables |
| `shopee` | Raw layer (existing) | category trees, etc |
| `magpie_reference` | Reference / taxonomy layer (NEW) | `brand_dict`, `product_brand_map` |
| `magpie_universe` | Analytics layer (NEW) | `marketshare_universe` |

**`brand_dict`** is small (~thousands of rows) and human-curated. It will be:
- Primarily edited via a Google Sheets tab (human-friendly)
- Synced/mirrored to BQ at pipeline run time
- The BQ copy is the runtime source of truth for joins

**`product_brand_map`** is large (millions of rows, growing). It lives in BQ only.

**`marketshare_universe`** is the final analytics table. Partitioned by `month`, clustered by `country` and `magpie_category_3`.

---

## Alternatives Considered

**Storing product_brand_map in Google Sheets:** Rejected. Sheets hard limit is 10M cells. At 1.2M products × 10 columns = 12M cells already over limit. Performance degrades severely past ~500K rows.

**Single dataset for everything:** Rejected. Mixing raw source tables with reference and analytics tables in one dataset makes access control impossible (different teams need different permissions) and makes the data lineage unclear.

---

## Consequences

- Clear separation: raw → reference → analytics, each in its own dataset
- `magpie_reference` can be granted read-only to analysts without exposing raw data
- BQ clustering on `(master_table, product_id)` makes brand lookup joins cheap even at scale
- Need a sync script to push Sheets `brand_dict` edits into BQ
