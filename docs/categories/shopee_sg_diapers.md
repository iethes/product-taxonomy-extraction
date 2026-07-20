# shopee_sg_diapers — Category Context

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ❌ Not started |
| LLM Pass 2 | ❌ Not started |
| GMV Coverage | TBD |
| Last run | 2026-07-20 |
| Current MAX taxonomy_id | Query `sku_block_registry` live — never trust this file |

Review month for all queries in this file: **2026-06-01** (source `month` column is `DATE`, not a string).

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-091442–093441 | Full Rebuild — Pass 1 OFFICIAL + Pass 2 RESELLER (claimed atomically via `sku_block_registry`, 2026-07-20) |

---

## Brand Scope (GMV threshold 95%, June 2026, GWP-zeroed)

Computed via `product_brand_map` → `brand_dict` (not the raw `brand` text column, which is
often blank/inconsistently cased per `docs/data-dictionary.md`). GWP GMV zeroed via
`CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END` before ranking (Decision 15).

**16 brands** cross the 95% cumulative-GMV threshold (real running-sum computation, not a
fixed top-N snapshot):

1. **Merries** — `BRD-GLOBAL-00021` — S$897,468 (25.0% cum)
2. **HUGGIES** — `BRD-GLOBAL-00211` — S$882,837 (49.6% cum)
3. **Mamypoko** — `BRD-SG-00001` — S$593,584 (66.1% cum)
4. **Drypers** — `BRD-SG-00361` — S$334,991 (75.4% cum)
5. **Nino Nana** — `BRD-SG-00754` — S$105,029 (78.4% cum)
6. **Offspring** — `BRD-SG-00762` — S$90,489 (80.9% cum)
7. **moony** — `BRD-SG-00760` — S$83,934 (83.2% cum)
8. **Goo.n** — `BRD-GLOBAL-00093` — S$82,614 (85.5% cum)
9. **Charnins** — `BRD-SG-00980` — S$72,200 (87.5% cum)
10. **Pampers** — `BRD-SG-00823` — S$60,666 (89.2% cum)
11. **Rascal + Friends** — `BRD-SG-00811` — S$59,096 (90.9% cum)
12. **Applecrumby** — `BRD-GLOBAL-00120` — S$43,397 (92.1% cum)
13. **NOMIEO** — `BRD-SG-00906` — S$36,617 (93.1% cum)
14. **`BRD-UNDEFINED`** — S$30,529 (93.9% cum) — no resolvable brand identity; Pass 2 / UNRESOLVED only, no official-store allowlist entry possible
15. **Day&** — `BRD-SG-12796` — S$27,328 (94.7% cum)
16. **Peachy Bum** — `BRD-SG-01758` — S$19,921 (95.2% cum, crosses threshold)

Brands excluded from scope (below 5% GMV tail, ~85 more brands ranked 17+, e.g. Aiwibi,
Einmilk, Hoppi, Beenies, Bambo Nature, unicharm, Pigeon, DryNites, etc.) — full ranked list
available via the query in QA History if needed for a future top-up pass.

---

## Official Store Allowlist (Pass 1)

Built by querying distinct `merchant_name WHERE merchant_badge='Shopee Mall'`, joined through
`product_brand_map` to the in-scope `brand_id`s above (not `LIKE '%official%'` — Decision 14).
Every candidate below was checked against ALL brands it sells in this dataset (not just the
scoped brand) to confirm it isn't a multi-brand retailer wearing an "Official Store" name.

| Brand | brand_id | Official Store Merchant Name |
|-------|----------|------------------------------|
| Applecrumby | BRD-GLOBAL-00120 | `Applecrumby® Official Store` |
| Charnins | BRD-SG-00980 | `BIC OFFICIAL STORE` — sells only Charnins in this dataset; likely the SG distributor name, not a generic word |
| Drypers | BRD-SG-00361 | `Drypers Official Store` |
| HUGGIES | BRD-GLOBAL-00211 | `Huggies Official Store` |
| HUGGIES | BRD-GLOBAL-00211 | `Kimberly-Clark Official Store` (parent company — Kimberly-Clark owns Huggies; verified sells only HUGGIES in this dataset) |
| Mamypoko | BRD-SG-00001 | `Mamypoko Official` |
| moony | BRD-SG-00760 | `Mamypoko Official` (parent-company store — Unicharm owns both Mamypoko and moony; verified this store sells both, no other brands) |
| Merries | BRD-GLOBAL-00021 | `Merries Official Store` |
| Nino Nana | BRD-SG-00754 | `Nino Nana ` (note: trailing space is literal in the merchant_name value) |
| Offspring | BRD-SG-00762 | `Offspring Official` |
| Pampers | BRD-SG-00823 | `Pampers Official Store` |

