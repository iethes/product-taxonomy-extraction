# Targeted QA Fix V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `script/niq/targeted_qa_fix_v2.sh` — an auto-discovery QA loop whose worklist (strict-tier
GMV-prioritized, Tier-1-flagged, candidate-enriched) is fully pre-built by SQL/Python before `claude -p` ever
runs, cutting the agentic session down to judgment-and-fix only. Also reorganize NIQ-coupled scripts into
`script/niq/`, move all tests into a `tests/` tree, and migrate Python dependency management to `uv`.

**Architecture:** `script/niq/qa_v2_worklist.py` runs three phases against BigQuery before any LLM is invoked:
(1) fast-lane auto-promotion of already-fixed rows that now pass a clean Tier-1 recheck, (2) a strict-tier
(never-reviewed-before-unconfident) GMV-sorted worklist build capped at `--block-size`, (3) Tier-1 mechanical
flags + same-brand confident-entry candidates + similarly-named brand candidates + sample `sku_name`s, all
attached per row. The result prints as one JSON array. `script/niq/targeted_qa_fix_v2.sh` embeds that JSON
directly into the `claude -p` prompt and reuses `targeted_qa_fix.sh`'s proven post-processing (independent gate
re-check, universe refresh, `FAILED_QA` marking, `QA_HISTORY` insert) verbatim.

**Tech Stack:** BigQuery Standard SQL (`EDIT_DISTANCE`, `QUALIFY ROW_NUMBER()`), Python 3 (`google-cloud-bigquery`)
managed via `uv`, bash + `jq` for the wrapper, `claude -p --output-format json --permission-mode bypassPermissions`.

## Global Constraints

