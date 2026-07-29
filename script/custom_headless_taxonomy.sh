#!/usr/bin/env bash
set -euo pipefail

# One-off variant of headless_taxonomy.sh for source tables that don't live in master_clean_niq and
# don't match its schema (daily grain, no `month` column, no model_id, no merchant/brand columns).
# Built for: makanananjing (dog food) / makanankucing (cat food) MY daily tables.
#
# Usage: ./script/custom_headless_taxonomy.sh <DATASET> <SOURCE_TABLE> <CATEGORY> [MAX_TURNS]
# e.g.  ./script/custom_headless_taxonomy.sh makanananjing 9_makanananjing_my_daily makanananjing_my
#       ./script/custom_headless_taxonomy.sh makanankucing 9_makanankucing_my_daily makanankucing_my 800
#
# CATEGORY is the master_table value written into product_taxonomy_map / sku_block_registry and the
# docs/categories/${CATEGORY}.md filename — it does NOT have to match SOURCE_TABLE.
#
# Auto-detects scenario from live BigQuery state, same as headless_taxonomy.sh:
#   - gap_count == 0                          -> nothing to do, exit 0, no claude -p call
#   - gap_count > 0, existing_llm_rows == 0    -> scenario=first_run (no category doc yet, full rebuild)
#   - gap_count > 0, existing_llm_rows > 0     -> scenario=top_up (category doc already exists)
# existing_llm_rows counts source='LLM' rows only — HUMAN keyword-seed rows don't count as prior
# LLM coverage.
#
# NOTE: ${DATASET} is outside master_clean_niq — an unconfirmed data path per CLAUDE.md's SKU/QA
# conventions, used here only because this specific table pair was explicitly requested. Don't reuse
# this script for other non-NIQ tables without the same explicit go-ahead.
#
# MAX_TURNS defaults to 300.

PROJECT="sincere-hearth-273704"

