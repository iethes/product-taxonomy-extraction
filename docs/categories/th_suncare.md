# shopee_th_suncare — Category Context

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete |
| LLM Pass 2 | ✅ Complete (Pass 2 + Pass 3 long-tail) |
| GMV Coverage | ~85% (Apr 2026) |
| Last run | Jun 19 2026 (Pass 3 long-tail) |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-003353–003516 | Pass 1 OFFICIAL (164 entries, top brands) |
| SKU-003517–003546 | Pass 2 RESELLER ≥THB 50k (30 entries, 9 brands) |
| SKU-005885–005957 | Pass 3 long-tail 95% GMV (73 entries, 16 brands) |
| SKU-000787–000820 | Wave-4 keyword seeds (Biore, LRP, MizuMi TH + Cosrx/Bioderma + Shiseido/Cute Press/Charmiss etc.) |
| SKU-000001–000558 | Waves 1–3 keyword seeds |

---

## Brand Scope

**Pass 1 (official stores):** Top-10 brands by GMV — L'Oreal, ANESSA, Isdin, Srichand, Clear Nose, Biore, La Roche-Posay, Eucerin, MizuMi + more

**Pass 3 long-tail (16 brands):** ROUND LAB, ICE LERSKIN, Dr.Pong, Elixir, Ingu, Terry, SKINPRO Rx, Canmake, Sibling, Cathy Doll, iMin, Beauty of Joseon, Vaseline, Banana Boat, KA, Nivea

**Cathy Doll breakdown (9 distinct product lines):**
Ultra Light Sun Fluid, Aqua Sun Body Serum (Bright Up / Cool Up / PDRN), Sun Mist, CC Body Primer, Sun Essence, Hydrofill Sun Serum, Invisible Sun Matte

---

## Taxonomy Design Notes

**Brand mismatches found:**
- Vaseline Official Store selling Citra products → flagged brand_mismatch=TRUE
- Banana Boat listing selling Sunplay products → flagged

**GWP rule established here (Decision context):** Option lists (not cover image) are authoritative for multi-variant detection. "buy-1-get-1-free" / free-foam = GWP → pack_count=1. `[แพ็คคู่]` / `x2pcs` / "SAVE 50% duo" = genuine pack≥2.

**LRP routing order fix (Decision 12 origin):** Route "Oil Control Gel Cream" BEFORE "Oil Control" to prevent generic catch-all from capturing specific products.

---

## Map Row Counts (Jun 2026)

| Source | Count | Notes |
|--------|-------|-------|
| LLM/OFFICIAL | 213 | Pass 1 |
| LLM/RESELLER | 142 | Pass 2 |
| LLM/long-tail | 322 | Pass 3 |
| HUMAN | ~14 | Long-tail retained |
