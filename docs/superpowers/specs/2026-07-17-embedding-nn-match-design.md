# Design: Embedding + Nearest-Neighbor Taxonomy Match, with an LLM-Compliance Audit Mode (Rec 3, `traditional-ml-execution-model.md`)

> Status: **piloted and blocked, 2026-07-18.** Tasks 1-5 of the implementation plan (tables, embedding worker,
> matching queries, three rounds of pilot validation against `shopee_th_toothpaste`) were completed; precision
> never cleared the required 0.98 bar in either the ambiguous-candidate bucket (~52-55%) or the unambiguous
> bucket (~87%, after fixing genuine ground-truth errors). Tasks 6-7 (production wiring, documentation) were not
> started — the human decision was to stop rather than ship at this precision. Root cause: the brand+size
> candidate key doesn't discriminate between same-brand/same-size product-line variants. Full findings:
> [`docs/superpowers/plans/2026-07-17-embedding-nn-match.md`](../plans/2026-07-17-embedding-nn-match.md)'s
> Appendix (three dated rounds). The tables, worker, and SQL patterns below remain valid and reusable
> infrastructure for a future attempt with a tighter candidate key — only the matching-logic scope is invalidated,
> not the mechanism.
>
> Revised 2026-07-17 (pre-pilot): embedding generation moved to a self-hosted
> worker on the existing Hetzner VM (Option 2 from the cost review) rather than BigQuery-native Vertex AI
> (Option 1, kept open — see "Embedding generation" below for why the matching layer is forward-compatible with
> switching to it later); brand-resolution join corrected against live schema (`product_brand_map`, not
> `marketshare_universe.brand_id`, which doesn't exist on the live table).
> Implements Recommendation 3 from
> [`docs/traditional-ml-execution-model.md`](../../traditional-ml-execution-model.md) ("Embedding + nearest-neighbor
> match against the canonical taxonomy") — that doc's own "biggest structural win" tier, chosen as the next tier to
> build now that Tier 0 (brand match) and Tier 1/2 (`parse_size` regex, see
> [`docs/superpowers/specs/2026-07-14-size-regex-pass-design.md`](2026-07-14-size-regex-pass-design.md)) are both live.

---

## Why this tier, and why now

The driving problem isn't just LLM cost/duration — it's that **Session A follows `docs/llm-extraction-rules.md`
correctly and Session B silently doesn't**, for a part or all of a product's fields (`product_line`, `sub_line`,
`variant`, `size`, `pack_count`). Today the only fix is another LLM session doing QA on the previous one's output.

Embedding match addresses this more directly than "just another cost-cutting tier" would suggest: for any product
with a confident nearest-neighbor match to an existing `product_taxonomy` entry, **there is no extraction step at
all** — every field is inherited from the matched entry, not re-derived by a model that might forget a rule. The
compliance-drift failure mode is only representable when a session does independent extraction; matching removes
that step entirely for the subset this tier is confident about.

This gives the tier two independent jobs, sharing one matching mechanism:

1. **Auto-match** — for products with no taxonomy mapping yet, skip Tier 5 (LLM) entirely when confident.
2. **Audit** — for products an LLM session already mapped, flag (never auto-fix) cases where this tier's
   independent judgment disagrees, as a queue for QA review — a direct, structural check on session-to-session
   compliance drift, not another LLM call trusting another LLM call.

## Scope

- **Both modes ship together** in this design — audit mode reuses the exact same matching query as auto-match
  (same candidate filter, same distance calculation), just pointed at already-mapped rows and writing to a
  different destination. Building one without the other would duplicate the matching logic for no reason.
- **The candidate pool is the entire `product_taxonomy` table, not scoped to the target category.** A product
  being taxonomized for the first time in one category can still have a confident match in a *different*
  category or country's existing taxonomy — same brand, same size, genuinely the same or a near-identical
  physical product (cross-category duplicates, or the same SKU resurfacing under a different Intrepid
  country/platform). The candidate filter is `WHERE pt.brand_id = <resolved> AND (size filter)` with no
  `master_table` restriction — this is what makes wiring into Full Rebuild (below) actually pay off, not just the
  "new products in an already-built category" case.
- **Pilot category: `th_toothpaste`** — 5 QA passes (the most scrutinized TH category per
  `docs/categories/STATUS.md`), 92.5% GMV coverage, and (live-queried 2026-07-17) **4,177** mapped products in
  `product_taxonomy_map` — a real sample size, not the ~700-row SKU-block-range figure `STATUS.md`'s notation
  first suggested (that range is the *taxonomy_id* block claimed for new entries, not the count of products
  mapped to them). Its already-correct LLM mappings serve as ground truth to tune both thresholds below before
  either mode runs unattended anywhere.
- **Country/category rollout after the pilot clears its precision bar:** auto-match starts on new TH products
  (brand + size resolution both most mature there); audit mode can run across all existing `source='LLM'` rows
  immediately, since it only ever produces a flag and can't damage existing state.

## Embedding generation: self-hosted on the existing Hetzner VM

**Decision (2026-07-17):** embeddings are generated externally, on the existing Hetzner VM (AMD Ryzen 7 7700,
8-core, 128GB RAM, no GPU), not via BigQuery's `ML.GENERATE_EMBEDDING`/Vertex AI. Reasoning from the cost/tradeoff
review: dollar cost is a non-factor either way (Vertex AI would run under $10 total even embedding the entire
6.16M-row universe once; self-hosted compute is a few dollars of VM time at this data volume). The real
difference is *what kind of new infrastructure this repo takes on* — Vertex AI needs a new BQ `CLOUD_RESOURCE`
connection plus a project-level IAM grant (`roles/aiplatform.user`); self-hosting needs no new GCP IAM surface at
all, and the Hetzner VM already exists and is idle capacity, not a new resource to provision.

- **Model:** `intfloat/multilingual-e5-large` (560M params) via `sentence-transformers`, run on CPU. Chosen over
  an English-only model because `canonical_name`/`sku_name` mix Thai and English text; chosen over a smaller
  multilingual model because 128GB RAM and 8 cores comfortably absorb the larger model's cost at this data
  volume (21,415 catalog rows, low-hundred-thousands of incoming rows per pass — not a throughput-constrained
  workload even on CPU). `e5`'s explicit `"query: "`/`"passage: "` prefix convention maps naturally onto this
  tier's asymmetric comparison (incoming `sku_name` as query, existing `canonical_name` as passage). Revisable in
  the plan/pilot if `th_toothpaste` validation shows a different model matching better — not fixed by this design.
- **Storage:** two new BigQuery tables, populated by batch load (`bq load`, never the streaming API — same rule
  as everywhere else in this pipeline, avoids the 90-minute streaming-buffer restriction):
  - `magpie_reference.product_taxonomy_embeddings` (taxonomy_id STRING, embedding ARRAY<FLOAT64>, model_version
    STRING, computed_at TIMESTAMP) — one row per catalog entry.
  - `magpie_reference.universe_sku_embeddings` (product_id, platform, country — the ADR-006 composite key —
    embedding ARRAY<FLOAT64>, model_version STRING, computed_at TIMESTAMP) — one row per incoming product this
    tier has ever considered a candidate (both unmapped products, for auto-match, and `source='LLM'` mapped
    products, for audit — no need to special-case which mode needs which rows; embedding is idempotent and cheap
    at this volume).
- **Worker:** a Python script on the Hetzner VM, cron'd (e.g. hourly), that queries BigQuery via the
  `google-cloud-bigquery` client for rows in `product_taxonomy` / `marketshare_universe_niq` not yet present in the
  corresponding embeddings table, computes vectors locally with the model above, and batch-loads the results
  back. Fully decoupled from `headless_taxonomy.sh` — it does not run synchronously as part of a Full Rebuild.
- **This is what keeps Option 1 (Vertex AI) genuinely open, not just documented as an aspiration:** matching
  (below) is pure BigQuery SQL over plain `ARRAY<FLOAT64>` columns using `ML.DISTANCE` — a native, zero-connection
  BigQuery function that works identically regardless of *how* the vectors were produced. Swapping the generation
  step for `ML.GENERATE_EMBEDDING`/Vertex AI later touches only the worker; the matching queries, thresholds, and
  safety guards below don't change.
- **Cold-start consequence, not a defect:** a brand-new `master_table` has zero rows in `universe_sku_embeddings`
  until the Hetzner cron job next runs against it. `headless_taxonomy.sh`'s pre-step (below) only ever reads
  whatever embeddings already exist — on a table's very first Full Rebuild, before the worker has ever seen it,
  the pre-step may find zero candidates and every product falls through to Tier 5 as it does today. Same
  graceful-degradation principle as every other guard in this design, not a new failure mode to handle specially.

## Mechanism

**Ordering dependency:** this tier runs strictly after Tier 0 (brand) and Tier 1/2 (`parse_size`), and consumes
both of their outputs as filters rather than re-deriving brand or size itself.

```
Tier 0 (brand_id resolved on marketshare_universe_niq?) ──not resolved──▶ skip, product goes to Tier 5 as today
       │ resolved
       ▼
Tier 1/2 (parse_size(sku_name))
       │
       ▼
Candidate filter: product_taxonomy WHERE brand_id = <resolved> AND size = <parsed size, if any>
       │
       ▼
Precomputed embeddings (Hetzner worker, see above) joined by key; ML.DISTANCE(incoming, candidate, 'COSINE')
over the filtered candidates, top-1 by distance
       │
       ├─ auto-match mode:  distance ≤ AUTO_MATCH_MAX_DISTANCE  → INSERT new product_taxonomy_map row
       │                    (source='EMBEDDING_MATCH'), skip Tier 5
       │
       └─ audit mode:       top-1 taxonomy_id ≠ currently-mapped taxonomy_id
                             AND distance ≤ AUDIT_FLAG_MAX_DISTANCE
                             → INSERT into taxonomy_match_audit_flags (flag only, no write to product_taxonomy_map)
```

**Brand filter is a hard requirement, not a fallback**, for both modes. A wrong-brand match is a fully wrong
taxonomy assignment (worse blast radius than the milder wrong-size case the size filter guards against), and a
distance threshold tuned against `th_toothpaste` — where brand *is* resolved for every row — isn't a real substitute
for the categorical filter on the segment where it's missing. Products without a resolved `brand_id` are also
already the harder tail Tier 0's deterministic match couldn't handle, and get zero cost regression from being
skipped here (they fall through to Tier 5 exactly as they do today).

Brand resolution itself needs no new work — Stage 03 of the external pipeline
(`pipeline/03_product_mapping/build_product_brand_map.py`, documented in `docs/brand-extraction.md`) already
resolves every product's `brand_id` before any taxonomy work touches it (`BRAND_FIELD` → `PRODUCT_NAME_SCAN` →
`FALLBACK`).

**Two rounds of live-schema correction, 2026-07-17 — record both, since the second corrects the first:**

1. First pass checked `magpie.marketshare_universe` and found no `brand_id`/`brand_confidence`/`master_table` at
   all (only a raw `brand` STRING) — concluded brand had to come from a `product_brand_map` join instead.
2. **That table turned out to be the wrong one entirely.** `magpie.marketshare_universe`'s TH data (live-queried,
   latest month) is 100% appliance/electronics categories (Lighting, Grooming, Rice Cooker, Air Purifier, etc.) —
   it's a separate Intrepid/appliance universe, not where FMCG categories like `shopee_th_toothpaste` live. The
   table `headless_taxonomy.sh` and this tier actually need is **`magpie.marketshare_universe_niq`**
   (`sql/schema/marketshare_universe_niq.sql`, live-confirmed) — it has `master_table`, `product_id`,
   `ecommerce_platform`, `sku_name`, and **already-denormalized** `brand_id`/`brand_confidence`/`brand_source`,
   matching `docs/brand-extraction.md`'s cascade exactly (live-checked distribution for
   `shopee_th_toothpaste`: `HIGH`/`BRAND_FIELD` 6,996, `UNRESOLVED`/`FALLBACK` 2,011, `MEDIUM`/`PRODUCT_NAME_SCAN`
   1,206, `HIGH`/`PRODUCT_NAME_SCAN` 340 — real numbers, not the stale schema's aspiration). No
   `product_brand_map` join needed after all — this table's own columns are the correct source, gated exactly as
   originally assumed:

```sql
WHERE u.brand_confidence IN ('HIGH', 'MEDIUM')
  AND u.brand_id NOT IN ('BRD-UNDEFINED', 'BRD-UNBRANDED')
```

The `NOT IN (...)` half matters as much as the confidence check: `BRD-UNDEFINED`/`BRD-UNBRANDED` are both
"resolved" values in a data-quality sense, but filtering candidates by either would pool every unknown-brand or
generic-brand taxonomy entry across the *entire* catalog into one candidate set — exactly the cross-product
collision risk the brand filter exists to prevent in the first place.

**Scope consequence:** since `marketshare_universe_niq` is TH+SG NIQ only (matching `headless_taxonomy.sh`'s own
`master_clean_niq.*` source and its explicit warning against the unconfirmed Intrepid path), this tier's
practical scope for auto-match/audit is TH+SG NIQ categories, full stop — not a hedge, a direct consequence of
which table has the data. Cross-category matching still holds (Scope section above) *within* that NIQ universe.

**Size filter is a soft fallback.** `parse_size` coverage is narrower (TH-only today) than brand resolution
(75–90% broad per the traditional-ml doc), so requiring it would gut coverage for a much smaller safety win than
requiring brand does. When `parse_size` returns NULL, match on brand + embedding alone, at a stricter
`AUTO_MATCH_MAX_DISTANCE`/`AUDIT_FLAG_MAX_DISTANCE` pair than the size-filtered case uses.

