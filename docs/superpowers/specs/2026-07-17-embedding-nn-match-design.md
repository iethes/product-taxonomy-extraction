# Design: Embedding + Nearest-Neighbor Taxonomy Match, with an LLM-Compliance Audit Mode (Rec 3, `traditional-ml-execution-model.md`)

> Status: approved design, not yet implemented.
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
  `docs/categories/STATUS.md`), ~700 taxonomy rows across two SKU blocks, 92.5% GMV coverage. Its already-correct
  LLM mappings serve as ground truth to tune both thresholds below before either mode runs unattended anywhere.
- **Country/category rollout after the pilot clears its precision bar:** auto-match starts on new TH products
  (brand + size resolution both most mature there); audit mode can run across all existing `source='LLM'` rows
  immediately, since it only ever produces a flag and can't damage existing state.

## Mechanism

**Ordering dependency:** this tier runs strictly after Tier 0 (brand) and Tier 1/2 (`parse_size`), and consumes
both of their outputs as filters rather than re-deriving brand or size itself.

```
Tier 0 (brand_id resolved?) ──not resolved──▶ skip this tier entirely, product goes to Tier 5 as today
       │ resolved
       ▼
Tier 1/2 (parse_size(sku_name))
       │
       ▼
Candidate filter: product_taxonomy WHERE brand_id = <resolved> AND size = <parsed size, if any>
       │
       ▼
AI.EMBED(sku_name) vs. AI.EMBED(canonical_name) over the filtered candidates, top-1 by cosine distance
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
`FALLBACK`), and the result is already denormalized onto `marketshare_universe.brand_id`/`brand_confidence`. This
tier just reads that column, gated the same way `marketshare_universe.sql`'s own documented "standard market
share filter" already gates it:

```sql
brand_confidence IN ('HIGH', 'MEDIUM') AND brand_id NOT IN ('BRD-UNDEFINED', 'BRD-UNBRANDED')
```

The `NOT IN (...)` half matters as much as the confidence check: `BRD-UNDEFINED`/`BRD-UNBRANDED` are both
"resolved" values in a data-quality sense, but filtering candidates by either would pool every unknown-brand or
generic-brand taxonomy entry across the *entire* catalog into one candidate set — exactly the cross-product
collision risk the brand filter exists to prevent in the first place.

**Size filter is a soft fallback.** `parse_size` coverage is narrower (TH-only today) than brand resolution
(75–90% broad per the traditional-ml doc), so requiring it would gut coverage for a much smaller safety win than
requiring brand does. When `parse_size` returns NULL, match on brand + embedding alone, at a stricter
`AUTO_MATCH_MAX_DISTANCE`/`AUDIT_FLAG_MAX_DISTANCE` pair than the size-filtered case uses.

**Illustrative auto-match query shape** (final SQL, exact `AI.EMBED`/`AI.SEARCH` syntax, and threshold constants
are implementation-plan work, not fixed here):

```sql
-- Illustrative — thresholds and exact embedding-function calls TBD by the pilot (see Testing below).
INSERT INTO `magpie_reference.product_taxonomy_map`
  (product_id, platform, country, taxonomy_id, source, confidence, meta_agent, created_at)
SELECT
  u.product_id, u.platform, u.country,
  cand.taxonomy_id, 'EMBEDDING_MATCH', 1 - cand.distance, @meta_agent, CURRENT_TIMESTAMP()
FROM `magpie.marketshare_universe` u
JOIN <brand resolution output>  b  ON b.product_id = u.product_id  -- Tier 0's resolved brand_id
LEFT JOIN `magpie_reference.product_taxonomy_map` m
  ON m.product_id = u.product_id AND m.platform = u.platform AND m.country = u.country
CROSS JOIN UNNEST([magpie_reference.parse_size(u.sku_name)]) AS parsed
, LATERAL (
    SELECT pt.taxonomy_id,
           ML.DISTANCE(AI.EMBED(u.sku_name), AI.EMBED(pt.canonical_name), 'COSINE') AS distance
    FROM `magpie_reference.product_taxonomy` pt
    WHERE pt.brand_id = b.brand_id
      AND (parsed.size_text IS NULL OR pt.size = parsed.size_text)
    ORDER BY distance ASC
    LIMIT 1
  ) cand
WHERE m.taxonomy_id IS NULL              -- never touch an already-mapped product
  AND cand.distance <= @auto_match_max_distance;
```

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
- **`AI.EMBED` failure/NULL on a given row** → skip that row for the run, don't fail the batch; tally skips in a
  run summary.
- **Rollback is cheap**: undo a bad auto-match run with `DELETE ... WHERE source = 'EMBEDDING_MATCH' AND
  created_at >= <run start>` — no manual pre-run snapshot needed, unlike the regex pass's UPDATE-based backfill.
- **`meta_agent` set on every inserted row** per the AGENTS.md hard rule; `source = 'EMBEDDING_MATCH'` keeps
  provenance distinguishable from `'LLM'` directly, without needing to infer it from `updated_at` the way the
  regex pass's rows currently have to.
- Standard dry-run discipline (`bq query --dry_run`) before any real run, given the join touches
  `marketshare_universe`.
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
  against real taxonomy data — it depends on `AI.EMBED` output and the actual catalog, not hardcoded structs.
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

1. A new BigQuery table `magpie_reference.taxonomy_match_audit_flags` (product_id, platform, country, current
   taxonomy_id, suggested taxonomy_id, distance, flagged_at).
2. `sql/queries/embedding_match_auto.sql` — the auto-match INSERT query.
3. `sql/queries/embedding_match_audit.sql` — the audit-flag INSERT query (same matching logic, different
   destination and filter).
4. Pilot validation query + recorded results against `th_toothpaste`, determining the two distance thresholds —
   findings recorded in the implementation plan the way the regex pass's discovery findings were merged into its
   own plan's Appendix.
5. A short subsection in `docs/llm-extraction-rules.md` (or a new `docs/embedding-match.md`, TBD in the plan)
   documenting that a pre-mapping step now runs before Tier 5, and that `source='EMBEDDING_MATCH'` /
   `taxonomy_match_audit_flags` are new things a session touching taxonomy provenance should know about.
6. `script/headless_taxonomy.sh` modified: the `bq query` pre-step added before its `claude -p` invocation, and
   the one-line addition to that prompt telling the session not to re-map `source='EMBEDDING_MATCH'` rows (see
   Wiring section above).

## Relationship to other designs

- Depends on Tier 0 (brand resolution, existing) and Tier 1/2 (`parse_size`, live — see
  [`docs/superpowers/specs/2026-07-14-size-regex-pass-design.md`](2026-07-14-size-regex-pass-design.md)) as hard
  and soft filters respectively.
- Natural following step, per `traditional-ml-execution-model.md`'s own suggested sequencing: Tier 4 (clustering
  unmatched products) only pays off once this tier exists to feed it a genuine "no confident match" pool — not
  designed here, flagged as the next tier after this one ships and its pilot results are in.
