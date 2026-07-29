# shopee_sg_toilet_rolls — Category Context

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ⏳ In progress (this session) |
| LLM Pass 2 | ⏳ In progress (this session) |
| GMV Coverage | TBD after run |
| Last run | 2026-07-29 |
| Current MAX taxonomy_id | See sku_block_registry claim below (queried live, not from STATUS.md) |

Prior to this session: **zero** `product_taxonomy_map` rows of any source (`LLM` or `HUMAN`) existed for
`master_table = 'shopee_sg_toilet_rolls'` — this is a true from-scratch first run, not even a keyword-seed
baseline. STATUS.md's "⏳ Keyword only" label for `sg_toilet_rolls` overstates existing coverage; verified live
2026-07-29 (see QA History).

**Pipeline note (not a blocker for this session):** `magpie.marketshare_universe_niq` (the production analytics
table) has zero rows for month `2026-06-01` across **every** category — Stage 04 (Universe Append) hasn't
processed June 2026 yet pipeline-wide (max month present = `2026-05-01`). None of this session's steps
(extraction, QA-gate-as-code) depend on that table, so this doesn't block the run — but the `universe_taxonomy_overlay`
refresh (not part of this session) won't make June 2026 toilet-roll GMV analyst-visible with taxonomy attached
until Stage 04 catches up.

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| (claimed live in Step 3, see session output) | Full Rebuild — Pass 1 + Pass 2 |

---

## Brand Scope (GMV threshold 95%, month 2026-06)

Computed from `master_clean_niq.shopee_sg_toilet_rolls` (the production universe table has no June 2026 data —
see Status note above), GWP-zeroed (`CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END`), **and in-category-filtered**
before ranking: this table mixes genuine toilet-roll listings with facial tissue box, kitchen towel, wet wipes,
and toilet-bowl-cleaner products under the same `master_table` (see Scope section below) — per
`llm-extraction-rules.md` §8, GMV from those other product types is excluded from the brand-ranking sum so an
adjacent-category brand doesn't inflate into the toilet-roll brand scope. This mattered concretely: **NOMIEO**
ranked #4 ($33,691 GMV) on unfiltered brand GMV, almost entirely from a single facial-tissue-box line ($32,348
of its $33,691); once facial-tissue GMV is excluded, NOMIEO's real toilet-roll GMV is $1,343 and it ranks #28,
outside the 95% cutoff. Brand name variants merged: `Manhua` / `manHUA` / `漫花` → `Manhua`.

Category total in-category GMV (June 2026): $287,270.72 (revised — see wet-wipes refinement below).
**23 entries cross the 95% cumulative threshold** (22 real brands + 1 "(blank)" bucket for products with no
`brand` field value):

1. **Vinda** — $46,188.23 (16.1% cum.)
2. **Kleenex** — $43,079.65 (31.1% cum.)
3. **(blank)** — $27,144.77 (40.5% cum.) — not a real brand; products with empty `brand` field. Still in scope
   via Rule A (top-95% GMV); brand resolved per-product during extraction via `brand_from_image`/sku_name, same
   as any `BRD-UNDEFINED`/`FALLBACK` product.
4. **Hearttex** — $24,858.14 (49.2% cum.)
5. **Onwards** — $21,079.70 (56.5% cum.)
6. **Jie Rou C&S** — $17,383.06 (62.5% cum.)
7. **HG** — $14,419.22 (67.6% cum.)
8. **IUIGA** — $10,683.94 (71.3% cum.)
9. **PASEO** — $10,546.93 (74.9% cum.)
10. **AOG** — $7,992.40 (77.7% cum.)
11. **Belux** — $6,894.46 (80.1% cum.)
12. **Breeze** — $6,310.69 (82.3% cum.)
13. **Scott** — $6,255.96 (84.5% cum.)
14. **植护 Botare** — $5,421.52 (86.4% cum.)
15. **ValueStar** — $4,676.70 (88.0% cum.)
16. **Cloversoft** — $4,326.70 (89.5% cum.)
17. **Manhua** — $3,086.31 (90.6% cum.)
18. **Uzumi** — $2,768.92 (91.6% cum.)
19. **JIJI.SG** — $2,654.94 (92.5% cum.)
20. **Pursoft** — $2,511.54 (93.3% cum.)
21. **myCK** — $2,143.10 (94.1% cum.)
22. **EverFresh** — $2,140.78 (94.8% cum.)
23. **Beautex** — $2,012.70 (95.5% cum.) — last brand included; crosses the 95% line.

