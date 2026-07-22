# shopee_sg_carbonated_drink — Category Context

> First-run Full Rebuild, generated headlessly 2026-07-22. No prior LLM pass exists for this table.

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ⏳ In progress |
| LLM Pass 2 | ⏳ In progress |
| GMV Coverage | TBD — filled after run |
| Last run | 2026-07-22 |
| Current MAX taxonomy_id | Query BQ live before every write — do not trust any number in this file |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| (filled in Step 3 — atomic claim, 2000 slots) | Pass 1 OFFICIAL + Pass 2 RESELLER, first-run full_rebuild |

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

## Map Row Counts (as of session start, before this run)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 0 | Confirms genuine first-run |
| HUMAN | 758 | Keyword-seed rows, coarse "(all variants and pack sizes)" catch-alls per brand |
| NULL (unmapped) | ~3,502 of 4,260 distinct products | Below GMV scope or awaiting this run |
