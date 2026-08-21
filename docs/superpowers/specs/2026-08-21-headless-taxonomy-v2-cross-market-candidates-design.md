# Headless Taxonomy V2 — Cross-Market Candidate Retrieval — Design

**Status:** Approved, ready for implementation planning.

## Goal

Port `targeted_qa_fix_v2.sh`'s candidate-retrieval pattern (pre-fetch reference candidates in Python/SQL
before `claude -p` ever runs, embed as JSON, agent judges instead of discovering) into a new
`headless_taxonomy_v2.sh` — with one extension: candidates aren't limited to the current table. They also
pull from **sibling category tables in other countries** (e.g. `shopee_id_adult_diapers` pulling reference
from `shopee_th_adult_diapers`), since a new-market first-run session has no in-table taxonomy to match
against yet, but an already-QA'd sibling market usually does.

Ship as a new script alongside the existing `headless_taxonomy.sh` (V1 untouched), same convention as
`targeted_qa_fix_v2.sh` alongside `targeted_qa_fix.sh`.

## Context / prior art

- `sql/queries/qa_v2_taxonomy_candidates.sql` / `qa_v2_brand_candidates.sql` +
  `script/niq/qa_v2_worklist.py` (`docs/superpowers/specs/2026-08-10-targeted-qa-fix-v2-design.md`) are the
  direct template: plain `EDIT_DISTANCE` SQL, `review_confidence='confident'`-gated, advisory-only,
  never a basis for an autonomous write. This design reuses that discipline wholesale.
- Same history applies here as it did there: the embedding-based nearest-neighbor matcher
  (`docs/superpowers/plans/2026-07-17-embedding-nn-match.md`) is blocked at ~55-59% precision. No
  embeddings in this design either — plain BigQuery string similarity only.
- `master_clean_niq` table names do **not** follow a clean `{platform}_{country}_{category}` match across
  countries — confirmed live 2026-08-21: `shopee_id_adult_diapers` / `shopee_th_adult_diapers` line up, but
  SG's equivalent is `shopee_sg_diapers` (no "adult"), and `hand_and_body_lotion` (ID) vs
  `hand_and_body_moisturiser` (SG) is a same-concept/different-name pair. Sibling discovery has to tolerate
  this — see §1.
