# Traditional AI/ML Before Agentic AI — A Cheaper, More Reliable Tiered Pipeline

> Follow-up to [`docs/cheaper-reliable-execution-model.md`](cheaper-reliable-execution-model.md).
> That doc made the existing LLM calls cheaper (batching, caching, tiered models).
> This doc asks a more basic question first: **does this product even need an LLM call at all?**
> For most of the catalog, the answer is no — nearest-neighbor search, clustering, and
> regex/NER can resolve it deterministically, cheaper and more reliably than any model call.

---

## Why traditional ML is not just cheaper here — it's more reliable

A classifier can only emit a label from its known set. An embedding search can only return a real neighbor from the catalog or "no confident match." Neither can invent the word `"Undefined"` the way free-text generation can — the failure mode that produced `"No Brand Washing Machine Undefined Undefined"` isn't representable in a bounded-output system. Two things this pipeline already does are proof this works here:

- **Brand string matching** (`BRAND_FIELD`/`PRODUCT_NAME_SCAN`, `docs/data-dictionary.md`) is deterministic lookup — no model, no ML — and already resolves 75–90% of products at zero marginal cost. Nothing in this doc proposes replacing it; it's the template for the tiers below.
- **Brand dedup** (`brand_review`, `pipeline/02_taxonomy_build/detect_duplicates.py`) already uses `SequenceMatcher` fuzzy-ratio clustering (YELLOW 0.82, auto-merge 0.90) — classic unsupervised string-similarity clustering, no LLM.

The gap: **taxonomy extraction** (product line, size, pack, match-or-create) has no equivalent cheap tier — every product currently goes straight to multimodal LLM calls. That's what this doc adds.

---

## The tiered pipeline

```
Tier 0  Exact/substring brand match (existing)          → ~75-90% of brand, $0
Tier 1  Regex size/pack extraction                      → most size/pack, $0
Tier 2  Embedding + nearest-neighbor vs. canonical taxonomy → auto-match confident products, embedding cost only
Tier 3  Clustering of unmatched products (per brand+category) → collapses 1000s of listings into dozens of new-SKU candidates
Tier 4  Bounded classification (AI.CLASSIFY-style, fixed label set) → cheap, cannot hallucinate outside its labels
Tier 5  LLM structured extraction (from cheaper-reliable-execution-model.md) → only cluster representatives / true long tail
Tier 6  Human QA review                                 → genuine UNRESOLVED edge cases
```

Each tier only ever sees what the previous tier couldn't resolve. The expensive tier (5) isn't made cheaper here — it's made **rare**. Apply the Batch API + prompt-caching design from the prior doc to whatever volume survives to Tier 5, not to the full catalog.

---

## Recommendations by tier

| # | Tier | What it replaces | Feasibility | Difficulty | Cost |
|---|------|-------------------|:---:|:---:|:---:|
| 1 | Keep Tier 0 (brand string match) as-is | Nothing — already correct | High | — | $0 |
| 2 | Better regex/keyword size-pack parsing (locale numbers, per-market keywords) | Missed sizes like the `2,5kg` bug | High | Low | $ |
| 3 | Embedding + nearest-neighbor match vs. `product_taxonomy` | The LLM's match-or-create text/image comparison, for confident cases | High | Medium | $ (embedding-only, no generation) |
| 4 | Clustering of unmatched products within brand+category | Per-product "should I create a new SKU?" LLM judgment | Medium | Medium | $ |
| 5 | Bounded classification for fixed-candidate decisions (e.g. "which of these N product lines") | Free-text extraction where the candidate set is already known | High | Low | $ |
| 6 | OCR + existing string-match cascade for brand-from-image | Multimodal LLM call for legible-text packaging | High | Low–Medium | $ |
| 7 | Image embedding + kNN for brand-from-image (style-based) | Multimodal LLM call when OCR fails but the image itself is distinctive | Medium | Medium | $ |
| 8 | Knowledge-distill a small size/pack NER model from the ~140K existing LLM-labeled `product_taxonomy_map` rows | Regex's remaining blind spots | Medium | Medium–High | $ (one training run, then near-zero inference) |

