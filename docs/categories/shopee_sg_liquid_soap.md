# shopee_sg_liquid_soap — Category Context

> First-run Full Rebuild, generated headlessly 2026-07-23. No prior LLM pass exists for this table.
> `docs/categories/STATUS.md` confirmed this category was still "⏳ Keyword only" before this session started.

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete |
| LLM Pass 2 | ✅ Complete |
| GMV Coverage | 94.5% (2026-06, row-grain, as of Full Rebuild); in-scope-set coverage 3,321/3,696 (89.9%) as of Full Rebuild |
| Top-up sessions | 2026-07-23: 267 additional products mapped from the live 664-row worklist gap (242 new entries + 24 reused); 391 rows of that worklist confirmed OOS (bar soap / bath bomb / lotion bleed / unrelated), not a coverage miss — see QA History |
| Last run | 2026-07-23 (top-up) |
| Current MAX taxonomy_id | Query BQ live before every write — do not trust any number in this file |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-129756–131755 | Claimed block (2000 slots, full_rebuild), `sku_block_registry` status COMPLETE |
| SKU-129756–130324 | Pass 1 OFFICIAL (569 entries, ~40 store fronts, 686 products mapped) |
| SKU-130325–131369 | Pass 2 RESELLER (1045 new entries; 60 products reused a Pass-1 entry; 1,262 products mapped total) |
| SKU-131370–131755 | Unused remainder of claimed block |
| SKU-134532–135195 | Claimed block (664 slots, taxonomy_topup, 2026-07-23), `sku_block_registry` status COMPLETE |
| SKU-134532–134773 | Top-up session: 242 new entries minted (bulk text-match reuse-before-mint), 267 products mapped |
| SKU-134774–135195 | Unused remainder of claimed block |

---

## Scale

| Metric | Value (month = 2026-06) |
|--------|--------------------------|
| Total rows (all months, table lifetime) | 1,497,061 |
| Total rows, 2026-06 | 55,775 |
| Distinct products, 2026-06 | 20,072 |
| Official-store (`merchant_badge='Shopee Mall'`) rows, 2026-06 | 5,866 |
| Official-store distinct products, 2026-06 | 3,352 |
| Distinct merchants, 2026-06 | 3,589 |
| **In-scope set (Rule A ∪ Rule B, quality-standards.md §2)** | **3,208 distinct products** (Rule A top-95%-cum-GMV: 1,718 · Rule B official-store-for-in-scope-brand: 2,113) |

