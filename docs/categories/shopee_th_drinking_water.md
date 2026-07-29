# shopee_th_drinking_water — Category Context

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete (rebuilt) |
| LLM Pass 2 | ✅ Complete |
| GMV Coverage | ~90% (Apr 2026) |
| Last run | Jun 23 2026 (NULL coverage pass) |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-011000–011087 | Original 16-brand base (retained) |
| SKU-045000–045231 | Quality pass — bulk pack-count expansion (232 entries) |
| SKU-050000–050062 | NULL coverage pass (63 entries) |

---

## Brand Scope (GMV threshold 95%, Apr 2026)

16 brands: Singha, Crystal, Purra, Pure, Nestle, 6ty Degrees, evian, Minere, Welle, Aura, Iora, Mont Fleur, FIJI, Siamdrink, Iceland Spring, Undefined

---

## Official Store Allowlist (Pass 1)

| Brand | Merchant Name |
|-------|---------------|
| Singha | Singha Official Store |
| Crystal | Crystal Water Official |
| Purra | Purra Official Store |
| Nestle | Nestlé Official Store |
| evian | evian Official Store |
| Minere | Minere Official Store |

---

## Scope — What's In vs Out

**In scope:**
- Still drinking water, natural mineral water, sparkling mineral water
- Plain alkaline water (no functional additives)
- **Ichitan น้ำต่าง (plain water, no ผสมวิตามิน) = IN SCOPE**

**Out of scope (leave NULL):**
- **Ichitan Alkaline Water ผสมวิตามิน / Vitamin B / Vitamin D & Ginkgo** = FUNCTIONAL BEVERAGE, OOS even though brand appears in scope. Filter by product_id, not brand_id.
- **Pocari Sweat** = sports/ion drink, OOS
- **Yanhee Vitamin Water** (vitamin-fortified) = OOS; Yanhee plain drinking water = IN scope
- **B'lue, Vitaday** = functional water, OOS
- กรวยน้ำดื่ม (paper drinking cups) = wrong category
- Coffee brewing mineral concentrate = wrong category
- Water filter equipment, chlorine test kits

**OOS brand filter:** filter by `brand_id IN (ichitan_ids)` and `'vitamin' not in canonical`, NOT by brand name substring. Ichitan's brand_dict canonical_name is "Ichitan" without "Alkaline" suffix.

---

## Taxonomy Design Notes

**Size extraction:** Standard L/ml parsing from sku_name.

**Bulk pack-count patterns (dominant in this category — 79% of top-GMV products sell in multi-case lots):**
1. `"N แพ็ค รวม M ขวด"` → M total (most reliable — M is stated explicitly)
2. `"N แพ็ค M ขวด"` → N × M total
3. `"N ขวด ฟรี M ขวด"` (same product freebie) → N + M total
4. `"3 FREE 1"` → 4 × base_pack
5. `"ยกลัง N ขวด"` / `"ลังละ N ขวด"` → N total
6. `"N แพ็ค"` alone → N × base_pack_per_case

**Verified base pack sizes per brand+size (bottles per standard case):**
- Crystal 600ml = 12, Crystal 1500ml = 6
- Singha 600ml = 12, Singha 1500ml = 6
- Nestle 600ml = 12, Nestle 1500ml = 6
- **Purra 600ml = 15** (NOT 12 — verified from official store)
- evian 500ml = 24, evian 1500ml = 12
- Purra 1500ml = 8

**Canonical name rule:** `x{TOTAL}` only. Never write `"(N packs of M)"` breakdown. Fix 123 existing entries: `REGEXP_REPLACE(canonical_name, r" \(\d+ packs of \d+\)$", "")`.

**Welle freebie totals:** `"(N ขวดฟรี M ขวด)"` = N + M total (same product free bottles). Use explicit total from text, NOT base_pack multiplier.

**Cross-brand Namthip/Coca-Cola:** Products mapped to BRD-GLOBAL-00145 (Coca-Cola) in product_brand_map may actually be น้ำทิพย์ (Namthip). Create taxonomy under BRD-SG-00926 (Namthip) and map these products there.

---

## QA History

| Date | Session | Finding | Resolution |
|------|---------|---------|------------|
| Jun 23 | 51 | Streaming buffer clear; Ichitan OOS confirmed; evian 2 conflicts | Dedup; 18 Ichitan entries deleted; evian fixed |
| Jun 23 | 52 | 123 canonical names had "(N packs of M)" suffix | REGEXP_REPLACE fix; NULL coverage added 63 entries |

---

## Map Row Counts (Jun 23 2026)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 7,679 | All passes |
| HUMAN | 131 | May 2026, outside rebuild scope |
| Total universe rows | 24,953 | sincere |
