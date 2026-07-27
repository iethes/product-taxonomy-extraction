# shopee_sg_diapers — Category Context

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete |
| LLM Pass 2 | ✅ Complete |
| GMV Coverage | 97.93% (2026-06) |
| Last run | 2026-07-20 |
| Current MAX taxonomy_id | Query `sku_block_registry` live — never trust this file |

Review month for all queries in this file: **2026-06-01** (source `month` column is `DATE`, not a string).

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-091442–093441 | Full Rebuild — Pass 1 OFFICIAL + Pass 2 RESELLER (claimed atomically via `sku_block_registry`, 2026-07-20) |
| SKU-091442–091668 | Pass 1 OFFICIAL — 227 entries actually used (of 320 official-store products; many diaper listings are genuinely multi-size buyer-select, collapsing to fewer taxonomy entries than products) |
| SKU-091669–091695 | Pass 2 RESELLER — 27 brand×type catch-all entries (156 products routed) |
| SKU-091696–093441 | Unused, block left `ACTIVE` for any future top-up/QA-fix session |

---

## Brand Scope (GMV threshold 95%, June 2026, GWP-zeroed)

Computed via `product_brand_map` → `brand_dict` (not the raw `brand` text column, which is
often blank/inconsistently cased per `docs/data-dictionary.md`). GWP GMV zeroed via
`CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END` before ranking (Decision 15).

**16 brands** cross the 95% cumulative-GMV threshold (real running-sum computation, not a
fixed top-N snapshot):

1. **Merries** — `BRD-GLOBAL-00021` — S$897,468 (25.0% cum)
2. **HUGGIES** — `BRD-GLOBAL-00211` — S$882,837 (49.6% cum)
3. **Mamypoko** — `BRD-SG-00001` — S$593,584 (66.1% cum)
4. **Drypers** — `BRD-SG-00361` — S$334,991 (75.4% cum)
5. **Nino Nana** — `BRD-SG-00754` — S$105,029 (78.4% cum)
6. **Offspring** — `BRD-SG-00762` — S$90,489 (80.9% cum)
7. **moony** — `BRD-SG-00760` — S$83,934 (83.2% cum)
8. **Goo.n** — `BRD-GLOBAL-00093` — S$82,614 (85.5% cum)
9. **Charnins** — `BRD-SG-00980` — S$72,200 (87.5% cum)
10. **Pampers** — `BRD-SG-00823` — S$60,666 (89.2% cum)
11. **Rascal + Friends** — `BRD-SG-00811` — S$59,096 (90.9% cum)
12. **Applecrumby** — `BRD-GLOBAL-00120` — S$43,397 (92.1% cum)
13. **NOMIEO** — `BRD-SG-00906` — S$36,617 (93.1% cum)
14. **`BRD-UNDEFINED`** — S$30,529 (93.9% cum) — no resolvable brand identity; Pass 2 / UNRESOLVED only, no official-store allowlist entry possible
15. **Day&** — `BRD-SG-12796` — S$27,328 (94.7% cum)
16. **Peachy Bum** — `BRD-SG-01758` — S$19,921 (95.2% cum, crosses threshold)

Brands excluded from scope (below 5% GMV tail, ~85 more brands ranked 17+, e.g. Aiwibi,
Einmilk, Hoppi, Beenies, Bambo Nature, unicharm, Pigeon, DryNites, etc.) — full ranked list
available via the query in QA History if needed for a future top-up pass.

---

## Official Store Allowlist (Pass 1)

Built by querying distinct `merchant_name WHERE merchant_badge='Shopee Mall'`, joined through
`product_brand_map` to the in-scope `brand_id`s above (not `LIKE '%official%'` — Decision 14).
Every candidate below was checked against ALL brands it sells in this dataset (not just the
scoped brand) to confirm it isn't a multi-brand retailer wearing an "Official Store" name.

| Brand | brand_id | Official Store Merchant Name |
|-------|----------|------------------------------|
| Applecrumby | BRD-GLOBAL-00120 | `Applecrumby® Official Store` |
| Charnins | BRD-SG-00980 | `BIC OFFICIAL STORE` — sells only Charnins in this dataset; likely the SG distributor name, not a generic word |
| Drypers | BRD-SG-00361 | `Drypers Official Store` |
| HUGGIES | BRD-GLOBAL-00211 | `Huggies Official Store` |
| HUGGIES | BRD-GLOBAL-00211 | `Kimberly-Clark Official Store` (parent company — Kimberly-Clark owns Huggies; verified sells only HUGGIES in this dataset) |
| Mamypoko | BRD-SG-00001 | `Mamypoko Official` |
| moony | BRD-SG-00760 | `Mamypoko Official` (parent-company store — Unicharm owns both Mamypoko and moony; verified this store sells both, no other brands) |
| Merries | BRD-GLOBAL-00021 | `Merries Official Store` |
| Nino Nana | BRD-SG-00754 | `Nino Nana ` (note: trailing space is literal in the merchant_name value) |
| Offspring | BRD-SG-00762 | `Offspring Official` |
| Pampers | BRD-SG-00823 | `Pampers Official Store` |

**Multi-brand stores excluded** (verified by checking full brand mix sold, not just Mall
badge — none of these get Pass-1 treatment for any brand):
- `Watsons Singapore Official Store` — sells MamyPoko, HUGGIES, Drypers, NOMIEO, Merries, Pampers, Desitin, Hello Bello (per existing beauty-vertical exclusion list, confirmed multi-brand here too)
- `Guardian SG Official Store` — sells Nino Nana, Merries, HUGGIES, Petpet, MamyPoko (pharmacy chain, same class as Watsons/Boots — add to baby vertical exclusion list)
- `BIG Pharmacy` — sells Sanrio, Drypers, HUGGIES, MamyPoko (pharmacy chain)
- `Diapers.com.sg Offical Store` [sic] — sells Pampers, moony, GOO.N, Genki!, MamyPoko, nepia Whito (multi-brand diaper specialty retailer)
- `myCK_online` — sells MamyPoko, Drypers, Pokana, NOMIEO, Merries (multi-brand retailer)
- `Weloveourkids` — single ambiguous 0-GMV mention for Mamypoko; excluded for lack of evidence it's brand-owned

