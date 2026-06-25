# Product Taxonomy Extraction — Shopee TH & SG Brand/Product Harmonization Pipeline

**Owner:** Magpie Analytics  
**Built by:** Magpie Analytics × Claude Code (Anthropic)  
**BQ Project:** `sincere-hearth-273704`  
**Status:** Phase 5 LLM extraction active — 20/20 TH categories complete, SG seeded at keyword level

---

## What This Is

A BigQuery data pipeline that transforms raw Shopee e-commerce data (43 FMCG/Beauty product categories across Shopee SG and Shopee TH) into a clean, brand-resolved, product-taxonomy-enriched market share dataset.

**Business purpose:** Brands and their agencies need reliable market share data for Shopee — who is winning, at what price points, which SKUs are growing. The raw data from Shopee has inconsistent brand labeling, no product hierarchy, and no canonical product names. This pipeline fixes that.

**Output table:** `sincere-hearth-273704.magpie.marketshare_universe` (mirrored to `magpie-farsight.universe.marketshare_universe`)

---

## Pipeline at a Glance

```
Raw Shopee data (master_clean_niq.shopee_{country}_{category})
        │
        ├── Stage 01: Brand Audit
        │   Identify all unique brands per category, find duplicates
        │
        ├── Stage 02: Taxonomy Build  
        │   Build canonical brand_dict (19,700 brands), resolve duplicates
        │
        ├── Stage 03: Product Mapping
        │   Map every product_id → brand_id (1.2M products, product_brand_map)
        │
        ├── Stage 04: Universe Append
        │   Join source data + brand mappings → marketshare_universe (9.96M rows)
        │
        └── Stage 05: Product Taxonomy (LLM Multimodal)
            Map every product_id → canonical product name + size + pack_count
            (product_taxonomy + product_taxonomy_map)
```

---

## Current Coverage (as of Jun 2026)

| Country | Categories | LLM Extraction | Keyword Seed | GMV Coverage |
|---------|-----------|----------------|--------------|--------------|
| TH | 20 | ✅ Complete (all 20) | ✅ Done | 75–93% per category |
| SG | 23 | ⏳ In progress | ✅ Done (85/90/95%) | ~50–70% (keyword only) |

**TH Categories with full LLM extraction:**
body_wash · shampoo · conditioner · cleanser · moisturizer_for_face · moisturizer_for_body · suncare · make_up_face · toothpaste · toothbrush · baby_diapers · adult_diapers · liquid_milk · milk_powder · pet_food · coffee · detergent · fabric_softener · drinking_water · softdrink

See [`docs/categories/STATUS.md`](docs/categories/STATUS.md) for per-category GMV coverage, SKU ranges, and QA status.

---

## Repository Structure

```
├── README.md                        ← You are here
├── ARCHITECTURE.md                  ← System design, BigQuery layout, data flow
├── AGENTS.md                        ← Guide for AI agents collaborating on this pipeline
├── docs/
│   ├── data-dictionary.md           ← All table schemas with column descriptions
│   ├── llm-extraction-rules.md      ← Universal rules for LLM taxonomy extraction
│   ├── runbook.md                   ← Step-by-step operational guide per stage
│   ├── quality-standards.md         ← QA review process: 6 quality dimensions, scope, gates, scorecard
│   ├── decisions/                   ← Architecture Decision Records (ADR-001 to ADR-005)
│   ├── plans/                       ← Phase planning docs
│   └── categories/
│       ├── STATUS.md                ← All categories at a glance
│       ├── _TEMPLATE.md             ← Standard template for category context
│       └── th_{category}.md         ← Per-category: brands, stores, scope, edge cases
├── pipeline/
│   ├── 01_brand_audit/              ← brand_audit.py
│   ├── 02_taxonomy_build/           ← build_brand_dict.py, detect_duplicates.py
│   ├── 03_product_mapping/          ← build_product_brand_map.py
│   ├── 04_universe_append/          ← build_marketshare_universe.py
│   └── 05_product_taxonomy/         ← LLM extraction scripts per category
│       └── llm_th_{category}/
├── sql/schema/                      ← DDL for all BQ tables
├── config/
│   └── tables.py                    ← All 43 source table names
└── requirements.txt
```

---

## Quick Start (new collaborator)

### Prerequisites

