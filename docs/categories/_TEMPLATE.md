# shopee_{country}_{category} — Category Context

> Copy this template for each new category. Fill in all sections.
> Keep this file updated after each session run.

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete / ⏳ In progress / ❌ Not started |
| LLM Pass 2 | ✅ Complete / ⏳ In progress / ❌ Not started |
| GMV Coverage | XX% (Apr 2026) |
| Last run | YYYY-MM-DD |
| Current MAX taxonomy_id | SKU-XXXXXX |

---

## SKU Blocks Assigned

| Block | Usage |
|-------|-------|
| SKU-XXXXX–XXXXX | Pass 1 OFFICIAL (N entries, N brands) |
| SKU-XXXXX–XXXXX | Pass 2 RESELLER (N entries) |
| SKU-XXXXX–XXXXX | QA corrections / gap fills |

---

## Brand Scope (GMV threshold 95%, Apr 2026)

N brands in scope. Listed by GMV rank:

1. **{Brand}** — `BRD-{SCOPE}-{ID}` — {GMV in M THB/SGD}
2. **{Brand}** — `BRD-{SCOPE}-{ID}` — ...
...

Brands excluded from scope (below 5% GMV tail): {list}

---

## Official Store Allowlist (Pass 1)

Built by querying distinct `merchant_name WHERE merchant_badge='Shopee Mall'` per brand_id.

| Brand | brand_id | Official Store Merchant Name |
|-------|----------|------------------------------|
| {Brand} | BRD-XX-XXXXX | `{Merchant Name Exactly As In BQ}` |
| {Brand} | BRD-XX-XXXXX | `{Parent Company Store Name}` |

**Multi-brand stores (require brand_from_image disambiguation):**
- `{Merchant Name}` — sells {BrandA}, {BrandB}, {BrandC}

**Brands with no official store (Pass 2 only):**
- {Brand}, {Brand}

---

## Scope — What's In vs Out

**In scope:**
- {product type 1}
- {product type 2}

**Out of scope (leave NULL):**
- {product type with Thai keyword} — e.g. ล้างมือ (hand wash)
- {product type}

**Edge cases:**
- {Specific brand or product}: {ruling and why}

---

## Taxonomy Design Notes

**Product line extraction approach:**
- {Brand}: extract from sku_name using `{keyword pattern}`
- {Brand}: uses parent company store — disambiguate via brand_from_image

**Size extraction notes:**
- Primary unit: ml / g / L / kg
- {Brand}-specific: {special size note}
- Pack-count patterns common in this category: {Thai patterns}

**Known difficult products:**
- {product_id} — {why it's hard} — currently routed to {SKU}

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| YYYY-MM-DD | Initial | {finding} | {fix} |
| YYYY-MM-DD | QA Gate A | {finding} | {fix} |

---

## Scripts

| Script | Purpose |
|--------|---------|
| `pipeline/05_product_taxonomy/llm_{table}/build_taxonomy.py` | Pass 1 extraction |
| `pipeline/05_product_taxonomy/llm_{table}/build_p2_taxonomy.py` | Pass 2 routing |
| `pipeline/05_product_taxonomy/llm_{table}/cleanup_refresh.py` | HUMAN cleanup + universe refresh |

---

## Map Row Counts (as of last run)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | N | Pass 1 + Pass 2 |
| HUMAN | N | Long-tail out-of-scope products (retained) |
| NULL (unmapped) | N | Below GMV scope or out-of-category |