- Confirmed live 2026-08-21: `product_brand_map` (Stage 03's automated brand resolution) has **zero rows**
  for `shopee_id_adult_diapers` — it only covers a handful of ID beauty categories today. Brand-scoped
  candidate matching (Tier A, §2) will silently return nothing for tables Stage 03 hasn't reached; the
  design accounts for this via a per-product fallback, not a table-level precondition.

## Non-goals

- Not touching `headless_taxonomy.sh` (V1) — it keeps working exactly as today for anyone still using it.
- Not building a maintained category-family mapping table/config. Sibling discovery is computed fresh each
  run from `INFORMATION_SCHEMA.TABLES`, no new reference table to keep in sync.
- Not adding embeddings or any ML matcher — plain `EDIT_DISTANCE`, per the prior-art precedent above.
- Not giving the agent authority to auto-apply a cross-market candidate. Every candidate (in-table or
  sibling) is reference/format context only — the agent still independently verifies against `sku_name` /
  image before writing anything, identical framing to `qa_v2`'s candidates.
- Not adding a manual sibling-table override/exclude flag in this version — if the Jaccard threshold
  (§1) misfires on a real category, that's a v2.1 follow-up, not blocking this design.

## 1. Sibling-table discovery

Pure string matching, computed fresh per run against `master_clean_niq.INFORMATION_SCHEMA.TABLES` — no
new table to maintain.

**Algorithm**, per table name (e.g. `shopee_id_adult_diapers`):
1. Split on `_`. First token = platform (`shopee`), second = country (`id`), remaining tokens joined = the
   category slug (`adult_diapers`).
2. Tokenize the category slug on `_` into a word set, **minus a small stopword list**
   (`for`, `and`, `or`, `of`, `the`, `a`) — without this, `moisturizer_for_body` vs `moisturizer_for_face`
   score 0.5 Jaccard (2 of 4 tokens shared: `moisturizer`, `for`) and would falsely match two genuinely
   different products. With stopwords stripped: `{moisturizer, body}` vs `{moisturizer, face}` → 0.33,
   correctly excluded.
3. For every other table in `master_clean_niq` with the **same platform, different country**: compute
   Jaccard similarity between the two (stopword-stripped) category-slug token sets.
   `intersection / union >= 0.5` → sibling.
4. Verified against real table names (2026-08-21): `diapers` vs `adult_diapers` → 0.5 ✅. `baby_diapers` vs
   `adult_diapers` → 0.33 ❌ (correctly excluded — baby ≠ adult diapers is a known landmine in this repo).
   `hand_and_body_lotion` vs `hand_and_body_moisturiser` → 0.5 ✅.

**Same-platform-only restriction:** Shopee/Lazada/TikTok have materially different brand-fill and
official-store semantics (`docs/brand-extraction.md` §"Platform Differences") — cross-platform sibling
matching adds noise without a clear benefit here, so it's out of scope for v1 of this feature.

**Transparency:** the matched sibling list (with scores) is printed to stderr by the worklist builder
before the prompt is built, so a human running the script can see exactly which tables got pulled in per
run. Not silent.

## 2. Candidate retrieval query

One query serves both scenarios (first_run and top_up) — see §4 for why no scenario branch is needed here.

`sql/queries/headless_v2_candidate_products.sql` — params `@worklist_product_ids ARRAY<STRING>`,
`@this_table STRING`, `@scope_tables ARRAY<STRING>` (= `[this_table] + siblings`):

**Tier A (brand-scoped, preferred):** join the worklist product to `product_brand_map` (by `product_id`,
`master_table = @this_table`) to get a candidate `brand_id`, then to `product_taxonomy` rows sharing that
`brand_id` whose `taxonomy_id` maps (via `product_taxonomy_map`) to a table in `@scope_tables`, filtered to
`JSON_VALUE(_meta, '$.review_confidence') = 'confident'`. Ranked by `EDIT_DISTANCE(sku_name,
candidate.canonical_name)` normalized by `GREATEST(LENGTH(...), LENGTH(...))`, ascending.

**Tier B (fallback, text-only):** for any worklist product with zero Tier A rows (no `product_brand_map`
row for this table — the confirmed-live case for `shopee_id_adult_diapers` — or no same-brand confident
entry anywhere in scope), drop the brand requirement entirely: same `@scope_tables` + confidence filter,
ranked purely by `EDIT_DISTANCE(sku_name, candidate.canonical_name)`.

Top 5 per worklist product, Tier A rows first, Tier B filling any remaining slots. Each candidate row
carries `{taxonomy_id, canonical_name, source_table, match_tier, normalized_distance}` — `source_table` is
new relative to `qa_v2`'s candidates, so the agent can see at a glance whether a candidate is in-table
(direct reuse candidate) or cross-market (pattern reference only, never a direct reuse target — different
country's taxonomy_id space, never map a product to it).

## 3. `script/niq/headless_v2_worklist.py`

Pure SQL/Python, zero LLM calls, mirrors `qa_v2_worklist.py`'s shape.

1. **Sibling discovery** (§1) — one `INFORMATION_SCHEMA` query + in-Python Jaccard scoring.
2. **Worklist product selection** — scenario-dependent:
   - `top_up`: reuse V1's existing `worklist_query()` SQL verbatim (the 95%-cumulative-GMV,
     GWP-zeroed, `canonical_name IS NULL`, `category_scope_exceptions`-excluded gap query) — ported
     from bash into this Python file, same query text.
   - `first_run`: the in-scope, **non-official-store** product pool (Pass 2's target set) — reuses the
     same 95%-cumulative-GMV worklist shape but additionally excludes rows whose `merchant_name` is in
     the category brief's Official Store Allowlist (Pass 1 already covers those directly via multimodal
     read; they don't need text-candidate reference). Capped to a GMV-sorted top-N block (same
     `compute_block_size` convention V1 already uses, default 2000) — Pass 2 already processes
     bulk-first up to its own turn budget, so precomputing candidates for the whole long tail beyond that
     is wasted work.
3. **Candidate retrieval** (§2), scoped to this batch's product_ids.
4. Assemble one JSON object per worklist product:
   `{product_id, sku_name, merchant_name, gmv, candidates: [...]}`, printed to stdout.

CLI: `python3 script/niq/headless_v2_worklist.py --table <TABLE> --scenario first_run|top_up --month <YYYY-MM> [--block-size N]`.
Scenario detection (gap_count / existing_llm_rows check) stays in the bash wrapper, same as V1 — the
Python builder is told which scenario, not asked to figure it out.

## 4. `script/niq/headless_taxonomy_v2.sh` — the wrapper

Same overall shape as V1 (`decide_scenario`, `compute_block_size`, SKU-block claim, STEP structure,
`decide_queue_signal`) — only the worklist-sourcing and Pass-2-facing prompt text change.

**Why one query serves both scenarios (§2):** `@scope_tables` always includes `@this_table`. For
`first_run`, `product_taxonomy` has zero rows in `@this_table` at precompute time by construction (that's
the definition of first_run) — so the in-table half of the query just contributes zero rows automatically,
no special-casing needed. For `top_up`, it contributes the real in-table matches, same as `qa_v2` does
today. The sibling half fires identically in both scenarios.

**`first_run` prompt changes vs V1:**
- STEP 2 (write category brief), STEP 3 (claim SKU block), STEP 4 (Pass 1, official-store, multimodal) —
  **unchanged verbatim** from V1. No candidates involved; Pass 1 is building from scratch by definition.
- STEP 5 (Pass 2, bulk reseller routing) — the worklist-builder's product-level candidate JSON (§3) is
  embedded directly into this step, replacing V1's "group by brand+line pattern and write your own bulk
  SQL" instruction with "judge the pre-attached candidates per product; in-table candidates
  (`source_table == this table`, only possible for entries your own Pass 1 already created earlier in
  *this* session) are direct reuse candidates; `source_table` from a sibling market is pattern/format
  reference only — never map a product directly to a cross-market `taxonomy_id`, mint or reuse an
  in-table entry informed by it instead."

**`top_up` prompt changes vs V1:**
- STEP 0 stops being "run this SQL yourself" — replaced with "here is your pre-fetched,
  candidate-enriched worklist" (the same v1→v2 shift `targeted_qa_fix_v2.sh` already made). STEP 1's bulk
  reuse-before-mint instruction changes from "write your own fuzzy-matching SQL from scratch" to "judge the
  pre-attached candidates per product, write bulk UPDATE/INSERT DML from your verdicts."
- Everything else (STEP 2 SKU block claim, STEP 3 write discipline, STEP 4 run-log insert, STEP 5 QA-gate
  self-check) carries over from V1 near-verbatim.

**Piping:** same as `targeted_qa_fix_v2.sh` — worklist JSON piped via stdin (`<<< "$prompt"`), not a CLI
arg, since it can exceed `argv` size limits.

## 5. Testing

- `tests/niq/test_headless_v2_worklist.py`: unit tests against the sibling-discovery Jaccard function
  (the exact cases in §1 — `diapers`/`adult_diapers` match, `baby_diapers`/`adult_diapers` don't,
  `hand_and_body_lotion`/`hand_and_body_moisturiser` match) and the SQL-string-builder functions (mock the
  BigQuery client, same pattern as `test_qa_v2_worklist.py`).
- `tests/niq/test_headless_taxonomy_v2.sh`: mirrors `test_targeted_qa_fix_v2.sh` — source the script,
  assert on `decide_queue_signal`, `extract_json_object`, prompt-building functions.

## Open verification items (first implementation steps, not open design questions)

- Jaccard threshold `>= 0.5` is an initial guess validated against exactly 3 hand-picked pairs, not a full
  sweep. Before trusting it: run sibling-discovery across **every** real table pair in `master_clean_niq`
  (same platform, different country) and eyeball the full match list — adjust the threshold if it's letting
  through a false positive as damaging as baby/adult diapers, or missing an obvious true pair.
- Confirm `EDIT_DISTANCE` behaves the same joining across tables at this row scale as it does in `qa_v2`'s
  single-table case — no reason to expect different behavior, but dry-run before wiring into the worklist
  builder, same discipline `qa_v2`'s spec used.
- First_run's official-store-allowlist exclusion (§3 step 2) reads `merchant_name` matching out of the
  category brief's markdown table — confirm this is reliably parseable, or fall back to re-querying the
  same Official Store Allowlist logic directly from `merchant_badge='Shopee Mall'` + the brand list instead
  of parsing brief prose.

## Deferred (explicitly out of scope here)

- Manual sibling-table include/exclude override flag.
- Cross-platform sibling matching (Shopee ↔ Lazada ↔ TikTok).
- A maintained category-family mapping table, if fuzzy matching turns out to misfire often enough in
  practice to need one.
