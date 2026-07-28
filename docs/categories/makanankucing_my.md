# makanankucing_my — Category Context

> Custom (non-NIQ) source: `sincere-hearth-273704.makanankucing.9_makanankucing_my_daily`
> (daily grain summed to monthly). Not a `master_clean_niq` table — different
> schema, no `model_id`/`month`/`merchant_badge`-driven official-store data in the form other
> categories rely on. Taxonomy state is keyed under `master_table = 'makanankucing_my'`, not the
> source table name.
>
> **Platform scope (updated 2026-07-28):** originally Shopee Malaysia only. As of the 2026-07-28
> top-up session, `ecommerce_platform='Tiktok'` rows are also IN SCOPE — this is the first category
> to mix platforms under one `master_table`. `product_taxonomy_map` is keyed on `(product_id,
> platform, country)` precisely so Shopee and Tiktok products never collide. **Known, accepted data
> issue:** Tiktok rows' `price`/`gmv_daily` figures in this source table are corrupted by an
> inconsistent scale factor and mixed daily/monthly grain — the 95%-cumulative-GMV worklist ordering
> and `gmv_monthly` figures are unreliable for Tiktok rows specifically (values run ~1000x too high).
> This is a separate upstream data-pipeline problem, out of scope for taxonomy sessions to fix —
> proceed with extraction using the worklist as given.

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass | ✅ Complete (Full Rebuild, first run) + 🔶 Top-up coverage pass (2026-07-23) + 🔶 second top-up coverage pass (2026-07-23) + 🔶 third top-up coverage pass (2026-07-28, this session, partial — first pass to include Tiktok; 396 products still gap) |
| GMV Coverage | 86.4% as of Full Rebuild; see prior QA History rows for the 2026-07-23 top-ups. This session added Tiktok to scope for the first time — live worklist was 1,501 products (all Tiktok), resolved 1,103 |
| Last run | 2026-07-28 (third top-up coverage session — Tiktok scope added) |
| Current MAX taxonomy_id (this category) | SKU-191193 |
| SKU blocks this category has claimed | SKU-145586–147585 (Full Rebuild, 1,554 used) · SKU-155023–155717 (top-up 1, 77 used) · SKU-157403–157956 (top-up 2, 53 used) · SKU-191043–192543 (top-up 3, this session, 151 used) |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-145586–SKU-147585 | Claimed block (2,000 slots, `sku_block_registry`, scenario `custom_full_rebuild`) |
| SKU-145586–SKU-147139 | Actually used (1,554 taxonomy entries) — 435 slots left unused in the block |
| SKU-155023–SKU-155717 | Claimed block (695 slots, `sku_block_registry`, scenario `custom_topup`, 2026-07-23) |
| SKU-155023–SKU-155099 | Actually used (77 new taxonomy entries) — 618 slots left unused in the block |
| SKU-157403–SKU-157956 | Claimed block (554 slots, `sku_block_registry`, scenario `custom_topup`, 2026-07-23, second top-up) |
| SKU-157403–SKU-157455 | Actually used (53 new taxonomy entries) — 501 slots left unused in the block |
| SKU-191043–SKU-192543 | Claimed block (1,501 slots, `sku_block_registry`, scenario `custom_topup`, 2026-07-28, third top-up — Tiktok scope added) |
| SKU-191043–SKU-191193 | Actually used (151 new taxonomy entries) — 1,350 slots left unused in the block |

## Brand IDs Assigned

