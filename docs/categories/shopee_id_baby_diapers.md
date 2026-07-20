# shopee_id_baby_diapers — Category Context

> First-ever ID (Indonesia) category in this pipeline. Created during a headless Full Rebuild
> session, 2026-07-20, month = 2026-06.

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete |
| LLM Pass 2 | ✅ Complete (text-match routing; long reseller tail left UNRESOLVED, see below) |
| Top-up coverage session | ✅ Complete 2026-07-20 (SKU-096476–096540; see QA History) |
| Second top-up coverage session | ✅ Complete 2026-07-20 (SKU-096541–096557; see QA History) |
| Third top-up coverage session | ✅ Complete 2026-07-20 (no new SKU; 1 reroute to existing SKU-096513; see QA History) |
| GMV Coverage | 98.38% product-level GWP-zeroed (month 2026-06), up from 98.18% |
| Last run | 2026-07-20 (third top-up session) |
| Current MAX taxonomy_id (registry floor at session start) | SKU-096557 (third top-up session made no new taxonomy entries — see QA History) |

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
| SKU-093462–094397 | Pass 1 OFFICIAL (936 entries, allowlist-scoped) — within the original 2000-slot claim |
| SKU-094398–096475 | Pass 2 RESELLER (2060 entries after dedup, text-match routed/created) — spills into a supplemental 1500-slot claim (095462–096961) after the original block filled; 18 IDs in this range were deleted as duplicates, see QA History |
| SKU-096476–096540 | Top-up coverage session (2026-07-20), 65 new entries — consumed from the remainder below |
| SKU-096541–096557 | Second top-up coverage session (2026-07-20), 17 new entries — consumed from the remainder below |
| SKU-096558–096961 | Remaining unused remainder of the supplemental block — still `ACTIVE`, safe to reuse for a future QA/gap-fill pass on this category. Third top-up session (2026-07-20) claimed none of it — the resolvable work that session found needed no new taxonomy entries |

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
| 2026-07-20 | Pass 1 | `Unicharm Pet Official Store`'s sole listing is a dog diaper (Unicharm MannerWear), confirmed via image | Excluded — the store is a genuine NIQ mis-categorization, not part of the Pass 1 allowlist |
| 2026-07-20 | Pass 1 | `GIT Prime Official Shop` confirmed via image as a MAKUKU-exclusive authorized distributor | Kept in the allowlist as MAKUKU |
| 2026-07-20 | Pass 1 | Discovered new brands not previously in `brand_dict`: FITTI (sold through Unicharm-family stores despite being unrelated), Baby Happy (Wings), Fluffy, MomBaby (sold through Pokana stores), Happy Nappy (sold through Sweety Official Shop), Goo.N (already existed as `BRD-GLOBAL-00093`, initially mis-created a duplicate then removed) | Created `BRD-ID-08592`–`08597` in `brand_dict` (Fluffy, Baby Happy, MomBaby, Happy Nappy, FITTI); reused existing `BRD-GLOBAL-00093` for Goo.N |
| 2026-07-20 | Pass 1 | Regex bug: sku_names like `"Fluffy ... L96 - L32 x 3 Pack"` state the true total (96) then redundantly restate the per-bag breakdown (32 × 3) — naive parsing double-counted to 288 | Fixed with a redundant-total-restatement guard (8 Fluffy entries corrected) |
| 2026-07-20 | Pass 1 | Fluffy and Baby Happy packaging/sku_names carry no distinguishable sub-line name beyond the brand itself (confirmed via image for Fluffy) | `product_line = NULL` by design for these two brands — Tier B per quality-standards.md §3 (D1), not a parsing gap |
| 2026-07-20 | Pass 2 | 20,746 raw CREATE candidates collapsed to 2,078 distinct `(brand, line, variant, type, size, pack_count)` keys once deduplicated — the raw count would have been extreme over-fragmentation | Grouped before minting; 42% of the 2,078 are singleton-product entries but only ~8% of Pass-2-create GMV, consistent with genuine reseller long-tail variety |
| 2026-07-20 | Pass 2 | Some multi-size reseller listings (e.g. `"Mamy Poko Pants X-tra Kering NB40 S38 M32 L28 XL26 XXL24"`, buyer picks one) were parsed to a single (first-matched) size rather than `is_multi_size=TRUE` | Known simplification — product_taxonomy_map is 1 row per product_id, GMV on these specific listings is negligible-to-zero in the sample checked; flagged here rather than fixed, since fixing would need a second full multi-size-detection pass for low expected GMV payoff |
| 2026-07-20 | Post-Pass-2 self-check | Pass 2's reuse-key check omitted `type` (pants/tape) from the lookup, and a same-key overwrite bug in the type index meant 18 Pass-2 entries were exact-spec duplicates of existing Pass-1 entries rather than reusing them | Merged: rerouted the 18 duplicate SKUs' `product_taxonomy_map` rows to the original (lower) `taxonomy_id`, deleted the duplicate `product_taxonomy` rows. G1 (dual-mapped) confirmed 0 both before and after — no product lost its mapping |
| 2026-07-20 | Post-Pass-2 self-check | Spot-checked the top-40-by-GMV products still unmapped after Pass 2 (advisor-suggested check, since the Pass 2 pull used a brand-keyword filter that STEP 5 forbids as an *extraction* gate — it's meant only for *routing*). Findings: (a) most are genuinely brand-unidentifiable "repack"/"non kemasan" (no-packaging, rebranded) resellers — correctly out of scope; (b) a real long tail of brands below the 95% threshold even by their true identity (Kinto, Hanuka, Runbeier — all confirmed in the Brand Scope raw ranking below rank 12); (c) a meaningful chunk (e.g. `"[TOKO MANUR]...MERRIES..."`, `"...MAKUKU..."`, `"...BABY HAPPY..."`, `"MAMYPOKO 1 KARTON..."`) ARE in-scope-brand listings that the regex pull did catch, but the size/pack parser failed on them — bulk multi-pack descriptors (`KARTON`, `BALL`) with no explicit size letter, and Indonesian size words (`Ukuran Besar/Sedang/Kecil` = Large/Medium/Small) my regex doesn't recognize. These are already counted in the 1,950-product/6.66B-IDR `UNRESOLVED_NO_SPEC` bucket above, not a *new* gap — confirms the 91.93% coverage number is honest, not inflated by a silent keyword-filter exclusion | Documented as the Pass 2 known-limitation list below; not fixed this session (would need Indonesian size-word support + bulk-pack-without-size handling, real but bounded follow-up work) |
| 2026-07-20 | Top-up session, STEP 0 | The prompt's STEP 0 worklist query (`QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id, model_id ...)`) dedups at *model* grain, not *product* grain, and ranks/thresholds on per-model `gmv_monthly` rather than `SUM(gmv_monthly) GROUP BY product_id` as ARCHITECTURE.md and quality-standards.md §2 Rule A require. This produced 1,208 "rows" for what was actually only 406 distinct `product_id`s (model-level fan-out), and the 95%-cumulative-GMV threshold was computed on the wrong grain. Confirmed with advisor before proceeding | Rewrote STEP 0 with `GROUP BY product_id` (SUM GWP-zeroed GMV, `ANY_VALUE` for descriptive columns) before applying the cumulative-95% filter. The corrected live worklist was **314 distinct products** (not 1,208), 15.94B IDR GWP-zeroed GMV. All further work in this session used the corrected 314-row worklist |
| 2026-07-20 | Top-up session, classification | Built a bulk text/pattern classifier over the 314-product worklist rather than reading every image: detected brand via literal-token regex (both the 11 documented brand families and 9 previously-undocumented-but-identifiable reseller brands — Mamycare, Mamamia, Sensi, Pokky, Pookio, Runbeier, Kinto, Midday Bear, Hanuka — since `docs/llm-extraction-rules.md` §8 forbids a brand-family pre-filter from gating *extraction*, only routing), then product_line/type/size/pack_count via regex against sku_name text, cross-checked against existing taxonomy for reuse-before-mint. 14 swim-diaper listings (`renang`/`swim` — a different product type, not a documented category exclusion but a straightforward TYPE-gate call) were excluded as out-of-category. One early regex bug (`x-?tra\s*kering` matching inside "Extra" via substring, and bare `S`/`M`/`L` matching inside words like "PANTS") produced false brand/size positives; fixed with explicit word-boundary anchoring before finalizing | 202 of 314 products classified with a brand; 94 had no identifiable brand at all (generic "repack"/"non kemasan" reseller stock — legitimately `UNRESOLVED` per `docs/product-lifecycle.md` §5); 14 excluded as swim diapers (OOS type); 4 ambiguous multi-brand-token listings resolved individually (see below) |
| 2026-07-20 | Top-up session, price sanity check | Before writing, sanity-checked every parsed `pack_count` by computing implied price-per-piece (`gmv_zeroed / sold_monthly / pack_count`) — flagged anything above ~10,000 IDR/piece as implausible for a diaper. Caught two real bugs this way: (a) bare bag/ball/karton counts (e.g. "3 BAL") were briefly being written directly as `pack_count` even though they represent *number of bags*, not total pieces, silently understating reality by an order of magnitude; (b) several highest-GMV single-size items had no pack signal in text at all. Read product images directly (per this session's own extraction, not a subprocess) for the top 5 by GMV to resolve: `Sweety Bronze Dry X-Pert Pants Ukuran Besar` → confirmed L, 38 pcs/bag, no bag multiplier (was defaulting to pack_count=1); `POPOK BABY HAPPY PANTS 3 BAL` → confirmed M, 32 pcs/bag × 3 bags = 96; `BABY HAPPY FIT PANTS 3 & 2 BAL` and `Popok Bayi Fitti Pants 2ball` → images showed multiple distinct sizes stacked/collaged, genuinely ambiguous which size ships → routed to `is_multi_size=TRUE` catch-all instead of guessing; `SENSI NIGHT PANTS XXXXL20+2 BOY` → image confirmed the text-parsed 20+2=22 was already correct | Fixed the bag-vs-piece-count conflation in the parser (bag/ball/karton counts are never used alone as `pack_count`); 2 of the 5 top-GMV ambiguous items got precise single-size entries after image confirmation, 2 were correctly downgraded to `is_multi_size=TRUE`, 1 was already correct |
| 2026-07-20 | Top-up session, writes | Reused the documented unused remainder of the existing `full_rebuild_pass2_supplemental` SKU block (`SKU-096476–096961`, still `ACTIVE` per this file's own SKU Blocks Assigned table) rather than claiming a new block — verified 0 existing rows in that sub-range via BQ immediately before writing, per the atomic-claim discipline. Created 9 new `brand_dict` entries (`BRD-ID-08608`–`08616`: Hanuka, Kinto, Mamamia, Mamycare, Midday Bear, Pokky, Pookio, Runbeier, Sensi — reused existing `BRD-GLOBAL-01046` for Company Love, already in `brand_dict`), 65 new `product_taxonomy` entries (`SKU-096476`–`SKU-096540`, 61 `is_multi_size=TRUE` catch-alls + 4 precise single-size/pack entries), and 206 `product_taxonomy_map` rows (205 to the new entries + 1 reused an existing entry) via `bq query` DML, `meta_agent='CLAUDE_CODE'`, `source='LLM'`, `platform='Shopee'`, `country='ID'` on every row | GMV coverage rose from 91.93% to 96.85% (product-level, GWP-zeroed, month 2026-06). All 4 QA gates (G1 dual-mapped, G2 HUMAN+LLM coexistence, placeholder-leak, G5 provenance) passed at 0, and the structured-fields-missing check came in at 35% (below the 50% fail threshold) |
| 2026-07-20 | Top-up session, honest gap remaining | 108 of the 314-product worklist remain unmapped: 94 products (4.82B IDR) are genuinely brand-unidentifiable generic "repack"/"non kemasan" reseller stock with no brand signal in text at all — left `UNRESOLVED` per `docs/product-lifecycle.md` §5, consistent with this category's established Pass 2 precedent; 14 products (302M IDR) are swim diapers, a different product type, excluded via the type gate. Both are legitimate `UNRESOLVED` outcomes, not a coverage shortfall this session should have closed | Not fixed — no brand signal exists in text to resolve the 94, and the 14 are out-of-category by type. A future session could try to identify the 94 via image reads (batched by merchant_name/sku_name pattern) if a decision is made that this GMV is worth per-image spend |
| 2026-07-20 | Second top-up session, STEP 0 correction | The wrapper's live pre-check reported 517 unmapped products against the 95%-cumulative-GMV threshold. Re-ran the worklist query from scratch per this session's brief rather than trusting that number. The prompt's own supplied STEP 0 SQL had the **same model-grain bug already documented above** (`QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id, model_id ...)` and cumulative-GMV computed on per-model `gmv_monthly` instead of `SUM(gmv_monthly) GROUP BY product_id`). Rewrote it with `GROUP BY product_id` (SUM GWP-zeroed GMV) before applying the cumulative-95% filter, matching the fix already applied in the prior top-up session | Corrected live worklist was **108 distinct products**, 5.12B IDR GWP-zeroed GMV — not 517. This turned out to be exactly the same 108-product residual gap the prior top-up session had already investigated and left `UNRESOLVED` that same day (94 no-brand-signal + 14 swim diapers) |
| 2026-07-20 | Second top-up session, re-investigation of the "unidentifiable" 94 | Re-examined the 94 products the prior session left `UNRESOLVED` as "genuinely brand-unidentifiable." Text-keyword classification against the documented 11-brand scope was too narrow: it missed real brands outside that list entirely (the 11-brand scope was built from *brand-level* 95% cumulative GMV for Pass 1/2 targeting, but `docs/quality-standards.md` §2 Rule A scope is *product-level* GMV — a smaller brand's single high-GMV listing can still be in scope). Broadened classification found 9 previously-unlisted real brands with a Shopee Mall or clearly-branded presence (Cottons Baby Diapers, Berries, Popoku, HOGO, Med+, Yori & Co, K-Mom, Sayangku, Pampy, Doubaocool, LALAKU — 11 total incl. duplicates of pattern). Also caught: `RoyalSoft`/`BABBY HAPPY` (typo) tokens that existing regexes missed due to concatenation/misspelling, `Bronze Dry X-pert` as a Sweety sub-line already known from this same day's price-sanity check, and `Moko Moko` (an existing but previously unused `brand_dict` entry, `BRD-ID-02867`). Per `docs/llm-extraction-rules.md` §8, this matters most for "high-GMV Mall-seller listings that are genuinely miscategorized" — several of the newly-found brands were exactly that (Mall-badged, real brand, just outside the old keyword list) | Read images for the top-GMV items in each remaining ambiguous bucket (34 of 40 "no signal" text-classified items) rather than trusting title text alone — text proved unreliable even within a single reseller: `RYUGA.STORE.ID` sold Sweety-branded stock under one generic "repack" title and MamyPoko-branded stock under a near-identical title. Confirmed via image: the large majority of generic "repack"/"non kemasan" titles are actually **Sweety** (already brand_dict-known) stock with branding stripped from the *title* but still visible on the *package* — text pre-filtering alone would have permanently misclassified ~3.3B IDR of Sweety GMV as unidentifiable |
| 2026-07-20 | Second top-up session, writes | Reused the documented unused remainder of the `full_rebuild_pass2_supplemental` SKU block (`SKU-096541–096961`, still `ACTIVE`) — verified 0 existing rows in the target sub-range via BQ immediately before writing. Created 11 new `brand_dict` entries (`BRD-ID-08617`–`08627`: Cottons Baby Diapers, Berries, Popoku, HOGO, Med+, Yori & Co, K-Mom, Sayangku, Pampy, Doubaocool, LALAKU), 17 new `product_taxonomy` entries (`SKU-096541`–`SKU-096557`: 15 `is_multi_size=TRUE` catch-alls + 2 precise single-size/pack entries — `Pampy Premium XXL Pants x30`, `Mamypoko Standard M Pants x50`), and heavily reused existing catch-all entries from the prior same-day session (`Sweety Pants Multiple Sizes`, `Sweety Multiple Sizes`, `Sweety NB-S Tape x50`, `Sweety M Pants x20`, `Sweety Bronze Dry X-pert Multiple Sizes`, `Runbeier Multiple Sizes`, `Baby Happy Multiple Sizes`, `Mamypoko Royal Soft Multiple Sizes`). 76 new `product_taxonomy_map` rows written via `bq query` DML, `meta_agent='CLAUDE_CODE'`, `source='LLM'`, `platform='Shopee'`, `country='ID'` on every row. Zero pre-existing map rows for any of the 76 target product_ids, confirmed before insert (no G1 risk) | GMV coverage rose from 96.85% to 98.18% (product-level, GWP-zeroed, month 2026-06). All QA gates (G1 dual-mapped, G2 HUMAN+LLM coexistence, G7 placeholder-leak, G5 provenance) passed at 0; structured-fields-missing check at 35% (below the 50% fail threshold) |
| 2026-07-20 | Second top-up session, honest gap remaining | 16 of the 108-product worklist remain genuinely unmapped (~350M IDR): 10 products have no brand signal on package or in text even after image review (plain unbranded/generic repack stock); 4 products show a random mixed-brand assortment in the product image itself (e.g. one repack SKU visibly containing a mix of Sweety, Happy Nappy, and Huggies units) — cannot be assigned a single `taxonomy_id`, left `UNRESOLVED` per `docs/product-lifecycle.md` §5 (equivalent to the documented "buyer-choice multi-brand → leave NULL" precedent from `th_softdrink`); 1 product (`Lifree`, Yanni688 store) is a genuine NIQ mis-categorization — confirmed via image to be an **adult** incontinence product (waist-sized L, 90–131cm), out of scope per this category's own scope table (belongs in `shopee_id_adult_diapers`). Separately, 16 products (14 swim diapers + 2 underpads/`alas ompol`) are out-of-category by type, excluded via the type gate, not a brand gap | Not fixed — no brand signal exists to resolve the 10 no-signal items or disambiguate the 4 mixed-brand-assortment items; the Lifree and swim/underpad items are correctly out of category and were left unmapped rather than force-fit |
| 2026-07-20 | Third top-up session, STEP 0 correction | The wrapper's live pre-check reported 237 unmapped products against the 95%-cumulative-GMV threshold. Re-ran the worklist query from scratch rather than trusting that number, per this session's brief. **The prompt's own supplied STEP 0 SQL had the exact same model-grain fan-out bug documented twice already in this file** (`QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id, model_id ...)`, cumulative-GMV computed on per-model `gmv_monthly` instead of `SUM(gmv_monthly) GROUP BY product_id`) — confirmed by running the as-supplied query verbatim: 237 rows collapsed to only 135 distinct `product_id`s. Rewrote with `GROUP BY product_id` (SUM GWP-zeroed GMV, `ANY_VALUE` for descriptive columns) before applying the cumulative-95% filter, matching the fix already applied in both prior top-up sessions this same day. **Note for future sessions: this wrapper bug has now recurred three times against this exact category — worth fixing at the wrapper/prompt-template level, not re-discovering per session.** Also hit a known `bq --format=csv` corruption: the source table's `image` column contains literal embedded double-quotes that break naive CSV row-splitting (documented in `docs/headless-runbook.md`) — excluding `image` from the worklist SELECT and fetching it separately per-product_id avoided the corruption | Corrected live worklist was **32 distinct products**, 2.209B IDR GWP-zeroed GMV |
| 2026-07-20 | Third top-up session, worklist reconciliation | Bucketed the corrected 32-product worklist by pattern: 14 swim diapers (`renang`/`swim` keyword, 301.6M IDR), 2 underpads (`underpad`/`alas ompol`, 22.7M IDR), 1 Lifree/Yanni688 (21.4M IDR), 15 "other" generic-brand/repack listings (1.863B IDR). Cross-referencing against the Second top-up session's QA History entries above, this 32-product set is **the exact same residual** that session already investigated and left `UNRESOLVED`/out-of-category that same day (14 swim + 2 underpad + 1 Lifree + 15 no-signal/mixed-brand ≈ its documented "16 unmapped + 16 out-of-category" = 32) — re-surfaced by the wrapper's live pre-check only because those products still correctly have `taxonomy_id IS NULL`, not because anything changed | Re-verified rather than assumed stale: independently read the product image (not reusing any assumption from the prior session's prose) for all 15 "other" products via `curl` + `Read` per `docs/headless-runbook.md`'s image-fetch pattern (images were already present in `/tmp/diaper_imgs/` on this host from the same-day prior session, reused directly rather than re-downloaded) |
| 2026-07-20 | Third top-up session, per-product image findings | Of the 15 "other" products: `42850156681` (SINAR TERATAI, 356M IDR, `brand_raw="Sweety"`) — image is a promotional banner explicitly showing Sweety Baby Pants + Happy Nappy + Huggies logos together → confirmed mixed-brand repack, NULL correct despite the seller's brand field. `24155095154` (MoonLight Baby Shop, 27M IDR, `brand_raw="Sweety"`) — image is a 5-brand "Newborn Series" buyer-choice comparison graphic (Happy Nappy, MamyPoko, 2× Sweety lines, MAKUKU) → buyer-choice multi-brand, NULL correct (same precedent as `th_softdrink`'s multi-brand-listing rule). The remaining 12 (`29872308538`, `29622346080`, `43758533384`, `41311637318`, `27238859342`, `50656417873`, `20671847659`, `24810023589`, `19378105654`, `17099068056`, `41228358960`, `29276896730`) show either no legible brand mark at all or a visibly mixed pile of different products/patterns in the photo — genuinely unidentifiable, NULL correct. **One exception found and fixed: `26437769434`** (POJOK POPOK TERJANGKAU, 453M IDR, `brand_raw="Sweety"`) — image is the same generic "Diapers Best Seller / Popok Anak Repack Termurah" stock template also used by `50656417873` (RYUGA, `brand_raw="-"`), i.e. *uninformative*, not contradictory. Per `docs/llm-extraction-rules.md` §2/§6, an uninformative image doesn't override a real text/field-level brand signal — and `brand_raw="Sweety"` here is a seller-entered field value, not a title-text guess. Advisor-flagged before finalizing as "0 writes" — correctly caught that this one product was being folded into the blanket-NULL bucket without being distinguished from the confirmed-mixed-brand cases | Verified zero pre-existing `product_taxonomy_map` row for `26437769434` (G1 safe), then inserted one row routing it to the existing `SKU-096513` ("Sweety Multiple Sizes", `is_multi_size=TRUE` catch-all created by the second top-up session for this exact generic-repack pattern) — `source='LLM'`, `confidence='0.70'`, `meta_agent='CLAUDE_CODE'`, `platform='Shopee'`, `country='ID'`. No new SKU minted, no SKU block claimed (STEP 2 skipped — see below) |
| 2026-07-20 | Third top-up session, STEP 2 deviation | Did not claim the prompt's specified 237-slot SKU block. The premise (237 unmapped products) was stale per the STEP 0 correction above, and the actual resolvable work (1 product, routed to an existing entry) needed zero new taxonomy entries. Claiming and leaving an unused 237-slot block would only create registry noise | No block claimed; `SKU-096558–096961` (documented in the SKU Blocks table below) remains the `ACTIVE`, unused reusable range for any future session in this category |
| 2026-07-20 | Third top-up session, QA gates + coverage | Ran all `docs/headless-runbook.md` QA-gate-as-code checks **without** `--skip-coexistence` (coexistence is a genuine bug at this stage, category already shipped): G1 dual-mapped (LLM-scoped) = 0, G1 dual-mapped (unscoped) = 0, G2 HUMAN+LLM coexistence = 0, placeholder-leak = 0, G5 provenance = 0, structured-fields-missing = 35% (below the 50% fail threshold, consistent with prior sessions). GMV coverage rose from 98.18% to **98.38%** (product-level, GWP-zeroed, month 2026-06) | All gates pass; universe refresh intentionally **not** run this session — that is a separate, independently-triggered step per this session's brief |
| 2026-07-20 | Third top-up session, honest gap remaining | 31 of the 32-product corrected worklist remain unmapped, unchanged from the Second top-up session's already-documented conclusion: 14 swim diapers + 2 underpads (out-of-category by type), 1 Lifree (NIQ mis-categorization, adult product), 14 generic-brand/mixed-brand-assortment products with no reliable single-brand signal even after fresh independent image review. This is very likely at or near this category's practical ceiling given current signal availability — a future session would need either a different data source (e.g. actual package-level OCR/zoom) or a policy decision to accept lower-confidence guesses on the mixed-pile resellers to move this further | Not fixed — no new information available to resolve the remaining 31; recommend the wrapper's STEP 0 SQL template be corrected at the source so this model-grain bug stops recurring across categories, not just this one |

---

## Targeted QA Fix Brief

> Scope: quality-standard violations on products that **already have** a `taxonomy_id`. Not applicable
> yet — this is the first extraction pass for this category.

---

## Scripts

Not applicable — this category is extracted directly by a Claude Code session (multimodal reading),
not via `pipeline/05_product_taxonomy/llm_{table}/*.py` scripts.

---

## Map Row Counts (as of last run, month 2026-06)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 34,185 (1,674 Pass 1 + 32,511 Pass 2) | 2,996 new `product_taxonomy` entries (936 Pass 1 + 2,060 Pass 2 after dedup — 18 Pass 2 entries were exact-spec duplicates of Pass 1 entries, since the reuse-key check didn't include type; merged post-hoc, map rows rerouted to the earlier SKU, no product lost its mapping) |
| HUMAN | 0 | No prior keyword seed existed for this table |
| NULL (unmapped) | 6,280 products / ~17.6B IDR GMV within the brand-identifiable pool, plus the long tail outside the 11-brand 95% scope | See breakdown below |

**GMV coverage: 91.93%** (202.15B / 219.90B IDR, GWP-zeroed, month 2026-06) — exceeds the ≥85% LLM Pass 2 and ≥90% NULL-coverage-pass targets in `docs/quality-standards.md` §6.

**Unmapped breakdown (Pass 2 candidate pool of 34,508 brand-identifiable products):**
- 1,950 products (6.66B IDR) — brand identified but size/pack/type not confidently parseable from text; left `UNRESOLVED` per `docs/product-lifecycle.md` §5 rather than guessed.
- 47 products (1.7M IDR) — brand keyword matched a false positive or ambiguous context; left `UNRESOLVED`.
- The remaining unmapped pool (`master_clean_niq` products with no brand-family keyword match at all) is long-tail out-of-scope per `docs/quality-standards.md` §2 (outside both Rule A top-95%-GMV and Rule B official-store) and legitimately stays `UNRESOLVED` — dominated by the raw `(UNDEFINED/BLANK)`/`"-"` bucket documented in Brand Scope above.
- 21 Pass-1 official-store listings were excluded as genuine out-of-category items (dog diapers, wipes, pantyliners, promotional non-diaper gimmicks, one adult-diaper cross-bundle) — see QA History.
