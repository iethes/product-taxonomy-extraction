# shopee_th_baby_diapers — Category Context

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete |
| LLM Pass 2 | ✅ Complete |
| GMV Coverage | 90.8% (Apr 2026) |
| Last run | Jun 21 2026 |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-005547–005884 | Full taxonomy (338 entries, 16 brands) |

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
