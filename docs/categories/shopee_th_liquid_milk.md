# shopee_th_liquid_milk — Category Context

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete (rebuilt Jun 22) |
| LLM Pass 2 | ✅ Complete |
| GMV Coverage | ~85% (Apr 2026) |
| Last run | Jun 22 2026 (multiplier fix) |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-026000–026326 | Full rebuild (190 entries, 54 brands) |
| SKU-027000–027332 | Multiplier fix + Oatside 180ml (333 entries) |
| SKU-013000–013218 | DELETED (v1, superseded) |

---

## Brand Scope

54 brands in 95% GMV scope. Key brands:
- Enfagrow, Enfalac, S-26 (formula / growing-up milk)
- Hi-Q (Super Gold S3/S4, Start PrebioProteq, Explorer PrebioProteq, Primary School)
- Meiji, Dumex, Morinaga (formula brands)
- Foremost (Omega 369, Smart Gold 1+, Smart Gold 4+)
- Dutch Mill, Anlene, Anchor (dairy/UHT)
- Oatside (oat milk — Unsweetened, Barista, Original, Plain 180ml)
- Ovaltine (powder + RTD cartons)
- Soy Twist, Dna

**NIQ mislabeled brands (cocoa powder in liquid_milk table):**
- Tulip, BM, AM, Cacao Barry, Cacao Rich, Dreamy, Mill Mill, KC Interfoods, Master, Baramio
- These are cocoa powder products mislabeled by NIQ — taxonomy created to avoid orphaned mappings but flagged as out-of-category

---

## Disambiguation Rules (CRITICAL)

**Enfagrow vs Enfalac vs S-26:**
- **Enfalac** = Stage 1 infant formula (0–12 months)
- **Enfagrow** = Stage 3 growing-up milk (1–3 years)
- These are DIFFERENT products by the SAME brand (Mead Johnson / RB)
- 778 Enfalac→Enfagrow cross-brand routing errors fixed in Session 32 (QA Fix)
- 319 more Enfalac→S-26 errors also fixed

**S-26 sub-lines:**
- S-26 Gold ≠ S-26 Gold Pro ≠ S-26 Omega Plus (all different)

**Hi-Q sub-lines:**
- Super Gold S3 ≠ Super Gold S4
- Start PrebioProteq (180ml/110ml) ≠ Explorer PrebioProteq (180ml/110ml)

**Oatside 180ml Plain gap:** Product 25725893545 was wrongly routed to SKU-026113 (Unsweetened 1000ml). Created SKU-027000 "Oatside Oat Milk Plain 180ml" base + SKU-027001 "Oatside Oat Milk Plain 180ml x24".

---

## Taxonomy Design Notes

**Bulk pack multiplier patterns (25-rule Thai text parser):**
- **Critical ordering:** `"(N กล่อง) ยกลัง"` → N total, checked BEFORE `"(N กล่อง) xM"` → N×M
- Without this order: `"(108 กล่อง) ยกลัง x4"` would be parsed as 432 instead of 108
- 411 products with unparseable pack counts remain at base entries

---

## QA History

| Date | Session | Finding | Resolution |
|------|---------|---------|------------|
| Jun 22 | 35 | v1 had wrong brand routing (#1 Enfagrow → Plain not Vanilla; #3 S-26 → Gold Pro not Promil) | Full rebuild |
| Jun 22 | 36 | 2,121 products needed pack-count-specific entries | 333 new entries; pack parser built |

---

## Map Row Counts (Jun 22 2026)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 10,212 | All passes (0 unrouted) |
| HUMAN | 1,167 | Out-of-scope (out-of-scope products) |
| Total universe rows | 1,449,432 | sincere (shared with formula milk rollup) |
