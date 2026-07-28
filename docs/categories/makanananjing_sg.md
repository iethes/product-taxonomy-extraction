# makanananjing_sg — Category Context

> Custom (non-NIQ) source: `sincere-hearth-273704.makanananjing.9_makanananjing_sg_daily`
> (TikTok Shop Singapore, daily grain summed to monthly). Not a `master_clean_niq` table — different
> schema (daily grain, no `month`/`model_id` columns the way NIQ tables have). Unlike the sibling
> `makanananjing_my`/`makanankucing_my` MY tables, this table **does** carry `merchant_id`/
> `merchant_name`/`merchant_badge` columns — but `merchant_badge` is uniformly `'Tiktok Shop'` for all
> 1,370 source rows (no per-brand official-store tier the way Shopee Mall works), so the Pass-1
> official-store-allowlist strategy still doesn't apply here in practice, even though the "no merchant
> data" premise in the session prompt was technically incorrect. Taxonomy state is keyed under
> `master_table = 'makanananjing_sg'`, not the source table name.
>
> **Platform/country note:** the source is 100% `ecommerce_platform = 'Tiktok'`, `country = 'SG'`
> (685 distinct products, all TikTok Shop). `product_taxonomy_map`/`product_brand_map` rows for this
> table are written with `platform = 'TikTok Shop'` (the documented ARCHITECTURE.md/data-dictionary.md
> enum value, confirmed as the live convention already used for TikTok Shop rows in `product_brand_map`
> across ID/TH/VN/PH/MY — SG had 2,122 pre-existing TikTok Shop brand-map rows before this session,
> none for this specific product set), `country = 'SG'`.

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass | ✅ Complete (Full Rebuild, first run) + top-up 2026-07-28 |
| GMV Coverage | 87.11% of total table GMV (201/685 products mapped); 94.9% cumulative-GMV in-scope worklist fully worked (201 mapped + 8 legitimately excluded/unresolved of 209) |
| Last run | 2026-07-28 (top-up session) |
| Current MAX taxonomy_id (this category) | SKU-190645 — **query BQ directly before trusting this**, per CLAUDE.md's SKU Block Management warning |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-186352–SKU-188351 | Claimed block (2,000 slots, `sku_block_registry`, scenario `custom_full_rebuild`) |
| SKU-186352–SKU-186545 | First pass, 194 taxonomy entries |
| SKU-186546–SKU-186547 | Post-write precision fix (split 2 over-merged entries, see QA History) — 196 taxonomy entries actually used total; remainder (186548–188351) left unused |
| SKU-190643–SKU-190842 | Top-up session 2026-07-28 (200 slots, `sku_block_registry`, scenario `custom_topup`) — 3 taxonomy entries used (190643–190645); remainder left unused for future top-ups |

---

## Brand Scope

56 distinct brands mapped (49 reused from existing global `brand_dict` plus 8 newly minted local brands
with no prior `brand_dict` presence: `BRD-SG-14499`–`BRD-SG-14505` from the first-run session
(Sourcesage Club, FREZ, Barsk, Chonk Club, Mercifur, Bethel Pet, Dr. Pat Pat) and `BRD-SG-14510`
(小七妈妈 / Xiao Qi Ma Ma) from the 2026-07-28 top-up session — see QA History). Two more top-up
products reused existing global brands not previously mapped in this category: Addiction
(`BRD-SG-00986`) and Luffy's Pawfect Picks (`BRD-SG-10950`). Top brands by mapped GMV:

1. **Taki Pets** — `BRD-SG-01350` — 7 products, $10,910.72 SGD
2. **Sourcesage Club** — `BRD-SG-14499` (new) — 33 products, $8,812.91 — single-ingredient air-dried/dehydrated animal-part chews, one entry per cut/species
3. **Dr.Shiba** — `BRD-GLOBAL-00298` — 6 products, $3,544.93
4. **Absolute Holistic** — `BRD-GLOBAL-00902` — 15 products, $3,088.00
5. **Food For The Good** — `BRD-SG-01098` — 11 products, $2,812.10
6. **Wanpy** — `BRD-SG-02024` — 13 products, $2,588.02
7. **Singapaw** — `BRD-SG-01506` — 6 products, $2,577.53
8. **Pawlicious** — `BRD-SG-04278` — 13 products, $2,513.05
9. **Bronco** — `BRD-SG-01185` — 5 products, $2,038.51
10. **FREZ** — `BRD-SG-14500` (new) — 7 products, $1,783.33
11. **Absolute Bites** — `BRD-SG-00740` — 7 products, $1,178.69

