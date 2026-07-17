# shopee_th_detergent — Category Context

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete |
| LLM Pass 2 | ✅ Complete |
| GMV Coverage | ~85% (Apr 2026) |
| Last run | Jun 21 2026 |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-010000–010190 | Full taxonomy (191 entries, 27 brands) |

---

## Brand Scope

27 brands. Key brands: Ariel, Persil, Breeze, Kao Attack, Downy (detergent line), Biomax, Magiclean (EXCLUDED — floor cleaner).

**Magiclean exclusion:** Despite appearing in brand rankings, Magiclean products are floor/toilet cleaners, not laundry detergent. Leave all Magiclean products NULL.

---

## Scope — What's In vs Out

**In scope:** Laundry detergent (liquid, powder, pod/capsule), fabric conditioner-detergent combos

**Out of scope:**
- Floor cleaner (Magiclean, Flash, Mr. Muscle)
- Dish soap / dishwasher tablets
- Toilet cleaner

---

## Map Row Counts (Jun 21 2026)

| Source | Count | Notes |
|--------|-------|-------|
| LLM/OFFICIAL | 949 | Pass 1 |
| LLM/RESELLER | 948 | Pass 2, keyword routing from sku_name |
| HUMAN | 1,584 | Deleted; 2,606 retained (long-tail) |

---

## Targeted QA Fix Brief

> Source: TH Detergent QA Fix session brief (brainstormed 2026-07-17). Read this whole section as the
> scope for the next `script/targeted_qa_fix.sh shopee_th_detergent` run — it is the actual work, not
> background.

**Verdict: TARGETED FIX (not full rebuild).** Product line names are good quality. The single structural
failure is `pack_count=1` on every entry. Three secondary issues: wrong sizes on range-listings, bundle
misclassification, and high-GMV NULLs.

### Fix A — Pack_count multiplier expansion (MAIN TASK)

Every taxonomy entry at SKU-010xxx has `pack_count=1`. But ~20 of the top 50 products are bulk/multipack
listings. Examples:

- product_id 7180456348: `"[ยกลัง] 1100ml x6"` → canonical shows ×1
- product_id 8079936096: `"[ยกลัง] 4000g x3"` → canonical shows ×1
- product_id 13622158377: `"(1+1) 1500ml"` → canonical shows ×1
- product_id 2416987716: `"9,000g 2 ถุง"` → canonical shows ×1
- product_id 19159538388: `"[3แถม1] 1.8L x4"` → canonical shows ×1

**Approach:**
1. Pre-flight: claim the SKU block via the atomic `sku_block_registry` transaction immediately before the
   first insert. Do not trust this brief's numbers — a parallel session may have run since it was written.
2. Scan all LLM map rows for `shopee_th_detergent`, parse the multiplier from `sku_name` using these patterns
   (most specific first):
   - `[ยกลัง] N ถุง` / `N แกลลอน` → pack_count = N
   - `×12` / `x12` / `X12` → pack_count = 12
   - `[แพ็ค N]` / `แพ็ค N ถุง` → pack_count = N
   - `N แถม N` (same product) → pack_count = first N + second N
   - `(1+1)` / `1+1` → pack_count = 2
   - `N ชิ้น` (where N > 1) → pack_count = N
   - Default → pack_count = 1 (skip, already correct)
3. For each `(taxonomy_id, target_pack_count)` pair: check whether a variant entry already exists
   (`canonical_name LIKE '% xN'`). If yes, reroute the product to the existing variant. If no, create a new
   entry: `canonical_name = base_canonical + ' x' + N`. Reroute = DELETE old map row + INSERT new map row.
4. Dedup: `GROUP BY product_id` when querying — one product can have multiple model rows. Always keep exactly
   one map row per product_id.

### Fix B — Wrong-size reroutes (~6 products)

- **Product 22777858052**: `"[ทั้งหมด 6 ถุง] 1200-1350ml"` → currently at SKU-010000 (wrong product + wrong
  size). Find the correct Breeze Excel entry, create a ×6 variant.
- **Product 42226467434**: `"3.2-3.4L (เลือกสูตรด้านใน)"` → currently at SKU-010021 (3200ml).
  `เลือกสูตรด้านใน` = "formula selector inside" — this is a multi-variant listing, not a size range. DML
  UPDATE: set `is_multi_variant=TRUE`, `size=NULL`.

### Fix C — Bundle + multi-variant tagging

- **Product 42601768145**: `"[Exclusive Set] Breeze Excel Cotton Candy 1100ml + Comfort Beauty Perfume
  1050ml"` → currently at SKU-010009 (Breeze only). Create a new entry: "Breeze Excel Signature + Comfort Set
  1100ml", `is_bundle=TRUE`. Reroute the product to the new bundle entry.
- **Product 29119882389**: `"[ซื้อคู่] Hygiene wash 2800ml + fabric softener 3300ml"` → create a bundle entry:
  "Hygiene Expert Wash + Fabric Softener Set", `is_bundle=TRUE`, `size=NULL`, `pack_count=1`.

### NULL coverage pass — top 100 NULL products

Re-query NULLs **after** Fix A completes — many will be auto-covered by the new xN variants. Then handle the
remaining high-value NULLs:

**Needs a new taxonomy entry:**
- 40368556782: Nancy Oxy powder 24 pcs/box → create "Nancy Oxy Powder 24-pack"
- 24422635034: Lion SUPER NANOX Anti-Bacteria → create a new product line entry
- 46802825229: P&G Bold Power Gel Ball 4D → create "Bold Power Gel Ball 4D"
- 26623461217: Haiter Color 800ml แพค 3 → create "Haiter Color Liquid 800ml x3"

**OOS / leave NULL (do not map):**
- 27834214127: fabric bleach powder (stain remover, not detergent)
- 4510907051: DIY raw chemicals kit
- 4235171948: pool chemical
- 22371042619: DMSO industrial chemical

### QA gates (run before universe refresh)

Handled by `script/qa_report.sh shopee_th_detergent` (no `--skip-coexistence` — coexistence must be a genuine
0 for a Targeted QA Fix). In addition to the standard 4 gates, spot-check:

```sql
-- Pack count distribution should now include x2/x3/x4/x6/x12 variants
SELECT pack_count, COUNT(*) n FROM product_taxonomy
WHERE taxonomy_id LIKE 'SKU-010%' GROUP BY 1 ORDER BY pack_count;

-- Confirm top-5 GMV products now have correct pack_count
-- product 7180456348  → expect pack_count=6
-- product 8079936096  → expect pack_count=3
-- product 13622158377 → expect pack_count=2
```

### Universe refresh

Runs after gates pass, scoped to `shopee_th_detergent` only, `sincere-hearth-273704` overlay table only (see
`docs/headless-runbook.md` § Universe refresh — farsight refresh is dropped for this design, no farsight
equivalent of `universe_taxonomy_overlay` exists). `shopee_th_detergent` maps to multiple `category_3` values
(Laundry Detergent + Baby Laundry Detergent at minimum) — the standard NIQ-join MERGE already handles this
correctly, no per-category_3 filter needed.

### Reference

- Extraction rules: `docs/llm-extraction-rules.md` §1 (pack) + §2 (size)
- Prior art (pack multiplier): th_liquid_milk, th_pet_food sessions (see `docs/llm-extraction-rules.md`
  changelog)
- Prior art (bundle): th_softdrink QA sessions
- SKU-010xxx = detergent block (191 entries used, 809 remain at 010191–010999) — new entries for this session
  go in a freshly claimed 200-slot block, never reuse 010191–010999 without re-verifying it's still free.

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
