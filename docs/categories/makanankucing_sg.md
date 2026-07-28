# makanankucing_sg — Category Context

> Custom (non-NIQ) source: `sincere-hearth-273704.makanankucing.9_makanankucing_sg_daily`
> (**TikTok Shop Singapore**, daily grain summed to monthly — not Shopee, despite the naming
> convention shared with the `makanankucing_my`/`makanananjing_my` precedent categories, which
> *are* Shopee-sourced). Not a `master_clean_niq` table — different schema, no
> `model_id`/`month`/`merchant_badge`-driven official-store data in the form other categories rely
> on. Taxonomy state is keyed under `master_table = 'makanankucing_sg'`, not the source table name.
> Raw `ecommerce_platform` column value is `'Tiktok'`; normalized to the documented canonical
> `'TikTok Shop'` in `product_taxonomy_map.platform` (no live collision risk confirmed —
> `universe_taxonomy_overlay` had zero pre-existing rows for any `makanan*` table before this
> session, and its only other platform value in use is `'Shopee'`).

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass | ✅ Complete (Full Rebuild, first run) — single pass, no official-store tier exists for TikTok Shop (`merchant_badge` is uniformly `'Tiktok Shop'` for all 871 SG products, confirmed live — no Mall-equivalent signal) |
| GMV Coverage | 95.88% of the top-95%-cumulative-GMV (GWP-zeroed) in-scope worklist (234/246 products); 234/871 of all SG products in the source table |
| Last run | 2026-07-28 (this session) |
| Current MAX taxonomy_id (this category) | SKU-188540 |
| SKU block this category has claimed | SKU-188352–SKU-190351 (2,000 slots, `sku_block_registry`, scenario `custom_full_rebuild`) |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-188352–SKU-190351 | Claimed block (2,000 slots) |
| SKU-188352–SKU-188540 | Actually used (189 taxonomy entries) — 1,811 slots left unused in the block |

---

## Brand Scope (GMV threshold 95%, in-scope worklist)

62 distinct brands mapped (58 reused from the existing global `brand_dict`, 4 newly minted as
`BRD-SG-*`). Top 15 by GMV:

1. **Aatas Cat** — `BRD-SG-00561` — 45.7K SGD
2. **Royal Canin** — `BRD-GLOBAL-00001` — 34.4K SGD
3. **Ciao** — `BRD-SG-00024` — 25.2K SGD
4. **Daily Delight** — `BRD-SG-00664` — 22.2K SGD
5. **Aristo-Cats** — `BRD-SG-00563` — 22.1K SGD
6. **Sumo Cat** — `BRD-SG-01278` — 10.5K SGD
7. **Uncle Tails** — `BRD-MY-01124` — 6.7K SGD
8. **Happi Skippi** — `BRD-SG-01937` — 6.1K SGD
9. **Fancy Feast** — `BRD-SG-00713` — 5.6K SGD
10. **Kit Cat** — `BRD-SG-00588` — 4.7K SGD
11. **Loveabowl** — `BRD-SG-01072` — 4.3K SGD
12. **NurturePro** — `BRD-MY-01029` — 4.1K SGD
13. **Catsmart** — `BRD-SG-14506` (new) — 3.1K SGD
14. **SAVA** — `BRD-SG-02059` — 2.6K SGD
15. **FAENBEI** — `BRD-SG-05598` — 2.2K SGD

Remaining 47 brands (each < 2.1K SGD in-scope GMV): Top Ration, Friskies, Absolute Bites, Ziwi Peak,
Vitachat (new), Bitacat (new), Sparkles (new), Purina ONE, IQ Cat, Taste Of The Wild, Wellness CORE,
Boneve, SmartHeart, Farmina, Food For The Good, Holuah!, Whiskas, D'Zahara, Reflex, BelliFull, Fussie
Cat, Sheba, Felix, Angel, Rich Choice, Zealandia, Absolute Holistic, Urbanwolf, Schesir, babyKET,
Snappy Tom, Instinct, Nutripe, Solid Gold, Furvit, Petag, Wanpy, Unicharm, Singapaw, Meow Meow, LDECO,
Vitakraft, Aixia, Platinum Choice, Amelisa, Prof. Bengal, Ishtar.

