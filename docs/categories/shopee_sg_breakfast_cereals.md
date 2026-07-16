# shopee_sg_breakfast_cereals — Category Context

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ❌ Not started |
| LLM Pass 2 | ❌ Not started |
| GMV Coverage | 0% (baseline: 508 HUMAN keyword-seed rows only) |
| Last run | 2026-07-16 |
| Current MAX taxonomy_id | SKU-074188 (query BQ directly before any insert — never trust this file) |

**Prior attempt today:** `sku_block_registry` shows a claim `SKU-076001–080150` (4,150 slots, `full_rebuild`,
`status=FAILED_QA`, claimed 2026-07-16 09:45:01) for this exact table. Verified: zero `product_taxonomy` rows
exist in that range and zero `source='LLM'` rows exist in `product_taxonomy_map` for this table — nothing was
left behind, the block is simply burned. Per `docs/headless-runbook.md` Error handling, it is never reused; this
session claims a fresh block starting after `MAX(block_end)`.

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-080151–082150 (2,000 slots) | Pass 1 OFFICIAL + Pass 2 RESELLER — claimed this session |

---

## Scale (verified 2026-07-16, all-time unless noted)

- Source table `master_clean_niq.shopee_sg_breakfast_cereals`: 614,302 rows total (model/variant grain,
  Feb 2025–Jun 2026). Single NIQ category — `category_3_EN = 'Cereal, Granola & Oats'` for 100% of rows, so
  **no mixed-content keyword guard is needed** for brand GMV ranking (unlike body_wash/liquid_milk).
- Distinct products, all-time: 10,808.
- Official-store (`merchant_badge='Shopee Mall'`) rows all-time: 45,879 → 1,194 distinct products across *all*
  brands (in and out of 95% scope).
