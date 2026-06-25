# LLM Extraction Rules

> Living document. Update immediately after each category review reveals a new rule.
> These are UNIVERSAL rules that apply to every category (TH and SG) unless a
> category-specific override is noted.
>
> Last updated: Jun 24 2026 (added explicit size + pack_count extraction priority chains to §1/§2)

---

## 1. Pack Count & Multiplier

**The hardest part to get right.**

**Extraction priority (consult signals in this order):**
1. **`sku_name` text** — promo phrases (`ซื้อ 2 แถม 1`, `1+1`, `6+1`) and explicit
   multipliers (`x2`, `แพ็คคู่`, `ยกลัง N`) are stated here most often. Start here.
2. **Product image** — count the physical units in the pack shot. **The image is the
   tiebreaker: when text and image disagree on the count, the image wins.**
3. **`product_specification`** (`raw_niq_history`) — fallback when text and image are
   silent or ambiguous on quantity.
4. **`product_description`** (`raw_niq_history`) — last resort; marketing copy, lowest trust.

Default `pack_count = 1` only after all four signals are exhausted and none indicates a
multipack. Never leave `pack_count` NULL.

> This mirrors the size priority in §2. The one difference: for *size*, text wins over
> image; for *pack_count*, image wins over text (you can miscount from a title, but the
> pack shot shows exactly how many units ship).

| Pattern in text / image | pack_count | Notes |
|--------------------------|-----------|-------|
| "ซื้อ 2 แถม 1" / "buy 2 get 1 free" | 3 | Buyer receives 3 of same product |
| "ซื้อ 1 แถม 1" / "buy 1 get 1" / "1+1" | 2 | Buyer receives 2 of same product |
| "6+1" / "x6+1" / "5+1" | 6+N | Count the total units received |
| "ฟรี N ชิ้น" — freebie is SAME product | 1+N | e.g. "ฟรี 2 ชิ้น" → pack_count=3 |
| "ฟรี N ชิ้น" — freebie is DIFFERENT product | 1 | flag_GWP=TRUE, NOT a multipack |
| Image shows stacked/bundled units | match image | Override text if different |
| Text says range "x2" + image confirms | match image | Never use text range as-is |

**GWP vs genuine multipack — the critical distinction:**
- **GWP** = a *different* product given free (body wash + shampoo sampler = GWP).
  → pack_count=1, flag_GWP=TRUE, GMV zeroed in threshold calculations
- **Genuine multipack** = multiple units of the *same* product.
  → pack_count=N, NOT GWP, counts toward GMV threshold

**When text says a size range AND a multiplier (e.g. "155–170ml x2"):**
→ Use the image-confirmed size (not the range), keep the multiplier from image.
→ If image is ambiguous, use the *larger* value in the range.

**False positive patterns — do NOT count as multipacks:**

| Text pattern | Correct action | Notes |
|---|---|---|
| "มี N สูตรให้เลือก" | pack_count=1 | N formula options to select, not N units bundled |
| "มี N แพ็คให้เลือก" | pack_count=1 | N pack sizes to select from, not N units in this listing |
| "แพ็คเกจใหม่" / "new package" | pack_count=1 | New packaging design, not a multipack |
| "3 สินค้าในหลอดเดียว" | pack_count=1 | "3 ingredients in 1 tube" — formulation claim, not bundle |
| "มี N สูตรในขวดเดียว" | pack_count=1 | Multiple formulas in one bottle — not a multipack |

**`[แพ็กคู่]` in product title (square-bracket format) = ALWAYS pack_count=2.**
The bracket position distinguishes it from the false-positive patterns above — it appears as part of the product name, not as a description of buyer options.

---

## 2. Size

**Extraction priority (consult signals in this order):**
1. **`sku_name` text** — the seller almost always states size in the title
   (`200ml`, `400g`, `1L`). **Text wins:** never override a size clearly stated in the
   title with a guess from the image.
2. **Product image** — read the size off the pack when the title is silent or ambiguous,
   and to resolve a size *range* in the title (see below).
3. **`product_specification`** (`raw_niq_history`) — structured weight/volume fields;
   fallback when title and image don't yield a size. Often empty for personal care.
4. **`product_description`** (`raw_niq_history`) — last resort; marketing copy, lowest trust.

Return `UNRESOLVED` (leave size NULL only via a genuine `is_multi_size=TRUE` entry) only
after all four signals are exhausted.

- **size must not be NULL** for any product where size is visible in the image or product name.
- **"All variant" / "All size"** entries are not acceptable as canonical names. Use:
  - A specific size if the product comes in one size
  - `is_multi_size=TRUE` + a meaningful name if it genuinely covers multiple sizes
