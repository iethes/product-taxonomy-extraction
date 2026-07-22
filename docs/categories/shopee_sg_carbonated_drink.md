# shopee_sg_carbonated_drink — Category Context

> First-run Full Rebuild, generated headlessly 2026-07-22. No prior LLM pass exists for this table.

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete |
| LLM Pass 2 | ✅ Complete |
| GMV Coverage | 95.05% (2026-06, after 2026-07-22 top-up) |
| Last run | 2026-07-22 (top-up coverage session) |
| Current MAX taxonomy_id | Query BQ live before every write — do not trust any number in this file |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-110406–112405 | Claimed block (2000 slots, full_rebuild), `sku_block_registry` status COMPLETE |
| SKU-110406–110490 | Pass 1 OFFICIAL (85 entries, 8 brands via 4 store fronts, 86 products mapped) |
| SKU-110491–110728 | Pass 2 RESELLER (238 new entries; 92 products reused a Pass-1 entry; 398 products mapped total) |
| SKU-110729–112405 | Unused remainder of claimed block |
| SKU-116806–117005 | Claimed block (200 slots, taxonomy_topup, 2026-07-22), `sku_block_registry` status ACTIVE |
| SKU-116806–116824 | Top-up coverage session: 19 new entries minted; 174 slots (116825-117005) unused remainder |

---

## Scorecard (2026-07-22, first Full Rebuild)

```
In-scope products: 495 (Rule A top-95% GMV: 440 · Rule B official-store: 88)
GMV coverage (all products, 2026-06): 94.4% (884 / 4,260 products mapped)

QUALITY (GMV-weighted, LLM entries)          GATES (post HUMAN-dedup delete)
  D1 Tier-A completeness ... 97.7%           G1 dual-mapped ........ 0  ✅
  D4 NULL size ............. 0.0%            G2 HUMAN+LLM coexist .. 0  ✅
  D2 NULL product_line ..... 0.0%            G5 provenance ......... 0  ✅
                                              placeholder-leak (LLM only) . 0  ✅

Map rows: LLM 484 (86 Pass1 + 398 Pass2) · HUMAN 403 (untouched long-tail, no LLM row exists) ·
355 duplicate HUMAN rows deleted post-QA (superseded by LLM row for same product)

D6 in-scope NULL coverage: 11 remaining, all legitimately excluded —
  6 genuine alcoholic beer (Heineken, Tiger, Hite, Wusu — real beer, out of scope per category Scope section)
  2 multi-brand buyer-choice assortments (different actual brands in one listing, can't determine what buyer receives)
  2 "[Not For Sale]" listings (not genuinely purchasable, 0 GMV)
  1 unbranded "Taiwan Root Beer Vegan Drink" (no identifiable brand entity, GMV 149.4)
```

**Decision: SHIP.** All gates pass, D1 Tier-A 97.7% ≥ 90% target, D4/D2 both 0% NULL (target ≥95%
size coverage exceeded). No universe refresh run this session (out of scope for this prompt —
next session should run the `universe_taxonomy_overlay` MERGE per docs/headless-runbook.md).

---

## Brand Scope (GMV threshold 95%, month 2026-06, GWP-zeroed)

Computed via canonical `brand_id` (product_brand_map → brand_dict), not raw `brand` text field —
raw text fragments the same brand across casing variants (e.g. would double-count "7-up"/"7UP").
GWP-flagged GMV zeroed per Decision 15 before ranking. **40 brands** cross the 95% cumulative
threshold (real threshold — NOT a fixed top-15/20 snapshot).

Category total GMV (GWP-zeroed, 2026-06): ~S$599,700 across 101 distinct brand_ids (including
`BRD-UNDEFINED`).