Remaining 43 brands (Royal Canin, Ziwi Peak, Taste Of The Wild, aTwoValley, Barsk, Happi Skippi,
Loveabowl, Stella & Chewy's, Underdog, Cesar, Bow Wow, NurturePro, The Better, Vitakraft, OMAKASE,
JerHigh, Notti, Hoya Barkery, Hill's SCIENCE DIET, Probalance, Knine Culture, Chonk Club, Kyndred Paws,
Urban Waggo, Orijen, Petio, Boneve, Holuah!, BIG BROWN DOG, Kooky Kibble, Mercifur, SmartBones, Solid
Gold, BelliFull, Platinum Choice, Joberill, Atasco, Bethel Pet, Pedigree, Dr. Pat Pat, SoulMate, Top
Ration) each contribute 1-4 products, $46–$402 GMV — long tail.

`BRD-UNBRANDED` used for 4 genuine cross-brand "[LIVE EXCLUSIVE BUNDLE]" grab-bags (no dominant brand
identifiable from title/image) and 1 generic dental-chew private-label listing, $2,769.31 combined.

No official-store allowlist — `merchant_badge` carries no per-brand tier signal on this source table
(see header note); routing was bulk text-matching on `sku_name`, corroborated by `merchant_id` grouping
where the same seller's sibling listings established a brand name that an individual listing's title
omitted (e.g. 3 of "The sourcesage club"'s 33 listings lack the "Sourcesage Club" token in-title but
share the identical merchant_id and product-naming convention as the 30 that do carry it), plus 6
targeted product-image reads for cases where text signals were genuinely ambiguous or absent.

---

## Scope — What's In vs Out

**In scope:** dog dry food, dog wet food (tray/can), dog treats (jerky, air-dried, freeze-dried,
dehydrated single-ingredient chews), dental chews/sticks, dog nutritional supplements (joint, gut,
skin/coat, calming). Dual-species "for Dogs & Cats" listings kept in scope (no cat-exclusive listings
were found in this worklist at all — every "cat" mention co-occurred with dog/puppy/canine text).

**Out of scope (left NULL):**
- **Diagnostic/medical, not food**: Pawllergy Test Kit (food/environmental allergy sensitivity test,
  $3,971.56 — 2nd-highest GMV item in the worklist; a real, deliberate NULL, not a coverage miss).
- **Human products (general-merch contamination)**: Health+ Orofill Revive 60s Softgel — image-confirmed
  human wellness supplement (JML brand, vaginal/eye/skin dryness), $493.85. This source table has no
  fixed `category_1`/`category_2` mislabeling issue like the MY sibling tables, but individual listings
  from mixed-catalog TikTok sellers still leak through.
- **Brand genuinely unreadable (UNRESOLVED, not force-mapped)**: 6 products, $531.19 combined — all from
  merchant "Sniff Sniff SG" (Dehydrated Pork Ears, Duck Gizzards & Hearts, Pork Chops, Duck Trachea, Duck
  Feet, Beef Tendon — dehydrated single-ingredient treats with no brand token in `sku_name`; all 6 images
  checked 2026-07-28, each shows only the loose product with no packaging/label at all). Per
  `docs/product-lifecycle.md` §5, UNRESOLVED (leave NULL) is the correct output when brand cannot be
  confidently determined from text or image — not forced into a generic catch-all.
  **Corrected 2026-07-28**: the first-run session's doc text undercounted this bucket at "5 from Sniff
  Sniff SG" (actually 6) and had folded 3 *other* products into the same "unresolved" bucket without
  individually verifying their images — those 3 turned out to be resolvable on re-check; see QA History.