| Range | Usage |
|-------|-------|
| BRD-MY-01070–BRD-MY-01127 | 58 new local/house brands minted in the Full Rebuild session |
| BRD-MY-01169–BRD-MY-01184 | 16 new local/house brands minted in the 2026-07-23 top-up session, after confirming the other 21 initially-assumed-new brands already existed in the *global* `brand_dict` under other markets/categories (see top-up QA History rows for the full reuse map, incl. routing "Advance" products to the existing `BRD-MY-01072` "Advance Veterinary") |
| BRD-MY-01187–BRD-MY-01214 | 28 new local/house brands minted in the second 2026-07-23 top-up session, after a global `brand_dict` check confirmed several other candidates (Hi-Cubs/喜崽, PETSEE, Carry's, Chun Fu, Prochoice, Partner, Kucinta, Rich.Co, Proud Holistic, NurturePro, Gewuan, Legendsandy, Felix, Meow, BOSSKU, Wono) already existed globally and were reused instead of re-minted. `Hegen` (the pet-treat listings, distinct from the pre-existing SG baby-bottle brand `BRD-SG-00702 Hegen`) was evaluated but left unmapped this session — its products' per-unit size could not be confirmed even from the product image, so no taxonomy entry was created pending a future size-resolution pass |
| BRD-MY-01230–BRD-MY-01247 | 18 new local/house brands minted in the 2026-07-28 top-up session (this session, Tiktok scope), after a global `brand_dict` REGEXP_CONTAINS search confirmed several other candidates already existed globally and were reused instead: Kucinta (BRD-MY-01032), Deeplove (BRD-SG-00669), Midalac (BRD-MY-01219), Omega Plus (BRD-SG-05090), PUAINTA (BRD-TH-02109), Pet Record (BRD-GLOBAL-00348), my meow (BRD-SG-04971). Also reused this category's own existing entries where the Tiktok worklist's text form differed from `brand_dict`'s stored spelling: `SPACECAT` (worklist: "Space Cat"), `Si Comot` (worklist: "Comot"), `Carry's` (worklist: "CARRYS"), `SmartHeart` (worklist: "Smart Heart"), `Smartz Choice` (worklist: "SMARTCHOICE PREFECTKAT" — read as a typo'd "Smart Choice Perfect Cat"), and `A-Tier` (worklist: "Sarar" — reusing this category's own pre-existing brand_id/canonical_name mismatch from an earlier session rather than minting a second "Sarar" brand; the mismatch itself is a precision-pass fix, not resolved this session). New mints: Mivita, Public Pet, Regal Whiskers, COMEOW, GoodMew, Dr.Pikac, PAWROO, Neco, FURREVER, CAPTAIN CAT, Pets Science, WormShield, LUMeO, YESFAVOR, Petfos, Purr Lab, Aplus (MY-scoped; a same-named `BRD-TH-02250 "A Plus"` exists but wasn't reused — no verified real-world link between the TH and MY listings, same caution as the Hegen precedent above), MeowShop |

**Collision note:** `brand_dict` has no atomic claim registry equivalent to `sku_block_registry`.
A parallel session inserted 47 new `BRD-MY-*` rows (`BRD-MY-01012`–`BRD-MY-01058`) ~4 minutes before
this session's insert at the *same* IDs (both sessions independently computed `MAX+1` from a stale
read). Detected via `COUNT(*) > COUNT(DISTINCT brand_id)` in the claimed range post-insert. Fix:
this session's 58 rows were deleted and re-inserted at a freshly-verified-safe range
(`BRD-MY-01070`–`BRD-MY-01127`); the 1,554 `product_taxonomy` rows referencing the old range were
updated to the new IDs. One casualty during cleanup: both sessions had independently minted a brand
row named exactly `Josera` at the same colliding ID (`BRD-MY-01041`) — the delete-by-`(brand_id,
canonical_name)` match caught both identical rows, silently removing the other session's `Josera`
row too. Restored immediately after detection (re-inserted `BRD-MY-01041 = Josera`) to avoid leaving
a dangling FK for that other session's data. **Recommendation for future sessions on this or other
new-market categories: `brand_dict` needs the same atomic-claim mechanism `sku_block_registry`
provides for `taxonomy_id` — this collision class will recur otherwise.**

---

## Brand Scope

134 distinct brands mapped (76 reused from existing `brand_dict`, 58 newly minted as `BRD-MY-*`
local/house brands not previously seen in SG/TH data). Top 15 by GMV:

1. **Royal Canin** — `BRD-GLOBAL-00001` — 10.07M
2. **Purina ONE** — `BRD-SG-00003` — 1.90M
3. **LGD** — `BRD-MY-*` (new) — 1.82M
4. **Whiskas** — `BRD-SG-00004` — 1.75M
5. **Cindy's Recipe** — `BRD-MY-*` (new) — 1.54M
6. **ProDiet** — `BRD-MY-*` (new) — 1.31M
7. **SmartHeart** — `BRD-GLOBAL-00039` — 1.27M
8. **Reflex** (incl. "Reflex Plus" listings) — `BRD-SG-02025` — 1.24M
9. **Molly** — `BRD-MY-*` (new) — 1.06M
10. **Snappy Tom** — `BRD-MY-*` (new) — 1.04M
11. **NOTTI** — `BRD-MY-*` (new) — 0.92M
12. **SIMBA** — `BRD-MY-*` (new) — 0.91M
13. **Sheba** — `BRD-SG-00097` — 0.90M
14. **Family Pets** — `BRD-MY-*` (new) — 0.65M
15. **Brit** (incl. "Brit Care") — `BRD-SG-02158` — 0.60M

**Brand consolidation applied during extraction** (spelling/casing variants merged to one brand
before ID assignment — see `docs/product-lifecycle.md` §4.1, same real-world entity must not get two
IDs): `Dr Bites`/`Dr. Bites`→`Dr.Bites`; `Cindy's`/`Cindy's Recipe` (curly apostrophe)→`Cindy's
Recipe`; `Cindy & Friend`→`Cindy & Friends`; `Buttons and Bows`→`Buttons & Bows`; `Hill's
Prescription/Science Diet`→`Hill's`; `Maxi Cat`→`Maxi`; `PawmisedLand`→`Pawmised`; `MrVET`→`MR.VET`;
`Vital Plus`→`VitalPlus`; `TOTW`→`Taste Of The Wild` (existing brand, shorthand in listings);
`Reflex Plus`→`Reflex` (existing brand — "Plus" is a product line, not a separate brand); `Brit
Care`→`Brit` (existing brand); `Ciao Churu`/`Churu`→`Ciao` (existing brand — Churu is Ciao's
treats/paste line).

No official-store allowlist — this source table has no `merchant_badge`/official-store signal
usable the way `master_clean_niq` tables have it (see Scope note below); Pass 1 (official-store)
was skipped entirely per the session brief, going straight to bulk keyword-matched routing.

---

## Scope — What's In vs Out

**In scope:** cat dry food, cat wet food (pouch/can/tray), cat treats and freeze-dried snacks/boosters.

**Out of scope (left NULL/unmapped, 237 products, 2.99M MYR GMV):**
- Dog food of any kind (dry, wet, treats) — `dog food`, `anjing`, `puppy`, brand-specific dog lines
  (`Advance Dog`, `Nature's Protection White Dog`, `ALPS NATURAL Pureness Dog`, `Back2Nature B2N ...
  Dry Dog`, `Bravery`/`Wilderness Legend`/`Natural Core` when explicitly dog-labelled)
- Cat litter (`cat litter`, `pasir kucing`, `tofu litter`, `clumping litter`)
- Flea/tick treatment (`Frontline`, `flea`, `ubat kutu`, `earmite`) — pet care, not pet food
- Human baby formula miscategorized into the feed (`Dumex Dugro`)
- Non-pet items miscategorized into the feed (rolling papers `Gajah Duduk Pelikat`, a children's
  balance bike, building-block toys, A4 paper, a "PURINA Felix" branded shopping bag)

**Edge cases:**
- Freeze-dried "booster"/chicken-cube treats sold by many near-identical generic listings with no
  discernible brand text (`Pet Booster Freeze Dried Chicken Cube ...`) — genuinely unbranded
  commodity treats from many small resellers, not a single missed brand. Left unmapped rather than
  forced into a fabricated brand.
- `[GWP]`/`[NOT FOR SALE]` flagged rows (6 in the worklist) were still extracted normally where a
  brand/size was identifiable (e.g. `WHISKAS Pouch TastyMix ... 70g`); a "PURINA Felix Wide Shopping
  Bag" and one ambiguous "Classic 500g" listing were left unmapped (merch item / unidentifiable).

---

## Taxonomy Design Notes

**Extraction method:** bulk SQL/regex text-matching on `sku_name` (per session brief — no
merchant/official-store data to seed Pass 1). Brand identified via a ~180-entry curated keyword
dictionary (longest-match-first) built iteratively against the worklist's GMV-ranked unmatched
tail. Size and pack-count extracted via regex over `sku_name` (kg/g/ml/L units, `x{N}` and `{N}
{pouches|cans|packs|...}` multiplier patterns, `{N}unit / {M}unit` alternation → `is_multi_size`).
A small number (~10) of highest-GMV size-ambiguous listings were verified against the product image
directly (`curl` + `Read`) — confirmed sizes for Cindy's Recipe Original 24-can cartons (80g/can),
Cindy's Recipe Naturelle Holistic (7kg), Sheba pouch cartons (70g/pouch), and BEAST U36 (1.5kg, whose
`sku_name` is truncated mid-title in the source data itself, not a query artifact).

