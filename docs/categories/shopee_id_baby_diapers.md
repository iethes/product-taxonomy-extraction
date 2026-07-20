# shopee_id_baby_diapers — Category Context

> First-ever ID (Indonesia) category in this pipeline. Created during a headless Full Rebuild
> session, 2026-07-20, month = 2026-06.

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ⏳ In progress (this session) |
| LLM Pass 2 | ⏳ In progress (this session) |
| GMV Coverage | TBD — recorded at end of session |
| Last run | 2026-07-20 |
| Current MAX taxonomy_id (registry floor at session start) | SKU-093441 |

**Pipeline onboarding gap (read before trusting any downstream join for this table):**
`master_clean_niq.shopee_id_baby_diapers` exists (3,789,296 rows total; 91,799 rows / 40,465 distinct
products for month 2026-06) and has a `niq_category_mapping` row, but as of session start:
- `magpie_reference.product_brand_map` has **zero** rows for this `master_table` — Stage 03 (brand
  resolution) has never run on it. (12 other ID `master_table`s have `product_brand_map` coverage, but
  those are all Intrepid-pipeline tables — `lazada_id_*`/`shopee_id_*`/`tiktok_id_*` body_lotion,
  facial_moisturizer, facial_wash, sunscreen — a different dataset/pipeline entirely.)
