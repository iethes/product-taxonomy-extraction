#!/usr/bin/env bash
set -euo pipefail

# Usage: ./script/targeted_qa_fix.sh <TABLE> [BLOCK_SIZE] [MAX_TURNS]
# e.g.  ./script/targeted_qa_fix.sh shopee_th_detergent
#
# Runs the "Scenario: Targeted QA Fix" procedure from docs/headless-runbook.md: claim a small SKU
# block, run claude -p, then independently re-verify via script/qa_report.sh before refreshing the
# universe overlay. Never trusts the agent's own self-report to gate a production write.
#
# Two modes, chosen automatically per category file:
#   - Brief mode: docs/categories/<table>.md has a filled-in '## Targeted QA Fix Brief' section
#     (a real Verdict line, not the _TEMPLATE.md placeholder) -> executes exactly what it specifies.
#   - Auto-discovery mode (default otherwise): reviews product_taxonomy entries the category hasn't
#     confidently reviewed yet (product_taxonomy._meta), fixes what it finds wrong. No human-written
#     brief needed. See docs/superpowers/specs/2026-07-21-taxonomy-review-loop-design.md.
#
# See docs/superpowers/specs/2026-07-17-targeted-qa-fix-script-design.md for the original design and
# docs/superpowers/specs/2026-07-21-taxonomy-review-loop-design.md for the auto-discovery mode design.

PROJECT="sincere-hearth-273704"

resolve_category_file() {
  local table="$1"
  local candidate="docs/categories/${table}.md"
  if [[ -f "$candidate" ]]; then
    echo "$candidate"
    return 0
  fi
  local stripped="${table#shopee_}"
  candidate="docs/categories/${stripped}.md"
  if [[ -f "$candidate" ]]; then
    echo "$candidate"
    return 0
  fi
  return 1
}

has_real_brief() {
  local category_file="$1"
  if ! grep -q "^## Targeted QA Fix Brief" "$category_file" 2>/dev/null; then
    echo "false"
    return
  fi
  local verdict_line
  verdict_line=$(grep "^\*\*Verdict:\*\*" "$category_file" | head -1)
  if [[ -z "$verdict_line" ]] || [[ "$verdict_line" == *"{"* ]]; then
    echo "false"
  else
    echo "true"
  fi
}

append_qa_history_row() {
  local category_file="$1"
  local finding="$2"
  local resolution="$3"
  local timestamp="$4"
  local qa_history_line divider_line
  qa_history_line=$(grep -n '^## QA History' "$category_file" | head -1 | cut -d: -f1)
  [[ -z "$qa_history_line" ]] && return 1
  divider_line=$(awk -v start="$qa_history_line" 'NR > start && /^---$/ { print NR; exit }' "$category_file")
  [[ -z "$divider_line" ]] && return 1
  finding=$(printf '%s' "$finding" | tr '\n' ' ' | sed 's/|/\\|/g')
  resolution=$(printf '%s' "$resolution" | tr '\n' ' ' | sed 's/|/\\|/g')
  local new_row="| ${timestamp} | Automated review session (auto-discovery) | ${finding} | ${resolution} |"
  local tmpfile
  tmpfile=$(mktemp)
  head -n $((divider_line - 1)) "$category_file" > "$tmpfile"
  printf '%s\n' "$new_row" >> "$tmpfile"
  tail -n +"$divider_line" "$category_file" >> "$tmpfile"
  mv "$tmpfile" "$category_file"
}

