# shopee_sg_pet_food — Category Context

> First-run category. Created during headless Full Rebuild session, month 2026-06.

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete |
| LLM Pass 2 | ✅ Complete |
| Top-up coverage pass | ✅ 2026-07-23 (4 sessions today — see QA History) |
| GMV Coverage | ~97.9% GMV-weighted (2026-06) — up slightly from 97.88%. By product count: 29,729 of 39,343 (75.6%) |
| Last run | 2026-07-23 (session 4) |
| Current MAX taxonomy_id | SKU-157225 (no new entries this session — all 3 newly-resolved products bulk-matched existing catch-alls; 157226–157402 unused remainder still available for QA follow-up) |
| Remaining live gap (95%-cum-GMV, GWP-zeroed) | 241 products / SGD ~76,539 — ~222 genuine dual-species listings (cannot be single-bucketed per this category's hard rule — unchanged structural question, see QA History) and ~19 long-tail listings (OOS: aquarium/bird/reptile contamination; or genuinely unresolved even after product_specification/description and image re-check) — 3 resolved this session 4 via a new spec-field-*name* signal (untried by session 3); session 4 also GMV-triaged image-reverified the top of the "clean" dual-signal population (11/11 confirmed genuinely dual) — see QA History |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-147586–148514 | Pass 1 OFFICIAL (929 entries, text-first extraction from the 1,045-product allowlist) |
| SKU-148515–149172 | Pass 2 RESELLER — per-(brand, species, food-type) catch-alls (658 entries) |
| SKU-149173 | Single QA fix (species-mixing split, see QA History) |
| SKU-149174–149585 | Unused remainder (412 slots) — available for QA follow-up |
| SKU-153023–153310 | Top-up coverage session, 2026-07-23 (session 1) — 288 new per-(brand,species,food-type) catch-alls (`sku_block_registry` scenario `taxonomy_topup`) |
| SKU-153311–155022 | Unused remainder of session 1's top-up block (1,712 slots) — available for further QA/coverage follow-up |
| SKU-157203–157221 | Top-up coverage session, 2026-07-23 (session 2) — 19 new per-(brand,species,food-type) catch-alls, individually image-verified (`sku_block_registry` scenario `taxonomy_topup`, block 157203–157402) |
| SKU-157222–157225 | Top-up coverage session, 2026-07-23 (session 3) — 4 new per-(brand,species,food-type) catch-alls, resolved via `product_specifications`' structured `Pet Type` field (3) and image-verification of Pet-Type-vs-sku_name conflicts (1, `SKU-157225` MASTI Cat Treats) — reused session 2's still-ACTIVE unused remainder rather than claiming a fresh block (see QA History) |
| SKU-157226–157402 | Unused remainder (177 slots) — available for further QA/coverage follow-up (top-up session 4, 2026-07-23, claimed no new block and minted 0 new entries — all 3 resolved products bulk-matched existing catch-alls) |

---

## Existing map rows (live query, STEP 1)

`SELECT source, COUNT(*) FROM product_taxonomy_map WHERE master_table = 'shopee_sg_pet_food'` → **0 rows total**
(neither HUMAN nor LLM). Matches the wrapper's pre-check exactly — this is a genuine first run, not just
first-LLM-pass. `STATUS.md`'s "⏳ Keyword only" label for `sg_pet_food` is stale/inaccurate (implies HUMAN
keyword-seed rows exist); live BigQuery state shows none. Noted, not a blocker — nothing to dedupe against or
delete.

---

## Brand Scope (GMV threshold 95%, GWP-zeroed, month 2026-06)

**156 brands in scope out of 174 total brands selling in this category** (real cumulative-GMV 95% threshold —
not a fixed top-N snapshot). Computed via `SUM(CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END)` per product,
left-joined to `product_brand_map` (Shopee/SG), summed per `brand_id`, ranked descending, cumulative fraction.
Threshold crossing is inclusive of the brand that pushes cumulative GMV to/past 95% (rank 156, `Malaysia
Collection`, cum_frac 0.9502 — the prior brand, `earthmade` at rank 155, sits at 0.9495). Total category GMV
(GWP-zeroed, June 2026): ~SGD 5,689,700 across all 174 brands.

**Known brand_dict data-quality flag:** rank 141, `BRD-SG-08876` / canonical_name `"12/+＝"`, SGD 4,811 GMV —
this is the exact watermark-misread artifact documented in `docs/llm-extraction-rules.md`'s Jul 22 2026 §11
changelog entry (product `7155345414`, a reseller's own logo overlay misread as brand). It is **not a real
brand**. Excluded from Pass 1 allowlist construction (no legitimate official store exists for it anyway). Its
associated product(s) still get extracted in Pass 2 like any other in-scope product — the LLM assigns the
product's real brand from its own text/image, independent of this corrupted `brand_dict` row.

`BRD-UNDEFINED` (rank 3, SGD 175,129) is not a single brand — it's the aggregate bucket for products where
Stage 03 brand resolution failed. No official store concept applies; these route entirely through Pass 2
individual/bulk handling, with brand re-derived from the product's own sku_name/image where possible (see
`docs/llm-extraction-rules.md` §9 for phonetic-brand rerouting patterns, though SG has no Thai-script variant
of this issue).

### Full 156-brand scope list (rank, brand, brand_id, GWP-zeroed GMV SGD)

