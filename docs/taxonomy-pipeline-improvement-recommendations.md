# Product Taxonomy Pipeline — Improvement Recommendations

> Follow-up to [`docs/sku-taxonomy-quality-scan-2026-04.md`](sku-taxonomy-quality-scan-2026-04.md).
> That scan found the problems; this doc proposes fixes, rated by feasibility,
> difficulty, and cost so they can be triaged and sequenced.

---

## The triggering example

```
sku_name           : "Mesin Cuci Mini Portable Mesin Cuci Lipat Mini Folding
                       Washing Machine Mesin Cuci Kecil KAPASITAS 2,5kg"
sku_type_complete  : "No Brand Washing Machine Undefined Undefined"
```

The size (`2,5kg`) is sitting right there in `sku_name`, but the canonical name has
two literal `"Undefined"` tokens instead. This one row is a symptom of three
separate root causes, and the recommendations below map to each:

| # | Root cause | What it looks like |
|---|-----------|---------------------|
| 1 | **Placeholder leakage** — unresolved template slots get the literal string `"Undefined"` instead of being omitted or triggering `UNRESOLVED` | `"No Brand Washing Machine Undefined Undefined"` — a clearly-failed extraction shipped as if it were a real answer |
| 2 | **Size parser gaps** — the extractor doesn't handle Indonesian comma-decimals (`2,5kg` vs `2.5kg`) or the keyword that precedes the number (`KAPASITAS`) | Size is present in text but never reaches `product_taxonomy.size` |
| 3 | **Scope drift** — `Washing Machine` isn't in `config/tables.py`'s documented 43-category list, yet it has taxonomy rows, produced by something cruder than the documented two-pass multimodal Phase 5 pipeline | Whole categories getting stub treatment instead of real extraction |

Root cause 1 directly contradicts existing policy: `docs/product-lifecycle.md §5`
already says *"UNRESOLVED is not a failure... We do not force it into a catch-all
of a different type or brand."* The pipeline that produced this row isn't
following that rule.

---

## Recommendations, prioritized by effort-to-impact ratio

| # | Recommendation | Feasibility | Difficulty | Cost | Fixes root cause |
|---|-----------------|:---:|:---:|:---:|:---:|
| 1 | Stop emitting literal `"Undefined"` — use `UNRESOLVED`/NULL instead | High | Low | $ | 1 |
| 2 | Backfill-clean existing placeholder rows | High | Low | $ | 1 |
| 3 | Broaden size/pack text parsing (locale numbers, more keywords) | High | Low–Med | $ | 2 |
| 4 | Decouple a cheap text-only size/pack pass from the expensive multimodal pass | High | Medium | $–$$ | 2 |
| 5 | Docs-vs-production category drift monitor | High | Low | $ | 3 |
| 6 | Category-tag integrity check (catches "Rice" = lamp) | Medium | Medium | $ | — (separate issue) |
| 7 | Decide + execute real Phase 5 extraction for in-scope-but-uncovered categories | Medium | High | $$$ | 3 |
| 8 | Continuous QA dashboard instead of ad hoc scans | Medium | Medium | $$ | — (process) |

