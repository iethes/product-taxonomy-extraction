# shopee_sg_coffee — Category Context

> First LLM Full Rebuild session. Generated headless 2026-07-20, review month 2026-06.

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ⏳ In progress (this session) |
| LLM Pass 2 | ⏳ In progress (this session) |
| GMV Coverage | TBD — measured after this session's writes |
| Last run | 2026-07-20 |
| Current MAX taxonomy_id | Query BQ live before first insert — see Step 3, never trust this file |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| TBD — claimed atomically in Step 3 (this session), 2,000-slot block | Pass 1 OFFICIAL + Pass 2 RESELLER |

---

## Brand Scope (GMV threshold 95%, month 2026-06-01)

Computed as: per-product GWP-zeroed GMV (`CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END`), rolled up to
canonical brand via `product_brand_map` → `brand_dict` (not the raw, inconsistently-cased `brand` text
column), ranked descending, cumulative GMV ≤ 95% of category total. `shopee_sg_coffee` is a clean
single-category source table (`category_3_EN = 'Coffee'` for 100% of June rows) — no keyword pre-filter
needed before the brand ranking.

**96 brands** are in scope (cumulative GMV reaches 94.96% at rank 96; rank 97 crosses to 95.07%). This is
a real threshold count, not a fixed top-N snapshot — do not truncate it.

