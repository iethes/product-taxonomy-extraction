# Headless Script Scope Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `script/headless_taxonomy.sh` a repeatable coverage-closer (re-runnable against any
category, auto-detecting first-run vs. top-up), narrow `script/targeted_qa_fix.sh` to quality-standard
fixes only, stop the keyword-relevance gate from silently skipping individual in-scope products, and remove
the stale direct-DML universe-refresh language from `ARCHITECTURE.md`/`docs/product-lifecycle.md`.

**Architecture:** `headless_taxonomy.sh` is refactored from a flat single-shot script into pure
query/decision-building functions (testable without BigQuery) plus a `main()` that does the real `bq`/`claude`
calls — the same shape `script/targeted_qa_fix.sh` already uses. `targeted_qa_fix.sh` gets a scoped prompt-text
edit only, no structural change. Doc files get targeted text replacements.

**Tech Stack:** Bash (`set -euo pipefail`), `bq` CLI, `claude -p --output-format json`, `jq` for JSON parsing
(already a `targeted_qa_fix.sh` dependency).

## Global Constraints

- BigQuery project: `sincere-hearth-273704` (referenced as `PROJECT` in both scripts).
- Every write to `product_taxonomy`/`product_taxonomy_map` is DML (`bq query` `INSERT`), never the streaming
  `insert_rows_json` API.
- Every new/touched row gets `meta_agent='CLAUDE_CODE'`.
- SKU block claims: atomic transaction against `sku_block_registry`, `DECLARE next_start INT64;` **before**
  `BEGIN TRANSACTION;` — reversing that order is a real BigQuery scripting syntax error (documented in both
  existing scripts).
- Never let an agent query `MAX(taxonomy_id)` directly — always the atomic `sku_block_registry` claim.
- `status='blocked'` is a valid, expected `claude -p` outcome, never treated as a failure.
- Never delete an existing `product_taxonomy_map` row unless explicitly instructed to.
- `bq query`'s default table display truncates to 100 rows — any query needing a full result set must pass
  `--format=csv` or `--max_rows=100000`.
- No `pipeline/*.py` changes, no schema migrations, no changes to `script/qa_report.sh` in this plan.

---

### Task 1: Rewrite `script/headless_taxonomy.sh` as testable functions + scenario auto-detection

**Files:**
- Modify: `script/headless_taxonomy.sh` (full rewrite, same filename)
- Create: `script/test_headless_taxonomy.sh`

**Interfaces:**
- Produces (functions later tasks/operators rely on): `worklist_query(table, month) -> SQL string`,
  `gap_count_query(table, month) -> SQL string`, `existing_rows_query(table) -> SQL string`,
  `default_month_query(table) -> SQL string`, `decide_scenario(existing_rows_int) -> "first_run"|"top_up"`,
  `compute_block_size(scenario, gap_count) -> int string`, `build_first_run_prompt(table, month, block_size)
  -> prompt string`, `build_topup_prompt(table, month, block_size, gap_count) -> prompt string`, `main(args...)`.
- Consumes: nothing from other tasks (this is the first task).

- [ ] **Step 1: Write the test file skeleton and the first failing tests (query-building functions)**

Create `script/test_headless_taxonomy.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Self-test for script/headless_taxonomy.sh's pure helper functions.
# No network, BQ, or claude calls — mirrors script/test_targeted_qa_fix.sh's convention.
# Run: bash script/test_headless_taxonomy.sh

cd "$(dirname "$0")/.."
source script/headless_taxonomy.sh

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- worklist_query ---
q=$(worklist_query "shopee_th_suncare" "2026-06")
echo "$q" | grep -q "master_clean_niq.shopee_th_suncare" || fail "worklist_query should reference the source table"
echo "$q" | grep -q "2026-06" || fail "worklist_query should reference the month"
echo "$q" | grep -q "CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END" || fail "worklist_query must zero GWP gmv in the cumulative calc"
echo "$q" | grep -q "canonical_name IS NULL" || fail "worklist_query should filter to unmapped products"
echo "$q" | grep -q "cumulative_gmv_pct <= 95" || fail "worklist_query should apply the 95% threshold"
echo "PASS: worklist_query"

# --- gap_count_query ---
q=$(gap_count_query "shopee_th_suncare" "2026-06")
echo "$q" | grep -q "SELECT COUNT(\*) FROM (" || fail "gap_count_query should wrap the worklist in COUNT(*)"
echo "$q" | grep -q "canonical_name IS NULL" || fail "gap_count_query should still carry the worklist's NULL filter"
echo "PASS: gap_count_query"

# --- existing_rows_query ---
q=$(existing_rows_query "shopee_th_suncare")
echo "$q" | grep -q "product_taxonomy_map" || fail "existing_rows_query should hit product_taxonomy_map"
echo "$q" | grep -q "master_table = 'shopee_th_suncare'" || fail "existing_rows_query should scope by master_table"
echo "PASS: existing_rows_query"

# --- default_month_query ---
q=$(default_month_query "shopee_th_suncare")
echo "$q" | grep -q "MAX(month)" || fail "default_month_query should find the latest month"
echo "$q" | grep -q "master_clean_niq.shopee_th_suncare" || fail "default_month_query should reference the source table"
echo "PASS: default_month_query"

echo "ALL TESTS PASSED (part 1)"
```

