# makanananjing_my — Category Context

> Custom (non-NIQ) source: `sincere-hearth-273704.makanananjing.9_makanananjing_my_daily`
> (Shopee Malaysia, daily grain summed to monthly). Not a `master_clean_niq` table — different
> schema (daily grain, `category_1`/`category_2` fixed to `Pet`/`Pet Food` for every row regardless
> of actual product, no `model_id`/`month`/official-store-badge-driven data the way NIQ tables have
> it). Taxonomy state is keyed under `master_table = 'makanananjing_my'`, not the source table name.

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass | ✅ Complete (Full Rebuild, first run) |
| GMV Coverage | 89.0% of dog-food in-scope worklist GMV mapped (7.45M / 8.37M MYR) |
| Last run | 2026-07-23 |
| Current MAX taxonomy_id (this category) | SKU-150711 |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-149586–SKU-151585 | Claimed block (2,000 slots, `sku_block_registry`, scenario `custom_full_rebuild`) |
| SKU-149586–SKU-150711 | Actually used (684 taxonomy entries) — remainder of block left unused |

---

## Brand Scope

75 distinct brands mapped (46 reused from existing `brand_dict`, 29 newly minted as `BRD-MY-*`
local/house brands — a wider first pass of 47 new brands was minted, but 18 turned out unused after
the cat-scope correction below). Top brands by product count:

1. **Royal Canin** — `BRD-GLOBAL-00001` — 108 products
2. **Probalance** — `BRD-GLOBAL-01915` — 44
3. **Brit** — `BRD-SG-02158` — 42
4. **Chunk Bits** — `BRD-MY-01034` (new) — 36
5. **Alps Natural** — `BRD-SG-02056` — 32
6. **Nature's Protection** — `BRD-SG-00100` — 31
7. **Pedigree** — `BRD-SG-00016` — 26
8. **Notti** — `BRD-SG-02108` — 23
9. **Natural Core** — `BRD-SG-00136` — 23
10. **Back2Nature** — `BRD-SG-09726` — 17
11. **Monge** / **JerHigh** / **Rosy Fresh** — 15 each
12. **Hill's** / **Amelisa Pet & Co** — 14 each

No official-store allowlist — this source table has no `merchant_badge`/official-store signal;
Pass 1 (official-store) was skipped, going straight to bulk keyword-matched routing per the session
brief.

---

## Scope — What's In vs Out

**In scope:** dog dry food, dog wet food (can/pouch/tray), dog treats, dental chews, freeze-dried
dog snacks, dog nutritional supplements.

**Out of scope (left NULL/unmapped):**
- **Cat food of any kind.** A sibling category, `docs/categories/makanankucing_my.md`, already
  covers cat food comprehensively from a separate source table
  (`makanankucing.9_makanankucing_my_daily`) — see "Cross-category discovery" below. 413 cat-scoped
  products (explicit `cat`/`kucing` text, or known cat-exclusive brands like Sheba, Aixia, Nekko,
  Snappy Tom, Kucinta, Fancy Feast, Felix, Friskies, ME-O, Kit Cat, Royal Canin Kitten) were excluded
  from this category's mapping.