1. Nescafe — `BRD-SG-00009` — SGD 157,734 (12.03% cum.)
2. Starbucks — `BRD-GLOBAL-00146` — SGD 102,046 (19.81%)
3. Zero Coffee — `BRD-GLOBAL-01176` — SGD 57,865 (24.22%)
4. COWPRESSO COFFEE ROASTERS — `BRD-SG-01146` — SGD 53,484 (32.49%, includes prior-rank "Undefined"/unmapped GMV bucket at 28.41%)
5. Old Town — `BRD-SG-00492` — SGD 46,617 (36.05%)
6. ILLY — `BRD-SG-00331` — SGD 43,796 (39.39%)
7. Milo — `BRD-GLOBAL-00183` — SGD 36,615 (42.18%)
8. Lavazza — `BRD-SG-00367` — SGD 36,022 (44.92%)
9. Oriental — `BRD-SG-01150` — SGD 35,349 (47.62%)
10. L'OR — `BRD-SG-00468` — SGD 27,539 (49.72%)
11. Oriental White Coffee — `BRD-SG-03713` — SGD 27,323 (51.80%)
12. Kopi — `BRD-SG-00737` — SGD 19,281 (53.27%)
13. Moccona — `BRD-GLOBAL-00088` — SGD 19,252 (54.74%)
14. UCC Coffee — `BRD-SG-01673` — SGD 17,854 (56.10%)
15. Gold Kili — `BRD-SG-01598` — SGD 17,213 (57.41%)
16. maxime — `BRD-GLOBAL-00224` — SGD 16,653 (58.68%)
17. OWL — `BRD-SG-01534` — SGD 15,430 (59.86%)
18. Suzuki Coffee — `BRD-SG-00459` — SGD 14,564 (62.11%)
19. Aik Cheong — `BRD-SG-01880` — SGD 14,211 (63.20%)
20. G7 — `BRD-GLOBAL-00734` — SGD 13,763 (64.25%)
21. Chek Hup — `BRD-SG-01879` — SGD 12,580 (65.21%)
22. Fortune Coffee Club — `BRD-SG-02149` — SGD 12,469 (66.16%)
23. Coffeehock — `BRD-SG-01744` — SGD 12,469 (67.11%)
24. Encik Guan — `BRD-SG-02040` — SGD 12,117 (68.03%)
25. Cheerful Goat — `BRD-SG-02200` — SGD 11,348 (68.90%)
26. Killiney — `BRD-SG-01452` — SGD 10,866 (69.72%)
27. PARCHMEN & CO. — `BRD-SG-02510` — SGD 10,445 (70.52%)
28. TAG Espresso — `BRD-SG-02087` — SGD 10,293 (71.31%)
29. Nespresso — `BRD-SG-00179` — SGD 10,094 (72.08%)
30. Arabica — `BRD-SG-09596` — SGD 9,964 (72.84%)
31. REDMAN — `BRD-SG-02082` — SGD 9,940 (73.59%)
32. TRUNG NGUYEN — `BRD-SG-01292` — SGD 9,565 (74.32%)
33. POKKA — `BRD-GLOBAL-00722` — SGD 9,419 (75.04%)
34. Gold Beverage — `BRD-SG-02367` — SGD 9,170 (75.74%)
35. Cafe Specialists — `BRD-SG-02239` — SGD 9,158 (76.44%)
36. Toast Box — `BRD-SG-02055` — SGD 8,991 (77.12%)
37. Kim's Duet — `BRD-SG-01620` — SGD 8,934 (77.80%)
38. TNI King Coffee — `BRD-SG-03035` — SGD 8,902 (78.48%)
39. Kanu — `BRD-SG-01424` — SGD 8,705 (79.15%)
40. Mövenpick — `BRD-SG-00753` — SGD 7,775 (79.74%)
41. Bacha Coffee — `BRD-SG-02411` — SGD 7,300 (80.30%)
42. Modern Hippi — `BRD-SG-02506` — SGD 7,182 (80.84%)
43. luckin coffee — `BRD-GLOBAL-02085` — SGD 6,664 (81.35%)
44. Indocafe — `BRD-SG-00471` — SGD 6,643 (81.86%)
45. Chang — `BRD-SG-00647` — SGD 6,426 (82.35%)
46. The Brew Therapy — `BRD-SG-02437` — SGD 6,276 (82.83%)
47. ESSENSO — `BRD-SG-02078` — SGD 6,201 (83.30%)
48. Suntory — `BRD-GLOBAL-01032` — SGD 6,025 (83.76%)
49. Gran Maestro Italiano — `BRD-SG-02619` — SGD 5,760 (84.20%)
50. Ah Huat — `BRD-SG-01352` — SGD 5,655 (84.63%)
51. Nestle — `BRD-GLOBAL-00059` — SGD 5,632 (85.06%)
52. VPP Coffee — `BRD-SG-00893` — SGD 5,457 (85.48%)
53. Little's — `BRD-SG-02570` — SGD 5,441 (85.89%)
54. Ghostbird Coffee Roasters — `BRD-SG-03013` — SGD 5,042 (86.27%)
55. IN — `BRD-SG-06662` — SGD 4,798 (86.64%)
56. Bialetti — `BRD-SG-00997` — SGD 4,643 (86.99%)
57. Malaysia Collection — `BRD-GLOBAL-01865` — SGD 4,481 (87.34%)
58. Gold Roast — `BRD-SG-02953` — SGD 4,270 (87.66%)
59. Mister Coffee — `BRD-SG-02972` — SGD 4,131 (87.98%)
60. AGF — `BRD-GLOBAL-01117` — SGD 4,075 (88.29%)
61. Key Coffee — `BRD-SG-02666` — SGD 3,691 (88.57%)
62. Dongsuh — `BRD-SG-02832` — SGD 3,515 (88.84%)
63. Segafredo Zanetti — `BRD-SG-02964` — SGD 3,460 (89.10%)
64. Drip Coffee — `BRD-SG-12416` — SGD 3,358 (89.36%)
65. Lao Qian — `BRD-SG-04669` — SGD 3,282 (89.61%)
66. Jamu Ratu Malaya — `BRD-SG-01830` — SGD 3,274 (89.86%)
67. Ye Ye — `BRD-SG-03063` — SGD 3,224 (90.10%)
68. Rly Coffee — `BRD-SG-03249` — SGD 2,973 (90.33%)
69. TRUNG NGUYEN LEGEND — `BRD-SG-01886` — SGD 2,969 (90.56%)
70. Pod Labs — `BRD-SG-02755` — SGD 2,851 (90.77%)
71. Bean — `BRD-SG-01017` — SGD 2,774 (90.98%)
72. LOTTE — `BRD-GLOBAL-01727` — SGD 2,615 (91.18%)
73. Agf Blendy — `BRD-SG-03340` — SGD 2,569 (91.38%)
74. GS25 — `BRD-SG-03317` — SGD 2,427 (91.56%)
75. BOLD Coffee — `BRD-SG-03431` — SGD 2,402 (91.75%)
76. Kimbo — `BRD-SG-01183` — SGD 2,301 (91.92%)
77. Foresta — `BRD-GLOBAL-00493` — SGD 2,285 (92.10%)
78. Fresh Cafe — `BRD-SG-04110` — SGD 2,251 (92.27%)
79. BATTUTA COFFEE — `BRD-SG-03910` — SGD 2,211 (92.44%)
80. ZUS COFFEE — `BRD-SG-04475` — SGD 2,190 (92.60%)
81. KLUANG RailCoffee — `BRD-SG-03728` — SGD 2,187 (92.77%)
82. King Coffee — `BRD-SG-01060` — SGD 2,183 (92.94%)
83. Cafe21 — `BRD-SG-03846` — SGD 2,162 (93.10%)
84. Leone — `BRD-SG-03246` — SGD 2,118 (93.26%)
85. Yit Foh Coffee — `BRD-SG-04213` — SGD 2,115 (93.43%)
86. Wake The Crew — `BRD-SG-03513` — SGD 1,986 (93.58%)
87. Punto Italia Espresso — `BRD-SG-00887` — SGD 1,943 (93.72%)
88. Lipbusycare — `BRD-SG-02860` — SGD 1,936 (93.87%)
89. All — `BRD-SG-06567` — SGD 1,920 (94.02%)
90. Noble — `BRD-SG-06528` — SGD 1,892 (94.16%)
91. MacCoffee — `BRD-SG-03097` — SGD 1,841 (94.30%)
92. Sin Boon Kee — `BRD-SG-04888` — SGD 1,808 (94.44%)
93. Jewel Coffee — `BRD-SG-03742` — SGD 1,808 (94.58%)
94. ROBERT TIMMS — `BRD-SG-03844` — SGD 1,727 (94.71%)
95. Kluang Coffee — `BRD-SG-06813` — SGD 1,654 (94.84%)
96. Namyang — `BRD-SG-02785` — SGD 1,608 (94.96%)

