# shopee_sg_household_cleaner — Category Context

> Generated during headless Full Rebuild session, 2026-07-29. First-ever session for this table —
> zero pre-existing `product_taxonomy_map` rows found (see "Existing map rows" below), despite
> `docs/categories/STATUS.md` listing `sg_household_cleaner` as "⏳ Keyword only" — that dashboard
> entry is stale for this specific category; flagged in session findings for reconciliation.

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ❌ Not started (this session) |
| LLM Pass 2 | ❌ Not started (this session) |
| GMV Coverage | 0% before this session |
| Last run | 2026-07-29 |
| Current MAX taxonomy_id | Query BQ live — do not trust a static number here |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| (assigned in Step 3, this session) | Full Rebuild, ~2000 slots |

---

## Brand Scope (GWP-zeroed GMV threshold ≥95%, month = 2026-06-01)

Threshold computed at **product grain**, not brand grain: `SUM(CASE WHEN flag_GWP THEN 0 ELSE
gmv_monthly END)` per `product_id` (joined to `product_brand_map` on `(product_id, platform='Shopee',
country='SG')` for `brand_id`), then summed per brand, ranked descending, cumulative fraction taken
over **total GWP-zeroed category GMV = SGD 1,158,226.50** (raw total incl. GWP = 1,158,700.96; 29 rows
flagged `flag_GWP=TRUE`). Crossing convention: a brand is in-scope if its cumulative GMV *before*
adding its own GMV is `< 0.95` (i.e. the row that first crosses 0.95 is included in full — standard
"top-95%" inclusion, not exclusion).

**118 brands** are in scope (full list, GMV-ranked). `BRD-UNDEFINED` is real rank #1 at 20.03% of
category GMV — see note below.

