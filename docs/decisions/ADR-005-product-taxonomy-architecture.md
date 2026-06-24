# ADR-005 — Product Taxonomy Architecture

**Date:** June 2026
**Status:** Proposed — pending pre-build validation
**Decided by:** Magpie Analytics

---

## Context

Brand-level data (`brand_dict` + `product_brand_map`) is complete. The next layer is product-level consolidation: the same physical product sold by multiple merchants should resolve to one canonical identifier with a structured name. This ADR records the key architectural decisions and what was rejected.

See full planning document: [`docs/plans/phase5-product-taxonomy-plan.md`](../plans/phase5-product-taxonomy-plan.md)

---

## Decisions

### 1. Two new tables: `product_taxonomy` + `product_taxonomy_map`

Mirrors the `brand_dict` / `product_brand_map` pattern one level deeper.

- `product_taxonomy` — canonical product master, human-reviewed, grows slowly
- `product_taxonomy_map` — LLM-generated mapping at product_id grain, auto-refreshed

**Rejected:** Adding taxonomy columns directly to `product_brand_map`. The table is at product_id grain and would need new columns plus logic changes. Keeping them separate maintains clean separation of concerns and allows Phase 6 (model_id grain) without touching Phase 5 tables.

---

### 2. Mapping grain is product_id, not model_id

`product_taxonomy_map` PK: `(product_id, master_table)` — same grain as `product_brand_map` and the universe.

Model_id grain (full variant/size resolution) is deferred to Phase 6, where a separate `product_model_map` table will be introduced.

**Rejected:** Model_id grain for Phase 5. The universe is aggregated to product_id. A model_id-grain taxonomy would be more precise than the universe it serves. Build the finer grain only when the universe grain is also refined.

---

### 3. LLM inputs: `brand_canonical` (Phase 3), `sku_name`, `option_names[]`, `image` — no `_EN` variants

Input: `brand_canonical` (from `brand_dict` via Phase 3 join) + `sku_name` + aggregated `option_name` values + `image` URL.

`brand_canonical` replaces `brand_raw` — Phase 3 has already resolved brands. `sku_name_EN` and `option_name_EN` (machine-translated) are excluded; Claude handles Thai natively. `option_name` values are collected as an array per product_id (all distinct variants for that listing).

Image is used for ALL seller types, not only official stores. The two-pass distinction governs workflow (LLM vs. similarity match); images are always sent when available regardless of pass.

**Rejected:** `brand_raw` as LLM brand input. Already resolved by Phase 3; using raw form introduces noise and inconsistency.
**Rejected:** `sku_name_EN` / `option_name_EN`. Machine translation adds failure modes.
**Rejected:** Text-only LLM. Insufficient for sub-line extraction (UVMUNE 400 vs UVAIR).
**Rejected:** Images only for official stores. Reseller images are lower quality on average but still provide useful signal; confidence field reflects image quality naturally.

---

### 4. Two-pass extraction: official stores first, resellers second

**Pass 1** — Shopee Mall listings where `merchant_name` contains brand name or "official": run full multimodal LLM, build `product_taxonomy`.

**Pass 2** — Remaining listings for top 10 brands: text similarity match against established taxonomy; LLM only as fallback.

Official store listings have pack-shot images and brand-convention naming. They are the ground truth for canonical names. Reseller listings are noisier and should converge to the taxonomy anchored by official store data.

**Rejected:** Single-pass uniform extraction across all merchants. Wastes LLM calls on noisy reseller listings when official store data provides a cleaner signal. Also misses the opportunity to use similarity matching for cost efficiency in Pass 2.

---

### 5. Multi-variant / multi-size: NULL + boolean flags, not descriptive strings

When a product_id listing covers multiple variants or sizes, the ambiguous field is set to NULL and a boolean flag is set (`is_multi_variant`, `is_multi_size`). The canonical name is the concatenation of non-NULL fields only.

**Rejected:** "Multi Size", "Multi Variant" or similar strings in canonical name. These are data quality annotations, not product attributes. They corrupt client-facing reports, are unjoignable to clean product data from external sources, and create ambiguity between: `Nivea Facial Wash 60ml` (single SKU), `Nivea Facial Wash 120ml` (single SKU), and a hypothetical `Nivea Facial Wash Multi Size` (same product family, none joinable).

The NULL + flag approach allows analysts to filter for precision (`is_multi_variant = FALSE`) while still including all GMV in brand/product_line totals.

---

### 6. Canonical name structure: Brand · Product Line · Sub-line · Variant · Size