**Unattributed GMV bucket** (SGD ~55,027 at raw rank 4 / SGD ~14,996 at raw rank 19 — brand_dict
`BRD-UNDEFINED` and products with no `product_brand_map` row at all): not a real brand, excluded from the
numbered list above but its GMV still consumes cumulative share (this is why brand ranks above jump
unevenly — e.g. rank 4 COWPRESSO absorbs the position after the largest Undefined bucket). These products
still get read directly during Pass 1/2 — the LLM's own `brand_from_image` extraction may resolve a
correct brand where `product_brand_map` couldn't.

Brands excluded from scope (below 95% cumulative, long tail): everything from rank 97 onward (KopiHouse,
Atomy, ... down through 790 distinct brand_ids seen in this table this month, most single-digit-SGD GMV).
Not enumerated here — the tail is large and immaterial individually; Rule B (official-store) can still pull
an out-of-scope-by-GMV brand's listing into scope if it has a Mall store, but none of the excluded-brand
Mall stores found in this session's scan carry only sub-95% brands.

---

## Official Store Allowlist (Pass 1)

Built by querying distinct `merchant_name WHERE merchant_badge='Shopee Mall'` for products of the 96
in-scope brands, month 2026-06-01. **42 of the 96 in-scope brands have at least one official store; 54 have
none (Pass 2 only).**

