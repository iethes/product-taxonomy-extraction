# shopee_th_moisturizer_for_body — Category Context

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete (rebuilt Jun 22) |
| LLM Pass 2 | ✅ Complete |
| GMV Coverage | ~80% (Apr 2026) |
| Last run | Jun 23 2026 (QA pack-count correction) |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-037000–037886 | Pass 1 OFFICIAL (887 entries, full product_line × variant × size) |
| SKU-038000–038132 | Pass 2 catch-alls (133 entries) |
| SKU-039000–039088 | Extended catch-alls for brands with no body moisturizer entry |
| SKU-040000–040096 | QA pass — pack-count x2/x3/x7 variants + Clear Nose + Nivea |
| SKU-041216–041229 | Body moisturizer QA entries relocated (were at 041000–041013, collided with softdrink) |
| SKU-041230 | Shokubutsu x12 body wash cross-ref |
| SKU-025000–025008 | Baby Lotion/Oil TYPE_CONFLICT fix |
| SKU-016000–016357 | DELETED (v1, superseded) |

---

## Brand Scope (GMV threshold 95%, Apr 2026)

104 brands. Key brands:

**Tier 1:**
- **Vaseline** — `Vaseline Official Store` — Gluta-Hya (UV Serum / Serum Burst Lotion), Healthy Bright, Proderma, Intensive Care lines × sizes
- **Nivea** — `Nivea Body Official Store TH` — Body Lotion, Rich Nourishing, Whitening, Men's range
- **Eucerin** — Spotless Brightening, pH5, UreaRepair, AtoControl
- **Dr.Pong** — BarrierX, U9.9, Beautilab, Timeless, 28D lines
- **CeraVe** — SA Smoothing, Moisturising Lotion
- **Jergens** — Natural Glow, Skin Firming
- **Johnson's Baby** — Baby Lotion, Baby Oil (3 brand_ids: BRD-SG-00150, BRD-SG-00228, BRD-SG-00404)

**Baby products (included):**
- Enfant, D-nee, Babi Mild, Mustela, Bepanthen

**Other key brands:**
- L'Occitane, Oriental Princess, Physiogel, Cetaphil, Palmer's, Smooth E, Sebamed, Aveeno, Yanhee, Boots Thailand

**Important: Clear Nose** — rank #4 brand in body moisturizer, missed entirely by original LLM extraction. Added in Session 41 (SKU-036000–036003) and expanded in QA pass (SKU-040000+ block).

---

## Official Store Allowlist (Pass 1)

| Brand | Merchant Name |
|-------|---------------|
| Vaseline | `Vaseline Official Store` |
| Nivea | `Nivea Body Official Store TH` |
| Eucerin | `Eucerin Official Store TH` |
| CeraVe | `CeraVe Official Store` |
| Johnson's Baby | `Johnson's Official Store` (covers all 3 brand_ids) |
| D-nee | `D-nee Official Store` |
| Mustela | `Mustela Official Store` |
| Cetaphil | `Cetaphil Official Store` |
| Physiogel | `Physiogel Official Store` |

---

## Scope — What's In vs Out

**In scope:**
- Body lotion, body cream, body serum, body milk, body butter
- Baby lotion, baby cream, baby oil (routed within this category)

**Out of scope (leave NULL):**
- Face moisturizer (separate category)
- Hand cream (if separate category in scope)
- Body wash / shower gel (separate category)
- Sunscreen (SPF-focused)

**TYPE_CONFLICT issues fixed:**
- Baby Lotion → oil taxonomy (and vice versa): 190 products fixed in Session 33
  - Added 9 catch-all entries for Johnson's Baby Oil (3 brand_ids), D-nee Baby Oil, Babi Mild Baby Oil, Enfant Baby Oil, Tropicana Baby Oil, Narak Baby Lotion, Narak Organic Baby Lotion

---

## Taxonomy Design Notes

**Vaseline product lines (complex):**
- Gluta-Hya UV Serum (50ml / 180ml / 180ml x2 / 300ml)
- Gluta-Hya Serum Burst Lotion (same sizes)
- Healthy Bright (multiple sizes)
- Proderma Light (multiple sizes)
- Intensive Care (original range, pre-rebrand)

**Dr.Pong brand ordering rule:** BarrierX must be detected BEFORE U9.9 in router (BarrierX detection comes first to avoid false matches). Beautilab detected from Dr.Pong shop specifically.

**Pass 2 wrong-route bug (fixed):** Session 42 Pass 2 loaded ALL taxonomy for brands (including their shampoo/coffee/cleanser entries), causing 1,207 products routed to wrong-category entries. Fixed by adding category filter to `load_existing_taxonomy()` — must filter to `master_table = '{table}'` products only.

**Pack-count false positives:**
- `"แพ็คเกจใหม่"` = new packaging design, NOT a multipack
- `"มี N แพ็คให้เลือก"` = N size options to choose from, NOT N units
- `"[แพ็ค N]"` in title brackets = genuine N-unit multipack

**GROUP BY dedup risk:** When rerouting suspect products, always `GROUP BY product_id` only (then take MAX sku_name). If you GROUP BY (product_id, taxonomy_id, confidence, brand_from_image), a product with N existing map rows produces N reroute groups → inserts N new rows.

---

## QA History

| Date | Session | Finding | Resolution |
|------|---------|---------|------------|
| Jun 22 | 33 | 190 baby lotion/oil TYPE_CONFLICTs | SKU-025000–025008; TYPE_CONFLICT→0 |
| Jun 22 | 42 | Full rebuild: 1,207 Pass 2 wrong-category routes | Fix: category filter in load_existing_taxonomy |
| Jun 22–23 | 43/44 | 70 pack-count errors across 18 groups | 14 new xN entries; false-positive patterns documented |

---

## Map Row Counts (Jun 22 2026)

| Source | Count | Notes |
|--------|-------|-------|
| LLM/OFFICIAL | 1,202 | Pass 1 |
| LLM/RESELLER | 3,523 | Pass 2 |
| LLM (extended catch-alls) | 875 | SKU-039xxx block |
| HUMAN | ~3,500 | Long-tail |
| Total universe rows | ~28,200 | sincere + farsight |
