# shopee_th_baby_diapers — Category Context

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete |
| LLM Pass 2 | ✅ Complete |
| GMV Coverage | 97.3% (Jun 2026, month-level product coverage; not the GWP-zeroed 95%-scope figure) |
| Last run | Jul 20 2026 (top-up coverage session) |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-005547–005884 | Full taxonomy (338 entries, 16 brands) |
| SKU-090951–091058 | Top-up coverage session, Jul 20 2026 (108 new entries; block claimed 90951–91391, remainder unused/closed) |
| SKU-097703–097706 | Second top-up session same day, Jul 20 2026 (4 new entries; block claimed 97703–97902, remainder unused/closed) |

---

## Brand Scope

16 brands in 95% GMV scope. Key brands: Huggies, Merries, Mamy Poko, Moony, GOO.N, Pampers, BabyLove, Mamypoko, BabyGots.

---

## Scope — What's In vs Out

**In scope:** Diaper tape, diaper pants

**Out of scope:**
- **ม้วนทิ้ง** (disposal tape sticker on pants) — text pattern `ม้วนทิ้ง` = exclusion from diaper tape detection. `is_diaper_tape()` must NOT match this.
- Cloth diapers

---

## Taxonomy Design Notes

**Product types:** Diaper Tape (ผ้าอ้อมแบบเทป) vs Diaper Pants (ผ้าอ้อมแบบกางเกง). Size ranges: NB/S/M/L/XL/XXL.

**Pack-count:** Usually stated explicitly (e.g. "36ชิ้น", "48ชิ้น"). Bulk listings (ยกลัง) detected from sku_name.

---

## Map Row Counts (Jun 21 2026)

