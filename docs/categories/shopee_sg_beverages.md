# shopee_sg_beverages — Category Context

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete |
| LLM Pass 2 | ✅ Complete |
| GMV Coverage | 96.8%+ (2026-06, after 2026-07-29 top-up + second top-up session) |
| Last run | 2026-07-29 (second top-up session — 1 product resolved, 4 confirmed legitimately OOS) |
| Current MAX taxonomy_id | SKU-210807 (this category's own block; overall table MAX may be higher from concurrent sessions) |

**Note on STATUS.md drift:** `docs/categories/STATUS.md` lists `sg_beverages` as "⏳ Keyword only," but live
`product_taxonomy_map` has **zero** rows for `master_table = 'shopee_sg_beverages'` (source='HUMAN' or 'LLM').
No keyword-seed pass has actually run for this table. Documented state disagrees with live state — flagging
per session convention, not treating as a blocker. Consequence: the QA-gate HUMAN+LLM coexistence check is
trivially 0, and there is no HUMAN-row cleanup step needed after this run.

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-206029–206232 | Pass 1 OFFICIAL (204 entries, from 207 official-store products across 48 allowlisted merchants) |
| SKU-206233–207476 | Pass 2 RESELLER (1,244 entries, from 1,465 remaining in-scope products via bulk regex + word-overlap consolidation) |
| SKU-207477–208028 | Unused remainder of claimed 2,000-slot block |
| SKU-210049–210356 | 2026-07-29 top-up, initial pass (308-slot claim, scenario `taxonomy_topup`) — 208 entries written at SKU-210049–210256, then superseded by the correction pass below and left **orphaned** (no map row references them; not deleted). SKU-210257–210356 never used |
| SKU-210357–210606 | 2026-07-29 top-up, correction pass (250-slot claim, scenario `taxonomy_topup`) — 244 live entries at SKU-210357–210600. SKU-210601–210606 unused remainder |
| SKU-210807–211006 | 2026-07-29 second top-up session (200-slot claim, scenario `taxonomy_topup`) — 1 live entry at SKU-210807 (Allre Pre-Meal Effervescent Tablet, current MAX for this category). SKU-210808–211006 unused remainder |

---

## Brand Scope (GMV threshold 95%, month 2026-06-01)

**177 brands** in scope (GWP-zeroed product GMV, `flag_GWP` products' GMV set to 0 before ranking; brand-level
GMV = `SUM` of GWP-zeroed product GMV per `product_brand_map.brand_id`). Category total GMV (all 1,234 distinct
brand buckets): **SGD 1,966,805**. The 95% cumulative threshold falls at rank 177 (cum_frac 0.9495).

**`BRD-UNDEFINED` is rank 1 (7.34% of category GMV, SGD 144,430)** — kept in the ranking and denominator rather
than excluded. It is not a brand, but it represents real, extractable product-level GMV (per the TH changelog
precedent: brand-map assignment failures don't excuse a product from taxonomy — e.g. phonetically-identifiable
Coke/Pepsi products with `BRD-UNDEFINED` still get mapped to the correct taxonomy entry regardless of the brand
bucket they landed in upstream). Products under this bucket are extracted from `sku_name`/image like any other;
their real brand (if determinable) informs `product_taxonomy.brand_id`, independent of what `product_brand_map`
assigned.

**Category-hierarchy check (ran before finalizing this list):** `category_3_EN` breakdown for 2026-06-01 shows
a single coherent vertical — Water (785,707), Juice & Juice Vinegar (488,047), Energy & Isotonic Drinks
(352,815), Traditional & Herbal Drinks (240,708), Others (92,392), Drink Toppings (7,224) — all genuinely
beverage subcategories. **No keyword pre-filter gate was needed on the brand-GMV ranking** (llm-extraction-rules.md
§8 applies only to mixed-content source tables like `shopee_th_body_wash`'s hand-wash contamination; this table has none).

**Known brand_id noise (do not propagate into extraction):** `&Honey` (BRD-GLOBAL-00237) is a haircare brand
in `brand_dict` that PRODUCT_NAME_SCAN mismatched onto honey-flavored juice/drink products (token collision on
the word "honey"). `12/+＝` (BRD-SG-08876, rank 81) is a garbled-brand defect matching the exact pattern in
`llm-extraction-rules.md` §11's Jul 22 changelog entry (reseller watermark/username misread as brand). Neither
should be written into `canonical_name` or `product_taxonomy.brand_id` — re-derive the real brand from
`sku_name`/image per product during extraction; taxonomy mapping does not require brand_id agreement with
`product_brand_map` (see llm-extraction-rules.md Thai-brand-phonetic precedent, applies the same way here).

Full 177-brand list (rank, brand_id, canonical_name, GMV SGD, cumulative fraction):

| Rank | Brand | brand_id | GMV (SGD) | Cum % |
|---|---|---|---|---|
| 1 | Undefined | BRD-UNDEFINED | 144,429.63 | 7.34% |
| 2 | Dasani | BRD-SG-00656 | 124,789.86 | 13.69% |
| 3 | 100PLUS | BRD-TH-00610 | 124,348.58 | 20.01% |
| 4 | evian | BRD-GLOBAL-00239 | 90,540.88 | 24.61% |
| 5 | Ice Mountain | BRD-SG-00872 | 80,790.89 | 28.72% |
| 6 | Spritzer | BRD-SG-00957 | 69,330.39 | 32.25% |
| 7 | Yeo's | BRD-TH-02505 | 59,823.79 | 35.29% |
| 8 | Elements | BRD-SG-01314 | 56,370.54 | 38.15% |
| 9 | Taishin | BRD-SG-01354 | 52,252.42 | 40.81% |
| 10 | Monster Energy | BRD-SG-01206 | 35,965.05 | 42.64% |
| 11 | Three Legs Brand | BRD-SG-01426 | 34,857.83 | 44.41% |
| 12 | POLAR | BRD-SG-01413 | 29,396.54 | 45.91% |
| 13 | UFC Refresh | BRD-SG-01473 | 28,257.81 | 47.34% |
| 14 | Red Bull | BRD-GLOBAL-01413 | 26,164.05 | 48.67% |
| 15 | Pocari Sweat | BRD-SG-00448 | 25,810.70 | 49.99% |
| 16 | HSC | BRD-SG-00944 | 24,845.79 | 51.25% |
| 17 | TEA | BRD-SG-03175 | 21,895.26 | 52.36% |
| 18 | San Pellegrino | BRD-GLOBAL-00862 | 21,715.59 | 53.47% |
| 19 | PomeFresh | BRD-SG-01644 | 21,263.32 | 54.55% |
| 20 | Perrier | BRD-GLOBAL-01102 | 20,270.57 | 55.58% |
| 21 | TUTTI FRUTTI | BRD-SG-01631 | 19,367.79 | 56.56% |
| 22 | F&N | BRD-GLOBAL-00345 | 19,086.25 | 57.53% |
| 23 | Apple Cider | BRD-SG-09544 | 18,408.19 | 58.47% |
| 24 | pH balancer | BRD-SG-01717 | 16,378.10 | 59.30% |
| 25 | Ribena | BRD-SG-01932 | 15,680.70 | 60.10% |
| 26 | Fiji | BRD-SG-04489 | 15,485.15 | 60.89% |
| 27 | Ice Cool | BRD-SG-02174 | 15,380.04 | 61.67% |
| 28 | YOU.C1000 | BRD-SG-01957 | 14,695.96 | 62.42% |
| 29 | Chi Forest | BRD-GLOBAL-01226 | 14,648.24 | 63.16% |
| 30 | Lakewood | BRD-SG-02034 | 13,722.12 | 63.86% |
| 31 | MARIGOLD | BRD-SG-01742 | 13,574.99 | 64.55% |
| 32 | RADIANT ORGANIC | BRD-SG-02459 | 12,657.92 | 65.19% |
| 33 | UFC | BRD-GLOBAL-01611 | 12,506.05 | 65.83% |
| 34 | Glaceau Vitaminwater | BRD-SG-01921 | 12,464.47 | 66.46% |
| 35 | Volvic | BRD-SG-00813 | 12,130.69 | 67.08% |
| 36 | Good Lady | BRD-SG-01155 | 12,113.82 | 67.69% |
| 37 | Pere Ocean | BRD-SG-01759 | 11,851.07 | 68.30% |
| 38 | Tropicfarmers | BRD-SG-02441 | 11,310.24 | 68.87% |
| 39 | Kagome | BRD-TH-03079 | 11,217.06 | 69.44% |
| 40 | POKKA | BRD-GLOBAL-00722 | 11,077.48 | 70.01% |
| 41 | Bragg | BRD-GLOBAL-01777 | 11,050.61 | 70.57% |
| 42 | Acqua Panna | BRD-SG-00603 | 10,874.80 | 71.12% |
| 43 | Voss | BRD-GLOBAL-01198 | 10,652.24 | 71.66% |
| 44 | Minute Maid | BRD-SG-01874 | 10,263.34 | 72.18% |
| 45 | SCIENCE IN SPORT | BRD-SG-02191 | 9,202.31 | 72.65% |
| 46 | TRADITIONAL MEDICINALS | BRD-SG-02169 | 9,180.01 | 73.12% |
| 47 | Abbott | BRD-GLOBAL-00056 | 8,977.54 | 73.57% |
| 48 | PureWater | BRD-SG-02130 | 8,957.89 | 74.03% |
| 49 | SUNFARM | BRD-SG-02140 | 8,860.40 | 74.48% |
| 50 | Coco Republic | BRD-SG-01855 | 8,515.04 | 74.91% |
| 51 | Apple | BRD-SG-05608 | 8,399.48 | 75.34% |
| 52 | Zam Zam | BRD-SG-04712 | 8,339.85 | 75.76% |
| 53 | FIZZ HYDRATION | BRD-SG-02487 | 8,248.35 | 76.18% |
| 54 | Cellucor | BRD-SG-02446 | 7,898.92 | 76.59% |
| 55 | Wang Lao Ji | BRD-SG-02414 | 7,840.34 | 76.98% |
| 56 | Food Art | BRD-SG-03655 | 7,309.90 | 77.36% |
| 57 | Hockhua Tonic | BRD-SG-01318 | 7,306.63 | 77.73% |
| 58 | Genki Forest | BRD-TH-01319 | 7,201.40 | 78.09% |
| 59 | Jia Jia | BRD-SG-02293 | 6,886.50 | 78.44% |
| 60 | If Local Sensation | BRD-SG-02363 | 6,627.40 | 78.78% |
| 61 | Bonne | BRD-SG-02256 | 6,604.28 | 79.12% |
| 62 | All | BRD-SG-06567 | 6,559.10 | 79.45% |
| 63 | LUSOL | BRD-SG-04596 | 6,440.29 | 79.78% |
| 64 | Foresta | BRD-GLOBAL-00493 | 5,817.14 | 80.07% |
| 65 | LMNT | BRD-SG-02465 | 5,731.87 | 80.36% |
| 66 | MunGyeong MISO | BRD-SG-02605 | 5,691.52 | 80.65% |
| 67 | Cocomax | BRD-GLOBAL-02088 | 5,663.39 | 80.94% |
| 68 | Haitai | BRD-SG-02676 | 5,574.08 | 81.23% |
| 69 | Cocolife | BRD-SG-02577 | 5,556.10 | 81.51% |
| 70 | TongRenTang | BRD-SG-02554 | 5,205.16 | 81.77% |
| 71 | Three Legs Cooling Water | BRD-SG-04390 | 5,185.20 | 82.04% |
| 72 | Teazen | BRD-TH-02380 | 5,120.71 | 82.30% |
| 73 | Gatorade | BRD-SG-03302 | 5,098.87 | 82.56% |
| 74 | Huiji | BRD-SG-01486 | 4,904.04 | 82.81% |
| 75 | Georgia's Natural | BRD-SG-03087 | 4,897.08 | 83.05% |
| 76 | Eu Yan Sang | BRD-SG-00522 | 4,871.60 | 83.30% |
| 77 | COCOLOCO | BRD-SG-02810 | 4,695.40 | 83.54% |
| 78 | Cactus | BRD-SG-02657 | 4,683.68 | 83.78% |
| 79 | Herbal Sense | BRD-SG-02096 | 4,637.08 | 84.01% |
| 80 | Lemon | BRD-TH-03174 | 4,608.59 | 84.25% |
| 81 | 12/+＝ (garbled brand — re-derive, see note above) | BRD-SG-08876 | 4,443.62 | 84.47% |
| 82 | GlucosCare | BRD-SG-02467 | 4,432.46 | 84.70% |
| 83 | Nuskin | BRD-GLOBAL-00872 | 4,251.00 | 84.92% |
| 84 | Rabenhorst | BRD-SG-03694 | 4,051.90 | 85.12% |
| 85 | Sangha | BRD-SG-02814 | 3,970.00 | 85.32% |
| 86 | Shih Chuan | BRD-SG-03051 | 3,910.92 | 85.52% |
| 87 | Fuji | BRD-GLOBAL-01242 | 3,783.18 | 85.72% |
| 88 | Optimum Nutrition | BRD-GLOBAL-02165 | 3,659.18 | 85.90% |
| 89 | SUPERnatural+ | BRD-SG-03052 | 3,646.00 | 86.09% |
| 90 | FANCL | BRD-GLOBAL-00856 | 3,625.34 | 86.27% |
| 91 | BOTO | BRD-GLOBAL-02016 | 3,624.05 | 86.46% |
| 92 | Naturally Plus | BRD-SG-04353 | 3,624.00 | 86.64% |
| 93 | LOTTE | BRD-GLOBAL-01727 | 3,594.35 | 86.82% |
| 94 | J&J | BRD-TH-01226 | 3,564.60 | 87.00% |
| 95 | 内廷上用 | BRD-SG-01840 | 3,536.32 | 87.18% |
| 96 | EHPlabs | BRD-SG-02922 | 3,533.40 | 87.36% |
| 97 | &Honey (brand_id noise — see note above) | BRD-GLOBAL-00237 | 3,493.95 | 87.54% |
| 98 | AQUA | BRD-SG-03094 | 3,441.40 | 87.72% |
| 99 | Royal | BRD-GLOBAL-01748 | 3,264.00 | 87.88% |
| 100 | chunhoncare | BRD-SG-03030 | 3,258.50 | 88.05% |
| 101 | Watsons | BRD-GLOBAL-00640 | 3,243.20 | 88.21% |
| 102 | Beacon | BRD-SG-04532 | 2,805.84 | 88.36% |
| 103 | Zico | BRD-SG-03408 | 2,802.90 | 88.50% |
| 104 | Cocobella | BRD-GLOBAL-01398 | 2,610.00 | 88.63% |
| 105 | Sigolstory | BRD-SG-03179 | 2,607.05 | 88.76% |
| 106 | GHOST | BRD-SG-03810 | 2,569.92 | 88.89% |
| 107 | Laoshan | BRD-SG-03961 | 2,542.60 | 89.02% |
| 108 | Dragon Brand | BRD-SG-01403 | 2,531.99 | 89.15% |
| 109 | Hydradrinks | BRD-SG-02835 | 2,529.88 | 89.28% |
| 110 | Tenplus | BRD-SG-02948 | 2,521.50 | 89.41% |
| 111 | Liquid IV | BRD-GLOBAL-03155 | 2,521.02 | 89.54% |
| 112 | High5 | BRD-SG-03303 | 2,416.07 | 89.66% |
| 113 | BAWANG | BRD-SG-03388 | 2,398.52 | 89.78% |
| 114 | PURE Sports Nutrition | BRD-SG-03195 | 2,343.80 | 89.90% |
| 115 | ARK+ | BRD-SG-03639 | 2,296.00 | 90.02% |
| 116 | Pigeon | BRD-GLOBAL-00381 | 2,194.52 | 90.13% |
| 117 | Jeju Samdasoo | BRD-SG-03669 | 2,193.93 | 90.24% |
| 118 | Sparkle | BRD-GLOBAL-00184 | 2,187.80 | 90.35% |
| 119 | Zestiva | BRD-SG-02846 | 2,146.52 | 90.46% |
| 120 | Taiwan Collection | BRD-GLOBAL-01122 | 2,142.81 | 90.57% |
| 121 | Onsensui99 | BRD-SG-02299 | 2,141.28 | 90.68% |
| 122 | Naturally | BRD-TH-02908 | 2,131.50 | 90.79% |
| 123 | Core | BRD-TH-01364 | 2,120.20 | 90.89% |
| 124 | IN | BRD-SG-06662 | 2,114.62 | 91.00% |
| 125 | Gerolsteiner | BRD-SG-04500 | 2,092.02 | 91.11% |
| 126 | Nongfu Spring | BRD-SG-01383 | 2,088.74 | 91.21% |
| 127 | Helmig's | BRD-SG-03068 | 2,087.80 | 91.32% |
| 128 | NutrioneLife | BRD-GLOBAL-02125 | 1,937.48 | 91.42% |
| 129 | TAYLOR | BRD-SG-03398 | 1,926.92 | 91.52% |
| 130 | hanmi | BRD-GLOBAL-01564 | 1,914.78 | 91.61% |
| 131 | PopoMama | BRD-SG-03645 | 1,911.10 | 91.71% |
| 132 | Ye Shu Pai | BRD-SG-03671 | 1,890.00 | 91.81% |
| 133 | Living Healthy | BRD-SG-03008 | 1,845.00 | 91.90% |
| 134 | Balloon | BRD-TH-02126 | 1,841.09 | 92.00% |
| 135 | Rokeby Farms | BRD-SG-02942 | 1,816.30 | 92.09% |
| 136 | Ripple Hydration | BRD-SG-03727 | 1,697.00 | 92.17% |
| 137 | Zaram Food | BRD-SG-03755 | 1,696.60 | 92.26% |
| 138 | Switzer | BRD-SG-03640 | 1,694.69 | 92.35% |
| 139 | Paldo | BRD-TH-03596 | 1,683.13 | 92.43% |
| 140 | EDEN | BRD-SG-07251 | 1,639.67 | 92.52% |
| 141 | Ri-o | BRD-TH-01356 | 1,602.30 | 92.60% |
| 142 | Coca-Cola | BRD-GLOBAL-00145 | 1,591.25 | 92.68% |
| 143 | SidoMuncul | BRD-SG-03983 | 1,566.90 | 92.76% |
| 144 | Chung Jung One | BRD-SG-03771 | 1,487.73 | 92.83% |
| 145 | Qoo | BRD-SG-02511 | 1,457.29 | 92.91% |
| 146 | Bean | BRD-SG-01017 | 1,421.91 | 92.98% |
| 147 | CJ | BRD-SG-04289 | 1,416.18 | 93.05% |
| 148 | Keto | BRD-SG-04167 | 1,400.07 | 93.12% |
| 149 | Atomy | BRD-GLOBAL-00813 | 1,395.88 | 93.19% |
| 150 | Dr. LEAN | BRD-GLOBAL-02172 | 1,393.60 | 93.26% |
| 151 | Asia Farm | BRD-SG-04173 | 1,392.30 | 93.34% |
| 152 | Jin Man Tang | BRD-SG-03103 | 1,385.70 | 93.41% |
| 153 | H-TWO-O | BRD-SG-04188 | 1,365.54 | 93.48% |
| 154 | Coco Island | BRD-SG-03946 | 1,329.00 | 93.54% |
| 155 | Get | BRD-TH-01966 | 1,305.90 | 93.61% |
| 156 | Nestle | BRD-GLOBAL-00059 | 1,299.40 | 93.68% |
| 157 | Care | BRD-GLOBAL-00623 | 1,290.31 | 93.74% |
| 158 | Le Minerale | BRD-SG-02912 | 1,284.90 | 93.81% |
| 159 | Sunquick | BRD-SG-04910 | 1,264.88 | 93.87% |
| 160 | CNI | BRD-SG-05633 | 1,260.04 | 93.93% |
| 161 | vitamin village | BRD-SG-03772 | 1,253.00 | 94.00% |
| 162 | JA Aoren | BRD-SG-03957 | 1,250.74 | 94.06% |
| 163 | Fever-Tree | BRD-SG-02482 | 1,249.70 | 94.13% |
| 164 | BEBECOOK | BRD-SG-04174 | 1,244.88 | 94.19% |
| 165 | Simply Natural | BRD-SG-03023 | 1,212.00 | 94.25% |
| 166 | Schweppes | BRD-TH-00294 | 1,207.10 | 94.31% |
| 167 | Nai Xue Tea | BRD-SG-04739 | 1,206.20 | 94.37% |
| 168 | Nilofa | BRD-SG-03836 | 1,183.00 | 94.43% |
| 169 | Vico | BRD-SG-04269 | 1,181.59 | 94.49% |
| 170 | Pristine | BRD-SG-02668 | 1,158.00 | 94.55% |
| 171 | Guinness | BRD-GLOBAL-01211 | 1,150.00 | 94.61% |
| 172 | Raw C | BRD-SG-04648 | 1,121.59 | 94.67% |
| 173 | Bodiez | BRD-SG-06067 | 1,119.81 | 94.72% |
| 174 | 9 Star | BRD-SG-03563 | 1,110.00 | 94.78% |
| 175 | Bloom | BRD-GLOBAL-02875 | 1,109.20 | 94.84% |
| 176 | Master Kong | BRD-SG-02747 | 1,103.20 | 94.89% |
| 177 | Jaade | BRD-SG-04107 | 1,085.60 | 94.95% |

Brands excluded from scope (below 5% GMV tail, rank 178+ of 1,234 total brand buckets): the long tail — every
brand not listed above.

---

## Official Store Allowlist (Pass 1)

Built by: for each of the 177 in-scope brands, `SELECT DISTINCT merchant_name WHERE merchant_badge='Shopee Mall'`
joined via `product_brand_map` → 165 raw (brand, merchant_name) pairs across 84 distinct merchant names.

**Multi-brand retailer exclusion methodology:** queried `COUNT(DISTINCT brand_id)` per Mall-badged merchant
across **all** Mall products in this table (not just the 177 in-scope brands), then excluded every merchant
carrying **≥3 distinct brand_id buckets** — the auditable generalization of the fixed named list in
llm-extraction-rules.md §4 (Watsons/BigC/Lotuss-style retailers), since none of that fixed list's Thai grocery
chains (BigC, Lotuss, Tops, Villa Market) appear in SG data. 36 merchants met this threshold and are excluded:
RedMan Official Store (21 brands), K-Market by Koryo Trading (20), Guardian SG Official Store (16), Prestigio
Delights Official (14), Cold Storage Official Store (10), BẾP CỦA MẸ ONICI (9), Watsons Singapore Official
Store (9), cukkcukk's Sundries Official Store (9), Ren Ren Pharmacy Official (8), Food People Official Store
(7), Farmasi C S (7), DON DON DONKI Official Store (6), 大買家網路店 Save & Safe Official (6), simplyactiveasia
(5), CC Herb Health Official (5), Arumi Health (5), ZLX Hardware Wholesaling Official (4), SL Foods Official
Store (4), eslite 誠品 Flagship Bookstore (4), Woah Group Official Store (4), Signature Market Official
Store✅ (4), Delyco Official Store (4), QQ Trading Bubble Tea +Dessert Mart (4), BIG Pharmacy (4), Nutrifres
(4), Shih-Chuan Food Official (4), Green Earth Organic Official Store (4), Nutrition Asia (3), Mount Fuji
Official Store (3), ZENXIN ORGANIC OFFICIAL STORE (3), ToppingsKids Official Store (3), EverCura (3), Nature's
Glory Organic Official (3), Mediduplex Official store (3), Decathlon Official Store (3). Also manually excluded
despite <3-brand appearance in the in-scope-177 slice (general/multi-category retailers by well-known name, not
brand principals): **Mustafa Centre Official Store** (large SG department store), **Bake With Yen SG** (baking
supplies retailer), **jt0886 Official** (generic reseller-style store name).

**Parent-company store exception (kept despite 5 distinct brands):** **Coca-Cola** — carries its own brand plus
Glaceau Vitaminwater, Minute Maid, Monster Energy, and Zico. This is the P&G/Unilever/Lion pattern from
llm-extraction-rules.md §4 (a corporate distributor's own storefront selling its portfolio, not a third-party
multi-brand reseller) — Pass-1-eligible for all five.

**Final allowlist: 54 (brand, merchant) pairs across 48 distinct merchant names.** Many resolve to
`BRD-UNDEFINED` in `product_brand_map` (brand assignment failed upstream) but are legitimate single-brand own
official stores by name — brand will be read from `sku_name`/image during Pass 1 extraction, not taken from the
map's (failed) brand_id.

| Brand (per product_brand_map) | brand_id | Official Store Merchant Name |
|---|---|---|
| Apple | BRD-SG-05608 | Taiwan Want Want Official Store |
| Apple Cider | BRD-SG-09544 | Miss Dou's Groceries Official |
| Apple Cider | BRD-SG-09544 | NE:AR Official Store |
| Asia Farm | BRD-SG-04173 | Asia Farm SG Official Store |
| BOTO | BRD-GLOBAL-02016 | BOTO OFFICIAL STORE |
| Bloom | BRD-GLOBAL-02875 | Purple Cane Tea |
| Bragg | BRD-GLOBAL-01777 | JAWStore - Puritan's Pride |
| Bragg | BRD-GLOBAL-01777 | myCK_online |
| Chi Forest | BRD-GLOBAL-01226 | Chi Forest Official Store |
| Chung Jung One | BRD-SG-03771 | ChungJungOne O'food Store |
| Coco Island | BRD-SG-03946 | Mingfa Fishball Official Store |
| Dr. LEAN | BRD-GLOBAL-02172 | Dr.Lean Korea SG |
| Dragon Brand | BRD-SG-01403 | Dragon Brand BN Official Store |
| EHPlabs | BRD-SG-02922 | EHPlabs |
| EHPlabs | BRD-SG-02922 | EHPlabs, LLC |
| Eu Yan Sang | BRD-SG-00522 | Eu Yan Sang Official Store |
| Fiji | BRD-SG-04489 | SUTL Consumer Goods Official Store |
| GHOST | BRD-SG-03810 | Ghost Lifestyle |
| Glaceau Vitaminwater | BRD-SG-01921 | Coca-Cola |
| Haitai | BRD-SG-02676 | Hanguk Kitchen SG Official Store |
| Huiji | BRD-SG-01486 | Huiji Singapore Official Store |
| IN | BRD-SG-06662 | Hiko Drinks Official Store |
| LOTTE | BRD-GLOBAL-01727 | lotteofficial |
| Lemon | BRD-TH-03174 | Centellian24.sg |
| Minute Maid | BRD-SG-01874 | Coca-Cola |
| Monster Energy | BRD-SG-01206 | Coca-Cola |
| NutrioneLife | BRD-GLOBAL-02125 | Nutrione Official Store |
| Optimum Nutrition | BRD-GLOBAL-02165 | Optimum Nutrition Official Store |
| SCIENCE IN SPORT | BRD-SG-02191 | SIS (SCIENCE IN SPORT) |
| SUNFARM | BRD-SG-02140 | The Dinky Shop |
| Tropicfarmers | BRD-SG-02441 | Killiney Mart |
| Zestiva | BRD-SG-02846 | Zestiva Official Store |
| Zico | BRD-SG-03408 | Coca-Cola |
| chunhoncare | BRD-SG-03030 | Chunho N Care Official Store |
| Undefined | BRD-UNDEFINED | 3:15PM Official Store |
| Undefined | BRD-UNDEFINED | Cellarmaster Wines Official Store |
| Undefined | BRD-UNDEFINED | Dr's Formula Official 台塑生醫 |
| Undefined | BRD-UNDEFINED | Farmer Brand Official Store |
| Undefined | BRD-UNDEFINED | Hemille.sg |
| Undefined | BRD-UNDEFINED | Holistic Way Official Store |
| Undefined | BRD-UNDEFINED | Kinder Dreams Official Store |
| Undefined | BRD-UNDEFINED | Ksisters Official Store |
| Undefined | BRD-UNDEFINED | Long Beach SG |
| Undefined | BRD-UNDEFINED | MonMilk Official Store |
| Undefined | BRD-UNDEFINED | Nutrition Bro Official Store |
| Undefined | BRD-UNDEFINED | O2W SELECTION |
| Undefined | BRD-UNDEFINED | Sake.SG Official Store |
| Undefined | BRD-UNDEFINED | Suwany2world MART |
| Undefined | BRD-UNDEFINED | Taiwan Want Want Official Store |
| Undefined | BRD-UNDEFINED | Yuxiangyan Official Store |
| Undefined | BRD-UNDEFINED | dominge.sg |
| Undefined | BRD-UNDEFINED | quevietrl.sg |

**Multi-brand stores (excluded, listed for audit — NOT part of the allowlist):** RedMan Official Store,
K-Market by Koryo Trading, Guardian SG Official Store, Prestigio Delights Official, Cold Storage Official
Store, Watsons Singapore Official Store, BẾP CỦA MẸ ONICI, cukkcukk's Sundries Official Store, Ren Ren Pharmacy
Official, Farmasi C S, Food People Official Store, DON DON DONKI Official Store, 大買家網路店 Save & Safe
Official, simplyactiveasia, CC Herb Health Official, Arumi Health, ZLX Hardware Wholesaling Official, SL Foods
Official Store, eslite 誠品 Flagship Bookstore, Woah Group Official Store, Signature Market Official Store✅,
Delyco Official Store, QQ Trading Bubble Tea +Dessert Mart, BIG Pharmacy, Nutrifres, Shih-Chuan Food Official,
Green Earth Organic Official Store, Nutrition Asia, Mount Fuji Official Store, ZENXIN ORGANIC OFFICIAL STORE,
ToppingsKids Official Store, EverCura, Nature's Glory Organic Official, Mediduplex Official store, Decathlon
Official Store, Mustafa Centre Official Store, Bake With Yen SG, jt0886 Official.

**Brands with no official store (Pass 2 only):** all 177 in-scope brands not listed in the allowlist table
above (the large majority — most in-scope brands in this category have no Shopee Mall presence and route
entirely through Pass 2 reseller matching).

---

## Scope — What's In vs Out

**In scope:**
- Bottled/packaged water — still, sparkling, mineral, alkaline
- Juice, juice vinegar, fruit drinks
- Energy drinks, isotonic/sports drinks, electrolyte powders sold as ready-to-drink or mix
- Traditional & herbal drinks (herbal tea, tonic drinks, RTD Chinese medicinal drinks)
- Soft drinks / carbonated drinks appearing under this table's category hierarchy
- Drink toppings (bubble tea pearls, syrups) — `category_3_EN = 'Drink Toppings'`, a legitimate sub-category of
  this table, not an out-of-scope adjacent category

**Out of scope (leave NULL):**
- Non-beverage products misfiled under a beverage brand's Mall store (e.g. protein powder/supplement capsules
  sold by a sports-nutrition brand whose RTD drinks are in scope) — apply the category/type match-or-create
  gate per product-lifecycle.md §4.2, not a blanket brand exclusion
- Products where the resolved brand is clearly non-beverage (e.g. `&Honey` haircare token collision — re-derive
  the real product's brand/category from its own sku_name and image, do not inherit the mismatched brand_id's
  implied category)

**Edge cases:**
- `BRD-UNDEFINED` products: still extract normally from sku_name/image; do not skip because the brand bucket
  is unresolved.
- `12/+＝` (BRD-SG-08876): garbled brand from a misread reseller watermark/username — never write this string
  into any `canonical_name`; re-derive the real brand from the product's own packaging/title.

---

## Taxonomy Design Notes

**Product line extraction approach:**
- Most in-scope brands have no official store — expect Pass 2 (bulk SQL text-matching against Pass-1-built
  entries) to carry most of the volume; only 54 (brand, merchant) pairs / 48 distinct merchants need direct
  image reads in Pass 1.
- Corporate distributor stores (Coca-Cola) carry multiple sibling brands — disambiguate via `brand_from_image`
  per product, don't assume all products in that store are the parent brand.

**Size extraction notes:**
- Primary unit: ml / L for liquids; g for powders (electrolyte mix, herbal powder sachets).
- Bulk-pack canonical name = `x{TOTAL}` only, per llm-extraction-rules.md §2 — never a "(N packs of M)" breakdown.

**Known difficult products:**
- Products under `&Honey` (BRD-GLOBAL-00237) and `12/+＝` (BRD-SG-08876) — brand_id is noise, re-derive brand
  from sku_name/image per product (see Brand Scope section above).

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-29 | Pre-run research | STATUS.md says "Keyword only" but live `product_taxonomy_map` has 0 rows for this table | Documented; no HUMAN cleanup needed, first genuine pass |
| 2026-07-29 | Pre-run research | `&Honey` and `12/+＝` are brand_id noise (token collision / garbled-watermark) affecting rank-97/rank-81 brand buckets | Flagged for extraction-time re-derivation; not a blocker |
| 2026-07-29 | Pre-run research | Broader brand_id noise discovered during extraction: several single-common-English-word brand_dict entries (Apple, Apple Cider, Lemon, TEA, All, IN, Core, Get, Care, Bean, Keto, Royal, AQUA, Sparkle, Naturally) are PRODUCT_NAME_SCAN false positives, not real brand identities | Added to a blocklist; brand resolution fell back to official-store identity (Pass 1) or first-capitalized-token heuristic (Pass 2) instead of trusting these upstream brand_ids |
| 2026-07-29 | Pass 1+2 build | Bulk regex-based extraction (brand/size/pack from `sku_name_EN`) was used for both passes given the ~1,672-product in-scope worklist scale — Pass 1 read all 207 official-store products' text directly (no vision reads needed; `sku_name_EN` was rich enough); Pass 2 applied the same pipeline plus a word-overlap consolidation pass (Jaccard ≥0.55 within same brand/size/pack bucket) to reduce near-duplicate entries from resellers' varying phrasing (1,370→1,244 entries) | Coverage-first per Full Rebuild philosophy; exact `product_line` wording polish deferred to `targeted_qa_fix.sh` per its documented scope |
| 2026-07-29 | Post-run QA gates | G1 dual-mapped=0, G2 HUMAN+LLM coexistence=0, placeholder-leak=0, structured-fields (product_line NULL%) among LLM=0%, G5 provenance=0 | All gates pass; universe refresh eligible |
| 2026-07-29 | Post-run coverage | 95.1% GMV coverage (2026-06); 340/1,244 Pass-2 entries and several Pass-1 entries have NULL `size` (~23% each pass) — legitimately size-ambiguous multi-flavor/combo listings in many cases, but not individually verified | Flagged for `targeted_qa_fix.sh` D4 sweep |
| 2026-07-29 | Top-up coverage session | Live re-run of the STEP 0 worklist query (top-95%-cumulative-GMV, GWP-zeroed, 2026-06) found 308 in-scope products still `taxonomy_id IS NULL` — confirmed live via `bq --format=csv` (not the truncated default), matching the wrapper's pre-check count | Claimed SKU block SKU-210049–SKU-210356 (308 slots, scenario `taxonomy_topup`) atomically via `sku_block_registry` |
| 2026-07-29 | Top-up bulk match (initial pass) | Grouped the 308-row worklist by brand text-matched against this category's 1,448 existing taxonomy entries via `(brand_id, size, pack_count)` join, picking the first candidate on ties. 91 reused an existing entry; 212 minted into 208 new entries; 5 non-beverage products (supplement capsules/tablets, raw barley) left NULL | Bulk DML: 208 `product_taxonomy` rows (SKU-210049–SKU-210256) + 303 `product_taxonomy_map` rows |
| 2026-07-29 | Top-up self-review (advisor) found reuse-matching defects before declaring done | Two structural bugs in the matcher, not just imprecision: (1) brand regex required exact-spacing match, so `"100 Plus"`/`"REDBULL"` text failed to match curated brand names `"100PLUS"`/`"Red Bull"` and silently fell through to a wrong same-parent-company brand bucket (e.g. `F&N 100 Plus 500ml x24` → matched into the `F&N`-brand-id "Ice Mountain" water sub-family — a real type conflict, isotonic drink vs bottled water); (2) `(brand_id, size, pack)` alone picked the *first* candidate with no check that the candidate was actually the same product — merged distinct Yeo's flavors (Lychee → matched "Coconut Milk Beverage"), distinct Traditional Medicinals teas (8 flavors → 2 wrong entries), and picked up false-positive token overlap from merchant-name leakage ("Stop and Compare Supermarket" appearing in both the worklist title and a prior session's leaked canonical_name), expiry-date fragments, and brand-wide marketing boilerplate ("halal", "no preservatives", "Finland") | Fixed brand-matching to allow flexible digit/letter spacing; fixed a decimal-pack extraction bug (`12x1.5L` was parsed as pack=1, not 12); added token-overlap scoring requiring ≥1 genuine non-boilerplate shared word between worklist title and candidate `canonical_name`, with merchant name/expiry-date/marketing-boilerplate stripped from the comparison — rejects to mint-fresh on zero overlap |
| 2026-07-29 | Top-up correction pass | Re-ran the full match with the fixed algorithm: reuse dropped to 52 (39 of the original 91 were wrong-product matches, now correctly re-routed), mint rows consolidated into 244 new entries (up from 208, since many previously-merged products are genuinely distinct). Claimed a second block (SKU-210357–SKU-210606, 250 slots) for the additional entries rather than reuse the first (avoids reconciling partial overlap) | 244 new `product_taxonomy` INSERT rows (SKU-210357–SKU-210600) + 269 `product_taxonomy_map` UPDATE rows (correcting `taxonomy_id` on rows written this session only — no pre-existing rows touched, no deletes). The original 208 SKU-210049–210256 entries are now orphaned (no map row references them) — left in place as harmless unused entries, not deleted |
| 2026-07-29 | Top-up post-correction QA gates | Re-ran STEP 0 verbatim post-write: gap fell from 308 to exactly the 5 intentional-NULL non-beverage products (`3662052687`, `29720643558`, `795355146`, `43414114180`, `54256250306`), confirming full resolution of the addressable worklist. Gates: G1 dual-mapped(LLM)=0, G2 HUMAN+LLM coexistence=0 (checked without `--skip-coexistence`), placeholder-leak=0, structured-fields (product_line NULL%) among LLM=0%, provenance(NULL meta_agent/source)=0, platform/country populated on all new rows=0 missing. Category-total LLM map rows now 1,975 (was 1,672) | All gates pass; universe refresh eligible (not run this session — separate step) |
| 2026-07-29 | Second top-up session (re-verification) | Re-ran STEP 0 live (not trusting the wrapper's pre-check or the prior row above): worklist returned the same 5 product_ids. 4 of the 5 were genuine non-beverage exclusions on re-check (FIQ Herbs capsules, Risell Horse Placenta tablets — swallowed pill form, no dissolve-in-water signal; Organic Pearl Barley 2x500g — confirmed via image as whole dry grain for cooking, not a drink-mix powder, distinct from this category's existing barley-grass-*powder* drink entries; Okinawa Spring Turmeric 1000 Tablets — swallowed pill form). The 5th, `43414114180` ("Allre... 气泡锭/餐前发泡锭 Pre-Meal Effervescent Tablet Low Calorie & Sugar-Free"), was a genuine miss: image confirmed a dissolve-in-water effervescent tube (即冲即饮), the same product class as existing in-scope entries (Nuun Hydration tablets, Helmig's Curcumin Effervescent, GlucosCare). Brand `ALLRE` already exists as `BRD-SG-07183`; no existing taxonomy entry matched (new brand, no reuse candidate) | Claimed SKU block SKU-210807–SKU-211006 (200 slots, scenario `taxonomy_topup`). Minted 1 new entry SKU-210807 "Allre Pre-Meal Effervescent Tablet Low Calorie Sugar-Free x20" (pack_count=20, confirmed via a cropped/upscaled re-read of the product image — label text "每日1锭 20枚" ["1 tablet daily, 20 pieces"] was illegible at native resolution but legible after a 4x PIL crop-and-resize of the label region; size left NULL — no explicit weight/volume anywhere in title or on label) and mapped `43414114180` to it (source=LLM, confidence='0.7', platform='Shopee', country='SG'). Re-ran STEP 0 post-write: gap now exactly the 4 confirmed non-beverage products, all legitimately NULL. Gates re-run: G1=0, G2=0, placeholder-leak=0, structured-fields NULL%=0, provenance=0 — all pass. Universe refresh not run this session (separate step). **Repo finding**: `raw_niq_history.shopee_sg_beverages` (the size/pack fallback source per llm-extraction-rules.md §1/§2, step 3 of 4) does not exist as a BigQuery dataset in this project (`bq ls raw_niq_history` → Not Found) despite ARCHITECTURE.md documenting it as a live dataset with `product_specification`/`product_description` columns — confirmed via direct query, not a location/permissions issue. Also `brand_dict`'s live schema uses `country_scope` (not `scope` as ARCHITECTURE.md states) and has no `category` column; has extra `brand_level`/`status`/`deprecated_at`/`superseded_by` fields undocumented in ARCHITECTURE.md |

---

## Targeted QA Fix Brief

*(not applicable — this is the first extraction pass; no existing taxonomy entries to fix yet)*

---

## Scripts

| Script | Purpose |
|--------|---------|
| `pipeline/05_product_taxonomy/llm_shopee_sg_beverages/build_taxonomy.py` | Pass 1 extraction (not used — extraction performed directly by Claude Code session per headless-runbook.md) |
| `pipeline/05_product_taxonomy/llm_shopee_sg_beverages/build_p2_taxonomy.py` | Pass 2 routing (same note) |

---

## Map Row Counts (as of last run)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 1,976 | Pass 1 (207) + Pass 2 (1,465) initial build, + 303 from the 2026-07-29 top-up/correction session, + 1 from the 2026-07-29 second top-up session |
| HUMAN | 0 | Confirmed via live query 2026-07-29 — no keyword-seed pass ever ran; none created by any session either |
| NULL (unmapped) | ~13,052 (distinct products, 2026-06, outside the top-95%-cumulative-GMV in-scope worklist) | Long-tail below GMV threshold / out-of-category, plus 4 confirmed non-beverage products (supplement capsules/tablets, raw pearl barley) — legitimately left unmapped per quality-standards.md §2 |

**Scale (2026-06-01, `master_clean_niq.shopee_sg_beverages`):**
- Total rows (all months, source table): 276,841
- Distinct products (2026-06): 15,028 · Total model-rows (2026-06): 32,221
- Shopee Mall-badged: 1,032 distinct products / 2,183 rows (2026-06) — moderate scale, not tens-of-thousands;
  Pass 1 image-reading is feasible in-session once narrowed to the 48-merchant allowlist (54 brand-merchant
  pairs), not the full 1,032-product Mall pool.
- **In-scope worklist (quality-standards.md §2, Rule A ∪ Rule B, 2026-06-01):** Rule A (top-95% GWP-zeroed
  product GMV) = 1,524 products · Rule B (allowlisted official-store listings) = 207 products · overlap = 59 ·
  **union total = 1,672 products.** This is the population Pass 1 + Pass 2 must resolve and what QA D6 will be
  measured against.