| # | Brand | brand_id | GMV (SGD) | Cum. % |
|---|-------|----------|-----------|--------|
| 1 | Undefined | BRD-UNDEFINED | 231,942.11 | 20.03% |
| 2 | Magiclean | BRD-SG-00790 | 99,483.13 | 28.61% |
| 3 | Walch | BRD-SG-00491 | 74,831.29 | 35.08% |
| 4 | Seaways | BRD-SG-00551 | 58,111.68 | 40.09% |
| 5 | Dettol | BRD-SG-00034 | 56,978.77 | 45.01% |
| 6 | 999 | BRD-TH-01500 | 24,828.96 | 47.16% |
| 7 | method | BRD-SG-01091 | 24,772.84 | 49.30% |
| 8 | Mr Muscle | BRD-SG-01650 | 20,322.11 | 51.05% |
| 9 | Clorox | BRD-SG-01559 | 20,285.84 | 52.80% |
| 10 | TINECO | BRD-SG-01846 | 18,188.00 | 54.37% |
| 11 | krafter | BRD-SG-01628 | 18,185.92 | 55.94% |
| 12 | Easyout | BRD-SG-01521 | 17,924.47 | 57.49% |
| 13 | MAMAFOREST | BRD-SG-01769 | 13,824.36 | 58.68% |
| 14 | Zappy | BRD-SG-01585 | 12,910.54 | 59.80% |
| 15 | SukGarden | BRD-SG-01586 | 11,255.07 | 60.77% |
| 16 | Home | BRD-GLOBAL-02850 | 10,879.10 | 61.71% |
| 17 | 3M | BRD-GLOBAL-00359 | 10,273.30 | 62.60% |
| 18 | Cif | BRD-SG-01883 | 10,189.65 | 63.48% |
| 19 | Jackie | BRD-SG-02160 | 9,917.39 | 64.33% |
| 20 | Supersteam | BRD-SG-02276 | 9,306.24 | 65.13% |
| 21 | Bona | BRD-SG-02212 | 8,918.55 | 65.91% |
| 22 | Floral | BRD-SG-01522 | 8,394.21 | 66.63% |
| 23 | SimplyGood | BRD-SG-00814 | 8,301.13 | 67.35% |
| 24 | Howard | BRD-SG-02424 | 8,278.07 | 68.06% |
| 25 | The Pink Stuff | BRD-SG-02069 | 8,101.56 | 68.76% |
| 26 | Buster | BRD-SG-02526 | 8,075.72 | 69.46% |
| 27 | Ecover | BRD-SG-01987 | 6,967.15 | 70.06% |
| 28 | GONG100 | BRD-SG-02338 | 6,835.03 | 70.65% |
| 29 | HG | BRD-SG-02519 | 6,796.29 | 71.24% |
| 30 | bio-home | BRD-SG-01974 | 6,637.61 | 71.81% |
| 31 | Harpic | BRD-SG-02390 | 6,623.31 | 72.38% |
| 32 | ETL No. 9 | BRD-SG-02583 | 6,584.16 | 72.95% |
| 33 | Shark | BRD-SG-02990 | 6,580.57 | 73.52% |
| 34 | Making Lifestyle Solutions | BRD-SG-02235 | 6,482.72 | 74.08% |
| 35 | KINBATA | BRD-SG-02865 | 5,850.39 | 74.58% |
| 36 | Jomo | BRD-SG-00500 | 5,797.16 | 75.08% |
| 37 | Mr McKenic | BRD-SG-03131 | 5,775.20 | 75.58% |
| 38 | Philips | BRD-GLOBAL-00417 | 5,409.36 | 76.05% |
| 39 | Dreame | BRD-SG-02659 | 5,367.98 | 76.51% |
| 40 | Ajax | BRD-SG-04057 | 5,238.70 | 76.96% |
| 41 | IN | BRD-SG-06662 | 4,924.09 | 77.39% |
| 42 | Dr.ville | BRD-GLOBAL-00875 | 4,827.81 | 77.81% |
| 43 | dyson | BRD-SG-03490 | 4,773.00 | 78.22% |
| 44 | Dr.Beckmann | BRD-SG-02326 | 4,742.30 | 78.63% |
| 45 | Weiman | BRD-SG-02774 | 4,712.52 | 79.04% |
| 46 | Kobayashi | BRD-GLOBAL-01922 | 4,709.00 | 79.44% |
| 47 | Aimedia | BRD-SG-03446 | 4,572.38 | 79.84% |
| 48 | TP 706 | BRD-SG-03520 | 4,531.19 | 80.23% |
| 49 | mixshop | BRD-SG-02982 | 4,334.90 | 80.60% |
| 50 | Two Steps Cleaning | BRD-SG-02232 | 4,324.01 | 80.98% |
| 51 | Hospicare | BRD-SG-03133 | 4,298.78 | 81.35% |
| 52 | Consolidated | BRD-SG-02996 | 4,286.00 | 81.72% |
| 53 | Bref | BRD-SG-02393 | 4,144.52 | 82.07% |
| 54 | Bar Keepers Friend | BRD-SG-02834 | 4,093.18 | 82.43% |
| 55 | Roborock | BRD-SG-03004 | 3,989.68 | 82.77% |
| 56 | SOFIX | BRD-SG-02900 | 3,948.99 | 83.11% |
| 57 | Agape Nature | BRD-SG-02789 | 3,880.00 | 83.45% |
| 58 | Kincho | BRD-SG-03873 | 3,725.15 | 83.77% |
| 59 | Offspring | BRD-SG-00762 | 3,669.00 | 84.09% |
| 60 | SELLEYS | BRD-SG-02026 | 3,603.63 | 84.40% |
| 61 | KLEEN UP | BRD-SG-03024 | 3,392.90 | 84.69% |
| 62 | Goo Gone | BRD-SG-02827 | 3,374.98 | 84.98% |
| 63 | Green Kulture | BRD-SG-02388 | 3,324.26 | 85.27% |
| 64 | POWERMAX | BRD-SG-03915 | 3,286.98 | 85.55% |
| 65 | For Furry Friends | BRD-SG-02714 | 3,228.64 | 85.83% |
| 66 | FIELL | BRD-SG-02986 | 3,215.70 | 86.11% |
| 67 | Imakara | BRD-SG-02144 | 3,168.23 | 86.38% |
| 68 | Cosway | BRD-SG-02931 | 3,111.41 | 86.65% |
| 69 | Deep | BRD-SG-12678 | 3,101.89 | 86.92% |
| 70 | cafetto | BRD-SG-03553 | 3,086.00 | 87.19% |
| 71 | G-Natural | BRD-SG-03320 | 3,077.60 | 87.45% |
| 72 | BOSCH | BRD-SG-03165 | 3,067.65 | 87.72% |
| 73 | Nichigo | BRD-SG-03418 | 3,043.42 | 87.98% |
| 74 | Koala Home Lifestyle | BRD-SG-02771 | 2,917.18 | 88.23% |
| 75 | SingCrop | BRD-SG-03308 | 2,800.42 | 88.47% |
| 76 | Nippon Home | BRD-SG-02951 | 2,724.16 | 88.71% |
| 77 | Yuri | BRD-GLOBAL-01555 | 2,689.07 | 88.94% |
| 78 | AROMA | BRD-GLOBAL-00294 | 2,659.00 | 89.17% |
| 79 | Kao | BRD-GLOBAL-00835 | 2,434.24 | 89.38% |
| 80 | bin buddy | BRD-SG-03266 | 2,382.89 | 89.59% |
| 81 | molton | BRD-SG-03261 | 2,382.58 | 89.79% |
| 82 | Care | BRD-GLOBAL-00623 | 2,348.16 | 89.99% |
| 83 | Wd-40 | BRD-SG-03281 | 2,334.96 | 90.20% |
| 84 | Uwant | BRD-SG-04802 | 2,213.70 | 90.39% |
| 85 | OxiClean | BRD-SG-03217 | 2,164.84 | 90.57% |
| 86 | East Chem | BRD-SG-04009 | 2,140.48 | 90.76% |
| 87 | KLEENSO | BRD-SG-03737 | 2,125.51 | 90.94% |
| 88 | Hair+ | BRD-SG-04456 | 2,124.19 | 91.13% |
| 89 | Guardsman | BRD-SG-03558 | 2,114.69 | 91.31% |
| 90 | SinCare | BRD-SG-03409 | 2,052.25 | 91.49% |
| 91 | Earth | BRD-SG-03906 | 1,998.99 | 91.66% |
| 92 | Fasclean | BRD-SG-03022 | 1,818.91 | 91.81% |
| 93 | Weicon | BRD-SG-04312 | 1,817.69 | 91.97% |
| 94 | B Lock | BRD-GLOBAL-02121 | 1,815.26 | 92.13% |
| 95 | Kiss | BRD-GLOBAL-02465 | 1,779.03 | 92.28% |
| 96 | Amway | BRD-GLOBAL-00300 | 1,768.00 | 92.43% |
| 97 | Fresh HY | BRD-SG-01231 | 1,717.10 | 92.58% |
| 98 | Floor Master | BRD-SG-04638 | 1,715.30 | 92.73% |
| 99 | Nature Love Mere | BRD-GLOBAL-01902 | 1,605.24 | 92.87% |
| 100 | MR PERFECT | BRD-SG-05619 | 1,539.80 | 93.00% |
| 101 | Oxygen | BRD-TH-01424 | 1,488.01 | 93.13% |
| 102 | Old English | BRD-SG-03594 | 1,482.07 | 93.26% |
| 103 | Singapore Collection | BRD-GLOBAL-02338 | 1,480.30 | 93.39% |
| 104 | Lemon | BRD-TH-03174 | 1,447.56 | 93.51% |
| 105 | Clean Conscience | BRD-SG-01615 | 1,423.06 | 93.63% |
| 106 | Netcare | BRD-SG-03725 | 1,384.30 | 93.75% |
| 107 | Jif | BRD-SG-03789 | 1,383.91 | 93.87% |
| 108 | Cloversoft | BRD-SG-00919 | 1,382.00 | 93.99% |
| 109 | All | BRD-SG-06567 | 1,369.51 | 94.11% |
| 110 | KARCHER | BRD-SG-03707 | 1,355.04 | 94.23% |
| 111 | Fast | BRD-SG-04063 | 1,339.86 | 94.34% |
| 112 | Dew | BRD-GLOBAL-02582 | 1,310.52 | 94.46% |
| 113 | Lion | BRD-GLOBAL-00873 | 1,239.15 | 94.56% |
| 114 | Lysol | BRD-SG-04140 | 1,235.66 | 94.67% |
| 115 | MOVA | BRD-SG-03856 | 1,206.70 | 94.77% |
| 116 | Hoover | BRD-SG-03569 | 1,205.28 | 94.88% |
| 117 | Day& | BRD-SG-12796 | 1,140.66 | 94.98% |
| 118 | Melaleuca | BRD-SG-02385 | 1,137.50 | 95.08% |

