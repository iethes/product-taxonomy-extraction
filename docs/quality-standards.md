# QA & Review Process — Product Taxonomy Extraction

> Every extraction run (Pass 1, Pass 2, NULL-coverage, or a targeted fix) is followed
> by a structured review before it ships to the universe. This document defines that
> review: the **scope** we hold ourselves to, the **6 quality dimensions** we score,
> the **hard gates** that must pass, and the **iteration loop** that connects them.
>
> Companion docs: [llm-extraction-rules.md](llm-extraction-rules.md) (the rules the LLM
> follows at extraction time) and [product-lifecycle.md](product-lifecycle.md) (how one
> product flows through the pipeline). This doc is what we check *after* a run.

---

## 1. The Review Loop

QA is not a one-shot check at the end — it is the loop that drives each category to
production quality across multiple iterations.

```
        ┌──────────────────────────────────────────────────────────┐
        │                                                          │
        ▼                                                          │
  ┌───────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌────┴─────┐
  │  EXTRACT  │──▶│  MEASURE │──▶│  TRIAGE  │──▶│   FIX    │──▶│ RE-MEASURE│
  │ (a run)   │   │ score 6  │   │ rank gaps│   │ targeted │   │  same 6   │
  │           │   │ dims +   │   │ by GMV   │   │ reroute/ │   │  metrics  │
  │           │   │ gates    │   │ impact   │   │ rebuild  │   │           │
  └───────────┘   └──────────┘   └──────────┘   └──────────┘   └────┬─────┘
                                                                     │
                                              all gates pass AND     │
                                              scores ≥ target?  ─────┤
                                                                     │
                                          NO ◀──────────────────────┘
                                          YES ▼
                                   ┌─────────────────────┐
                                   │  SHIP: universe      │
                                   │  refresh (sincere +  │
                                   │  farsight) + summary │
                                   └─────────────────────┘
```

**Triage rule:** always rank gaps by **GMV impact**, not row count. A single 7M-THB
product mapped to a generic stub matters more than 200 long-tail rows. Fix the
highest-GMV defects first; the long tail can remain `UNRESOLVED`.

---

## 2. The Review Scope (the denominator)

Every quality metric below is measured over **the in-scope set**, defined per category
per month (default review month: latest, e.g. `2026-04-01`). A product is **in scope**
if it satisfies **either** rule:

| Rule | Definition | Source decision |
|------|------------|-----------------|
| **A — Top-95% GMV** | Rank all products in the category by GWP-zeroed GMV descending; take products whose cumulative GMV ≤ 95% of category total | Decision 8 |
| **B — Official-store listings** | **Every** listing in any brand-principal official store, where that brand is within the 95% GMV brand scope — regardless of the individual listing's GMV | Decisions 7, 9 |

**In-scope set = A ∪ B.** This is the population that *must* be fully resolved. A NULL or
a generic stub **inside this set** that is identifiable from text/image is a defect.
Products **outside** this set (long-tail resellers, out-of-scope brands) may legitimately
remain `UNRESOLVED` — they are not counted against the quality scores.

```sql
-- In-scope set for a category (Rule A ∪ Rule B), review month 2026-04-01
WITH cat AS (
  SELECT u.product_id, u.master_table, u.brand_id, u.merchant_name, u.merchant_badge,
         SUM(u.gmv_monthly) gmv          -- GWP already zeroed upstream
  FROM `sincere-hearth-273704.magpie.marketshare_universe` u
  WHERE u.master_table = '{table}' AND u.month = '2026-04-01'
    AND u.ecommerce_platform = 'Shopee'
  GROUP BY 1,2,3,4,5
),
ranked AS (
  SELECT *,
    SUM(gmv) OVER (ORDER BY gmv DESC) / NULLIF(SUM(gmv) OVER (), 0) AS cum_frac
  FROM cat
),
scope_a AS ( SELECT product_id, master_table FROM ranked WHERE cum_frac <= 0.95 ),
-- Rule B: official-store allowlist is maintained per category (see docs/categories/*)
scope_b AS (
  SELECT product_id, master_table FROM cat
  WHERE merchant_badge = 'Shopee Mall'
    AND merchant_name IN UNNEST(@official_store_allowlist)
)
SELECT product_id, master_table FROM scope_a
UNION DISTINCT
SELECT product_id, master_table FROM scope_b;
```

---

## 3. The 6 Quality Dimensions (graded scores)

These are **GMV-weighted percentages over the in-scope set**. They are *scores*, tracked
across iterations, with target thresholds — not binary gates. The headline metric is D1.

