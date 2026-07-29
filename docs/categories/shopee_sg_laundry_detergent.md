# shopee_sg_laundry_detergent — Category Context

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete |
| LLM Pass 2 | ✅ Complete |
| GMV Coverage | 96.2% (2026-06, after 2026-07-29 top-up session) |
| Last run | 2026-07-29 (Top-up coverage session; prior: Full Rebuild, first-run) |
| Current MAX taxonomy_id | SKU-215615 (this category's own block; overall table MAX may be higher from concurrent sessions) — query BQ live before any future insert, never trust this file |

**Note on STATUS.md drift:** `docs/categories/STATUS.md` lists `sg_laundry_detergent` as "⏳ Keyword
only," but live `product_taxonomy_map` has **zero** rows total (source='HUMAN' or 'LLM') for
`master_table = 'shopee_sg_laundry_detergent'`, confirmed via direct query 2026-07-29. No keyword-seed
pass has actually run for this table — same drift pattern already seen in `shopee_sg_beverages` and
`shopee_sg_household_cleaner`. Consequence: the HUMAN+LLM coexistence gate is trivially 0 and there is no
HUMAN-row cleanup step needed after this run.

**Cross-table collision check (done before any claim):** none of this category's 1,123-product in-scope
worklist (see Scale below) already has a `product_taxonomy_map` row under any other `master_table` —
checked directly against the full table (not scoped to `shopee_sg_fabric_softener` alone), 0 rows
returned. Safe to proceed without a pre-existing-row reconciliation step.

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-213207–215206 | Claimed block (2,000 slots, scenario `full_rebuild`) |
| SKU-213207–214276 | Used — Pass 1 (572 official-store products) + Pass 2 (525 remaining in-scope products) built together as one grouped match-or-create pass, 1,070 entries minted (1,068 after 2 placeholder-leak deletions, see QA History) |
| SKU-214277–215206 | Unused remainder (930 slots) |
| SKU-215407–215653 | Claimed block (247 slots, scenario `taxonomy_topup`, 2026-07-29 top-up session) |
| SKU-215407–215615 | Used — 209 new taxonomy entries from the 2026-07-29 top-up session (210 map rows; 1 pair of identical Tide-Pods listings from 2 sellers shares one entry) |
| SKU-215616–215653 | Unused remainder (38 slots) |

New `brand_dict` entries created 2026-07-29 (Full Rebuild session; brands found via `product_specs`/`sku_name` with no existing entry): `BRD-SG-14513` (Fairy), `BRD-SG-14514` (Top — real Lion Corp SG detergent brand, 47 products), `BRD-SG-14515` (Dr. Beckmann), `BRD-SG-14516` (essence).

New `brand_dict` entries created 2026-07-29 (top-up session): `BRD-SG-14517` (8X), `BRD-SG-14518` (DOZEE), `BRD-SG-14519` (Bluekey), `BRD-SG-14520` (Kerzon), `BRD-SG-14521` (Happy Home), `BRD-SG-14522` (Pure51/Esspur51).

---

## Brand Scope (GMV threshold 95%, month 2026-06-01)

**53 brands** in scope (GWP-zeroed product GMV — `flag_GWP` products' GMV set to 0 before ranking;
brand-level GMV = `SUM` of GWP-zeroed product GMV per `product_brand_map.brand_id`, `LEFT JOIN` so
unresolved products fall into `BRD-UNDEFINED` rather than being dropped). Category total GMV (all 416
distinct brand buckets, 2026-06-01): **SGD 1,599,825.13**. Threshold convention: **first rank where
cumulative fraction ≥ 0.95** (not `<= 0.95`) — the crossing row (rank 53, `MAMAFOREST`, cum 95.07%) is
included. This is the literal reading of "find where cumulative/total >= 0.95"; note this differs from the
`shopee_sg_beverages` session's `<= 0.95` convention (which would have stopped at rank 52) — stated
explicitly here so a future session doesn't need to re-derive which convention this file used.

**Category-hierarchy check (ran before finalizing this list):** `category_3_EN` / `category_4_EN` for
2026-06-01 show a single coherent bucket — `Laundry Care` → `Detergents`, 17,651/17,651 rows, no other
`category_3_EN`/`category_4_EN` value present. **No keyword pre-filter gate was needed on the brand-GMV
ranking** (llm-extraction-rules.md §8 applies only to mixed-content source tables; this table has none at
the category-metadata level). A `sku_name` text scan does find 1,385 rows (7.8%) mentioning
softener/conditioner/fabric-softener language and 133 rows (0.75%) mentioning dish/floor/toilet-cleaner
language — see Scope section below for how these are handled; they were **not** used to pre-filter the
brand ranking (per llm-extraction-rules.md §8, the keyword gate is a routing/documentation aid, never a
pre-extraction filter on individual products).

Full 53-brand list (rank, brand, brand_id, GWP-zeroed GMV SGD, product count, cumulative %):

| Rank | Brand | brand_id | GMV (SGD) | Products | Cum % |
|---|---|---|---|---|---|
| 1 | KA | BRD-GLOBAL-00161 | 217,826.54 | 189 | 13.62% |
| 2 | DYNAMO | BRD-SG-00626 | 161,466.67 | 265 | 23.71% |
| 3 | Undefined | BRD-UNDEFINED | 156,002.56 | 1,660 | 33.46% |
| 4 | Breeze | BRD-GLOBAL-00028 | 108,777.82 | 274 | 40.26% |
| 5 | Walch | BRD-SG-00491 | 87,736.13 | 147 | 45.74% |
| 6 | SimplyGood | BRD-SG-00814 | 81,477.88 | 12 | 50.84% |
| 7 | Kapsa | BRD-SG-01007 | 60,923.24 | 28 | 54.64% |
| 8 | Persil | BRD-SG-01170 | 55,994.04 | 94 | 58.14% |
| 9 | Dettol | BRD-SG-00034 | 54,464.36 | 73 | 61.55% |
| 10 | ar FUM | BRD-SG-00942 | 47,563.65 | 73 | 64.52% |
| 11 | Poddo | BRD-SG-01268 | 39,444.71 | 43 | 66.99% |
| 12 | Cloversoft | BRD-SG-00919 | 36,364.57 | 109 | 69.26% |
| 13 | Fresh HY | BRD-SG-01231 | 34,981.54 | 51 | 71.45% |
| 14 | BiC | BRD-SG-02538 | 33,578.45 | 4 | 73.55% |
| 15 | Duo&Duo | BRD-SG-01255 | 31,460.35 | 69 | 75.51% |
| 16 | Attack | BRD-SG-00063 | 26,287.98 | 84 | 77.16% |
| 17 | Yuri | BRD-GLOBAL-01555 | 22,647.75 | 25 | 78.57% |
| 18 | Clean Conscience | BRD-SG-01615 | 17,038.95 | 27 | 79.64% |
| 19 | UIC | BRD-SG-01835 | 14,962.10 | 89 | 80.57% |
| 20 | Orita | BRD-SG-01136 | 14,617.17 | 24 | 81.48% |
| 21 | Vanish | BRD-SG-00094 | 14,363.56 | 105 | 82.38% |
| 22 | Fab | BRD-SG-01718 | 13,984.40 | 134 | 83.26% |
| 23 | Tide | BRD-SG-01660 | 13,144.20 | 99 | 84.08% |
| 24 | P&G | BRD-GLOBAL-00971 | 12,968.81 | 54 | 84.89% |
| 25 | SELLEYS | BRD-SG-02026 | 10,647.20 | 41 | 85.55% |
| 26 | Zappy | BRD-SG-01585 | 9,655.21 | 8 | 86.16% |
| 27 | Seaways | BRD-SG-00551 | 9,371.75 | 14 | 86.74% |
| 28 | Seventh Generation | BRD-SG-02014 | 8,292.57 | 20 | 87.26% |
| 29 | Laundrin | BRD-SG-00378 | 7,792.47 | 19 | 87.75% |
| 30 | Nikwax | BRD-SG-04083 | 7,046.31 | 21 | 88.19% |
| 31 | Fasclean | BRD-SG-03022 | 6,961.57 | 32 | 88.62% |
| 32 | Ariel | BRD-SG-02206 | 6,629.42 | 15 | 89.04% |
| 33 | Naturali | BRD-SG-02648 | 6,484.66 | 6 | 89.44% |
| 34 | IN | BRD-SG-06662 | 6,392.76 | 86 | 89.84% |
| 35 | NOMIEO | BRD-SG-00906 | 6,309.12 | 2 | 90.24% |
| 36 | Kao | BRD-GLOBAL-00835 | 6,106.54 | 46 | 90.62% |
| 37 | JWB | BRD-SG-02728 | 5,897.75 | 19 | 90.99% |
| 38 | SukGarden | BRD-SG-01586 | 5,586.94 | 25 | 91.34% |
| 39 | Daia | BRD-SG-01816 | 5,413.04 | 57 | 91.68% |
| 40 | Dr.ville | BRD-GLOBAL-00875 | 5,273.32 | 2 | 92.01% |
| 41 | Easyout | BRD-SG-01521 | 5,194.11 | 11 | 92.33% |
| 42 | Finish | BRD-SG-02708 | 5,048.50 | 6 | 92.65% |
| 43 | Ecover | BRD-SG-01987 | 4,357.39 | 40 | 92.92% |
| 44 | Ka POD | BRD-SG-03128 | 4,235.11 | 6 | 93.18% |
| 45 | Nara Home Affairs | BRD-SG-02706 | 4,030.16 | 2 | 93.44% |
| 46 | bio-home | BRD-SG-01974 | 4,006.71 | 35 | 93.69% |
| 47 | SPINMATIC | BRD-SG-03417 | 3,554.22 | 12 | 93.91% |
| 48 | Jie Rou C&S | BRD-SG-01482 | 3,244.08 | 3 | 94.11% |
| 49 | method | BRD-SG-01091 | 3,240.03 | 31 | 94.31% |
| 50 | Green Kulture | BRD-SG-02388 | 3,222.10 | 9 | 94.51% |
| 51 | Bold | BRD-SG-02923 | 3,017.41 | 11 | 94.70% |
| 52 | Miele | BRD-SG-03463 | 2,986.00 | 18 | 94.89% |
| 53 | MAMAFOREST | BRD-SG-01769 | 2,899.07 | 2 | 95.07% |

Brands excluded from scope (below 5% GMV tail, rank 54+ of 416 total brand buckets): the long tail — every
brand not listed above (363 brand buckets, cumulative 4.93% of category GMV).

**`BRD-UNDEFINED` is rank 3 (9.75% of category GMV, SGD 156,002.56, 1,660 products)** — kept in the ranking
and denominator, not excluded (same precedent as `shopee_sg_beverages`). Products under this bucket are
extracted from `sku_name`/image like any other product; their real brand (if determinable, e.g. from a
"P&G Official Store" merchant name or a phonetically-identifiable brand in `sku_name`) informs
`product_taxonomy.brand_id`, independent of what `product_brand_map` assigned.

---

## Official Store Allowlist (Pass 1)

Built by: for each of the 53 in-scope brands, `SELECT DISTINCT merchant_name WHERE
merchant_badge='Shopee Mall'` joined via `product_brand_map` (LEFT JOIN so `BRD-UNDEFINED` products are
included) — 122 raw (brand, merchant_name) pairs across ~50 distinct merchant names.

**Multi-brand retailer exclusion methodology:** queried `COUNT(DISTINCT brand_id)` per Mall-badged merchant
across **all** Mall products in this table (not just the 53 in-scope brands), then reviewed every merchant
carrying **≥3 distinct brand_id buckets** individually — the auditable generalization from
`shopee_sg_beverages`, since this vertical (household/FMCG) has no explicit named list in
llm-extraction-rules.md §4 (that section names Beauty and Grocery/Thai-chain verticals, not SG household).
Unlike beverages, the ≥3 threshold could **not** be applied mechanically here without excluding genuine
parent-company stores — several ≥3-brand merchants in this category are manufacturers selling their own
multi-brand portfolio (Kao owns Attack; Unilever owns Breeze/Persil/Seventh Generation in this market;
Reckitt owns Dettol/Vanish; Walch Group owns Walch/DYNAMO/KA/Fresh HY/ar FUM/Fab as a real SG household-goods
conglomerate). Each ≥3-brand merchant was checked individually:

| Merchant | n_brands | Verdict | Reason |
|---|---|---|---|
| Kao Official Store | 3 | **Keep** (parent) | Kao Corporation's own store; owns Attack |
| Unilever Official Store | 4 | **Keep** (parent) | Unilever's own store; owns Breeze, Persil, Seventh Generation |
| Dettol Official Store | 4 | **Keep** (parent) | Reckitt's own store; owns Dettol, Vanish |
| RB Home Official Store | 2 | **Keep** (parent) | Reckitt Benckiser Home — same manufacturer as Dettol/Vanish |
| Walch SG Official Store | 8 | **Keep** (parent) | Walch Group's own store; owns Walch, DYNAMO, KA, Fresh HY, ar FUM, Fab |
| Watsons Singapore Official Store | 25 | Exclude | Third-party multi-brand pharmacy retailer (named explicitly in llm-extraction-rules.md §4) |
| myCK_online | 20 | Exclude | Generic multi-brand reseller |
| Prestigio Delights Official | 10 | Exclude | Third-party distributor (same verdict as in `shopee_sg_beverages`) |
| Corlison Official Store | 3 | Exclude | Third-party eco-cleaning distributor (sells Ecover + method, neither of which it manufactures) |
| DON DON DONKI Official Store | 3 | Exclude | General discount-store retailer, not a brand principal (same verdict as in `shopee_sg_beverages`) |
| Moda Paolo Official Store | 3 | Exclude | General lifestyle-goods retailer, not a brand principal (sells Seaways + Walch) |
| Guardian SG Official Store | 2 | **Exclude (manual override)** | Below the 3-brand mechanical threshold in this category's narrow slice (only Dettol + Vanish appear here), but Guardian is a well-known SG multi-brand pharmacy/drugstore chain (same class as Watsons) — excluded on identity, not on the mechanical count, since the count alone would be a false negative here |

**Final allowlist: 35 distinct merchant names, 44 (brand, merchant) pairs, covering 39 of the 53 in-scope
brands** (the remaining 13 in-scope brands plus `BRD-UNDEFINED` have no qualifying official store and go
straight to Pass 2 — see below).

| Brand | brand_id | Official Store Merchant Name |
|---|---|---|
| Ariel | BRD-SG-02206 | yougo.sg |
| Attack | BRD-SG-00063 | Kao Official Store |
| BiC | BRD-SG-02538 | BIC OFFICIAL STORE |
| Breeze | BRD-GLOBAL-00028 | Unilever Official Store |
| Clean Conscience | BRD-SG-01615 | Yuri Shop |
| Cloversoft | BRD-SG-00919 | Cloversoft Flagship Store |
| Dettol | BRD-SG-00034 | Dettol Official Store |
| Duo&Duo | BRD-SG-01255 | DuoDuo Mall |
| DYNAMO | BRD-SG-00626 | Walch SG Official Store |
| Easyout | BRD-SG-01521 | Easyout Home Clean |
| Easyout | BRD-SG-01521 | Easyout SG Local Store |
| Ecover | BRD-SG-01987 | Ecover Official Store |
| Fab | BRD-SG-01718 | Walch SG Official Store |
| Fasclean | BRD-SG-03022 | Fasclean Factory Store.sg |
| Finish | BRD-SG-02708 | Weloveourkids |
| Fresh HY | BRD-SG-01231 | GoodLion |
| Fresh HY | BRD-SG-01231 | GadgetLion |
| Fresh HY | BRD-SG-01231 | Walch SG Official Store |
| JWB | BRD-SG-02728 | JWB HOUSEHOLD OFFICIAL STORE |
| KA | BRD-GLOBAL-00161 | Casa Official Store |
| KA | BRD-GLOBAL-00161 | Walch SG Official Store |
| Kao | BRD-GLOBAL-00835 | Kao Official Store |
| Kapsa | BRD-SG-01007 | Pristine Aroma |
| Laundrin | BRD-SG-00378 | Mandom Official Store |
| MAMAFOREST | BRD-SG-01769 | ToppingsKids Official Store |
| Miele | BRD-SG-03463 | Miele |
| Naturali | BRD-SG-02648 | The Ugly Company |
| Nikwax | BRD-SG-04083 | Nikwax Singapore |
| P&G | BRD-GLOBAL-00971 | P&G Official Store *(reroute — see note)* |
| Persil | BRD-SG-01170 | Unilever Official Store |
| Poddo | BRD-SG-01268 | Poddo Official Store |
| SELLEYS | BRD-SG-02026 | LifeStyle OS |
| SELLEYS | BRD-SG-02026 | Selleys Official Store |
| Seaways | BRD-SG-00551 | Seaways Store SG |
| Seventh Generation | BRD-SG-02014 | Unilever Official Store |
| SimplyGood | BRD-SG-00814 | SimplyGood |
| SukGarden | BRD-SG-01586 | SukGarden Official Store |
| Tide | BRD-SG-01660 | cosblah |
| Vanish | BRD-SG-00094 | Dettol Official Store |
| Vanish | BRD-SG-00094 | RB Home Official Store |
| Walch | BRD-SG-00491 | Walch SG Official Store |
| Yuri | BRD-GLOBAL-01555 | Yuri Shop |
| ar FUM | BRD-SG-00942 | Walch SG Official Store |
| method | BRD-SG-01091 | Method Official Store |
| Zappy | BRD-SG-01585 | Zappy & HospiCare by Freshening |

**P&G reroute note:** `P&G`'s own `product_brand_map`-resolved row only shows "DON DON DONKI Official Store"
(excluded, multi-brand). A separate product resolved to `BRD-UNDEFINED` sells at a merchant literally named
"P&G Official Store" — this is P&G's real official store; brand-map resolution failure on that one listing
doesn't change what store it is. Rerouted into the P&G allowlist row above (same pattern as the Coca-Cola
reroute precedent in `shopee_sg_beverages`).

