# shopee_id_makeup_face — Category Context

> Second-ever ID (Indonesia) category in this pipeline (after `shopee_id_baby_diapers`). Created
> during a headless Full Rebuild session, 2026-07-20, month = 2026-06.

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete |
| LLM Pass 2 | ✅ Complete + top-up session (2026-07-20) closed most of the remaining coverage gap — 871 products still unmapped, see Targeted QA Fix Brief |
| GMV Coverage | 99.34% (see Map Row Counts) |
| Last run | 2026-07-20 (top-up session) |
| Current MAX taxonomy_id (registry floor at session start of top-up) | SKU-102345 (`sku_block_registry` MAX(block_end)) |

**Pipeline onboarding gap (read before trusting any downstream join for this table) — same gap
documented in `shopee_id_baby_diapers.md`, confirmed again live for this table:**
- `magpie_reference.product_brand_map` has **zero** rows for `master_table = 'shopee_id_makeup_face'`
  — Stage 03 (brand resolution) has never run on it.
- `magpie.marketshare_universe_niq` has **zero** rows for `country = 'ID'` at all — Stage 04
  (Universe Append) has never run for ID.
- `magpie.marketshare_universe` (general/legacy table) is not usable as a substitute — no
  `master_table` column, not keyed to this table.

None of this session's 7 steps depend on `product_brand_map` or `marketshare_universe_niq` — brand-scope
GMV and the official-store allowlist are computed directly off `master_clean_niq`, and the QA-gate-as-code
checks only touch `product_taxonomy`/`product_taxonomy_map`. Proceeding is correct, per the precedent. The
`product_taxonomy_map` rows this session writes will not be visible via the standard
`universe_taxonomy_overlay` → `marketshare_universe_niq` join until Stage 03/04 are separately run for ID —
a real follow-up item, not something this session can fix.

**brand_id resolution note:** since `product_brand_map` is empty for this table, `taxonomy.brand_id` is
resolved directly against `brand_dict` by raw brand-string lookup (not via `product_brand_map`), same as
`shopee_id_baby_diapers`. 10 top-95%-scope brands have no `brand_dict` entry yet and need new `BRD-ID-*`
rows minted during Pass 1 (see Brand Scope below).

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-100346–102345 | Full Rebuild claim (2000 slots) — Pass 1 + Pass 2, this session |

---

## Brand Scope (GWP-zeroed GMV threshold 95%, month 2026-06)

Computed directly from `master_clean_niq.shopee_id_makeup_face` (`CASE WHEN flag_GWP THEN 0 ELSE
gmv_monthly END`, GWP is rare here — 514/442,685 rows), `brand` field raw-string ranking. **110 raw brand
strings** are required to cross 95% cumulative GMV — this is a large, genuinely fragmented brand universe
(consistent with the task brief's warning that a fixed-size top-15/20 snapshot would undercount by ~6x;
here it would undercount by ~10x). Full ranked list queried live, not reproduced in full here — see query
below to regenerate. Cutoff: **rank 110 = Espoir, cumulative 95.03%**.

**Data-quality note on raw ranking — consolidation (conservative, cannot pull a brand out of scope):**
- Case/punctuation-only duplicates (merge, no scope impact): `Luxcrime`/`LUX CRIME`, `O.Two.O`/`O. TWO. O`,
  `MAC`/`M.A.C`, `Gogo Tales`/`GOGOTALES`, `L.A. Girl`/`L.A.Girl`, `B Erl`/`Berl`.
