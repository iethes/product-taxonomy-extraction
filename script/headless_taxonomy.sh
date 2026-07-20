#!/usr/bin/env bash
set -euo pipefail

# Usage: ./script/headless_taxonomy.sh <TABLE> [MONTH] [MAX_TURNS]
# e.g.  ./script/headless_taxonomy.sh shopee_th_conditioner
#       ./script/headless_taxonomy.sh shopee_th_suncare 2026-06        (explicit month instead of live-latest)
#       ./script/headless_taxonomy.sh shopee_th_suncare "" 800         (default month, larger turn budget for a big gap)
#
# MAX_TURNS defaults to 300 if omitted. Raise it for a large live gap you want closed in one session — bulk-first
# processing (see build_topup_prompt) means turn count no longer scales 1:1 with worklist size, but a very large
# gap can still exhaust the default budget partway; that's fine (status='partial'), just re-run to continue.
#
# Auto-detects scenario from live BigQuery state:
#   - gap_count == 0                    -> nothing to do, exit 0, no claude -p call
#   - gap_count > 0, existing_llm_rows == 0  -> scenario=first_run  (no genuine Phase 5 LLM pass yet: Pass 1 + Pass 2 rebuild)
#   - gap_count > 0, existing_llm_rows > 0   -> scenario=top_up     (category already has LLM coverage: close the live gap)
# Note: existing_llm_rows counts source='LLM' rows only — HUMAN keyword-seed rows (present for almost every
# category before Phase 5 ever runs) must not be mistaken for prior LLM coverage.
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

existing_llm_rows_query() {
  local table="$1"
  echo "SELECT COUNT(*) FROM \`${PROJECT}.magpie_reference.product_taxonomy_map\` WHERE master_table = '${table}' AND source = 'LLM'"
}

default_month_query() {
  local table="$1"
  echo "SELECT FORMAT_DATE('%Y-%m', MAX(month)) FROM \`${PROJECT}.master_clean_niq.${table}\`"
}

decide_scenario() {
  local existing_llm_rows="$1"
  if [[ "$existing_llm_rows" =~ ^[0-9]+$ ]] && [[ "$existing_llm_rows" -eq 0 ]]; then
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
Existing HUMAN rows here are normal and expected for a first LLM pass — most categories start with keyword-seed coverage before Phase 5 ever runs; do not treat their presence alone as a blocker. If you find any existing LLM rows, however, that means the wrapper's scenario detection was wrong (a genuine Phase 5 pass already happened on this table) — stop and report the discrepancy in findings rather than silently proceeding as a first run.

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

STEP 5 — Pass 2: the priority for Pass 2 is closing the coverage gap quickly, not per-row precision — quality correctness (exact product_line wording, variant capture, pack-count edge cases, D1-D5 of docs/quality-standards.md) is a separate, later concern owned by script/targeted_qa_fix.sh, scoped by GMV impact; do not spend this session's turns chasing it. Route remaining official-store-unmatched and reseller products in BULK via SQL text-matching of sku_name against the Pass 1 taxonomy you just built — group by brand+line pattern and write statements that map many products per statement, not one row at a time. Only read product images for individual products where text matching is genuinely ambiguous — do not vision-read the full candidate pool. This keyword/text-matching step is a routing convenience, never a scope filter: this keyword gate must never be used to decide whether an individual product gets extracted. Every product in the 95%-cumulative-GMV-or-official-store in-scope set (docs/quality-standards.md §2) must be considered — only your own category/type match-or-create gate (docs/product-lifecycle.md §4.2), applied after reading a product, may conclude it doesn't belong here and leave it NULL. This matters most for high-GMV Mall-seller listings that are genuinely miscategorized (their sku_name doesn't match the category's expected keywords even though the product itself belongs) — a text pre-filter would silently drop them before you ever looked. Hard gates G1 (no dual-mapping), G2 (no HUMAN+LLM coexistence), G4 (no cross-category mapping), and G5 (provenance) are structural invariants and must still pass regardless of this speed-first approach — never skip or relax those.

STEP 6 — For every taxonomy entry, populate product_line, sub_line, and variant as their own structured columns — do NOT leave them NULL while folding that same information into canonical_name as free text. product_line is close to mandatory (populate it whenever a real on-label line name exists, per docs/llm-extraction-rules.md §3); sub_line and variant are optional — populate only where a real signal exists, leave NULL rather than guess when the text doesn't clearly support a split. This was gotten wrong before: 934 entries once shipped with product_line NULL on 100% of them because the extraction wrote good canonical_name text but never decomposed it into the structured fields.

Write via bq query DML only, never the streaming API.

STEP 7 — Before declaring status, self-check using the exact QA-gate queries from docs/headless-runbook.md's QA-gate-as-code section, run with --skip-coexistence semantics (dual-mapped scoped to source='LLM', and placeholder-leak). Report the actual numbers in findings — do not just assert 'gates passed' without the figures.

If you hit a genuine blocker at any step — something wrong with these instructions, missing data, the source table not existing where expected, anything that would make proceeding unsafe — stop, write nothing further, and output status='blocked' with the blockers array populated. That is a valid, expected outcome, not a failure.

Output ONLY this JSON when done, nothing else:
{status: complete|partial|failed|blocked, rows_created, rows_mapped, taxonomy_id_range_used, findings, blockers}.
PROMPT
}

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