**Multi-brand stores (excluded, listed for audit — NOT part of the allowlist):** Watsons Singapore Official
Store, myCK_online, Prestigio Delights Official, Corlison Official Store, DON DON DONKI Official Store, Moda
Paolo Official Store, Guardian SG Official Store.

**Brands with no official store (Pass 2 only):** UIC, Orita, SPINMATIC, IN, NOMIEO, Daia, Dr.ville, Ka POD,
Nara Home Affairs, bio-home, Jie Rou C&S, Green Kulture, Bold — plus `BRD-UNDEFINED` (no single "official
store" concept applies; individual Undefined-bucket products are read from `sku_name`/image like any other
during Pass 2).

---

## Scale

- **Total rows, all months (`master_clean_niq.shopee_sg_laundry_detergent`):** 542,847
- **2026-06 rows:** 17,651 · **distinct products:** 5,999 · **category total GWP-zeroed GMV:** SGD 1,599,825.13
- **Shopee Mall-badged (2026-06):** 2,636 rows / 1,152 distinct products — moderate scale; Pass 1 vision-reads
  are scoped to the 35-merchant allowlist (44 brand-merchant pairs), not the full 1,152-product Mall pool.
- **In-scope worklist (quality-standards.md §2, Rule A ∪ Rule B, 2026-06-01):** Rule A (top-95%
  cumulative GWP-zeroed GMV, product-level) = 813 products · Rule B (official-store listings from the
  allowlist above, brand within the 53-brand scope) = 572 products · overlap = 262 · **union total = 1,123
  products.** This is the population Pass 1 + Pass 2 must resolve and what STEP 7's self-check is measured
  against.