build_prompt() {
  local table="$1"
  local category_file="$2"
  local block_size="${3:-200}"
  local gate_report="${4:-}"
  local slot_offset=$((block_size - 1))
  cat <<PROMPT
Targeted QA Fix session for ${table}.

BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/llm-extraction-rules.md, docs/headless-runbook.md, docs/quality-standards.md, and ${category_file} (your fix brief lives in that file's '## Targeted QA Fix Brief' section — read it in full, it is the specific work for this session, not background).

If ${category_file} has no '## Targeted QA Fix Brief' section, or the section has no concrete fixes to perform, that is a genuine blocker: stop, write nothing, output status='blocked'.

You perform every fix yourself, directly, using your own multimodal reading of product images and text where the brief calls for it. You do not invoke external scripts or subprocesses and do not need any API key beyond your own session auth — CLAUDE.md's ANTHROPIC_API_KEY note is about a different, external pipeline that does not exist in this repo.

Known pitfalls from prior sessions, apply generally: (1) \`bq query\` silently truncates displayed results to 100 rows unless you pass --max_rows=100000 or --format=csv — always use one of those on any query where you need the complete result set, and sanity-check the row count against what you expect rather than assuming a short result means a short true set. (2) You are a one-shot, non-interactive process — do NOT use the Agent/Task tool, ScheduleWakeup, or any background/async dispatch mechanism; work through your list directly and sequentially, since nothing dispatched asynchronously will be waited for or reported back.

STEP 1 — Sanity-check the brief's stated current-state numbers against a live query before trusting them:
Run: SELECT source, COUNT(*) FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy_map\` WHERE master_table = '${table}' GROUP BY source
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
  SET next_start = (SELECT COALESCE(MAX(block_end), 69000) + 1 FROM \`sincere-hearth-273704.magpie_reference.sku_block_registry\`);
  INSERT INTO \`sincere-hearth-273704.magpie_reference.sku_block_registry\`
    (block_start, block_end, master_table, scenario, claimed_at, status)
  VALUES (next_start, next_start + ${slot_offset}, '${table}', 'targeted_qa_fix', CURRENT_TIMESTAMP(), 'ACTIVE');
  COMMIT TRANSACTION;
END;
Never query MAX(taxonomy_id) directly and assume it's safe to use — this atomic claim against the registry table is what prevents two sessions colliding on the same ID range.

STEP 3 — Execute exactly the fixes described in ${category_file}'s '## Targeted QA Fix Brief' section: pack-count / size / bundle / product-line / variant corrections, hard-gate violations (G1, G2, G3, G5, G6 per docs/quality-standards.md §4), brand_mismatch review per docs/brand-extraction.md — whatever that section specifies. That section is the actual scope of this session — this prompt does not restate it. This script fixes existing taxonomy entries only; it never creates coverage for products with taxonomy_id IS NULL — if the Brief's scope turns out to actually be a NULL-coverage/unmapped-product backfill, that is a genuine blocker (the correct tool is script/headless_taxonomy.sh's top-up scenario, not this script): stop, write nothing, output status='blocked' explaining the mismatch.

STEP 4 — Write via bq query DML only, never the streaming API. Set meta_agent='CLAUDE_CODE' on every row you write. Never delete an existing row unless the brief explicitly instructs you to.

STEP 5 — Do NOT run the universe refresh yourself. That step runs after this session, only if independent QA gates pass — it is not something you do.

STEP 6 — Do not edit ${category_file} or run git yourself. Instead, set the final JSON output's
qa_history_entry field to {finding: "...", resolution: "..."} summarizing what you did and found this
session — the same content that used to go directly into the QA History table's Finding/Resolution columns.
The wrapper appends it to ${category_file} and commits on your behalf after you finish.

STEP 7 — If you hit a genuine blocker at any step — something wrong with these instructions, missing data, anything that would make proceeding unsafe — stop, write nothing further, and output status='blocked' with the blockers array populated. That is a valid, expected outcome, not a failure.

Output ONLY this JSON when done, nothing else:
{status: complete|partial|failed|blocked, rows_created, rows_mapped, taxonomy_id_range_used, qa_history_entry: null|{finding, resolution}, findings, blockers}.
PROMPT
}

build_auto_discovery_prompt() {
  local table="$1"
  local category_file="$2"
  local block_size="${3:-200}"
  local gate_report="${4:-}"
  local slot_offset=$((block_size - 1))
  cat <<PROMPT
Automated Taxonomy Review session for ${table}. No '## Targeted QA Fix Brief' section with real content
exists in ${category_file} — this session auto-discovers its own scope instead of executing a hand-written
brief. See docs/superpowers/specs/2026-07-21-taxonomy-review-loop-design.md for the full design.

BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/llm-extraction-rules.md (including §11,
Signal Provenance & Cross-Validation), docs/quality-standards.md, docs/brand-extraction.md,
docs/headless-runbook.md, and ${category_file} (brand scope, allowlist, and scope rules are already
documented there — do not rediscover them from scratch).

You perform every review and fix yourself, directly, using your own multimodal reading of product images and
text where needed. You do not invoke external scripts or subprocesses and do not need any API key beyond your
own session auth — CLAUDE.md's ANTHROPIC_API_KEY note is about a different, external pipeline that does not
exist in this repo.

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
WHERE m.master_table = '${table}'
  AND (pt._meta IS NULL OR IFNULL(JSON_VALUE(pt._meta, '$.review_confidence'), 'unreviewed') != 'confident')

STEP 1B — Pre-fix QA gate report (already run before this session):
${gate_report}

The gates above split into two classes. For any FAILing gate in this list — placeholder-leak,
structured-fields NULL%, 'all variant/size' name, canonical_name fields, garbled brand text — first check
whether its rows already carry a confirmed exception:
SELECT * FROM \`${PROJECT}.magpie_reference.qa_gate_exceptions\` WHERE gate_name = '<the gate's exact name>' AND master_table = '${table}'.
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
('<gate name>', '${table}', '<the brand_id or taxonomy_id>', '<why this is permanent, not a defect>', CURRENT_TIMESTAMP(), 'CLAUDE_CODE')
so no future session re-spends turns on it.

For any FAILing gate in this list instead — dual-mapped (LLM), HUMAN+LLM coexistence, duplicate product_id,
duplicate product+taxon — do NOT attempt a fix: every one of these can only be resolved by deleting or
re-mapping a product_taxonomy_map row, and this session never deletes an existing row (STEP 7). Record the
gate name and count in findings instead, flagged as needing a deletion-authorized session. Note also: the
post-fix independent qa_report.sh re-check (STEP 10) re-runs these same gates — if one is failing here, it
will fail there too regardless of how well this session's fixes go, so a FAILED_QA outcome driven by a gate
this session was never able to touch is expected, not a sign the session did anything wrong.

STEP 2 — Tier 1: run this SQL sweep over that same worklist to flag mechanical defects cheaply, before
spending any LLM judgment. canonical_field_mismatch mirrors script/qa_report.sh's independent
"canonical_name fields" gate exactly — added after a live run passed its own Tier 1 sweep but still failed
that wrapper-side gate on 81 rows, because this check wasn't in Tier 1 yet. stub_leak also catches "Multiple
Sizes"/"Multiple Variants" — an earlier th_softdrink precedent sanctioned this phrasing when paired with
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
  NOT REGEXP_CONTAINS(bd.canonical_name, r'[\p{L}]') AS garbage_brand
FROM \`${PROJECT}.magpie_reference.product_taxonomy\` pt
JOIN \`${PROJECT}.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
JOIN \`${PROJECT}.magpie_reference.brand_dict\` bd ON bd.brand_id = pt.brand_id
WHERE m.master_table = '${table}'
  AND (pt._meta IS NULL OR IFNULL(JSON_VALUE(pt._meta, '$.review_confidence'), 'unreviewed') != 'confident')
GROUP BY 1,2,3,pt.product_line,pt.sub_line,pt.variant,pt.size,pt.pack_count,pt.is_multi_size,pt.is_bundle
Every TRUE flag here is an automatic last_verdict='wrong' candidate — no LLM judgment needed to detect these,
only to decide and apply the fix in STEP 4. null_size (D4, docs/quality-standards.md) was never wired into
any automated check before now, same gap D5 had — found via product 16254994627's image-visible 400ml size
that was never extracted. garbage_brand catches a resolved brand (brand_dict.canonical_name via
product_taxonomy.brand_id) with no letters at all (e.g. "12/+＝") — see docs/llm-extraction-rules.md §11 for
the root cause (a reseller's watermark/logo overlay misread as the product's brand) and STEP 4 for the fix.

STEP 2b — Tier 1 also includes this product-grain sweep (docs/quality-standards.md §3 D5 — this exact query
existed only as a manual snippet there before now, never wired into any automated check, which is why product
16254994627's "Buy 1 Get 1" sku_name text was never caught): pack_count=1 but promo/multiplier language
present in sku_name. Unlike the flags above, this is NOT an automatic wrong verdict — most "ฟรี"/"free" hits are GWP (correctly pack=1); confirm against the product image before treating a hit as a real miss.
Feed every hit into your Tier 2 judgment budget alongside the GMV-prioritized sample from STEP 3, not as a
separate exhaustive pass:
SELECT m.product_id, s.sku_name, pt.taxonomy_id, pt.canonical_name, pt.pack_count
FROM \`${PROJECT}.magpie_reference.product_taxonomy_map\` m
JOIN \`${PROJECT}.magpie_reference.product_taxonomy\` pt ON pt.taxonomy_id = m.taxonomy_id
JOIN \`${PROJECT}.master_clean_niq.${table}\` s ON s.product_id = m.product_id
WHERE m.master_table = '${table}'
  AND pt.pack_count = 1
  AND (pt._meta IS NULL OR IFNULL(JSON_VALUE(pt._meta, '$.review_confidence'), 'unreviewed') != 'confident')
  AND REGEXP_CONTAINS(LOWER(s.sku_name), r'แถม|1\+1|ฟรี|ซื้อ \d+ แถม|แพ็คคู่|ยกลัง|x\s*\d|buy\s*\d+\s*get\s*\d+|free')

STEP 3 — Tier 2: a bounded, GMV-prioritized sample only, not every un-flagged row. Order the rows Tier 1
didn't flag by GMV (join master_clean_niq for gmv_monthly) and judge the top slice your remaining turn budget
allows against docs/llm-extraction-rules.md in full (product_line §3, size §2, the new §11 signal-provenance
and size-cross-validation rules) and docs/quality-standards.md §3's D1-D5 dimensions. This is the one script in
this pipeline where per-entry LLM judgment is the right tool, not a shortcut to avoid — precision is this script's job, not headless_taxonomy.sh's.

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
affected row in one statement (this repo has precedent: docs/categories/th_moisturizer_for_face.md's
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

UPDATE \`${PROJECT}.magpie_reference.product_taxonomy\`
SET _meta = '{"is_reviewed": false}'
WHERE taxonomy_id IN (/* the taxonomy_ids you just fixed */)
Reminder: the actual content-fixing UPDATE (the one that changes canonical_name/product_line/size/pack_count —
not shown as a template above since it varies per defect) must also set meta_agent='CLAUDE_CODE' in that same
statement. Don't wait until STEP 7 to remember this.

STEP 5 — For every row you gave a real Tier 2 judgment this session and found correct (no fix needed), update
its _meta by comparing this review's verdict against the stored previous verdict — agreement promotes to
confident; disagreement, or a first-ever review, lands on unconfident. Do this in ONE bulk statement covering
every such taxonomy_id, not one UPDATE per row — a prior session burned most of its turn budget on
one-UPDATE-per-taxonomy_id bookkeeping alone and only reviewed 133 of ~5,812 rows as a result:
UPDATE \`${PROJECT}.magpie_reference.product_taxonomy\` pt
SET _meta = TO_JSON_STRING(STRUCT(
  true AS is_reviewed,
  CURRENT_TIMESTAMP() AS last_reviewed_at,
  IF(JSON_VALUE(pt._meta, '$.last_verdict') = 'correct', 'confident', 'unconfident') AS review_confidence,
  'correct' AS last_verdict
))
WHERE pt.taxonomy_id IN ('SKU-XXXXXX', 'SKU-YYYYYY', /* every taxonomy_id you Tier-2-judged as correct this session — the IF() expression re-reads each row's own prior _meta, so one statement handles all of them correctly even though their prior states differ */)
This is metadata bookkeeping for the rows you actually reviewed (Tier 2 sample size, not the whole worklist),
so the taxonomy_id list stays small enough to write out literally — never bulk-mark a Tier-1-clean row you
did NOT Tier-2-sample (see STEP 3). Note last_verdict only ever records 'correct' in practice: rows you judge
wrong either get fixed (STEP 4 resets their _meta to unreviewed so they're re-evaluated fresh next run) or, if
not fixed this session, are simply left with their _meta untouched so the next run re-reviews them — nothing
writes last_verdict='wrong' directly.

STEP 6 — If, and only if, a fix genuinely requires minting a new taxonomy entry (e.g. splitting a bad
multi-size stub into distinct real entries), claim a ${block_size}-slot SKU block atomically first (DECLARE
before BEGIN TRANSACTION — reversing that order is a real BigQuery scripting syntax error):
BEGIN
  DECLARE next_start INT64;
  BEGIN TRANSACTION;
  SET next_start = (SELECT COALESCE(MAX(block_end), 69000) + 1 FROM \`${PROJECT}.magpie_reference.sku_block_registry\`);
  INSERT INTO \`${PROJECT}.magpie_reference.sku_block_registry\`
    (block_start, block_end, master_table, scenario, claimed_at, status)
  VALUES (next_start, next_start + ${slot_offset}, '${table}', 'targeted_qa_fix', CURRENT_TIMESTAMP(), 'ACTIVE');
  COMMIT TRANSACTION;
END;
Never query MAX(taxonomy_id) directly — this atomic claim is what prevents two sessions colliding on the same
ID range. Most review sessions fix existing entries in place and need no new SKU at all; only claim a block
when you actually mint one.

STEP 7 — Write via bq query DML only, never the streaming API. Set meta_agent='CLAUDE_CODE' on every row you
write or update. Never delete an existing row.

STEP 8 — Do NOT run the universe refresh yourself. That step runs after this session, only if independent QA
gates pass — it is not something you do.

STEP 9 — Do not edit ${category_file} or run git yourself. Instead, set the final JSON output's
qa_history_entry field to {finding: "...", resolution: "..."} summarizing what you reviewed, what you fixed,
and the confidence distribution you left behind — the same content that used to go directly into the QA
History table's Finding/Resolution columns. The wrapper appends it to ${category_file} and commits on your
behalf after you finish.

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
  local table="$1"
  echo "Marking most recent ACTIVE targeted_qa_fix block for ${table} as FAILED_QA..." >&2
  bq query --use_legacy_sql=false --project_id="${PROJECT}" \
    "UPDATE \`${PROJECT}.magpie_reference.sku_block_registry\`
     SET status = 'FAILED_QA'
     WHERE master_table = '${table}' AND scenario = 'targeted_qa_fix' AND status = 'ACTIVE'
       AND claimed_at = (
         SELECT MAX(claimed_at) FROM \`${PROJECT}.magpie_reference.sku_block_registry\`
         WHERE master_table = '${table}' AND scenario = 'targeted_qa_fix' AND status = 'ACTIVE'
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

main() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <TABLE> [BLOCK_SIZE] [MAX_TURNS]" >&2
    echo "  e.g. $0 shopee_th_detergent            (defaults: BLOCK_SIZE=200, MAX_TURNS=300)" >&2
    echo "  e.g. $0 shopee_th_suncare 200 600       (larger turn budget for a big-scope brief or category)" >&2
    exit 1
  fi
  local table="$1"
  local block_size="${2:-200}"
  local max_turns="${3:-300}"

  local category_file
  if ! category_file=$(resolve_category_file "$table"); then
    echo "ERROR: no category file found at docs/categories/${table}.md or docs/categories/${table#shopee_}.md" >&2
    echo "A Targeted QA Fix requires an existing, documented category — write the category file (and its '## Targeted QA Fix Brief' section) first." >&2
    exit 1
  fi

  # Global, not local: this EXIT trap fires after main() itself may have returned, when a `local` would
  # already be out of scope. Every exit from here on (blocked/failed/noop/success) reports coverage.
  QA_FIX_TABLE="$table"
  trap './script/qa_coverage_report.sh "$QA_FIX_TABLE" || true' EXIT

  echo "${table}"

  echo "Running pre-fix QA gate report..."
  local gate_report
  gate_report=$(./script/qa_report.sh "$table") || true

  local prompt
  if [[ "$(has_real_brief "$category_file")" == "true" ]]; then
    echo "TARGETED QA FIX STARTED (brief mode: ${category_file}, block_size=${block_size}, max_turns=${max_turns})"
    echo "==========================="
    prompt=$(build_prompt "$table" "$category_file" "$block_size" "$gate_report")
  else
    echo "TARGETED QA FIX STARTED (auto-discovery mode: ${category_file}, block_size=${block_size}, max_turns=${max_turns})"
    echo "==========================="
    prompt=$(build_auto_discovery_prompt "$table" "$category_file" "$block_size" "$gate_report")
  fi

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
    local qa_timestamp
    qa_timestamp=$(date -u +'%Y-%m-%d %H:%M UTC')
    if append_qa_history_row "$category_file" "$qa_finding" "$qa_resolution" "$qa_timestamp"; then
      echo "Appending QA History row and committing..."
      git add "$category_file"
      git commit -m "Automated review session for ${table}: update QA History"
    else
      echo "WARNING: could not append QA History row (no '## QA History' heading or closing '---' found in ${category_file}) — skipping commit." >&2
    fi
  fi

  local decision
  decision=$(decide_next_step "$result_json")

  case "$decision" in
    BLOCKED)
      echo "STATUS: blocked. Claimed block left ACTIVE (nothing written) — see blockers below."
      echo "$result_json" | jq -r '.blockers[]?' >&2
      exit 0
      ;;
    NOOP)
      echo "STATUS: complete/partial with rows_created=0 — nothing to gate or refresh. Block left ACTIVE."
      exit 0
      ;;
    MARK_FAILED)
      echo "STATUS: failed or malformed. Marking block FAILED_QA." >&2
      echo "$result_json" >&2
      mark_failed_qa "$table"
      exit 1
      ;;
    GATE_AND_REFRESH)
      echo "STATUS: rows written — running independent QA gates via script/qa_report.sh..."
      if ./script/qa_report.sh "$table"; then
        run_universe_refresh "$table"
        echo "============================"
        echo "TARGETED QA FIX FINISHED — universe refreshed"
      else
        echo "QA gates failed — marking block FAILED_QA, skipping universe refresh." >&2
        mark_failed_qa "$table"
        exit 1
      fi
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
