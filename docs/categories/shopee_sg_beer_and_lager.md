# shopee_sg_beer_and_lager — Category Context

> Generated during headless Full Rebuild session, 2026-07-22.

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ⏳ In progress (this session) |
| LLM Pass 2 | ⏳ In progress (this session) |
| GMV Coverage | TBD — measured after this session |
| Last run | 2026-07-22 |
| Current MAX taxonomy_id | SKU-110395 (live, pre-session) |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| (assigned in Step 3 of this session — see session findings) | Full Rebuild (Pass 1 + Pass 2) |

---

## Brand Scope (GMV threshold 95%, month 2026-06)

Computed from `master_clean_niq.shopee_sg_beer_and_lager`, `month = '2026-06-01'`, GWP-zeroed
(`CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END`), aggregated to product level, joined to
`product_brand_map` (`platform='Shopee', country='SG'`) → `brand_dict.canonical_name`, ranked by
GMV descending with a running cumulative-GMV fraction. Total category GMV (month): **SGD 935,567.02**
across 324 distinct brand buckets (including `BRD-UNDEFINED` and unmatched/NULL brand rows).

**29 brands** reach the 95% cumulative-GMV threshold (cutoff at rank 29, `Bavaria Beer`, cum. 95.01%).
This is the full real threshold, not a fixed-size snapshot — the tail (ranks 30–324) accounts for the
remaining ~5% of GMV and is excluded from scope.

| Rank | Brand | brand_id | GMV (SGD) | Cum. % |
|---|---|---|---|---|
| 1 | Carlsberg | BRD-SG-00402 | 337,696.36 | 36.10% |
| 2 | Sapporo | BRD-GLOBAL-01222 | 91,408.54 | 45.87% |
| 3 | Guinness | BRD-GLOBAL-01211 | 75,377.22 | 53.92% |
| 4 | Heineken | BRD-GLOBAL-00871 | 62,061.44 | 60.56% |
| 5 | Yebisu | BRD-SG-01772 | 31,621.86 | 63.94% |
| 6 | Suntory | BRD-GLOBAL-01032 | 31,167.65 | 67.27% |
| 7 | Asa-Hi | BRD-TH-02704 | 30,341.00 | 70.51% |
| 8 | Kronenbourg 1664 | BRD-SG-01122 | 27,964.37 | 73.50% |
| 9 | TIGER | BRD-SG-08104 | 25,905.62 | 76.27% |
| 10 | *(unmatched — no `product_brand_map` row)* | BRD-UNDEFINED | 25,344.33 | 78.98% |
| 11 | TUBORG | BRD-SG-01893 | 22,284.01 | 81.36% |
| 12 | Anchor | BRD-SG-02557 | 19,887.74 | 83.49% |
| 13 | SKOL | BRD-SG-02221 | 14,990.59 | 85.09% |
| 14 | Somersby | BRD-SG-01881 | 11,494.29 | 86.32% |
| 15 | Cass | BRD-SG-02587 | 9,965.20 | 87.38% |
| 16 | Danish Royal Stout | BRD-SG-02403 | 9,468.60 | 88.39% |
| 17 | Hoegaarden | BRD-SG-02319 | 8,904.11 | 89.35% |
| 18 | Snow Beer | BRD-SG-02223 | 7,346.95 | 90.13% |
| 19 | Corona Extra | BRD-SG-02530 | 7,097.28 | 90.89% |
| 20 | KIRIN ICHIBAN | BRD-SG-02606 | 7,049.52 | 91.64% |
| 21 | Paulaner | BRD-SG-02626 | 4,823.91 | 92.16% |
| 22 | Connor's Stout Porter | BRD-SG-02460 | 4,173.00 | 92.60% |
| 23 | Singha | BRD-GLOBAL-00047 | 3,820.80 | 93.01% |
| 24 | Pure Blonde | BRD-SG-02468 | 3,788.40 | 93.42% |
| 25 | Erdinger | BRD-SG-02188 | 3,719.24 | 93.81% |
| 26 | Tsingtao | BRD-SG-03703 | 3,256.36 | 94.16% |
| 27 | Maximus | BRD-GLOBAL-01036 | 2,838.00 | 94.47% |
| 28 | ANGLIA | BRD-SG-01681 | 2,532.00 | 94.74% |
| 29 | Bavaria Beer | BRD-SG-02568 | 2,512.00 | 95.01% |