---

## Existing map rows (Step 1)

**Zero.** `SELECT source, COUNT(*) FROM product_taxonomy_map WHERE master_table =
'shopee_sg_laundry_detergent' GROUP BY source` returns no rows at all — not even `HUMAN` keyword-seed rows.
Confirmed genuine first-run: no HUMAN+LLM coexistence possible, no cleanup step needed, no stale rows to
reconcile.

---

## Scope — What's In vs Out

**In scope:**
- Laundry detergent — liquid, powder, capsule/pod, bar/soap-for-laundry format
- 2-in-1 wash+soften laundry products (a detergent with a softening agent is still a detergent — matches
  the `fabric_softener` category's own "2-in-1 wash+soften = in scope" rule from llm-extraction-rules.md's
  changelog, applied here from the detergent side)
- Laundry-specific stain removers / pre-treatment sold as a wash-in product (Vanish, OxiClean-style)

**Out of scope (leave NULL):**
- Dish soap / washing-up liquid
- Floor cleaner
- Toilet cleaner
- Standalone fabric softener/conditioner with **no** wash function (pure softener, no detergent claim) —
  belongs to `shopee_sg_fabric_softener`, a separate category/table entirely; if such a product appears
  misfiled in this table's data, leave it NULL here rather than taxonomize it under this category's block