1. **Coca-Cola** — `BRD-GLOBAL-00145` — S$269,200.42 (44.9% cum)
2. **schweppes** — `BRD-TH-00294` — S$44,204.73 (52.3% cum)
3. **Undefined** — `BRD-UNDEFINED` — S$24,982.91 (56.4% cum) — no brand text resolved at Stage 03; still in-scope by product-level GMV, no official store possible
4. **Chang** — `BRD-SG-00647` — S$20,713.63 (59.9% cum) — soda water brand; Chang also makes beer, see Scope exclusions
5. **Chi Forest** — `BRD-GLOBAL-01226` — S$17,974.21 (62.9% cum)
6. **F&N** — `BRD-GLOBAL-00345` — S$17,271.74 (65.8% cum)
7. **Sprite** — `BRD-GLOBAL-00812` — S$16,970.92 (68.6% cum)
8. **Pepsi** — `BRD-GLOBAL-00268` — S$16,874.64 (71.4% cum)
9. **Ice Mountain** — `BRD-SG-00872` — S$10,412.68 (73.2% cum)
10. **Singha** — `BRD-GLOBAL-00047` — S$9,566.03 (74.8% cum) — soda water brand; Singha also makes beer, see Scope exclusions
11. **Bundaberg** — `BRD-GLOBAL-01726` — S$8,282.87 (76.1% cum)
12. **Fanta** — `BRD-GLOBAL-00523` — S$7,764.16 (77.4% cum)
13. **POKKA** — `BRD-GLOBAL-00722` — S$7,058.31 (78.6% cum)
14. **Vida** — `BRD-GLOBAL-00850` — S$6,892.35 (79.8% cum)
15. **Hivetown** — `BRD-SG-05068` — S$6,769.03 (80.9% cum)
16. **Remedy** — `BRD-SG-02775` — S$6,373.02 (82.0% cum)
17. **7-up** — `BRD-GLOBAL-01646` — S$5,533.70 (82.9% cum)
18. **LOTTE** — `BRD-GLOBAL-01727` — S$5,343.64 (83.8% cum)
19. **AW** (A&W) — `BRD-TH-01451` — S$5,209.58 (84.6% cum) — note: duplicate brand_id `BRD-GLOBAL-01343` "A&W" also exists far down the tail (99.77% cum, S$111.90) — same real brand, unmerged brand_dict entry; map products to whichever taxonomy makes sense, do not require brand_id agreement (per llm-extraction-rules.md §9 Thai-brand precedent / brand-extraction.md)
20. **Monster Energy** — `BRD-SG-01206` — S$4,592.48 (85.4% cum)
21. **San Pellegrino** — `BRD-GLOBAL-00862` — S$4,087.86 (86.1% cum)
22. **Fever-tree** — `BRD-SG-02482` — S$4,008.76 (86.8% cum)
23. **Qoo** — `BRD-SG-02511` — S$3,957.28 (87.4% cum)
24. **KICKAPOO** — `BRD-TH-01777` — S$3,730.60 (88.0% cum)
25. **Nipis Madu** — `BRD-SG-02516` — S$3,611.22 (88.6% cum)
26. **J&J** — `BRD-TH-01226` — S$3,600.28 (89.2% cum)
27. **Yeo's** — `BRD-TH-02505` — S$3,583.91 (89.8% cum)
28. **Asina** — `BRD-SG-02867` — S$3,194.40 (90.4% cum)
29. **Dr Pepper** — `BRD-SG-02976` — S$3,032.70 (90.9% cum)
30. **Mountain Dew** — `BRD-GLOBAL-02156` — S$2,932.96 (91.4% cum)
31. **Perrier** — `BRD-GLOBAL-01102` — S$2,921.30 (91.9% cum)
32. **Orangina** — `BRD-TH-00904` — S$2,526.30 (92.3% cum)
33. **Cloop** — `BRD-GLOBAL-02399` — S$2,481.06 (92.7% cum)
34. **100PLUS** — `BRD-TH-00610` — S$2,450.39 (93.1% cum)
35. **ANGLIA** — `BRD-SG-01681` — S$2,353.54 (93.5% cum)
36. **SaltCola** — `BRD-SG-03488` — S$2,182.60 (93.9% cum)
37. **Kang Shi Fu** — `BRD-SG-03084` — S$2,106.80 (94.2% cum)
38. **sodastream** — `BRD-SG-03892` — S$1,865.20 (94.5% cum)
39. **MUG** — `BRD-SG-05201` — S$1,658.90 (94.8% cum)
40. **"Soda"** — `BRD-SG-05429` — S$1,646.68 (95.07% cum) — **data-quality artifact, not a real brand**: PRODUCT_NAME_SCAN mis-bucketed the generic word "soda" as a brand token. Products under this brand_id are actually DAYAO, Fruit.B, gutc, and other unrelated small brands. No official store possible. Route each product in Pass 2 to its real brand read from image/sku_name, not to a "Soda" taxonomy entry.

