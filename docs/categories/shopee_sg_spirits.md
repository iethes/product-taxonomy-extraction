# shopee_sg_spirits — Category Context

> Generated during headless Full Rebuild, 2026-07-22. First-ever LLM pass for this table —
> `product_taxonomy_map` had 945 `HUMAN` (keyword-seed) rows and 0 `LLM` rows before this run.

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete — 373 entries, 382 official-store products (SKU-114606–114978) |
| LLM Pass 2 | ✅ Complete — 664 new entries + 1,049 reused, 4,970 products (SKU-114979–115642) |
| GMV Coverage | 90.99% (month 2026-06) |
| Last run | 2026-07-22 |
| Current MAX taxonomy_id (before this run) | SKU-114605 (ceiling at claim time — had moved from SKU-110405 seen during earlier research to SKU-114605 by claim time; a parallel session claimed a block in between, confirming why the atomic claim exists) |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-114606–SKU-116605 | Full Rebuild block (2,000 slots), `sku_block_registry` status ACTIVE, scenario `full_rebuild` |

---

## Brand Scope (GMV threshold 95%, month = 2026-06-01)

Ranked by **canonical `brand_id`** (via `product_brand_map`, not raw `brand` string — this table has real
Stage 03 coverage: 13,401 `product_brand_map` rows for `shopee_sg_spirits`, so brand fragmentation across
spelling variants is not a factor here the way it would be for an unmapped table). GWP-zeroed
(`CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END`) before ranking. Product-level GMV summed per `product_id`,
then summed per `brand_id`.

**111 brands** reach the 95% cumulative-GMV threshold (843 total distinct brand_ids appear in the category at
all — this is a long tail, consistent with the "6x undercount" warning: a top-15/20 snapshot would have
covered roughly Martell through Chivas Regal only, ~26% of GMV, nowhere close to 95%).

Top 20 by GMV (full 111-brand list retained in session notes, all included in scope):

1. **Martell** — `BRD-SG-00676` — $115,918.05 (cum 14.29%)
2. **Dewar's** — `BRD-SG-01175` — $50,787.04 (cum 20.56%)
3. **Chivas Regal** — `BRD-SG-01305` — $44,036.90 (cum 25.99%)
4. **The Singleton** — `BRD-SG-01339` — $34,084.21 (cum 30.19%)
5. **Glenfiddich** — `BRD-SG-01437` — $32,189.32 (cum 34.16%)
6. **Suntory** — `BRD-GLOBAL-01032` — $25,726.49 (cum 37.33%)
7. *(BRD-UNDEFINED — $25,693.16, cum 40.5% — see note below, not a real brand)*
8. **Johnnie Walker** — `BRD-SG-01537` — $23,307.22 (cum 43.37%)
9. **Roku Gin** — `BRD-SG-01562` — $22,400.21 (cum 46.14%)
10. **Benedictine Dom** — `BRD-SG-01602` — $21,852.72 (cum 48.83%)
11. **Jameson** — `BRD-SG-01637` — $17,175.60 (cum 50.95%)
12. **The Macallan** — `BRD-SG-01672` — $16,077.74 (cum 52.93%)
13. **Yamazaki** — `BRD-SG-02220` — $15,624.92 (cum 54.86%)
14. **Absolut Vodka** — `BRD-SG-01655` — $14,854.93 (cum 56.69%)
15. **Teacher's** — `BRD-SG-01822` — $14,666.90 (cum 58.5%)
16. **Ballantine's** — `BRD-SG-01868` — $14,567.76 (cum 60.29%)
17. **NIKKA** — `BRD-SG-01977` — $12,685.17 (cum 61.86%)
18. **Bombay Sapphire** — `BRD-SG-02209` — $11,078.38 (cum 63.22%)
19. **Yomeishu** — `BRD-SG-02120` — $10,389.00 (cum 64.5%)
20. **Auchentoshan** — `BRD-SG-02011` — $10,254.71 (cum 65.77%)

