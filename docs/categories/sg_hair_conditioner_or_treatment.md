# shopee_sg_hair_conditioner_or_treatment — Category Context

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ⏳ In progress |
| LLM Pass 2 | ⏳ In progress |
| GMV Coverage | TBD% (Jun 2026) |
| Last run | 2026-07-23 (this session) |
| Current MAX taxonomy_id | SKU-134131 (as of 2026-07-23 top-up session #3; query BQ directly, never trust this static value) |

**Note on this session's starting premise:** the wrapper prompt that kicked off this run stated "no category
context file exists yet" and "first-run invocation." Both were inaccurate — this file already existed
(added 2026-07-20 in commit `4848f1e`, based on a 2026-07-16 session that computed Apr-2026 brand scope +
official-store allowlist but wrote zero `product_taxonomy_map` LLM rows and never claimed a SKU block). That
2026-07-16 research is superseded below with real June-2026 numbers (the review month this run was asked to
use). This file is kept at its existing path (`sg_hair_conditioner_or_treatment.md`, no `shopee_` prefix) per
the naming convention `STATUS.md` already uses and commit `4848f1e` established — **not** at the
`shopee_sg_hair_conditioner_or_treatment.md` path the wrapper prompt named, to avoid forking the docs. Verified
live: 0 `source='LLM'` rows exist for this table (2,187 `HUMAN` rows only) — the wrapper's "first LLM run"
framing is correct even though "no file / first-run" was not.

---

## SKU Blocks Assigned

| Block | Usage | Status |
|-------|-------|--------|
| SKU-074001–075000 | (stale — 2026-07-16 session's note) | **Superseded/invalid.** 188 unrelated `product_taxonomy` rows now occupy this range from other categories' work since Jul 16. Never used. |
| SKU-122056–124055 | Full Rebuild (Pass 1 + Pass 2), this session | Never used — superseded by the actual Full Rebuild block below before any writes landed |
| SKU-124556–126555 | Full Rebuild | ACTIVE |
| SKU-128556–129555 | Full Rebuild supplemental | ACTIVE |
| SKU-131756–133645 | Top-up coverage session #2 (2026-07-23) | ACTIVE — used 131756–131934, 1,761 slots unused |
| SKU-134046–134145 | Top-up coverage session #3 (2026-07-23, this session) | RELEASED — used 134046–134131 (86 entries), 14 slots unused |

---

## Brand Scope (GMV threshold 95%, **Jun 2026**, GWP-zeroed)

**231 brands in scope** (cumulative GMV up to Keratin Complex at 95.03%; includes `BRD-UNDEFINED` at rank 13,
which has no real "brand" or official store but must stay in the ranked list since its GMV is real and counts
toward the 95% denominator — so 230 addressable brands + 1 undefined bucket). Computed via `bq query
--max_rows=2000` (the default `bq` CLI cap silently truncates to 100 rows without this flag — confirmed live:
the naive first pass returned only 100 brands reaching 84% cumulative, which would have been exactly the kind
of ~6x undercount this file's own prior version was warned against).

Full ranked list (all 231, GMV in SGD):

1. **UNOVE** — `BRD-SG-00480` — SGD 132085.4
2. **Kérastase** — `BRD-SG-00007` — SGD 130749.5
3. **Hair+** — `BRD-SG-04456` — SGD 97330.8
4. **REGAINE** — `BRD-SG-00937` — SGD 63835.9
5. **Dr.ville** — `BRD-GLOBAL-00875` — SGD 54305.8
6. **Miriqa** — `BRD-SG-01107` — SGD 52905.8
7. **Milbon** — `BRD-GLOBAL-00357` — SGD 49288.3
8. **Shiseido** — `BRD-GLOBAL-00072` — SGD 48812.6
9. **Fayre Beauty** — `BRD-SG-00858` — SGD 48582.1
10. **groWell** — `BRD-SG-01065` — SGD 47394.1
11. **d'Alba** — `BRD-GLOBAL-00013` — SGD 46940.7
12. **PO KIN TONG 保健堂** — `BRD-SG-00932` — SGD 46693.4
13. **BRD-UNDEFINED** — `BRD-UNDEFINED` — SGD 45491.5 *(no official store; reseller/unbranded GMV only)*
14. **Grafen** — `BRD-GLOBAL-01072` — SGD 41291.4
15. **ICM Pharma** — `BRD-SG-00833` — SGD 38151.2
16. **Olaplex** — `BRD-SG-00057` — SGD 37129.5
17. **Regro** — `BRD-SG-00323` — SGD 33195.9
18. **L'Oreal Paris** — `BRD-SG-00815` — SGD 32642.8
19. **Julioly** — `BRD-SG-01050` — SGD 31857.0
20. **Seapuri** — `BRD-SG-01247` — SGD 30827.7
21. **Lilyeve** — `BRD-SG-01636` — SGD 27562.6
22. **The Ordinary** — `BRD-SG-00010` — SGD 25937.7
23. **Dr.FORHAIR** — `BRD-SG-00783` — SGD 25680.3
24. **ATHALIA** — `BRD-SG-02241` — SGD 23554.7
25. **BiOSys** — `BRD-SG-01436` — SGD 22981.2
26. **Alluora** — `BRD-SG-00567` — SGD 22278.1
27. **Growus** — `BRD-GLOBAL-01116` — SGD 21985.6
28. **VT COSMETICS** — `BRD-GLOBAL-00406` — SGD 20185.8
29. **Fayre** — `BRD-SG-01388` — SGD 19822.6
30. **SOME BY MI** — `BRD-GLOBAL-00605` — SGD 19233.8
31. **NARD** — `BRD-GLOBAL-00703` — SGD 18594.7
32. **Kaminomoto** — `BRD-SG-01076` — SGD 17853.9
33. **MadeToBloom** — `BRD-SG-00973` — SGD 17549.9
34. **Aveda** — `BRD-SG-00486` — SGD 16906.0
35. **L'Oreal Professionnel** — `BRD-GLOBAL-00222` — SGD 16326.1
36. **Care** — `BRD-GLOBAL-00623` — SGD 16007.9
37. **Nutrafol** — `BRD-SG-02765` — SGD 15731.4
38. **MiseEnScene** — `BRD-GLOBAL-00509` — SGD 15448.1
39. **Beauty Language** — `BRD-SG-05964` — SGD 15201.0
40. **Phytopecia** — `BRD-SG-01077` — SGD 14847.4
41. **Anuko** — `BRD-SG-01962` — SGD 14520.2
42. **MUCOTA** — `BRD-SG-01358` — SGD 14239.1
43. **Har** — `BRD-SG-01009` — SGD 13872.5
44. **Nourkrin** — `BRD-SG-01853` — SGD 13453.9
45. **Tsubaki** — `BRD-SG-00050` — SGD 13109.3
46. **Stryv** — `BRD-SG-01842` — SGD 12964.3
47. **Moroccanoil** — `BRD-SG-00233` — SGD 12703.2
48. **KUNDAL** — `BRD-GLOBAL-01205` — SGD 12513.6
49. **Sugardoll** — `BRD-SG-01913` — SGD 12251.3
50. **Ryo** — `BRD-SG-00348` — SGD 12045.1
51. **Lassie Manna** — `BRD-SG-00160` — SGD 11801.9
52. **Fino** — `BRD-SG-00111` — SGD 11393.3
53. **＆honey** — `BRD-SG-03756` — SGD 11073.5
54. **RENE FURTERER** — `BRD-SG-01518` — SGD 10804.9
55. **TOKIO IE** — `BRD-SG-01388` — SGD 10501.3
56. **andSons** — `BRD-SG-01523` — SGD 10240.5
57. **Trichoderm** — `BRD-SG-01520` — SGD 10007.4
58. **Primucell** — `BRD-SG-02203` — SGD 9782.6
59. **Pantene** — `BRD-GLOBAL-00090` — SGD 9584.6
60. **MASIL** — `BRD-SG-01526` — SGD 9401.9
61. **Yanagiya** — `BRD-SG-01263` — SGD 9247.0
62. **Kyogoku Professional** — `BRD-SG-01917` — SGD 9078.5
63. **Aromatica** — `BRD-GLOBAL-01310` — SGD 8887.4
64. **L'Occitane** — `BRD-GLOBAL-00240` — SGD 8724.8
65. **Bee Choo Origin** — `BRD-SG-01680` — SGD 8547.0
66. **Julyme** — `BRD-GLOBAL-01565` — SGD 8352.9
67. **Shea Moisture** — `BRD-GLOBAL-01402` — SGD 8176.0
68. **mandom** — `BRD-GLOBAL-02045` — SGD 7996.7
69. **Raip** — `BRD-SG-00426` — SGD 7826.5
70. **Goldwell** — `BRD-SG-01282` — SGD 7657.3
71. **Suu Balm** — `BRD-SG-00424` — SGD 7484.9
72. **KAMINOWA** — `BRD-SG-02539` — SGD 7318.6
73. **Toppik** — `BRD-SG-02849` — SGD 7147.5
74. **Clovee** — `BRD-SG-02461` — SGD 6979.4
75. **Lucido-L** — `BRD-GLOBAL-00978` — SGD 6816.9
76. **Kerasys** — `BRD-SG-01463` — SGD 6659.7
77. **Klorane** — `BRD-SG-01040` — SGD 6510.7
78. **LebeL** — `BRD-SG-00782` — SGD 6355.3
79. **Orbis** — `BRD-GLOBAL-01541` — SGD 6208.0
80. **GATSBY** — `BRD-GLOBAL-01435` — SGD 6069.5
81. **Advante** — `BRD-SG-01831` — SGD 5921.2
82. **Dixmondsg** — `BRD-SG-00777` — SGD 5787.9
83. **DASHU** — `BRD-GLOBAL-01395` — SGD 5654.1
84. **Viviscal** — `BRD-GLOBAL-01112` — SGD 5533.0
85. **Nature's Organic Sense** — `BRD-SG-01899` — SGD 5407.6
86. **Ubersuave** — `BRD-SG-02360` — SGD 5289.1
87. **FORBEAUT** — `BRD-SG-02572` — SGD 5169.7
88. **ellips** — `BRD-SG-01422` — SGD 5052.7
89. **Oribe** — `BRD-SG-00290` — SGD 4939.5
90. **Clear** — `BRD-GLOBAL-00148` — SGD 4834.4
91. **Rehues** — `BRD-SG-02161` — SGD 4737.5
92. **Off&relax** — `BRD-SG-01524` — SGD 4634.6
93. **Amazing Ammar** — `BRD-SG-02662` — SGD 4534.5
94. **iRestore** — `BRD-SG-02967` — SGD 4442.6
95. **sukin** — `BRD-SG-00948` — SGD 4352.5
96. **Apestomen** — `BRD-SG-01926` — SGD 4262.5
97. **AYUNCHE** — `BRD-SG-07294` — SGD 4174.6
98. **Dove** — `BRD-GLOBAL-00123` — SGD 4089.4
99. **medicube** — `BRD-GLOBAL-00299` — SGD 4008.4
100. **Curel** — `BRD-GLOBAL-00199` — SGD 3931.6
101. **Naissant** — `BRD-SG-02362` — SGD 3856.0
102. **Biacid** — `BRD-SG-02631` — SGD 3785.1
103. **Watmaion** — `BRD-SG-02643` — SGD 3716.0
104. **AHC** — `BRD-GLOBAL-00914` — SGD 3648.5
105. **MARO** — `BRD-SG-01466` — SGD 3583.0
106. **Bond** — `BRD-GLOBAL-00448` — SGD 3535.6
107. **Elage** — `BRD-SG-01871` — SGD 3457.4
108. **Sevich** — `BRD-SG-00458` — SGD 3396.0
109. **Fino Premium Touch** — `BRD-SG-09805` — SGD 3339.7
110. **Bananal** — `BRD-SG-02781` — SGD 3283.1
111. **Cavilla** — `BRD-SG-05314` — SGD 3227.9
112. **Diane** — `BRD-SG-00703` — SGD 3173.3
113. **NaturVital** — `BRD-SG-01859` — SGD 3120.8
114. **Schwarzkopf Professional** — `BRD-SG-03343` — SGD 3068.9
115. **davines** — `BRD-SG-00127` — SGD 3018.2
116. **Wella** — `BRD-SG-00807` — SGD 2967.5
117. **Phyto** — `BRD-GLOBAL-00800` — SGD 2919.0
118. **Neo Hair** — `BRD-SG-00237` — SGD 2871.5
119. **O'right** — `BRD-SG-02899` — SGD 2825.0
120. **Pilgrim** — `BRD-SG-03109` — SGD 2779.5
121. **COCO & EVE** — `BRD-GLOBAL-01342` — SGD 2734.9
122. **Nioxin** — `BRD-SG-00418` — SGD 2691.7
123. **Sunsilk** — `BRD-SG-00021` — SGD 2649.4
124. **Lakme** — `BRD-SG-00869` — SGD 2607.9
125. **Alpecin** — `BRD-SG-00573` — SGD 2567.2
126. **Get** — `BRD-TH-01966` — SGD 2527.4
127. **All** — `BRD-SG-06567` — SGD 2488.4
128. **anillo** — `BRD-SG-02784` — SGD 2450.2
129. **Hoyu** — `BRD-SG-02187` — SGD 2412.9
130. **Lush** — `BRD-GLOBAL-00563` — SGD 2376.4
131. **Tresemme** — `BRD-SG-00042` — SGD 2340.7
132. **Schwarzkopf** — `BRD-SG-00289` — SGD 2305.8
133. **Nature Republic** — `BRD-GLOBAL-00311` — SGD 2271.7
134. **Deep** — `BRD-SG-12678` — SGD 2238.5
135. **Wella Professionals** — `BRD-SG-01111` — SGD 2206.1
136. **Innisfree** — `BRD-GLOBAL-00070` — SGD 2174.5
137. **CHIETT** — `BRD-SG-03390` — SGD 2143.6
138. **Rene Furterer** — `BRD-SG-05012` — SGD 2113.5
139. **Elizavecca** — `BRD-SG-01605` — SGD 2084.1
140. **Original Sprout** — `BRD-SG-00994` — SGD 2055.4
141. **Bio** — `BRD-SG-01390` — SGD 2027.4
142. **Daeng Gi Meori** — `BRD-GLOBAL-00082` — SGD 2000.1
143. **The Body Shop** — `BRD-GLOBAL-00035` — SGD 1973.5
144. **Kumano** — `BRD-SG-01477` — SGD 1947.5
145. **Reuzel** — `BRD-SG-01606` — SGD 1922.1
146. **NATURIA** — `BRD-SG-03886` — SGD 1897.3
147. **K18 Hair** — `BRD-SG-02207` — SGD 1873.1
148. **Herbal Essences** — `BRD-GLOBAL-00091` — SGD 1849.4
149. **KMS** — `BRD-SG-01458` — SGD 1826.2
150. **Audace** — `BRD-SG-03059` — SGD 1803.6
151. **Vita Green** — `BRD-GLOBAL-01120` — SGD 1781.5
152. **Plantur 39** — `BRD-GLOBAL-01253` — SGD 1760.0
153. **BIOSTIMULINES** — `BRD-SG-03610` — SGD 1739.0
154. **Aussie** — `BRD-GLOBAL-00095` — SGD 1718.5
155. **simplyO** — `BRD-SG-03920` — SGD 1698.5
156. **Dr. Groot** — `BRD-SG-02244` — SGD 1679.0
157. **Nano Singapore** — `BRD-SG-04166` — SGD 1660.0
158. **Elixir** — `BRD-SG-02890` — SGD 1641.5
159. **BioNike** *(and remaining brands 159–231, each SGD ≤1081.0 — 73 brands, cumulative long tail from ~78.6% to 95.03%)*

*(Ranks 159–231 recorded in the raw query output `/tmp/brand_scope_full.csv` from this session but not
individually transcribed here to keep this file readable — every one of the 231 brand_ids was used to build
the official-store allowlist below, per Rule B of `docs/quality-standards.md` §2. Selected names spot-checked
in that range: PUREOLOGY, Infinity, &Be, Nuskin, Moremo, Richenna, Ford, method, Kiehl's, Oway, LADOR, Yves
Rocher, Kao Curel, Silkpro, Herbal Care, Keratin Complex.)*

**Brands excluded from scope** (below 95% GMV threshold): hundreds of long-tail brands, each individually
< SGD 980.

**⚠️ Critical finding — do not bulk-map by brand.** The top of this brand list is dominated by hair-loss /
hair-growth pharmaceutical and supplement brands (REGAINE = Minoxidil, Miriqa = oral supplement, Nourkrin =
oral tablets, Regro = Minoxidil, Dr.ville/Seapuri/ATHALIA/Fayre = anti-hair-loss tonics, Toppik = fiber
concealer, iRestore = laser device, Viviscal = oral supplement), which are **out of scope** for this category
per the Scope section below even though the *brand* is in the GMV-95% scope. A text-scan of the top 25
products by June GMV found ~60% (15/25) are hair-loss/growth pharma or supplements, not conditioner/treatment.
**The taxonomy must be built per product line, not per brand** — every brand in this list can have both
in-scope (conditioner/treatment) and out-of-scope (shampoo, minoxidil, oral supplement, styling, dye) listings
simultaneously. A bulk `INSERT` that maps "all of Brand X's official-store products" to one conditioner entry
would badly violate G4 (cross-category mapping) and D1/D2 (wrong product line).

---

## Official Store Allowlist (Pass 1)

Built by querying distinct `merchant_name WHERE merchant_badge='Shopee Mall'` per brand_id in the 231-brand
scope, June 2026. **Excluded per `llm-extraction-rules.md` §4's beauty list:** Sasa Official Store, Watsons
Singapore Official Store (Boots/BEAUTRIUM/Tsuruha do not appear in this table's data). **163 brands** have at
least one qualifying Mall-badged store; **217 distinct merchant names** remain after the two exclusions.
**Parent-company stores kept as Pass-1-eligible for every brand they carry** (not excluded as multi-brand),
per this session's task instruction: P&G Official Store / P&G Beauty Official Store (Pantene), Unilever
Official Store (Clear, Dove, Sunsilk, Tresemme).

Top 45 brands by official-store product volume (June 2026; store name with product count in that store):

| Brand | Official/Mall stores (n products) |
|---|---|
| Hair+ | Beauty Morning Makeup Boutique (32), Xiaoling Boutique Store (31), Xi Yao Health Center3.sg (12), 77 Boutique Pavilion (11), YA YA Beauty Salon (11), Mrs. Fang's Boutique (9), +57 more — **see contamination note below** |
| Kérastase | KimageSalon Official Store (54), Strawberrynet SG Official Store (50), Kerastase (47), Nana Mall Official Store (43), Cosmede Official Store (18), HEY SUP (5), +3 more |
| BRD-UNDEFINED | Xiaoling Boutique Store (14), Beauty Morning Makeup Boutique (14), YA YA Beauty Salon (9), 77 Boutique Pavilion (8), +51 more |
| Care | Xiaoling Boutique Store (23), YA YA Beauty Salon (18), Beauty Morning Makeup Boutique (14), +14 more |
| Olaplex | Olaplex Official Store (51), Strawberrynet SG (8), Beautyhaus SG (6), Nana Mall Official Store (6), BB Beauty Global (6), +3 more |
| L'Oreal Paris | L'Oreal Paris Official Store (28), Strawberrynet SG (20), Guardian SG (13), KimageSalon (12), myCK_online (5), Nana Mall (1) |
| Shiseido Professional | Shiseido Professional (67) |
| Sevich | SEVICH Official Store (56), LEWEDO Official Store (6) |
| Aveda | Strawberrynet SG (31), Nana Mall (16), Cosmede (7), Beautyhaus SG (4), +2 more |
| Dr.ville | Dr.ville SG Office Store (34), BUV·DR (17), KAZOO Mall Store (9) |
| RENE FURTERER | René Furterer Official Flagship Store (20), Guardian SG (16), Strawberrynet SG (13), Nana Mall (6), +2 more |
| Pantene | P&G Official Store (22), P&G Beauty Official Store (18), Guardian SG (13), Oral Oasis (2), myCK_online (2) |
| Lakme | LAKMÉ Official Store (54), Shins.sg Official Store (3) |
| Tsubaki | Fine Today Japan (15), Prestigio Delights Official (10), Guardian SG (4), Nana Mall (4), +5 more |
| KUNDAL | Guardian SG (22), KUNDAL SG (20) |
| Ryo | AMOREPACIFIC Hair&Beauty Shop (24), Guardian SG (15) |
| sukin | Natural Therapeutic House (20), SukinSG Official Store (16), Guardian SG (2), Beautyhaus SG (1) |
| L'Occitane | L'Occitane Official Store (24), Nana Mall (5), BEAUTY U & ME.SG (3), Strawberrynet SG (3), Beautyhaus SG (2) |
| NaturVital | NaturVital Official Store (26), Guardian SG (11) |
| UNOVE | UNOVE KOREA OFFICIAL STORE (22), Tsupply Official Store (8), Pestlo.SG (5), Nana Mall (1) |
| Schwarzkopf Professional | Schwarzkopf Professional (36) |
| davines | Strawberrynet SG (35) |
| Wella | Strawberrynet SG (33), Wella Professionals (1) |
| Phyto | Beauté By Nature (17), Strawberrynet SG (10), Guardian SG (6) |
| Neo Hair | Xi Yao Health Center (11), Xi Yao Health Center3.sg (10), 77 Boutique Pavilion (9), +2 more |
| Shiseido | Nana Mall (11), HEY SUP (6), Strawberrynet SG (4), BB Beauty Global (4), +4 more |
| Moroccanoil | BEAUTY U & ME.SG (16), Strawberrynet SG (8), Nana Mall (4), HEY SUP (2), BB Beauty Global (2) |
| Grafen | Grafen Korea Official Store (21), MexxiMall (9), Satoshi Official (1) |
| MiseEnScene | AMOREPACIFIC Hair&Beauty Shop (14), cosblah (7), Younfamily (3), +4 more |
| Lucido-L | Guardian SG (13), Mandom Official Store (10), Strawberrynet SG (4), +2 more |
| Get | Xiaoling Boutique Store (9), Beauty Morning Makeup Boutique (7), +8 more |
| Dove | Unilever Official Store (16), Guardian SG (7), BIG Pharmacy (3), +2 more |
| Milbon | Nana Mall (11), HEY SUP (6), Strawberrynet SG (4), BEAUTY U & ME.SG (3), +2 more |
| Sunsilk | Unilever Official Store (19), BIG Pharmacy (6), myCK_online (2), Guardian SG (1) |
| Klorane | Klorane Official Flagship Store (15), Guardian SG (9), Strawberrynet SG (2), myCK_online (1) |
| COCO & EVE | Coco & Eve Official Store (26) |
| O'right | O'right Official Store (26) |
| Clear | Unilever Official Store (17), Guardian SG (5), Prestigio Delights Official (3) |
| MASIL | Younfamily (14), YAOCOS.kr (7), HEY SUP (2), +2 more |
| Alpecin | Dr. Wolff Official Store (22), BIG Pharmacy (1), Global Buyer (1) |
| Pilgrim | Pilgrim Official Store (24) |
| Julyme | Julyme Korea Official Store (23) |
| Oribe | Strawberrynet SG (22), BEAUTY U & ME.SG (1) |
| MUCOTA | Mucota Official Store (22) |
| Growus | Growus global store (20), iQueen Official Store (1) |

*(remaining ~118 brands with official stores have smaller volume; full per-brand breakdown in this session's
`/tmp/official_stores_filtered.csv`.)*

**⚠️ Undocumented multi-brand-store contamination (record, not silently fixed):** `llm-extraction-rules.md`
§4's beauty exclusion list names only 5 stores (Watsons, Boots, BEAUTRIUM, Sasa, Tsuruha). Live data shows at
least 77 additional Shopee-Mall-badged stores carrying >4 brands each that are almost certainly third-party
multi-brand marketplaces, not brand-owned — **Guardian SG Official Store (40 brands)**, **Strawberrynet SG
Official Store (27 brands)**, **Nana Mall Official Store (19 brands)**, **myCK_online (15 brands)**,
**Beautyhaus SG (14 brands)**, **HEY SUP (13 brands)**, **BEAUTY U & ME.SG Official Store (13 brands)**,
**BIG Pharmacy (9 brands)**, plus a long tail of tiny "boutique"/reseller accounts (Xiaoling Boutique Store,
Beauty Morning Makeup Boutique, YA YA Beauty Salon, MELEA, etc.) that appear across many unrelated brand_ids
including the generic-token brand buckets below. This session followed the literal, currently-documented
5-name exclusion list rather than unilaterally expanding it — but this is a real gap worth adding to
`llm-extraction-rules.md` §4 in a follow-up.

**⚠️ Generic-token brand_dict contamination:** `Hair+`, `Care`, `All`, `Get`, `Neo Hair` are brand_dict
entries that appear to be catching unrelated small resellers via generic English-word `PRODUCT_NAME_SCAN`
matches (e.g. "Hair+" matched across 63 different tiny boutique stores selling completely unrelated
hair-loss tonics, TCM products, and miscellaneous items with no coherent single-brand identity). Per
`docs/llm-extraction-rules.md` §7, brand_mismatch is flagged not auto-corrected during extraction — this is
noted here for QA follow-up, not fixed in this run.

**Brands with no official store (Pass 2 only):** ~68 of the 231 in-scope brands have no qualifying Mall store.

---

## Scale — Key Numbers (June 2026, this session)

| Metric | Count | Notes |
|--------|-------|-------|
| Distinct products (Jun 2026) | 38,841 | Product-level grain |
| Total rows (Jun 2026) | 77,947 | Product × model rows at review month |
| All Mall-badged rows (unfiltered) | 9,219 | Before allowlist scoping — **Pass 1 must not use this pool directly** |
| Official-store allowlist products | 3,168 | Products from the 217-merchant, 231-brand-scoped allowlist (Sasa/Watsons excluded) |
| Existing HUMAN map rows | 2,187 | Confirmed live 2026-07-23, from prior keyword seed scripts; 0 LLM rows exist |
| June row count vs other months | 77,947 (Jun) vs 143,911 (May) vs 142,529 (Apr) | June is ~half of May/April — likely a still-filling recent month (session date 2026-07-23, only ~7 weeks after June closed), not a data-quality problem. April's GMV ($7.48M) is the outlier month, not June ($2.86M, which tracks March/May's $2.5–2.7M band) — June is a representative scope month. |

**Official store scale note:** 3,168 is tractable for a mostly-real, per-line-classified vision-extraction pass
within one session, unlike the 187,902-row pool that caused `shopee_sg_shampoo` attempt #1 to block on scale.

---

## Scope — What's In vs Out

**In scope:**
- Hair conditioner (conditioner spray, leave-in conditioner, rinse-out conditioner)
- Hair treatment/mask (hair repair mask, hot oil treatment, protein treatment, damage-repair treatment)
- Hair essence/serum/oil — only when clearly marketed as a conditioning/repair line, not styling or anti-hair-loss

**Out of scope (leave NULL):**
- Shampoo — separate category, even if same brand or same listing photo style (confirmed live: the very first
  sampled product image from this table, "Alpecin Caffeine Shampoo 3x250ml", is a shampoo despite appearing in
  this conditioner/treatment source table)
- **Hair-loss / hair-growth pharmaceuticals and supplements** — Minoxidil (REGAINE, groWell, Regro), oral hair
  growth supplements/tablets (Miriqa, Nourkrin, Viviscal), anti-hair-loss tonics/serums marketed primarily on
  hair growth or hair loss claims (Dr.ville, Seapuri, ATHALIA, Fayre Beauty, Dr.FORHAIR), fiber concealers
  (Toppik), laser growth devices (iRestore) — **this is the single largest contamination risk in this
  category's top-GMV brand list**, confirmed via direct sku_name text of the top 25 GMV products
- Hair styling products (gel, wax, spray)
- Hair color/dye products
- Hair washing/cleansing tools, brushes
- Multi-category bundles where conditioner/treatment is not the primary product

**Edge cases:**
- **Kérastase / Milbon / professional salon lines** — include all regardless of sub-line; genuinely
  conditioner-treatment focused as a brand (Kérastase's own top sellers are Fortifiant serum, Gloss Absolu
  anti-frizz oil — both in-scope treatment products, confirmed by image in this session).
- **"Hair Growth Serum"/"Hair Tonic"/"Scalp Treatment" phrasing** — default OUT unless the product image and
  full description clearly market it as a conditioning/repair treatment rather than an anti-hair-loss claim.
  When ambiguous, read the image; "hair growth", "hair loss", "anti-loss", "stimulate regrowth", "minoxidil"
  in the title are strong OUT signals even if "treatment" also appears in the title.
- **Oil-based / serum-based treatments** — include if positioned as conditioning/repair (UNOVE Silk Oil
  Essence, d'Alba Repairing Hair Perfume Serum); exclude if positioned as growth/loss.
- **Leave-in sprays** — include if labeled conditioner/detangler spray; exclude if styling-hold spray.

---

## Taxonomy Design Notes

**Product line extraction approach:**
- Extract product_line directly from packaging/title text, real on-label line name (e.g. Kérastase "Genesis
  Fortifiant", "Gloss Absolu"; UNOVE "Deep Damage Treatment Ex").
- Populate `product_line` as close to mandatory whenever a real line name exists (not just folding it into
  `canonical_name` as free text) — this exact defect (934 entries shipped with `product_line` NULL on 100% of
  them) was previously found in another SG category and is a named regression risk in this session's own
  instructions.
- `sub_line`/`variant`: only when a real signal exists (flavor/scent/formula variant); leave NULL otherwise.

**Size / pack-count:** standard priority chains from `llm-extraction-rules.md` §1/§2 — size: text → image →
spec → description (text wins on conflict); pack_count: text → image → spec → description (image wins on
conflict).

**Known difficult products:**
- Generic-token brand contamination (Hair+, Care, All, Get, Neo Hair) — see finding above; use image +
  sku_name to classify actual product identity regardless of the (likely wrong) brand_dict bucket.
- BRD-UNDEFINED reseller listings — brand extraction from sku_name/image required per product.
- Multi-size seller listings — use image to determine actual size or mark `is_multi_size=TRUE`.

---

## Existing Map Rows

**2,187 HUMAN source rows**, 0 LLM rows (verified live 2026-07-23). Per policy confirmed 2026-07-16: HUMAN
rows are deleted only where they duplicate a product that also gets an LLM row from this rebuild — never a
blanket delete. This is a wrapper-side step after this session's JSON output, not performed by this session.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-16 | Pre-build | Apr-2026 scope research (115 brands, 100 official stores) — superseded | Zero rows written that session |
| 2026-07-23 | Pre-build | Re-verified live: 0 LLM rows, 2,187 HUMAN rows. Real Jun-2026 95% GWP-zeroed brand scope = 231 brands (bq CLI `--max_rows` default of 100 silently truncated the naive query to 84% cumulative — caught before it caused an undercount). Official-store allowlist = 3,168 products / 217 merchants / 163 brands, Sasa+Watsons excluded. **Found the category's top-GMV brands are ~60% hair-loss/growth pharma, not conditioner/treatment** (text-scan of top 25 products by GMV) — taxonomy must be built per product line, not per brand. | Category file rewritten with real Jun-2026 data; proceeding to SKU claim + per-line extraction |
| 2026-07-23 | Top-up coverage (same day, later session) | A Full Rebuild had already completed between the prior QA History row and this session (2,239 LLM rows existed live, block SKU-124556–126555 + supplemental SKU-128556–129555, MAX=SKU-129286) — this file's Status/SKU-block sections were stale (still said "In progress" / listed a different block) but the wrapper's "top-up" framing was correct once verified against live BQ state, not this file. Live worklist re-query (95%-cumulative-GMV, GWP-zeroed, Jun 2026) found 1,890 rows / 1,318 distinct products still `taxonomy_id IS NULL`. Per-product scope classification against this file's Scope section (text-first, bulk-grouped, escalating to individual judgment only where text was ambiguous — no images read) found **951 of 1,318 products (72%) are out-of-scope** — overwhelmingly hair-loss/growth pharma, scalp-only tonics/serums, shampoo, styling/dye, and chemical straightening systems (e.g. PURC Brazilian Keratin Straightening, Fiole Neo Process) that share this category's source table and brand list but aren't conditioner/treatment, exactly the contamination pattern the Jul-23 pre-build session already flagged. 367 products were in-scope: 183 bulk-matched to existing taxonomy entries by brand + distinctive-token text overlap; 182 had no match and were minted into 179 new entries (2 groups of near-duplicate reseller listings shared one entry each) using claimed block SKU-131756–133645 (used 131756–131934, 1,761 slots returned unused). Remaining worklist gap after this session: 1,343 rows (the OOS majority, correctly left NULL) — not a shortfall, per this category's documented brand-list contamination. | Inserted 179 `product_taxonomy` rows + 365 `product_taxonomy_map` LLM rows (meta_agent=CLAUDE_CODE). G1 (dual-map) and G5 (provenance) pass at 0. **G2 (HUMAN+LLM coexistence) = 868 and a placeholder-leak check = 1,741 both pre-date this session and involve zero of the 365 rows just written** (verified by joining each gate's failing set against the new taxonomy_id range) — the placeholder-leak is entirely one pre-existing legacy entry, `SKU-003050 "ANTI Hair Conditioner / Treatment (all variants)"`, mapped via HUMAN source to 1,741 products; its ID range (003xxx) is outside every block ever assigned to this category, so it's a cross-category keyword-seed artifact predating Phase 5. Left untouched — a targeted_qa_fix.sh scope, not a coverage top-up's. |
| 2026-07-23 | Top-up coverage (same day, third session — wrapper prompt repeated the identical "1343 unmapped" premise verbatim) | Wrapper's live pre-check (1,343) matched the row count this same-day prior session had *already investigated and deliberately left NULL* (commit `37a30c0`) — re-verified live via the wrapper's own STEP 0 query (1,343 rows / 953 distinct products, i.e. no drift since the prior session). Rather than treat the repeated premise as a new gap to force-close, classified the live remainder itself: keyword+brand hard-OOS filter (hair-loss/growth pharma brand list, shampoo/dye/styling/straightening/supplement tokens) dropped 798 rows; of the remaining 545, cross-referencing sku_name text against the source table's structured `product_specs` "Hair Care Benefits" attribute (not used by the prior text-only session) isolated 142 with a genuine conditioning/repair signal and no anti-loss/growth benefit tag; excluding 8 scalp-itch-relief/dermatological items (Suu Balm, Kao Curel Scalp Lotion, Monnali) and 1 physical scalp scrub (SABON) — neither is hair conditioner/treatment per this file's Scope section — left **134 genuinely in-scope stragglers the prior text-only pass missed** (repair oils, hair masks, leave-in sprays, bonding treatments across 64 brands), plus 24 benefit-tag-ambiguous and 379 default-OUT (scalp tonic/serum phrasing per this file's own edge-case rule) left unresolved this session, pending image verification — a real, smaller residual, not the 1,343. Of the 134: 20 rows (11 products) matched existing taxonomy entries on exact brand+line+size+form fingerprint (e.g. Milbon Global Replenishing Treatment 500g, Tsubaki Premium Water 210ml); 113 rows (88 products) had no safe match and were minted into 86 new entries, one per distinct product line/size (e.g. UNOVE Frizz-Calming Glass Hair Oil 70ml, MadeToBloom Restorative Hair Oil) — several near-matches were deliberately rejected as mints instead of forced onto existing SKUs where size/pack/form genuinely differed (e.g. Pantene 40ml Miracle Serum ≠ existing "Bundle Of 3 ...300ml x3" Conditioner; Dove single 220g Mask ≠ existing "Bundle Of 2 ...265g x2"). 3 of the 86 mints carry `brand_mismatch=TRUE` (Mimosa Professional product wrongly pre-tagged to the generic-token "Hair+" brand bucket this file already flagged as contaminated; Davines OI product tagged "All"; an unbranded "Vspa...L'oreal HairSpa Replacement" tagged "Deep") — corrected to the real brand or `BRD-UNDEFINED` rather than bulk-mapped under the wrong brand_id. Claimed a 100-slot block (SKU-134046–134145, used 134046–134131, 14 slots unused) — not 1,343 — sized to the actual mint count, per this session's explicit instruction not to claim the full worklist size reflexively. Post-write live worklist re-query: 1,210 rows / 854 distinct products still `taxonomy_id IS NULL` (down from 1,343/953) — the residual is dominated by the 379 default-OUT scalp-tonic/serum items and the pre-existing OOS majority documented in the prior session's row, plus the 24 ambiguous items awaiting image verification; not re-litigated or force-mapped this session. | Inserted 86 `product_taxonomy` rows + 99 `product_taxonomy_map` LLM rows (meta_agent=CLAUDE_CODE, confidence=0.7). **G1 (dual-mapped LLM) = 0.** **G2 (HUMAN+LLM coexistence) = 868 and placeholder-leak = 1,741 — identical counts to the prior session's row, reverified to involve zero of this session's 99 product_ids** (joined each gate's failing set against this session's product_id list directly) — both are the same pre-existing `SKU-003050` legacy artifact, untouched here, a targeted_qa_fix.sh scope. **structured_fields_missing_pct (product_line NULL) = 0%** — every new entry's product_line was populated at write time. |

---

## Scripts

| Script | Purpose | Status |
|--------|---------|--------|
| This rebuild (headless Full Rebuild, Claude Code direct multimodal extraction) | Pass 1 + Pass 2, per-product-line scope classification | In progress |
