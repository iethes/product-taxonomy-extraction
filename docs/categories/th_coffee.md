# shopee_th_coffee — Category Context

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete |
| LLM Pass 2 | ✅ Complete |
| GMV Coverage | 87.1% (Apr 2026) |
| Last run | Jun 21 2026 |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-008000–008649 | Full taxonomy (650 entries, 263 brands) |

---

## Brand Scope

16 brands in Pass 1 (official stores). 263 total brands in Pass 2.

Key brands: Nescafé, Doi Chaang, Wawee, Caffe Vergnano, Baraco, Dolce Gusto, Lavazza, Kaname, 711 Coffee, Singha Coffee (Siam Craft Coffee).

---

## Scope Notes

Coffee in Thailand covers: instant coffee sachets, RTD coffee beverages, ground coffee, whole bean coffee, coffee pods/capsules. NIQ category includes these mixed.

---

## Map Row Counts (Jun 21 2026)

| Source | Count | Notes |
|--------|-------|-------|
| LLM/OFFICIAL | 612 | Pass 1, 16 brands |
| LLM/RESELLER | 5,221 | Pass 2, 247 brands |
| HUMAN | 2,944 | Deleted (superseded) |

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-29 | Top-up coverage (bulk text-match) | Live `product_taxonomy_map` for this table had collapsed to 74 rows (all `source='LLM'`) vs. ~5,833 documented above — consistent with the pipeline-wide TH data-loss incident tracked separately (not investigated further per this session's scope; the 650-entry `product_taxonomy` dictionary block SKU-008000–008649 was confirmed fully intact and had zero orphaned map rows, so bulk reuse-before-mint against it was safe). Live 95%-cumulative-GMV worklist (month 2026-06) had 4,818 distinct products with no `taxonomy_id`. | Claimed SKU block SKU-195649–197648 (2,000 slots). Closed the gap via bulk SQL text-matching in tiers, never one row at a time: (1) 1,848 products whose `product_brand_map.brand_id` matched a brand with exactly one existing catch-all entry → direct reuse; (2) 922 products matched an existing multi-entry brand's specific line/size/variant via text scoring; (3) 122 products routed through a brand_dict alias table built from normalized-name matching (catches duplicate brand_ids for the same real brand, e.g. `Nescafe`/BRD-SG-00009 vs `NESCAFÉ`/BRD-GLOBAL-00032, `Doi Chaang`/BRD-SG-00929 vs `Doi Chaang Coffee`/BRD-SG-00412) — reused existing entries instead of minting duplicates; (4) 957 products across 89 brands with no existing coffee taxonomy entry (product_ct ≥ 3, brand name not a placeholder/garbage token) → minted one new catch-all entry per brand (SKU-195649–195737) in the established "{Brand} Coffee Product" / Assorted / `is_multi_variant=TRUE` style, then bulk-mapped; (5) 134 + 39 products with `BRD-UNDEFINED`/`BRD-UNBRANDED`/no brand-map row → resolved via direct brand-name (including one Thai-phonetic case, เนสกาแฟ→NESCAFÉ) text matching against the now-352-entry brand dictionary. Net: 4,022 new `product_taxonomy_map` rows (74→4,096, all LLM), 89 new taxonomy entries. 791 of the original 4,818 remain unmapped — long-tail products with no reliable brand/text signal (generic/unbranded sellers, e.g. detox/calcium/ginseng-mix coffee, or brand names only readable from images/typos this session's text-only pass couldn't catch) — left NULL rather than guessed; candidates for a future image-reading pass, triaged by GMV. QA gates G1/G2/G4/G5 all confirmed 0. |
| 2026-07-29 | Top-up coverage, 2nd pass (bulk group-mint) | Prompt referenced a nonexistent `docs/categories/shopee_th_coffee.md` — real file is this one (`th_coffee.md`); noted, not treated as a blocker. Re-ran the 95%-cumulative-GMV worklist live: 1,470 rows but only **791 distinct products** (worklist is grained by `(product_id, model_id)`; `product_taxonomy_map` has no `model_id` column) — exactly the 791 left unmapped by the prior session above. Pre-write checks: 0 orphaned map rows, 0 dual-mapped, 0 HUMAN/LLM coexistence, dictionary blocks (739 entries across SKU-008000–008649 + SKU-195649–195737) fully intact. | Claimed SKU block SKU-197859–199328 (1,470 slots; used SKU-197859–198255, 397 entries). Of the 791: 1 reused an existing single-entry brand (BRD-SG-00584 → SKU-008582 directly). The remaining 790 had either a resolved `brand_id` with zero or multiple existing category entries (avoided guessing which of a multi-entry brand's variants matched — "better a new entry than a wrong match" per `product-lifecycle.md` §4.3), or `BRD-UNDEFINED`/`BRD-UNBRANDED`/no brand-map row entirely (mostly small independent Thai coffee-bean roasters selling under their own shop name, e.g. โรงคั่วกาแฟป่าตึง, MAEKOK ROASTER, Sati Coffee Roaster — merchant name used as brand proxy after normalized-exact-match against the 37k-row `brand_dict` found only 9 safe hits; a broader substring match was tried and abandoned — too many false positives, e.g. "Roastery" matching brand "Aster" as a substring). Grouped all 790 by effective brand identity (398 groups total after folding in the 1 reuse), minted 169 new `brand_dict` rows (BRD-TH-07352–07520, merchant name as canonical_name) and 397 new `product_taxonomy` catch-all entries (same "{Brand} Coffee Product" / `is_multi_variant=TRUE` style as the prior session; `sub_line` assigned via keyword heuristic on `sku_name`, defaulting to "Whole Bean / Ground Coffee" which fits most of this residual set), then bulk-mapped all 791 products in one `INSERT...SELECT`. Net: +791 `product_taxonomy_map` rows (4,096→4,887, all LLM), +397 taxonomy entries, +169 brand_dict entries. Live worklist now 0 rows / 0 distinct products. Post-write QA gates (runbook's exact `run_qa_gates` queries, no `--skip-coexistence`) all confirmed 0: dual-mapped, HUMAN+LLM coexistence, placeholder-leak, orphaned map rows, cross-category (out-of-block) map rows, NULL `meta_agent`; structured-fields-missing 0%. Universe refresh intentionally not run (separate step per instructions). |
