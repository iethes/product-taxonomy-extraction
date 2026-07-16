# shopee_sg_shampoo — Category Context

> First LLM extraction for this category — SG was 0/23 categories LLM-extracted per `docs/categories/STATUS.md`
> before this. Written as part of the headless-taxonomy-runbook worked example
> (`docs/plans/headless-taxonomy-runbook-implementation-plan.md` Task 6). Two live headless attempts so far —
> see QA History for what each found. Attempt #2 (2026-07-15) actually wrote to production: Pass 1 complete,
> Pass 2 intentionally partial. Read the Brand Scope correction below before trusting the old "~20 brands"
> framing — the true 95%-GMV universe is ~190 brands, not ~20.

---

## Status

| Field | Value |
|-------|-------|
| LLM Pass 1 | ✅ Complete — 925 taxonomy entries, 965 official-store products mapped (all 23 allowlist brands) |
| LLM Pass 2 | ⏳ Partial — bulk text-matching (301 products) + minimal catch-alls for the 9 named no-official-store brands (1,155 products); ~158 further brands in the true 95%-GMV list are still unmapped |
| Keyword-seed (HUMAN) coverage | 2,255 rows in `product_taxonomy_map`, `source='HUMAN'` — **not yet deleted**, still coexists with the new LLM rows (see disposition policy below) |
| GMV Coverage (LLM) | 33.7% of category GMV (up from 0%) |
| Product-count coverage (LLM) | 9.8% (2,421 of 24,818 distinct products) — expected to lag GMV coverage since Pass 1 targets highest-GMV listings first |
| Last run | 2026-07-15, attempt #2, `status='partial'`, verified against live BigQuery (not just claimed) |
| Current MAX taxonomy_id (as of 2026-07-15, before this session) | SKU-068015 — **re-verify live before claiming any new block, never trust this number** |

---

## Scale (verified live 2026-07-15)

- **1,615,309 total rows** in `master_clean_niq.shopee_sg_shampoo`; **24,818 distinct products**.
- **187,902 rows** with `merchant_badge = 'Shopee Mall'` (candidate Pass 1 pool before narrowing to the actual
  allowlist below — Pass 1 correctly used only the allowlist, not all 187,902).