**product_line vs variant split:** where `sku_name` yields a real on-label formula/line name (e.g.
Royal Canin's `Hair & Skin Care`, `Fit 32`, `Indoor 27`; SmartHeart's `Refine`; Fancy Feast's
`Royale`), that text is written to `product_line`. Where the only differentiating text is a
flavor/recipe description (e.g. `Chicken Tuna With Milk`, `Ocean Fish Salmon Chicken Goat Milk`) —
common for house/Turkish mass-market brands (LGD, Family Pets, MISHA, Timi, Molly) that carry no
named sub-line beyond the flavor — that text is written to `variant` instead, per the food-keyword
heuristic (chicken/tuna/salmon/fish/beef/duck/lamb/milk/etc.), and `product_line` is left NULL rather
than forcing a fabricated line name. 25 of 1,554 entries (1.6%) have neither field populated — plain
`{Brand} {Size}` for brands with no distinguishing text at all in this catalog (e.g. `Reflex 15kg`,
`Snappy Tom 400g`).

**Known coverage gaps (flagged for `targeted_qa_fix.sh` / a future NULL-coverage pass, not fixed this
session):**
- 334 products (2.22M MYR GMV) — brand not identifiable from `sku_name` text alone; mostly
  single-occurrence generic/no-name listings. Left `taxonomy_id IS NULL`.
- 124 products (1.32M MYR GMV) — brand matched but size not confidently extractable from text and
  not genuinely multi-size (e.g. bulk-carton listings stating pouch *count* but not per-pouch
  *size*, like `"1 kotak Cindy's Recipe ... Wet Food"` with no gram figure anywhere in the title).
  Left `taxonomy_id IS NULL` rather than guess or force a `NULL` size onto a non-multi-size entry.
  These are good candidates for image-based resolution in a follow-up session.

**Pack-count/size regex gotchas found this session** (fixed in the extraction script, noted here in
case a future session hand-rolls similar regex against this source table):
- `"24 x 80g"` (count-before-size) vs `"80g x24"` (size-before-count) both occur; must extract the
  count from whichever side is *not* attached to a unit, not always the token immediately after `x`.
- Unit regex must handle plural forms (`70grams`, `7kgs`) and no-space runs (`80gx24pouch`) — a bare
  `\b` word-boundary after `kg`/`g` fails on both (`s`/`x` are word characters, no boundary).
- `"6.6kg / 10kg"` style listings (buyer picks one of two sizes) are multi-size seller listings, not
  a single extractable size — must be detected and routed to `is_multi_size=TRUE, size=NULL` rather
  than silently taking the first size mentioned.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-23 | Full Rebuild (first run) | Confirmed 0 pre-existing `product_taxonomy_map` rows for `master_table='makanankucing_my'` — genuine first run | Proceeded per Full Rebuild scenario |