**Row 10 caveat:** `BRD-UNDEFINED` at rank 10 (SGD 25,344.33) is products with no `product_brand_map`
row joinable at all (not the same as `brand_dict`'s literal "Undefined" canonical entry, which separately
appears at rank 33 outside the 95% cutoff). These products still get extracted like any other in-scope
product — the LLM reads `brand_from_image` directly per `docs/llm-extraction-rules.md` §7 — they just have
no brand-owned official store to query for a Pass 1 allowlist, so route via Pass 2 text/image matching only.

Brands excluded from scope (tail, ranks 30–324, ~5% of GMV): Budweiser, MUG, Kirei, Terra, Estrella,
Brooklyn, Leo, Hite, Weihenstephaner, San Miguel, KINGFISHER, Little Creatures, HiteJinro, Wusu, and ~285
smaller/long-tail brands. One tail entry of note: `12/+＝` (BRD-SG-08876, rank 58) — a known garbage brand
from a prior seller-watermark misread (see `llm-extraction-rules.md` §11, product `7155345414`); it is
below the 95% cutoff regardless, so it requires no special handling this session.

---

## Official Store Allowlist (Pass 1)

Built by querying distinct `merchant_name WHERE merchant_badge='Shopee Mall'` per in-scope `brand_id`
(month 2026-06-01), then checking each candidate merchant's full brand portfolio within this table to
distinguish a genuine brand/parent-company store from a multi-brand distributor or general retailer.

**Included (brand-owned or single-corporate-family stores):**

| Brand(s) covered | brand_id(s) | Official Store Merchant Name | Basis |
|---|---|---|---|
| Carlsberg, Connor's Stout Porter, Danish Royal Stout, Kronenbourg 1664, SKOL, Somersby, TUBORG | BRD-SG-00402, BRD-SG-02460, BRD-SG-02403, BRD-SG-01122, BRD-SG-02221, BRD-SG-01881, BRD-SG-01893 | `Carlsberg Beer Official Store` | Parent-company store — Carlsberg Group owns all 7 brands globally (Unilever/Lion-style pattern) |
| Sapporo, Yebisu | BRD-GLOBAL-01222, BRD-SG-01772 | `Sake Inn Official Store` | Both brands are owned by Sapporo Holdings; store carries only these two — treated as parent-company store, not a general multi-brand importer |
| Suntory | BRD-GLOBAL-01032 | `Suntory Global Spirits` | Single-brand — Suntory's own global spirits/beer division storefront |

Pass 1 in-scope row count from these 3 stores: **44 rows / 43 distinct products** (month 2026-06-01).

**Multi-brand stores excluded** (confirmed via full brand-portfolio check within this table — regardless of
Mall badge, per `docs/llm-extraction-rules.md` §4):

| Merchant Name | Distinct brands carried (sample) | Why excluded |
|---|---|---|
| `Pacific Beverages Official Store` | 17 brands: Estrella Galicia, MAELOC, James Squire, James Boag's, Franziskaner, Stella Artois, Hoegaarden, Tooheys, ... | Multi-brand craft/import beverage distributor |
| `RedMan Official Store` | 11 brands: BRUT, Hoegaarden, Bavaria, TUBORG, SWEET, Mort Subite, Leffe, ... (spans multiple unrelated brewers — AB InBev, Carlsberg, independents) | Multi-brand beer importer/distributor, not a single owner's portfolio |
| `DON DON DONKI Official Store` | 8 brands: Kirin, Suntory Horoyoi, Suntory, Asa-Hi, Coca-Cola, ... | General multi-category discount retail chain (SG equivalent of BigC/Lotuss) |
| `Kirei – Japan's Finest` | 7 brands: Suntory, Echigo, TAKARA, ASEED ASTER, Kirin, Kirei, Sapporo | Multi-brand Japanese beverage importer |
| `K-Market by Koryo Trading` | 5 brands: Jinro, KookSoonDang, Gs Retail Youus, LOTTE, Cass | Multi-brand Korean goods distributor |
| `Lubritrade Distribution Official` | 4 brands: Cass, Haywards 5000, Kwirk Beer Co., Dester | Multi-brand distributor |
| `Prestigio Delights Official` | 2 brands: Corona Extra, Bundaberg (unrelated companies — AB InBev vs. Bundaberg Brewed Drinks) | Multi-brand reseller |