| # | Dimension | Question | Target (GMV-weighted, in-scope) |
|---|-----------|----------|--------------------------------|
| **D1** | **Canonical Completeness** | Is the name fully structured, or a generic stub? | ≥ 90% Tier-A |
| **D2** | Product Line Accuracy | Is the real product line captured (not a category word)? | ≥ 95% |
| **D3** | Variant / Sub-line Coverage | Is the variant captured where the product has one? | ≥ 90% of variant-bearing |
| **D4** | Size Coverage | Is size extracted (or legitimately multi-size)? | ≥ 95% |
| **D5** | Pack-Count Correctness | Is the multiplier extracted/calculated right? | ≥ 95% |
| **D6** | In-Scope NULL Coverage | Are there identifiable in-scope products still NULL? | 0 identifiable |

### D1 — Canonical Completeness (the primary score)

Target structure: **`Brand + Product Line + [Sub-line/Variant] + Size + [xN]`**.
Each in-scope product's canonical name is graded into a tier:

| Tier | Definition | Example |
|------|------------|---------|
| **A — Complete** | Real product line **and** size present (or `is_multi_size`) **and** pack_count present | `Lifebuoy Total 10 Activ Silver Body Wash 450ml x2` |
| **B — Partial** | Real product line, but size or variant missing where it should exist | `Lifebuoy Total 10 Body Wash` (no size) |
| **C — Generic stub** | Product line is only a **category word** → name collapses to `Brand + Category` | `Lifebuoy Body Wash` ← **the failure you flagged** |
| **D — Unmapped** | In scope but `taxonomy_id IS NULL` | — |

**The D1 score = % of in-scope GMV in Tier A.** Tiers C and D are the defects to drive
to zero. Tier B is acceptable only where the listing genuinely lacks the attribute.

Detecting Tier C (generic stub) is the crux. A name is a stub when, after stripping the
brand, size, and `xN`, the remainder is **only** generic category tokens for that
category (maintained per category — e.g. body_wash: `body wash, shower gel, shower cream,
ครีมอาบน้ำ, เจลอาบน้ำ, สบู่เหลว`). Pure SQL can flag candidates; final tier assignment of
ambiguous cases is an LLM-assisted review of the flagged list.

```sql
-- D1 candidate stub detector: in-scope LLM entries whose product line looks generic.
-- Strip brand + size + xN, then test the remainder against the category's generic tokens.
SELECT pt.taxonomy_id, pt.canonical_name, SUM(u.gmv_monthly) gmv
FROM in_scope s                                   -- the §2 CTE
JOIN `sincere-hearth-273704.magpie.marketshare_universe` u USING (product_id, master_table)
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt ON u.taxonomy_id = pt.taxonomy_id
WHERE u.month = '2026-04-01'
  AND REGEXP_CONTAINS(
        LOWER(pt.canonical_name),
        r'(body wash|shower gel|shower cream|ครีมอาบน้ำ|เจลอาบน้ำ|สบู่เหลว)\s*(\d+\s*(ml|g|ก\.)|x\d+)?\s*$')
GROUP BY 1,2
ORDER BY gmv DESC;        -- highest-GMV stubs first → fix these first
```

### D2 / D3 — Product Line & Variant

- **D2** fails when the product line is wrong or generic. Overlaps with D1 Tier C, but
  also catches *mis-attributed* lines (right structure, wrong line — e.g. a Pantene
  "Total Damage Care" mapped to "Pro-V Miracles"). Caught by spot-checking the top-GMV
  products per brand against their images.
- **D3** fails when a variant-bearing product (flavor, formula, shade, scent) is merged
  into a variant-less entry — e.g. all Singha Soda flavors collapsed to one entry, or
  Pepsi Zero Sugar silently routed to Pepsi Cola. Detect by scanning sku_names within one
  taxonomy entry for distinct variant keywords.

### D4 — Size Coverage

```sql
-- In-scope LLM entries with NULL size that are NOT legitimately multi-size
SELECT pt.taxonomy_id, pt.canonical_name, SUM(u.gmv_monthly) gmv
FROM in_scope s
JOIN `sincere-hearth-273704.magpie.marketshare_universe` u USING (product_id, master_table)
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt ON u.taxonomy_id = pt.taxonomy_id
WHERE u.month = '2026-04-01' AND pt.size IS NULL AND pt.is_multi_size IS NOT TRUE
GROUP BY 1,2 ORDER BY gmv DESC;
```

### D5 — Pack-Count Correctness