Brands excluded from scope (below 95% cumulative tail, from 95.34% cum onward): Ribena, Monarch,
Rock Mountain, F&N Seasons, Authentic Tea House, Red Bull, Kuwwe, Apple, Mayora, Haus Boom,
LaCroix, Suntory, Da Yao, evian, DONGA OTSUKA, Curated Culture, ICE PEAK, Dash, Canada Dry,
Laoshan, Somersby, Lo Bros Kombucha, Vitabee, Vitami, Evervess, Ice Cool, Asa-Hi, Barbican,
Oceanic, C&C, Three Legs Brand, Kai Beverage, Heineken (also OOS as beer regardless of GMV — see
Scope), Genki Forest, Spritzer, Famous Soda Co, Palestine Drinks, Franklin & Sons, Hey Song,
Salaam Cola, "12/+＝" (likely a garbled/watermark brand read, per llm-extraction-rules.md §11 —
do not resolve any product's brand from this string), Karma Drinks, Remedy Organic, Old Jamaica,
Sangaria, Arctic Ocean, Jonetsu Kakaku, Mirinda, LOTTE Chilsung Beverage (dup of LOTTE),
Alchemy & Tonic, Haus Brew, honeyB, Schweppes (dup of schweppes, `BRD-SG-01179`, S$142.76 —
unmerged brand_dict duplicate), Ante, The Tapping Tapir, ZERO, Kirei, Hakutsuru, Lemon, A&W
(dup, `BRD-GLOBAL-01343`), and the remaining long tail. These may still be routed via bulk
text-matching in Pass 2 if they clearly match an existing taxonomy entry's brand, but are not
required reading for Pass 1/2 completeness the way the 40 in-scope brands are.

---

## Official Store Allowlist (Pass 1)

Built by querying distinct `merchant_name WHERE merchant_badge='Shopee Mall'` for the 40 in-scope
`brand_id`s above, then excluding multi-brand retailers/distributors (none of the Beauty/Grocery-TH/
Pet exclusion-list names from llm-extraction-rules.md §4 apply directly to SG F&B — this is a
fresh per-brand determination for this vertical).

| Brand(s) covered | brand_id | Official Store Merchant Name | Distinct products | GMV (GWP-zeroed) |
|-------------------|----------|-------------------------------|---|---|
| Coca-Cola, Fanta, Sprite, schweppes, AW | `BRD-GLOBAL-00145` + owned/licensed brands | `Coca-Cola` | 43 | S$41,882.30 |
| Chi Forest | `BRD-GLOBAL-01226` | `Chi Forest Official Store` | 15 | S$15,862.10 |
| LOTTE | `BRD-GLOBAL-01727` | `lotteofficial` | 27 | S$4,641.70 |
| sodastream | `BRD-SG-03892` | `SodaStream Singapore Official Store` | 3 | S$1,865.20 |

**Parent-company store note:** `Coca-Cola` merchant_name is The Coca-Cola Company's own Shopee
Mall store. It also lists Fanta, Sprite, Schweppes, and A&W products (all owned or bottled/licensed
by Coca-Cola in various markets) — per CLAUDE.md's parent-company-store guidance this is
Pass-1-eligible for all of those brands, not excluded as multi-brand. Every product read from this
store must still have its `brand_from_image` extracted per-product (it will legitimately vary
across Coca-Cola/Fanta/Sprite/Schweppes/A&W within this one store).

**Multi-brand stores excluded (NOT in allowlist, despite carrying in-scope-brand products):**
- `Prestigio Delights Official` — carries 100PLUS, Bundaberg, Coca-Cola products; a multi-brand F&B distributor's own store, not any single brand's official channel
- `RedMan Official Store` — carries Coca-Cola, Sprite, Undefined-brand products; multi-brand distributor
- `DON DON DONKI Official Store` — Japanese multi-category discount retail chain
- `Choco Express Official Store` — carries Dr Pepper, Fanta, Pepsi products; multi-brand distributor
- `K-Market by Koryo Trading` — carries LOTTE products; reads as a general Korean-grocery importer/mart, not LOTTE's own channel
- `SnackFirst Official Store` — carries Remedy products; multi-brand snack/beverage retailer
- `Delyco Official Store` — carries schweppes products; multi-brand F&B distributor

**Brands with no official store (Pass 2 only):** all remaining 36 of the 40 in-scope brands —
Undefined, Chang, F&N, Pepsi, Ice Mountain, Singha, Bundaberg, Fanta (also partially covered via
Coca-Cola store), POKKA, Vida, Hivetown, Remedy, 7-up, AW (also partially covered via Coca-Cola
store), Monster Energy, San Pellegrino, Fever-tree, Qoo, KICKAPOO, Nipis Madu, J&J, Yeo's, Asina,
Dr Pepper, Mountain Dew, Perrier, Orangina, Cloop, 100PLUS, ANGLIA, SaltCola, Kang Shi Fu,
sodastream (also has own store), MUG, "Soda" (not a real brand — see above).

---

## Scope — What's In vs Out

**In scope:**
- Carbonated soft drinks (cola, lemon-lime, fruit-flavored soda)
- Sparkling/soda water, tonic water, mixers (plain and flavored)
- Craft/artisanal soda, kombucha-style carbonated drinks, energy drinks that are carbonated
- Ready-to-drink carbonated functional beverages (e.g. sparkling honey drinks, probiotic soda)

**Out of scope (leave NULL):**
- **Alcoholic beer/lager**, even from brands that also sell soda water under the same name —
  e.g. Chang and Singha both sell soda water (in scope) AND beer (out of scope) in this table;
  Heineken and Tiger appear almost exclusively as beer (out of scope). Judge per-product from
  sku_name/image ("Soda Water" vs "Lager Beer" / "Beer"), not by brand alone.
- Soda-making equipment/machines (e.g. "gagasoda Household... Soda Machine") — appliance, not a beverage
- Non-carbonated juices, still water, sports/ion drinks (e.g. Pocari-style) mis-tagged into this table
- Garbled/unreadable listings where no real product can be identified (e.g. brand text `"12/+＝"`)

**Edge cases:**
- **"Soda" brand_id (`BRD-SG-05429`)**: not a real brand — a PRODUCT_NAME_SCAN false-positive
  bucket for the generic word "soda". Route each product to its real brand (read from
  sku_name/image), never create a taxonomy entry under a "Soda" brand.
- **Chang / Singha**: dual-purpose brands (soda water + beer) in this source table. Only soda
  water products are in scope.
- **A&W duplicate brand_ids** (`BRD-TH-01451` "AW" and `BRD-GLOBAL-01343` "A&W"): same real
  brand, unmerged in brand_dict. Map to whichever taxonomy entry is correct; taxonomy mapping
  does not require brand_id agreement with product_brand_map.
- **Schweppes duplicate brand_ids** (`BRD-TH-00294` "schweppes" and `BRD-SG-01179` "Schweppes"):
  same situation as A&W above.

---

## Taxonomy Design Notes

**Product line extraction approach:**
- Coca-Cola company products (Coca-Cola, Coke Zero, Coke Light, Fanta, Sprite, Schweppes): use the
  real on-label variant name (e.g. "Zero Sugar", "Original Taste - Less Sugar", "Classic", "Light")
  as product_line/variant — never a bare generic "Cola"/"Soda".
- Chang / Singha soda water: product_line should reflect flavor where stated (e.g. "Soda Water",
  "Soda Water Lemon Flavour", "Fresh Lime") — do not collapse flavors into one entry (D3).
- Bulk carton/case deals are extremely common in this category ("24 x 320ml", "12 x 1.5L",
  "TRIO CARTON DEAL 72 x 325ml") — pack_count extraction is high-stakes here; always resolve via
  §1's priority chain (text → image → spec → description), watch for nested multipliers
  ("[Bundle of 1Cartons]" style bundle-of-N-cartons wording = N × per-carton count).

**Size extraction notes:**
- Primary units: ml (320ml, 325ml, 1.5L cans/bottles), L for large format.
- Common sizes seen: 320ml, 325ml (glass bottle, common for Thai brands Chang/Singha/Chi Forest),
  330ml, 350ml, 355ml, 1.5L.
- Pack-count patterns common in this category: `"(N x SIZE)"` explicit multiplier is the dominant
  pattern (not Thai promo phrases like the TH categories) — e.g. "(24 x 320ML)", "24x325ml",
  "(12 x 1.5L)". `"[1 Carton]"` / `"[Bundle of N Cartons]"` / `"[Wholesale - Ns]"` prefixes are
  seller-added tags, not part of the product name — do not fold into canonical_name, but do use
  them to help resolve pack_count when the trailing "(NxSIZE)" is itself ambiguous or missing.

**Known difficult products:**
- Products under `BRD-SG-05429` ("Soda") — see Edge cases above, must be individually re-brand-read.
- `"12/+＝"` brand text — garbled OCR/watermark read, per §11 do not trust it as a brand signal.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-22 | Category-file research | 758 existing HUMAN keyword-seed rows found (0 LLM) — confirms genuine first LLM pass, matches wrapper's live pre-check | None needed — proceed with Full Rebuild per headless-runbook.md |
| 2026-07-22 | Category-file research | Naive top-15/20-brand snapshot would have undercounted brand scope — real 95% threshold is 40 brands, not ~15-20 | Used full cumulative-GMV ranking, listed all 40 |
| 2026-07-22 | Pass 1 (Official) | Image check on Coca-Cola "Classic" vs "Original Taste" listings revealed genuinely different products (11% vs 5% sugar, different Nutri-Grade) despite similar naming — would have been wrongly merged from text alone | Kept as separate taxonomy entries |
| 2026-07-22 | Pass 2 (Reseller) | `bq query` CLI defaults to a 100-row output cap (`--max_rows`) — first worklist pull silently truncated 410 rows to 100 | Re-ran with explicit `--max_rows=2000`; always set this flag for any query expected to return >100 rows |
| 2026-07-22 | Pass 2 (Reseller) | 6 genuine alcoholic beer listings (Heineken, Tiger, Hite, Wusu) present in source table despite category being "Carbonated Drinks & Tonics" — same-brand soda (Chang/Singha) vs beer required per-listing text judgment, not a brand-level filter | Left NULL; documented in Scope section |
| 2026-07-22 | Top-up coverage | Live re-run of the worklist query found 46 in-scope NULL rows (matches wrapper's live pre-check of 46). Bulk brand+line+size+pack text-matching against the existing Pass1/Pass2 taxonomy resolved 16 via reuse and required 19 new entries (SKU-116806–116824) for previously-unseen flavors/sizes/brands (Fever-Tree Light Aromatic Tonic, Barbican x6, Remedy Peach Kombucha, MUG Root Beer 1.5L, F&N Cherryade 1.5L, DemiSoda Peach, Old Jamaica Ginger Beer, Lo Bros Raspberry & Blackcurrant, Bundaberg Passionfruit, POKKA Natsbee Honey Yuzu, Karma Drinks Lemmy Lemonade, 2x Vitami flavors, Antipodes multi-size Sparkling Water, Vida 3-bottle Assortment, Coca-Cola Classic/Zero Sugar cans Assortment, QiuLin Kvass, Remedy Sodaly). GMV coverage moved 94.4%→95.05% (884→919/4260 products). | 35 new `product_taxonomy_map` rows written (16 reuse + 19 mint); all 4 QA gates (G1, G2, placeholder-leak, G5) re-ran at 0 |
| 2026-07-22 | Top-up coverage | 11 of the 46 worklist rows correctly left NULL, not force-mapped: 6 genuine alcoholic beer (Heineken/Tiger/Hite/Wusu, consistent with prior Scope finding), 1 Sting Strawberry (verified via image: still/non-carbonated energy drink, not in scope), 2 rows for one "Tropic Farmers Assorted Drinks Can" product + 1 "Tropic Farmers ... Calamansi Sour Plum" product (verified via image: the Tropic Farmers line is entirely non-carbonated juices/tea/soy milk — Young Coconut Juice, Soy Bean, Pineapple Juice, Chrysanthemum Tea, Calamansi & Sour Plum — none carbonated, out of scope for this category despite appearing in the source table) | Left NULL; new scope-exclusion precedent for "Tropic Farmers" and "Sting" documented below |
| 2026-07-22 | Top-up coverage | **Pre-existing scope contamination found, not fixed this session**: `SKU-110643`/`SKU-110644` ("F&N Seasons Ice Lemon Tea"/"Barley") already exist in this category's taxonomy from the original Full Rebuild with real GMV mapped — but F&N Seasons is a non-carbonated RTD tea/barley line, out of scope per this category's own Scope section. A new NULL row for the same product line (F&N Season Ice Lemon Tea 1.5L x12, product `5608313935`) was correctly left NULL this session rather than compounding the error by reusing/extending the contaminated entries. Fixing the existing SKU-110643/110644 mappings is out of scope for a top-up session — flagged for `script/targeted_qa_fix.sh`. | Left NULL this session; existing SKU-110643/110644 contamination NOT remediated — needs a future targeted QA fix pass |
| 2026-07-22 | Targeted QA Fix (auto-discovery) | Tier 1 SQL sweep over the 371-row incremental worklist found the entire remaining 403-row HUMAN keyword-seed long tail was bucketed into 28 pre-Phase-5 catch-all bins (`SKU-002750`–`SKU-002779`), all sharing the banned `(all variants)`/`(all flavors)` stub suffix **and** a bare `product_line = "Carbonated Drink"` — this is the D1 Tier-C "generic stub" pattern quality-standards.md's own example describes, and it independently trips `headless-runbook.md`'s placeholder-leak hard gate (that query is not source-scoped, unlike the "(LLM only)" placeholder-leak line in this file's original ship scorecard above). 6 further entries had `wrong_field_order`-flagged case-(b) brand_id defects: `canonical_name` correctly named a real brand but `brand_id` resolved to an unrelated/undefined brand (Chi Forest→"Genki Forest", Nipis Madu→"Mayora" ×2 dup entries, POKKA→"Apple", 2× BRD-UNDEFINED for real brands Chongdefa/QiuLin with no prior brand_dict entry). | **Structural fix (all 28 bins)**: bulk `REGEXP_REPLACE` stripped the banned suffix, set `is_multi_size=TRUE`/`is_multi_variant=TRUE` (genuinely both apply — each bin spans real heterogeneous sizes/flavors under one correct brand), one entry (`SKU-002774` J&J, bare "Carbonated Drink" remainder) got a real product_line. Hard gates re-ran clean incl. the unscoped placeholder-leak query. **Targeted reroute**: wrote a brand+size+pack extraction query against `sku_name`, required an exact match AND a flavor/product_line keyword hit before auto-applying (a size/pack-only match proved unsafe — e.g. the sole "A&W Root Beer" candidate silently would have matched an unrelated "A&W Sarsaparilla" entry); 103 of 403 stub-bin products (~S$2,102 of ~S$9,949 GMV) safely rerouted to their correct existing `SKU-110xxx` entries, zero new mints needed. Remaining ~300 low/zero-GMV products stay in the now-compliant renamed multi-variant bins (legitimate long-tail, not a stub). **Brand_id fixes**: created 2 new brand_dict entries (`BRD-SG-13400` Chongdefa, `BRD-SG-13401` QiuLin) and corrected `brand_id` on all 6 entries; also found and consolidated an exact-duplicate pair (`SKU-110654`==`SKU-110631` "Nipis Madu Lime Soda Honey 330ml") by rerouting `SKU-110654`'s 1 product onto `SKU-110631`. |
| 2026-07-22 | Targeted QA Fix (Tier 2 GMV sample) | GMV-prioritized sample of the un-flagged worklist surfaced two real defects Tier 1's regex sweep can't see: (1) `SKU-110596` "Cloop Zero Soda Assortment... 500ml" (`pack_count=1`) had 3 mapped products with explicit `[Buy 1 Free 1]` sku_name text — same product/line, different flavor pick, matches the §1 "buy 1 get 1 = pack_count 2" rule, not GWP. (2) `SKU-110494` "Coca-Cola Zero Sugar 320ml" (`pack_count=1`, ~S$6,605 GMV) had drifted into a mixed bag: a genuine `x24` listing (S$4,863.50 GMV) and a mislabeled Coke *Light* `x24` listing (S$709.60) miscoded as this Zero-Sugar single-can entry, a `[Bundle of 48]` listing (S$182.95) with no `x48` entry to route to, and a multi-**brand** buyer-choice assortment ("Coke/Coke Zero/A&W/Sprite ASSORTED", ~S$364) that doesn't belong under a Coca-Cola-only entry at all. | Cloop: `pack_count` 1→2, canonical_name updated to `...500ml x2`. Coca-Cola: rerouted the `x24` product to existing `SKU-110414`, the Coke Light product to existing `SKU-110412`; claimed SKU block `SKU-117606–117805` (targeted_qa_fix, 200 slots, ACTIVE — 198 unused) and minted `SKU-117606` "Coca-Cola Zero Sugar 320ml x48" and `SKU-117607` "Coca-Cola Assorted Cola Cans (Coke/Coke Zero/A&W/Sprite) 320ml" (`is_bundle=TRUE`) for the two unroutable listings; renamed `SKU-110494` itself to `Coca-Cola Classic/Original/Zero/Light Assortment 320ml` (`is_multi_variant=TRUE`) to honestly describe what remains (a single-can, buyer-picks-flavor listing plus a handful of $0-GMV miscoded-pack long tail, left as-is). 31 further top-GMV entries (Coca-Cola/Schweppes/Sprite/Chi Forest/Singha/Chang/Pepsi/POKKA/Ice Mountain/Qoo/SaltCola/Vida/Bundaberg families) spot-checked against sample sku_names and found structurally correct — `_meta` set to `unconfident` (first review). **Not remediated, flagged again**: `SKU-110643`/`SKU-110644` (F&N Seasons Ice Lemon Tea/Barley, ~S$795) remain genuinely out-of-scope non-carbonated RTD tea/barley per this file's own Scope section, first flagged in the 2026-07-22 top-up row above — this session could not resolve it because the two mapped products have real GMV and no in-scope taxonomy exists to reroute them to, and STEP 7 of this session's own brief forbids deleting existing map rows; still needs a human decision (delete vs. recategorize) that this script isn't authorized to make unilaterally. | Confidence distribution after this session: 0 confident (first pass for all reviewed rows), 31 unconfident (Tier-2-reviewed-correct), 340 unreviewed (incl. the ~39 taxonomy entries fixed this session, reset to unreviewed for fresh re-evaluation next run) |
| 2026-07-22 | Targeted QA Fix (auto-discovery, round 2) | **Largest single defect class found across any session so far**: STEP 2b's pack-count/promo-language sweep (previously only "flag, review against image" per its own docstring, never bulk-fixed) surfaced ~90 case-pack listings silently absorbed into single-unit taxonomy entries — buyer paid for a 12/24/48/72-can carton but the entry read as `pack_count=1`. Led by `SKU-110543` "POKKA Soft Drink 300ml" (`pack_count=1`) holding a S$284,337 GMV product whose image (`Assorted Pokka Can Drinks 1 Carton of 24 Cans x 300ml`) shows a 9-flavor **tea** assortment (Lychee Oolong, Peach Oolong, Ice Peach, Green Tea, Houjicha, Sencha, Ice Lemon, Jasmine, Oolong) — wrong product type (tea, not "soft drink") *and* wrong pack_count, not just a pack-count miss. Also found: Chang/Singha "(Bundle of N)" seller-tag text means N×24 total (confirmed against Chang's own pre-existing x24/x48/x72 sibling set, which had been silently under-populated for Singha); a Chang "Passion Fruit" flavor and several Coca-Cola/F&N/Schweppes case sizes had no matching xN sibling to route to at all (D3 variant-collapse-by-omission, not just D5). GMV-prioritized Tier 2 spot-check of the remaining top-40 unflagged-by-Tier-1 entries also caught two type/brand mismatches invisible to regex: `SKU-110513` "Pepsi Black Zero Sugar 320ml x24" held a S$56,407 multi-**brand** buyer-choice assortment ("Pepsi/Pepsi Zero/7up/Mug/Mountain Dew"); `SKU-110439` "Schweppes Soda Water 320ml x12" held a S$63,737 **Ginger Ale** product (wrong flavor entirely, not a Soda Water variant). Tier 1 also reconfirmed the 27 `SKU-0027xx` catch-all bins (renamed off the stub suffix in the prior round) still carried a literal `product_line = "Carbonated Drink"` — the banned generic-category-word defect, just relocated from `canonical_name` into the structured field the prior fix didn't touch. `brand_casing_mismatch`/`wrong_field_order` flags on 10 brands turned out to be `brand_dict.canonical_name` scraping artifacts (all-caps/all-lowercase), not `canonical_name` defects — `canonical_name` (independently LLM-derived from image/text) already carried the correct real-world casing in every case but one (`ANGLIA`→`Anglia`, `Anglia` was in `brand_dict` correctly, `canonical_name` was the outlier there). Image checks on two flagged long-tail rows found a missing "Peach" variant (Three Legs) and a mis-typed generic "Beverage" product_line masking a real 3-flavor Cola/Cola Sugarfree/Orange assortment (Palestine). `duplicate_brand` flag on 3 Vitami rows was a false positive (brand "Vitami" is a literal substring of "Vitamin", which legitimately appears in the product name). | Claimed SKU block `SKU-117806–118005` (targeted_qa_fix, 200 slots, ACTIVE — 183 unused) and minted 17 new entries: POKKA Milk Series 500ml x24, Coca-Cola Classic 320ml x144, Coca-Cola Vanilla 320ml x24, Coca-Cola Original Taste Less Sugar 320ml x48/x72, Singha Soda Water 325ml x48/x72, Chang Soda Water Passion Fruit 325ml x24, Fever-Tree Ginger Ale 200ml x24, Schweppes Ginger Ale 320ml x24, Schweppes Soda Water 330ml x12, F&N Sarsi 325ml x24, F&N Club Soda Water 325ml x48, Ice Cool Coconut Can Drink 310ml x24, Haus Boom Cheers Sparkling Juice Assortment 325ml x12, Nipis Madu Lime Soda Honey 330ml x12, Pepsi Assorted Cola Cans (Pepsi/Pepsi Zero/7up/Mug/Mountain Dew) 320ml x24 (`is_bundle=TRUE`). Rerouted 63 products (~S$1,104,136 cumulative multi-month GMV) from wrong-pack/wrong-type single-unit entries to these new or pre-existing sibling entries via bulk `product_taxonomy_map.taxonomy_id` UPDATEs (POKKA→`SKU-110547` tea assortment, Pepsi assortment→`SKU-117822`, Schweppes Ginger Ale product→`SKU-110442`, remainder to existing/new xN siblings) — zero new `product_taxonomy_map` rows inserted, only pointer corrections, so `G1` stayed clean throughout. Reset all 27 stub-bin `product_line` values to `NULL` (matching the established multi-variant-catch-all precedent already used for this table's coffee-category equivalents) — bulk `REGEXP_REPLACE`-free single `UPDATE ... WHERE product_line = 'Carbonated Drink'`. Fixed `brand_dict.canonical_name` casing for 10 global brand_ids (schweppes→Schweppes, sodastream→SodaStream, DONGA OTSUKA→Donga Otsuka, ICE PEAK→Ice Peak, Fever-tree→Fever-Tree, KICKAPOO→Kickapoo, honeyB→HoneyB, 7-up→7-Up, AW→A&W, Yeo's curly→straight apostrophe) after confirming blast radius was small (1–3 other category tables per brand) and `canonical_name` in this table already independently corroborated the corrected casing. Fixed `SKU-002768` canonical_name casing (ANGLIA→Anglia), `SKU-110613` (added missing "Peach" variant), `SKU-110683` (Palestine: real 3-flavor assortment, not generic "Beverage"). All hard gates (G1, G2, placeholder-leak, G5) re-ran at 0 post-fix. `_meta` bulk-updated for 42 Tier-2-judged-correct entries (comparing against prior verdict — 26 promoted to `confident`, rest `unconfident` first-pass); all touched/created taxonomy rows reset to `unreviewed` for fresh re-evaluation. **Not investigated this session** (left for a future round, both moderate-GMV genuine ambiguities, not silent defects): Salaam Cola product `29681316480` states conflicting can counts (6 vs 8) across scrape snapshots of the same listing; Coca-Cola product `26017258340` (~S$2,554 GMV) uses bare "Carton" text without an explicit count and sometimes mentions "& Zero" (possible mixed-flavor assortment, not pure Classic). |
| 2026-07-22 | Targeted QA Fix (auto-discovery, round 3) | **Major scope-contamination cluster confirmed, much larger than previously realized.** The round-1/round-2 sessions already flagged `SKU-110643`/`SKU-110644` (F&N Seasons Ice Lemon Tea/Barley) as non-carbonated RTD tea wrongly mapped into this category, and round 2 itself rerouted a mis-pack-counted POKKA product into `SKU-110547` "POKKA Tea Assortment" — noting the *pack_count* was wrong without noticing the entry's whole *product type* (tea) was out of scope for a carbonated-drink category. This session verified via actual product images (not just canonical_name text) and found the pattern is systemic, not a one-off: **9 additional taxonomy entries are non-carbonated RTD tea or herbal water, none belonging in this category**, worth ~S$53,281 combined GMV (≈9% of category total) — `SKU-110547` POKKA Tea Assortment 24x300ml (S$5,374.80, confirmed via image: Sencha/Houjicha/Oolong/Peach/Bandung Rose cans, zero carbonation), `SKU-110546` POKKA Tea Series 500ml PET (S$11,956.70, same brand's still-tea PET line), `SKU-110612` Authentic Tea House Variety Set 12x300ml (S$1,166.40, image shows "Ayataka"/"Yin Hao"/Oolong brewed teas), `SKU-110705`/`SKU-110706`/`SKU-110708` J&J Fusion Ice Grape/Yuzu/Peach Tea 24x300ml (S$3,602.40 + S$371.00 + S$454.35, "Real Brewed Real Juice" RTD tea), `SKU-110707` J&J O'Cha Premium Jasmine Green Tea 24x300ml (S$2,657.89, "Real Brewed" still tea), `SKU-110572` Chi Forest Red Bean & Barley Herbal Water 500ml x15 (S$453.63 — a different Genki Forest sub-line, "好自在" boiled herbal water, not their Sparkling Water line), `SKU-110717` Yeo's Green Tea White Grape 250ml x24 (S$27,243.71 — the single largest scope-contamination line found to date, tetra-pak "Justea" brewed green tea, zero fizz). Separately, Tier 2 GMV-sampling also caught two genuine D5 pack-count misses hiding under single-can entries: `SKU-110586` Bundaberg Ginger Beer 375ml (pack_count=1) silently held a 24-bottle wholesale case (S$23,456.30 + S$836 GMV) and several 4-packs; `SKU-110588` Bundaberg Lemon Lime & Bitters 375ml similarly held a 24-pack case (S$7,251.63); `SKU-110506` Coca-Cola Zero Sugar 1.5L held a 12-pack case (S$13,061); `SKU-110542` Fanta Fruit Soda Grape 320ml held a 24-can case (S$2,820.73, itself also a buyer-choice Orange/Grape listing — flagged, not fixed, D3 nuance deferred); `SKU-110510` Coca-Cola Light 320ml (S$0 GMV) held a 12-pack listing; `SKU-110667` Salaam Cola 330ml had conflicting can-count text across scrape snapshots of the *same* product (flagged unresolved in round 2) — majority evidence (2 of 3 non-empty snapshots, higher combined GMV) confirms 8 cans, not 6. Tier 1 SQL sweep also found all 28 `SKU-0027xx` catch-all bins carry a synthetic `sub_line` "tag pair" (e.g. `"Cola / CSD"`, `"Asian / Sparkling"`) that is not a genuine on-package signal — same defect class as the `product_line` NULL fix already applied to these bins in round 1, just never extended to `sub_line`. `wrong_field_order` also caught 2 genuine brand-name truncations: `SKU-110683` canonical_name said "Palestine" but the real brand (confirmed via sku_name "Palestine Drinks 6 x 330ML Cans") is "Palestine Drinks"; `SKU-110613` said "Three Legs" but the real brand (confirmed via a sibling entry already using the full name) is "Three Legs Brand". `duplicate_brand` flags on 3 Vitami rows and the `SKU-117822` Pepsi bundle re-confirmed as false positives (brand substring inside "Vitamin"; intentional brand repetition in bundle/catch-all-bin naming). `SKU-110668` Hivetown Acacia Sparkling Honey Drink (S$6,657.93, size/pack_count both NULL) confirmed genuinely unresolvable — single fixed hero-shot image has no visible size text, no `raw_niq_history` table exists for this category to fall back to, sku_name is silent — `is_multi_size=TRUE` correctly used as the established NULL-size escape hatch. | **Scope contamination: found and documented, NOT fixed** — this session's own instructions forbid deleting existing `product_taxonomy_map` rows, and no in-scope taxonomy exists to reroute these products to (they aren't carbonated at all). Needs a human decision (delete the 9 entries' map rows vs. formally recategorize the products to a tea/RTD category) before a future session can act — same blocker class as the still-unresolved `SKU-110643`/`SKU-110644`. **D5 pack-count fixes applied**: claimed SKU block `SKU-120206–120405` (targeted_qa_fix, 200 slots, now COMPLETE — 198 unused) and minted 2 new entries (`SKU-120206` Bundaberg Lemon Lime & Bitters 375ml x24, `SKU-120207` ...x4, no existing sibling to reuse); rerouted 11 products via `product_taxonomy_map.taxonomy_id` pointer UPDATEs to these new entries plus 4 pre-existing siblings (`SKU-110583` Ginger Beer x24, `SKU-110585` Ginger Beer x4, `SKU-110417` Coca-Cola Zero Sugar 1.5L x12, `SKU-110539` Fanta Grape 320ml x24, `SKU-110413` Coca-Cola Light 320ml x12) — zero new map rows, `G1` stayed clean. Fixed `SKU-110667` Salaam Cola in place: `pack_count` 1→8, canonical_name → `...330ml x8`. **Mechanical fixes**: bulk-nulled `sub_line` on all 28 `SKU-0027xx` bins, also fixed 2 stale brand-casing echoes (`Fever-tree`→`Fever-Tree`, `KICKAPOO`→`Kickapoo`) left over from round 2's `brand_dict` casing fix; fixed `SKU-110683` and `SKU-110613` canonical_name to include the full real brand name. All hard gates (G1, G2 — run *without* `--skip-coexistence`, placeholder-leak, G5, structured-fields) re-ran at 0 post-fix. `_meta` bulk-updated for 59 Tier-2-judged-correct entries (comparing against prior verdict); all touched/fixed/created taxonomy rows reset to `unreviewed` for fresh re-evaluation next run. |

---

## Targeted QA Fix Brief

(Not applicable — this is the initial Full Rebuild, not a targeted fix. Future QA passes should
use `script/targeted_qa_fix.sh` auto-discovery mode per docs/headless-runbook.md.)

---

## Scripts

Extraction performed directly by Claude Code multimodal reading during this headless session —
no pipeline scripts under `pipeline/05_product_taxonomy/llm_shopee_sg_carbonated_drink/` exist or
are needed for this run.

---

## Map Row Counts

| Source | Before Full Rebuild | After Full Rebuild | After 2026-07-22 top-up | Notes |
|--------|-----------------|-----------------|-----------------|-------|
| LLM | 0 | 484 | 519 | 86 Pass 1 + 398 Pass 2 + 35 top-up (16 reuse + 19 new-entry) |
| HUMAN | 758 | 403 | 403 | Untouched this session — top-up scenario only adds LLM rows |
| NULL (unmapped) | ~3,502 | ~3,376 of 4,260 distinct products | ~3,341 of 4,260 | GMV coverage 95.05% (2026-06). Remaining NULLs below GMV scope, or genuinely OOS (beer, Tropic Farmers non-carbonated line, Sting, unidentifiable multi-brand listings) |