- Semantic duplicates confirmed by GMV inspection (merge): `WARDAH` + `Wardah Exclusive+` + `Wardah
  Acnederm Series` + `Wardah Perfect Bright` + `Wardah Crystallure` → **Wardah**. `GLAD2GLOW` + `Glad2Glow
  Official Store` → **Glad2Glow**. `OMG OH MY GLAM` + `Oh My Glam` + `OMG OH MY GLOW` + `OMG Mascara` →
  **OMG/Oh My Glam** (same brand family; "Oh My Glow" appears to be a sub-line, not a separate brand — low
  GMV either way). `Mother of Pearl` + `MOP Mother Of Pearl` → **Mother of Pearl**. `Rose All Day
  Cosmetics` + `ROSE ALL DAY` → **Rose All Day Cosmetics**. `barenbliss` + `bnb barenbliss` → **barenbliss**
  (both route to the same official store, confirmed below). `GLOWSOPHY` + `glowsohpy` (typo) → **Glowsophy**.
  `SIVANNA COLORS` + `Sivanna` → **Sivanna Colors**.
- None of these merges change the 95% cutoff rank materially — consolidation only concentrates GMV further
  into brands already in scope (same logic as `shopee_id_baby_diapers.md`).

**Brands with no `brand_dict` entry — need new `BRD-ID-*` rows during Pass 1** (checked against 105 of the
top-110 raw brand strings; the other ~5 are minor spelling variants of matched brands):
`ARTISANPRO`, `MERCREDI`, `EMINA`, `MADAME GIE`, `GOUTE`, `HAQUHARA`, `Maange`, `Sasc`, `Reveline`,
`Zencolor`.

Regenerate the ranking with:
```sql
WITH brand_gmv AS (
  SELECT CASE WHEN brand IS NULL OR TRIM(brand)='' OR TRIM(brand)='-' THEN '(UNDEFINED/BLANK)' ELSE TRIM(brand) END AS brand_raw,
    SUM(CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END) AS gmv
  FROM `sincere-hearth-273704.master_clean_niq.shopee_id_makeup_face`
  WHERE month = '2026-06-01' GROUP BY 1
)
SELECT brand_raw, gmv, SUM(gmv) OVER (ORDER BY gmv DESC) / SUM(gmv) OVER () AS cum_frac
FROM brand_gmv ORDER BY gmv DESC;
```

Top of the ranking (rank / brand / GMV IDR / cum%): 1 Wardah 24.69B 8.27% · 2 Skintific 23.45B 16.13% ·
3 Glad2Glow 22.87B 23.80% · 4 Make Over 17.89B 29.79% · 5 (UNDEFINED/BLANK) 16.76B 35.41% · 6 OMG/Oh My Glam
13.78B 40.03% · 7 Esqa 10.25B 43.46% · 8 PIXY 8.80B 46.41% · 9 Somethinc 6.68B 48.65% · 10 LT Pro 6.01B
50.66% · ... · 110 Espoir 0.22B 95.03%. `(UNDEFINED/BLANK)` (rank 5, 16.76B, 5.8% share) is GMV-real but not
a brand — no allowlist entry possible, routed via Pass 2 text/image only.

Brands excluded from scope (rank 111+, below the tail): everything from `NURILAB`-adjacent long tail
downward — legitimately `UNRESOLVED` unless caught via Rule B (official store).

---

## Official Store Allowlist (Pass 1)

Built by querying `merchant_name WHERE merchant_badge='Shopee Mall'` per scope brand, month 2026-06, then
excluding any merchant name selling **3 or more distinct scope brands** (a data-driven multi-brand-retailer
signal — more reliable than name-pattern matching alone at this brand count) or matching known chain/pharmacy
name patterns. **99 merchant names excluded this way**, including confirmed multi-brand retailers: `Watsons
Indonesia Official`, `Guardian Official Shop`, `Merah Jingga Official Store` (40 brands), `BEAUTYHAUL
Official Shop`, `Makeupbeautyhouse Official Store`, `Blessing Mask Official Store`, `WabiSabi Official Shop`
(46 brands — the largest cross-brand reseller found), `Dan+Dan Official Store`, `Nihonmart Official Shop`,
`Ayah Bunda Mart Official Store`, all `Kios *`/`Century *`/`Apotek *` variants, `Edit by Sociolla`, `Citrus
Department Store`, plus assorted zero/low-GMV reseller accounts — same exclusion pattern as
`llm-extraction-rules.md` §4 and the `shopee_id_baby_diapers` precedent (Watsons/pharmacy-chain/generic-mart
stores selling many brands under an "Official"-sounding name).

