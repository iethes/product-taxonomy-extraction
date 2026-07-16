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
| LLM Pass 1 | ⏳ In progress (this session) |
| LLM Pass 2 | ⏳ In progress (this session) |
| GMV Coverage | TBD — recorded at end of session |
| Last run | 2026-07-16 |
| Current MAX taxonomy_id (pre-session, per STATUS.md — NOT trusted, re-verified live before claim) | SKU-058455 |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| (filled in Step 3 of this session, atomic claim, 2000 slots) | Pass 1 OFFICIAL + Pass 2 RESELLER + structured-field work |

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
- To be filled in during Pass 1/2 as specific hard cases are found.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-16 | Step 0–2 (category research) | Task prompt used short table name `sg_toothpaste`, which doesn't exist — actual table is `shopee_sg_toothpaste` (matches the established `sg_shampoo`/`shopee_sg_shampoo` naming convention). 1,534 pre-existing HUMAN map rows found (not 0 as an untested assumption might suggest). Real 95%-GMV brand threshold is 44 brands (not a fixed top-N guess). | This file written with the full table name used throughout; existing HUMAN rows documented, left untouched; full 44-brand list and 20-entry allowlist recorded below rather than a truncated snapshot. |

---

## Map Row Counts (as of session start, before this run's writes)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 0 | None yet — this is the first LLM extraction for this category |
| HUMAN | 1,534 | Keyword-seed routing (automated, not actual human review per Decision 18). Left untouched this session. |
| NULL (unmapped) | remainder of 12,455 distinct products | To be reduced by this session's Pass 1 + Pass 2 |