- Non-pet-food contamination: dairy/milk powder (Dutch Lady, Fernleaf), coffee (Nescafe, Moccona),
  snacks (Julie's, Maggi, Quaker), laundry detergent (Top, Downy), toothpaste (Colgate), skincare
  (Olay), baby diapers (Huggies, Merries, Diapex), toys. This source table's `category_1`/`category_2`
  are fixed to `Pet`/`Pet Food` for every row regardless of actual product — a large share of the
  95%-cumulative-GMV worklist (539 of 1,968 products, ~$9.85M of $31.5M) is general-merchandise
  leakage from mixed-catalog sellers (`Shopee Supermarket`, `Lotus's`), not pet food at all.
- Pet non-food/medicine: cat/dog litter, flea/tick treatment (Frontline, Advantage, Bayer, Drontal
  dewormer), pet training pads, cages, carriers, grooming shampoo/wipes.

**Edge cases:**
- Dual-species listings (e.g. "NOTTI [Treat] ... Dogs & Cats", "Greenies Pill Pockets for Cats &
  Dogs") were kept in this (dog) category rather than excluded — they are not cat-exclusive.
- 46 genuinely dog-labeled products (Royal Canin, Hill's, Orijen, Brit, etc. explicitly "Dog"/"Canine"
  in the title) were found already mapped under `master_table='makanankucing_my'` — see below. These
  were dropped from this session's mapping to avoid a dual-map (product_id, platform, country)
  violation, deferring to the pre-existing (if mis-scoped) row rather than editing another category's
  already-shipped data.

---

## Cross-category discovery (significant finding)

Mid-session, a collision check against the true dedup key `(product_id, platform, country)` — not
just `master_table` — found that **370 of this session's initially-mapped 1,190 "pet food" products
were already mapped under `master_table='makanankucing_my'`**, a same-day sibling Full Rebuild session
covering cat food from a *different* source table (`makanankucing.9_makanankucing_my_daily`). Its
category doc confirms its scope is "cat dry food, cat wet food, cat treats" with dog food explicitly
listed as out-of-scope for it.

This meant this session's original scope decision — "any identifiable pet food, dog or cat" — was too
broad given the sibling category already owns cat food. Corrected scope to **dog food only**
(matching the literal source table name, "makanan anjing" = dog food in Malay), removing 413
cat-scoped products from this session's mapping (see Scope section above).

A residual 46 collisions remained after that correction: genuinely dog-labeled products that
`makanankucing_my` had *also* mapped, despite its own documented scope excluding dog food. Rather than
edit that category's already-shipped, already-QA'd data (out of scope for this session, and its
universe-refresh state is unknown from here), this session's duplicate rows were dropped and the
existing `makanankucing_my` rows were left standing. **This is a real residual defect**: those 46
products are dog food sitting under a "cat food" master_table, and the correct long-term fix is a
`targeted_qa_fix.sh` (or manual) pass against `makanankucing_my` to re-route them here — flagged in
Targeted QA Fix Brief below.

---

## Taxonomy Design Notes

**Extraction method:** bulk SQL/regex text-matching on `sku_name` only — no merchant/official-store
data, no image reads (all 731 mapped products were resolved from title text alone; this is a lower
signal-richness pass than categories with image verification). Brand identified via an ~110-entry
curated keyword dictionary (longest-match-first, iteratively built against the GMV-ranked unmatched
tail across three refinement passes). Size and pack-count extracted via regex over `sku_name`
(kg/g/ml/L/lb units incl. plural/uppercase forms, `x{N}`/`*{N}` and `({N} cans/pcs/pouches)`
multiplier patterns).

**product_line:** derived by stripping the matched brand token, retailer/reseller noise (`GUN PET`,
`POODEE`, `Borong`, `MAIN`, `ORIGINAL`, bracketed promo tags, `WH\d+` warehouse codes), generic
category words (dog/food/dry/wet/premium/anjing/makanan), and the extracted size/pack tokens from the
cleaned `sku_name`; the remainder is written to `product_line`. This is a bulk-first, coverage-over-
precision pass per `docs/headless-runbook.md`'s Full Rebuild guidance — long-tail entries'
`product_line` text sometimes retains noise (stray retained words, embedded Chinese descriptive text)
that a `targeted_qa_fix.sh` pass would clean up. `sub_line`/`variant` were left NULL throughout (no
reliable bulk signal to split product_line from a genuine sub-line/variant at this text-only,
no-image extraction depth).

**Brand registry note:** ~47 new `BRD-MY-*` brand_dict rows were minted this session for pet-food
brands not previously in the global registry (Sarar, Vet-Pro, Furlari, Rich.Co, Josera, Wilderness
Legend, NutriEdge, etc.) — `brand_dict` has no atomic-claim mechanism analogous to
`sku_block_registry` for `taxonomy_id`; `MAX(BRD-MY-*)+1` was queried immediately before each insert
batch, no collision was detected against this session's own inserts, but see the sibling category's
own doc for a same-day collision it hit against a different parallel session at the same ID range —
this class of race is a known gap for future sessions.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-23 | Full Rebuild (first run) | Confirmed 0 pre-existing `product_taxonomy_map` rows for `master_table='makanananjing_my'` — genuine first run | Proceeded per Full Rebuild scenario |
| 2026-07-23 | Full Rebuild | Source table is dramatically mixed-category (`category_1`/`category_2` fixed to `Pet`/`Pet Food` for every row regardless of actual product) — snacks, dairy, coffee, detergent, diapers, skincare all present | Built a pet-food scope keyword classifier (positive pet+food signal AND NOT hardware/medicine AND NOT human-FMCG signal), iteratively refined across 3 passes against the GMV-ranked unmatched tail |
| 2026-07-23 | Full Rebuild | Cross-category collision: 370 of 1,190 initially-mapped products were already mapped under sibling category `makanankucing_my` (cat food, different source table) | Corrected scope from "any pet food" to "dog food only"; removed 413 cat-scoped products (see Cross-category discovery above) |
| 2026-07-23 | Full Rebuild | Residual 46 collisions: genuinely dog-labeled products also mapped (out-of-scope) under `makanankucing_my` | Dropped this session's duplicate rows rather than edit the other category's shipped data; flagged for future re-routing (see Targeted QA Fix Brief) |
| 2026-07-23 | Full Rebuild | Self-check QA gates (G1, G2, G5, placeholder-leak, structured-fields-NULL%, cross-master_table dual-map, dog/cat type-conflict spot-check) | All passed after corrections: 0 dual-mapped, 0 HUMAN+LLM coexistence, 0 provenance gaps, 0 placeholder leaks, 1% NULL `product_line`, 0 cross-master_table collisions, 0 dog↔cat type conflicts |

---

## Targeted QA Fix Brief

> Scope for a future `targeted_qa_fix.sh` / NULL-coverage session — not executed this session.

**Verdict:** D6 in-scope NULL coverage gap + a cross-category re-routing task + a D1/D2 precision pass.

- **Coverage gap** (~137 products, dog-scope estimate): products matching a dog-food text signal in
  the 95%-cumulative-GMV worklist but not resolved to a brand/line by this session's keyword
  dictionary. Candidates for direct image-based resolution.
- **Cross-category re-routing** (46 products, see Cross-category discovery): genuinely dog-labeled
  products currently sitting under `master_table='makanankucing_my'` (out of scope for that category
  per its own doc). Re-route these `product_taxonomy_map` rows to `master_table='makanananjing_my'`
  once a session is scoped to safely touch `makanankucing_my`'s data.
- **Precision pass**: this was a bulk regex/text-matching, no-image-read pass (Full Rebuild scenario
  explicitly deprioritizes per-row precision). `product_line` for long-tail brands is a regex-stripped
  `sku_name` remainder and sometimes retains noise or embedded CJK text. A pass re-reading product
  images for the long tail would sharpen D1/D2.
- **`brand_dict` cleanup**: 18 of the 47 newly-minted `BRD-MY-*` brand rows from this session's first
  extraction pass ended up unused after the cat-scope correction (their only referencing taxonomy rows
  were deleted). They remain in `brand_dict` as unused rows — harmless but not cleaned up this
  session.

---

## Scripts

No committed pipeline scripts for this category — extraction was done directly via ad hoc SQL against
BigQuery (bulk regex-based scope/brand/size/pack classification), not a
`pipeline/05_product_taxonomy/llm_{table}/` script, per the session brief for this custom, non-NIQ
source table.

---

## Map Row Counts (as of this session)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 731 | This session, Full Rebuild first run |
| HUMAN | 0 | No prior keyword-seed pass for this category |
| NULL (unmapped, in-scope dog food) | ~137 | Brand/line not resolvable from text alone — see Targeted QA Fix Brief |
| NULL (out-of-scope, correctly excluded) | 1,237 | Cat food (belongs to `makanankucing_my`) + non-pet-food contamination + pet non-food/medicine |
