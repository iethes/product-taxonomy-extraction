# shopee_sg_infant_milk — Category Context

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete |
| LLM Pass 2 | ✅ Complete |
| GMV Coverage | 97.32% (2026-06) |
| Last run | 2026-07-29 (top-up) |
| Current MAX taxonomy_id | Query BQ live — never trust this file (was SKU-215250 at end of this run) |

**Prior state note:** `docs/categories/STATUS.md` line 67 labeled this category "⏳ Keyword only," but a
live check on 2026-07-29 found **zero** `product_taxonomy_map` rows of any source (HUMAN or LLM) for
`shopee_sg_infant_milk`. This is consistent with the category simply never having been reached by any
extraction pass yet — several other SG categories with the same stale "Keyword only" label were found live
to already hold thousands of LLM-source rows (full extractions that ran without STATUS.md being updated),
so the label itself carries no reliable signal either way. Separately, this session also confirmed that
**zero `HUMAN`-source rows exist anywhere in the entire `product_taxonomy_map` table**, across all 31
`master_table`s that currently hold any data — the keyword-seed layer is gone pipeline-wide, not just for
TH categories as previously documented (see the `project-th-baby-diapers-data-loss` memory). The SG
keyword-seed SKU dictionary block (`SKU-002360–003219` per `docs/categories/STATUS.md`'s SKU Block
Registry) also has zero surviving `product_taxonomy` entries. This is a real, repo-wide finding worth
escalating separately — it is not treated as a blocker for this session because there are no surviving
map rows for *this* table to orphan or duplicate against (the specific hazard the memory warns about).

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-211207–213206 | Claimed block (2000 slots), full_rebuild |
| SKU-211207–211567 | Pass 1 official-store extraction (361 entries, 407 map rows, 9 merchants) |
| SKU-211568–211598 | Pass 1 continuation: Enfagrow A+ / Enfamil Official Store (31 entries, 43 map rows) — this merchant name has a trailing space in the source data (`'Enfagrow A+ Official Store '`) that caused it to be silently missed by the initial exact-match allowlist query; caught and backfilled during Pass 2 triage |
| SKU-211599–211748 | Pass 2 bulk reseller routing (150 new entries; 72 more products reused existing Pass 1/1b entries via text match) |
| SKU-211749–213206 | Unused remainder of claimed block |
| SKU-215207–215406 | Top-up 2026-07-29 claimed block (200 slots, registry scenario `taxonomy_topup`) |
| SKU-215207–215250 | Top-up: 44 new entries covering 46 products (2 entries each cover 2 products with matching brand+line+size) |
| SKU-215251–215406 | Unused remainder of top-up block |

---

## Brand Scope (GMV threshold 95%, month 2026-06-01)

Computed from `master_clean_niq.shopee_sg_infant_milk`, GWP-zeroed
(`CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END`), brand resolved via
`product_brand_map` on the composite key `(product_id, platform='Shopee', country='SG')` — not
`master_table`, per ADR-006. 100 distinct brand buckets (incl. `BRD-UNDEFINED`) have any GMV this month;
the real 95% cumulative-GMV threshold is reached at 18 brands (not a fixed top-15/20 snapshot):

1. **Nestle** — `BRD-GLOBAL-00059` — 17.1% cum.
2. **Similac** — `BRD-GLOBAL-00679` — 29.4% cum.
3. **Enfagrow** — `BRD-GLOBAL-00030` — 41.1% cum.
4. **PediaSure** — `BRD-GLOBAL-00738` — 49.8% cum.
5. **Aptamil** — `BRD-GLOBAL-00581` — 57.1% cum.
6. **Nature One Dairy** — `BRD-SG-00631` — 61.5% cum.
7. **Dumex** — `BRD-GLOBAL-00040` — 65.7% cum.
8. **Nan** — `BRD-GLOBAL-00969` — 69.8% cum.
9. **Grow** — `BRD-SG-00661` — 73.7% cum.
10. **Bellamy's Organic** — `BRD-SG-00509` — 77.4% cum.
11. **Kendamil** — `BRD-SG-00644` — 81.1% cum.
12. **Enfamil** — `BRD-SG-01010` — 84.6% cum.
13. **Wyeth Nutrition** — `BRD-GLOBAL-01021` — 87.6% cum.
14. **Friso** — `BRD-SG-00615` — 90.3% cum.
15. **Karihome** — `BRD-SG-00908` — 92.6% cum.
16. **Isomil** — `BRD-SG-01181` — 93.9% cum.
17. **Abbott** — `BRD-GLOBAL-00056` — 94.8% cum.
18. **S-26** — `BRD-GLOBAL-00009` — 95.6% cum. (threshold crossed here)

