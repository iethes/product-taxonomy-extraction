# Size Regex Pass — Discovery Findings

Run date: 2026-07-14
Latest month partition found (1a): 2026-05-01
Bytes processed (largest single block, from dry-run): ~2.72GB (1b/1e), ~3.2MB (1d)

## Live schema drift found during this task (not anticipated by the design/plan)

`magpie.marketshare_universe`'s live schema does **not** match `sql/schema/marketshare_universe.sql` or
`ARCHITECTURE.md`: no `master_table`, `taxonomy_id`, `brand_id`, `model_count`, or `magpie_category_*`
columns. Live columns include `category_1/2/3`, `ecommerce_platform`, `merchant_*`, raw price/GMV fields,
`sku_type_complete`, and a single `brand` STRING — a different, apparently broader/older or differently-evolved
table than what the schema files describe. All discovery queries below were corrected in-flight to use the
live column set. `sql/schema/marketshare_universe.sql` should be treated as aspirational/stale, not
authoritative, until someone reconciles it — **out of scope for this plan, flagged for a separate session.**

Join key used (corrected from the plan's original `master_table`-based join, which doesn't exist in the live
table): `product_id + country + ecommerce_platform = platform` — this is exactly ADR-006's composite key
`(product_id, platform, country)`, which turns out to be the *more correct* join key per that ADR's own stated
invariant (`master_table` is metadata-only, not part of the key). `product_taxonomy_map`'s schema does match
its documented version, including `platform`/`country` columns.

## Country breakdown (1b)

| country | row_count | sku_name_populated |
|---|---:|---:|
| ID | 5,178,148 | 5,178,069 |
| TH | 430,959 | 430,959 |
| SG | 157,062 | 157,062 |
| PH | 148,182 | 148,182 |
| MY | 135,338 | 135,338 |
| VN | 115,776 | 115,776 |

All 6 Intrepid countries are live in `marketshare_universe` today — ID alone is ~12x the size of TH. This
directly contradicts `ARCHITECTURE.md`'s documented NIQ-only (SG/TH) scope for this table; Intrepid data (or
something broader) is already flowing into it, undocumented.

## ID sample plausibility (1c)

Sampled 20 `country='ID'` rows — all genuine Indonesian Shopee refrigerator ("Kulkas") listings, e.g.:
`"Changhong Kulkas 2 Pintu (Refrigerator) Kulkas No Frost Tanpa Bunga Es Lemari Es Kapasitas 220 Liter
FTM280NB - Black"`. Confirms real, plausible Indonesian marketplace text — not mislabeled TH/SG data. This
matches the original reported bug's category (appliances) and language pattern (`Kapasitas` = capacity)
exactly.

## Eligible NULL-size counts (1d)

| country | eligible_null_size_taxonomy_ids |
|---|---:|
| TH | 2,454 |
| ID | **0** |

## Join resolvability (1e, TH only — ID has nothing to resolve)

| country | eligible | resolvable_via_universe |
|---|---:|---:|
| TH | 2,454 | 1,549 |

(905 eligible TH rows have no matching row in the 2026-05-01 partition — likely no sales that month; not a bug,
just outside this pass's reach until/unless a wider month range is joined.)

## Decision

ID_SCOPE_CONFIRMED: **no — not in the way the design assumed**

ID data is real and enormous (5.17M rows, genuine Indonesian appliance listings), but **zero** of it has ever
gone through `product_taxonomy_map` — there is no taxonomy mapping layer for ID at all yet. This plan's
mechanism (UPDATE `product_taxonomy.size` via a `product_taxonomy_map` join) has **zero rows to act on** for
ID, regardless of how good the regex is. The originally-reported bug
(`"No Brand Washing Machine Undefined Undefined"`) lives in `marketshare_universe.sku_type_complete` directly,
written by some process that bypasses `product_taxonomy`/`product_taxonomy_map` entirely — a different,
undocumented data path this plan was never scoped to touch.

**Proceeding TH-only for Task 3, as originally hedged in the plan's Task 3 Step 1 branch.** Fixing the ID
appliance bug at its actual source (`marketshare_universe.sku_type_complete`) is a separate, larger effort —
it would mean writing directly to the production output table instead of the clean reference layer, and first
requires a scope decision on whether Intrepid/ID appliance categories are even meant to be taxonomized (per
`taxonomy-pipeline-improvement-recommendations.md` Root Cause 7, not yet decided). Flagged as a follow-up, not
pulled into this plan's scope.

## Task 3 execution (2026-07-14)

- Pre-backfill snapshot of all 2,454 eligible TH rows saved to `/tmp/size_regex_pre_backfill_snapshot_2026-07-14.csv`
  (taxonomy_id, size, is_multi_size, is_bundle, updated_at) as a manual rollback point — no automated backup
  mechanism exists in this pipeline beyond this ad hoc snapshot.
- Struct-alias bug found only at dry-run time: the fill query's derived-table alias (`parsed`) collides with its
  own STRUCT column name (also `parsed`) — `SET size = parsed.size_text` is ambiguous/wrong,
  `parsed.parsed.size_text` is correct (the WHERE clause already had this right; the SET clause didn't). Fixed
  in `sql/queries/backfill_size_regex.sql` and synced into the design/plan docs.
- Dry-run: 33.6GB estimated (12x the 2.7GB country-breakdown query) — the country filter lives in a JOIN
  condition, not a WHERE, so BQ can't prune by cluster before the join; adding a redundant `WHERE u.country =
  'TH'` made no difference. Bounded (one month partition), proceeded per plan's Task 3 Step 3 guidance.
- **Result: 562 of 2,454 eligible TH rows filled** (1,892 remain NULL — no regex-extractable size in their
  `sku_name`, or no matching row in the 2026-05-01 partition; not a bug, matches the expected gap noted in the
  plan).
- Sanity check: `still_null` count (1,892) + affected rows (562) = 2,454, matches the pre-backfill eligible
  count exactly.
- Spot-checked 15 filled rows — all plausible real product sizes (toothpaste 40g–180g, 85–130ml range). One
  observation for future QA, not a bug in this pass: several filled entries have `"(all variants)"` in
  `canonical_name` (e.g. `SKU-001044 Colgate Great Regular / Kids / Herbal / Other Toothpaste (all variants)` →
  `150g`) but are not flagged `is_multi_size=TRUE`. The filled size reflects whichever single product
  `ANY_VALUE()` happened to select — correct if all variants under that entry genuinely share one physical
  size, wrong if they don't. This is a pre-existing taxonomy-entry-design question (should some of these be
  `is_multi_size=TRUE`?), not something this regex pass introduced — flagging for whoever next reviews TH
  toothpaste taxonomy quality, out of scope to fix here.