**102 of 109 scope-brand-strings have a genuine dedicated official store** (180 allowlisted merchant names
total, since several brands have a primary store + regional/authorized variants). Selected examples
(top-GMV brands; full list is the `allowlist_raw.csv`/`allowlist_merchants.txt` query output, regenerate
with the query pattern above joined to `merchant_badge='Shopee Mall'`):

| Brand | Official Store Merchant Name(s) |
|-------|----------------------------------|
| Wardah | `Wardah Official Shop`, `Lightplus Official Store` |
| Skintific | `SKINTIFIC Official Store` |
| Glad2Glow | `Glad2Glow Official Store` |
| Make Over | `Make Over Official Shop` |
| Esqa | `Esqa Cosmetics Official Shop` |
| PIXY | `Pixy Official Store` |
| Somethinc | `SOMETHINC Official Shop`, `SOMETHINC MAKEUP Official Shop` |
| LT Pro | `LT Pro Official Shop` |
| Focallure | `Focallure Official Shop` |
| Ultima II | `ULTIMA II Official Shop` |
| Luxcrime | `Luxcrime Official Shop` |
| AZZURA | `Azzura Official Shop`, `Wings Official Shop` *(parent company — Wings also carries BABY HAPPY-style products in other categories, verify makeup SKUs via image)* |
| Timephoria | `TimePhoria Official Store` |
| Maybelline | `Maybelline Indonesia Official Store` |
| HANASUI | `Hanasui Official Shop` |
| DAZZLE ME | `DAZZLE ME Official Shop` |
| Embryolisse | `Embryolisse Official Store` |
| Mother of Pearl | `Mother of Pearl Official Shop` (covers both `Mother of Pearl` and `MOP Mother Of Pearl` raw strings) |
| INEZ | `Inez Official Shop`, `Inez Malang Shop`, `Inez Medan Official Shop` |
| Instaperfect | `Instaperfect Official Shop` |
| Tirtir | `Tirtir Official Store` |
| O.Two.O | `O.TWO.O Official Shop` |
| IMPLORA | `Implora Official Shop` |
| Muaq | `MUAQ Official Shop` |
| L'Oreal Paris | `L'Oreal Paris Indonesia Official Shop` |
| Judydoll | `Judydoll Official Store` |
| MERCREDI | `Mercredi Official Store` |
| Laneige | `Laneige Official Shop` |
| Saniye | `SANIYE Official Shop` |
| Rose All Day Cosmetics | `Rosé All Day Cosmetics Official Shop` *(note diacritic — matches ASCII "Rose All Day" raw string)* |
| Guele | `Guèle Official Shop` *(diacritic)* |
| bnb barenbliss / barenbliss | `barenbliss Official Shop` (both raw strings route to the same store) |
| EMINA | `Emina Official Shop` |
| La Tulipe | `La Tulipe Official Shop` |
| You | `YOU Beauty Official Store` |
| lumecolors | `Lume Official Store`, `Lumecolors Official Shop` |
| GLOWSOPHY | `Glowsophy Official Store` |
| MADAME GIE | `Madame Gie Official Shop`, `Glam Girl Official Shop` |
| GOUTE | `gouté Official Store` *(diacritic)* |
| Marina | `Marina Official Shop` |
| Pinkflash | `Pinkflash Indonesia Official Shop` |
| HAQUHARA | `Haquhara Official Store` |
| Revlon | `Revlon Official Shop` |
| SALSA | `Salsa Cosmetic Official Shop` |
| Jung Saem Mool | `JUNG SAEM MOOL Official Store` |
| Kryolan | `Kryolan Official Shop` |
| BUTTONSCARVES | `Buttonscarves Beauty Official` |
| GMEELAN | `GMEELAN Official Store` |
| Azarine | `Azarine Cosmetic Official Shop` |
| Y.O.U Makeups | `YOU Beauty Official Store` (same store as `You`) |
| Estee Lauder | `Estee Lauder Official Store` |
| Facetology | `Facetology Official Shop` |
| Hojo | `HOJO Official Store` |
| BLP by Lizzie Parra | `BLP Official Store` |
| 3CE | `3CE Official Store` |
| Bioaqua | `BIOAQUA Indonesia Official Shop` |
| Brasov | `Brasov Official Shop` |
| MAC | `MAC Official Store` |
| Becoming | `Becoming Official Store` |
| DAVIENA SKINCARE | `DAVIENA SKINCARE Official Store`, `Daviena Max Official Store` |
| LUNA | `Luna Makeup Official Shop` |
| Pigeon / Pigeon Teens | `Pigeon Teens Indonesia Official Shop`, `Pigeon Indonesia Official Shop` |
| ONLYOU | `ONLYOU Official Store` |
| MS Glow | `MS Glow Beauty Official Store`, `MS Glow Indonesia Official Shop` |
| Innisfree | `Innisfree Official Shop` |
| NARS | `NARS Official Store` |
| ANIMATE | `Animate Official Shop` |
| N'PURE | `Npure Official Shop` |
| NATURACTOR | `Tammia Official Shop` *(flag: verify — only candidate, name doesn't contain "Naturactor"; likely an authorized ID distributor per the parent-company-store pattern, unconfirmed)* |
| Purbasari | `Purbasari Official Store` |
| Reveline | `Reveline Official Shop` |
| Sulwhasoo | `Sulwhasoo Official Shop` |
| Laura Mercier | `Laura Mercier Official Store` |
| SARIAYU | `Sariayu Martha Tilaar Official Shop`, `Martha Tilaar Official Shop` |
| NURILAB | `Nurilab Official Shop` |
| CLEYA | `Cleya Beauty Official Shop` |
| FEALI | `Feali Official Shop` |
| Shiseido | `Shiseido Official Shop` |
| SYB | `SYB Official Shop` |
| TAVI | `Tavi Official Shop` |
| Fanbo | `Fanbo Cosmetics Official Store` |
| CLIO | `Clio Official Shop` |
| Espoir | `Espoir ID Official Store` |
| ARTISANPRO | `Artisan Pro Official Shop` |
| Viva / Viva Cosmetics | `Viva Cosmetics Store Bandung`, `Viva Cosmetics Official Shop`, `Viva Cosmetics Authorized Store Surabaya` |
| Trueve | `Trueve Official Shop` |
| Studio Tropik | `Studio Tropik Official Shop` |
| SR12 | `VMJ PERMATA Official Store` *(flag: verify — indirect name match)* |
| Zencolor | `Zencolor Official Store` |
| YZS | `YZS Official Store` |

**Brands with NO official-store candidate found (Pass 2 only):** `Maange`, `SIVANNA COLORS`, `Oh My
Glam`/`OMG OH MY GLOW` (folded into the OMG family above via other spellings — see consolidation note),
`YESSICA'S`. `MARCKS'` technically has 3 near-zero-GMV candidates (all under 3M IDR combined vs. 1.75B total
GMV) — effectively no dedicated official store; nearly all its GMV flows through excluded multi-brand
resellers or non-Mall sellers — treat as **Pass 2 heavy**, not Pass 1.

---

## Scale

- Total rows (month 2026-06): 442,685 — distinct products: 112,651. GMV: ~2.99T IDR total (GWP-zeroed).
- **Full Mall-badged pool: 65,507 rows / 19,521 distinct products — large (tens of thousands scale).**
  Pass 1 does **not** vision-read this whole pool.
- **Official Store Allowlist-scoped pool (actual Pass 1 worklist): 20,860 rows / 3,686 distinct
  products**, ~1.21T IDR GMV. This is the tractable Pass 1 scope — roughly 2x `shopee_id_baby_diapers`'
  1,696 products, expected given ~10x the brand count.
- `brand` field fill rate: high (only rows with blank/`-` brand fold into `(UNDEFINED/BLANK)`, 5.8% share).
- `flag_GWP` prevalence: low, 514/442,685 rows (0.12%).

---

## Scope — What's In vs Out

**In scope — all 7 `category_4_EN` buckets are legitimately face makeup, no mixed-content contamination
found** (unlike `shopee_th_body_wash`/`shopee_th_liquid_milk`): Foundation (`Base`, 29,629 products, 1.11T IDR — largest
sub-type), Face Powder (`Bedak`, 31,122 products, 430B), Blush (12,934, 27.3B), Make Up Base & Primer
(12,606, 16.6B), Concealer & Corrector (6,937, 15.2B), BB & CC Cream (10,497, 14.1B), Bronzer/Contour/
Highlighter (8,926, 11.5B).

**TYPE GATE (product-lifecycle.md §4.2, hard gate):** these 7 sub-types are distinct product types and must
**never** be merged across — a Foundation entry is not interchangeable with a BB Cream or Concealer entry
for the same brand+line, even if the line name is shared (e.g. a brand's "Perfect Cover" line may have both
a Foundation and a BB Cream SKU — these are two different `product_taxonomy` entries).

**Out of scope (leave NULL):** lip makeup, eye makeup, makeup tools/brushes/sponges if any slip in via
mislabeled `category_3`/`category_4` (none observed in the category_4 breakdown above — this table appears
cleanly scoped to face makeup only).

**Edge cases:**
- `AZZURA` via `Wings Official Shop` — Wings is a large FMCG conglomerate parent store; verify makeup SKUs
  via image/sku_name before trusting as AZZURA (parent-company store carries other Wings brands too).
- `NATURACTOR` via `Tammia Official Shop` and `SR12` via `VMJ PERMATA Official Store` — indirect store-name
  matches, flagged for verification during extraction, not fabricated with confidence.

---

## Taxonomy Design Notes

**Product line extraction approach:** ID `sku_name` text for this category is generally descriptive
(brand + line/shade + product type + size stated together, similar richness to `shopee_id_baby_diapers`).
Read sku_name first; use product image for brand-vouching per distinct product-line cluster and to resolve
genuine ambiguity (shade/variant naming, size when text is silent) — not for exhaustive per-row reads,
per this session's STEP 5 instruction.

**Size extraction notes:** Face makeup sizes are typically small-format: g (powder/blush/bronzer), ml/mL
(liquid foundation/BB cream/primer), or shade-count for palette-style products. Many listings are
per-shade single-SKU (no pack multiplier) — `pack_count=1` is the common case here, unlike bulk-pack FMCG
categories; verify against sku_name/image per `llm-extraction-rules.md` §1 before defaulting.

**Known difficult products:**
- Multi-shade "pick your shade" reseller listings (buyer selects 1 of N shades in a single sku_name) —
  apply the same `is_multi_variant=TRUE` treatment as `shopee_th_softdrink`'s multi-variant pattern, or route to
  the specific shade if the option list resolves it unambiguously.
- Brands sold under diacritic store names (`gouté`, `Guèle`, `Rosé All Day`) — canonical_name and
  brand_dict lookups should use the ASCII raw `brand` field spelling for consistency with the rest of the
  pipeline (`GOUTE`, `Guele`, `Rose All Day Cosmetics`), not the diacritic store-name spelling.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-20 | Session start | Second-ever ID category; same `product_brand_map`/`marketshare_universe_niq` pipeline gap as `shopee_id_baby_diapers` | Documented as known gap, not a blocker |
| 2026-07-20 | Brand scope | 110 brands required for 95% GMV threshold (vs. ~12 for baby_diapers) — a much more fragmented category; confirmed via full live query, not a fixed-size snapshot | Full ranking documented; regenerate query provided above |
| 2026-07-20 | Brand scope | 10 top-95%-scope brands absent from `brand_dict` | Flagged for new `BRD-ID-*` entries during Pass 1 (see Brand Scope) |
| 2026-07-20 | Official store allowlist | 99 merchant names selling ≥3 distinct scope brands identified as multi-brand retailers via data-driven detection (more reliable than name-pattern matching alone at this brand count) and excluded | Allowlist scoped to 180 genuine merchant names across 102 brands |
| 2026-07-20 | Top-up coverage session | Live re-query of the STEP 0 worklist (95%-cumulative-GMV, GWP-zeroed, `canonical_name IS NULL`) found 4,241 distinct unmapped products (8,817 product/model rows) — close to but not identical to the wrapper's stale pre-check number, confirming the live re-query was necessary. Bulk-first reuse-before-mint pipeline (SQL text-matching, not per-row image reads): (1) 195 products matched to existing taxonomy entries via brand+product_line substring match; (2) 2,759 products minted into 2,652 new entries via brand resolution (direct `brand_dict` match + empirical brand_raw→brand_id lookup from already-mapped products) + regex size/pack extraction + cluster-by-normalized-sku_name; (3) 262 more products resolved via a broader `brand_dict`-wide sku_name-prefix scan (after filtering ~187 false-positive generic-word matches like "Foundation"/"Ready"/"Promo" via a stoplist) → 251 new entries; (4) 154 more products resolved via official-store merchant_name → brand inference, minting 47 new `BRD-ID-*` brand_dict entries for genuine single-brand stores not yet registered (cross-checked against this file's known multi-brand-retailer exclusion list — Watsons/Guardian/BEAUTYHAUL/Blessing Mask/Nihonmart/Boots/Ulta Beauty excluded from store-as-brand inference) → 154 new entries. Total: 3,370 of 4,241 products resolved (79.5%); 871 remain genuinely unresolved (no identifiable brand from text signals within this session's bulk-SQL budget — mostly blank-`brand` field long-tail resellers with generic/non-descriptive titles). Category GMV coverage rose to 99.34%. | 3,057 new `product_taxonomy` entries (`SKU-104246`–`SKU-107302`, within claimed blocks; `SKU-100346`–`101545` range reused for the 195 text-matches), 3,370 new `product_taxonomy_map` rows, all `source='LLM'`, `meta_agent='CLAUDE_CODE'`, confidence 0.62–0.75 (bulk text-match tier, not image-verified — flagged for `targeted_qa_fix.sh` precision pass per D1–D5). QA gates (G1 dual-mapped, G2 HUMAN+LLM coexistence, placeholder-leak, G5 provenance) all passed at 0, run without `--skip-coexistence`. Universe refresh NOT run this session (separate step, pending independent QA verification). Remaining 871-product gap and D1–D5 precision (generic-stub product lines from the regex extraction, e.g. verbose marketing-copy `product_line` values) are real follow-up items for a future `targeted_qa_fix.sh` session, not resolved here — this session's explicit priority was coverage, not precision. |

---

## Targeted QA Fix Brief

> Follow-up items from the 2026-07-20 top-up session (see QA History above), for a future `targeted_qa_fix.sh` run:
> - 871 products still unmapped (95%-cumulative-GMV scope) — mostly blank-`brand`-field long-tail resellers with non-descriptive titles; need per-product image reads.
> - The 3,057 entries minted this session used regex-only size/pack/product_line extraction (no image verification) — expect generic-stub / verbose product_line text needing D1–D3 cleanup, and NULL size on products where the regex didn't catch the unit format.
> - 47 new `BRD-ID-*` brand_dict entries minted from official-store merchant names — spot-check for accuracy (a few store names had inconsistent suffix-stripping, e.g. `URRACX Official Store` may have retained its suffix in `canonical_name`).

---

## Scripts

Not applicable — this category is extracted directly by a Claude Code session (multimodal reading), not
via `pipeline/05_product_taxonomy/llm_{table}/*.py` scripts.

---

## Map Row Counts (as of last run, month 2026-06)

As of the 2026-07-20 top-up session: 44,966 `product_taxonomy_map` rows (all `source='LLM'`), spanning
44,653 distinct `product_taxonomy` entries (`SKU-100346`–`SKU-107302`). Category GMV coverage: 99.34%.
871 in-scope products remain unmapped (see Targeted QA Fix Brief above).