**Excluded as multi-brand general retailers** (per `docs/llm-extraction-rules.md` §4 — Mall badge present
but not brand-representative; carry unrelated brands/categories, not a manufacturer or specialist coffee
distributor storefront):
- `DON DON DONKI Official Store` — general Japanese discount department store (snacks/cosmetics/electronics/coffee mixed)
- `K-Market by Koryo Trading` — general Korean grocery importer
- `myCK_online` — general reseller, no single-brand affiliation
- `Miele` — household appliances retailer (unrelated category bleed-through)
- `Electronics House` — electronics retailer
- `Ren Ren Pharmacy Official` — pharmacy/general retailer

| Brand | brand_id | Official Store Merchant Name(s) |
|-------|----------|----------------------------------|
| AGF | BRD-GLOBAL-01117 | `Miss Dou's Groceries Official` / `CODIA Japan` / `大買家網路店 Save & Safe Official` |
| Agf Blendy | BRD-SG-03340 | `CODIA Japan` |
| All | BRD-SG-06567 | `cosblah` |
| Arabica | BRD-SG-09596 | `Gracious Naturals Official Store` / `Signature Market Official Store✅` / `大買家網路店 Save & Safe Official` / `RedMan Official Store` / `888 Official Store` |
| Bean | BRD-SG-01017 | `SL Foods Official Store` / `SenmuYuan.sg` / `RedMan Official Store` / `888 Official Store` |
| Bialetti | BRD-SG-00997 | `Bialetti Official Store` |
| Cheerful Goat | BRD-SG-02200 | `CheerfulGoat` |
| Coffeehock | BRD-SG-01744 | `FoodCulture.SG Official Store` / `Prestigio Delights Official` |
| Drip Coffee | BRD-SG-12416 | `Signature Market Official Store✅` |
| ESSENSO | BRD-SG-02078 | `JDE World Of Coffee Official Store` |
| Gold Kili | BRD-SG-01598 | `Lioncity Distributor` |
| ILLY | BRD-SG-00331 | `illy Flagship Store` |
| IN | BRD-SG-06662 | `888 Official Store` / `ZLX Hardware Wholesaling Official` / `Kluang Coffee Official Store` / `3:15PM Official Store` |
| Killiney | BRD-SG-01452 | `Killiney Mart` / `FoodCulture.SG Official Store` / `Pod Labs Official Store` |
| Kluang Coffee | BRD-SG-06813 | `Food Affinity Singapore Official` / `Kluang Coffee Official Store` |
| Kopi | BRD-SG-00737 | `NESTLÉ Official Store` |
| L'OR | BRD-SG-00468 | `JDE World Of Coffee Official Store` |
| LOTTE | BRD-GLOBAL-01727 | `SL Foods Official Store` / `lotteofficial` |
| Lao Qian | BRD-SG-04669 | `ETC Travel Retail` |
| Lavazza | BRD-SG-00367 | `Lavazza Official Store` |
| Milo | BRD-GLOBAL-00183 | `NESTLÉ Official Store` |
| Moccona | BRD-GLOBAL-00088 | `JDE World Of Coffee Official Store` |
| Modern Hippi | BRD-SG-02506 | `Modern Hippi Freeze-Dried Coffee` |
| Nescafe | BRD-SG-00009 | `NESTLÉ Official Store` / `Prime Online Official Store` / `NESCAFE Dolce Gusto Official Store` |
| Nespresso | BRD-SG-00179 | `cosblah` |
| Nestle | BRD-GLOBAL-00059 | `NESTLÉ Official Store` / `EZMORE Official` |
| OWL | BRD-SG-01534 | `JDE World Of Coffee Official Store` |
| Old Town | BRD-SG-00492 | `JDE World Of Coffee Official Store` |
| PARCHMEN & CO. | BRD-SG-02510 | `Parchmen and Co Official Store` |
| Pod Labs | BRD-SG-02755 | `Pod Labs Official Store` / `Killiney Mart` |
| Punto Italia Espresso | BRD-SG-00887 | `Singapore Coffee Service` |
| REDMAN | BRD-SG-02082 | `RedMan Official Store` |
| Sin Boon Kee | BRD-SG-04888 | `Food Affinity Singapore Official` |
| Starbucks | BRD-GLOBAL-00146 | `Starbucks at Home Official Store` / `NESTLÉ Official Store` |
| Suntory | BRD-GLOBAL-01032 | `Kirei – Japan's Finest` / `Choco Express Official Store` |
| TAG Espresso | BRD-SG-02087 | `TAG Espresso Official Store` |
| TRUNG NGUYEN | BRD-SG-01292 | `Trung Nguyen Legend Cafe` |
| TRUNG NGUYEN LEGEND | BRD-SG-01886 | `Trung Nguyen Legend Cafe` |
| Wake The Crew | BRD-SG-03513 | `Wake The Crew Official Store` |
| Ye Ye | BRD-SG-03063 | `JDE World Of Coffee Official Store` |
| luckin coffee | BRD-GLOBAL-02085 | `Aurora Marketplace` / `Sara.` |
| maxime | BRD-GLOBAL-00224 | `Hanguk Kitchen SG Official Store` |