...continuing through rank 111, **The Botanist** — `BRD-SG-04267` — $675.93 (cum 94.95%). Ranks 21–111
(Balvenie, Grey Goose, Royal Salute, Bacardi, Luzhou Laojiao, Hibiki, Monkey Shoulder, Hennessy, Kweichow
Moutai, Jack Daniel's, Jim Beam, and ~89 more brands down to sub-$1K GMV) are all in scope per the 95% rule
and retained in session query output; not all reproduced inline here for length.

**Two entries in the ranked list are not real brands and are excluded from the Official Store Allowlist /
taxonomy brand-building below, though their underlying products remain in scope for extraction** (brand gets
re-derived from `sku_name`/image at extraction time, per `product-lifecycle.md` — taxonomy brand_id does not
need to match `product_brand_map.brand_id`):

- **`BRD-UNDEFINED`** (rank 7, $25,693.16, cum 40.5%) — brand could not be resolved by Stage 03. Standard case.
- **`BRD-SG-08876` "12/+＝"** (rank 101, $796.79, cum 94.07%) — a **garbled/OCR-junk brand_dict entry**, the
  exact live example `docs/llm-extraction-rules.md` §11 and the new `qa_report.sh` `GARBAGE_BRAND` gate
  (`NOT REGEXP_CONTAINS(canonical_name, r'[\p{L}]')` — zero letters) were built for. Do **not** mint taxonomy
  entries under this brand_id; the ~$797 GMV behind it needs its real brand re-read from sku_name/image during
  Pass 2, same handling as `BRD-UNDEFINED`.

Brands below the 95% cutoff (732 brands, long tail, sub-$676 GMV each): out of scope, may remain `UNRESOLVED`.

---

## Official Store Allowlist (Pass 1)

Built by querying `merchant_name WHERE merchant_badge='Shopee Mall'` per brand_id, restricted to the 111
in-scope brands (excluding `BRD-UNDEFINED`/`BRD-SG-08876`).

**Spirits distribution structure note:** unlike FMCG categories, this vertical's Mall-badged stores are
dominated by large multi-brand **distributor/importer** stores, not single-brand-owner stores. Some of these
are genuine **parent-company stores** (the listed brands are actually all owned by one beverage conglomerate —
Pass-1-eligible for every brand they carry, same precedent as P&G/Unilever/Lion in FMCG). Others are
independent multi-brand retailers/distributors carrying brands from several unrelated owners — these are
**excluded**, same treatment as Watsons/BigC in other categories. Determined by cross-referencing each store's
brand list against real-world beverage-conglomerate ownership:

| Store | Verdict | Brands carried (in scope) |
|-------|---------|---------------------------|
| `Pernod Ricard Official Store` | ✅ Parent company (Pernod Ricard owns all of these) | Martell, Chivas Regal, Jameson, Absolut Vodka, Ballantine's, Royal Salute, The Glenlivet, MALFY, Codigo 1530, Kahlua, Beefeater, Monkey 47, Malibu, KI NO BI |
| `Suntory Global Spirits` | ✅ Parent company (Suntory/Beam Suntory) | Suntory, Roku Gin, Teacher's, Auchentoshan, Hibiki, Yamazaki, Jim Beam, The Chita, Maker's Mark, Bowmore, Laphroaig, Hakushu |
| `Bacardi Official Store` | ✅ Parent company (Bacardi Ltd. / John Dewar & Sons portfolio) | Dewar's, Benedictine Dom, Bombay Sapphire, Bacardi, Grey Goose, Aberfeldy, Patron, Eristoff, Craigellachie, ROYAL BRACKLA |
| `Brown-Forman Official Store` | ✅ Parent company | JACK DANIEL'S, The GlenDronach, BenRiach |
| `Luzhou Laojiao SG` | ✅ Single-brand store | Luzhou Laojiao |
| `DON DON DONKI Official Store` | ❌ Multi-brand retailer (general Japanese discount chain) | (carries Suntory/NIKKA/Yamazaki/Jim Beam alongside unrelated grocery/cosmetics — not a brand owner) |
| `Prestigio Delights Official` | ❌ Multi-brand retailer | Carries Suntory- **and** Diageo-owned brands (Baileys, Singleton) in one store — proves 3rd-party distributor, not owner |
| `Malt & Wine Asia Official Store` | ❌ Multi-brand retailer | Mixes Brown-Forman, independent, and unrelated-owner brands |
| `Le Vigne Official Store` | ❌ Multi-brand retailer | Mixes Suntory- and LVMH-owned brands (Glenmorangie, Ardbeg) |
| `Kirei – Japan's Finest` | ❌ Multi-brand retailer | Mixes Suntory, Takara Shuzo, Asahi(NIKKA)-owned brands — specialty importer, not owner. Note: `Kirei` is *also* brand_id `BRD-SG-00249` — likely this retailer's own private-label line; do not confuse with a Suntory/NIKKA/TAKARA official presence |
| `Lubritrade Distribution Official` | ❌ Distributor (name says so), not brand-owner | Ballantine's, Kahlua (both happen to be Pernod Ricard brands, but this is a 3rd-party distribution partner, not Pernod Ricard's own storefront) |
| `RedMan Official Store` | ❌ Multi-brand retailer | Mixes Diageo (Baileys, Smirnoff), Rémy Cointreau, Campari, Bacardi(Martini)-owned brands |
| `Sake.SG Official Store` | ❌ Specialty multi-brand retailer | Yomeishu + undefined-brand products |

