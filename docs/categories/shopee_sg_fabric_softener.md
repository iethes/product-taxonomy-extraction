# shopee_sg_fabric_softener — Category Context

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete |
| LLM Pass 2 | ✅ Complete |
| GMV Coverage | 87.08% of total category GMV (2026-06); 34/305 Rule-A in-scope products remain NULL, all confirmed out-of-scope (see QA History) |
| Last run | 2026-07-29 |
| Current MAX taxonomy_id | SKU-208309 (this category's own block; overall table MAX may be higher from concurrent sessions) |

**Live pre-check confirmed:** `product_taxonomy_map` had **zero** rows (HUMAN or LLM) for
`master_table = 'shopee_sg_fabric_softener'` at session start. Genuine first run — matches
`docs/categories/STATUS.md`'s `sg_fabric_softener` row, which was also marked "⏳ Keyword only" (no seed rows
existed despite the label, same drift pattern seen on `sg_beverages`/`sg_household_cleaner`).

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-208049–208309 | Pass 1 + Pass 2 combined (261 taxonomy entries, 358 products mapped) |
| SKU-208310–210048 | Unused remainder of claimed 2,000-slot block |

---

## Brand Scope (GMV threshold 95%, month 2026-06-01)

**18 named brands + 1 blank-brand bucket** in scope (GWP-zeroed product GMV: `flag_GWP` products' `gmv_monthly`
set to 0 before ranking). This category is naturally concentrated — unlike a prior session's ~6x under-count
incident, the true 95% cumulative threshold genuinely falls at rank 19 here (verified by walking the full
cumulative curve, not truncated at a fixed top-N).

Ranked by GWP-zeroed GMV (SGD), month 2026-06-01:

1. **Downy** — `BRD-SG-00002` — 74,826
2. **Comfort** — `BRD-GLOBAL-00086` — 25,615
3. **(blank brand field)** — no brand_id, see note below — 22,878
4. **Laundrin'** — `BRD-SG-00378` — 19,457
5. **Softlan** — `BRD-SG-01607` — 18,959
6. **ar FUM** — `BRD-SG-00942` — 14,180
7. **P&G** (raw brand string — see note below, distinct from Downy/Bounce) — no dedicated official store — 12,090
8. **Daia** — `BRD-SG-01816` — 10,814
9. **Cosway** — `BRD-SG-01334` — 5,306
10. **Duo&Duo** — `BRD-SG-13054` — 4,390
11. **Hygiene** — `BRD-GLOBAL-00020` — 3,978
12. **Bounce** — `BRD-SG-01046` — 3,974
13. **Snuggle** — `BRD-SG-02483` — 3,412
14. **Fasclean** — `BRD-SG-03022` — 2,733
15. **Flair** — `BRD-SG-02551` — 2,512
16. **LG** — `BRD-GLOBAL-01668` — 1,831
17. **Yuri** — `BRD-GLOBAL-01555` — 1,586
18. **ODOCO** — `BRD-SG-04946` — 1,503
19. **Ecover** — `BRD-SG-01987` — 1,163 (cum_frac crosses 0.95 here: 0.9515)

Category total GWP-zeroed GMV (139 brand buckets, corrected count — an earlier `bq query` pull without
`--max_rows` silently truncated to 100 rows mid-session; re-run with `--max_rows` gave the real count):
**SGD 242,992**. Threshold row: Ecover at cum_frac 0.9515.

**Correction found during Pass 2:** Cosway's brand-level GMV in this category table is contaminated by
wrong-product-type listings — both of its Rule-A-eligible products (`29866308198` "PowerMax Dish Drop",
`25677553559` "PowerMax Bathroom Cleaner") are dish soap / bathroom cleaner, not fabric softener at all,
and were left unmapped (OOS) rather than force-taxonomized. Cosway's true fabric-softener GMV in this table
is effectively ~0 — its rank-9 brand position above is an artifact of mixed-category source-table
contamination (the same class of issue `docs/llm-extraction-rules.md` §8 warns about for brand-GMV ranking). Everything from rank 20 (Faultless, cum_frac 0.956) downward is below-threshold long tail (81 more
brand buckets, mostly near-zero GMV) — out of Rule-A scope, in scope only if they qualify under Rule B
(official store).

