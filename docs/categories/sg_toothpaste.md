# shopee_sg_toothpaste — Category Context

> Full Rebuild session, 2026-07-16. First LLM extraction for this category — was "⏳ Keyword only"
> per `docs/categories/STATUS.md` before this run. Source table confirmed as `shopee_sg_toothpaste`
> in `master_clean_niq` (the task that kicked off this file used the short form `sg_toothpaste`,
> which does not exist as a table — `master_table` values everywhere use the full `shopee_sg_toothpaste`
> name, matching the pattern already established for `sg_shampoo` / `shopee_sg_shampoo`).

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete — 519 taxonomy entries, 535 official-store products mapped |
| LLM Pass 2 | ✅ Complete (with documented gaps) — 146 bulk-text-matched + 436 no-official-store-brand catch-all mapped; `Care`/`Hygiene`/`Deep` noise brands and non-matching officially-stored-brand resellers left unmapped |
| GMV Coverage | 92.3% (June 2026), 2,589 of 9,566 distinct products — exceeds the ≥85% Pass 1+2 target in `docs/quality-standards.md` §6 |
| Last run | 2026-07-16 |
| Current MAX taxonomy_id (pre-session, per STATUS.md — NOT trusted, re-verified live before claim) | SKU-058455 (stale — live check at claim time found SKU-070194) |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-072001–SKU-074000 (2000 slots, claimed atomically 2026-07-16, `sku_block_registry` status ACTIVE) | Pass 1 OFFICIAL + Pass 2 RESELLER + structured-field work. Live `MAX(taxonomy_id)` at claim time was SKU-070194 — no collision. |
| SKU-137441–SKU-137743 (303 slots, claimed atomically 2026-07-23, scenario `taxonomy_topup`, `sku_block_registry` status ACTIVE) | 2026-07-23 top-up session. Only SKU-137441–SKU-137641 (201 entries) actually used; SKU-137642–SKU-137743 (102 slots) unused and left in the block. |

---

## Scale (verified live 2026-07-16)

- **697,334 total rows** in `master_clean_niq.shopee_sg_toothpaste`; **12,455 distinct products**;
  data spans `2025-02-01`–`2026-06-01` (17 months). Review month for GMV ranking: **2026-06-01** (latest).
- **73,882 rows** with `merchant_badge = 'Shopee Mall'` (**1,858 distinct Mall products**) — the
  candidate pool before narrowing to the actual allowlist below. Pass 1 must scope to the allowlist
  only (584 distinct products), not the full Mall-badged pool.
- NIQ category tagging within this table is clean: 100% of rows fall under `category_3_EN='Oral Care'`/
  `'Dental Care'` with `category_4/5_EN` = `Toothpastes`/`Toothpaste` — no cross-category contamination
  bucket (unlike e.g. TH body_wash mixing in hand wash). However, individual `sku_name`s inside this
  clean bucket still contain the standard toothpaste-adjacent OOS patterns (row counts, all months):
  oil pulling 145, candy/lozenge 2,881, denture 977, mouthwash-as-main 237, toothbrush-as-main 2,542.
  These are excluded from both the brand-scope GMV ranking and taxonomy building (see Scope below).
- **Pass 1 pool: 584 distinct products** across the 20-entry Official Store Allowlist below.
- **Pass 2 pool: 3,950 distinct products** — remaining products under the 44 in-scope brands, sold
  outside the allowlisted stores (resellers, multi-brand Mall retailers, non-Mall sellers).
- Remaining ~7,950 distinct products in the category are below the 95%-GMV brand threshold or
  `BRD-UNDEFINED`/long-tail — legitimately left `UNRESOLVED` per `docs/llm-extraction-rules.md` §5.

---

## Existing map rows (Step 1 — do not assume 0/0)

```sql
SELECT source, COUNT(*) FROM product_taxonomy_map WHERE master_table = 'shopee_sg_toothpaste' GROUP BY source;
```

| Source | Count |
|--------|-------|
| HUMAN | 1,534 |
| LLM | 0 |

