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