Sub-line is included as a distinct field — not merged into product_line or variant. Image sampling confirmed sub-line is a load-bearing distinction (e.g., La Roche-Posay Anthelios `UVMUNE 400` vs `UVAIR` are different sub-lines within Anthelios, each with multiple variants).

**Rejected:** Brand + Product Line + Variant + Size (no sub-line). Sub-line is required for at least La Roche-Posay Anthelios and other multi-sub-line product families. Omitting it would merge distinct product groups under one product_line.

---

### 7. Human review gate before BQ write for new `product_taxonomy` entries

New entries are staged for human review before insertion, similar to the `brand_review` step in the brand phase. Deduplication normalisation (lowercase + strip punctuation) is applied before lookup to catch LLM inconsistency (`"UVMUNE 400"` vs `"UVMUNE400"`).

**Rejected:** Fully automated taxonomy creation. Silent duplicates corrupt consolidation and are hard to detect after the fact.

---

### 8. `source_listing` field on `product_taxonomy_map`

Each mapping row records whether it came from an official brand store or a reseller. Enables downstream analysis of official vs. reseller channel without re-querying merchant data.

---

### 9. Bundle multiplier is explicit in canonical name; `pack_count` replaces `is_bundle` as source of truth

Bundle listings (x2, x3, etc.) get distinct taxonomy_ids with the multiplier written into the canonical name: `Senka Perfect Whip Original 120g x2` is a different taxonomy entry from `Senka Perfect Whip Original 120g`.

`pack_count` (INT64) is the source of truth: 1 = single unit, 2/3/etc. = bundle size, NULL = bundle detected but count unclear. `is_bundle` is derived (`pack_count > 1 OR (bundle detected AND pack_count IS NULL)`) and stored for query convenience. Size in the canonical name always refers to the single-unit size; the multiplier is appended as ` x{N}`.

**Rejected:** `is_bundle = TRUE` flag while keeping the same canonical name as the single unit. Creates two taxonomy_ids with identical canonical names — a dedup and reporting failure.
**Rejected:** Omitting bundle count from canonical name. Clients reading reports need to know if a "50ml" row represents a single tube or a 2-pack. The difference is material for price benchmarking and unit-level share calculations.

---

### 10. Brand correction scope: `brand_mismatch` only for `PRODUCT_NAME_SCAN` and `FALLBACK` sources

`brand_from_image` is extracted and stored for all products. `brand_mismatch = TRUE` is only set when `product_brand_map.source IN ('PRODUCT_NAME_SCAN', 'FALLBACK')`:

- `BRAND_FIELD` — seller explicitly declared the brand → authoritative → no correction triggered
- `HUMAN` — manually verified → no correction triggered
- `PRODUCT_NAME_SCAN` — brand inferred from product name text → image verification applies
- `FALLBACK` — brand undetermined → image may now identify it → image verification applies

**Rationale:** `BRAND_FIELD` is the seller's own declaration — the most direct signal available. Inferred mappings (`PRODUCT_NAME_SCAN`, `FALLBACK`) have meaningful error risk and benefit from the independent image signal.

**Rejected:** Applying mismatch check to all sources uniformly. Generates false correction flags for `BRAND_FIELD` products where the seller's own brand declaration is correct.

---

### 11. Brand correction feedback loop: Phase 5 → Phase 3

For confirmed `brand_mismatch` cases (source = `PRODUCT_NAME_SCAN` or `FALLBACK`): the corrected brand flows back to update `brand_dict` and `product_brand_map`, followed by a partial re-run of `marketshare_universe` for affected products.

**Rationale:** The product image is an independent brand verification signal that text-only Phase 3 extraction did not have. A wrong brand assignment in Phase 3 corrupts market share calculations retroactively.

---

### 12. No text similarity in Pass 2 — full LLM multimodal for both passes

**Decided:** Jun 20 2026

Pass 2 (reseller listings) uses full multimodal LLM extraction — the same method as Pass 1. There is no text similarity pre-filter.

**Rationale:** Text similarity matching is the same failure mode as keyword routing — it operates on surface text without image signal, produces wrong assignments when product names are similar (e.g. `"Oil Control Fluid"` matching `"Oil Control Gel Cream"`), and creates temporal lock-in where a wrong match prevents correct re-extraction on subsequent runs. This was empirically demonstrated by 1,783 rows requiring manual DML correction in Jun 2026 (LRP TH suncare reroute + moisturizer multipack fix). With GMV threshold already controlling reseller volume, the cost argument for text similarity no longer applies.

