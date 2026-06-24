# shopee_th_toothpaste — Category Context

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete (v2 rebuild) |
| LLM Pass 2 | ✅ Complete (v2 rebuild) |
| GMV Coverage | 92.5% (Apr 2026) |
| Last run | Jun 24 2026 (quality pass 3) |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-047000–047450 | Pass 1 OFFICIAL (451 entries, 42 brands) |
| SKU-048000–048257 | Pass 2 RESELLER (258 entries, 74+ brands) |
| SKU-051000–051006 | NULL coverage pass (7 entries) |
| SKU-052000–052012 | Quality pass A/B/C — pack variants |
| SKU-053000–053004 | Fix A/B — 3M Clinpro + Dentiste corrections |
| SKU-055000–055022 | Quality pass 3 — Colgate Salt / Sensodyne / Dr.Pong / Wonder Smile / Beyond |
| SKU-022000–022176 | DELETED (v1) |

---

## Brand Scope (GMV threshold 95%, Apr 2026)

42 brands with official stores (Pass 1). 74+ additional brands in Pass 2.

**Major brands (Pass 1):**
- **Colgate** — `Colgate Official Store TH` — 13 product lines: Optic White (O2/Purple/Renewal/Gold), Sensitive Pro-Relief, MaxFresh, Total 12h, Triple Action, Naturals, Herbal, Kids, Great Regular, Salt line (Herbal/Charcoal/Guava Leaf/XtraFresh/Whitening)
- **Dentiste** — `Dentiste Official Store` — 14 lines: Original, Nighttime, Premium Care, Purple, Ultra Sensitive, Anticavity Max, Premium White, 100% Natural, Repaire ReX3, Pro Max, Extra Strong Mint, Enamel Expert, Kids, Remin
- **Sensodyne** — via P&G / GSK — Repair & Protect, Rapid Relief, Deep Clean, Multi Care, Clinical White (is_multi_variant), Stain Protector
- **Darlie** — `Darlie Official Store` — 7 lines: Double Action, All Shiny White, Charcoal Clean, Salt & Baking Soda, Double Action Extra Fresh, Double Action Multi-Care, Kids
- **Lion Shop Online** — multi-brand: Salz, Systema, Zact
- **Dr.Pong** — Y2B, GUMX Propolis, ZURFACEX Hypersensitive, BREATHX
- **Marvis** — 7 flavors (Whitening Mint, Classic Strong Mint, Aquatic Mint, Cinnamon Mint, Jasmine Mint, Amarelli Licorice, Ginger Mint)
- **Curaprox** — Be You, generic catch-all
- **Oral-B** — various
- **3M Clinpro** — ESPE Tooth Creme 113g + F1450 (is_multi_variant)
- **Fluocaril** — Orthodontics, 40+
- **Sparkle**, **Haewon**, **Funton**, **Parodontax**

**Important: 3M Clinpro SKU-047000 originally had 69 misrouted products** (Thai herbal brands + GC Tooth Mousse wrongly tagged 3M in source data). These were audited and removed in Fix A (Jun 23).

---

## Official Store Allowlist (Pass 1)

| Brand | Merchant Name |
|-------|---------------|
| Colgate | `Colgate Official Store TH` |
| Dentiste | `Dentiste Plus White Official Store` |
| Sensodyne / Parodontax | Sensodyne/GSK store |
| Darlie | `Darlie Official Store` |
| Salz, Systema, Zact | `Lion Shop Online` |
| Marvis | `Marvis Official Store` |
| Dr.Pong | `Dr.Pong Official Store` |
| 3M Clinpro | `3M Official Store` or similar |

**Excluded from allowlist:**
- Vidhyasom Mall store — sells only toothpaste-with-brush SETS as main product (OOS bundles)
- Watsons, Boots, BigC

**Brands with no official store (Pass 2 only):**
- Beyond, Tepthai, Kolbadent, Rasyan, Nokthai, Thaya, Zhulian, Himalaya, Chula Dent, Elitesmile, DR.J, Greater Pharma, Dr.Ray, ~65 more

---

## Scope — What's In vs Out

**In scope:**
- Toothpaste (ยาสีฟัน), tooth serum, whitening serum, enamel repair gel, tooth mousse (if dental brand)

