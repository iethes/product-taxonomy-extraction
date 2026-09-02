# Handoff: eiger image-taxonomy QA

> Self-contained — assumes no context from the session that built this. If you're reading this
> to run or maintain `script/non_niq/eiger_qa.sh`, or to hook it into a Windmill-driven task
> queue, this is everything you need. Full design rationale:
> [`docs/superpowers/specs/2026-09-02-eiger-image-taxonomy-qa-design.md`](superpowers/specs/2026-09-02-eiger-image-taxonomy-qa-design.md).

## What this is

`eiger` (Outdoor Equipment & Supplies, ID, platforms lazada/shopee/tiktok/tokopedia) is a
non-NIQ agentic QA category like `cookiesbiscuit`/`babybath`/etc., run via
`script/non_niq/non_niq_qa_v2.sh` for every other dataset — **except eiger has no free-text
taxonomy dict table**, so it gets its own script, `script/non_niq/eiger_qa.sh`:

```
script/non_niq/eiger_qa.sh <PLATFORM> [COUNTRY] [MAX_TURNS] [MAX_ROWS]
# e.g. script/non_niq/eiger_qa.sh shopee ID 300 300
```

If you already know `non_niq_qa_v2.sh`: the worklist materialization shape (Tier-1 scoped,
priority 0/1 via `_meta.qa_confidence`, filter-table exclusion), the retry-once confidence loop,
and the `_meta` JSON conventions are identical. What's different is STEP 1 (the Meilisearch
corpus) and STEP 2 (how a product gets categorized) — see below.

## Real table names (the Sheet is wrong/incomplete for two of these)

| Concept | v2's Sheet column | eiger's real table | Notes |
|---|---|---|---|
| Source (Tier-1 scoped) | `master_table_prod` | `eiger.master_eiger_id` | Correctly configured in the Sheet |
| QA output | `product_id_dict_qa` | `eiger.product_id_dict_image_qa` | Sheet's `product_id_dict_qa` is `-`; the real table lives under the Sheet's `product_id_dict_image_qa` column, which `non_niq_helper.py`'s `ROW_FIELDS` doesn't read yet — `eiger_qa.sh` hardcodes the table name as a constant instead |
| Taxonomy dict | `dict` | *(none)* | eiger has no free-text dict table at all — see below |
| Filter/exclusion | `filter_table` | `eiger.filter_eiger` | Correctly configured in the Sheet |

`eiger.product_id_dict` does not exist in BigQuery. `eiger.product_id_dict_image` exists but is
sparse and unused by this pipeline — don't confuse it with `product_id_dict_image_qa`.

## `eiger.product_id_dict_image_qa` schema

`product_id, ecommerce_platform, brand, sku_name, sku_type_complete, vlookup, mgh_2, mgh_3,
mgh_4, product_type, image, keywords, color, _meta, timestamp, gender`

Insert-only (many historical rows per product, same convention as every other dataset's QA
table). `vlookup`, `color`, `gender` are unused by `eiger_qa.sh` — always left NULL. 30,083
existing rows are from a prior human-QA-freelance process; ~42% have NULL or placeholder
(`'-'`, `'{Defining Process}'`) `sku_type_complete` — those are pre-existing gaps, not something
this script backfills.

## Categorization rule: guidance-doc tree, not free text

`docs/eiger_labelling_guidance.csv` (1061 rows, columns `mgh_2, mgh_3, mgh_4, product_type,
Product Style`) is the ONLY valid source of category values. A product's `mgh_2 → mgh_3 → mgh_4
→ product_type → Product Style` path must be one that actually exists as a row in this CSV —
never free-typed at any level. The CSV's own catch-all leaf values (`Not assigned`, `N/A`,
`Mix`) mean there is always a valid Product Style once the four-level path is right. Product
Style gets written to both `sku_type_complete` and `keywords` on the QA table.

## Brand rule: `eiger.brand_store_product_fix` for known multi-brand resellers only

`eiger.brand_store_product_fix` (`brand_store, brand, url, ...`, 203 rows / 119 stores / 179
brands) is a strict override list for a small set of stores — like "Decathlon" — that sell many
different sub-brands under one storefront. If a product's `brand_store` appears in this table,
its brand MUST come from this table (matched by `url` first, else by disambiguating among that
store's listed brands using the product's own image/text). For every other store (the large
majority — only ~20 of eiger's ~250 Tier-1 merchants are covered here), brand comes from normal
image/text judgment, same as any other dataset. This table is read-only reference data — never
write to it or try to expand its coverage.

## Meilisearch: one-time corpus backfill

Index name: `eiger_taxonomy_qa`. It starts empty — before running `eiger_qa.sh` for the first
time, seed it from the existing (human-labelled) QA rows, filtered to ones with a real
categorization (verified live: 16,738 rows currently qualify):

```sql
SELECT product_id, sku_name, brand, product_type, sku_type_complete, mgh_2, mgh_3, mgh_4
FROM `sincere-hearth-273704.eiger.product_id_dict_image_qa`
WHERE product_type IS NOT NULL
  AND sku_type_complete NOT IN ('-', '{Defining Process}')
QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY timestamp DESC NULLS LAST) = 1
```

Run it, save the output as JSONL (one row per line), then:

```bash
.venv/bin/python3 script/non_niq/non_niq_helper.py index \
  --input-file <backfill.jsonl> --meili-index eiger_taxonomy_qa
```

This is a real write to a shared Meilisearch instance (`http://34.124.146.29:7700`) — run it
once, deliberately, not as part of any automated pipeline. Going forward, `eiger_qa.sh`'s own
STEP 3 keeps the index updated incrementally after every session (newly-confident rows only).

## What was deliberately NOT done

- `non_niq_helper.py`'s `ROW_FIELDS` still doesn't read the Sheet's `product_id_dict_image_qa`/
  `product_id_image_taxonomy` columns — `eiger_qa.sh` hardcodes the real QA table name as a
  constant instead. If you "fix" `ROW_FIELDS` later, update `eiger_qa.sh`'s `QA_TABLE` constant
  to read from the Sheet too, or the two will drift.
- `eiger.brand_store_product_fix`'s coverage gap (20/250 Tier-1 stores) is not addressed —
  accepted as-is per explicit product decision.
- Legacy `product_id_dict_image_qa` rows with placeholder/NULL `sku_type_complete` (~42%) are
  not backfilled or corrected — out of scope, `eiger_qa.sh` only processes the current Tier-1
  worklist going forward.
- No wiring into `script/non_niq/queue_worker.sh` or the task-queue submitter UI — this script is
  run directly for now (`script/non_niq/eiger_qa.sh <platform> ...`), same as any other
  dataset's script before it's queue-integrated.
