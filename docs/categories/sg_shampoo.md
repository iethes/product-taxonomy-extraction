# shopee_sg_shampoo — Category Context

> First-ever LLM extraction attempt for this category — SG has 0/23 categories LLM-extracted per
> `docs/categories/STATUS.md`. Written as part of the headless-taxonomy-runbook worked example
> (`docs/plans/headless-taxonomy-runbook-implementation-plan.md` Task 6). Brand/store data below is real,
> pulled live from `magpie.marketshare_universe_niq` on 2026-07-15. **Correction (2026-07-15, after the first
> live `claude -p` attempt):** this file originally claimed the category had zero existing map rows — wrong,
> never actually checked. It has 2,255 `HUMAN` (keyword-seed) rows already. See Map Row Counts and Scale below
> — both sections were rewritten after the first headless attempt caught this and correctly refused to proceed
> without it being addressed explicitly.

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ❌ Not started |
| LLM Pass 2 | ❌ Not started |
| Keyword-seed (HUMAN) coverage | 2,255 rows in `product_taxonomy_map`, `source='HUMAN'` — verified live 2026-07-15 |
| GMV Coverage (LLM) | 0% |
| Last run | Never (one aborted headless attempt 2026-07-15 — stopped itself before writing, see QA History) |
| Current MAX taxonomy_id (as of 2026-07-15) | SKU-068015 — **re-verify live before claiming, never trust this number** |

---

## Scale (verified live 2026-07-15 — read before writing any extraction prompt)

- **1,615,309 total rows** in `master_clean_niq.shopee_sg_shampoo`.
- **187,902 rows** with `merchant_badge = 'Shopee Mall'` (candidate Pass 1 official-store pool, before
  narrowing to the actual allowlist below — the allowlist covers a small fraction of this).
- This is **too large for a single `claude -p` session to read image-by-image**. The first live attempt
  correctly refused to improvise a brand-match/size/embedding cascade against this volume with no existing
  pipeline code to lean on. Any extraction prompt for this category must scope Pass 1 to the *allowlist*
  merchant names below (not all 187,902 Mall rows), and make Pass 2 primarily bulk SQL text-matching against
  the Pass 1 taxonomy — vision reads only for products that don't resolve confidently via text. Do not ask a
  headless session to vision-read hundreds of thousands of products; that was never the intent, but the first
  prompt was ambiguous enough that a careful agent read it as requiring exactly that.

---

## SKU Blocks Assigned

| Block | Usage | Status |
|-------|-------|--------|
| SKU-069001–SKU-070000 | Full Rebuild attempt #1 | Claimed 2026-07-15, `status='ACTIVE'` in `sku_block_registry`. Nothing was written under it — the first attempt stopped before any insert. **Safe to reuse for attempt #2** rather than claiming a new block, since zero rows exist under this range (verify with a quick `COUNT(*) FROM product_taxonomy WHERE taxonomy_id BETWEEN 'SKU-069001' AND 'SKU-070000'` before reusing, don't just trust this note). |

Claim atomically at run time per `docs/headless-runbook.md` § Atomic SKU block claim if this block is ever
marked `FAILED_QA`/`COMPLETE` or exhausted — do not pre-assign a new static block while this one is still valid
and unused.

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

Not yet written — no successful extraction has run. Fill in during Pass 1 per `docs/categories/_TEMPLATE.md`'s
structure.

---

## Existing HUMAN rows — disposition policy

2,255 `source='HUMAN'` rows exist in `product_taxonomy_map` for this category (automated keyword-routing from
an earlier seed pass — per `docs/decisions/ADR-006`, `HUMAN` does **not** mean an actual person reviewed them).
This is a **Full Rebuild**, and Full Rebuild's own definition already answers what happens to them (per
`docs/plans/headless-taxonomy-runbook-design.md`'s Per-scenario differences table: "Delete old category rows,
rebuild taxonomy + map from scratch") — **these rows are superseded**, matching the TH Liquid Milk Full Rebuild
precedent.

**Timing matters — delete only after, never before:**
1. Pass 1 + Pass 2 build new LLM taxonomy first.
2. QA gates run and pass (including the HUMAN+LLM co-existence check — it will legitimately fail while old
   HUMAN rows and new LLM rows briefly coexist mid-session; that's expected during the session, not a reason to
   stop).
3. Only then delete the stale HUMAN rows:
   ```sql
   DELETE FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
   WHERE master_table = 'shopee_sg_shampoo' AND source = 'HUMAN';
   ```
4. Re-run QA gates after the delete to confirm the co-existence check now passes cleanly.

Deleting HUMAN rows *before* Pass 1/2 finish would leave those 2,255 products with no taxonomy at all if the
session fails partway through — worse than what exists today. Build first, verify, delete last.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-15 | Headless attempt #1 (Full Rebuild) | Session correctly stopped before writing: found 2,255 undocumented HUMAN rows (this file wrongly said 0), ambiguous instruction about whether the agent itself performs extraction or needs `ANTHROPIC_API_KEY` for a subprocess, and 187,902-row official-store pool too large for one session to vision-read. | This file corrected (Scale + disposition sections added above); prompt to be rewritten before attempt #2 — see `docs/headless-runbook.md` Full Rebuild scenario. |

---

## Scripts

| Script | Purpose |
|--------|---------|
| `pipeline/05_product_taxonomy/llm_shopee_sg_shampoo/build_taxonomy.py` | Pass 1 extraction (external pipeline repo — not in this repo, see `docs/claude-code-headless-orchestration.md`) |
| `pipeline/05_product_taxonomy/llm_shopee_sg_shampoo/build_p2_taxonomy.py` | Pass 2 routing (external pipeline repo) |

---

## Map Row Counts (verified live 2026-07-15)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 0 | Never run |
| HUMAN | 2,255 | Keyword-seed routing, to be superseded per the disposition policy above — **not** zero, this file was wrong before 2026-07-15 |
| NULL (unmapped) | remainder of 1,615,309 total rows | Most of the category — HUMAN coverage is a small fraction of total volume |
