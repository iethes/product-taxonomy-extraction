# shopee_th_pet_food — Category Context

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete |
| LLM Pass 2 | ✅ Complete |
| GMV Coverage | ~85% (Apr 2026) |
| Last run | Jun 22 2026 (5 QA passes) |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-017000–017553 | Core LLM taxonomy (554 entries, 131 brands) |
| SKU-024000–024011 | TYPE_CONFLICT fix — wet food entries |
| SKU-029000–029005 | Nekko taxonomy (wet pouch x1/x12/x24/x48, wet can, dry) |
| SKU-030000–030199 | Bulk wet pack-count variants (x12/x24/x48/x60) |
| SKU-031000–031018 | Purina ONE size fix (19 entries) |
| SKU-032000–034290 | Dry food size expansion (2,291 entries) |

---

## Brand Scope

131 official-store brands. Key brands:

**Cats:**
- Royal Canin (97 entries: dry + wet + vet diet per species × life stage)
- Whiskas (dry + wet × sizes)
- Hill's Science Diet + Prescription Diet
- Purina (ONE / Felix / Fancy Feast / Friskies / Pro Plan)
- Me-O, Kaniva, SmartHeart
- Nekko (wet pouch + wet can + dry holistic)

**Dogs:**
- Pedigree (dry × sizes)
- Royal Canin (separate from cat entries — never share)
- SmartHeart Gold
- LOLA&CO

**Multi-brand Mall retailers EXCLUDED from allowlist:**
- PET N ME, PetPaw, Lotuss, BigC, Tops

---

## Scope — What's In vs Out

**In scope:** All pet food for cats and dogs

**Critical rules:**
- **Wet food and dry food must have SEPARATE taxonomy entries** — never merge
- **Cat and dog NEVER share a taxonomy entry** — species separation is mandatory
- Entry canonical name must include species AND food type: `"Royal Canin Dry Cat Food Indoor Adult 4kg"` not just `"Royal Canin Indoor Adult 4kg"`

---

## Taxonomy Design Notes

**Royal Canin routing (complex — 97 entries, keyword router required):**
- Priority: vet diet (neutral) → specific wet cat → specific wet dog → dry by breed/size
- `is_wet_canonical()` must use `\b` word boundary to avoid false-positive "can" substring in "Royal Canin"
- 60+ routing rules in `fix_rc_routing_v2.py`
- 601 products fixed in Session 37 (22M THB)

**Dry food size extraction:**
- All 323 base dry food TIDs had NULL size originally
- Expanded to 2,291 size-specific entries (SKU-032000–034290)
- Parse: kg/g patterns + multipliers (x2/x4/x12/x24/x48, ยกลัง, N ฟรี M)
- 9,893 products rerouted; 4,327 with no parseable size remain at base catch-alls

**Wet food bulk pack-count:**
- 200 new entries (SKU-030000–030199) for x12/x24/x48/x60 variants
- Detect: ยกลัง + Thai quantity keywords
- 1,761 products rerouted from pack_count=1 base entries

---

## QA History

| Date | Session | Finding | Resolution |
|------|---------|---------|------------|
| Jun 22 | 34 | 849 Cat TC (wet→dry), 277 Dog TC (cross-species) | 12 new wet entries; TYPE_CONFLICT→0 |
| Jun 22 | 37 | 601 Royal Canin misrouted (22M THB) | Keyword router v2; all fixed |
| Jun 22 | 37 | Nekko all HUMAN | SKU-029000–029005; 284 HUMAN→290 LLM |
| Jun 22 | 39 | Bulk wet pack_count=1 for ยกลัง 48ซอง listings | 200 new pack-count variant entries |
| Jun 22 | 40 | All 323 dry food TIDs had NULL size | 2,291 new size-specific entries |

---

## Map Row Counts (Jun 22 2026)

| Source | Count | Notes |
|--------|-------|-------|
| LLM/OFFICIAL | 4,515 | Pass 1 |
| LLM/RESELLER | 9,440 | Pass 2 keyword routing |
| LLM (QA additions) | ~3,000 | Type conflict fix + size expansion |
| HUMAN | 6,033 | Long-tail out-of-scope |
| Total universe rows | ~87,000 | sincere (post dry-size expansion) |