**Pass 1 official-store allowlist = the 5 ✅ stores only.** 382 distinct products, 405 model rows
(month=2026-06-01). This is the actual Pass 1 population — small enough to read directly, not the full
834-row/774-product Mall-badged pool (which includes the ❌ multi-brand retailers above).

**Brands with no official store at all (in scope, Pass 2 only):** the majority of the 111 — including
The Singleton, Johnnie Walker, The Macallan, Kweichow Moutai, Grey Goose (only via Bacardi's store, already
counted above), Balvenie, Hennessy, Monkey Shoulder, and ~85 more. All routed via reseller text-matching in
Pass 2.

---

## Scale

- Total rows (2026-06-01, all merchants): 14,435 rows / 13,591 distinct products
- Official-store (any Mall badge) rows: 834 / 774 distinct products — **but Pass 1 must scope to the 5-store
  allowlist above (382 products), not this full Mall-badged pool**, per the multi-brand-retailer exclusions.
- 843 distinct brand_ids appear in the category total; 111 reach the 95% GMV threshold.

---

## Existing Map Rows (Step 1, re-verified live)

| Source | Count |
|--------|-------|
| HUMAN | 945 |
| LLM | 0 |

Confirms genuine first LLM pass — matches wrapper's pre-check. No coexistence, no cross-contamination to
pre-sweep for.

---

## Scope — What's In vs Out

**In scope:** all spirits/liquor products — whisky, vodka, gin, rum, brandy/cognac, tequila, baijiu/Chinese
liquor, sake-adjacent herbal liqueurs (Yomeishu), liqueurs (Kahlua, Baileys, Cointreau), bitters used as
category-listed products (Angostura, Campari, Aperol, Fernet Branca).

**Out of scope (leave NULL):** barware/accessories (glasses, decanters, ice molds) if present under this
NIQ category by mislabeling; non-alcoholic 0.0 "mocktail" mixers unless they are a spirits brand's own
0%-ABV line (judged per product); gift boxes / hampers where the primary content is non-alcoholic.

**Edge cases:**
- `BRD-SG-08876` ("12/+＝") — garbled brand, see Brand Scope note. Re-derive real brand from sku_name/image.
- Bundle listings (e.g. whisky + glass gift set) — real product signal per llm-extraction-rules.md §11: never
  read brand from a reseller watermark/overlay; only packaging text/label counts.

---

## Taxonomy Design Notes

