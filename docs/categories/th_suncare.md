# shopee_th_suncare — Category Context

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete (v2 rebuild) |
| LLM Pass 2 | ✅ Complete (v2 rebuild, Pass 2 + Pass 3) |
| GMV Coverage | 65.0% v2-only (Apr 2026) — narrower single-session pass than v1's iteratively-built 85%; 90 v1-only products (not yet re-covered by v2) kept live to avoid a coverage regression, see Map Row Counts |
| Last run | Jul 17 2026 (v2 rebuild) |

**Version history:** v1 (through Jun 19 2026, 3 passes) reached ~85% GMV but had 10 catch-all entries with literal `(all variants)` text in canonical_name (product_line/sub_line generically filled with the category name, is_multi_size incorrectly false) and 34/321 entries (10.6%) with NULL pack_count. v2 (Jul 17 2026, session cost $19.89, 196 turns) fixed both defects (0 `(all variants)` leaks, 0 NULL pack_count across 709 new entries) and broadened Pass 2/3 candidate pool coverage (4,250 products vs v1's 677), but reached only 65.0% GMV in one session vs v1's multi-session 85%. Cutover was scoped, not blanket: 587 v1 LLM rows + 3 HUMAN rows superseded by v2 were deleted from the live map; 90 v1-only LLM rows and 11 HUMAN-only rows were kept live because v2 doesn't cover those products yet. Full v1 snapshot preserved in `magpie_reference.product_taxonomy_map_backup_th_suncare_v1_20260717` / `..._taxonomy_backup_th_suncare_v1_20260717`. A follow-up NULL-coverage iteration targeting the unmapped Pass 2/3 candidates (~1,823 products) is the natural next step to close the GMV gap.

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-082151–082859 | v2 rebuild: Pass 1 OFFICIAL + Pass 2 RESELLER + Pass 3 long-tail (709 entries), Jul 17 2026 |
| SKU-003353–003516 | v1 Pass 1 OFFICIAL — retired from live map except 90 products not covered by v2 (backed up in full) |
| SKU-003517–003546 | v1 Pass 2 RESELLER ≥THB 50k — retired from live map except uncovered products (backed up in full) |
| SKU-005885–005957 | v1 Pass 3 long-tail 95% GMV — retired from live map except uncovered products (backed up in full) |
| SKU-000787–000820 | Wave-4 keyword seeds (Biore, LRP, MizuMi TH + Cosrx/Bioderma + Shiseido/Cute Press/Charmiss etc.) |
| SKU-000001–000558 | Waves 1–3 keyword seeds |

---

## Brand Scope

**Pass 1 (official stores):** Top-10 brands by GMV — L'Oreal, ANESSA, Isdin, Srichand, Clear Nose, Biore, La Roche-Posay, Eucerin, MizuMi + more

**Pass 3 long-tail (16 brands):** ROUND LAB, ICE LERSKIN, Dr.Pong, Elixir, Ingu, Terry, SKINPRO Rx, Canmake, Sibling, Cathy Doll, iMin, Beauty of Joseon, Vaseline, Banana Boat, KA, Nivea

**Cathy Doll breakdown (9 distinct product lines):**
Ultra Light Sun Fluid, Aqua Sun Body Serum (Bright Up / Cool Up / PDRN), Sun Mist, CC Body Primer, Sun Essence, Hydrofill Sun Serum, Invisible Sun Matte

---

## Taxonomy Design Notes

**Brand mismatches found:**
- Vaseline Official Store selling Citra products → flagged brand_mismatch=TRUE
- Banana Boat listing selling Sunplay products → flagged

**GWP rule established here (Decision context):** Option lists (not cover image) are authoritative for multi-variant detection. "buy-1-get-1-free" / free-foam = GWP → pack_count=1. `[แพ็คคู่]` / `x2pcs` / "SAVE 50% duo" = genuine pack≥2.

**LRP routing order fix (Decision 12 origin):** Route "Oil Control Gel Cream" BEFORE "Oil Control" to prevent generic catch-all from capturing specific products.

---

## Targeted QA Fix Brief

> Source: shopee_th_suncare long-tail coverage backfill (brainstormed 2026-07-17, after v2 rebuild +
> brand_map_gap_fix). Read this whole section as the scope for the next
> `script/targeted_qa_fix.sh shopee_th_suncare <BLOCK_SIZE> <MAX_TURNS>` run — it is the actual work, not
> background. **Use a larger BLOCK_SIZE/MAX_TURNS than the 200/30 defaults** (e.g. 1200 / 400) — this is a
> several-hundred-product coverage backfill, not a small surgical fix; the defaults are sized for the latter.

**Verdict: NULL-COVERAGE BACKFILL (not full rebuild, not a structural-defect fix).** v2's Pass 1–3 already
built a clean, correctly-structured taxonomy (0 `(all variants)` leaks, 0 bad NULL pack_count — see QA
History). The remaining gap is pure coverage: products within the 95%-cumulative-GMV threshold that still
have no taxonomy_id at all. As of the last live check this was **891 products** — do NOT trust that number,
re-query live per STEP 0 below, since prior partial sessions may have closed more of the gap since this was
written.

### STEP 0 — Get the live worklist (do not trust any number in this file)

Run with `--max_rows=100000` or `--format=csv` — `bq query`'s default display silently truncates to 100 rows,
which caused an earlier session to under-process its worklist by ~9x without realizing it:

```sql
WITH base AS (
  SELECT s.product_id, s.model_id, s.merchant_name, s.merchant_badge, s.sku_name, s.image,
         s.gmv_monthly, s.flag_GWP, pt.canonical_name AS canonical_name
  FROM `sincere-hearth-273704.master_clean_niq.shopee_th_suncare` s
  LEFT JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_map` ptm
    ON ptm.product_id = s.product_id AND ptm.master_table = 'shopee_th_suncare'
  LEFT JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt ON pt.taxonomy_id = ptm.taxonomy_id
  WHERE FORMAT_DATE('%Y-%m', s.month) = '2026-06'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY s.product_id, s.model_id ORDER BY CASE ptm.source WHEN 'LLM' THEN 1 WHEN 'HUMAN' THEN 2 ELSE 3 END, ptm.taxonomy_id ASC) = 1
),
with_cumulative AS (
  SELECT *, ROUND(100.0 * SUM(CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END) OVER (ORDER BY gmv_monthly DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) / NULLIF(SUM(CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END) OVER (), 0), 2) AS cumulative_gmv_pct
  FROM base
)
SELECT * FROM with_cumulative
WHERE cumulative_gmv_pct <= 95 AND canonical_name IS NULL
ORDER BY gmv_monthly DESC
```

### STEP A — Reuse-before-mint (CRITICAL)

Before minting any new taxonomy_id, search `magpie_reference.product_taxonomy` for an existing entry (brand +
product line + size, compared via `canonical_name` text, not `sku_name` string-matching) describing the SAME
physical product. Reuse it via a new `product_taxonomy_map` row. Only mint a genuinely new entry (from your
claimed block) when no match exists. This is not optional — v2 already built 709 entries and prior backfill
rounds added ~350 more; most remaining products are the SAME physical items sold by additional resellers, not
new SKUs.

### STEP B — Brand resolution edge cases

- **Multi-brand retailer mistagged as a brand**: already found once with `Eveandboy` (a Thai multi-brand
  cosmetics retailer, `brand_id=BRD-GLOBAL-00068`, incorrectly recorded in `product_brand_map` as if it were
  the product brand). Watch for this pattern generally — if a product's real brand (visible on the image/in
  the title) doesn't match what `product_brand_map` says, use the real brand on the taxonomy entry. Do NOT
  modify the existing `product_brand_map` row — that correction is a separate, deliberate process.
- **`brand_id='BRD-UNDEFINED'`**: attempt real identification from the image/title. If found, use it on the
  new taxonomy entry only (leave `product_brand_map` untouched). If genuinely unidentifiable, or the brand
  isn't in `brand_dict` at all, leave the product unresolved rather than guessing — note it in findings.
- **GWP products are IN scope** (revised 2026-07-17, see `docs/plans/phase5-product-taxonomy-plan.md`) — do
  not skip `flag_GWP=TRUE` rows. Map them like any other product: `pack_count=1`,
  `flag_GWP=TRUE` carried through, GMV still zeroed in ranking/threshold math only.
- **Out-of-scope leakage**: some rows in this source table aren't actually suncare (bundled non-suncare
  items, unrelated categories that leaked in). Skip these — do not force a taxonomy entry — and note them.

### Quality bar (same as every prior session on this category)

Real `product_line` (not a generic category-name placeholder like `'Suncare'`/`'Sunscreen'`), `sub_line`/
`variant` only where genuine signal exists, `pack_count` never left NULL without cause, no catch-all
`canonical_name` text like `(all variants)` unless `is_multi_size` is correctly set `TRUE` for a genuine
unsplittable catch-all. `meta_agent='CLAUDE_CODE'` on every row.

### Expected scale

This will very likely take more than one `targeted_qa_fix.sh` invocation to fully close — that's fine and
expected. Each run re-queries the live worklist (STEP 0), so it naturally picks up wherever the previous run
left off. Report exactly how far you got rather than rushing to a false "complete".

---

## QA History

| Date | Session | Finding | Resolution |
|------|---------|---------|------------|
| Jun 19 2026 | v1 (3 passes) | 10 catch-all entries with `(all variants)` canonical_name text, generic product_line='Suncare'/sub_line='Sunscreen', is_multi_size incorrectly false; 34/321 entries NULL pack_count | v2 rebuild required |
| Jul 17 2026 | v2 rebuild | Both defects fixed (0/709 leaks, 0/709 NULL pack_count) but v2-only GMV coverage (65.0%) fell short of v1's 85.0%; 90 v1-only products would have been dropped by a blanket cutover | Scoped cutover: kept 90 v1-only + 11 HUMAN-only rows live instead of deleting them; full v1 snapshot backed up before any write |
| Jul 17 2026 | brand_map_gap_fix | Live query found 100 products (95%-cumulative-GMV, zero prior `product_brand_map` rows) — narrower than the 121 cited at session start; trusted the live query per session instructions. 5 out-of-scope (GWP-only sunscreen inside a non-suncare set, or unidentifiable listing); 2 genuinely unresolved brands (Lively Nose, Dr.Mallika — not in `brand_dict`) | 92 `product_brand_map` rows written (source=LLM); 16 products reused existing SKU-082xxx entries, 74 new taxonomy entries minted (SKU-084151–084224, well inside the claimed SKU-084151–084350 block) for 75 products (one pair of duplicate mint proposals for the same physical CeraVe product collapsed to 1 entry); 9 mint entries required a size-field fix post-hoc (bundle "size" mistakenly left NULL without `is_multi_size=TRUE`, or a stray secondary-item size on the main line) — all resolved via sibling-entry inference or `is_multi_size=TRUE` fallback, 0 leaks remain |
| Jul 17 2026 | targeted_qa_fix (this session) | Live STEP 0 worklist still 891 in-scope NULL products, unchanged from the number written into this brief — despite `sku_block_registry` showing 6 intervening `longtail_backfill_*` sessions (batch1–8, retry_consolidated, retry_round2) between brief-writing and this session. Root cause found: batches 2–6 + retry_consolidated wrote 569 clean, non-dual-mapped `product_taxonomy_map` rows, but **every one of those rows points to a product with `cumulative_gmv_pct=100.0` and `gmv_monthly=0.0`** — entirely outside the 95%-cumulative in-scope definition this brief targets (§2 of quality-standards.md). Those sessions burned real effort on zero-GMV, out-of-scope products and never touched the actual worklist. batch1, batch5, batch7, batch8, retry_round2 remain `ACTIVE` in the registry with **zero** taxonomy rows written in their claimed ranges — consistent with those sessions hitting a blocker or crashing before writing (correctly left `ACTIVE`, not `FAILED_QA`, since nothing was written). Also reconfirmed the `Eveandboy`-mistagging pattern (STEP B) at much larger scale than `brand_map_gap_fix` found: 22+ products in this worklist alone carry `brand_id=BRD-GLOBAL-00068` (Eveandboy, a multi-brand retailer) in `product_brand_map` when the real brand — read from `sku_name`/image — is ANESSA, Elixir, La Roche-Posay, MizuMi, Sibling, Vaseline, Eucerin, or Srichand. One clear out-of-scope leak found and left unmapped: "PAPA FEEL Probiotic Soothing Care Silky Foam Cleanser 236ml" (GMV 111,671) — a facial cleanser, not suncare. | Resolved 58 in-scope-NULL worklist rows (52 unique products; some had multiple `model_id` rows) via reuse-before-mint against the existing SKU-082xxx/084xxx/085xxx/086xxx catalog: 48 products reused an existing taxonomy entry (with `brand_mismatch=TRUE` + `brand_from_image` set wherever the Eveandboy/retailer mistag applied), 6 new taxonomy entries minted (SKU-088551–088556, e.g. d'Alba UV Essence Waterfull+ Tone-Up Sun Cream Keyring Mini, Mediheal Madecassoside Repair Serum Sachet 2ml, Worshi Tone Up Cream Whitening Real Skin 65g, Citra Sunscreen Serum Blueberry 170ml, P.O.Care Daily UV Bright Body Serum HyaC+ Extra Glow 190ml, By365 Powdery UV Cream 60g x2) inside the freshly-claimed SKU-088551–089750 block. Verified two `d'Alba`/three `Elixir` top-GMV candidates against product images (text alone was ambiguous on shade/variant) before committing. Rejected several auto-matcher candidates on manual review for wrong pack_count (text said single unit, candidate was a bulk/duo entry, e.g. Verite, Smooth E, innisfree) or wrong product line (Eucerin "Spotless Day Fluid" vs the Sun Serum Spotless Brightening candidate — likely a different, non-suncare-primary Thiamidol line; left unmapped for a future session to re-examine with image/spec). 891 → 833 in-scope-NULL rows remain; all 4 hard gates (G1 dual-map, G2 HUMAN+LLM coexist, G5 provenance, placeholder-leak) pass at 0. Expected to need further sessions per this brief's own scale note. |

---

## Map Row Counts (Jul 17 2026, post-cutover)

| Source | Count | Notes |
|--------|-------|-------|
| LLM (v2) | 4,250 | v2 rebuild, SKU-082151–082859 |
| LLM (v1 remnant) | 90 | Kept live — not yet covered by v2, avoids coverage regression |
| HUMAN | 11 | Long-tail retained — no LLM coverage from either version |
| Live map total | 4,351 | Matches universe_taxonomy_overlay refresh row count |
| v1 full backup (pre-cutover) | 691 (677 LLM + 14 HUMAN) | `magpie_reference.product_taxonomy_map_backup_th_suncare_v1_20260717` |
| LLM (brand_map_gap_fix) | +91 map rows / +74 taxonomy entries | SKU-084151–084224, Jul 17 2026 — see QA History |
