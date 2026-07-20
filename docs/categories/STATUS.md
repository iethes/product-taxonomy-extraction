# Category Extraction Status Dashboard

Last updated: Jun 24 2026

---

## TH Categories — LLM Extraction Status

| Category | Pass 1 | Pass 2 | GMV Coverage | SKU Range (Pass 1) | SKU Range (Pass 2) | Notes |
|----------|--------|--------|-------------|--------------------|--------------------|-------|
| th_suncare | ✅ | ✅ | 65.0% v2-only | SKU-082151–082859 | (v2, single block) | v2 rebuild Jul 17 2026 (fixed `(all variants)` leak + NULL pack_count); 90 v1-only + 11 HUMAN-only rows kept live, v1 backed up |
| th_moisturizer_for_face | ✅ | ✅ | 85.6% | SKU-042000–042424 | SKU-042500–042526 | Rebuilt Jun 23 |
| th_moisturizer_for_body | ✅ | ✅ | ~80% | SKU-037000–037886 | SKU-038000–039088 | Rebuilt Jun 22; QA pass Jun 22–23 |
| th_body_wash | ✅ | ✅ | 75.5% | SKU-058000–058423 | SKU-057000–057569 | v3 rebuild Jun 24 |
| th_shampoo | ✅ | ✅ | 84.9% | SKU-053005–053456 | SKU-054000–054098 | Rebuilt Jun 23 |
| th_conditioner | ✅ | ✅ | ~80% | SKU-011088–011322 | (within same block) | Jun 21 |
| th_cleanser | ✅ | ✅ | ~85% | SKU-007000–007554 | SKU-007555–007711 | Jun 21 |
| th_toothpaste | ✅ | ✅ | 92.5% | SKU-047000–047450 | SKU-048000–048257 | Rebuilt + 5 QA passes Jun 23–24 |
| th_toothbrush | ✅ | ✅ | ~85% | SKU-020000–020270 | SKU-020271–020329 | Jun 21 |
| th_baby_diapers | ✅ | ✅ | 90.8% | SKU-005547–005884 | (same block) | Jun 21 |
| th_adult_diapers | ✅ | ✅ | ~85% | SKU-004547–004841 | SKU-004842–004935 | Jun 20 |
| th_liquid_milk | ✅ | ✅ | ~85% | SKU-026000–026326 | SKU-027000–027332 | Full rebuild + multiplier fix Jun 22 |
| th_milk_powder | ✅ | ✅ | 79% | SKU-015000–015255 | (within block) | + QA fix SKU-023000–023843 Jun 22 |
| th_pet_food | ✅ | ✅ | ~85% | SKU-017000–017553 | (within block) | + 5 QA passes Jun 22 |
| th_make_up_face | ✅ | ✅ | ~75% | SKU-014000–014485 | (within block) | Jun 21 |
| th_coffee | ✅ | ✅ | 87.1% | SKU-008000–008294 | SKU-008295–008649 | Jun 21 |
| th_detergent | ✅ | ✅ | ~85% | SKU-010000–010190 | (within block) | Jun 21 |
| th_fabric_softener | ✅ | ✅ | ~85% | SKU-012000–012185 | (within block) | Jun 21 |
| th_drinking_water | ✅ | ✅ | ~90% | SKU-011000–011087 + SKU-045000–045231 | SKU-050000–050062 | Rebuilt + 2 QA passes Jun 23 |
| th_softdrink | ✅ | ✅ | 90.9% | SKU-041000–041165 | SKU-041166–041309 | Rebuilt + 3 QA passes Jun 23 |

**Total TH:** 20/20 complete ✅

---

## ID Categories — Status

First-ever ID (Indonesia) category, added 2026-07-20. Source table lives in `master_clean_niq`
(`shopee_id_*`, 22 tables exist there — undocumented in `ARCHITECTURE.md`, which still says NIQ = SG+TH
only) but `product_brand_map` and `magpie.marketshare_universe_niq` have zero rows for any of them —
Stage 03/04 have never run for ID in this pipeline. See `docs/categories/shopee_id_baby_diapers.md`'s
Status section for what this means for a session picking up the next ID category.