**Brands in scope with no official store** (skip Pass 1, go directly to Pass 2 per §4): Guinness, Heineken,
TIGER, Anchor, Hoegaarden (its only Mall presence is via the excluded Pacific Beverages/RedMan
distributors), Snow Beer, Corona Extra, KIRIN ICHIBAN, Paulaner, Singha, Pure Blonde, Erdinger, Tsingtao,
Maximus, ANGLIA, Bavaria Beer, Cass (only via excluded K-Market/Lubritrade), and the unmatched-brand
(`BRD-UNDEFINED`) bucket. Verified TIGER, Heineken, and Anchor (all Asia Pacific Breweries/Heineken-family
brands, high GMV rank) have **zero** `Shopee Mall` rows in this table at all — confirmed via direct query,
not an allowlist omission.

---

## Scale

- Total rows (month 2026-06-01): 5,072
- Distinct products (month 2026-06-01): 4,037
- `Shopee Mall`-badged rows (all merchants, before allowlist filtering): 602 rows / 489 distinct products —
  **not** the Pass 1 scope; most of this pool belongs to the excluded multi-brand distributors above.
- Official Store Allowlist rows (actual Pass 1 scope): 44 rows / 43 distinct products — small, no
  further scoping needed.
- All-time source table row count (all months): 167,678 rows.
- Category composition: `category_3_EN` is `Beer & Cider` (160,028 rows) and `Alcohol - Beer & Cider`
  (7,650 rows) — single coherent vertical, no evidence of mixed unrelated content (spot-checked 15 random
  `sku_name`s, all genuine beer/cider/chu-hai products). No brand-ranking keyword pre-filter was needed.

---

## Existing map rows (Step 1, live-queried 2026-07-22)

| Source | Count |
|--------|-------|
| HUMAN | 463 |
| LLM | 0 |

Consistent with a genuine first LLM pass — no prior Phase 5 run has touched this table.

---

## Scope — What's In vs Out

