# shopee_th_softdrink — Category Context

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete (rebuilt) |
| LLM Pass 2 | ✅ Complete (rebuilt) |
| GMV Coverage | 90.9% (Apr 2026) |
| Last run | Jun 23 2026 (NULL coverage pass) |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-041000–041165 | Pass 1 OFFICIAL (166 entries, 5 official stores) |
| SKU-041166–041309 | Pass 2 RESELLER + QA corrections (144 entries) |
| SKU-041310–041999 | Future expansion (690 slots) |
| SKU-019000–019119 | DELETED (v1 text-routing, 85 entries) |

---

## Brand Scope (GMV threshold 95%, Apr 2026)

20 brands in scope. Official stores cover 5 parent companies.

**Official stores (Pass 1):**
- Coca-Cola Official Shop → Coca-Cola, Fanta, Sprite, Schweppes, Smartwater
- Suntory PepsiCo → Pepsi Cola, Pepsi Zero Sugar, Schweppes, 100PLUS
- Sermsuk Click → Est, Sprite, Rock Mountain, Oishi, Farmzaa, Sarsi
- TCP Online → Farmzaa
- Osotspa Delivery → Calpis

**Important brand notes:**
- **Sarsi** — sold under Oishi brand_id (BRD-GLOBAL-00900, Sermsuk distributes both)
- **ZWS Coca-Cola** (BRD-GLOBAL-00521) — fake/reseller brand; route products to real Coke taxonomy
- **Singha** — dual brand_id: BRD-GLOBAL-00047 (Singha) + BRD-GLOBAL-01008 (Sing)
- **A&W Root Beer** — BRD-TH-01451 (canonical "AW"), products may have BRD-UNDEFINED in product_brand_map but map correctly to taxonomy

**NULL coverage pass brands (added Jun 23):**
7UP, Lipton Za, Red Bull Soda, Hite Zero, Chi Forest, San Pellegrino, Mountain Dew, Mirinda, Canada Dry, Barbican, Ibev, Kickapoo, Hokkaido Migoto, Leo Soda, Hata Kosen Ramune, BIG Ajemin, Oishi CoolZa, Sarsi, HBD Sparkling Water, Zuza, Orangina, P80, Fever Tree, Mind Kombucha, Tan San Su

---

## Scope — What's In vs Out

**In scope:**
- Carbonated soft drinks: cola, lemon soda, orange soda, cream soda, ginger ale, tonic water, sparkling water (flavored), root beer, energy soda variants
- Non-alcoholic beer (Heineken 0.0 = IN scope — labeled as soft drink by NIQ)

**Out of scope:**
- Multi-brand Cola listings (seller offering Pepsi+Coke+Fanta as choice) → leave NULL
- Mystery/assortment boxes where buyer can't determine what they receive

**Difficult listings:**
- Multi-size seller listings (seller offers 300ml/345ml/545ml as buyer choice) → `is_multi_size=TRUE`, size=NULL
- Multi-variant listings (Coke Original/Less Sugar/Zero Sugar as choice) → `is_multi_variant=TRUE`

---

## Taxonomy Design Notes

**Canonical name format:** `{Brand} {Flavor/Variant} {Size} x{Pack}`  
Examples: `"Coca-Cola Less Sugar 1.5L x12"`, `"Pepsi Zero Sugar 325ml x24"`

**Pack-count patterns (critical for this category):**
- `"รวม N ขวด"` — most reliable, N is the total
- `"[xN] M กระป๋อง"` = N × M total
- `"แพ็คN"` (no brackets) = N packs
- `"N+M กระป๋อง/ชิ้น"` = N+M total
- **`"[แพ็กN] ยกลังxM"`** = N × M total (e.g. `[แพ็ก12] ยกลังx3` = 36) — NESTED MULTIPLIER

**Flavor differentiation rule:** Pepsi Zero Sugar and Pepsi Cola must have SEPARATE taxonomy entries. Zero Sugar cannot be routed to Cola entries. Same applies to all flavor variants (Singha Soda Lemon vs Cream Soda vs Watermelon = separate entries).

**Bundle taxonomy:** `"Brand A Size xN + Brand B Size xN"`, is_bundle=True, pack_count=total units. E.g., Coke Less Sugar 1.5L x12 + Fanta Orange 1.5L x12 = pack_count=24.

**Heineken 0.0 naming:** `"Heineken 0.0 Alcohol Free Beer 330ml x24"` (not "Non-Alcoholic 0.0").

---

## QA History

| Date | Session | Finding | Resolution |
|------|---------|---------|------------|
| Jun 21 | 23 | Text-routing v1: 78% NULL size, 72% wrong pack_count | Full rebuild |
| Jun 23 | 45 | Rebuilt with systematic Thai text parsing | ✅ 84.2% coverage |
| Jun 23 | 46 | Nested multiplier missed; Singha flavor not split | 14 new entries (SKU-041231–041244) |
| Jun 23 | 47 | Pepsi Zero Sugar had 0 entries; Coke bundles contaminated | 17 new entries (SKU-041245–041261); QA gate passed |
| Jun 23 | 48 | NULL coverage: 28 new brands | 48 new entries (SKU-041262–041309); 90.9% coverage |

---

## Scripts

| Script | Purpose |
|--------|---------|
| `pipeline/05_product_taxonomy/llm_th_softdrink/` | All v1 scripts (historical reference) |
| `/tmp/softdrink_cleanup_and_refresh.py` | v2 rebuild main script |
| `/tmp/softdrink_corrections.py` | QA pass corrections |
| `/tmp/softdrink_comprehensive_fix.py` | Comprehensive QA pass |
| `/tmp/softdrink_null_pass.py` | NULL coverage pass |

---

## Map Row Counts (Jun 23 2026)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | ~400 | All passes combined |
| HUMAN | ~480 | Long-tail retained |
| Total universe rows | 156,653 | sincere |