1. **Royal Canin** — `BRD-GLOBAL-00001` — 728,721
2. **ARISTO-CATS** — `BRD-SG-00563` — 178,528
3. **Undefined** — `BRD-UNDEFINED` — 175,129
4. **Aatas Cat** — `BRD-SG-00561` — 168,536
5. **Aixia** — `BRD-SG-00314` — 161,822
6. **WELLNESS** — `BRD-GLOBAL-00460` — 158,647
7. **Absolute Holistic** — `BRD-GLOBAL-00902` — 152,011
8. **Kit Cat** — `BRD-SG-00588` — 149,285
9. **Hill's SCIENCE DIET** — `BRD-SG-00670` — 141,438
10. **Daily Delight** — `BRD-SG-00664` — 139,873
11. **Orijen** — `BRD-GLOBAL-00154` — 131,610
12. **Fancy Feast** — `BRD-SG-00713` — 114,837
13. **Ziwi Peak** — `BRD-SG-00698` — 113,028
14. **Absolute Bites** — `BRD-SG-00740` — 107,665
15. **Nurture Pro** — `BRD-SG-00801` — 100,273
16. **Stella & Chewy's** — `BRD-SG-00756` — 98,788
17. **Addiction** — `BRD-TH-01768` — 88,185
18. **Pet Cubes** — `BRD-SG-00808` — 81,825
19. **Ciao** — `BRD-SG-00024` — 72,753
20. **ACANA** — `BRD-SG-00351` — 71,631
21. **Taste Of The Wild** — `BRD-SG-00061` — 70,062
22. **OMAKASE** — `BRD-SG-01027` — 68,784
23. **Underdog** — `BRD-SG-00967` — 66,835
24. **Ciao Chu Ru** — `BRD-SG-00088` — 65,245
25. **Sheba** — `BRD-SG-00097` — 57,600
26. **Loveabowl** — `BRD-SG-01072` — 53,537
27. **Food For The Good** — `BRD-SG-01098` — 53,068
28. **Feline Natural** — `BRD-SG-01257` — 52,169
29. **PROPLAN** — `BRD-GLOBAL-00137` — 49,362
30. **Fussie Cat** — `BRD-SG-01131` — 45,489
31. **K9 Natural** — `BRD-SG-01368` — 40,433
32. **Sumo Cat** — `BRD-SG-01278` — 40,072
33. **Schesir** — `BRD-SG-01144` — 38,498
34. **Friskies** — `BRD-SG-00035` — 37,163
35. **Bacon** — `BRD-SG-01317` — 37,063
36. **GoodWoof** — `BRD-SG-01333` — 36,574
37. **Bronco** — `BRD-SG-01185` — 36,223
38. **SmartHeart** — `BRD-GLOBAL-00039` — 34,053
39. **PURINA** — `BRD-GLOBAL-00538` — 32,984
40. **Instinct Pet Food** — `BRD-SG-01397` — 31,403
41. **Purina ONE** — `BRD-SG-00003` — 31,065
42. **Greenies** — `BRD-SG-00966` — 29,813
43. **Taki Pets** — `BRD-SG-01350` — 28,945
44. **Furry's Kitchen** — `BRD-SG-01425` — 26,808
45. **AFreschi Srl** — `BRD-SG-01517` — 26,712
46. **The Grateful Pet** — `BRD-SG-02302` — 26,304
47. **Natural Core** — `BRD-SG-00136` — 26,137
48. **Hill's** — `BRD-GLOBAL-00042` — 26,027
49. **Whole Animal Butchery** — `BRD-SG-01669` — 25,466
50. **Singapaw** — `BRD-SG-01506` — 24,757
51. **Knine Culture** — `BRD-SG-01698` — 24,690
52. **Finesse** — `BRD-SG-01471` — 24,551
53. **Smallbatch** — `BRD-SG-01659` — 22,030
54. **Buddy Bites** — `BRD-SG-01857` — 21,699
55. **Zealandia** — `BRD-SG-01564` — 21,339
56. **Floof** — `BRD-SG-01581` — 21,314
57. **Temptations** — `BRD-SG-00055` — 21,074
58. **Monge** — `BRD-SG-00453` — 20,774
59. **Burp** — `BRD-SG-01513` — 20,528
60. **Nutripe** — `BRD-SG-01657` — 19,926
61. **Primal** — `BRD-SG-01870` — 19,454
62. **Cesar** — `BRD-SG-00072` — 19,019
63. **Dr.Shiba** — `BRD-GLOBAL-00298` — 18,299
64. **Zignature** — `BRD-SG-01888` — 17,597
65. **The Grateful Dog** — `BRD-SG-01906` — 17,498
66. **Farmina** — `BRD-SG-00565` — 17,197
67. **Notti** — `BRD-SG-02108` — 16,582
68. **Top Ration** — `BRD-SG-01944` — 16,174
69. **Vital Essentials** — `BRD-SG-01801` — 16,032
70. **Kooky Kibble** — `BRD-SG-01818` — 15,368
71. **Angel** — `BRD-GLOBAL-01296` — 15,057
72. **Boneve** — `BRD-SG-01691` — 15,015
73. **IQ Cat** — `BRD-SG-01849` — 14,708
74. **Whimzees** — `BRD-SG-02019` — 14,470
75. **Club** — `BRD-GLOBAL-01080` — 13,795
76. **PackNPride** — `BRD-SG-01907` — 13,758
77. **Almo Nature** — `BRD-SG-02022` — 13,542
78. **Amelisa Pet & Co** — `BRD-SG-01939` — 13,527
79. **Dogcatstar** — `BRD-SG-01910` — 13,378
80. **Wanpy** — `BRD-SG-02024` — 13,361
81. **Big Dog Barf** — `BRD-SG-01751` — 13,126
82. **Woof** — `BRD-SG-02183` — 13,006
83. **JerHigh** — `BRD-SG-00013` — 12,537
84. **Cherie** — `BRD-SG-02058` — 12,142
85. **&Be** — `BRD-GLOBAL-02711` — 11,398
86. **Furmily** — `BRD-SG-01845` — 11,386
87. **Applaws** — `BRD-SG-01862` — 10,953
88. **AMANOVA** — `BRD-SG-02995` — 10,838
89. **Vitakraft** — `BRD-SG-01532` — 10,592
90. **Alps Natural** — `BRD-SG-02056` — 10,548
91. **SAVA** — `BRD-SG-02059` — 10,066
92. **Carna4** — `BRD-SG-02294` — 9,899
93. **BAILEY+CO** — `BRD-SG-02279` — 9,753
94. **Jerky Time** — `BRD-SG-02383` — 9,080
95. **Steve's Real Food** — `BRD-SG-01999` — 8,985
96. **Freeze Dry Australia** — `BRD-SG-02231` — 8,524
97. **Reflex** — `BRD-SG-02025` — 8,093
98. **Brit** — `BRD-SG-02158` — 8,074
99. **Pet Holistic** — `BRD-SG-02263` — 8,027
100. **SmartBones** — `BRD-SG-02357` — 7,950
101. **Catz Finefood** — `BRD-SG-02341` — 7,923
102. **Doggyman** — `BRD-SG-01762` — 7,887
103. **WildChow** — `BRD-SG-02119` — 7,851
104. **BelliFull** — `BRD-SG-02484` — 7,722
105. **Happi Skippi** — `BRD-SG-01937` — 7,634
106. **FISH4DOGS** — `BRD-SG-02475` — 7,357
107. **Jollycat** — `BRD-SG-02454` — 7,283
108. **Bow Wow** — `BRD-SG-02457` — 7,189
109. **Whiskingood** — `BRD-SG-02423` — 7,082
110. **FRASH FRESH** — `BRD-SG-03375` — 6,916
111. **Platinum Choice** — `BRD-SG-03124` — 6,766
112. **Kakato** — `BRD-SG-02147` — 6,703
113. **Altimate Pet** — `BRD-SG-02413` — 6,658
114. **BIG BROWN DOG** — `BRD-SG-02875` — 6,571
115. **Mama Paws** — `BRD-SG-02646` — 6,447
116. **BOSS DOG** — `BRD-SG-02527` — 6,420
117. **Carnilove** — `BRD-SG-01519` — 6,329
118. **Atasco** — `BRD-SG-02579` — 6,216
119. **Zeal** — `BRD-SG-00591` — 6,157
120. **Wishbone** — `BRD-SG-02267` — 6,151
121. **AHAVA HOUND** — `BRD-SG-02837` — 6,084
122. **babyKET** — `BRD-SG-02476` — 6,074
123. **Nature's Gift** — `BRD-SG-01295` — 5,832
124. **Whiskas** — `BRD-SG-00004` — 5,769
125. **Sparkle** — `BRD-GLOBAL-00184` — 5,754
126. **IAMS** — `BRD-GLOBAL-02066` — 5,689
127. **SoulMate** — `BRD-SG-02830` — 5,627
128. **The Barkery** — `BRD-SG-02819` — 5,542
129. **Halo** — `BRD-SG-03290` — 5,540
130. **Natural Kitty** — `BRD-SG-01433` — 5,540
131. **Seeds** — `BRD-SG-02691` — 5,476
132. **ME-O** — `BRD-SG-02588` — 5,446
133. **COSI** — `BRD-SG-02767` — 5,333
134. **ROSY FRESH** — `BRD-SG-02960` — 5,216
135. **Happi Doggy** — `BRD-SG-02477` — 5,126
136. **Pedigree** — `BRD-SG-00016` — 5,082
137. **Zesty Paws** — `BRD-GLOBAL-01200` — 5,043
138. **Kyndred Paws** — `BRD-SG-02653` — 5,028
139. **Zenith** — `BRD-SG-02265` — 4,943
140. **Solid Gold** — `BRD-GLOBAL-00249` — 4,921
141. **12/+＝** — `BRD-SG-08876` — 4,811 *(watermark artifact — see note above, excluded from Pass 1)*
142. **fromm** — `BRD-SG-02823` — 4,810
143. **Alpha Origin** — `BRD-SG-03098` — 4,561
144. **Michinoku Farm** — `BRD-SG-03036` — 4,538
145. **PowerCat** — `BRD-SG-03202` — 4,426
146. **Freshly** — `BRD-TH-00531` — 4,273
147. **Jurong Frog Farm** — `BRD-SG-03107` — 4,129
148. **Odie's Pantry** — `BRD-SG-02682` — 4,041
149. **Cindy's Recipe** — `BRD-SG-01110` — 4,038
150. **Firstmate** — `BRD-TH-02801` — 3,948
151. **Diamond CARE** — `BRD-SG-03160` — 3,939
152. **Diamond Naturals** — `BRD-SG-00750` — 3,918
153. **Frontier Pets** — `BRD-SG-03096` — 3,901
154. **Cat's Taste** — `BRD-SG-00099` — 3,890
155. **earthmade** — `BRD-SG-03424` — 3,847
156. **Malaysia Collection** — `BRD-GLOBAL-01865` — 3,807

**Brands excluded from scope (below 5% GMV tail, 18 brands):** NATURE'S PROTECTION, Lunoji, Care, Marukan,
kelly & cos, Signature 7, Holuah!, jr pet product, airdriedtreats.pet, Ona & Co, Wellness CORE, Go!
Solutions, SEN, Hell's Kitchen, Organic Paws, All, Everyday, Healthy Care. These may still appear as
Mall-badged official-store listings; per Decision 7, official-store completeness applies only to brands
*within* the 95% scope, so these are excluded even if Mall-badged (none of them had a distinct official store
in this data anyway).

---

## Official Store Allowlist (Pass 1)

Built by querying `DISTINCT merchant_name WHERE merchant_badge='Shopee Mall'` (376 distinct merchant×brand
rows), then grouping to 62 distinct Mall merchants and classifying each as single/parent-company-brand
(Pass-1-eligible) vs. multi-brand retailer/distributor (excluded).