worklist_query() {
  local dataset="$1" table="$2" category="$3"
  cat <<SQL
WITH agg AS (
  SELECT
    s.url,
    s.image,
    s.product_id,
    s.ecommerce_platform AS platform,
    s.sku_name,
    COALESCE(s.flag_GWP, FALSE)
      OR REGEXP_CONTAINS(UPPER(s.sku_name), r'\[NOT FOR SALE\]|\[GWP\]') AS flag_GWP,
    SUM(s.gmv_daily) AS gmv_monthly,
    SUM(s.sold_daily) AS sold_monthly,
  FROM \`${PROJECT}.${dataset}.${table}\` s
  WHERE s.country = 'MY'
  GROUP BY 1,2,3,4,5,6
),
base AS (
  SELECT agg.*, pt.canonical_name AS canonical_name
  FROM agg
  LEFT JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` ptm
    ON ptm.product_id = agg.product_id AND ptm.platform = agg.platform AND ptm.master_table = '${category}'
  LEFT JOIN \`${PROJECT}.magpie_reference.product_taxonomy\` pt ON pt.taxonomy_id = ptm.taxonomy_id
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY agg.product_id
    ORDER BY CASE ptm.source WHEN 'LLM' THEN 0 WHEN 'HUMAN' THEN 1 ELSE 2 END, ptm.taxonomy_id ASC
  ) = 1
),
with_cumulative AS (
  SELECT
    *,
    ROUND(
      100.0
      * SUM(CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END) OVER (
          ORDER BY gmv_monthly DESC
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )
      / NULLIF(SUM(CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END) OVER (), 0),
      2
    ) AS cumulative_gmv_pct
  FROM base
)
SELECT *
FROM with_cumulative
WHERE cumulative_gmv_pct <= 95 AND canonical_name IS NULL
ORDER BY gmv_monthly DESC
SQL
}

gap_count_query() {
  local dataset="$1" table="$2" category="$3"
  echo "SELECT COUNT(*) FROM ($(worklist_query "$dataset" "$table" "$category"))"
}

existing_llm_rows_query() {
  local category="$1"
  echo "SELECT COUNT(*) FROM \`${PROJECT}.magpie_reference.product_taxonomy_map\` WHERE master_table = '${category}' AND source = 'LLM'"
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
  local dataset="$1" table="$2" category="$3" block_size="$4"
  local slot_offset=$((block_size - 1))
  local query
  query=$(worklist_query "$dataset" "$table" "$category")
  cat <<PROMPT
Full Rebuild session for a custom (non-NIQ) source table: dataset='${dataset}', table='${table}'.
Write all taxonomy rows under master_table = '${category}' — that identifier, not the source table
name, is what product_taxonomy_map/sku_block_registry/docs/categories use to key this category. No
category context file exists yet for '${category}' — you are creating one as part of this run, not
reading a pre-existing one.

BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/data-dictionary.md,
docs/llm-extraction-rules.md, docs/quality-standards.md, docs/headless-runbook.md,
docs/brand-extraction.md, and docs/categories/_TEMPLATE.md. Note: data-dictionary.md documents
master_clean_niq tables — \`${PROJECT}.${dataset}.${table}\` is NOT in that dataset and has a
different schema (daily grain summed to monthly here, no month/model_id/merchant columns). Treat its
column set as exactly what STEP 0's query below returns, not what data-dictionary.md describes. Also
check docs/categories/STATUS.md to confirm '${category}' hasn't already been completed by someone else
since this prompt was written.

You perform extraction yourself, directly, using your own multimodal reading of product images and
text. You do not invoke external scripts or subprocesses and do not need any API key beyond your own
session auth — CLAUDE.md's ANTHROPIC_API_KEY note is about a different, external pipeline that does
not exist in this repo.

SCOPE DECISION (already made, do not re-litigate or block on it): ecommerce_platform='Tiktok' rows are
IN SCOPE for '${category}' alongside Shopee rows — this category mixes platforms under one
master_table. The worklist query below writes 'platform' into each row and joins product_taxonomy_map
on (product_id, platform) so Shopee and Tiktok products never collide.

KNOWN, ACCEPTED DATA ISSUE (do not fix, do not block on it): Tiktok rows' price/gmv_daily figures in
this source table are corrupted by an inconsistent scale factor and mixed daily/monthly grain, so the
95%-cumulative-GMV ordering is unreliable for Tiktok rows specifically. Proceed with extraction using
the worklist as given anyway — fixing those numbers is a separate upstream data-pipeline problem.

STEP 0 — Verify the source table exists, then get the live worklist (the wrapper's pre-check found 0
existing LLM rows under master_table = '${category}', but re-verify live — this canonical_name IS NULL
filter is what would exclude already-mapped rows, if any exist):
${query}

STEP 1 — Re-verify existing state before assuming this is genuinely a first run:
Run: SELECT source, COUNT(*) FROM \`${PROJECT}.magpie_reference.product_taxonomy_map\`
WHERE master_table = '${category}' GROUP BY source
If you find any existing LLM rows, this script's first-run assumption was wrong — stop and report the
discrepancy in findings rather than silently proceeding.

STEP 2 — Claim your SKU block atomically. Query the real current ceiling first, then use this exact
pattern (DECLARE before BEGIN TRANSACTION — reversing that order is a real BigQuery scripting syntax
error):
BEGIN
  DECLARE next_start INT64;
  BEGIN TRANSACTION;
  SET next_start = (SELECT COALESCE(MAX(block_end), 69000) + 1 FROM \`${PROJECT}.magpie_reference.sku_block_registry\`);
  INSERT INTO \`${PROJECT}.magpie_reference.sku_block_registry\`
    (block_start, block_end, master_table, scenario, claimed_at, status)
  VALUES (next_start, next_start + ${slot_offset}, '${category}', 'custom_full_rebuild', CURRENT_TIMESTAMP(), 'ACTIVE');
  COMMIT TRANSACTION;
END;
Never query MAX(taxonomy_id) directly and assume it's safe to use — the atomic claim against the
registry table is what prevents two sessions colliding on the same ID range.

STEP 3 — Extraction. There is no merchant/brand/official-store data in this source table, so the usual
official-store-allowlist Pass 1 does not apply here. Instead: read sku_name + image for enough products
to identify the real brand/product-line universe, then bulk match-or-create — group the worklist by
brand+line pattern via SQL text-matching on sku_name and write statements that map many products per
statement (INSERT ... SELECT / UPDATE with a JOIN), not one row at a time. Only read images for
individual products where text signals are genuinely ambiguous. This keyword grouping is a routing
convenience, never a scope filter — every product in the STEP 0 worklist must be considered; only your
own category/type match-or-create gate (docs/product-lifecycle.md §4.2), applied after reading a
product, may conclude it doesn't belong here and leave it NULL.

Hard gates G1 (no dual-mapping), G2 (no HUMAN+LLM coexistence), G4 (no cross-category mapping), and G5
(provenance) are structural invariants and must still pass — never skip or relax those.

STEP 4 — For every taxonomy entry, populate product_line, sub_line, and variant as their own
structured columns — do NOT leave them NULL while folding that information into canonical_name as free
text. product_line is close to mandatory (populate whenever a real on-label line name exists); sub_line
and variant are optional — populate only where a real signal exists.

Write via bq query DML only, never the streaming API. Set meta_agent='CLAUDE_CODE' on every row.

STEP 5 — Write docs/categories/${category}.md following _TEMPLATE.md's structure, documenting what you
actually found this session (brand scope, SKU blocks assigned, scale) — this is written post-hoc here
since there's no pre-existing brand/merchant data to research upfront. Then commit it:
git add docs/categories/${category}.md && git commit -m 'Add category context for ${category}, generated during custom Full Rebuild'

STEP 6 — Before declaring status, self-check using the exact QA-gate queries from
docs/headless-runbook.md's QA-gate-as-code section, scoped to master_table = '${category}'. Report the
actual numbers in findings — do not just assert 'gates passed' without the figures.

If you hit a genuine blocker at any step — something wrong with these instructions, missing data, the
source table not existing where expected, anything that would make proceeding unsafe — stop, write
nothing further, and output status='blocked' with the blockers array populated. That is a valid,
expected outcome, not a failure.

Output ONLY this JSON when done, nothing else:
{status: complete|partial|failed|blocked, rows_created, rows_mapped, taxonomy_id_range_used, findings, blockers}.
PROMPT
}

build_topup_prompt() {
  local dataset="$1" table="$2" category="$3" block_size="$4" gap_count="$5"
  local query
  query=$(worklist_query "$dataset" "$table" "$category")
  cat <<PROMPT
Top-up coverage session for a custom (non-NIQ) source table: dataset='${dataset}', table='${table}',
master_table = '${category}'. This category already has taxonomy coverage from a prior run, but the
wrapper's live pre-check just found ${gap_count} products still within the 95%-cumulative-GMV
(GWP-zeroed) threshold with no taxonomy_id under '${category}' — do NOT trust that number as still-
current, re-run the worklist query yourself in STEP 0 below and use its live result as your actual
worklist.

BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/llm-extraction-rules.md,
docs/quality-standards.md, docs/headless-runbook.md, docs/brand-extraction.md, and
docs/categories/${category}.md (the existing category file — its brand scope and scope rules are
already documented there; do not rediscover them from scratch). Note: \`${PROJECT}.${dataset}.${table}\`
is NOT in master_clean_niq and has a different schema (daily grain summed to monthly, no
month/model_id/merchant columns) — treat its column set as exactly what STEP 0's query below returns.

You perform extraction yourself, directly, using your own multimodal reading of product images and
text. You do not invoke external scripts or subprocesses and do not need any API key beyond your own
session auth — CLAUDE.md's ANTHROPIC_API_KEY note is about a different, external pipeline that does
not exist in this repo.

SCOPE DECISION (already made, do not re-litigate or block on it): as of this session,
ecommerce_platform='Tiktok' rows are IN SCOPE for '${category}' alongside the existing Shopee rows —
this is the first category to mix platforms under one master_table. The worklist query below writes
'platform' into each row and joins product_taxonomy_map on (product_id, platform) precisely so Shopee
and Tiktok products never collide. If ${category}.md still describes this category as Shopee-only,
that text is stale — treat Tiktok as in scope regardless, and feel free to update that section in STEP
4 while you're in the file for QA History.

KNOWN, ACCEPTED DATA ISSUE (do not fix, do not block on it): Tiktok rows' price/gmv_daily figures in
this source table are corrupted by an inconsistent scale factor and mixed daily/monthly grain. This
means the worklist's 95%-cumulative-GMV ordering and gmv_monthly figures are unreliable for Tiktok rows
specifically. Proceed with extraction using the worklist as given anyway — correctness of the GMV
numbers is a separate upstream data-pipeline problem, out of scope for this session.

Known pitfall from prior sessions: \`bq query\` silently truncates displayed results to 100 rows unless
you pass --max_rows=100000 or --format=csv — always use one of those on the STEP 0 query below, and
sanity-check the row count against what you expect rather than assuming a short result means a short
true set.

STEP 0 — Get the live worklist (do not trust any number in this prompt or in ${category}.md):
${query}

STEP 1 — Bulk-first reuse-before-mint. The priority for this session is closing the coverage gap
quickly, not per-row precision — quality correctness (exact product_line wording, variant capture,
pack-count edge cases) is a separate, later concern. Do NOT process the live worklist one product at a
time. Instead:
(a) Group the live worklist by sku_name pattern (brand+line). Write BULK SQL (INSERT ... SELECT /
UPDATE with a JOIN) that maps many matching products to an existing ${category} taxonomy entry in a
single statement wherever a clear brand+line+size/pack text match exists (docs/product-lifecycle.md
§4's match-or-create decision tree) — reuse-before-mint via bulk text matching, not per-item image
verification.
(b) For groups of worklist products that share a brand+line but don't match any existing entry (new
size/pack/variant), mint ONE new taxonomy entry per group and map every matching product to it in one
bulk statement — never process that group's products one by one.
(c) Only read an individual product's image when text signals (sku_name) are genuinely insufficient to
identify brand or product line for minting a new entry. Even then, look for other unresolved worklist
rows with a similar sku_name pattern and batch them under the same new entry rather than reading and
minting one at a time. This is a routing convenience, never a scope filter — every product in the live
worklist gets considered; only your own category/type match-or-create gate may conclude a product
doesn't belong here and leave it NULL.
(d) Attempt to resolve the ENTIRE live worklist within your available turn budget this session — do not
self-limit to a small sample. Stop early only when genuinely running low on turns, and say so honestly
in findings.

Hard gates G1 (no dual-mapping), G2 (no HUMAN+LLM coexistence), G4 (no cross-category mapping), and G5
(provenance) are structural invariants and must still pass regardless of this speed-first approach —
never skip or relax those.

STEP 2 — Claim a ${block_size}-slot SKU block atomically (DECLARE before BEGIN TRANSACTION — reversing
that order is a real BigQuery scripting syntax error):
BEGIN
  DECLARE next_start INT64;
  BEGIN TRANSACTION;
  SET next_start = (SELECT COALESCE(MAX(block_end), 69000) + 1 FROM \`${PROJECT}.magpie_reference.sku_block_registry\`);
  INSERT INTO \`${PROJECT}.magpie_reference.sku_block_registry\`
    (block_start, block_end, master_table, scenario, claimed_at, status)
  VALUES (next_start, next_start + ${block_size} - 1, '${category}', 'custom_topup', CURRENT_TIMESTAMP(), 'ACTIVE');
  COMMIT TRANSACTION;
END;
Never query MAX(taxonomy_id) directly and assume it's safe to use — this atomic claim against the
registry table is what prevents two sessions colliding on the same ID range.

STEP 3 — Write via bq query DML only, never the streaming API. Set meta_agent='CLAUDE_CODE' on every
row you write. Never delete an existing row.

STEP 4 — Append a dated row to ${category}.md's '## QA History' table (columns: Date | Pass | Finding |
Resolution) summarizing what you did and found this session. Commit the updated file:
git add docs/categories/${category}.md && git commit -m 'Top-up coverage session for ${category}: update QA History'

STEP 5 — Before declaring status, self-check using the exact QA-gate queries from
docs/headless-runbook.md's QA-gate-as-code section, run WITHOUT --skip-coexistence (HUMAN+LLM
coexistence should be a genuine bug at this point, not an expected mid-rebuild state, since this
category already shipped once), scoped to master_table = '${category}'. Report the actual numbers in
findings.

Do NOT run the universe refresh yourself — that is a separate step, run only after independent QA
verification, not something this session does.

If you hit a genuine blocker at any step — something wrong with these instructions, missing data,
anything that would make proceeding unsafe — stop, write nothing further, and output status='blocked'
with the blockers array populated. That is a valid, expected outcome, not a failure.

Output ONLY this JSON when done, nothing else:
{status: complete|partial|failed|blocked, rows_created, rows_mapped, taxonomy_id_range_used, findings, blockers}.
PROMPT
}

main() {
  if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <DATASET> <SOURCE_TABLE> <CATEGORY> [MAX_TURNS]" >&2
    echo "  e.g. $0 makanananjing 9_makanananjing_my_daily makanananjing_my" >&2
    echo "  e.g. $0 makanankucing 9_makanankucing_my_daily makanankucing_my 800" >&2
    exit 1
  fi
  local dataset="$1" table="$2" category="$3"
  local max_turns="${4:-300}"

  echo "${dataset}.${table} -> category=${category}"

  local gap_count
  gap_count=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "$(gap_count_query "$dataset" "$table" "$category")" | tail -1)

  if [[ "$gap_count" == "0" ]]; then
    echo "No in-scope coverage gap for ${dataset}.${table} (category=${category}) — nothing to do."
    exit 0
  fi

  local existing_llm_rows
  existing_llm_rows=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "$(existing_llm_rows_query "$category")" | tail -1)

  local scenario
  scenario=$(decide_scenario "$existing_llm_rows")

  local block_size
  block_size=$(compute_block_size "$scenario" "$gap_count")

  echo "Scenario: ${scenario} (existing_llm_rows=${existing_llm_rows}, gap_count=${gap_count}, block_size=${block_size}, max_turns=${max_turns})"
  echo "TAXONOMY EXTRACTION STARTED"
  echo "==========================="

  local prompt
  if [[ "$scenario" == "first_run" ]]; then
    prompt=$(build_first_run_prompt "$dataset" "$table" "$category" "$block_size")
  else
    prompt=$(build_topup_prompt "$dataset" "$table" "$category" "$block_size" "$gap_count")
  fi

  claude -p --output-format json --permission-mode bypassPermissions --max-turns "$max_turns" "$prompt"

  echo "============================"
  echo "TAXONOMY EXTRACTION FINISHED"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
