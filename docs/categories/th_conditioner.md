# shopee_th_conditioner — Category Context

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete |
| LLM Pass 2 | ✅ Complete |
| GMV Coverage | ~80% (Apr 2026); partial top-up 2026-07-27 for Jun 2026 (see QA History — 943 of 3,093 live-gap products mapped, gap not fully closed) |
| Last run | Jun 21 2026 (full); 2026-07-27 (top-up, partial) |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-011088–011322 | Full taxonomy (235 entries, 29 brands) |
| SKU-172347–174346 (2,000 slots, claimed 2026-07-27, scenario `taxonomy_topup`) | SKU-172347–173196 used (850 entries) for the 2026-06 coverage top-up. SKU-173197–174346 unused, block remains ACTIVE. |

This category now owns **two disjoint SKU ranges** — a G4 check must treat both SKU-011088–011322 and SKU-172347–174346 as this category's own, not cross-category contamination.

---

## Brand Scope

30 official-store brands: Kérastase, Farger, L'Oreal Professionnel, Pantene/P&G, Lyo, The Ordinary, Nigao, Daeng Gi Meori, Dr.Pong, Dove/Unilever, L'Oreal Paris, Olaplex, Yves Rocher, Vichy, Yanhee, clear/Unilever, Divyne, Go Hair, Fino, My Organic, Lolane, TRESemmé, Herrmetto, Tsubaki, Sunsilk, &honey, Dcash, Shiseido, Nectapharma.

**&honey brand note:** TH products use BRD-SG-03756 (＆honey) in product_brand_map; taxonomy inserted under BRD-GLOBAL-00237. Both brand_ids should route to the same taxonomy entries.

**3 brand mismatches from Pass 1:** Hair+ official store sells Vichy, Pantene, and Ririko products — flagged brand_mismatch=TRUE for those.

---

## Scope Notes

Include: hair conditioner, hair mask/treatment, deep conditioning treatment, leave-in conditioner.
Exclude: shampoo (separate category), hair serum/oil (different sub-category).

---

## Map Row Counts (Jun 21 2026)