Two failure modes: (a) `pack_count=1` but the listing is a genuine multipack (missed
multiplier); (b) wrong arithmetic on nested patterns (`[แพ็ก12] ยกลังx3` = 36, not 12).

```sql
-- pack_count=1 but promo/multiplier language present in sku_name → review each
SELECT m.product_id, s.sku_name, pt.canonical_name, SUM(s.gmv_monthly) gmv
FROM in_scope sc
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m USING (product_id, master_table)
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt ON m.taxonomy_id = pt.taxonomy_id
JOIN `sincere-hearth-273704.master_clean_niq.{table}` s
  ON s.product_id = m.product_id AND s.month = '2026-04-01'
WHERE pt.pack_count = 1
  AND REGEXP_CONTAINS(s.sku_name, r'แถม|1\+1|free|ฟรี|ซื้อ \d+ แถม|แพ็คคู่|ยกลัง|x\s*\d')
GROUP BY 1,2,3 ORDER BY gmv DESC;
-- Most "ฟรี" hits are GWP (correct pack=1); confirm against image before changing.
```

### D6 — In-Scope NULL Coverage

The "is anything we *should* have caught still NULL?" check. This is D1 Tier D, ranked by
GMV. Anything identifiable from text/image is a defect to fix this iteration.

```sql
SELECT u.brand_id, b.canonical_name brand, u.product_id, u.merchant_name, u.gmv_monthly
FROM in_scope s
JOIN `sincere-hearth-273704.magpie.marketshare_universe` u USING (product_id, master_table)
JOIN `sincere-hearth-273704.magpie_reference.brand_dict` b ON u.brand_id = b.brand_id
WHERE u.month = '2026-04-01' AND u.taxonomy_id IS NULL
ORDER BY u.gmv_monthly DESC;     -- top NULLs first; OOS/unidentifiable may stay NULL
```

---

## 4. Hard Gates (binary — must all pass before shipping)

These are structural-integrity invariants. Unlike the scores above, **any** violation
blocks the universe refresh. They are not "graded" — the only acceptable value is 0.

| Gate | Invariant | Query |
|------|-----------|-------|
| G1 | Zero dual-mapped products (1 product → 1 taxonomy) | below |
| G2 | Zero HUMAN+LLM co-existence for the same product | below |
| G3 | Zero TYPE_CONFLICT (wet↔dry, lotion↔oil, paste↔wash) | below |
| G4 | Zero cross-category mappings (face product → shampoo entry) | below |
| G5 | Every new row has `meta_agent` set and `source='LLM'` | below |
| G6 | Brand mismatches flagged, not silently mismapped | review `brand_mismatch=TRUE` |

```sql
-- G1: dual-mapped
SELECT product_id, master_table, COUNT(*) ct
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
WHERE master_table = '{table}' GROUP BY 1,2 HAVING ct > 1;          -- EXPECT 0

-- G2: HUMAN + LLM co-existence
SELECT product_id FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
WHERE master_table = '{table}' GROUP BY product_id
HAVING COUNTIF(source='LLM') > 0 AND COUNTIF(source='HUMAN') > 0;     -- EXPECT 0

-- G3: TYPE_CONFLICT (pet food example — adapt token sets per category)
SELECT m.product_id, s.sku_name, pt.canonical_name
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt ON m.taxonomy_id = pt.taxonomy_id
JOIN `sincere-hearth-273704.master_clean_niq.{table}` s
  ON s.product_id = m.product_id AND s.month = '2026-04-01'
WHERE m.master_table = '{table}'
  AND REGEXP_CONTAINS(LOWER(s.sku_name), r'wet|เปียก|ซอง|pouch|can|กระป๋อง')
  AND REGEXP_CONTAINS(LOWER(pt.canonical_name), r'dry|เม็ด|kibble');   -- EXPECT 0

-- G4: cross-category — taxonomy entries mapped here that belong to another category's block
--    (compare taxonomy_id ranges against docs/categories/STATUS.md for this category)

-- G5: provenance completeness
SELECT COUNT(*) FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
WHERE master_table='{table}' AND (meta_agent IS NULL OR source IS NULL);  -- EXPECT 0
```

---

## 5. Scorecard — what we record each iteration

Capture this block in the category file ([docs/categories/](categories/)) and the session
log after every run, so progress is visible across iterations:

```
Category: shopee_th_body_wash   |   Run: v3 Pass 2   |   Month: 2026-04-01
In-scope products: 1,842  (Rule A: 1,610 · Rule B: 412 · overlap 180)

QUALITY SCORES (GMV-weighted, in-scope)        GATES
  D1 Canonical Completeness  Tier-A  82%  ▲     G1 dual-mapped ........ 0  ✅
     (B 11% · C 5% · D 2%)                      G2 HUMAN+LLM .......... 0  ✅
  D2 Product Line ........... 94%               G3 TYPE_CONFLICT ...... 0  ✅
  D3 Variant ................ 88%               G4 cross-category ..... 0  ✅
  D4 Size ................... 91%               G5 provenance ......... 0  ✅
  D5 Pack-Count ............. 96%               G6 brand_mismatch .. flagged
  D6 In-scope NULLs ......... 14 (top GMV: 3)

Decision: NOT shipped — D1 Tier-C 5% (12 stubs, top 1.1M THB) → fix then re-measure.
```

A run **ships** only when: **all gates = 0** AND **D1 Tier-A ≥ 90%** AND **D4, D5 ≥ 95%**
AND **D6 has no identifiable in-scope NULLs above a GMV floor**. Otherwise → triage → fix
→ re-measure (the §1 loop).

---

## 6. GMV Coverage Targets by Stage

Coverage is the *floor* metric (did we map enough GMV at all); the §3 dimensions measure
whether what we mapped is *correct and complete*.

| Stage | Source | Target Coverage | Notes |
|-------|--------|-----------------|-------|
| Keyword seed (HUMAN) | Text matching | 50–70% | Baseline before LLM |
| LLM Pass 1 (OFFICIAL) | Multimodal | +15–25% | Official-store products: near-100% of official GMV |
| LLM Pass 2 (RESELLER) | Multimodal | Total ≥ 85% | Resellers in 95% GMV brand scope |
| NULL coverage pass | Multimodal | Total ≥ 90% | Top NULL products mapped individually |

```sql
-- Category GMV coverage (Apr 2026)
SELECT
  COUNTIF(taxonomy_id IS NOT NULL) mapped_products, COUNT(*) total_products,
  ROUND(SUM(IF(taxonomy_id IS NOT NULL, gmv_monthly, 0)) / SUM(gmv_monthly) * 100, 1) gmv_coverage_pct
FROM `sincere-hearth-273704.magpie.marketshare_universe`
WHERE master_table = '{table}' AND month = '2026-04-01' AND ecommerce_platform = 'Shopee';
```

---

## 7. Common QA Failures and Fixes

| Failure | Dimension | Root Cause | Fix |
|---------|-----------|-----------|-----|
| Generic canonical names (`Lifebuoy Body Wash`) | D1/D2 | API auth error → text fallback; or text-only extraction | Rebuild with real LLM calls; verify `ANTHROPIC_API_KEY` in subprocess env |
| NULL size across all entries | D4 | `size` not populated in insertion script | Rebuild: extract size (sku_name→image→spec→description) before building the taxonomy dict |
| Variant collapse (all flavors → one entry) | D3 | No per-variant entries created at Pass 1 | Create variant entries; reroute matching map rows |
| `pack_count=1` for `ยกลัง`/nested listings | D5 | Thai bulk pattern absent from parser | Add regex; recompute nested `[แพ็กN] ยกลังxM` = N×M |
| In-scope Mall product still NULL | D6 | Brand missed in allowlist / Thai-only sku_name router gap | Add to allowlist; add Thai keyword router |
| Wrong-category entries in map | G4 | Pass 2 used global taxonomy search without category filter | Pre-sweep delete; re-route by brand_id within category |
| Dual-mapped products | G1 | Streaming buffer + duplicate inserts; multi-option source rows | Dedup: keep most-specific (has_size > pack_count DESC) entry |
| HUMAN rows not cleaned up | G2 | Cleanup deferred past 90-min streaming buffer | Re-run cleanup once buffer clears |
| Farsight DML "match at most one source row" | ship | Multi-model products: many rows per (product_id, category_3, month) | `QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id, category_3, month ORDER BY taxonomy_id)=1` in src |

---

## 8. Where this connects

| Need | Doc |
|------|-----|
| The rules the LLM applies *during* extraction | [llm-extraction-rules.md](llm-extraction-rules.md) |
| How one product flows raw → brand → taxonomy → universe | [product-lifecycle.md](product-lifecycle.md) |
| Per-category scope, official-store allowlist, edge cases | [docs/categories/](categories/) |
| What's done vs pending, SKU range map | [docs/categories/STATUS.md](categories/STATUS.md) |
| How to run an extraction + universe refresh | [runbook.md](runbook.md) |