**Edge cases:**
- **Sourcesage Club vs Sniff Sniff SG naming-convention collision**: both sellers use near-identical
  "[cut] (single ingredient dog treats, dog dental chew)" title phrasing for air-dried/dehydrated animal
  parts. Distinguished by `merchant_id`/`merchant_name` (not used as a naming signal per
  `llm-extraction-rules.md` §11 — the brand *name* "Sourcesage Club" comes from 30 of that merchant's own
  listing titles; merchant identity was only used to decide which un-suffixed listings belong to that
  already-text-established brand, and conversely to correctly withhold the Sniff Sniff SG listings from
  it since that merchant's titles never carry any brand token).
- **`[Chewbarka]` bracket suffix**: appears on aTwoValley, Notti, and Mercifur listings. Confirmed via
  `merchant_name = 'Chewbarka'` to be a multi-brand reseller's own store tag, not a product brand —
  correctly excluded from `product_line`/`canonical_name`, real brand taken from the rest of the title.
- **`【Mi Pet Lover】` bracket prefix**: same pattern — a reseller tag on a Food For The Good listing,
  stripped.
- **Knine Culture "Rabbit Ears" (2 listings, different `merchant_id`s) vs Sourcesage Club "Rabbit Ears
  With Fur"**: image-verified Knine Culture has a genuine printed brand logo on packaging ("KNINE CULTURE
  — EAT SLEEP PLAY TRAIN BOND"), distinguishing it from the Sourcesage Club product of the same animal
  part sold by a different seller — kept as two separate taxonomy entries under two different brands, not
  merged.
- **Bethel Pet**: `sku_name` was fully generic ("Grinding teeth snack; beef flavor bone-shaped dental
  stick") with no brand text at all — image-read revealed the real packaging brand "Bethel Pet" and pack
  structure (10g/stick, 8 sticks/pack). New brand minted from the image read, not the title.
- **Multi-size / multi-variant selector listings**: several titles state a size range ("454g/1kg/2.5kg/
  4kg", "500g-1.5kg", "2kg/12kg") or an explicit flavor-count selector ("6 Flavors Available", "20
  Flavours"). Per `llm-extraction-rules.md` §2 (amended 2026-07-22), these got `is_multi_size=TRUE` /
  `is_multi_variant=TRUE` with `size=NULL` and **no** "Multiple Sizes"/"Multiple Variants" text in
  `canonical_name` — the flag alone conveys that semantic (verified via the placeholder-leak QA gate,
  which regexes for exactly that banned phrasing).

---

## Taxonomy Design Notes

**Extraction method:** bulk text-matching on `sku_name`, grouped by (brand, product_line, variant, size,
pack_count) into 194 taxonomy entries covering 198 products (194 ≠ 198 because 4 pairs of near-duplicate
reseller/repeat listings collapsed onto a shared entry, e.g. two identical "Sourcesage Club Air Dried
Ostrich Flat Tendon" listings from different sellers, two identical Bronco Pate Tray Wet Food 16-tray
bundles). 6 individual product images were read where `sku_name` text was insufficient to determine
brand or product identity (Taki Pets bulk-pack composition, Bethel Pet, Knine Culture rabbit-ears
authenticity check, Sniff Sniff SG brand-absence confirmation, Health+ Orofill Revive scope
determination, one multi-species generic-snack scope check) — all other products were resolved from
`sku_name` text alone per the bulk-first, coverage-priority mandate for Full Rebuild sessions.

**product_line:** derived from the on-label product line/flavor description in `sku_name` after
stripping the brand token, promo tags (`[PROMO]`, `*PROMO*`, `[CLEARANCE]`, percentage-off tags), reseller
bracket tags (`[Chewbarka]`, `【Mi Pet Lover】`), and size/pack tokens. `sub_line` left NULL throughout (no
listings had a genuine third-level naming tier beyond product_line + variant). `variant` populated for
~20 entries with a clearly stated single flavor/type (e.g. "Beef" on Bethel Pet's dental stick, "Salmon
Floss" on a Taki Pets treat); left NULL for true single-SKU products with no flavor axis.

**Size/pack extraction:** regex over `sku_name` for `\d+(kg|g|ml|L|lb|oz)` and explicit multiplier
patterns (`[Bundle of N]`, `[N Trays]`, `NxM` — e.g. Absolute Holistic's `[Carton Deal] ... (16x100g)` →
size=100g, pack_count=16). Listings whose sizes are seller-side option selectors ("227g/1.5kg/9.9kg",
"2.5\"|50x9g / 4\"|20x25g") were set `is_multi_size=TRUE`, `size=NULL` rather than guessing one value.

**Known difficult products:**
- `1730813571110897076` — "[Assorted] Single Protein Natural Flavour Gently Dehydrated Dog Treats by
  BigBrownDog..." — text explicitly names "BigBrownDog" twice but doesn't match the existing brand_dict
  spelling ("BIG BROWN DOG", `BRD-SG-02875`) exactly; matched by normalization, not a new brand.
- Sourcesage Club's 33-entry catalog is one taxonomy entry per (animal origin × cut), with no
  size/pack stated on almost any listing — a category where "single ingredient chew" genuinely has no
  weight/count on the packaging per the seller's own listings; left `size=NULL`, `pack_count=1` (not
  `is_multi_size`, since these are not selector listings — each is a distinct single-SKU product, just
  without a stated weight).

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-28 | Full Rebuild (first run) | Confirmed 0 pre-existing `product_taxonomy_map` rows for `master_table='makanananjing_sg'` — genuine first run (STEP 1 re-verify) | Proceeded per Full Rebuild scenario |
| 2026-07-28 | Full Rebuild | Session prompt's premise "no merchant/brand/official-store data in this source table" was factually wrong — `merchant_id`/`merchant_name`/`merchant_badge` all exist on this table, unlike the MY sibling tables the prompt template was written for | Verified `merchant_badge` is uniformly `'Tiktok Shop'` (1,370/1,370 source rows) — no per-brand tier signal exists in practice, so the prompt's operational conclusion (skip Pass-1 official-store allowlist) held despite the wrong premise. `merchant_name`/`merchant_id` were still used (per `llm-extraction-rules.md` §11's allowed scope) to disambiguate two sellers using near-identical product-naming conventions — see Scope § Edge cases |
| 2026-07-28 | Full Rebuild | `image` column format differs from `docs/headless-runbook.md`'s documented "direct CDN URL" — it's a Python-repr'd list of dicts with `url_list` arrays (TikTok CDN, webp, multiple resolutions) | Confirmed the `curl -sL -o <file> "<url_list[0]>"` → `Read` pattern still works after extracting the first URL; used for 6 targeted ambiguous-case verifications |
| 2026-07-28 | Full Rebuild | Cross-`master_table` true-composite-key collision check (`platform='TikTok Shop', country='SG'`) run **before** writing, against all 209 in-scope product_ids — 0 collisions found (no other category has touched these TikTok Shop SG product_ids) | No action needed; confirmed clean via `docs/categories/makanananjing_my.md`'s established pre-write-check precedent |
| 2026-07-28 | Full Rebuild | `product_brand_map` has 0 rows for any of these 209 product_ids (`platform='TikTok Shop', country='SG'`) — Stage 03 brand resolution has never run for this product set, mirroring the documented gap for `shopee_id_*` tables in `docs/categories/STATUS.md` | Not a blocker for Phase 5 — `product_taxonomy`/`product_taxonomy_map` brand assignment is independent of `product_brand_map`; noted for awareness, not remediated this session |
| 2026-07-28 | Full Rebuild | Pre-report review found 2 of the 4 taxonomy entries that collapsed 2 products onto 1 entry were genuine over-merges, not true duplicates: (1) Absolute Bites "Single Ingredient Air Dried Treats" merged a "Small Pack (35g-240g)" listing and a "Big Pack (150g-900g)" listing into one entry — different seller-labeled pack tiers, not the same product; (2) OMAKASE's generic multi-variant catch-all merged a regular listing with a "[MEDIUM Packs] WHOLESALE" listing — different pack tier. (The other 2 merges — Sourcesage Club Ostrich Flat Tendon reseller dup, Bronco 16-tray Pate Tray dup — were verified genuine.) Also found the 5 `BRD-UNBRANDED` entries had the raw brand_id leaking into `canonical_name` (e.g. "BRD-UNBRANDED Live Exclusive Bundle Medium Dog") — a placeholder-leak-class defect the QA gate's regex didn't catch since it doesn't check for a `BRD-` prefix | Split the 2 over-merged entries: minted `SKU-186546` (Absolute Bites Big Pack) and `SKU-186547` (OMAKASE Wholesale Medium Pack) from the unused block remainder, re-pointed the 2 affected `product_taxonomy_map` rows, renamed the original 2 entries to disambiguate ("(Small Pack)" / drop the wholesale qualifier). Stripped the `BRD-UNBRANDED ` prefix from all 5 affected `canonical_name` values via `REGEXP_REPLACE`. Re-ran QA gates after fix (see below) |
| 2026-07-28 | Full Rebuild | Self-check QA gates, post-fix (G1, G2 without `--skip-coexistence` since no pre-existing HUMAN rows exist, G4 full cross-table, G5, placeholder-leak extended to also check for a leaked `BRD-` prefix, structured-fields-NULL%): G1=0, G2=0, G4=0, G5=0, placeholder-leak=0, structured-fields-NULL%=0% (well under 50% threshold) | All gates pass; proceeded to write category doc |
| 2026-07-28 | Top-up (custom_topup) | Re-ran the live 95%-cumulative-GMV (GWP-zeroed) worklist query rather than trusting the wrapper's "11 products" figure — result was the identical 11 products the same-day Full Rebuild session had already evaluated and left NULL (2 OOS: Pawllergy Test Kit, Health+ Orofill Revive; 9 in the "brand genuinely unreadable" bucket). Not a new coverage gap — the wrapper can't distinguish "deliberately excluded" from "never evaluated" since both read as `taxonomy_id IS NULL` | Applied the category doc's already-documented OOS verdicts to the 2 OOS products without re-litigating them. Re-verified all 9 "unresolved" products by fetching and reading each product image directly (not just trusting the prior session's text) rather than assuming the prior verdict was exhaustive |
| 2026-07-28 | Top-up (custom_topup) | Image re-verification found 3 of the 9 "unresolved" products actually have a legible on-package brand the first-run session missed: (1) `1732640443239138793` "Wild Kangaroo & Apples..." — packaging clearly printed "ADDICTION" (existing brand `BRD-SG-00986`, no prior taxonomy entry in this category); (2) `1731236091961050927` "Freeze Dried Chicken for Cats & Dogs..." — jar label printed "LUFFY'S PAWFECT PICKS" (existing brand `BRD-SG-10950`, no prior entry); (3) `1735440315142473603` "steamed vacuumed packed snack..." — Chinese-language packaging printed "小七妈妈" (no `brand_dict` entry existed for any transliteration). Cross-`master_table` composite-key collision check (`platform='TikTok Shop', country='SG'`) run before writing — 0 collisions, consistent with this category's established pre-write-check precedent. The remaining 6 (all merchant "Sniff Sniff SG") were independently re-confirmed as genuinely unbranded — each image shows only the loose dehydrated product, no packaging at all | Minted brand `BRD-SG-14510` (小七妈妈) in `brand_dict`. Claimed a fresh 200-slot block `SKU-190643`–`SKU-190842` (`sku_block_registry`, scenario `custom_topup`) rather than reusing the first-run session's unused remainder, per this session's explicit claim procedure. Wrote 3 new `product_taxonomy` entries (`SKU-190643` Addiction Wild Kangaroo & Apples Sensitive Care, `is_multi_size=TRUE` since sku_name states two sizes "1.8kg, 9kg" with no signal to resolve which one this specific listing sells; `SKU-190644` Luffy's Pawfect Picks Freeze-Dried Chicken, size left NULL — genuinely unstated in text/image/schema, not a selector listing, same precedent as the Sourcesage Club catalog; `SKU-190645` 小七妈妈 Steamed Pet Snack 30g, `is_multi_variant=TRUE` since sku_name lists many flavors) and 3 `product_taxonomy_map` rows (`source='LLM'`, `source_listing='image_verified'`, `brand_from_image` populated, `meta_agent='CLAUDE_CODE'`). All via `bq query` DML, no streaming API, no existing rows touched or deleted |
| 2026-07-28 | Top-up (custom_topup) | Self-check QA gates post-write, scoped to `master_table='makanananjing_sg'`, **without** `--skip-coexistence` (coexistence is a genuine bug at this point per this session's instructions, not an expected mid-rebuild state) | G1 (dual-mapped) = 0, G2 (HUMAN+LLM coexistence) = 0, G4 (cross-category — all mapped `taxonomy_id`s fall inside either the `186352–188351` or `190643–190842` claimed blocks) = 0, G5 (provenance: `meta_agent`/`source` both set) = 0. All gates pass. Total `product_taxonomy_map` rows for this category: 201 (all `source='LLM'`, all `meta_agent='CLAUDE_CODE'`) |

| 2026-07-28 07:28 UTC | Automated review session (auto-discovery) | STEP 1 live count check confirmed the Brief's stated numbers (LLM=201, HUMAN=0) are current — no drift. Verified the session prompt's 'mixes Shopee/Tiktok' premise does not apply to this specific table (confirmed 100% ecommerce_platform='Tiktok', country='SG', matching the category doc, not the generic prompt template — consistent with this category's prior documented pattern of prompt-template/table mismatches). Executed the Brief's two named work items: (1) Sourcesage Club catalog (33 entries, BRD-SG-14499) — image-verified 6 products spanning distinct animal parts (Ostrich Long Tendon, Beef Weasand, Ostrich Foot/Meaty/Spaghetti/Tidbits Tendon) against the seller's own branded packaging infographics; every product_line, size, and pack_count already matches exactly what's printed on-package. (2) The 6 named catch-all brands' (Wanpy, FREZ, Food For The Good, Absolute Holistic/Bites, Pawlicious, OMAKASE) 21 is_multi_variant/is_multi_size entries — checked structurally for ALL 21 (not a sample): every taxonomy_id maps to exactly 1 product_id, so the shared-bucket defect pattern from the sibling shopee_sg_pet_food category (multiple distinct products merged onto one entry, losing a per-product size) does not reproduce in this category's build. Image-verified 5 of the 21 (2x Food For The Good, 2x OMAKASE) and confirmed each is a genuine seller-side 'mix & match / pick any flavor' bundle or selector listing — the generic product_line + is_multi_variant=TRUE modeling is accurate, not a lazy stub. Separately, STEP 1B's '[FAIL] canonical_name fields: 3' gate was traced to 3 specific rows: SKU-186511 (Happi Skippi) and SKU-186527 (SoulMate) both have size populated simultaneously with is_multi_size=TRUE (a genuine field-consistency defect), and SKU-190645 (小七妈妈) has a product_line not reflected in canonical_name. None of these 3 fall within the Brief's named scope (Sourcesage Club / the 6 catch-all brands). | No product_taxonomy or product_taxonomy_map writes were made — every entry examined within the Brief's actual named scope was already correct. Claimed a 200-slot SKU block (SKU-193142–SKU-193341, scenario custom_targeted_qa_fix) per STEP 2 as instructed, but left it entirely unused since no corrections were required; it remains ACTIVE and reusable for a future session, consistent with this category's established precedent for unused claimed blocks. The 3 canonical_name-field defects found outside the Brief's scope (SKU-186511, SKU-186527, SKU-190645) were deliberately left untouched per this session's scope boundary and are flagged below for a future targeted session. No universe refresh was run (nothing changed to refresh). |
---

## Targeted QA Fix Brief

> Scope for a future `targeted_qa_fix.sh` / NULL-coverage session — not executed this session.

**Verdict:** D6 in-scope NULL coverage is minimal (2 OOS products, $4,465.41 combined — correctly excluded;
6 genuinely brand-unreadable products, $531.19 combined — correctly UNRESOLVED) — no urgent coverage gap.
A D1/D2 precision pass would
sharpen the Sourcesage Club catalog (33 entries with no image verification beyond spot-checks) and the
generic multi-variant/multi-size catch-alls (Wanpy, FREZ, Food For The Good, Absolute Holistic/Bites,
Pawlicious, OMAKASE — ~15 entries where a single flavor/size selector listing was routed to one
catch-all entry rather than per-flavor image verification). No cross-category collision risk identified
this session (no sibling `makanankucing_sg` category exists yet to collide with, unlike the MY pair).

---

## Map Row Counts (as of last run)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 201 | 198 Full Rebuild (first run) + 3 top-up (2026-07-28) |
| HUMAN | 0 | No prior keyword seed for this table |
| NULL (unmapped) | 8 in-scope (of 209 worklist) + 476 below the 95%-cumulative-GMV threshold | 2 OOS (Pawllergy Test Kit, Health+ Orofill Revive) + 6 genuinely brand-unreadable (Sniff Sniff SG). Below-threshold long tail not evaluated this session per Rule A/B scope (`docs/quality-standards.md` §2) |
