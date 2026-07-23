# shopee_sg_hand_and_body_moisturiser — Category Context

> First-run category. Created during headless Full Rebuild session, month 2026-06.

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ⏳ In progress (this session) |
| LLM Pass 2 | ⏳ In progress (this session) |
| GMV Coverage | TBD — see QA History after this run |
| Last run | 2026-07-23 |
| Current MAX taxonomy_id | Queried live at claim time — see SKU Blocks Assigned |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| (filled in after Step 3 atomic claim) | Full Rebuild — Pass 1 OFFICIAL + Pass 2 RESELLER |

---

## Brand Scope (GMV threshold 95%, GWP-zeroed, month 2026-06)

161 brands in scope out of the full brand universe selling in this category (real cumulative-GMV
95% threshold — NOT a fixed top-N snapshot; computed via `SUM(CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END)`
per product, joined to `product_brand_map`, summed per brand, ranked desc, cumulative fraction.
Total in-scope brand GMV: ~SGD 753,427 (month 2026-06-01).

| # | Brand | brand_id | GMV (SGD) | Official store (Pass 1) |
|---|---|---|---|---|
| 1 | Suu Balm | BRD-SG-00424 | 74,941.7 | *none — Pass 2 only* |
| 2 | QV | BRD-SG-00660 | 54,937.4 | QV Official Store |
| 3 | Jolicare | BRD-SG-00727 | 53,289.6 | Jolicare™ Official Store |
| 4 | Cetaphil | BRD-GLOBAL-00069 | 48,894.6 | Cetaphil Official Store |
| 5 | Bioderma | BRD-GLOBAL-00062 | 48,217.4 | Bioderma Official Store |
| 6 | Undefined | BRD-UNDEFINED | 40,042.4 | *n/a — reserved bucket, no Pass 1 concept, see note below* |
| 7 | Nivea | BRD-GLOBAL-00023 | 26,370.6 | Nivea Official Store |
| 8 | Ceradan | BRD-SG-00860 | 23,992.0 | Ceradan SG Official Store |
| 9 | Aveeno | BRD-GLOBAL-00265 | 23,661.4 | Kenvue Official Store |
| 10 | Vaseline | BRD-GLOBAL-00019 | 22,799.2 | Unilever Official Store |
| 11 | Cerave | BRD-GLOBAL-00006 | 17,409.3 | Supple Beauty |
| 12 | GLAD2GLOW | BRD-GLOBAL-03244 | 16,162.7 | Glad2Glow OFFICIAL STORE |
| 13 | L'Occitane | BRD-GLOBAL-00240 | 16,162.0 | L’Occitane Official Store |
| 14 | Eucerin | BRD-GLOBAL-00003 | 14,163.3 | EUCERIN Official Store |
| 15 | Vytle | BRD-SG-02244 | 10,833.9 | Vytle Official Store |
| 16 | Physiogel | BRD-GLOBAL-00124 | 10,312.8 | Physiogel  Official  Store |
| 17 | Illiyoon | BRD-GLOBAL-00796 | 9,298.4 | AMOREPACIFIC Hair&Beauty Shop |
| 18 | Paula's Choice | BRD-GLOBAL-00251 | 7,939.5 | Paula’s Choice Official Store |
| 19 | Aestura | BRD-GLOBAL-00235 | 7,762.7 | AMOREPACIFIC Official Store |
| 20 | NARD | BRD-GLOBAL-00703 | 7,617.3 | Nard Store |
| 21 | Clarins | BRD-GLOBAL-00242 | 7,457.4 | *none — Pass 2 only* |
| 22 | Rejuran | BRD-GLOBAL-00335 | 6,799.0 | Rejuran Official Store |
| 23 | Derma Lab | BRD-GLOBAL-01449 | 6,287.9 | *none — Pass 2 only* |
| 24 | Dermal Therapy | BRD-SG-02595 | 6,147.2 | Dermal Therapy Official Store; Pharmacy Express Official Store |
| 25 | ICM Pharma | BRD-SG-00833 | 6,084.8 | *none — Pass 2 only* |
| 26 | La Roche-Posay | BRD-GLOBAL-00002 | 5,940.1 | La Roche Posay Official Store |
| 27 | Alluora | BRD-SG-00567 | 5,400.9 | Alluora |
| 28 | Lydimoon | BRD-SG-00884 | 5,082.5 | *none — Pass 2 only* |
| 29 | Horse Oil | BRD-SG-05969 | 4,742.3 | *none — Pass 2 only* |
| 30 | All | BRD-SG-06567 | 4,646.2 | *none — Pass 2 only* |
| 31 | The Body Shop | BRD-GLOBAL-01534 | 4,547.8 | The Body Shop Official Store |
| 32 | Elizabeth Arden | BRD-GLOBAL-01349 | 3,829.6 | Elizabeth Arden Official Store |
| 33 | HAN.d | BRD-SG-11191 | 3,806.8 | P&Q Pharmacy Official; SCENZ; YA YA Beauty  Salon; helinyue.sg |
| 34 | Hada Labo | BRD-GLOBAL-00055 | 3,574.5 | Mentholatum Flagship Store |
| 35 | Bouquet Garni | BRD-GLOBAL-01453 | 3,505.8 | Bouquet Garni Official Store |
| 36 | Hatomugi | BRD-GLOBAL-00797 | 3,368.5 | *none — Pass 2 only* |
| 37 | Jergens | BRD-GLOBAL-00134 | 3,275.1 | Kao Official Store |
| 38 | Origins | BRD-GLOBAL-00616 | 3,184.1 | *none — Pass 2 only* |
| 39 | DR JUNGLE | BRD-SG-03444 | 3,126.7 | DR JUNGLE |
| 40 | Care | BRD-GLOBAL-00623 | 3,020.0 | Lashpire Official; UIQ Korea; X.Asian Store.sg |
| 41 | Rosken | BRD-SG-03149 | 3,012.6 | Nature's Way Offical Store |
| 42 | Innisfree | BRD-GLOBAL-00070 | 2,926.8 | Innisfree Official Store |
| 43 | Eau Thermale Avène | BRD-SG-01081 | 2,882.9 | Eau Thermale Avene Official Flagship Store |
| 44 | Cuccio | BRD-SG-02314 | 2,767.1 | *none — Pass 2 only* |
| 45 | PALMER'S | BRD-GLOBAL-00432 | 2,559.2 | Palmer's Singapore Official Store |
| 46 | Hetras | BRD-SG-00312 | 2,534.7 | *none — Pass 2 only* |
| 47 | Theo10 | BRD-SG-01755 | 2,472.6 | Theo10sg Official Store |
| 48 | Sebamed | BRD-GLOBAL-00142 | 2,406.6 | JAWStore - Puritan's Pride; sebamed Official Store |
| 49 | Gold Bond | BRD-SG-04143 | 2,322.9 | *none — Pass 2 only* |
| 50 | eos | BRD-SG-01477 | 2,318.5 | *none — Pass 2 only* |
| 51 | Amlactin | BRD-SG-01196 | 2,229.3 | *none — Pass 2 only* |
| 52 | Gmeelan | BRD-GLOBAL-00550 | 2,222.0 | *none — Pass 2 only* |
| 53 | APLB | BRD-GLOBAL-01196 | 1,938.0 | *none — Pass 2 only* |
| 54 | Fast | BRD-SG-04063 | 1,918.4 | *none — Pass 2 only* |
| 55 | TRUU | BRD-SG-00875 | 1,878.2 | TRUU 童 Official Store |
| 56 | C&C | BRD-SG-08080 | 1,866.0 | *none — Pass 2 only* |
| 57 | Biore | BRD-GLOBAL-00061 | 1,703.4 | Kao Official Store |
| 58 | Melalueca | BRD-SG-02385 | 1,668.2 | *none — Pass 2 only* |
| 59 | Neutrogena | BRD-GLOBAL-00080 | 1,593.0 | Kenvue Official Store |
| 60 | Advanced clinicals | BRD-GLOBAL-02127 | 1,581.1 | *none — Pass 2 only* |
| 61 | Vanicream | BRD-SG-02262 | 1,579.8 | *none — Pass 2 only* |
| 62 | Bio Essence | BRD-GLOBAL-00754 | 1,466.5 | Ebene Official Store |
| 63 | IN | BRD-SG-06662 | 1,461.2 | *none — Pass 2 only* |
| 64 | White Conc | BRD-GLOBAL-01401 | 1,459.2 | *none — Pass 2 only* |
| 65 | SunoHada | BRD-SG-02944 | 1,423.0 | *none — Pass 2 only* |
| 66 | Uriage | BRD-GLOBAL-01644 | 1,417.7 | Uriage Official Store |
| 67 | Dr.ville | BRD-GLOBAL-00875 | 1,370.1 | BUV·DR |
| 68 | Lishan | BRD-GLOBAL-02476 | 1,368.5 | *none — Pass 2 only* |
| 69 | Kao Curel | BRD-SG-03058 | 1,321.0 | *none — Pass 2 only* |
| 70 | YTNING | BRD-SG-03642 | 1,275.6 | *none — Pass 2 only* |
| 71 | Koelf | BRD-SG-04075 | 1,268.9 | *none — Pass 2 only* |
| 72 | Curel | BRD-GLOBAL-00199 | 1,262.9 | Kao Beauty Official Store; Kao Official Store |
| 73 | Noreva | BRD-SG-03086 | 1,255.2 | Noreva Official Store |
| 74 | Pyunkang Yul | BRD-GLOBAL-01252 | 1,227.4 | PyunkangYul Official Store |
| 75 | Emporal Co | BRD-SG-04454 | 1,210.3 | *none — Pass 2 only* |
| 76 | Soap & Glory | BRD-GLOBAL-00412 | 1,204.0 | *none — Pass 2 only* |
| 77 | Mediheal | BRD-GLOBAL-00361 | 1,202.0 | Mediheal Singapore Official Store |
| 78 | Cosrx | BRD-GLOBAL-00109 | 1,180.4 | COSRX Official Store |
| 79 | Sadoer | BRD-GLOBAL-00488 | 1,179.9 | Ustar Beauty |
| 80 | Kiehl's | BRD-GLOBAL-00084 | 1,175.5 | Kiehl's Official Store |
| 81 | Ego QV | BRD-TH-01734 | 1,169.6 | *none — Pass 2 only* |
| 82 | Ongredients | BRD-GLOBAL-01884 | 1,160.3 | *none — Pass 2 only* |
| 83 | Topicrem | BRD-SG-03251 | 1,140.6 | Topicrem Official |
| 84 | Zeroid | BRD-GLOBAL-00498 | 1,128.6 | *none — Pass 2 only* |
| 85 | A Bonne | BRD-GLOBAL-00939 | 1,121.0 | *none — Pass 2 only* |
| 86 | SOME BY MI | BRD-GLOBAL-00605 | 1,069.3 | SOMEBYMI SG Official Store |
| 87 | &Honey | BRD-GLOBAL-00237 | 1,043.8 | Amagogo; Sunnimix; 幸福角落 x2 |
| 88 | Snowhitee | BRD-SG-07784 | 1,043.2 | *none — Pass 2 only* |
| 89 | W.DRESSROOM | BRD-SG-02940 | 1,020.5 | *none — Pass 2 only* |
| 90 | Perspirex | BRD-SG-03857 | 1,019.6 | Perspirex Singapore Official |
| 91 | Precious Skin | BRD-GLOBAL-01520 | 993.8 | *none — Pass 2 only* |
| 92 | Naturie | BRD-SG-01478 | 981.9 | *none — Pass 2 only* |
| 93 | Ego Pharmaceuticals | BRD-SG-03690 | 950.3 | *none — Pass 2 only* |
| 94 | Foreo | BRD-GLOBAL-00052 | 937.0 | *none — Pass 2 only* |
| 95 | Niks | BRD-SG-02218 | 933.0 | *none — Pass 2 only* |
| 96 | sukin | BRD-SG-00948 | 887.4 | *none — Pass 2 only* |
| 97 | FANCL | BRD-GLOBAL-00856 | 866.6 | *none — Pass 2 only* |
| 98 | SVR | BRD-GLOBAL-01279 | 860.4 | *none — Pass 2 only* |
| 99 | SKINEVER | BRD-GLOBAL-02393 | 801.7 | SKINEVER Global Store |
| 100 | Kose | BRD-GLOBAL-00014 | 800.3 | Kosé Official Store |
| 101 | Jo Malone | BRD-GLOBAL-02153 | 786.1 | *none — Pass 2 only* |
| 102 | D'ARK | BRD-SG-12623 | 779.4 | fixory; momshinshop8i.sg |
| 103 | TENA | BRD-SG-08380 | 755.5 | Dr P & TENA  |
| 104 | Luxe Organix | BRD-SG-04757 | 750.8 | *none — Pass 2 only* |
| 105 | Clinique | BRD-GLOBAL-00171 | 749.8 | *none — Pass 2 only* |
| 106 | The Lab By Blanc Doux | BRD-GLOBAL-01755 | 742.5 | *none — Pass 2 only* |
| 107 | Sabon | BRD-GLOBAL-02007 | 734.2 | *none — Pass 2 only* |
| 108 | Hustle Butter | BRD-SG-04395 | 726.0 | *none — Pass 2 only* |
| 109 | Shiseido | BRD-GLOBAL-00072 | 686.7 | *none — Pass 2 only* |
| 110 | NATURIUM | BRD-SG-02310 | 681.5 | *none — Pass 2 only* |
| 111 | Gloves In A Bottle | BRD-SG-04243 | 681.2 | *none — Pass 2 only* |
| 112 | Florasis | BRD-GLOBAL-01540 | 654.0 | 花西子 Florasis Official Store |
| 113 | The Face Shop | BRD-GLOBAL-00275 | 650.6 | THEFACESHOP VIỆT NAM |
| 114 | Fine today | BRD-SG-09800 | 636.0 | *none — Pass 2 only* |
| 115 | Clé de peau beaute | BRD-GLOBAL-00482 | 631.0 | *none — Pass 2 only* |
| 116 | OBgE | BRD-GLOBAL-00440 | 621.0 | FOODOLOGY Official Store; OBgE Official Store |
| 117 | Lanate | BRD-SG-04369 | 620.2 | *none — Pass 2 only* |
| 118 | Jurlique | BRD-GLOBAL-01109 | 618.8 | *none — Pass 2 only* |
| 119 | Pigeon | BRD-GLOBAL-00381 | 605.9 | Pigeon Official Store |
| 120 | Medi Flower | BRD-GLOBAL-02514 | 594.2 | MEDIFLOWER KOREA OFFICIAL STORE |
| 121 | DR.WU | BRD-SG-01654 | 590.9 | Dr Wu SG Official Store |
| 122 | Elixir | BRD-GLOBAL-00106 | 589.4 | *none — Pass 2 only* |
| 123 | Bioglo | BRD-GLOBAL-03585 | 577.1 | *none — Pass 2 only* |
| 124 | olay | BRD-GLOBAL-00075 | 576.5 |  junhe.sg; Oral Oasis; yougo.sg |
| 125 | Schulke | BRD-SG-02064 | 574.4 | *none — Pass 2 only* |
| 126 | Forever Living | BRD-SG-02754 | 573.4 | *none — Pass 2 only* |
| 127 | Careso | BRD-SG-04873 | 568.2 | *none — Pass 2 only* |
| 128 | Beauty Buffet | BRD-GLOBAL-00732 | 558.3 | *none — Pass 2 only* |
| 129 | Nuskin | BRD-GLOBAL-00872 | 556.5 | *none — Pass 2 only* |
| 130 | Moogoo | BRD-SG-03456 | 549.2 | Posh Baby Shop Official Store |
| 131 | Rosee | BRD-TH-01122 | 536.1 | *none — Pass 2 only* |
| 132 | Muji | BRD-GLOBAL-02059 | 533.4 | MUJI Official Store |
| 133 | Beyond | BRD-GLOBAL-00208 | 532.4 | BEYOND Official Store |
| 134 | Nutseline | BRD-GLOBAL-02796 | 511.7 | nutseline_officialstore |
| 135 | Beyond Belief | BRD-GLOBAL-02515 | 510.1 | *none — Pass 2 only* |
| 136 | Aesop | BRD-GLOBAL-01368 | 509.1 | *none — Pass 2 only* |
| 137 | Magika | BRD-SG-10004 | 507.0 | *none — Pass 2 only* |
| 138 | Sol De Janeiro | BRD-GLOBAL-01645 | 504.5 | *none — Pass 2 only* |
| 139 | JARDIN | BRD-SG-03203 | 499.5 | *none — Pass 2 only* |
| 140 | Dr.Melaxin | BRD-GLOBAL-00962 | 499.2 | Dr.Melaxin Singapore |
| 141 | KAZOO | BRD-SG-03369 | 497.9 | KAZOO Mall Store |
| 142 | Le Labo | BRD-SG-01469 | 488.1 | *none — Pass 2 only* |
| 143 | jennie moon | BRD-SG-02415 | 486.4 | *none — Pass 2 only* |
| 144 | hersteller | BRD-GLOBAL-02731 | 481.1 | *none — Pass 2 only* |
| 145 | AROMA | BRD-GLOBAL-00294 | 477.9 | *none — Pass 2 only* |
| 146 | Malin-Goetz | BRD-SG-04526 | 476.6 | *none — Pass 2 only* |
| 147 | BARUBT | BRD-SG-06454 | 470.1 | *none — Pass 2 only* |
| 148 | Derma:B | BRD-GLOBAL-00855 | 465.2 | MaysonBeauty; Real Barrier Official Store |
| 149 | St.Ives | BRD-GLOBAL-01334 | 462.3 | Unilever International |
| 150 | Comfort | BRD-GLOBAL-00086 | 460.4 | *none — Pass 2 only* |
| 151 | Chemist at Play | BRD-SG-11439 | 429.6 | Onesto Labs PTE. Ltd |
| 152 | Phiten | BRD-SG-04218 | 418.0 | *none — Pass 2 only* |
| 153 | Cathy Doll | BRD-GLOBAL-00131 | 414.1 | *none — Pass 2 only* |
| 154 | Clinical Radiance | BRD-SG-06184 | 412.2 | *none — Pass 2 only* |
| 155 | Caudalie | BRD-GLOBAL-00975 | 410.7 | *none — Pass 2 only* |
| 156 | Kojie.san | BRD-SG-02772 | 398.4 | *none — Pass 2 only* |
| 157 | Now | BRD-GLOBAL-00779 | 390.6 | *none — Pass 2 only* |
| 158 | Burns | BRD-SG-08055 | 389.0 | *none — Pass 2 only* |
| 159 | MUMCHIT | BRD-SG-03750 | 388.2 | *none — Pass 2 only* |
| 160 | A-DERMA | BRD-SG-03893 | 387.1 | A-DERMA Official Flagship Store |
| 161 | BioNike | BRD-SG-02733 | 385.8 | BioNike Official Store |

**Note on `BRD-UNDEFINED`:** included in the 95%-GMV brand-rank scope (SGD 40,042 GMV, rank 6) because Rule A
(top-95% cumulative GMV) is defined over all products regardless of resolved brand — but it has no Pass 1
"official store" concept (no brand to query an allowlist for). Products under `BRD-UNDEFINED` are Pass 2 only;
the LLM should read `brand_from_image` per product and, where the real brand is identifiable, route/create
under the correct brand rather than leaving a generic "Undefined" taxonomy entry (per
`docs/product-lifecycle.md` §4.1 — brand gate is hard, but the extraction step is exactly where a wrong Stage 03
`PRODUCT_NAME_SCAN`/`FALLBACK` brand gets corrected).

**Suspected generic-word brand mismatches — verify at extraction, don't trust `product_brand_map` blindly:**
`All` (BRD-SG-06567), `Care` (BRD-GLOBAL-00623), `Now` (BRD-GLOBAL-00779 — likely genuine "NOW Foods"), `Fast`
(BRD-SG-04063), `IN` (BRD-SG-06662), `AROMA` (BRD-GLOBAL-00294), `C&C` (BRD-SG-08080). These look like
`PRODUCT_NAME_SCAN` false positives on common English words. Read the product before minting/reusing a taxonomy
entry under these brand_ids — route to the real brand read off the image/title, or leave brand-ambiguous
products `UNRESOLVED` rather than building out a taxonomy for a literal generic word.

---

## Official Store Allowlist (Pass 1)

Built by: per-brand query of `merchant_name WHERE merchant_badge='Shopee Mall'` for each of the 161 in-scope
brands, then auto-classified — a merchant name is kept as brand-exclusive only if, across this table's entire
Mall-badged pool, it sells **exactly one** brand_id, or it matches a documented parent-company pattern. Any
merchant selling 2+ different scoped brands is excluded as a multi-brand retailer regardless of how
official-sounding its name is (Decision 14).

**76 of 161 brands have at least one qualifying store; 85 have none (Pass 2 only).**
Pass 1 candidate pool (Mall-badged rows at these 87 distinct allowlist merchant names, month 2026-06):
**904 rows / 609 distinct products.**

**Parent-company stores (Pass-1-eligible for every brand they carry, per `llm-extraction-rules.md` §4):**
- `Kao Official Store` / `Kao Beauty Official Store` → Biore, Jergens, Curel
- `Unilever Official Store` / `Unilever International` → Vaseline, St.Ives
- `Kenvue Official Store` → Aveeno, Neutrogena (J&J consumer-health spinoff)
- `AMOREPACIFIC Official Store` / `AMOREPACIFIC Hair&Beauty Shop` → Aestura, Illiyoon
- `Mentholatum Flagship Store` → Hada Labo (Rohto-Mentholatum)

**Multi-brand retailers excluded (confirmed via this table's data; expands `llm-extraction-rules.md` §4's
documented beauty list — Watsons, Boots, BEAUTRIUM, Sasa, Tsuruha — with SG-specific finds not yet in that
doc):** Guardian SG Official Store, Cosmede Official Store, Nana Mall Official Store, Beautyhaus SG,
BB Beauty Global Official Store, BEAUTY U & ME.SG Official Store, Strawberrynet SG Official Store, HEY SUP,
Farmasi C S, BIG Pharmacy, Ren Ren Pharmacy Official, Younfamily, Global Buyer, Xxiao.SG1.sg, myCK_online,
J-Mart Official, Neighbor Good Shopping Official, cosblah — plus a long tail of generic cross-border reseller
shopfronts (e.g. `qimugai111.sg`, `sumax.sg`, `wangruipeng01.sg`) that surfaced almost entirely under
`BRD-UNDEFINED`.

**Heuristic limitation (flag for human review, not blocking):** the "sells exactly 1 scoped brand → kept"
classifier can false-positive on a genuine multi-brand reseller that just happens to carry only one scoped
brand within *this specific category table* (e.g. `Supple Beauty` kept for CeraVe — plausible but unverified;
CeraVe has no obviously-named dedicated store in this data). Low-harm either way since the underlying products
are genuine stock of that brand regardless of the reseller's classification — but Pass 1 should not stamp these
with top-tier (0.95+) confidence; treat as ~0.85 (verified-brand, unverified-official-status).

---

## Scope — What's In vs Out

**In scope:**
- Body lotion, body cream, body butter, body milk, body serum (leave-on body moisturizers)
- Hand cream, hand lotion (leave-on hand moisturizers)
- Combined hand & body cream/lotion products

**Out of scope (leave NULL):**
- Standalone hand soap / liquid soap / hand wash / sanitizer with no leave-on cream or lotion component
  (small genuine contamination found in `category_3_EN = 'Hand Care'`, e.g. NESTI DANTE Liquid Soap, MUJI Hand
  Soap — these are wash products, not moisturizers, despite sharing the Hand Care NIQ bucket)
- Standalone body wash / shower gel / shower cream (separate category)
- Standalone foot-odor / antifungal treatment sprays with no moisturizing claim

**Edge cases:**
- **Multi-option "wash + lotion + cream" bundle listings** (common pattern here, e.g. QV, Ego QV, Aveeno,
  CeraVe, L'Occitane, Soap & Glory, EOS — one `product_id` where the buyer selects from a dropdown that
  includes both a wash SKU and a lotion/cream SKU): the listing as a whole is IN SCOPE for its lotion/cream
  options. Do not force a taxonomy match for the wash-only option into a moisturizer entry — per
  `docs/product-lifecycle.md`'s option-list authority rule, read the `option_name` list; if the specific model
  the GMV is attributed to is a wash-only variant, that portion is out of type (TYPE GATE, §4.2 step 3) even
  though the parent listing is in-scope.
- **`BRD-UNDEFINED` products**: still must be read and either routed to a real brand (correcting Stage 03) or
  left `UNRESOLVED` — never given a generic "Undefined Lotion" taxonomy stub (per D1's Tier-C ban).

---

## Taxonomy Design Notes

**Product line extraction approach:**
- Most sellers use bundle-style titles listing multiple size/pack options (e.g. "QV Gentle Wash 1.25kg | QV
  Intense Cream 500g | QV Lotion 1.25L") — the true line/size/pack for a given `product_id` is often only
  resolvable via the `option_name` column, not `sku_name` alone. Check `option_name`/`option_name_EN` before
  falling back to image reads.
- Parent-company official stores (Kao, Unilever, Kenvue, Amorepacific, Mentholatum) carry multiple brands —
  disambiguate via `brand_from_image`, do not assume the store's brand.

**Size extraction notes:**
- Primary unit: ml / g / L / kg — same priority chain as `llm-extraction-rules.md` §2 (text → image → spec →
  description).
- Bundle/multi-size listings ("Gentle Wash 1.25kg | Cream 500g | Lotion 1.25L") are seller-side option
  selectors, not multipacks — resolve to the specific option's size, do not multiply.

**Known difficult products:**
- To be filled in during extraction as specific hard cases are found.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-23 | Category research | 161 brands in real 95% GMV scope (GWP-zeroed); 1,714 pre-existing HUMAN rows, 0 LLM rows confirmed live | Category file authored; proceeding to Full Rebuild Pass 1+2 |

---

## Map Row Counts (as of session start, 2026-07-23)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 0 | First run |
| HUMAN | 1,714 | Pre-existing keyword-seed rows, retained (not deleted this session) |
| NULL (unmapped) | ~29,361 of 31,075 distinct products (month 2026-06) | To be reduced by this session's Pass 1 + Pass 2 |