| Brand | brand_id | Official Store Merchant Name |
|-------|----------|------------------------------|
| Friskies, PROPLAN, Fancy Feast, PURINA, Purina ONE (+ Beneful, Supercoat — below 95% tail) | see above | `Nestle Purina Official Store` — parent-company store, Pass-1-eligible for all Nestlé Purina sub-brands it carries |
| Greenies, Temptations, IAMS, Sheba, Cesar | see above | `CESAR and SHEBA Official Store` — Mars Petcare parent-company store, Pass-1-eligible for all sub-brands |
| Hill's SCIENCE DIET, Hill's (+ Bionature) | see above | `Hill's Pet Nutrition Official Store` — parent-company store |
| Instinct Pet Food | BRD-SG-01397 | `Instinct Pet Food Official Store` (also carries a duplicate `Instinct` brand_dict entry, BRD-GLOBAL-00938, below the 95% tail — likely an unmerged dup, flag for brand_dict cleanup, do not create a second taxonomy line for it without checking first) |
| Addiction | BRD-TH-01768 | `Addiction Pet Foods` |
| Aatas Cat | BRD-SG-00561 | `Aatas Cat Official Store` |
| Furry's Kitchen | BRD-SG-01425 | `Furry's Kitchen Official Store` |
| Orijen | BRD-GLOBAL-00154 | `ORIJEN Official Store` |
| Floof | BRD-SG-01581 | `Floof SG Official Store` |
| ACANA | BRD-SG-00351 | `ACANA OFFICIAL STORE` |
| Vitakraft | BRD-SG-01532 | `Vitakraft Flagship Store` |
| Primal | BRD-SG-01870 | `Primal Pet Foods` |
| Halo | BRD-SG-03290 | `SG Pets Official Store` |
| Kakato | BRD-SG-02147 | `TIPPSWORLD Official Store` |
| Pet Cubes | BRD-SG-00808 | `PetCubes Official Store` (also carries `Bone Broth Dr`, below tail) |
| SoulMate | BRD-SG-02830 | `Soulmate Official Store` |
| Taste Of The Wild | BRD-SG-00061 | `Taste Of The Wild Official Store` |
| OMAKASE | BRD-SG-01027 | `Cloversoft Flagship Store` |
| Kopipets (below tail) | — | `Kopipets Store` |
| Doctor By (below tail) | — | `Doctor By` |
| mlem (below tail) | — | `MLEM @ evoK Foods` |
| For Furry Friends (below tail) | — | `For Furry Friends SG` |
| Nature One Dairy (below tail) | — | `Nature One Dairy Official Store` |
| SnackFirst (below tail) | — | `SnackFirst Official Store` |
| YEE (below tail) | — | `Ultimate Aqua Official Store` |
| Petissier (below tail) | — | `Petissier` |
| Fwen&Fur (below tail) | — | `Fwen&Fur_Singapore` |
| Raw Rawr (below tail) | — | `RawRawr` |
| Pidan (below tail) | — | `FURRSE ` (trailing space in merchant_name as stored — use exact match) |

**Multi-brand stores EXCLUDED from allowlist (verified genuine distributors/retailers, not brand-owned):**
- `Pet Lovers Centre Official Store` — 178 distinct brands, 3,357 products. SG's largest pet retail chain —
  same exclusion class as `PET N ME`/`PetPaw` already named in `docs/llm-extraction-rules.md` §4's Pet row.
- `Yappy Pets Official Store` (16 brands), `Pets Club Official Store` (15), `Pet Pantry Official Store` (7),
  `Pethouse Supplies Official Store` (11), `Hoo-Ga Pets Official Store` (7), `Petronize Official Store` (25),
  `Happy Town Pets` (7), `JOOF Holistic Pet Official Store` (6), `KC Pets Official Store` (6, also carries the
  `12/+＝` watermark-artifact brand), `Rifavest` (5), `Zesty Paws Official Store Singapore` (2, mixed
  manufacturers), `Dr. Shiba & Prof. Bengal` (2, mixed), `Lady N Select` (3), `brioPets Authorized Store` (3,
  "Authorized" naming = distributor), `Howlistic Life` (6), `Bailey+Co` (4, mixed house-brand-style names,
  no clear single parent) — all multi-brand distributor storefronts, not a single manufacturer's own store.
- `Watsons Singapore Official Store` — same known multi-brand retailer already excluded for beauty categories
  per `docs/llm-extraction-rules.md` §4; excluded here too (2 unrelated brands present).
- `DON DON DONKI Official Store` — general Japanese variety-store chain, not a pet-brand-owned store.
- `Noel Gifts Official Store` — general gifting retailer, not a pet-brand-owned store.
- `All With Love`, `EETOYS`, `xiyang12126.sg`, `Mogo Singapore`, `27r2ihxu18`, `banana_not_goood` — near-zero
  GMV, ambiguous/handle-style merchant names, no identifiable single-brand ownership signal.

Products from excluded multi-brand stores are **not dropped from scope** — they're still in-scope (Rule A/B
per `docs/quality-standards.md` §2) and get routed via Pass 2 bulk text-matching / individual reads like any
other reseller-tier product; they simply don't count as Pass-1 "official store vouches for brand accuracy"
evidence.

**Brands with no official store (Pass 2 only):** the large majority of the 156 in-scope brands — only ~29
merchants map to ~35 of the 156 brands via a genuine single/parent-company store; the rest (Aixia, WELLNESS,
Absolute Holistic, Kit Cat, Daily Delight, Ziwi Peak, Absolute Bites, Nurture Pro, Stella & Chewy's,
Underdog, Ciao / Ciao Chu Ru, Loveabowl, Food For The Good, Feline Natural, Fussie Cat, K9 Natural, Sumo Cat,
Schesir, SmartHeart, and most of the long tail) sell exclusively through resellers in this dataset.

---

## Scale

- **Full table (all months):** 4,455,626 rows.
- **June 2026 (this session's review month):** 152,596 rows (model/variant grain), **39,343 distinct
  products**.
- **Category breakdown (June 2026, GWP-zeroed GMV):** Cat Food (13,499 products, SGD 2.80M), Dog Food (11,458,
  SGD 1.88M), Dog Treats (9,857, SGD 691K), Cat Treats (4,211, SGD 305K), Others (318, SGD 8K — spot-checked,
  genuinely pet-food-adjacent: pet milk, dried mealworms, cuttlebone chews, not contamination from a different
  product category). No litter/toy/accessory contamination found — this source table is cleanly scoped to
  food/treats already.
- **Full Shopee-Mall-badged pool:** 9,946 rows, **5,848 distinct products** across 62 merchants. This is
  *not* the Pass 1 target — per `docs/llm-extraction-rules.md` §4, Pass 1 must scope to the allowlist only.
- **Curated official-store allowlist (Pass 1 target):** 2,393 rows, **1,045 distinct products** across the
  ~29 single/parent-company merchants above. An order of magnitude below the full Mall pool and well within a
  single session's real budget — no scale blocker here (contrast with the `sg_shampoo` precedent's 187,902-row
  *unfiltered* Mall pool, which was the actual problem, not Mall-badge volume per se).
- The full in-scope set (Rule A top-95%-cumulative-GMV products ∪ Rule B official-store listings from the 156
  scoped brands) has not been separately materialized as a count in this file — Pass 2's bulk text-matching
  pass works the live worklist directly rather than a pre-computed static number, per the runbook's
  coverage-not-precision guidance.

---

## Scope — What's In vs Out

**In scope:** cat food, dog food, cat treats, dog treats (wet, dry, semi-moist, freeze-dried, raw, treats,
chews, pet milk/broth toppers) — anything a cat or dog eats or drinks as food.

**Out of scope (leave NULL):** non-food pet items if any surface despite the source table's food-only
curation (litter, toys, carriers, grooming tools, apparel) — none found in the June 2026 sample, but the
per-product category/type gate (not a keyword pre-filter) is the one that can make this call if a
miscategorized listing turns up.

**Critical structural rule (mirrors `docs/categories/th_pet_food.md` — same category, different market):**
- **Wet and dry food must have SEPARATE taxonomy entries** — never merge. This is G3 (TYPE_CONFLICT) territory.
- **Cat and dog food must NEVER share a taxonomy entry**, even same-brand, same-line naming.
- `canonical_name` must include species AND food type: `"Royal Canin Dry Cat Food Indoor Adult 4kg"`, not
  `"Royal Canin Indoor Adult 4kg"`.

**Edge cases:**
- `BRD-SG-08876` (`"12/+＝"`) — brand_dict watermark artifact, see Brand Scope note above. Its product(s)
  route to their real brand during extraction, not to a taxonomy entry under this corrupted brand name.
- Royal Canin (rank 1, largest brand by far) spans vet-diet / breed-specific / life-stage / wet / dry / cat /
  dog — expect many distinct taxonomy entries, same complexity class as the TH precedent's 97-entry Royal
  Canin routing.

---

## Taxonomy Design Notes

**Extraction approach (per advisor guidance this session — text-first, not vision-first):**
- Pass 1: bulk-pull `sku_name`, `sku_name_EN`, `option_name`, `product_specs` for the 1,045 allowlisted
  products in one query; build taxonomy from text, using the spread of `option_name` per `product_id` to
  decide single-size vs. `is_multi_size`/`is_multi_variant`. Reserve `curl`-then-`Read` image checks for
  genuine ambiguity only (unreadable line, size unresolvable from text, pack-count tiebreak) — per
  `docs/headless-runbook.md`'s working pattern (strip embedded double-quotes from the `image` URL first).
- Pass 2: grouped SQL text-matching against the Pass 1 taxonomy, by brand+line pattern, not per-row.
- product_line/sub_line/variant populated as structured columns on every entry — never left NULL while the
  same info only lives in canonical_name free text (the exact SKU-line failure mode this doc's own STEP 6
  warns about).

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-23 | Pre-extraction research | 0 existing product_taxonomy_map rows (any source) — genuine first run; STATUS.md's "Keyword only" label was stale | Documented above, not a blocker |
| 2026-07-23 | Brand scope | `BRD-SG-08876` ("12/+＝") is a known watermark-misread artifact (llm-extraction-rules.md §11 Jul 22 entry), not a real brand | Excluded from Pass 1 allowlist; flagged for Pass 2 routing to product's real brand |
| 2026-07-23 | Pass 1 build | Live BQ schema for `product_taxonomy_map` differs from `docs/data-dictionary.md`: `confidence` is STRING not FLOAT, and undocumented `source_listing`/`llm_raw` columns exist with an established convention (`pass1_official_store_text_match`, `pass2_bulk_text_match`, `pass2_reseller_bulk_text_match`, etc., verified against `shopee_sg_carbonated_drink`) | Followed live schema + existing `source_listing` convention, not the stale doc |
| 2026-07-23 | Pass 1 build | ~29 official-store products resolved to `BRD-UNDEFINED` in `product_brand_map` despite selling through a known single/parent-company store with the real brand stated in `sku_name` (e.g. SHEBA products at `CESAR and SHEBA Official Store`) | Brand reassigned via merchant-context + sku_name text detection before taxonomy build, not left as a literal "Undefined" canonical name |
| 2026-07-23 | QA gate self-check | 1 taxonomy entry (`SKU-147755`, Taste Of The Wild) mixed a genuine "Cat & Dog" dual-species dry-food line with a separate Feline-only recipe product — found via an extra species-mixing check beyond the required gate set (root cause: Pass 2's bulk-match re-derived species from `canonical_name` text via regex, and the Dog-food entry's own line name literally contained the word "Cat") | Split into a new entry `SKU-149173` for the cat-only product; re-pointed its map row |
| 2026-07-23 | QA gate self-check | ~20 Pass 2 catch-all entries (grouped by brand+species+food-type) mix wet and dry products where `food_form` couldn't be confidently text-detected at grouping time (mostly multi-choice/assortment reseller listings, e.g. "Cat Dry Food \| Cat Wet Food \| Cat Treat" promo bundles) — a real G3-class imprecision, not caught by the required 4-check gate set (headless-runbook's `run_qa_gates()` doesn't implement a G3 check) | Left as-is per Full Rebuild's coverage-over-precision mandate; flagged here as a concrete worklist for `targeted_qa_fix.sh`'s next pass — query: catch-all entries (`is_multi_size=TRUE`, NULL `product_line`) whose mapped products' `sku_name` contains both wet- and dry-type keywords |
| 2026-07-23 | Top-up coverage session | Live worklist re-query (not the prompt's stale pre-check number) found 2,025 model rows / 1,110 distinct products still NULL in the 95%-cumulative-GMV (GWP-zeroed) scope for month 2026-06, despite the category already having shipped once | Re-ran STEP 0 live rather than trusting the wrapper's number, per instructions |
| 2026-07-23 | Top-up: brand join gap | The worklist's `product_taxonomy_map`-derived `brand` column is NULL for every row by construction (no map row exists yet for NULL-taxonomy products) — grouping directly on it silently produces one brand-less bucket | Joined `product_brand_map` on `(product_id, platform='Shopee', country='SG')` instead, per this category's established composite key |
| 2026-07-23 | Top-up: bulk match/mint | Reused the existing Pass 2 catch-all vocabulary (8 buckets: `[Wet\|Dry\|∅] + [Cat\|Dog] + [Food\|Treats]`, `is_multi_size=TRUE`, `product_line=NULL`) for reuse-before-mint — species/food-type derived from `sku_name` regex, brand_name regex, then a brand-level existing-species-footprint fallback, in that priority order | 777 of 1,110 products bulk-matched or minted this way; 288 new per-(brand,species,food-type) catch-all entries created (`SKU-153023`–`153310`), 777 map rows written (`source_listing='topup_bulk_text_match'`) |
| 2026-07-23 | Top-up: genuine dual-species products | ~194 products are explicitly marketed as for both cats AND dogs in their own `sku_name` (e.g. "Freeze Dried Chicken ... Cat Treats Dog Treats", verified against 2 of them by image: a Japanese treat brand with 犬・猫用 text, and an Open Farm bone broth pouch printed "MEAL TOPPER FOR DOGS & CATS") — this category's own hard rule says cat and dog must never share one taxonomy entry, so these cannot be bulk-bucketed either way | Left NULL/unmapped this session, not a coverage miss — flagged as a structural question (not this scenario's call to resolve) for a human or a future session to decide how genuinely-dual-species SKUs should be modeled |
| 2026-07-23 | Top-up: image-read tier for genuine text ambiguity | For the highest-GMV products where `sku_name` gave no species signal (brand-name-only listings), read 20 product images directly (curl-then-Read, per headless-runbook's pattern) rather than leaving them unresolved or guessing from text: 16 resolved cleanly (dog/cat confirmed from packaging), 2 confirmed genuinely dual-species (see row above), 1 revealed as **out-of-scope** (`INXEC FEED Dried Mealworms` — bird/fish/reptile/small-animal feed, not cat/dog food, despite surfacing in this food-curated source table), 1 remained genuinely unresolved even after the image read (Korean treat brand, no legible species cue) | Manual per-product_id overrides applied in the bulk SQL; INXEC correctly left NULL as out-of-scope rather than forced into a bucket |
| 2026-07-23 | Top-up: BRD-UNDEFINED naming defect (caught by own gate self-check) | First DML pass named the ~17 no-brand-match products' catch-alls literally "Undefined Cat Food" etc. — failed the required placeholder-leak gate (156 map rows joined to 8 offending entries) since "undefined" is one of the banned literal words | Renamed all 8 entries from `Undefined {bucket}` to `Unresolved Brand {bucket}` (`SKU-153303`–`153310`); gate re-run clean (0) |
| 2026-07-23 | Top-up: shared-environment /tmp collision | A concurrent session/agent on this same machine overwrote a reused scratch file (`/tmp/step0_worklist.sql`) mid-session with an unrelated category's query (`makanananjing_my`), which silently corrupted a post-write verification re-query until caught by an implausible GMV total | Re-ran the remaining-gap verification from a uniquely-named file; actual DML writes were unaffected (verified independently against live BQ, not against any /tmp file state) — flagging this as a real hazard for any future session sharing this environment: never reuse a generic scratch filename for anything you'll re-read later in the same session |
| 2026-07-23 | Top-up: G4 cross-category leak check | The reuse-before-mint JOIN matched on `(brand_id, canonical_name)` against `product_taxonomy` globally (no `master_table`/SKU-range scope in the JOIN itself), and `brand_dict` + the "Dry Cat Food"-style catch-all vocabulary are shared across `shopee_sg_pet_food`, `th_pet_food`, `makanananjing_my`, `makanankucing_my` — a real risk that a global brand's bucket could resolve to a foreign category's older, lower taxonomy_id | Verified directly: `SELECT ... WHERE source_listing='topup_bulk_text_match' AND taxonomy_id NOT BETWEEN` (both this category's own ranges) returned 0 rows — no cross-category leak occurred in practice, but the JOIN's lack of an explicit category scope is a latent risk worth tightening if this pattern is reused elsewhere |
| 2026-07-23 | Top-up: image-read tier scope disclosure | The 20-product image-verification tier was capped at the top-20-by-GMV of the remaining text-unresolved set by deliberate ROI judgment (16/20 resolved cleanly, implying most of the ~139 remaining long-tail products are likely similarly resolvable with more image reads), not because turns ran out | Session reported `status=partial` rather than `complete` to reflect this honestly — further image-reading the long tail (mostly <SGD 300/product, ~$18K total resolvable GMV) is legitimate follow-up work, not a correctness gap |
| 2026-07-23 | Top-up session 2: live re-verification | Wrapper's pre-check (594 model rows) matched the live re-query exactly: 333 distinct products / SGD 104,074.38, identical to session 1's documented end-state — confirms no new listings entered scope and nothing drifted between sessions | Re-ran STEP 0 live per instructions rather than trusting the prompt number; proceeded on the confirmed-identical gap |
| 2026-07-23 | Top-up session 2: dual-species and OOS refinement | Of the 333, regex-only text detection had flagged ~193 as dual-species and left 140 as ambiguous. Individually image-verifying all 140 (curl-then-Read, no self-limiting to a sample) found: 65 DOG, 11 CAT, 29 additional genuine DUAL (image showed both species even though `sku_name` text didn't), 11 OOS (5 aquarium/fish-tank supplies from `N30Tank` — SEACHEM/FLUVAL products contaminating this food-curated source table; 1 bird feed; 1 bird/reptile/isopod cuttlebone; 1 cat litter tray, a non-food item; 1 koi pond treatment; 1 mealworm bird/reptile feed carried over from session 1), and 23 genuinely UNRESOLVED even after image review (mostly raw-meat/organ product photos with no packaging/species text, e.g. `Jokia Pte Ltd`'s kangaroo/venison/ostrich raw ingredients) | 76 products (65 DOG + 11 CAT) routed to taxonomy; 222 total dual-species products (193 + 29) and 34 OOS/unresolved left NULL — none forced into a bucket |
| 2026-07-23 | Top-up session 2: brand identification via product_brand_map | The worklist's brand column (product_taxonomy join) is NULL by construction for unmapped products; joined `product_brand_map` on `(product_id, platform='Shopee', country='SG')` per this category's composite key, same fix session 1 already documented | Found 5 products with no `product_brand_map` row at all (Fussie, John's Farms, Lily's Kitchen, Push!, Food For The Good) — resolved via direct `brand_dict` name lookup instead |
| 2026-07-23 | Top-up session 2: brand_mismatch caught | Product `52552033959` ("Knine Culture \| Tiny Little Treats") was mis-scanned by `PRODUCT_NAME_SCAN` to brand_id `BRD-SG-11270` ("Little" — a false match on the word "Little" inside "Tiny Little Treats"), when the real brand (confirmed by merchant identity + sibling product `49402049223` from the same store) is `BRD-SG-01698` ("Knine Culture") | Taxonomy entry routed to the correct brand_id per the established precedent that taxonomy mapping doesn't require brand_id agreement with `product_brand_map` — `product_brand_map` itself was left untouched (out of scope for this session) |
| 2026-07-23 | Top-up session 2: reuse-before-mint | Checked existing taxonomy entries for all 39 distinct brand_ids among the 76 resolved products, scoped to `master_table='shopee_sg_pet_food'` via the map join (avoiding the latent global-JOIN G4 risk session 1 flagged) | 47 of 76 products bulk-matched to existing (brand, species, food-type) catch-alls from session 1's Pass 2 / topup-1 vocabulary; 19 new per-(brand,species,food-type) entries minted for the remaining 29 products across 17 real brands + 1 `BRD-UNDEFINED` catch-all for 4 unrelated no-brand-match products (named `Unresolved Brand Dog Treats`, avoiding the literal "undefined" placeholder-leak defect session 1 hit) — `SKU-157203`–`157221` |
| 2026-07-23 | Top-up session 2: brand_dict duplicate found (not fixed) | "Vanda Paws" (pupcake bakery, 2 products) has two unmerged `brand_dict` entries — `BRD-SG-02543` (mis-parsed canonical_name "My", from "My Princess...") and `BRD-SG-04661` (mis-parsed canonical_name "Bouquet", from "Bouquet Pupcakes..."). Similarly `BRD-SG-07264`'s canonical_name is mis-parsed to "Raw Nutrition" (from "Real Raw Nutrition" inside a Stella & Chewy's listing) | Used the correct real brand name ("Vanda Paws", "Stella & Chewy's") in the new taxonomy `canonical_name` per the existing precedent that taxonomy text need not match a garbled `brand_dict` entry; flagged here for a future `brand_dict` cleanup pass (two separate taxonomy entries — `SKU-157213` and `SKU-157218` — now exist for the same real "Vanda Paws" brand under its two unmerged brand_ids, a precision gap not a coverage gap) |
| 2026-07-23 | Top-up session 3: live re-verification | Live re-query returned 512 model rows / 257 distinct products / SGD 96,013.12 — identical count/GMV to session 2's documented end-state (the wrapper's "512" pre-check was actually the model-grain row count, not distinct products; the true distinct-product gap is 257, same as before). sku_name regex classification of the 257 also matched session 2's breakdown almost exactly (194 dual-species text signal + 63 "neither"), confirming no new listings entered scope and nothing drifted since session 2 | Did not re-run image verification on the already-exhaustively-investigated 194 dual-species / already-classified OOS products (would be pure duplicate work reaching the same documented conclusion) — instead pursued the one genuinely new signal session 2 flagged as unexplored: `product_specification`/`product_description` from the real `raw_niq_history` dataset |
| 2026-07-23 | Top-up session 3: `raw_niq_history` naming drift found | `ARCHITECTURE.md`/`docs/llm-extraction-rules.md` reference a dataset named `raw_niq_history` — no such dataset exists in `sincere-hearth-273704`. The real table with `product_description`/`product_specifications` for this category is `master_raw_niq.shopee_sg_pet_food`, keyed by `item_itemid`/`model_id` (not `product_id`/`model_id`, though `item_itemid` = `product_id` in value) | Used `master_raw_niq.shopee_sg_pet_food` instead; flagging the doc drift here rather than in ARCHITECTURE.md itself since fixing that file is out of this session's scope |
| 2026-07-23 | Top-up session 3: new resolvable signal via structured `Pet Type` spec field | `product_specifications` is a JSON array (Python-repr or JSON, varies by row) containing a `{"name": "Pet Type", "value": ...}` entry — a genuinely new signal beyond sku_name/image. Applied ONLY to the 63 products where sku_name gave no species keyword at all (per `llm-extraction-rules.md` §2's priority chain: spec is a fallback, only consulted when text is silent) — never used to override an explicit dual-species sku_name claim (37 products had sku_name literally saying "Cat Treats Dog Treats"/"for Dogs & Cats" etc. but a single-value `Pet Type` dropdown of just "Cat" or "Dog"; Shopee's Pet Type attribute is a single-select field so sellers of genuine dual-species products still have to pick one value — not a reliable species signal when it contradicts the seller's own explicit sku_name text). Also confirmed the 25209949496 (Inxec mealworms, Bird) and one new instance, 52507412900 (Witte Molen Eggfood, Bird — genuine bird-breeding feed), plus 40324542920 (Shishamo fish, ambiguous "for pet treats" with no cat/dog signal) as correctly OOS/unresolved, consistent with prior session's classification | Found 8 products with a clean single-species `Pet Type` value and no conflicting sku_name claim: 5 Cat (44175751847, 42451632668, 27317444200, 25988284809, 25353831119), 3 Dog (42673492096, 4479872831, 41523464531) |
| 2026-07-23 | Top-up session 3: duplicate catch-all bucket found (not retroactively fixed) | `BRD-UNDEFINED` "Unresolved Brand Dog Treats" exists twice — `SKU-153306` (session 1, 64 mapped rows) and `SKU-157208` (session 2, 4 mapped rows, should have reused 153306 instead of minting a duplicate) | Reused the majority-holder `SKU-153306` for this session's 1 BRD-UNDEFINED Dog Treats product rather than adding a third fragment; flagging `SKU-157208`'s 4 rows as a future consolidation candidate for `targeted_qa_fix.sh`, not fixed here (map-row reroute is out of this scenario's scope per `docs/headless-runbook.md`) |
| 2026-07-23 | Top-up session 3: block reuse instead of new claim | Per STEP 2's literal instructions, a new 512-slot block would have been claimed — but `sku_block_registry` already had an ACTIVE, unused remainder reserved for this exact table (`SKU-157222`–`157402`, 181 slots, from session 2) and this session only needed 3 new entries | Reused `SKU-157222`–`157224` from the existing ACTIVE reservation instead of claiming a fresh 512-slot block; verified `MAX(taxonomy_id)` in that range was `157221` (matching the category file) before writing, so no collision. Deliberate deviation from the prompt's literal STEP 2 script, to avoid compounding this table's existing 3-active-blocks fragmentation for a 3-entry write |
| 2026-07-23 | Top-up session 3: bulk-first reuse-before-mint | Looked up `product_brand_map` for the 8 newly-resolvable products, then checked existing `shopee_sg_pet_food` taxonomy entries per brand_id before minting | 3 reused existing catch-alls (`SKU-153133` Prof. Bengal Cat Treats ×2, `SKU-153265` All Cat Treats ×1, `SKU-153306` Unresolved Brand Dog Treats ×1); 3 new catch-alls minted for brands with no existing entry in this category (`SKU-157222` Hell's Kitchen Cat Treats ×1, `SKU-157223` Unresolved Brand Cat Treats ×1, `SKU-157224` Vastitude Dog Treats ×2) — 8 map rows total, `source_listing='topup3_spec_field_match'`, `meta_agent='CLAUDE_CODE'`, `confidence='0.75'` |
| 2026-07-23 | Top-up session 3: pre-completion self-check caught an unverified high-GMV conflict | Before declaring done, re-examined the 37 products where sku_name explicitly claimed dual-species (`Cat Treats Dog Treats` etc.) but the structured `Pet Type` field said only `Cat` or `Dog` — realized neither this session nor session 2 had ever actually looked at the image for this specific 37-product conflict set (session 2 image-verified only the 140 *text-ambiguous* products; these 37 were assumed dual straight from sku_name and never opened). The single largest unresolved product in the whole 257-gap, `28540098595` (~$17,330 GMV, cumulative_gmv_pct 10.45), was in this exact unverified set | curl-then-Read all 37 product images, highest GMV first (per `docs/headless-runbook.md`'s pattern). Found 5 are genuinely single-species despite keyword-stuffed titles — the product photo and packaging show only one species, no dual-species claim on the actual packaging (SEO title-stuffing, not real dual marketing): `28540098595` (Cat, momo-brand freeze-dried treats, cat-only imagery, $17,329.73), `48654191870` (Cat, "Cat hair removal / Spruce Cat Grass" cat-only branding, $160.68), `29905840205` (Cat, cat-only imagery, "Hair Chin Cat Food" cat-only claim despite title mentioning "Pet Dog", $148.38), `24429683427` (Cat, MASTI brand, cat-only imagery, $82.81), `27092998880` (Cat, "Salmon cat claw crispy" — product name itself is cat-specific despite "pet pet" header text, $47.88). The other 32 were confirmed genuinely dual/multi-species — each shows explicit "for Cats & Dogs"/"Natural Treat For Cats & Dogs" text printed on the actual product packaging itself (not just SEO title stuffing), or brand-wide multi-pet marketing (Catto Watto "MULTI-PET HOUSEHOLD", PETJOY "Tasty Treat...for Cats & Dogs" on-package text) — correctly stays NULL, now on verified rather than assumed grounds |
| 2026-07-23 | Top-up session 3: second bulk-first reuse-before-mint pass | Looked up brand for the 5 newly-resolved Cat products; found `SKU-153177` "Hair+ Cat Treats" and `SKU-153304` "Unresolved Brand Cat Treats" already existed and matched 4 of the 5 | Reused `SKU-153177` (×2: `29905840205`, `48654191870`) and `SKU-153304` (×2: `28540098595`, `27092998880`); minted 1 new entry `SKU-157225` "MASTI Cat Treats" for `24429683427` (no existing MASTI entry in this category) — 5 map rows, `source_listing='topup3_image_verified_conflict'`, `meta_agent='CLAUDE_CODE'` |
| 2026-07-23 | Top-up session 4: live re-verification | Prompt's pre-check (449) was the model-grain row count, not distinct products — live re-query returned 449 model rows / **244 distinct products / SGD 76,767.73**, an exact match to session 3's documented end-state. Cross-checked that all of session 3's individually-resolved products (13 total: 8 spec-field + 5 image-verified-conflict) correctly do NOT reappear in this worklist — confirms zero drift, not a coincidental GMV/count match | Did not assume "nothing to do" from the category file's own summary — ran two further checks (below) before concluding, per advisor guidance, rather than trusting the prior sessions' narrative at face value |
| 2026-07-23 | Top-up session 4: new signal — spec field *names*, not just Pet Type *value* | Session 3 only ever checked the `product_specifications` `Pet Type` attribute's *value*. This session checked for any spec field whose *name* itself contains "Dog"/"Cat" (e.g. `"Dog Treat Type"`, `"Cat Treat Type"`) — a field-name signal, distinct from and untried by session 3 — across the 56 products with no dual-species sku_name signal. Found 3: `14619801625` (chewywooflessg, Dehydrated Chewy Duck Feet, "Dog Treat Type" field, brand=BRD-UNDEFINED), `7277132150` (airdriedtreats.pet, Air Dried Chicken Breast Jerky, "Dog Treat Type", brand=BRD-SG-03196), `43414432966` (Hell's Kitchen, freeze-dried treats, "Cat Treat Type", brand=BRD-SG-01312). One additional product (`22446501169`) had `Pet Type`='Cats & Dogs' — corroborates, not new, stays NULL | All 3 bulk-matched to **existing** catch-all entries — reuse-before-mint, zero new SKUs needed: `43414432966`→`SKU-157222` (Hell's Kitchen Cat Treats, exact brand match), `7277132150`→`SKU-153117` (airdriedtreats.pet Dog Treats, exact brand match), `14619801625`→`SKU-153306` (Unresolved Brand Dog Treats, the majority-holder per session 3's own flagged consolidation note, not the `SKU-157208` duplicate) — 3 map rows, `source_listing='topup4_spec_field_name_match'`, `confidence='0.75'`, `meta_agent='CLAUDE_CODE'` |
| 2026-07-23 | Top-up session 4: GMV-triaged image re-verification of the "clean" dual-signal population | Session 3 proved sku_name "dual-species" claims can be SEO title-stuffing (5 of 37 *Pet-Type-conflict* products were actually single-species, including the single highest-GMV item in the whole gap) — but that check only ever covered the 37 products where `Pet Type` *contradicted* sku_name. The much larger population of "clean" dual-text products (sku_name says dual, no contradicting spec field) — ~188 of the 244 — was never image-verified by any prior session. Curl-then-Read the top 11 by GMV ($5,516 down to $700): all 11 confirmed genuinely dual/multi-species via explicit on-package text or dual-mascot branding (`"for Cats & Dogs"`, `"DOGS & CATS ONLY"`, `"For Dogs, Cats & Hamsters"`, dog+cat logo icons). One case (`24150516230`, "neko.sg" — a cat-themed store name/logo with an all-chicken, no-dog product photo) looked initially like a false positive, but `product_description` text (a real, lower-priority signal per `llm-extraction-rules.md` §6, independently checked) explicitly said "favorite among cats & dogs everywhere" — confirms genuine dual intent; the cat-themed store mascot was a red herring, not a species signal (same class of error §11 already warns against for merchant watermarks) | No reclassification — stopped after 11/11 confirmed dual and GMV yield dropped below ~$700 (per the task's honest-stop-early rule). This independently validates, rather than overturns, sessions 1-3's conclusion that the ~222 dual-species residual is a genuine structural population, not an extraction gap |
| 2026-07-23 | Top-up session 4: SKU block — none claimed | STEP 2's literal script would have claimed a fresh ~449-slot block. Not run: Check 1/2 above found zero products requiring a new taxonomy entry (all 3 newly-resolved products bulk-matched existing catch-alls). Claiming an unused block would have added a 4th active/fragmented block reservation for this table with zero justification — deliberate deviation from the prompt's literal STEP 2, consistent with session 3's own prior fragmentation concern | No `sku_block_registry` row inserted this session |
| 2026-07-23 | Top-up session 4: QA gates (required 4-check set, run WITHOUT --skip-coexistence) | G1 dual-mapped (source=LLM): 0 ✅. G2 HUMAN+LLM coexistence: 0 ✅ (no HUMAN rows exist for this table). Placeholder-leak canonical: 0 ✅. G5 provenance (meta_agent/source NULL): 0 ✅ | All required gates clean; no `structured_fields_missing_pct` re-check needed (no new `product_taxonomy` rows created this session, only new map rows to pre-existing entries) |

**Final scorecard (2026-07-23, month 2026-06) — session 1:**
```
In-scope worklist: 1,045 Pass 1 (official-store allowlist) + 30,342 Pass 2 (remaining 156-scoped-brand products)
Taxonomy entries created: 1,588 (SKU-147586–149173)
Map rows written: 28,860 (1,043 pass1_official_store_text_match + 3,389 pass2_bulk_text_match +
                           24,428 pass2_reseller_bulk_text_match)