---

## 1. Keep Tier 0 as-is — the reference implementation for every tier below

**Nothing to fix.** `BRAND_FIELD`/`PRODUCT_NAME_SCAN` is deterministic string lookup and it's the reason brand resolution is already cheap and reliable at 75–90% coverage. It's included here as the pattern the other tiers copy: **resolve everything a deterministic method can handle before spending anything on a model.**

**Feasibility:** High (already built). **Difficulty:** — . **Cost:** $0.

---

## 2. Better size/pack regex — fixes the reported bug directly

**Problem:** `sku_name` text contains size/pack info (`"KAPASITAS 2,5kg"`) that a narrower, TH-FMCG-tuned parser doesn't catch — comma-decimal notation, appliance-specific precursor keywords (`kapasitas`, `capacity`, `daya`).

**Fix:** Extend the regex/rules layer: accept `\d+[.,]\d+` with comma normalized to period, add a per-market keyword table (ID: `kapasitas`, `berat`, `isi`; TH: existing list in `docs/llm-extraction-rules.md`). Pure text pattern matching — no model, no training data, no inference cost.

**Feasibility:** High. **Difficulty:** Low — regex plus a keyword table to maintain. **Cost:** $ — no compute increase, only ongoing keyword-list maintenance as new markets/phrasings appear.

---

## 3. Embedding + nearest-neighbor match against the canonical taxonomy

**Problem:** "Does this product match an existing `product_taxonomy` entry?" is currently answered by an LLM comparing brand/line/size/pack in free text — expensive, and it's the step that needs to run per-product regardless of how many other pipeline stages have already resolved brand.