- Source spec: [`docs/superpowers/specs/2026-08-10-targeted-qa-fix-v2-design.md`](../specs/2026-08-10-targeted-qa-fix-v2-design.md) — read it before starting; this plan implements it and does not re-derive its reasoning.
- Project: `sincere-hearth-273704`. All BigQuery table references are fully qualified.
- Candidate lists are advisory/reference-only, never a basis for an autonomous write — the agent still
  independently verifies every row against `sku_name`/image (per the spec's Non-goals, informed by the
  embedding-nn-match plan's blocked ~55-59% precision finding).
- No embeddings for candidate retrieval — plain BigQuery SQL `EDIT_DISTANCE`, no dependency on the Hetzner
  worker or embedding-table freshness.
- Writes use `bq query` DML only, never the streaming API (90-minute streaming-buffer rule). Every written row
  sets `meta_agent` (never NULL).
- Table names are interpolated into f-strings only after a `^[a-zA-Z0-9_]+$` regex guard (BigQuery cannot
  parameterize table identifiers) — same pattern as the existing `script/embedding_worker.py`.
- V2 is auto-discovery only — no brief-mode branch. Brief-mode QA fixes stay on `targeted_qa_fix.sh` (V1),
  unmodified by this plan except for its move to `script/niq/`.
- Never delete an existing `product_taxonomy`/`product_taxonomy_map` row from this script.

---

### Task 1: Migrate Python dependency management to `uv`

**Files:**
- Create: `pyproject.toml`
- Delete: `.venv-embedding/` (directory), `script/embedding_worker_requirements.txt`, `requirements.txt`
- Modify: `README.md:85`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: `.venv/` + `uv.lock` at repo root. Every later Python task (`qa_v2_worklist.py` and its test) runs
  via `uv run python3 ...` against this environment.

- [ ] **Step 1: Confirm `.venv-embedding/` is safe to delete**

Run: `git check-ignore .venv-embedding && git status --porcelain -- .venv-embedding`
Expected: `check-ignore` prints `.venv-embedding` (confirms it's gitignored) and `status --porcelain` prints
nothing (confirms nothing tracked lives under it).

- [ ] **Step 2: Delete the old venv**

```bash
rm -rf .venv-embedding/
```

- [ ] **Step 3: Write `pyproject.toml`**

```toml
[project]
name = "product-taxonomy-extraction"
version = "0.1.0"
requires-python = ">=3.9"
dependencies = [
    "google-auth>=2.0.0",
    "google-auth-oauthlib>=0.5.0",
    "google-api-python-client>=2.0.0",
    "google-cloud-bigquery>=3.11",
    "pandas>=2.0",
    "pyarrow>=14.0",
    "db-dtypes>=1.2",
    "xgboost>=2.0",
    "scikit-learn>=1.4",
    "sentence-transformers>=2.7",
]

[[tool.uv.index]]
name = "pytorch-cpu"
url = "https://download.pytorch.org/whl/cpu"
explicit = true

[tool.uv.sources]
torch = [{ index = "pytorch-cpu" }]
```

- [ ] **Step 4: Sync the environment**

Run: `uv sync`
Expected: creates `.venv/` and `uv.lock` at repo root, exits 0.

- [ ] **Step 5: Verify the key dependencies import cleanly**

Run: `uv run python3 -c "import google.cloud.bigquery, pandas, xgboost, sklearn, sentence_transformers; print('ok')"`
Expected: prints `ok`.

- [ ] **Step 6: Remove the now-superseded requirements files**

```bash
rm -f script/embedding_worker_requirements.txt requirements.txt
```

- [ ] **Step 7: Update `README.md`'s file-tree listing**

Find the line `└── requirements.txt` at `README.md:85` and replace it with:

```
├── pyproject.toml
└── uv.lock
```

(Adjust the tree-branch character on the line above it from `└──` to `├──` if `requirements.txt` was previously
the last entry — check the surrounding lines and keep the tree glyphs consistent.)

- [ ] **Step 8: Commit**

```bash
git add pyproject.toml uv.lock README.md
git rm -f script/embedding_worker_requirements.txt requirements.txt
git commit -m "Migrate Python dependency management to uv, rebuild .venv"
```

---

### Task 2: Move NIQ-coupled scripts into `script/niq/`, fix internal path references

**Files:**
- Move: `script/headless_taxonomy.sh`, `script/targeted_qa_fix.sh`, `script/custom_headless_taxonomy.sh`,
  `script/custom_targeted_qa_fix.sh`, `script/qa_report.sh`, `script/qa_coverage_report.sh`,
  `script/queue_worker.sh`, `script/queue_ctl.sh`, `script/embedding_worker.py`, `script/taxonomy_match_encoding.py`,
  `script/train_taxonomy_matcher.py`, `script/compute_training_features.py` → same filenames under `script/niq/`
- Modify: `script/niq/targeted_qa_fix.sh`, `script/niq/custom_targeted_qa_fix.sh`, `script/niq/queue_worker.sh`,
  `script/niq/queue_ctl.sh`, `docs/headless-runbook.md`

**Interfaces:**
- Consumes: nothing new.
- Produces: `script/niq/` populated with the full NIQ cluster. Task 4/5/6/7/8/9/10 create new files directly
  inside `script/niq/` — this task must land first.

- [ ] **Step 1: Create the directory and move the files**

```bash
mkdir -p script/niq
git mv script/headless_taxonomy.sh script/niq/headless_taxonomy.sh
git mv script/targeted_qa_fix.sh script/niq/targeted_qa_fix.sh
git mv script/custom_headless_taxonomy.sh script/niq/custom_headless_taxonomy.sh
git mv script/custom_targeted_qa_fix.sh script/niq/custom_targeted_qa_fix.sh
git mv script/qa_report.sh script/niq/qa_report.sh
git mv script/qa_coverage_report.sh script/niq/qa_coverage_report.sh
git mv script/queue_worker.sh script/niq/queue_worker.sh
git mv script/queue_ctl.sh script/niq/queue_ctl.sh
git mv script/embedding_worker.py script/niq/embedding_worker.py
git mv script/taxonomy_match_encoding.py script/niq/taxonomy_match_encoding.py
git mv script/train_taxonomy_matcher.py script/niq/train_taxonomy_matcher.py
git mv script/compute_training_features.py script/niq/compute_training_features.py
```

- [ ] **Step 2: Fix `script/niq/targeted_qa_fix.sh`'s internal path references**

Three occurrences of `./script/qa_report.sh` (lines referencing the pre-fix gate report, the post-fix
`GATE_AND_REFRESH` re-check, and the case-branch echo) and one `./script/qa_coverage_report.sh` (the `EXIT`
trap) — replace every one with the `niq/`-prefixed path:

```bash
sed -i 's#\./script/qa_report\.sh#./script/niq/qa_report.sh#g; s#\./script/qa_coverage_report\.sh#./script/niq/qa_coverage_report.sh#g' script/niq/targeted_qa_fix.sh
```

- [ ] **Step 3: Fix `script/niq/custom_targeted_qa_fix.sh`'s internal path references**

Same substitution — this file has the same `./script/qa_report.sh` / `./script/qa_coverage_report.sh` pattern:

```bash
sed -i 's#\./script/qa_report\.sh#./script/niq/qa_report.sh#g; s#\./script/qa_coverage_report\.sh#./script/niq/qa_coverage_report.sh#g' script/niq/custom_targeted_qa_fix.sh
```

- [ ] **Step 4: Fix `script/niq/queue_worker.sh`'s default script paths and `load_env.sh` source**

Two default env-var fallback paths on the line invoking the dispatched script, and one `source` line that
resolves relative to the script's own directory (which moved, but `load_env.sh` did not):

```bash
sed -i \
  -e 's#HEADLESS_TAXONOMY_SCRIPT:-./script/headless_taxonomy\.sh#HEADLESS_TAXONOMY_SCRIPT:-./script/niq/headless_taxonomy.sh#' \
  -e 's#TARGETED_QA_FIX_SCRIPT:-./script/targeted_qa_fix\.sh#TARGETED_QA_FIX_SCRIPT:-./script/niq/targeted_qa_fix.sh#' \
  -e 's#source "\$(dirname "\$0")/load_env\.sh"#source "$(dirname "$0")/../load_env.sh"#' \
  script/niq/queue_worker.sh
```

- [ ] **Step 5: Fix `script/niq/queue_ctl.sh`'s `load_env.sh` source**

Same directory-relative source fix (this file doesn't reference `qa_report.sh`/`qa_coverage_report.sh` or the
headless/targeted scripts directly, only `load_env.sh`):

```bash
sed -i 's#source "\$(dirname "\$0")/load_env\.sh"#source "$(dirname "$0")/../load_env.sh"#' script/niq/queue_ctl.sh
```

- [ ] **Step 6: Verify every moved shell script still parses**

Run: `for f in script/niq/*.sh; do bash -n "$f" || echo "SYNTAX ERROR: $f"; done`
Expected: no `SYNTAX ERROR` lines printed.

- [ ] **Step 7: Verify no stale unprefixed references remain in the moved files**

Run: `grep -rn '\./script/qa_report\.sh\|\./script/qa_coverage_report\.sh\|\./script/headless_taxonomy\.sh\|\./script/targeted_qa_fix\.sh' script/niq/`
Expected: no output (every match inside `script/niq/` should already carry the `niq/` prefix from Steps 2-4).

- [ ] **Step 8: Update `docs/headless-runbook.md`'s script references**

Replace every bare `script/headless_taxonomy.sh`, `script/targeted_qa_fix.sh`, `script/queue_worker.sh`,
`script/queue_ctl.sh` reference with the `niq/`-prefixed path (`script/load_env.sh` references stay unchanged —
that file did not move):

```bash
sed -i \
  -e 's#`script/headless_taxonomy\.sh`#`script/niq/headless_taxonomy.sh`#g' \
  -e 's#`script/targeted_qa_fix\.sh`#`script/niq/targeted_qa_fix.sh`#g' \
  -e 's#\./script/headless_taxonomy\.sh#./script/niq/headless_taxonomy.sh#g' \
  -e 's#^script/queue_ctl\.sh#script/niq/queue_ctl.sh#g' \
  -e 's#^script/queue_worker\.sh#script/niq/queue_worker.sh#g' \
  -e 's#`script/queue_worker\.sh`#`script/niq/queue_worker.sh`#g' \
  docs/headless-runbook.md
grep -n 'script/headless_taxonomy\|script/targeted_qa_fix\|script/queue_worker\|script/queue_ctl' docs/headless-runbook.md
```

Expected: every line in the `grep` output already shows the `script/niq/` prefix — manually fix any remaining
bare occurrence the `sed` patterns above missed (check line-start vs. inline vs. backtick-wrapped forms
individually since the file mixes all three).

- [ ] **Step 9: Commit**

```bash
git add script/niq docs/headless-runbook.md
git commit -m "Move NIQ-coupled scripts into script/niq/, fix internal path references"
```

---

### Task 3: Move test files into `tests/niq/`, `tests/non_niq/`, `tests/`

**Files:**
- Move: `script/test_headless_taxonomy.sh`, `script/test_targeted_qa_fix.sh`, `script/test_custom_headless_taxonomy.sh`,
  `script/test_custom_targeted_qa_fix.sh`, `script/test_queue_worker.sh`, `script/test_queue_ctl.sh` → `tests/niq/`
- Move: `script/non_niq/test_non_niq_sheet.py`, `script/non_niq/test_non_niq_embed.py`,
  `script/non_niq/test_non_niq_qa.sh`, `script/non_niq/test_non_niq_queue_worker.sh` → `tests/non_niq/`
- Move: `script/test_load_env.sh`, `script/test_migrate_category_docs_to_bq_2026_07_29.py` → `tests/`
- Modify: every moved file's source/import path

**Interfaces:**
- Consumes: `script/niq/*` from Task 2, `script/non_niq/*` (unchanged), `script/load_env.sh`/
  `script/migrate_category_docs_to_bq_2026_07_29.py` (unchanged, top-level).
- Produces: a runnable `tests/` tree. No later task depends on this one's internals, only on it not breaking
  anything — this is the last structural-move task before new code is written.

- [ ] **Step 1: Create the directories and move the files**

```bash
mkdir -p tests/niq tests/non_niq
git mv script/test_headless_taxonomy.sh tests/niq/test_headless_taxonomy.sh
git mv script/test_targeted_qa_fix.sh tests/niq/test_targeted_qa_fix.sh
git mv script/test_custom_headless_taxonomy.sh tests/niq/test_custom_headless_taxonomy.sh
git mv script/test_custom_targeted_qa_fix.sh tests/niq/test_custom_targeted_qa_fix.sh
git mv script/test_queue_worker.sh tests/niq/test_queue_worker.sh
git mv script/test_queue_ctl.sh tests/niq/test_queue_ctl.sh
git mv script/non_niq/test_non_niq_sheet.py tests/non_niq/test_non_niq_sheet.py
git mv script/non_niq/test_non_niq_embed.py tests/non_niq/test_non_niq_embed.py
git mv script/non_niq/test_non_niq_qa.sh tests/non_niq/test_non_niq_qa.sh
git mv script/non_niq/test_non_niq_queue_worker.sh tests/non_niq/test_non_niq_queue_worker.sh
git mv script/test_load_env.sh tests/test_load_env.sh
git mv script/test_migrate_category_docs_to_bq_2026_07_29.py tests/test_migrate_category_docs_to_bq_2026_07_29.py
```

- [ ] **Step 2: Fix the NIQ shell tests' `cd`/`source` lines**

Every file in `tests/niq/*.sh` currently starts with `cd "$(dirname "$0")/.."` (one level up, back to
`script/`) then `source script/<name>.sh`. From `tests/niq/`, the repo root is now two levels up, and the
sourced file lives under `script/niq/`:

```bash
for f in tests/niq/test_headless_taxonomy.sh tests/niq/test_targeted_qa_fix.sh \
         tests/niq/test_custom_headless_taxonomy.sh tests/niq/test_custom_targeted_qa_fix.sh \
         tests/niq/test_queue_worker.sh tests/niq/test_queue_ctl.sh; do
  sed -i \
    -e 's#cd "\$(dirname "\$0")/\.\."#cd "$(dirname "$0")/../.."#' \
    -e 's#source script/#source script/niq/#' \
    "$f"
done
```

- [ ] **Step 3: Fix the non_niq tests' import/source paths**

`tests/non_niq/test_non_niq_embed.py` and `test_non_niq_sheet.py` use
`sys.path.insert(0, str(Path(__file__).parent))` then a bare `from non_niq_embed import ...` — since the module
now lives in `script/non_niq/`, not next to the test, point `sys.path` there instead:

```bash
sed -i "s#sys.path.insert(0, str(Path(__file__).parent))#sys.path.insert(0, str(Path(__file__).parent.parent.parent / \"script\" / \"non_niq\"))#" \
  tests/non_niq/test_non_niq_sheet.py tests/non_niq/test_non_niq_embed.py
```

Check `tests/non_niq/test_non_niq_qa.sh` and `test_non_niq_queue_worker.sh` for the same `cd`/`source` pattern
used by the NIQ shell tests and apply the equivalent fix if present:

```bash
grep -n 'cd "\$(dirname\|source script/' tests/non_niq/test_non_niq_qa.sh tests/non_niq/test_non_niq_queue_worker.sh
```

If found, apply: `cd "$(dirname "$0")/.."` → `cd "$(dirname "$0")/../.."`, and
`source script/non_niq/<name>` stays as-is if it already carried the `non_niq/` prefix (it should, since these
tests always lived one level below the sourced files), or gets that prefix added if it was a bare
`source <name>.sh` relying on being co-located.

- [ ] **Step 4: Fix `tests/test_load_env.sh` and `tests/test_migrate_category_docs_to_bq_2026_07_29.py`**

These moved from `script/` (one level below root) to `tests/` (also one level below root) — same depth, so
check whether their `cd`/`source`/`sys.path` lines need any change at all:

```bash
grep -n 'cd "\$(dirname\|source script/\|sys.path' tests/test_load_env.sh tests/test_migrate_category_docs_to_bq_2026_07_29.py
```

If they use `cd "$(dirname "$0")/.."` + `source script/load_env.sh` (or equivalent), no change is needed — the
relative depth from `tests/` to repo root is identical to `script/`'s. Only fix if the grep reveals something
depth-sensitive (e.g. a `Path(__file__).parent` used to locate a same-directory module that no longer applies).

- [ ] **Step 5: Run every moved test and confirm it still passes**

```bash
bash tests/niq/test_headless_taxonomy.sh
bash tests/niq/test_targeted_qa_fix.sh
bash tests/niq/test_custom_headless_taxonomy.sh
bash tests/niq/test_custom_targeted_qa_fix.sh
bash tests/niq/test_queue_worker.sh
bash tests/niq/test_queue_ctl.sh
bash tests/non_niq/test_non_niq_qa.sh
bash tests/non_niq/test_non_niq_queue_worker.sh
uv run python3 tests/non_niq/test_non_niq_sheet.py
uv run python3 tests/non_niq/test_non_niq_embed.py
bash tests/test_load_env.sh
uv run python3 tests/test_migrate_category_docs_to_bq_2026_07_29.py
```

Expected: every invocation prints its own `ALL TESTS PASSED` (or equivalent pass marker) and exits 0. Fix any
remaining path issue a given test surfaces before moving on.

- [ ] **Step 6: Commit**

```bash
git add tests script/niq script/non_niq
git commit -m "Move all test files into tests/, fix source/import paths after the niq/ reorg"
```

---

### Task 4: Write and dry-run `sql/queries/qa_v2_tier1_sweep.sql`

**Files:**
- Create: `sql/queries/qa_v2_tier1_sweep.sql`

**Interfaces:**
- Consumes: nothing (first SQL file for V2).
- Produces: a query taking one parameter, `@taxonomy_ids ARRAY<STRING>`, returning one row per taxonomy_id with
  columns `taxonomy_id, canonical_name, brand, stub_leak, duplicate_brand, wrong_field_order,
  brand_casing_mismatch, excess_content, canonical_field_mismatch, null_size, garbage_brand, count_as_size,
  provenance_leak` (all boolean except the first three). Task 6's `TIER1_FLAG_COLUMNS` constant and
  `build_tier1_sweep_query` must name exactly these ten flag columns, in this order.

- [ ] **Step 1: Write the query**

Ported verbatim from `script/niq/targeted_qa_fix.sh`'s STEP 2 Tier-1 sweep (same ten flags, same regex bodies),
re-scoped from `WHERE m.master_table = @table AND (...)` to `WHERE pt.taxonomy_id IN UNNEST(@taxonomy_ids)` —
V2's caller already knows exactly which rows are in scope from the worklist build, so no `master_table`/
`review_confidence` filter is needed here.

```sql
-- sql/queries/qa_v2_tier1_sweep.sql
-- Tier-1 mechanical defect sweep, scoped to an explicit taxonomy_id list (the current worklist batch) rather
-- than a whole master_table -- see docs/superpowers/specs/2026-08-10-targeted-qa-fix-v2-design.md.
-- Ported verbatim from script/niq/targeted_qa_fix.sh's STEP 2 (same ten flags, same regex bodies).
-- Params: @taxonomy_ids ARRAY<STRING>

SELECT pt.taxonomy_id, pt.canonical_name, bd.canonical_name AS brand,
  REGEXP_CONTAINS(LOWER(pt.canonical_name), r'\b(undefined|null|n/a|tbd|all variants?|all sizes?|multiple variants?|multiple sizes?)\b') AS stub_leak,
  (LENGTH(pt.canonical_name) - LENGTH(REPLACE(pt.canonical_name, bd.canonical_name, ''))) / GREATEST(LENGTH(bd.canonical_name),1) >= 2 AS duplicate_brand,
  NOT STARTS_WITH(LOWER(TRIM(pt.canonical_name)), LOWER(bd.canonical_name)) AS wrong_field_order,
  (STARTS_WITH(LOWER(pt.canonical_name), LOWER(bd.canonical_name)) AND NOT STARTS_WITH(pt.canonical_name, bd.canonical_name)) AS brand_casing_mismatch,
  (ARRAY_LENGTH(REGEXP_EXTRACT_ALL(pt.canonical_name, r'\d+\s*(?:ml|g|kg|l|L)\b')) > 1 OR ARRAY_LENGTH(REGEXP_EXTRACT_ALL(pt.canonical_name, r'x\d+\b')) > 1) AS excess_content,
  (
    (SELECT LOGICAL_OR(LOWER(pt.canonical_name) NOT LIKE CONCAT('%', w, '%'))
     FROM UNNEST(SPLIT(LOWER(pt.product_line), ' ')) w WHERE w != '')
    OR (pt.sub_line IS NOT NULL AND (SELECT LOGICAL_OR(LOWER(pt.canonical_name) NOT LIKE CONCAT('%', w, '%'))
        FROM UNNEST(SPLIT(LOWER(pt.sub_line), ' ')) w WHERE w != ''))
    OR (pt.variant IS NOT NULL AND (SELECT LOGICAL_OR(LOWER(pt.canonical_name) NOT LIKE CONCAT('%', w, '%'))
        FROM UNNEST(SPLIT(LOWER(pt.variant), ' ')) w WHERE w != ''))
    OR (pt.size IS NOT NULL AND NOT LOWER(pt.canonical_name) LIKE CONCAT('%', LOWER(pt.size), '%'))
    OR (pt.pack_count > 1 AND pt.is_bundle IS NOT TRUE AND NOT LOWER(pt.canonical_name) LIKE CONCAT('%x', CAST(pt.pack_count AS STRING), '%'))
  ) AND NOT REGEXP_CONTAINS(LOWER(pt.canonical_name), r'\(all\s+(variants?|sizes?)\b|\bmultiple\s+(variants?|sizes?)\b') AS canonical_field_mismatch,
  (pt.size IS NULL AND pt.is_multi_size IS NOT TRUE) AS null_size,
  NOT REGEXP_CONTAINS(bd.canonical_name, r'[\p{L}]') AS garbage_brand,
  (pt.size IS NOT NULL AND REGEXP_CONTAINS(LOWER(pt.size), r'\b(pcs?|capsules?|sachets?|packets?|tablets?|pieces?|units?|ea|count)\b') AND NOT REGEXP_CONTAINS(LOWER(pt.size), r'\d+(\.\d+)?\s*(ml|g|kg|l|oz|lb)\b')) AS count_as_size,
  (REGEXP_CONTAINS(pt.canonical_name, r'(?i)\b(ready stock|100%\s*original|direct from|fast shipping|local seller|\w+\s+seller|latest packaging|similar to)\b') OR REGEXP_CONTAINS(pt.canonical_name, r'[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}]')) AS provenance_leak
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy` pt
JOIN `sincere-hearth-273704.magpie_reference.brand_dict` bd ON bd.brand_id = pt.brand_id
WHERE pt.taxonomy_id IN UNNEST(@taxonomy_ids)
GROUP BY 1,2,3,pt.product_line,pt.sub_line,pt.variant,pt.size,pt.pack_count,pt.is_multi_size,pt.is_bundle
```

- [ ] **Step 2: Dry-run with a placeholder taxonomy_id**

```bash
bq query --dry_run --use_legacy_sql=false --project_id=sincere-hearth-273704 \
  --parameter='taxonomy_ids:ARRAY<STRING>:["SKU-000001"]' \
  < sql/queries/qa_v2_tier1_sweep.sql
```

Expected: "Query successfully validated." (not a syntax error).

- [ ] **Step 3: Commit**

```bash
git add sql/queries/qa_v2_tier1_sweep.sql
git commit -m "Add Tier-1 mechanical sweep query for QA V2, scoped by explicit taxonomy_id list"
```

---

### Task 5: Write and dry-run the two candidate-retrieval queries

**Files:**
- Create: `sql/queries/qa_v2_taxonomy_candidates.sql`
- Create: `sql/queries/qa_v2_brand_candidates.sql`

**Interfaces:**
- Consumes: nothing new.
- Produces: `qa_v2_taxonomy_candidates.sql` takes `@taxonomy_ids ARRAY<STRING>` and `@n INT64`, returns
  `worklist_taxonomy_id, candidate_taxonomy_id, candidate_canonical_name, normalized_distance` — up to `@n` rows
  per `worklist_taxonomy_id`. `qa_v2_brand_candidates.sql` takes `@taxonomy_ids ARRAY<STRING>` and `@n INT64`,
  returns `worklist_taxonomy_id, candidate_brand_id, candidate_canonical_name, normalized_distance` — up to
  `@n` rows per `worklist_taxonomy_id`, each with `normalized_distance < 0.4`. Task 6's
  `build_taxonomy_candidates_query`/`build_brand_candidates_query` load these files verbatim (see Task 6 Step
  1's `_load_sql` helper) and bind these exact parameter names.

- [ ] **Step 1: Write `qa_v2_taxonomy_candidates.sql`**

```sql
-- sql/queries/qa_v2_taxonomy_candidates.sql
-- For each worklist taxonomy_id, the top @n other product_taxonomy rows sharing the same brand_id, restricted
-- to review_confidence='confident', ranked by normalized edit distance on canonical_name. Reference/format
-- context for the QA judge only -- never a basis for an autonomous decision. See
-- docs/superpowers/specs/2026-08-10-targeted-qa-fix-v2-design.md.
-- Params: @taxonomy_ids ARRAY<STRING>, @n INT64

SELECT worklist_taxonomy_id, candidate_taxonomy_id, candidate_canonical_name, normalized_distance
FROM (
  SELECT
    base.taxonomy_id AS worklist_taxonomy_id,
    cand.taxonomy_id AS candidate_taxonomy_id,
    cand.canonical_name AS candidate_canonical_name,
    SAFE_DIVIDE(
      EDIT_DISTANCE(base.canonical_name, cand.canonical_name),
      GREATEST(LENGTH(base.canonical_name), LENGTH(cand.canonical_name))
    ) AS normalized_distance
  FROM `sincere-hearth-273704.magpie_reference.product_taxonomy` base
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` cand
    ON cand.brand_id = base.brand_id
    AND cand.taxonomy_id != base.taxonomy_id
    AND JSON_VALUE(cand._meta, '$.review_confidence') = 'confident'
  WHERE base.taxonomy_id IN UNNEST(@taxonomy_ids)
)
QUALIFY ROW_NUMBER() OVER (PARTITION BY worklist_taxonomy_id ORDER BY normalized_distance ASC) <= @n
```

- [ ] **Step 2: Write `qa_v2_brand_candidates.sql`**

```sql
-- sql/queries/qa_v2_brand_candidates.sql
-- For each worklist taxonomy_id, the top @n brand_dict entries (excluding its own brand_id) closest by
-- normalized edit distance to its own resolved brand name, capped at normalized_distance < 0.4. Surfaces
-- brand_id misattribution / brand-dict aliasing candidates for the QA judge -- reference only. See
-- docs/superpowers/specs/2026-08-10-targeted-qa-fix-v2-design.md.
-- Params: @taxonomy_ids ARRAY<STRING>, @n INT64

SELECT worklist_taxonomy_id, candidate_brand_id, candidate_canonical_name, normalized_distance
FROM (
  SELECT
    base.taxonomy_id AS worklist_taxonomy_id,
    cand.brand_id AS candidate_brand_id,
    cand.canonical_name AS candidate_canonical_name,
    SAFE_DIVIDE(
      EDIT_DISTANCE(base_brand.canonical_name, cand.canonical_name),
      GREATEST(LENGTH(base_brand.canonical_name), LENGTH(cand.canonical_name))
    ) AS normalized_distance
  FROM `sincere-hearth-273704.magpie_reference.product_taxonomy` base
  JOIN `sincere-hearth-273704.magpie_reference.brand_dict` base_brand ON base_brand.brand_id = base.brand_id
  JOIN `sincere-hearth-273704.magpie_reference.brand_dict` cand ON cand.brand_id != base.brand_id
  WHERE base.taxonomy_id IN UNNEST(@taxonomy_ids)
)
WHERE normalized_distance < 0.4
QUALIFY ROW_NUMBER() OVER (PARTITION BY worklist_taxonomy_id ORDER BY normalized_distance ASC) <= @n
```

- [ ] **Step 3: Dry-run both**

```bash
bq query --dry_run --use_legacy_sql=false --project_id=sincere-hearth-273704 \
  --parameter='taxonomy_ids:ARRAY<STRING>:["SKU-000001"]' \
  --parameter=n:INT64:5 \
  < sql/queries/qa_v2_taxonomy_candidates.sql

bq query --dry_run --use_legacy_sql=false --project_id=sincere-hearth-273704 \
  --parameter='taxonomy_ids:ARRAY<STRING>:["SKU-000001"]' \
  --parameter=n:INT64:3 \
  < sql/queries/qa_v2_brand_candidates.sql
```

Expected: "Query successfully validated." for both. If `EDIT_DISTANCE` is rejected as an unknown function, stop
and record the finding — the design spec's "Open verification items" flagged this as unconfirmed; a rejection
here means falling back to a different SQL similarity function (e.g. token-overlap via `SPLIT`/`ARRAY`
intersection) is a genuine spec change, not something to route around silently in this task.

- [ ] **Step 4: Commit**

```bash
git add sql/queries/qa_v2_taxonomy_candidates.sql sql/queries/qa_v2_brand_candidates.sql
git commit -m "Add taxonomy and brand candidate-retrieval queries for QA V2"
```

---

### Task 6: `script/niq/qa_v2_worklist.py` — pure query-builder and data-assembly functions

**Files:**
- Create: `script/niq/qa_v2_worklist.py`
- Test: `tests/niq/test_qa_v2_worklist.py`

**Interfaces:**
- Consumes: `sql/queries/qa_v2_tier1_sweep.sql`, `sql/queries/qa_v2_taxonomy_candidates.sql`,
  `sql/queries/qa_v2_brand_candidates.sql` (Task 4/5, loaded from disk).
- Produces (used by Task 7): `PROJECT` (str constant), `TIER1_FLAG_COLUMNS` (list of 10 strings, matching Task
  4's column order), `_validate_table(table) -> None` (raises `ValueError` on unsafe input),
  `build_worklist_query(table, block_size) -> (sql: str, params: list[bigquery.ScalarQueryParameter])`,
  `build_pending_recheck_query(table) -> (sql, params)`,
  `build_tier1_sweep_query(taxonomy_ids: list[str]) -> (sql, params)`,
  `build_taxonomy_candidates_query(taxonomy_ids, n=5) -> (sql, params)`,
  `build_brand_candidates_query(taxonomy_ids, n=3) -> (sql, params)`,
  `build_sample_sku_names_query(table, taxonomy_ids) -> (sql, params)`,
  `build_promote_query(taxonomy_ids) -> (sql, params)`,
  `clean_taxonomy_ids(flag_rows: list[dict]) -> list[str]`,
  `assemble_worklist_json(rows, flags_by_id, tax_cands_by_id, brand_cands_by_id, samples_by_id) -> list[dict]`.

- [ ] **Step 1: Write the failing test for `_validate_table`, `build_worklist_query`, and `clean_taxonomy_ids`**

```python
# tests/niq/test_qa_v2_worklist.py
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "script" / "niq"))
from qa_v2_worklist import (
    _validate_table, build_worklist_query, build_pending_recheck_query, build_tier1_sweep_query,
    build_taxonomy_candidates_query, build_brand_candidates_query, build_sample_sku_names_query,
    build_promote_query, clean_taxonomy_ids, assemble_worklist_json, TIER1_FLAG_COLUMNS,
)

def test_validate_table_accepts_safe_name():
    _validate_table("shopee_th_toothpaste")  # must not raise

def test_validate_table_rejects_unsafe_name():
    try:
        _validate_table("shopee_th_toothpaste`; DROP TABLE x;--")
        assert False, "expected ValueError"
    except ValueError:
        pass

def test_build_worklist_query_orders_never_reviewed_before_unconfident():
    sql, params = build_worklist_query("shopee_th_toothpaste", 200)
    assert "tier_rank ASC, gmv DESC" in sql
    assert "pt._meta IS NULL" in sql
    assert "review_confidence" in sql
    param_names = {p.name for p in params}
    assert param_names == {"table", "block_size"}

if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print(f"PASS: {name}")
    print("ALL TESTS PASSED")
```

- [ ] **Step 2: Run it to confirm it fails on import**

Run: `uv run python3 tests/niq/test_qa_v2_worklist.py`
Expected: `ModuleNotFoundError: No module named 'qa_v2_worklist'` (the file doesn't exist yet).

- [ ] **Step 3: Write `script/niq/qa_v2_worklist.py`'s pure functions**

```python
#!/usr/bin/env python3
"""Builds the candidate-enriched, strict-tier GMV-sorted QA worklist for targeted_qa_fix_v2.sh -- all pure
SQL/Python, no LLM calls. See docs/superpowers/specs/2026-08-10-targeted-qa-fix-v2-design.md."""
import json
import re
import sys
from pathlib import Path

from google.cloud import bigquery

PROJECT = "sincere-hearth-273704"
_SAFE_TABLE_NAME = re.compile(r"^[a-zA-Z0-9_]+$")
_SQL_DIR = Path(__file__).parent.parent.parent / "sql" / "queries"

TIER1_FLAG_COLUMNS = [
    "stub_leak", "duplicate_brand", "wrong_field_order", "brand_casing_mismatch", "excess_content",
    "canonical_field_mismatch", "null_size", "garbage_brand", "count_as_size", "provenance_leak",
]


def _validate_table(table):
    if not _SAFE_TABLE_NAME.match(table):
        raise ValueError(f"Unsafe table value for table-name interpolation: {table!r}")


def _load_sql(filename):
    return (_SQL_DIR / filename).read_text()


def build_worklist_query(table, block_size):
    _validate_table(table)
    sql = f"""
    WITH never_reviewed AS (
      SELECT pt.taxonomy_id, pt.canonical_name, 0 AS tier_rank, 'unlabelled' AS tier,
             CAST(SUM(mast.gmv_monthly) AS INT64) AS gmv
      FROM `{PROJECT}.magpie_reference.product_taxonomy` pt
      JOIN `{PROJECT}.magpie_reference.product_taxonomy_map` m ON m.taxonomy_id = pt.taxonomy_id
      JOIN `{PROJECT}.master_clean_niq.{table}` mast ON mast.product_id = m.product_id
      WHERE m.master_table = @table AND pt._meta IS NULL
      GROUP BY 1, 2
    ),
    unconfident AS (
      SELECT pt.taxonomy_id, pt.canonical_name, 1 AS tier_rank, 'unconfident' AS tier,
             CAST(SUM(mast.gmv_monthly) AS INT64) AS gmv
      FROM `{PROJECT}.magpie_reference.product_taxonomy` pt
      JOIN `{PROJECT}.magpie_reference.product_taxonomy_map` m ON m.taxonomy_id = pt.taxonomy_id
      JOIN `{PROJECT}.master_clean_niq.{table}` mast ON mast.product_id = m.product_id
      WHERE m.master_table = @table AND pt._meta IS NOT NULL
        AND IFNULL(JSON_VALUE(pt._meta, '$.review_confidence'), 'unreviewed') != 'confident'
      GROUP BY 1, 2
    )
    SELECT taxonomy_id, canonical_name, tier, gmv
    FROM (SELECT * FROM never_reviewed UNION ALL SELECT * FROM unconfident)
    ORDER BY tier_rank ASC, gmv DESC
    LIMIT @block_size
    """
    params = [
        bigquery.ScalarQueryParameter("table", "STRING", table),
        bigquery.ScalarQueryParameter("block_size", "INT64", block_size),
    ]
    return sql, params


def build_pending_recheck_query(table):
    _validate_table(table)
    sql = f"""
    SELECT DISTINCT pt.taxonomy_id
    FROM `{PROJECT}.magpie_reference.product_taxonomy` pt
    JOIN `{PROJECT}.magpie_reference.product_taxonomy_map` m ON m.taxonomy_id = pt.taxonomy_id
    WHERE m.master_table = @table
      AND pt._meta IS NOT NULL
      AND JSON_VALUE(pt._meta, '$.review_confidence') IS NULL
    """
    params = [bigquery.ScalarQueryParameter("table", "STRING", table)]
    return sql, params


def build_tier1_sweep_query(taxonomy_ids):
    sql = _load_sql("qa_v2_tier1_sweep.sql")
    params = [bigquery.ArrayQueryParameter("taxonomy_ids", "STRING", taxonomy_ids)]
    return sql, params


def build_taxonomy_candidates_query(taxonomy_ids, n=5):
    sql = _load_sql("qa_v2_taxonomy_candidates.sql")
    params = [
        bigquery.ArrayQueryParameter("taxonomy_ids", "STRING", taxonomy_ids),
        bigquery.ScalarQueryParameter("n", "INT64", n),
    ]
    return sql, params


def build_brand_candidates_query(taxonomy_ids, n=3):
    sql = _load_sql("qa_v2_brand_candidates.sql")
    params = [
        bigquery.ArrayQueryParameter("taxonomy_ids", "STRING", taxonomy_ids),
        bigquery.ScalarQueryParameter("n", "INT64", n),
    ]
    return sql, params


def build_sample_sku_names_query(table, taxonomy_ids):
    _validate_table(table)
    sql = f"""
    SELECT m.taxonomy_id, ARRAY_AGG(DISTINCT s.sku_name IGNORE NULLS LIMIT 3) AS sample_sku_names
    FROM `{PROJECT}.magpie_reference.product_taxonomy_map` m
    JOIN `{PROJECT}.master_clean_niq.{table}` s ON s.product_id = m.product_id
    WHERE m.master_table = @table AND m.taxonomy_id IN UNNEST(@taxonomy_ids)
    GROUP BY 1
    """
    params = [
        bigquery.ScalarQueryParameter("table", "STRING", table),
        bigquery.ArrayQueryParameter("taxonomy_ids", "STRING", taxonomy_ids),
    ]
    return sql, params


def build_promote_query(taxonomy_ids):
    sql = f"""
    UPDATE `{PROJECT}.magpie_reference.product_taxonomy`
    SET _meta = TO_JSON_STRING(STRUCT(
      true AS is_reviewed,
      CURRENT_TIMESTAMP() AS last_reviewed_at,
      'confident' AS review_confidence,
      'correct' AS last_verdict
    ))
    WHERE taxonomy_id IN UNNEST(@taxonomy_ids)
    """
    params = [bigquery.ArrayQueryParameter("taxonomy_ids", "STRING", taxonomy_ids)]
    return sql, params


def clean_taxonomy_ids(flag_rows):
    """flag_rows: list of dict with 'taxonomy_id' + TIER1_FLAG_COLUMNS keys. Returns ids where every flag is
    False -- these are the fast-lane promotion candidates (STEP 1C's judgment-free bulk-promote case)."""
    return [r["taxonomy_id"] for r in flag_rows if not any(r[f] for f in TIER1_FLAG_COLUMNS)]


def assemble_worklist_json(rows, flags_by_id, tax_cands_by_id, brand_cands_by_id, samples_by_id):
    worklist = []
    for row in rows:
        tid = row["taxonomy_id"]
        worklist.append({
            "taxonomy_id": tid,
            "canonical_name": row["canonical_name"],
            "tier": row["tier"],
            "gmv": row["gmv"],
            "tier1_flags": flags_by_id.get(tid, {}),
            "taxonomy_candidates": tax_cands_by_id.get(tid, []),
            "brand_candidates": brand_cands_by_id.get(tid, []),
            "sample_sku_names": samples_by_id.get(tid, []),
        })
    return worklist
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `uv run python3 tests/niq/test_qa_v2_worklist.py`
Expected: `PASS: test_validate_table_accepts_safe_name`, `PASS: test_validate_table_rejects_unsafe_name`,
`PASS: test_build_worklist_query_orders_never_reviewed_before_unconfident`, `ALL TESTS PASSED`.

- [ ] **Step 5: Add tests for the remaining query builders and `clean_taxonomy_ids`/`assemble_worklist_json`**

Append to `tests/niq/test_qa_v2_worklist.py` (before the `if __name__ == "__main__":` block):

```python
def test_build_pending_recheck_query_scopes_to_pending_bucket():
    sql, params = build_pending_recheck_query("shopee_th_toothpaste")
    assert "review_confidence') IS NULL" in sql
    assert "_meta IS NOT NULL" in sql
    assert {p.name for p in params} == {"table"}

def test_build_tier1_sweep_query_binds_taxonomy_ids_array():
    sql, params = build_tier1_sweep_query(["SKU-000001", "SKU-000002"])
    assert "UNNEST(@taxonomy_ids)" in sql
    assert len(params) == 1
    assert params[0].name == "taxonomy_ids"
    assert params[0].values == ["SKU-000001", "SKU-000002"]

def test_build_taxonomy_candidates_query_defaults_n_to_5():
    sql, params = build_taxonomy_candidates_query(["SKU-000001"])
    n_param = next(p for p in params if p.name == "n")
    assert n_param.value == 5

def test_build_brand_candidates_query_defaults_n_to_3():
    sql, params = build_brand_candidates_query(["SKU-000001"])
    n_param = next(p for p in params if p.name == "n")
    assert n_param.value == 3

def test_build_sample_sku_names_query_rejects_unsafe_table():
    try:
        build_sample_sku_names_query("bad`table", ["SKU-000001"])
        assert False, "expected ValueError"
    except ValueError:
        pass

def test_build_promote_query_sets_confident():
    sql, params = build_promote_query(["SKU-000001"])
    assert "'confident' AS review_confidence" in sql
    assert params[0].values == ["SKU-000001"]

def test_clean_taxonomy_ids_excludes_any_flagged_row():
    rows = [
        {"taxonomy_id": "SKU-1", **{f: False for f in TIER1_FLAG_COLUMNS}},
        {"taxonomy_id": "SKU-2", **{f: False for f in TIER1_FLAG_COLUMNS}, "null_size": True},
    ]
    assert clean_taxonomy_ids(rows) == ["SKU-1"]

def test_assemble_worklist_json_defaults_missing_candidates_to_empty():
    rows = [{"taxonomy_id": "SKU-1", "canonical_name": "Brand Product 100g", "tier": "unlabelled", "gmv": 500}]
    result = assemble_worklist_json(rows, {}, {}, {}, {})
    assert result == [{
        "taxonomy_id": "SKU-1", "canonical_name": "Brand Product 100g", "tier": "unlabelled", "gmv": 500,
        "tier1_flags": {}, "taxonomy_candidates": [], "brand_candidates": [], "sample_sku_names": [],
    }]
```

- [ ] **Step 6: Run the full test file again**

Run: `uv run python3 tests/niq/test_qa_v2_worklist.py`
Expected: all ten `PASS:` lines print, then `ALL TESTS PASSED`.

- [ ] **Step 7: Commit**

```bash
git add script/niq/qa_v2_worklist.py tests/niq/test_qa_v2_worklist.py
git commit -m "Add QA V2 worklist builder's pure query-builder and data-assembly functions"
```

---

### Task 7: `script/niq/qa_v2_worklist.py` — BigQuery-wired functions and CLI

**Files:**
- Modify: `script/niq/qa_v2_worklist.py`

**Interfaces:**
- Consumes: Task 6's pure functions; `bigquery.Client`.
- Produces: `run_query(client, sql, params) -> list[dict]`, `fastlane_promote(client, table) -> int`,
  `fetch_worklist_rows(client, table, block_size) -> list[dict]`,
  `fetch_tier1_flags(client, taxonomy_ids) -> dict[str, dict]`,
  `fetch_taxonomy_candidates(client, taxonomy_ids) -> dict[str, list[dict]]`,
  `fetch_brand_candidates(client, taxonomy_ids) -> dict[str, list[dict]]`,
  `fetch_sample_sku_names(client, table, taxonomy_ids) -> dict[str, list[str]]`, `main()`. CLI:
  `python3 script/niq/qa_v2_worklist.py --table <TABLE> --block-size <N>`, prints the worklist JSON array to
  stdout (or `[]` if empty) and status lines to stderr. This is the interface `targeted_qa_fix_v2.sh` (Task 8)
  invokes.

Per this repo's existing convention (`script/embedding_worker.py`, `script/non_niq/non_niq_embed.py`),
BigQuery-touching functions are not unit-tested with a mock client — they're verified via a live smoke-test
step against a real table, same as this task's Step 5.

- [ ] **Step 1: Add the BigQuery-wired functions and CLI to `script/niq/qa_v2_worklist.py`**

Append (after the existing pure functions, before end of file):

```python
import argparse


def run_query(client, sql, params):
    job_config = bigquery.QueryJobConfig(query_parameters=params)
    return [dict(row.items()) for row in client.query(sql, job_config=job_config).result()]


def fastlane_promote(client, table):
    """STEP 1C-equivalent: bulk-promote fixed-pending-recheck rows that come back Tier-1-clean. No LLM
    judgment -- this is a direct cost removal, these rows never reach claude -p at all."""
    sql, params = build_pending_recheck_query(table)
    pending_ids = [r["taxonomy_id"] for r in run_query(client, sql, params)]
    if not pending_ids:
        return 0
    sql, params = build_tier1_sweep_query(pending_ids)
    flag_rows = run_query(client, sql, params)
    clean_ids = clean_taxonomy_ids(flag_rows)
    if not clean_ids:
        return 0
    sql, params = build_promote_query(clean_ids)
    client.query(sql, job_config=bigquery.QueryJobConfig(query_parameters=params)).result()
    return len(clean_ids)


def fetch_worklist_rows(client, table, block_size):
    sql, params = build_worklist_query(table, block_size)
    return run_query(client, sql, params)


def fetch_tier1_flags(client, taxonomy_ids):
    if not taxonomy_ids:
        return {}
    sql, params = build_tier1_sweep_query(taxonomy_ids)
    rows = run_query(client, sql, params)
    return {r["taxonomy_id"]: {f: r[f] for f in TIER1_FLAG_COLUMNS} for r in rows}


def fetch_taxonomy_candidates(client, taxonomy_ids):
    if not taxonomy_ids:
        return {}
    sql, params = build_taxonomy_candidates_query(taxonomy_ids)
    rows = run_query(client, sql, params)
    result = {}
    for r in rows:
        result.setdefault(r["worklist_taxonomy_id"], []).append({
            "taxonomy_id": r["candidate_taxonomy_id"],
            "canonical_name": r["candidate_canonical_name"],
            "normalized_distance": r["normalized_distance"],
        })
    return result


def fetch_brand_candidates(client, taxonomy_ids):
    if not taxonomy_ids:
        return {}
    sql, params = build_brand_candidates_query(taxonomy_ids)
    rows = run_query(client, sql, params)
    result = {}
    for r in rows:
        result.setdefault(r["worklist_taxonomy_id"], []).append({
            "brand_id": r["candidate_brand_id"],
            "canonical_name": r["candidate_canonical_name"],
            "normalized_distance": r["normalized_distance"],
        })
    return result


def fetch_sample_sku_names(client, table, taxonomy_ids):
    if not taxonomy_ids:
        return {}
    sql, params = build_sample_sku_names_query(table, taxonomy_ids)
    rows = run_query(client, sql, params)
    return {r["taxonomy_id"]: list(r["sample_sku_names"]) for r in rows}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--table", required=True)
    parser.add_argument("--block-size", type=int, default=200)
    args = parser.parse_args()

    client = bigquery.Client(project=PROJECT)

    n_promoted = fastlane_promote(client, args.table)
    print(f"Fast-lane promoted {n_promoted} rows to confident (Tier-1-clean on recheck)", file=sys.stderr)

    rows = fetch_worklist_rows(client, args.table, args.block_size)
    if not rows:
        print("[]")
        return

    taxonomy_ids = [r["taxonomy_id"] for r in rows]
    flags_by_id = fetch_tier1_flags(client, taxonomy_ids)
    tax_cands_by_id = fetch_taxonomy_candidates(client, taxonomy_ids)
    brand_cands_by_id = fetch_brand_candidates(client, taxonomy_ids)
    samples_by_id = fetch_sample_sku_names(client, args.table, taxonomy_ids)

    worklist = assemble_worklist_json(rows, flags_by_id, tax_cands_by_id, brand_cands_by_id, samples_by_id)
    print(json.dumps(worklist))


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Move the `import argparse` line to the top of the file with the other imports**

The `import argparse` shown inline in Step 1 must live in the existing top-of-file import block (alongside
`json`, `re`, `sys`, `Path`, `bigquery`), not inline mid-file — inline was shown there only to mark what Step 1
adds versus Task 6's existing imports.

- [ ] **Step 3: Verify the file parses and Task 6's tests still pass**

Run: `uv run python3 -c "import ast; ast.parse(open('script/niq/qa_v2_worklist.py').read())"`
Expected: no output, exit 0.

Run: `uv run python3 tests/niq/test_qa_v2_worklist.py`
Expected: `ALL TESTS PASSED` (Task 6's pure-function tests must be unaffected by this task's additions).

- [ ] **Step 4: Smoke-test against a real table with `--block-size` capped small**

```bash
uv run python3 script/niq/qa_v2_worklist.py --table shopee_th_toothpaste --block-size 3
```

Expected: a `Fast-lane promoted N rows...` line on stderr (N may be 0 — fine, just confirms the fast-lane path
ran without error), followed by a JSON array on stdout with at most 3 objects, each containing all eight keys
from `assemble_worklist_json`. If the table has zero never-reviewed/unconfident rows left, stdout is `[]` —
also a valid, confirmed-working outcome.

If any row's `brand_candidates` is non-empty, eyeball a couple: do the listed brand names actually look like
plausible near-duplicates/aliases of the row's own brand, or does `normalized_distance < 0.4` look too loose
(unrelated brands showing up) or too tight (obviously-related brands like a truncated/typo variant getting
excluded)? Per the design spec's "Open verification items," this cutoff is an initial guess — if it looks off
here, adjust the `0.4` literal in `sql/queries/qa_v2_brand_candidates.sql` (Task 5) before moving on, rather
than shipping a value nobody checked against real data.

- [ ] **Step 5: Commit**

```bash
git add script/niq/qa_v2_worklist.py
git commit -m "Add BigQuery-wired fetch functions and CLI to qa_v2_worklist.py"
```

---

### Task 8: `script/niq/targeted_qa_fix_v2.sh` — reused generic helpers

**Files:**
- Create: `script/niq/targeted_qa_fix_v2.sh`
- Test: `tests/niq/test_targeted_qa_fix_v2.sh`

**Interfaces:**
- Consumes: nothing new (these are self-contained bash functions, copied from `script/niq/targeted_qa_fix.sh`
  with one behavioral change: `mark_failed_qa`'s `scenario` filter changes from `'targeted_qa_fix'` to
  `'targeted_qa_fix_v2'`, matching the SKU-block scenario Task 9's prompt will claim under).
- Produces: `category_key_for(table) -> str`, `qa_history_insert_query(category_key) -> str`,
  `insert_qa_history_row(category_key, finding, resolution, task_date)`,
  `extract_json_object(text) -> str`, `decide_next_step(result_json) -> str`,
  `mark_failed_qa(table)`, `run_universe_refresh(table)`. Task 9 and Task 10 call these by name.

- [ ] **Step 1: Write the failing test for `category_key_for` and `decide_next_step`**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Self-test for script/niq/targeted_qa_fix_v2.sh's pure helper functions. No network, BQ, or claude calls --
# same scope discipline as tests/niq/test_targeted_qa_fix.sh.
# Run: bash tests/niq/test_targeted_qa_fix_v2.sh

cd "$(dirname "$0")/../.."
source script/niq/targeted_qa_fix_v2.sh

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- category_key_for ---
[[ "$(category_key_for "shopee_th_widget")" == "master_clean_niq.shopee_th_widget" ]] || fail "category_key_for should prefix with master_clean_niq"
echo "PASS: category_key_for"

# --- decide_next_step ---
[[ "$(decide_next_step '{"status":"blocked","blockers":["x"]}')" == "BLOCKED" ]] || fail "blocked status"
[[ "$(decide_next_step '{"status":"failed"}')" == "MARK_FAILED" ]] || fail "failed status"
[[ "$(decide_next_step '{"status":"complete","rows_created":5}')" == "GATE_AND_REFRESH" ]] || fail "complete with rows"
[[ "$(decide_next_step '{"status":"partial","rows_created":1}')" == "GATE_AND_REFRESH" ]] || fail "partial with rows"
[[ "$(decide_next_step '{"status":"complete","rows_created":0}')" == "NOOP" ]] || fail "complete with zero rows"
[[ "$(decide_next_step 'not json at all')" == "MARK_FAILED" ]] || fail "malformed json"
echo "PASS: decide_next_step"

echo "ALL TESTS PASSED"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash tests/niq/test_targeted_qa_fix_v2.sh`
Expected: fails — `script/niq/targeted_qa_fix_v2.sh` doesn't exist yet.

- [ ] **Step 3: Write `script/niq/targeted_qa_fix_v2.sh`'s reused generic helpers**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: ./script/niq/targeted_qa_fix_v2.sh <TABLE> [BLOCK_SIZE] [MAX_TURNS]
# e.g.  ./script/niq/targeted_qa_fix_v2.sh shopee_th_detergent
#
# Auto-discovery only (no brief-mode branch -- that stays on script/niq/targeted_qa_fix.sh). The worklist --
# strict-tier GMV-sorted, Tier-1-flagged, candidate-enriched -- is fully pre-built by
# script/niq/qa_v2_worklist.py before claude -p is ever invoked, so this session's job is judgment-and-fix
# only, not discovery. See docs/superpowers/specs/2026-08-10-targeted-qa-fix-v2-design.md.

PROJECT="sincere-hearth-273704"

category_key_for() {
  local table="$1"
  echo "master_clean_niq.${table}"
}

qa_history_insert_query() {
  local category_key="$1"
  echo "INSERT INTO \`${PROJECT}.magpie_reference.category_brief\` (category_key, task_type, task_date, brief_markdown, updated_at, meta_agent) VALUES (@category_key, 'QA_HISTORY', @task_date, @brief_markdown, CURRENT_TIMESTAMP(), 'CLAUDE_CODE')"
}

insert_qa_history_row() {
  local category_key="$1" finding="$2" resolution="$3" task_date="$4"
  local note
  note=$(printf 'Finding: %s\nResolution: %s' "$finding" "$resolution")
  bq query --use_legacy_sql=false --project_id="${PROJECT}" \
    --parameter="category_key:STRING:${category_key}" \
    --parameter="task_date:DATE:${task_date}" \
    --parameter="brief_markdown:STRING:${note}" \
    "$(qa_history_insert_query "$category_key")"
}

extract_json_object() {
  local text="$1"
  printf '%s' "$text" | grep -Pzo '(?s)\{.*\}' | tr -d '\0'
}

decide_next_step() {
  local result_json="$1"
  local status rows_created
  if ! echo "$result_json" | jq -e . >/dev/null 2>&1; then
    local extracted
    extracted=$(extract_json_object "$result_json")
    if [[ -n "$extracted" ]] && echo "$extracted" | jq -e . >/dev/null 2>&1; then
      result_json="$extracted"
    fi
  fi
  status=$(echo "$result_json" | jq -r '.status // empty' 2>/dev/null) || status=""
  case "$status" in
    blocked)
      echo "BLOCKED"
      ;;
    failed)
      echo "MARK_FAILED"
      ;;
    complete|partial)
      rows_created=$(echo "$result_json" | jq -r '.rows_created // 0' 2>/dev/null) || rows_created="0"
      if [[ "$rows_created" =~ ^[0-9]+$ ]] && [[ "$rows_created" -gt 0 ]]; then
        echo "GATE_AND_REFRESH"
      else
        echo "NOOP"
      fi
      ;;
    *)
      echo "MARK_FAILED"
      ;;
  esac
}

mark_failed_qa() {
  local table="$1"
  echo "Marking most recent ACTIVE targeted_qa_fix_v2 block for ${table} as FAILED_QA..." >&2
  bq query --use_legacy_sql=false --project_id="${PROJECT}" \
    "UPDATE \`${PROJECT}.magpie_reference.sku_block_registry\`
     SET status = 'FAILED_QA'
     WHERE master_table = '${table}' AND scenario = 'targeted_qa_fix_v2' AND status = 'ACTIVE'
       AND claimed_at = (
         SELECT MAX(claimed_at) FROM \`${PROJECT}.magpie_reference.sku_block_registry\`
         WHERE master_table = '${table}' AND scenario = 'targeted_qa_fix_v2' AND status = 'ACTIVE'
       )"
}

run_universe_refresh() {
  local table="$1"
  echo "Running universe refresh for ${table}..."
  bq query --use_legacy_sql=false --project_id="${PROJECT}" \
    "MERGE \`${PROJECT}.magpie_reference.universe_taxonomy_overlay\` t
     USING (
       SELECT m.product_id, m.platform, m.country, m.master_table,
              pt.taxonomy_id, pt.canonical_name, m.source, m.confidence, m.meta_agent
       FROM \`${PROJECT}.magpie_reference.product_taxonomy_map\` m
       JOIN \`${PROJECT}.magpie_reference.product_taxonomy\` pt ON m.taxonomy_id = pt.taxonomy_id
       WHERE m.master_table = '${table}'
       QUALIFY ROW_NUMBER() OVER (
         PARTITION BY m.product_id, m.platform, m.country
         ORDER BY CASE m.source WHEN 'LLM' THEN 0 ELSE 1 END, m.taxonomy_id
       ) = 1
     ) src
     ON t.product_id = src.product_id AND t.platform = src.platform AND t.country = src.country
       AND t.master_table = '${table}'
     WHEN MATCHED THEN UPDATE SET
       taxonomy_id = src.taxonomy_id,
       sku_type_complete = src.canonical_name,
       taxonomy_source = src.source,
       taxonomy_confidence = src.confidence,
       taxonomy_meta_agent = src.meta_agent,
       updated_at = CURRENT_TIMESTAMP()
     WHEN NOT MATCHED BY SOURCE AND t.master_table = '${table}' THEN DELETE
     WHEN NOT MATCHED BY TARGET THEN INSERT
       (product_id, platform, country, master_table, taxonomy_id, sku_type_complete,
        taxonomy_source, taxonomy_confidence, taxonomy_meta_agent, updated_at)
       VALUES (src.product_id, src.platform, src.country, src.master_table, src.taxonomy_id, src.canonical_name,
               src.source, src.confidence, src.meta_agent, CURRENT_TIMESTAMP())"
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `bash tests/niq/test_targeted_qa_fix_v2.sh`
Expected: `PASS: category_key_for`, `PASS: decide_next_step`, `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add script/niq/targeted_qa_fix_v2.sh tests/niq/test_targeted_qa_fix_v2.sh
git commit -m "Add targeted_qa_fix_v2.sh's reused generic helpers (decide_next_step, gate refresh, etc.)"
```

---

### Task 9: `script/niq/targeted_qa_fix_v2.sh` — the V2 prompt builder

**Files:**
- Modify: `script/niq/targeted_qa_fix_v2.sh`
- Modify: `tests/niq/test_targeted_qa_fix_v2.sh`

**Interfaces:**
- Consumes: Task 8's helpers (none directly called by the prompt builder itself, but both live in the same
  file).
- Produces: `build_auto_discovery_prompt_v2(table, category_key, worklist_json, block_size) -> str`. Task 10's
  `main()` calls this.

- [ ] **Step 1: Write the failing test**

Append to `tests/niq/test_targeted_qa_fix_v2.sh` (before `echo "ALL TESTS PASSED"`):

```bash
# --- build_auto_discovery_prompt_v2 ---
sample_worklist='[{"taxonomy_id":"SKU-000001","canonical_name":"Sweety Silver Pants M","tier":"unlabelled","gmv":500000,"tier1_flags":{"null_size":true},"taxonomy_candidates":[],"brand_candidates":[],"sample_sku_names":["Sweety Silver M"]}]'
prompt=$(build_auto_discovery_prompt_v2 "shopee_th_diapers" "master_clean_niq.shopee_th_diapers" "$sample_worklist" 200)
echo "$prompt" | grep -q "SKU-000001" || fail "prompt must embed the worklist JSON verbatim"
echo "$prompt" | grep -q "never-reviewed rows before any unconfident row" || fail "prompt must document the strict-tier ordering it was given"
echo "$prompt" | grep -q "'targeted_qa_fix_v2'" || fail "SKU block claim must use the targeted_qa_fix_v2 scenario, matching mark_failed_qa's filter"
echo "$prompt" | grep -qF 'status: complete|partial|failed|blocked' || fail "prompt must specify the required output JSON shape"
echo "PASS: build_auto_discovery_prompt_v2"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash tests/niq/test_targeted_qa_fix_v2.sh`
Expected: fails — `build_auto_discovery_prompt_v2: command not found`.

- [ ] **Step 3: Add the prompt builder to `script/niq/targeted_qa_fix_v2.sh`**

Append after `run_universe_refresh`'s closing brace:

```bash
build_auto_discovery_prompt_v2() {
  local table="$1"
  local category_key="$2"
  local worklist_json="$3"
  local block_size="${4:-200}"
  local slot_offset=$((block_size - 1))
  cat <<PROMPT
Targeted QA Fix V2 session for ${table}. This is a candidate-enriched, pre-built worklist -- unlike
script/niq/targeted_qa_fix.sh's auto-discovery mode, worklist discovery, the Tier-1 mechanical sweep, and
reference-candidate retrieval have already run in Python/SQL before this session started. See
docs/superpowers/specs/2026-08-10-targeted-qa-fix-v2-design.md for the full design.

BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/llm-extraction-rules.md,
docs/quality-standards.md, docs/brand-extraction.md, and the category brief -- run: SELECT brief_markdown FROM
\`${PROJECT}.magpie_reference.category_brief\` WHERE category_key = '${category_key}' AND task_type = 'BRIEF'.

You are a one-shot, non-interactive process -- do NOT use the Agent/Task tool, ScheduleWakeup, or any
background/async dispatch mechanism.

Your worklist for this session, in JSON, already ordered highest-priority first (every never-reviewed row
before any unconfident row, GMV descending within each tier -- never-reviewed rows before any unconfident row
regardless of relative GMV). Each row carries: tier1_flags (mechanical defects already detected by SQL regex --
you decide the correct fix, not whether the flag fired; a flag can still be a false positive, e.g.
"all variant/size" language on legitimately variant text), taxonomy_candidates (up to 5 same-brand
review_confidence='confident' entries, closest by edit distance -- reference/format context only, never assume
one is correct without checking sku_name/image yourself), brand_candidates (up to 3 similarly-named brand_dict
entries excluding this row's own brand -- for catching brand_id misattribution), and sample_sku_names (up to 3
real listing titles mapped to this taxonomy_id):

${worklist_json}

For every row: judge correct/wrong against docs/llm-extraction-rules.md and docs/quality-standards.md §3's
D1-D5 dimensions, using the pre-attached flags and candidates as a starting point, never as a verdict on their
own. Apply fixes directly via bq query DML.

STEP 4 (fix) -- prefer bulk SQL per defect class over one row at a time. Read a product's image only when the
fix itself requires re-deriving a value. Every row you change must have its _meta reset in the same session:
UPDATE \`${PROJECT}.magpie_reference.product_taxonomy\`
SET _meta = '{"is_reviewed": false}'
WHERE taxonomy_id IN (/* the taxonomy_ids you just fixed */)

STEP 5 -- promote reviewed rows' _meta using the same Path 1/Path 2 rules as script/niq/targeted_qa_fix.sh
(docs/superpowers/specs/2026-07-28-qa-fix-one-pass-confidence-design.md): a never-reviewed row you judge correct
AND that has no un-excepted Tier-1 flag promotes straight to 'confident'; a row you fixed this session that
comes back clean on an immediate Tier-1 recheck also promotes straight to 'confident'; every other row you
review gets its _meta updated by comparing this verdict against its stored prior verdict (agreement ->
confident, disagreement -> unconfident).

STEP 6 -- if a fix genuinely requires minting a new taxonomy entry, claim a ${block_size}-slot SKU block first
(DECLARE before BEGIN TRANSACTION -- reversing that order is a real BigQuery scripting syntax error):
BEGIN
  DECLARE next_start INT64;
  BEGIN TRANSACTION;
  SET next_start = (SELECT COALESCE(MAX(block_end), 69000) + 1 FROM \`${PROJECT}.magpie_reference.sku_block_registry\`);
  INSERT INTO \`${PROJECT}.magpie_reference.sku_block_registry\`
    (block_start, block_end, master_table, scenario, claimed_at, status)
  VALUES (next_start, next_start + ${slot_offset}, '${table}', 'targeted_qa_fix_v2', CURRENT_TIMESTAMP(), 'ACTIVE');
  COMMIT TRANSACTION;
END;
Most sessions fix existing entries in place and need no new SKU at all; only claim a block when you actually
mint one.

STEP 7 -- write via bq query DML only, never the streaming API. Set meta_agent='CLAUDE_CODE' on every row you
write or update. Never delete an existing row.

STEP 8 -- do NOT run the universe refresh yourself; that runs after this session, only if independent QA gates
pass.

STEP 9 -- do not write to \`${PROJECT}.magpie_reference.category_brief\` yourself. Instead, set the final JSON
output's qa_history_entry field to {finding: "...", resolution: "..."}; the wrapper inserts it as a QA_HISTORY
row on your behalf.

STEP 10 -- before declaring status, self-check the hard gates from docs/headless-runbook.md's QA-gate-as-code
section, WITHOUT --skip-coexistence (this category already shipped once -- coexistence is always a genuine bug
at this point). Report the actual numbers in findings.

STEP 11 -- if you hit a genuine blocker at any step, stop, write nothing further, and output status='blocked'
with the blockers array populated. That is a valid, expected outcome, not a failure.

Output ONLY this JSON when done, nothing else:
{status: complete|partial|failed|blocked, rows_created, rows_mapped, taxonomy_id_range_used, qa_history_entry: null|{finding, resolution}, findings, blockers}.
PROMPT
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `bash tests/niq/test_targeted_qa_fix_v2.sh`
Expected: `PASS: build_auto_discovery_prompt_v2`, then `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add script/niq/targeted_qa_fix_v2.sh tests/niq/test_targeted_qa_fix_v2.sh
git commit -m "Add targeted_qa_fix_v2.sh's candidate-enriched auto-discovery prompt builder"
```

---

### Task 10: `script/niq/targeted_qa_fix_v2.sh` — `main()` wiring

**Files:**
- Modify: `script/niq/targeted_qa_fix_v2.sh`
- Modify: `tests/niq/test_targeted_qa_fix_v2.sh`

**Interfaces:**
- Consumes: Task 8's helpers, Task 9's `build_auto_discovery_prompt_v2`, `script/niq/qa_v2_worklist.py` (Task
  7's CLI), `script/niq/qa_report.sh` and `script/niq/qa_coverage_report.sh` (Task 2's moved files).
- Produces: the complete, runnable `script/niq/targeted_qa_fix_v2.sh` — this is the plan's final deliverable
  script.

- [ ] **Step 1: Write the failing test for `main()`'s wiring**

`main()` sets a live `EXIT` trap that runs `qa_coverage_report.sh` against real BigQuery — actually invoking it
in a test (even down the `NOTHING_TO_DO` path) would violate this repo's established "no network, BQ, or
claude calls" test discipline (see `tests/niq/test_targeted_qa_fix.sh`'s own `main()` tests, which check the
function's *source* with `grep`, never call it). Follow the same static-check convention here. Append to
`tests/niq/test_targeted_qa_fix_v2.sh` (before `echo "ALL TESTS PASSED"`):

```bash
# --- main(): worklist build + NOTHING_TO_DO short-circuit + post-processing wiring (static check -- live
# bq/python/claude calls are out of scope here, same convention as tests/niq/test_targeted_qa_fix.sh) ---
script_src=$(cat script/niq/targeted_qa_fix_v2.sh)
grep -qF 'worklist_json=$(python3 script/niq/qa_v2_worklist.py --table "$table" --block-size "$block_size")' <<< "$script_src" || fail "main() must build the worklist via qa_v2_worklist.py before invoking claude -p"
grep -qF 'if [[ "$worklist_json" == "[]" ]]; then' <<< "$script_src" || fail "main() must detect an empty worklist"
grep -qF 'echo "QUEUE_SIGNAL: NOTHING_TO_DO"' <<< "$script_src" || fail "main() must emit NOTHING_TO_DO when the worklist is empty"
grep -qF 'QA_FIX_TABLE="$table"' <<< "$script_src" || fail "main() must set QA_FIX_TABLE as a global for the EXIT trap to see"
grep -q 'trap.*qa_coverage_report\.sh.*EXIT' <<< "$script_src" || fail "main() must set an EXIT trap invoking qa_coverage_report.sh"
grep -qF 'build_auto_discovery_prompt_v2 "$table" "$category_key" "$worklist_json" "$block_size"' <<< "$script_src" || fail "main() must pass the worklist JSON to build_auto_discovery_prompt_v2"
grep -qF 'insert_qa_history_row' <<< "$script_src" || fail "main() must call insert_qa_history_row"
grep -qF 'echo "QUEUE_SIGNAL: BLOCKED"' <<< "$script_src" || fail "main() must emit BLOCKED in the BLOCKED case branch"
grep -qF 'echo "QUEUE_SIGNAL: FAILED"' <<< "$script_src" || fail "main() must emit FAILED in the MARK_FAILED and failed-gate branches"
signal_done_count=$(grep -cF 'echo "QUEUE_SIGNAL: DONE"' <<< "$script_src")
[[ "$signal_done_count" -eq 2 ]] || fail "main() must emit DONE in both the NOOP branch and the successful GATE_AND_REFRESH branch, got $signal_done_count occurrences"
echo "PASS: main() wiring (static check)"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash tests/niq/test_targeted_qa_fix_v2.sh`
Expected: fails at the first new assertion — `FAIL: main() must build the worklist via qa_v2_worklist.py before
invoking claude -p` — since `main()` doesn't exist in the file yet.

- [ ] **Step 3: Add `main()` to `script/niq/targeted_qa_fix_v2.sh`**

Append after `build_auto_discovery_prompt_v2`'s closing brace — same hardcoded-sibling-path convention V1 uses
for its own `./script/qa_report.sh`/`./script/qa_coverage_report.sh` calls, not the configurable-dispatch
pattern `queue_worker.sh` uses for choosing between scripts (different situation: this is one script calling
its own fixed internal dependency, not a dispatcher selecting among scripts):

```bash
main() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <TABLE> [BLOCK_SIZE] [MAX_TURNS]" >&2
    echo "  e.g. $0 shopee_th_detergent            (defaults: BLOCK_SIZE=200, MAX_TURNS=300)" >&2
    exit 1
  fi
  local table="$1"
  local block_size="${2:-200}"
  local max_turns="${3:-300}"

  local category_key
  category_key=$(category_key_for "$table")

  QA_FIX_TABLE="$table"
  trap './script/niq/qa_coverage_report.sh "$QA_FIX_TABLE" || true' EXIT

  echo "Building candidate-enriched worklist for ${table}..."
  local worklist_json
  worklist_json=$(python3 script/niq/qa_v2_worklist.py --table "$table" --block-size "$block_size")

  if [[ "$worklist_json" == "[]" ]]; then
    echo "No unlabelled/unconfident taxonomy entries for ${table} after fast-lane promotion -- nothing to do."
    echo "QUEUE_SIGNAL: NOTHING_TO_DO"
    exit 0
  fi

  echo "TARGETED QA FIX V2 STARTED (${category_key}, block_size=${block_size}, max_turns=${max_turns})"
  echo "==========================="
  local prompt
  prompt=$(build_auto_discovery_prompt_v2 "$table" "$category_key" "$worklist_json" "$block_size")

  local claude_output
  claude_output=$(claude -p --output-format json --permission-mode bypassPermissions --max-turns "$max_turns" "$prompt")

  local result_json
  result_json=$(echo "$claude_output" | jq -r '.result // empty')

  if [[ -z "$result_json" ]]; then
    echo "ERROR: claude -p produced no parseable .result field. Raw output:" >&2
    echo "$claude_output" >&2
    mark_failed_qa "$table"
    exit 1
  fi

  if ! echo "$result_json" | jq -e . >/dev/null 2>&1; then
    local extracted
    extracted=$(extract_json_object "$result_json")
    if [[ -n "$extracted" ]] && echo "$extracted" | jq -e . >/dev/null 2>&1; then
      result_json="$extracted"
    fi
  fi

  local qa_finding qa_resolution
  qa_finding=$(echo "$result_json" | jq -r '.qa_history_entry.finding // empty')
  qa_resolution=$(echo "$result_json" | jq -r '.qa_history_entry.resolution // empty')
  if [[ -n "$qa_finding" ]]; then
    local qa_task_date
    qa_task_date=$(date -u +'%Y-%m-%d')
    insert_qa_history_row "$category_key" "$qa_finding" "$qa_resolution" "$qa_task_date"
    echo "Inserted QA_HISTORY row for ${category_key}."
  fi

  local decision
  decision=$(decide_next_step "$result_json")

  case "$decision" in
    BLOCKED)
      echo "STATUS: blocked. Claimed block left ACTIVE (nothing written) -- see blockers below."
      echo "$result_json" | jq -r '.blockers[]?' >&2
      echo "QUEUE_SIGNAL: BLOCKED"
      exit 0
      ;;
    NOOP)
      echo "STATUS: complete/partial with rows_created=0 -- nothing to gate or refresh. Block left ACTIVE."
      echo "QUEUE_SIGNAL: DONE"
      exit 0
      ;;
    MARK_FAILED)
      echo "STATUS: failed or malformed. Marking block FAILED_QA." >&2
      echo "$result_json" >&2
      mark_failed_qa "$table"
      echo "QUEUE_SIGNAL: FAILED"
      exit 1
      ;;
    GATE_AND_REFRESH)
      echo "STATUS: rows written -- running independent QA gates via script/niq/qa_report.sh..."
      if ./script/niq/qa_report.sh "$table"; then
        if run_universe_refresh "$table"; then
          echo "============================"
          echo "TARGETED QA FIX V2 FINISHED -- universe refreshed"
          echo "QUEUE_SIGNAL: DONE"
        else
          echo "Universe refresh failed -- marking block FAILED_QA." >&2
          mark_failed_qa "$table"
          echo "QUEUE_SIGNAL: FAILED"
          exit 1
        fi
      else
        echo "QA gates failed -- marking block FAILED_QA, skipping universe refresh." >&2
        mark_failed_qa "$table"
        echo "QUEUE_SIGNAL: FAILED"
        exit 1
      fi
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `bash tests/niq/test_targeted_qa_fix_v2.sh`
Expected: `PASS: main() wiring (static check)`, then `ALL TESTS PASSED`.

- [ ] **Step 5: Run the complete test file one more time to confirm nothing regressed**

Run: `bash tests/niq/test_targeted_qa_fix_v2.sh`
Expected: every `PASS:` line from Tasks 8, 9, and 10, then `ALL TESTS PASSED`.

- [ ] **Step 6: Make the script executable and commit**

```bash
chmod +x script/niq/targeted_qa_fix_v2.sh
git add script/niq/targeted_qa_fix_v2.sh tests/niq/test_targeted_qa_fix_v2.sh
git commit -m "Wire targeted_qa_fix_v2.sh's main(): worklist build, claude -p, post-processing"
```

---

### Task 11: Documentation pass

**Files:**
- Modify: `docs/headless-runbook.md`

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing consumed by other tasks — documentation-only, terminal task.

- [ ] **Step 1: Add a subsection documenting V2 near the existing auto-discovery-mode description**

In `docs/headless-runbook.md`, find this exact line (already updated by Task 2 Step 8 to carry the `niq/`
prefix):

```
**Auto-discovery mode** (new default when no real Brief exists): reviews `product_taxonomy` entries the
```

That's the start of the "Auto-discovery mode" bullet; it continues for four more lines and ends with
`for the full mechanics.` immediately before the numbered `1. Claim a ~200-slot block...` list. Insert the new
block immediately after that `for the full mechanics.` line and before the numbered list:

```markdown

**V2 (added 2026-08-10):** `script/niq/targeted_qa_fix_v2.sh` is a separate, auto-discovery-only script that
pre-builds the entire worklist — strict-tier (never-reviewed before unconfident) GMV-sorted, Tier-1-flagged,
and enriched with same-brand confident-entry and brand_dict candidates — via `script/niq/qa_v2_worklist.py`
(pure SQL/Python, no LLM calls) before `claude -p` ever runs. This removes worklist discovery and the Tier-1
sweep from the agent's own turn budget, cutting session cost versus V1's auto-discovery mode. Brief-mode QA
fixes are unaffected and stay on V1 (`script/niq/targeted_qa_fix.sh`) — V2 has no brief-mode branch. See
[`docs/superpowers/specs/2026-08-10-targeted-qa-fix-v2-design.md`](superpowers/specs/2026-08-10-targeted-qa-fix-v2-design.md).
```

- [ ] **Step 2: Verify it renders in the right place**

Run: `grep -n "V2 (added 2026-08-10)" docs/headless-runbook.md`
Expected: exactly one match.

- [ ] **Step 3: Commit**

```bash
git add docs/headless-runbook.md
git commit -m "Document targeted_qa_fix_v2.sh in the headless runbook"
```
