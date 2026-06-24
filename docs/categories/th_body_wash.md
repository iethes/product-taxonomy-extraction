# shopee_th_body_wash — Category Context

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete (v3 rebuild) |
| LLM Pass 2 | ✅ Complete (v3 rebuild) |
| GMV Coverage | 75.5% LLM (Apr 2026) |
| Last run | Jun 24 2026 |
| Current MAX taxonomy_id | SKU-058455 |

**Version history:** v1 (Session 17, Jun 21) had NULL size everywhere. v2 (Session 48, Jun 23) had API auth errors → text fallback → generic names. v3 (Session 58, Jun 24) is the authoritative version using text-based smart extraction.

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-058000–058423 | Pass 1 OFFICIAL (424 entries, 56 brands) |
| SKU-057000–057569 | Pass 2 RESELLER (570 entries, 80+ brands) |
| SKU-036010–036015 | Bennett bar soap gap fill (6 entries, Session 41) |
| SKU-041230 | Shokubutsu x12 body moisturizer cross-ref |
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
