# shopee_sg_breakfast_cereals — Category Context

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete (264 official-store candidate products, 173 taxonomy entries, 174 map rows) |
| LLM Pass 2 | ⏳ Partial (top-95%-of-remaining-GMV reseller pool routed: 99 new entries, 140 map rows; long tail of ~4,392 low-GMV reseller products left `UNRESOLVED` by deliberate GMV-impact triage) |
| Top-up (2026-06) | ✅ Complete — 418 new entries, 421 new map rows; live worklist (450 products) fully resolved |
| GMV Coverage | 95.8% (2026-06-01, combined LLM rows) — up from 83.9% (2026-05-01) |
| Last run | 2026-07-27 |
| Current MAX taxonomy_id | SKU-172069 (query BQ directly before any insert — never trust this file) |

**Prior attempt today:** `sku_block_registry` shows a claim `SKU-076001–080150` (4,150 slots, `full_rebuild`,
`status=FAILED_QA`, claimed 2026-07-16 09:45:01) for this exact table. Verified: zero `product_taxonomy` rows
exist in that range and zero `source='LLM'` rows exist in `product_taxonomy_map` for this table — nothing was
left behind, the block is simply burned. Per `docs/headless-runbook.md` Error handling, it is never reused; this
session claims a fresh block starting after `MAX(block_end)`.

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-080151–082150 (2,000 slots, claimed) | SKU-080151–080323 used for Pass 1 (173 entries); SKU-080324–080422 used for Pass 2 (99 entries). SKU-080423–082150 remains unused/ACTIVE — **not reused by the 2026-07-27 top-up session below**, which claimed a fresh block per its own instructions rather than this reserved tail (see that session's QA History entry for why); still available for a future targeted-fix pass. |
| SKU-171652–172346 (695 slots, claimed 2026-07-27, scenario `taxonomy_topup`) | SKU-171652–172069 used (418 entries) for the 2026-06 coverage top-up. SKU-172070–172346 unused, block remains ACTIVE. |

This category now owns **two disjoint SKU ranges** — both are legitimate; a G4 check must treat SKU-080151–082150 and SKU-171652–172346 as this category's own ranges, not cross-category contamination.

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
| 2026-07-16 | Pass 1 (this session) | 264 candidate products from the confirmed single-brand official-store allowlist; text-based extraction (sku_name is unusually rich/explicit for this category — brand, product line, size, pack count almost always stated) with one targeted image read to resolve a genuine size-range ambiguity (Quaker 5 Multi-Grain, resolved to `is_multi_variant=TRUE`, size=450g). 67 zero/near-zero-GMV catalog items (GWP-not-for-sale, seasonal gift boxes, non-food merch like a jute tote bag, generic import padding) explicitly excluded with documented per-item reasons rather than force-mapped. | 173 taxonomy entries, 174 map rows, `source='LLM'`, `meta_agent='CLAUDE_CODE'` |
| 2026-07-16 | Pass 2 (this session) | Full reseller/non-principal-Mall unmapped pool = 4,936 products; GMV concentration check showed 95% of remaining GMV sits in just 544 products. Routed the top-GMV portion of that set via text-match against the Pass 1 dictionary (including a shared `BRD-UNBRANDED` catch-all for a recurring generic "Five White Multigrain Instant Oat" commodity product sold by many unrelated resellers) plus new entries for real branded products not seen in Pass 1 (Dr OatCare, Bob's Red Mill additional sizes, Vogel's, familia, Nissin, etc.). A large Chinese-language long tail of TCM-adjacent tonic/meal-replacement products (tremella soup, yam powder, sour date kernel powder) was left unmapped as likely out-of-scope (not genuinely breakfast cereal) rather than force-classified. | 99 new taxonomy entries, 140 map rows. GMV coverage reached 83.9% (target ≥85%) — just short; a follow-up NULL-coverage pass targeting the remaining long tail would close the gap. Remaining SKU headroom (SKU-080423–082150) reserved for that. |
| 2026-07-16 | QA gate self-check (`--skip-coexistence`, per Full Rebuild pre-delete convention) | Dual-mapped LLM products: 0. Placeholder-leak: 0. Structured-fields (`product_line IS NULL`, distinct entries, excl. `is_multi_size`): 0%. HUMAN+LLM coexistence: 87 (expected at this stage — deletion of HUMAN rows that duplicate an LLM-mapped product is a wrapper-side step, not performed by this session). | All gates applicable to this session pass; no rows deleted by this session per explicit instruction |
| 2026-07-27 | Top-up coverage session, month 2026-06 | Live worklist (top-95%-cumulative-GMV, GWP-zeroed, `taxonomy_id IS NULL`) was 695 rows / **450 distinct products** (the prompt's 695-count was model/variant grain, not product grain — re-derived live per instructions, matching CLAUDE.md's `GROUP BY product_id ONLY` pitfall). The category's pre-existing 508 `source='HUMAN'` rows are gone from `product_taxonomy_map` as of this session (live query returned `LLM=314` only, no `HUMAN` rows) — G2 coexistence is now structurally 0, not something this session fixed; the "Map Row Counts" table above is stale on this point. Claimed a **fresh** 695-slot block (SKU-171652–172346) per the session's Step 2 instructions rather than reusing the SKU-080423–082150 tail reserved by the prior session for this exact purpose — flagged to an advisor before proceeding; the fresh-claim path was confirmed correct (the reserved tail's registry row no longer reflects a used/free boundary once partially consumed off-registry, and the task's own instruction is more specific/current) — see the SKU Blocks table above, both ranges are now this category's own. Processed all 450 in scope, bulk-first: 29 products (~2.1% of worklist GMV) excluded as out-of-scope TCM tonic/herbal/single-ingredient supplement products (white fungus/tremella, bird's nest, sour date kernel, soy lecithin, camel milk, baobab, astragalus/codonopsis, mulberry-leaf-bitter-gourd, flaxseed/almond powder alone), consistent with this doc's own prior "TCM-adjacent tonic" precedent — **Mrs Ma Food Therapy's multi-grain powder line (~37% of worklist GMV) was kept IN SCOPE**, correcting a likely over-exclusion in the prior session (the brand already had one taxonomy entry, `SKU-080392`, confirming precedent; 8 new distinct-formula entries minted, one per named product — not a flavor-variant collapse, each is a separately marketed formula). Reuse-before-mint found only 1 exact match to an existing entry (`SKU-080164`, Amazin' Graze Hazelnut Blackforest Granola 250g); everything else minted fresh (418 new entries, SKU-171652–172069) rather than risk false-positive collapsing — a naive brand+size text matcher tested first would have wrongly merged Mrs Ma's 8 distinct formulas into one existing entry on token overlap alone, confirmed via manual review before rejecting that approach. Brand resolution used `docs/categories/sg_breakfast_cereals.md`'s brand list + `brand_dict` lookups + merchant-name fallback for official/single-brand stores whose listings omit the brand in-title; **182 of 421 in-scope products (≈$20.8K/~18% of worklist GMV) resolved to `BRD-UNDEFINED`** — some with a real but not-yet-catalogued brand name preserved in `canonical_name` (Grande Granola, Okiss, Anmi Food, Milkywell, Green Earth Organic — real brands missing from `brand_dict`, out of this session's scope to add), the remainder (141 products) genuinely unresolved and named `"{line text} (unresolved)"` per `llm-extraction-rules.md` §3's convention. First DML write attempt leaked the literal word "Undefined" into `canonical_name` for the `BRD-UNDEFINED` entries (144 rows) — caught by this session's own placeholder-leak gate check, fixed in-place via `UPDATE ... REGEXP_REPLACE` before declaring done. Size/pack/product-line extraction was automated (regex-assisted) rather than fully hand-reviewed per-product, consistent with this task's explicit coverage-over-precision instruction; expect D1–D5 precision gaps in the tail (imprecise product-line wording, some `NULL` sizes where a size may actually be extractable, occasional cross-brand text contamination in multi-keyword-stuffed reseller titles) — **flagged as follow-up scope for `script/targeted_qa_fix.sh`, not fixed here**. | 418 new taxonomy entries + 421 new map rows, all `source='LLM'`, `meta_agent='CLAUDE_CODE'`. GMV coverage jumped from 83.9% (May, prior session) to **95.8%** (June, this session). QA gates: G1 dual-mapped=0, G2 HUMAN+LLM coexistence=0, G5 provenance=0, placeholder-leak=13 (all 13 are pre-existing `SKU-080xxx` entries using the now-banned "Multiple Variants" phrasing from before the 2026-07-22 rule change — zero introduced by this session, out of scope to fix here) |
| 2026-07-27 | Top-up verification session #2 (same day), month 2026-06 | Wrapper's live pre-check flagged 35 rows (29 distinct products, $2,385.65 GMV) still within the 95%-cumulative-GMV (GWP-zeroed) threshold with `taxonomy_id IS NULL`. Re-ran the live worklist query per this session's own instructions rather than trusting that count. All 29 products, without exception, are TCM-tonic/herbal-supplement/single-ingredient products (white fungus/tremella ×6, bird's nest ×2, astragalus/codonopsis soy milk powder ×4, soy lecithin ×2, camel milk protein powder, baobab powder, sour date kernel powder, yam powder ×2, black sesame/walnut/mulberry tonic powder ×2, flaxseed/almond powder alone ×3, black bean/red date soy milk powder ×2, dampness-clearing herbal paste, mulberry-leaf-bitter-gourd powder) plus one miscategorized snack listing (Japanese Kellogg's Pringles Kyushu Mentaiko — chips, not cereal, despite Kellogg's being an in-scope brand). These are the exact same 29 products the row above (same-day top-up session) already reviewed and deliberately excluded as out-of-scope per `docs/llm-extraction-rules.md` §5 and this file's own Scope section — since their `taxonomy_id` is intentionally left NULL, they reappear in any live "no taxonomy_id" re-query; this is not a new coverage gap, it's the expected residual of a documented scope decision. No SKU block claimed (no rows to write — claiming one would only burn it). QA gates re-verified live (no `--skip-coexistence`): G1 dual-mapped=0, G2 HUMAN+LLM coexistence=0, G5 provenance=0, placeholder-leak=13 (unchanged — pre-existing "Multiple Variants" entries from before the 2026-07-22 rule change, `targeted_qa_fix.sh` territory, not this session's scope). GMV coverage reconfirmed 95.82% (unchanged from the prior session's 95.8%). | No writes made — status quo confirmed correct. Recommend the wrapper's live pre-check exclude products already reviewed-and-rejected as OOS (e.g. via a documented exclusion list or a `reviewed_oos` marker) so this same non-actionable residual doesn't keep triggering fresh top-up dispatches. |

---

## Map Row Counts (as of this session's end)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 314 | 174 Pass 1 + 140 Pass 2, this session |
| HUMAN | 508 | Pre-existing keyword-seed stubs — untouched; 87 of these duplicate a product now also LLM-mapped and are eligible for wrapper-side deletion per policy |
| NULL (unmapped) | ~5,600 | Includes long-tail resellers below this session's GMV-impact cutoff and likely-out-of-scope TCM/tonic listings — candidates for a future NULL-coverage pass, not a defect in this run |
