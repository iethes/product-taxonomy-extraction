# Design: Supervised Taxonomy-Match Classifier (v2, successor to the blocked embedding-match design)

> Status: approved design, not yet implemented.
> Successor to [`docs/superpowers/specs/2026-07-17-embedding-nn-match-design.md`](2026-07-17-embedding-nn-match-design.md)
> (v1, embedding + nearest-neighbor, **piloted 2026-07-18 and blocked** — precision capped at ~52-55%
> ambiguous-candidate / ~87% unambiguous-candidate, both short of the 0.98 bar; root cause: brand+size alone
> doesn't discriminate between same-brand/same-size product-line variants). This design reframes the same
> underlying problem — does an incoming product match an existing `product_taxonomy` entry? — as **supervised
> learning-to-match** using the ~140K existing `source='LLM'` `product_taxonomy_map` rows as labels, instead of
> unsupervised similarity ranking. v1's embedding infrastructure is reused, not discarded — see "Relationship to
> v1" at the bottom.

---

## Why supervised, and why now

v1's failure mode was specific and instructive, not a generic "embeddings don't work" result: a generic
multilingual sentence embedding's notion of "similar text" doesn't know which words in *this catalog* actually
distinguish one product from another (a flavor name, a formulation qualifier) versus which words are boilerplate
that's identical across confusable candidates (brand, category noise words). The exact same same-brand/same-size
candidate pools that broke v1's ranking are, reframed, a **free labeled dataset**: every existing
`product_taxonomy_map` assignment is a positive example, and every other same-brand candidate that product
*wasn't* assigned to is a hard negative — the model gets to learn, from this catalog's own history, what
actually differs between confusable pairs, rather than relying on a generic embedding to guess.

## Scope

- **Both Full Rebuild and Targeted QA Fix are in scope**, not just one — three consumption modes (below), not
  the two v1 had. Full Rebuild gets two: a cross-category auto-match pre-step (v1's role) and a new formalization
  of Pass 2's currently-vague "bulk SQL text-matching" step. Targeted QA Fix gets one: an audit-flag generator,
  same role as v1's audit mode.
- **Pilot category: `th_toothpaste` again** — same category as v1's pilot, deliberately, for an apples-to-apples
  precision comparison against v1's recorded 0.52–0.87 range.
- **NIQ-only (TH+SG)**, same reasoning as v1: `marketshare_universe_niq` is where `headless_taxonomy.sh`'s data
  actually lives; ID/MY/PH/VN have no `product_taxonomy_map` coverage to train or evaluate against.
- **Training scope**: all TH categories' `source='LLM'` rows (per `docs/categories/STATUS.md`, 20/20 complete),
  not just toothpaste's — a general model, evaluated on a toothpaste held-out slice.

## Architecture

**Candidate retrieval is looser than v1's, deliberately.** v1 hard-filtered candidates by brand **and** size;
when `parse_size` mis-parsed or a product's true size didn't match any existing entry's *recorded* size (itself
sometimes wrong, per v1's ground-truth findings), the correct candidate could be silently excluded before the
matcher ever saw it. This design retrieves by **brand only** (`u.brand_confidence IN ('HIGH','MEDIUM') AND
u.brand_id NOT IN ('BRD-UNDEFINED','BRD-UNBRANDED')`, `pt.brand_id = u.brand_id` — the same live-verified brand
filter v1 established) and lets size become a *feature* the classifier weighs, not a gate that can silently drop
the right answer.

**The classifier is a gradient-boosted tree (XGBoost/LightGBM), self-hosted on the Hetzner VM** — same
credential/venv/cron pattern as v1's embedding worker (`script/embedding_worker.py`), not a new infrastructure
class. Chosen over BigQuery-native BQML for feature-engineering flexibility (text-stripping, edit distance, joins
across multiple signal types are all easier in Python) and faster local iteration; chosen over a fine-tuned
cross-encoder as unnecessary model complexity for a bounded, tabular-feature problem this catalog's size doesn't
need.

**Training data and hard-negative mining.** For each `product_taxonomy_map` row with `source='LLM'`: one
positive example (product, its assigned `taxonomy_id`). For negatives, do **not** use every other same-brand
candidate — a large brand can have 50+ SKUs, and most are trivially distinguishable (wrong size entirely, wrong
product line entirely), diluting training signal and creating severe class imbalance. Instead, use v1's existing
`product_taxonomy_embeddings`/`universe_sku_embeddings` cosine distance to select the **top-K nearest same-brand
non-matches per product** (e.g. K=5) as hard negatives — the genuinely confusable pairs, which is exactly what
the classifier needs to learn to distinguish. This is the first concrete reuse of v1's infrastructure: embedding
distance becomes a hard-negative-mining tool as well as a training feature.

**Ground-truth hygiene runs before training, not after three rounds of confusion.** Apply v1's
self-consistency check (`parse_size(sku_name)` vs. the mapped taxonomy entry's `size`) as a filter up front:
rows that fail it are excluded from training (don't teach the model from known-wrong labels) and reported
separately in evaluation (see Testing below) rather than silently blended into one precision number.

**Features per (product, candidate) pair:**

| Feature | Definition |
|---|---|
| `embedding_cosine_distance` | Reused directly from v1's `universe_sku_embeddings`/`product_taxonomy_embeddings` — no new embedding computation needed |
| `size_match` | `parse_size(sku_name).size_text = candidate.size` (three-valued: match / mismatch / unknown when either side is NULL — unknown is its own category, not folded into mismatch) |
| `pack_multiplier_signal` | Best-effort regex-detected multiplier token in `sku_name` (`x2`, `x6`, …) compared against `candidate.pack_count` — noisy by construction (no dedicated extractor exists), the model is expected to learn how much to trust it, not treat it as ground truth |
| `edit_distance_stripped` | `EDIT_DISTANCE` between `sku_name`/`sku_name_EN` and `canonical_name`, both with brand name and detected size token stripped first — isolates the part of the text that's actually informative instead of comparing full strings where brand+size dominate the distance for free |
| `token_jaccard_stripped` | Same stripping, word-level Jaccard overlap — a second, differently-shaped view of the same "what's left after brand+size" comparison |
| `keyword_table_hit` | Boolean: does a known variant/flavor keyword for this `brand_id` (mined from `product_taxonomy.variant`/`sub_line`, see below) appear in the product's text and match/mismatch the candidate's recorded variant |
| `text_length_ratio` | `LENGTH(sku_name) / LENGTH(canonical_name)` — a cheap proxy for gross mismatches (bundle vs. single item, wildly different listing styles) |

**Variant/flavor keyword table**, mined once from existing data: `SELECT brand_id, variant, COUNT(*) FROM
product_taxonomy WHERE variant IS NOT NULL GROUP BY brand_id, variant` — a per-brand vocabulary of already-known
variant names, extending Tier 0's proven "deterministic lookup before spending anything on a model" pattern into
this problem. Feeds the classifier as a feature; not a hard filter (a novel variant not yet in the table
shouldn't silently exclude a product — the same lesson as the size-filter change above).

## The three consumption modes

1. **Cross-category auto-match pre-step (Full Rebuild, before `claude -p`)** — same role, same bash-level
   pre-step position, and the same `WHERE m.taxonomy_id IS NULL` INSERT-only guard as v1's wiring into
   `script/headless_taxonomy.sh`. Auto-accept when the top-scored candidate's probability clears
   `AUTO_MATCH_MIN_PROBABILITY` (pilot-determined, mirrors v1's `AUTO_MATCH_MAX_DISTANCE` role but higher-is-better
   now). Writes `product_taxonomy_map` rows with `source = 'CLASSIFIER_MATCH'` (parallel to v1's
   `'EMBEDDING_MATCH'`).

2. **Pass 2 formalization (Full Rebuild, within-category) — new, v1 never targeted this.** `headless_taxonomy.sh`
   STEP 5 currently says "route remaining official-store-unmatched and reseller products primarily via bulk SQL
   text-matching of `sku_name` against the Pass 1 taxonomy you just built" — vague, ad hoc, implemented
   differently by whichever session runs it. This design gives it a concrete mechanism: after Pass 1 completes,
   score each remaining product against *only that category's* freshly-built taxonomy entries (candidate pool
   scoped to the category, not cross-category) with the same classifier. High-confidence matches are automatic;
   below-threshold falls through to the *existing* "read the image if genuinely ambiguous" step the script
   already has — no restructuring of the Full Rebuild process, just a real implementation for a step that's
   currently undefined. Likely higher precision than mode 1, since Pass 1's candidates were just carefully
   hand-built with clean structured fields moments earlier in the same session.

3. **Audit mode (Targeted QA Fix input, same role as v1)** — for existing `source='LLM'` rows, flag when the
   *current* mapping's score is low **and** some other candidate scores meaningfully higher (a real confidence
   delta this classifier's calibrated probability supports better than v1's raw distance did) into the
   already-built `magpie_reference.taxonomy_match_audit_flags` table (v1's table, reused as-is — flag-only,
   never writes to `product_taxonomy_map`, feeds `docs/headless-runbook.md`'s Targeted QA Fix scenario).

## Data flow

```
Feature computation (once, batch)
  → local model training/eval (fast, iterate freely — the process fix for v1's 3 slow redo rounds)
  → scored (product, candidate) pairs batch-loaded into a new table, magpie_reference.taxonomy_match_scores
    (product_id, platform, country, candidate_taxonomy_id, match_probability, model_version, computed_at)
  → mode 1/2/3 queries are simple threshold reads over precomputed scores:
    JOIN taxonomy_match_scores ... QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id, platform, country
    ORDER BY match_probability DESC) = 1 AND match_probability >= @threshold
    (the same JOIN + QUALIFY ROW_NUMBER() / UNNEST([scalar]) AS alias patterns v1 already validated live against
    this BigQuery project — reused directly, not rediscovered)
```

Scoring runs on the Hetzner worker (same machine, same pattern as embedding generation) — not `ML.PREDICT`/BQML
inference, keeping the "no new GCP infra class" property v1 established.

## Error handling / safety guards

- No same-brand candidates at all → skip, falls through to Tier 5 exactly as today. Not an error.
- No candidate clears the relevant threshold → skip, same fallback. Expected common case.
- Auto-match (modes 1 and 2) only ever `INSERT`s where `taxonomy_id IS NULL` — never `UPDATE`s an existing map
  row, identical guard to v1.
- Audit mode (mode 3) only ever appends to `taxonomy_match_audit_flags` — never touches `product_taxonomy_map`.
- Every inserted row sets `meta_agent` (AGENTS.md hard rule) and `source = 'CLASSIFIER_MATCH'`.
- Training explicitly excludes ground-truth rows that fail the size self-consistency check — a bad label
  doesn't get to teach the model, and doesn't silently inflate or deflate the eval number either.
- Rollback: same shape as v1 — `DELETE ... WHERE source = 'CLASSIFIER_MATCH' AND mapped_at >= <run start>`.

## Testing / the pilot

- `th_toothpaste` held out from training (trained on the other 19 complete TH categories), for a genuine
  out-of-sample evaluation — stronger than v1's pilot, which measured against the same category-in-training-scope
  data implicitly.
- **Report two numbers from the first measurement, not after later rescue rounds**: precision on the full
  held-out set, and precision on the subset that passes the size self-consistency check — making the
  ground-truth-noise confound visible immediately instead of requiring a redo cycle to discover, as happened
  with v1.
- Same 0.98 bar for auto-match modes (1 and 2) before trusting unattended writes. Audit mode (3) can tolerate a
  lower bar since it only ever produces a flag for review — pilot determines a separate, looser
  `AUDIT_FLAG_MIN_CONFIDENCE_DELTA`.
- Feature importance / SHAP review as part of the pilot write-up — if the model turns out to lean almost
  entirely on one feature (e.g. just `embedding_cosine_distance`, reducing to v1 in disguise), that's worth
  knowing before trusting the result.

## Out of scope

- **MY/PH/VN/ID rollout** — same reasoning as v1: no `product_taxonomy_map` coverage to train or evaluate
  against outside TH+SG NIQ.
- **A dedicated pack_count extractor** — `pack_multiplier_signal` is deliberately a noisy, best-effort feature;
  only build a real extractor later if the pilot's feature-importance review shows this is the binding
  constraint on precision.
- **BQML boosted-tree classifier** — considered as a lower-effort, zero-new-infra alternative to the self-hosted
  model. Rejected as the starting point: the feature engineering this problem needs (text-stripping before
  comparison, combining several signal types) is materially clunkier in BQML's SQL-based feature pipeline than in
  Python, and BQML training-job latency is slower for iteration than a local run. Worth revisiting only if the
  Hetzner Python stack becomes an operational burden — nothing so far suggests it will.
- **A fine-tuned cross-encoder** (small transformer trained end-to-end as a pairwise matcher) — rejected as
  unnecessary model complexity for a bounded, tabular-feature problem at this catalog's size; heavier to train,
  harder to debug, and a bigger step away from the "traditional ML, not more model machinery" premise of this
  whole doc than a feature-engineered GBM.
- **Auto-fixing audit-flagged mismatches** — same as v1, flag-only, human/LLM QA review closes the loop.

## Deliverables

1. Feature computation script (Hetzner VM, extends `script/embedding_worker.py`'s pattern — likely a sibling
   script, `script/taxonomy_match_features.py`, reusing its BigQuery client/venv setup).
2. Training script + the trained model artifact, with feature importance recorded as part of the pilot writeup.
3. `magpie_reference.taxonomy_match_scores` table (schema above).
4. Keyword-table mining query (one-off SQL, `product_taxonomy.variant`/`sub_line` → per-brand vocabulary).
5. Three consumption-mode SQL queries (auto-match pre-step, Pass 2 formalization, audit-flag generator).
6. `script/headless_taxonomy.sh` modified: the mode-1 pre-step (same shape as v1's, updated table/threshold
   names) plus STEP 5's prompt text updated to describe the formalized Pass 2 mechanism.
7. Pilot validation against `th_toothpaste` — dual precision numbers (raw + clean-subset), feature importance,
   and the chosen thresholds, recorded the way v1's plan Appendix recorded its three pilot rounds.

## Relationship to v1

- **Reuses, doesn't replace**, v1's embedding infrastructure: `product_taxonomy_embeddings` and
  `universe_sku_embeddings` are read directly as a feature source and for hard-negative mining — the embedding
  worker itself needs no changes, it gains a new consumer.
- `magpie_reference.taxonomy_match_audit_flags` (v1's table) is reused as-is for mode 3.
- The validated BigQuery SQL patterns (`JOIN` + `QUALIFY ROW_NUMBER()`, `UNNEST([scalar]) AS alias`, no
  `LATERAL`) carry forward directly — that discovery cost was already paid once.
- What does **not** carry forward: v1's candidate key (brand+size hard filter) and its distance-threshold
  auto-match logic — both are superseded by this design's looser retrieval + learned scoring.