```bash
# Python — must use this version (has google-auth, pandas, BQ client)
/Users/magpie/.pyenv/versions/3.8.12/bin/python3

# BQ CLI — full path required
/Users/magpie/google-cloud-sdk/bin/bq

# Service account key (NOT in git — get from team)
cp "/path/to/Magpie OpenClaw.json" /tmp/brand_audit_creds.json

# API key for LLM extraction (Phase 5 only)
export ANTHROPIC_API_KEY="sk-ant-..."

# Verify BQ access
/Users/magpie/google-cloud-sdk/bin/bq query \
  --project_id=sincere-hearth-273704 --nouse_legacy_sql \
  "SELECT COUNT(*) FROM \`sincere-hearth-273704.magpie.marketshare_universe\`"
```

### What to read first

1. [`ARCHITECTURE.md`](ARCHITECTURE.md) — understand the data model (15 min)
2. [`docs/product-lifecycle.md`](docs/product-lifecycle.md) — how one product flows from raw listing → brand → taxonomy → universe, incl. the match-or-create decision
3. [`docs/data-dictionary.md`](docs/data-dictionary.md) — understand every table and column
4. [`docs/categories/STATUS.md`](docs/categories/STATUS.md) — see what's done and what needs work
5. [`docs/llm-extraction-rules.md`](docs/llm-extraction-rules.md) — mandatory before running any Phase 5 extraction
6. [`docs/quality-standards.md`](docs/quality-standards.md) — the QA review process: 6 quality dimensions, in-scope definition, hard gates, scorecard — mandatory before reviewing/shipping any run

---

## Key Constants

```python
BQ_PROJECT   = 'sincere-hearth-273704'
BQ_SOURCE    = 'sincere-hearth-273704.master_clean_niq'        # raw Shopee data
BQ_REFERENCE = 'sincere-hearth-273704.magpie_reference'        # brand_dict, product_brand_map
BQ_UNIVERSE  = 'sincere-hearth-273704.magpie'                  # marketshare_universe output
BQ_RAW_HIST  = 'sincere-hearth-273704.raw_niq_history'         # product_specification, product_description
BQ_FARSIGHT  = 'magpie-farsight.universe'                      # downstream mirror
SHEETS_ID    = '1MvJdpoccc63AMs8D0qShI7PhKZ2BrrJJP-kwvDbh40M' # brand_audit working sheet
```

---

## Data Scale

| Table | Rows | Notes |
|-------|------|-------|
| `master_clean_niq.*` | ~200M+ | 43 source tables, model-level grain |
| `brand_dict` | 19,714 | Canonical brands, global + SG + TH scopes |
| `product_brand_map` | 1,229,806 | Every product → brand_id |
| `marketshare_universe` | ~9.96M | Jun 2025–Apr 2026, 11 months |
| `product_taxonomy` | ~15,000 | Canonical product entries (SKU-XXXXXX IDs) |
| `product_taxonomy_map` | ~140,000 | Every product → taxonomy entry |

---

## What Makes This Hard

1. **Thai brand names** — same brand appears as `Vaseline`, `vaseline`, `Vaseline(วาสลีน)`, `วาสลีน` in the raw data
2. **Shared official stores** — P&G sells Pantene + Head & Shoulders + Rejoice from one store; Unilever sells Dove + Clear + Sunsilk from one store. Brand disambiguation requires reading product images.
3. **Pack-count extraction** — Thai promo language (`ซื้อ 2 แถม 1`, `ยกลัง 48 ซอง`, `[แพ็ก12] ยกลังx3`) creates significant ambiguity between genuine multipacks and GWP (gift-with-purchase).
4. **Category scope ambiguity** — `shopee_th_body_wash` contains hand wash, feminine wash, baby shampoo, and body wash. Scope must be enforced per-product, not per-table.
5. **product_id is NOT globally unique** — composite key is always `(product_id, master_table)`.

---

## Credentials & Security

- Service account key `Magpie OpenClaw.json` — **never commit**. Copy to `/tmp/` before running.
- `ANTHROPIC_API_KEY` — for Phase 5 LLM extraction. Set as environment variable, never hardcode.
- BQ uses ADC (Application Default Credentials) for cross-project access to `magpie-farsight`.

---

## Contact / Handoff

**Magpie Analytics** — admin@magpie.co.id  
Built with Claude Code (Anthropic). Session history and detailed per-session notes in CLAUDE.md (internal, not in this repo).