**New brands minted this session** (verified against the *global* `brand_dict` first — all four had
zero matches under any spelling/casing before minting; MAX+1 computed inside a single
`INSERT...SELECT` to avoid the read-then-write collision documented in `makanankucing_my.md`, and a
parallel session did in fact claim the immediately-preceding ID range in the few minutes between
research and insert, confirmed via `COUNT(*) = COUNT(DISTINCT brand_id)` post-insert):

| Brand | brand_id | Notes |
|-------|----------|-------|
| Catsmart | `BRD-SG-14506` | SG pet retailer's own private-label cat food line (also appears as `merchant_name` `catsmartsg`, but the sku_name itself states "Catsmart"/"CatSmart" as the product brand, not just the seller — a real product brand per §11, not a merchant-name leak) |
| Bitacat | `BRD-SG-14507` | Multivitamin/supplement cat candy brand |
| Sparkles | `BRD-SG-14508` | Halal wet cat food brand (SilverSky-distributed); deliberately NOT merged with the existing unrelated `BRD-GLOBAL-00184` "Sparkle" (singular, no confirmed pet-food association) |
| Vitachat | `BRD-SG-14509` | Soft jelly wet cat food brand |

**Brand consolidation applied during extraction** (spelling/casing variants merged to one existing
`brand_dict` entry, not re-minted): `Aristo Cat`/`Aristo-cats`/`ARISTO-CATS`→`ARISTO-CATS`
(`BRD-SG-00563` — the SG-scoped entry, not the separately-minted `BRD-MY-01076 Aristo Cats` from the
`makanankucing_my` session; same real-world brand has two IDs across markets, a known dedup debt, not
resolved this session); `Dzahara`→`D'Zahara` (`BRD-MY-01089`); `CIAO Churu`→`Ciao` (`BRD-SG-00024`);
`Uncle Tail`/`UNCLE TAIL`→`Uncle Tails` (`BRD-MY-01124`); `Furvite`→`Furvit` (`BRD-MY-01177`);
`NurturePRO`→`NurturePro` (`BRD-MY-01029`, the no-space spelling match — a separate `Nurture Pro`
(`BRD-SG-00801`) also exists in `brand_dict` and was not used); `Farmina N&D`/`N&D`→`Farmina`
(`BRD-SG-00565`, no separate `N&D` entry exists); `PetAg`→`Petag` (`BRD-GLOBAL-00554`); `Prof
Bengal`→`Prof. Bengal` (`BRD-SG-03451`); `Sava`/`Sava Essential(s)`→`SAVA` (`BRD-SG-02059`, distinct
from the unrelated `SAVAS` `BRD-SG-11980`); `Smartheart`→`SmartHeart` (`BRD-GLOBAL-00039` generic —
no products in this worklist referenced the separate `SmartHeart Gold` `BRD-SG-00018`);
`Instinct`→`BRD-GLOBAL-00938` (not the ambiguous `Instinct Pet Food` `BRD-SG-01397`);
`MeowMeow`→`Meow Meow` (`BRD-SG-00113` — deliberately not the unrelated `ME-O`/`Me O`/`Meow`
look-alikes); `Absolute Bites`→`BRD-SG-00740`; `Absolute Holistic`→`BRD-GLOBAL-00902` (two genuinely
distinct Absolute-prefixed brands, not merged with each other).

**Known unresolved duplicate (flagged, not fixed):** `Rich Choice` has two active, identically-named
`brand_dict` entries — `BRD-MY-01046` and `BRD-MY-01113`. This session used `BRD-MY-01046`
(lower/earlier ID) for the one in-scope Rich Choice product; a future session should investigate and
merge.