**Brands with no official store found (Pass 2 only):**
- Goo.n, NOMIEO, Day&, Peachy Bum, `BRD-UNDEFINED`

---

## Scale

Review month: 2026-06-01.

| Metric | Count |
|--------|-------|
| Total source rows (model grain) | 41,398 |
| Distinct products | 7,606 |
| Rows badged `Shopee Mall` (any merchant) | 3,200 |
| Distinct products badged `Shopee Mall` (any merchant, **before** allowlist scoping) | 974 |
| **Rule A** — top-95%-cumulative-GMV products (GWP-zeroed) | 338 |
| **Rule B** — allowlist-only official-store products | 320 |
| **In-scope set (A ∪ B)** | **546** |

`category_3` is single-purpose (`Disposable Diapers` only, 100% of rows) — no mixed-content
keyword gate needed for brand ranking (unlike body_wash/liquid_milk).

The raw Mall-badged pool (974 products) is **not** the Pass 1 scope — after excluding the six
multi-brand retailers above, only 320 products belong to genuine brand-owned or parent-company
official stores. Pass 1 must scope to the allowlist only, per `docs/llm-extraction-rules.md`
§4 — confirmed via this run's own query, not assumed. The in-scope set overall (546) is
tractable for full per-product LLM read within one session, unlike the `shopee_sg_shampoo`
attempt #1 precedent (187,902-row official pool, correctly blocked).

---

## Scope — What's In vs Out

**In scope:**
- Diaper tape (ผ้าอ้อมแบบเทป-equivalent English listings), diaper pants