**Out of scope (leave NULL):**
- **Toothbrush** as main product (แปรงสีฟัน at START of sku_name)
- **Mouthwash SET** as main product — น้ำยาบ้วนปาก is OOS only when NOT preceded by ฟรี/แถม (GWP mouthwash is OK)
- **Oil pulling** (oil pulling / ออยล์พูลลิ่ง)
- **Candy/lozenge** (ลูกอม)
- **Polident Denture Cleanser** — hard OOS regardless of sku_name content
- **OOS bundles** — toothbrush+mouthwash sets where the main product is NOT toothpaste

**`is_oos_bundle()` function must catch:**
1. Electric/manual toothbrush as main product (`^แปรงสีฟัน` at start)
2. Mouthwash SET as main product (น้ำยาบ้วนปาก without preceding ฟรี!/แถม)
3. Toothbrush bundled without GWP marker (แปรงสีฟัน x\d+, พร้อมแปรง)
4. Oil pulling content
5. Candy (ลูกอม)

---

## Taxonomy Design Notes

**Size extraction:** Most products specify size in sku_name (e.g., "150g", "100g x2"). `product_specification` column has NO size data for toothpaste (confirmed in Fix C).

**Pack-count parsing:**
- `ฟรี!` (exclamation after ฟรี): regex must be `r'(\d+)\s*ฟรี!?\s*(\d+)'` — without `!?` it fails on `[แพ็คสุดคุ้ม 2 ฟรี! 1]`
- `[แพ็คสุดคุ้ม 2 ฟรี! 1]` = buy 2 get 1 free → pack_count=3

**Multi-variant dedup:** Same product_id appears multiple times in source data for multi-option listings. Dedup before insert: for each product_id, keep the map row pointing to the most-specific taxonomy entry (`has_size=1 > pack_count DESC`). Use `entry_specificity()` sort + keep-first.

**Colgate Salt line:** 5 variants × 150g × x1/x2/x3 = 15 entries (SKU-055001–055011). Herbal/Charcoal/Guava Leaf/XtraFresh/Whitening.

**Sensodyne Clinical White:** is_multi_variant=TRUE. x1 and x2 entries both needed (SKU-055012–055013).

**3M product naming:** `3M Clinpro ESPE Tooth Creme 113g` (SKU-053000) and `3M Clinpro F1450` (is_multi_variant=TRUE, SKU-053001). The catch-all SKU-047000 should ONLY have genuine unidentifiable 3M products — not Thai herbal brands that had wrong brand assignment in product_brand_map.

---

## QA History

| Date | Session | Finding | Resolution |
|------|---------|---------|------------|
| Jun 23 | 50 (rebuild) | v1 had universal NULL size, 46% wrong pack_count, Polident in taxonomy | Full rebuild: SKU-047000–048257 |
| Jun 23 | 54 | 70 OOS products in NULL top-100 (toothbrushes, Polident) | 13 in-scope mapped; OOS left NULL |
| Jun 23 | 55 (QA A/B/C) | SKU-047000 had 14 misrouted Colgate/Salz products; Sensodyne CW needs is_multi_variant | Pack-count entries SKU-052000–052012; reroutes |
| Jun 23 | 56 (Fix A/B) | 69 misrouted products at 3M SKU-047000 (herbal brands, GC Tooth Mousse) | Audit + delete + reroute; SKU-053000–053004 |
| Jun 23 | 57 (NULL pass 2) | 18 more products mappable | SKU-055000 + routes to existing |
| Jun 24 | quality pass 3 | Colgate Salt line missing; Sensodyne CW fix; Dr.Pong product line split; Wonder Smile gaps; 9 OOS Dentiste bundles | SKU-055001–055022; 9 OOS NULLed |

---

## Scripts

| Script | Purpose |
|--------|---------|
| `pipeline/05_product_taxonomy/llm_th_toothpaste/build_taxonomy_v2.py` | Pass 1 |
| `pipeline/05_product_taxonomy/llm_th_toothpaste/build_p2_taxonomy_v2.py` | Pass 2 |
| `/tmp/toothpaste_quality_pass.py` | QA pass A/B/C |
| `/tmp/toothpaste_fix_abc.py` | Fix A (3M audit) + Fix B (NULL coverage) |
| `/tmp/toothpaste_null_pass2.py` | NULL coverage pass 2 |
| `/tmp/toothpaste_quality_pass2.py` | Quality pass 3 |

---

## Map Row Counts (Jun 24 2026)

| Source | Count | Notes |
|--------|-------|-------|
| LLM total | ~2,000 | Pass 1 + Pass 2 + QA passes |
| HUMAN | ~1,900 | Long-tail (out-of-scope oral care) |
| Total universe rows | ~33,600 | sincere |
