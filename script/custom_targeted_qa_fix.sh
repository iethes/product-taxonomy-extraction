#!/usr/bin/env bash
set -euo pipefail

# One-off variant of targeted_qa_fix.sh for categories built from custom (non-NIQ) source tables —
# same DATASET/SOURCE_TABLE/CATEGORY split as script/custom_headless_taxonomy.sh. Built for:
# makanananjing (dog food) / makanankucing (cat food) MY daily tables.
#
# Usage: ./script/custom_targeted_qa_fix.sh <DATASET> <SOURCE_TABLE> <CATEGORY> [BLOCK_SIZE] [MAX_TURNS]
# e.g.  ./script/custom_targeted_qa_fix.sh makanankucing 9_makanankucing_my_daily makanankucing_my
#       ./script/custom_targeted_qa_fix.sh makanananjing 9_makanananjing_my_daily makanananjing_my 200 600
#
# CATEGORY is the master_table value in product_taxonomy_map / sku_block_registry and the
# docs/categories/${CATEGORY}.md filename — it does NOT have to match SOURCE_TABLE. All
# product_taxonomy / product_taxonomy_map / sku_block_registry access is generic (keyed on
# master_table) so this script reuses script/qa_report.sh and script/qa_coverage_report.sh
# unmodified. Only the prompts' own STEP 2b/2c/3 sku_name+gmv lookups, which join the raw source
# table, need the DATASET/SOURCE_TABLE swapped in for master_clean_niq.
#
# `${DATASET}.${SOURCE_TABLE}` mixes ecommerce_platform IN ('Shopee', 'Tiktok') and is a known,
# accepted state (see docs/categories/${CATEGORY}.md) — product_taxonomy_map carries a `platform`
# column precisely so this doesn't collide. Tiktok rows' price/gmv_daily figures are known-corrupted
# (inconsistent scale factor, mixed daily/monthly grain) — do not attempt to fix that here.
#
# Same two modes as targeted_qa_fix.sh, chosen automatically per category file:
#   - Brief mode: docs/categories/<category>.md has a filled-in '## Targeted QA Fix Brief' section.
#   - Auto-discovery mode (default otherwise): reviews product_taxonomy entries the category hasn't
#     confidently reviewed yet (product_taxonomy._meta), fixes what it finds wrong.
#
# BLOCK_SIZE defaults to 200, MAX_TURNS defaults to 300.

PROJECT="sincere-hearth-273704"

has_real_brief() {
  local brief_markdown="$1"
  local brief_line
  brief_line=$(grep -n "^## Targeted QA Fix Brief" <<< "$brief_markdown" | head -1 | cut -d: -f1)
  if [[ -z "$brief_line" ]]; then
    echo "false"
    return
  fi
  # custom_headless_taxonomy.sh writes this section post-hoc (STEP 5) as a punch list of future
  # scope, not a ready-to-execute brief — every custom category doc (makanananjing_my/sg,
  # makanankucing_my/sg) opens the section with this exact disclaimer. Without this check, a
  # non-templated Verdict line still reads as "real", so brief mode picks a Brief full of items this
  # script structurally can't do (NULL-coverage backfill, cross-master_table re-routing, no enumerated
  # rows) and burns a whole session declaring status=blocked instead of falling through to
  # auto-discovery, which has real work waiting.
  local section
  section=$(awk -v start="$brief_line" 'NR > start && /^## / { exit } NR >= start { print }' <<< "$brief_markdown")
  # Extended 2026-08-01 (see targeted_qa_fix.sh's matching check) to also catch "not yet assessed" /
  # "none written yet" deferral disclaimers, the same underlying pattern found on the NIQ-source side.
  if grep -qiE "not executed this session|not yet assessed|none written yet" <<< "$section"; then
    echo "false"
    return
  fi
  local verdict_line
  verdict_line=$(grep "^\*\*Verdict:\*\*" <<< "$section" | head -1)
  if [[ -z "$verdict_line" ]] || [[ "$verdict_line" == *"{"* ]]; then
    echo "false"
  else
    echo "true"
  fi
}

category_key_for() {
  local dataset="$1" category="$2"
  echo "${dataset}.${category}"
}