**Product line extraction approach:**
- Whisky brands: product_line = the expression/label name (e.g. "12 Year Old", "Double Black", "Distiller's
  Edition"), never the generic word "Whisky"/"Whiskey".
- Cognac/brandy (Martell, Hennessy, Remy Martin): product_line = the tier name (VS, VSOP, XO, Cordon Bleu).
- Vodka/gin: product_line = the flavor/expression if any (e.g. Absolut "Elyx", Roku "Gin"), else brand alone
  is acceptable only when the product genuinely has no sub-line (plain vodka).
- Parent-company stores (Pernod Ricard, Suntory Global Spirits, Bacardi, Brown-Forman): disambiguate brand via
  `brand_from_image`/sku_name per product — the store sells many brands, so the store name itself is never a
  brand signal (llm-extraction-rules.md §11).

**Size extraction notes:**
- Primary units: ml and L (700ml, 750ml, 1L, 1.5L are standard spirits bottle sizes).
- Miniature/gift-set multi-bottle packs common (e.g. "50ml x3 miniature set") — pack_count = bottle count.
- Duty-free / large-format bottles (1.75L) appear for some brands — verify against image, don't assume 700ml.

**Known difficult products:**
- Products under `BRD-SG-08876`/`BRD-UNDEFINED` — read image/sku_name directly, ignore the resolved brand_id.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-22 | Initial (this run) | First LLM pass; 111-brand 95% scope (vs. a naive top-20 snapshot that would only cover ~26% GMV) | Full brand list computed via canonical brand_id ranking, GWP-zeroed |
| 2026-07-22 | Pass 1 | Official-store allowlist (5 parent-conglomerate stores, 382 products) vision/text-extracted | 373 taxonomy entries created SKU-114606–114978; 2 new brand_dict entries (Camino Real BRD-SG-13396, Toki BRD-SG-13397) for real brands missing from brand_dict |
| 2026-07-22 | Pass 2 | Bulk SQL brand-name regex matching found 2 garbage `brand_dict` entries causing false-positive matches: `BRD-TH-00448` "Deal" matched any sku_name containing the word "deal" (~28 unrelated products); `BRD-SG-09857` "Famous" was a truncated duplicate of the real `BRD-SG-04373` "The Famous Grouse" | Excluded "Deal" from matching (28 products left unmapped, ~$2.1K GMV, real brand unclear from text alone); relabeled "Famous" matches to `BRD-SG-04373` (41 products, all genuinely Famous Grouse) |
| 2026-07-22 | Pass 2 | Bulk-routed 4,970 unmapped products: 1,040 matched into existing Pass 1 entries via product_line keyword overlap; 3,930 grouped into 664 new brand+size catch-all entries (product_line intentionally NULL — bulk/coverage-first routing per headless-runbook.md, not a per-product line-text extraction) | SKU-114979–115642 minted; GMV coverage 74.37% (Pass 1 only) → 90.99% (post Pass 2) |
| 2026-07-22 | QA gate self-check | `structured_fields_missing_pct` = 63% (603/951 non-multi-size LLM entries have NULL `product_line`), exceeding the 50% gate threshold — driven entirely by Pass 2's 664 bulk brand+size catch-alls (by design; Pass 1's 373 entries are only 22/373 ≈ 6% NULL). Placeholder-leak gate showed 485 hits but all trace to 17 pre-existing `HUMAN`-source SKU-002xxx legacy keyword-seed entries with "(all variants)" naming predating this session — 0 when scoped to this session's `source='LLM'` rows. | Not fixed this session — per headless-runbook.md's explicit Full Rebuild design ("priority is coverage, not precision... per-row quality... belongs to targeted_qa_fix.sh, scoped by GMV impact"), decomposing the 664 catch-alls into real product lines is left as follow-up work, prioritized by GMV. |
| 2026-07-22 | Automated Targeted QA review (auto-discovery) | Tier 1 SQL sweep over the 1,067-entry never-reviewed worklist found: 17 legacy `SKU-002840`–`002869` catch-alls using the now-banned "(all variants/ages/...)" stub suffix, each with `product_line`='Spirits' (generic word) and `is_multi_size`/`is_multi_variant` incorrectly FALSE — 30 rows total matched the same defect once the null_size sweep was cross-checked (stub_leak's regex only caught 17 of the 30 real instances). Brand_dict casing: 11 brands stored ALL-CAPS (Jack Daniel's, Breezer, Malfy, Royal Brackla, Glenglassaugh, Redbreast, Ricard, Longmorn, Lillet, Old Forester, Herradura) vs. proper-case in already-correct taxonomy entries. Brand_dict typo: "St Germaine" (extra "e") vs. the real "St Germain", confirmed via 2 independent sku_name listings. SKU-114895 canonical_name had a corrupted bundle description (dropped "Chivas" token, double space) plus an uncaptured second variant option (Sherry Cask vs Mizunara, both with real GMV in source model rows). SKU-114964 canonical_name was truncated mid-bundle (trailing "+" with the second product name/size missing) — real product is a Roku Gin + Hakushu Distiller's Reserve cross-brand bundle. 23 Pass-1 entries had `product_line` polluted with listing-format bracket tags (`[Bundle of 6]`, `[2-Pack]`, `[Gift Set]`, etc.) not part of the real product line. STEP 2b's promo-language sweep (226 pack_count=1 rows with GWP/multiplier text) found 9 genuine multipack misses (vs. the ~217 correctly-classified GWP freebies) — plus a severe D3 variant-collapse: `SKU-114806` "Chivas Regal Extra 13 Year Old Bourbon Cask" was being used as a 52-product catch-all silently absorbing distinct real expressions (12 Year Old, 18 Year Old, 25 Year Old, XV Gold, Royal Salute — a different brand entirely). Also found "Martell Cognac **France** VSOP" — an ungrounded country-name insertion into `product_line` absent from every underlying sku_name. | All 30 legacy stub entries fixed in one bulk UPDATE (suffix stripped, `product_line`→NULL, `is_multi_size`/`is_multi_variant`→TRUE). Brand_dict casing and "St Germaine"→"St Germain" typo fixed at the brand_dict level (11 + 1 rows). SKU-114895 and SKU-114964 canonical_name/product_line corrected directly. 23 entries' bracket-tag `product_line` pollution stripped in one bulk UPDATE. Claimed SKU block 117406–117605 (`targeted_qa_fix` scenario) and minted 1 new entry (`SKU-117406` "Johnnie Walker Double Black 1000ml x3") for 2 previously-mismapped products. Rerouted 9 individual multipack-miss products to correct existing x2/x3/x6 pack-variant entries via direct `product_taxonomy_map` UPDATE. Rerouted all 52 `SKU-114806` products via a `MERGE` keyed on sku_name regex (Royal Salute→`SKU-002854`, XV Gold→`SKU-114900`, 25YO→`SKU-114852`, 18YO→`SKU-114879`/`SKU-114898`, 12YO→`SKU-114813`), leaving only 4 genuine Extra-13-Bourbon-Cask products at `SKU-114806`. "France" stripped from 3 Martell VSOP entries' `product_line`/`canonical_name`. 126 taxonomy entries given a genuine Tier-2 review this session were bulk-marked `_meta.review_confidence='unconfident'` (first-ever review) via one UPDATE; every fixed entry's `_meta` was reset to `unreviewed` in the same statement as its content fix. **Not fixed (reported, out of scope for this session):** G2 hard gate (HUMAN+LLM coexistence) = 152, a pre-existing gap from this category's Full Rebuild session (its own HUMAN-row cleanup step was never run) — remediation is the wrapper/Full-Rebuild's job per headless-runbook.md, not this review session's. `structured_fields_missing_pct` remains 63%, unchanged and still by-design per the prior entry above. |
| 2026-07-22 | Top-up coverage session | Live re-run of the 95%-cumulative-GMV (GWP-zeroed) worklist for month 2026-06 found 183 distinct in-scope products (186 model rows) with `taxonomy_id IS NULL` — a real, current gap, not the same as the "186" figure the wrapper's pre-check reported (that number happened to match, but was independently re-derived per this session's instructions, not trusted as-is). Root cause: this is genuine long-tail reseller inventory below Pass 2's original brand-ranking cutoff, plus several `brand_dict` contamination cases surfaced during resolution: `BRD-TH-00448` "Deal" (Singleton Of Dufftown mismatched, same known-garbage brand from the original Pass 2 session), `BRD-GLOBAL-00129` "Scoth" (Passport and VAT 69 both mismatched to this typo'd generic-word entry), `BRD-TH-03174` "Lemon" (Pallini Limoncello), `BRD-SG-02708` "Finish" (Glendalough, matched on "...Oak **Finish** PROMO..."), `BRD-SG-04721` "Cellarbration" (2 products — brand derived from the *merchant's own store name* "Cellarbration", the exact anti-pattern `llm-extraction-rules.md` §11 warns against; one resolved to the real brand Kanto, the other — "Ube Cream Liqueur" — had no legible brand text in either sku_name or product image and was deliberately left unmapped rather than guessed), and `BRD-SG-05846` "Hapsburg Absinthe" (2 Teichenne/Jacques Senaux products mismatched to an unrelated absinthe brand). 22 products had no size stated in `sku_name` or in `raw_niq_history` (which has zero SG spirits coverage — TH-only per the size-regex-pass note in `llm-extraction-rules.md` §2); all 22 product images were fetched and read directly, resolving 17 to a confirmed size and leaving 5 genuinely unreadable (Kinmen Kaoliang "Superior" grade defaulted to the brand's existing 600ml entry as the best available signal; Henri Bardouin Pastis, Golden Star Kaoliang, and both Golden Flower ceramic-bottle products — Mei Kuei Lu and Wu Chia Pi — had no legible net-content text at any resolution available). | Bulk-first reuse-before-mint per this session's brief: matched 30 products to 25 already-existing taxonomy entries by brand+size (e.g. Kahlua 750ml, Baileys 750ml, William Lawson's 700ml, 4× Macallan-700ml reuses, 3× Balvenie-700ml reuses) rather than minting duplicates. Minted 145 new taxonomy entries (`SKU-120006`–`SKU-120150`, within the claimed `taxonomy_topup` block `SKU-120006`–`SKU-120205`) for products with no existing brand+size match, keeping genuinely distinct same-brand-same-size expressions separate (e.g. 4 distinct Blanton's editions, 2 distinct Glenfarclas ages, 6 distinct Yanghe baijiu sub-lines) rather than collapsing them into one ambiguous catch-all. Created 22 new `brand_dict` entries (`BRD-SG-13403`–`BRD-SG-13424`) for real brands with no prior entry (Yanghe, Hongxing/Red Star, Golden Flower, Golden Star, Kong Fu Jia, Shui Jing Fang, Hua Tuo, Beehive, Passport, VAT 69, Pallini, Glendalough, ORI-GIN, Rocca di Montemassi, Kanosuke, Marlborough, Jian Zhuang, Granuaile, Henri Bardouin, Jiang, Topanito, Pere Kermann's) and re-pointed all 5 brand-contamination cases above to their real, pre-existing brand_id (Singleton, Passport, VAT 69, Pallini, Glendalough, Kanto, Teichenne — `product_brand_map` itself was left untouched, since taxonomy mapping does not require brand_id agreement with it, per established precedent). 182 of the 183 in-scope products mapped (1 left `NULL` — Ube Cream Liqueur, genuinely unresolvable brand). GMV coverage rose from 90.99% to 97.80% (month 2026-06). Live worklist re-run after writes: 1 row remaining (the deliberate Ube Cream skip). QA gates: G1 (dual-mapped LLM) = 0, G4 (cross-category — no `shopee_sg_spirits`-mapped `taxonomy_id` shared with any other `master_table`) = 0, G5 (provenance) = 0, placeholder-leak = 0 — all clean, this session introduced no new violations. `structured_fields_missing_pct` = 58% (down from the 63% recorded in the QA-review entry above, re-measured live this session rather than assumed unchanged — this session's ~115 product_line-populated new entries moved it, even though the metric remains high-by-design overall because of the 664 pre-existing Pass 2 catch-alls). **G2 (HUMAN+LLM coexistence) = 152 — unchanged from the pre-existing baseline measured before this session's writes began**, confirming this session added zero new coexistence (every one of the 183 worklist products had no prior map row of either source). This is the same pre-existing gap flagged in the QA-review entry above and remains the Full-Rebuild wrapper's cleanup responsibility, not this session's — reported here again since this session's instructions required a fresh, un-skipped coexistence check. |
| 2026-07-22 | Top-up coverage session (2nd) | Live re-run of the 95%-cumulative-GMV (GWP-zeroed) worklist for month 2026-06 found exactly 1 row: product `24979350639`, "Ube Cream Liqueur 700ml" from merchant "Cellarbration" (cumulative 86.64%) — matching the wrapper's pre-check count, but independently re-derived per this session's instructions rather than trusted as-is. This is the exact same product the prior top-up session (row above) already investigated and deliberately left unmapped. Re-fetched and re-read the product image directly (not trusting the prior session's conclusion blind): the bottle label reads "Ube Cream Liqueur 17% 700ml" with a stylized/mirrored-font logo and a metal medallion tag, both illegible at available resolution even after 3x/4x crop-and-zoom — no real brand name resolves from either. "Cellarbration" (top-left logo) is confirmed as the reseller's own store branding, not the product's brand, per `llm-extraction-rules.md` §11 (never resolve brand from a reseller watermark/overlay). No new legible signal found beyond what the prior session already established. | No writes this session — zero rows created, zero rows mapped, no SKU block claimed (nothing to mint or route). GMV coverage unchanged at 97.80% (month 2026-06). QA gate self-check (run without `--skip-coexistence`, per this session's instructions): G1 (dual-mapped LLM) = 0, G2 (HUMAN+LLM coexistence) = 152 — unchanged, still the pre-existing Full-Rebuild-wrapper cleanup gap flagged in the two entries above, not introduced or touched this session, G4 (cross-category) = 0, G5 (provenance) = 0, placeholder-leak = 0 (both all-source and LLM-only scoped). `structured_fields_missing_pct` = 58%, unchanged from the prior session's measurement (no new LLM entries written to move it). The single remaining NULL is confirmed genuinely unresolvable, not a coverage gap needing action. |
| 2026-07-22 | Automated Targeted QA review (auto-discovery, 2nd) | Tier 1 SQL sweep over the 1,213-entry never/unconfident worklist found (no `stub_leak`/`null_size`/`garbage_brand` this time — prior session's fixes held): `brand_dict` casing/typos on 3 more brands (`LOCH LOMOND`→correct-case entries already existed, `JURA`, `jingpai` lowercase) plus `Pere Kermanns` missing its apostrophe (typo introduced when the top-up session created it) and two brand_dict entries with a stray category word baked into the name (`Plantation Rum`, `Blanton's Bourbon`) causing every real taxonomy entry under them to read as "wrong field order" against the polluted brand string. `Benedictine Dom` brand_dict entry vs. 3 different on-taxonomy spellings (`D.O.M.`/`Dom`/`DOM`) — standardized on the correct on-label form `Benedictine D.O.M.`. 20 `SKU-115xxx` Jack Daniel's/Royal Brackla entries had ALL-CAPS `canonical_name` (brand_dict itself was correctly cased — the defect was on the taxonomy row, opposite direction from the brand_dict casing bugs). While correcting those, 4 entries had sizes visibly wrong against their own `sku_name` (`698ml`→700ml, `198ml`→200ml, `373ml`→375ml, `710ml`→700ml — a data-entry corruption, not a real alternate bottle size). `SKU-114960` "Jim Beam Bourbon Whiskey Apple, Honey, White" turned out to merge 3 unrelated source rows: 2 plain "Jim Beam White" listings plus 1 genuine `[Mixed Bundle of 3]` listing incorrectly carrying `pack_count=1` — the D5 promo-regex sweep doesn't catch "Mixed Bundle of N" phrasing (no `x\d`/`free`/Thai token). Investigated the `is_bundle=TRUE` population generally (24 entries): most `pack_count=1` bundle entries are correctly GWP/single-bottle, but `SKU-114876` (Ballantine's+Chivas), `SKU-114881` (Jameson+Redbreast), `SKU-114964` (Roku+Hakushu), and the ambiguous `SKU-114895` (Chivas "2+1") look like paid 2-bottle bundles undercounted at `pack_count=1` — left unfixed this session (near-zero monthly GMV each, and `SKU-114895`'s true bottle count is genuinely ambiguous from the listing text) rather than risk a wrong bulk correction across a heterogeneous flag population. STEP 2b's promo-language sweep (224 pack_count=1 rows) found one more genuine miss beyond the bundle cases: `House of Nikka ... 2Bottles x 700ml` mapped into the 115-product `NIKKA 700ml` catch-all at pack_count=1. Per this session's own re-derivation (not trusted from the wrapper's stale note), GMV-prioritized the 664 pre-existing Pass 2 brand+size catch-alls (per-entry `SUM(gmv_monthly)` correctly scoped to month=2026-06, not summed across all history — an early draft of this query double-counted ~17 months and had to be redone) and decomposed the two highest-impact ones by real product line, reading every underlying `sku_name`: **Jameson 700ml** (27 products, one generic catch-all) → 25 are the same base "Original/Triple Distilled" expression (kept, renamed), 2 are genuinely distinct expressions ("18 Year Old Limited Reserve", "Cooper's Croze") that had been silently absorbed. **KAVALAN 700ml** (92 products, the single worst D3 variant-collapse found in this category to date) → decomposed into 13 real product-line buckets (Classic, Concertmaster Port Cask Finish, King Car Conductor, Triple Sherry Cask, Distillery Select No.1/No.2/unnumbered, Ex-Bourbon Oak, Oloroso Sherry Oak, LAN, Podium, Selection Single Cask Strength, and a `Solist Single Cask Strength` `is_multi_variant=TRUE` bucket for the 37 one-off single-cask limited releases that aren't practical to atomize further per-cask-code). | `brand_dict` fixed for 7 brands in one bulk `UPDATE` (`BRD-SG-04737` Loch Lomond, `BRD-SG-05264` Jura, `BRD-SG-04708` Jingpai, `BRD-SG-13424` Pere Kermann's, `BRD-SG-05167` Plantation, `BRD-SG-04282` Blanton's, `BRD-SG-01602` Benedictine D.O.M.). 20 ALL-CAPS `canonical_name` rows fixed via `REPLACE`; the 4 wrong sizes corrected in `canonical_name` and `size` together; `SKU-002848`/`SKU-115246` standardized to "Benedictine D.O.M."; `SKU-120044` given the "Year Old" suffix to match its `18 Year Old` sibling. Claimed SKU block `SKU-120656`–`120855` (`targeted_qa_fix` scenario). Jim Beam split: `SKU-114960` renamed to the plain "White" expression; minted `SKU-120656` for the Mixed Bundle of 3 (`pack_count=3`, rerouted 1 product). Jameson split: `SKU-114901` renamed "Jameson Original Irish Whiskey 700ml"; minted `SKU-120657`/`120658` for the 2 distinct expressions, rerouted both products. Kavalan split: `SKU-114992` repurposed as the Solist `is_multi_variant=TRUE` bucket (37 products stay); minted `SKU-120659`–`120670` (12 entries) and rerouted the other 55 products via bulk `product_taxonomy_map` `UPDATE`s grouped by bucket. Minted `SKU-120671` for the House of Nikka 2-bottle set (`pack_count=2`), rerouted 1 product out of `SKU-115081`. 46 Tier-1-flagged rows that turned out to be false positives of this session's own SQL heuristics (the "/"-token artifact on 30 legacy `SKU-002840`–`002869` catch-alls, parenthetical-detail omissions correctly left out of `canonical_name`, and brand_dict-casing rows that resolved once brand_dict itself was fixed) were bulk-marked reviewed via one `_meta` `UPDATE`, matching this session's own genuine Tier-2 judgment — not blanket-applied to the whole worklist. **Not fixed (reported, deferred):** the 4 ambiguous/low-GMV bundle `pack_count` cases above; residual D3 collapse inside `SKU-115149`/`SKU-115156` (Jack Daniel's flavor variants still merged, low GMV); a `Johnnie Walker ... Empty Bottle And Box` listing (GMV=0) mapped to a real-whisky entry that is arguably out-of-scope (a collectible, not a spirits sale) — left as-is since map rows cannot be deleted and no NULL-safe alternative exists; the remaining ~600 Pass-2 catch-alls beyond Jameson/Kavalan, GMV-ranked next-up: `GLENALLACHIE 700ml` (50 products), `Tanqueray 700ml` (57), `Dalmore 700ml` (49), `Ardbeg 700ml` (51), `The Macallan 700ml` (42), `NIKKA 700ml` (113 remaining), `Lagavulin 700ml` (30) — all identified this session as the next GMV-prioritized decomposition targets, not attempted due to per-session turn budget. `structured_fields_missing_pct` = 57% (down from 58%, still above the 50% soft-gate threshold — expected, by design, per the two entries above; this session's 2 decompositions moved it only slightly since 12 of 16 new/renamed entries still needed a real `product_line`, which they now have). GMV coverage unchanged at 97.80% (no new NULL products mapped this session — all fixes were reroutes/splits of already-mapped products). QA gate self-check (no `--skip-coexistence`): G1 (dual-mapped LLM) = 0, G2 (HUMAN+LLM coexistence) = 152 — unchanged, still the pre-existing Full-Rebuild-wrapper gap, not touched this session, G4/G5/placeholder-leak = 0. |

---

## Targeted QA Fix Brief

_(Not applicable — this is the first Full Rebuild pass, not a targeted fix. Auto-discovery mode will apply on
future `targeted_qa_fix.sh` runs against this category.)_

---

## Scripts

| Script | Purpose |
|--------|---------|
| `script/headless_taxonomy.sh` | Full Rebuild orchestration (this run) |
| `script/qa_report.sh` | Post-run QA gate report incl. `GARBAGE_BRAND` |
| `script/targeted_qa_fix.sh` | Future per-entry quality fixes |

---

## Map Row Counts (as of last run)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 5,352 | Pass 1 (382) + Pass 2 (4,970) |
| HUMAN | 945 | Retained; not deleted by this session per headless-runbook.md (wrapper's job, not this session's); 152 products now have both a HUMAN and LLM row (expected pre-cleanup coexistence, not yet swept) |
| NULL (unmapped) | 7,269 | Below GMV scope or out-of-category; GMV coverage 90.99% |
