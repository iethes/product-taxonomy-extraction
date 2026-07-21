# shopee_th_body_wash — Category Context

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete (v3 rebuild) |
| LLM Pass 2 | ✅ Complete (v3 rebuild) |
| GMV Coverage | 75.5% LLM (Apr 2026); top-up Jul 20 2026 closed 92.4% of the live 95%-GMV coverage gap (Jun 2026) |
| Last run | Jul 20 2026 (top-up, Session 59); re-verified Jul 20 2026 (Session 60, zero new writes — residual 380 confirmed OOS); Jul 21 2026 (auto-discovery targeted QA fix, Session 61 — 95 entries fixed, no new SKUs minted) |
| Current MAX taxonomy_id | SKU-109606 |

**Version history:** v1 (Session 17, Jun 21) had NULL size everywhere. v2 (Session 48, Jun 23) had API auth errors → text fallback → generic names. v3 (Session 58, Jun 24) is the authoritative version using text-based smart extraction.

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-058000–058423 | Pass 1 OFFICIAL (424 entries, 56 brands) |
| SKU-057000–057569 | Pass 2 RESELLER (570 entries, 80+ brands) |
| SKU-036010–036015 | Bennett bar soap gap fill (6 entries, Session 41) |
| SKU-041230 | Shokubutsu x12 body moisturizer cross-ref |
| SKU-107746–109745 | Top-up coverage claim (Session 59, Jul 20 2026); 1,861 entries used (SKU-107746–109606), 139 slots unused |
| SKU-006000–006999 | DELETED (v1) |
| SKU-044000–044999 | DELETED (v2) |
| SKU-049000–049383 | DELETED (v2 dedup recovery) |

---

## Brand Scope (GMV threshold 95%, Apr 2026)

56 brands with official stores (Pass 1). 80+ brands in Pass 2. Key brands by GMV:

**Top-tier (Pass 1 official stores):**
- **Shokubutsu / Kodomo / Goodage / Kirei Kirei** — shared `Lion Shop Online` store (BRD-SG-00249)
- **Dove** — `Unilever Body Wash Official Store`
- **Lifebuoy** — Unilever store
- **Vaseline** — Unilever store
- **Safeguard / Protex** — P&G store
- **Lactacyd** — separate store
- **Shower Mate** — separate store
- **Enchanteur** — separate store
- **Biore** — `KAO Beauty & Personal Care`
- **Nivea** — `Nivea Body Official Store TH`
- **Citra** — Unilever store
- **Lux** — Unilever store
- **Bennett** — No official store (Pass 2 only → SKU-036010–036015)

---

## Official Store Allowlist (Pass 1)

| Brand | Merchant Name |
|-------|---------------|
| Shokubutsu, Kodomo, Goodage, Kirei Kirei | `Lion Shop Online` |
| Dove, Lifebuoy, Citra, Lux, Vaseline (body wash) | `Unilever Body Wash Official Store` |
| Safeguard | P&G official store |
| Biore | `KAO Beauty & Personal Care` |
| Nivea | `Nivea Body Official Store TH` |
| Lactacyd | standalone |
| Shower Mate | standalone |
| Enchanteur | standalone |

**Multi-brand stores (brand_from_image required):**
- `Lion Shop Online` — 4 brands: Shokubutsu / Kodomo / Goodage / Kirei Kirei

**Excluded retailers (multi-brand, not brand-owned):**
- Watsons, Boots, BigC, Lotuss, Tsuruha

**Brands with no official store (Pass 2 only):**
- Bennett, Parrot, and ~70 other reseller-only brands

---

## Scope — What's In vs Out

**In scope:**
- Body wash / shower gel (เจลอาบน้ำ, ครีมอาบน้ำ)
- 2-in-1 wash+soften (สบู่เหลว)
- Baby wash (สบู่อาบน้ำเด็ก)
- Kodomo Head-to-Toe Wash — INCLUDED despite containing แชมพู keyword

**Out of scope (leave NULL):**
- Hand wash (ล้างมือ, โฟมล้างมือ, สบู่ล้างมือ, hand wash)
- Feminine wash (เฟมินีน, feminine)
- Floor cleaner / dish soap
- Standalone shampoo/conditioner
- Body scrub (สครับ)