1,534 pre-existing `source='HUMAN'` rows (automated keyword-seed routing, per `ARCHITECTURE.md`
Decision 18 — not actual human review). Per the manager-confirmed policy already applied to
`sg_shampoo` (2026-07-16): **do not delete any HUMAN rows during this session.** Deletion of
HUMAN rows that duplicate a newly-created LLM row for the same product is a separate, deliberately
manual/wrapper-side step performed after this session, never something this session does itself.

---

## Brand Scope (real cumulative-GMV 95% threshold, GWP-zeroed, review month 2026-06-01)

Computed by ranking brands by `SUM(IF(flag_GWP, 0, gmv_monthly))` over **in-scope sku_names only**
(excludes oil pulling / candy-lozenge / denture / mouthwash-as-main / toothbrush-as-main rows —
see Scope section), joined through `product_brand_map`. Cumulative fraction crosses 95% at rank 44
(Sun Star, 95.09%) — **44 brands in the real threshold**, not a fixed top-N snapshot.

| # | Brand | brand_id | GMV (June 2026, SGD) | Cum. % |
|---|-------|----------|----------------------|--------|
| 1 | Sensodyne | BRD-GLOBAL-00101 | 76,195 | 19.70% |
| 2 | Colgate | BRD-GLOBAL-00043 | 74,419 | 38.94% |
| 3 | Dr.ville | BRD-GLOBAL-00875 | 46,391 | 50.93% |
| 4 | Elgydium | BRD-SG-01398 | 29,279 | 58.50% |
| 5 | Pearlie White | BRD-GLOBAL-01781 | 16,033 | 62.65% |
| 6 | Darlie | BRD-GLOBAL-00420 | 11,639 | 65.66% |
| 7 | *(BRD-UNDEFINED — 10,818 GMV, 68.45% cum.; not a real brand, counted in the denominator only, excluded from allowlist work)* | | | |
| 8 | GUM | BRD-GLOBAL-00990 | 8,570 | 70.67% |
| 9 | Zenyum | BRD-SG-02801 | 6,445 | 72.33% |
| 10 | KORMESIC | BRD-GLOBAL-01932 | 6,344 | 73.98% |
| 11 | Dentiste | BRD-GLOBAL-00064 | 6,136 | 75.56% |
| 12 | Parodontax | BRD-GLOBAL-00323 | 6,105 | 77.14% |
| 13 | GC | BRD-SG-01154 | 5,694 | 78.61% |
| 14 | Marvis | BRD-GLOBAL-00363 | 4,980 | 79.90% |
| 15 | Ora2 | BRD-GLOBAL-00809 | 4,601 | 81.09% |
| 16 | Bioniq | BRD-SG-02874 | 4,448 | 82.24% |
| 17 | Oral-B | BRD-GLOBAL-00081 | 3,882 | 83.24% |
| 18 | BOTANICA CULTURE | BRD-SG-02817 | 3,463 | 84.14% |
| 19 | Apagard | BRD-SG-00601 | 3,353 | 85.00% |
| 20 | Care *(brand_dict noise — see Edge cases)* | BRD-GLOBAL-00623 | 2,901 | 85.75% |
| 21 | Curaprox | BRD-GLOBAL-00246 | 2,529 | 86.41% |
| 22 | Atomy | BRD-GLOBAL-00813 | 2,365 | 87.02% |
| 23 | Red Seal | BRD-GLOBAL-02029 | 2,254 | 87.60% |
| 24 | KAGAMI | BRD-SG-04285 | 2,182 | 88.17% |
| 25 | Systema | BRD-GLOBAL-00178 | 2,127 | 88.72% |
| 26 | Crest | BRD-GLOBAL-01391 | 2,068 | 89.25% |
| 27 | SSBB | BRD-SG-01083 | 1,871 | 89.73% |
| 28 | Daiichi Sankyo Healthcare | BRD-SG-03925 | 1,710 | 90.18% |
| 29 | SPLAT | BRD-SG-04195 | 1,693 | 90.61% |
| 30 | Median | BRD-GLOBAL-01340 | 1,685 | 91.05% |
| 31 | Nuskin | BRD-GLOBAL-00872 | 1,372 | 91.41% |
| 32 | Lion | BRD-GLOBAL-00873 | 1,324 | 91.75% |
| 33 | Oral7 | BRD-SG-03899 | 1,270 | 92.08% |
| 34 | ISME Rasyan | BRD-SG-04668 | 1,257 | 92.40% |
| 35 | Deep *(brand_dict noise — see Edge cases)* | BRD-SG-12678 | 1,224 | 92.72% |
| 36 | NARD | BRD-GLOBAL-00703 | 1,150 | 93.01% |
| 37 | TOOTH NOTE | BRD-GLOBAL-02432 | 1,118 | 93.30% |
| 38 | YunNan BaiYao | BRD-SG-04032 | 1,079 | 93.58% |
| 39 | ZAITUN | BRD-SG-05435 | 1,042 | 93.85% |
| 40 | Amway | BRD-GLOBAL-00300 | 986 | 94.11% |
| 41 | Hygiene *(brand_dict noise — see Edge cases)* | BRD-GLOBAL-00020 | 982 | 94.36% |
| 42 | Enzim | BRD-SG-04448 | 966 | 94.61% |
| 43 | Himalaya | BRD-GLOBAL-00470 | 944 | 94.85% |
| 44 | Sun Star | BRD-GLOBAL-01327 | 919 | 95.09% |