| Source | Count | Notes |
|--------|-------|-------|
| LLM/OFFICIAL | 722 | Pass 1 (725 products, 3 skipped for brand mismatch) |
| LLM/RESELLER | 1,184 | Pass 2 |
| HUMAN | 1,595 | Deleted (superseded) |

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-27 | Top-up coverage session, month 2026-06 | Live worklist (top-95%-cumulative-GMV, GWP-zeroed, `canonical_name IS NULL`) re-derived live rather than trusting the prompt's number: 4,359 model/variant-grain rows resolving to **3,093 distinct products** (~87.9M THB GMV) — the prompt's 4,354-count is model-grain and also subject to tie-order instability in the ungrouped `ORDER BY gmv_monthly DESC` window (no secondary sort key), confirmed by re-running the count query twice and getting 4,354 vs 4,359; added `, product_id` as a secondary sort key for this session's own re-derivation to make it reproducible. **Blocker found and worked around (not fixed):** 224 of the 3,093 products already had a `product_taxonomy_map` row (all `source='LLM'`, `meta_agent='CLAUDE_CODE'`) pointing at one of 44 distinct `taxonomy_id`s (mostly in the `SKU-000xxx`–`SKU-007xxx` "TH wave scripts" range) that **do not exist** in `product_taxonomy` at all — a pre-existing orphaned-FK defect, not introduced by this session and not something Step 3's "never delete a row" instruction permits fixing here. Excluded all 224 from every insert to avoid a G1 dual-mapping violation; flagged for a human/future session to investigate (candidates: a prior rebuild deleted those taxonomy rows without repointing the map rows). Applied `th_conditioner.md`'s own Scope Notes (conditioner/mask/treatment/leave-in IN; shampoo/serum/oil OUT) as a bulk multilingual keyword classifier (Thai + English), refined through three iterations after manually reviewing the top-60-GMV items across buckets (caught "Masque" — French spelling — and "คอนดิชันเนอร์" Thai transliteration being missed by an English-only first pass; also separated hair-loss tonics/serums, anti-dandruff/growth supplements, keratin-**straightening** kits, and heat-protectant sprays out from legitimate keratin **treatment/mask** creams, which share vocabulary but are different product types): 1,129 in-scope, 1,099 out-of-scope (shampoo/serum/oil/tonic/supplement), 862 left unclassified (ambiguous or no keyword signal) — the out-of-scope and unclassified buckets (1,961 products, ~$34.8M THB of the $87.9M gap) are left `NULL`/unresolved this session, not force-mapped; a text pre-filter was never used to decide extraction eligibility, every one of the 3,093 was considered, this is a genuine per-product type-gate judgment applied at bulk scale, not a shortcut. Bulk text-matched the 1,129 in-scope products against all 235 existing taxonomy entries for this category (not just the 151 reachable via a live map join — the extra 84 include entries like Kérastase Genesis whose Pass-1 products no longer have live map rows but the taxonomy entry itself is still valid) using brand-token + product-line-token containment plus size/pack-count regex extraction (Thai + English units, `sql/functions/parse_size.sql`'s pattern reused since the UDF itself isn't deployed live). **Two matcher bugs found and fixed before any DML ran:** (1) plain substring brand matching false-positived "Go Hair" onto "**Go**at Milk Extra Long**hair**" (word-boundary token matching required after); (2) an "allow one token missing" fuzzy-match tolerance let Olaplex "No.0" match the existing "No.3" entry (single-digit tokens were being dropped as insignificant, and a shared popular line name like Kérastase "Blond Absolu" could satisfy the threshold on its own while ignoring a differing sub-line) — switched to full-containment-only matching; a wrong reuse is worse than a new entry per `product-lifecycle.md` §4.3. Result: 38 products mapped directly to an existing entry, 10 more via 9 new same-brand-and-line entries at a previously-uncatalogued size/pack (e.g. GWP sample sizes), 77 via 72 new entries for a new line under an already-catalogued brand, 818 via 769 new entries for brands new to this category's taxonomy (brand resolved from `product_brand_map`, filtering out multi-brand-retailer false positives — Boots/Watsons/KONVY/Lush — as the brand signal per `llm-extraction-rules.md` §4's retailer-exclusion principle). 121 in-scope products left `UNRESOLVED` (no usable brand signal from either text match or `product_brand_map`) rather than guessed. `raw_niq_history` (documented in `ARCHITECTURE.md` as the `product_specification`/`product_description` size fallback) **does not exist as a dataset in this project** — confirmed via `bq ls` (572 datasets, several `*niq*` variants, none named exactly `raw_niq_history`) — a real doc/live discrepancy, flagged rather than chased; 258 of the 850 new entries have `size=NULL` as a result (title text genuinely had no stated size and the documented fallback source isn't reachable). `product_taxonomy_map.confidence` is `STRING` in the live schema, not `FLOAT64` as `ARCHITECTURE.md` documents — caught by an INSERT type error, fixed by quoting. The live schema also carries `platform`/`country` columns on `product_taxonomy_map` (populated `'Shopee'`/`'TH'` on every existing row) that this session's first insert draft omitted — caught before running, by inspecting existing rows first. Known precision gaps carried into `targeted_qa_fix.sh` scope, not fixed here per this session's coverage-over-precision mandate: heuristic product-line extraction retains some promotional noise; brand assignment for the 818 new-brand entries trusted `product_brand_map` without image verification (spot-checked one case, a Schwarzkopf product mapped under brand `Joico` — likely a pre-existing `product_brand_map` error, not introduced here); pack_count defaults to 1 where bundle language wasn't in the regex (e.g. "เซ็ท 3 ชิ้น" 3-piece sets). | 850 new taxonomy entries (SKU-172347–173196) + 943 new map rows, all `source='LLM'`, `meta_agent='CLAUDE_CODE'`, `platform='Shopee'`, `country='TH'`. Live gap dropped from 3,093 to 2,147 distinct products (~$63.0M THB remaining, includes the 224 orphaned-FK products and the 1,961 out-of-scope/unclassified products, neither of which this session's mapping could reduce). QA gates (no `--skip-coexistence`, per this category's prior full-ship status): G1 dual-mapped=0, G2 HUMAN+LLM coexistence=0, placeholder-leak=0, G5 provenance=0, structured-fields NULL% (distinct LLM entries, excl. `is_multi_size`)=0%. All brand_ids used were verified to exist in `brand_dict` before writing (250 distinct brand_ids, all valid) to avoid recreating the same class of orphaned-FK defect found in the blocker above. |
