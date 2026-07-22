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