Brands below the tail (Melaleuca) are excluded from scope — long tail, may remain UNRESOLVED.

**`BRD-UNDEFINED` note (rank #1, 20.03% of category GMV):** no brand assignment at all in
`product_brand_map` — these products have no official store by definition, so all of this GMV routes
through Pass 2. `product_taxonomy_map` does not require `brand_id` agreement with `product_brand_map`
(per `docs/llm-extraction-rules.md`'s th_softdrink/th_drinking_water precedents) — where `sku_name` or
the product image identifies a real brand for a `BRD-UNDEFINED` product, map it to that brand's real
taxonomy entry, not a generic catch-all. Never name an entry "Undefined ..." — the placeholder-leak QA
gate bans that token in `canonical_name`; use `"{Real Brand} (unresolved)"` only if the product-level
brand genuinely cannot be read from sku_name/image either.

**Category composition check (before accepting this brand list):** the source table's
`category_3_EN` is uniformly `"Cleaning Agents"` for all rows (no sub-category breakdown). Several
top-118 brands are primarily known as appliance manufacturers (TINECO, dyson, Shark, Roborock, Dreame,
Philips, BOSCH, KARCHER, Hoover, MOVA) or industrial/hardware brands (3M, Wd-40, Weicon). Spot-checked
their actual `sku_name`s: without exception, every listing found is a **cleaning solution / detergent /
descaler / degreaser product** for that brand's own appliances (e.g. "Tineco Multi-Surface Deodorizing
Cleaning Solution", "Dyson 02 Probiotic Hard Floor Cleaning Solution", "Bosch Clean & Care Washing
Machine Cleaner", "Zojirushi Electric Pot Cleaner and Descaler") — not the appliances/tools themselves.
NIQ's own `category_3='Cleaning Agents'` filter is doing real work here; the brand list is **not**
contaminated at the brand-ranking level. A handful of individual non-cleaner products exist within
otherwise-legitimate brands (e.g. a "simplehuman Sink Caddy" among simplehuman's cleaning tablets —
simplehuman itself did not make the 95% cut) — these are a per-product exclusion at extraction time via
the category/type match-or-create gate, never a reason to drop the brand from scope.

---

## Official Store Allowlist (Pass 1)

Built from: `merchant_name WHERE merchant_badge='Shopee Mall'` per in-scope `brand_id`, then hand-filtered
against merchants that carry ≥2 distinct in-scope brands (objective multi-brand-retailer signal) plus the
known SG multi-brand retailers.

| Brand | brand_id | Official Store Merchant Name(s) |
|-------|----------|----------------------------------|
| 3M | BRD-GLOBAL-00359 | `3M Official eStore`, `3M Safety & Industrial` |
| Ajax | BRD-SG-04057 | `Colgate Official Store` (Colgate-Palmolive owns Ajax) |
| BOSCH | BRD-SG-03165 | `Bosch Home Appliances Official Store` |
| Bona | BRD-SG-02212 | `Bona Singapore Official Store` |
| Buster | BRD-SG-02526 | `Challs Asia Official Store` |
| Cif | BRD-SG-01883 | `Unilever International` |
| Cloversoft | BRD-SG-00919 | `Cloversoft Flagship Store` |
| Dettol | BRD-SG-00034 | `Dettol Official Store` |
| Dew | BRD-GLOBAL-02582 | `Baby Central SG Official Store` |
| Dr.ville | BRD-GLOBAL-00875 | `Dr.ville SG Office Store`, `Easyout SG Local Store` |
| Dreame | BRD-SG-02659 | `Dreame Official Store` |
| ETL No. 9 | BRD-SG-02583 | `ETL.shop` |
| Earth | BRD-SG-03906 | `Mandom Official Store` (parent/distributor — shared with Nichigo, Kincho) |
| Easyout | BRD-SG-01521 | `Easyout SG Local Store` |
| Ecover | BRD-SG-01987 | `Ecover Official Store`, `Corlison Official Store` (shared with method) |
| FIELL | BRD-SG-02986 | `FIELL.sg` |
| Fasclean | BRD-SG-03022 | `Fasclean Factory Store.sg` |
| For Furry Friends | BRD-SG-02714 | `For Furry Friends SG` |
| Fresh HY | BRD-SG-01231 | `Walch SG Official Store` (shared with Walch) |
| GONG100 | BRD-SG-02338 | `Minimolife Official Store` |
| Guardsman | BRD-SG-03558 | `Guardsman Official` |
| HG | BRD-SG-02519 | `HG Singapore`, `Hi-Glitz Official Store` |
| Harpic | BRD-SG-02390 | `Dettol Official Store` (RB parent, shared with Dettol), `RB Home Official Store` |
| Hospicare | BRD-SG-03133 | `Zappy & HospiCare by Freshening` (shared with Zappy) |
| KARCHER | BRD-SG-03707 | `Karcher Singapore Official Store` |
| Kincho | BRD-SG-03873 | `Mandom Official Store` (shared) |
| Lion | BRD-GLOBAL-00873 | `LION Official Store` |
| MAMAFOREST | BRD-SG-01769 | `ToppingsKids Official Store` |
| MOVA | BRD-SG-03856 | `Mova Official Store` |
| Magiclean | BRD-SG-00790 | `Kao Official Store` (Kao owns Magiclean) |
| Making Lifestyle Solutions | BRD-SG-02235 | `M.L.S Official Store` |
| Mr Muscle | BRD-SG-01650 | `SC Johnson Official Store` (SCJ owns Mr Muscle) |
| Nature Love Mere | BRD-GLOBAL-01902 | `The Dinky Shop` |
| Netcare | BRD-SG-03725 | `Netcare.Singapore Official Store` |
| Nichigo | BRD-SG-03418 | `Mandom Official Store` (shared) |
| Nippon Home | BRD-SG-02951 | `Nippon Home Official Store` |
| Offspring | BRD-SG-00762 | `Offspring Official` |
| Philips | BRD-GLOBAL-00417 | `Philips Home Appliances Store` |
| SELLEYS | BRD-SG-02026 | `Selleys Official Store` |
| Seaways | BRD-SG-00551 | `Seaways Store SG` |
| Shark | BRD-SG-02990 | `SharkNinja` |
| SimplyGood | BRD-SG-00814 | `SimplyGood` |
| SukGarden | BRD-SG-01586 | `SukGarden Official Store` |
| TINECO | BRD-SG-01846 | `Tineco` |
| The Pink Stuff | BRD-SG-02069 | `The Pink Stuff Official Store` |
| Two Steps Cleaning | BRD-SG-02232 | `twostepscleaning` |
| Uwant | BRD-SG-04802 | `Uwant Official Store` |
| Walch | BRD-SG-00491 | `Walch SG Official Store` (shared with Fresh HY) |
| Wd-40 | BRD-SG-03281 | `WD40 Official Store Singapore` |
| Yuri | BRD-GLOBAL-01555 | `Yuri Shop` |
| Zappy | BRD-SG-01585 | `Zappy & HospiCare by Freshening` (shared) |
| dyson | BRD-SG-03490 | `Dyson Official Store` |
| method | BRD-SG-01091 | `Method Official Store`, `Corlison Official Store` (shared with Ecover) |
| molton | BRD-SG-03261 | `MOLTON .sg` |

**Excluded multi-brand retailers (regardless of Mall badge)** — identified objectively as carrying ≥2
distinct in-scope brands, plus known SG multi-category retailers per `docs/llm-extraction-rules.md` §4
pattern (Watsons is explicitly named there for beauty; extending the same logic to household/variety
here): `Watsons Singapore Official Store` (14 distinct brands), `Ohere! Official Store` (8), `myCK_online`
(7), `MR DIY Official Store` (5, hardware/variety retailer), `JassByte` (5, reseller), `ModernHome
Official Store` (3), `Prestigio Delights Official` (3), `gelli888xl.sg` (3, reseller), `DON DON DONKI
Official Store` (Japanese multi-category retailer), `JAWStore - Puritan's Pride` (supplement retailer),
`Moda Paolo Official Store` (fashion retailer selling unrelated cleaning SKUs), `STEVE & LEIF Official
Store`, `Aromantic_SG`, `Weloveourkids`, `RedMan Official Store`, `dbxjp002.sg`, `BUV·DR`, `Ms.lin shop`,
`COBEN`, `suncanjun003.sg`, `amao12fp.sg`, `chulisia` (last several are $0–13 GMV tail resellers with no
material impact either way).

**Brands with no official store found (Pass 2 only)** — every scoped brand not listed in the allowlist
table above, including several materially significant ones that only appeared via excluded multi-brand
retailers or not at all in the Mall-badged pool: `BRD-UNDEFINED` (20.03% of GMV — see note above), `999`
(BRD-TH-01500, rank #6, 24.8K GMV — no Mall presence found at all despite high rank; flag for extra Pass 2
attention), `Clorox`, `krafter`, `Jackie`, `Supersteam`, `Floral`, `bio-home`, `Jomo`, `Mr McKenic`,
`KINBATA`, `Dr.Beckmann`, `Weiman`, `Kobayashi`, `Aimedia`, `TP 706`, `mixshop`, `Consolidated`, `Bref`,
`Bar Keepers Friend`, `Roborock`, `SOFIX`, `Agape Nature`, `KLEEN UP`, `Goo Gone`, `Green Kulture`,
`POWERMAX`, `Imakara`, `Cosway`, `Deep`, `cafetto`, `G-Natural`, `Koala Home Lifestyle`, `SingCrop`,
`AROMA`, `Kao`, `bin buddy`, `Care`, `OxiClean`, `East Chem`, `KLEENSO`, `Hair+`, `SinCare`, `Weicon`,
`B Lock`, `Kiss`, `Amway`, `Floor Master`,
`MR PERFECT`, `Oxygen`, `Old English`, `Singapore Collection`, `Lemon`, `Clean Conscience`, `Jif`, `All`,
`Fast`, `Lysol`, `Hoover`, `Day&`, `Melaleuca`, `Howard`, `IN`, `Home`.

---

## Scale

| Metric | Value |
|--------|-------|
| Total rows (month 2026-06) | 44,086 |
| Total distinct products (month 2026-06) | 17,476 |
| Total GMV (raw) | SGD 1,158,700.96 |
| Total GMV (GWP-zeroed) | SGD 1,158,226.50 |
| Official-store rows (all Mall-badged, unfiltered) | 3,016 |
| Official-store distinct products (all Mall-badged, unfiltered) | 1,884 |
| Rule A — top-95%-GMV products | 1,520 |
| Rule B — official-store listings (scoped to allowlist, post multi-brand exclusion) | subset of 1,884; exact count pending Pass 1 query |

Official-store row count (3,016 / 1,884 products) is not large enough to require sampling — full
vision-read of the allowlist-scoped subset is feasible in this session per
`docs/headless-runbook.md`'s coverage-first guidance. This is roughly an order of magnitude smaller than
the `shopee_sg_shampoo` 187,902-row pool that caused a prior session to correctly block itself — no
scale blocker here.

---

## Existing map rows (Step 1)

| Source | Count |
|--------|-------|
| LLM | 0 |
| HUMAN | 0 |
| Total | 0 |

Zero pre-existing rows for `master_table='shopee_sg_household_cleaner'` — genuine first run, confirmed
live (also checked for `master_table LIKE '%household%'` variants — none found). Matches the wrapper's
pre-check. `docs/categories/STATUS.md`'s "⏳ Keyword only" designation for this category is stale/wrong —
no keyword seed was ever run here despite the dashboard row implying baseline HUMAN coverage exists.

---

## Scope — What's In vs Out

**In scope:** chemical household cleaning products — multi-purpose cleaners, floor cleaners, toilet
cleaners, glass/window cleaners, bathroom/kitchen cleaners, degreasers, descalers, stain removers,
disinfectant sprays/wipes, appliance-specific cleaning solutions (washing machine cleaner, dishwasher
cleaner, robot-vacuum/mop cleaning fluid), drain cleaners/unclogging agents, rust/mold removers, fabric
protector sprays (e.g. 3M Scotchgard).

**Out of scope (leave NULL):** the physical appliances/tools themselves (vacuum cleaners, mops, robot
vacuums, pressure washers) even when sold by a brand that also sells cleaning solution in this table;
non-cleaning accessories from a cleaning brand (e.g. a sink caddy); water bottles/thermoses/kettles sold
under a brand also known for descaling products; skin/personal cleansers miscategorized into this table
(e.g. "3M Cavilon No-Rinse Skin Cleanser" is a medical skin product, not a household cleaner).

**Edge cases:**
- Appliance-brand cleaning solutions (Tineco, Dyson, Shark, Roborock, Dreame, Bosch, Miele, Zojirushi,
  Electrolux, Karcher, Philips, Stanley, CamelBak) — IN SCOPE when the product is the cleaning
  fluid/tablet/descaler itself; OUT OF SCOPE if the listing is the appliance/tool/accessory.
- `simplehuman` did not reach the 95% GMV threshold as a brand, so its mixed catalog (cleaning tablets +
  sink caddy) is out of scope entirely for this run regardless.

---

## Taxonomy Design Notes

**Product line extraction approach:**
- Most brands: extract from `sku_name`/`sku_name_EN` — cleaning-solution product lines are usually
  explicit (e.g. "OneUp", "HydroVac Multi-Surface Concentrate", "Clean & Care").
- Parent/distributor stores (Mandom → Nichigo/Kincho/Earth; Corlison → method/Ecover; Dettol Official
  Store → Dettol/Harpic; Walch SG Official Store → Walch/Fresh HY; Zappy & HospiCare → Zappy/Hospicare):
  disambiguate brand via `brand_from_image`/`sku_name`, not the store name.

**Size extraction notes:**
- Primary units: ml / L / g / kg. Concentrate products often state "uses" or dilution ratio in addition
  to volume — extract the stated volume, not the derived-uses count.

**Known difficult products:**
- `BRD-UNDEFINED` products (20% of GMV, no official store) — highest-priority Pass 2 target; identify
  real brand from sku_name/image wherever possible per the note above.
- `999` (BRD-TH-01500, rank #6 by GMV, no official store found) — route via bulk text-matching against
  the "999" token in `sku_name`; verify this isn't a brand-detection artifact before treating as a
  genuine brand.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-29 | Pre-run research | STATUS.md incorrectly shows "⏳ Keyword only" for this category; live check found 0 HUMAN and 0 LLM rows | Documented as finding; proceeding as genuine first run per wrapper pre-check |
| 2026-07-29 | Pre-run research | Initial unfiltered brand-GMV ranking suspected of appliance-cluster contamination (Tineco, Dyson, Shark, Roborock, etc.) | Spot-checked sku_names — confirmed legitimate cleaning-solution products, not appliances; brand list retained as-is |

---

## Targeted QA Fix Brief

(Not applicable this session — this is Full Rebuild / initial extraction, not a QA fix pass.)

---

## Scripts

| Script | Purpose |
|--------|---------|
| (none — this session performs extraction directly via Claude Code multimodal reading, not external scripts) | |

---

## Map Row Counts (as of last run)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 0 | Pre-session baseline; updated after Pass 1/2 |
| HUMAN | 0 | No keyword seed ever ran for this category |
| NULL (unmapped) | 17,476 | Full category, pre-session |