**In scope:** beer, lager, cider, chu-hai (flavored malt/spirit-based canned beverages sold under
Suntory Horoyoi and similar lines appear in this table's `sku_name`s) — anything genuinely a
beer/cider/malt beverage product per the source category's own `Beer & Cider` / `Alcohol - Beer & Cider`
classification.

**Out of scope (leave NULL):** products that are not beer/cider despite appearing in this table due to
NIQ mislabeling (to be identified per-product during extraction, not via a pre-filter) — e.g. wine,
spirits, or unrelated grocery items a multi-brand Mall seller might cross-list.

**Edge cases:** none identified yet — to be filled in during extraction per
`docs/quality-standards.md`'s review process.

---

## Taxonomy Design Notes

**Product line extraction approach:**
- Brand-owned stores (Carlsberg, Sake Inn, Suntory Global Spirits): read product line directly from
  image/sku_name per brand.
- All other brands: Pass 2 bulk text-matching against Pass-1-built taxonomy, image reads reserved for
  ambiguous cases.

**Size extraction notes:**
- Primary unit: ml (bottles/cans), L (kegs/growlers if present).
- Pack-count patterns common in this category: `x{N}`, `[N Bottles]`, `{N} Cans`, `[1 Carton]`,
  "24 bottles x 330ml" style explicit total statements — apply §1 priority chain (sku_name → image →
  spec → description), image is tiebreaker for pack count per universal rule.

**Known difficult products:** none catalogued yet — to be filled in during extraction.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-22 | Category file generation | Real 95% GMV threshold is 29 brands (not a fixed top-15/20 snapshot) | Full 29-brand list documented above |
| 2026-07-22 | Automated Targeted QA Fix (auto-discovery) | Reviewed 181 never-reviewed/unconfident `product_taxonomy` entries mapped to this table. Tier 1 SQL sweep flagged 50: 30 legacy generic-stub catch-alls (SKU-002810–002839, e.g. "Carlsberg Lager / Green Label / Smooth (all variants)"), 1 brand_id literally leaked into canonical_name ("BRD-SG-04283 620ml x12" instead of "Wusu"), 7 brand_dict brands stored ALL-CAPS/mangled (TUBORG, ANGLIA, KIRIN ICHIBAN, KINGFISHER, TIGER, SKOL, "Asa-Hi") inconsistent with sibling brands. Tier 2 GMV-prioritized + full-worklist brand cross-check surfaced a bigger issue: systematic cross-brand contamination from the prior Full Rebuild's Pass 2 bulk text-matching — 16 products (Kronenbourg 1664 Brut/Blanc, Connor's Stout Porter, Carlsberg 0.0 Pilsner/Wheat/Special Brew/Smooth Draught, SKOL Lager/Strong, Jolly Shandy) routed to wrong-brand or wrong-product-line taxonomy entries (e.g. Connor's Stout Porter product mapped under "Carlsberg Danish Pilsner Pint"; 2 of 3 products under "Somersby Shandy 320ml x24" were actually SKOL). Also found 2 Somersby Ninja-Slushi-promo bundle entries with pack_count=72 when the sku_name consistently states "Pack of 24" (72 was a fabricated multiplier), and one dual-mapped product (49950884767, HUMAN row → SKU-002820 + LLM row → SKU-112610) whose title changed over time between a Somersby- and Carlsberg-themed promo — confirmed via most-recent-month data that the real current content is the Carlsberg Jersey/Duffel-bag bundle. | Bulk-renamed all 30 catch-all stubs (stripped "(all variant(s)/flavor(s)[, and pack sizes])" suffix, set `product_line=NULL` + `is_multi_variant=is_multi_size=TRUE` instead of the banned generic-text pattern). Fixed the brand_id-leak canonical_name via REPLACE. Normalized the 7 brand_dict casing/spelling defects (global fix, safe text-only, no brand_id/FK changes). Rerouted all 16 contaminated products to their correct existing taxonomy entries; minted 2 new entries (SKU-117006 Jolly Shandy Lemon Beer 320ml x24, SKU-117007 Carlsberg Smooth Draught Pint 325ml x48 — block SKU-117006–117205 claimed for `targeted_qa_fix`) where no correct existing entry existed. Corrected the 2 mispacked Somersby bundle entries from x72 to x24. Reworded SKU-112610 to drop the unsupported "Football Edition" claim. Reassigned SKU-112729 from brand_id HiteJinro to the correct Hite brand_dict entry (sku_name says "Hite", not "HiteJinro") and renamed canonical_name to match. Left the SKU-002820/SKU-112610 dual-map (G2 violation, pre-existing from the Full Rebuild's incomplete HUMAN-row cleanup) unresolved — this session's brief explicitly forbids row deletion, and the standard remedy (delete the stale HUMAN row) belongs to the Full Rebuild's own step 5, not a Targeted QA Fix pass. Confidence left behind: 52 entries promoted unreviewed→unconfident (first-ever review, correct verdict — needs one more agreeing review to reach confident), 2 new entries confident, 30 fixed catch-alls + 19 casing-affected + 9 contamination-affected entries reset to unreviewed for fresh re-check next session, 140 entries untouched (out of this session's sampled scope). Hard gates: G1=0 ✅, G2=196 ❌ (pre-existing HUMAN+LLM coexistence, not introduced this session, needs the Full Rebuild HUMAN-cleanup step), placeholder-leak=0 ✅ (was 30 before this session), G5 provenance=0 ✅. |
| 2026-07-22 | Automated Targeted QA Fix (auto-discovery), 2nd pass | Worklist of 192 never-reviewed/unconfident entries (the prior session's own fixed-and-reset rows, re-entering scope). Tier 1 SQL sweep this time flagged only residual defects the prior pass's fix left half-done: the 30 catch-all entries (SKU-002810–002839) had `product_line` correctly nulled last session but `sub_line` still carried ungrounded generic descriptor text never reflected in `canonical_name` (e.g. `sub_line="Lager / Danish"` on SKU-002810, `"Stout / Irish"` on SKU-002811) — same ungrounded-stub defect class as the banned "(all variants)" text, just hiding in a different column. 5 of the casing-normalized brands (Tiger, Tuborg, Skol, Anglia, Kirin Ichiban) had `brand_dict` fixed last session but the ALL-CAPS text was never propagated into the `canonical_name` strings on SKU-002817/002819/002822/002825/002833 themselves. SKU-112610's `canonical_name` had its "Football Edition" claim stripped last session but `product_line` still read "Danish Pilsner Football Edition & Smooth Draught Bundle" — same stale-claim leftover in a different field. Went beyond the prescribed Tier 1/2b checklist to bulk-verify all 162 non-catch-all worklist entries via grouped sku_name-vs-canonical_name text comparison (the bulk-first method `docs/headless-runbook.md` sanctions for Pass 2), which surfaced two more defect classes: (1) SKU-112606 "Carlsberg Danish Pilsner Football Edition 320ml x24" (GMV 303,301.62, 2nd-highest in worklist) had only 1 of its 11 mapped products genuinely Football Edition — 10 were plain Danish Pilsner/Lager Green Tab listings (contamination from the same bulk-text-match root cause the prior session already diagnosed, just a different SKU it hadn't reached), including 2 "(10 Cartons)" Malaysia-import listings actually worth 240 units each, not 24, and 1 mislabeled Carlsberg Smooth Draught listing. (2) A systemic "(N Cartons)"/"(Bundle of N Cartons)" pack-count-multiplier miss: sku_name explicitly states a carton multiplier (e.g. "Bundle of 2 Cartons", "(5 Carton)") that was never applied to `pack_count`, confirmed on 8 products across Tiger Lager 320ml (x48/x72/x120), Asahi Super Dry 330ml (x48/x72), Carlsberg Danish Pilsner 320ml (x240), and Heineken Lager 320ml (a product with a sibling listing under the identical exact sku_name text already correctly routed to the x48 entry — proof the miss was inconsistent, not a genuine ambiguity). One additional ambiguous case found and deliberately left unresolved: SKU-112611 has 3 mapped products (combined GMV ~9,639) whose sku_name literally concatenates two different products' descriptions ("Tuborg Strong Lager Beer 490ml 24s can/ Danish Pilsner Green Label Beer Can, 24 x 320ml") — a genuine multi-brand buyer-choice listing per `docs/llm-extraction-rules.md`'s multi-brand-listing precedent, which calls for leaving it unmapped, but this session's no-deletion constraint (STEP 7) makes that remedy unavailable; left mapped to Tuborg (the first-named product) as the least-bad default, flagged here for a session empowered to unmap. Also verified against month-over-month `sku_name` history (per the Estrella Damm 12-pack and Somersby/Carlsberg precedents) that SKU-112606's sole genuine Football Edition product and the two Asahi 330ml carton-bundle products are still selling under their current titles as of 2026-06-01, not stale historical text. | Cleared the ungrounded `sub_line` text on all 30 catch-all entries (kept `is_multi_size`/`is_multi_variant`=TRUE, `product_line`/`sub_line` both NULL — the flag alone now carries the semantic, nothing restates it as text). Re-cased the brand token in `canonical_name` on the 5 affected entries to match the already-fixed `brand_dict` casing (mechanical `CONCAT`/`SUBSTR` replace, brand_id unchanged). Stripped "Football Edition" from SKU-112610's `product_line`. Claimed SKU block 117206–117405 (`targeted_qa_fix`) and minted 6 new entries: SKU-117206 Tiger Lager 320ml x48, SKU-117207 Tiger Lager 320ml x72, SKU-117208 Tiger Lager 320ml x120, SKU-117209 Asahi Super Dry 330ml x48, SKU-117210 Asahi Super Dry 330ml x72, SKU-117211 Carlsberg Danish Pilsner 320ml x240. Rerouted the LLM map row for 14 products to their correct entries: the 6 new SKUs above (8 products, 2 sharing SKU-117211), 1 Heineken product to the existing SKU-112651 (x48), 4 plain Carlsberg Danish Pilsner 320ml x24 products + 1 ambiguous multi-quantity-selector listing (approximated to the base-carton entry) to the existing SKU-116613, and 1 mislabeled Smooth Draught listing to the existing SKU-112608 — leaving SKU-112606 mapped only to its one genuine Football Edition product. Did NOT create new mappings for 4 other carton-multiplier misses found during the same sweep (2 Heineken, 1 Guinness Foreign Extra Stout, 1 Guinness Draught) — each has only a HUMAN catch-all mapping and no LLM row at all, making them coverage gaps rather than existing-row defects, out of scope for a Targeted QA Fix per `docs/headless-runbook.md`; flagged here for the category's next NULL-coverage/Full Rebuild pass. Reset `_meta` to unreviewed on all fixed/rerouted entries (30 catch-alls, SKU-112610, SKU-112606, SKU-112649, SKU-112743, SKU-112750, SKU-112608, SKU-116613, SKU-112651) plus the 6 new entries (seeded as reviewed/unconfident); bulk-promoted the other 153 worklist entries verified correct via the grouped text sweep (`review_confidence`: prior 'correct' verdict → confident, else → unconfident) in one statement. Left SKU-112611's multi-brand ambiguity and the G2 pre-existing coexistence unresolved, both for the reasons stated above. Confidence left behind: 153 entries promoted (mix of confident/unconfident depending on prior verdict), 6 new entries at unconfident, 39 entries (the fixed/rerouted set) reset to unreviewed for fresh re-check next session. Hard gates: G1=0 ✅, G2=196 ❌ (unchanged from prior session, still pre-existing, still belongs to Full Rebuild's HUMAN-cleanup step), placeholder-leak=0 ✅, G5 provenance=0 ✅. |
| 2026-07-23 | Top-up coverage session (live 95%-cumulative-GMV worklist, month 2026-06) | Re-ran the live worklist query rather than trusting the wrapper's pre-check number — confirmed 19 in-scope products (not 790; that figure belongs to a different category's session history and does not apply here) with `taxonomy_id IS NULL`. Bulk-first reuse-before-mint: grouped all 19 by brand via `product_brand_map`→`brand_dict` (the STEP 0 query's own `pt.brand_id`-derived `brand` column is NULL for every unmapped worklist row, by construction — had to re-join separately) and matched sku_name brand+line+size+pack text against this category's existing taxonomy (scoped to `master_table='shopee_sg_beer_and_lager'` only, to avoid the cross-brand/cross-category contamination pattern documented in the two prior QA sessions above). 10 of 19 matched an existing entry exactly on brand+size+pack and were mapped directly — including 2 cases where the sku_name's own wording ("Heineken Pint 325ml x24", "Carlsberg Smooth Draught 24x325ml") looked like it might need a new "Pint"-variant entry, but a product-image check (the only 4 images read this session, reserved for genuinely ambiguous text per STEP 1(c)) confirmed both are the same product as the existing plain "Heineken Lager 325ml x24" (SKU-112652) and "Carlsberg Smooth Draught Pint 325ml x24" (SKU-112645) entries respectively — avoided minting 2 unnecessary duplicate SKUs. The other 2 image checks confirmed a genuine new flavor ("Hoegaarden Peach", printed as "peach" on the can — distinct from the existing "Hoegaarden Rosee" entry, which is a different label string per the on-pack-text rule in `docs/llm-extraction-rules.md` §3) and a genuine pack-count ("Guinness Foreign Extra Stout... Bundle of 12" confirmed as 12-count via the pack photo, not the existing 24-count entry). One worklist product (Budweiser, product `11017251552`) belongs to a brand outside this category's documented 29-brand Pass-1-allowlist scope list, but is genuinely a beer product within the live per-product 95%-cumulative-GMV scope (quality-standards.md §2 Rule A is per-product, not per-brand) — mapped it to the existing `SKU-112717` Budweiser entry rather than leaving it NULL, per STEP 1(c)'s instruction that the brand-ranking keyword gate must never be used to decide whether an individual in-scope product gets extracted. | Claimed SKU block 141043–141242 (`taxonomy_topup`). Minted 9 new entries for products with no existing brand+size+pack match: SKU-141043 Hoegaarden Peach 500ml x12, SKU-141044 Sapporo Premium 500ml x6, SKU-141045 Kronenbourg 1664 Blanc Wheat Beer 320ml x4, SKU-141046 Guinness Foreign Extra Stout 320ml x12, SKU-141047 Carlsberg Smooth Draught 320ml x12, SKU-141048 Connor's Stout Porter 490ml x4, SKU-141049 Corona Extra 330ml x48 (mapped to the existing `BRD-SG-02530` "Corona Extra" brand_id used by this category's other Corona Extra entries, not the `BRD-SG-03056` "Corona" id `product_brand_map` returned for this product — same brand-fragmentation pattern documented in `docs/llm-extraction-rules.md`'s Namthip/Coca-Cola precedent, taxonomy mapping doesn't require brand_id agreement with `product_brand_map`), SKU-141050 Bavaria Beer Original 330ml x24 (distinct from the existing 500ml x24 entry — sku_name explicitly states 330ml, text wins per size rule), SKU-141051 Hoegaarden White Beer 500ml x12 (distinct from both the existing 330ml x24 "White Beer" and 500ml x24 "Wheat Beer" entries — this size+pack combination didn't exist yet). Mapped all 19 products (10 to existing SKUs, 9 to the new ones), `source='LLM'`, `meta_agent='CLAUDE_CODE'`, `platform='Shopee'`, `country='SG'` on every row. Self-check (STEP 5, exact `run_qa_gates` queries, no `--skip-coexistence`): G1 dual-mapped=0 ✅, G2 HUMAN+LLM coexistence=0 ✅ (better than the ~196 this category's own prior QA History sessions recorded as pre-existing and unresolved — appears to have been fixed by a session between 2026-07-22 and this one; none of the 19 products this session touched had a pre-existing HUMAN row, confirmed directly), placeholder-leak=0 ✅, structured-fields-missing=12% (well under the 50% gate threshold) ✅. `run_qa_gates` itself doesn't check G4/G5, so verified both by hand per this session's own read of the gate script: G5 provenance (`meta_agent`/`source` NULL)=0 ✅ on both new taxonomy rows and new map rows; G4 cross-category — queried every map row for all 10 reused SKUs across the whole `product_taxonomy_map` table (not just this category), confirmed 100% of them (63 rows) are `master_table='shopee_sg_beer_and_lager'`, no cross-category contamination introduced. Universe refresh NOT run this session (out of scope per the prompt — a separate step after independent QA verification). |

---

## Targeted QA Fix Brief

Not applicable — this is a first-run Full Rebuild session, not a Targeted QA Fix.

---

## Scripts

| Script | Purpose |
|--------|---------|
| N/A | This session performs extraction directly via Claude's own multimodal reading, not external scripts. |

---

## Map Row Counts (as of last run)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | TBD | Populated after this session's Pass 1 + Pass 2 |
| HUMAN | 463 (pre-session) | Long-tail out-of-scope products (retained) |
| NULL (unmapped) | TBD | Below GMV scope or out-of-category |