**Zappy excluded** (was rank 18 at $2,895.70 on an earlier pass): 100% of Zappy's GMV in this table is
"Flushable Toilet Tissue Wipes" — individually-wrapped moist wipes marketed as toilet-adjacent, not dry paper
rolls (Scope § wet-wipes exclusion applies at the product-type level, and Zappy has no other product in this
table). Once excluded, Zappy's real toilet-roll GMV is $0 — it drops out of the brand scope entirely, and its
official store drops out of the Pass 1 allowlist (see below). Caught because the first-pass wet-wipes regex
(`wet tissue|wet wipes|...`) didn't match "Toilet Tissue Wipes" phrasing; the second-pass regex over-corrected
and also zeroed out several genuine Kleenex toilet-roll bundle listings whose titles mention "+ Free Moist
Toilet Tissue Flushable Wipes" as a GWP bonus item (not the primary product) — fixed by requiring the exclusion
regex to also check for absence of "roll"/"rolls" in the sku_name, so a bundle that states a roll count stays
in-category regardless of a wipes-freebie mention.

Brands excluded from scope (below 5% GMV tail, ranks 25+, e.g. KCA, Nara Home Affairs, Watsons(-brand, distinct
from the retailer of the same name), PINSE, Pulppy, Qing Feng, Peri, Soiselle, Tempo, Bambooloo, Nufresh,
NooTrees, Prefer, RoyoPanda, Charmin, Hello Kitty, Naturesoft, WypAll, Kirkland Signature, and further long tail):
remain eligible for Pass 2 catch-all routing if they surface, but not required reading.

---

## Official Store Allowlist (Pass 1)

Built by querying distinct `merchant_name WHERE merchant_badge='Shopee Mall'`, month 2026-06, restricted to the
24 scoped brands' `brand` field values (plus a broader name-pattern search for brands with no direct hit).

| Brand | brand_id | Official Store Merchant Name |
|-------|----------|------------------------------|
| Vinda | (resolve via brand_dict at extraction time) | `Vinda & Tempo Tissue Official Store` |
| Kleenex | — | `Kimberly-Clark Official Store` |
| Kleenex | — | `Kimberly-Clark Professional Store` |
| Scott | — | `Kimberly-Clark Official Store` (same parent as Kleenex — Kimberly-Clark owns both brands) |
| Scott | — | `Kimberly-Clark Professional Store` |
| Hearttex | — | `Hearttex Store` |
| Hearttex | — | `Hearttex.SG` |
| IUIGA | — | `IUIGA Official` |
| PASEO | — | `PASEO` |

**Parent-company stores:** `Kimberly-Clark Official Store` / `Kimberly-Clark Professional Store` carry both
Kleenex and Scott (Kimberly-Clark owns both brands) — Pass-1-eligible for both, disambiguate per-product via
`brand_from_image`/sku_name, not excluded as multi-brand.

**Excluded as multi-brand / unconfirmed / not brand-owned** (found via Mall-badged query, rejected):
- `myCK_online` — sells Hearttex, Onwards, PASEO, Vinda, and myCK products under one Mall storefront; a
  multi-brand distributor/reseller, not any single brand's own store. Excluded per the multi-brand-retailer rule
  (same class as Watsons/BigC/Lotuss) even though "myCK" is in its name — its own myCK-branded GMV ($214.20)
  routes via Pass 2 instead.
- `Watsons Singapore Official Store` — known multi-brand retailer (explicit exclusion per
  `llm-extraction-rules.md` §4), carries incidental Kleenex/Vinda stock.
- `Kimberly-Clark Professional Store` line items with $0 GMV, `eslite 誠品 Flagship Bookstore`, `J-Mart Official`,
  `Neighbor Good Shopping Official` (all $0 GMV, general multi-category retailers carrying incidental Kleenex
  stock) — excluded, negligible GMV regardless.
