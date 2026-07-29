# shopee_th_moisturizer_for_face — Category Context

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete (rebuilt Jun 23) |
| LLM Pass 2 | ✅ Complete |
| GMV Coverage | 85.6% (Apr 2026) |
| Last run | Jun 23 2026 |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-042000–042424 | Pass 1 OFFICIAL (336 entries, 52 brands) |
| SKU-042500–042526 | Pass 2 catch-alls (27 entries, brands with no existing taxonomy) |
| SKU-028000–028002 | LRP Cicaplast B5+ size fix (3 entries) |
| SKU-003231–003352 | Granular v2 seed entries (retained, 109 entries) |
| SKU-003547–003936 | DELETED (v1 LLM Pass 1, superseded) |
| SKU-021000–021102 | DELETED (v1 Pass 2 generic fallbacks, superseded) |

---

## Brand Scope (GMV threshold 95%, Apr 2026)

52 brands with official stores (Pass 1). 292 brands in Pass 2 reseller scope.

**Key brands:**
- Smooth E (Babyface / Hyaluron / Vitamin C / Glutathione / Acne)
- Hada Labo (Gokujyun / Shirojyun / Premium lines)
- Srichand (Translucent / Sunscreen / Acne range)
- Kiehl's (Ultra Facial / Rare Earth / Midnight Recovery)
- Innisfree (Green Tea Seed Cream / Serum)
- Lancôme (Advanced Génifique / Idôle)
- Shiseido (Ultimune / Vital Perfection)
- Sulwhasoo (Concentrated Ginseng)
- Clinique (Moisture Surge)
- Elixir, Torriden, FYNE, Cetaphil, Vichy
- d'Alba, numbuzin, Dr.Althea, Physiogel
- Pond's, CureCode, Aestura, + 30 more

**Pass 2 catch-all brands (SKU-042500–042526):**
- S-ERUM, Mesoestetic, La Mer, SK-II, Rejuran, PURITO SEOUL, + 21 more

---

## Scope — What's In vs Out

**In scope:**
- Face moisturizer, face cream, face serum, face gel, face essence
- Eye cream (if in this NIQ category)
- Face sleeping mask

**Out of scope (leave NULL):**
- Body moisturizer → `moisturizer_for_body` category
- Sunscreen (SPF products) → `suncare` category
- Face cleanser → `cleanser` category
- Hair serum, shampoo, conditioner
- Toothpaste, coffee, detergent (all found as contamination in Session 38)

**Critical pre-sweep step:** Before any rebuild, query all existing map rows and verify taxonomy entries belong to face moisturizer category. Session 38 found 1,802 contaminated rows (shampoo 473, cleanser 460, makeup 319, body lotion 205, toothpaste 146, coffee 57, hand cream 40, detergent 30). Root cause: seed scripts used global taxonomy search without category filter.

---

## Taxonomy Design Notes

**Sub-line disambiguation required for similar brands:**
- Eucerin: Hyaluron Filler vs AtopiControl vs pH5 — read full sub-line from label
- CeraVe: SA Cleanser vs Blemish Control vs Foaming — different categories
- La Roche-Posay: B5+ vs B5+ SPF50 → SEPARATE entries; `SKU-000046` = B5+ SPF50 40ml, `SKU-028000` = B5+ SPF50 40ml x2, `SKU-028001` = B5+ 15ml, `SKU-028002` = B5+ 100ml x3

**Brand-Brand naming bug (fixed Jun 22):** 120 taxonomy entries had duplicate brand prefix (e.g., "Srichand Srichand Moisturizer 10ml"). Fixed via DML UPDATE: `canonical_name = REGEXP_REPLACE(canonical_name, r'^(\w+) \1 ', r'\1 ')`.

**Nivea routing issue (Jun 23):** 45 Nivea products routed to cleanser catch-all (SKU-000285 "Nivea Cleanser Set") because Thai-dominant sku_names scored 0 in text matching. Fixed with Thai keyword router in `/tmp/face_fix_nivea_cleanup.py`.

---

## QA History

| Date | Session | Finding | Resolution |
|------|---------|---------|------------|
| Jun 23 | 38 | 1,802 wrong-category rows (shampoo/cleanser/makeup in face map) | Deleted wrong rows; re-routed 1,502; 300 left NULL |
| Jun 23 | 38 | LRP B5+ size confusion (14 products at wrong SKU) | SKU-028000–028002 created; rerouted |
| Jun 23 | 38 | 120 Brand-Brand double name entries | DML fix |
| Jun 23 | 47 | Full rebuild: old SKU-003547–003936 + SKU-021000–021102 deleted | SKU-042000–042526 inserted; 85.6% coverage |

---

## Map Row Counts (Jun 23 2026)

| Source | Count | Notes |
|--------|-------|-------|
| LLM/OFFICIAL | 2,210 | Pass 1, 52 brands |
| LLM/RESELLER | 3,786 | Pass 2 routed to existing taxonomy |
| LLM (catch-all, conf=0.55) | 3,945 | Pass 2 catch-alls, 27 brands |
| HUMAN | 2,029 | Long-tail out-of-scope |
| Total universe rows | 101,046 | sincere; 101,187 farsight |