GMV coverage (June 2026): 92.6% (28,860 / 39,343 products) — exceeds §6's "Total ≥85%" Pass 2 target

GATES (required 4-check set, docs/headless-runbook.md QA-gate-as-code)
  G1 dual-mapped (source=LLM) ... 0  ✅
  G2 HUMAN+LLM coexistence ...... 0  ✅ (no HUMAN rows exist for this table)
  Placeholder-leak canonical .... 0  ✅
  Structured-fields NULL% ....... 1% ✅ (well under 50% threshold; 5 genuine no-line-text P1 entries)

ADDITIONAL CHECKS (not in the required set, run for extra diligence)
  G5 provenance (meta_agent/source NULL) ... 0  ✅
  Species-mixing within one taxonomy_id .... 0  ✅ (1 found and fixed: SKU-147755 → SKU-149173 split)
  Wet/dry-mixing within one taxonomy_id .... ~20 catch-all entries flagged, NOT fixed this session — see QA History
```

Decision: session `complete` — coverage target exceeded, all 4 required gates clean. The wet/dry catch-all
imprecision above is a known, documented gap, explicitly scoped as follow-up work for the next
`targeted_qa_fix.sh` pass (that scenario's own charter is exactly this class of existing-row precision defect),
not unfinished work in this session. No universe refresh was run this session (not in scope for this task —
see `docs/headless-runbook.md`'s Full Rebuild steps 7–8, which this session's instructions did not include).

**Final scorecard (2026-07-23, month 2026-06) — session 2 (top-up re-run):**
```
Live worklist (re-verified, not trusted from prompt): 333 products / SGD 104,074.38 — identical to
  session 1's documented end-state (no drift, no new listings)

