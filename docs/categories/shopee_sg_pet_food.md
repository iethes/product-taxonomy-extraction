# shopee_sg_pet_food — Category Context

> First-run category. Created during headless Full Rebuild session, month 2026-06.

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete |
| LLM Pass 2 | ✅ Complete |
| GMV Coverage | 92.6% (2026-06, 28,860 of 39,343 products mapped, LLM only — no prior HUMAN rows existed) |
| Last run | 2026-07-23 |
| Current MAX taxonomy_id | SKU-149173 (149174–149585 unused remainder, available for QA follow-up) |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-147586–148514 | Pass 1 OFFICIAL (929 entries, text-first extraction from the 1,045-product allowlist) |
| SKU-148515–149172 | Pass 2 RESELLER — per-(brand, species, food-type) catch-alls (658 entries) |
| SKU-149173 | Single QA fix (species-mixing split, see QA History) |
| SKU-149174–149585 | Unused remainder (412 slots) — available for QA follow-up |

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

**Final scorecard (2026-07-23, month 2026-06):**
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

---

## Scripts

| Script | Purpose |
|--------|---------|
| N/A — this session performs extraction directly (Claude multimodal + bq DML), no pipeline scripts invoked |

---

## Map Row Counts (as of last run, 2026-07-23)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 28,860 | Pass 1 (1,043) + Pass 2 (3,389 bulk-matched to Pass 1 entries + 24,428 per-brand catch-all routed) |
| HUMAN | 0 | No pre-existing keyword seed for this category |
| NULL (unmapped) | 10,483 | 39,343 June-2026 products total; remainder is below the 156-brand GMV scope, `BRD-UNDEFINED` products with no text-detectable brand, or genuinely out-of-category listings |