**Edge cases:**
- Kodomo Head-to-Toe: contains "แชมพู" keyword but IS body wash — the keyword exclusion must only fire when NO body wash keywords (อาบน้ำ, body wash, shower) AND NO "Head to Toe" phrase are present
- Multi-category NIQ: this table maps to 6 NIQ category_3 values (Body Wash, Baby Shampoo & Body Wash, Men's Body Wash, Hand Wash, Hand Cream) — universe refresh must use NIQ join, not a single category_3 filter

---

## Taxonomy Design Notes

**Product line extraction approach:**
- Every brand has its own `extract_{brand}()` function detecting product_line from sku_name text
- `Lion Shop Online` uses `lion_shop_route()` — routes by brand name keyword before product line
- Size extracted from Thai patterns: `(\d+(?:\.\d+)?)\s*(?:ml|มล\.?|g|กรัม|ก\.|oz)` — note: `ก.` is Thai gram abbreviation
- Pack-count: แพ็คคู่/แพ็ค 2/x2/Pack 2/ซื้อ1แถม1 = 2; ยกลัง = case qty; `N ฟรี M` same product = N+M

**Size extraction notes:**
- `ก.` is a short form of กรัม — regex must include `r'(\d+(?:\.\d+)?)\s*(?:g(?:r(?:am)?)?\.?|กรัม|ก\.)'`
- Without this, sizes like "105ก." in bar soap sku_names are missed

**Pack-count patterns common in this category:**
- `[N ฟรี M]` or `N แถม M` = buy N get M free → pack_count=N (M is GWP, NOT additional units)
- `แพ็คคู่` / `แพ็ค 2` / `x2` / `ซื้อ1แถม1` = pack_count=2
- Cross-product bundle: `Brand A Product xN + Brand B Product xN` → is_bundle=True

**Farsight DML special handling:**
- Multi-model products cause "UPDATE/MERGE must match at most one source row" error
- Fix: add `QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id, category_3, month ORDER BY taxonomy_id) = 1` to src subquery

---

## QA History

| Date | Session | Finding | Resolution |
|------|---------|---------|------------|
| Jun 21 | 17 | All 233 entries had NULL size | Full rebuild required |
| Jun 23 | 48 (v2) | API auth error → text fallback → generic names | Full rebuild v3 required |
| Jun 23 | 53 | Dedup script deleted 362 valid entries | Recovery: rebuild from orphaned map rows |
| Jun 24 | 58 (v3) | Final rebuild with text-based smart extraction | ✅ Clean, 75.5% GMV coverage |
| Jul 20 | 59 (top-up) | Live re-check (month 2026-06) found 3,286 in-scope-candidate rows (1,994 distinct products) with no taxonomy_id, despite category being marked complete — categories accumulate new listings over time. Bulk-first reuse-before-mint: grouped by (brand, size, pack_count, normalized product line text) rather than reading images per product. Only 18 products matched existing Pass 1/2 taxonomy entries (this gap is almost entirely new long-tail reseller listings, not variants of already-covered products) — 1,861 new taxonomy entries were minted, one per distinct group. 343 candidate rows (238 distinct products, ~2.39M THB) were confirmed out-of-scope (hand wash, standalone shampoo/conditioner, lice shampoo, scrub soap, bath bombs/onsen bath-salt powder — a distinct product type from body wash despite containing "bath" — and a body-lotion listing miscategorized into this table) and correctly left NULL. One Thai-Unicode variant (น้ํา using NIKHAHIT instead of the standard SARA AM in น้ำ) initially misrouted a genuine body-wash bundle to the OOS bucket; caught on manual review of the 347 OOS candidates and corrected. Brand resolution: 818 products had no product_brand_map brand at all (221 with zero row, 597 FALLBACK/Undefined); ~140 recovered via merchant-official-store-name cross-validated against sku_name text (e.g. "enfant.official" → Enfant), remainder minted under BRD-UNDEFINED with brand text left out of canonical_name rather than guessed. 628 of 1,861 new entries have no extractable size from text (bar soap sold by piece count, multi-size seller listings, etc.) — written as is_multi_size=TRUE, size=NULL per existing precedent rather than left unmapped. Per-row canonical_name wording precision (exact product_line phrasing, e.g. a few entries retain the brand name duplicated in product_line) intentionally not polished this session — deferred to `script/targeted_qa_fix.sh`, scoped by GMV impact. All hard gates (G1 dual-map, G2 HUMAN+LLM coexistence, G4 cross-category range, G5 provenance, placeholder-leak) verified 0 post-run. | ✅ Live worklist gap closed from 3,286→380 rows (~31.28M→~2.39M THB, 92.4% GMV reduction); remaining 380 rows all independently verified as correctly-classified out-of-scope, zero unexpected leftovers |
| Jul 20 | 60 (top-up, independent re-verify) | Wrapper re-fired the top-up job citing "380 unmapped products" as if new — re-ran the live STEP 0 worklist query rather than trusting the number: still exactly 380 rows / 238 distinct products / ~2.33M THB, matching Session 59's already-committed residual almost exactly (238 distinct products identical). Applied the per-product category/type gate live rather than only trusting Session 59's summary text: keyword-classified 337 of 380 rows against documented OOS categories (223 hand-wash/feminine/scrub, 110 standalone-shampoo, 4 conditioner); image-verified the 3 highest-ambiguity remainders per the "keyword gate must never decide extraction alone" rule — (1) "Perfect Official" โปรคละ 3 ชิ้น 1000 เฉพาะในไลฟ์ (9 rows, ~347K THB, the single largest unmapped chunk): cover image shows a buyer's-choice-of-3-of-7 mixed set (baby lotion, eyebrow serum, sunscreen, shower gel, 4-in-1 shampoo) — genuinely indeterminate which 3 items ship, left NULL per existing buyer-choice-bundle precedent; (2) TOPJapan/DONDONKI "Horse Oil" listings (สบู่/ยาสระผม/ครีมนวด, Body Soap/Shampoo variant-selector, 4 rows ~9.9K THB): image confirms a 3-way product-type variant selector (shampoo/conditioner/body soap) with no option-name data available to determine which model_id maps to the body-soap variant — left NULL, same "can't determine what buyer receives" precedent as multi-size ambiguous listings; (3) "Perfect" PREMIUM SET (1 row, 7.5K THB): image confirms a fixed 4-item cross-category bundle (shampoo+hair oil+shower gel+baby lotion) where only 1 of 4 items is body wash — left NULL, no precedent supports single-category-izing a mostly-other-category fixed set. Zero rows resolved to a mintable in-scope product; no SKU block claimed (nothing to write). QA gates re-run without --skip-coexistence: G1=0, G2=0, placeholder-leak=0, G5=0, structured-fields-missing=0% — unchanged from Session 59, confirming no regression. | ✅ Independently re-confirmed Session 59's finding via live re-query + per-product image verification of every high-ambiguity candidate (not just keyword text) — all 380 rows / 238 distinct products correctly out-of-scope or genuinely indeterminate (buyer-choice bundles). No writes made, no SKU block claimed. Live gap is 0 mintable products, not a fresh 380-product backlog — treat future wrapper re-fires on this exact residual as expected until new listings actually change the worklist |
| Jul 21 | 61 (auto-discovery, `_meta`-tracked) | First run of the new auto-discovery `targeted_qa_fix.sh` loop (no `## Targeted QA Fix Brief` existed) — worklist = 2,997 distinct never-reviewed/unconfident taxonomy entries. Tier 1 SQL sweep flagged 71 stub-leak, 8 duplicate-brand, 439 wrong-field-order, 10 brand-casing-mismatch, 20 excess-content candidates; each was individually judged rather than auto-applied. **Biggest finding:** 71 SKU-001xxx catch-all entries (predating this category's own SKU-057xxx/107xxx blocks, globally shared brand+category buckets from the pre-Phase-5 HUMAN keyword-seed era) had literal `"(all variants)"` canonical-name stubs banned by `quality-standards.md` — each covers dozens to 474 distinct real products under one generic `Brand + "Body Wash"` name. Renamed to the established `{Brand} {Line} Multiple Variants` convention (matches the `th_softdrink` precedent) and set `is_multi_variant=TRUE`; the underlying genericness (`product_line` still just "Body Wash") is a Full-Rebuild-scale problem — splitting hundreds of products per bucket into real per-product entries needs per-product image reads, out of this session's scope, flagged for a future Full Rebuild pass targeting this SKU-001xxx block specifically. Other confirmed-and-fixed defects: 12 entries with an impossible `size="0ml"` — root cause is comma-thousands-separator sizes ("1,000 ml") being misread as "000ml"→"0ml"; corrected to `1000ml` from the underlying `sku_name` text. 2 entries (`Aveeno Aveeno Baby Body Care`) had a literal duplicated-brand naming bug (same pattern as `th_moisturizer_for_face`'s fix), collapsed to one `Aveeno`. 2 entries (`"360" LRL ...`) had a stray duplicate "ml" token before the real size, stripped. §11 signal-provenance violations found via targeted scan: 3 "MORITOMO Official NAIVE Body Wash ... Set" entries had the reseller's store name baked into `canonical_name`/`product_line` and were mis-branded `BRD-UNDEFINED` even though `Naive` exists in `brand_dict` (`BRD-GLOBAL-01100`) — corrected brand_id, stripped the merchant name, and recovered the missing 360ml free-refill size from `sku_name`. 1 entry ("Qin Feisi ... goodhomeofficial CR081 ...") had the same merchant-name leak, stripped. §11 short/ambiguous-size cross-validation found 4 more G2G-style digit-collision misreads: `Philosophy ... 1g` (real size stated as "480ml (16oz)" in `sku_name`, size was misread from unrelated promo text), `Pinks Angel ... 1g x2` (misread from "1แถม1" promo language, no real gram weight stated — set to NULL, genuinely unresolved), `Fyne ... 04L` (fabricated from a stray "R04 l" product code with zero real size signal in `sku_name` — set to NULL), and `Medix5.5 ... 5.5g x5` (both size and pack_count misread from the brand's own "5.5" digits — real size "444ml" stated plainly in `sku_name`, no multiplier language present so pack_count corrected to 1). 96 content-fixing UPDATEs total (95 distinct taxonomy_ids, one entry touched twice across two defect classes), each resetting `_meta` to unreviewed and setting `meta_agent='CLAUDE_CODE'`. 451 rows judged correct (Tier 1 false positives): 435 `wrong_field_order` hits were `BRD-UNDEFINED` products correctly omitting brand from `canonical_name` per existing precedent (not a defect); the remaining 16 were brand-casing "mismatches" traced to `brand_dict` itself using non-standard casing (`"Safe guard"`, `"Benice"` vs. the taxonomy's more-correct `"Safe Guard"`/`"BeNice"`/`"Kirei Kirei"`) — a `brand_dict` data-quality note, not a taxonomy fix, plus one bilingual Thai+English `Protex` name and 4 legitimate two-size bundle entries (`Babi Mild ... 800ml + Refill 350ml x3 Bundle`) that correctly trip the "multiple sizes in one name" regex. **Findings left unfixed, flagged for follow-up (not blockers — nothing prevented completing the session):** (1) 2 taxonomy entries (SKU-107983, SKU-108497) are wet-tissue/wet-wipe products (ทิชชู่เปียก) mapped into the body_wash taxonomy under a garbage `brand="S"` (mis-scanned from a `(S)` size code in `sku_name`) — a genuine scope violation, but left as-is rather than deleting the `product_taxonomy_map` rows per this session's "never delete a row" instruction; needs a human scope decision. (2) SKU-108074 (3M hand soap) and SKU-108753 (a health-coffee product with "Deproud Official Store" baked into the name) are similarly out-of-category entries left untouched for the same reason. (3) ~14 excess-content-flagged entries are raw Thai marketing copy dumped wholesale as `canonical_name` (values look directionally correct, just not distilled to `Brand + Line + Size` format) — likely a much broader pattern across reseller-sourced entries in this category than just these 14; deferred to a dedicated distillation pass rather than one-off fixes this session. Hard gates re-verified post-run without `--skip-coexistence` (this category has already shipped): G1=0, G2=0, G5=0, placeholder-leak=0, structured-fields-missing=0%. Confidence distribution left behind: 451 `unconfident` (first-ever review, per the promote-on-agreement rule), 2,546 `unreviewed` (2,451 never touched this session + 95 freshly fixed and reset for re-review next run), out of 2,997 in the worklist. | ✅ 95 distinct entries fixed (96 UPDATEs), 451 judged correct, hard gates clean. Biggest structural finding (71-entry SKU-001xxx catch-all block, `"(all variants)"` stub naming) has its naming-convention violation fixed but its underlying per-product genericness flagged as Full-Rebuild-scope work, not resolved here. 3 scope-violation entries (wet wipes ×2, hand soap, coffee) and ~14 verbose-canonical-name entries flagged for follow-up, left unmodified |

---

## Scripts

| Script | Purpose |
|--------|---------|
| `pipeline/05_product_taxonomy/llm_th_body_wash/build_taxonomy_v3.py` | Pass 1 text-based extraction |
| `pipeline/05_product_taxonomy/llm_th_body_wash/build_p2_taxonomy_v3.py` | Pass 2 reseller routing |
| `/tmp/bw_p1_smart_text.py` | v3 Pass 1 (canonical version) |
| `/tmp/bw_p2_reseller.py` | v3 Pass 2 (canonical version) |
| `/tmp/bw_cleanup_and_refresh.py` | HUMAN cleanup + universe refresh |

---

## Map Row Counts (Jun 24 2026)

| Source | Count | Notes |
|--------|-------|-------|
| LLM/OFFICIAL | 856 | Pass 1, 56 brands × ~15 entries avg |
| LLM/RESELLER | 3,596 | Pass 2, 80+ brands |
| HUMAN | 3,167 | Long-tail out-of-scope products (retained) |
| Total universe rows | 61,512 | sincere; 61,531 farsight |