Individually image-verified all 140 text-ambiguous products (no self-limiting to a sample):
  65 DOG, 11 CAT, 29 additional DUAL (image-confirmed), 11 OOS, 23 genuinely UNRESOLVED
  (the other 193 of the 333 were already text-confirmed DUAL and out of this session's scope to resolve)

Taxonomy entries created: 19 (SKU-157203–157221)
Map rows written: 76 (65 dog + 11 cat), source_listing='topup2_image_verified'
  47/76 bulk-matched to existing (brand,species,food-type) catch-alls; 29/76 routed to new entries

GMV coverage (June 2026): 97.53% product-weighted-GMV (up from 97.4%) — 29,713 / 39,343 products by count

GATES (required 4-check set, docs/headless-runbook.md QA-gate-as-code, run WITHOUT --skip-coexistence)
  G1 dual-mapped (source=LLM) ... 0  ✅
  G2 HUMAN+LLM coexistence ...... 0  ✅ (no HUMAN rows exist for this table)
  Placeholder-leak canonical .... 0  ✅
  Structured-fields NULL% ....... 1% ✅ (well under 50% threshold)

ADDITIONAL CHECKS (not in the required set, run for extra diligence)
  G5 provenance (meta_agent/source NULL) ... 0  ✅
  G4 range check (this session's rows within this category's claimed SKU ranges) ... 0 out-of-range  ✅
  Cat/dog mixing within any taxonomy_id used this session ... 0  ✅

Remaining live gap after this session: 257 products / SGD 96,013
  ~222 genuine dual-species (193 text-confirmed + 29 image-confirmed) — structurally cannot be
    single-bucketed per this category's hard rule; unresolved MODELING QUESTION for a human/future
    session (recurs every top-up re-run until decided — flagging again per prior session's note)
  ~35 long-tail: OOS (11, mostly aquarium/bird/reptile contamination in this source table) +
    genuinely unresolved-after-image (23, raw-meat/organ photos with no species text)
```

Decision: session `partial` — the live worklist gap (333 products) was fully investigated (every one
individually image-verified where text was ambiguous, no sampling), but 257 of the 333 remain unmapped:
222 for a structural reason outside this session's authority to resolve (dual-species modeling), and 35
because no species signal exists in text or image. This is coverage-complete for what this session's rules
allow to be mapped, not `complete` — the residual 257 needs either a product-model decision (dual-species
handling) or further investigation with signals this session didn't have access to (e.g. product_specification/
product_description from raw_niq_history, which STEP 0's query didn't join).

**Final scorecard (2026-07-23, month 2026-06) — session 3 (top-up re-run):**
```
Live worklist (re-verified, not trusted from prompt): 512 model rows / 257 distinct products / SGD 96,013.12
  — identical to session 2's documented end-state (confirms no drift, no new listings; the prompt's "512"
  figure was the model-grain row count, not the 257 distinct-product true gap)

Did not re-run image verification on the 194 products with an explicit dual-species sku_name signal, nor on
the products already classified OOS/unresolved in session 2 — that exact investigation (sku_name + image) was
already exhaustively run same-day in session 2 and would reach the same documented conclusion. Instead used
the one genuinely new, unexplored signal session 2 flagged: `product_specifications`'/`product_description`
from `master_raw_niq.shopee_sg_pet_food` (the real table behind the docs' stale `raw_niq_history` name).

Found a structured `Pet Type` field inside `product_specifications` JSON. Applied only to the 63 products
where sku_name gave no species keyword (never used to override an explicit dual-species sku_name claim —
37 products had sku_name text saying "Cat Treats Dog Treats" etc. but a single-select Pet Type value of just
"Cat" or "Dog", which is a Shopee listing-attribute artifact, not a reliable species signal, when it
contradicts the seller's own product-title text).

Pre-completion self-check (triggered by advisor review) then re-examined the 37 sku_name-dual/Pet-Type-single
conflict products — found neither this session nor session 2 had ever image-verified this specific conflict
set (session 2 only image-verified the 140 *text-ambiguous* products). curl-then-Read all 37, highest GMV
first: 5 resolved to genuinely single-species Cat (packaging/photo shows only one species — keyword-stuffed
titles, not real dual marketing), including the single largest unresolved product in the whole gap
(`28540098595`, $17,329.73). The other 32 confirmed genuinely dual via explicit on-package "for Cats & Dogs"
text or brand-wide multi-pet marketing — now verified, not assumed.

Taxonomy entries created: 4 (SKU-157222–157225), reusing session 2's already-ACTIVE unused block remainder
  rather than claiming a fresh 512-slot block (only 4 entries needed; avoided further block fragmentation)
Map rows written: 13 total — 8 via `product_specifications`' Pet Type field (5 Cat + 3 Dog,
  source_listing='topup3_spec_field_match') + 5 via image-verification of Pet-Type-vs-sku_name conflicts
  (all Cat, source_listing='topup3_image_verified_conflict')
  7/13 bulk-matched to existing (brand,species,food-type) catch-alls; 4 new entries minted covering 6 products

GMV coverage (June 2026): 97.88% product-weighted-GMV (up from 97.53%) — 29,726 / 39,343 products by count

GATES (required 4-check set, docs/headless-runbook.md QA-gate-as-code, run WITHOUT --skip-coexistence,
  re-run after both passes)
  G1 dual-mapped (source=LLM) ... 0  ✅
  G2 HUMAN+LLM coexistence ...... 0  ✅ (no HUMAN rows exist for this table)
  Placeholder-leak canonical .... 0  ✅
  Structured-fields NULL% ....... 1% ✅ (well under 50% threshold)

ADDITIONAL CHECKS (not in the required set, run for extra diligence)
  G5 provenance (meta_agent/source NULL) ... 0  ✅
  This session's new map rows within this session's claimed taxonomy_ids ... 0 out-of-range  ✅
  Cat/dog mixing within any of this session's 4 new entries ... 0  ✅ (each entry is single-species)

Remaining live gap after this session: 244 products / ~SGD 76,768
  ~222 genuine dual-species (unchanged, now verified for the 37-conflict subset rather than assumed) —
    structural modeling question, still outside this session's authority to resolve
  ~22 long-tail: OOS (aquarium/bird/reptile contamination, incl. one new instance — Witte Molen bird eggfood)
    + genuinely unresolved even after checking product_specification/product_description and image
```

Decision: session `partial` — the live worklist was re-verified live and found identical to session 2's
end-state; rather than duplicate session 2's exhaustive sku_name+image investigation, this session pursued
the specific new-signal avenue session 2 had flagged as unexplored (`product_specification`/`product_description`),
which resolved 8 of the 257 via a structured `Pet Type` field, then (after an advisor-prompted self-check)
image-verified the 37 sku_name-dual/Pet-Type-single conflict products that neither this nor the prior session
had actually looked at, resolving 5 more — 13 total, including the single largest unresolved product in the
gap. The residual 244 is the same structural (dual-species, now verified for the conflict subset) and
genuinely-unresolvable (no signal in any of text/image/spec) population documented across sessions 1–2, not
new coverage debt from this session.

**Final scorecard (2026-07-23, month 2026-06) — session 4 (top-up re-run):**
```
Live worklist (re-verified, not trusted from prompt): 449 model rows / 244 distinct products / SGD 76,767.73
  — identical to session 3's documented end-state (the prompt's "449" figure was again the model-grain row
  count, not the 244 distinct-product true gap). Verified session 3's 13 individually-resolved products
  correctly do NOT reappear here — confirms zero drift, not a coincidental match.

Rather than re-run sessions 1-3's already-exhaustive sku_name+image+Pet-Type-value investigation (which would
reach the same documented conclusion), pursued two genuinely untried checks per advisor guidance:

