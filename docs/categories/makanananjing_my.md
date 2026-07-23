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
| LLM Pass | ✅ Complete (Full Rebuild, first run) + 3 top-up sessions |
| GMV Coverage | 89.0% of dog-food in-scope worklist GMV mapped (7.45M / 8.37M MYR) — stale, not recomputed since first run |
| Last run | 2026-07-23 (3rd top-up) |
| Current MAX taxonomy_id (this category) | SKU-156803 — **query BQ directly before trusting this**, per `CLAUDE.md`'s SKU Block Management warning; this field lags real time between sessions |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-149586–SKU-151585 | Claimed block (2,000 slots, `sku_block_registry`, scenario `custom_full_rebuild`) |
| SKU-149586–SKU-150711 | Actually used (684 taxonomy entries) — remainder of block left unused |
| SKU-151786–SKU-153022 | Claimed block (1,237 slots, `custom_topup`, 1st top-up) — 124 used |
| SKU-155718–SKU-156802 | Claimed block (1,085 slots, `custom_topup`, 2nd top-up) — 10 used |
| SKU-156803–SKU-157002 | Claimed block (200 slots, `custom_topup`, 3rd top-up) — 1 used (`SKU-156803`, Tarokun) |

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
| 2026-07-23 | Top-up (coverage gap, 2nd) | Live re-run of the 95%-cumulative-GMV worklist found 1,085 still-unmapped products (matched the number cited in the session brief, but re-verified live rather than trusted). Classified all 1,085 via scope rules from this doc: 509 cat-only, 20 dog+cat dual (mostly non-food accessories/flea treatment/sample-pack giveaways), 53 dog-only, 503 neither-keyword (mostly general-merchandise contamination — Glade, Nestle, Prego, Tenten, Libresse, Pokka — plus a handful of brand-only Royal Canin/Orijen/Wanpy/Ciao Churu listings resolved by brand-name matching). Image-verified 5 ambiguous high-GMV candidates: 2 "Royal Canin Wet Food Pouch" listings (232,818 + 39,823 MYR) turned out to be **Feline** wet food despite no cat keyword in the title — excluded; 1 Wanpy "Creamy Lickable Treats" listing confirmed cat-scoped via a sibling listing's explicit "Cat Treat / Makanan Kucing" text — excluded; 1 "Myfoodie Meat Package" confirmed dog (poodle on packaging) — included; 1 "NEW Pudding Fresh Goat Milk Jelly ...Dog/Cat" listing, despite "Dog treat" in the title, was confirmed **cat-scoped** via image text "使用对象：12月龄以上猫" (for cats 12mo+) — excluded after already being provisionally scoped in, catching a keyword-stuffed false positive. Net 58 products classified in-scope dog food/treats/dental-chews/supplements. | Mapped via reuse-before-mint: matched 9 products to pre-existing `makanananjing_my` taxonomy entries (same brand+line+size/pack) by grepping the category's existing 808 entries; minted 43 new entries for the remainder (merging near-duplicate listings sharing brand+line+size/pack, e.g. 2 "GUN PET Royal Canin Poodle Pouch 85g" resellers → 1 entry, 3 "DentDoc Dental Stick" resellers → 1 entry). Claimed SKU block SKU-155718–SKU-156802 (1,085 slots, `custom_topup`). |
| 2026-07-23 | Top-up (coverage gap, 2nd) — **cross-category collision, caught pre-refresh** | After the initial 43-entry / 57-map-row write, a true-composite-key (`product_id, platform, country`, per ADR-006) collision check against **all** `master_table`s — not just this one — found 35 of the 58 just-mapped products (33 of the 43 new taxonomy entries, plus 8 of the 9 reuse-mapped products) were **already mapped under `master_table='makanankucing_my'`** (the sibling cat-food category, same-day session, `mapped_at` ~08:00–08:55, i.e. before this session started writing). Spot-checked several: their `makanankucing_my` canonical_names literally read e.g. "Royal Canin Dog Adult Large Breed 13kg" and "Back2Nature ... Dog 95g" — genuinely dog-scoped products that a same-day `makanankucing_my` session mapped despite its own documented scope excluding dog food, a large-scale recurrence of the single-digit residual this doc's Cross-category discovery section already flagged. This session's own G1/G2 gate queries didn't catch it because they're scoped to `master_table='makanananjing_my'` only, and none of these 35 products had any pre-existing row *under this table* (that's exactly why they were in the live gap) — the collision is only visible by joining across `master_table`s on the true composite key, which this session's SQL didn't do until after writing. | Per this doc's established precedent (Cross-category discovery section): dropped this session's own 35 duplicate `product_taxonomy_map` rows and deleted the 33 taxonomy entries that were left with zero remaining map rows after the drop (0 products referencing them); left the pre-existing `makanankucing_my` rows standing untouched (out of scope to edit this session, unknown QA/refresh state). Final surviving write: **10 new taxonomy entries, 14 map rows** (13 new-mint + 1 reuse of a pre-existing entry). Re-ran G1/G2/G4(full cross-table)/G5/placeholder-leak after the fix — all 0 except one **pre-existing** G4 residual (product `24442421432`, mapped under both tables at 08:45/08:55, before this session touched anything) — confirmed this session introduced zero net-new collisions. Live gap reduced 1,085 → 1,071. **Flagged for future work**: the same re-routing task this doc already tracks in Targeted QA Fix Brief (46 products) has grown substantially — a same-day `makanankucing_my` session remapped a large batch of genuinely dog-scoped products; a full audit of `makanankucing_my`'s cross-table collisions (not just the ones this session happened to touch) is now overdue. |
| 2026-07-23 | Top-up (coverage gap, 3rd) — **collision now dominates the entire live gap** | Live re-run of the 95%-cumulative-GMV worklist found 1,071 still-unmapped products (matched the wrapper's pre-check number, but re-verified live rather than trusted, per instructions). Classified all 1,071 via this doc's established bulk text rules: 453 cat-only (has_cat, no dog signal), 159 general-merchandise-only signal (Milo, Glade, Shokubutsu, Aik Cheong, Tong Garden, Gillette, Dettol, Nescafe, etc. — dozens of unrelated FMCG/cosmetics/electronics brands), 61 pet-non-food/medicine (flea/tick treatment, litter, wee-wee pads, pet wipes, reptile/bird/rabbit equipment — none of it dog food), 6 not-for-sale (sample-pack/mystery-gift giveaways, incl. the recurring "[Gift/NotForSale] Mystery Gift Dog Food" listing already excluded in the first Full Rebuild), and 332 signal-neither products manually reviewed in full (overwhelmingly further general-merchandise contamination — Nestle, Biscoff, Kotex, Oral-B, reptile UVB lamps, human cosmetics/electronics — plus 4 with a genuine dog signal missed by the keyword regex: 2 breed names not caught by `\bdog\b` matching (Royal Canin German Shepherd, Orijen Small Breed Marine Fish), 1 explicit dual-species phrase ("Royal Canin Recovery Liquid ... for cats and dogs"), and 1 image-verified case (Tarokun "Little Bun/Mix Bone Shape" pet biscuit — no dog keyword in `sku_name`, but the product image's own packaging text reads "ドッグフード" / "Healthy Biscuit ... for Dog" with dog-breed illustrations, confirming dog scope per this doc's image-priority rule; the reseller's own "EasyMEOW" watermark on the image was correctly not treated as a brand/species signal per `llm-extraction-rules.md` §11). This produced 44 candidate dog-scoped products in total (37 from the `\bdog\b`/`anjing`/`puppy`/`canine` regex sweep + 3 genuine dual-species treats/kibble/dental-chew listings from the has_cat+has_dog bucket + 4 from the manual sweep above). **A true-composite-key collision check run *before* writing anything this time** (lesson learned from the 2nd top-up session's post-write discovery) found **43 of these 44 already mapped under `master_table='makanankucing_my'`** — spot-checked canonical_names confirm genuine dog scope (e.g. `9642444110` → "Royal Canin Dog Adult Large Breed 13kg", `52958728091` → "Orijen Fish Dog 2kg", `10756858966` → "Greenies Dog Dental Treatpak ... Dog Dental"), all `mapped_at` ~2026-07-23 08:00–08:46, i.e. the same same-day `makanankucing_my` session already implicated in the prior top-up's collision finding. Only 1 of the 44 (Tarokun) had zero pre-existing row anywhere. | Wrote only the 1 genuinely clean product: minted brand `BRD-MY-01186` (Tarokun, a Japanese-import dog-biscuit brand with no prior `brand_dict` presence) and taxonomy entry `SKU-156803` ("Tarokun Little Bun Mix Bone Shape Dog Biscuit", size NULL — not stated in title or clearly legible in the pack-jar image, pack_count=1), mapped product `2641777624` to it (`source='LLM'`, `meta_agent='CLAUDE_CODE'`, confidence 0.85). The other 43 were left untouched — **not written here** — per this doc's established precedent of not editing `makanankucing_my`'s already-shipped data out-of-scope for this session. Claimed SKU block SKU-156803–SKU-157002 (200 slots per `headless-runbook.md`'s topup floor, sized to the verified need rather than the stale 1,071-worklist-row figure — only 1 slot used, 199 returned unused). Self-check QA gates (G1, G2 without `--skip-coexistence`, G4 full cross-table, G5, placeholder-leak, structured-fields-NULL%): all 0 except structured-fields-NULL% at 1% (well under the 50% threshold) and G4 at 1 — confirmed via direct lookup to be the same **pre-existing** residual (`24442421432`) already documented in the prior session's entry, not a new collision. Live gap reduced 1,071 → 1,070 — the smallest single-session reduction so far, because **the coverage gap is no longer the bottleneck**: of everything left in the worklist, cat/general-merch/pet-non-food exclusions are genuinely out of scope, and nearly all remaining genuine dog-food signal is phantom — already sitting under `makanankucing_my`. Further sessions against this table's live worklist will keep finding a near-identical result until the cross-category re-routing task below is actually executed. |
| 2026-07-23 | Full Rebuild (first run) | Confirmed 0 pre-existing `product_taxonomy_map` rows for `master_table='makanananjing_my'` — genuine first run | Proceeded per Full Rebuild scenario |
| 2026-07-23 | Full Rebuild | Source table is dramatically mixed-category (`category_1`/`category_2` fixed to `Pet`/`Pet Food` for every row regardless of actual product) — snacks, dairy, coffee, detergent, diapers, skincare all present | Built a pet-food scope keyword classifier (positive pet+food signal AND NOT hardware/medicine AND NOT human-FMCG signal), iteratively refined across 3 passes against the GMV-ranked unmatched tail |
| 2026-07-23 | Full Rebuild | Cross-category collision: 370 of 1,190 initially-mapped products were already mapped under sibling category `makanankucing_my` (cat food, different source table) | Corrected scope from "any pet food" to "dog food only"; removed 413 cat-scoped products (see Cross-category discovery above) |
| 2026-07-23 | Full Rebuild | Residual 46 collisions: genuinely dog-labeled products also mapped (out-of-scope) under `makanankucing_my` | Dropped this session's duplicate rows rather than edit the other category's shipped data; flagged for future re-routing (see Targeted QA Fix Brief) |
| 2026-07-23 | Full Rebuild | Self-check QA gates (G1, G2, G5, placeholder-leak, structured-fields-NULL%, cross-master_table dual-map, dog/cat type-conflict spot-check) | All passed after corrections: 0 dual-mapped, 0 HUMAN+LLM coexistence, 0 provenance gaps, 0 placeholder leaks, 1% NULL `product_line`, 0 cross-master_table collisions, 0 dog↔cat type conflicts |
| 2026-07-23 | Top-up (coverage gap) | Live re-run of the 95%-cumulative-GMV worklist found 1,237 still-unmapped products (not 0, despite Status showing "Complete") — re-verified live per instructions rather than trusting the doc. Classified all 1,237 via bulk text rules: 405 already mapped under sibling `makanankucing_my` (cross-category, left untouched), 117 cat-scoped, 82 pet-non-food (flea/tick treatment, diapers, playpens, oral gel), 268 general-merchandise contamination (dairy, coffee, snacks, detergent, tissue, tea), 199 residual unresolved (mostly further general-merch/ambiguous-species long-tail, sampled and confirmed not dog-specific), 14 explicitly excluded (not-for-sale mystery-gift/sample-pack giveaways — one image-verified given its outsized nominal GMV, chocolate-candy contamination, non-food furniture/diapers, cat-dominant keyword-stuffed listing) | Mapped the remaining 152 genuine dog-food/treat/supplement products via bulk brand+size+pack grouping into 124 taxonomy entries (33 reused an existing global `brand_dict` brand incl. `BRD-UNBRANDED` for 9 genuinely brand-less generic listings, 41 new `BRD-MY-01128`–`BRD-MY-01168` brands minted for regional/house brands with zero prior taxonomy presence, e.g. Cesar, Addiction, Blue Bay, Elitas, BilJac — several long-established global pet-food brands that had never been mapped in this category before). Claimed SKU block SKU-151786–SKU-153022 (1,237 slots, `custom_topup`, only 124 used); wrote via `bq query` DML only, `meta_agent='CLAUDE_CODE'`, `source='LLM'`, no existing rows touched. Live gap reduced 1,237 → 1,085 (all reduction is genuine dog-scope coverage; the residual 1,085 is legitimately out-of-scope or unresolved, not an artifact). Self-check QA gates (G1, G2 without `--skip-coexistence`, G4 cross-category, G5, placeholder-leak, structured-fields-NULL%): all 0 except structured-fields-NULL% at 1% (well under the 50% threshold) |

---

## Targeted QA Fix Brief

> Scope for a future `targeted_qa_fix.sh` / NULL-coverage session — not executed this session.

**Verdict:** D6 in-scope NULL coverage gap + a cross-category re-routing task + a D1/D2 precision pass.

- **Coverage gap** (~137 products, dog-scope estimate): products matching a dog-food text signal in
  the 95%-cumulative-GMV worklist but not resolved to a brand/line by this session's keyword
  dictionary. Candidates for direct image-based resolution.
- **Cross-category re-routing** (78+ products, see Cross-category discovery): genuinely dog-labeled
  products currently sitting under `master_table='makanankucing_my'` (out of scope for that category
  per its own doc). Re-route these `product_taxonomy_map` rows to `master_table='makanananjing_my'`
  once a session is scoped to safely touch `makanankucing_my`'s data. **Grown substantially again as of
  the 2026-07-23 third top-up session**: of 44 dog-scoped candidates identified from that session's live
  worklist (spanning Royal Canin vet-diet variants, Orijen, Hill's Prescription Diet, Farmina, Brit,
  Wanpy, PetCoCo, N&D, Nature's Protection, Greenies, and more), **43 were already mapped under
  `makanankucing_my`** — this is no longer a residual edge case, it is now the dominant explanation for
  why this category's live coverage gap barely moves session over session (1,085 → 1,071 → 1,070: two
  full top-up sessions' worth of classification work, net one product resolved here). The true scope of
  this re-routing task is almost certainly much larger than the ~78 products (35 + 43) directly observed
  across the two top-up sessions that happened to collide with it — a dedicated audit of
  `makanankucing_my`'s **full** map for dog-signal canonical_names/sku_names (not just the intersection
  each top-up session's worklist happened to touch) is now overdue and should be treated as higher
  priority than further `makanananjing_my` top-up passes, which will keep returning near-zero net new
  coverage until this is resolved.
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
