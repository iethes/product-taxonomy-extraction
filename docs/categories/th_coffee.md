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