**Illustrative auto-match query shape** (final SQL and threshold constants are implementation-plan work, not
fixed here — but the embedding call itself is no longer illustrative-syntax territory, since generation now
happens on the Hetzner worker and this query only ever reads plain `ARRAY<FLOAT64>` data via `ML.DISTANCE`):

```sql
-- Illustrative — thresholds TBD by the pilot (see Testing below). Uses JOIN + QUALIFY ROW_NUMBER() for
-- top-1-per-product selection, not a LATERAL join — confirmed live (2026-07-17) that BigQuery has no LATERAL
-- keyword; a bare correlated subquery in FROM fails with "Unrecognized name" for the outer alias. QUALIFY is
-- the same top-1-per-group idiom this repo's own universe-refresh MERGE query already uses.
INSERT INTO `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
  (product_id, master_table, platform, country, taxonomy_id, source, confidence, meta_agent, mapped_at)
SELECT
  u.product_id, u.master_table, u.ecommerce_platform, u.country,
  pt.taxonomy_id, 'EMBEDDING_MATCH', FORMAT('%.2f', 1 - dist), @meta_agent, CURRENT_TIMESTAMP()
FROM `sincere-hearth-273704.magpie.marketshare_universe_niq` u
JOIN `sincere-hearth-273704.magpie_reference.universe_sku_embeddings` ue
  ON ue.product_id = u.product_id AND ue.platform = u.ecommerce_platform AND ue.country = u.country
