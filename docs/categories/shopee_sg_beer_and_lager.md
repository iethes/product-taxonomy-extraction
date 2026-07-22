# shopee_sg_beer_and_lager — Category Context

> Generated during headless Full Rebuild session, 2026-07-22.

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ⏳ In progress (this session) |
| LLM Pass 2 | ⏳ In progress (this session) |
| GMV Coverage | TBD — measured after this session |
| Last run | 2026-07-22 |
| Current MAX taxonomy_id | SKU-110395 (live, pre-session) |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| (assigned in Step 3 of this session — see session findings) | Full Rebuild (Pass 1 + Pass 2) |

---

## Brand Scope (GMV threshold 95%, month 2026-06)

Computed from `master_clean_niq.shopee_sg_beer_and_lager`, `month = '2026-06-01'`, GWP-zeroed
(`CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END`), aggregated to product level, joined to
`product_brand_map` (`platform='Shopee', country='SG'`) → `brand_dict.canonical_name`, ranked by
GMV descending with a running cumulative-GMV fraction. Total category GMV (month): **SGD 935,567.02**
across 324 distinct brand buckets (including `BRD-UNDEFINED` and unmatched/NULL brand rows).

**29 brands** reach the 95% cumulative-GMV threshold (cutoff at rank 29, `Bavaria Beer`, cum. 95.01%).
This is the full real threshold, not a fixed-size snapshot — the tail (ranks 30–324) accounts for the
remaining ~5% of GMV and is excluded from scope.

| Rank | Brand | brand_id | GMV (SGD) | Cum. % |
|---|---|---|---|---|
| 1 | Carlsberg | BRD-SG-00402 | 337,696.36 | 36.10% |
| 2 | Sapporo | BRD-GLOBAL-01222 | 91,408.54 | 45.87% |
| 3 | Guinness | BRD-GLOBAL-01211 | 75,377.22 | 53.92% |
| 4 | Heineken | BRD-GLOBAL-00871 | 62,061.44 | 60.56% |
| 5 | Yebisu | BRD-SG-01772 | 31,621.86 | 63.94% |
| 6 | Suntory | BRD-GLOBAL-01032 | 31,167.65 | 67.27% |
| 7 | Asa-Hi | BRD-TH-02704 | 30,341.00 | 70.51% |
| 8 | Kronenbourg 1664 | BRD-SG-01122 | 27,964.37 | 73.50% |
| 9 | TIGER | BRD-SG-08104 | 25,905.62 | 76.27% |
| 10 | *(unmatched — no `product_brand_map` row)* | BRD-UNDEFINED | 25,344.33 | 78.98% |
| 11 | TUBORG | BRD-SG-01893 | 22,284.01 | 81.36% |
| 12 | Anchor | BRD-SG-02557 | 19,887.74 | 83.49% |
| 13 | SKOL | BRD-SG-02221 | 14,990.59 | 85.09% |
| 14 | Somersby | BRD-SG-01881 | 11,494.29 | 86.32% |
| 15 | Cass | BRD-SG-02587 | 9,965.20 | 87.38% |
| 16 | Danish Royal Stout | BRD-SG-02403 | 9,468.60 | 88.39% |
| 17 | Hoegaarden | BRD-SG-02319 | 8,904.11 | 89.35% |
| 18 | Snow Beer | BRD-SG-02223 | 7,346.95 | 90.13% |
| 19 | Corona Extra | BRD-SG-02530 | 7,097.28 | 90.89% |
| 20 | KIRIN ICHIBAN | BRD-SG-02606 | 7,049.52 | 91.64% |
| 21 | Paulaner | BRD-SG-02626 | 4,823.91 | 92.16% |
| 22 | Connor's Stout Porter | BRD-SG-02460 | 4,173.00 | 92.60% |
| 23 | Singha | BRD-GLOBAL-00047 | 3,820.80 | 93.01% |
| 24 | Pure Blonde | BRD-SG-02468 | 3,788.40 | 93.42% |
| 25 | Erdinger | BRD-SG-02188 | 3,719.24 | 93.81% |
| 26 | Tsingtao | BRD-SG-03703 | 3,256.36 | 94.16% |
| 27 | Maximus | BRD-GLOBAL-01036 | 2,838.00 | 94.47% |
| 28 | ANGLIA | BRD-SG-01681 | 2,532.00 | 94.74% |
| 29 | Bavaria Beer | BRD-SG-02568 | 2,512.00 | 95.01% |