**Fix:** This is nearest-neighbor search, a solved problem long before LLMs. Generate an embedding per canonical taxonomy entry and per incoming product (BigQuery's `AI.EMBED` can do this in a `GENERATED ALWAYS AS` column, computed once and reused), then search:

```sql
SELECT base.taxonomy_id, base.canonical_name, distance
FROM AI.SEARCH(
  TABLE magpie_reference.product_taxonomy,
  'canonical_name',
  new_product.sku_name,
  top_k => 3,
  distance_type => 'COSINE'
);
```

- Distance below a tuned threshold → **auto-match**, no generative call at all.
- Distance above threshold on every neighbor → **no confident match** — feed to Tier 3 (clustering) instead of an LLM per product.

Embedding calls have no output-token cost and are roughly an order of magnitude cheaper per item than a generative extraction call, regardless of how complex the input text is.

**Feasibility:** High — supported natively in BigQuery, no separate ML infra to stand up. **Difficulty:** Medium — mainly threshold-tuning per category (some categories will need a tighter distance cutoff than others) and validating against a category with known-good ground truth (e.g. `th_body_wash`, which already has full LLM extraction to compare against). **Cost:** $ — embedding-only, no generation cost; the catalog side (~15–68K rows) is embedded once and reused for every incoming product.

**Piloted 2026-07-18 — blocked, do not re-attempt this exact design without reading the findings first.**
Full pilot against `shopee_th_toothpaste` (real data, self-hosted `multilingual-e5-large` embeddings, not the
`AI.SEARCH` sketch above): precision against existing LLM ground truth **never cleared the required 0.98 bar** —
capped at ~52–55% for products where brand+size matches multiple taxonomy entries (90% of the pool), and only
~87% even for products where brand+size matches exactly one entry (the remaining 10%, after fixing genuine
ground-truth errors found along the way). Two independent fix attempts (translating `sku_name` to English before
embedding; correcting bad ground-truth rows) each moved the number by only a few points. Root cause, confirmed
by manual spot-check: **brand+size is too loose a candidate key** — it doesn't discriminate between same-
brand/same-size product-line variants (different flavor/formulation), and "unambiguous" (exactly one candidate)
often just means the taxonomy has sparse coverage at that brand+size, not that the match is actually correct.

The infrastructure this pilot built is real and reusable if this is picked up again: two BigQuery tables
(`magpie_reference.product_taxonomy_embeddings`, `magpie_reference.universe_sku_embeddings`), a self-hosted
embedding worker (`script/embedding_worker.py`, runs on commodity CPU hardware — no Vertex AI/GPU needed), and
validated `JOIN` + `QUALIFY ROW_NUMBER()` / `ML.DISTANCE` SQL patterns (BigQuery has no `LATERAL` keyword — a
real gotcha hit and fixed during this pilot). What's *not* reusable as-is is the matching logic itself — the
next attempt needs a materially tighter candidate key (e.g. `pack_count` equality plus some product-line/flavor
signal, not brand+size alone) before another pilot is worth running.

Full findings, precision tables, and the exact root-cause analysis:
[`docs/superpowers/specs/2026-07-17-embedding-nn-match-design.md`](superpowers/specs/2026-07-17-embedding-nn-match-design.md)
(the design) and [`docs/superpowers/plans/2026-07-17-embedding-nn-match.md`](superpowers/plans/2026-07-17-embedding-nn-match.md)
(the plan — see its Appendix for the full pilot history across three rounds).

---

## 4. Cluster the unmatched products instead of sending each to an LLM

**Problem:** Products with no confident taxonomy match (Tier 3 miss) still need a decision: is this a genuinely new SKU? Per-product LLM review of the long tail is the most expensive part of the current pipeline relative to how much new information each call actually contains — most "no match" listings are duplicates of a few real new products, not hundreds of distinct ones.

**Fix:** Cluster the unmatched products' embeddings (k-means or HDBSCAN), scoped within `brand_id` + category — the same scoping the pipeline already uses everywhere else (brand-gate, category-gate from `docs/product-lifecycle.md §4.2`). Each resulting cluster is very likely one physical new SKU appearing across many listings (different sellers, slightly different titles, same product). Only the cluster's representative item needs the expensive step (Tier 5) to mint a canonical name — every other member of the cluster inherits that `taxonomy_id`.

**Feasibility:** Medium — the clustering step itself is standard (BigQuery ML `CREATE MODEL ... OPTIONS(model_type='kmeans')` or an external HDBSCAN pass); the main work is picking a good per-category cluster count/threshold and validating cluster purity (a cluster containing two genuinely different products is a false economy — it'll assign them the same taxonomy_id). **Difficulty:** Medium. **Cost:** $ — clustering compute is cheap; the win is entirely on the LLM-call-count side (a brand+category with 200 unmatched listings that cluster into 4 real SKUs is a 50× reduction in Tier 5 calls for the same outcome quality).

---

## 5. Bounded classification for fixed-candidate decisions

**Problem:** Some decisions genuinely need model judgment but the candidate set is already known and small — e.g. "which of these N product lines for this brand does this listing belong to." Full free-text generation is overkill and reintroduces the placeholder-leakage risk.

**Fix:** Use a classification call constrained to an explicit label list (BigQuery's `AI.CLASSIFY` takes `categories => [...]` and can only return one of those labels, or use a lightweight trained classifier for the same decision). It **cannot** return `"Undefined"` — that string isn't in the label set. This is the middle ground between "pure ML" and "generative LLM": model-backed, but bounded, auditable, and far cheaper than a full multimodal extraction call.

**Feasibility:** High. **Difficulty:** Low. **Cost:** $ — one classification call per case, no output-token generation cost, and it can run wherever the pipeline already runs SQL.

---

## 6. OCR + the existing brand cascade, before reaching for vision reasoning

**Problem:** Multi-brand official-store disambiguation (`docs/product-lifecycle.md §6`) currently reads the product image with a multimodal LLM to determine `brand_from_image`.

**Fix:** Most packaging has the brand name printed legibly on it. Run OCR on the product image first, then route the extracted text through the **same string-matching cascade already built for brand resolution** (`brand_dict` normalized lookup). This only fails when the text is illegible or the brand isn't printed as text — a minority case, not the default.

**Feasibility:** High — OCR is a mature, cheap, off-the-shelf capability; the matching cascade already exists. **Difficulty:** Low–Medium — mainly wiring OCR output into the existing brand-lookup function and measuring the miss rate. **Cost:** $ — OCR calls are inexpensive and don't scale with image complexity the way generative reasoning does.

---

## 7. Image embedding + kNN for the cases OCR can't read

**Problem:** Some packaging is stylized enough that OCR fails (script fonts, logos-as-images, heavy graphic design) but the product is still visually recognizable.

**Fix:** Image embeddings (e.g. via `AI.EMBED` with a multimodal endpoint) capture visual style, not just legible text — a kNN search against a labeled set of official-store product images (free labels: every `BRAND_FIELD`-source row with an image already tells you the correct brand) can resolve many of these without any generative reasoning. Reserve an actual multimodal LLM call for the residual truly-ambiguous images — occluded packaging, unusual angles, near-duplicate competing brands.

**Feasibility:** Medium — needs a labeled reference set built from existing data (straightforward, since it already exists) and a similarity threshold tuned per category. **Difficulty:** Medium. **Cost:** $ — embedding + nearest-neighbor lookup, no generation.

---

## 8. Distill a size/pack model from the pipeline's own LLM history

**Problem:** Even after better regex (Rec. 2), some size/pack phrasing will remain ambiguous enough that rules alone won't catch it — new markets, new promotional phrasing patterns.

**Fix:** The ~140K `product_taxonomy_map` rows with `source='LLM'` are, in effect, a free labeled dataset: `sku_name → size, pack_count, product_line` as already extracted by the expensive model. Train a small model (sequence-tagging NER, or a lighter BQML classifier over n-gram features) on that history to handle new inputs similar in shape to what's already been seen. This is knowledge distillation — using the expensive model's *past* outputs as training signal for a cheap model that generalizes to *future*, similar inputs without another expensive call.

**Feasibility:** Medium — needs someone to actually run a training job and validate it, not just call an API. **Difficulty:** Medium–High — the one genuinely ML-engineering-heavy item in this list; requires held-out validation against categories with existing ground truth (`docs/categories/STATUS.md`) before trusting it in production. **Cost:** $ — one training run, then near-zero marginal inference cost per product going forward.

---

## What still needs the LLM (or a human) — and that's fine

- **Writing the canonical name for a genuinely new cluster** (`"Vaseline Gluta-Hya Serum Burst 400ml"`) is generation, not retrieval. Still needs a model or a person — but once per cluster (Tier 3's output), not once per product.
- **True long-tail products** with no close embedding neighbor and no legible/distinctive image — the residual that reaches Tier 5. This should be a small fraction of total volume once Tiers 0–4 are filtering correctly; apply the batching/caching/structured-output design from `docs/cheaper-reliable-execution-model.md` here.
- **UNRESOLVED edge cases** — same policy as today (`docs/product-lifecycle.md §5`): a NULL is a known gap, not a defect to paper over with a guess.

---

## Suggested sequencing

1. **Cheapest, ship first:** Rec. 2 (regex fix — closes the reported bug directly) and Rec. 6 (OCR-first for brand-from-image) — both reuse infrastructure that already exists.
2. **Biggest structural win, *if* it can be made to work:** Rec. 3 (embedding + nearest-neighbor match) — this is the one that actually changes the cost curve, since it removes the LLM from the common case entirely rather than making the LLM call cheaper. **Piloted 2026-07-18 and blocked as originally scoped** (brand+size candidate key, whole-name embedding) — see Rec. 3's own section above for the full findings before attempting this again. Not proven infeasible in general, just proven that *this specific* candidate-key design doesn't discriminate well enough.
3. **Compounds with #2:** Rec. 4 (clustering unmatched products) — only pays off once Tier 3 exists to feed it a "no match" pool to cluster.
4. **Opportunistic:** Rec. 5 and Rec. 7 — smaller wins, pick up once the pipeline above is stable.
5. **Only if the simpler tiers plateau:** Rec. 8 — the highest-effort item; worth it only if regex and nearest-neighbor matching leave a persistent, sizable residual that a distilled model would meaningfully shrink.