Brands excluded from scope (long tail beyond 95%, ~82 remaining brand buckets including `BRD-UNDEFINED` at
96.2% cum.): not individually listed — long tail, low GMV, may remain `UNRESOLVED` per docs/quality-standards.md §2.
Note `BRD-UNDEFINED` itself sits just outside the 95% brand-scope threshold (96.2% cum.) — its individual
products can still fall inside the *product-level* Rule A in-scope set and must still be considered per
docs/quality-standards.md §2, brand-scope ≠ product-scope.

---

## Official Store Allowlist (Pass 1)

Built by querying distinct `merchant_name WHERE merchant_badge='Shopee Mall'` per in-scope brand_id
(composite-key join), month 2026-06-01.

| Brand | brand_id | Official Store Merchant Name | Products |
|-------|----------|------------------------------|----------|
| Enfagrow, Enfamil | BRD-GLOBAL-00030, BRD-SG-01010 | `Enfagrow A+ Official Store` | shared store |
| Dumex, Aptamil | BRD-GLOBAL-00040, BRD-GLOBAL-00581 | `aptamildumex.official` | 120 (parent/Danone store) |
| Similac, PediaSure, Grow, Isomil | BRD-GLOBAL-00679, BRD-GLOBAL-00738, BRD-SG-00661, BRD-SG-01181 | `Abbott's Nutrition Official Store` | 120 (parent/Abbott store) |
| Nestle, Nan | BRD-GLOBAL-00059, BRD-GLOBAL-00969 | `Nestlé Infant Nutrition Official Store` | 63 |
| Nestle | BRD-GLOBAL-00059 | `Nestle Health Science Official SG` | 5 (secondary Nestle storefront) |
| Wyeth Nutrition | BRD-GLOBAL-01021 | `Wyeth Nutrition  Official Store` (note: double space in the live merchant_name string) | 27 |
| Friso | BRD-SG-00615 | `Friso Official Store` | 28 |
| Nature One Dairy | BRD-SG-00631 | `Nature One Dairy Official Store` | 22 |
| Bellamy's Organic | BRD-SG-00509 | `Bellamy's Organic Official Store` | 12 |
| Kendamil | BRD-SG-00644 | `Kendamil Official Store` | 12 |

**Total allowlist scope: ~409 distinct products** (of 580 total Mall-badged products in the table this month
— see Scale below; the allowlist is a subset, not the full Mall pool).

**Parent-company stores (Pass-1-eligible for all brands they carry):**
- `aptamildumex.official` — Danone; carries both Dumex and Aptamil.
- `Abbott's Nutrition Official Store` — Abbott; carries Similac, PediaSure, Grow, and Isomil (all
  Abbott-owned sub-brands). Plain `Abbott` (`BRD-GLOBAL-00056`) had no distinct product volume under this
  store as of this run (only 1 product, at a non-official reseller — see exclusions) but is conceptually
  covered by the same parent umbrella if Abbott-labeled products appear later.

**Excluded — multi-brand retailers (per docs/llm-extraction-rules.md §4, Baby vertical):**
- `Watsons Singapore Official Store` — multi-brand pharmacy retailer (same pattern as Watsons in the
  Beauty exclusion list).
- `Guardian SG Official Store` — multi-brand pharmacy retailer, SG equivalent of Boots/Watsons for this
  vertical.
- `myCK_online` — general reseller, Mall-badged but appears across Enfagrow/Nestle/Wyeth/Grow/Enfamil
  listings; not a brand-owned store.