fetch_brief_markdown_query() {
  local category_key="$1"
  echo "SELECT brief_markdown FROM \`${PROJECT}.magpie_reference.category_brief\` WHERE category_key = '${category_key}' AND task_type = 'BRIEF'"
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

review_worklist_count_query() {
  local category="$1"
  cat <<SQL
SELECT COUNT(DISTINCT pt.taxonomy_id)
FROM \`${PROJECT}.magpie_reference.product_taxonomy\` pt
JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
WHERE m.master_table = '${category}'
  AND (pt._meta IS NULL OR IFNULL(JSON_VALUE(pt._meta, '\$.review_confidence'), 'unreviewed') != 'confident')
SQL
}

scope_note() {
  local dataset="$1" table="$2"
  cat <<NOTE
SCOPE DECISION (already made, do not re-litigate or block on it): \`${PROJECT}.${dataset}.${table}\`
mixes ecommerce_platform IN ('Shopee', 'Tiktok') — both are in scope. product_taxonomy_map carries a
'platform' column precisely so Shopee and Tiktok products never collide; any query you write against
this source table that joins back to product_taxonomy_map should match on (product_id, platform), not
product_id alone.

KNOWN, ACCEPTED DATA ISSUE (do not fix, do not block on it): Tiktok rows' price/gmv_daily figures in
this source table are corrupted by an inconsistent scale factor and mixed daily/monthly grain. Any
GMV-based prioritization or ranking you compute is unreliable for Tiktok rows specifically — usable
for relative ordering within Shopee, not trustworthy across platforms. Fixing those numbers is a
separate upstream data-pipeline problem, out of scope for this session.
NOTE
}

build_prompt() {
  local dataset="$1" table="$2" category="$3" category_key="$4" block_size="${5:-200}" gate_report="${6:-}"
  local slot_offset=$((block_size - 1))
  local scope
  scope=$(scope_note "$dataset" "$table")
  cat <<PROMPT
Targeted QA Fix session for master_table='${category}' (custom source: \`${PROJECT}.${dataset}.${table}\`,
not master_clean_niq).

BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/llm-extraction-rules.md, docs/headless-runbook.md, docs/quality-standards.md, and the category brief — run: SELECT brief_markdown FROM \`${PROJECT}.magpie_reference.category_brief\` WHERE category_key = '${category_key}' AND task_type = 'BRIEF' (your fix brief lives in that content's '## Targeted QA Fix Brief' section — read it in full, it is the specific work for this session, not background).

If the category brief has no '## Targeted QA Fix Brief' section, or the section has no concrete fixes to perform, that is a genuine blocker: stop, write nothing, output status='blocked'.

You perform every fix yourself, directly, using your own multimodal reading of product images and text where the brief calls for it. You do not invoke external scripts or subprocesses and do not need any API key beyond your own session auth — CLAUDE.md's ANTHROPIC_API_KEY note is about a different, external pipeline that does not exist in this repo.

${scope}

Known pitfalls from prior sessions, apply generally: (1) \`bq query\` silently truncates displayed results to 100 rows unless you pass --max_rows=100000 or --format=csv — always use one of those on any query where you need the complete result set, and sanity-check the row count against what you expect rather than assuming a short result means a short true set. (2) You are a one-shot, non-interactive process — do NOT use the Agent/Task tool, ScheduleWakeup, or any background/async dispatch mechanism; work through your list directly and sequentially, since nothing dispatched asynchronously will be waited for or reported back.

STEP 1 — Sanity-check the brief's stated current-state numbers against a live query before trusting them:
Run: SELECT source, COUNT(*) FROM \`${PROJECT}.magpie_reference.product_taxonomy_map\` WHERE master_table = '${category}' GROUP BY source
If the live counts disagree with what the brief claims, record the discrepancy in findings — do not silently proceed as if the brief were current.

STEP 1B — Pre-fix QA gate report (already run before this session, informational only — this is a Brief-mode
session, so your scope is exactly what STEP 3's Brief section specifies, not expanded by this report):
${gate_report}
If any FAILing gate above touches rows your Brief already covers, treat it as corroborating signal. If a
FAILing gate touches rows outside the Brief's stated scope, do not act on it — note it in findings so a future
session can pick it up; this session does exactly what the Brief says, nothing more.

STEP 2 — Claim a ${block_size}-slot SKU block atomically (DECLARE before BEGIN TRANSACTION — reversing that order is a real BigQuery scripting syntax error):
BEGIN
  DECLARE next_start INT64;
  BEGIN TRANSACTION;
  SET next_start = (SELECT COALESCE(MAX(block_end), 69000) + 1 FROM \`${PROJECT}.magpie_reference.sku_block_registry\`);
  INSERT INTO \`${PROJECT}.magpie_reference.sku_block_registry\`
    (block_start, block_end, master_table, scenario, claimed_at, status)
  VALUES (next_start, next_start + ${slot_offset}, '${category}', 'custom_targeted_qa_fix', CURRENT_TIMESTAMP(), 'ACTIVE');
  COMMIT TRANSACTION;
END;
Never query MAX(taxonomy_id) directly and assume it's safe to use — this atomic claim against the registry table is what prevents two sessions colliding on the same ID range.

STEP 3 — Execute exactly the fixes described in the category brief's '## Targeted QA Fix Brief' section: pack-count / size / bundle / product-line / variant corrections, hard-gate violations (G1, G2, G3, G5, G6 per docs/quality-standards.md §4), brand_mismatch review per docs/brand-extraction.md — whatever that section specifies. That section is the actual scope of this session — this prompt does not restate it. This script fixes existing taxonomy entries only; it never creates coverage for products with taxonomy_id IS NULL — if the Brief's scope turns out to actually be a NULL-coverage/unmapped-product backfill, that is a genuine blocker (the correct tool is script/custom_headless_taxonomy.sh's top-up scenario, not this script): stop, write nothing, output status='blocked' explaining the mismatch.

STEP 4 — Write via bq query DML only, never the streaming API. Set meta_agent='CLAUDE_CODE' on every row you write. Never delete an existing row unless the brief explicitly instructs you to.

STEP 5 — Do NOT run the universe refresh yourself. That step runs after this session, only if independent QA gates pass — it is not something you do.

STEP 6 — Do not write to \`${PROJECT}.magpie_reference.category_brief\` yourself. Instead, set the final
JSON output's qa_history_entry field to {finding: "...", resolution: "..."} summarizing what you did and
found this session. The wrapper inserts it as a QA_HISTORY row on your behalf after you finish.

STEP 7 — If you hit a genuine blocker at any step — something wrong with these instructions, missing data, anything that would make proceeding unsafe — stop, write nothing further, and output status='blocked' with the blockers array populated. That is a valid, expected outcome, not a failure.

Output ONLY this JSON when done, nothing else:
{status: complete|partial|failed|blocked, rows_created, rows_mapped, taxonomy_id_range_used, qa_history_entry: null|{finding, resolution}, findings, blockers}.
PROMPT
}

build_auto_discovery_prompt() {
  local dataset="$1" table="$2" category="$3" category_key="$4" block_size="${5:-200}" gate_report="${6:-}"
  local slot_offset=$((block_size - 1))
  local scope
  scope=$(scope_note "$dataset" "$table")
  cat <<PROMPT
Automated Taxonomy Review session for master_table='${category}' (custom source:
\`${PROJECT}.${dataset}.${table}\`, not master_clean_niq). No '## Targeted QA Fix Brief' section with
real content exists in the category brief — this session auto-discovers its own scope instead of
executing a hand-written brief. See docs/superpowers/specs/2026-07-21-taxonomy-review-loop-design.md
for the full design.

BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/llm-extraction-rules.md (including §11,
Signal Provenance & Cross-Validation), docs/quality-standards.md, docs/brand-extraction.md,
docs/headless-runbook.md, and the category brief — run: SELECT brief_markdown FROM
\`${PROJECT}.magpie_reference.category_brief\` WHERE category_key = '${category_key}' AND task_type =
'BRIEF' (brand scope, allowlist, and scope rules are already documented there — do not rediscover them
from scratch).

You perform every review and fix yourself, directly, using your own multimodal reading of product images and
text where needed. You do not invoke external scripts or subprocesses and do not need any API key beyond your
own session auth — CLAUDE.md's ANTHROPIC_API_KEY note is about a different, external pipeline that does not
exist in this repo.

${scope}

Known pitfalls from prior sessions, apply generally: (1) \`bq query\` silently truncates displayed results to
100 rows unless you pass --max_rows=100000 or --format=csv — always use one of those on any query where you
need the complete result set. (2) You are a one-shot, non-interactive process — do NOT use the Agent/Task
tool, ScheduleWakeup, or any background/async dispatch mechanism; work through your list directly and
sequentially.

STEP 1 — Get your review worklist (incremental scope: never-reviewed or previously-unconfident entries only,
never a full re-scan of the category):
SELECT DISTINCT pt.taxonomy_id, pt.canonical_name, bd.canonical_name AS brand, pt.product_line, pt.size,
       pt.pack_count
FROM \`${PROJECT}.magpie_reference.product_taxonomy\` pt
JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
JOIN \`${PROJECT}.magpie_reference.brand_dict\` bd ON bd.brand_id = pt.brand_id
WHERE m.master_table = '${category}'
  AND (pt._meta IS NULL OR IFNULL(JSON_VALUE(pt._meta, '$.review_confidence'), 'unreviewed') != 'confident')

STEP 1B — Pre-fix QA gate report (already run before this session):
${gate_report}

The gates above split into two classes. For any FAILing gate in this list — placeholder-leak,
structured-fields NULL%, 'all variant/size' name, canonical_name fields, garbled brand text — first check
whether its rows already carry a confirmed exception:
SELECT * FROM \`${PROJECT}.magpie_reference.qa_gate_exceptions\` WHERE gate_name = '<the gate's exact name>' AND master_table = '${category}'.
If an exception already covers a row, skip re-verifying it entirely — it's closed, not a fresh finding. For
rows without an existing exception, treat the flag as an automatic candidate needing a fix, the same way a
Tier 1 SQL hit below does: no LLM judgment needed to detect it, only to decide and apply the correct fix (a
gate can still false-positive — e.g. the 'all variant/size' gate flagging legitimate text like "All Skin
Types" — sanity-check before applying, don't blind-apply). Get the actual affected rows by adapting that
gate's own query from docs/headless-runbook.md's QA-gate-as-code section (drop the outer COUNT(*), select the
underlying columns instead) — do not guess which rows failed from the count alone. If you confirm a row is a
genuine, structural false positive (not a data defect, nothing a fix could ever resolve) — check this
category's QA History for a prior session reaching the same conclusion on the same entity first, since a
single confirmation is not enough to close it permanently, mirroring the existing
confident-after-two-agreeing-reviews rule for regular rows. Once a second (or later) confirmation lands,
insert a row: INSERT INTO \`${PROJECT}.magpie_reference.qa_gate_exceptions\`
(gate_name, master_table, entity_id, reason, confirmed_at, meta_agent) VALUES
('<gate name>', '${category}', '<the brand_id or taxonomy_id>', '<why this is permanent, not a defect>', CURRENT_TIMESTAMP(), 'CLAUDE_CODE')
so no future session re-spends turns on it.

For any FAILing gate in this list instead — dual-mapped (LLM), HUMAN+LLM coexistence, duplicate product_id,
duplicate product+taxon — do NOT attempt a fix: every one of these can only be resolved by deleting or
re-mapping a product_taxonomy_map row, and this session never deletes an existing row (STEP 7). Record the
gate name and count in findings instead, flagged as needing a deletion-authorized session. Note also: the
post-fix independent qa_report.sh re-check (STEP 10) re-runs these same gates — if one is failing here, it
will fail there too regardless of how well this session's fixes go, so a FAILED_QA outcome driven by a gate
this session was never able to touch is expected, not a sign the session did anything wrong.

Policy (management decision): a product that is simply irrelevant/out-of-category for ${category} — genuinely
a different product type, sitting in this source table's raw data for reasons upstream of this pipeline — is
NOT a defect on its own. An accurately-described, correctly-structured taxonomy entry for the real product
(e.g. "Royal Canin Dog Gastrointestinal Dog 2kg" mapped under a cat-food master_table) is acceptable to leave
exactly as-is. Do NOT flag category/scope mismatch alone as needing a deletion-authorized session, and do not
spend Tier 2 judgment re-litigating it if a prior session already concluded the same. The only thing that
still needs a deletion/reroute-authorized session is a genuine content duplicate — the same real-world product
minted as two or more separate taxonomy_id rows (in this category or spanning into another one), which
fragments its GMV across multiple entries instead of one. Run this check (global — a duplicate can exist in
any master_table, not just this one) over every taxonomy_id currently mapped to ${category}:
SELECT pt.taxonomy_id, pt.canonical_name, dup.taxonomy_id AS duplicate_of, dup.canonical_name AS duplicate_canonical_name
FROM \`${PROJECT}.magpie_reference.product_taxonomy\` pt
JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id AND m.master_table = '${category}'
JOIN \`${PROJECT}.magpie_reference.product_taxonomy\` dup
  ON dup.taxonomy_id != pt.taxonomy_id
  AND dup.brand_id = pt.brand_id
  AND LOWER(dup.product_line) = LOWER(pt.product_line)
  AND IFNULL(LOWER(dup.sub_line),'') = IFNULL(LOWER(pt.sub_line),'')
  AND IFNULL(LOWER(dup.variant),'') = IFNULL(LOWER(pt.variant),'')
  AND IFNULL(LOWER(dup.size),'') = IFNULL(LOWER(pt.size),'')
  AND IFNULL(dup.pack_count, -1) = IFNULL(pt.pack_count, -1)
GROUP BY 1,2,3,4
A genuine hit here (same brand+product_line+sub_line+variant+size+pack_count signature under two different
taxonomy_ids) is a real defect: record both taxonomy_ids, their master_tables, and their combined mapped-product
counts in findings, flagged as needing a dedup-authorized session (a human picks the surviving taxonomy_id and
a reroute-then-delete of the other is run explicitly, not by this script — same STEP 7 restriction as above).

STEP 1C — Fast-lane recheck: before spending any Tier 2 judgment, resolve rows that were already fixed in a
prior session and are only waiting on one more clean confirmation to become confident — identifiable as
_meta IS NOT NULL AND JSON_VALUE(_meta, '$.review_confidence') IS NULL (the "fixed pending recheck" bucket
qa_coverage_report.sh reports separately from "unconfident"). Run the exact same Tier 1 SQL sweep as STEP 2
below, scoped to just this subset:
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
FROM \`${PROJECT}.magpie_reference.product_taxonomy\` pt
JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
JOIN \`${PROJECT}.magpie_reference.brand_dict\` bd ON bd.brand_id = pt.brand_id
WHERE m.master_table = '${category}'
  AND pt._meta IS NOT NULL AND JSON_VALUE(pt._meta, '$.review_confidence') IS NULL
GROUP BY 1,2,3,pt.product_line,pt.sub_line,pt.variant,pt.size,pt.pack_count,pt.is_multi_size,pt.is_bundle

For every row where every flag above comes back FALSE, bulk-promote it directly — no LLM judgment, no image
read, no Tier 2 sample slot spent — using the exact same promotion logic as STEP 5:
UPDATE \`${PROJECT}.magpie_reference.product_taxonomy\` pt
SET _meta = TO_JSON_STRING(STRUCT(
  true AS is_reviewed,
  CURRENT_TIMESTAMP() AS last_reviewed_at,
  IF(JSON_VALUE(pt._meta, '$.last_verdict') = 'correct', 'confident', 'unconfident') AS review_confidence,
  'correct' AS last_verdict
))
WHERE pt.taxonomy_id IN ('SKU-XXXXXX', /* every fixed_pending_recheck row that came back Tier-1-clean this pass */)

Any row where a flag still trips is a regression or an incomplete prior fix, not a clean confirmation — leave
its _meta untouched here (STEP 2's worklist-wide sweep will flag it again the normal way, and it flows into
STEP 4's real fix path like any other flagged row). Do not spend Tier 2 judgment on a row this step already
promoted — STEP 3 below excludes it.

STEP 2 — Tier 1: run this SQL sweep over that same worklist to flag mechanical defects cheaply, before
spending any LLM judgment. canonical_field_mismatch mirrors script/qa_report.sh's independent
"canonical_name fields" gate exactly — added after a live run passed its own Tier 1 sweep but still failed
that wrapper-side gate on 81 rows, because this check wasn't in Tier 1 yet. stub_leak also catches "Multiple
Sizes"/"Multiple Variants" — an earlier shopee_th_softdrink precedent sanctioned this phrasing when paired with
is_multi_size/is_multi_variant=TRUE, but it's banned unconditionally now: the is_multi_size/is_multi_variant
column already conveys that semantic, so restating it as generic text in canonical_name is the same
ungrounded-stub problem as "All variant"/"All size" — flag or no flag, the text itself is the defect:
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
FROM \`${PROJECT}.magpie_reference.product_taxonomy\` pt
JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
JOIN \`${PROJECT}.magpie_reference.brand_dict\` bd ON bd.brand_id = pt.brand_id
WHERE m.master_table = '${category}'
  AND (pt._meta IS NULL OR IFNULL(JSON_VALUE(pt._meta, '$.review_confidence'), 'unreviewed') != 'confident')
GROUP BY 1,2,3,pt.product_line,pt.sub_line,pt.variant,pt.size,pt.pack_count,pt.is_multi_size,pt.is_bundle
Every TRUE flag here is an automatic last_verdict='wrong' candidate — no LLM judgment needed to detect these,
only to decide and apply the fix in STEP 4. null_size (D4, docs/quality-standards.md) was never wired into
any automated check before now, same gap D5 had — found via product 16254994627's image-visible 400ml size
that was never extracted. garbage_brand catches a resolved brand (brand_dict.canonical_name via
product_taxonomy.brand_id) with no letters at all (e.g. "12/+＝") — see docs/llm-extraction-rules.md §11 for
the root cause (a reseller's watermark/logo overlay misread as the product's brand) and STEP 4 for the fix.
count_as_size closes a real blind spot found via a category_brief QA_HISTORY audit: `size='10 pcs'`/`'20
capsules'` satisfies `size IS NOT NULL`, so a missing real weight/volume was invisible to the null_size flag
above — same underlying defect, different disguise. provenance_leak is §11's merchant/seller/SEO-leak rule
(store names, "SG SELLER", "🔥HQ🔥", "Similar to <competitor>") finally wired into Tier 1 instead of relying on
luck during GMV-sampled Tier 2 review to catch it — ponytail: heuristic keyword/emoji regex, not exhaustive;
raise a genuinely new leak pattern here if Tier 2 keeps catching the same phrasing Tier 1 missed.

STEP 2b — Tier 1 also includes this product-grain sweep (docs/quality-standards.md §3 D5 — this exact query
existed only as a manual snippet there before now, never wired into any automated check, which is why product
16254994627's "Buy 1 Get 1" sku_name text was never caught): pack_count=1 but promo/multiplier language
present in sku_name. Unlike the flags above, this is NOT an automatic wrong verdict — most "ฟรี"/"free" hits are GWP (correctly pack=1); confirm against the product image before treating a hit as a real miss.
Feed every hit into your Tier 2 judgment budget alongside the GMV-prioritized sample from STEP 3, not as a
separate exhaustive pass. Match on (product_id, platform) against this custom source, never product_id alone:
SELECT m.product_id, m.platform, s.sku_name, pt.taxonomy_id, pt.canonical_name, pt.pack_count
FROM \`${PROJECT}.magpie_reference.product_taxonomy_map\` m
JOIN \`${PROJECT}.magpie_reference.product_taxonomy\` pt ON pt.taxonomy_id = m.taxonomy_id
JOIN \`${PROJECT}.${dataset}.${table}\` s ON s.product_id = m.product_id AND s.ecommerce_platform = m.platform
WHERE m.master_table = '${category}'
  AND pt.pack_count = 1
  AND (pt._meta IS NULL OR IFNULL(JSON_VALUE(pt._meta, '$.review_confidence'), 'unreviewed') != 'confident')
  AND REGEXP_CONTAINS(LOWER(s.sku_name), r'แถม|1\+1|ฟรี|ซื้อ \d+ แถม|แพ็คคู่|ยกลัง|x\s*\d|buy\s*\d+\s*get\s*\d+|free')

STEP 2c — Tier 1 also includes this product-grain sweep for the shared-bucket size/multiplier miss found in
the shopee_sg_pet_food review (2026-07-28): a product's own sku_name states exactly one readable size (or
exactly one pack multiplier) that its taxonomy_id's canonical_name doesn't carry — typically because the
product got mapped into a generic is_multi_size=TRUE catch-all that also legitimately serves listings whose
own titles state 2+ sizes (genuine buyer-choice-of-size). A single readable value is not ambiguous the way
STEP 2b's promo language is — feed every hit straight into STEP 4's fix path, no Tier 2 judgment needed to
detect it (deciding write-in-place vs. reroute in STEP 4 still needs the aggregation query shown there, not
LLM judgment). Sanity-check a pack-multiplier hit against the product image before applying if the packaging
language is a marketing name rather than a literal count (e.g. "value pack"). Match on (product_id, platform)
against this custom source, never product_id alone:
SELECT m.product_id, m.platform, s.sku_name, pt.taxonomy_id, pt.canonical_name, pt.size, pt.is_multi_size, pt.pack_count,
  REGEXP_EXTRACT(s.sku_name, r'(?i)(\d+(?:\.\d+)?\s*(?:kg|g|ml|l|oz|lb))\b') AS extracted_size,
  REGEXP_EXTRACT(s.sku_name, r'(?i)(\d+)\s*(?:pcs|pc|packs|pack)\b') AS extracted_multiplier
FROM \`${PROJECT}.magpie_reference.product_taxonomy_map\` m
JOIN \`${PROJECT}.magpie_reference.product_taxonomy\` pt ON pt.taxonomy_id = m.taxonomy_id
JOIN \`${PROJECT}.${dataset}.${table}\` s ON s.product_id = m.product_id AND s.ecommerce_platform = m.platform
WHERE m.master_table = '${category}'
  AND (pt._meta IS NULL OR IFNULL(JSON_VALUE(pt._meta, '\$.review_confidence'), 'unreviewed') != 'confident')
  AND (
    (ARRAY_LENGTH(REGEXP_EXTRACT_ALL(s.sku_name, r'(?i)\d+(?:\.\d+)?\s*(?:kg|g|ml|l|oz|lb)\b')) = 1
     AND NOT REGEXP_CONTAINS(pt.canonical_name, r'(?i)\d+(?:\.\d+)?\s*(kg|g|ml|l|oz|lb)\b'))
    OR
    (ARRAY_LENGTH(REGEXP_EXTRACT_ALL(s.sku_name, r'(?i)\d+\s*(?:pcs|pc|packs|pack)\b')) = 1
     AND COALESCE(pt.pack_count, 1) = 1
     AND NOT REGEXP_CONTAINS(pt.canonical_name, r'(?i)x\d+\b'))
  )

STEP 3 — Tier 2: a bounded, GMV-prioritized sample only, not every un-flagged row. Order the rows Tier 1
didn't flag by GMV (join \`${PROJECT}.${dataset}.${table}\` on product_id AND platform for gmv_daily — recall
the SCOPE note above: this ordering is unreliable for Tiktok rows specifically, so treat a Tiktok-heavy sample
as a rough prioritization, not a precise one) and judge the top slice your remaining turn budget allows
against docs/llm-extraction-rules.md in full (product_line §3, size §2, the new §11 signal-provenance
and size-cross-validation rules) and docs/quality-standards.md §3's D1-D5 dimensions. This is the one script in
this pipeline where per-entry LLM judgment is the right tool, not a shortcut to avoid — precision is this script's job, not custom_headless_taxonomy.sh's. Exclude any taxonomy_id STEP 1C already bulk-promoted this
session — they're resolved, don't spend judgment budget re-confirming them.

For every row you judge, explicitly check whether the matched/reused entry's product type genuinely matches
sku_name and the image — not just whether the name/structure looks right. This is the same conflict class as
hard gate G3 (docs/quality-standards.md §4 — wet vs dry, lotion vs oil, paste vs wash) and the TYPE GATE in
docs/product-lifecycle.md §4.2's match-or-create decision tree, just for this category's own product types
(e.g. shampoo vs body wash/shower gel, found via product 22501764599). Bulk text-matching (used during
coverage runs for speed) can produce a superficially plausible but wrong-type match when a brand carries
multiple product lines with overlapping vocabulary — a match that "sounds right" from a text diff is not
verified until the type is confirmed against sku_name/image. A wrong-type match is never partial credit —
reroute to the correct existing entry, or mint a new one; do not rename in place.

But exhaustively re-judging every Tier-1-clean row one by one is
what capped a prior session at 133 of ~5,812 rows in one run. A Tier-1-clean row you do NOT sample this
session gets no _meta write at all — do not mark it reviewed just because Tier 1 found nothing; that would
fabricate a review that never actually happened (only genuine Tier 2 judgment, or a Tier 1 flag + fix, earns a
_meta write). It stays exactly as eligible next run as it is now — Tier 1's cheap SQL sweep re-checks it for
free either way, and a future session's sample will eventually reach it. Do not use this to justify skipping
Tier 2 broadly; sample as much as your GMV-prioritized budget genuinely allows.

STEP 4 — Apply fixes. Prefer bulk SQL per defect class over one-row-at-a-time corrections wherever the fix
is mechanical — e.g. a single REGEXP_REPLACE UPDATE can strip a duplicated brand substring across every
affected row in one statement (this repo has precedent: docs/categories/shopee_th_moisturizer_for_face.md's
"Brand-Brand naming bug" fix used exactly this pattern). Read an individual product's image only when the fix
itself requires re-deriving a value (e.g. confirming the real size after a G2G-style false match). Every row
you change must have its _meta reset in the same session (_meta is STRING-typed, storing serialized JSON text —
never use the JSON '...' literal prefix or TO_JSON(), always a plain string):

wrong_field_order has two different root causes needing two different fixes — check which one before acting:
(a) text is genuinely out of order (e.g. "Size Type Multiplier" instead of "Brand Product-Line Size xN"):
reorder canonical_name to match the established template, brand_id itself is correct. (b) brand_id resolves to BRD-UNDEFINED/BRD-UNBRANDED while canonical_name clearly states a real, identifiable brand name (found
via product 26143837772: brand_id resolved to "Undefined" but canonical_name correctly said "Enfant..."):
canonical_name is already correct, do NOT touch it — the defect is brand_id. Look up the correct brand in
brand_dict (exact or close name match against the brand already stated in canonical_name), or create a new
brand_dict entry if it genuinely doesn't exist yet, and update product_taxonomy.brand_id to point there.

garbage_brand's fix follows docs/llm-extraction-rules.md §11: re-read the image applying the seller-watermark
discipline (a reseller's overlay/logo, however large in the frame, is never the brand — only text printed on
the actual packaging counts), find or create the correct brand_dict entry, update product_taxonomy.brand_id,
and correct canonical_name to start with the real brand — unlike case (b) above, both fields are wrong here
and both need fixing.

count_as_size's fix: this is null_size wearing a disguise, not a separate defect class — run the same
extraction chain (sku_name text → image → product_specification → description per §2's priority order) to
find the real weight/volume and write it to `size`; only if the listing genuinely has no weight/volume (a true
unit-count product, e.g. a set of loose capsules with no stated fill weight) is the count value itself
legitimate — leave it as-is and do not flag it again by hand.

provenance_leak's fix follows docs/llm-extraction-rules.md §11 exactly like garbled brand text: strip the
merchant/seller/SEO text from canonical_name (and product_line/variant if it leaked there too) and re-derive
from sku_name and the image only — never from merchant_name or store branding.

STEP 2c's fix needs one aggregation query first — never write a single size/multiplier value onto a
taxonomy_id shared by products whose real values genuinely differ. Match on (product_id, platform), never
product_id alone:
SELECT pt.taxonomy_id,
  COUNT(DISTINCT REGEXP_EXTRACT(s.sku_name, r'(?i)(\d+(?:\.\d+)?\s*(?:kg|g|ml|l|oz|lb))\b')) AS distinct_sizes,
  COUNT(DISTINCT REGEXP_EXTRACT(s.sku_name, r'(?i)(\d+)\s*(?:pcs|pc|packs|pack)\b')) AS distinct_multipliers
FROM \`${PROJECT}.magpie_reference.product_taxonomy_map\` m
JOIN \`${PROJECT}.magpie_reference.product_taxonomy\` pt ON pt.taxonomy_id = m.taxonomy_id
JOIN \`${PROJECT}.${dataset}.${table}\` s ON s.product_id = m.product_id AND s.ecommerce_platform = m.platform
WHERE m.master_table = '${category}' AND pt.taxonomy_id IN (/* every taxonomy_id STEP 2c flagged */)
GROUP BY 1
Run this over the WHOLE bucket (every product currently mapped to that taxonomy_id), not just the flagged
rows, since a bucket can also hold genuinely multi-size titles (2+ size tokens in their own sku_name) that
STEP 2c correctly left unflagged.
- distinct_sizes = 1 (or distinct_multipliers = 1) across the whole bucket → every mapped product genuinely
  carries the same value; is_multi_size=TRUE (or pack_count left at 1) was simply wrong, or the size was never
  captured for what is really a single-SKU entry. Write in place: UPDATE product_taxonomy SET size = '<value>'
  (or pack_count = <value>, canonical_name updated to end in the established 'x{N}' suffix — never
  '(N packs of M)', per CLAUDE.md's common-pitfalls table), is_multi_size = FALSE (safe here precisely because
  distinct_sizes=1 means no genuinely multi-size product is stranded on this id), meta_agent = 'CLAUDE_CODE',
  _meta = '{"is_reviewed": false}' WHERE taxonomy_id = '...'.
- distinct_sizes >= 2 (or distinct_multipliers >= 2) → the bucket is a real catch-all serving genuinely
  different values; do not touch its size/pack_count/is_multi_size/canonical_name. For each distinct value,
  find an existing taxonomy_id already carrying that exact brand + product_line + variant + size (or +
  pack_count), or mint one (STEP 6 SKU block claim) with a canonical_name following the established template,
  then reroute only the affected products: UPDATE product_taxonomy_map SET taxonomy_id = '<matching/new id>',
  meta_agent = 'CLAUDE_CODE' WHERE product_id IN (<products carrying that one value>) AND platform = '<their
  platform>' AND master_table = '${category}'. Leave every product whose own sku_name states 2+ sizes mapped
  to the original bucket — only the single-value products move, and the original bucket's own _meta only
  needs resetting if its canonical_name/size/is_multi_size actually changed (it doesn't, in this branch).

UPDATE \`${PROJECT}.magpie_reference.product_taxonomy\`
SET _meta = '{"is_reviewed": false}'
WHERE taxonomy_id IN (/* the taxonomy_ids you just fixed */)
Reminder: the actual content-fixing UPDATE (the one that changes canonical_name/product_line/size/pack_count —
not shown as a template above since it varies per defect) must also set meta_agent='CLAUDE_CODE' in that same
statement. Don't wait until STEP 7 to remember this.

Same-session gate-verify (2026-07-28): immediately after applying a fix and resetting a row's _meta to
{"is_reviewed": false}, re-run the same Tier 1 flag checks (stub_leak, duplicate_brand, wrong_field_order,
brand_casing_mismatch, excess_content, canonical_field_mismatch, null_size, garbage_brand, count_as_size,
provenance_leak) against that row's
new values, in this same session — do not wait for a future session's STEP 1C to confirm the fix held. A row
that comes back fully clean on this immediate recheck qualifies for STEP 5's Path 1(b) promotion below, this
session. A row that still trips a flag keeps _meta at {"is_reviewed": false}, unresolved — picked up again by
STEP 2's worklist-wide sweep or a future STEP 1C pass, same as today.

STEP 5 — Promote reviewed rows' _meta. Two distinct promotion paths apply — run both; they cover different
rows and never conflict as long as you don't put the same taxonomy_id in both lists:

PATH 1 (new, 2026-07-28) — never-reviewed rows and freshly-fixed rows, promoted in ONE pass, no waiting for a
future session:
  (a) A never-reviewed row (pt._meta IS NULL going into this session) that you Tier-2-judged 'correct' this
      session AND that came back fully clean on Tier 1 (STEP 2's sweep) — where "fully clean" means no flag
      tripped, OR every flag that did trip already has a matching row in
      \`${PROJECT}.magpie_reference.qa_gate_exceptions\` for (gate_name = '<the tripped flag's name, e.g.
      null_size>', master_table = '${category}', entity_id = '<the taxonomy_id>') — promotes straight to
      'confident'. A never-reviewed row Tier-2-judged 'correct' but with an un-excepted Tier 1 flag instead
      lands on 'unconfident' (the two signal types disagree).
  (b) A row you fixed this session (STEP 4's same-session gate-verify): fully clean on the immediate post-fix
      Tier 1 recheck (same "fully clean" definition as (a), including the qa_gate_exceptions carve-out) →
      promotes straight to 'confident', this session. Still flagged on recheck → do not include it here (STEP
      4 already left its _meta at {"is_reviewed": false}, unresolved).
  Bulk statement for every taxonomy_id qualifying under (a) or (b) this session:
  UPDATE \`${PROJECT}.magpie_reference.product_taxonomy\`
  SET _meta = TO_JSON_STRING(STRUCT(
    true AS is_reviewed,
    CURRENT_TIMESTAMP() AS last_reviewed_at,
    'confident' AS review_confidence,
    'correct' AS last_verdict
  ))
  WHERE taxonomy_id IN ('SKU-XXXXXX', /* every taxonomy_id qualifying under (a) or (b) this session */)

PATH 2 (existing, unchanged) — every other row you gave a real Tier 2 judgment this session and found correct,
that is NOT already covered by Path 1 (i.e. rows with a prior stored verdict already in _meta, being reviewed
again — the fixed_pending_recheck-via-fresh-Tier-2-judgment case, or a previously unconfident row sampled
again). Update its _meta by comparing this review's verdict against the stored previous verdict — agreement
promotes to confident; disagreement lands on unconfident. Do this in ONE bulk statement covering every such
taxonomy_id, not one UPDATE per row — a prior session burned most of its turn budget on
one-UPDATE-per-taxonomy_id bookkeeping alone and only reviewed 133 of ~5,812 rows as a result:
  UPDATE \`${PROJECT}.magpie_reference.product_taxonomy\` pt
  SET _meta = TO_JSON_STRING(STRUCT(
    true AS is_reviewed,
    CURRENT_TIMESTAMP() AS last_reviewed_at,
    IF(JSON_VALUE(pt._meta, '$.last_verdict') = 'correct', 'confident', 'unconfident') AS review_confidence,
    'correct' AS last_verdict
  ))
  WHERE pt.taxonomy_id IN ('SKU-XXXXXX', 'SKU-YYYYYY', /* every taxonomy_id you Tier-2-judged as correct this session under Path 2 — the IF() expression re-reads each row's own prior _meta, so one statement handles all of them correctly even though their prior states differ */)

This is metadata bookkeeping for the rows you actually reviewed (Tier 2 sample size, not the whole worklist),
so each path's taxonomy_id list stays small enough to write out literally — never bulk-mark a Tier-1-clean row you
did NOT Tier-2-sample (see STEP 3), and never double-count a taxonomy_id in both Path 1 and Path 2's lists.
Note last_verdict only ever records 'correct' in practice: rows you judge wrong either get fixed (STEP 4 resets
their _meta to unreviewed so they're re-evaluated fresh next run) or, if not fixed this session, are simply
left with their _meta untouched so the next run re-reviews them — nothing writes last_verdict='wrong' directly.

STEP 6 — If, and only if, a fix genuinely requires minting a new taxonomy entry (e.g. splitting a bad
multi-size stub into distinct real entries), claim a ${block_size}-slot SKU block atomically first (DECLARE
before BEGIN TRANSACTION — reversing that order is a real BigQuery scripting syntax error):
BEGIN
  DECLARE next_start INT64;
  BEGIN TRANSACTION;
  SET next_start = (SELECT COALESCE(MAX(block_end), 69000) + 1 FROM \`${PROJECT}.magpie_reference.sku_block_registry\`);
  INSERT INTO \`${PROJECT}.magpie_reference.sku_block_registry\`
    (block_start, block_end, master_table, scenario, claimed_at, status)
  VALUES (next_start, next_start + ${slot_offset}, '${category}', 'custom_targeted_qa_fix', CURRENT_TIMESTAMP(), 'ACTIVE');
  COMMIT TRANSACTION;
END;
Never query MAX(taxonomy_id) directly — this atomic claim is what prevents two sessions colliding on the same
ID range. Most review sessions fix existing entries in place and need no new SKU at all; only claim a block
when you actually mint one.

STEP 7 — Write via bq query DML only, never the streaming API. Set meta_agent='CLAUDE_CODE' on every row you
write or update. Never delete an existing row.

STEP 8 — Do NOT run the universe refresh yourself. That step runs after this session, only if independent QA
gates pass — it is not something you do.

STEP 9 — Do not write to \`${PROJECT}.magpie_reference.category_brief\` yourself. Instead, set the final
JSON output's qa_history_entry field to {finding: "...", resolution: "..."} summarizing what you reviewed,
what you fixed, and the confidence distribution you left behind. The wrapper inserts it as a QA_HISTORY
row on your behalf after you finish.

STEP 10 — Before declaring status, self-check the hard gates from docs/headless-runbook.md's QA-gate-as-code
section, WITHOUT --skip-coexistence (this category already shipped once — coexistence is always a genuine bug
at this point). Report the actual numbers in findings.

STEP 11 — If you hit a genuine blocker at any step — something wrong with these instructions, missing data,
anything that would make proceeding unsafe — stop, write nothing further, and output status='blocked' with
the blockers array populated. That is a valid, expected outcome, not a failure.

Output ONLY this JSON when done, nothing else:
{status: complete|partial|failed|blocked, rows_created, rows_mapped, taxonomy_id_range_used, qa_history_entry: null|{finding, resolution}, findings, blockers}.
PROMPT
}

# The prompt instructs the model to output ONLY JSON, but sessions sometimes wrap it in prose
# commentary anyway (observed live: "QA gates all pass. Final wrap-up.\n```json\n{...}\n```\n**Summary:** ...").
# If result_json isn't valid JSON as-is, pull out the first-to-last-brace span before giving up on it —
# that recovers a real status='partial' result that would otherwise silently fall through to MARK_FAILED
# and skip the independent QA-gate-before-refresh check this script exists to run.
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
  local category="$1"
  echo "Marking most recent ACTIVE custom_targeted_qa_fix block for ${category} as FAILED_QA..." >&2
  bq query --use_legacy_sql=false --project_id="${PROJECT}" \
    "UPDATE \`${PROJECT}.magpie_reference.sku_block_registry\`
     SET status = 'FAILED_QA'
     WHERE master_table = '${category}' AND scenario = 'custom_targeted_qa_fix' AND status = 'ACTIVE'
       AND claimed_at = (
         SELECT MAX(claimed_at) FROM \`${PROJECT}.magpie_reference.sku_block_registry\`
         WHERE master_table = '${category}' AND scenario = 'custom_targeted_qa_fix' AND status = 'ACTIVE'
       )"
}

run_universe_refresh() {
  local category="$1"
  echo "Running universe refresh for ${category}..."
  bq query --use_legacy_sql=false --project_id="${PROJECT}" \
    "MERGE \`${PROJECT}.magpie_reference.universe_taxonomy_overlay\` t
     USING (
       SELECT m.product_id, m.platform, m.country, m.master_table,
              pt.taxonomy_id, pt.canonical_name, m.source, m.confidence, m.meta_agent
       FROM \`${PROJECT}.magpie_reference.product_taxonomy_map\` m
       JOIN \`${PROJECT}.magpie_reference.product_taxonomy\` pt ON m.taxonomy_id = pt.taxonomy_id
       WHERE m.master_table = '${category}'
       QUALIFY ROW_NUMBER() OVER (
         PARTITION BY m.product_id, m.platform, m.country
         ORDER BY CASE m.source WHEN 'LLM' THEN 0 ELSE 1 END, m.taxonomy_id
       ) = 1
     ) src
     ON t.product_id = src.product_id AND t.platform = src.platform AND t.country = src.country
       AND t.master_table = '${category}'
     WHEN MATCHED THEN UPDATE SET
       taxonomy_id = src.taxonomy_id,
       sku_type_complete = src.canonical_name,
       taxonomy_source = src.source,
       taxonomy_confidence = src.confidence,
       taxonomy_meta_agent = src.meta_agent,
       updated_at = CURRENT_TIMESTAMP()
     WHEN NOT MATCHED BY SOURCE AND t.master_table = '${category}' THEN DELETE
     WHEN NOT MATCHED BY TARGET THEN INSERT
       (product_id, platform, country, master_table, taxonomy_id, sku_type_complete,
        taxonomy_source, taxonomy_confidence, taxonomy_meta_agent, updated_at)
       VALUES (src.product_id, src.platform, src.country, src.master_table, src.taxonomy_id, src.canonical_name,
               src.source, src.confidence, src.meta_agent, CURRENT_TIMESTAMP())"
}

main() {
  if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <DATASET> <SOURCE_TABLE> <CATEGORY> [BLOCK_SIZE] [MAX_TURNS]" >&2
    echo "  e.g. $0 makanankucing 9_makanankucing_my_daily makanankucing_my            (defaults: BLOCK_SIZE=200, MAX_TURNS=300)" >&2
    echo "  e.g. $0 makanananjing 9_makanananjing_my_daily makanananjing_my 200 600     (larger turn budget)" >&2
    exit 1
  fi
  local dataset="$1" table="$2" category="$3"
  local block_size="${4:-200}"
  local max_turns="${5:-300}"

  local category_key
  category_key=$(category_key_for "$dataset" "$category")

  local brief_markdown
  brief_markdown=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=json \
    "$(fetch_brief_markdown_query "$category_key")" | jq -r '.[0].brief_markdown // empty')
  if [[ -z "$brief_markdown" ]]; then
    echo "ERROR: no category_brief BRIEF row found for category_key=${category_key}" >&2
    echo "A Targeted QA Fix requires an existing, documented category — run custom_headless_taxonomy.sh's Full Rebuild first." >&2
    exit 1
  fi

  # Global, not local: this EXIT trap fires after main() itself may have returned, when a `local` would
  # already be out of scope. Every exit from here on (blocked/failed/noop/success) reports coverage.
  QA_FIX_CATEGORY="$category"
  trap './script/qa_coverage_report.sh "$QA_FIX_CATEGORY" || true' EXIT

  echo "${dataset}.${table} -> category=${category}"

  echo "Running pre-fix QA gate report..."
  local gate_report
  gate_report=$(./script/qa_report.sh "$category") || true

  local prompt
  if [[ "$(has_real_brief "$brief_markdown")" == "true" ]]; then
    echo "TARGETED QA FIX STARTED (brief mode: ${category_key}, block_size=${block_size}, max_turns=${max_turns})"
    echo "==========================="
    prompt=$(build_prompt "$dataset" "$table" "$category" "$category_key" "$block_size" "$gate_report")
  else
    local review_worklist_count
    review_worklist_count=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
      "$(review_worklist_count_query "$category")" | tail -1)
    if [[ "$review_worklist_count" == "0" ]]; then
      echo "No unreviewed/unconfident taxonomy entries for ${category} — nothing to do."
      echo "QUEUE_SIGNAL: NOTHING_TO_DO"
      exit 0
    fi
    echo "TARGETED QA FIX STARTED (auto-discovery mode: ${category_key}, block_size=${block_size}, max_turns=${max_turns}, review_worklist_count=${review_worklist_count})"
    echo "==========================="
    prompt=$(build_auto_discovery_prompt "$dataset" "$table" "$category" "$category_key" "$block_size" "$gate_report")
  fi

  local claude_output
  claude_output=$(claude -p --output-format json --permission-mode bypassPermissions --max-turns "$max_turns" "$prompt")

  local result_json
  result_json=$(echo "$claude_output" | jq -r '.result // empty')

  if [[ -z "$result_json" ]]; then
    echo "ERROR: claude -p produced no parseable .result field. Raw output:" >&2
    echo "$claude_output" >&2
    mark_failed_qa "$category"
    exit 1
  fi

  # Normalize once here so every downstream use (decide_next_step AND the BLOCKED branch's
  # direct jq calls below) sees the same clean JSON, even if the model wrapped it in prose.
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
      echo "STATUS: blocked. Claimed block left ACTIVE (nothing written) — see blockers below."
      echo "$result_json" | jq -r '.blockers[]?' >&2
      echo "QUEUE_SIGNAL: BLOCKED"
      exit 0
      ;;
    NOOP)
      echo "STATUS: complete/partial with rows_created=0 — nothing to gate or refresh. Block left ACTIVE."
      echo "QUEUE_SIGNAL: DONE"
      exit 0
      ;;
    MARK_FAILED)
      echo "STATUS: failed or malformed. Marking block FAILED_QA." >&2
      echo "$result_json" >&2
      mark_failed_qa "$category"
      echo "QUEUE_SIGNAL: FAILED"
      exit 1
      ;;
    GATE_AND_REFRESH)
      echo "STATUS: rows written — running independent QA gates via script/qa_report.sh..."
      if ./script/qa_report.sh "$category"; then
        if run_universe_refresh "$category"; then
          echo "============================"
          echo "TARGETED QA FIX FINISHED — universe refreshed"
          echo "QUEUE_SIGNAL: DONE"
        else
          echo "Universe refresh failed — marking block FAILED_QA." >&2
          mark_failed_qa "$category"
          echo "QUEUE_SIGNAL: FAILED"
          exit 1
        fi
      else
        echo "QA gates failed — marking block FAILED_QA, skipping universe refresh." >&2
        mark_failed_qa "$category"
        echo "QUEUE_SIGNAL: FAILED"
        exit 1
      fi
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