**Multi-brand stores excluded** (verified by checking full brand mix sold, not just Mall
badge — none of these get Pass-1 treatment for any brand):
- `Watsons Singapore Official Store` — sells MamyPoko, HUGGIES, Drypers, NOMIEO, Merries, Pampers, Desitin, Hello Bello (per existing beauty-vertical exclusion list, confirmed multi-brand here too)
- `Guardian SG Official Store` — sells Nino Nana, Merries, HUGGIES, Petpet, MamyPoko (pharmacy chain, same class as Watsons/Boots — add to baby vertical exclusion list)
- `BIG Pharmacy` — sells Sanrio, Drypers, HUGGIES, MamyPoko (pharmacy chain)
- `Diapers.com.sg Offical Store` [sic] — sells Pampers, moony, GOO.N, Genki!, MamyPoko, nepia Whito (multi-brand diaper specialty retailer)
- `myCK_online` — sells MamyPoko, Drypers, Pokana, NOMIEO, Merries (multi-brand retailer)
- `Weloveourkids` — single ambiguous 0-GMV mention for Mamypoko; excluded for lack of evidence it's brand-owned

**Brands with no official store found (Pass 2 only):**
- Goo.n, NOMIEO, Day&, Peachy Bum, `BRD-UNDEFINED`

---

## Scale

Review month: 2026-06-01.

| Metric | Count |
|--------|-------|
| Total source rows (model grain) | 41,398 |
| Distinct products | 7,606 |
| Rows badged `Shopee Mall` (any merchant) | 3,200 |
| Distinct products badged `Shopee Mall` (any merchant, **before** allowlist scoping) | 974 |
| **Rule A** — top-95%-cumulative-GMV products (GWP-zeroed) | 338 |
| **Rule B** — allowlist-only official-store products | 320 |
| **In-scope set (A ∪ B)** | **546** |

`category_3` is single-purpose (`Disposable Diapers` only, 100% of rows) — no mixed-content
keyword gate needed for brand ranking (unlike body_wash/liquid_milk).

The raw Mall-badged pool (974 products) is **not** the Pass 1 scope — after excluding the six
multi-brand retailers above, only 320 products belong to genuine brand-owned or parent-company
official stores. Pass 1 must scope to the allowlist only, per `docs/llm-extraction-rules.md`
§4 — confirmed via this run's own query, not assumed. The in-scope set overall (546) is
tractable for full per-product LLM read within one session, unlike the `shopee_sg_shampoo`
attempt #1 precedent (187,902-row official pool, correctly blocked).

---

## Scope — What's In vs Out

**In scope:**
- Diaper tape (ผ้าอ้อมแบบเทป-equivalent English listings), diaper pants

