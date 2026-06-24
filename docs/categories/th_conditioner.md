# shopee_th_conditioner — Category Context

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete |
| LLM Pass 2 | ✅ Complete |
| GMV Coverage | ~80% (Apr 2026) |
| Last run | Jun 21 2026 |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-011088–011322 | Full taxonomy (235 entries, 29 brands) |

---

## Brand Scope

30 official-store brands: Kérastase, Farger, L'Oreal Professionnel, Pantene/P&G, Lyo, The Ordinary, Nigao, Daeng Gi Meori, Dr.Pong, Dove/Unilever, L'Oreal Paris, Olaplex, Yves Rocher, Vichy, Yanhee, clear/Unilever, Divyne, Go Hair, Fino, My Organic, Lolane, TRESemmé, Herrmetto, Tsubaki, Sunsilk, &honey, Dcash, Shiseido, Nectapharma.

**&honey brand note:** TH products use BRD-SG-03756 (＆honey) in product_brand_map; taxonomy inserted under BRD-GLOBAL-00237. Both brand_ids should route to the same taxonomy entries.

**3 brand mismatches from Pass 1:** Hair+ official store sells Vichy, Pantene, and Ririko products — flagged brand_mismatch=TRUE for those.

---

## Scope Notes

Include: hair conditioner, hair mask/treatment, deep conditioning treatment, leave-in conditioner.
Exclude: shampoo (separate category), hair serum/oil (different sub-category).

---

## Map Row Counts (Jun 21 2026)

| Source | Count | Notes |
|--------|-------|-------|
| LLM/OFFICIAL | 722 | Pass 1 (725 products, 3 skipped for brand mismatch) |
| LLM/RESELLER | 1,184 | Pass 2 |
| HUMAN | 1,595 | Deleted (superseded) |