- `magpie.marketshare_universe_niq` (the proven downstream FMCG output table per
  `docs/headless-runbook.md`'s Universe refresh section — 10.9M rows, confirmed SG+TH only) has
  **zero** rows for `country = 'ID'` at all, let alone this table — Stage 04 (Universe Append) has
  never run for ID in this table.
- `magpie.marketshare_universe` (the general/legacy table) does separately carry ~315M `country='ID'`
  rows from an unrelated ingestion path, but none keyed to `master_table = 'shopee_id_baby_diapers'`
  (that table doesn't even have a `master_table` column) — not usable as a substitute join target.

None of the 7 steps in this session's brief actually depend on `product_brand_map` or
`marketshare_universe_niq` (brand-scope GMV and the official-store allowlist are computed directly off
`master_clean_niq`; the QA-gate-as-code checks in `docs/headless-runbook.md` only touch
`product_taxonomy`/`product_taxonomy_map`), so this session proceeded. But the `product_taxonomy_map`
rows this session writes will **not** be visible via the standard `universe_taxonomy_overlay` →
`marketshare_universe_niq` join pattern until Stage 03 and Stage 04 are separately run for this table —
flagging this as a real follow-up item, not something this session can or should fix.

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-093462–095461 | Full Rebuild (Pass 1 OFFICIAL + Pass 2 RESELLER), claimed this session |

---

## Brand Scope (GWP-zeroed GMV threshold 95%, month 2026-06)

Computed directly from `master_clean_niq.shopee_id_baby_diapers` (`CASE WHEN flag_GWP THEN 0 ELSE
gmv_monthly END`), `brand` field raw-string ranking. The raw `brand` field is seller-entered and noisy —
see the consolidation note below before trusting rank order alone.

**Data-quality note on the raw ranking:** `"-"` is a placeholder (not a real brand) sitting at raw rank
6 with 8.3% share — folded into an `(UNDEFINED/BLANK)` bucket together with genuinely blank values
(0.4% of rows). Several raw-string entries are sub-line names a seller entered in the `brand` field
instead of the actual brand (e.g. `Sweety Bronze Pants`, `SWEETY SILVER COMFORT`, `SWEETY GOLD PANTS` →
all really **Sweety**; `Mamypoko royal soft`, `MAMYPOKOPANTS`, `MAMY POKO`, `MAMYLOVE` → all really
**Mamypoko**; `MAKUKU SAP DIAPERS` → **MAKUKU**; `Genki` → **Genki!**). Consolidating these only
concentrates GMV further into brands already in scope — it cannot pull a brand out of scope — so the
raw ranking below is a safe (slightly conservative in brand count) basis for the threshold.

Raw ranking, cumulative GWP-zeroed GMV (IDR), first crosses 95% at rank 12 (POKANA):

| Rank | Brand (raw) | GMV (IDR) | Cum % |
|------|-------------|-----------|-------|
| 1 | Sweety | 41.12B | 18.70% |
| 2 | unicharm | 33.27B | 33.83% |
| 3 | Mamypoko | 29.12B | 47.07% |
| 4 | MAKUKU | 28.49B | 60.03% |
| 5 | Merries | 20.39B | 69.30% |
| 6 | (UNDEFINED/BLANK — incl. literal `"-"`) | 18.28B | 77.61% |
| 7 | BABY HAPPY | 16.80B | 85.26% |
| 8 | Sweety Bronze Pants *(= Sweety)* | 7.58B | 88.70% |
| 9 | Fluffy | 4.87B | 90.92% |
| 10 | HAPPY NAPPY | 4.72B | 93.06% |
| 11 | Sumikko | 2.72B | 94.30% |
| 12 | POKANA | 1.62B | 95.04% |

**Consolidated brand-family scope (11 real brands) used for the allowlist below:**
Sweety, unicharm/Mamypoko (same corporate family — Mamypoko is a Unicharm brand), MAKUKU, Merries (a Kao
brand), BABY HAPPY (a Wings brand), Fluffy, HAPPY NAPPY, Sumikko, POKANA, Genki!/Nepia.
`(UNDEFINED/BLANK)` is GMV-real but not a brand — no allowlist entry possible; routed via Pass 2
text/image only, expect much of it to land in `BRD-UNDEFINED`/`BRD-UNBRANDED` per
`docs/product-lifecycle.md` §4.2's UNRESOLVED rule.

Brands excluded from scope (below the tail, rank 13+): POKANA was the last brand admitted; everything
from rank 13 (Genki!, 0.67% share) downward is out of the 95% scope and may legitimately stay
`UNRESOLVED` unless it appears via Rule B (official store).

---

## Official Store Allowlist (Pass 1)

Built by querying `merchant_name WHERE merchant_badge='Shopee Mall'` per brand-family (raw `brand`
string match), month 2026-06. **304 distinct (brand, Mall-merchant) pairs exist in the raw pool** —
the overwhelming majority are multi-brand retailers (pharmacy chains, supermarket chains, generic baby
stores) that must be excluded regardless of Mall badge per `docs/llm-extraction-rules.md` §4.

| Brand family | brand_id | Official Store Merchant Name(s) |
|---|---|---|
| Sweety | *(assign at extraction time via brand_dict)* | `Sweety Official Shop` |
| unicharm / Mamypoko | *(same family — see note)* | `Unicharm Official Shop`, `MamyPoko Official Store`, `Unicharm Authorized Partner Jawa Timur`, `Unicharm Authorized Partner Jawa Barat`, `Unicharm Authorized Partner Jawa Tengah`, `Unicharm Pet Official Store` *(flag: verify at extraction — 1 row, 1.8B IDR, name suggests a pet-diaper storefront also carrying baby SKUs; confirm real baby-diaper products via image before trusting)* |
| MAKUKU | | `MAKUKU Official Store`; `GIT Prime Official Shop` *(flag: appears only under MAKUKU in this data, 301 rows/40.5M IDR — tentatively an authorized distributor per the parent-company-store pattern in llm-extraction-rules.md §4, not confirmed — verify a sample before trusting as Pass 1)* |
| Merries | | `Merries Official Shop`, `Kao Official Shop` (Merries is a Kao brand) |
| Fluffy | | `Fluffy Official Shop` |
| Genki! / Nepia | | `Nepia Genki & Neppi Official Store` (parent-company store — also carries Neppi, a different Nepia sub-brand; disambiguate per product via sku_name/image) |
| POKANA | | `Pokana Family Official Store`, `Pokana Official Store` |
| BABY HAPPY | | `Wings Official Shop` (BABY HAPPY is a Wings brand) |

**Brands with no official store (Pass 2 only):**
- Sumikko — zero Mall-badged rows for this brand at all.
- HAPPY NAPPY — no dedicated store found; 13 HAPPY NAPPY-labeled rows (28.8M IDR) appear under `Sweety
  Official Shop`, suggesting HAPPY NAPPY may be a Sweety value sub-line, but this is unconfirmed — treat
  as Pass 2, verify brand_from_image if encountered.

**Multi-brand retailers excluded from the allowlist (confirmed by appearing across ≥2 unrelated brand
families in the raw data, or by chain/pharmacy/supermarket naming pattern):**
`Raja Susu Official *` (14 city-branch variants — a multi-brand baby-milk/diaper retail chain),
`Hypermart *` (54 branch variants — supermarket chain), `Century Authorized Store *` / `Century Health
Official Shop` / `Century Mall *` (pharmacy chain, ID's Watsons-equivalent), `Apotek *` (generic pharmacy
stores), `Watsons Indonesia Official`, `Guardian Official Shop`, `ALFAMIDI OFFICIAL STORE`, `Yogya Online
Supermarket Official Shop`, `NM Baby Shop Official Store`, `Mommy n Me Official Shop`, `Prama Borma` /
`Prama Borma Toserba Store`, `Foodmart *`, `Suzuya Superstore Official Shop`, `Supermarket Instant
Cempaka Putih`, `Sehati Market`/`Sehati Healthcare`, `Ayah Bunda Mart Official Store`, `Loz Indonesia
Official Shop`, `Era 2000 Official Shop` (sells both MAKUKU and Sweety), `Cessa Indonesia Official Shop`
(sells MAKUKU, Merries, and POKANA), `Pasar Swalayan ADA Setiabudi`, `Surya Jaya Toko Susu Official
Store`, `Heneco Beauty Official Store`, `FOODIESHOP Official Store` (sells both Fluffy and POKANA),
`Sahabat Bunda Official Shop`, `Hyfresh *`, `Primo *`, `Viva Apotek *`, `KeenSya.id`, `Indofood Official
Shop`, `Genki Moko Moko Official` (0 GMV, ambiguous — excluded pending evidence), plus assorted zero-GMV
long-tail resellers (`omnistore395`, `erradanstore`, `berkah gusra`, `TUTUP AKUN 2` [defunct account],
`BabyAlmeera2/3`, `Berkah Susu Rayyan`, `Healthy One Official Shop`, `Expert Care Official Store`,
`Tentang Anak Shop`, `Pigeon Indonesia Official Shop` [different baby-gear brand, cross-listed],
`Unilever Indonesia Official Shop` [cross-listed, 0 GMV], `Cetaphil Indonesia` [different skincare brand,
cross-listed], `MBJCARE Official Store`).

---

## Scale

- Total rows (month 2026-06): 91,799 — distinct products: 40,465.
- **Full Mall-badged pool: 20,649 rows / 17,384 distinct products — large (tens of thousands scale).**
  Pass 1 does **not** vision-read this whole pool — it scopes strictly to the allowlist above.
- **Official Store Allowlist-scoped pool (actual Pass 1 worklist): 3,300 rows / 1,696 distinct
  products**, 70.06B IDR GMV. This is the real, tractable Pass 1 scope.
- `brand` field fill rate: 99.6% (336 blank rows of 91,799).

---

## Scope — What's In vs Out

**In scope:** disposable baby diapers — tape style (`Popok Perekat` / `Popok Tape`) and pants style
(`Popok Celana` / `Pants`), all sizes (NB/S/M/L/XL/XXL/XXXL) and pack counts. `category_3_EN` for this
table is uniformly "Disposable Diapers" (`category_3` = "Popok Sekali Pakai") — the source table is
cleanly single-category, no mixed-content keyword gate needed for the brand-GMV ranking (unlike
`th_body_wash`/`th_liquid_milk`).

**Out of scope (leave NULL):** training pants marketed as a different product line if any appear (none
seen in the Pass-1 sample); adult diapers (separate category, `shopee_id_adult_diapers`); diaper
disposal bags/accessories if any slip in via mislabeled `category_3`.

**Edge cases:**
- `Unicharm Pet Official Store` and `GIT Prime Official Shop` — flagged above, verify before trusting as
  Pass 1 official-store sources.
- `Nepia Genki & Neppi Official Store` sells two distinct Nepia sub-brands (Genki, Neppi) — disambiguate
  per product.

---

## Taxonomy Design Notes

**Product line / segment extraction approach — text-first, per `docs/llm-extraction-rules.md` §2 (size:
text wins) and this table's own sku_name quality:** `sku_name` is unusually rich and structured for this
category — brand, segment/line, type, size, and pack count are almost always stated explicitly in text
(spot-checked top-40-GMV rows across all main official stores). Example:
`"Sweety Silver Max Protection Soft L 54s x 3 Popok Celana Baby Diapers"` → brand=Sweety,
product_line="Silver Max Protection Soft", type=pants (Popok Celana), size="L", count-per-pack=54,
pack multiplier=3. Images are used for brand-vouching per distinct product-line cluster and to resolve
genuine ambiguity, not for exhaustive per-row reads.

**Segment/tier keywords observed (each is a distinct product_line, never collapse across tiers):**
- Sweety: Silver Max Protection (Soft), Silver Comfort Cloud Soft, Silver Pants Cloud Soft
- Unicharm/MamyPoko: X-tra Kering, X-tra Kering Slim Tidak Gembung, Pants Skin Comfort, Royal Soft
  Organic Cotton
- MAKUKU: SAP Diapers Comfort Fit 3.0 (Plus Extra Jumbo)
- Merries: Pants Good Skin, Skin Protection Slim Pants (Ergoslim)
- Genki: Jumbo Premium Soft

**Type (never merge across):** `Popok Celana` / `Celana` / `Pants` = pants-style; `Popok Perekat` /
`Perekat` / `Popok Tape` / `Tape` = tape-style (newborn sizes NB/NB-S are almost always tape).

**Size + pack-count patterns:**
- Size token: NB, NB-S, S, M, L, XL, XXL, XXXL, sometimes with an attached count e.g. `L 54s`, `XL 38`,
  `NB-S 40` — the trailing number after the size letter is the **pieces-per-pack count**, not the pack
  multiplier.
- Pack multiplier: `x 2` / `x 3` / `2 Packs` / `3 Packs` / `Twinpack` (=2) / `Triple Pack` (=3) /
  `Karton Isi N` (= N packs, carton count) — apply the same GWP-vs-genuine-multipack distinction as
  `docs/llm-extraction-rules.md` §1.
- `Special Upcount` in title = promotional extra pieces bundled into the stated count, not a separate
  multiplier — read the stated total count as-is (needs image spot-check to confirm, flagged as a known
  difficult pattern below).

**Known difficult products:**
- `"Sweety Silver Max Protection Soft S-38s x 3 Popok Celana Baby Diapers - Special Upcount"` — verify
  whether "Special Upcount" changes the piece count vs. the base SKU during extraction.
- `Unicharm Pet Official Store` / `GIT Prime Official Shop` listings — verify brand/category via image
  before minting entries (see Edge Cases above).

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-20 | Session start | First-ever ID category; `product_brand_map`/`marketshare_universe_niq` have zero rows for this table (Stage 03/04 never run) | Documented as a known gap, not a blocker — see Status section |

---

## Targeted QA Fix Brief

> Scope: quality-standard violations on products that **already have** a `taxonomy_id`. Not applicable
> yet — this is the first extraction pass for this category.

---

## Scripts

Not applicable — this category is extracted directly by a Claude Code session (multimodal reading),
not via `pipeline/05_product_taxonomy/llm_{table}/*.py` scripts.

---

## Map Row Counts (as of last run)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | TBD | Recorded at end of session |
| HUMAN | 0 | No prior keyword seed existed for this table |
| NULL (unmapped) | TBD | Below GMV scope or out-of-category |