- General household cleaning equipment (e.g. digital locks, appliances) that happens to appear under a Mall
  merchant selling in-scope products at the same store

**133 rows (0.75%) match a dish/floor/toilet keyword scan** — per llm-extraction-rules.md §8, this was used
only to confirm the exclusion boundary exists in the data, never as a pre-extraction filter; each such
product is still read individually and excluded via the category/type match-or-create gate
(product-lifecycle.md §4.2) if it's genuinely out of scope, not dropped by the keyword scan itself.

**1,385 rows (7.8%) mention softener/conditioner/fabric language** — the large majority of these are
2-in-1 wash+soften detergents (in scope, per above) rather than pure softeners; each is resolved by the
same per-product category/type gate at extraction time, not pre-filtered.

**Edge cases:**
- `BRD-UNDEFINED` products (1,660 total, rank 3 in brand scope): extract normally from sku_name/image; do
  not skip because the brand bucket is unresolved.
- Parent-company multi-brand stores (Kao Official Store, Unilever Official Store, Dettol Official Store,
  RB Home Official Store, Walch SG Official Store): disambiguate via `brand_from_image` per product — don't
  assume every product in the store is the store's namesake brand (Walch SG Official Store alone carries 6
  distinct brands).

---

## Taxonomy Design Notes

**Product line extraction approach:**
- Never use generic category words as `product_line`: `laundry detergent`, `detergent`, `laundry liquid`,
  `washing powder`, `laundry powder`, `laundry capsules`, `pods`, `fabric softener` are banned as standalone
  product_line values for this category (llm-extraction-rules.md §3) — extract the real on-label line name
  (e.g. "Total 10 Activ Silver", "3-in-1 Pods Fresh Sensations").