- **Size range in text** ("155–170ml"): resolve against image. Image wins.
- **Size from option list**: option/variant dropdown is authoritative when image is ambiguous.
- **Units**: always write units explicitly — "200ml", "400g", "1L", not "200", "400", "1".
- **Bulk pack multiplier in canonical name**: write only the total as `x{TOTAL}`. Never add a
  breakdown suffix like `(N packs of M)`. Use `x90` not `x90 (15 packs of 6)`. The total
  is what analysts need for market sizing; the pack breakdown belongs in sku_name, not canonical.

---

## 3. Product Line Naming

- Use the **exact product line name as shown on the product packaging/label**.
- **Never** use generic category words as the product_line unless the label literally says so:
  - ❌ "Body Lotion", "Moisturizer", "Body Cream", "Shampoo", "Conditioner"
  - ✅ "Intensive Care Deep Restore", "Smooth Skin", "Repair & Protect"
- **Never repeat the brand name** in product_line — it's already captured in brand_id.
- When the LLM cannot confidently read the product line from the image, write
  `product_line = "{Brand} (unresolved)"` and flag for human review — do not guess.
- **Routing order rule (Decision 12):** match the most-specific phrase first, then fall back
  to generic. E.g. check "Oil Control Gel Cream" before "Oil Control".
- **Sub-line disambiguation for look-alike brands**: Eucerin, CeraVe, La Roche-Posay and
  similar clinical brands have multiple product lines that look similar in thumbnails
  (Hyaluron Filler vs AtoControl vs pH5; SA vs Blemish Control; B5+ vs Cicaplast). Always
  read the full sub-line name from the label — do not group into generic brand catch-alls
  unless the sub-line is genuinely unreadable. If unreadable, write `"{Brand} (unresolved)"`
  and flag for review.

---

## 4. Official Store Allowlist (Pass 1)

- Build an **explicit per-brand allowlist** by querying distinct Mall merchant_names
  per brand_id before each Pass 1 run. Do not use `LIKE '%official%'` or `LIKE '%brand%'`.
- **Always exclude multi-brand retailers** from the allowlist, regardless of Mall badge:
  - Beauty: Watsons, Boots, BEAUTRIUM, Sasa, Tsuruha
  - Grocery/FMCG: BigC, Lotuss, Tops, Villa Market
  - Pet: PET N ME, PetPaw
  - Baby: (check per category)
- Some brands use **parent company store names** — must be discovered per brand:
  - Biore → "KAO Beauty & Personal Care"
  - Dove, Sunsilk, Clear → "Unilever [category] Official Store"
  - Salz, Systema, Zact → "Lion Shop Online"
- A brand with **no official store** skips Pass 1 entirely and goes directly to Pass 2.

---

## 5. Scope Exclusions

Universal: never map a product to a taxonomy entry in the wrong category.
If a product is out of scope, leave it unmapped (NULL) — do not force it to a catch-all.

**Category-specific scope rules confirmed so far:**

| Category | Include | Exclude |
|----------|---------|---------|
| body_wash | body wash, shower gel, 2-in-1 wash+soften | hand wash (ล้างมือ), feminine wash, floor cleaner, standalone shampoo/conditioner |
| fabric_softener | fabric softener, 2-in-1 wash+soften | ironing spray, laundry-only detergent, Downy Gel Ball detergent |
| toothbrush | manual + electric toothbrush, replacement heads | toothpaste, mouthwash, nasal stickers (Happy Noz), cloth diapers |
| toothpaste | toothpaste, tooth serum, tooth gel, whitening serum, enamel repair | toothbrush (unless GWP), mouthwash (น้ำยาบ้วนปาก) set as main product, oil pulling (oil pulling/ออยล์พูลลิ่ง), candy/lozenge (ลูกอม), denture cleanser (Polident = hard OOS) |
| detergent | laundry detergent | floor cleaner (Magiclean), dish soap |
| moisturizer_for_body | body lotion, body cream, body serum, body milk | hand cream (if separate category), face moisturizer |
| baby_diapers | diaper tape, diaper pants | disposal tape sticker (ม้วนทิ้ง), cloth diapers |
| drinking_water | still drinking water, natural/sparkling mineral water, plain alkaline water (no functional additives), **Ichitan น้ำต่าง (plain water, no vitamin additives) = IN SCOPE** | Ichitan Alkaline Water ผสมวิตามิน / Vitamin B / Vitamin D & Ginkgo (functional beverage — OOS even though brand appears in scope list), Pocari Sweat (sports/ion drink), water filter equipment, chlorine test kits |

