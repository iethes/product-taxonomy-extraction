# shopee_th_adult_diapers — Category Context

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete |
| LLM Pass 2 | ✅ Complete |
| GMV Coverage | ~85% (Apr 2026) |
| Last run | Jun 20 2026 |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-004547–004841 | Pass 1 OFFICIAL (295 entries, 9 brands) |
| SKU-004842–004935 | Pass 2 RESELLER (94 entries, 9 new brands) |

---

## Brand Scope

20 brands total. **9 brands with official stores (Pass 1):** Tena, Certainty, Friend, Unicharm (MamyPoko Adult), Daio, Lifree, Drypers Adult, Abena, Attends.

**9 Pass-2-only brands:** Uniqare, Andlove, Pullet, HUGHIE, Sumikko, Sunmed, Youli, Sekure, DR klean, NS.

**Brand mismatch issue:** BRD-TH-01939 (NS/Nisuki) had 8 flagged rows — 4 Procare products and 4 NS products from Nisuki store were both mapped to BRD-TH-01939. The brand_from_image distinguishes them.

---

## Taxonomy Design Notes

**Product types:** Diaper Tape, Diaper Pants, Pad/Insert, Underpants. Size: S/M/L/XL.

**Pull-up pants vs tape distinction:** Mandatory. Pull-up pants (กางเกง/pants/pull-up) and tape diapers must have separate taxonomy entries.

---

## Map Row Counts (Jun 20 2026)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 1,025 | Pass 1 + Pass 2 |
| HUMAN | 552 | Deleted (superseded) |
| HUMAN (retained) | varies | Long-tail |