- `Prestigio Delights Official`, `Dr P & TENA`, `Drypers Official Store`, `kimyu122165.sg`, `Weloveourkids` (all
  under Vinda/PASEO in the raw query) — names don't match the brand or a known parent company; treated as
  unconfirmed resellers, not official stores. Mostly $0 GMV.
- `Scanpap Tissue` (Pursoft, $151.20 GMV) — name doesn't match brand; unconfirmed, excluded. Low stakes either
  way — routes via Pass 2.
- `Prime Online Official Store` (Beautex, $0 GMV), `Ohere! Official Store` (Cloversoft, $120.40 GMV) — names
  don't match brand; excluded.

**Brands with no official store found (Pass 2 only)** — confirmed via both direct `brand` field match and a
broader `merchant_name` pattern search (no hits for any of these): Onwards, Jie Rou C&S, HG, AOG, Belux, Breeze,
植护 Botare, ValueStar, Cloversoft, Manhua, myCK, Uzumi, JIJI.SG, Pursoft, EverFresh, Beautex, plus the
"(blank)"-brand bucket (no brand field, so no brand-owned store to look up).

**Zappy removed from Pass 1 entirely** (was 7th confirmed store, `Zappy & HospiCare by Freshening`) — Zappy
fell out of the brand scope once its GMV was correctly attributed to an out-of-scope product type (wet wipes,
see Brand Scope § Zappy note above). Its official-store products are wet-wipes, not toilet-roll, so excluding
them from Pass 1 is correct on both grounds (brand scope and product type).

---

## Scale

- Total rows (model-grain, June 2026): **8,602**
- Distinct products (June 2026): **4,269**
- Mall-badged rows: 550 (283 distinct products) — **not** the Pass 1 scope; see below.
- Confirmed official-store-allowlist rows: distinct products = **62** — Pass 1 must scope to only these 62
  products (9 confirmed merchant names across 7 brands), not the full 283-product Mall-badged pool (4.5x larger).
  Not "tens of thousands" — a single-session vision-read of the full allowlist is feasible.

---

## Existing map rows (from Step 1)

Zero. No `HUMAN` or `LLM` rows exist for `master_table = 'shopee_sg_toilet_rolls'` in `product_taxonomy_map`.
Also verified no June-2026 product from this table has an existing map row under any *other* `master_table`
(the real dedup invariant is `(product_id, platform, country)`, not `master_table`) — none found.

---

## Scope — What's In vs Out

This table mixes several BE-categorized-as-"Toilet Paper" product types under one `master_table`. Sampling the
June 2026 data (8,602 rows) surfaced real contamination, not just theoretical risk:

**In scope:**
- Toilet paper / bathroom tissue rolls (any ply count, single or bulk-pack/carton)
- Bamboo / recycled-pulp bathroom rolls
- Bundle listings combining toilet rolls with a free GWP item (e.g. "+ Free Flushable Wipes") — the toilet-roll
  portion is in scope, the free wipes are GWP (flag_GWP, zeroed GMV, not a separate product)

**Out of scope (leave NULL):**
- Facial tissue boxes / soft-pack tissue (抽纸) — distinct product format from bathroom rolls. Found
  concentrated in NOMIEO ($32,348 GMV) and smaller amounts in Manhua, PASEO, Vinda, Nepia, 植护 Botare listings.
  A brand can legitimately have both in-scope roll products and out-of-scope tissue-box products — this is a
  per-product gate, not a brand-level exclusion.
- Kitchen towels / kitchen paper rolls (厨房纸) — different product, different use case.
- Wet wipes / wet tissue / moist wipes (baby wipes, antibacterial wipes, "Hand and Face Moist Wipes") — a
  different product category entirely, ~727 listings but only $5,330 GMV, mostly low-value.