| 2026-07-23 | Full Rebuild | `brand_dict` new-ID collision with a concurrent parallel session at `BRD-MY-01012`–`01058` (no atomic claim mechanism for brand IDs, unlike `sku_block_registry` for `taxonomy_id`) | Relocated this session's 58 new brand rows to `BRD-MY-01070`–`01127` (re-verified safe immediately before re-insert); updated the 1,554 affected `product_taxonomy.brand_id` references; restored one row (`BRD-MY-01041 = Josera`) accidentally deleted because both sessions had independently minted an identically-named row at the same colliding ID |
| 2026-07-23 | Full Rebuild | Self-check QA gates (G1, G2, G5, placeholder-leak, structured-fields-NULL%) — see session findings | All passed: 0 dual-mapped, 0 HUMAN+LLM coexistence (no HUMAN rows exist for this category), 0 provenance gaps, 0 placeholder leaks, 34% NULL `product_line` (well under the 50% fail threshold, and expected — many entries correctly carry the flavor in `variant` instead) |
| 2026-07-23 | Top-up coverage (custom_topup) | Re-ran the live 95%-cumulative-GMV (GWP-zeroed) worklist query rather than trusting the wrapper's pre-check number — confirmed 695 products with `taxonomy_id IS NULL`, matching the wrapper's figure exactly | Proceeded with bulk-first reuse-before-mint against this live worklist |
| 2026-07-23 | Top-up coverage | Scope classification: 252 of 695 correctly OOS (138 pure dog food, 59 non-pet merch/accessories, 24 cat litter, 17 dog-only brands e.g. Pedigree/Cesar/Greenies, 6 flea/tick treatment, 3 merch/GWP-only, 1 human baby formula); 443 in-scope. Two Korean "ISKHAN...Dog Food...Makanan Anjing" listings with a stray "Kitten" keyword (template/copy-paste artifact) were manually overridden to OOS despite matching the cat-word regex — the explicit "Dog Food"/"Makanan Anjing" phrasing outweighed the single stray word | Scope filter + 2 manual overrides |
| 2026-07-23 | Top-up coverage | **Caught before writing (self-review, prompted by an advisor consult):** a CJK-only brand alias (`蓝氏`→Legendsandy, `纯福`→Chun Fu) normalized to whitespace-only text after CJK-stripping, which then matched as a substring of *any* string containing a space — silently mislabeling 195 of 389 brand-matched rows as "Legendsandy". Found via a full manual read of all (brand, sku_name) pairs sorted by brand, not by the row-count summary, which looked plausible. Fixed by removing CJK-only alias entries (their ASCII equivalents already covered the same brands) and hardening the matcher to reject any alias that normalizes to empty/whitespace | Full re-run of brand matching from the corrected matcher before any SQL was generated — no bad rows were ever written |
| 2026-07-23 | Top-up coverage | A bare `"tom"` alias (added for a `TOM🐾`-branded product) collided with `"Snappy Tom"` (existing brand) and the substring `"sTOMach"` in unrelated sku_names | Removed the alias; the 3 genuine `TOM🐾` products (~44K MYR GMV) were left brand-unmatched rather than risk another short-token collision |
| 2026-07-23 | Top-up coverage | Brand-dedup check against the *global* `brand_dict` (not just this category's existing 1,554 entries) found 21 of an initially-assumed "37 new brands" already registered under other markets/categories: Legendsandy, Masti (MASTI), Tommy's Kitchen, Agogo, Leonardo, Schesir, Empire, Regalos, Iskhan, Urbanwolf, La Philanth, Weruva, Vet-Pro, Instinct, Chun Fu, Mumm, Petlusci, Neku, Hukii, Furrytail. "Advance Cat - Urinary/Renal/Gastro sensitive/Hypoallergenic" products were routed to the existing `BRD-MY-01072` **"Advance Veterinary"** (not a new plain "Advance" brand, and not the unrelated `BRD-ID-06375` Indonesian "Advance") since the products are explicitly the veterinary/therapeutic diet line | Reused existing `brand_id`s for all 21 — avoided minting 21 duplicate brand entities for real-world brands that already exist elsewhere in `brand_dict` (ADR-1) |
| 2026-07-23 | Top-up coverage | 16 brands confirmed genuinely new after the global check (Allando, Bonacibo, Cator, Cattylov, DogsPlus, FURPET, Felicia, Fregate, Furvit, Gewuan, Kenny Wood, LILIEN, Nutritail, SND, Smartz Choice, Ultimates) | Minted `BRD-MY-01169`–`01184` (re-verified `MAX(BRD-MY-*)` immediately before insert per the category's own documented collision risk; re-checked post-insert for duplicates — none found) |
| 2026-07-23 | Top-up coverage | Bulk-first reuse-before-mint resolved 141 of 695 live-worklist products (15 via exact `(brand,size,pack)` match to an existing taxonomy entry, 126 via 77 newly-minted entries) — 5.62M MYR of the ~9.5M in-scope worklist GMV remains unmapped: 115 brand-matched-but-size-not-extractable, 187 brand-unidentifiable-from-text (mostly the already-documented "genuinely unbranded freeze-dried booster/treat" pattern), plus the 252 correctly-OOS. Claimed SKU block `SKU-155023`–`SKU-155717` (695 slots); used `SKU-155023`–`SKU-155099` (77), 618 unused | Session ran out of reasonable turn budget for a full image-verification pass on the remaining 302 brand-or-size-ambiguous products — flagged below for a future session |
| 2026-07-23 | Top-up coverage | **Known simplification:** new entries were grouped/deduped by `(brand, size, pack_count)` only, not by product line — e.g. all "Advance Cat - Urinary" and "Advance Cat - Renal" 1.5kg listings would collapse to one entry if they shared that exact size/pack (in this run they didn't collide, but the risk exists for future brand/size overlaps). This is the coverage-over-precision tradeoff the Full Rebuild/top-up scenario calls for; a future `targeted_qa_fix.sh` precision pass should re-check each of the 77 new entries' `product_line`/`variant` split rather than assume the bulk-derived descriptor is exact | Not fixed this session — flagged for precision pass |
| 2026-07-23 | Top-up coverage | Self-check QA gates (G1, G2, G4, G5, placeholder-leak, structured-fields-NULL%) run without `--skip-coexistence` (per this being a post-initial-ship category) | All passed: 0 dual-mapped (LLM-scoped), 0 HUMAN+LLM coexistence, 0 cross-category `taxonomy_id` leakage, 0 provenance gaps, 0 placeholder-leak canonical names, 32% NULL `product_line` (existing 1,554 + 77 new combined, under the 50% threshold) |
| 2026-07-23 | Top-up coverage | **Anomaly found during post-write verification, not resolved:** re-running the exact STEP-0 live-worklist SQL (grouped by `url, image, product_id, sku_name, flag_GWP`) after the writes intermittently still listed some of this session's own newly-mapped `product_id`s as `canonical_name IS NULL`, and returned inconsistent total counts (1,085) across repeated cache-busted re-runs of the identical query. Direct verification (`product_taxonomy_map JOIN product_taxonomy` for all 141 target `product_id`s, and a simplified product_id-grain rewrite of the worklist query) both confirm all 141 writes are correct and stable, and the true remaining gap is **554 products / 5.62M MYR GMV** — matching 695−141 exactly. Root cause not identified in this session (suspect BigQuery `QUALIFY`/window-function tie-breaking instability in the finer (url,image,sku_name)-grained grouping, though no fan-out was found for the specific products checked) | Do not trust the STEP-0 query's raw row count for this table without cross-checking against a simple product_id-grain join — flagged for investigation in a future session |
| 2026-07-23 | Second top-up coverage (this session) | Re-ran the live STEP-0 worklist query directly rather than trusting the wrapper's pre-check number (per prior session's own anomaly finding) — confirmed exactly 554 products with `taxonomy_id IS NULL`, matching the wrapper's figure. Also found `/tmp/worklist.csv` and `/tmp/existing_taxonomy.csv` (generic shared filenames) got silently overwritten mid-session by other concurrent sessions running against `makanananjing_my` and `shopee_sg_pet_food` (visible live in `sku_block_registry`) | Moved all working files to a session-unique `/tmp` directory and re-generated every BQ export from scratch there before using it — a real, live collision risk this environment doesn't otherwise guard against for ad hoc file exports (only `sku_block_registry` and BigQuery itself are collision-safe) |
| 2026-07-23 | Second top-up coverage | Scope classification of the 554 live-worklist rows found and fixed several real classifier bugs before any SQL was generated: (1) `re.VERBOSE` silently stripped literal spaces from non-food phrase patterns ("condo house" → "condohouse"), so pet-bed/training-pad/toy/shampoo listings were never actually excluded; (2) a blanket dog-brand-name regex (TOTW, Addiction, Sniffly, Brit, Hill's, IAMS, Royal Canin, SmartHeart, Carnilove — all dual cat+dog brands) wrongly excluded real cat products just for containing the brand name, e.g. a genuine "Taste Of The Wild Rocky Mountain Cat Kibble" and a "Cindy's Recipe ... Sniffly ... Cat Wet Food"; (3) `\bdog\b`/`\bcat\b` word-boundary checks missed plural "Dogs"/"Cats" (e.g. "Goat Milk Powder For Dogs" was never excluded); (4) `Gajah Duduk Pelikat` (rolling papers), explicitly documented as OOS in this file's own Scope section, was never actually filtered by any pattern. Final split: 301 in-scope / 253 OOS (158 dog, 63 non-food, 24 litter, 6 flea, 1 baby formula) | Fixed all four bugs before generating any SQL; verified against this file's own documented OOS examples |
| 2026-07-23 | Second top-up coverage | Brand matching against the 301 in-scope rows found the same class of bug as scope classification: a naive substring match on normalized text (adopted to fix CJK brand names like 纯福/Chun Fu fusing with no space against adjacent Chinese text) let the alias `"n d"` (from brand `N&D`) match inside any "...protein **n** **d**og/duck..." text, since Latin words aren't separated by spaces the way tokens are padded. Fixed by requiring CJK aliases to match as plain substrings (correct — Chinese has no space delimiters) but Latin aliases to match only as a padded, space-bounded whole token | 175 of 301 in-scope rows brand-matched (127 to one of this category's 163 existing brands or a documented alias, e.g. `Reflex Plus`→Reflex, `D Zahara`→D'Zahara, `TOTW`→Taste Of The Wild; 57 to a brand new to this category — see below) |
| 2026-07-23 | Second top-up coverage | **Global `brand_dict` reuse-before-mint check** (per this file's own documented collision precedent) on all "new" brand candidates found 17 already existed elsewhere in the global dictionary: PETSEE (BRD-MY-01024), Carry's (BRD-MY-01133), Prochoice (BRD-SG-11543), Partner (BRD-MY-01157), Kucinta (BRD-MY-01032), Rich.Co (BRD-MY-01015), Proud Holistic (BRD-MY-01160), NurturePro (BRD-MY-01029), Gewuan (BRD-MY-01178, already known from this category), Legendsandy (BRD-MY-01147, already known), Hi-Cubs/喜崽 (BRD-SG-06569), Felix (BRD-GLOBAL-00230), Meow (BRD-SG-01596), BOSSKU (BRD-MY-01044), Wono (BRD-ID-07771), Chun Fu (BRD-MY-01051, already known). `Hegen` (BRD-SG-00702, SG) was deliberately **not** reused — that existing entity is a Singapore baby-bottle company, and this session's "Hegen Pet" cat-treat listings show a distinct "hegen pet" logo in-image, making them very likely a different real-world business coincidentally sharing the name; conflating them would misattribute cat treats to an unrelated baby-products brand | Reused 16 existing global `brand_id`s; did not mint or map `Hegen` this session (products left unmapped — see below) |
| 2026-07-23 | Second top-up coverage | 28 brands confirmed genuinely new after the global check (AliCat, CICI, Cat's Eye, Docile, Fish In, Food Chain, GINO, Greens, Healthy Catz, Hell's Kitchen, I Have Shanhai, MICAT, MORTITI, Manroupaipai, Masha Cat, Matisse, Mera, Mito Lamito, Muezza, Naisi, Nice Bite, PETSUP, Pet Runner, Si Comot, The Cat's Travel, Trawler, Yamagold, ZUVA). Minted `BRD-MY-01187`–`01214` (re-verified `MAX(BRD-MY-*)` immediately before the atomic-computed insert per this category's own documented collision risk; re-checked post-insert via `COUNT(*) = COUNT(DISTINCT brand_id)` — no collision, 28/28 unique) | Minted 28 new brand rows |
| 2026-07-23 | Second top-up coverage | Size/pack extraction via `sku_name` regex resolved only 57 of 175 brand-matched rows (much of this category's remaining gap is genuinely size-silent listings, consistent with the first top-up session's finding). Given the resulting ~1.47M MYR of brand-matched-but-size-unresolved GMV, image-verified the 15 highest-GMV such listings directly (`curl` + `Read`, per this file's and the runbook's documented pattern) — resolved 8 more (Nanovet Freeze Dried Combo 200g, Rosy Fresh Roast Meat 2kg, MORTITI Chicken Breast 40g in both a 50-pack and single-pack SKU, Nanovet Topper 70g×6, Cassiel Urinary 1kg, MASTI Chicken Breast 40g, Whiskas Tasty Mix 70g×24), confirmed 1 as genuine multi-brand mix unattributable to any single brand_id (Royal Canin + Purina ONE + Taste Of The Wild kibble blended into one reseller SKU — left unmapped rather than misattribute to one of the three), confirmed 1 as a non-food merch item ("PURINA Felix Wide Shopping Bag", `[NOT FOR SALE]` — matches this file's own documented merch-item precedent), and left 5 genuinely size-unresolved even from the image (per-sachet/per-stick gram weight not legible on 3 Hegen listings, 1 FURVIT Nutri Lick, 1 Amelisa Rawly Stick, 1 Pawmised Catty Flossy topper) | 65 total mappable products (6 reused an existing taxonomy entry exactly on `(brand_id, size, pack_count)`, 59 needed a new entry) |
| 2026-07-23 | Second top-up coverage | Claimed SKU block `SKU-157403`–`SKU-157956` (554 slots, atomic `DECLARE`/`BEGIN TRANSACTION` claim per the runbook). Grouped the 65 mappable products by `(brand_id, size, pack_count, is_multi_size)`: 6 exact-matched an existing taxonomy entry (reused directly, no new row), 53 groups had no existing match and got one new taxonomy entry each (covering the other 59 products) — used `SKU-157403`–`SKU-157455` (53 of 554 claimed slots), 501 unused. Two groups (Food Chain, Hell's Kitchen, both genuine "80g/170g"-style buyer-choice multi-size listings) were correctly written `is_multi_size=TRUE, size=NULL` with a real brand+descriptor name, never "Multiple Sizes" text (checked against this file's own banned-phrase precedent before writing) | 53 new `product_taxonomy` rows + 65 new `product_taxonomy_map` rows written via `bq query` DML, `meta_agent='CLAUDE_CODE'`, `source='LLM'` on every row |
| 2026-07-23 | Second top-up coverage | Self-check QA gates (G1 dual-mapped, G2 HUMAN+LLM coexistence, G4 cross-category `taxonomy_id` leakage, G5 provenance, placeholder-leak) run without `--skip-coexistence`, scoped to `master_table='makanankucing_my'` | All passed: 0 dual-mapped (LLM-scoped), 0 HUMAN+LLM coexistence, 0 out-of-range/cross-category `taxonomy_id`s (all map rows resolve to this category's own 3 claimed blocks), 0 provenance gaps, 0 placeholder-leak canonical names |
| 2026-07-23 | Second top-up coverage | **Remaining gap after this session: 489 products (554 − 65)**, breakdown: ~237 in-scope but brand-unidentifiable-from-text or size-unresolved-even-from-image (mostly the already-documented "genuinely unbranded freeze-dried booster/treat" commodity pattern, plus a handful of newly-identified-but-size-silent branded listings like Hegen/FURVIT/Amelisa/Pawmised toppers), ~253 correctly-OOS this pass (158 dog, 63 non-food/accessory, 24 litter, 6 flea/dewormer, 1 baby formula) | Not fixed this session — flagged for a future top-up or `targeted_qa_fix.sh` pass; per this session's own turn budget, did not attempt a full image-verification sweep of all ~118 remaining brand-matched-but-size-unresolved rows, only the top 15 by GMV |
| 2026-07-28 | Third top-up coverage (Tiktok scope added) | Re-ran the live STEP-0 worklist query directly rather than trusting the wrapper's 1,501 pre-check number — confirmed exactly 1,501 products with `taxonomy_id IS NULL`, matching the wrapper's figure. All 1,501 were `ecommerce_platform='Tiktok'` — Tiktok entered scope for the first time this session (prior sessions' 489-product Shopee gap dropped out of the live top-95%-cumulative-GMV window because Tiktok's inflated GMV figures now dominate the ranking; this is a side-effect of the documented Tiktok GMV data issue, not a coverage regression — those Shopee products still have `taxonomy_id IS NULL`, just outside this session's 95% window) | Proceeded with the live 1,501-product Tiktok worklist per the session brief's explicit scope decision |
| 2026-07-28 | Third top-up coverage | Scope classifier's first pass wrongly excluded ~112 genuine cat-food listings (`no_food_kw` rule required an explicit food/kibble/makanan keyword, but many listings are brand+descriptor+size only, e.g. `"Reflex Plus Adult Chicken 15kg"`, `"ROYAL CANIN HAIR & SKIN 10KG"`) — caught by manually reading the rejected bucket before generating any SQL. Also found 2 false-positive OOS matches: `"Rich Choice Holistic ... Dry Cat Food (Coat & Flea Control...)"` (flea-repelling *feature* of food, not a standalone flea treatment) and `"Meow Litter Fat Premium Cat Treat..."` (bare `litter` substring-matched a typo'd "Little Fat" booster-treat listing, not actual cat litter) | Dropped the food-keyword requirement (source table is already the cat-food category feed — default in-scope, exclude only on explicit OOS signal); tightened `flea`/`litter` patterns to require the real product bigram or absence of a food-framing keyword. Final split: 1,499 in-scope / 2 OOS (1 litter, 1 grooming/supplement product) |
| 2026-07-28 | Third top-up coverage | Brand matching: built an alias table from this category's 198 existing `brand_dict` entries + documented consolidation aliases, then a `REGEXP_CONTAINS` sweep of the *global* `brand_dict` for repeated unmatched-candidate tokens found 7 reuse hits (Kucinta, Deeplove, Midalac, Omega Plus, PUAINTA, Pet Record, my meow) plus several worklist-text-vs-brand_dict-spelling mismatches within this category's own existing brands (`SPACECAT`, `Si Comot`, `Carry's`, `SmartHeart`, `Smartz Choice`, and `A-Tier`/"Sarar" — the last reusing this category's own pre-existing brand_id/canonical_name mismatch from an earlier session for consistency rather than minting a duplicate). 1,233 of 1,499 in-scope rows (82%, 90% of in-scope GMV) brand-matched; 266 left unmatched (genuinely brand-unidentifiable from text, consistent with prior sessions' commodity-treat pattern) | Minted 18 confirmed-new brands (`BRD-MY-01230`–`01247`, re-verified `MAX(BRD-MY-*)` immediately before insert; re-checked post-insert via `COUNT(*) = COUNT(DISTINCT brand_id)` — no collision, 18/18 unique) — see Brand IDs Assigned above for the full list and reuse map |
| 2026-07-28 | Third top-up coverage | Size/pack regex (built fresh this session, not reused from a prior session's script since none is committed) had two bugs caught before writing: (1) the unit-alternation regex required a trailing "m" for gram-unit matches (`gr?a?ms?`), so bare `"g"` and `"gr"` never matched at all — silently missed slash-separated multi-size listings like `"60g/550g"`; (2) `\b` word-boundary checks after a unit fail on no-space runs like `"85gx12"` (letter→letter, no boundary) and on multi-digit numbers following a single-digit pack check (`"x 16"` — boundary check landed between "1" and "6"), both matching this file's own previously-documented gotcha class for this source table. Also caught a false-positive: `"ProDiet 8kg... (8kg/500g x 16 Packs)"` initially flagged as multi-size-alternation by the slash-pattern gate even though `500g×16=8kg` is a consistent pack breakdown, not two alternative sizes | Fixed unit alternation to include bare `g`/`gr`, replaced boundary check with a lookahead permitting no-space `x<digit>` runs, and added a pack-qualifier guard + same-unit ratio-consistency check so a "total/breakdown" pattern isn't misread as buyer-choice multi-size. Verified against multiple sample rows post-fix before generating SQL |
| 2026-07-28 | Third top-up coverage | Grouped the 1,233 brand-matched rows by `(brand_id, size, pack_count)` (concrete) or `(brand_id)` with `is_multi_size=TRUE` (40 rows, buyer-choice multi-size listings like `"1.5KG & 2KG"`, `"500GM/1KG"`) — 428 groups total, 277 exact-matched an existing taxonomy entry (reused), 151 needed a new entry. 130 rows had no extractable size (not genuinely multi-size either) and were left unmapped rather than guessed, per this file's own established precedent | Claimed SKU block `SKU-191043`–`SKU-192543` (1,501 slots, atomic `DECLARE`/`BEGIN TRANSACTION` claim). Wrote 151 new `product_taxonomy` rows (`SKU-191043`–`SKU-191193`, 1,350 slots unused) + 1,103 new `product_taxonomy_map` rows via `bq query` DML, `meta_agent='CLAUDE_CODE'`, `source='LLM'`, `platform='Tiktok'`, `country='MY'` on every row. First DML attempt for the map rows failed cleanly with 0 rows written (`confidence` column is `STRING` in this table, not `FLOAT64` as `ARCHITECTURE.md` documents, and the `country` column — part of the ADR-006 composite key — was initially omitted) — fixed and re-ran before any partial write occurred |
| 2026-07-28 | Third top-up coverage | Self-check QA gates (G1 dual-mapped, G2 HUMAN+LLM coexistence, G4 cross-category `taxonomy_id` leakage, G5 provenance, placeholder-leak), run without `--skip-coexistence`, scoped to `master_table='makanankucing_my'` | All passed: 0 dual-mapped (LLM-scoped, keyed on product_id+platform+country), 0 HUMAN+LLM coexistence, 0 out-of-range/cross-category `taxonomy_id`s (all map rows resolve to this category's own 4 claimed blocks), 0 provenance gaps, 0 placeholder-leak canonical names, 30% NULL `product_line` among LLM entries excluding multi-size catch-alls (well under the 50% threshold) |
| 2026-07-28 | Third top-up coverage | **Remaining gap after this session: 396 products** (266 brand-unidentifiable-from-text + 130 brand-matched-but-size-unresolved), all in-scope. This is a bulk-first regex-only pass (per the session brief's coverage-over-precision mandate) — no product images were read this session; `product_line`/`variant` text is regex-stripped `sku_name` remainder and retains noise on some long-tail entries (consistent with the "known simplification" already accepted for this category's prior sessions) | Not fixed this session — flagged for a future top-up (image-based resolution of the size-unresolved tail) or `targeted_qa_fix.sh` precision pass on the 151 newly-minted entries' `product_line`/`variant` split |

---

## Targeted QA Fix Brief

> Scope for a future `targeted_qa_fix.sh` / NULL-coverage session — not executed this session.
> **Note (2026-07-28):** the figures below predate the Tiktok-scope top-up sessions and are stale —
> see "Map Row Counts" above for the current gap (396 products, all Tiktok, as of 2026-07-28) and this
> session's QA History rows for what's specifically unresolved. Kept here as historical record of the
> original Shopee-only gap.

**Verdict:** D6 in-scope NULL coverage gap + D1/D2 precision pass needed.

- **Coverage gap A** (458 products, ~3.54M MYR GMV): 334 brand-unidentifiable + 124 size-ambiguous
  products left `taxonomy_id IS NULL`. See "Known coverage gaps" above for the exact lists —
  candidates for direct image-based resolution (text signals were exhausted; image wasn't checked
  per-product given this session's bulk-first budget, only spot-checked on ~10 top-GMV examples).
- **Precision pass B**: this was a coverage-first bulk regex/text-matching pass (Full Rebuild
  scenario explicitly deprioritizes per-row precision — see `docs/headless-runbook.md`). Product-line
  text for long-tail brands is regex-stripped `sku_name` remainder and occasionally retains noise
  (e.g. `Aristo Cats G Plus Tuna Wet Chunk Meat Snack TPF` — stray `G`/`TPF` fragments). A pass
  re-reading product images for the long tail (~130 brands outside the top 15) would sharpen D2
  (product line accuracy) without needing full re-extraction.

---

## Scripts

No committed pipeline scripts for this category — extraction was done directly (multimodal reading +
ad hoc SQL/Python, not a `pipeline/05_product_taxonomy/llm_{table}/` script) per the session brief for
this custom, non-NIQ source table.

---

## Map Row Counts (as of the third top-up session, 2026-07-28, this session — Tiktok scope added)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 3,141 | 1,832 Full Rebuild + 141 first top-up + 65 second top-up + 1,103 this session (all Tiktok — bulk regex text-matching against sku_name, no image reads this session) |
| HUMAN | 0 | No prior keyword-seed pass for this category |
| NULL (unmapped, in-scope, live-worklist gap remaining) | 396 | 266 brand-unidentifiable-from-text + 130 brand-matched-but-size-unresolved (neither genuinely multi-size nor text-extractable) — see this session's QA History row below |
| NULL (out-of-scope, correctly excluded, this session's live worklist) | 2 | 1 cat litter, 1 grooming/supplement product mixed with shampoo mention |

Prior sessions' snapshots (kept for history):

Snapshot before this session's top-up (after the second 2026-07-23 top-up):

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 2,038 | 1,832 Full Rebuild + 141 first top-up + 65 second top-up |
| NULL (unmapped, in-scope, live-worklist gap remaining) | 489 (~3.35M MYR) | Mostly genuinely brand-unidentifiable or size-unresolved-even-from-image commodity treats |
| NULL (out-of-scope, correctly excluded) | 253 | 158 dog, 63 non-food/accessory, 24 cat litter, 6 flea/dewormer, 1 baby formula |

Snapshot before the second top-up (after the first 2026-07-23 top-up):

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 1,973 | 1,832 from Full Rebuild + 141 from the first 2026-07-23 top-up |
| NULL (unmapped, in-scope, live-worklist gap remaining) | 554 (~5.62M MYR) | 187 brand-unidentifiable-from-text + 115 brand-matched-but-size-unresolved + the original 458/237 breakdown below |
| NULL (out-of-scope, correctly excluded) | 252 | 138 pure dog food, 59 non-pet merch/accessories, 24 cat litter, 17 dog-only brands, 6 flea/tick, 3 merch/GWP-only, 1 baby formula, 2 manually-overridden mislabeled dog-food listings |

Snapshot before the first 2026-07-23 top-up (Full Rebuild only):

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 1,832 | Full Rebuild first run |
| NULL (unmapped, in-scope) | 458 | 334 brand-unresolved + 124 size-ambiguous — see Targeted QA Fix Brief |
| NULL (out-of-scope, correctly excluded) | 237 | Dog food / litter / flea treatment / non-pet items |