- `JAWStore - Puritan's Pride` — another brand's own store reselling Nestle products; not Nestle-owned.
- `joeyho187`, `nguyenlen.sg`, `huangzhongbo003.sg` — single-product, unverified Mall-badged sellers with
  no recognizable brand-official naming; excluded as unverified.

**Brands with no official store (Pass 2 only):**
- Karihome (`BRD-SG-00908`) — no brand-named Mall store found for this month.
- S-26 (`BRD-GLOBAL-00009`) — no brand-named Mall store found for this month.

---

## Scale

| Metric | Value |
|--------|-------|
| Total source rows (`master_clean_niq.shopee_sg_infant_milk`, all months) | 308,340 |
| Distinct products, all months | 5,108 |
| Distinct products, month 2026-06-01 | 4,208 |
| Total Mall-badged (`merchant_badge='Shopee Mall'`) products, month 2026-06-01 | 580 |
| Official Store Allowlist products (subset of the 580 above) | ~409 |

The full Mall-badged pool (580) is not itself large enough to require special handling, but Pass 1 must
still scope strictly to the allowlist merchant names above, not the full Mall-badged pool — the excluded
multi-brand retailers above are all Mall-badged and would otherwise leak in.

---

## Existing map rows (Step 1, live check 2026-07-29)

| Source | Count |
|--------|-------|
| LLM | 0 |
| HUMAN | 0 |
| Total | 0 |

Genuinely a first pass — no prior map rows of either source exist for this table.

---

## Scope — What's In vs Out

**In scope:**
- Infant formula milk powder (all stages: 0-6mo, 6-12mo, 1-3yr / stage 1-4 numbering varies by brand)
- Follow-on / growing-up milk powder marketed for infants/toddlers under the same brand lines above
- Ready-to-feed liquid infant formula, if present under these brands

**Out of scope (leave NULL):**
- Adult/general nutrition products from the same parent companies (e.g. generic Abbott/Nestle adult
  supplement lines) that are not infant/toddler formula
- Feeding equipment (bottles, sterilizers, breast pumps) if present in this source table under these
  merchants — not a milk product
- Products from brands entirely outside the 95%-cumulative-GMV brand scope AND not sold via an official
  store — long tail, may remain `UNRESOLVED`

**Edge cases:**
- RTD (ready-to-drink) GROW cartons: base unit is 180ml; a `[Bundle of N]` prefix in `sku_name` is a
  bundle-of-(4-carton-base-pack), i.e. real `pack_count = N*4`, confirmed against the image's `x{total}`
  badge — text alone would have undercounted 4x. Confirmed via direct image read on several listings.
  Products with no bundle text at all in the title still pictured 4 cartons (pack_count=4) — text was
  silent, image was not.
- `[Bundle of N]`/`(Bundle of N)` sometimes conflicts with an inline `SIZE x M` fragment in the same title
  (e.g. `[Bundle of 4] ... 900g x3 + Timmy & Tammy Books`) — the bracketed `[Bundle of N]` count was trusted
  over the inline fragment, consistent with the `shopee_th_moisturizer_for_body` bracket-format precedent in
  llm-extraction-rules.md §1.
- GWP text patterns (`[GWP]`, `+ Free {other item}`, `GWP Bundle of N [GWP] {product}`) almost always wrap a
  genuine, real-product listing (the free item is a toy/appliance bonus, not a different milk product) —
  these were extracted normally at the stated pack_count, not treated as GWP-flagged/zeroed products.
- `[NOT FOR SALE]` / `[NWP]` tagged listings (all 0 GMV) were still mapped to the same real product/size
  when parseable — these are catalog placeholder listings for a genuine product, not out-of-category.
- One listing (`56208107207`) was a Tefal cookware GWP set with no milk product at all — excluded from the
  taxonomy entirely (wrong category, not an infant-milk listing despite appearing in this source table).
- Multi-stage-selector reseller titles (e.g. `Stage 3/4`, `Friso Gold Stage 3 / Stage 4`, `S26 ... Progress
  (Stage 3) & Promise (Stage 4)`) were routed to a stage-agnostic `is_multi_variant=TRUE` catch-all rather
  than guessing which stage the buyer actually receives.