**Multi-brand stores (parent-company / specialist distributor — require `brand_from_image` disambiguation
per product, per Decision 14 — never treat the store name as the brand):**
- `JDE World Of Coffee Official Store` — sells ESSENSO, L'OR, Moccona, OWL, Old Town, Ye Ye
- `NESTLÉ Official Store` — parent company store (Nestle owns/licenses Nescafe, Milo, Starbucks-at-home in SG) — sells Kopi, Milo, Nescafe, Nestle, Starbucks
- `888 Official Store`, `RedMan Official Store` — Arabica, Bean, IN, REDMAN
- `CODIA Japan`, `大買家網路店 Save & Safe Official` — AGF, Agf Blendy, Arabica
- `Food Affinity Singapore Official` — Kluang Coffee, Sin Boon Kee
- `FoodCulture.SG Official Store`, `Killiney Mart`, `Pod Labs Official Store` — Coffeehock, Killiney, Pod Labs
- `Kluang Coffee Official Store` — IN, Kluang Coffee
- `SL Foods Official Store` — Bean, LOTTE
- `Signature Market Official Store✅` — Arabica, Drip Coffee
- `Trung Nguyen Legend Cafe` — TRUNG NGUYEN, TRUNG NGUYEN LEGEND (same corporate family, kept as distinct brand_dict entries per existing brand_dict — do not merge)
- `cosblah` — All, Nespresso

**Brands with no official store (Pass 2 only, 54 brands):** Ah Huat, Aik Cheong, BATTUTA COFFEE, BOLD
Coffee, Bacha Coffee, COWPRESSO COFFEE ROASTERS, Cafe Specialists, Cafe21, Chang, Chek Hup, Dongsuh, Encik
Guan, Foresta, Fortune Coffee Club, Fresh Cafe, G7, GS25, Ghostbird Coffee Roasters, Gold Beverage, Gold
Roast, Gran Maestro Italiano, Indocafe, Jamu Ratu Malaya, Jewel Coffee, KLUANG RailCoffee, Kanu, Key Coffee,
Kim's Duet, Kimbo, King Coffee, Leone, Lipbusycare, Little's, MacCoffee, Malaysia Collection, Mister
Coffee, Mövenpick, Namyang, Noble, Oriental, Oriental White Coffee, POKKA, ROBERT TIMMS, Rly Coffee,
Segafredo Zanetti, Suzuki Coffee, TNI King Coffee, The Brew Therapy, Toast Box, UCC Coffee, VPP Coffee, Yit
Foh Coffee, ZUS COFFEE, Zero Coffee.

(Note: Toast Box, UCC Coffee, Key Coffee, Dongsuh, GS25 each had a Mall listing, but only through an
excluded general-retailer store — DON DON DONKI or K-Market — so they correctly fall into Pass 2, not Pass 1.)

