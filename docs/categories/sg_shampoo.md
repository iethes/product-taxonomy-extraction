# shopee_sg_shampoo — Category Context

> First-ever context file for this category — SG has 0/23 categories LLM-extracted per
> `docs/categories/STATUS.md`. Written as part of the headless-taxonomy-runbook worked example
> (`docs/plans/headless-taxonomy-runbook-implementation-plan.md` Task 6). Brand/store data below is real,
> pulled live from `magpie.marketshare_universe_niq` on 2026-07-15. No extraction has run yet — Taxonomy
> Design Notes and QA History are empty by design.

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ❌ Not started |
| LLM Pass 2 | ❌ Not started |
| GMV Coverage | 0% |
| Last run | Never |
| Current MAX taxonomy_id (as of 2026-07-15) | SKU-068015 — **re-verify live before claiming, never trust this number** |

---

## SKU Blocks Assigned

Not yet claimed. Claim atomically at run time per `docs/headless-runbook.md` § Atomic SKU block claim — do not
pre-assign a static block here, that's exactly the race condition the registry table exists to prevent.

---

## Brand Scope (top 20 by GMV, SG, latest month at time of research)

Pulled live 2026-07-15 from `magpie.marketshare_universe_niq WHERE country='SG' AND category_3='Shampoo'`:

1. **Milbon** — SGD 95,043 GMV, 568 products
2. **Grafen** — SGD 73,619 GMV, 48 products
3. **MadeToBloom** — SGD 73,562 GMV, 9 products
4. **Dr.FORHAIR** — SGD 70,489 GMV, 76 products
5. **Kérastase** — SGD 62,069 GMV, 435 products
6. **Tsubaki** — SGD 57,941 GMV, 104 products
7. **Diane** — SGD 56,039 GMV, 208 products
8. **UNOVE** — SGD 55,836 GMV, 33 products
9. **Dr.ville** — SGD 55,428 GMV, 32 products
10. **NARD** — SGD 52,026 GMV, 33 products
11. **sukin** — SGD 50,789 GMV, 33 products
12. **Phytopecia** — SGD 41,863 GMV, 19 products
13. **Shiseido Professional** — SGD 41,261 GMV, 182 products
14. **Off&relax** — SGD 40,432 GMV, 104 products
15. **Suu Balm** — SGD 37,828 GMV, 20 products

Brands 16–20 (Hair+, KUNDAL, Aveda, Har, Fayre Beauty) sit close behind #15 — re-run the GMV query at claim
time and confirm the actual 95%-threshold cutoff before finalizing scope; this file captures a snapshot, not a
frozen boundary.

`brand_id` values were not resolved in this research pass (would require joining to `magpie_reference.brand_dict`)
— do that as the first step of Pass 1, not assumed here.

---

## Official Store Allowlist (Pass 1)

Pulled live 2026-07-15 from `merchant_badge = 'Shopee Mall'` rows. Exact merchant names, not a
`LIKE '%official%'` wildcard, per `docs/llm-extraction-rules.md` §4:

| Brand | Official Store Merchant Name |
|-------|------------------------------|
| Shiseido Professional | `Shiseido Professional` |
| Daeng Gi Meori | `Daeng Gi Meo Ri Official Store` |
| Grafen | `Grafen Korea Official Store` |
| KUNDAL | `KUNDAL SG` |
| NaturVital | `NaturVital Official Store` |
| Dr.FORHAIR | `Dr.FORHAIR KOREA OFFICIAL STORE` |
| Diane | `Mandom Official Store` |
| Schwarzkopf | `Schwarzkopf` |
| Himalaya | `Himalaya Official Store` |
| O'right | `O'right Official Store` |
| ＆honey | `Cosme Flagship Store` |
| Lakme | `LAKMÉ Official Store` |
| Klorane | `Klorane Official Flagship Store` |
| Fanola | `Fanola Official Store Singapore` |
| Ryo | `AMOREPACIFIC Hair&Beauty Shop` |
| Kevin Murphy | `WOOSHOP Singapore` |
| Herbal Essences | `P&G Beauty Official Store` |
| Bananal | `RAUM Korea` |
| Pantene | `P&G Official Store` |
| Dove | `Unilever Official Store` |
| Amos Professional | `Amos Professional SG Official Mall` |
| Head & Shoulders | `P&G Official Store` |
| NARD | `Nard Store` |
| Avalon Organics | `Avalon Organics X Official Store` |
| Kérastase | `Kerastase` |

**Multi-brand stores excluded from the allowlist** (per `docs/llm-extraction-rules.md` §4's explicit exclusion
list — Sasa is named there directly):
- `Sasa Official Store` — sells Kérastase among other brands
- `Nana Mall Official Store` — sells Kérastase among other brands
- `Strawberrynet SG Official Store` — sells Kérastase among other brands
- `KimageSalon Official Store` — sells Kérastase among other brands

Note: Kérastase appears under 5 different merchant names in this data (its own store plus 4 multi-brand
retailers) — Pass 1 should use only `Kerastase` (the single-brand store); the multi-brand-store listings are
Pass 2 (reseller) scope, not Pass 1.

P&G Official Store sells both Pantene and Head & Shoulders — a parent-company store covering multiple P&G
brands, not a multi-brand *retailer* in the exclusion sense (`docs/llm-extraction-rules.md` §4's "parent
company store names" pattern, same as Unilever/Dove/Sunsilk/Clear). Keep both brands routed to this store in
Pass 1, disambiguated by product content, not merchant name alone.

**Brands with no official store found in this sample** (Pass 2 only, or store exists but fell outside
`merchant_badge = 'Shopee Mall'` — re-check before assuming no official presence): Milbon, MadeToBloom, Tsubaki,
UNOVE, Dr.ville, sukin, Phytopecia, Off&relax, Suu Balm.

---

## Scope — What's In vs Out

**In scope:** shampoo, 2-in-1 shampoo+conditioner (per the same pattern already established for
`th_body_wash`/`th_fabric_softener` 2-in-1 handling in `docs/llm-extraction-rules.md`).

**Out of scope (leave NULL):** standalone conditioner/hair treatment (separate NIQ category), dry shampoo —
**not confirmed** whether SG's `category_3='Shampoo'` bucket includes dry shampoo as its own line; check the
top-GMV sample at Pass 1 time rather than assuming either way.

**Edge cases:** none identified yet — this file has no prior extraction history to draw edge cases from. Add
rows here as Pass 1/2 reveal them, same convention as every other `docs/categories/*.md` file.

---

## Taxonomy Design Notes

Not yet written — no extraction has run. Fill in during Pass 1 per `docs/categories/_TEMPLATE.md`'s structure.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| — | — | No sessions run yet | — |

---

## Scripts

| Script | Purpose |
|--------|---------|
| `pipeline/05_product_taxonomy/llm_shopee_sg_shampoo/build_taxonomy.py` | Pass 1 extraction (external pipeline repo — not in this repo, see `docs/claude-code-headless-orchestration.md`) |
| `pipeline/05_product_taxonomy/llm_shopee_sg_shampoo/build_p2_taxonomy.py` | Pass 2 routing (external pipeline repo) |

---

## Map Row Counts (as of last run)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 0 | Never run |
| HUMAN | 0 | Never run |
| NULL (unmapped) | all | Full category, per Brand Scope table above |