Brands ranked below Sun Star (95.09%+) are outside the 95% threshold and may legitimately remain
`UNRESOLVED` per `docs/quality-standards.md` §2.

**Edge case — noise brand_dict entries:** `Care` (BRD-GLOBAL-00623), `Hygiene` (BRD-GLOBAL-00020),
and `Deep` (BRD-SG-12678) are registered brand_dict rows whose `canonical_name` is a generic English
word, almost certainly an artifact of brand-string matching against generic sku_name tokens rather
than a real company. No dedicated official-store allowlist entry was built for them — during
extraction, use `brand_from_image`/full sku_name text to identify the real brand for these products
rather than trusting the `Care`/`Hygiene`/`Deep` brand_id label.

---

## Official Store Allowlist (Pass 1)

Built by querying, for each of the 44 scope brands, which `merchant_badge='Shopee Mall'` stores
actually carry that brand (via `product_brand_map`), then classifying each store as single/parent-brand
(keep) vs. multi-brand retailer (exclude), per `docs/llm-extraction-rules.md` §4.

| Brand(s) | brand_id | Official Store Merchant Name |
|----------|----------|-------------------------------|
| Colgate | BRD-GLOBAL-00043 | `Colgate Official Store` |
| Darlie | BRD-GLOBAL-00420 | `Darlie Official Store` |
| Dentiste | BRD-GLOBAL-00064 | `Dentiste Official Store` |
| Dr.ville | BRD-GLOBAL-00875 | `Dr.ville SG Office Store` (current name, active 2026-06+) and `DrvilleofficialStore.sg` (same store, prior name, active 2025-02–2026-05 — same merchant, renamed mid-dataset) |
| Pearlie White | BRD-GLOBAL-01781 | `Pearlie White Official Store` |
| Himalaya | BRD-GLOBAL-00470 | `Himalaya Official Store` |
| Curaprox | BRD-GLOBAL-00246 | `Curaprox Official Store` and `CURAPROX_SG OFFICIAL` (two store-name variants seen across months) |
| Apagard | BRD-SG-00601 | `DENTALPRO/APAGARD SG Official Store` |
| Zenyum | BRD-SG-02801 | `Zenyum Official Store` |
| Enzim | BRD-SG-04448 | `enzim.sg` (confirmed single-brand: 10 Enzim products, 3 brand-unresolved, no other brand) |
| Bioniq | BRD-SG-02874 | `Dr. Wolff Official Store` |
| NARD | BRD-GLOBAL-00703 | `Nard Store` |
| YunNan BaiYao | BRD-SG-04032 | `Science Arts Official Store` |
| SPLAT | BRD-SG-04195 | `SPLAT Official Store` |

**Parent-company stores (Pass-1-eligible for every brand they carry, per `docs/llm-extraction-rules.md` §4):**
- `Haleon Official Store` — Sensodyne (BRD-GLOBAL-00101) + Parodontax (BRD-GLOBAL-00323). Haleon is
  the parent consumer-health company for both brands.