- [ ] **Step 2: Run the test file to verify it fails (functions don't exist yet)**

Run: `bash script/test_headless_taxonomy.sh`
Expected: FAIL — `source script/headless_taxonomy.sh` errors because `worklist_query` etc. don't exist yet, or
the script itself still has its old flat-body form (which would attempt a live `claude -p` call on source —
Step 3 replaces the whole file before this is re-run for real, so this failure is expected and not separately
diagnosed).

- [ ] **Step 3: Replace `script/headless_taxonomy.sh` with the function-based rewrite (query/decision functions only, prompts stubbed as empty strings for now — filled in Step 5)**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: ./script/headless_taxonomy.sh <TABLE> [MONTH]
# e.g.  ./script/headless_taxonomy.sh shopee_th_conditioner
#       ./script/headless_taxonomy.sh shopee_th_suncare 2026-06   (explicit month instead of live-latest)
#
# Auto-detects scenario from live BigQuery state:
#   - gap_count == 0                    -> nothing to do, exit 0, no claude -p call
#   - gap_count > 0, existing_rows == 0  -> scenario=first_run  (category never touched: Pass 1 + Pass 2 rebuild)
#   - gap_count > 0, existing_rows > 0   -> scenario=top_up     (category already has coverage: close the live gap)
# See docs/superpowers/specs/2026-07-20-headless-script-scope-refinement-design.md for the full design.

PROJECT="sincere-hearth-273704"

worklist_query() {
  local table="$1" month="$2"
  cat <<SQL
WITH base AS (
  SELECT s.product_id, s.model_id, s.merchant_name, s.merchant_badge, s.sku_name, s.image,
         s.gmv_monthly, s.sold_monthly, s.flag_GWP,
         bd.canonical_name AS brand, pt.canonical_name AS canonical_name
  FROM \`${PROJECT}.master_clean_niq.${table}\` s
  LEFT JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` ptm
    ON ptm.product_id = s.product_id AND ptm.master_table = '${table}'
  LEFT JOIN \`${PROJECT}.magpie_reference.product_taxonomy\` pt ON pt.taxonomy_id = ptm.taxonomy_id
  LEFT JOIN \`${PROJECT}.magpie_reference.brand_dict\` bd ON bd.brand_id = pt.brand_id
  WHERE FORMAT_DATE('%Y-%m', s.month) = '${month}'
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY s.product_id, s.model_id
    ORDER BY CASE ptm.source WHEN 'LLM' THEN 1 WHEN 'HUMAN' THEN 2 ELSE 3 END, ptm.taxonomy_id ASC
  ) = 1
),
with_cumulative AS (
  SELECT *,
    ROUND(100.0 * SUM(CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END)
            OVER (ORDER BY gmv_monthly DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
          / NULLIF(SUM(CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END) OVER (), 0), 2) AS cumulative_gmv_pct
  FROM base
)
SELECT * FROM with_cumulative
WHERE cumulative_gmv_pct <= 95 AND canonical_name IS NULL
ORDER BY gmv_monthly DESC
SQL
}

gap_count_query() {
  local table="$1" month="$2"
  echo "SELECT COUNT(*) FROM ($(worklist_query "$table" "$month"))"
}

existing_rows_query() {
  local table="$1"
  echo "SELECT COUNT(*) FROM \`${PROJECT}.magpie_reference.product_taxonomy_map\` WHERE master_table = '${table}'"
}

default_month_query() {
  local table="$1"
  echo "SELECT FORMAT_DATE('%Y-%m', MAX(month)) FROM \`${PROJECT}.master_clean_niq.${table}\`"
}

decide_scenario() {
  local existing_rows="$1"
  if [[ "$existing_rows" =~ ^[0-9]+$ ]] && [[ "$existing_rows" -eq 0 ]]; then
    echo "first_run"
  else
    echo "top_up"
  fi
}

compute_block_size() {
  local scenario="$1" gap_count="$2"
  if [[ "$scenario" == "first_run" ]]; then
    echo 2000
    return
  fi
  local size="$gap_count"
  [[ "$size" =~ ^[0-9]+$ ]] || size=200
  [[ "$size" -lt 200 ]] && size=200
  [[ "$size" -gt 2000 ]] && size=2000
  echo "$size"
}

build_first_run_prompt() {
  echo "PLACEHOLDER_FIRST_RUN"
}

build_topup_prompt() {
  echo "PLACEHOLDER_TOP_UP"
}

main() {
  echo "not yet wired up"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
```

- [ ] **Step 4: Run the test file to verify the query/decision functions pass**

Run: `bash script/test_headless_taxonomy.sh`
Expected: `ALL TESTS PASSED (part 1)` printed, exit 0.

- [ ] **Step 5: Add failing tests for `decide_scenario` and `compute_block_size`, then verify they already pass**

Append to `script/test_headless_taxonomy.sh` (before the final `echo "ALL TESTS PASSED (part 1)"` line — move
that line to the end after adding these):

```bash
# --- decide_scenario ---
[[ "$(decide_scenario 0)" == "first_run" ]] || fail "0 existing rows -> first_run"
[[ "$(decide_scenario 5000)" == "top_up" ]] || fail "nonzero existing rows -> top_up"
echo "PASS: decide_scenario"

# --- compute_block_size ---
[[ "$(compute_block_size first_run 0)" == "2000" ]] || fail "first_run always claims 2000 regardless of gap_count"
[[ "$(compute_block_size top_up 50)" == "200" ]] || fail "top_up floors the block size at 200"
[[ "$(compute_block_size top_up 500)" == "500" ]] || fail "top_up scales the block size with gap_count"
[[ "$(compute_block_size top_up 5000)" == "2000" ]] || fail "top_up caps the block size at 2000"
echo "PASS: decide_scenario / compute_block_size"
```

Run: `bash script/test_headless_taxonomy.sh`
Expected: passes (these functions were already implemented correctly in Step 3) — `ALL TESTS PASSED (part 1)`.

- [ ] **Step 6: Add failing tests for the two prompt builders, confirm they fail against the placeholders**

Append to `script/test_headless_taxonomy.sh`:

```bash
# --- build_first_run_prompt ---
prompt=$(build_first_run_prompt "shopee_th_conditioner" "2026-06" "2000")
echo "$prompt" | grep -q "shopee_th_conditioner" || fail "build_first_run_prompt should mention the table"
echo "$prompt" | grep -q "2026-06" || fail "build_first_run_prompt should mention the resolved month"
echo "$prompt" | grep -q "2000" || fail "build_first_run_prompt should mention the claimed block size"
echo "$prompt" | grep -q "CASE WHEN flag_GWP THEN 0 ELSE" || fail "build_first_run_prompt's brand-scope step must zero GWP gmv"
echo "$prompt" | grep -q "never be used to decide whether an individual product gets extracted" || fail "build_first_run_prompt must forbid keyword pre-filtering of individual products"
echo "$prompt" | grep -q "status='blocked'" || fail "build_first_run_prompt should document the blocked outcome"
echo "PASS: build_first_run_prompt"

# --- build_topup_prompt ---
prompt=$(build_topup_prompt "shopee_th_suncare" "2026-06" "500" "412")
echo "$prompt" | grep -q "shopee_th_suncare" || fail "build_topup_prompt should mention the table"
echo "$prompt" | grep -q "412" || fail "build_topup_prompt should mention the pre-check gap_count as a hint"
echo "$prompt" | grep -q "do NOT trust that number" || fail "build_topup_prompt must tell the agent to re-verify the gap live"
echo "$prompt" | grep -q "reuse-before-mint" || fail "build_topup_prompt must instruct reuse-before-mint against existing taxonomy"
echo "$prompt" | grep -q "never be used to decide whether an individual product gets extracted" || fail "build_topup_prompt must forbid keyword pre-filtering of individual products"
echo "$prompt" | grep -q "taxonomy_topup" || fail "build_topup_prompt should claim a taxonomy_topup-scenario SKU block"
echo "$prompt" | grep -q "500" || fail "build_topup_prompt should mention the computed block size"
echo "$prompt" | grep -q "status='blocked'" || fail "build_topup_prompt should document the blocked outcome"
echo "PASS: build_topup_prompt"
```

Run: `bash script/test_headless_taxonomy.sh`
Expected: FAIL at the first `build_first_run_prompt` assertion (`PLACEHOLDER_FIRST_RUN` doesn't contain
`shopee_th_conditioner`).

- [ ] **Step 7: Implement `build_first_run_prompt`**

Replace the `build_first_run_prompt` placeholder in `script/headless_taxonomy.sh`:

```bash
build_first_run_prompt() {
  local table="$1" month="$2" block_size="$3"
  local slot_offset=$((block_size - 1))
  cat <<PROMPT
Full Rebuild session for ${table}, month ${month}. This is a first-run invocation — the wrapper's live
pre-check found 0 existing \`product_taxonomy_map\` rows for this table. No category context file exists yet
for this table — you are creating one as part of this run, not reading a pre-existing one.

BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/data-dictionary.md, docs/llm-extraction-rules.md, docs/quality-standards.md, docs/headless-runbook.md, docs/brand-extraction.md, and docs/categories/_TEMPLATE.md (the last one because you are about to fill it in — not in the original doc list, but required for this run specifically). Also check docs/categories/STATUS.md to confirm ${table} hasn't already been completed by someone else since this prompt was written.

You perform extraction yourself, directly, using your own multimodal reading of product images and text. You do not invoke external scripts or subprocesses and do not need any API key beyond your own session auth — CLAUDE.md's ANTHROPIC_API_KEY note is about a different, external pipeline that does not exist in this repo.

STEP 0 — Verify the source table actually exists where you expect it, before anything else:
Run: SELECT COUNT(*) FROM \`${PROJECT}.master_clean_niq.${table}\` LIMIT 1
This pipeline is proven end-to-end for NIQ tables (master_clean_niq → marketshare_universe_niq). If ${table} isn't there, do NOT guess at intrepid_pipeline_clean_product_level or any other dataset — that data path is
unconfirmed and was the source of real problems in an earlier session. Treat 'source table not found where expected' as a genuine blocker: stop, status='blocked', explain what you found instead.

STEP 1 — Re-verify existing state before assuming anything about it (the wrapper's pre-check is a hint, not a fact — re-query live):
Run: SELECT source, COUNT(*) FROM \`${PROJECT}.magpie_reference.product_taxonomy_map\`
WHERE master_table = '${table}' GROUP BY source
If this disagrees with "0 rows", stop and report the discrepancy in findings rather than silently proceeding as a first run.

STEP 2 — Research and write docs/categories/${table}.md, following _TEMPLATE.md's structure:
- Brand Scope: compute the REAL cumulative-GMV 95% threshold for month = '${month}' — ORDER BY brand GMV DESC, running SUM, find where cumulative/total >= 0.95. Zero out flag_GWP=TRUE products' GMV in this cumulative calculation (CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END) — GWP products still get extracted like any other in-scope product, they just must not inflate the brand-GMV ranking. Do NOT just list the top 15-20 brands by magnitude and call that the 95% scope — that undercounted a real category's true brand universe by roughly 6x in an earlier session (~20 claimed vs. ~190 actual). List every brand in the real threshold, not a fixed-size snapshot.
- Official Store Allowlist: query DISTINCT merchant_name WHERE merchant_badge = 'Shopee Mall', per brand in scope. Exclude known multi-brand retailers per docs/llm-extraction-rules.md §4 (Sasa, Watsons, Boots, BEAUTRIUM, Tsuruha for beauty; BigC, Lotuss, Tops, Villa Market for grocery; check the full list in that doc for this category's vertical). Note parent-company stores (P&G, Unilever, Lion-style) as Pass-1-eligible for all brands they carry, not excluded as multi-brand.
- Scale: total row count, official-store row count, distinct product count. If official-store row count alone is large (tens of thousands+), say so explicitly — Pass 1 must still scope to the allowlist only, not the full Mall-badged pool.
- Existing map rows (from Step 1): document the real counts, not an assumption.
- Write the file, then commit it: git add docs/categories/${table}.md && git commit -m 'Add category context for ${table}, generated during headless Full Rebuild'

STEP 3 — Claim your SKU block atomically. Query the real current ceiling first, then use this exact pattern (DECLARE before BEGIN TRANSACTION — reversing that order is a real syntax error in BigQuery scripting, found
the hard way in an earlier session):
BEGIN
  DECLARE next_start INT64;
  BEGIN TRANSACTION;
  SET next_start = (SELECT COALESCE(MAX(block_end), 69000) + 1 FROM \`${PROJECT}.magpie_reference.sku_block_registry\`);
  INSERT INTO \`${PROJECT}.magpie_reference.sku_block_registry\`
    (block_start, block_end, master_table, scenario, claimed_at, status)
  VALUES (next_start, next_start + ${slot_offset}, '${table}', 'full_rebuild', CURRENT_TIMESTAMP(), 'ACTIVE');
  COMMIT TRANSACTION;
END;
Claim ${block_size} slots — sized by the wrapper for a first-run category (products fragment into many near-unique SKUs, so a generous block avoids needing a supplemental claim mid-run). Never query MAX(taxonomy_id) directly and assume it's safe to use — the atomic claim is what prevents two sessions colliding on the same ID range.

STEP 4 — Pass 1: build taxonomy ONLY from the Official Store Allowlist merchant names you just wrote into the category file — not the full Mall-badged pool.

STEP 5 — Pass 2: route remaining official-store-unmatched and reseller products primarily via bulk SQL text-matching of sku_name against the Pass 1 taxonomy you just built. Only read product images for individual products where text matching is genuinely ambiguous — do not vision-read the full candidate pool. This keyword/text-matching step is a routing convenience, never a scope filter: this keyword gate must never be used to decide whether an individual product gets extracted. Every product in the 95%-cumulative-GMV-or-official-store in-scope set (docs/quality-standards.md §2) must be read and evaluated — only your own category/type match-or-create gate (docs/product-lifecycle.md §4.2), applied after reading a product, may conclude it doesn't belong here and leave it NULL. This matters most for high-GMV Mall-seller listings that are genuinely miscategorized (their sku_name doesn't match the category's expected keywords even though the product itself belongs) — a text pre-filter would silently drop them before you ever looked.

STEP 6 — For every taxonomy entry, populate product_line, sub_line, and variant as their own structured columns — do NOT leave them NULL while folding that same information into canonical_name as free text. product_line is close to mandatory (populate it whenever a real on-label line name exists, per docs/llm-extraction-rules.md §3); sub_line and variant are optional — populate only where a real signal exists, leave NULL rather than guess when the text doesn't clearly support a split. This was gotten wrong before: 934 entries once shipped with product_line NULL on 100% of them because the extraction wrote good canonical_name text but never decomposed it into the structured fields.

Write via bq query DML only, never the streaming API.

STEP 7 — Before declaring status, self-check using the exact QA-gate queries from docs/headless-runbook.md's QA-gate-as-code section, run with --skip-coexistence semantics (dual-mapped scoped to source='LLM', and placeholder-leak). Report the actual numbers in findings — do not just assert 'gates passed' without the figures.

If you hit a genuine blocker at any step — something wrong with these instructions, missing data, the source table not existing where expected, anything that would make proceeding unsafe — stop, write nothing further, and output status='blocked' with the blockers array populated. That is a valid, expected outcome, not a failure.

Output ONLY this JSON when done, nothing else:
{status: complete|partial|failed|blocked, rows_created, rows_mapped, taxonomy_id_range_used, findings, blockers}.
PROMPT
}
```

- [ ] **Step 8: Run the test file to verify `build_first_run_prompt`'s assertions now pass**

Run: `bash script/test_headless_taxonomy.sh`
Expected: `PASS: build_first_run_prompt`, then FAIL at the first `build_topup_prompt` assertion
(`PLACEHOLDER_TOP_UP` still in place).

- [ ] **Step 9: Implement `build_topup_prompt`**

Replace the `build_topup_prompt` placeholder in `script/headless_taxonomy.sh`:

```bash
build_topup_prompt() {
  local table="$1" month="$2" block_size="$3" gap_count="$4"
  local query
  query=$(worklist_query "$table" "$month")
  cat <<PROMPT
Top-up coverage session for ${table}, month ${month}. This category already has taxonomy coverage from a
prior run, but the wrapper's live pre-check just found ${gap_count} products still within the 95%-cumulative-GMV
(GWP-zeroed) threshold with no taxonomy_id — do NOT trust that number as still-current, re-run the worklist
query yourself in STEP 0 below and use its live result as your actual worklist.

BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/llm-extraction-rules.md, docs/quality-standards.md, docs/headless-runbook.md, docs/brand-extraction.md, and docs/categories/${table}.md (the existing category file — its brand scope, official store allowlist, and scope rules are already documented there; do not rediscover them from scratch).

You perform extraction yourself, directly, using your own multimodal reading of product images and text. You do not invoke external scripts or subprocesses and do not need any API key beyond your own session auth — CLAUDE.md's ANTHROPIC_API_KEY note is about a different, external pipeline that does not exist in this repo.

Known pitfall from prior sessions: \`bq query\` silently truncates displayed results to 100 rows unless you pass --max_rows=100000 or --format=csv — always use one of those on the STEP 0 query below, and sanity-check the row count against what you expect rather than assuming a short result means a short true set.

STEP 0 — Get the live worklist (do not trust any number in this prompt or in ${table}.md):
${query}

STEP 1 — For every product in that live worklist, apply reuse-before-mint against ${table}'s EXISTING taxonomy first (docs/product-lifecycle.md §4's match-or-create decision tree: brand gate, category gate, type gate, specificity match, size+pack match). Only mint a new SKU-XXXXXX entry when no existing brand+line+size+pack entry fits — a correct-but-granular new entry is always better than a wrong reuse.

Read product image + sku_name directly for each product. This is a routing convenience, never a scope filter: no keyword/text heuristic may be used to decide whether an individual product in the live worklist gets read and evaluated at all — every product in the worklist gets read. Only your own category/type match-or-create gate, applied after reading a product, may conclude it doesn't belong here and leave it NULL. This matters most for high-GMV Mall-seller listings that are genuinely miscategorized (their sku_name doesn't match the category's expected keywords even though the product itself belongs) — a text pre-filter would silently drop them before you ever looked.

STEP 2 — Claim a ${block_size}-slot SKU block atomically (DECLARE before BEGIN TRANSACTION — reversing that order is a real BigQuery scripting syntax error):
BEGIN
  DECLARE next_start INT64;
  BEGIN TRANSACTION;
  SET next_start = (SELECT COALESCE(MAX(block_end), 69000) + 1 FROM \`${PROJECT}.magpie_reference.sku_block_registry\`);
  INSERT INTO \`${PROJECT}.magpie_reference.sku_block_registry\`
    (block_start, block_end, master_table, scenario, claimed_at, status)
  VALUES (next_start, next_start + ${block_size} - 1, '${table}', 'taxonomy_topup', CURRENT_TIMESTAMP(), 'ACTIVE');
  COMMIT TRANSACTION;
END;
Never query MAX(taxonomy_id) directly and assume it's safe to use — this atomic claim against the registry table is what prevents two sessions colliding on the same ID range.

STEP 3 — Write via bq query DML only, never the streaming API. Set meta_agent='CLAUDE_CODE' on every row you write. Never delete an existing row.

STEP 4 — Append a dated row to ${table}.md's '## QA History' table (columns: Date | Pass | Finding | Resolution) summarizing what you did and found this session. Commit the updated file:
git add docs/categories/${table}.md && git commit -m 'Top-up coverage session for ${table}: update QA History'

STEP 5 — Before declaring status, self-check using the exact QA-gate queries from docs/headless-runbook.md's QA-gate-as-code section, run WITHOUT --skip-coexistence (HUMAN+LLM coexistence should be a genuine bug at this point, not an expected mid-rebuild state, since this category already shipped once). Report the actual numbers in findings.

Do NOT run the universe refresh yourself — that is a separate step, run only after independent QA verification, not something this session does.

If you hit a genuine blocker at any step — something wrong with these instructions, missing data, anything that would make proceeding unsafe — stop, write nothing further, and output status='blocked' with the blockers array populated. That is a valid, expected outcome, not a failure.

Output ONLY this JSON when done, nothing else:
{status: complete|partial|failed|blocked, rows_created, rows_mapped, taxonomy_id_range_used, findings, blockers}.
PROMPT
}
```

- [ ] **Step 10: Run the test file to verify both prompt builders now pass**

Run: `bash script/test_headless_taxonomy.sh`
Expected: `PASS: build_first_run_prompt`, `PASS: build_topup_prompt`, `ALL TESTS PASSED (part 1)`.

- [ ] **Step 11: Implement `main()` and the source/execute guard**

Replace the `main` placeholder in `script/headless_taxonomy.sh`:

```bash
main() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <TABLE> [MONTH]" >&2
    echo "  e.g. $0 shopee_th_conditioner" >&2
    echo "  e.g. $0 shopee_th_suncare 2026-06   (explicit month instead of live-latest)" >&2
    exit 1
  fi
  local table="$1"
  local month="${2:-}"

  if [[ -z "$month" ]]; then
    month=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
      "$(default_month_query "$table")" | tail -1)
  fi

  echo "${table}"
  echo "Resolved month: ${month}"

  local gap_count
  gap_count=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "$(gap_count_query "$table" "$month")" | tail -1)

  if [[ "$gap_count" == "0" ]]; then
    echo "No in-scope coverage gap for ${table}/${month} — nothing to do."
    exit 0
  fi

  local existing_rows
  existing_rows=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "$(existing_rows_query "$table")" | tail -1)

  local scenario
  scenario=$(decide_scenario "$existing_rows")

  local block_size
  block_size=$(compute_block_size "$scenario" "$gap_count")

  echo "Scenario: ${scenario} (existing_rows=${existing_rows}, gap_count=${gap_count}, block_size=${block_size})"
  echo "TAXONOMY EXTRACTION STARTED"
  echo "==========================="

  local prompt
  if [[ "$scenario" == "first_run" ]]; then
    prompt=$(build_first_run_prompt "$table" "$month" "$block_size")
  else
    prompt=$(build_topup_prompt "$table" "$month" "$block_size" "$gap_count")
  fi

  claude -p --output-format json --permission-mode bypassPermissions --max-turns 300 "$prompt"

  echo "============================"
  echo "TAXONOMY EXTRACTION FINISHED"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
```

- [ ] **Step 12: Run the full test file once more, then the syntax and argument-validation checks**

Run: `bash script/test_headless_taxonomy.sh`
Expected: `ALL TESTS PASSED (part 1)` (sourcing the file no longer runs `main`, since `$0` during `source` is
not `script/headless_taxonomy.sh`).

Run: `bash -n script/headless_taxonomy.sh`
Expected: no output, exit 0 (syntax check).

Run: `./script/headless_taxonomy.sh`
Expected: prints `Usage: ./script/headless_taxonomy.sh <TABLE> [MONTH]` and two example lines to stderr, exits 1
— before any `bq`/`claude` call (verifies the argument check runs first).

Run: `chmod +x script/headless_taxonomy.sh` if the last command fails with a permissions error instead of a
usage message.

- [ ] **Step 13: Commit**

```bash
git add script/headless_taxonomy.sh script/test_headless_taxonomy.sh
git commit -m "Rewrite headless_taxonomy.sh as a repeatable coverage-closer with scenario auto-detection"
```

---

### Task 2: Narrow `script/targeted_qa_fix.sh` to quality-standard violations only

**Files:**
- Modify: `script/targeted_qa_fix.sh:32-78` (the `build_prompt` function)
- Modify: `script/test_targeted_qa_fix.sh:35-42` (the `build_prompt` assertions)

**Interfaces:**
- Consumes: nothing from Task 1 (independent file).
- Produces: nothing new — same `build_prompt(table, category_file, block_size)` signature, text content only.

- [ ] **Step 1: Add failing assertions to `script/test_targeted_qa_fix.sh` for the new scope-boundary text**

In `script/test_targeted_qa_fix.sh`, in the `--- build_prompt ---` section (after the existing five `grep -q`
checks, before `echo "PASS: build_prompt"`), add:

```bash
echo "$prompt" | grep -q "never creates coverage for products with" || fail "build_prompt must state this script never creates coverage for taxonomy_id IS NULL products"
echo "$prompt" | grep -q "headless_taxonomy.sh" || fail "build_prompt should point NULL-coverage work at headless_taxonomy.sh instead"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: FAIL at the first new assertion — the current STEP 3 text doesn't contain that phrase yet.

- [ ] **Step 3: Edit `script/targeted_qa_fix.sh`'s STEP 3 prompt text**

In `script/targeted_qa_fix.sh`, find this line inside `build_prompt` (currently line 64):

```
STEP 3 — Execute exactly the fixes described in ${category_file}'s '## Targeted QA Fix Brief' section: pack-count / size / bundle corrections, the NULL-coverage pass, whatever that section specifies. That section is the actual scope of this session — this prompt does not restate it.
```

Replace it with:

```
STEP 3 — Execute exactly the fixes described in ${category_file}'s '## Targeted QA Fix Brief' section: pack-count / size / bundle / product-line / variant corrections, hard-gate violations (G1, G2, G3, G5, G6 per docs/quality-standards.md §4), brand_mismatch review per docs/brand-extraction.md — whatever that section specifies. That section is the actual scope of this session — this prompt does not restate it. This script fixes existing taxonomy entries only; it never creates coverage for products with taxonomy_id IS NULL — if the Brief's scope turns out to actually be a NULL-coverage/unmapped-product backfill, that is a genuine blocker (the correct tool is script/headless_taxonomy.sh's top-up scenario, not this script): stop, write nothing, output status='blocked' explaining the mismatch.
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash script/test_targeted_qa_fix.sh`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add script/targeted_qa_fix.sh script/test_targeted_qa_fix.sh
git commit -m "Narrow targeted_qa_fix.sh scope to existing-row quality defects, exclude NULL-coverage work"
```

---

### Task 3: Scope the §8 keyword gate to brand-ranking only in `docs/llm-extraction-rules.md`

**Files:**
- Modify: `docs/llm-extraction-rules.md:224-231` (§8 "Brand scope GMV threshold" subsection)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: the exact sentence `never be used to decide whether an individual product gets extracted` that
  Task 1's prompt-builder tests already assert appears in the generated prompts (the prompts restate this rule
  inline so the LLM sees it without a doc lookup; this task is the source-of-truth doc edit).

- [ ] **Step 1: Edit the §8 subsection**

In `docs/llm-extraction-rules.md`, find:

```markdown
**Brand scope GMV threshold — filter to category sku_names first:**
- When calculating which brands are in the 95% GMV scope, filter sku_names to
  category-relevant products BEFORE summing GMV. Source tables can contain mixed products.
- Example: `shopee_th_body_wash` contains hand wash, feminine wash, and baby shampoo. A
  hand-wash-only brand would appear in the brand rank if GMV is summed across all sku_names.
- Pattern: add a keyword guard (`has_body_wash_keyword(sku_name) = TRUE`) in the GMV query,
  or use the NIQ category mapping to pre-filter to in-scope products only.
- This applies to every category with a mixed-content source table.
```

Replace with:

```markdown
**Brand scope GMV threshold — filter to category sku_names first:**
- When calculating which brands are in the 95% GMV scope, filter sku_names to
  category-relevant products BEFORE summing GMV. Source tables can contain mixed products.
- Example: `shopee_th_body_wash` contains hand wash, feminine wash, and baby shampoo. A
  hand-wash-only brand would appear in the brand rank if GMV is summed across all sku_names.
- Pattern: add a keyword guard (`has_body_wash_keyword(sku_name) = TRUE`) in the GMV query,
  or use the NIQ category mapping to pre-filter to in-scope products only.
- This applies to every category with a mixed-content source table.
- **This keyword gate is a brand-ranking control only — it must never be used to decide whether an
  individual product gets extracted.** Every product in the in-scope worklist (top-95%-cumulative-GMV,
  GWP-zeroed, plus official-store listings per `docs/quality-standards.md` §2) must be read (image + text) by
  the LLM. Only the LLM's own category/type match-or-create gate (`docs/product-lifecycle.md` §4.2), applied
  *after* reading the product, may conclude a product doesn't belong to this category and leave it NULL —
  never a pre-extraction keyword/text heuristic. This matters most for high-GMV Mall-seller listings that are
  genuinely miscategorized (their `sku_name` doesn't match the category's expected keywords even though the
  product itself belongs): a keyword pre-filter would drop them before the LLM ever sees them; the
  category/type gate, applied per-product, catches them correctly.
```

- [ ] **Step 2: Verify the edit**

Run: `grep -n "never be used to decide whether an individual product gets extracted" docs/llm-extraction-rules.md`
Expected: one match, inside the §8 section.

- [ ] **Step 3: Commit**

```bash
git add docs/llm-extraction-rules.md
git commit -m "Scope the §8 keyword gate to brand-ranking only, forbid per-product pre-filtering"
```

---

### Task 4: Add a scoped `## Targeted QA Fix Brief` section to `docs/categories/_TEMPLATE.md`

**Files:**
- Modify: `docs/categories/_TEMPLATE.md` (add a new section after `## QA History`)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: the section header `## Targeted QA Fix Brief` that future category files will copy — matches what
  `script/targeted_qa_fix.sh`'s `build_prompt` (Task 2) already expects to find in a category file.

- [ ] **Step 1: Insert the new section**

In `docs/categories/_TEMPLATE.md`, find:

```markdown
## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| YYYY-MM-DD | Initial | {finding} | {fix} |
| YYYY-MM-DD | QA Gate A | {finding} | {fix} |

---

## Scripts
```

Replace with:

```markdown
## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| YYYY-MM-DD | Initial | {finding} | {fix} |
| YYYY-MM-DD | QA Gate A | {finding} | {fix} |

---

## Targeted QA Fix Brief

> Scope: quality-standard violations on products that **already have** a `taxonomy_id` — generic-stub
> product lines, missing size/variant/pack-count, wrong product line, hard-gate violations (G1, G2, G3, G5,
> G6 per docs/quality-standards.md §4), brand_mismatch review per docs/brand-extraction.md. Never products
> with `taxonomy_id IS NULL` — that coverage gap is `script/headless_taxonomy.sh`'s job (its live worklist
> query finds it automatically; no brief needed for that).

**Verdict:** {defect class, e.g. "D1 Tier-C generic stubs" / "D5 pack-count errors" / "G6 unreviewed brand_mismatch rows"}

{Fix A/B/C description: which products, what's wrong, how to detect them (a SQL snippet if useful),
category-specific QA gate notes.}

---

## Scripts
```

- [ ] **Step 2: Verify the edit**

Run: `grep -n "## Targeted QA Fix Brief" docs/categories/_TEMPLATE.md`
Expected: one match.

Run: `grep -c "^## " docs/categories/_TEMPLATE.md`
Expected: one more section heading than before (confirms the section was added, not substituted over an
existing one).

- [ ] **Step 3: Commit**

```bash
git add docs/categories/_TEMPLATE.md
git commit -m "Add scoped Targeted QA Fix Brief section to the category file template"
```

---

### Task 5: Update scenario prose in `docs/headless-runbook.md` and `docs/headless-scripts-flow.md`

**Files:**
- Modify: `docs/headless-runbook.md:259-277` (the "Scenario: Targeted QA Fix" and "Scenario: Full Rebuild" section openings)
- Modify: `docs/headless-scripts-flow.md` (both scripts' description paragraphs)

**Interfaces:**
- Consumes: the scenario names `first_run` / `top_up` / `taxonomy_topup` established in Task 1, and the
  quality-standards-only scope established in Task 2, purely as prose references (no code dependency).
- Produces: nothing consumed elsewhere — documentation only.

- [ ] **Step 1: Edit `docs/headless-runbook.md`'s "Scenario: Targeted QA Fix" opening**

Find:

```markdown
## Scenario: Targeted QA Fix

Small SKU block (~200), narrow prompt scope (specific flagged products, not a full category rebuild), QA gates
scoped to affected `product_id`s only, universe refresh runs but only touches the products actually rerouted.
```

Replace with:

```markdown
## Scenario: Targeted QA Fix

Small SKU block (~200), narrow prompt scope (specific flagged products, not a full category rebuild), QA gates
scoped to affected `product_id`s only, universe refresh runs but only touches the products actually rerouted.

**Scope boundary:** this scenario fixes existing-row quality defects only — `docs/quality-standards.md`
§3's D1–D5 dimensions (generic-stub product lines, missing size/variant/pack-count, wrong product line) and
§4's hard gates G1/G2/G3/G5/G6, plus `brand_mismatch` review per `docs/brand-extraction.md`. Coverage gaps
(products with `taxonomy_id IS NULL`) are explicitly out of scope for this script — see "Scenario: Full
Rebuild" below, which now also covers re-running against an already-complete category to close a live
coverage gap.
```

- [ ] **Step 2: Edit `docs/headless-runbook.md`'s "Scenario: Full Rebuild" opening**

Find:

```markdown
## Scenario: Full Rebuild

Full SKU block (~1,000 slots), rebuilds a category's taxonomy from scratch — supersedes old map rows (delete
*after* the new taxonomy is built and QA'd, never before — see step 4), re-extracts via Pass 1 (official
stores) + Pass 2 (reseller routing), then QA gates + universe refresh across the whole category.
```

Replace with:

```markdown
## Scenario: Full Rebuild

`script/headless_taxonomy.sh` implements two scenarios, auto-selected from live BigQuery state rather than
chosen by the operator — the script itself checks whether any `product_taxonomy_map` rows exist for the
target table and picks accordingly:

- **First run** (0 existing rows): full SKU block (~2,000 slots), rebuilds a category's taxonomy from
  scratch, re-extracts via Pass 1 (official stores) + Pass 2 (reseller routing), then QA gates. This is the
  procedure documented below.
- **Top-up** (existing rows present): the script always re-checks whether the live 95%-cumulative-GMV
  (GWP-zeroed) worklist still has products with no `taxonomy_id`, regardless of `docs/categories/STATUS.md`
  marking the category "complete" — categories accumulate new listings over time. If the live gap is 0, the
  script exits immediately with no SKU claim and no `claude -p` call. If the gap is nonzero, it claims a
  smaller block (sized to the gap, floor 200 / cap 2,000) and works only that live gap via reuse-before-mint
  against the category's existing taxonomy — never a full Pass 1/Pass 2 re-extraction.

The rest of this section describes the first-run procedure.
```

- [ ] **Step 3: Verify both edits**

Run: `grep -n "auto-selected from live BigQuery state" docs/headless-runbook.md`
Expected: one match.

Run: `grep -n "Coverage gaps (products with \`taxonomy_id IS NULL\`) are explicitly out of scope" docs/headless-runbook.md`
Expected: one match.

- [ ] **Step 4: Edit `docs/headless-scripts-flow.md`'s `headless_taxonomy.sh` description**

Find the opening paragraph:

```markdown
## `script/headless_taxonomy.sh` — Full Rebuild

```

Replace with:

```markdown
## `script/headless_taxonomy.sh` — Coverage Closer (Full Rebuild + Top-Up)

Auto-detects scenario from live state before invoking `claude -p`: if the live 95%-cumulative-GMV
(GWP-zeroed) worklist for `<TABLE>` has 0 products with no `taxonomy_id`, the script exits immediately —
no SKU claim, no LLM call, safe to re-run against any category regardless of `docs/categories/STATUS.md`.
Otherwise it picks **first-run** (0 existing `product_taxonomy_map` rows — full Pass 1/Pass 2 rebuild, shown
below) or **top-up** (existing rows present — closes just the live gap via reuse-before-mint, smaller SKU
block sized to the gap).

```

- [ ] **Step 5: Edit `docs/headless-scripts-flow.md`'s `targeted_qa_fix.sh` description**

Find the opening paragraph of the `## \`script/targeted_qa_fix.sh\` — Targeted QA Fix` section (the line
directly under that header, before the `$ ./script/targeted_qa_fix.sh <TABLE>` code block):

```markdown
## `script/targeted_qa_fix.sh` — Targeted QA Fix

```

Replace with:

```markdown
## `script/targeted_qa_fix.sh` — Targeted QA Fix

Scope is existing-row quality defects only (`docs/quality-standards.md` D1–D5, hard gates G1/G2/G3/G5/G6,
`brand_mismatch` review). Coverage gaps (`taxonomy_id IS NULL`) are out of scope for this script — see
`script/headless_taxonomy.sh`'s top-up scenario above.

```

- [ ] **Step 6: Verify both edits**

Run: `grep -n "Coverage Closer (Full Rebuild + Top-Up)" docs/headless-scripts-flow.md`
Expected: one match.

Run: `grep -n "Coverage gaps (\`taxonomy_id IS NULL\`) are out of scope for this script" docs/headless-scripts-flow.md`
Expected: one match.

- [ ] **Step 7: Commit**

```bash
git add docs/headless-runbook.md docs/headless-scripts-flow.md
git commit -m "Document the coverage-vs-quality-fix scope split across both headless scripts"
```

---

### Task 6: Remove stale direct-DML universe-refresh language from `ARCHITECTURE.md` and `docs/product-lifecycle.md`

**Files:**
- Modify: `ARCHITECTURE.md:286-305`
- Modify: `docs/product-lifecycle.md:100-109` (§3 diagram box)
- Modify: `docs/product-lifecycle.md:275-279` (§7 worked example)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: nothing consumed elsewhere — documentation only, closes out the contradiction with
  `ARCHITECTURE.md`'s own line 246.

- [ ] **Step 1: Edit `ARCHITECTURE.md`'s Universe Refresh subsection**

Find:

```markdown
### Universe Refresh

After each category, run targeted DML UPDATE:
```sql
UPDATE marketshare_universe u
SET taxonomy_id = src.taxonomy_id, sku_type_complete = src.canonical_name, ...
FROM (
  SELECT m.product_id, m.master_table, pt.taxonomy_id, pt.canonical_name, ...
  FROM product_taxonomy_map m
  JOIN product_taxonomy pt ON m.taxonomy_id = pt.taxonomy_id
  JOIN niq_category_mapping nm ON nm.master_table = m.master_table
  WHERE nm.master_table = '{table}'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY m.product_id, m.master_table ORDER BY 
    CASE m.source WHEN 'LLM' THEN 0 ELSE 1 END, m.taxonomy_id) = 1
) src
WHERE u.product_id = src.product_id AND u.master_table = src.master_table
  AND u.ecommerce_platform = 'Shopee'
```

See [`docs/runbook.md`](docs/runbook.md) for full refresh script.
```

Replace with:

```markdown
### Universe Refresh

Taxonomy state is never written directly onto `marketshare_universe`/`marketshare_universe_niq` (see the
**Taxonomy columns** note above). A `MERGE` upserts `product_taxonomy_map` × `product_taxonomy` into
`magpie_reference.universe_taxonomy_overlay`, keyed on `(product_id, platform, country)`:

```sql
MERGE `sincere-hearth-273704.magpie_reference.universe_taxonomy_overlay` t
USING (
  SELECT m.product_id, m.platform, m.country, m.master_table,
         pt.taxonomy_id, pt.canonical_name, m.source, m.confidence, m.meta_agent
  FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt ON m.taxonomy_id = pt.taxonomy_id
  WHERE m.master_table = '{table}'
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY m.product_id, m.platform, m.country
    ORDER BY CASE m.source WHEN 'LLM' THEN 0 ELSE 1 END, m.taxonomy_id
  ) = 1
) src
ON t.product_id = src.product_id AND t.platform = src.platform AND t.country = src.country
  AND t.master_table = '{table}'
WHEN MATCHED THEN UPDATE SET
  taxonomy_id = src.taxonomy_id, sku_type_complete = src.canonical_name,
  taxonomy_source = src.source, taxonomy_confidence = src.confidence,
  taxonomy_meta_agent = src.meta_agent, updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED BY SOURCE AND t.master_table = '{table}' THEN DELETE
WHEN NOT MATCHED BY TARGET THEN INSERT
  (product_id, platform, country, master_table, taxonomy_id, sku_type_complete,
   taxonomy_source, taxonomy_confidence, taxonomy_meta_agent, updated_at)
  VALUES (src.product_id, src.platform, src.country, src.master_table, src.taxonomy_id, src.canonical_name,
          src.source, src.confidence, src.meta_agent, CURRENT_TIMESTAMP());
```

Analysts join the overlay to `marketshare_universe` at query time on `(product_id, platform, country)`; the
production table's schema and rows are never altered. See [`docs/headless-runbook.md`](docs/headless-runbook.md)
§ Universe refresh for the authoritative version of this statement (the `AND t.master_table = '{table}'`
condition on the `WHEN NOT MATCHED BY SOURCE` branch is load-bearing — without it BigQuery deletes every
other category's overlay rows too).
```

- [ ] **Step 2: Edit `docs/product-lifecycle.md`'s §3 stage-flow diagram box**

Find:

```
        ▼ UNIVERSE REFRESH (targeted DML UPDATE)                           │
  ┌──────────────────────────────────────────────────────────────────┐   │
  │ Join product_taxonomy_map → product_taxonomy → niq_category_mapping │◄─┘
  │ → product_brand_map → brand_dict                                   │
  │ Stamp onto marketshare_universe: taxonomy_id, sku_type_complete,   │
  │ brand, taxonomy_source/confidence/meta_agent                       │
  │ (LLM beats HUMAN; lower taxonomy_id breaks ties)                   │
  └──────────────────────────────────────────────────────────────────┘   │
```

Replace with:

```
        ▼ UNIVERSE REFRESH (MERGE into overlay table)                      │
  ┌──────────────────────────────────────────────────────────────────┐   │
  │ Join product_taxonomy_map → product_taxonomy → niq_category_mapping │◄─┘
  │ → product_brand_map → brand_dict                                   │
  │ Upsert into universe_taxonomy_overlay: taxonomy_id, sku_type_complete, │
  │ brand, taxonomy_source/confidence/meta_agent                       │
  │ (LLM beats HUMAN; lower taxonomy_id breaks ties)                   │
  │ Joined to marketshare_universe at query time by                    │
  │ (product_id, platform, country) — no columns/rows on               │
  │ marketshare_universe itself change                                 │
  └──────────────────────────────────────────────────────────────────┘   │
```

- [ ] **Step 3: Edit `docs/product-lifecycle.md`'s §7 worked example**

Find:

```markdown
**Universe refresh:**
- DML UPDATE stamps `marketshare_universe`:
  `taxonomy_id = SKU-036021`,
  `sku_type_complete = "Shokubutsu Vacation Series Shower Cream 500ml x2"`,
  `brand = "Shokubutsu"`, `taxonomy_source = LLM`.
```

Replace with:

```markdown
**Universe refresh:**
- A `MERGE` upserts a row into `universe_taxonomy_overlay`:
  `taxonomy_id = SKU-036021`,
  `sku_type_complete = "Shokubutsu Vacation Series Shower Cream 500ml x2"`,
  `taxonomy_source = LLM`. (`brand` still comes from `product_brand_map`/`brand_dict`, unchanged by this
  step — the overlay table only carries taxonomy columns.)
- Analysts get the combined view by joining `universe_taxonomy_overlay` to `marketshare_universe` on
  `(product_id, platform, country)` at query time; `marketshare_universe` itself is never altered.
```

- [ ] **Step 4: Verify all three edits and confirm no stale references remain**

Run: `grep -n "targeted DML UPDATE\|DML UPDATE stamps\|UPDATE marketshare_universe" ARCHITECTURE.md docs/product-lifecycle.md`
Expected: no output (both files clean of the stale pattern).

Run: `grep -n "universe_taxonomy_overlay" ARCHITECTURE.md docs/product-lifecycle.md`
Expected: multiple matches in both files, confirming the overlay pattern is now the documented mechanism in
each.

- [ ] **Step 5: Commit**

```bash
git add ARCHITECTURE.md docs/product-lifecycle.md
git commit -m "Replace stale direct-DML universe-refresh language with the overlay-table MERGE pattern"
```

---

## Post-plan note (not a task)

`docs/categories/th_suncare.md`'s existing `## Targeted QA Fix Brief` (titled "NULL-COVERAGE BACKFILL") is
the concrete case this plan's Task 2/5 carve out of `targeted_qa_fix.sh`'s scope. It is intentionally not
edited by this plan — per the design spec's Open Follow-ups, the next operator working that category should
run `script/headless_taxonomy.sh shopee_th_suncare`'s new top-up scenario instead, and update or remove that
Brief section at that time.