| Category | Pass 1 | Pass 2 | GMV Coverage | SKU Range (Pass 1) | SKU Range (Pass 2) | Notes |
|----------|--------|--------|-------------|--------------------|--------------------|-------|
| shopee_id_baby_diapers | ✅ | ✅ | 91.93% (Jun 2026) | SKU-093462–094397 | SKU-094398–096475 | First ID category; created 5 new `brand_dict` entries (Fluffy, Baby Happy, MomBaby, Happy Nappy, FITTI); SKU-096476–096961 still ACTIVE/unused |

**Total ID:** 1/22 (of the `master_clean_niq` ID tables) LLM complete

---

## SG Categories — Status

| Category | Status | Notes |
|----------|--------|-------|
| sg_shampoo | ⏳ Keyword only | Seeded at 85/90/95% GMV, 11-month window |
| sg_facial_cleanser | ⏳ Keyword only | |
| sg_facial_moisturiser | ⏳ Keyword only | |
| sg_hand_and_body_moisturiser | ⏳ Keyword only | |
| sg_liquid_soap | ⏳ Keyword only | |
| sg_hair_conditioner_or_treatment | ⏳ Keyword only | |
| sg_laundry_detergent | ⏳ Keyword only | |
| sg_fabric_softener | ⏳ Keyword only | |
| sg_household_cleaner | ⏳ Keyword only | |
| sg_toothpaste | ✅ Complete | LLM Pass 1+2 complete Jul 16, 92.3% GMV coverage, SKU-072001–074000 |
| sg_diapers | ⏳ Keyword only | |
| sg_infant_milk | ⏳ Keyword only | |
| sg_health_food_drink | ⏳ Keyword only | |
| sg_coffee | ✅ Complete | LLM Pass 1+2 complete Jul 20, 93.85% GMV coverage, SKU-098346–100345 + SKU-102346–102519; created brand_dict entry BRD-SG-13379 (Super) |
| sg_carbonated_drink | ⏳ Keyword only | |
| sg_beverages | ⏳ Keyword only | |
| sg_beer_and_lager | ⏳ Keyword only | |
| sg_breakfast_cereals | ⏳ LLM Pass 1 complete, Pass 2 partial (83.9% GMV) | SKU-080151–080422; see sg_breakfast_cereals.md for NULL-coverage follow-up scope |
| sg_pet_food | ⏳ Keyword only | |
| sg_spirits | ⏳ Keyword only | |
| sg_toilet_rolls | ⏳ Keyword only | |
| sg_baby_accessories | ⏳ Keyword only | |
| sg_vitamin_mineral_health_supplements | ⏳ Keyword only | |

| **Total SG:** 2/23 LLM complete (sg_toothpaste, sg_coffee) — keyword seed provides ~50–70% GMV coverage for the rest

---

## Next Priority Queue (suggested order)

1. `sg_shampoo` — mirrors the most mature TH category; benchmark comparison ready
2. `sg_facial_cleanser` — high brand overlap with TH
3. `sg_toothpaste` — completed in TH with comprehensive rules; SG parallel straightforward
4. `sg_facial_moisturiser` — high value category
5. Remaining SG FMCG in roughly GMV-descending order

---

## SKU Block Registry

**Current MAX taxonomy_id: SKU-058455**  
**Next safe NEW block: SKU-058456+ (or jump to SKU-059000 for clean boundaries)**