- Most in-scope brands (39 of 53) have an official store — expect Pass 1 to carry more of the volume
  proportionally than in `shopee_sg_beverages` (which had only 48 of 177 brands with a store).

**Size extraction notes:**
- Primary unit: ml/L for liquid, g/kg for powder, count (e.g. "x30 pods") for capsules/pods.
- **`raw_niq_history` does not exist as a BigQuery dataset in this project** (confirmed live via `bq ls`,
  matching the `shopee_sg_beverages` session's finding) despite ARCHITECTURE.md documenting it. Size/pack
  fallback chain for this session is therefore: `sku_name`/`sku_name_EN` → product image (curl the `image`
  column URL to `/tmp`, then `Read` the local file) → this table's own `product_specs` column (structured
  fallback) → none (no `product_description` equivalent exists here either).
- Bulk-pack canonical name = `x{TOTAL}` only, per llm-extraction-rules.md §2 — never a "(N packs of M)"
  breakdown.
- **Never resolve `canonical_name` to "Multiple Sizes"/"Multiple Variants"/"All Variants"/"All Sizes"** even
  when `is_multi_size`/`is_multi_variant` is correctly set — banned unconditionally per the placeholder-leak
  QA gate. Use a real per-brand `(unresolved)` catch-all name instead for genuinely fragmented long-tail
  resellers (same pattern as `shopee_sg_hand_and_body_moisturiser`'s 146 per-brand catch-alls).

**Known difficult products:**
- Products at parent-company multi-brand stores need `brand_from_image` confirmation, not an assumption
  from `merchant_name` (llm-extraction-rules.md §11 — never derive brand from `merchant_name`).

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-29 | Pre-run research | STATUS.md says "Keyword only" but live `product_taxonomy_map` has 0 rows for this table (not even HUMAN) | Documented; no HUMAN cleanup needed, genuine first pass |
| 2026-07-29 | Pre-run research | Mechanical ≥3-distinct-brand merchant exclusion (the `shopee_sg_beverages` methodology) would have wrongly excluded 5 genuine parent-company stores (Kao, Unilever, Dettol, RB Home, Walch SG) that together cover the #1 and #2 ranked brands (KA, DYNAMO — 24% of category GMV combined) | Reviewed each ≥3-brand merchant manually; kept the 5 parent stores, excluded 6 genuine third-party multi-brand retailers/distributors, manually excluded Guardian SG Official Store despite its in-category count (2) falling below the mechanical threshold |
| 2026-07-29 | Pre-run research | Cross-table composite-key collision check: 0 of the 1,123-product in-scope worklist already has a `product_taxonomy_map` row under any other `master_table` | No reconciliation needed before insert |
| 2026-07-29 | Pre-run research | `raw_niq_history.shopee_sg_laundry_detergent` does not exist as a BigQuery dataset (same finding as `shopee_sg_beverages`) | Size/pack fallback uses this table's own `product_specs` column instead |
| 2026-07-29 | Pre-run research | 2026-06 row count (17,651) is lower than April/May (32k–34k) — the month specified by this run's wrapper prompt | Noted in session findings, not treated as a blocker; wrapper specified this month explicitly |
| 2026-07-29 | Pass 1+2 build | Bulk regex-based extraction (brand/size/pack/variant from `sku_name_EN` + `product_specs` Brand field) used for both passes given the 1,123-product worklist scale — Pass 1 (572 official-store products) and Pass 2 (551 remaining) processed together as one grouped match-or-create pass (Pass 2 naturally reused Pass 1's entries where brand+line+size+pack matched, minted new ones otherwise); only text signals were used, no vision reads (rich `sku_name_EN` text was sufficient) | Coverage-first per Full Rebuild philosophy; exact wording polish deferred to `targeted_qa_fix.sh` |
| 2026-07-29 | Pass 1+2 build | Found and fixed 3 extraction bugs during construction: (1) a bare digit in "4-in-1"/"5-in-1" format descriptors was misread as a pods/pcs size count (28.6% of products contained this pattern) — fixed by blanking `\d+-in-\d+` before running size/pack regexes; (2) the generic-stub `"{Brand} (unresolved)"` product_line fallback caused a duplicated brand name in `canonical_name` (e.g. "Persil Persil (unresolved)") — fixed by stripping the leading brand token when building the display name only (stored `product_line` field keeps the brand per llm-extraction-rules.md §3); (3) `raw_niq_history` does not exist for this table (same finding as `shopee_sg_beverages`) — used this table's own `product_specs` column instead | All fixed before insert |
| 2026-07-29 | Pass 1+2 build | Manually reviewed 16 auto-flagged softener/non-laundry keyword hits and excluded 13 genuinely out-of-scope products (pure fabric softeners: Miele, Comfort, Downy; dishwasher/dish-soap: Finish x2, IN; body soap: glow; scent booster: P&G Lenor; ambiguous cross-category kit bundles: Poddo x3, Dynamo, Yuri) — kept 4 Yuri "Gift:"-tagged GWP freebies and 1 bio-home genuinely-multi-use product as in-scope | Applied product-lifecycle.md §4.2 category/type gate per product before extraction |
| 2026-07-29 | Post-write QA gates | Live schema drift found: `product_taxonomy_map.confidence` is `STRING` in production, not `FLOAT64` as ARCHITECTURE.md/data-dictionary.md document (same drift class as the `shopee_sg_beverages` session's `brand_dict` finding) | Insert DML adjusted to quote confidence as a string literal |
| 2026-07-29 | Post-write QA gates | First gate run found 2 placeholder-leak violations: `SKU-213859`/`SKU-213862`, both literally containing "Multiple Variants" in `canonical_name`, sourced from 2 reseller listings genuinely offering buyer's-choice between two *different* brands (Tide vs. Gain) in one SKU | Deleted both taxonomy entries and their 2 map rows — matches the `th_softdrink` precedent for multi-brand buyer-choice listings (leave unmapped, not a forced/generic name) rather than rename into something misleading |
| 2026-07-29 | Post-write QA gates (final) | G1 dual-mapped(LLM)=0, G2 HUMAN+LLM coexistence=0, placeholder-leak=0, structured-fields (product_line NULL%, excl. is_multi_size)=0%, G5 provenance (NULL meta_agent/source)=0, platform/country populated on all rows=0 missing | All gates pass; universe refresh eligible (not run this session — separate step per headless-runbook.md) |
| 2026-07-29 | Post-write coverage | 94.0% GMV coverage (2026-06): 4,114 of 17,651 rows mapped by product count; 1,068 final taxonomy entries (1,070 minted minus 2 deleted) from 1,095 map rows (1,097 minus 2 deleted) | 26 products left unmapped: 13 genuine scope-exclusions (documented above) + 13 brand-unresolvable listings (mystery/generic-private-label resellers, e.g. "Shopee x DuoDuo Brand Box", "DOZEE 10KG Laundry Detergent") — legitimately UNRESOLVED per product-lifecycle.md §5 |
| 2026-07-29 | Known gaps for `targeted_qa_fix.sh` | ~23% of entries have NULL `size` (legitimately size-ambiguous bundle/kit listings in many cases, not individually verified); some nested nested nested-multiplier bundle patterns ("Bundle of 10 Packs + 1 Box") left at `pack_count=1` rather than computed; a handful of Miele professional-appliance model numbers produced garbled size text (e.g. "0302L") | Flagged for D4/D5 sweep, low GMV impact (long-tail products) |
| 2026-07-29 | Top-up coverage session | Live pre-check found 247 rows / 225 distinct products still unmapped within the top-95%-cumulative-GMV (GWP-zeroed) worklist despite the prior Full Rebuild's 94.0% coverage claim. Live `product_taxonomy_map`/`product_taxonomy` state was verified against the doc first (1,095 LLM rows, 1,068 dict entries in SKU-213207–214276, 0 orphans, registry claim intact) — matched exactly, so this was a genuine incremental gap, not a repeat of the pipeline-wide HUMAN-row data-loss incident tracked elsewhere. Bulk text-only (no image reads) brand+size+pack extraction via Python regex against `sku_name`, same crude-but-consistent style as the prior Pass 1+2 build. 15 products (31 raw rows) excluded as genuinely out of scope: dishwasher/dish-soap (Finish, P&G Joy), body soap (ANGGUN), pure fabric softener (Comfort), appliance descaler (Karcher), unlabeled industrial soda ash (DChemie), cross-category kit bundles (2× Poddo, 1× Dynamo, 1× Fasclean 8-in-1 set — matches this category's own "Poddo x3/Dynamo" precedent), scent booster beads (P&G Lenor — matches existing precedent), and 3 Tide/Gain/Arm&Hammer buyer-choice "Multiple Variant(s)" listings (matches this category's own SKU-213859/213862 placeholder-leak precedent — can't determine what the buyer actually receives). Found and fixed during construction: (1) a naive brand-token-stripping regex ate substrings inside unrelated words for short brand tokens like "IN"/"KA" (e.g. "Stain"→"Sta", "Bleaching"→"Bleachg") — fixed with `\b` word-boundary matching; (2) 3 products where `product_brand_map`'s resolved brand didn't match what `sku_name` actually said (a "KA"-resolved product that was really Fresh HY, a "Walch"-resolved product that was really KA, one dropped to `BRD-UNDEFINED` since neither text nor the resolved brand could be confirmed) — corrected per llm-extraction-rules.md §7/§11 (sku_name text is authoritative over `product_brand_map`). 6 new `brand_dict` entries minted for real recognizable brands with no existing entry: `BRD-SG-14517` (8X), `BRD-SG-14518` (DOZEE), `BRD-SG-14519` (Bluekey), `BRD-SG-14520` (Kerzon), `BRD-SG-14521` (Happy Home), `BRD-SG-14522` (Pure51/Esspur51). | Claimed SKU-215407–215653 (247 slots, scenario `taxonomy_topup`); used SKU-215407–215615 (209 new taxonomy entries, 210 map rows after deduping 1 identical Tide-Pods pair sold by 2 sellers); 38 unused slots (SKU-215616–215653) left in the block. GMV coverage 94.0% → 96.2% (2026-06); LLM map rows 1,095 → 1,305. Post-write QA gates: G1 dual-mapped=0, G2 HUMAN+LLM coexistence=0, placeholder-leak=0, structured-fields NULL%=0, G5 provenance=0, G4 cross-category=0. Live worklist re-check after write: 0 rows remaining except the 15 documented exclusions above. Per-row wording precision (exact product_line polish) intentionally deprioritized per this session's coverage-first mandate — deferred to `targeted_qa_fix.sh`. |

---

## Targeted QA Fix Brief

*(not applicable — this is the first extraction pass; no existing taxonomy entries to fix yet)*

---

## Scripts

| Script | Purpose |
|--------|---------|
| `pipeline/05_product_taxonomy/llm_shopee_sg_laundry_detergent/build_taxonomy.py` | Pass 1 extraction (not used — extraction performed directly by Claude Code session per headless-runbook.md) |
| `pipeline/05_product_taxonomy/llm_shopee_sg_laundry_detergent/build_p2_taxonomy.py` | Pass 2 routing (same note) |

---

## Map Row Counts (as of last run)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 1,305 | Pass 1 (572 official-store) + Pass 2 (525 remaining in-scope) minus 2 deleted placeholder-leak rows, + 210 top-up rows (2026-07-29 top-up session) |
| HUMAN | 0 | Confirmed via live query 2026-07-29 — no keyword-seed pass ever ran |
| NULL (unmapped) | ~13,327 (distinct products, 2026-06, outside the in-scope worklist) + 41 in-worklist exclusions (13 original-pass scope exclusions + 13 original-pass brand-unresolved + 15 top-up-session scope exclusions) | Long-tail below GMV threshold / out-of-category, plus documented exclusions above |
