# Targeted QA Fix V2 + NIQ Script Reorg — Design

**Status:** Approved, ready for implementation planning.

## Goal

Reduce the per-session cost of the auto-discovery QA loop (`targeted_qa_fix.sh`'s auto-discovery mode) by
moving worklist discovery, mechanical defect detection, and reference-candidate retrieval out of the agentic
`claude -p` session and into deterministic SQL/Python that runs before the agent is ever invoked. The agent's
job shrinks to: given a pre-built worklist row (with its Tier-1 flags, similar-entry candidates, and sample
titles already attached), judge it and apply the fix. Ship this as a new script, `targeted_qa_fix_v2.sh`,
alongside the existing `targeted_qa_fix.sh` rather than editing it in place.

Also: reorganize NIQ-coupled scripts into `script/niq/` (mirroring the existing `script/non_niq/` convention),
move all shell/Python test files into a new top-level `tests/` tree, and migrate Python dependency management
to `uv`.

## Context / prior art

- `script/targeted_qa_fix.sh`'s auto-discovery mode already does a two-tier review (Tier 1: cheap regex SQL
  sweep for mechanical defects; Tier 2: bounded GMV-prioritized LLM judgment) — see
  `docs/superpowers/specs/2026-07-21-taxonomy-review-loop-design.md` and
  `docs/superpowers/specs/2026-07-28-qa-fix-one-pass-confidence-design.md`. V2 reuses this two-tier model; it
  does not redesign the QA rules themselves.
- `docs/superpowers/plans/2026-07-17-embedding-nn-match.md` attempted an embedding-based (multilingual-e5-large)
  nearest-neighbor matcher for **auto-writing** new product→taxonomy mappings. It is blocked: precision
  plateaued at ~55-59% overall (85% even in the easiest "unambiguous" bucket), far short of the 0.98 bar needed
  to trust it unattended. **This history directly shaped V2's scope**: the candidate lists V2 introduces are
  explicitly advisory/reference-only, never a basis for an autonomous decision, and use plain SQL string
  similarity (not embeddings) — see "Non-goals" below.
- `script/non_niq/` already establishes the self-contained-folder-per-pipeline convention this reorg extends to
  NIQ.

## Non-goals

- Not re-litigating or changing the Tier-1 regex rules or the `_meta.review_confidence` promotion logic — both
  carry over from V1 unchanged.
- Not building brief-mode support into V2. Brief-mode QA fixes stay on `targeted_qa_fix.sh` (V1).
- Not reviving the embedding-match approach. No new embedding infrastructure; candidate retrieval is plain
  BigQuery SQL (`EDIT_DISTANCE`), computed fresh per run — no dependency on the Hetzner worker or embedding
  table freshness.
- Not auto-applying STEP 2c's mechanical single-value size/pack fix in this version — that's real, deferred
  scope (see "Deferred to V2.1").

## 1. Folder reorg

**`script/niq/`** (moved from `script/`):
```
headless_taxonomy.sh
targeted_qa_fix.sh
targeted_qa_fix_v2.sh        (new, this design)
custom_headless_taxonomy.sh
custom_targeted_qa_fix.sh
qa_report.sh
qa_coverage_report.sh
queue_worker.sh
queue_ctl.sh
embedding_worker.py
embedding_worker_requirements.txt   (superseded by pyproject.toml — see §5; remove once migrated)
taxonomy_match_encoding.py
train_taxonomy_matcher.py
compute_training_features.py
qa_v2_worklist.py            (new, this design)
```

**`script/non_niq/`**: unchanged — production files only (`non_niq_sheet.py`, `non_niq_embed.py`,
`non_niq_qa.sh`, `non_niq_queue_worker.sh`).

**`script/`** (stays at top level — genuinely shared or standalone):
`load_env.sh`, `migrate_category_docs_to_bq_2026_07_29.py`, `poc_multimodal_match.sh` (untracked POC, excluded
from this reorg).

**`tests/niq/`**: `test_headless_taxonomy.sh`, `test_targeted_qa_fix.sh`, `test_custom_headless_taxonomy.sh`,
`test_custom_targeted_qa_fix.sh`, `test_queue_worker.sh`, `test_queue_ctl.sh`, plus new
`test_targeted_qa_fix_v2.sh` and `test_qa_v2_worklist.py`. Each updated to source/import from
`../../script/niq/<file>` instead of `script/<file>`.

**`tests/non_niq/`**: `non_niq/`'s existing `test_non_niq_sheet.py`, `test_non_niq_embed.py`,
`test_non_niq_qa.sh`, `test_non_niq_queue_worker.sh`, same path-fix treatment.

**`tests/`** (top level, for scripts staying at `script/` top level): `test_load_env.sh`,
`test_migrate_category_docs_to_bq_2026_07_29.py`.