The official-store row count alone (5,866 rows / 3,352 products across **all** brands, not just
in-scope ones) is large, but Pass 1 must scope to the **Official Store Allowlist** below (in-scope
brands' own stores only), not the full Mall-badged pool. The real must-resolve worklist is the
3,208-product in-scope set, not the raw 20,072 distinct products — the long GMV tail contributes
almost nothing to the quality scores.

---

## Brand Scope (GMV threshold 95%, month 2026-06, GWP-zeroed)

Computed via canonical `brand_id` (`product_brand_map` → `brand_dict`), not raw `brand` text —
raw text fragments the same brand across casing/spacing variants. GWP-flagged GMV zeroed
(`CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END`) before ranking, per Decision 15.

**174 brands** cross the 95% cumulative threshold (real threshold via full cumulative ranking —
NOT a fixed top-15/20 snapshot; this category's long tail is unusually deep for a personal-care
vertical, comparable in shape to a small-item-count-per-brand FMCG category).

Category total GMV (GWP-zeroed, 2026-06): ~S$1,384,600 across ~1,596 distinct brand_ids
(including `BRD-UNDEFINED`).

Top 30 (see full 174-brand list below for the rest):

1. **Dettol** — `BRD-SG-00034` — S$110,904.32 (8.0% cum)
2. **Kirei Kirei** — `BRD-GLOBAL-00156` — S$91,749.64 (14.6% cum)
3. **Dove** — `BRD-GLOBAL-00123` — S$73,996.39 (20.0% cum)
4. **QV** — `BRD-SG-00660` — S$68,459.25 (24.9% cum)
5. **Undefined** — `BRD-UNDEFINED` — S$65,914.69 (29.7% cum) — no brand text resolved at Stage 03; still in-scope by product-level GMV, no official store possible
6. **NARD** — `BRD-GLOBAL-00703` — S$49,738.84 (33.3% cum)
7. **sukin** — `BRD-SG-00948` — S$40,268.84 (36.2% cum)
8. **medicube** — `BRD-GLOBAL-00299` — S$39,387.39 (39.0% cum)
9. **Neutrogena** — `BRD-GLOBAL-00080` — S$36,324.40 (41.7% cum)
10. **Ginvera** — `BRD-SG-01315` — S$31,798.29 (44.0% cum)
11. **Cetaphil** — `BRD-GLOBAL-00069` — S$31,727.93 (46.3% cum)
12. **Aveeno** — `BRD-GLOBAL-00265` — S$28,404.48 (48.3% cum)
13. **Walch** — `BRD-SG-00491` — S$26,583.79 (50.2% cum)
14. **Lifebuoy** — `BRD-SG-01493` — S$26,212.38 (52.1% cum)
15. **Ceradan** — `BRD-SG-00860` — S$26,080.89 (54.0% cum)
16. **method** — `BRD-SG-01091` — S$22,366.72 (55.6% cum)
17. **SOME BY MI** — `BRD-GLOBAL-00605` — S$19,912.94 (57.1% cum)
18. **Shokubutsu** — `BRD-GLOBAL-00107` — S$19,892.28 (58.5% cum)
19. **TODAY With** — `BRD-SG-02335` — S$18,078.21 (59.8% cum)
20. **Diane** — `BRD-SG-00703` — S$17,775.42 (61.1% cum)
21. **Sebamed** — `BRD-GLOBAL-00142` — S$15,689.23 (62.2% cum)
22. **Theo10** — `BRD-SG-01755` — S$15,392.76 (63.3% cum)
23. **Cloversoft** — `BRD-SG-00919` — S$14,483.46 (64.4% cum)
24. **Schulke** — `BRD-SG-02064` — S$12,370.42 (65.3% cum)
25. **The Body Shop** — `BRD-GLOBAL-01534` — S$11,515.48 (66.1% cum)
26. **Alluora** — `BRD-SG-00567` — S$11,297.75 (66.9% cum)
27. **Bioderma** — `BRD-GLOBAL-00062` — S$11,011.55 (67.7% cum)
28. **Eversoft** — `BRD-SG-01481` — S$10,665.36 (68.5% cum)
29. **Fushi Maison** — `BRD-SG-02153` — S$9,902.79 (69.2% cum)
30. **KUNDAL** — `BRD-GLOBAL-01205` — S$9,047.24 (69.9% cum)

Full 174-brand list (rank, brand_id, name, GMV, cum%), 31–174:

31 BRD-SG-02175 Hygeia 8851.36 70.5 · 32 BRD-SG-00424 Suu Balm 8824.39 71.14 · 33 BRD-SG-00312 Hetras 8466.99 71.75 · 34 BRD-SG-02462 Shower Mate 8313.72 72.35 · 35 BRD-GLOBAL-00003 Eucerin 7606.92 72.9 · 36 BRD-SG-00086 LUX 7558.93 73.44 · 37 BRD-GLOBAL-01300 Aprilskin 7464.5 73.98 · 38 BRD-GLOBAL-00640 Watsons 7335.85 74.51 (own-brand private label, not the retailer allowlist exclusion — see Official Store Allowlist note) · 39 BRD-SG-11191 HAN.d 7257.13 75.04 · 40 BRD-GLOBAL-01271 Johnson & Johnson 7216.63 75.56 · 41 BRD-GLOBAL-01368 Aesop 6262.03 76.01 · 42 BRD-GLOBAL-00796 Illiyoon 6132.45 76.45 · 43 BRD-SG-03123 KHO 5800.45 76.87 · 44 BRD-SG-02232 Two Steps Cleaning 5710.18 77.29 · 45 BRD-SG-02737 Dermatological Basics 5652.5 77.69 · 46 BRD-SG-00884 Lydimoon 4940.4 78.05 · 47 BRD-SG-05608 Apple 4881.77 78.4 · 48 BRD-GLOBAL-00061 Biore 4799.06 78.75 · 49 BRD-SG-02596 TidyNethers 4742.61 79.09 · 50 BRD-GLOBAL-01453 Bouquet Garni 4661.93 79.43 · 51 BRD-SG-02458 Guardian 4472.84 79.75 (own private-label brand, not the retailer's generic store — see allowlist note) · 52 BRD-SG-02470 Lynk Fragrances 4432.05 80.07 · 53 BRD-SG-02625 Isoderm 4137.71 80.37 · 54 BRD-SG-02772 Kojie.san 3897.29 80.65 · 55 BRD-SG-00821 Bouncia 3826.26 80.93 · 56 BRD-GLOBAL-00199 Curel 3752.66 81.2 · 57 BRD-GLOBAL-00934 Dr.Bronner's 3520.08 81.46 · 58 BRD-SG-12678 Deep 3454.04 81.7 · 59 BRD-SG-03486 yukazan 3427.57 81.95 · 60 BRD-GLOBAL-00248 Seyoul 3361.72 82.2 · 61 BRD-SG-02100 Safi 3284.5 82.43 · 62 BRD-GLOBAL-00240 L'Occitane 3249.03 82.67 · 63 BRD-GLOBAL-00433 Snake Brand 3149.86 82.89 · 64 BRD-SG-02094 Jam 3047.53 83.11 · 65 BRD-SG-02955 APPELLES 2964.0 83.33 · 66 BRD-SG-03358 KUSTIE 2942.67 83.54 · 67 BRD-SG-10984 Goat 2936.89 83.75 · 68 BRD-SG-00833 ICM Pharma 2891.29 83.96 · 69 BRD-GLOBAL-00349 Madame Heng 2879.97 84.17 · 70 BRD-SG-00973 MadeToBloom 2814.0 84.37 · 71 BRD-SG-02663 Good Virtues Co. 2755.55 84.57 · 72 BRD-SG-03410 MSCENT 2611.74 84.76 · 73 BRD-GLOBAL-00563 Lush 2575.0 84.95 · 74 BRD-SG-01953 K.Brothers 2558.35 85.13 · 75 BRD-SG-02742 Molton Brown 2528.31 85.32 · 76 BRD-SG-03458 Pine & Co 2520.5 85.5 · 77 BRD-SG-01063 Herbal Pharm 2486.74 85.68 · 78 BRD-SG-01926 Apestomen 2401.9 85.85 · 79 BRD-SG-02522 MyLustre 2388.0 86.02 · 80 BRD-SG-00455 Palmolive 2244.8 86.19 · 81 BRD-GLOBAL-00337 Blanc Nature 2235.0 86.35 · 82 BRD-SG-01019 Adidas 2147.31 86.5 · 83 BRD-GLOBAL-00873 Lion 2115.68 86.65 · 84 BRD-GLOBAL-01449 Derma Lab 2062.8 86.8 · 85 BRD-GLOBAL-02333 Goat Soap Australia 2053.07 86.95 · 86 BRD-SG-03054 medimix 2038.33 87.1 · 87 BRD-GLOBAL-01462 Lucido 2018.09 87.25 · 88 BRD-GLOBAL-01663 HAPPY BATH 1988.59 87.39 · 89 BRD-GLOBAL-01555 Yuri 1960.78 87.53 · 90 BRD-SG-04013 Original Source 1887.75 87.67 · 91 BRD-SG-03591 Vermont Soap 1873.4 87.8 · 92 BRD-SG-04454 Emporal Co 1867.5 87.94 · 93 BRD-SG-04433 Yanzsoap 1853.37 88.07 · 94 BRD-SG-06567 All 1826.66 88.2 · 95 BRD-SG-01585 Zappy 1815.95 88.33 · 96 BRD-SG-07166 EC Essentials 1794.77 88.46 · 97 BRD-SG-01573 Botanist 1788.22 88.59 · 98 BRD-GLOBAL-00208 Beyond 1765.48 88.72 · 99 BRD-SG-09057 ALADA 1757.12 88.85 · 100 BRD-GLOBAL-00237 &Honey 1698.76 88.97 · 101 BRD-SG-01586 SukGarden 1691.54 89.09 · 102 BRD-GLOBAL-01334 St.Ives 1679.04 89.21 · 103 BRD-SG-04332 T3 1666.66 89.33 · 104 BRD-SG-03452 Ollie 1661.23 89.45 · 105 BRD-SG-02310 NATURIUM 1590.9 89.57 · 106 BRD-GLOBAL-01722 BAD LAB 1565.52 89.68 · 107 BRD-SG-03886 Ouji 1540.05 89.79 · 108 BRD-GLOBAL-02393 SKINEVER 1524.14 89.9 · 109 BRD-SG-00814 SimplyGood 1503.2 90.01 · 110 BRD-GLOBAL-01520 Precious Skin 1498.47 90.12 · 111 BRD-GLOBAL-00728 Kumano 1482.81 90.23 · 112 BRD-SG-03221 simplehuman 1463.45 90.33 · 113 BRD-SG-04746 Bella 1447.24 90.44 · 114 BRD-GLOBAL-01617 Men's Biore 1428.56 90.54 · 115 BRD-GLOBAL-00023 Nivea 1425.3 90.64 · 116 BRD-SG-02944 SunoHada 1408.83 90.75 · 117 BRD-GLOBAL-00623 Care 1363.18 90.84 · 118 BRD-SG-03465 The Blessed Soap 1360.9 90.94 · 119 BRD-SG-05040 wollyo 1356.29 91.04 · 120 BRD-SG-01649 Pears 1352.1 91.14 · 121 BRD-GLOBAL-01190 Simple 1342.99 91.24 · 122 BRD-SG-02244 Vytle 1333.36 91.33 · 123 BRD-SG-03381 DermaVeen 1331.61 91.43 · 124 BRD-SG-03690 Ego Pharmaceuticals 1318.32 91.52 · 125 BRD-SG-05907 HQ 1280.0 91.62 · 126 BRD-SG-05964 Beauty Language 1275.66 91.71 · 127 BRD-GLOBAL-00002 La Roche-Posay 1254.96 91.8 · 128 BRD-GLOBAL-01252 Pyunkang Yul 1252.66 91.89 · 129 BRD-SG-00171 Bath & Body Works 1241.59 91.98 · 130 BRD-SG-01499 Maya 1222.98 92.07 · 131 BRD-SG-04209 HOSPIGEL 1177.4 92.15 · 132 BRD-GLOBAL-00863 Enchanteur 1162.01 92.24 · 133 BRD-SG-03637 Baren 1161.97 92.32 · 134 BRD-SG-02529 Everyday 1136.99 92.4 · 135 BRD-GLOBAL-00185 Boots 1123.34 92.48 (retailer own-label — not the multi-brand-retailer exclusion which applies to Boots-as-reseller-of-other-brands) · 136 BRD-SG-11439 Chemist at Play 1118.88 92.56 · 137 BRD-SG-02360 Ubersuave 1088.37 92.64 · 138 BRD-GLOBAL-00404 Johnson's 1018.11 92.72 · 139 BRD-SG-04345 ETL No.7 1011.84 92.79 · 140 BRD-SG-04069 The Soap Haven 1004.83 92.86 · 141 BRD-SG-03743 Hygienix 998.72 92.93 · 142 BRD-GLOBAL-00214 Senka 973.71 93.0 · 143 BRD-SG-03893 A-DERMA 963.0 93.07 · 144 BRD-SG-04729 Tabs 960.92 93.14 · 145 BRD-SG-09064 AMBER 959.0 93.21 · 146 BRD-GLOBAL-01085 Cow Brand 952.77 93.28 · 147 BRD-SG-03909 Kirona Scent 939.12 93.35 · 148 BRD-SG-09368 Base 939.03 93.42 · 149 BRD-GLOBAL-01431 Kracie 928.15 93.48 · 150 BRD-GLOBAL-01257 Pelican 927.11 93.55 · 151 BRD-SG-05437 DHERBS 918.9 93.62 · 152 BRD-SG-03541 YUAN 912.0 93.68 · 153 BRD-SG-06914 AllenMan 904.66 93.75 · 154 BRD-GLOBAL-02220 ON: THE BODY 896.45 93.81 · 155 BRD-SG-04684 HOMLLY 881.1 93.88 · 156 BRD-GLOBAL-00006 Cerave 880.66 93.94 · 157 BRD-GLOBAL-01865 Malaysia Collection 874.03 94.0 · 158 BRD-SG-08070 Bomb 863.68 94.07 · 159 BRD-SG-04540 Nudy Rudy 852.3 94.13 · 160 BRD-SG-06801 Shanghai Sulfur Soap 849.44 94.19 · 161 BRD-SG-02729 Lucky 842.57 94.25 · 162 BRD-SG-07120 GBT 839.77 94.31 · 163 BRD-SG-04128 Nixoderm 831.43 94.37 · 164 BRD-SG-01878 Dalan d'Olive 829.0 94.43 · 165 BRD-SG-00540 Old Spice 818.9 94.49 · 166 BRD-SG-09828 Men+ 816.74 94.55 · 167 BRD-SG-04979 Chandrika 807.68 94.61 · 168 BRD-SG-03811 BACTISHIELD 795.47 94.66 · 169 BRD-SG-04456 Hair+ 794.02 94.72 · 170 BRD-SG-04906 Steril Medical 789.97 94.78 · 171 BRD-SG-04838 Alepia 784.79 94.84 · 172 BRD-SG-04012 Reve Scent 782.2 94.89 · 173 BRD-SG-03918 THE VERDANT LAB 730.0 94.95 · 174 BRD-SG-00462 JMELLA 724.29 95.0

Brands excluded from scope (below 95% cumulative tail, from 95.05% cum onward, e.g. `BRD-TH-00138`
"Your", `BRD-SG-07079` "STILL BOTANICALS", `BRD-GLOBAL-00275` "The Face Shop", `BRD-SG-04742`
"REFRESH WELLNESS", `BRD-SG-04526` "Malin-Goetz", `BRD-GLOBAL-00181` "Protex", `BRD-SG-02733`
"BioNike", `BRD-GLOBAL-00732` "Beauty Buffet", `BRD-SG-02388` "Green Kulture", `BRD-SG-04849`
"Hanboli", `BRD-GLOBAL-01349` "Elizabeth Arden", `BRD-GLOBAL-00296` "Aura", `BRD-GLOBAL-00624`
"Thann", `BRD-SG-01078` "Follow Me", `BRD-SG-03251` "Topicrem", and the remaining long tail down to
~1,596 distinct brand_ids). These may still be routed via bulk text-matching in Pass 2 if they
clearly match an existing taxonomy entry, but are not required reading for Pass 1/2 completeness.

---

## Official Store Allowlist (Pass 1)

Built by querying distinct `merchant_name WHERE merchant_badge='Shopee Mall'` per in-scope brand_id,
then classifying each merchant as (a) the brand's own dedicated channel, (b) a legitimate
parent-company store carrying multiple owned/licensed brands (Pass-1-eligible for all of them, per
CLAUDE.md's parent-company-store guidance), or (c) a general multi-brand
retailer/distributor/marketplace — excluded regardless of "Official Store" naming.

**Multi-brand retailers excluded** (per llm-extraction-rules.md §4's canonical beauty list —
Watsons, Boots, BEAUTRIUM, Sasa, Tsuruha — plus additional general retailers/distributors/
marketplaces confirmed by data: each carries products from many unrelated in-scope brands, not one
brand's own channel):
`Watsons Singapore Official Store`, `Guardian SG Official Store` (except as BRD-SG-02458 "Guardian"
own-label store), `Sasa Official Store`, `Strawberrynet SG Official Store`, `Nana Mall Official
Store`, `myCK_online`, `Prestigio Delights Official`, `BIG Pharmacy`, `Beautyhaus SG`, `BEAUTY U &
ME.SG Official Store`, `HEY SUP`, `Aurigamart Official Store`, `Cosmede Official Store`, `BB Beauty
Global Official Store`, `RedMan Official Store`, `Xiaoling Boutique Store`, `FUJITOKU.JAPAN`,
`Weloveourkids`, `K-Market by Koryo Trading`, `Tsupply Official Store`, `SGPomades Mens Grooming
Store`, `cosblah`, `Ecover Official Store`, `Dr. Scholl Official Store`, `JAWStore - Puritan's
Pride`, `Global Buyer`, `Eltean Plus`.

| Brand(s) covered | brand_id | Official Store Merchant Name | Products | GMV (GWP-zeroed) |
|-------------------|----------|-------------------------------|---|---|
| Dettol | BRD-SG-00034 | `Dettol Official Store` | 115 | 97,749.66 |
| Kirei Kirei, Shokubutsu, Lion, SunoHada | BRD-GLOBAL-00156 + BRD-GLOBAL-00107 + BRD-GLOBAL-00873 + BRD-SG-02944 | `LION Official Store` (parent: Lion Corp) | 36 | 28,914.68 |
| Dove, LUX, Lifebuoy, Simple, St.Ives | BRD-GLOBAL-00123 + BRD-SG-00086 + BRD-SG-01493 + BRD-GLOBAL-01190 + BRD-GLOBAL-01334 | `Unilever Official Store` (parent: Unilever) | 82 | 56,161.62 |
| QV, method | BRD-SG-00660 + BRD-SG-01091 | `Corlison Official Store` (parent-distributor for both brands in SG) | 68 | 27,882.24 |
| QV | BRD-SG-00660 | `QV Official Store` | 29 | 8,669.13 |
| NARD | BRD-GLOBAL-00703 | `Nard Store` | 13 | 47,357.95 |
| sukin | BRD-SG-00948 | `SukinSG Official Store` | 8 | 17,260.56 |
| medicube | BRD-GLOBAL-00299 | `Medicube Official Store` | 4 | 38,072.00 |
| Neutrogena, Aveeno, Johnson & Johnson | BRD-GLOBAL-00080 + BRD-GLOBAL-00265 + BRD-GLOBAL-01271 | `Kenvue Official Store` (parent: Kenvue, ex-J&J Consumer Health) | 31 | 31,038.05 |
| Ginvera, Eversoft, Hygienix | BRD-SG-01315 + BRD-SG-01481 + BRD-SG-03743 | `Bio Essence Official Store` (parent-distributor, SG) | 14 | 34,439.12 |
| Cetaphil | BRD-GLOBAL-00069 | `Cetaphil Official Store` | 10 | 18,151.57 |
| Walch, KHO, Ouji | BRD-SG-00491 + BRD-SG-03123 + BRD-SG-03886 | `Walch SG Official Store` (parent: Walch Group) | 32 | 31,838.62 |
| Ceradan | BRD-SG-00860 | `Ceradan SG Official Store` | 8 | 1,510.54 |
| SOME BY MI | BRD-GLOBAL-00605 | `SOMEBYMI SG Official Store` | 3 | 19,912.94 |
| TODAY With | BRD-SG-02335 | `TODAYWith` | 4 | 18,078.21 |
| Diane, Cow Brand, Bouncia, Lucido | BRD-SG-00703 + BRD-GLOBAL-01085 + BRD-SG-00821 + BRD-GLOBAL-01462 | `Mandom Official Store` (parent: Mandom Corp) | 25 | 21,724.10 |
| Sebamed | BRD-GLOBAL-00142 | `sebamed Official Store` | 6 | 4,446.80 |
| Theo10 | BRD-SG-01755 | `Theo10sg Official Store` | 15 | 15,392.76 |
| Cloversoft | BRD-SG-00919 | `Cloversoft Flagship Store` | 12 | 506.85 |
| Schulke | BRD-SG-02064 | `Aurigamart Official Store` — **excluded, see above; no other dedicated store found → Pass 2 only** | — | — |
| The Body Shop | BRD-GLOBAL-01534 | `The Body Shop Official Store` | 23 | 11,350.92 |
| Alluora | BRD-SG-00567 | `Alluora` | 4 | 11,297.75 |
| Bioderma | BRD-GLOBAL-00062 | `Bioderma Official Store` | 7 | 9,324.05 |
| Biore, Curel, Men's Biore | BRD-GLOBAL-00061 + BRD-GLOBAL-00199 + BRD-GLOBAL-01617 | `Kao Official Store` (parent: Kao Corp) | 6 | 4,252.53 |
| Biore | BRD-GLOBAL-00061 | `Biore Official Store` | 1 | 142.80 |
| Suu Balm | BRD-SG-00424 | `Suu Balm OFFICIAL STORE` (Vytle also appears here but has no confirmed brand relationship — do not treat as Vytle's official store) | 4 | 4,776.85 |
| Eucerin | BRD-GLOBAL-00003 | `EUCERIN Official Store` | 1 | 4,950.20 |
| Aprilskin | BRD-GLOBAL-01300 | `Aprilskin Official Store` | 1 | 7,320.50 |
| Watsons (own private label) | BRD-GLOBAL-00640 | `Watsons Singapore Official Store` — **note: this IS Watsons' own store for its own private-label products; the exclusion above applies to Watsons as a *reseller of other brands*, not to Watsons' own house-brand products** | 47 | 6,983.59 |
| Aesop | BRD-GLOBAL-01368 | (no single dominant own-store; scattered across Beautyhaus SG/Nana Mall/Sasa/Strawberrynet — all excluded multi-brand retailers) → **Pass 2 only** | — | — |
| Bouquet Garni | BRD-GLOBAL-01453 | `Bouquet Garni Official Store` | 11 | 4,661.93 |
| Guardian (own private label) | BRD-SG-02458 | `Guardian SG Official Store` — **this IS Guardian's own store for its own private-label products; exclusion above applies when this store carries other brands** | 25 | 4,467.40 |
| Lynk Fragrances | BRD-SG-02470 | `Lynk Fragrances Official Store` | 3 | 4,432.05 |
| L'Occitane | BRD-GLOBAL-00240 | `L'Occitane Official Store` | 21 | 1,163.00 |
| KUNDAL | BRD-GLOBAL-01205 | `KUNDAL SG` | 7 | 7,808.27 |
| Pyunkang Yul | BRD-GLOBAL-01252 | `PyunkangYul Official Store` | 4 | 1,252.66 |
| The Blessed Soap, Vermont Soap | BRD-SG-03465 + BRD-SG-03591 | `Naturain Official Store` (parent-distributor, natural soap) | 6 | 2,847.50 |
| YUAN | BRD-SG-03541 | `Yuan Skincare & Soap Official Store` | 7 | 912.00 |
| The Verdant Lab | BRD-SG-03918 | `The Verdant Lab Official Store` | 13 | 730.00 |
| Steril Medical | BRD-SG-04906 | `Steril Medical Official Store` | 4 | 789.97 |
| Lush | BRD-GLOBAL-00563 | `Lush Singapore Official Store` | 82 | 2,575.00 |
| Chemist at Play | BRD-SG-11439 | `Onesto Labs PTE. Ltd` | 2 | 1,118.88 |
| SimplyGood | BRD-SG-00814 | `SimplyGood` | 1 | 1,503.20 |
| simplehuman | BRD-SG-03221 | `simplehuman Official Store` | 2 | 283.80 |
| Snake Brand | BRD-GLOBAL-00433 | (only via excluded `Prestigio Delights Official`) → **Pass 2 only** | — | — |

**Brands with no reliable single official store (Pass 2 only):** the remaining ~130 of the 174
in-scope brands, including Undefined (no store possible), Hygeia, Hetras (own store `Hetras`
found at low volume — recheck if needed), Shower Mate, HAN.d, Illiyoon (scattered across
excluded resellers), Two Steps Cleaning (`twostepscleaning`, non-Mall-badged so not in this
allowlist mechanism — route via Pass 2 text match), Dermatological Basics, Lydimoon, Apple,
TidyNethers, Isoderm, Kojie.san, Dr.Bronner's, Deep, yukazan, Seyoul, Safi (`SAFI Official`
appears but low official volume — Pass 2 preferred given ambiguity), Snake Brand, Jam, APPELLES,
KUSTIE, Goat, ICM Pharma, Madame Heng, MadeToBloom, Good Virtues Co., MSCENT, K.Brothers, Molton
Brown, Pine & Co, Herbal Pharm, Apestomen, MyLustre, Palmolive, Blanc Nature, Adidas, Derma Lab,
Goat Soap Australia, medimix, HAPPY BATH, Yuri, Original Source, Emporal Co, Yanzsoap, All, Zappy,
EC Essentials, Botanist, Beyond, ALADA, &Honey, SukGarden, T3, Ollie, NATURIUM, BAD LAB, Ouji,
SKINEVER, Precious Skin, Kumano, Bella, Nivea, Care, wollyo, Pears, Vytle, DermaVeen, Ego
Pharmaceuticals, HQ, Beauty Language, La Roche-Posay, Bath & Body Works, Maya, HOSPIGEL,
Enchanteur, Baren, Everyday, Boots, Ubersuave, Johnson's, ETL No.7, The Soap Haven, Senka,
A-DERMA, Tabs, AMBER, Kirona Scent, Base, Kracie, Pelican, DHERBS, AllenMan, ON: THE BODY, HOMLLY,
Cerave, Malaysia Collection, Bomb, Nudy Rudy, Shanghai Sulfur Soap, Lucky, GBT, Nixoderm, Dalan
d'Olive, Old Spice, Men+, Chandrika, BACTISHIELD, Hair+, Alepia, Reve Scent, JMELLA.

---

## Scope — What's In vs Out

**In scope:**
- Liquid hand soap / hand wash (all formats: pump bottle, refill pouch, foaming)
- Liquid body wash marketed primarily as antibacterial/medicated liquid soap (e.g. Dettol)
- Bar soap that is the brand's core liquid-soap-adjacent SKU line is OUT (see below) — this table
  is liquid soap specifically; solid/bar soap products appearing here are a data-quality bleed and
  should be judged per-listing

**Out of scope (leave NULL):**
- Standalone shampoo, conditioner, body lotion/moisturizer, or facial cleanser products that
  bleed into this table under a liquid-soap brand's storefront but are not a liquid soap SKU
  themselves
- Hand sanitizer (no rinse, alcohol-based) — different product type from liquid soap despite
  similar antibacterial marketing
- Dishwashing liquid / laundry liquid detergent mis-tagged into this table under a generic "liquid
  soap" NIQ mapping

**Edge cases:**
- **Dettol**: sells both liquid hand soap and liquid body wash under the same brand — both are
  in scope for this category (Dettol markets them together as one "liquid soap" range); judge
  per-listing only to exclude non-soap Dettol SKUs (e.g. antiseptic liquid, wipes) if they appear.
- **Guardian / Watsons private-label**: only the private-label liquid soap SKUs are in scope under
  those brand_ids — do not conflate with the retailers' multi-brand reseller activity (excluded
  from Pass 1 allowlist above).

---

## Taxonomy Design Notes

**Product line extraction approach:**
- Text-first from `sku_name` (sellers reliably fill this in) — per llm-extraction-rules.md §3, use
  the real on-label line name (e.g. "Skincare Antibacterial", "Cool", "Gold"), never a bare
  "Liquid Soap"/"Hand Wash"/"Body Wash" category word.
- Parent-company stores (Unilever, Kao, LION, Mandom, Kenvue, Bio Essence, Walch, Corlison,
  Naturain): disambiguate `brand_from_image`/sku_name per product since the storefront spans
  multiple owned brands.

**Size extraction notes:**
- Primary units: ml (pump bottles, common 250ml/450ml/500ml/900ml), L for large refills, g for bar
  soap bleed-through if any.
- Refill-pack promo language common in this category (`refill`, `isi ulang`-style bundle wording is
  not expected for SG/English listings, but "value pack", "twin pack", "refill + bottle" bundles
  are) — apply the standard §1 GWP-vs-multipack distinction (bottle + refill of the SAME product
  sold together = genuine multipack, not GWP, unless the refill is explicitly a different product).

**Known difficult products:**
- None identified yet — will be logged here as Pass 1/2 encounters them.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-23 | Category-file research | 1,726 existing HUMAN keyword-seed rows found (0 LLM) — confirms genuine first LLM pass, matches wrapper's live pre-check | None needed — proceed with Full Rebuild per headless-runbook.md |
| 2026-07-23 | Category-file research | Naive top-15/20-brand snapshot would have undercounted brand scope — real 95% threshold is 174 brands (unusually long tail for this vertical), not ~15-20 | Used full cumulative-GMV ranking via canonical brand_id, listed all 174 |
| 2026-07-23 | Category-file research | Raw in-scope worklist framing (20,072 distinct products) overstates true scope — real in-scope set (Rule A ∪ Rule B) is 3,208 products (later refined to 3,696 with the final brand list) | Computed and used the real §2 in-scope query before starting extraction |
| 2026-07-23 | Pass 1 (Official) | Claimed SKU block SKU-129756–131755 (2000 slots, full_rebuild). Built taxonomy from 40 allowlisted official-store fronts, 780 candidate products. Bulk regex-based size/pack_count extraction (sku_name text) + per-brand product_line rules derived from direct reading of the pull. | 569 taxonomy entries minted (SKU-129756–130324), 686 products mapped |
| 2026-07-23 | Pass 1 (Official) | Scope-correctness catches during extraction: (1) solid **bar soap** listings (Dettol Bar Soap, Cow Brand Beauty Body Bar Soap, Lifebuoy Anti-Bacterial Bar Soap — all weight-labeled, no liquid signal) are a different physical format than "liquid soap" and were excluded, not force-mapped. (2) Yuan brand's "Soap (115g)" bar-soap SKUs excluded; only their "Body Wash" liquid SKUs mapped. (3) Lush's official store is 90%+ bath bombs/bubble bars/bar soap (non-wash formats) — only Shower Gel/Shower Cream/Shower Jelly listings included. (4) A size-extraction regex bug initially grabbed a bundled GWP freebie's size (100g) instead of the main product's real size (250ml) for a Neutrogena listing — caught by cross-checking against a sibling listing before insert, per llm-extraction-rules.md §11. | Excluded 94 of 780 Pass-1 candidates as OOS-format/indeterminate (documented, not silently dropped); fixed size bug before insert |
| 2026-07-23 | Pass 2 (Reseller) | Live worklist re-query (post Pass-1) found 1,637 in-scope-month products still NULL. Routed via bulk regex-based text extraction (reused Pass-1's brand rule functions where the brand matched; generic cleaned-text fallback for ~250 long-tail brands with no dedicated rule) — reuse-before-mint against Pass-1's own taxonomy entries first (60 products reused), then minted new entries for the rest. 426 of the 1,637 gap products carried `brand_id = BRD-UNDEFINED`; 80 of those were re-identified to a real brand by scanning `sku_name` for a known in-scope brand name (taxonomy mapping does not require `brand_id` agreement with `product_brand_map`, per precedent). | 1,045 new entries minted (SKU-130325–131369), 1,262 products mapped (1,202 new + 60 reused) |
| 2026-07-23 | Pass 2 (Reseller) | Format-based scope filter (bar soap by weight-unit absent any liquid/wash/gel/foam signal; body lotion/balm/butter/treatment; bath bomb/bubble bar) applied per-product across the full gap, not as a pre-extraction brand filter — excluded 375 of 1,637 gap products. Two whole-brand-level OOS findings: **Goat Soap Australia** (100% bar soap, no liquid SKU exists under this brand at all) and (partially) **Pelican** (predominantly 80g bar soap) — confirmed via direct reading of every gap row for these brands, not assumed from brand name. A few individual misses caught and fixed before insert: a "South Moon" nasal-inhaler-stick listing (wrong product type entirely, not a wash), an Aesop "Hand Wash / Hand Balm" bundle initially over-excluded by the bar/balm keyword filter (fixed: only exclude when no wash/liquid keyword is also present), and a Neutrogena "Clear Body Wash" naming variant the brand's own product-line rule initially missed. | All fixed before insert; format-oos exclusions documented per product, not silently dropped |
| 2026-07-23 | Pass 2 (Reseller) | **Self-inflicted placeholder-leak gate failure, caught and fixed same session**: canonical names synthesized for `BRD-UNDEFINED`-branded entries used the literal brand_dict display name "Undefined" as a name prefix (e.g. "Undefined Acne Body Wash 300ml") — this trips the hard-gate's banned-word check on "undefined" itself. Found by running the QA gate immediately after Pass 2 insert, before declaring done. | `UPDATE` stripped the leading "Undefined " token from all 252 affected `product_taxonomy` rows (`REGEXP_REPLACE(canonical_name, r'^Undefined ', '')`); placeholder-leak re-ran at 0 for `source='LLM'` |
| 2026-07-23 | Post-run QA gates | Unscoped placeholder-leak query (whole category, HUMAN+LLM combined) returns 1,271 — traced to pre-existing `source='HUMAN'` keyword-seed rows created 2026-06-18 (before this session), all using a banned "(all variants)" catch-all phrasing (e.g. "Dettol Antibacterial Liquid Soap / Body Wash (all variants)"). **Not remediated this session** — out of scope for a Full Rebuild (this is `script/targeted_qa_fix.sh` auto-discovery territory); flagged here for a future targeted QA pass. | Left as-is; `source='LLM'`-scoped placeholder-leak (this session's actual output) is 0 |
| 2026-07-23 | Top-up coverage (month 2026-06) | Live re-query of the STEP 0 worklist (top-95%-cum-GMV, GWP-zeroed, `taxonomy_id IS NULL`) found 664 rows / 552 distinct products, close to the wrapper's stale 664 pre-check. Format classification (sku_name text, cross-checked against 9 representative product images across ALADA/Madame Heng/YUAN/SKINEVER/Herbal Pharm/Lydimoon/Precious Skin/Snail White/Yanzsoap) found the overwhelming majority — 345 of 664 rows, $50,674 GMV — are **solid/bar-format "Whitening Soap"/"Herbal Soap" listings** (weight-in-grams, no liquid unit or wash/gel/foam keyword), the same data-quality bleed already documented in this file's Pass-1/Pass-2 QA rows, not a coverage miss. One prior-session mapping (`SKU-130555` "Precious Skin Extra Pure Gluta White Soap") is itself now suspected mismapped bar soap based on this session's image check — flagged for a future targeted QA pass, not corrected here (out of top-up scope). A further 40 rows ($4.3k GMV) were bath bombs/bubble bars, standalone body lotion/cream bleed, or unrelated product types (nasal inhaler, bath sponge, fragrance body spray, facial cleanser) miscategorized into this table — excluded per category scope, not force-mapped. | 273 rows ($16,665 GMV) confirmed genuine liquid soap/wash format and processed; 391 rows ($56,266 GMV) left NULL as documented OOS |
| 2026-07-23 | Top-up coverage (month 2026-06) | Bulk-first reuse-before-mint per headless-runbook.md: grouped the 273 in-scope rows by (brand_id, normalized product-line text, size, pack_count) → 266 distinct products. Token-overlap matching against the category's existing 1,654 taxonomy entries (same brand_id, same size, ≥50% Jaccard token overlap) found 24 genuine reuse matches (duplicate listings of already-taxonomized products across different resellers/sellers). Resolved 5 `BRD-UNDEFINED` products to their real brand (Dove ×2, Kirei Kirei ×2, Aesop ×1) by scanning sku_name for a known brand token, consistent with th_softdrink precedent that taxonomy mapping does not require `brand_id` agreement with `product_brand_map`. | 24 products mapped to existing taxonomy entries (no new SKU); remaining 242 distinct products minted as new entries |
| 2026-07-23 | Top-up coverage (month 2026-06) | Claimed SKU block SKU-134532–135195 (664 slots, `taxonomy_topup`) per the atomic-claim pattern — queried `sku_block_registry` live, did not trust this file's stale numbers. Minted 242 new `product_taxonomy` entries (SKU-134532–134773) via bulk regex-based size/pack_count extraction from sku_name text (ml/L/oz/kg/g units; bundle/x-N pack patterns) — no per-product image reads for minting (text was sufficient in all 242 cases; the representative-sample image checks above were for the format/scope decision, not per-product extraction). Verified zero `canonical_name` "undefined" leaks before insert (`BRD-UNDEFINED` appears only in the brand_id column, never in canonical_name text, avoiding the exact defect from this file's earlier Pass-2 QA row). Wrote via `bq query` DML only. `sku_block_registry` marked COMPLETE; SKU-134774–135195 left unused. | 242 taxonomy entries inserted, 267 distinct products mapped (24 reused + 243 new-entry rows collapse to 242 distinct entries via 1 exact-duplicate group; 6 worklist rows shared a product_id with another row and correctly deduped to 1 map row per product_id, per the "one row per product_id" rule) |
| 2026-07-23 | Top-up coverage — QA self-check | Ran QA-gate-as-code from headless-runbook.md **without** `--skip-coexistence` per this session's instructions. G1 dual-mapped (source=LLM) = 0. Placeholder-leak (source=LLM) = 0. G5 provenance = 0. structured_fields_missing_pct = 0%. **G2 HUMAN+LLM coexistence = 491** — verified this is the exact pre-existing count from the prior Full Rebuild session (this file's own QA History row above, "no dedup/delete step run this session"), confirmed **not** introduced by this top-up: none of this session's 267 newly-mapped `product_id`s had a pre-existing `source='HUMAN'` row (explicit `IN`-list check against the map table returned 0). The Full Rebuild's step-5 HUMAN-dedup-delete was never run in either session — this remains a genuine open item but is unchanged by this top-up. | No action taken on G2 (out of this session's instructed scope — no dedup/delete step was requested); flagged for whoever next runs the HUMAN-row cleanup per docs/headless-runbook.md's Full Rebuild step 5 |

---

## Targeted QA Fix Brief

(Not applicable — this is the initial Full Rebuild, not a targeted fix. Future QA passes should
use `script/targeted_qa_fix.sh` auto-discovery mode per docs/headless-runbook.md.)

---

## Scripts

Extraction performed directly by Claude Code multimodal/text reading during this headless session —
no pipeline scripts under `pipeline/05_product_taxonomy/llm_shopee_sg_liquid_soap/` exist or are
needed for this run.

---

## Map Row Counts

| Source | Before Full Rebuild | After Full Rebuild | After top-up (2026-07-23) | Notes |
|--------|-----------------|-----------------|-----------------|-------|
| LLM | 0 | 1,948 | 2,215 | 686 Pass 1 + 1,262 Pass 2 + 267 top-up (24 reused-entry + 243 new-entry) |
| HUMAN | 1,726 | 1,726 | 1,726 | Untouched across both sessions — no HUMAN dedup/delete step run yet |
| In-scope set (month 2026-06 top-up worklist) | — | — | 664 live worklist rows re-queried; 273 mapped, 391 confirmed OOS (bar soap / bath bomb / lotion bleed / unrelated) | See QA History for the full OOS breakdown |
| GMV coverage (all products, 2026-06) | — | 94.5% | not re-measured this session (worklist was Rule-A-only, not the full §2 in-scope set) | — |

**Universe refresh:** not run this session (explicitly out of scope for this top-up prompt — a separate step, to run only after independent QA verification). A future session should run the `universe_taxonomy_overlay` MERGE per docs/headless-runbook.md before this category's data reaches `marketshare_universe`.

**QA gate results (top-up session, 2026-07-23, run without `--skip-coexistence`):**
```
G1 dual-mapped (source=LLM) ................ 0  ✅
Placeholder-leak (source=LLM) ............... 0  ✅
structured_fields_missing_pct (product_line NULL, excl. is_multi_size) .. 0%  ✅
G5 provenance (meta_agent/source NULL) ...... 0  ✅
G2 HUMAN+LLM coexistence .................... 491  ⚠️ pre-existing from prior Full Rebuild session, confirmed NOT introduced by this top-up (0 of this session's 267 mapped product_ids had a prior HUMAN row) — unresolved dedup-delete step remains an open item
```

**QA gate results (prior Full Rebuild session, for reference):**
```
G1 dual-mapped (source=LLM) ................ 0  ✅
Placeholder-leak (source=LLM, that session)   0  ✅
Placeholder-leak (unscoped, incl. legacy HUMAN rows)  1,271  ⚠️ pre-existing, not that session's scope
structured_fields_missing_pct (product_line NULL, excl. is_multi_size) .. 0%  ✅
G5 provenance (meta_agent/source NULL) ...... 0  ✅
G2 HUMAN+LLM coexistence .................... 491  (expected at that point — no dedup/delete step had run yet)
```
