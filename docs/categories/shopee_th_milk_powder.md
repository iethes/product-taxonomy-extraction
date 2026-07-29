# shopee_th_milk_powder — Category Context

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete |
| LLM Pass 2 | ✅ Complete + QA fix |
| GMV Coverage | 79% total (42% LLM + 37% HUMAN), Apr 2026 |
| Last run | Jun 22 2026 (QA fix) |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-015000–015255 | Core LLM taxonomy (256 entries, 29+ brands) |
| SKU-023000–023843 | Formula milk QA fix (844 entries) |

---

## Brand Scope

29+ brands with official stores. Category is highly heterogeneous:

**Infant formula:** Enfagrow/Enfalac (Mead Johnson), S-26 (Wyeth), Hi-Q (Dumex-Danone), Meiji, Morinaga, NAN (Nestlé)

**Adult nutrition:** Ensure Gold/AdvancePro (Abbott), Glucerna (Abbott), BOOST, Anlene, Anmum

**Medical tube-feeding:** Otsuka Once Renal / GEN-DM / Blender-MF (specialty medical nutrition)

**Maternal:** Anmum, Enfamama, Materna

**Condensed/evaporated milk:** Carnation (Nestlé), Teapot, Bear Brand

---

## Critical Disambiguation Rules

**Same-brand cross-routing is the #1 failure mode for this category:**
- Enfalac ≠ Enfagrow ≠ Enfamama (all Mead Johnson / RB brands)
- S-26 Gold ≠ S-26 Gold Pro ≠ S-26 Omega Plus ≠ S-26 Promil
- Hi-Q Super Gold S3 ≠ S4; Start ≠ Explorer PrebioProteq

**Decision 19 (mandatory):** When routing reseller products, always match brand first, then stage. Never match a product to a taxonomy entry of a different brand by stage alone. 2850g and 1800g are different products even if the product line name is identical.

---

## QA History

| Date | Session | Finding | Resolution |
|------|---------|---------|------------|
| Jun 22 | 31 | 1,938 SIZE_MISMATCH; 778 Enfalac→Enfagrow cross-brand; 319 Enfalac→S-26 | 844 new taxonomy entries; flag rate 78%→11% |

---

## Map Row Counts (Jun 22 2026)

| Source | Count | Notes |
|--------|-------|-------|
| LLM/OFFICIAL | 1,106 | Pass 1 (28 brands) |
| LLM/RESELLER | 3,550 | Pass 2 (31 brands) |
| HUMAN | 5,399 | Long-tail out-of-scope |