- **The real 95%-GMV brand universe is ~190 distinct brands**, not the ~20 this file originally listed (that
  was a top-20-by-absolute-GMV snapshot, never an actual cumulative-GMV-threshold calculation — a real gap in
  the original research, caught by attempt #2's own live GWP-adjusted cumulative ranking). Of those ~190: 23
  have official stores (Pass 1, done), 9 more were explicitly named as no-official-store (got minimal
  catch-all coverage in Pass 2), and **~158 remain completely unaddressed** — several individually larger than
  brands already covered (e.g. Goldwell, Aveda, L'Oréal Paris, Nizoral, Hair+, Fayre Beauty, Dixmondsg).
- **SKU budget is the binding constraint for finishing Pass 2 properly, not effort.** Personal-care listings
  fragment into many near-unique SKUs — Pass 1 alone (965 official-store products) consumed 925 of the
  pre-assigned 1,000 slots, leaving only 75 for all of Pass 2. Extrapolating Pass 1's density, properly
  covering the remaining ~158 brands at real product-line/size granularity needs a **supplemental block on the
  order of 1,500–3,000 slots** — claim one via Shared mechanics § Atomic SKU block claim before a follow-up
  session; don't try to force this into the 66 slots left in the current block (`SKU-069935`–`SKU-070000`).

---

## SKU Blocks Assigned

| Block | Usage | Status |
|-------|-------|--------|
| SKU-069001–SKU-069934 | Attempt #2 — Pass 1 (925 entries) + Pass 2 catch-alls (9 entries) | Written 2026-07-15. Verified live: 934 `product_taxonomy` rows, 2,421 `product_taxonomy_map` rows (`source='LLM'`). |
| SKU-069935–SKU-070000 (66 slots, within the same claimed block) | Unused | Technically available but **not enough** for a proper Pass 2 completion pass — see Scale above. Leave unused, claim a fresh supplemental block instead of fragmenting further work across two small ranges. |

Registry row for this block is still `status='ACTIVE'` — normal, since the block wasn't exhausted or marked
`FAILED_QA`/`COMPLETE`. No new claim needed unless a follow-up session wants the leftover 66 slots for a small,
targeted fix (not a full Pass 2 completion).

---

## Brand Scope — corrected 2026-07-15

**The original "top 15–20 by GMV" list below was never an actual 95%-threshold calculation** — it was a
top-20-by-magnitude snapshot mislabeled as brand scope. Kept for reference (it's still useful as "highest
individual GMV brands," which is why they were correctly prioritized for Pass 1's official-store allowlist),
but **do not treat this as the Pass 2 scope boundary.** The real boundary is ~190 brands by cumulative GMV
share — recompute live before any follow-up Pass 2 session, do not reuse this snapshot as-is.

1. **Milbon** — SGD 95,043 GMV, 568 products
2. **Grafen** — SGD 73,619 GMV, 48 products
3. **MadeToBloom** — SGD 73,562 GMV, 9 products
4. **Dr.FORHAIR** — SGD 70,489 GMV, 76 products
5. **Kérastase** — SGD 62,069 GMV, 435 products
6. **Tsubaki** — SGD 57,941 GMV, 104 products
7. **Diane** — SGD 56,039 GMV, 208 products
8. **UNOVE** — SGD 55,836 GMV, 33 products
9. **Dr.ville** — SGD 55,428 GMV, 32 products
10. **NARD** — SGD 52,026 GMV, 33 products
11. **sukin** — SGD 50,789 GMV, 33 products
12. **Phytopecia** — SGD 41,863 GMV, 19 products
13. **Shiseido Professional** — SGD 41,261 GMV, 182 products
14. **Off&relax** — SGD 40,432 GMV, 104 products
15. **Suu Balm** — SGD 37,828 GMV, 20 products

`brand_id` values: resolved during Pass 1/2 for the 32 brands actually processed; not resolved for the
remaining ~158 in this snapshot.

---

## Official Store Allowlist (Pass 1) — used as-is, confirmed correct

Pulled live 2026-07-15 from `merchant_badge = 'Shopee Mall'` rows. Exact merchant names, not a
`LIKE '%official%'` wildcard, per `docs/llm-extraction-rules.md` §4. **All 23 entries below were used in Pass
1 with full coverage** (973 candidate products, 965 in-scope and mapped, 8 correctly left NULL as genuinely
out-of-scope pure-styling listings):

| Brand | Official Store Merchant Name |
|-------|------------------------------|
| Shiseido Professional | `Shiseido Professional` |
| Daeng Gi Meori | `Daeng Gi Meo Ri Official Store` |
| Grafen | `Grafen Korea Official Store` |
| KUNDAL | `KUNDAL SG` |
| NaturVital | `NaturVital Official Store` |
| Dr.FORHAIR | `Dr.FORHAIR KOREA OFFICIAL STORE` |
| Diane | `Mandom Official Store` |
| Schwarzkopf | `Schwarzkopf` |
| Himalaya | `Himalaya Official Store` |
| O'right | `O'right Official Store` |
| ＆honey | `Cosme Flagship Store` |
| Lakme | `LAKMÉ Official Store` |
| Klorane | `Klorane Official Flagship Store` |
| Fanola | `Fanola Official Store Singapore` |
| Ryo | `AMOREPACIFIC Hair&Beauty Shop` |
| Kevin Murphy | `WOOSHOP Singapore` |
| Herbal Essences | `P&G Beauty Official Store` |
| Bananal | `RAUM Korea` |
| Pantene | `P&G Official Store` |
| Dove | `Unilever Official Store` |
| Amos Professional | `Amos Professional SG Official Mall` |
| Head & Shoulders | `P&G Official Store` |
| NARD | `Nard Store` |
| Avalon Organics | `Avalon Organics X Official Store` |
| Kérastase | `Kerastase` |

**Multi-brand stores excluded from the allowlist** (per `docs/llm-extraction-rules.md` §4's explicit exclusion
list — Sasa is named there directly) — confirmed handled correctly, routed to Pass 2/bulk-text-matching instead:
- `Sasa Official Store`, `Nana Mall Official Store`, `Strawberrynet SG Official Store`, `KimageSalon Official Store`
  — all sell Kérastase among other brands.

P&G Official Store sells both Pantene and Head & Shoulders — parent-company store, both brands correctly kept
in Pass 1, disambiguated by product content per plan.

**Brands with no official store — got Pass 2 catch-all coverage 2026-07-15:** Milbon, MadeToBloom, Tsubaki,
UNOVE, Dr.ville, sukin, Phytopecia, Off&relax, Suu Balm. Each got exactly one `size=NULL,
is_multi_variant=TRUE` catch-all taxonomy entry (confidence 0.6) covering all shampoo-keyword-filtered products
for that brand — real non-NULL coverage, zero product-line/size granularity. Milbon alone has 768 distinct real
products collapsed into its single catch-all entry — a follow-up session with a proper SKU budget should split
these into real per-line entries.

---

## Scope — What's In vs Out

**In scope:** shampoo, 2-in-1 shampoo+conditioner (per the same pattern already established for
`th_body_wash`/`th_fabric_softener` 2-in-1 handling in `docs/llm-extraction-rules.md`).

**Dry shampoo: resolved 2026-07-15, IN SCOPE.** Real dry-shampoo products exist in this NIQ bucket (K18
AirWash, Diane UV Dry Shampoo) — no separate dry-shampoo NIQ category exists in this data, and NIQ itself
bucketed them here. Treated as in-scope during Pass 1/2.

**Out of scope (leave NULL):** standalone conditioner/hair treatment (separate NIQ category).

**Edge cases:**
- **Same-brand multi-component sets** (e.g. "Shampoo + Treatment" bundles from one brand) — found 2026-07-15,
  52 entries. These do **not** get `is_bundle=TRUE` — per `ARCHITECTURE.md`, that flag is schema-reserved for
  *cross-brand* bundles. Same-brand sets use `is_multi_variant=TRUE` plus a descriptive `canonical_name`
  instead. New precedent for this category; apply consistently to any future same-brand-set discoveries.
- **Brand `&herb`** (2 low-GMV `Cosme Flagship Store` products) is not registered in `brand_dict` under any
  casing checked — routed to `BRD-UNDEFINED` in this pass, flagged here for Stage 02 registration. Its sibling
  private label `&Honey` *is* registered (`BRD-GLOBAL-00237`) — worth checking if `&herb` should be under the
  same umbrella brand.
- **NARD's single highest-GMV product** ($9.76M, 82% of NARD's Mall GMV) is an 8ml shampoo+treatment sachet
  sampler, not a full-size bottle — confirmed via image read, not assumed from size text alone (a case where
  the size-text-wins-over-image rule in `docs/llm-extraction-rules.md` §2 didn't have clean text to trust, so
  image was the deciding signal by necessity, not by overriding a stated size).

---

## Taxonomy Design Notes

**Entry quality is tiered, not uniform** (2026-07-15 Pass 1 result, 925 entries total):
- **739 STANDARD** — clean brand + product line + size, extracted directly from text.
- **52 SET_WITH_SIZE** — same-brand multi-component sets with a real, confirmed size (see Edge cases above).
- **50 STANDARD_BRAND_FALLBACK** — size not stated in the specific listing's `sku_name`, but confirmed via
  `option_name` variant lists or sibling listings from the same brand/line rather than guessed.
- **124 MULTI_VARIANT_CATCHALL** — `size=NULL`, `is_multi_size=TRUE`, for listings offering many
  product-type/flavor choices in one SKU. **This is the real precision debt in Pass 1** — concentrated in
  low/zero-GMV long-tail listings, not documented per-row individually, not image-verified case by case.
  Candidate list for a future precision pass if these prove to matter for analysis.

**Image verification was used where text was genuinely ambiguous**, not by default: confirmed Kérastase 500ml
sample sizing, K18 AirWash at 118ml, Grafen 500ml×2, Kevin Murphy standard=250ml, Dungud standard=1000ml — all
via image read or `option_name` cross-reference, per `docs/llm-extraction-rules.md`'s image-as-tiebreaker
priority.

**Finding (2026-07-15, manual QA): `product_line`/`sub_line`/`variant` are NULL on all 934 entries — 100%,
not a tier-specific gap.** The "739 STANDARD — clean brand + product line + size" self-report above is
inaccurate on this specific point: the session wrote good, human-readable `canonical_name` values (e.g.
`"Amos Professional PURE SMART Line dandruff care Shampoo FRESH / MOIST / Deep Action / Pack 500ml"`, where
`"PURE SMART Line dandruff care Shampoo"` is clearly the on-label product line per
`docs/llm-extraction-rules.md` §3) but never decomposed that text back into the structured `product_line`
column the schema provides for exactly this purpose. Verified this is run-specific, not a pipeline-wide issue:
the rest of `product_taxonomy` (18,582 rows from shipped TH categories) sits at a normal 9.2% NULL rate for
`product_line` (legitimate catch-alls); this run alone is 100%.

Contributing factor: `sql/schema/product_taxonomy.sql` documents `product_line STRING NOT NULL`, but the live
column is actually nullable (`INFORMATION_SCHEMA.COLUMNS.is_nullable = 'YES'`) — another instance of the
schema-file-vs-live-table drift found repeatedly elsewhere this session. Nothing blocked this at write time.

**Not yet fixed in the data** — `product_line`/`sub_line`/`variant` remain NULL for all 934 entries as of
2026-07-15. A backfill pass (re-parsing `canonical_name` back into structured fields) is possible but not run
yet; a full Pass 1 re-run with the corrected prompt (see `docs/headless-runbook.md`'s Full Rebuild prompt,
revised 2026-07-15) is the more reliable fix since it re-derives the fields from source rather than
reverse-engineering them from already-flattened text.

---

## Existing HUMAN rows — delete only where duplicated by LLM

2,255 `source='HUMAN'` rows exist in `product_taxonomy_map` for this category (automated keyword-routing from
an earlier seed pass — per `docs/decisions/ADR-006`, `HUMAN` does **not** mean an actual person reviewed them).

**Policy (confirmed by manager, 2026-07-16): delete a HUMAN row only if that same product also has an LLM
row.** Not a blanket supersede of every HUMAN row in the category (an earlier revision of this file said that,
then a later revision removed deletion entirely — both superseded by this narrower, confirmed policy). Of the
2,255 HUMAN rows, exactly **847 duplicate an existing LLM row** and are deletable; the remaining **1,408** have
no LLM row yet and stay untouched — deleting those would leave that product with no taxonomy at all, worse
than the keyword-seed routing it has today.

**Delete query** (exact scope — verified live 2026-07-16 that this matches 847 rows before running for real):
```sql
DELETE FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
WHERE master_table = 'shopee_sg_shampoo' AND source = 'HUMAN'
  AND product_id IN (
    SELECT product_id FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
    WHERE master_table = 'shopee_sg_shampoo' AND source = 'LLM'
  );
```

**Sequence** (see `docs/headless-runbook.md`'s Full Rebuild scenario steps 4–8 for the authoritative version):
1. Pass 1 + Pass 2 built the new LLM taxonomy (934 entries, 2,421 map rows). ✅ Done 2026-07-15.
2. `run_qa_gates shopee_sg_shampoo --skip-coexistence` — dual-mapped (scoped to LLM) and placeholder-leak both
   verified 0/0 live. ✅ Done.
3. Delete the 847 overlapping HUMAN rows (query above). **Not yet run.**
4. `run_qa_gates shopee_sg_shampoo` (no flag) — coexistence should now be exactly 0. **Not yet run.**
5. Universe refresh (Shared mechanics § Universe refresh) — makes the new taxonomy visible in
   `universe_taxonomy_overlay`/analyst-facing queries. **Not yet run.**

Use "Reviewing this run's output" below to inspect the new taxonomy before proceeding with steps 3–5.

---

## Reviewing this run's output (manual QA)

**Tables involved:**

| Table | What's in it for this run | Grain |
|-------|---------------------------|-------|
| `magpie_reference.product_taxonomy` | The 934 new canonical SKU entries (`SKU-069001`–`SKU-069934`) — brand, product line, size, pack, canonical name | One row per canonical SKU |
| `magpie_reference.product_taxonomy_map` | Links each real product to a `taxonomy_id`. Filter `master_table='shopee_sg_shampoo' AND source='LLM'` for the new rows, `source='HUMAN'` for the 2,255 rows being considered for deletion | One row per `(product_id, platform, country)` |
| `master_clean_niq.shopee_sg_shampoo` | Raw listings — `sku_name`, `merchant_name`, images, price, GMV — cross-reference to sanity-check what the LLM actually extracted against | One row per product/model variant |

**Query 1 — browse the new taxonomy entries themselves:**
```sql
SELECT taxonomy_id, brand_id, product_line, sub_line, variant, size, pack_count,
       canonical_name, is_bundle, is_multi_variant, is_multi_size
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy`
WHERE taxonomy_id BETWEEN 'SKU-069001' AND 'SKU-069934'
ORDER BY taxonomy_id;
```

**Query 2 — new taxonomy joined back to the real product it was extracted from** (the most useful one for spot
checking — lets you see the LLM's canonical name next to the actual `sku_name` it read):
```sql
SELECT pt.taxonomy_id, pt.canonical_name, pt.size, pt.pack_count, m.confidence,
       src.sku_name, src.merchant_name, src.merchant_badge, src.gmv_monthly
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy` pt
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m ON m.taxonomy_id = pt.taxonomy_id
JOIN `sincere-hearth-273704.master_clean_niq.shopee_sg_shampoo` src ON src.product_id = m.product_id
WHERE m.master_table = 'shopee_sg_shampoo' AND m.source = 'LLM'
ORDER BY src.gmv_monthly DESC;
```

**Query 3 — the 124 catch-all entries specifically** (the flagged precision debt — `is_multi_size=TRUE`, worth
a closer look since these collapse many real products into one generic entry):
```sql
SELECT taxonomy_id, canonical_name, brand_id
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy`
WHERE taxonomy_id BETWEEN 'SKU-069001' AND 'SKU-069934' AND is_multi_size = TRUE
ORDER BY taxonomy_id;
```

**Query 4 — side-by-side old (HUMAN) vs new (LLM) for the same product**, where both exist — the most direct
before/after comparison for products that were routed under the keyword-seed pass and now have a real LLM
taxonomy assignment too:
```sql
SELECT m_llm.product_id, src.sku_name,
       pt_llm.canonical_name AS new_llm_canonical_name,
       pt_human.canonical_name AS old_human_canonical_name
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m_llm
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt_llm ON pt_llm.taxonomy_id = m_llm.taxonomy_id
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m_human
  ON m_human.product_id = m_llm.product_id AND m_human.source = 'HUMAN' AND m_human.master_table = 'shopee_sg_shampoo'
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt_human ON pt_human.taxonomy_id = m_human.taxonomy_id
JOIN `sincere-hearth-273704.master_clean_niq.shopee_sg_shampoo` src ON src.product_id = m_llm.product_id
WHERE m_llm.master_table = 'shopee_sg_shampoo' AND m_llm.source = 'LLM';
```

**Query 5 — what's still NULL among the highest-GMV products** (useful for judging whether the ~158
unaddressed brands actually matter before deciding to claim a supplemental block):
```sql
SELECT src.product_id, src.sku_name, src.merchant_name, src.gmv_monthly
FROM `sincere-hearth-273704.master_clean_niq.shopee_sg_shampoo` src
LEFT JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
  ON m.product_id = src.product_id AND m.master_table = 'shopee_sg_shampoo'
WHERE m.taxonomy_id IS NULL
ORDER BY src.gmv_monthly DESC
LIMIT 50;
```

---

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-07-15 | Headless attempt #1 (Full Rebuild) | Session correctly stopped before writing: found 2,255 undocumented HUMAN rows (this file wrongly said 0), ambiguous instruction about whether the agent itself performs extraction or needs `ANTHROPIC_API_KEY` for a subprocess, and 187,902-row official-store pool too large for one session to vision-read. | This file and `docs/headless-runbook.md`'s Full Rebuild prompt rewritten before attempt #2. |
| 2026-07-15 | Headless attempt #2 (Full Rebuild) | Completed `status='partial'`, verified against live BigQuery. Pass 1 complete (925 entries, 965 products, all 23 allowlist brands). Pass 2 intentionally partial — SKU budget (1,000 slots) consumed almost entirely by Pass 1's fragmentation; only 75 slots left, 9 used for no-official-store catch-alls, 301 products bulk-text-matched, ~158 further brands (of the true ~190-brand 95% list, itself a correction to this file's original ~20-brand snapshot) left unmapped. Also caught a real bug: `headless-runbook.md`'s dual-mapped QA gate was unscoped and would have misfired (847, not 0) on legitimate mid-rebuild HUMAN+LLM coexistence. | `sg_shampoo.md` rewritten with corrected Brand Scope/Scale/Edge Cases (this revision). `headless-runbook.md`'s QA gate scoped to `source='LLM'`, `--skip-coexistence` flag added. HUMAN-row deletion + refresh still pending (see disposition policy above). |
| 2026-07-15 | Manual QA (post attempt #2) | `product_line`/`sub_line`/`variant` NULL on 100% of the 934 new entries (rest of `product_taxonomy` sits at a normal 9.2% NULL rate — run-specific, not pipeline-wide). Root cause: extraction wrote good `canonical_name` text but never decomposed it into the structured fields; the session's own quality-tier self-report ("739 STANDARD — clean... product line") was inaccurate on this point. Contributing factor: live `product_line` column is nullable despite `sql/schema/product_taxonomy.sql` documenting `NOT NULL` — another schema-vs-live drift instance. | `docs/headless-runbook.md`'s Full Rebuild prompt now explicitly requires populating these 3 fields, with worked examples. New QA gate (`structured_fields_missing`) added to `run_qa_gates()` to catch this automatically on future runs. Data for this run's 934 entries not backfilled yet — see Taxonomy Design Notes. |

---

## Scripts

| Script | Purpose |
|--------|---------|
| `pipeline/05_product_taxonomy/llm_shopee_sg_shampoo/build_taxonomy.py` | Pass 1 extraction (external pipeline repo — not in this repo; this category's actual Pass 1/2 was done directly by a headless `claude -p` session instead, per `docs/headless-runbook.md`, not by this script) |
| `pipeline/05_product_taxonomy/llm_shopee_sg_shampoo/build_p2_taxonomy.py` | Pass 2 routing (same — not used; headless session did this directly) |

---

## Map Row Counts (verified live 2026-07-15, after attempt #2)

| Source | Count | Notes |
|--------|-------|-------|
| LLM | 2,421 | 965 Pass 1 (official-store) + 301 Pass 2 bulk-text-matched + 1,155 Pass 2 catch-all (9 no-official-store brands) |
| HUMAN | 2,255 | Keyword-seed routing. 847 duplicate an LLM row and are pending deletion (step 3 above); 1,408 have no LLM row and will remain permanently |
| NULL (unmapped) | remainder of 24,818 distinct products | ~158 brands of the true 95%-GMV universe still unaddressed — see Scale section |