**Note on "(blank)" bucket:** rank 3, SGD 22,878 GMV, is products whose `brand` source column is empty —
not a real brand name, no `brand_id` to allowlist an official store against. These products still fall in the
95%-cumulative in-scope set and must be extracted like any other in-scope product — brand comes from
`brand_from_image`/`sku_name` reading at extraction time, not from this bucket.

**Note on "P&G" raw brand string:** distinct from the `Downy`/`Bounce` brand strings even though Downy and
Bounce are also P&G-owned. Investigated: every product tagged `brand='P&G'` is actually a **Lenor** product
(P&G's separate fabric-softener/scent-booster line, not sold under the Downy or Bounce name in this market) —
100% sold by resellers/parallel importers (Japan direct-ship shops), **zero Shopee Mall presence**. No official
store exists for this bucket — go straight to Pass 2. Route these to a `Lenor` product line (brand_id likely
`BRD-GLOBAL-00971` P&G, or create/locate a dedicated Lenor brand entry if one exists — check `brand_dict` at
extraction time).

Brands excluded from scope (below-threshold tail, rank 20+): Faultless, Seventh Generation, SOFSIL, Lenor
(as a brand_dict entry, if distinct from the "P&G" raw-string bucket above), UIC, LEIFHEIT, Weavve Home,
Kirkland Signature, Vanzo, LION, method, PiPPER STANDARD, Bouquet Garni, The Laundress, SHIRO, NS FAFA JAPAN,
Bluna, Tide, ATOMY, Walch, Dr. Beckmann, TOP, Fineline, Fresh HY, ORITA, AURA, and ~75 further near-zero-GMV
brand buckets. These may still surface individual in-scope products only via Rule B (official-store listing) —
none were found with a Mall presence in this category's data, so they are Pass-2-only long tail, extractable
opportunistically but not required for the 95% target.

---

## Official Store Allowlist (Pass 1)

Built by querying distinct `merchant_name WHERE merchant_badge='Shopee Mall'` per in-scope brand, month
2026-06-01.

| Brand | brand_id | Official Store Merchant Name |
|-------|----------|------------------------------|
| Downy | BRD-SG-00002 | `P&G Official Store` |
| Bounce | BRD-SG-01046 | `P&G Official Store` (shared — P&G parent-company store, Pass-1-eligible for both) |
| Comfort | BRD-GLOBAL-00086 | `Unilever Official Store` |
| Snuggle | BRD-SG-02483 | `Unilever International` (parent-company store — Unilever-owned brand, separate merchant name from the Comfort one above) |
| Laundrin' | BRD-SG-00378 | `Mandom Official Store` |
| Softlan | BRD-SG-01607 | `Colgate Official Store` |
| ar FUM | BRD-SG-00942 | `Walch SG Official Store` |
| Duo&Duo | BRD-SG-13054 | `DuoDuo Mall` |
| Fasclean | BRD-SG-03022 | `Fasclean Factory Store.sg` |
| Flair | BRD-SG-02551 | `Kao Official Store` |
| Yuri | BRD-GLOBAL-01555 | `Yuri Shop` |
| Ecover | BRD-SG-01987 | `Ecover Official Store` |

**Excluded multi-brand retailers (Mall-badged but not brand-specific — verified by checking how many distinct
brands each merchant sells across this whole category, not just the in-scope subset):**
- `Watsons Singapore Official Store` — sells 17 distinct brands (Bounce, Comfort, Laundrin', Snuggle, Softlan,
  ar FUM, Seventh Generation, and 10 more) — matches `docs/llm-extraction-rules.md` §4's Watsons exclusion,
  confirmed empirically here too even outside the Beauty vertical.
- `myCK_online` — 6 distinct brands (Comfort, Downy, Softlan, and others) — reseller, not a brand's own store.
- `Prestigio Delights Official` — 5 distinct brands (Comfort, Seventh Generation, and others) — distributor,
  not brand-specific.
- `Corlison Official Store` — sells 2 unrelated, non-affiliated brands (Ecover and method — different
  companies, not a shared parent) — a multi-brand distributor despite the "Official Store" name, not a
  parent-company store. Only SGD 40 of Ecover GMV routes through it; excluded from the allowlist, that GMV
  still counts toward Ecover's brand-scope ranking but is captured via Pass 2 (reseller routing), not Pass 1.

**Brands with no official store found (Pass 2 only):** (blank-brand bucket), P&G/Lenor (see note above — no
Mall presence at all for this raw-string bucket), Daia, Cosway, Hygiene, LG, ODOCO.

---

## Scale

| Metric | Value (month 2026-06-01) |
|--------|---------------------------|
| Total source rows | 12,828 |
| Distinct products | 3,714 |
| Official-store (`Shopee Mall`) rows, unfiltered | 916 |
| Official-store (`Shopee Mall`) distinct products, unfiltered | 470 |

Official-store row count is modest (470 distinct products, not tens of thousands) — after applying the
allowlist above (excluding Watsons/myCK_online/Prestigio Delights/Corlison), the actual Pass 1 candidate pool
is smaller still. Pass 1 must scope to the allowlisted merchant names only, never the full unfiltered
Mall-badged pool.

---

## Scope — What's In vs Out

**In scope:**
- Fabric softener (liquid, concentrated, sheets/beads)
- 2-in-1 wash+soften products (per `docs/llm-extraction-rules.md` §5 `fabric_softener` row)

**Out of scope (leave NULL):**
- Ironing spray / wrinkle-releaser spray / anti-wrinkle spray / "no-iron" spray (e.g. Downy Wrinkle Releaser
  Spray, Faultless Ironing Spray, Hygiene Wrinkle Spray, generic "no-iron wrinkle release" listings) — a
  distinct ironing-aid format, not a rinse-cycle fabric softener, even when sold by a fabric-softener brand.
- Starch spray for ironing (Dr. Beckmann "Starch & Easy Iron", Yuri Tril Ironing Starch Spray) — same class.
- Laundry pods/capsules (ODOCO 7-in-1 Laundry Pods, Downy 4-in-1 Laundry Pods, Vanzo 3-in-1 Laundry Capsules)
  — a detergent-format product (used in the wash cycle) even when marketed with "fabric softener" as one of
  several claimed benefits; structurally not a rinse-cycle softener.
- Kispray / Rapika / Rapika Biang (Indonesian "pelicin"/ironing-smoothing spray products) — same ironing-spray
  class under different brand names.
- Laundry-only detergent (no softening function), dish soap, bathroom cleaner (Cosway PowerMax Dish
  Drop/Bathroom Cleaner — wrong product type despite same source table)
- Stain/spot remover (Ink Cleaner Fabric Stain Remover, TOP Lion Fabric Spot Remover, Tide To Go stain
  wipes/pen)
- Foot softener (BAREN Foot Softener — personal care product, wrong category entirely)
- Physical accessories (LEIFHEIT Ironing Board Cover — not a chemical product at all)
- Downy/other Gel Ball detergent capsules (a detergent product, not a softener, despite brand overlap)
- Cross-category bundles dominated by non-softener items (e.g. Snuggle Fabric Conditioner + Sunlight
  Dishwashing + Cif Anti-Bac Spray + Scrub Daddy sponge, sold as one SKU)

**Edge cases:**
- P&G-raw-string "Lenor" products: in scope (fabric softener/scent booster), route per the note above — do
  not confuse the scent-booster-beads sub-format with an out-of-scope product type; scent boosters used
  alongside fabric softener are still a fabric-care product in this category's source data.
- Watsons/myCK_online/Prestigio Delights/Corlison listings: still in scope as individual products (Rule A if
  high-GMV enough, or plain Pass 2 reseller routing) — excluded only from the Pass 1 *official-store allowlist*
  gate, not from extraction entirely.
- A single ambiguous multi-product option listing (`26056558343`, iiMONO reseller bundling Downy Infusions
  Dryer Sheets / Unstopables Scent Booster / Wrinkle Releaser Spray as buyer-choice variants in one SKU) was
  left NULL — can't determine which option the buyer actually receives, and one of the three options is itself
  out-of-scope.

---

## Taxonomy Design Notes

**Product line extraction approach:**
- Read `sku_name` + product image for real on-label line names (e.g. Downy's "Sunrise Fresh", "Passion",
  "Antibac+" lines; Comfort's "Ultra Concentrate", "First Instinct" lines) — never default to generic
  "Fabric Softener" as product_line.
- Parent-company stores (P&G Official Store, Unilever Official Store/International) carry multiple brands —
  disambiguate the actual brand via `brand_from_image`/`sku_name`, not the merchant name.

**Size extraction notes:**
- Primary unit: ml / L.
- Pack-count patterns to watch for in this category: refill vs. bottle bundles (e.g. "1 bottle + 2 refills"),
  `x2`/`x3` multi-unit bundles — apply the standard GWP-vs-genuine-multipack distinction from
  `docs/llm-extraction-rules.md` §1.

**Known difficult products:**
- P&G-raw-string Lenor scent-booster-bead products: brand routing needs confirmation against `brand_dict` at
  extraction time (see Brand Scope note above) — not yet resolved to a final brand_id as of this file's
  writing.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-29 | Pre-run | Live pre-check: 0 existing map rows, confirms genuine first-run scenario | Proceeded with Full Rebuild |
| 2026-07-29 | Pass 1+2 | `bq query` silently truncates result sets to 100 rows without `--max_rows` — first Pass-1-pool pull and brand-bucket count were both truncated mid-session | Re-ran every query expected to exceed 100 rows with `--max_rows=5000` |
| 2026-07-29 | Pass 1+2 | Rule A (product-level 95% cumulative GMV) is a different, larger set than the 19-brand-scope official-store pool — 305 products vs. 187; worklist = Rule A ∪ Rule B (393 unique products) | Built the full union before extraction, not just the official-store pool |
| 2026-07-29 | Pass 1+2 | 35 products in the worklist are wrong-format/wrong-category for this category (ironing/wrinkle spray, starch spray, Kispray/Rapika, laundry pods/capsules, dish soap/bathroom cleaner mislabeled under Cosway, stain remover, foot softener, ironing board cover, one cross-category bundle) | Excluded via keyword filter, documented in Scope section; left `taxonomy_id` NULL |
| 2026-07-29 | QA gates | G1/G2/G3-placeholder-leak/structured-fields/G5 all ran at 0 violations post-insert | Shipped without a fix iteration needed |
| 2026-07-29 | D6 | 34 remaining Rule-A in-scope NULLs, top-GMV checked individually — all 34 confirmed as the same OOS classes above, none is a genuine coverage miss | No further action; documented as legitimately-NULL |

**Known gap for a future `targeted_qa_fix.sh` pass (not this session's scope, coverage was prioritized over
precision per the headless runbook):** several long-tail single-appearance brands (SOFSIL, Bluna, SHIRO, UIC,
Fineline, Weavve Home, Bouquet Garni, Kirkland Signature, Pigeon, and a few "Unbranded" dryer-sheet/scent-bead
catch-alls) got `product_line` derived by generic text-stripping rather than a read on-label line name, since
each appears only once or twice in the worklist. Also several Downy/Comfort/Daia/Softlan buckets use the
category-adjacent line name "Fabric Softener"/"Regular"/"Concentrated Fabric Softener" where the sku_name
didn't clearly state a more specific on-label line — D2 (product line accuracy) risk worth a future
image-verification pass on the highest-GMV of these.

---

## Map Row Counts (as of last run)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 358 | Pass 1 + Pass 2 combined (single bulk-routed pass, 261 distinct taxonomy entries) |
| HUMAN | 0 | No prior keyword-seed pass ran for this table |
| NULL (unmapped, in-scope) | 34 | All confirmed out-of-scope product-type contamination (ironing spray, laundry pods, stain remover, etc.) — see Scope and QA History |

---

## Targeted QA Fix Brief

> Not yet applicable — no prior extraction exists for this category. Future targeted QA fix sessions should
> fill this section per the template once D1–D5 defects are identified against this run's output.

---

## Scripts

| Script | Purpose |
|--------|---------|
| (headless session, no persisted pipeline script — direct multimodal extraction by the Claude Code session) | Pass 1 + Pass 2 |