- Toilet bowl cleaner / toilet gel / toilet sterilization wipes ("Mr. Muscle Toilet Gel", "Toilet Sterilization
  Bowl Disinfection...", "LEC Tank Toilet Cleaner") — cleaning chemical products, not paper. Near-zero GMV this
  month but a real TYPE_CONFLICT risk for bulk text-matching in Pass 2 (both mention "toilet" heavily).

**Edge cases:**
- Multi-size/assorted listings (e.g. "[Bundle] Kleenex Ultra Soft & Thick Cushiony Soft 4-Ply Assorted
  (20/40rolls)") — buyer selects from multiple roll counts in one listing → `is_multi_size=TRUE`, per
  `llm-extraction-rules.md` §2, not two separate entries.
- A meaningful "other/unclear" bucket in the initial keyword scan (1,592 products, $20,408 GMV) turned out on
  inspection to be genuine toilet-roll listings using phrasing my classifier regex simply didn't catch (plain
  "rolls", "bathroom roll", "tissue roll" without the exact tokens tested) — confirms the keyword scan here is
  for brand-ranking convenience only, never a per-product extraction gate (per §8's explicit rule). Every
  in-scope product must still be read individually; only the LLM's own category/type match-or-create gate may
  conclude a specific product is out of scope.

---

## Taxonomy Design Notes

**Product line extraction approach:**
- Most brands in this category use simple line names printed on-pack (e.g. "Ultra Soft & Thick", "Prestige
  4D-Deco Embossed", "Total 10") — read directly from sku_name/image, not from category words like "Bathroom
  Roll"/"Toilet Paper" alone.
- Kleenex and Scott share the Kimberly-Clark parent store — disambiguate via `brand_from_image`/sku_name, never
  the store name.

**Size extraction notes:**
- Primary unit: roll count (`N rolls`) combined with ply count (`3-Ply`, `4-Ply`) and sometimes sheet count per
  roll (`200s`, `220 sheets`) or weight (`120g`, `6600ply`). Capture roll count as part of `size` (e.g. "3-Ply
  20 rolls"), not `pack_count` — `pack_count` is for buy-N-of-this-listing multipliers (cartons of multiple
  units of the same listing), which is a separate signal from the roll count printed on one package.
- Bulk "carton"/"case" listings (e.g. "CARTON OF 10", "[Bulk Offer] 60 ROLLS") — read the total roll count as
  size, per the canonical-name `x{TOTAL}` rule if it represents multiple listing-units bundled; if it's a single
  purchasable unit containing N rolls, that's `size`, not `pack_count`.

**Known difficult products:**
- NOMIEO brand: majority of its GMV is facial tissue (OOS), only $1,343 is genuine toilet-roll GMV — apply the
  per-product type gate carefully, do not create a catch-all NOMIEO entry that silently absorbs tissue-box
  products.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-29 | Pre-run verification | STATUS.md said "⏳ Keyword only" implying seed rows exist; live query found zero rows of any source for this master_table, and zero for any June-2026 product_id under any other master_table | Proceeded as genuine from-scratch first run, not top-up |
| 2026-07-29 | Pre-run verification | Unfiltered brand-GMV ranking put NOMIEO at #4 ($33,691) almost entirely from facial-tissue-box GMV, not toilet-roll GMV | Applied in-category product-type filter before ranking (excluding facial tissue/kitchen towel/wet wipes/toilet cleaner GMV); NOMIEO fell to #28, outside 95% scope |
| 2026-07-29 | Pre-run verification | `marketshare_universe_niq` has zero rows for month 2026-06 pipeline-wide (max month = 2026-05) | Confirmed not a blocker for this session's scope (extraction + QA-gate-as-code only, no universe dependency); noted for whoever runs universe refresh later |
| 2026-07-29 | Pre-run verification | Zappy ranked in the 95% brand scope on GWP-zeroed GMV, but 100% of its GMV is a wet-wipes product type ("Flushable Toilet Tissue Wipes"), not toilet-roll — a first-pass wet-wipes exclusion regex missed the "Toilet Tissue Wipes" phrasing entirely | Refined regex to catch it; had to add a "contains 'roll'" carve-out so genuine Kleenex toilet-roll bundles with a "+ Free ... Flushable Wipes" GWP freebie mention weren't wrongly zeroed too. Zappy dropped out of brand scope and Pass 1 allowlist entirely |

---

## Targeted QA Fix Brief

(Not applicable this session — this is a Full Rebuild first run, not a targeted fix.)

---

## Scripts

N/A — extraction performed directly by Claude Code session (multimodal reading), no external pipeline scripts
invoked.

---

## Map Row Counts (as of last run)

To be filled in after Step 7 self-check.