**Dedup rule:** A `product_id` already mapped in Pass 1 is excluded from Pass 2 by set exclusion only — not by similarity check.

**Rejected:** Text similarity first, LLM fallback. Two-tier quality standard; inconsistent `source` values (`MATCH` vs `LLM`); same root failure mode as keyword routing.

---

### 14. Official store filter: explicit per-brand allowlist, not keyword match

**Decided:** Jun 20 2026 — validated on shopee_th_suncare

Pass 1 uses `merchant_name IN ({allowlist})` — not `LIKE '%official%'` or `LIKE '%{brand}%'`.

**Why `LIKE '%official%'` fails:** Catches multi-brand authorized retailers that carry Shopee Mall certification — Watsons Official Store, BEAUTRIUM Official Store, Tsuruha_Official, Matsukiyo Official, Sasa Official Shop, Lotuss_official, SAVE DRUG OFFICIAL STORE. These are multi-brand resellers, not brand-own curated shelves. Including them in Pass 1 pollutes the taxonomy anchor with non-canonical reseller listings.

**Why `LIKE '%{brand_name}%'` fails:** Some brands operate their official store under a parent company or house-of-brands name. Biore (Shopee TH) → "KAO Beauty & Personal Care" (39 products, ฿8.1M GMV). A brand keyword filter misses this store entirely, pushing its 39 products to Pass 2 fallback despite being the authoritative brand catalog.

**Correct approach:** Before each category run, query `SELECT DISTINCT merchant_name WHERE merchant_badge = 'Shopee Mall' AND brand_id = {brand_id}` for each in-scope brand. Inspect the results, identify the brand-own store (single curated shelf, not multi-brand), and hardcode into the per-run allowlist. Store names are stable between runs; allowlist needs updating only when a brand opens/closes/renames its store.

**Rejected:** Dynamic keyword filter (`LIKE '%official%'` or `LIKE '%brand%'`). Generates false positives (multi-brand retailers) and false negatives (parent-company named stores) confirmed by live data.

---

### 13. Brand scope is GMV threshold per category per run — not a fixed brand list

**Decided:** Jun 20 2026

The brands processed in each Phase 5 run are determined dynamically by GMV threshold query for the target category and month. There is no fixed "top 10" or "top N" list.

**Official store scope:** ALL listings from the official store for any brand that appears in the GMV threshold — no per-product GMV filter on official store products. The brand's own store is the ground truth catalog; products with low or zero GMV in the target month may have future relevance.

**Reseller scope:** GMV threshold applied to reseller product_ids for the same brands. Excludes product_ids already mapped in Pass 1.

**Fallback:** If no official store found for a brand, treat all its GMV threshold products as Pass 2.

**Rejected:** Fixed "top 10 brands" list. Doesn't adapt to category-level market structure where rank shifts across months; requires manual curation; may miss breakout brands that cross threshold mid-year.

---

## Consequences

- `product_taxonomy_map` is at product_id grain — same as `product_brand_map`
- Phase 6 introduces `product_model_map` at model_id grain to resolve multi-variant/multi-size flags
- Monthly re-run of Pass 1 (official stores only) is required to catch new product launches
- A named owner for taxonomy maintenance must be assigned before Phase 5 ships
- `pack_count` is the source of truth for bundle detection; `is_bundle` is derived
- Bundle size is explicit in canonical name (` x2`, ` x3`) — bundles are distinct taxonomy_ids
- `sku_name_EN` and `option_name_EN` are explicitly excluded from extraction inputs
- `brand_mismatch` is scoped to `PRODUCT_NAME_SCAN` + `FALLBACK` sources only; `BRAND_FIELD` and `HUMAN` are trusted
- Brand corrections from Phase 5 require a controlled retroactive fix to `marketshare_universe`
- **No text similarity at any stage** — both passes use full LLM multimodal (Decision 12)
- **source field values:** `LLM` (both passes), never `MATCH` or `HUMAN` for new extractions
- **Brand scope is dynamic** — determined by GMV threshold query per category per run (Decision 13)
- **Official store products are never GMV-threshold filtered** — all listings for in-scope brands (Decision 13)
- **Backup required before each category run** — both `product_taxonomy` and `product_taxonomy_map` tables
- **Existing keyword-routed rows (source='HUMAN') will be replaced** category by category as LLM extraction completes; keyword rows are not deleted until LLM coverage is verified for that table
- **`flag_GWP = TRUE` products are excluded from all passes** — their GMV is zeroed in brand ranking and product threshold calculations; they never enter product_taxonomy_map