**Row 10 caveat:** `BRD-UNDEFINED` at rank 10 (SGD 25,344.33) is products with no `product_brand_map`
row joinable at all (not the same as `brand_dict`'s literal "Undefined" canonical entry, which separately
appears at rank 33 outside the 95% cutoff). These products still get extracted like any other in-scope
product — the LLM reads `brand_from_image` directly per `docs/llm-extraction-rules.md` §7 — they just have
no brand-owned official store to query for a Pass 1 allowlist, so route via Pass 2 text/image matching only.

Brands excluded from scope (tail, ranks 30–324, ~5% of GMV): Budweiser, MUG, Kirei, Terra, Estrella,
Brooklyn, Leo, Hite, Weihenstephaner, San Miguel, KINGFISHER, Little Creatures, HiteJinro, Wusu, and ~285
smaller/long-tail brands. One tail entry of note: `12/+＝` (BRD-SG-08876, rank 58) — a known garbage brand
from a prior seller-watermark misread (see `llm-extraction-rules.md` §11, product `7155345414`); it is
below the 95% cutoff regardless, so it requires no special handling this session.

---

## Official Store Allowlist (Pass 1)

Built by querying distinct `merchant_name WHERE merchant_badge='Shopee Mall'` per in-scope `brand_id`
(month 2026-06-01), then checking each candidate merchant's full brand portfolio within this table to
distinguish a genuine brand/parent-company store from a multi-brand distributor or general retailer.

**Included (brand-owned or single-corporate-family stores):**

| Brand(s) covered | brand_id(s) | Official Store Merchant Name | Basis |
|---|---|---|---|
| Carlsberg, Connor's Stout Porter, Danish Royal Stout, Kronenbourg 1664, SKOL, Somersby, TUBORG | BRD-SG-00402, BRD-SG-02460, BRD-SG-02403, BRD-SG-01122, BRD-SG-02221, BRD-SG-01881, BRD-SG-01893 | `Carlsberg Beer Official Store` | Parent-company store — Carlsberg Group owns all 7 brands globally (Unilever/Lion-style pattern) |
| Sapporo, Yebisu | BRD-GLOBAL-01222, BRD-SG-01772 | `Sake Inn Official Store` | Both brands are owned by Sapporo Holdings; store carries only these two — treated as parent-company store, not a general multi-brand importer |
| Suntory | BRD-GLOBAL-01032 | `Suntory Global Spirits` | Single-brand — Suntory's own global spirits/beer division storefront |

Pass 1 in-scope row count from these 3 stores: **44 rows / 43 distinct products** (month 2026-06-01).

**Multi-brand stores excluded** (confirmed via full brand-portfolio check within this table — regardless of
Mall badge, per `docs/llm-extraction-rules.md` §4):

| Merchant Name | Distinct brands carried (sample) | Why excluded |
|---|---|---|
| `Pacific Beverages Official Store` | 17 brands: Estrella Galicia, MAELOC, James Squire, James Boag's, Franziskaner, Stella Artois, Hoegaarden, Tooheys, ... | Multi-brand craft/import beverage distributor |
| `RedMan Official Store` | 11 brands: BRUT, Hoegaarden, Bavaria, TUBORG, SWEET, Mort Subite, Leffe, ... (spans multiple unrelated brewers — AB InBev, Carlsberg, independents) | Multi-brand beer importer/distributor, not a single owner's portfolio |
| `DON DON DONKI Official Store` | 8 brands: Kirin, Suntory Horoyoi, Suntory, Asa-Hi, Coca-Cola, ... | General multi-category discount retail chain (SG equivalent of BigC/Lotuss) |
| `Kirei – Japan's Finest` | 7 brands: Suntory, Echigo, TAKARA, ASEED ASTER, Kirin, Kirei, Sapporo | Multi-brand Japanese beverage importer |
| `K-Market by Koryo Trading` | 5 brands: Jinro, KookSoonDang, Gs Retail Youus, LOTTE, Cass | Multi-brand Korean goods distributor |
| `Lubritrade Distribution Official` | 4 brands: Cass, Haywards 5000, Kwirk Beer Co., Dester | Multi-brand distributor |
| `Prestigio Delights Official` | 2 brands: Corona Extra, Bundaberg (unrelated companies — AB InBev vs. Bundaberg Brewed Drinks) | Multi-brand reseller |