- ~20 long-tail brands (Dutch Lady, WAKODO, Meiji, HiPP, Lactogrow, Spring Sheep NZ, etc.) fall inside the
  95%-cumulative-GMV **product**-level scope (Rule A) despite being well outside the top-18 **brand**-level
  95% scope used for the official-store allowlist — expected per quality-standards.md §2 (Rule A is
  product-level, independent of brand-level scope). These got `"{Brand} (unresolved)"` product_line
  catch-alls (real brand, unconfirmed line) rather than a guessed line name.
- `product_brand_map` had one row with `brand_id='BRD-UNDEFINED'` for a real, identifiable brand (Spring
  Sheep, New Zealand sheep-milk formula) not yet in `brand_dict` — used the real brand name in
  `canonical_name` rather than literally writing "Undefined" (which would have tripped the
  placeholder-leak QA gate).

---

## Taxonomy Design Notes

**Product line extraction approach:**
- Extract stage/number (e.g. "Stage 1", "Step 2", "3") and formula line name (e.g. "Optipro", "Gain
  IQ", "A+ 4") directly from sku_name/image — never collapse to generic "Infant Formula" / "Milk Powder".
- Parent-store products (aptamildumex.official, Abbott's Nutrition Official Store, Nestlé Infant Nutrition
  Official Store) require `brand_from_image` disambiguation since one store carries multiple brands.

**Size extraction notes:**
- Primary unit: g / kg for powder, ml for ready-to-feed liquid.
- Multi-tin bulk packs common in this category (e.g. "x3", "Twin Pack") — apply standard pack_count rules
  from docs/llm-extraction-rules.md §1 (image is the tiebreaker).

**Known difficult products:**
- To be logged here as encountered during Pass 1/Pass 2.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-29 | Pre-run | STATUS.md "Keyword only" label found stale/unreliable; live map rows = 0 (genuine first pass) | Proceeded per advisor guidance — no orphan risk since zero surviving rows for this table |
| 2026-07-29 | Pass 1 | Text/image spot-checks confirmed `[Bundle of N]` pack_count and stage/size text signals are reliable for this category's official stores — high text-image agreement | Built 361 entries, 407 map rows via bulk text extraction with targeted image spot-checks (RTD cartons, Bellamy's no-size listing) |
| 2026-07-29 | Pass 1→1b | `Enfagrow A+ Official Store` (brand_id BRD-GLOBAL-00030/BRD-SG-01010) returned 0 rows on the initial exact-match allowlist pull — merchant_name has an undocumented trailing space, same bug class as the Wyeth store caught earlier in the same session | Re-pulled all 43 products under the correct (space-suffixed) name and processed as Pass 1: +31 entries, +43 map rows (SKU-211568–211598) |
| 2026-07-29 | Pass 2 | 314 in-scope (top-95%-cumulative-GMV) products remained unmapped after Pass 1; reseller titles far less structured than official-store titles, ~20 long-tail brands outside the brand-level 95% scope | Bulk text-matched via the same brand-line parser (reuse-before-mint against the Pass 1 dictionary): 72 products reused existing entries, 218 minted 150 new entries (SKU-211599–211748); unresolvable brand/line combos got `"{Brand} (unresolved)"` catch-alls rather than guesses |
| 2026-07-29 | Post-run QA | G1 (dual-mapped LLM) = 0, G2 (HUMAN+LLM coexistence) = 0, placeholder-leak = 0, structured-fields (product_line NULL among non-multi-size entries) = 0%, G5 (provenance) = 0 | All gates pass; 95.6% GMV coverage (2026-06), 542 taxonomy entries / 740 map rows total |
| 2026-07-29 | Top-up | Wrapper's live pre-check (94 products) re-verified live in STEP 0: 94 rows, 94 distinct products. Pre-write live-state check (per the pipeline-wide data-loss memory) confirmed no drift since the Full Rebuild — 740 LLM map rows, 542 dict entries, 0 orphans, 0 HUMAN rows — so this was a genuine small residual gap, not further data loss. `product_brand_map` resolved brand_id disagreed with `sku_name` text for several products (parent-brand routing: Similac/PediaSure products routed to `BRD-GLOBAL-00056` Abbott instead of their sub-brand, matching this category's own established Pass-1/2 precedent of minting Abbott-brand entries with product-specific canonical names) — verified via a precedent query (`taxonomy_brand` vs `resolved brand_id` agreement was 100% across all 740 existing map rows) before trusting it, per the receiving-code-review discipline of checking advice against primary evidence. One product (`16596244110`, "Nestle Nan OptiPro 4... 850g") resolved to Abbott despite unambiguously Nestle NAN text — flagged as a suspected `product_brand_map` data-quality error in its new entry's `product_line` field rather than silently overridden; not investigated further (out of scope for this session). Two "Nan" (`BRD-GLOBAL-00969`) vs "Nestle" (`BRD-GLOBAL-00059`) brand buckets exist in this category's dict for overlapping Optipro/SupremePro H.A. sub-lines with no reliable text signal distinguishing them — every ambiguous case was resolved via `product_brand_map`, never guessed from title wording. | Bulk-matched via brand+line+size text against the existing 542-entry dictionary: 47 products reused existing entries, 46 products minted 44 new entries (`SKU-215207–215250`, 2 entries each cover 2 products with matching brand+line+size text). 1 product (`56208107207`, Tefal cookware GWP set) correctly left `NULL`, matching this doc's pre-existing exclusion note. `product_taxonomy_map` 740→833 rows. Live worklist re-checked post-write: 0 remaining gap (excluding the 1 known Tefal exclusion). GMV coverage (2026-06) 95.6%→97.32%. Full gate check (G1/G2/G4-orphan/G5/placeholder-leak, exact queries from `docs/headless-runbook.md`) all 0 post-write. Universe refresh NOT run this session — separate step per instructions. |
| 2026-07-29 | Top-up (2nd, same day) | Wrapper's live pre-check claimed 1 unmapped product. Re-ran the STEP 0 worklist query live: exactly 1 row, `product_id 56208107207` — `"[GWP] Tefal Ingenio Serenity Eucalyptus Set (4pcs) [NOT FOR SALE]"`, `flag_GWP=true`, pure cookware, no milk product at all. This is the same product already documented above as a deliberate exclusion from the prior top-up session earlier today — not a new gap. Live state matched the doc exactly (833 LLM rows, 0 HUMAN rows) confirming no drift since the prior session. Full gate check (G1/G2/G4-orphan/G5/placeholder-leak/structured-fields, exact queries from `docs/headless-runbook.md`, run without `--skip-coexistence`) all 0. Per `docs/llm-extraction-rules.md` §5, an out-of-scope product stays NULL rather than being forced into the taxonomy — text alone was sufficient to confirm this (no image read needed). **Wrapper implication**: the wrapper's own gap pre-check counts this excluded row as a live gap, so it will keep re-triggering top-up sessions on this category indefinitely, each a no-op — worth a human recording a scope-exception for `56208107207` so future pre-checks stop flagging it. | No writes. No SKU block claimed (headless-runbook's top-up scenario claims none when the live gap is 0 after exclusions; prior session's `SKU-215251–215406` remainder still unused). GMV coverage unchanged at 97.32% (2026-06) — the sole worklist row is GWP-zeroed and contributes 0 to the coverage denominator either way. Universe refresh not run this session per instructions. |

---

## Targeted QA Fix Brief

> Not applicable yet — this is a first-run Full Rebuild session, not a targeted fix.

---

## Scripts

| Script | Purpose |
|--------|---------|
| (none — this session performs extraction directly via Claude Code multimodal reading, no external script) | |

---

## Map Row Counts (as of last run)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 833 | Pass 1 (407) + Pass 1b Enfagrow/Enfamil (43) + Pass 2 (290) + Top-up 2026-07-29 (93) |
| HUMAN | 0 | None existed prior to this session, none created by it |
| NULL (unmapped) | 3,375 (of 4,208 distinct products, month 2026-06) | Below the 95%-cumulative-GMV / official-store in-scope set — long tail, GMV coverage 97.32% (1 known non-milk exclusion, `56208107207`, is the only remaining in-threshold gap) |
