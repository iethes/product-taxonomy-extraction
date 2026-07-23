# makanankucing_my — Category Context

> Custom (non-NIQ) source: `sincere-hearth-273704.makanankucing.9_makanankucing_my_daily`
> (Shopee Malaysia, daily grain summed to monthly). Not a `master_clean_niq` table — different
> schema, no `model_id`/`month`/`merchant_badge`-driven official-store data in the form other
> categories rely on. Taxonomy state is keyed under `master_table = 'makanankucing_my'`, not the
> source table name.

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass | ✅ Complete (Full Rebuild, first run) |
| GMV Coverage | 86.4% of in-scope worklist GMV mapped (41.55M / 48.08M MYR) |
| Last run | 2026-07-23 |
| Current MAX taxonomy_id (this category) | SKU-147139 |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-145586–SKU-147585 | Claimed block (2,000 slots, `sku_block_registry`, scenario `custom_full_rebuild`) |
| SKU-145586–SKU-147139 | Actually used (1,554 taxonomy entries) — 435 slots left unused in the block |

## Brand IDs Assigned

| Range | Usage |
|-------|-------|
| BRD-MY-01070–BRD-MY-01127 | 58 new local/house brands minted this session |

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

---

## Targeted QA Fix Brief

> Scope for a future `targeted_qa_fix.sh` / NULL-coverage session — not executed this session.

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

## Map Row Counts (as of this session)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 1,832 | This session, Full Rebuild first run |
| HUMAN | 0 | No prior keyword-seed pass for this category |
| NULL (unmapped, in-scope) | 458 | 334 brand-unresolved + 124 size-ambiguous — see Targeted QA Fix Brief |
| NULL (out-of-scope, correctly excluded) | 237 | Dog food / litter / flea treatment / non-pet items |