**Legend** — Feasibility: how readily this fits the existing pipeline and team skillset. Difficulty: engineering complexity. Cost: $ = hours to low days + near-zero compute, $$ = days + some recurring LLM/BQ spend, $$$ = a build-out comparable to onboarding a new TH category (per `docs/categories/STATUS.md`, that's been multi-day-plus-QA-iterations per category historically).

---

## 1. Stop emitting literal `"Undefined"` — use the documented UNRESOLVED path instead

**Problem:** When the extraction script can't resolve a template slot (product line, variant, size), it currently writes the string `"Undefined"` into that slot and still creates/maps a taxonomy row. This is worse than doing nothing: it looks resolved (`taxonomy_id` is set, `sku_type_complete` is non-NULL) but carries zero information, and it silently passes any QA check that only looks for `NULL`.

**Fix:** In whatever script builds `canonical_name` (Stage 05 insertion code, not in this repo but referenced by `docs/product-lifecycle.md`):
- Build the name from only the slots that were actually extracted (`Brand + [Line] + [Variant] + [Size] + [xN]`, joining just the non-null parts) — never fill a gap with placeholder text.
- If **brand or product line** can't be determined at all, don't create a taxonomy row — leave `taxonomy_id` NULL on the map row per the existing `UNRESOLVED` policy (`docs/product-lifecycle.md §5`).
- If only **size or variant** is missing but brand+line are solid, that's a legitimate Tier-B partial entry (per `docs/quality-standards.md` D1) — fine to ship as-is, just without the placeholder word.

**Feasibility:** High — this is a string-template bug, not a new capability; the target behavior is already specified in existing docs.
**Difficulty:** Low — a few lines in the insertion script.
**Cost:** $ — no new LLM/BQ spend, an afternoon of engineering plus test coverage.

**Suggested QA gate addition** (extend `docs/quality-standards.md §4`):
```sql
-- G7: Zero canonical names containing leaked placeholder tokens
SELECT taxonomy_id, canonical_name
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy`
WHERE REGEXP_CONTAINS(LOWER(canonical_name), r'\b(undefined|null|n/a|tbd)\b');
-- EXPECT 0
```

---

## 2. Backfill-clean the existing placeholder rows

**Problem:** Rows like `"No Brand Washing Machine Undefined Undefined"` are already live in `product_taxonomy` and mapped in `product_taxonomy_map` / `marketshare_universe` today, actively degrading size/line-level analytics right now — fixing the code (Rec. 1) doesn't fix what's already shipped.

**Fix:** Run the G7 query above to find affected `taxonomy_id`s, then apply the **exact NULLIFY pattern already documented in `AGENTS.md`** (used for stale-row cleanup) to null out `taxonomy_id` on the affected `marketshare_universe` rows and delete/flag the corresponding `product_taxonomy_map` rows — reverting them to an honest "not yet resolved" state instead of a fake-resolved one. Re-queue those products for real extraction (Recs. 3/4/7).

**Feasibility:** High — reuses existing, already-battle-tested SQL patterns.
**Difficulty:** Low–Medium — mainly care in scoping the `WHERE` so legitimately short-but-correct names (e.g. `is_multi_size` entries) aren't swept up.
**Cost:** $ — one-off DML, cheap to run.

---

## 3. Broaden size/pack text parsing

**Problem:** `docs/product-lifecycle.md`'s stated trust order is `sku_name → image → spec → description`, and `sku_name` is supposed to be the *most* reliable source for stated size. Yet `"KAPASITAS 2,5kg"` — sitting in `sku_name` — didn't get picked up. Two likely gaps: (a) comma as decimal separator (`2,5` is Indonesian/European notation for `2.5`), and (b) the pipeline's known unit-keyword list is tuned for Thai FMCG (`docs/llm-extraction-rules.md`) and doesn't cover appliance-style precursor words (`kapasitas`, `capacity`, `daya`, `watt`) or Indonesian phrasing generally.

**Fix:** Extend the size-extraction regex/rules:
- Accept `\d+[.,]\d+` and normalize comma → period before parsing as a number.
- Add a locale-aware keyword list per market (ID: `kapasitas`, `berat`, `isi`, `ukuran`; TH: existing list in `llm-extraction-rules.md`) so the parser isn't only tuned to the original TH FMCG vocabulary.
- This is a pure text-pattern fix — no LLM/image call needed for cases this clean.

**Feasibility:** High.
**Difficulty:** Low–Medium — mostly regex + a per-market keyword table to maintain (similar in spirit to the per-category generic-stub token lists already maintained in `docs/categories/*.md`).
**Cost:** $ — no compute cost increase; some ongoing maintenance as new markets/phrasings appear.

---

## 4. Decouple a cheap text-only size/pack pass from the expensive multimodal pass

**Problem:** Size/pack extraction is currently entangled with the full two-pass **multimodal** Phase 5 pipeline (reads product images via Claude). But as this example shows, size is very often stated in plain text in `sku_name` alone and doesn't need an image read at all. Categories that haven't gone through the expensive multimodal pass (i.e. most of what showed up in the quality scan) get zero benefit from the text-only signal they already have.

**Fix:** Add a lightweight, **text-only** extraction pass (regex first, cheap LLM — e.g. Haiku — for ambiguous residuals) that runs across *all* products, independent of whether the full multimodal Phase 5 has reached that category yet. Rule: only fill `size`/`pack_count` when currently NULL/placeholder — never overwrite a value a real Phase-5 run already set. This directly targets D4/D5 (`docs/quality-standards.md`) at a fraction of the cost of the full pipeline, and gives categories outside the documented 43-list a real size field instead of "Undefined" while they wait for (or if they never get) full Phase 5 treatment.

**Feasibility:** High.
**Difficulty:** Medium — needs a careful "fill-only-if-missing, never clobber" guard and a confidence threshold before writing.
**Cost:** $–$$ — regex is free; a cheap text-only LLM pass for the harder cases is inexpensive relative to Sonnet multimodal calls (per `ARCHITECTURE.md` Decision 10, Sonnet was chosen for the full pipeline precisely because Haiku was unreliable for *image* disambiguation — but that constraint is about images, not plain text, so a cheaper model is worth testing here first).

---

## 5. Docs-vs-production category drift monitor

**Problem:** This entire investigation started because an ad hoc scan discovered `category_3` values (`TV`, `Washing Machine`, `Rice`, `Rempah`, ...) that don't exist anywhere in `config/tables.py`'s documented 43-category scope. Nobody would have caught this without manually querying — there's no automated check that the production table's actual categories match what the pipeline believes it covers.

**Fix:** A small scheduled query (weekly is plenty): `SELECT DISTINCT category_3 FROM marketshare_universe WHERE month = <latest>` diffed against the category list implied by `config/tables.py` (`TABLES_SG` + `TABLES_TH`, mapped to their `category_3` values via `niq_category_mapping`). New/unexpected categories get flagged for a conscious decision — "add to Phase 5 scope" or "explicitly out of scope, don't shove `sku_type_complete` guesses into it."

**Feasibility:** High.
**Difficulty:** Low — one query + a scheduled alert (email/Slack), no new infrastructure class needed.
**Cost:** $ — near-zero if scoped to a single month partition, per the same cost discipline used in the quality scan (`TABLESAMPLE` + partition filter + narrow column selection kept a similar query under 250MB).

---

## 6. Category-tag integrity check

**Problem:** Separate from taxonomy quality, some `category_3` assignments look wrong at the source — e.g. a Thai wall-lamp listing tagged `Rice`, a hair-color spray tagged `Meat`. The quality scan found this is concentrated in tiny long-tail categories (n≤10), not the well-populated ones, but it's still real and it corrupts whatever category-level rollups touch those rows.

**Fix:** A lightweight anomaly check: for each category, maintain a small keyword/vocabulary set (the per-category generic-stub token lists in `docs/categories/*.md` are a starting point, though they only exist for the 20 documented TH categories today) and flag `sku_name` rows with zero token overlap with their assigned category's vocabulary. Flag for manual review or exclude from category-level QA aggregates rather than letting one garbage row skew a small sample.

**Feasibility:** Medium — needs vocabulary lists built out for categories beyond the current 20.
**Difficulty:** Medium.
**Cost:** $ — pure SQL/regex for the first pass; escalate only ambiguous cases to an LLM.

**Note:** whether the root cause is seller-side mis-categorization on the marketplace (sellers cross-listing into unrelated categories for visibility — a known e-commerce pattern) or an upstream join issue couldn't be determined from the sample alone. This check would also help distinguish the two: if flagged rows cluster by `merchant_name`, it's sellers; if they cluster by ingestion batch/date, it's a pipeline bug.

---

## 7. Decide and execute real Phase 5 extraction for in-scope-but-uncovered categories

**Problem:** Categories like `Washing Machine`, `TV`, `Blender`, `Water Heater`, `AC`, `Refrigerator`, `Microwave` clearly have real GMV and real listings, but they're outside `config/tables.py` and getting placeholder-quality taxonomy instead of the documented two-pass multimodal extraction that the 20 TH FMCG categories received.

**Fix:** This is a scope/business decision first, engineering second:
- **If these categories matter for the business**, run them through the same process the 20 TH categories went through: build a `docs/categories/*.md` context file, an official-store allowlist, run Pass 1 (official) + Pass 2 (reseller), then the D1–D6 QA loop from `docs/quality-standards.md` until they ship.
- **If they don't matter**, explicitly exclude them (filter them out of `marketshare_universe`, or at minimum stop the placeholder-stuffing from Rec. 1) rather than leaving them in an ambiguous, silently-degraded state.

**Feasibility:** Medium — the process is well-documented and proven (20 categories already went through it), but it's genuinely new scope, not a bug fix.
**Difficulty:** High — per `docs/categories/STATUS.md`, TH categories took multiple rebuild + QA-pass iterations each; appliance categories will need their own type-gates (e.g. "capacity" and "wattage" instead of "size", a very different attribute schema than FMCG size/pack).
**Cost:** $$$ — multimodal LLM calls scale with product count/GMV per category, plus analyst time to define category-specific rules (this is comparable in cost/effort to onboarding a new TH category historically).

---

## 8. Continuous QA dashboard instead of ad hoc scans

**Problem:** This whole thread of findings — the scope drift, the placeholder leakage, the missing sizes — surfaced because someone ran a one-off manual BigQuery scan. `docs/quality-standards.md` defines a rigorous D1–D6 + gates process, but there's no evidence it runs continuously or covers categories outside the documented 20 — if it did, appliance categories full of `"Undefined"` would have been caught long before now.

**Fix:** Materialize the D1–D6 scores (or a cheaper proxy like the one used in `docs/sku-taxonomy-quality-scan-2026-04.md`) into a small scheduled table — refreshed weekly per category/country/platform — and put a thin dashboard on top (Looker Studio, or even just a scheduled query result someone glances at). This is a leverage investment: once built, it turns "surprise discovery via manual scan" into "visible on a dashboard by default."

**Feasibility:** Medium.
**Difficulty:** Medium — needs a scheduling mechanism and somewhere to render results; no new analytical logic beyond what's already documented.
**Cost:** $$ — a real setup cost once, then near-zero recurring BigQuery cost if queries stay partition- and column-scoped the way this investigation's queries did (231MB and under, per category-scan).

---

## Suggested sequencing

1. **This week, cheap and high-leverage:** Recs. 1, 2, 5 — stop the bleeding (placeholder bug), clean up what's already broken, and add a tripwire so scope drift doesn't happen silently again.
2. **Next:** Rec. 3, then 4 — close the size/pack gap that triggered this whole conversation, cheaply and without needing the expensive multimodal pipeline everywhere.
3. **When there's a business case for it:** Rec. 7 — a deliberate, scoped decision to bring appliances/groceries into full Phase 5, sized and budgeted like the past TH category build-outs.
4. **Ongoing hygiene:** Recs. 6 and 8 — smaller, can be picked up opportunistically once the above is stable.