**Follow-up reference updates required:** `docs/headless-runbook.md`, `CLAUDE.md`'s common-pitfalls table, any
crontab entries (per the embedding-nn-match plan's Task 2 Step 7), and internal `./script/X.sh` / `script/X.py`
string references across every moved file.

## 2. Candidate retrieval

Two bulk SQL queries (not one query per worklist row), each using the existing
`QUALIFY ROW_NUMBER() OVER (PARTITION BY ... ORDER BY ...)` top-N idiom already established in
`sql/queries/embedding_match_auto.sql`. Both live as dedicated files under `sql/queries/` (not inline bash
heredocs), consistent with that existing convention.

### `sql/queries/qa_v2_taxonomy_candidates.sql`

For each worklist row, top **5** other `product_taxonomy` rows where:
- `JSON_VALUE(_meta, '$.review_confidence') = 'confident'`
- same `brand_id` as the row under review (hard filter — brand is already resolved; this also makes the
  candidate list double as a duplicate-detection signal, since a same-brand near-identical `canonical_name` at
  high similarity is what the existing dedup-authorized-session check looks for)
- ranked by `EDIT_DISTANCE(canonical_name, candidate.canonical_name)` normalized by
  `GREATEST(LENGTH(canonical_name), LENGTH(candidate.canonical_name))`, ascending
- excludes the row's own `taxonomy_id`

### `sql/queries/qa_v2_brand_candidates.sql`

For each worklist row, top **3** `brand_dict.canonical_name` entries (excluding the row's own `brand_id`),
ranked by `EDIT_DISTANCE` (same normalization) between the row's own resolved `brand_dict.canonical_name` and
the candidate's, capped at normalized distance `< 0.4` to exclude unrelated brands. Serves two documented V1
pain points directly: `garbage_brand`'s fix ("find or create the correct brand_dict entry") and
`wrong_field_order` case (b) (brand_id resolves wrong despite correct canonical_name text) — Python hands the
agent a short candidate list instead of the agent running its own blind brand_dict search mid-session.

**n=5 / n=3 rationale:** reference context only, never decision authority — the Tier-2 judgment step still
independently verifies against `sku_name`/image. Large enough to show format spread and surface an obvious
duplicate; small enough that per-row prompt cost doesn't balloon across a whole worklist (unlike V1, where the
agent ran one exploratory query at a time and paid for it in turns, not prompt size).

## 3. `script/niq/qa_v2_worklist.py` — the worklist builder

Pure SQL/Python, zero LLM calls. Steps, in order:

1. **Fast-lane auto-promotion** (reuses V1 STEP 1C's logic, already proven judgment-free): query the
   "fixed, pending recheck" bucket (`_meta IS NOT NULL AND JSON_VALUE(_meta, '$.review_confidence') IS NULL`),
   run the Tier-1 regex sweep against it, bulk-`UPDATE` promote fully-clean rows straight to `confident` via
   `bq` DML — before any prompt is built. This is a direct cost removal: these rows never reach `claude -p` at
   all.
2. **Build the strict-tier worklist**: query never-reviewed rows (`_meta IS NULL`) sorted by GMV desc, then
   unconfident rows (`review_confidence != 'confident'`, `_meta IS NOT NULL`) sorted by GMV desc, concatenated
   in that order — never-reviewed rows are fully exhausted before any unconfident row is considered, regardless
   of relative GMV. Cap to `--block-size` (default 200, matching V1's convention).
3. **Tier-1 sweep**, scoped to just this batch (cheaper than V1's whole-category sweep since the batch is
   already selected) — same regex flags as V1 (`stub_leak`, `duplicate_brand`, `wrong_field_order`,
   `brand_casing_mismatch`, `excess_content`, `canonical_field_mismatch`, `null_size`, `garbage_brand`,
   `count_as_size`, `provenance_leak`), ported from `targeted_qa_fix.sh`'s heredoc into
   `sql/queries/qa_v2_tier1_sweep.sql`.
4. **Candidate retrieval** (§2's two queries), scoped to this batch's `taxonomy_id`s.
5. **Sample `sku_name`s**: top 3 distinct per row, same pass.
6. Assemble one JSON object per row:
   `{taxonomy_id, canonical_name, brand, gmv, tier, tier1_flags, taxonomy_candidates, brand_candidates, sample_sku_names}`,
   printed to stdout for the bash wrapper to embed into the prompt.

CLI: `python3 script/niq/qa_v2_worklist.py --table <TABLE> --block-size <N>`.

## 4. `script/niq/targeted_qa_fix_v2.sh` — the wrapper

Auto-discovery only, no brief-mode branch.

1. Parse `<TABLE> [BLOCK_SIZE] [MAX_TURNS]` (same signature as V1).
2. Run `qa_v2_worklist.py` (§3) — performs fast-lane promotion writes directly, then prints the
   candidate-enriched worklist JSON.
3. If the worklist is empty after fast-lane promotion → `QUEUE_SIGNAL: NOTHING_TO_DO`, exit clean (same as V1).
4. Build the prompt: embed the worklist JSON directly. Point at `llm-extraction-rules.md`,
   `quality-standards.md`, `brand-extraction.md` for the *rules* to apply, but do not restate V1's STEP
   1/2/2b/2c/3 SQL — the agent's job is "judge and fix what's given," not "discover what needs reviewing."
   STEP 4 (apply fix via `bq` DML), STEP 5 (promote `_meta`, same Path 1/Path 2 rules as V1), STEP 6 (SKU block
   claim if minting), STEP 7-11 (write discipline — DML only, no deletes, `meta_agent` always set, blocker
   handling, self-check against hard gates) carry over from V1 near-verbatim.
5. Post-processing reused near-verbatim from V1, repointed at `script/niq/` paths: `decide_next_step`,
   independent `qa_report.sh` re-check before universe refresh, `QA_HISTORY` insert via `category_brief`,
   `mark_failed_qa`, the `EXIT` trap running `qa_coverage_report.sh`.

**Net effect vs. V1:** removed from the agent's job — worklist discovery, Tier-1 sweep execution, sample-title
lookups, brand_dict/duplicate searches. Kept — image reads where a fix needs a re-derived value, the actual
DML writes, and judgment calls Tier 1 can't make mechanically.

## 5. Python dependency management: migrate to `uv`

Current state: one top-level `requirements.txt` plus a narrower `script/embedding_worker_requirements.txt`,
installed manually via `pip install -r` into ad-hoc venvs. `.venv-embedding/` (gitignored, untracked) was
hand-built during the embedding-match pilot against a macOS-only pyenv path from `CLAUDE.md` that doesn't apply
on this machine.

1. `rm -rf .venv-embedding/` (gitignored, safe to delete).
2. Add root `pyproject.toml`; migrate `requirements.txt`'s dependencies into it via `uv add` — one unified
   dependency set (matching today's single-`requirements.txt` convention; no per-folder split between
   `script/niq/` and `script/non_niq/`, since there's no real isolation need).
3. Drop `script/embedding_worker_requirements.txt` once its contents are confirmed covered by the unified
   `pyproject.toml`.
4. `uv sync` to build `.venv/` (uv's default location) and generate `uv.lock`.
5. `qa_v2_worklist.py`'s dependencies (`google-cloud-bigquery`, likely `pandas`) go into this same
   `pyproject.toml` from the start.
6. Update stale references to the old install path: `docs/superpowers/plans/2026-07-17-embedding-nn-match.md`
   Task 2 Step 3, and `CLAUDE.md`'s Environment Setup section if it's meant to apply on this machine.

This is Task 1 of the implementation plan — environment groundwork before any new script depends on it.

## 6. Testing

- `tests/niq/test_qa_v2_worklist.py`: unit tests against the SQL-string-builder functions and the fast-lane
  promotion decision logic (mock the BigQuery client).
- `tests/niq/test_targeted_qa_fix_v2.sh`: mirrors V1's `test_targeted_qa_fix.sh` convention — source the
  script, assert on `decide_next_step`, `extract_json_object`, and prompt-building functions.
- All reorged test files (§1) get their source/import paths fixed as part of the move, verified by actually
  running them post-move.

## Open verification items (first implementation steps, not open design questions)

- Confirm `EDIT_DISTANCE` is available in this project's BigQuery Standard SQL dialect (it's a documented GA
  string function, but the embedding-nn-match plan's own "no `LATERAL` keyword" note shows this project has
  been burned by assumed-available SQL before) — dry-run `qa_v2_taxonomy_candidates.sql` and
  `qa_v2_brand_candidates.sql` against a real table before wiring them into `qa_v2_worklist.py`, same discipline
  the embedding-match plan used for `ML.DISTANCE`.
- The brand-candidate normalized-distance cutoff (`< 0.4`) is an initial guess, not a validated threshold —
  spot-check its precision/recall against one real category (e.g. re-run the kind of eyeball check done for
  `shopee_id_baby_diapers`) during implementation and adjust if it's letting through noise or excluding genuine
  near-duplicates.

## Deferred to V2.1 (explicitly out of scope here)

- Auto-applying STEP 2c's mechanical single-value size/pack fix (aggregation query → write-in-place → re-check)
  without any LLM judgment. Real, judgment-free win per V1's own documentation, but a second distinct auto-fix
  code path — deferred until the core candidate-retrieval design is validated against a real category.
