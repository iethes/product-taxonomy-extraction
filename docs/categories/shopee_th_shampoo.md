# shopee_th_shampoo — Category Context

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete (v2 rebuild) |
| LLM Pass 2 | ✅ Complete (v2 rebuild) |
| GMV Coverage | 84.9% (84.5% LLM + 0.4% HUMAN, Apr 2026) |
| Last run | Jun 23 2026 |

**Version history:** v1 (Session 25, Jun 21) used text-routing in Pass 2 → generic names, P&G multi-brand confusion. v2 (Session 55, Jun 23) is authoritative with per-brand extraction routers.

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-053005–053456 | Pass 1 OFFICIAL (452 entries, 53 brands) |
| SKU-054000–054098 | Pass 2 RESELLER catch-alls (99 entries) |
| SKU-018000–018332 | DELETED (v1, 333 entries) |

---

## Brand Scope (GMV threshold 95%, Apr 2026)

53 brands with official stores. Key brands:

**P&G multi-brand store (brand_from_image REQUIRED):**
- Pantene, Head & Shoulders, Rejoice → all sold from same P&G store

**Unilever multi-brand store (brand_from_image REQUIRED):**
- Dove, Sunsilk, Clear, TRESemmé → Unilever Shampoo Official Store

**Single-brand stores:**
- L'Oreal Paris (Elseve / EverPure / Total Repair / Extraordinary Oil)
- L'Oreal Professionnel
- Kérastase
- Vichy (Dercos line)
- Daeng Gi Meori (Ki Gold / Glam Mo / JINGI / JINSOO)
- KhaokhoTalaypu (Ginger&Lotus / Mango / Mountain Goat)
- Nigao, MOIST DIANE, Regro, Bergamot
- Havilah, Kaff, Ryo, ASAKA, Maro, &honey
- Divyne, Farger, Cokki, Cerapure, Yanhee
- Biovech, Jee Herb, Curel, Common Ground
- Hommkesa, Olaplex, Go Hair, Chia Organic
- ardermis, L'Occitane, AloEx, OGX
- Selsun Blue, Herbal Essences, Tsubaki, Sebamed
- Nizoral, milk_shake, Eucerin, Siriraj

---

## Official Store Allowlist (Pass 1)

| Brand | Merchant Name |
|-------|---------------|
| Pantene, H&S, Rejoice | P&G Hair Care Official Store (or equivalent) |
| Dove, Sunsilk, Clear, TRESemmé | Unilever Shampoo Official Store |
| L'Oreal Paris | L'Oreal Paris Official Store |
| Kérastase | Kerastase Official Store |
| Vichy | Vichy Official Store |
| Daeng Gi Meori | Daeng Gi Meori Official Store |
| KhaokhoTalaypu | KhaokhoTalaypu Official Store |

**Multi-brand disambiguation:**
- P&G store: brand_from_image required — Pantene/H&S/Rejoice have visually distinct packaging
- Unilever store: brand_from_image required — Dove/Sunsilk/Clear/TRESemmé all different

---

## Scope — What's In vs Out

**In scope:**
- Shampoo (แชมพู), 2-in-1 shampoo+conditioner
- Anti-dandruff shampoo, color-protecting shampoo
- Hair treatment masks that are marketed as shampoo (e.g., treatment shampoo)

**Out of scope (leave NULL):**
- Conditioner-only (ครีมนวด)
- Hair serum / hair oil (not shampoo)
- Body wash
- Toothpaste / other personal care

---

## Taxonomy Design Notes

**Product line extraction:**
- Per-brand extraction functions in `build_p1_taxonomy_v2.py`
- H&S: Cool Menthol / Apple Fresh / 2in1 / Active Protect / Ginseng
- Pantene: Pro-V HFC / Total Damage Care / Miracles Bond Repair
- Dove: Intense Repair / Anti-HL / Biotin / Niacinamide / Micellar / Peptide
- Sunsilk: 7 variants (Black Shine, Smooth Manageable, etc.)
- Clear: Ice Cool / Apple Cider / Sakura / Men Cool Sport
- L'Oreal Elseve: Glycolic Gloss / Hyaluron Pure / Fall Resist / EverPure / Extraordinary Oil

**Size extraction:** Standard ml extraction from sku_name. Refill (ถุงเติม) = separate entry with is_refill=True.

**P&G/Unilever shared store rule:** For every product from a shared store, `brand_from_image` is mandatory. Never route to a brand entry based on GMV ranking alone when the product could belong to 3+ brands.

---

## QA History

| Date | Session | Finding | Resolution |
|------|---------|---------|------------|
| Jun 21 | 25 | P&G multi-brand confusion; generic names from text routing | Full rebuild required |
| Jun 23 | 55 | Per-brand extraction routers; size + pack per product | ✅ 84.9% coverage |

---

## Scripts

| Script | Purpose |
|--------|---------|
| `pipeline/05_product_taxonomy/llm_th_shampoo/build_p1_taxonomy_v2.py` | Pass 1 with per-brand routers |
| `pipeline/05_product_taxonomy/llm_th_shampoo/build_p2_taxonomy_v2.py` | Pass 2 reseller routing |
| `pipeline/05_product_taxonomy/llm_th_shampoo/cleanup_refresh.py` | HUMAN cleanup + universe refresh |

---

## Map Row Counts (Jun 23 2026)

| Source | Count | Notes |
|--------|-------|-------|
| LLM/OFFICIAL | 597 | Pass 1, 53 brands |
| LLM/RESELLER | 1,812 | Pass 2 catch-alls |
| HUMAN | 2,012 | Long-tail (pending cleanup after 90-min buffer) |
| Total universe rows | ~40,000 | sincere |
