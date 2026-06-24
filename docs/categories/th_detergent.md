# shopee_th_detergent — Category Context

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete |
| LLM Pass 2 | ✅ Complete |
| GMV Coverage | ~85% (Apr 2026) |
| Last run | Jun 21 2026 |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-010000–010190 | Full taxonomy (191 entries, 27 brands) |

---

## Brand Scope

27 brands. Key brands: Ariel, Persil, Breeze, Kao Attack, Downy (detergent line), Biomax, Magiclean (EXCLUDED — floor cleaner).

**Magiclean exclusion:** Despite appearing in brand rankings, Magiclean products are floor/toilet cleaners, not laundry detergent. Leave all Magiclean products NULL.

---

## Scope — What's In vs Out

**In scope:** Laundry detergent (liquid, powder, pod/capsule), fabric conditioner-detergent combos

**Out of scope:**
- Floor cleaner (Magiclean, Flash, Mr. Muscle)
- Dish soap / dishwasher tablets
- Toilet cleaner

---

## Map Row Counts (Jun 21 2026)

| Source | Count | Notes |
|--------|-------|-------|
| LLM/OFFICIAL | 949 | Pass 1 |
| LLM/RESELLER | 948 | Pass 2, keyword routing from sku_name |
| HUMAN | 1,584 | Deleted; 2,606 retained (long-tail) |