---

## Scale

- Total rows (2026-06): 48,772 · distinct products: 17,510
- Full Mall-badged pool: 4,044 rows / 1,657 distinct products
- **Official Store Allowlist scope (the actual Pass 1 pool, allowlist merchants only, not the full Mall pool): 2,724 rows / 1,209 distinct products.** This is a manageable size for direct per-product image reads within one session — no further sampling needed for Pass 1.
- Existing `product_taxonomy_map` rows (see below): 1,571 HUMAN, 0 LLM.

---

## Existing Map Rows (Step 1 result)

| Source | Count |
|--------|-------|
| LLM | 0 |
| HUMAN | 1,571 (distinct products) |

Confirms genuine first LLM pass — 0 `source='LLM'` rows is what the wrapper's auto-detection scoped to
(`docs/headless-runbook.md`'s Full Rebuild scenario-selection logic checks `source='LLM'` specifically).
The 1,571 HUMAN keyword-seed rows are expected baseline coverage and are not touched by this session except
where a product also gets an LLM row (dedup handled at universe-refresh MERGE time, LLM takes precedence —
no explicit HUMAN delete needed for coffee since, per headless-runbook.md, that delete pattern is scoped to
categories where the wrapper explicitly requests it; this session leaves existing HUMAN rows as-is and lets
the refresh MERGE's `QUALIFY` dedup logic prefer the new LLM rows per product automatically).

---

## Scope — What's In vs Out

**In scope:**
- Ground/instant/roasted coffee (beans, powder, sachets, capsules/pods, 3-in-1 mixes)
- Ready-to-drink bottled/canned coffee
- Coffee-brewing accessories bundled as GWP with a coffee product (main product still coffee)

**Out of scope (leave NULL):**
- Standalone brewing equipment with no coffee product attached (moka pots, machines, grinders sold alone)
- Non-coffee beverages that appear in this table due to NIQ mislabeling (verify per product, don't assume by brand)

**Edge cases:**
- Milo, Nestle: multi-category brands (Milo is a malt drink, not coffee) — only Milo *coffee* products (e.g. Milo x coffee blends) are in scope; verify per listing, not by brand alone.
- Suntory, POKKA, LOTTE: beverage conglomerates with non-coffee product lines — verify per sku_name/image that the specific listing is a coffee product.

---

## Taxonomy Design Notes

**Product line extraction approach:**
- Use the on-label product line name (e.g. "Gold Blend", "Classic", "3in1 Original") per `docs/llm-extraction-rules.md` §3 — never a generic word like "Coffee" or "Instant Coffee" alone.
- Multi-brand parent stores (JDE, NESTLÉ, 888, RedMan, CODIA, etc.): disambiguate brand via `brand_from_image`, not the store name.

**Size extraction notes:**
- Primary units: g (ground/instant sachets), ml/L (RTD bottled/canned), stick/sachet count for 3-in-1 mixes (write as pack_count with size = per-stick weight where stated, e.g. "20g x30").
- Pack-count patterns: sachets sold in boxes (`x10`, `x30`), RTD multi-can cases (`x24`), promo bundles (`buy 1 get 1`, `1+1`).

**Known difficult products:** none catalogued yet — first session.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-20 | Pre-run | 1,571 HUMAN rows, 0 LLM rows confirmed via live query | Not a blocker — genuine first LLM pass, proceed |

---

## Targeted QA Fix Brief

> Not applicable yet — no LLM rows exist prior to this session. Populate after this run's QA gate results if
> a follow-up Targeted QA Fix is needed.

---

## Scripts

Extraction performed directly by the Claude Code session (own multimodal reads), not via `pipeline/05_product_taxonomy/` scripts.

---

## Map Row Counts (as of last run)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | TBD | This session's Pass 1 + Pass 2 |
| HUMAN | 1,571 | Long-tail / pre-existing keyword seed, retained |
| NULL (unmapped) | TBD | Below GMV scope or out-of-category |