Add new rows here as each category is reviewed.

---

## 6. Image Reading Priority

When text and image conflict, use this priority order:

1. **Product image** (the main product photo) — authoritative for product line, variant, size
2. **Option/variant list** — authoritative for multi-variant detection and per-option sizes
3. **Product name / sku_name** — use when image is ambiguous or missing
4. **Merchant description** — last resort, lowest trust

**Cover image caveat:** the cover/hero image may show a different product from the one
being sold. Always check the product-specific image, not the banner/lifestyle image.

---

## 7. Brand Mismatch Detection

Every LLM extraction call should extract `brand_from_image` from the product image.

- If `brand_from_image` ≠ `brand_canonical` AND `product_brand_map.source IN ('PRODUCT_NAME_SCAN', 'FALLBACK')`:
  → flag `brand_mismatch=TRUE`
- If source is `BRAND_FIELD` or `HUMAN`: trust the existing assignment, skip check.
- Confirmed mismatches should be queued for: brand_dict update + product_brand_map update
  + partial universe re-run. Do not auto-correct during extraction.

---

## 8. Operational Rules

**SKU block pre-assignment (Decision 16):**
- Query `MAX(taxonomy_id)` ONCE before spawning any parallel agents.
- Assign non-overlapping 1,000-slot blocks upfront. Never let agents query MAX at launch.

**Streaming buffer:**
- Wait **90 minutes** before deleting rows that were just inserted in the same session.
- Old HUMAN rows from prior sessions: no buffer needed, delete immediately.

**Backups:**
- Always backup `product_taxonomy` and `product_taxonomy_map` before each category run.
- Snapshot query: `SELECT COUNT(*) FROM product_taxonomy` + `product_taxonomy_map`
  recorded in session notes before any writes.

**meta_agent:**
- All Phase 5 rows written by Claude Code: `meta_agent = 'CLAUDE_CODE'`
- Never leave meta_agent NULL on new rows.

**Universe refresh after each category:**
- Run `/tmp/refresh_universe_taxonomy.py` (sincere first, then farsight).
- Confirm row counts match expected delta before refreshing summary tables.

**Brand scope GMV threshold — filter to category sku_names first:**
- When calculating which brands are in the 95% GMV scope, filter sku_names to
  category-relevant products BEFORE summing GMV. Source tables can contain mixed products.
- Example: `shopee_th_body_wash` contains hand wash, feminine wash, and baby shampoo. A
  hand-wash-only brand would appear in the brand rank if GMV is summed across all sku_names.
- Pattern: add a keyword guard (`has_body_wash_keyword(sku_name) = TRUE`) in the GMV query,
  or use the NIQ category mapping to pre-filter to in-scope products only.
- This applies to every category with a mixed-content source table.

---

## 9. Thai Language Specifics

- Brand name format: `"Vaseline(วาสลีน)"` — strip the Thai in parentheses when normalizing.
- Zero-width spaces (U+200B) sometimes appended to brand names — strip before matching.
- **Thai phonetic brand names** — when a product has `BRD-UNDEFINED` or `source=FALLBACK`
  and the sku_name contains a Thai phonetic brand name, look up the correct brand_id from
  brand_dict and reroute to the correct taxonomy entry:
  - แป๊บซี่ / เป็บซี่ → Pepsi
  - โคคา-โคล่า / โค้ก → Coca-Cola
  - เฮไนเก้น / ไฮเนเก้น → Heineken
  - เรดบูล → Red Bull
  - มาเม่ → Mamee / Mamé
  Do not leave BRD-UNDEFINED products unmapped when the brand is phonetically identifiable.

- Thai promo language quick reference:
  - แถม = "free / bonus" (context determines GWP vs multipack — see Section 1)
  - ฟรี = "free"
  - ซื้อ = "buy"
  - ชิ้น = "piece/unit"
  - แพ็ค / แพ็กเกจ = "pack"
  - ขนาด = "size"
  - มล. = ml, กรัม = g, ลิตร = L

---

## 10. QA Checks (run after every category)

> **The full review process — the 6 quality dimensions (canonical completeness, product
> line, variant, size, pack-count, in-scope NULL coverage), the in-scope definition, the
> hard gates, and the iteration scorecard — lives in
> [docs/quality-standards.md](quality-standards.md).** Read it before reviewing any run.
> The quick gate queries below are a subset for convenience.

These checks should pass before doing any universe refresh:

```sql
-- A. Zero dual-mapped products
SELECT product_id, COUNT(*) FROM product_taxonomy_map
WHERE master_table = '{table}' GROUP BY 1 HAVING COUNT(*) > 1;
-- expect 0 rows

-- B. Zero HUMAN + LLM co-existence for same product
SELECT product_id FROM product_taxonomy_map WHERE master_table = '{table}'
GROUP BY product_id
HAVING COUNTIF(source='LLM') > 0 AND COUNTIF(source='HUMAN') > 0;
-- expect 0 rows

-- C. Official-store products in 95% GMV scope that are still NULL
-- (join universe WHERE taxonomy_id IS NULL AND merchant_badge='Shopee Mall'
--  AND brand_id IN scope_brands)
-- expect 0 rows

-- D. LLM rows with size IS NULL where size is readable
-- (join product_taxonomy WHERE size IS NULL AND canonical_name NOT LIKE '%all%'
--  cross-check sku_name for ml/g/oz pattern)
-- flag any rows — not hard fail, but must review

-- E. Pack_count = 1 but product name contains promo language
-- (source='LLM' AND pack_count=1 AND sku_name REGEXP 'แถม|1\+1|free|ฟรี')
-- flag any rows — review against image before accepting

-- F. Tier-1 NULL coverage: top-GMV brands with official stores should have zero NULLs
-- SELECT brand_id, COUNT(*) null_ct
-- FROM marketshare_universe WHERE taxonomy_id IS NULL AND country='{country}'
--   AND category_3='{cat}' AND month='2026-04-01'
--   AND merchant_badge='Shopee Mall'
-- GROUP BY brand_id HAVING COUNT(*) > 0
-- expect 0 rows — any Mall product from a scoped brand without taxonomy is an extraction miss
```

---

## Changelog