**Brands in scope with no official store** (skip Pass 1, go directly to Pass 2 per §4): Guinness, Heineken,
TIGER, Anchor, Hoegaarden (its only Mall presence is via the excluded Pacific Beverages/RedMan
distributors), Snow Beer, Corona Extra, KIRIN ICHIBAN, Paulaner, Singha, Pure Blonde, Erdinger, Tsingtao,
Maximus, ANGLIA, Bavaria Beer, Cass (only via excluded K-Market/Lubritrade), and the unmatched-brand
(`BRD-UNDEFINED`) bucket. Verified TIGER, Heineken, and Anchor (all Asia Pacific Breweries/Heineken-family
brands, high GMV rank) have **zero** `Shopee Mall` rows in this table at all — confirmed via direct query,
not an allowlist omission.

---

## Scale

- Total rows (month 2026-06-01): 5,072
- Distinct products (month 2026-06-01): 4,037
- `Shopee Mall`-badged rows (all merchants, before allowlist filtering): 602 rows / 489 distinct products —
  **not** the Pass 1 scope; most of this pool belongs to the excluded multi-brand distributors above.
- Official Store Allowlist rows (actual Pass 1 scope): 44 rows / 43 distinct products — small, no
  further scoping needed.
- All-time source table row count (all months): 167,678 rows.
- Category composition: `category_3_EN` is `Beer & Cider` (160,028 rows) and `Alcohol - Beer & Cider`
  (7,650 rows) — single coherent vertical, no evidence of mixed unrelated content (spot-checked 15 random
  `sku_name`s, all genuine beer/cider/chu-hai products). No brand-ranking keyword pre-filter was needed.

---

## Existing map rows (Step 1, live-queried 2026-07-22)

| Source | Count |
|--------|-------|
| HUMAN | 463 |
| LLM | 0 |

Consistent with a genuine first LLM pass — no prior Phase 5 run has touched this table.

---

## Scope — What's In vs Out

**In scope:** beer, lager, cider, chu-hai (flavored malt/spirit-based canned beverages sold under
Suntory Horoyoi and similar lines appear in this table's `sku_name`s) — anything genuinely a
beer/cider/malt beverage product per the source category's own `Beer & Cider` / `Alcohol - Beer & Cider`
classification.

**Out of scope (leave NULL):** products that are not beer/cider despite appearing in this table due to
NIQ mislabeling (to be identified per-product during extraction, not via a pre-filter) — e.g. wine,
spirits, or unrelated grocery items a multi-brand Mall seller might cross-list.

**Edge cases:** none identified yet — to be filled in during extraction per
`docs/quality-standards.md`'s review process.

---

## Taxonomy Design Notes

**Product line extraction approach:**
- Brand-owned stores (Carlsberg, Sake Inn, Suntory Global Spirits): read product line directly from
  image/sku_name per brand.
- All other brands: Pass 2 bulk text-matching against Pass-1-built taxonomy, image reads reserved for
  ambiguous cases.

**Size extraction notes:**
- Primary unit: ml (bottles/cans), L (kegs/growlers if present).
- Pack-count patterns common in this category: `x{N}`, `[N Bottles]`, `{N} Cans`, `[1 Carton]`,
  "24 bottles x 330ml" style explicit total statements — apply §1 priority chain (sku_name → image →
  spec → description), image is tiebreaker for pack count per universal rule.

**Known difficult products:** none catalogued yet — to be filled in during extraction.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-22 | Category file generation | Real 95% GMV threshold is 29 brands (not a fixed top-15/20 snapshot) | Full 29-brand list documented above |

---

## Targeted QA Fix Brief

Not applicable — this is a first-run Full Rebuild session, not a Targeted QA Fix.

---

## Scripts

| Script | Purpose |
|--------|---------|
| N/A | This session performs extraction directly via Claude's own multimodal reading, not external scripts. |

---

## Map Row Counts (as of last run)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | TBD | Populated after this session's Pass 1 + Pass 2 |
| HUMAN | 463 (pre-session) | Long-tail out-of-scope products (retained) |
| NULL (unmapped) | TBD | Below GMV scope or out-of-category |