- **Official-store products within the 95% GMV brand scope (the real Pass 1 workload): 673 distinct products.**
  This is the number that matters — small enough to vision-read in one session (contrast: `sg_shampoo`'s
  187,902-row Mall-badged pool, the scale failure that motivated this doc's "do not just badge-filter" warning).
- Reseller (non-Mall) products within the 95% GMV brand scope (the Pass 2 candidate pool, bulk-SQL text-match
  first): 5,227 distinct products.
- Review month used for GMV ranking: **2026-05-01** — the latest month present in `magpie.marketshare_universe_niq`
  for this table (source table has a partial 2026-06-01; universe_niq doesn't yet). `magpie.marketshare_universe`
  is NOT usable for this table — per the headless-runbook Addendum it has been repurposed to consumer
  electronics and carries no FMCG rows. GWP check: `flag_GWP=TRUE` on only 33 of 43,340 rows in the review month
  and `SUM(gmv_monthly)` is identical with/without excluding them (both round to 235,927) — GWP is immaterial for
  this category, no adjustment needed.

---

## Existing map rows (Step 1 — verified, not assumed)

| Source | Count | Notes |
|--------|-------|-------|
| HUMAN | 508 | Pre-existing keyword-seed rows, all generic "(all variants)" stubs, e.g. `Amazin' Graze Granola / Oats / Nut Butter (all variants)`, `Kellogg's Corn Flakes / Breakfast Cereal (all variants)`. These are Tier-C stubs per quality-standards.md D1 — expected to be superseded by real LLM entries for the same products, not deleted by this session. |
| LLM | 0 | Confirmed — the earlier FAILED_QA attempt wrote nothing. |

---

## Brand Scope (real 95% cumulative GMV threshold, review month 2026-05-01)

**71 brands** reach the 95% cumulative-GMV threshold (448 distinct brands total in the category — the tail is
long). Listed by GMV rank; `BRD-UNDEFINED` ("Undefined") is included in the scope set per existing category-file
convention (e.g. `th_drinking_water`) but is not itself Pass-1-eligible (no official store possible for an
unidentified brand).

1. Mrs Ma Food Therapy — `BRD-SG-00931` — $49,433 (20.95% cum)
2. Undefined — `BRD-UNDEFINED` — $27,081 (32.43% cum)
3. Amazin' Graze — `BRD-SG-01754` — $17,150 (39.70% cum)
4. Quaker — `BRD-GLOBAL-01882` — $16,642 (46.75% cum)
5. Dr OatCare — `BRD-SG-01699` — $15,786 (53.45% cum)
6. Zenko Superfoods — `BRD-SG-03306` — $6,255 (56.10% cum)
7. Omollomo — `BRD-SG-02613` — $4,936 (58.19% cum)
8. Calbee — `BRD-SG-03112` — $4,525 (60.11% cum)
9. Nocturne oats — `BRD-SG-02707` — $3,905 (61.76% cum)
10. SuperFarm — `BRD-SG-03712` — $3,700 (63.33% cum)
11. Kellogg's — `BRD-SG-03284` — $3,607 (64.86% cum)
12. Post — `BRD-SG-03319` — $3,343 (66.28% cum)
13. Nestle — `BRD-GLOBAL-00059` — $3,283 (67.67% cum)
14. CAPTAIN OATS — `BRD-SG-03277` — $2,634 (68.78% cum)
15. Ketogenius Kitchen — `BRD-SG-03802` — $2,553 (69.87% cum)
16. Living Forest — `BRD-SG-03590` — $2,432 (70.90% cum)
17. REDMAN — `BRD-SG-02082` — $2,358 (71.90% cum)
18. Nature's Nutrition — `BRD-SG-01894` — $2,106 (72.79% cum)
19. Nature's Superfoods — `BRD-SG-02101` — $2,090 (73.68% cum)
20. BIOGROW — `BRD-SG-04034` — $2,083 (74.56% cum)
21. Healthy Mate — `BRD-SG-03702` — $2,048 (75.43% cum)
22. Good Lady — `BRD-SG-01155` — $1,918 (76.24% cum)
23. Nature's Glory — `BRD-SG-03467` — $1,883 (77.04% cum)
24. YAVA — `BRD-SG-03848` — $1,757 (77.78% cum)
25. Dongseo — `BRD-SG-03595` — $1,715 (78.51% cum)
26. purely elizabeth — `BRD-SG-03814` — $1,680 (79.22% cum)
27. Zestiva — `BRD-SG-02846` — $1,574 (79.89% cum)
28. RADIANT ORGANIC — `BRD-SG-02459` — $1,499 (80.52% cum)
29. Black Sesame — `BRD-TH-01499` — $1,452 (81.14% cum)
30. Sweet Home Farm — `BRD-SG-03924` — $1,406 (81.74% cum)
31. NISSIN — `BRD-SG-03837` — $1,396 (82.33% cum)
32. D'ARK — `BRD-SG-12623` — $1,392 (82.92% cum)
33. Emco — `BRD-SG-03926` — $1,366 (83.50% cum)
34. Simply Natural — `BRD-SG-03023` — $1,355 (84.07% cum)
35. Bob's Red Mill — `BRD-SG-04397` — $1,315 (84.63% cum)
36. IN — `BRD-SG-06662` — $1,311 (85.18% cum)
37. Yogood — `BRD-SG-03900` — $1,162 (85.68% cum)
38. familia — `BRD-SG-04254` — $1,147 (86.16% cum)
39. love earth — `BRD-SG-04560` — $1,141 (86.65% cum)
40. Dr Gram — `BRD-SG-04232` — $978 (87.06% cum)
41. Kintry — `BRD-SG-04105` — $938 (87.46% cum)
42. Catalina Crunch — `BRD-SG-11983` — $912 (87.84% cum)
43. ORGANIC FIELDS — `BRD-SG-07757` — $797 (88.18% cum)
44. Alpen — `BRD-SG-05045` — $749 (88.50% cum)
45. Koko Krunch — `BRD-SG-04350` — $741 (88.81% cum)
46. Labnosh — `BRD-SG-04749` — $705 (89.11% cum)
47. FULLight — `BRD-SG-03141` — $698 (89.41% cum)
48. Twinfish — `BRD-SG-04797` — $683 (89.70% cum)
49. Nature's Own — `BRD-GLOBAL-02485` — $681 (89.99% cum)
50. UNISOY — `BRD-SG-02773` — $658 (90.27% cum)
51. GARDEN PICKS — `BRD-SG-04973` — $618 (90.53% cum)
52. Biogreen — `BRD-SG-02618` — $614 (90.79% cum)
53. iWhite — `BRD-GLOBAL-02699` — $613 (91.05% cum)
54. Gabrielle T — `BRD-SG-04934` — $598 (91.30% cum)
55. Beta Glucan+ — `BRD-TH-02346` — $583 (91.55% cum)
56. Ceres Organics — `BRD-SG-05286` — $575 (91.79% cum)
57. Applied Nutrition — `BRD-SG-04317` — $574 (92.04% cum)
58. Bean — `BRD-SG-01017` — $563 (92.27% cum)
59. Milo — `BRD-GLOBAL-00183` — $558 (92.51% cum)
60. munchy's — `BRD-SG-05521` — $552 (92.74% cum)
61. Tong Garden — `BRD-SG-05100` — $540 (92.97% cum)
62. ORION — `BRD-SG-04709` — $539 (93.20% cum)
63. Etblisse — `BRD-SG-03828` — $524 (93.42% cum)
64. Vogel's — `BRD-SG-05504` — $517 (93.64% cum)
65. Market O — `BRD-SG-05376` — $511 (93.86% cum)
66. Gold Kili — `BRD-SG-01598` — $504 (94.07% cum)
67. Surreal — `BRD-SG-05399` — $496 (94.28% cum)
68. Singapore Oats — `BRD-SG-05220` — $478 (94.49% cum)
69. Nestum — `BRD-SG-03215` — $459 (94.68% cum)
70. Psyllium husk — `BRD-TH-02224` — $459 (94.88% cum)
71. Cowhead — `BRD-SG-05447` — $421 (95.05% cum — first brand crossing the threshold, included)

Brands excluded from scope (below 5% GMV tail): remaining 377 brands, each <$421/mo, long-tail resellers of
generic/import cereal products. Leave unmapped unless individually flagged in a later NULL-coverage pass.

---

## Official Store Allowlist (Pass 1)

Built by querying distinct `merchant_name WHERE merchant_badge='Shopee Mall'` **per scope brand_id above**, not
the full Mall-badged pool. A critical finding from this query: most "X Official Store"-named merchants in this
category are actually **multi-brand supermarket/pharmacy/distributor chains** that happen to carry the Shopee
Mall badge and sell many brands' products — not brand-principal stores. These must be excluded even though the
name contains "Official Store" and even though `docs/llm-extraction-rules.md`'s hardcoded exclusion list
(Watsons, BigC, etc.) doesn't happen to name them. The exclusion test used here: **does this merchant appear
under more than one distinct scope brand in the query results?** If yes, exclude as multi-brand regardless of
name.

**Multi-brand retailers excluded (confirmed carrying 2+ scope brands each):**
`Cold Storage Official Store` (SG supermarket — 20+ brands), `Mustafa Centre Official Store` (department store),
`Shopee Supermarket` (Shopee's own multi-brand grocery), `Hao Mart Official Shop`, `DON DON DONKI Official Store`,
`Prime Online Official Store`, `BIG Pharmacy`, `Bulky Bay Hub`, `Choco Express Official Store`,
`Scarlett Supermarke(t) 思家客国货超市 Official/Offical` (two spelling variants seen), `Lim Siang Huat Official Store`,
`Prestigio Delights Official`, `SL Foods Official Store`, `K.O.I STORE VN`, `RedMan Official Store` (also carries
its own REDMAN brand — see disambiguation note below), `Miss Dou's Groceries Official`, `1326136418`,
`149254894`, `43719124`, `7876349`, `1278724105`, `296575148`, `151409130`, `379403271` (numeric-ID merchant
names — Shopee lets any verified seller earn a Mall badge; these are resellers, not brand owners, despite the
badge — every one of them appears under multiple unrelated scope brands in the query).

**Watsons Singapore Official Store** — the only "official" store found for **Dr OatCare** — is on the standard
multi-brand exclusion list per `docs/llm-extraction-rules.md` §4 even though it shows only one scope brand here
(Watsons carries far more brands outside this category's scope). Excluded. **Dr OatCare has no valid official
store → Pass 2 only**, despite being the #5 brand by GMV.

**Confirmed single-brand / parent-company official stores (Pass 1 eligible):**

| Brand | brand_id | Official Store Merchant Name |
|-------|----------|------------------------------|
| Amazin' Graze | BRD-SG-01754 | `Amazin' Graze Official Store` |
| Applied Nutrition | BRD-SG-04317 | `Couz-Nutri Official Store` |
| Nature's Glory | BRD-SG-03467 | `Nature's Glory Organic Official` |
| Nature's Nutrition | BRD-SG-01894 | `Nature's Nutrition Official Store` |
| Nature's Superfoods | BRD-SG-02101 | `Nature's Superfoods Official Store` |
| SuperFarm | BRD-SG-03712 | `Nature's Nutrition Official Store` (shared parent — same store also carries Nature's Nutrition; treat as joint official store for both, not a generic multi-brand exclusion, since only these two brands appear there) |
| Omollomo | BRD-SG-02613 | `Revive Snacks Official Store` **and** `Omollomo (formerly Revive Snacks)` (brand rename — both names legitimate, both official) |
| Nestle | BRD-GLOBAL-00059 | `NESTLÉ Official Store` |
| Milo | BRD-GLOBAL-00183 | `NESTLÉ Official Store` (Nestle parent — Milo is a Nestle-owned brand) |
| Koko Krunch | BRD-SG-04350 | `NESTLÉ Official Store` (Nestle parent) |
| Nestum | BRD-SG-03215 | `NESTLÉ Official Store` (Nestle parent) |
| Quaker | BRD-GLOBAL-01882 | `Lay's & Quaker Store` **and** `Pepsico Food Official Store` (PepsiCo parent — Quaker is PepsiCo-owned) |
| REDMAN | BRD-SG-02082 | `RedMan Official Store` (also carries Bob's Red Mill, D'ARK, IN — needs `brand_from_image` disambiguation per product; only attribute to REDMAN when the image confirms) |
| Biogreen | BRD-SG-02618 | `Biogreen&Etblisse SG Official store` (joint store, 2 owned brands only) |
| Etblisse | BRD-SG-03828 | `Biogreen&Etblisse SG Official store` (joint store, 2 owned brands only) |
| D'ARK | BRD-SG-12623 | `Signature Market Official Store✅` |
| Dr Gram | BRD-SG-04232 | `Lifewinners Organic Official Store` |
| Gold Kili | BRD-SG-01598 | `Lioncity Distributor` |
| Healthy Mate | BRD-SG-03702 | `Oz Health Official Store` |
| Labnosh | BRD-SG-04749 | `Woah Group Official Store` |
| RADIANT ORGANIC | BRD-SG-02459 | `Arumi Health` |
| Simply Natural | BRD-SG-03023 | `ZENXIN ORGANIC OFFICIAL STORE` |
| Sweet Home Farm | BRD-SG-03924 | `GTK Foods Official Store` |
| Tong Garden | BRD-SG-05100 | `Tong Garden SG Official Store` |
| UNISOY | BRD-SG-02773 | `UNISOY Official Store` |
| Dongseo | BRD-SG-03595 | `K-Market by Koryo Trading` **and** `Koryo Mart & K-Market` (Korean-import distributor, both names, only Dongseo attributed here) |

**Brands with no official store found (Pass 2 only)** — either no Mall-badged listing at all, or every
Mall-badged listing for the brand turned out to be one of the multi-brand retailers above: Mrs Ma Food Therapy,
Undefined (not a real brand), Zenko Superfoods, Dr OatCare (Watsons excluded), Nocturne oats, Kellogg's, Post,
Ketogenius Kitchen, Living Forest, Good Lady, YAVA, purely elizabeth, Zestiva, Black Sesame, NISSIN, Emco,
Bob's Red Mill (no clean single-brand store — REDMAN carries it but that's REDMAN's own store, disambiguate by
image if it appears, don't treat as Bob's Red Mill's official store), IN (same caveat), Yogood, familia,
love earth, Kintry, Catalina Crunch, ORGANIC FIELDS, Alpen, FULLight, Twinfish, Nature's Own, GARDEN PICKS,
iWhite, Gabrielle T, Beta Glucan+, Ceres Organics, Bean, munchy's, ORION, Vogel's, Market O, Surreal,
Singapore Oats, Psyllium husk, Cowhead, CAPTAIN OATS, Calbee.

---

## Scope — What's In vs Out

**In scope:** breakfast cereal, granola, muesli, oats/oatmeal, malt/cereal drink powder (Milo, Nestum-type),
cereal bars marketed as breakfast cereal. Source table is single-category (`Cereal, Granola & Oats`) — no
cross-category contamination expected, but verify per-product if a listing looks like a snack bar or supplement
rather than a breakfast product.

**Out of scope (leave NULL):** standalone health supplements/vitamins mis-tagged into this table, loose raw
ingredients unrelated to cereal (e.g. psyllium husk sold as a fiber supplement rather than a cereal-adjacent
product — verify per listing for the `Psyllium husk` brand specifically).

**Edge cases:** `RedMan Official Store` and `Bob's Red Mill` / `D'ARK` / `IN` / `REDMAN` overlap — always read
`brand_from_image` before assigning; do not default to REDMAN just because the store name matches.

---

## Taxonomy Design Notes

**Product line extraction approach:** use the real on-label product line (e.g. "Multigrain Muesli", "Steel Cut
Oats", "Corn Flakes Original") — never a bare category word. Populate `product_line`, `sub_line`, `variant` as
structured columns per `docs/llm-extraction-rules.md` §3 — do not fold this only into free-text `canonical_name`.

**Size extraction notes:** primary units g / kg for cereal/oats, ml for ready-to-drink malt beverages (rare in
this table). Multi-sachet boxes are common — apply the pack-count priority chain (§1 of the rules doc):
sku_name text first, image as tiebreaker.

**Known difficult products:** none identified yet — this is the first extraction pass for this category.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-16 | Prior attempt (this doc's predecessor session) | Claimed SKU-076001–080150, wrote 0 rows, marked FAILED_QA | Block abandoned per policy; this session claims a fresh block and starts from scratch with real scale numbers gathered first |

---

## Map Row Counts (as of this session's start)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 0 | — |
| HUMAN | 508 | Generic "(all variants)" keyword-seed stubs, retained until superseded per-product by an LLM row |
| NULL (unmapped) | ~10,300 (10,808 total distinct products − 508 HUMAN) | Below GMV scope or out-of-category |