STEP 1 — Bulk-first reuse-before-mint. The priority for this session is closing the coverage gap quickly, not per-row precision — quality correctness (exact product_line wording, variant capture, pack-count edge cases, D1-D5 of docs/quality-standards.md) is a separate, later concern: script/targeted_qa_fix.sh is the dedicated follow-up tool for that, scoped by GMV impact. Do not spend this session's turns chasing it.

Do NOT process the live worklist one product at a time — that under-uses this session's budget and is why a prior top-up run on this exact category only resolved 31 of 790 rows (it read one image per product and then self-limited to match this category's older QA History session sizes, which reflect the OLD targeted_qa_fix.sh workflow's smaller 200-slot/30-turn scope, not this scenario's real budget). Instead:
(a) Group the live worklist by brand (via product_brand_map/brand_dict) and by sku_name pattern. Write BULK SQL (INSERT ... SELECT / UPDATE with a JOIN) that maps many matching products to an existing ${table} taxonomy entry in a single statement wherever a clear brand+line+size+pack text match exists (docs/product-lifecycle.md §4's match-or-create decision tree) — reuse-before-mint via bulk text matching, not per-item image verification.
(b) For groups of worklist products that share a brand+line but don't match any existing entry (new size/pack/variant), mint ONE new taxonomy entry per group and map every matching product to it in one bulk statement — never process that group's products one by one.
(c) Only read an individual product's image when text signals (sku_name, product_specification, product_description) are genuinely insufficient to identify brand or product line for minting a new entry. Even then, look for other unresolved worklist rows with a similar sku_name pattern and batch them under the same new entry rather than reading and minting one at a time. This is a routing convenience, never a scope filter: this keyword gate must never be used to decide whether an individual product gets extracted — every product in the live worklist gets considered. Only your own category/type match-or-create gate may conclude a product doesn't belong here and leave it NULL. This matters most for high-GMV Mall-seller listings that are genuinely miscategorized (their sku_name doesn't match the category's expected keywords even though the product itself belongs) — a text pre-filter would silently drop them before you ever looked.
(d) Attempt to resolve the ENTIRE live worklist within your available turn budget this session — do not self-limit to a small sample or match this category's older QA History session sizes. Stop early only when you are genuinely running low on turns, and say so honestly in findings — never as a strategic choice to work only the top of the list.

Hard gates G1 (no dual-mapping), G2 (no HUMAN+LLM coexistence), G4 (no cross-category mapping), and G5 (provenance) are structural invariants and must still pass regardless of this speed-first approach — never skip or relax those.

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

main() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <TABLE> [MONTH] [MAX_TURNS]" >&2
    echo "  e.g. $0 shopee_th_conditioner" >&2
    echo "  e.g. $0 shopee_th_suncare 2026-06        (explicit month instead of live-latest)" >&2
    echo "  e.g. $0 shopee_th_suncare \"\" 800         (default month, larger turn budget for a big gap)" >&2
    exit 1
  fi
  local table="$1"
  local month="${2:-}"
  local max_turns="${3:-300}"

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

  local existing_llm_rows
  existing_llm_rows=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "$(existing_llm_rows_query "$table")" | tail -1)

  local scenario
  scenario=$(decide_scenario "$existing_llm_rows")

  local block_size
  block_size=$(compute_block_size "$scenario" "$gap_count")

  echo "Scenario: ${scenario} (existing_llm_rows=${existing_llm_rows}, gap_count=${gap_count}, block_size=${block_size}, max_turns=${max_turns})"
  echo "TAXONOMY EXTRACTION STARTED"
  echo "==========================="

  local prompt
  if [[ "$scenario" == "first_run" ]]; then
    prompt=$(build_first_run_prompt "$table" "$month" "$block_size")
  else
    prompt=$(build_topup_prompt "$table" "$month" "$block_size" "$gap_count")
  fi

  claude -p --output-format json --permission-mode bypassPermissions --max-turns "$max_turns" "$prompt"

  echo "============================"
  echo "TAXONOMY EXTRACTION FINISHED"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