- `P&G Official Store` — Oral-B (BRD-GLOBAL-00081) + Crest (BRD-GLOBAL-01391).
- `LION Official Store` — Systema (BRD-GLOBAL-00178) + Lion (BRD-GLOBAL-00873).
- `Aurigamart Official Store` — Ora2 (BRD-GLOBAL-00809) + GUM (BRD-GLOBAL-00990) + Sun Star
  (BRD-GLOBAL-01327) — confirmed live: 7 of 8 named-brand products under this store are Sunstar-family
  brands (Ora2/GUM/Sun Star are all Sunstar Group brands); 1 product is SATO PHARMACEUTICAL (not in
  scope) — flag that single product for `brand_from_image` disambiguation rather than assuming it's
  Sunstar, same pattern as any parent-company store carrying an occasional adjacent product.

**Multi-brand retailers excluded from the allowlist** (Mall-badged but sell many unrelated
in-scope brands — routed to Pass 2 bulk-text-matching instead, per §4's explicit exclusion list):
`BIG Pharmacy`, `Guardian SG Official Store`, `Farmasi C S`, `Watsons Singapore Official Store`,
`Sasa Official Store`, `Nana Mall Official Store`, `HEY SUP`, `J-Mart Official`,
`Strawberrynet SG Official Store`, `Neighbor Good Shopping Official`, `DON DON DONKI Official Store`,
`MR DIY Official Store`, `Ren Ren Pharmacy Official`, `Thrillion Items Offiicial`,
`Cosmede Official Store`, `RGAR.sg`, `Global Buyer`, `K.O.I STORE VN`, `Braun Official Store`,
`Easyout SG Local Store`, `KAZOO Mall Store`, `SGPomades Mens Grooming Store`,
`Corlison Official Store`, `Tsupply Official Store`, `junhe.sg`, `Oral Oasis`,
`BEAUTY U & ME.SG Official Store`.

**Brands with no confirmed official store (Pass 2 only):** Elgydium, KORMESIC, GC, Marvis,
BOTANICA CULTURE, Atomy, Red Seal, KAGAMI, SSBB, Daiichi Sankyo Healthcare, Median, Nuskin, Oral7,
ISME Rasyan, TOOTH NOTE, ZAITUN, Amway (Atomy/Amway/Nuskin are direct-sales companies with no
marketplace-badged own-store, as expected).

**Pass 1 pool size: 584 distinct products** across the 20 store-name entries above (verified live).

---

## Scope — What's In vs Out

Per `docs/llm-extraction-rules.md` §5's existing `toothpaste` row:

**In scope:** toothpaste, tooth serum, tooth gel, whitening serum, enamel repair.

**Out of scope (leave NULL):**
- toothbrush (unless GWP — a free toothbrush bundled with a toothpaste purchase is fine, pack_count
  rules apply to the toothpaste; a toothbrush *as the main product* is OOS)
- mouthwash (as the main/only product in the listing — a GWP mouthwash sample bundled with toothpaste
  is fine)
- oil pulling products
- candy/lozenge (ลูกอม-equivalent — breath mints/candy, not toothpaste)
- denture cleanser — Polident-style products are hard OOS at the brand level

**Edge cases:**
- `Care`, `Hygiene`, `Deep` brand_dict entries are almost certainly generic-word matching noise, not
  real single companies — see Brand Scope edge case above. Use `brand_from_image` + full sku_name to
  find the real brand for these products.
- `Aurigamart Official Store`'s 1 SATO PHARMACEUTICAL product — disambiguate via image, don't assume
  it's a Sunstar product just because the store mostly carries Sunstar brands.

---

## Taxonomy Design Notes

**Product line extraction approach:**
- Most brands here: extract product line directly from `sku_name` (SG listings are English-first,
  much cleaner than TH Thai-mixed listings — no Thai-specific parsing needed for this category).
- Parent-company stores (Haleon, P&G, LION, Aurigamart): disambiguate which of the parent's brands a
  given listing belongs to using the brand keyword actually present in `sku_name`/`option_name`
  (Sensodyne vs Parodontax; Oral-B vs Crest; Systema vs Lion; Ora2 vs GUM vs Sun Star), not by
  assuming one brand for the whole store.

**Size extraction notes:**
- Primary unit: g (most SG toothpaste tubes) or ml (gel/liquid formats).
- `product_specs` (structured JSON field in this table, equivalent to `raw_niq_history.product_specification`
  elsewhere) contains `Stock`, `Shelf Life`, `Oral Care Benefits`, `Pack Type`, `Formulation`, `Ships From`
  — **no explicit size/weight field** in the spec structure observed so far; size must come from
  `sku_name`/`option_name` text or image, per the standard priority chain in
  `docs/llm-extraction-rules.md` §2.
- `option_name`/`option_name_EN` holds per-variant option labels (flavor, size choice) — check this
  field before falling back to image for multi-option listings.

**Known difficult products:**
- Dr.ville has two product formats under one brand: a "tube" line (confirmed 100g across multiple
  sibling listings) and a "Mousse"/"Thermosensitive" sub-line (different format, no confirmed size
  anywhere in the Pass 1 pool — left genuinely unresolved rather than guessed).
- Dentiste's storefront prefixes almost every listing with "Dentist Bundle of 6 ..." — initially
  read as ambiguous marketing language, but cross-referencing against Zenyum's identical
  "Bundle of N - {product}" convention (where N is a confirmed real multiplier) showed this is a
  genuine pack_count=6, not a tier/marketing label. A first extraction pass under-counted this because
  the pack_count regex only matched bracketed `[Bundle of N]`/`(Bundle of N)` forms, missing the bare
  (unbracketed) `Bundle of N` form used by Dentiste, Zenyum, and Enzim — fixed before insert.
- Two Dentiste "Bundle of 6 Premium & Natural Mouthwash" listings were caught and excluded — mouthwash
  as the main product is OOS per scope rules, and would otherwise have been silently swept up in the
  same catch-all pattern as legitimate toothpaste listings.
- Enzim's per-listing sku_names frequently omit the tube size (e.g. `[3Pack]`, `[2 Pack]` variants)
  even though every sibling listing that does state a size says 100g — size backfilled by sibling-line
  inference (`docs/llm-extraction-rules.md`'s "sibling listings from the same brand/line" precedent),
  not guessed from nothing.

---

## Pass 1 — Official Store Extraction (done 2026-07-16)

**Method:** primarily text-based (`sku_name`/`option_name` decomposition), not exhaustive per-product
image reads — SG listings are far more descriptive and English-complete than TH Thai-mixed ones, so
text alone resolved size/pack_count/product_line for the large majority of the 584-product allowlist
pool. This mirrors the `sg_shampoo` precedent ("image verification used where text was genuinely
ambiguous, not by default"). Confidence recorded at **0.8** (text-based, not 0.85–0.99) to reflect this
honestly rather than overstating verification method.

- **519 taxonomy entries created** (`SKU-072001`–`SKU-072519`), covering **535 of 584** allowlist
  products (91.6%).
- **49 products intentionally left unmapped** from the allowlist pool: 2 SATO Pharmaceutical products
  at Aurigamart (not a scoped brand), 2 mouthwash-as-main-product OOS listings, several genuine
  mystery/surprise/brand-box bundles whose composition can't be determined from text (Darlie, Sensodyne,
  Pearlie White brand boxes), 1 toothbrush-only listing miscategorized into this table (SPLAT), and a
  handful of single-product entries with no confirmed size anywhere in the sibling pool.
- Structured fields: **509 of 509 non-catch-all entries have `product_line` and `size` populated
  (100%)**; `variant` populated for 89 (17.5%, matches the expectation that variant is optional and
  only genuine signal-bearing) — decomposed at insert time, not backfilled after the fact.
- 10 of the 519 entries are legitimate kit/assortment sets (`is_multi_variant=TRUE`, `size=NULL`) —
  Colgate/Curaprox/Darlie/Zenyum/Enzim combo packs with no single tube size.

## Pass 2 — Reseller Routing (done 2026-07-16)

- **146 products bulk-text-matched** to existing Pass 1 taxonomy entries via SQL substring matching
  (`sku_name` contains the taxonomy entry's `product_line` text and `size`), scoped per-brand,
  confidence **0.75**.
- **17 catch-all entries created** (`SKU-072520`–`SKU-072536`, `is_multi_variant=TRUE`,
  `is_multi_size=TRUE`, size/pack_count/product_line all NULL) for the brands confirmed to have no
  official store: Elgydium, KORMESIC, GC, Marvis, BOTANICA CULTURE, Atomy, Red Seal, KAGAMI, SSBB,
  Daiichi Sankyo Healthcare, Median, Nuskin, Oral7, ISME Rasyan, TOOTH NOTE, ZAITUN, Amway.
  **436 products mapped** to these catch-alls, confidence **0.6**.
- **Not addressed this session:** the `Care`/`Hygiene`/`Deep` brand_dict noise entries (see Edge cases
  above — not real distinguishable brands, no taxonomy built for them) and the residual
  officially-stored-brand resellers that didn't bulk-text-match (their listings don't contain the exact
  Pass 1 product_line text — would need either looser fuzzy matching or individual image reads to
  resolve, deliberately not attempted here to avoid false-positive routing into the wrong SKU).
- Overall category GMV coverage after Pass 1+2: **92.3%** (June 2026 review month), exceeding the
  ≥85% Pass-1+Pass-2 target in `docs/quality-standards.md` §6.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-16 | Step 0–2 (category research) | Task prompt used short table name `sg_toothpaste`, which doesn't exist — actual table is `shopee_sg_toothpaste` (matches the established `sg_shampoo`/`shopee_sg_shampoo` naming convention). 1,534 pre-existing HUMAN map rows found (not 0 as an untested assumption might suggest). Real 95%-GMV brand threshold is 44 brands (not a fixed top-N guess). | This file written with the full table name used throughout; existing HUMAN rows documented, left untouched; full 44-brand list and 20-entry allowlist recorded below rather than a truncated snapshot. |
| 2026-07-16 | Pass 1 extraction | Initial pack_count regex only matched bracketed `[Bundle of N]`/`(Bundle of N)` forms — missed the bare (unbracketed) `Bundle of N` form used throughout Dentiste, Zenyum, and Enzim listings, silently defaulting ~20 entries to pack_count=1. | Caught by spot-checking a random sample before insert (not after) — regex extended to a bare `\bbundle of (\d+)\b` pattern, whole extraction pipeline re-run before any BigQuery write. |
| 2026-07-16 | Pass 1 extraction | 2 Dentiste "Bundle of 6 Premium & Natural Mouthwash" listings would have been swept into the toothpaste catch-all pattern alongside legitimate toothpaste bundles. | Caught during size/pack_count review; excluded as OOS (mouthwash as main product) before insert. |
| 2026-07-16 | QA gates (post Pass 1+2) | Gate 1 (dual-mapped, LLM-scoped): 0. Gate 2 (HUMAN+LLM coexistence): 456 — expected non-zero under `--skip-coexistence` semantics since no HUMAN-row deletion has run (deliberately out of scope for this session per policy). Gate 3 (placeholder-leak): 0. Gate 4 (structured-fields NULL%, DISTINCT-entry version): 0%. | All gates pass under Full-Rebuild pre-delete semantics. HUMAN-row cleanup (delete only where duplicated by an LLM row for the same product) is a separate, deliberately manual/wrapper-side step not performed in this session. |
| 2026-07-23 | Top-up coverage session (month 2026-06) | Live re-run of the worklist query found 303 rows (217 distinct products) still within top-95%-cumulative-GMV (GWP-zeroed) with no `taxonomy_id` — the wrapper's pre-check number matched closely but was independently re-verified per instructions, not trusted as-is. Bulk brand+text grouping found only ~8 products with a high-confidence exact match against existing entries (same brand, ≥2 overlapping product-line words, matching size, matching pack multiplier where stated) — most of the live gap was genuinely new SKUs/sizes/reseller variants not previously captured, not a matching failure. `product_brand_map`'s `brand_id` was wrong or noise (`Care`/`Hygiene`/`Deep`/`Fresh`/generic-word `GUM`/`Orasyl`-for-GC) for a meaningful slice of the gap — re-derived the real brand from `sku_name` text per row rather than trusting the brand join, consistent with `docs/categories/sg_toothpaste.md`'s existing noise-brand edge case and `llm-extraction-rules.md` §11. 3 products were confirmed genuinely out-of-scope after image inspection: `29092514120` ("gentrisoneShinpoong cream") is a topical steroid/antibiotic cream, not oral care, miscategorized into this table; `12829071641` (TUNG Brush with sample Gel) and `25881141439` (Tung Gel) are White Magic tongue-care products (brush-as-main-product and tongue gel respectively) — not toothpaste/tooth gel per the category's scope definition. All 3 left `NULL` on purpose. | Minted 201 new `product_taxonomy` entries (`SKU-137441`–`SKU-137641`, block claimed atomically — see below), 4 of which each consolidate 2–3 near-duplicate reseller listings of the same physical product into one entry (e.g. 3 different sellers of an identical unbranded "Japan Repair Toothpaste 100g" import). Mapped 214 distinct products total this session (206 to new entries + 8 to existing entries via bulk text/size/pack match). Extraction was bulk text-based (sku_name only, per the session's speed-over-precision scope) — confidence recorded honestly at 0.7 (new mints) / 0.8 (reuse matches), not overstated as image-verified. Left the 3 OOS products `NULL`. Did not fix the pre-existing "(Multiple Variants)"/"(all variants)" catch-all entries from the 2026-07-16 session and an older global pass (30 distinct entries, e.g. `SKU-072520`–`072536`, `SKU-002360`–`002389`) even though they now fail the current (2026-07-22-dated) placeholder-leak rule — those predate this session, are out of scope for a coverage top-up, and are flagged here for a future `targeted_qa_fix.sh` pass rather than silently left undocumented. |
| 2026-07-23 | Top-up coverage session #2 (month 2026-06, re-invocation) | Same task re-run same day, hours after the prior top-up row above. Did not trust the category file or the wrapper's pre-check "3 products" figure — re-ran STEP 0 live against BigQuery. Live worklist returned exactly 3 rows, and they are byte-for-byte the same 3 products the prior session already investigated and gated OOS: `29092514120` (gentrisone cream, 412.39 GMV, cum. 61.94%), `12829071641` (TUNG Brush with sample Gel, 49.80 GMV, cum. 92.87%), `25881141439` (Tung Gel, 47.70 GMV, cum. 93.26%). No new listings have entered the top-95%-GMV worklist since the prior session closed it. | No SKU block claimed (zero live gap → no claim, per the Full-Rebuild top-up scenario's own rule in `docs/headless-runbook.md`). No rows written. Ran the 4 mandated QA-gate-as-code queries with coexistence checked (no `--skip-coexistence`, since this category already shipped): dual-mapped LLM = 0, HUMAN+LLM coexistence = 0, structured-fields-NULL% = 0%. Placeholder-leak = 43 distinct entries, but these are the same pre-existing "(Multiple Variants)"/"(all variants)" catch-alls already flagged in the prior session's row above as deferred to a future `targeted_qa_fix.sh` pass — not created or touched this session. Coverage gap remains genuinely closed; the 3 remaining rows are confirmed-OOS-left-NULL by design, not a defect. |

---

## Map Row Counts (verified live 2026-07-23, after this session's top-up writes)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 1,331 | 1,117 from 2026-07-16 Pass 1+2 + 214 from this session's top-up (206 newly minted + 8 reuse-matched) |
| HUMAN | 1,078 | Down from 1,534 recorded 2026-07-16 — some keyword-seed rows were cleaned up by a separate wrapper-side process between sessions (this session did not delete any HUMAN rows itself) |
| NULL (unmapped) | remainder of distinct products in `master_clean_niq.shopee_sg_toothpaste` | GMV coverage for month 2026-06 now 98.0% (up from 92.3%), exceeding the ≥90% NULL-coverage-pass target in `docs/quality-standards.md` §6. Live worklist re-check after this session's writes: 3 rows remain (the confirmed-OOS products above) — the full top-95%-cumulative-GMV gap is otherwise closed. |