| Date | Category | Rule added |
|------|----------|-----------|
| Jun 19 2026 | th_suncare | Routing order: specific before generic (Decision 12) |
| Jun 19 2026 | th_suncare | GWP vs multipack distinction; "ฟรี N ชิ้น" same product = pack |
| Jun 21 2026 | th_body_wash | Scope: exclude hand wash, feminine wash, floor cleaner |
| Jun 21 2026 | th_shampoo | Multi-variant dedup: exact duplicate LLM rows from multi-option inserts |
| Jun 21 2026 | th_toothbrush | Multi-brand LDC Online Store = single-brand representative (Jordan/Linko) |
| Jun 21 2026 | th_fabric_softener | 2-in-1 wash+soften = in scope; Downy Gel Ball detergent = exclude from Downy P1 |
| Jun 21 2026 | th_pet_food | Multi-brand Mall stores (PET N ME etc.) excluded via explicit name filter |
| Jun 22 2026 | th_moisturizer_for_body | Size range → use image; "1+1"/"2 free 1" pack_count rules; no generic product line names |
| Jun 23 2026 | th_moisturizer_for_body | QA pass: 14 new xN taxonomy entries (SKU-041000–041013, relocated to SKU-041216–041229 due to softdrink collision), 87 rerouted products. "แพ็คเกจใหม่"/"package" = new packaging NOT a multipack (false positive). "มี N แพ็คให้เลือก" = N size options to choose from NOT N units (false positive). "[แพ็ค N]" in title brackets = genuine N-unit multipack. "เซ็ตคู่" in canonical_name requires pack_count=2 in the taxonomy entry. |
| Jun 23 2026 | th_moisturizer_for_body | Routing dedup risk: when querying suspect products with GROUP BY on (taxonomy_id, confidence, brand_from_image, brand_mismatch), a product with N existing map rows returns N reroute groups → inserts N new rows. Always GROUP BY product_id only, then take MAX(sku_name), to produce exactly 1 reroute row per product. |
| Jun 23 2026 | th_softdrink | Scope: soft drinks only. Multi-size seller listings (seller offers any of 5 different sizes in one sku) → skip, can't determine what buyer receives. Mystery/assortment boxes → skip. Pack count from Thai patterns: "รวม N ขวด" (most reliable), "[xN] M กระป๋อง" = N×M, "แพ็คN" (no brackets), "x N" / "X N" (spacing), "N+M กระป๋อง/ชิ้น" = N+M. Bundle = " + " pattern with brand names in sku_name. Sarsi sold under Oishi brand_id (BRD-GLOBAL-00900, Sermsuk distributes both) — use canonical "Sarsi". ZWS Coca-cola brand (BRD-GLOBAL-00521) = route to real Coke taxonomy entries. Singha has dual brand_id (BRD-GLOBAL-00047 Singha + BRD-GLOBAL-01008 Sing). |
| Jun 23 2026 | th_softdrink | SKU block collision warning: verify MAX(taxonomy_id) immediately before first insert in every session, not just from CLAUDE.md notes. Session 43 body moisturizer QA extended to SKU-041000–041013 (not captured in session notes), causing collision when this session started at SKU-041000. Fix: relocate conflicting entries to new block before writing new taxonomy. |
| Jun 23 2026 | th_softdrink | Nested multiplier pattern "[แพ็กN] ยกลังxM" in sku_name = N×M total units (e.g. "[แพ็ก12] ยกลังx3" = 36). Regex scan must check both `แพ็ก` (not กระป๋อง) and `ยกลังx\d` (no space). Separate taxonomy entries required for each total pack_count; never merge x12 and x36 under one entry. |
| Jun 23 2026 | th_softdrink | Singha Soda flavor differentiation: flavored variants (Lemon, Red Lemon, Pink Lemon, Cream Soda, Ume Lemon, Watermelon) require separate taxonomy entries — do not merge all under generic "Singha Soda". Flavor is extractable from sku_name text (รสพิงก์, รสครีมโซดา, รสแตงโม, มะนาวโซดา). Generic entry kept only for assorted/all-flavors listings (ทุกรสชาติ, รสชาติต่างๆ). |
| Jun 23 2026 | th_softdrink | Bundle taxonomy naming standard: "Brand A Product Size xN + Brand B Product Size xN" with pack_count = N+M total units. A Coke Less Sugar 1.5L x12 + Fanta Orange 1.5L x12 bundle has pack_count=24, not 12. Use is_bundle=True on the taxonomy entry. |
| Jun 23 2026 | th_softdrink | Heineken 0.0 naming: canonical = "Heineken 0.0 Alcohol Free Beer 330ml x24" (not "Non-Alcoholic 0.0"). Brand = BRD-GLOBAL-00871. |
| Jun 23 2026 | th_softdrink | A&W Root Beer: real brand, BRD-TH-01451 (canonical_name "AW" in brand_dict — full name A&W). Products mapped to BRD-UNDEFINED in product_brand_map but still map to A&W taxonomy correctly via product_taxonomy_map. |
| Jun 23 2026 | th_softdrink | BRD-UNDEFINED Coke/Fanta products: resellers listing Coke/Fanta products get BRD-UNDEFINED brand from PRODUCT_NAME_SCAN (brand field not filled). Map these to correct Coca-Cola or Fanta taxonomy entries regardless — taxonomy mapping does not require brand_id consistency with product_brand_map. |
| Jun 23 2026 | th_softdrink | Flavor-variant gap: when a flavor variant has zero taxonomy entries (e.g. Pepsi Zero Sugar), all products silently fall back to the base-flavor entry (e.g. Pepsi Cola). Initial LLM extraction must create entries for ALL major flavor variants, not just the original. QA scan: check each tier-1 brand's products for distinct flavor keywords (ไม่มีน้ำตาล, ซีโร่, สตรอเบอร์รี่) to detect contamination. Remediation = create new entries + reroute all matching map rows. |
| Jun 23 2026 | th_softdrink | Mixed-flavor contamination at single-flavor taxonomy entries: after creating new flavor-specific entries, always scan EXISTING entries for products that belong to the new entry. Products often route to the wrong entry silently (e.g. Coke Zero Sugar at "Coke Original 325ml x6", Fanta Green at "Fanta Assorted 250ml x24"). Run sku_name keyword scan against all mapped products to catch cross-flavor contamination. |
| Jun 23 2026 | th_softdrink | Multi-brand Cola listings (e.g. seller offering Pepsi, Coke, Fanta, A&W, Schweppes in one SKU as buyer-choice) → leave NULL. Multi-size seller listings (seller offers choice of 300/345/545ml in one SKU) → create ONE entry with is_multi_size=TRUE, size=NULL, pack_count=NULL — canonical "{Brand} {Line} Multiple Sizes". This allows the product to appear in the universe with a taxonomy_id while flagging that size cannot be determined. |
| Jun 23 2026 | th_softdrink | Multi-variant seller listings (same brand, multiple flavor/formula variants buyer selects from, e.g. Coke Original / Less Sugar / Zero Sugar) → create ONE entry with is_multi_variant=TRUE — canonical "{Brand} Multiple Variants". Distinct from multi-size (same product, different quantities). |
| Jun 23 2026 | th_softdrink | NULL-coverage pass new brand scope: 7UP (Lemon Soda No Sugar 325ml x24/x72, No Sugar 345ml x12), Lipton Za (No Sugar 325ml x24, Lemon 245ml x72), Hite Zero (All Free 355ml x4/x6/x12), Chi Forest (Sparkling Assorted 330ml x24), San Pellegrino (Mineral 500ml x24, Pompelmo 330ml x24), Mountain Dew (330ml x24/x48), Mirinda (Blueberry Orange 440ml x24), Canada Dry (Diet Ginger Ale 350ml x12), Barbican (Pomegranate 330ml x6), Ibev (Date Soda 250ml x24), Kickapoo Joy Juice (Orange 325ml x24), Hokkaido Migoto (Melon/Peach Soda No Sugar 325ml x6), Leo Soda small bottle (280ml x120/x240), Hata Kosen Ramune (Original 200ml x6), Orangina (Orange 330ml x3), Fever Tree (Premium Mixer Assorted 200ml), Mind Kombucha (Sparkling 240ml x12), Red Bull Soda (Blueberry 250ml x24), Lorina (Sparkling Lemon-Lime 330ml x12), Tan San Su (Soda Water 330ml x24), P80 (Longa 325ml x24), BIG Ajemin (Assorted Flavors), Zuza (Assorted 4 Flavors x48), Sarsi (325ml x24, 250ml/325ml x48). |
| Jun 23 2026 | th_softdrink | Cross-brand bundle taxonomy (e.g. "Ichitan 280ml x24 + เย็นเย็น Soda 280ml x24"): use brand_id of the primary brand (first-named in sku_name), set is_bundle=True, pack_count = total units. Canonical follows standard bundle format with " + " separator. |
| Jun 23 2026 | universal | **Bulk pack canonical name = x{TOTAL} only.** Never write "(N packs of M)" breakdown. x90 not x90 (15 packs of 6). Analysts need clean totals; pack structure belongs in sku_name. |
| Jun 23 2026 | universal | **False-positive multipack patterns**: "มี N สูตรให้เลือก" (formula selector) and "มี N แพ็คให้เลือก" (size selector) = pack_count=1. "[แพ็กคู่]" in square brackets in product title = ALWAYS pack_count=2 (genuine bundle, not a selector). |
| Jun 23 2026 | universal | **Brand GMV threshold must filter to category sku_names first.** Source tables with mixed content (body_wash includes hand wash, liquid_milk includes cocoa powder) inflate out-of-scope brands into the GMV rank. Add keyword gate before summing GMV per brand. |
| Jun 23 2026 | th_drinking_water | Ichitan น้ำต่าง (plain water, no ผสมวิตามิน) = **IN SCOPE** despite brand appearing OOS for Alkaline+Vitamin products. Filter OOS by `brand_id AND 'vitamin' in sku_name` not by brand alone. |
| Jun 23 2026 | th_moisturizer_for_face | **Cross-category contamination pre-sweep**: before any rebuild, query all existing map rows for the table and verify taxonomy entries belong to the correct category. Session 38 found 1,802 face products mapped to shampoo/cleanser/makeup taxonomy (root cause: seed scripts used global taxonomy search without category filter). |
| Jun 23 2026 | th_body_wash | SIZE and PACK_COUNT are MANDATORY columns in product_taxonomy — never leave them NULL unless the product listing genuinely has no extractable size (e.g. multi-size seller listings). Session 17 omitted both fields on all 233 SKU-006xxx entries (structural failure requiring full rebuild). Always verify with `SELECT COUNT(*) FROM product_taxonomy WHERE brand_id IN (scope) AND size IS NULL AND taxonomy_id LIKE 'SKU-XXX%'` before declaring a session done. |
| Jun 23 2026 | th_body_wash | Universe refresh for tables with multi-category NIQ mapping: when a source table (e.g. shopee_th_body_wash) maps to multiple magpie_category_3 values (Body Wash, Baby Shampoo & Body Wash, Men's Body Wash, Hand Wash, Hand Cream), the DML UPDATE must use the NIQ join to cover ALL category_3 buckets — not a single `category_3 = '...'` filter. Use the standard pattern: `JOIN niq_category_mapping nm ON nm.master_table = m.master_table` in the src subquery, then `WHERE u.category_3 = src.category_3 AND u.country = src.country`. |
| Jun 23 2026 | th_body_wash | Scope keyword gate for body_wash: exclude ล้างมือ, hand wash, โฟมล้างมือ, สบู่ล้างมือ, เฟมินีน/Feminine, สครับ/scrub. EXCEPTION: "Head to Toe Wash" products (โคโดโม เฮดทูโท, KODOMO Head to Toe Wash) contain "แชมพู" keyword but ARE body wash products — include them. The `แชมพู` exclusion must only apply when there are NO body wash keywords (อาบน้ำ, body wash, shower, body) AND no "Head to Toe" phrase. |
| Jun 23 2026 | th_body_wash | Thai gram abbreviation: `ก.` is a short form of กรัม. Regex must include `r'(\d+(?:\.\d+)?)\s*(?:g(?:r(?:am)?)?\.?\|กรัม\|ก\.)'` — without `ก\.` the pattern misses sizes like "105ก." appearing in Thai soap sku_names. |
| Jun 23 2026 | th_body_wash | Bundle patterns (three types): (1) Refill-promo `[N ฟรี M]` or `N แถม M` = buy N get M free → pack_count=N (M is GWP, not additional units). (2) Genuine multipack: `แพ็คคู่`/`แพ็ค 2`/`x2`/`Pack 2`/`ซื้อ1แถม1` = pack_count=2. (3) Cross-product bundle: `Brand A Product xN + Brand B Product xN` → is_bundle=True, pack_count=total. Never merge refill-promo into genuine multipack — buyers pay for N units, not N+M. |
| Jun 23 2026 | th_body_wash | Farsight DML UPDATE for multi-model products: BQ throws "UPDATE/MERGE must match at most one source row for each target row" when the src subquery has multiple rows for the same (product_id, category_3, month) because the product has multiple model_ids. Fix: add `QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id, category_3, month ORDER BY taxonomy_id) = 1` to the src subquery. |
| Jun 23 2026 | th_toothpaste | OOS bundle detection for toothpaste: `is_oos_bundle(sku_name)` must catch (1) electric/manual toothbrush as main product (`^แปรงสีฟัน` at start of sku_name), (2) mouthwash SET as main product — `น้ำยาบ้วนปาก` is OOS only when NOT preceded by `ฟรี!?` or `แถม` (GWP mouthwash is OK), (3) toothbrush BUNDLED without GWP marker — `แปรงสีฟัน x\d+` or `พร้อมแปรง` or set-language without GWP, (4) oil pulling (`oil pulling`/`ออยล์พูลลิ่ง`), (5) candy/lozenge (`ลูกอม`). Hard OOS: Polident Denture Cleanser (brand-level exclusion, not keyword). |
| Jun 23 2026 | th_toothpaste | `parse_pack()` ฟรี! regex: Thai promotions use `"N ฟรี! M"` (exclamation mark AFTER ฟรี). Regex must be `r'(\d+)\s*ฟรี!?\s*(\d+)'` — without `!?` the pattern fails to parse `[แพ็คสุดคุ้ม 2 ฟรี! 1]` → pack_count stays at 1 instead of 3. Affects any promotion with `ฟรี!` syntax. |
| Jun 23 2026 | th_toothpaste | SKU block collision at SKU-045000: a drinking water quality pass ran in a parallel session and consumed SKU-045000–045231 at 04:33 UTC, before toothpaste rebuild started at 04:44 UTC. Both category sessions wrote to the same IDs. Resolution: (1) relocate toothpaste to SKU-047000–048257, (2) delete stale toothpaste taxonomy from collision zone after streaming buffer clears. Prevention: **always query `SELECT MAX(taxonomy_id) FROM product_taxonomy` immediately before first insert**, even if CLAUDE.md lists a pre-assigned block. CLAUDE.md may be stale if a parallel session ran between session planning and session execution. |
| Jun 23 2026 | th_toothpaste | Multi-variant product dedup in map rows: same product_id appearing multiple times in source data (multi-variant/multi-option listings) causes multiple map rows for the same product. Dedup before insert: for each product_id, keep the map row pointing to the most-specific taxonomy entry (has_size=1 > pack_count DESC). Use `pid_seen` set during build, or `entry_specificity()` sort + keep-first. |
| Jun 23 2026 | th_drinking_water | Scope: Ichitan Alkaline Water (with Vitamin B / Vitamin D & Ginkgo) = OOS (functional beverage, not plain water). Plain alkaline water from other brands (Siamdrink, Iceland Spring, Welle Alkaline) = IN SCOPE. Pocari Sweat = OOS (sports/ion drink). Water filter equipment, chlorine test kits = OOS. 95% GMV scope (Apr 2026): Singha, Crystal, Purra, Pure, Nestle, 6ty Degrees, evian, Minere, Welle, Aura, Iora, Mont Fleur, FIJI, Siamdrink, Iceland Spring, Undefined. |
| Jun 23 2026 | th_drinking_water | Bulk case pack count patterns (dominant mode — 79% of top-GMV products sell in multi-case lots): (1) "N แพ็ค รวม M ขวด" → M total (most reliable, M is stated explicitly). (2) "N แพ็ค M ขวด" → N×M total. (3) "N ขวด ฟรี M ขวด" (same product freebie) → N+M total (add the free bottles). (4) "3 FREE 1" pattern → 4 packs × base_pack. (5) "ยกลัง N ขวด" / "ลังละ N ขวด" → N total. (6) "N แพ็ค" alone → N × base_pack_per_case. Requires knowing BASE_PACK (bottles per standard case) per brand+size — build this lookup table before routing. |
| Jun 23 2026 | th_drinking_water | Purra 600ml standard case = 15 bottles (NOT 12). Base pack corrected from SKU-011071 which had pack_count=12. Always verify per-brand case sizes from official store product descriptions, not assumptions. Other verified base packs: Crystal 600ml=12, Crystal 1500ml=6, Singha 600ml=12, Singha 1500ml=6, Nestle 600ml=12, Nestle 1500ml=6, evian 500ml=24, evian 1500ml=12, Purra 1500ml=8, Minere 500ml=12. |
| Jun 23 2026 | th_drinking_water | OOS brand filter must check `canonical_name` (from brand_dict), not just sku_name substring — Ichitan's brand_dict canonical_name is "Ichitan" without "Alkaline" suffix. Filter `brand_id IN (ichitan_brand_ids)` rather than `'ichitan alkaline' in sku_name`. Products from OOS brands appearing in the category due to NIQ mislabeling: leave NULL. |
| Jun 23 2026 | th_drinking_water | **Canonical name format: always x{TOTAL}, never "(N packs of M)"**. Correct: "Crystal Drinking Water 1.5L x90". Wrong: "Crystal Drinking Water 1.5L x90 (15 packs of 6)". The breakdown is informational only and must not appear in canonical_name. Fixed 123 entries in SKU-045xxx via `REGEXP_REPLACE(canonical_name, r" \(\d+ packs of \d+\)$", "")`. |
| Jun 23 2026 | th_drinking_water | **NULL coverage pass OOS classification**: (1) Ichitan plain alkaline (น้ำด่างX.X with no ผสมวิตามิน) = IN SCOPE. (2) Any Ichitan product mentioning ผสมวิตามิน (Vitamin B/D/Ginkgo) = OOS. (3) Yanhee Drinking Water (plain) = IN SCOPE; Yanhee Vitamin B/C Water = OOS. (4) B'lue (vitamin-fortified functional water) = OOS. (5) Vitaday (vitamin water) = OOS. (6) Pocari Sweat (ion drink) = OOS. (7) กรวยน้ำดื่ม (paper drinking cups) = OOS (wrong product category). (8) Coffee brewing mineral concentrate = OOS. (9) Multi-size ambiguous listings (e.g. "[5/15 packs]" where the pack_count is the option selector) = SKIP. |
| Jun 23 2026 | th_drinking_water | **Welle freebie totals**: "(N ขวดฟรี M ขวด)" pattern = pack_count N+M (same product free bottles, not GWP). e.g. "(60 ขวดฟรี 15 ขวด)" = x75, "(108 ขวดฟรี 27 ขวด)" = x135. Do NOT use base_pack multiplier; use the explicit total stated in parentheses. |
| Jun 23 2026 | th_drinking_water | **Cross-brand Namthip/Coca-Cola**: products mapped to BRD-GLOBAL-00145 (Coca-Cola) in product_brand_map may be น้ำทิพย์ (Namthip) water products. Create taxonomy entries under BRD-SG-00926 (Namthip) and map these products to the Namthip taxonomy — the product_taxonomy_map does not require brand_id agreement between taxonomy and product_brand_map. Universe brand column comes from product_brand_map regardless. |
| Jun 24 2026 | universal | **Explicit extraction priority chains added to §1 and §2.** Size: `sku_name` text → image → `product_specification` → `product_description`; **text wins** over image (never override a stated size). Pack_count: `sku_name` text → image → spec → description; **image wins** over text (image is the tiebreaker — title can miscount, pack shot shows actual units). Previously the chain lived only in ARCHITECTURE.md/data-dictionary.md and was absent from the operative rulebook; the pack_count fallback order was undocumented. |
