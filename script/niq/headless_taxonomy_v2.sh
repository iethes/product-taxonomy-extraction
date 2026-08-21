#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

# Usage: ./script/niq/headless_taxonomy_v2.sh <TABLE> [MONTH] [MAX_TURNS]
# Same scenario auto-detection as headless_taxonomy.sh (V1), but the worklist -- for BOTH scenarios -- is
# fully pre-built by script/niq/headless_v2_worklist.py before claude -p is ever invoked, with each product
# enriched with up to 5 reference candidates pulled from this table AND fuzzy-matched sibling category
# tables in other countries. See
# docs/superpowers/specs/2026-08-21-headless-taxonomy-v2-cross-market-candidates-design.md.
#
# V1 (headless_taxonomy.sh) is unmodified and still works exactly as before -- this is a new sibling script,
# not a replacement.

PROJECT="sincere-hearth-273704"

gap_count_query() {
  local table="$1" month="$2"
  cat <<SQL
SELECT COUNT(*) FROM (
  SELECT s.product_id
  FROM \`${PROJECT}.master_clean_niq.${table}\` s
  LEFT JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` ptm
    ON ptm.product_id = s.product_id AND ptm.master_table = '${table}'
  LEFT JOIN \`${PROJECT}.magpie_reference.product_taxonomy\` pt ON pt.taxonomy_id = ptm.taxonomy_id
  LEFT JOIN \`${PROJECT}.magpie_reference.category_scope_exceptions\` exc
    ON exc.product_id = s.product_id AND exc.master_table = '${table}'
  WHERE FORMAT_DATE('%Y-%m', s.month) = '${month}' AND pt.canonical_name IS NULL AND exc.product_id IS NULL
)
SQL
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

build_first_run_prompt_v2() {
  local table="$1" month="$2" block_size="$3" cross_market_json="$4"
  local slot_offset=$((block_size - 1))
  cat <<PROMPT
Full Rebuild session (V2) for ${table}, month ${month}. This is a first-run invocation — the wrapper's live
pre-check found 0 existing \`product_taxonomy_map\` rows for this table. No category context file exists yet
for this table — you are creating one as part of this run, not reading a pre-existing one.

BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/data-dictionary.md, docs/llm-extraction-rules.md, docs/quality-standards.md, docs/headless-runbook.md, docs/brand-extraction.md, and docs/categories/_TEMPLATE.md (the last one because you are about to fill it in — not in the original doc list, but required for this run specifically). Also run: SELECT status, updated_at FROM \`${PROJECT}.magpie_reference.category_brief\` WHERE category_key = 'master_clean_niq.${table}' AND task_type = 'BRIEF' to confirm ${table} hasn't already been completed by someone else since this prompt was written. No row, or a row with status IN ('not_started', 'reset_pending_redo'), means proceeding as a first run is still correct.

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
- Official Store Allowlist: query DISTINCT merchant_name WHERE merchant_badge = 'Shopee Mall', per brand in scope. Exclude known multi-brand retailers per docs/llm-extraction-rules.md §4 (Sasa, Watsons, Boots, BEAUTRIUM, Tsuruha for beauty; BigC, Lotuss, Tops, Villa Market for grocery; check the full list in that doc for this category's vertical). Note parent-company stores (P&G, Unilever, Lion-style) as Pass-1-eligible for all brands they carry, not excluded as multi-brand. **This exact table is what a later V2 top-up/re-run session's worklist builder parses out of your markdown to exclude Pass-1-covered products from its candidate pool — keep it a real, well-formed markdown table (Brand | brand_id | Official Store Merchant Name columns, backtick-wrapped merchant names), not free text.**
- Scale: total row count, official-store row count, distinct product count. If official-store row count alone is large (tens of thousands+), say so explicitly — Pass 1 must still scope to the allowlist only, not the full Mall-badged pool.
- Existing map rows (from Step 1): document the real counts, not an assumption.
- Write your markdown to a local BRIEF row in \`${PROJECT}.magpie_reference.category_brief\` — never inline the markdown into a SQL string literal (it will contain backticks, quotes, and pipe characters that break a literal). Instead:
  1. Write it to /tmp/${table}_brief.ndjson as a single-line JSON object: {"category_key": "master_clean_niq.${table}", "task_type": "BRIEF", "source_dataset": "master_clean_niq", "master_table": "${table}", "country": "<2-3 letter country code parsed from ${table}>", "status": "active", "brief_markdown": "<your full markdown, JSON-string-escaped>", "updated_at": "<CURRENT_TIMESTAMP in ISO 8601 UTC>", "meta_agent": "CLAUDE_CODE"}
  2. Load it into a staging table: bq load --source_format=NEWLINE_DELIMITED_JSON --replace \`${PROJECT}:magpie_reference._stage_category_brief_${table}\` /tmp/${table}_brief.ndjson category_key:STRING,task_type:STRING,source_dataset:STRING,master_table:STRING,country:STRING,status:STRING,brief_markdown:STRING,updated_at:TIMESTAMP,meta_agent:STRING
  3. Merge it in: bq query --use_legacy_sql=false "MERGE \`${PROJECT}.magpie_reference.category_brief\` t USING \`${PROJECT}.magpie_reference._stage_category_brief_${table}\` s ON t.category_key = s.category_key AND t.task_type = 'BRIEF' WHEN MATCHED THEN UPDATE SET source_dataset=s.source_dataset, master_table=s.master_table, country=s.country, status=s.status, brief_markdown=s.brief_markdown, updated_at=s.updated_at, meta_agent=s.meta_agent WHEN NOT MATCHED THEN INSERT (category_key, task_type, source_dataset, master_table, country, status, brief_markdown, updated_at, meta_agent) VALUES (s.category_key, s.task_type, s.source_dataset, s.master_table, s.country, s.status, s.brief_markdown, s.updated_at, s.meta_agent)"
  4. Drop the staging table: bq rm -f -t \`${PROJECT}:magpie_reference._stage_category_brief_${table}\`
  Never use the streaming API (insert_rows_json) for this — CLAUDE.md's 90-minute streaming buffer rule.

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

STEP 5 — Pass 2: the priority for Pass 2 is closing the coverage gap quickly, not per-row precision — quality correctness (exact product_line wording, variant capture, pack-count edge cases, D1-D5 of docs/quality-standards.md) is a separate, later concern owned by script/targeted_qa_fix.sh, scoped by GMV impact; do not spend this session's turns chasing it.

Below is your pre-fetched, GMV-sorted candidate pool for Pass 2 — every non-official-store product in the 95%-cumulative-GMV in-scope set, each enriched with up to 5 reference candidates pulled from OTHER already-QA'd category tables in different countries (this table has zero taxonomy entries at precompute time by definition, so every candidate here is cross-market — "source_table" names which sibling table it came from). These candidates are pattern/format reference only — how a same-brand product was typically split into product_line/sub_line/variant/size/pack_count in a sibling market — never a direct map target. A candidate's taxonomy_id belongs to a different country's category table; never write a product_taxonomy_map row pointing at it. Use it to inform how you mint or match against the entries YOUR Pass 1 just built in THIS session, not as a routing shortcut. Every product below is still subject to your own category/type match-or-create gate (docs/product-lifecycle.md §4.2) — a cross-market candidate never overrides that:

${cross_market_json}

Route these products in BULK via SQL text-matching of sku_name against the Pass 1 taxonomy you just built — group by brand+line pattern and write statements that map many products per statement, not one row at a time. Only read product images for individual products where text matching is genuinely ambiguous — do not vision-read the full candidate pool. This keyword/text-matching step is a routing convenience, never a scope filter: this keyword gate must never be used to decide whether an individual product gets extracted. Every product in the 95%-cumulative-GMV-or-official-store in-scope set (docs/quality-standards.md §2) must be considered — only your own category/type match-or-create gate (docs/product-lifecycle.md §4.2), applied after reading a product, may conclude it doesn't belong here and leave it NULL. This matters most for high-GMV Mall-seller listings that are genuinely miscategorized (their sku_name doesn't match the category's expected keywords even though the product itself belongs) — a text pre-filter would silently drop them before you ever looked. Hard gates G1 (no dual-mapping), G2 (no HUMAN+LLM coexistence), G4 (no cross-category mapping), and G5 (provenance) are structural invariants and must still pass regardless of this speed-first approach — never skip or relax those.

When your match-or-create gate concludes a product genuinely doesn't belong in this category — wrong product type, not a size/variant/pack ambiguity — don't just leave it NULL and move on: record that determination in bulk (one statement per reason-group, not per row) so it stops re-entering every future session's live worklist and coverage-gap count:
INSERT INTO \`${PROJECT}.magpie_reference.category_scope_exceptions\` (master_table, product_id, reason, confirmed_at, meta_agent)
SELECT '${table}', new_id, '<why it does not belong, e.g. wrong product type: cocoa powder listed under this liquid-milk table>', CURRENT_TIMESTAMP(), 'CLAUDE_CODE'
FROM UNNEST(['<product_id>', '<product_id>']) AS new_id  -- product_id is STRING — quote every element
WHERE new_id NOT IN (SELECT product_id FROM \`${PROJECT}.magpie_reference.category_scope_exceptions\` WHERE master_table = '${table}');
Only use this for products you are confident are the wrong type/category for this table — never for ones you simply didn't get to this session, and never to paper over a real coverage shortfall.

STEP 6 — For every taxonomy entry, populate product_line, sub_line, and variant as their own structured columns — do NOT leave them NULL while folding that same information into canonical_name as free text. product_line is close to mandatory (populate it whenever a real on-label line name exists, per docs/llm-extraction-rules.md §3); sub_line and variant are optional — populate only where a real signal exists, leave NULL rather than guess when the text doesn't clearly support a split. This was gotten wrong before: 934 entries once shipped with product_line NULL on 100% of them because the extraction wrote good canonical_name text but never decomposed it into the structured fields.

Write via bq query DML only, never the streaming API.

STEP 7 — Before declaring status, self-check using the exact QA-gate queries from docs/headless-runbook.md's QA-gate-as-code section, run with --skip-coexistence semantics (dual-mapped scoped to source='LLM', and placeholder-leak). Report the actual numbers in findings — do not just assert 'gates passed' without the figures.

If you hit a genuine blocker at any step — something wrong with these instructions, missing data, the source table not existing where expected, anything that would make proceeding unsafe — stop, write nothing further, and output status='blocked' with the blockers array populated. That is a valid, expected outcome, not a failure.

Output ONLY this JSON when done, nothing else:
{status: complete|partial|failed|blocked, rows_created, rows_mapped, taxonomy_id_range_used, findings, blockers}.
PROMPT
}

build_topup_prompt_v2() {
  local table="$1" month="$2" block_size="$3" gap_count="$4" worklist_json="$5"
  local slot_offset=$((block_size - 1))
  cat <<PROMPT
Top-up coverage session (V2) for ${table}, month ${month}. This category already has taxonomy coverage from a
prior run — the wrapper's live pre-check just found ${gap_count} products still within the 95%-cumulative-GMV
(GWP-zeroed) threshold with no taxonomy_id. Unlike V1, this number and the worklist itself are NOT something
you re-query yourself — both are pre-fetched below, GMV-sorted highest-priority-first.

BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/llm-extraction-rules.md, docs/quality-standards.md, docs/headless-runbook.md, docs/brand-extraction.md, and the existing category brief — run: SELECT brief_markdown FROM \`${PROJECT}.magpie_reference.category_brief\` WHERE category_key = 'master_clean_niq.${table}' AND task_type = 'BRIEF' (its brand scope, official store allowlist, and scope rules are already documented there; do not rediscover them from scratch).

You perform extraction yourself, directly, using your own multimodal reading of product images and text. You do not invoke external scripts or subprocesses and do not need any API key beyond your own session auth — CLAUDE.md's ANTHROPIC_API_KEY note is about a different, external pipeline that does not exist in this repo.

STEP 0 — Your worklist, pre-fetched below (do not re-run STEP 0's SQL yourself — this IS the live worklist, already pulled fresh by the wrapper's Python builder before this session started). Each product carries up to 5 reference candidates, ranked by text similarity, each tagged with a source_table and a match_tier:
- "source_table" equal to '${table}' itself = a direct reuse candidate, an existing entry in THIS category you can map straight to if it's a genuine match.
- "source_table" from a different table = a cross-market candidate (sibling category, different country). Pattern/format reference only — never map a product directly to a cross-market taxonomy_id.
- "match_tier": "brand_match" means the candidate shares a resolved brand_id with this product (stronger signal); "text_only" means no brand could be resolved and it's ranked by raw text similarity alone (weaker — verify more carefully).
Never trust a candidate without checking sku_name/image yourself when there's any doubt — these are reference context, never a basis for an autonomous decision.

${worklist_json}

STEP 1 — Bulk-first reuse-before-mint. The priority for this session is closing the coverage gap quickly, not per-row precision — quality correctness (exact product_line wording, variant capture, pack-count edge cases, D1-D5 of docs/quality-standards.md) is a separate, later concern: script/targeted_qa_fix.sh is the dedicated follow-up tool for that, scoped by GMV impact. Do not spend this session's turns chasing it.

Do NOT process the live worklist one product at a time — that under-uses this session's budget. Instead:
(a) For each worklist product, check its pre-attached candidates first. If an in-table candidate (source_table == '${table}') is an unambiguous match — same brand+line+size+pack, confirmed via sku_name/image if there's any doubt — bulk-map it: group worklist products by their matched candidate's taxonomy_id and write ONE UPDATE/INSERT per taxonomy_id covering every matching product, never per-row. Cross-market candidates never resolve a match directly — they inform (b) below.
(b) For worklist products with no unambiguous in-table candidate: group by brand+line pattern (via product_brand_map/brand_dict and sku_name) and mint ONE new taxonomy entry per group, mapping every matching product to it in one bulk statement — never process that group's products one by one. Use any cross-market candidates attached to these products as pattern/format reference (how was this brand/line typically split into product_line/sub_line/variant/size/pack_count in a sibling market) to keep your new entry's structure consistent with the sibling market's, not as something to copy the taxonomy_id from.
(c) Only read an individual product's image when text signals (sku_name, product_specification, product_description) are genuinely insufficient to identify brand or product line for minting a new entry. Even then, look for other unresolved worklist rows with a similar sku_name pattern and batch them under the same new entry rather than reading and minting one at a time. This is a routing convenience, never a scope filter: this keyword gate must never be used to decide whether an individual product gets extracted — every product in the live worklist gets considered. Only your own category/type match-or-create gate may conclude a product doesn't belong here and leave it NULL. This matters most for high-GMV Mall-seller listings that are genuinely miscategorized (their sku_name doesn't match the category's expected keywords even though the product itself belongs) — a text pre-filter would silently drop them before you ever looked.
(d) Attempt to resolve the ENTIRE live worklist within your available turn budget this session — do not self-limit to a small sample or match this category's older QA History session sizes. Stop early only when you are genuinely running low on turns, and say so honestly in findings — never as a strategic choice to work only the top of the list.
(e) When your match-or-create gate concludes a product genuinely doesn't belong in this category — wrong product type, not a size/variant/pack ambiguity — don't just leave it NULL and move on: record that determination in bulk (one statement per reason-group, not per row) so it stops re-entering every future session's live worklist and coverage-gap count:
INSERT INTO \`${PROJECT}.magpie_reference.category_scope_exceptions\` (master_table, product_id, reason, confirmed_at, meta_agent)
SELECT '${table}', new_id, '<why it does not belong, e.g. wrong product type: anti-hair-loss tonic listed under this conditioner table>', CURRENT_TIMESTAMP(), 'CLAUDE_CODE'
FROM UNNEST(['<product_id>', '<product_id>']) AS new_id  -- product_id is STRING — quote every element
WHERE new_id NOT IN (SELECT product_id FROM \`${PROJECT}.magpie_reference.category_scope_exceptions\` WHERE master_table = '${table}');
Only use this for products you are confident are the wrong type/category for this table — never for ones you simply didn't get to this session, and never to paper over a real coverage shortfall. If the scope call itself is genuinely ambiguous (could plausibly belong depending on a judgment call, not a clear-cut wrong type), don't except it — leave it NULL and escalate the ambiguity in findings instead, same as before.

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

STEP 3 — Write via bq query DML only, never the streaming API. Set meta_agent='CLAUDE_CODE' on every row you write or update. Never delete an existing row.

STEP 4 — Record a dated run-log entry summarizing what you did and found this session, via a single parameterized INSERT (never build the SQL string by concatenating your own finding text into it directly — that breaks on quotes/backticks; use --parameter so bq handles escaping):
bq query --use_legacy_sql=false --project_id=${PROJECT} \
  --parameter="category_key:STRING:master_clean_niq.${table}" \
  --parameter="task_date:DATE:<today, YYYY-MM-DD>" \
  --parameter="brief_markdown:STRING:<your summary of what you did and found this session>" \
  "INSERT INTO \`${PROJECT}.magpie_reference.category_brief\` (category_key, task_type, task_date, brief_markdown, updated_at, meta_agent) VALUES (@category_key, 'TAXONOMY', @task_date, @brief_markdown, CURRENT_TIMESTAMP(), 'CLAUDE_CODE')"

STEP 5 — Before declaring status, self-check using the exact QA-gate queries from docs/headless-runbook.md's QA-gate-as-code section, run WITHOUT --skip-coexistence (HUMAN+LLM coexistence should be a genuine bug at this point, not an expected mid-rebuild state, since this category already shipped once). Report the actual numbers in findings.

Do NOT run the universe refresh yourself — that is a separate step, run only after independent QA verification, not something this session does.

If you hit a genuine blocker at any step — something wrong with these instructions, missing data, anything that would make proceeding unsafe — stop, write nothing further, and output status='blocked' with the blockers array populated. That is a valid, expected outcome, not a failure.

Output ONLY this JSON when done, nothing else:
{status: complete|partial|failed|blocked, rows_created, rows_mapped, taxonomy_id_range_used, findings, blockers}.
PROMPT
}

extract_json_object() {
  local text="$1"
  printf '%s' "$text" | grep -Pzo '(?s)\{.*\}' | tr -d '\0'
}

decide_queue_signal() {
  local claude_output="$1"
  local result_json
  result_json=$(echo "$claude_output" | jq -r '.result // empty') || result_json=""
  if [[ -z "$result_json" ]]; then
    echo "FAILED"
    return
  fi
  if ! echo "$result_json" | jq -e . >/dev/null 2>&1; then
    local extracted
    extracted=$(extract_json_object "$result_json")
    if [[ -n "$extracted" ]] && echo "$extracted" | jq -e . >/dev/null 2>&1; then
      result_json="$extracted"
    fi
  fi
  local status
  status=$(echo "$result_json" | jq -r '.status // empty' 2>/dev/null) || status=""
  case "$status" in
    blocked) echo "BLOCKED" ;;
    complete|partial) echo "DONE" ;;
    *) echo "FAILED" ;;
  esac
}

main() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <TABLE> [MONTH] [MAX_TURNS]" >&2
    exit 1
  fi
  local table="$1"
  local month="${2:-}"
  local max_turns="${3:-300}"

  if [[ -z "$month" ]]; then
    month=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
      "$(default_month_query "$table")" | tail -1)
  fi

  log INFO "Processing table: ${table}"
  log INFO "Resolved month: ${month}"

  local gap_count
  gap_count=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "$(gap_count_query "$table" "$month")" | tail -1)

  if [[ "$gap_count" == "0" ]]; then
    log INFO "No in-scope coverage gap for ${table}/${month} — nothing to do."
    echo "QUEUE_SIGNAL: NOTHING_TO_DO"
    emit_result "$table" "NOTHING_TO_DO" "No in-scope coverage gap for ${table}/${month}"
    exit 0
  fi

  local existing_llm_rows
  existing_llm_rows=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "$(existing_llm_rows_query "$table")" | tail -1)

  local scenario
  scenario=$(decide_scenario "$existing_llm_rows")

  local block_size
  block_size=$(compute_block_size "$scenario" "$gap_count")

  log INFO "Scenario: ${scenario} (existing_llm_rows=${existing_llm_rows}, gap_count=${gap_count}, block_size=${block_size}, max_turns=${max_turns})"
  log INFO "Building candidate-enriched worklist for ${table}..."

  local worklist_json
  worklist_json=$(python3 script/niq/headless_v2_worklist.py --table "$table" --scenario "$scenario" --month "$month" --block-size "$block_size")

  if [[ "$worklist_json" == "[]" ]]; then
    log INFO "No worklist products for ${table} after candidate build — nothing to do."
    echo "QUEUE_SIGNAL: NOTHING_TO_DO"
    emit_result "$table" "NOTHING_TO_DO" "No worklist products for ${table} after candidate build"
    exit 0
  fi

  log INFO "TAXONOMY EXTRACTION STARTED (V2, scenario=${scenario})"

  local prompt
  if [[ "$scenario" == "first_run" ]]; then
    prompt=$(build_first_run_prompt_v2 "$table" "$month" "$block_size" "$worklist_json")
  else
    prompt=$(build_topup_prompt_v2 "$table" "$month" "$block_size" "$gap_count" "$worklist_json")
  fi

  local claude_output
  # Piped via stdin, not passed as a CLI argument: this prompt embeds the full candidate-enriched worklist
  # JSON and can exceed the kernel's argv size limit (E2BIG) well before it gets near a real token-budget
  # concern — same reasoning as targeted_qa_fix_v2.sh.
  claude_output=$(claude -p --output-format json --permission-mode bypassPermissions --max-turns "$max_turns" <<< "$prompt")
  echo "$claude_output"

  log INFO "TAXONOMY EXTRACTION FINISHED (V2)"
  local signal
  signal=$(decide_queue_signal "$claude_output")
  echo "QUEUE_SIGNAL: ${signal}"
  emit_result "$table" "$signal" "Taxonomy extraction v2 finished" "max_turns=${max_turns}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