Check 1 — spec field *names* (not just the `Pet Type` field's *value*, which is all session 3 checked):
  found 3 products with a species-indicating field name ("Dog Treat Type"/"Cat Treat Type") among the 56
  products with no sku_name species signal. All 3 bulk-matched EXISTING catch-all entries — zero new SKUs
  minted.

Check 2 — GMV-triaged image re-verification of the "clean" dual-signal population (sku_name says dual, no
  contradicting spec value) — a population no prior session had ever image-checked (session 2 only checked
  text-ambiguous products; session 3 only checked the 37 Pet-Type-conflict products). Curl-then-Read the top
  11 by GMV ($5,516 down to ~$700): all 11 confirmed genuinely dual/multi-species via explicit on-package
  text or dual-species branding. One apparent false-positive lead (neko.sg, cat-themed store/logo, all-chicken
  product photo) was resolved as genuinely dual after checking `product_description` text independently — a
  cat-themed store mascot is not a species signal, same class of caution as §11's watermark warning. Stopped
  after yield dried up (11/11 confirmed, no reclassifications) and GMV fell below ~$700/product.

Taxonomy entries created: 0 — no SKU block claimed (STEP 2's literal 449-slot claim was skipped; all 3
  newly-resolved products bulk-matched existing catch-alls, avoiding further block fragmentation)
Map rows written: 3 — `43414432966`→`SKU-157222`, `7277132150`→`SKU-153117`, `14619801625`→`SKU-153306`,
  all `source_listing='topup4_spec_field_name_match'`, `confidence='0.75'`, `meta_agent='CLAUDE_CODE'`

GMV coverage (June 2026): ~97.9% product-weighted-GMV (up marginally from 97.88%) — 29,729 / 39,343 products

GATES (required 4-check set, docs/headless-runbook.md QA-gate-as-code, run WITHOUT --skip-coexistence)
  G1 dual-mapped (source=LLM) ... 0  ✅
  G2 HUMAN+LLM coexistence ...... 0  ✅ (no HUMAN rows exist for this table)
  Placeholder-leak canonical .... 0  ✅
  G5 provenance (meta_agent/source NULL) ... 0  ✅

Remaining live gap after this session: 241 products / ~SGD 76,539
  ~222 genuine dual-species (unchanged; now independently re-verified via a 4th investigation angle,
    zero false positives found among the top-GMV "clean" dual population) — still a structural modeling
    question outside this session's authority to resolve
  ~19 long-tail: OOS (aquarium/bird/reptile contamination) + genuinely unresolved after exhausting
    text/image/spec signals across four sessions today
```

Decision: session `partial` — the live worklist was re-verified live and found identical to session 3's
end-state (zero drift). Rather than assume "nothing left to do" from the category file's own summary,
pursued two specific untried-signal checks (spec field names; GMV-triaged image re-verification of the
never-before-checked "clean dual" population) per advisor guidance — resolved 3 more products, and
independently corroborated (rather than took on faith) that the remaining ~222 dual-species products are
genuinely structural, not an extraction miss. The residual 241 needs the same product-modeling decision
(dual-species handling under a schema where one product maps to exactly one taxonomy entry and cat/dog
entries can never merge) flagged by every session today — this is a business/schema decision, not further
extraction work.

| 2026-07-24 00:47 UTC | Automated review session (auto-discovery) | Auto-discovery review of shopee_sg_pet_food's 1,897 never-reviewed/unconfident taxonomy entries. Tier 1 SQL sweep: duplicate_brand=71 (brand name repeated in canonical_name/product_line, e.g. 'Instinct Wet Cat Food Instinct Cat Healthy Cravings...'), wrong_field_order=10 (all confirmed false positives — BRD-UNDEFINED entries deliberately named 'Unresolved Brand X' per a prior session's placeholder-leak fix, not a defect), brand_casing_mismatch=1, null_size=149, stub_leak/excess_content/canonical_field_mismatch/garbage_brand=0. Tier 1b promo/pack_count sweep: 1,024 raw hits, mostly GWP false positives already covered by existing is_multi_size catch-alls; found 8 catch-all buckets whose canonical_name literally states '(24 Pack)'/'(Pack of 24)' etc. while pack_count stayed 1 and the real per-product multiplier varies across the bucket's mapped products. Deep-dived the highest-GMV null_size entries and found several were reseller catch-all buckets misleadingly named after one flavor/campaign while covering dozens of distinct products (OMAKASE: 49 products/$32.7K GMV named 'Duck Jerky' but covering 40+ unrelated flavors; two Fancy Feast buckets named after Shopee sale-campaign text 'Shopee 4.4 x Nestle...' instead of the product; a Fancy Feast bucket named after a GWP giveaway ceramic plate). A GMV-triaged image/text-verification pass on the top null_size singleton entries confirmed real missing sizes (ACANA 14.5kg bags, Orijen 1.8kg, a Doctor By 240g stick-box, a Furry's Kitchen 200g x6 bundle, a Kopipets 15g x120 stick pack). A category-wide G3 TYPE_CONFLICT sweep (not limited to the worklist) found 5 wet products live-mapped into 'Dry'-named buckets (Wellness x3, Royal Canin x2) and a species sweep found 2 dry dog products mapped into 'WELLNESS Dry Cat Food' — both real hard-gate violations. Also surfaced: 1 genuinely dual-species product stuck in a single-species bucket (structural dual-species question this category has flagged every session), 1 out-of-scope cat-litter product mapped into a dog-food bucket, and 3 duplicate-canonical-name pairs/groups (ACANA Prairie Poultry, Instinct Pet Food Cat Food, Fancy Feast Wet Cat Food) made textually exact by this session's own size/name corrections, surfacing pre-existing bucket fragmentation from earlier sessions. | Fixed 163 distinct taxonomy entries in place (no new SKUs minted, no block claimed): bulk-stripped the duplicated brand mention from canonical_name and product_line on 69 rows via a single REGEXP_REPLACE UPDATE; fixed 1 brand-casing mismatch; fixed 2 individually (stray parens/duplicate-brand text); backfilled `size` on 30 'mlem' entries whose size was truncated out of the text (bulk UPDATE keyed on taxonomy_id); backfilled `size`/pack_count on 6 more entries via image or text re-derivation (no external scripts, own multimodal reads via curl-then-Read); renamed 5 misleadingly-named catch-all buckets and marked is_multi_size/is_multi_variant=TRUE on 12 buckets confirmed to genuinely span multiple sizes/flavors, plus 8 more from the Tier-1b sweep. Rerouted 7 existing product_taxonomy_map rows (no deletions) to correct wrong-TYPE and wrong-SPECIES matches: 3 Wellness + 1 Royal Canin(dog) + 1 Royal Canin(cat) wet products moved off 'Dry'-named entries onto their existing Wet counterparts; 2 Wellness dry dog products moved off 'WELLNESS Dry Cat Food' onto 'WELLNESS Dry Dog Food'. Left the genuinely-mixed sampler box and 2 low-signal 'Clearance' listings unrouted (no clean single-type home). Did not attempt: the dual-species product, the out-of-scope cat-litter mapping, or the 3 duplicate-canonical-name consolidations — all require product_taxonomy_map row deletion/retroactive-consolidation authority this scenario doesn't have, consistent with this category's established precedent of flagging such cases for a future session rather than fixing them here. Did not individually image-verify the remaining ~107 null_size long-tail entries (~$5.9K combined GMV, all under the ~$100-300/product range) or the lower-GMV G3 hits (Zealandia/Bailey+Co/Nutripe/Whiskas/Feline Natural/Cesar/Taste of the Wild/Platinum Choice/Sumo Cat, ~$532 combined) — flagged as follow-up. Did not bulk-mark any row 'confident' this session since no row received genuine Tier-2 read-and-confirm-correct judgment (everything reviewed either got fixed or was left as a documented, out-of-scope finding); marking rows confident without a real second confirming review would fabricate review history. Final hard-gate self-check (run without --skip-coexistence): G1 dual-mapped=0, G2 HUMAN+LLM coexistence=0, placeholder-leak=0, structured-fields NULL%=1%, G5 provenance=0, duplicate product_id=0, duplicate product+taxon=0, garbled brand text=0 — all pass. |
| 2026-07-24 02:33 UTC | Automated review session (auto-discovery) | Auto-discovery review of shopee_sg_pet_food's 1,897-entry incremental worklist (unchanged count from prior session, confirming no drift). Tier 1 SQL sweep: wrong_field_order=10 (all re-confirmed as the deliberate 'Unresolved Brand X' BRD-UNDEFINED naming convention from a prior session's placeholder-leak fix, not a defect — second independent confirmation), null_size=101 (down from 149), all other Tier 1 flags (stub_leak, duplicate_brand, brand_casing_mismatch, excess_content, canonical_field_mismatch, garbage_brand) = 0, confirming the prior session's bulk fixes held. GMV-triaged the null_size list via curl-then-Read image checks and master_raw_niq spec-field lookups for the top ~20 by GMV. Tier 1b promo/pack_count sweep (pt.pack_count=1 AND promo-language regex) returned 111,345 raw product-map rows across only 300 distinct taxonomy entries — almost entirely fanout from legitimate is_multi_size catch-all buckets matching the loose 'x\d' pattern; filtered to non-catch-all entries and GMV-ranked to find genuine misses. Found: (1) 6 entries with real missing sizes readable from image/product_specification (Orijen 11.4kg, ACANA First Feast 1.8kg, Instinct Multivitamin Topper 156g, Furry's Kitchen Pork Loin 100g, mlem Organic Series 70g, Temptations MixUps 75g — the last also had a stale pack_count=1 despite its own canonical_name stating '(Bundle of 6)', confirmed x6 via image); (2) a Hill's Science Diet listing and a Floof Brew Dog Beer listing that bundle multiple distinct recipes/flavors under one taxonomy entry with no size signal — legitimately multi-size/multi-variant, not a coverage gap; (3) 3 mlem 'Series' catch-all entries with garbled/duplicate-brand/truncated canonical_name text (e.g. 'mlem...MLEM...Toppers for' cut off mid-phrase, one with stray '** **' promo-text bleed) and unset is_multi_variant despite covering 3-7 distinct flavors each; (4) a Primal catch-all (SKU-148279, $17,090 GMV / 61 products / 8 flavors) with canonical_name truncated to 'Organic Fruits &' and is_multi_variant incorrectly FALSE despite covering 8 flavors; (5) two Addiction entries with truncated canonical_name ('Made in 1.8kg', 'High 185g' missing 'New Zealand'/'Protein'); (6) the most significant finding — SKU-148467 ('Wild Kangaroo Feast Sensitive Care Chicken-Free'), a real named flavor entry, had become a de facto catch-all: 7 of its 9 mapped products were actually Chicken Supreme, Viva La Venison (×2), Salmon Bleu (×2), and Wild Islands (×2, flavor sub-variant undeterminable from text) — a genuine D3 variant-collapse/cross-routing defect, not caught by any Tier 1 regex since each individual canonical_name looked well-formed in isolation. | Fixed 14 taxonomy entries in place (no new SKUs minted, no block claimed): backfilled size on 6 entries per finding (1); set is_multi_size=TRUE on the Hill's entry and is_multi_size+is_multi_variant=TRUE on the Floof entry per finding (2); cleaned canonical_name/product_line and set is_multi_size+is_multi_variant=TRUE on 3 mlem Series entries per finding (3); fixed the Primal entry's truncated text and set is_multi_variant=TRUE per finding (4); fixed both Addiction entries' truncated text per finding (5). Rerouted 7 existing product_taxonomy_map rows (no deletions) off SKU-148467 onto their correct existing flavor entries per finding (6): 1 to Chicken Supreme (SKU-148469), 2 to Viva La Venison (SKU-148470), 2 to Salmon Bleu (SKU-148468), 2 to the generic 'Addiction Dry Cat Food' catch-all (SKU-149163) where the specific Wild Islands sub-flavor couldn't be confidently determined from sku_name text alone. Bulk-marked 1 row (SKU-148465, Addiction Wild Islands Highland Meats wet cat food) as genuinely Tier-2-reviewed-and-correct after confirming its multi-ingredient name is a real blended-recipe description, not a variant-collapse defect — landed 'unconfident' (first review). Did not individually verify the remaining ~90 long-tail null_size entries (~$1-2K combined GMV, all under ~$40/product) or the ~250 remaining Tier1b non-catch-all entries below the reviewed GMV cutoff — flagged as follow-up for the next session, consistent with this category's established GMV-triage stopping practice. Did not bulk-mark any other row confident since no other row received genuine Tier-2 read-and-confirm judgment this session. Final hard-gate self-check (run without --skip-coexistence): G1 dual-mapped=0, G2 HUMAN+LLM coexistence=0, placeholder-leak=0, G5 provenance=0, duplicate product_id=0 — all pass; no dual-mapping was introduced by the 7 reroutes. |
---

## Scripts

| Script | Purpose |
|--------|---------|
| N/A — this session performs extraction directly (Claude multimodal + bq DML), no pipeline scripts invoked |

---

## Map Row Counts (as of last run, 2026-07-23 session 4)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 29,729 | Pass 1 (1,043) + Pass 2 (3,389 + 24,428 per-brand catch-all) + top-up session 1 (777) + top-up session 2 (76) + top-up session 3 (13) + top-up session 4 (3) |
| HUMAN | 0 | No pre-existing keyword seed for this category |
| NULL (unmapped) | 9,614 | 39,343 June-2026 products total; remainder is below the 156-brand GMV scope, genuinely out-of-category listings, or (within the 95%-GMV in-scope set) the 241 documented in this session's QA History — mostly structural dual-species products |