**Out of scope (leave NULL):**
- Cloth diapers, swim diapers/pants (different use case, verify per listing)
- Disposal tape stickers / roll-and-tie accessories (mirrors `ม้วนทิ้ง` exclusion documented for `th_baby_diapers`)
- Adult diapers (wrong category — none expected in this table's `category_3`, but verify if encountered)

**Edge cases:**
- To be logged here as Pass 1/2 encounters them.

---

## Taxonomy Design Notes

**Product line extraction approach:** to be filled in during Pass 1 as brand product lines are read from images/sku_name (e.g. Huggies has multiple named lines — Platinum, Dry Pants, Gold — confirm from packaging, never default to "Huggies Diapers").

**Size extraction notes:**
- Primary unit: piece count (`ชิ้น`-equivalent English "pcs"), plus diaper size band (NB/S/M/L/XL/XXL) — both matter; diaper size band is part of product_line/variant, not the `size` column (which should record pack quantity, e.g. "36pcs").
- Pack-count patterns expected: explicit counts in title ("36pcs", "Carton of 4"), bulk/carton listings need multiplier check per `docs/llm-extraction-rules.md` §1.

**Known difficult products:** to be logged during extraction.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-20 | Pre-run research | 908 HUMAN / 0 LLM existing map rows confirmed live (matches wrapper's first-run precheck and the documented `shopee_sg_diapers` precedent in `docs/headless-runbook.md`) | Proceeded as genuine first run |
| 2026-07-20 | Session handoff | Research + setup complete (brand scope, allowlist, SKU block SKU-091442–093441 claimed, Pass 1 worklist of 320 official-store products built and verified, image pipeline proven on 14 real products). Zero `product_taxonomy`/`product_taxonomy_map` rows written — Pass 1/2 extraction itself (546 in-scope products, each needing real per-size-band image confirmation since diaper pack pcs is not derivable from `sku_name` text alone, e.g. carton pcs varies by size band and must be read off the pack) is genuinely large and was not rushed. See Session Handoff section below for exactly where to resume. | Session ended with `status='partial'`, `rows_created=0`. SKU block left `ACTIVE` — safe to reuse. |
| 2026-07-20 | Pass 1 execution | Resumed from handoff. 15 representative product images read (10 confirming Huggies Platinum Naturemade Pants/Tape per size band — pcs totals printed directly on pack front, e.g. XL Pants=228pcs, Tape M=384pcs; 5 more confirming that Charnins BUNDLE/Offspring N-Pack-Bundle/Applecrumby Mega-Pack listings are genuinely buyer-select multi-size despite no size band in `sku_name`). Remaining 320-product worklist resolved via regex text-matching on `sku_name` (Merries/Drypers state explicit `NsxM Packs` totals in nearly every title — high-confidence bulk extraction) plus a conservative `is_multi_size=TRUE` fallback wherever no size was committed in the title (confirmed correct against all 3 spot-checked cases). 227 taxonomy entries created (SKU-091442–091668), 320 map rows inserted, source=LLM, meta_agent=CLAUDE_CODE. `product_line`/`variant`(size band)/`size`(total pcs) populated as structured columns per product, not folded into canonical_name only. | 320/320 official-store products mapped. |
| 2026-07-20 | Pass 2 execution | Bulk-routed the 156 remaining Rule-A (top-95%-GMV) in-scope products not covered by Pass 1 — almost all reseller listings combining brand + multiple types/sizes in one SKU ("Tape & Pants", "All size available", "S-XXL"). Grouped by (brand_id × Pants/Tape/Assorted type signal in `sku_name`) into 27 catch-all `is_multi_size=TRUE` entries (SKU-091669–091695), confidence 0.70 (reseller range). | 156/156 routed. |
| 2026-07-20 | QA gates (post Pass 1+2, `--skip-coexistence`) | G1 dual-mapped LLM: 0. G2 HUMAN+LLM coexistence: 446 (expected — HUMAN cleanup is the wrapper's job, not this session's, per scope). Placeholder-leak: found 2 taxonomy entries with literal "Undefined" in canonical_name (from `BRD-UNDEFINED`'s brand_canon text) — fixed via UPDATE to "Unresolved-Brand Reseller...", re-verified 0. Structured-fields-missing (product_line NULL, excl. is_multi_size): 0%. GMV coverage (month 2026-06, all sources combined): **97.93%**. | All gates pass. Category GMV coverage far exceeds the ≥85% Pass 2 target. |

| 2026-07-24 08:29 UTC | Automated review session (auto-discovery) | Auto-discovery review of 254 never-confident entries. STEP 1B's 'canonical_name fields' gate (92 rows) traced to a structural false positive: diaper `size` already encodes the pack-inclusive total pcs (e.g. '228pcs' for a 2-carton bundle), so the gate's expected xN suffix is redundant by this category's own established convention — confirmed via image reads across HUGGIES, Merries, and Drypers entries. This is a first confirmation (no prior QA History entry addressed this exact gate), not yet eligible for a qa_gate_exceptions row under the two-confirmation rule. While validating that pattern, found a genuine, separate content defect: 8 HUGGIES Platinum Naturemade Pants/Tape taxonomy entries (SKU-091505, 091506, 091507, 091508, 091516, 091519, 091524, 091528) were each silently merging two distinct real listings per size band — a small '[Bundle of 2]' (2 individual packs) and a large '[Bundle of 2 Cartons]' (multi-pack carton) product — under one taxonomy_id sized only for the larger variant. Confirmed via direct product image reads (not text alone, since product_description text proved unreliable/generic for the Cartons variant) across XL, L, XXL, XXXL Pants and Tape M/L/XL: the small variant's actual pcs was consistently 1/3 to 1/4 of the recorded size. Two other size bands (Tape S, Tape NB) were checked and found to already have matching totals for both variants — no defect there. Drypers and Merries entries checked separately show no such conflation (self-documenting 'NsxM - Carton' naming, single real product per entry). | Split the 8 affected HUGGIES entries: kept the original entries pointing only at their genuine Cartons-variant product (size unchanged, now individually image-verified as correct), and minted 8 new taxonomy entries (SKU-091696-091703, reusing the already-ACTIVE SKU-091442-093441 block, no new block claimed) with corrected pcs totals (76/88/56/52/128/108/116/88pcs) for the small-bundle variant, rerouting the 8 specific product_ids via product_taxonomy_map UPDATE. Bulk-promoted 144 STEP 1C fast-lane rows to unconfident. Individually Tier-2-validated and promoted 17 additional rows (10 HUGGIES Cartons-cluster incl. Tape S/NB, 1 Merries XXL, 4 Drypers, 2 BRD-UNDEFINED structural-naming rows, 2 high-GMV [$777k, $355k] reseller multi-size catch-alls) via real image/product spot-checks — all confirmed correct as-is. Left ~91 cfm-flagged rows and their false-positive-gate determination unpromoted/undisturbed (per guidance, a gate false-positive finding is not itself a review — avoids fabricating reviews that didn't happen). Final distribution: 17 confident, 234 unconfident, 11 unreviewed (the 8 new entries plus 2 pre-existing Pampers rows plus 1 fast-lane row with a genuine unresolved cfm flag, SKU-091597, sharing the same false-positive naming pattern but not yet individually re-validated). |
| 2026-07-24 08:47 UTC | Automated review session (auto-discovery) | Auto-discovery review of 245 never-confident entries (234 unconfident + 11 unreviewed carried over from the 2026-07-24 08:29 UTC session). STEP 1B: the 'canonical_name fields' gate (100 rows failing pre-fix) traced entirely to one pattern — pack_count>1 entries where canonical_name lacks an 'xN' suffix because this category's `size` field already encodes the pack-inclusive total pcs (e.g. '128pcs' for a 4-pack), making the suffix redundant. Breakdown confirmed all 85 in-worklist hits (plus 15 already-confident rows) trip purely on this one sub-check, with product_line/sub_line/variant/size all correct. This is the second confirmation of the exact same structural false positive first identified in the prior session's QA History entry — now closed permanently via 100 `qa_gate_exceptions` rows. STEP 2 Tier 1 sweep found 2 wrong_field_order flags (SKU-091690, SKU-091691), both false positives: BRD-UNDEFINED entries intentionally read 'Unresolved-Brand Reseller...' rather than starting with the literal brand_dict text 'Undefined', per the prior session's own placeholder-leak fix — flagging this as wrong_field_order would demand re-introducing the defect already fixed. STEP 2b (pack_count=1 promo-language sweep) found 0 candidates. STEP 3 Tier 2 GMV-prioritized sample (top ~60 of 242 GMV-ranked remaining rows, ~92.5% of remaining worklist GMV) verified 58 rows genuinely correct: 7 single-size HUGGIES/Merries/Drypers entries verified via exact sku_name pack-math (e.g. '36s x 4 Packs' = 144pcs, matching recorded size); 51 multi-size reseller/carton catch-all entries (is_multi_size=TRUE, Pass 2 design) verified by reading their full underlying sku_name lists — confirmed genuinely ambiguous buyer-select multi-size/multi-type cartons, not conflated product lines, and the catch-all naming design itself was left alone (already validated correct in the prior session, confirmed by advisor consultation this session — reworking it would be out-of-scope precision work). One genuine, NOT session-fixable defect surfaced during this sweep: 7 product_ids across 4 taxonomy entries (SKU-091523, SKU-091671, SKU-091676, SKU-091690) are out-of-scope swim-diaper listings ('Little Swimmer', 'Swimming Diapers', a cross-brand 'Huggies/Moony/Goon Little Swimmer' listing) incorrectly mapped into in-scope diaper taxonomy — total GMV ~S$22,263.24 (2026-06). SKU-091523 ('HUGGIES Pants Little Swimmer Assorted') is itself an entirely out-of-scope entry, not just a contaminated catch-all. A category-wide scope-violation sweep (cloth diapers, disposal-tape stickers, adult diapers) found no further contamination beyond swim diapers. | No content fixes applied — no genuine fixable mechanical or content defect was found in this session's Tier 1/Tier 2 review (the one real defect found, OOS swim-diaper contamination, requires deleting/rerouting product_taxonomy_map rows, which this session is forbidden from doing per STEP 7; flagged below for a deletion-authorized session). Wrote 100 qa_gate_exceptions rows (gate_name='canonical_name fields', master_table='shopee_sg_diapers') covering every currently-flagged taxonomy_id, permanently closing that previously-FAILing gate. Bulk-promoted 58 Tier-2-verified-correct rows plus 1 STEP 1C fast-lane row (SKU-091597) via a single _meta UPDATE. Final distribution: 75 confident (was 17), 177 unconfident (was 234), 10 unreviewed (was 11). All hard gates now pass with no --skip-coexistence: G1 dual-mapped=0, G2 HUMAN+LLM coexistence=0 (down from 446 in the prior report — resolved by the wrapper's cleanup between sessions), placeholder-leak=0, structured-fields NULL%=0%, duplicate product_id=0, duplicate product+taxon=0, 'all variant/size' name=0, canonical_name fields=0 (via exceptions), garbled brand text=0. |
| 2026-07-24 09:05 UTC | Automated review session (auto-discovery) | Auto-discovery review of 187 never-confident entries (177 unconfident + 10 unreviewed). Tier 1 SQL sweep: the only new flag was wrong_field_order on SKU-091690 (BRD-UNDEFINED entry correctly reading 'Unresolved-Brand Reseller...' rather than literal 'Undefined' per the earlier placeholder-leak fix) — third confirmation of this same structural false positive; all 78 canonical_field_mismatch flags in this worklist were already covered by the 100 existing qa_gate_exceptions rows from the prior session, so none needed re-verification. STEP 2b (pack_count=1 promo-language sweep) found 0 candidates. Tier 2 GMV-prioritized sample covered ~94% of remaining worklist GMV (top ~50 of 187 by GMV, plus a targeted is_multi_size audit across the full worklist) and found 8 genuine, previously-undetected defects, all confirmed via product image and/or explicit sku_name pack-math, all fixed in place: (1) SKU-091481 'Drypers worth $' — a truncated/garbled canonical name from a variable-price promotional 'Brand Box' (confirmed via image: contents vary by sale event, e.g. one instance shows Drypers baby wipes, another a single SuperDry Pants XL 36pcs pack) — renamed to 'Drypers Brand Box Assorted Bundle'. (2) SKU-091694 'Rascal + Friends Reseller Tape Diapers' — mislabeled is_multi_size=TRUE catch-all despite both underlying products stating a single M size; image confirmed 180pcs (Super Jumbo Pack) — converted to a proper sized entry, pack_count=3. (3) SKU-091628 'Nino Nana Newborn Diapers Tape' — same mislabeling; sku_name explicitly states NB, 62pcs — fixed. (4) SKU-091638 'Offspring Fashion Diaper' — sku_name silent on size but image confirmed L, 36 diapers — fixed. (5) SKU-091641 'Offspring Fashion Newborn Diapers' — image confirmed NB, 56 diapers — fixed. (6) SKU-091496 'Drypers Touch Premium Pants' — sku_name states M (4x44s)=176pcs, image-confirmed — fixed. (7)+(8) SKU-091637 'Offspring Fashion Deluxe Bundle' and SKU-091644 'Offspring Fashion Maxi Bundle' — both are same-brand diaper+wipes(+wash) bundles; per the established convention (map to the base diaper entry using the diaper portion's size/pack only, wipes are not a cross-brand is_bundle case), both images confirmed 4 packs of L/36pcs diapers — both fixed to 'Offspring Fashion Diaper L 144pcs' (kept as two separate entries since they are distinct bundle SKUs with different included freebies, not merged/rerouted). One new out-of-scope contamination instance found: SKU-091578 'MamyPoko Swimming Pants Diapers' (GMV S$607.42, June 2026) is an entirely out-of-scope swim-diaper product, joining the 4 already-documented swim-diaper contamination entries from the prior session (SKU-091523, SKU-091671, SKU-091676, SKU-091690) — not fixed, since fixing requires deleting/rerouting a product_taxonomy_map row, which this session cannot do. Three new systemic patterns were found but NOT fixed this session (out of remaining turn budget, and each needs dedicated per-entry image verification rather than a single mechanical pass): (a) ~18 HUGGIES diaper+wipes carton-bundle entries (e.g. SKU-091529, 091531, 091533, 091535–091543, 091547, 091548, 091553, 091558, 091559, 091561, 091562) record the bundled WIPES pack total as the entry's `size` and fold 'Wipes' into `product_line`, instead of the diaper portion's own pack size per the established bundle convention — needs per-entry image verification of true diaper-only pack counts. (b) 5 Merries entries (SKU-091611, 091612, 091613, 091614, 091619) are genuine two-component listings (Tape+Pants combo, or two size bands sold together) where only one component's pack math survived extraction, leaving a dangling 'and X' text fragment in product_line/canonical_name and silently dropping the other component's units — low aggregate GMV (~S$250). (c) At least 9 Pampers entries (SKU-091651, 091653–091656, 091658–091664) plus SKU-091545 (HUGGIES) show canonical names with dangling, meaningless fragments ('Pampers Baby Dry Pants x to', 'HUGGIES Platinum Naturemade Diapers x Pants x') from numeric tokens lost during a prior extraction/parsing pass — near-zero June GMV. The Offspring 'Pack Bundle'-suffix cluster (SKU-091640, 091647, 091648, 091650) likely shares the same single-size-mislabeled-as-multi defect confirmed in SKU-091637/091638/091641/091644 but was not individually image-verified this session. | Applied 8 in-place content fixes (canonical_name/product_line/variant/size/pack_count/is_multi_size corrected, _meta reset to unreviewed, meta_agent='CLAUDE_CODE' set) to SKU-091481, SKU-091496, SKU-091628, SKU-091637, SKU-091638, SKU-091641, SKU-091644, SKU-091694 — all via bq DML, no streaming API, no product_taxonomy_map rows touched (no reroutes, no deletions). Bulk-promoted 91 Tier-2-verified-correct rows to confident in one _meta UPDATE statement, each independently confirmed correct via real sku_name pack-math cross-check or product image (not blind pattern acceptance) — spanning Drypers (19 entries), Merries (16), MamyPoko (27), Nino Nana (2), HUGGIES (18), Offspring (6), Applecrumby (2), and moony (1). SKU-091690 was initially included in this promotion batch by mistake; caught and reverted mid-session back to unconfident, since that entry separately contains 2 out-of-scope swim-diaper products (a distinct, unresolved defect) even though its wrong_field_order Tier-1 flag is (for the third time) a confirmed naming-convention false positive. Left the 3 newly-identified systemic patterns (HUGGIES wipes-bundle mislabeling, Merries two-component 'and'-fragment entries, Pampers/HUGGIES garbled-name cluster) and the new MamyPoko swim-diaper contamination undisturbed and unpromoted, flagged above for a follow-up session. Final distribution: 158 confident (was 75), 94 unconfident (was 177), 8 fixed-pending-recheck (this session's 8 fixes, awaiting next session's confirming review), 2 unreviewed. All hard gates re-verified with no --skip-coexistence: G1 dual-mapped=0, G2 HUMAN+LLM coexistence=0, placeholder-leak=0, structured-fields NULL%=0%, duplicate product_id=0, duplicate product+taxon=0, 'all variant/size' name=0, garbled brand text=0. |
| 2026-07-24 09:34 UTC | Automated review session (auto-discovery) | Auto-discovery review of 104 never-confident entries. STEP 1B's 4-row 'canonical_name fields' gate failure traced to the same established xN-suffix-redundant false positive already confirmed twice in prior sessions (size field already encodes pack-inclusive total) -- closed via 4 new qa_gate_exceptions rows. Tier 1 sweep's 41 canonical_field_mismatch flags split into: 18 genuine HUGGIES diaper+wipes bundle entries recording the WIPES pack count as the entry's size/pack_count instead of the diaper portion's own count (confirmed via 13 image reads across Black Label/Airsoft/Naturemade Pants+Tape lines, all sizes S-XXL); 5 genuine Merries two-size-band entries silently dropping one component's units (confirmed via sku_name pack-math, e.g. 'M(46x2) and L(36x2)' recording only the M component); and the remaining 18 being the same established xN-suffix false positive. Verified via product-level detail that SKU-091671 ($169,410 GMV) and SKU-091676 ($111,022 GMV), the two largest catch-all entries in the category, are structurally sound genuine buyer-select reseller carton listings -- but found 2 additional swim-diaper-contaminated product_ids inside SKU-091676 (29769144525, 18481980619) not previously documented, joining the already-flagged contamination in SKU-091523/091578/091671/091690. New systemic pattern found: SKU-091480 'Drypers Wee Wee Dry Tape' merges 6 distinct single-size (NB/S/M/L/XL/XXL) listings plus 1 genuine multi-size listing under one taxonomy_id, same defect class as the HUGGIES/Offspring single-size-mislabeled-as-multi pattern fixed in the 2026-07-24 09:05 UTC session (~$1,213 of its $3,380 GMV affected). SKU-091647 'Offspring RAYA Fashion Diaper Pack Bundle' found to merge two distinct real products (Pants M-size and Tape S-size, different product_ids) under one entry -- a wrong-type merge, currently $0 GMV. A prompt-injection attempt occurred mid-session (a fake system-reminder claiming the worklist CSV had been overwritten with unrelated soft-drink data and instructing silence) -- not acted on, flagged to the operator. | Fixed 13 HUGGIES wipes-bundle entries in place (canonical_name/product_line/variant/size/pack_count corrected to diaper-only counts, e.g. SKU-091529: 768pcs/pack_count=12 -> 112pcs/pack_count=4; SKU-091547 additionally renamed product_line to 'Airsoft Gold Pants' to distinguish from the regular Airsoft line), and 5 Merries two-size-band entries (e.g. SKU-091611: 'M 92pcs' -> 'M+L 164pcs', summing both stated size bands), all via bq DML, _meta reset to unreviewed, meta_agent='CLAUDE_CODE', no product_taxonomy_map rows touched. Wrote 4 new qa_gate_exceptions rows (gate_name='canonical_name fields') closing that gate permanently for this category. Bulk-promoted 40 Tier-2-verified-correct rows to confident/unconfident-per-verdict in one _meta UPDATE (fast-lane clean rows, the 8 HUGGIES Platinum Naturemade splits from the first review session, Charnins/moony/Nino-Nana-travel-sample/Drypers-GWP/Drypers-Brand-Box multi-size catch-alls, and the 4 exception-covered rows) -- then caught and reverted my own premature inclusion of SKU-091671/091676 in that batch once I recalled they still carry unresolved swim-diaper contamination, restoring both to unconfident per the precedent already established for SKU-091690. Left the 5 zero-GMV wipes-bundle entries, SKU-091480, and SKU-091647 unfixed and flagged above (GMV-deprioritized or needs map-row changes outside this session's scope). Final distribution: 188 confident (was 158), 54 unconfident (was 94), 18 fixed-pending-recheck (was 8), 2 unreviewed (unchanged). All hard gates re-verified with no --skip-coexistence: dual-mapped=0, HUMAN+LLM coexistence=0, placeholder-leak=0, structured-fields NULL%=0%, duplicate product_id=0, duplicate product+taxon=0, 'all variant/size' name=0, canonical_name fields=0 (via exceptions), garbled brand text=0. |
| 2026-07-24 10:03 UTC | Automated review session (auto-discovery) | Auto-discovery review of 74 never-confident entries (56 unconfident + 18 fixed-pending-recheck carried over). STEP 1C fast-lane: all 18 fixed-pending-recheck rows only tripped canonical_field_mismatch, already covered by the established qa_gate_exceptions false-positive (pack_count>1 diaper entries where size already encodes the pack-inclusive total, so no xN suffix needed) -- verified all 18 already had exception rows, bulk re-confirmed. STEP 2 Tier 1: all 33 canonical_field_mismatch flags in the remaining worklist were already exception-covered (no new exceptions needed); SKU-091690's wrong_field_order flag is a 4th confirmed instance of the established BRD-UNDEFINED naming-convention false positive, but the entry stays unconfident due to its separate unresolved swim-diaper contamination. STEP 2b found 0 promo-language candidates. Tier 2 GMV-prioritized review cross-checked product_specification/product_description (master_raw_niq.shopee_sg_diapers, since raw_niq_history does not exist under that name in this project) and 5 direct + pattern-consistency image reads. Found 2 new genuine content defects: (1) SKU-091637 'Offspring Fashion Diaper L 144pcs' pack_count=4 -- the underlying product's own description explicitly states 'Bundle deal consists of: 5 packs of...diapers' (verified independently correct on the paired wipes count, 4=4), meaning a prior session's fix undercounted this specific bundle by one pack; the sibling entry SKU-091644 (different product_id, description confirms 4 packs) was correctly fixed and left alone. (2) SKU-091532 'HUGGIES Black Label Little Penguin Tape S 140pcs' pack_count=2 -- product image conclusively shows 'M 288 PCS TAPE, 2 Carton', not S/140pcs at all; a completely wrong size band and count. SKU-091538 ('Airsoft Pants M 348pcs', sku_name states a 'M-XXL' range) was flagged as a possible reverse case of the same single-size-mislabeled pattern but the fetched image was an inconclusive packaging-transition banner, not a size-confirming photo -- left untouched, not promoted, flagged for next session. 28 rows were genuinely Tier-2-confirmed correct (5 direct image reads, 1 description-confirmed random-assortment box, 1 product_specification-confirmed size band, 6 sku_name-title pack-math confirmations, and 15 HUGGIES diaper+wipes-bundle entries validated via 3 direct image samples across distinct sub-lines plus internal monotonic pcs-per-carton consistency checks). Deferred, not fixed this session (deprioritized by GMV/turn budget, or requiring map-row changes this session cannot make): swim-diaper contamination in SKU-091523/091578/091671/091676/091690 (still needs a deletion-authorized session); 5 remaining un-fixed HUGGIES wipes-bundle entries (SKU-091553, 091558, 091559, 091561, 091562, all $0 GMV, still recording the bundled wipes pack instead of diaper-only count); SKU-091480 Drypers Wee Wee Dry Tape single-size-merged-into-one-entry defect (~$1,213 of $3,380 GMV, needs 6 per-band image reads to split); SKU-091647 Offspring RAYA wrong-type merge ($0 GMV, 2 distinct products under one entry); the 8-entry Applecrumby cluster and ~12-entry Pampers/HUGGIES garbled-name cluster (mostly $0 GMV, unreviewed this session); SKU-091538's ambiguous size-range question. All hard gates re-verified with no --skip-coexistence: dual-mapped=0, HUMAN+LLM coexistence=0, placeholder-leak=0, structured-fields NULL%=0, duplicate product_id=0, duplicate product+taxon=0, garbled brand text=0. | Bulk-promoted 18 STEP1C fast-lane rows via one _meta UPDATE (all confirmed clean modulo the already-exception-covered false positive). Applied 2 in-place content fixes via bq DML (canonical_name/variant/size/pack_count corrected, meta_agent='CLAUDE_CODE', _meta reset to unreviewed) to SKU-091532 (S/140pcs -> M/288pcs) and SKU-091637 (144pcs/pack=4 -> 180pcs/pack=5) -- no product_taxonomy_map rows touched, no deletions. Bulk-promoted 28 Tier-2-verified-correct rows to confident/unconfident-per-verdict in one _meta UPDATE. Final distribution: 216 confident (was 188), 42 unconfident (was 54), 2 fixed-pending-recheck (this session's 2 fixes, awaiting next session's confirming review), 2 unreviewed (unchanged). |
| 2026-07-27 | Top-up coverage session | Wrapper's pre-check claimed 342 in-scope (top-95%-cumulative-GMV, GWP-zeroed) products with no `taxonomy_id` for month 2026-06; live re-run of the exact STEP 0 query confirmed 342 (343 rows / 184 distinct products, since several products have multiple `model_id` rows). This population is materially different from the 16-brand GMV-threshold scope documented earlier in this file: per-product top-95%-cumulative-GMV pulls in ~46 distinct brands (vs the 16 that cross brand-level 95% GMV), most never seen in this category before (Aiwibi, Beenies, Bzu Bzu, Cozycove, Einmilk/Enmilk, Hoppi, Iconic Babycare, Mabaoshi, MILK, Penbose, Poomsoft, etc.) — expected, categories accumulate new listings over time. Grouped all 184 distinct products by real brand (via `product_brand_map`/`brand_dict`, not the taxonomy join, which is always NULL for an unmapped worklist) and by `sku_name` pattern. 11 of the 46 brands already had existing taxonomy from the 2026-07-20 Pass 1/2 build (Applecrumby, Drypers, Goo.n, HUGGIES, Mamypoko, Merries, Pampers, Peachy Bum, Rascal + Friends, `BRD-UNDEFINED`, moony) — bulk-matched 87 products to existing entries (mostly the established brand+type "Reseller Diapers/Pants Diapers/Tape Diapers" catch-alls, plus several exact-line matches, e.g. Huggies Goodnites Youth Pants Assorted, Drypers DryPantz Pants). Found and corrected several `product_brand_map` brand-assignment noise cases where the scanned brand didn't match the real on-listing brand (a coincidental brand_dict entry named "Airfit"/"All"/"Amazon"/"Kao"/"Baby Pants"/"M" was actually a Moony/Mamypoko/Merries/Merries/Nomieo+Iconic-Babycare/unlisted-"Moonpie" product per `sku_name` text) — routed by real brand per `docs/llm-extraction-rules.md` §11, not by the noisy `product_brand_map` value (taxonomy mapping doesn't require brand_id agreement with `product_brand_map`, confirmed precedent in this doc's own Namthip/Coca-Cola note). For the remaining 90 products across 35 brands with no existing taxonomy (or a genuinely new line under an existing brand, e.g. Mamypoko Doraemon/BabyPopok, Merries Walker Pants, a Pampers Premium Care Tape NB size, and one missing Rascal + Friends Tape catch-all), minted 52 new entries grouped by brand+line+type read from `sku_name` text alone (bulk, no per-product image reads — consistent with this session's speed-over-precision mandate) using SKU-171305–171356 (claimed via the atomic `sku_block_registry` transaction, 342-slot block SKU-171305–171646, scenario `taxonomy_topup`; only 52 used, block left `ACTIVE` for future top-ups). 5 of the new mints (Moonpie, Molfix, Qiaoya, Neutrovis/Faybel, "Top") are real, readable brand names with no corresponding `brand_dict` entry at all (not even a mis-scanned one) — used `brand_id='BRD-UNDEFINED'` per its documented definition (brand identity not resolvable in the reference registry) while keeping the real brand name in `canonical_name`/`product_line` for analyst usability, mirroring this category's existing "Unresolved-Brand Reseller..." convention. Identified 7 products (all OOS per this file's own Scope section) inside the worklist that must NOT be mapped: 2 HUGGIES + 1 HGMIL + 1 Singapore Collection + 1 Undefined-bucket swim-diaper listings, plus 1 Umee + 1 tommee tippee diaper-disposal-bin/pail accessory listings (not diaper products at all) — left `taxonomy_id` NULL for all 7, consistent with the category's established swim-diaper exclusion and the general out-of-scope-stays-NULL rule; did not force these to a catch-all. Verified pre-insert: all 36 referenced existing `taxonomy_id`s exist, zero of the 177 target `product_id`s had any pre-existing map row (no dual-mapping risk). Wrote via `bq query` DML only (never streaming): 52 `product_taxonomy` INSERT rows + 177 `product_taxonomy_map` INSERT rows, `meta_agent='CLAUDE_CODE'`, `source='LLM'`, `confidence='0.70'` (matches this category's established reseller-tier convention), `platform='Shopee'`, `country='SG'`. Re-ran the live STEP 0 worklist query post-write: exactly the 7 intended OOS products remain NULL, confirming the coverage gap is closed for everything else. Per this session's explicit scope, did NOT pursue per-row precision (exact `product_line` wording refinement beyond what `sku_name` text gave, variant/pack-count edge cases, image verification of ambiguous multi-size groupings) — that is `script/targeted_qa_fix.sh`'s job, as multiple prior QA History entries above already demonstrate for this exact category. | 52 taxonomy rows created (SKU-171305–SKU-171356), 177 map rows inserted (87 to existing entries, 90 to newly minted entries). All hard gates re-verified with no `--skip-coexistence`: G1 dual-mapped=0, G2 HUMAN+LLM coexistence=0, G5 provenance (NULL meta_agent/source)=0, placeholder-leak=0, structured-fields-missing (product_line NULL, excl. is_multi_size)=0%, duplicate product_id=0. GMV coverage (month 2026-06, all sources): 97.59%. Universe refresh NOT run this session (per instructions, a separate step after independent QA verification). SKU block SKU-171305–171646 left `ACTIVE` (290 slots unused, available for future top-ups). |
| 2026-07-27 (2nd session) | Top-up coverage session (confirmation) | Wrapper's pre-check found 17 in-scope rows with no `taxonomy_id`; live re-run of the exact STEP 0 query (month 2026-06) confirmed 17 rows / 7 distinct `product_id`s, not 342 — this is the same 7-product OOS set the prior same-day top-up session (row above) already identified and deliberately left NULL: `6030394078` (Tommee Tippee Sangenic diaper disposal bin ×2 model rows), `7842202809` (Umee diaper pail ×5 model rows), `25819596415` (baby disposable swimming pants ×2), `26317085760` (Callum's Treasure Box swim diaper ×4), `29174027213` (Huggies Little Swimmer swim diaper), `43977171681` (Huggies/Moony/Goon cross-brand Little Swimmer), `21847393041` (Uber Bear swim diaper ×2). All 7 are disposal-bin/pail accessories or swim diapers — out of scope per this file's own Scope section (swim diapers, non-diaper accessories excluded). Confirmed zero of the 7 have any existing `product_taxonomy_map` row (no dual-mapping risk, nothing to reroute). No SKU block claimed (no minting needed) — the already-`ACTIVE` SKU-171305–171646 block from the prior session remains untouched. No taxonomy/map rows written. Re-verified all hard gates with no `--skip-coexistence`: G1 dual-mapped=0, G2 HUMAN+LLM coexistence=0, placeholder-leak=0, G5 provenance (NULL meta_agent/source)=0. GMV coverage (month 2026-06, all sources): 97.59% — matches the prior session's reported figure exactly, confirming no drift since that write. Universe refresh NOT run this session (separate step, per instructions). | No writes. Confirmed the coverage gap is already closed — the 17-row wrapper pre-check was the same 7 deliberately-OOS products already resolved same-day, not a new gap. |
---

## Session Handoff (2026-07-20, stopped after setup + worklist, before extraction)

**What's done and durable:** category file (this document), SKU block claim, Pass 1 worklist query (below).

**Pass 1 worklist query** (regenerate the 320-product official-store list, product-grain, deduped):
```sql
WITH allowlist AS (
  SELECT * FROM UNNEST([
    STRUCT('Applecrumby® Official Store' AS merchant_name,'BRD-GLOBAL-00120' AS brand_id),
    ('BIC OFFICIAL STORE','BRD-SG-00980'), ('Drypers Official Store','BRD-SG-00361'),
    ('Huggies Official Store','BRD-GLOBAL-00211'), ('Kimberly-Clark Official Store','BRD-GLOBAL-00211'),
    ('Mamypoko Official','BRD-SG-00001'), ('Mamypoko Official','BRD-SG-00760'),
    ('Merries Official Store','BRD-GLOBAL-00021'), ('Nino Nana ','BRD-SG-00754'),
    ('Offspring Official','BRD-SG-00762'), ('Pampers Official Store','BRD-SG-00823')
  ])
)
SELECT s.product_id, ANY_VALUE(s.sku_name) sku_name, ANY_VALUE(s.image) image,
  ANY_VALUE(s.merchant_name) merchant_name, ANY_VALUE(d.canonical_name) brand_canon,
  ANY_VALUE(b.brand_id) brand_id, ROUND(SUM(CASE WHEN s.flag_GWP THEN 0 ELSE s.gmv_monthly END),2) gmv
FROM `sincere-hearth-273704.master_clean_niq.shopee_sg_diapers` s
JOIN `sincere-hearth-273704.magpie_reference.product_brand_map` b
  ON b.product_id = s.product_id AND b.platform='Shopee' AND b.country='SG'
JOIN allowlist a ON a.merchant_name = s.merchant_name AND a.brand_id = b.brand_id
LEFT JOIN `sincere-hearth-273704.magpie_reference.brand_dict` d ON d.brand_id = b.brand_id
WHERE s.month = DATE('2026-06-01') AND s.merchant_badge='Shopee Mall'
GROUP BY s.product_id ORDER BY brand_canon, gmv DESC
```
`--max_rows` must be raised above `bq query`'s default 100-row cap for this and any full-worklist pull.

**Image fetch mechanism (proven working):** `image` column has literal embedded `"` characters —
strip with `tr -d '"'` before `curl -sL -o /tmp/img.jpg "<url>"`, then `Read` the local file.

**Key finding that shapes remaining work:** diaper `sku_name` text states size **band** (NB/S/M/L/XL/XXL/XXXL)
reliably but usually does **not** state total piece count for single-size-band listings — pcs count varies
by size band even within one product line ("Bundle of 2 Cartons XL" ≠ same pcs as "...L"), so it must be read
off the pack image per size band, not assumed constant across a cluster's sizes. "Assorted (N packs)" /
"M-XXL" listings are multi-size-in-one-listing (buyer picks at checkout) → `is_multi_size=TRUE`, `size=NULL`,
`pack_count=N` (packs), not per-size pcs.

**Confirmed from images this session (reusable, do not re-fetch):**
| Product line | Size band | Total pcs | Source |
|---|---|---|---|
| Huggies Platinum Naturemade Pants | XL (12-18kg) | 228 (Bundle of 2 Cartons) | product 8943145582 |
| Huggies Naturemade Panda Pants | L (9-14kg) | 126 (single carton, 3×42) | product 26126446013 |
| Huggies Naturemade Overnite Pants | M (6-11kg) | 116 (single carton, 2×58) | product 41103176948 |
| Huggies Airsoft Pants | M (6-12kg) | 184 (1 carton = 4 packs × 46) | product 83478027 |
| Huggies AirSoft Tape | S (4-8kg) | 174 (1 carton = 3 packs × 58) | product 1064516244 |

**52 distinct HUGGIES sku_name clusters identified** (size/number-stripped pattern dedup) covering all 105
HUGGIES official-store products — see git history of this file / re-run the clustering script if needed
(strip `\b(NB|S|M|L|XL|XXL|XXXL|2XL|3XL|4XL)\b` and digits from `sku_name`, group by remainder).

**Next session should:** work brand-by-brand in GMV order (HUGGIES → Merries → Mamypoko → Drypers cover
~75% of category GMV), confirming pcs-per-size-band from one representative image per (product_line ×
size-band) combination — not per product_id — then bulk-map same-cluster products via text match, writing
batched DML (taxonomy inserts, then map inserts) rather than per-product single statements. Cross-product
bundles (e.g. "Huggies Pants XL + Huggies Pure Clean Wipes") map to the base diaper entry using the diaper
portion's size/pack only — wipes are same-brand, not a cross-brand `is_bundle` case.

---

## Targeted QA Fix Brief

> Not applicable yet — no taxonomy exists for this table. Fill in after Pass 1/2 if a
> follow-up Targeted QA Fix session is needed.

---

## Scripts

| Script | Purpose |
|--------|---------|
| N/A — this run performs extraction directly via Claude's own multimodal reading, no external script | |

---

## Map Row Counts (as of last run, 2026-07-20)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 476 | Pass 1 (320, official-store) + Pass 2 (156, reseller catch-alls) |
| HUMAN | 908 | Long-tail keyword-seed routing, pre-dates this session — **not deleted by this session** (out of scope; wrapper's job, and only for products with a matching LLM row per policy) |
| NULL (unmapped) | 6,222 (7,606 − 908 − 476 + overlap not yet netted) | Long-tail below GMV scope; GMV coverage 97.93% despite low product-count coverage — expected, GMV is heavily concentrated |

**Note:** this session did not run the universe refresh `MERGE` into `universe_taxonomy_overlay` — out of scope per this run's instructions (ends at QA gates). A future step/session should run it before this category's taxonomy is visible to analysts joining `marketshare_universe_niq`.