LEFT JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
  ON m.product_id = u.product_id AND m.platform = u.ecommerce_platform AND m.country = u.country
CROSS JOIN UNNEST([`sincere-hearth-273704.magpie_reference.parse_size`(u.sku_name)]) AS parsed
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt
  ON pt.brand_id = u.brand_id
  AND (parsed.size_text IS NULL OR pt.size = parsed.size_text)
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_embeddings` pte
  ON pte.taxonomy_id = pt.taxonomy_id
CROSS JOIN UNNEST([ML.DISTANCE(ue.embedding, pte.embedding, 'COSINE')]) AS dist
WHERE u.brand_confidence IN ('HIGH', 'MEDIUM')
  AND u.brand_id NOT IN ('BRD-UNDEFINED', 'BRD-UNBRANDED')
  AND u.master_table = @table
  AND m.taxonomy_id IS NULL                -- never touch an already-mapped product
QUALIFY ROW_NUMBER() OVER (PARTITION BY u.product_id, u.ecommerce_platform, u.country ORDER BY dist ASC) = 1
  AND dist <= @auto_match_max_distance;
```

(`UNNEST([scalar_expr]) AS alias` is BigQuery's way to bring a computed scalar into scope as a joinable column — confirmed live; BigQuery does not support the `AS alias(column)` column-alias-list syntax some other engines use for this. `product_brand_map` is no longer needed — `marketshare_universe_niq` has its own brand columns.)

`confidence` is written as a formatted string (`'0.87'`), not a FLOAT64 — live `product_taxonomy_map.confidence`
is STRING (confirmed via `INFORMATION_SCHEMA.COLUMNS`, another place the schema file's documented FLOAT64 type
doesn't match reality), matching the numeric-string convention existing `source='LLM'` rows already use (e.g.
`'0.85'`, `'0.95'`).

**Illustrative audit query shape** is the same candidate/distance logic, filtered to `m.source = 'LLM'` instead of
`m.taxonomy_id IS NULL`, comparing `cand.taxonomy_id` against the existing `m.taxonomy_id`, and writing to
`taxonomy_match_audit_flags` instead of `product_taxonomy_map` — omitted here to avoid duplicating the same shape
twice; the implementation plan writes both queries out in full against the real schema.

## Wiring into `script/headless_taxonomy.sh`

Auto-match runs as a **bash-level pre-step, before the `claude -p` invocation** — not folded into the LLM
session's own instructions. Deterministic SQL belongs outside the prompt, same posture as everything else this
tier does; it also means the pre-step runs (and can fail or no-op) independently of whatever the LLM session
does.

```bash
# script/headless_taxonomy.sh — new block, inserted after argument parsing, before the claude -p call
echo "Running embedding pre-match for ${TABLE}..."
bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 \
  --parameter=table:STRING:"${TABLE}" \
  < sql/queries/embedding_match_auto.sql \
  || echo "Embedding pre-match failed or found nothing — continuing to claude -p unfiltered."
```

- **Scoped to this run's table** (`WHERE u.master_table = @table AND m.taxonomy_id IS NULL`) — but the *candidate*
  side of the match (`product_taxonomy`) is still the full cross-category table, per the Scope section above.
  Only the *incoming* side is scoped to `${TABLE}`; that's what makes this useful for a from-scratch category
  build, catching products that already exist elsewhere in the taxonomy.
- **Never blocks the run.** The `||` fallback means a failed or empty pre-match still lets `claude -p` proceed
  and do a normal Pass 1/Pass 2 build — this tier is a pure optimization on LLM volume, never a correctness
  dependency. `set -e` in the script would otherwise abort the whole Full Rebuild over what should be a
  best-effort filter.
- **The existing `claude -p` prompt needs one added line**, not a restructure: STEP 1 already runs `SELECT
  source, COUNT(*) FROM product_taxonomy_map WHERE master_table = @table GROUP BY source` and already tells the
  session not to assume 0/0 — `source='EMBEDDING_MATCH'` rows just show up as another value in that breakdown
  the session already has to handle. Add: *"Do not re-extract or re-map any product that already has a
  `source='EMBEDDING_MATCH'` row — Pass 1/Pass 2 scope to products with no existing map row at all."*
- **Net effect:** by the time Pass 1 starts, some fraction of `${TABLE}`'s products already have a taxonomy_id
  (reused from elsewhere in the catalog, zero LLM cost) — directly shrinking the candidate pool Pass 1/Pass 2
  and any per-image vision reads have to cover, which is the cost/duration half of the original problem this
  tier targets.
- The sg_shampoo-style worked example embedded directly in `docs/headless-runbook.md` (not `headless_taxonomy.sh`
  itself) should get the same pre-step and prompt line eventually, for consistency — not required for this
  design to land, flagged as a natural same-shape follow-up.

## Safety guards

- **Auto-match only ever `INSERT`s new rows**, guarded by `WHERE m.taxonomy_id IS NULL` (same shape as the size
  regex pass's `size IS NULL` guard) — structurally cannot overwrite an existing map row.
- **Audit mode only ever appends to `taxonomy_match_audit_flags`**, a new table separate from
  `product_taxonomy_map` — it cannot corrupt existing taxonomy state no matter how noisy the matcher is.
- **No confident candidate** (filters leave nothing, or top-1 exceeds the threshold) → skip; product falls
  through to Tier 5 unchanged. This is the expected common case for anything outside this tier's confidence, not
  an error.
- **No embedding yet for a given row** (Hetzner worker hasn't reached it — see cold-start note above) → the
  `JOIN` against `universe_sku_embeddings`/`product_taxonomy_embeddings` simply excludes that row; no special
  error handling needed since an inner join already skips anything missing an embedding.
- **Worker-side failure** (model load error, BigQuery load job failure) → the cron run logs and exits non-zero;
  next scheduled run picks up wherever the "not yet embedded" query naturally leaves off. No partial-state
  cleanup needed since the worker only ever adds rows to the embeddings tables, never updates or deletes.
- **Rollback is cheap**: undo a bad auto-match run with `DELETE ... WHERE source = 'EMBEDDING_MATCH' AND
  created_at >= <run start>` — no manual pre-run snapshot needed, unlike the regex pass's UPDATE-based backfill.
- **`meta_agent` set on every inserted row** per the AGENTS.md hard rule; `source = 'EMBEDDING_MATCH'` keeps
  provenance distinguishable from `'LLM'` directly, without needing to infer it from `updated_at` the way the
  regex pass's rows currently have to.
- Standard dry-run discipline (`bq query --dry_run`) before any real run, given the join touches
  `marketshare_universe_niq`.
- **Known residual gap, not solved here:** with no live pack_count extractor (out of scope per the regex pass's
  own constraints), a single-unit product and its bulk-pack sibling could embed as near-neighbors if
  `canonical_name`'s trailing `x{N}` token doesn't dominate the distance calculation. The pilot should
  specifically eyeball any mismatches of this shape rather than assume the size filter alone rules it out.

## Testing / the pilot

- **Read-only pilot against `th_toothpaste`**: for every product already correctly mapped by past LLM sessions,
  run the brand+size-filtered embedding search and compare its top-1 against the known-correct `taxonomy_id`.
  Because this ground truth is already right, any disagreement in the pilot *is* a false positive — one pilot run
  measures both auto-match precision (sets `AUTO_MATCH_MAX_DISTANCE`) and audit-mode false-positive rate (sets
  `AUDIT_FLAG_MAX_DISTANCE`) at once.
- **Pass bar:** pick the tightest distance where auto-match precision is ≥98% against this set before trusting it
  to write unattended.
- Unlike `parse_size`'s embedded static test block, this runnable check is necessarily a live read-only query
  against real taxonomy data — it depends on the Hetzner worker having already embedded `th_toothpaste`'s catalog
  and universe rows, not hardcoded structs.
- **Pilot precondition:** run the Hetzner worker against `th_toothpaste`'s ~4,177 mapped products and its
  taxonomy entries first (a small, fast one-off run, not waiting for the full cron cadence) before the
  precision-measurement query can return anything.
- Only after the pilot clears the precision bar: auto-match rolls out to new TH products first; audit mode can
  run immediately across all existing `source='LLM'` rows since it's flag-only.

## Out of scope

- **Pack_count-aware matching** — no live pack_count extractor exists yet (deferred by the regex pass's own
  design); this tier inherits that gap rather than solving it. Flagged as a residual risk above, not blocking.
- **A vector index** (e.g. `VECTOR_SEARCH` with `CREATE VECTOR INDEX`) — the catalog is small enough today that
  brute-force distance over the brand/size-filtered candidate set is cheap; add an index later only if the
  catalog grows enough to make brute-force costly. Not needed at current scale.
- **Auto-fixing audit-flagged mismatches** — audit mode only ever produces a flag for human/LLM QA review, never
  an automatic correction. Closing that loop (what happens to a flagged row) is separate follow-up work, not
  designed here.
- **MY/PH/VN or ID rollout** — same reasoning as the regex pass: `product_taxonomy_map` has zero rows for ID
  (per that design's findings) and no reported need yet for MY/PH/VN. TH (and SG once its LLM coverage grows
  past `sg_toothpaste`) is the actual scope.
- **Wiring this into the external Phase 5 Python pipeline** so it consults this tier's output before calling the
  LLM — this design is self-contained in BigQuery, same posture as the regex pass; cross-repo integration is a
  separate follow-up.

## Deliverables

1. Two new BigQuery tables: `magpie_reference.product_taxonomy_embeddings` and
   `magpie_reference.universe_sku_embeddings` (schemas above).
2. A new BigQuery table `magpie_reference.taxonomy_match_audit_flags` (product_id, platform, country, current
   taxonomy_id, suggested taxonomy_id, distance, flagged_at).
3. The Hetzner-VM embedding worker (Python script + cron entry) — embeds `product_taxonomy.canonical_name` and
   `marketshare_universe_niq.sku_name` for rows not yet present in the tables above, using
   `intfloat/multilingual-e5-large` via `sentence-transformers`, batch-loaded back via `bq load`.
4. `sql/queries/embedding_match_auto.sql` — the auto-match INSERT query.
5. `sql/queries/embedding_match_audit.sql` — the audit-flag INSERT query (same matching logic, different
   destination and filter).
6. Pilot validation query + recorded results against `th_toothpaste`, determining the two distance thresholds —
   findings recorded in the implementation plan the way the regex pass's discovery findings were merged into its
   own plan's Appendix.
7. A short subsection in `docs/llm-extraction-rules.md` (or a new `docs/embedding-match.md`, TBD in the plan)
   documenting that a pre-mapping step now runs before Tier 5, and that `source='EMBEDDING_MATCH'` /
   `taxonomy_match_audit_flags` are new things a session touching taxonomy provenance should know about.
8. `script/headless_taxonomy.sh` modified: the `bq query` pre-step added before its `claude -p` invocation, and
   the one-line addition to that prompt telling the session not to re-map `source='EMBEDDING_MATCH'` rows (see
   Wiring section above).

## Relationship to other designs

- Depends on Tier 0 (brand resolution, existing) and Tier 1/2 (`parse_size`, live — see
  [`docs/superpowers/specs/2026-07-14-size-regex-pass-design.md`](2026-07-14-size-regex-pass-design.md)) as hard
  and soft filters respectively.
- Natural following step, per `traditional-ml-execution-model.md`'s own suggested sequencing: Tier 4 (clustering
  unmatched products) only pays off once this tier exists to feed it a genuine "no confident match" pool — not
  designed here, flagged as the next tier after this one ships and its pilot results are in.
