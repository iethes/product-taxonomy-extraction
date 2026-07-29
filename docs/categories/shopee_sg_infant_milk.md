# shopee_sg_infant_milk — Category Context

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ⏳ In progress (this session) |
| LLM Pass 2 | ⏳ In progress (this session) |
| GMV Coverage | TBD after extraction |
| Last run | 2026-07-29 |
| Current MAX taxonomy_id | Query BQ live — never trust this file |

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
| (filled in after atomic claim in Step 3) | Full Rebuild, Pass 1 + Pass 2 |

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
- To be logged here as encountered during Pass 1/Pass 2.

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
| LLM | TBD | Filled in after Pass 1 + Pass 2 |
| HUMAN | 0 | None existed prior to this session |
| NULL (unmapped) | TBD | Below GMV scope or out-of-category |