**Out of scope (leave NULL):**
- Cloth diapers, swim diapers/pants (different use case, verify per listing)
- Disposal tape stickers / roll-and-tie accessories (mirrors `ม้วนทิ้ง` exclusion documented for `th_baby_diapers`)
- Adult diapers (wrong category — none expected in this table's `category_3`, but verify if encountered)

**Edge cases:**
- To be logged here as Pass 1/2 encounters them.

---

## Taxonomy Design Notes

**Product line extraction approach:** to be filled in during Pass 1 as brand product lines are read from images/sku_name (e.g. Huggies has multiple named lines — Platinum, Dry Pants, Gold — confirm from packaging, never default to "Huggies Diapers").

**Size extraction notes:**
- Primary unit: piece count (`ชิ้น`-equivalent English "pcs"), plus diaper size band (NB/S/M/L/XL/XXL) — both matter; diaper size band is part of product_line/variant, not the `size` column (which should record pack quantity, e.g. "36pcs").
- Pack-count patterns expected: explicit counts in title ("36pcs", "Carton of 4"), bulk/carton listings need multiplier check per `docs/llm-extraction-rules.md` §1.

**Known difficult products:** to be logged during extraction.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-20 | Pre-run research | 908 HUMAN / 0 LLM existing map rows confirmed live (matches wrapper's first-run precheck and the documented `shopee_sg_diapers` precedent in `docs/headless-runbook.md`) | Proceeded as genuine first run |
| 2026-07-20 | Session handoff | Research + setup complete (brand scope, allowlist, SKU block SKU-091442–093441 claimed, Pass 1 worklist of 320 official-store products built and verified, image pipeline proven on 14 real products). Zero `product_taxonomy`/`product_taxonomy_map` rows written — Pass 1/2 extraction itself (546 in-scope products, each needing real per-size-band image confirmation since diaper pack pcs is not derivable from `sku_name` text alone, e.g. carton pcs varies by size band and must be read off the pack) is genuinely large and was not rushed. See Session Handoff section below for exactly where to resume. | Session ended with `status='partial'`, `rows_created=0`. SKU block left `ACTIVE` — safe to reuse. |

---

## Session Handoff (2026-07-20, stopped after setup + worklist, before extraction)

**What's done and durable:** category file (this document), SKU block claim, Pass 1 worklist query (below).

**Pass 1 worklist query** (regenerate the 320-product official-store list, product-grain, deduped):
```sql
WITH allowlist AS (
  SELECT * FROM UNNEST([
    STRUCT('Applecrumby® Official Store' AS merchant_name,'BRD-GLOBAL-00120' AS brand_id),
    ('BIC OFFICIAL STORE','BRD-SG-00980'), ('Drypers Official Store','BRD-SG-00361'),
    ('Huggies Official Store','BRD-GLOBAL-00211'), ('Kimberly-Clark Official Store','BRD-GLOBAL-00211'),
    ('Mamypoko Official','BRD-SG-00001'), ('Mamypoko Official','BRD-SG-00760'),
    ('Merries Official Store','BRD-GLOBAL-00021'), ('Nino Nana ','BRD-SG-00754'),
    ('Offspring Official','BRD-SG-00762'), ('Pampers Official Store','BRD-SG-00823')
  ])
)
SELECT s.product_id, ANY_VALUE(s.sku_name) sku_name, ANY_VALUE(s.image) image,
  ANY_VALUE(s.merchant_name) merchant_name, ANY_VALUE(d.canonical_name) brand_canon,
  ANY_VALUE(b.brand_id) brand_id, ROUND(SUM(CASE WHEN s.flag_GWP THEN 0 ELSE s.gmv_monthly END),2) gmv
FROM `sincere-hearth-273704.master_clean_niq.shopee_sg_diapers` s
JOIN `sincere-hearth-273704.magpie_reference.product_brand_map` b
  ON b.product_id = s.product_id AND b.platform='Shopee' AND b.country='SG'
JOIN allowlist a ON a.merchant_name = s.merchant_name AND a.brand_id = b.brand_id
LEFT JOIN `sincere-hearth-273704.magpie_reference.brand_dict` d ON d.brand_id = b.brand_id
WHERE s.month = DATE('2026-06-01') AND s.merchant_badge='Shopee Mall'
GROUP BY s.product_id ORDER BY brand_canon, gmv DESC
```
`--max_rows` must be raised above `bq query`'s default 100-row cap for this and any full-worklist pull.

**Image fetch mechanism (proven working):** `image` column has literal embedded `"` characters —
strip with `tr -d '"'` before `curl -sL -o /tmp/img.jpg "<url>"`, then `Read` the local file.

**Key finding that shapes remaining work:** diaper `sku_name` text states size **band** (NB/S/M/L/XL/XXL/XXXL)
reliably but usually does **not** state total piece count for single-size-band listings — pcs count varies
by size band even within one product line ("Bundle of 2 Cartons XL" ≠ same pcs as "...L"), so it must be read
off the pack image per size band, not assumed constant across a cluster's sizes. "Assorted (N packs)" /
"M-XXL" listings are multi-size-in-one-listing (buyer picks at checkout) → `is_multi_size=TRUE`, `size=NULL`,
`pack_count=N` (packs), not per-size pcs.

**Confirmed from images this session (reusable, do not re-fetch):**
| Product line | Size band | Total pcs | Source |
|---|---|---|---|
| Huggies Platinum Naturemade Pants | XL (12-18kg) | 228 (Bundle of 2 Cartons) | product 8943145582 |
| Huggies Naturemade Panda Pants | L (9-14kg) | 126 (single carton, 3×42) | product 26126446013 |
| Huggies Naturemade Overnite Pants | M (6-11kg) | 116 (single carton, 2×58) | product 41103176948 |
| Huggies Airsoft Pants | M (6-12kg) | 184 (1 carton = 4 packs × 46) | product 83478027 |
| Huggies AirSoft Tape | S (4-8kg) | 174 (1 carton = 3 packs × 58) | product 1064516244 |

**52 distinct HUGGIES sku_name clusters identified** (size/number-stripped pattern dedup) covering all 105
HUGGIES official-store products — see git history of this file / re-run the clustering script if needed
(strip `\b(NB|S|M|L|XL|XXL|XXXL|2XL|3XL|4XL)\b` and digits from `sku_name`, group by remainder).

**Next session should:** work brand-by-brand in GMV order (HUGGIES → Merries → Mamypoko → Drypers cover
~75% of category GMV), confirming pcs-per-size-band from one representative image per (product_line ×
size-band) combination — not per product_id — then bulk-map same-cluster products via text match, writing
batched DML (taxonomy inserts, then map inserts) rather than per-product single statements. Cross-product
bundles (e.g. "Huggies Pants XL + Huggies Pure Clean Wipes") map to the base diaper entry using the diaper
portion's size/pack only — wipes are same-brand, not a cross-brand `is_bundle` case.

---

## Targeted QA Fix Brief

> Not applicable yet — no taxonomy exists for this table. Fill in after Pass 1/2 if a
> follow-up Targeted QA Fix session is needed.

---

## Scripts

| Script | Purpose |
|--------|---------|
| N/A — this run performs extraction directly via Claude's own multimodal reading, no external script | |

---

## Map Row Counts (as of last run)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 0 (pre-run) | Pending this session |
| HUMAN | 908 | Long-tail keyword-seed routing, pre-dates this session |
| NULL (unmapped) | 6,698 (7,606 − 908) | Pending this session |