| Source | Count | Notes |
|--------|-------|-------|
| LLM/OFFICIAL | 9 | Few official stores in this category |
| LLM/RESELLER | 634 | 16 brands, keyword routing |
| HUMAN | 1,418 | Long-tail out-of-scope |
| LLM/RESELLER (top-up, Jul 20 2026) | +185 | See QA History below |

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| Jul 20 2026 | Top-up coverage (month 2026-06) | Live worklist query (top-95%-cumulative-GMV, GWP-zeroed, `taxonomy_id IS NULL`) returned 441 rows at `(product_id, model_id)` grain but only **212 distinct products** — the model-grain query fans out per variant; dedup to product_id is the correct mint/read ceiling. All 212 vision-read (image + sku_name) via 18 parallel subagents, each applying reuse-before-mint against the existing 338-entry taxonomy. Result: 58 reused existing SKUs, 127 proposed new entries deduped down to 108 genuinely distinct new taxonomy entries (brand+type+line+size+pack_count+piece-count match), 27 left `UNRESOLVED` (13 mixed tape/pants listings that fail the hard TYPE GATE, 6 out-of-scope — 3 adult diapers, 1 cloth training pants, 1 burp cloths, 1 swaddle wrap — 1 unreadable brand, 7 genuinely ambiguous size/line from composite catalog images). Also found: `product_taxonomy_map.confidence` is typed STRING (not FLOAT64 as ARCHITECTURE.md states) and the table carries undocumented `platform`/`country` columns (`'Shopee'`/`'TH'` for this table) required by the ADR-006 composite key — DML adjusted accordingly. Wrote 108 rows to `product_taxonomy` (SKU-090951–091058) and 185 rows to `product_taxonomy_map`, all `source='LLM'`, `meta_agent='CLAUDE_CODE'`. | Post-write QA gates run without `--skip-coexistence` (genuine-bug policy since category already shipped): G1 dual-mapped=0, G2 HUMAN+LLM coexistence=0, G3 placeholder-leak=0, G5 provenance=0, structured-fields-missing=5% (baseline ~9%, pass). Soft D4 flag: 2 new entries (swim-diaper products, no brand_dict match → `BRD-UNDEFINED`) have `size IS NULL` — genuinely no size stated in text or image, not a rebuild trigger. Re-ran the live worklist query post-write: residual gap = 27, exactly matching the unresolved set — confirms no product silently dropped. SKU block registry entry marked `COMPLETE`. Universe refresh intentionally **not** run this session — deferred to a separate, independently-verified step per instructions. |
| Jul 20 2026 | Second top-up same day (month 2026-06) | A second wrapper invocation re-ran the same live-worklist definition a few hours after the session above and reported 79 rows at `(product_id, model_id)` grain. Before processing, verified this wasn't a duplicate/stale re-run: `sku_block_registry` showed the prior block (90951–91391) already `COMPLETE`, and the 79 rows deduped to exactly **27 distinct products** — suspiciously matching the residual count from the prior session's QA History entry. Initially considered this a false alarm, but per-product inspection (real brand data via `product_brand_map`, not the null `product_taxonomy.brand_id` join used in the raw worklist query, plus image reads for every product where text was ambiguous) showed the 27 were **not** identical to the prior residual: several (MamyPoko, Merries, GOO.N, Little Sheep, Dodolove single-type pants) were legitimately mappable and had simply not been looked at individually before. Of the 27: **7 reused** existing taxonomy entries via brand+line+pack text/image match (Dodolove Organic Pants → SKU-005727; 2× ambiguous MamyPoko Super Premium Organic composite-catalog listings → SKU-091011; Endebao duck-mascot mixed-type listing → SKU-091043 per established "(unresolved)" precedent; GOO.N Premium Soft single-bag → SKU-090966; Little Sheep Ultra Thin M-XXXL 1-pack → SKU-091034 exact match; Merries "Air Through" single-bag → SKU-090951 exact match). **4 new entries minted** (SKU-097703–097706): MamyPoko Happy All Day Dry Pants Multiple Sizes (pack=1, no existing pack=1 MULTI variant of this line); Merries Super Jumbo XXL 24pcs x3 (a 3-bag case of an existing single-bag SKU's size/line, no case-level entry existed); Simply Baby Swim Pants XXL (new brand, swim diapers already an established in-scope sub-type per Dodolove/Huggies/Sunny Baby/BRD-UNDEFINED precedents); Imported Baby Diaper Pants Multiple Sizes (BRD-UNDEFINED, generic reseller product, image-confirmed Pants type, sizes M–6XL). **16 left NULL**, all image-verified: 7 explicit mixed-tape/pants-type listings (BKF Honey ×2, Bambies ×2, MamyPoko×ButterBear, KUMO, Mimi Papa, Kissme — hard TYPE GATE), 5 adult diapers wrongly surfaced in this baby category (Certainty, Sekure ×2, Sunmed — all image-confirmed "Adult Diapers"/"ผู้ใหญ่" branding despite ambiguous sku_name text on some), 1 cloth training pants (Einmilk, gauze/ผ้าก๊อซ), 1 burp cloths (Airy — image confirmed, not a diaper at all), 1 swaddle wrap (Ergobaby Swaddler — not a diaper), 1 BKF Honey listing where the product image was a generic brand-range banner ad with no way to determine tape-vs-pants type for this specific SKU. Claimed a fresh 200-slot block (`taxonomy_topup`, block 97703–97902) since the prior block was already `COMPLETE`; used only 4 slots, remainder closed. Wrote 4 rows to `product_taxonomy` and 11 rows to `product_taxonomy_map`, all `source='LLM'`, `meta_agent='CLAUDE_CODE'`. | Post-write QA gates (no `--skip-coexistence`): G1 dual-mapped=0, G2 HUMAN+LLM coexistence=0, G3 placeholder-leak=1→0 (caught and fixed: a first-draft canonical name literally read "Undefined Baby Diaper Pants..." — the gate correctly flagged writing the literal brand-dict placeholder string into canonical_name; corrected to "Imported Baby Diaper Pants Multiple Sizes", consistent with the existing `BabyHip`/`Felicity Bebe` convention for BRD-UNDEFINED swim-diaper entries), G5 provenance=0, structured-fields-missing=5% (pass). Re-ran the live worklist query post-write: residual = 16 distinct products, exactly matching the documented NULL set above — confirms no product silently dropped. SKU block registry entry marked `COMPLETE`. Universe refresh intentionally **not** run this session — deferred to a separate, independently-verified step per instructions. |