No official-store allowlist — TikTok Shop has no Mall-equivalent tier (`merchant_badge` is uniformly
`'Tiktok Shop'` for every listing; per `docs/brand-extraction.md` and `ARCHITECTURE.md`, TikTok Pass 1
is always skipped, go directly to Pass-2-style bulk routing). This category went straight to
bulk-first text-matching per `docs/headless-runbook.md`'s Full Rebuild coverage-first mandate.

---

## Scope — What's In vs Out

**In scope:** cat dry food, cat wet food (can/pouch/tray), cat treats (sticks/purees/freeze-dried),
cat supplements (multivitamin candy). The source table's `category_1/2/3` is uniformly
`Pet`/`Pet Food`/`Cat Food` for all 871 SG products — no dog food, litter, or other mislabeled
non-food items were found in this table (unlike the `makanankucing_my` precedent, which required an
explicit dog-food/litter/flea-treatment exclusion list).

**Out of scope (left unmapped, 12 products, ~10.1K SGD GMV in the in-scope worklist):** all 12 are
genuinely brand-unidentifiable from `sku_name` text — no image check could resolve a brand that isn't
stated at all:
- Generic freeze-dried treat listings with no discernible brand (`PetJoy.PJ`/`MomJoy MJ`/`Pet Joy
  Shop` resellers — "Big bucket!!! Pet Food Freeze Dried Treats...", "Top Value!!! Freeze Dried
  Chicken 500g...", "【SG ready stock】Freeze Dried Pet Treats..." ×2) — same "genuinely unbranded
  commodity treat" pattern documented in `makanankucing_my.md`.
- `[New Buyer Only] Yappy Pets Welcome Box for Cat and Dog` — a reseller's own promotional bundle box,
  not a real product brand/line (`Yappy Pets` is the `merchant_name`, not a packaging brand — correctly
  excluded per §11's merchant-name-is-not-a-brand-signal rule).
- `【Combo Sets 】Cat food wet food mixed...` — multi-brand buyer-choice assortment, can't attribute to
  one brand (same rule as documented multi-brand Cola listings elsewhere in this pipeline).
- `NUTRILICK CAT CANDY SUPPLEMENT PROBIOTIC` — plausibly the same product as the (successfully mapped)
  `Furvit`-branded "Nutri Lick" line, but this specific listing's title never states "Furvit"/"Furvite"
  — left unmapped rather than guess.
- Two generic unbranded cat-grass listings and two generic unbranded "cat strip" treat-stick listings.

**Edge cases:**
- Cross-border brand entities: several brands in this SG TikTok worklist (`D'Zahara`, `Uncle Tails`,
  `NurturePro`, `Furvit`, `Urbanwolf`, `Rich Choice`) only had existing `brand_dict` entries under
  `BRD-MY-*` scope from the `makanankucing_my`/`makanananjing_my` sessions. Reused directly rather than
  minting SG-scoped duplicates — same real-world brand sold cross-border on TikTok Shop SG.
- `Aristo-Cats` has two brand entities (`BRD-SG-00563` and `BRD-MY-01076`) for the same real brand —
  see "Known unresolved duplicate" note above (this one wasn't flagged in either precedent doc).

---

## Taxonomy Design Notes

**Extraction method:** bulk regex/text-matching on `sku_name` against a ~62-brand curated keyword
dictionary (longest-pattern-first, Latin tokens word-bounded to avoid the substring-collision class of
bug documented in `makanankucing_my.md`, e.g. a bare `"tom"` alias colliding with unrelated text) — no
merchant/official-store data to seed a Pass 1 the way NIQ tables allow. Size and pack-count extracted
via regex over `sku_name` (kg/g/gm/ml/L units; `x{N}`, `*{N}` and `{N} cans/pouches/sticks` multiplier
patterns; `{N}unit/{M}unit` and `{N}kg/{M}kg` alternation → `is_multi_size`). 5 of the highest-GMV
size-ambiguous listings (all >1K SGD, all Ciao Churu / FAENBEI treat-stick jars) were verified directly
against the product image (`curl` + `Read`, converting the source's native WebP to PNG via Pillow since
this environment has no `dwebp`/ImageMagick) — confirmed 14g×50 for four Ciao Churu jar listings and
15g×60 for the FAENBEI stick box.

**Regex gotchas found and fixed this session** (noted here in case a future session hand-rolls similar
regex against this or another TikTok-sourced table):
- **Size-vs-pack ambiguity around a bare `x`**: `"24 cans x 80g"` initially mis-parsed as `pack_count=80`
  or `pack_count=8` — the naive `[x×]\s*(\d+)` pattern greedily matched the *size* half of a
  `"{count} cans x {size}"` phrase, and Python's `\d+` backtracking against a negative-lookahead unit
  check silently truncated `"80"` down to `"8"` to satisfy the lookahead at a shorter match. Fixed by
  switching to a manual `re.finditer` scan that takes each *full* digit run following `x`/`×`/`*` and
  only rejects it if that exact (non-truncated) run is immediately followed by a unit word — a single
  regex with a lookahead was not reliable here regardless of anchoring, because `\b` after `\d+` doesn't
  fire between adjacent digits.
- **`x` with a space before the count** (`"x 50"`, not `"x50"`) was missed entirely by an earlier
  version of the pack regex that required the digits to immediately follow `x` with no gap — silently
  defaulted several genuine 50-stick jars to `pack_count=1` until fixed.
- **`*` as a multiplier separator** (`"70g*24"`, `"15g*60Pcs"`) is used interchangeably with `x` in this
  source's listings — not handled by the original `x`-only pattern.
- **No-space unit-then-multiplier runs** (`"85gx12pouch"`): the naive `\b` word-boundary check after a
  unit fails here since `g` and `x` are both word characters with no boundary between them — same class
  of gotcha `makanankucing_my.md` documented for `"80gx24pouch"`.

**Variant/flavor collapse risk (caught before finalizing, not after):** the first grouping pass keyed
taxonomy entries by `(brand_id, size, pack_count)` alone, which silently merged genuinely distinct named
product lines sharing the same size/pack into one entry — e.g. all 7 different Aatas Cat 80g×24 flavor
lines (Tantalizing Tuna, Creamy Chicken, Finest Soul Superfoods, Complete Care, Finest Daily Defence...)
collapsed into one `"Aatas Cat 80g x24"` stub, and similarly for Aristo-Cats' 6 "Premium Plus {X}
Series" lines and Royal Canin's many named care lines (Hair & Skin, Indoor27, Urinary S/O vs Urinary
Care, Fit 32, Hairball Care, Maincoone, British Shorthair). This is exactly the D3 variant-collapse
defect class documented elsewhere in this pipeline (e.g. th_softdrink's Pepsi Zero Sugar silently
falling back to Pepsi Cola) — caught by manually reading every multi-product group's underlying
`sku_name`s before generating DML, not by an automated check. Re-grouped with an explicit per-product
line override for all 35 raw groups that had more than one underlying product, splitting them into the
correct number of distinct taxonomy entries by their actual on-label line name. Genuinely-identical
listings (same brand/size/pack, no distinguishing line text — e.g. 3 reseller listings of "Sumo Cat
Premium Can Food 80g x24" with only cosmetic title differences) were correctly kept merged.

**product_line vs variant split:** where `sku_name` yields a real on-label formula/line name (e.g. Royal
Canin's `Hair & Skin Care`, `Indoor27`, `Fit 32`; Aristo-Cats' `Premium Plus {X} Series`; Kit Cat's
`Deboned Food Topper`, `Petite Pouch`), that text is written to `product_line`. Where the only
differentiating text is a flavor/ingredient descriptor (e.g. `Chicken & Tuna Broth`, `Tantalizing Tuna`,
`Soft Jelly Cup Tuna Flake`) with no named formula, that text is written to `variant` instead and
`product_line` left NULL, per the food-keyword heuristic used in the `makanankucing_my` precedent.
Structured-fields-NULL rate (both fields NULL, brand+size+pack only): 26% of non-multi-size entries —
under the 50% QA-gate fail threshold, and expected for single-line brands like Sumo Cat and generic
"Royal Canin 2kg dry food" reseller listings with no line stated at all.

**Multi-size / ambiguous-bundle handling:** buyer-choice size ranges (`"2kg/4kg/10kg"`,
`"1.5kg | 3.5kg | 7kg"`) and pack-count ranges (`"Bundle of 12/24"`) get `is_multi_size=TRUE, size=NULL`
with a real descriptive name — never the banned "Multiple Sizes"/"Multiple Variants" text (checked
against every entry's `canonical_name` via the placeholder-leak gate regex before writing: 0 hits).
Genuinely ambiguous multi-line bundles (e.g. `"Royal Canin Cat Dry Food (Hair & Skin, Digestive,
Hairball, Urinary)"`, `"Rich Choice HOLISTIC CHEEK BOOSTER/OVEN-BAKED LARGE BREED/GASTROINTESTINAL
CARE"` — buyer picks one of several named lines in one SKU) got a distinct `"{Brand} Assorted Care
Lines"`-style catch-all rather than being force-fit into any one of the named lines.

**Known coverage gap (flagged for a future top-up/`targeted_qa_fix.sh` pass, not fixed this session):**
12 products (~10.1K SGD in-scope GMV) — brand not identifiable from `sku_name` text alone, all
low-signal generic freeze-dried-treat/merch/combo listings. Left `taxonomy_id IS NULL`. See Scope
section above for the full breakdown.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-28 | Pre-flight | STEP 1 re-verification: `SELECT source, COUNT(*) ... WHERE master_table='makanankucing_sg'` returned 0 rows — genuine first run, matching the wrapper's pre-check | Proceeded per Full Rebuild scenario |
| 2026-07-28 | Pre-flight | Source table's real `ecommerce_platform`/`country` columns (needed for the `product_taxonomy_map` composite key) are absent from the prompt's STEP 0 query — live schema check found the source is 100% TikTok Shop (871 SG products + 1 stray MY product from an earlier month, excluded via explicit `country='SG'` filter), not Shopee like the `makanankucing_my`/`makanananjing_my` naming-convention precedent | Normalized raw `'Tiktok'` → documented canonical `'TikTok Shop'`; confirmed zero collision risk against `universe_taxonomy_overlay` (which has no rows for any `makanan*` table and only uses `'Shopee'` elsewhere) before deciding, per an advisor consult |
| 2026-07-28 | Full Rebuild | Regex bugs in initial pack-count extraction (space-before-`x`, `*`-as-multiplier, size-vs-pack ambiguity around `"N cans x Sg"` phrasing, backtracking truncation of a lookahead-guarded `\d+`) — see Taxonomy Design Notes | Fixed all four before generating any DML; re-ran extraction from scratch each time and re-verified against known test strings |
| 2026-07-28 | Full Rebuild | Variant/flavor collapse: naive `(brand_id, size, pack_count)` grouping merged 35 groups of genuinely distinct named product lines into single stub entries (see Taxonomy Design Notes) — caught by manually reading every multi-product group's underlying `sku_name`s before writing, not by an automated check | Re-grouped with explicit per-product line overrides; re-verified 0 placeholder-leak hits and spot-checked the top 40 entries by GMV after the fix |
| 2026-07-28 | Full Rebuild | 5 highest-GMV size-ambiguous listings (Ciao Churu Festive Pack ×2, Ciao Churu 50-stick jars ×2, FAENBEI 60pcs box) image-verified via `curl`+Pillow-converted-PNG+`Read` | Confirmed 14g×50 (Ciao Churu) and 15g×60 (FAENBEI); applied as overrides |
| 2026-07-28 | Full Rebuild | Bulk global `brand_dict` dedup check (single UNNEST-joined query against all ~62 candidate brand names, normalized) before minting anything — found 58 of 62 candidates already existed (including several only under `BRD-MY-*` scope from the `makanankucing_my`/`makanananjing_my` sessions); only 4 genuinely new (Catsmart, Bitacat, Sparkles, Vitachat) | Reused 58 existing `brand_id`s; minted the 4 new ones in a single `INSERT...SELECT` computing `MAX+1` inside the statement (not read-then-write) — a parallel session claimed the immediately-preceding ID range in the few minutes between planning and insert, confirmed via `COUNT(*) = COUNT(DISTINCT brand_id)` post-insert, no collision |
| 2026-07-28 | Full Rebuild | Claimed SKU block `SKU-188352`–`SKU-190351` (2,000 slots) — re-verified live `MAX(block_end)` immediately before claiming (moved from 186351 to 188351 between the first check and the claim, confirming a parallel session was active) | Used `SKU-188352`–`SKU-188540` (189 of 2,000 slots), 1,811 unused |
| 2026-07-28 | Full Rebuild | Self-check QA gates (G1 dual-mapped [LLM-scoped], G2 HUMAN+LLM coexistence, G5 provenance, placeholder-leak, structured-fields-NULL%) run per `docs/headless-runbook.md`'s QA-gate-as-code, scoped to `master_table='makanankucing_sg'` | All passed: 0 dual-mapped, 0 HUMAN+LLM coexistence (no HUMAN rows exist for this category), 0 provenance gaps, 0 placeholder-leak canonical names, 26% NULL product_line among non-multi-size entries (well under the 50% fail threshold) |
| 2026-07-28 | Full Rebuild | GMV coverage: 234/246 (95.88% of in-scope GMV) of the top-95%-cumulative-GMV worklist mapped; 234/871 of all SG products in the source table | 12 remaining in-scope products (~10.1K SGD) are genuinely brand-unidentifiable — flagged for a future top-up pass |

---

## Targeted QA Fix Brief

> Scope for a future `targeted_qa_fix.sh` / top-up session — not executed this session.

**Verdict:** D6 in-scope NULL coverage gap (small) + two flagged data-quality items needing human
judgment, not extraction work.

- **Coverage gap** (12 products, ~10.1K SGD GMV): all genuinely brand-unidentifiable from text; see
  Scope section for the full list. Not candidates for image-based resolution — the brand text simply
  isn't in the sku_name for these, and several are explicitly multi-brand assortments.
- **`Rich Choice` brand_dict duplicate**: `BRD-MY-01046` and `BRD-MY-01113` are both active,
  identically-named entries. Needs a merge decision (which ID is canonical, re-point any dependent
  rows) — out of scope for a taxonomy-extraction session to resolve unilaterally.
- **`Aristo-Cats` cross-market brand duplicate**: `BRD-SG-00563` (used by this category) and
  `BRD-MY-01076` (used by `makanankucing_my`) are almost certainly the same real-world brand. Same
  merge-decision caveat as above.
- **Below-661-GMV long tail products not yet reviewed for line-name noise**: a handful of low-GMV
  entries (e.g. `Furvit Cat Candy Nutri Lick 5g s 5g x40`, `Amelisa Rawly Stick... 16g 16g...`, `Sheba
  Melty Moochie Puree Puree Treats`) retain minor regex-stripping artifacts (duplicate tokens, a stray
  trailing `s`) — cosmetic, don't trip the placeholder-leak gate, but a precision pass could clean them
  up.

---

## Scripts

No committed pipeline scripts for this category — extraction was done directly (multimodal reading +
ad hoc SQL/Python, not a `pipeline/05_product_taxonomy/llm_{table}/` script) per this session's brief
for this custom, non-NIQ source table.

---

## Map Row Counts (as of this session)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 234 | Full Rebuild, first run — 229 bulk text-matched, 5 image-verified |
| HUMAN | 0 | No prior keyword-seed pass for this category |
| NULL (unmapped, in-scope, live-worklist gap) | 12 (~10.1K SGD) | Genuinely brand-unidentifiable from text — see Scope section |
| NULL (out-of-scope / below 95% GMV threshold) | 625 | Long-tail resellers below the GMV cutoff — may legitimately remain unresolved per `docs/quality-standards.md` §2 |