| Block | Category / Purpose | Status |
|-------|--------------------|--------|
| SKU-000001–000820 | TH wave scripts (brand-specific seeds) | ACTIVE |
| SKU-000821–002359 | TH keyword seed (20 categories) | ACTIVE |
| SKU-002360–003219 | SG keyword seed (23 categories) | ACTIVE |
| SKU-003220–003229 | TH suncare keyword long-tail | ACTIVE |
| SKU-003230 | SOONSU brand fix | ACTIVE |
| SKU-003231–003546 | Moisturizer granular + suncare LLM P1+P2 | ACTIVE |
| SKU-004547–004935 | th_adult_diapers LLM | ACTIVE |
| SKU-005547–005957 | th_baby_diapers LLM + suncare Pass 3 | ACTIVE |
| SKU-006000–006999 | DELETED (body_wash v1, superseded) | DEAD |
| SKU-007000–007711 | th_cleanser LLM | ACTIVE |
| SKU-008000–008649 | th_coffee LLM | ACTIVE |
| SKU-010000–010190 | th_detergent LLM | ACTIVE |
| SKU-011000–011322 | th_drinking_water base + th_conditioner | ACTIVE |
| SKU-012000–012185 | th_fabric_softener LLM | ACTIVE |
| SKU-013000–013218 | th_liquid_milk v1 | DELETED (rebuilt at 026xxx) |
| SKU-014000–014485 | th_make_up_face LLM | ACTIVE |
| SKU-015000–015255 | th_milk_powder LLM | ACTIVE |
| SKU-016000–016357 | th_moisturizer_for_body v1 | DELETED (rebuilt at 037xxx) |
| SKU-017000–017553 | th_pet_food LLM | ACTIVE |
| SKU-018000–018332 | th_shampoo v1 | DELETED (rebuilt at 053xxx) |
| SKU-019000–019119 | th_softdrink v1 | DELETED (rebuilt at 041xxx) |
| SKU-020000–020329 | th_toothbrush LLM | ACTIVE |
| SKU-021000–021102 | th_moisturizer_for_face P2 generic fallbacks | DELETED (rebuilt at 042xxx) |
| SKU-022000–022176 | th_toothpaste v1 | DELETED (rebuilt at 047xxx) |
| SKU-023000–023843 | Formula milk QA fix | ACTIVE |
| SKU-024000–024011 | Pet food TYPE_CONFLICT fix | ACTIVE |
| SKU-025000–025008 | Baby lotion/oil TYPE_CONFLICT fix | ACTIVE |
| SKU-026000–026326 | th_liquid_milk full rebuild | ACTIVE |
| SKU-027000–027332 | th_liquid_milk multiplier + Oatside fix | ACTIVE |
| SKU-028000–028002 | moisturizer_for_face LRP B5+ fix | ACTIVE |
| SKU-029000–029005 | Nekko taxonomy | ACTIVE |
| SKU-030000–030199 | Pet food wet pack-count variants | ACTIVE |
| SKU-031000–031018 | Purina ONE size fix | ACTIVE |
| SKU-032000–034290 | Pet food dry food size expansion | ACTIVE |
| SKU-035000–036021 | Quality gap fixes (body moisturizer, body wash) | ACTIVE |
| SKU-037000–039088 | th_moisturizer_for_body REBUILT | ACTIVE |
| SKU-040000–040096 | Body moisturizer QA pack-count + Clear Nose | ACTIVE |
| SKU-041000–041309 | th_softdrink REBUILT + QA | ACTIVE |
| SKU-041310–041999 | softdrink future expansion | EMPTY |
| SKU-042000–042526 | th_moisturizer_for_face REBUILT | ACTIVE |
| SKU-043000–043999 | RESERVED | EMPTY |
| SKU-044000–044999 | DELETED (body_wash v2, superseded) | DEAD |
| SKU-045000–045231 | th_drinking_water quality pass (bulk packs) | ACTIVE |
| SKU-045232–046999 | EMPTY (collision zone cleaned) | EMPTY |
| SKU-047000–053004 | th_toothpaste REBUILT + QA passes | ACTIVE |
| SKU-053005–054098 | th_shampoo REBUILT | ACTIVE |
| SKU-055000–055022 | th_toothpaste quality pass 3 | ACTIVE |
| SKU-055023–056999 | EMPTY | EMPTY |
| SKU-057000–058455 | th_body_wash v3 (P2 + P1 + Linee/Lab Smile fixes) | ACTIVE |
| SKU-098346–100345 | shopee_sg_coffee LLM P1 + P2 head | ACTIVE |
| SKU-100346–102345 | shopee_id_makeup_face (concurrent session, not this run) | ACTIVE |
| SKU-102346–102519 | shopee_sg_coffee LLM P2 tail catch-alls | ACTIVE |
| SKU-102520–103845 | shopee_sg_coffee supplemental block, unused remainder | ACTIVE |
