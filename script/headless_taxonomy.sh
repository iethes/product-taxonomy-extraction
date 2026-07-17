#!/usr/bin/env bash
set -euo pipefail

# Usage: ./full_rebuild.sh <TABLE>
# e.g.  ./full_rebuild.sh shopee_th_conditioner
#       ./full_rebuild.sh sg_facial_cleanser

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <TABLE>" >&2
  echo "  e.g. $0 shopee_th_conditioner" >&2
  exit 1
fi

TABLE="$1"

echo "${TABLE}"
echo "TAXONOMY EXTRACTION STARTED"
echo "==========================="

claude -p --output-format json --permission-mode bypassPermissions --max-turns 300 "
Full Rebuild session for ${TABLE}. No category context file exists yet for this table — you are creating one as part of this run, not reading a pre-existing one.

BEFORE ANYTHING ELSE, read in full: CLAUDE.md, ARCHITECTURE.md, docs/data-dictionary.md, docs/llm-extraction-rules.md, docs/quality-standards.md, docs/headless-runbook.md, docs/brand-extraction.md, and docs/categories/_TEMPLATE.md (the last one because you are about to fill it in — not in the original doc list, but required for this run specifically). Also check docs/categories/STATUS.md to confirm ${TABLE} hasn't already been completed by someone else since this prompt was written.

You perform extraction yourself, directly, using your own multimodal reading of product images and text. You do not invoke external scripts or subprocesses and do not need any API key beyond your own session auth — CLAUDE.md's ANTHROPIC_API_KEY note is about a different, external pipeline that does not exist in this repo.

STEP 0 — Verify the source table actually exists where you expect it, before anything else:
Run: SELECT COUNT(*) FROM \`sincere-hearth-273704.master_clean_niq.${TABLE}\` LIMIT 1
This pipeline is proven end-to-end for NIQ tables (master_clean_niq → marketshare_universe_niq). If ${TABLE} isn't there, do NOT guess at intrepid_pipeline_clean_product_level or any other dataset — that data path is
unconfirmed and was the source of real problems in an earlier session. Treat 'source table not found where expected' as a genuine blocker: stop, status='blocked', explain what you found instead.

STEP 1 — Check existing state before assuming anything about it:
Run: SELECT source, COUNT(*) FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy_map\`
WHERE master_table = '${TABLE}' GROUP BY source
Do not assume this is 0/0. A prior run building against this exact table with an unverified 'this category has never been touched' assumption was wrong — it had 2,255 undocumented rows. Whatever you find, record it in the category file you're about to write.

STEP 2 — Research and write docs/categories/${TABLE}.md, following _TEMPLATE.md's structure:
- Brand Scope: compute the REAL cumulative-GMV 95% threshold — ORDER BY brand GMV DESC, running SUM, find where cumulative/total >= 0.95. Do NOT just list the top 15-20 brands by magnitude and call that the 95% scope — that undercounted a real category's true brand universe by roughly 6x in an earlier session (~20 claimed vs. ~190 actual). List every brand in the real threshold, not a fixed-size snapshot.
- Official Store Allowlist: query DISTINCT merchant_name WHERE merchant_badge = 'Shopee Mall', per brand in scope. Exclude known multi-brand retailers per docs/llm-extraction-rules.md §4 (Sasa, Watsons, Boots, BEAUTRIUM, Tsuruha for beauty; BigC, Lotuss, Tops, Villa Market for grocery; check the full list in that doc for this category's vertical). Note parent-company stores (P&G, Unilever, Lion-style) as Pass-1-eligible for all brands they carry, not excluded as multi-brand.
- Scale: total row count, official-store row count, distinct product count. If official-store row count alone is large (tens of thousands+), say so explicitly — Pass 1 must still scope to the allowlist only, not the full Mall-badged pool.
- Existing map rows (from Step 1): document the real counts, not an assumption.
- Write the file, then commit it: git add docs/categories/${TABLE}.md && git commit -m 'Add category context for ${TABLE}, generated during headless Full Rebuild'

STEP 3 — Claim your SKU block atomically. Query the real current ceiling first, then use this exact pattern (DECLARE before BEGIN TRANSACTION — reversing that order is a real syntax error in BigQuery scripting, found
the hard way in an earlier session):
BEGIN
  DECLARE next_start INT64;
  BEGIN TRANSACTION;
  SET next_start = (SELECT COALESCE(MAX(block_end), 69000) + 1 FROM \`sincere-hearth-273704.magpie_reference.sku_block_registry\`);
  INSERT INTO \`sincere-hearth-273704.magpie_reference.sku_block_registry\`
    (block_start, block_end, master_table, scenario, claimed_at, status)
  VALUES (next_start, next_start + 1999, '${TABLE}', 'full_rebuild', CURRENT_TIMESTAMP(), 'ACTIVE');
  COMMIT TRANSACTION;
END;
Claim 2000 slots, not 1000 — an earlier Full Rebuild consumed 925 of 1000 slots in Pass 1 alone for a personal-care category (products fragment into many near-unique SKUs); 2000 gives real headroom for Pass 2
without needing a supplemental claim mid-run. Never query MAX(taxonomy_id) directly and assume it's safe to use — the atomic claim is what prevents two sessions colliding on the same ID range.

STEP 4 — Pass 1: build taxonomy ONLY from the Official Store Allowlist merchant names you just wrote into the category file — not the full Mall-badged pool.

STEP 5 — Pass 2: route remaining official-store-unmatched and reseller products primarily via bulk SQL text-matching of sku_name against the Pass 1 taxonomy you just built. Only read product images for individual products where text matching is genuinely ambiguous — do not vision-read the full candidate pool.

STEP 6 — For every taxonomy entry, populate product_line, sub_line, and variant as their own structured columns where a genuine value exists — do NOT leave them NULL while folding that same information into canonical_name as free text only. product_line is close to mandatory (populate it whenever a real on-label line name exists, per docs/llm-extraction-rules.md §3); sub_line and variant are optional — populate only where a real signal exists (e.g. an explicit fragrance/formula name, an 'Assorted' marker), leave NULL rather than guess when the text doesn't clearly support a split. This was gotten wrong before: 934 entries once shipped with product_line NULL on 100% of them because the extraction wrote good canonical_name text but never decomposed it into the structured fields.

2,255 existing HUMAN rows were found duplicating an LLM row in a prior session and the correct policy (manager-confirmed) was: delete a HUMAN row only if that same product also has an LLM row, never a blanket supersede. Do NOT delete any existing rows yourself regardless of source — deletion is a separate, deliberately manual/wrapper-side step, never something this session does.

Write via bq query DML only, never the streaming API.

STEP 7 — Before declaring status, self-check using the exact QA-gate queries from docs/headless-runbook.md's QA-gate-as-code section, run with --skip-coexistence semantics (dual-mapped scoped to source='LLM', and placeholder-leak). Report the actual numbers in findings — do not just assert 'gates passed' without the figures. Note: the structured-fields gate must count DISTINCT taxonomy entries excluding is_multi_size catch-alls, not raw product_taxonomy_map rows — the row-counting version of that query is wrong and was already found and fixed once (a category can show a misleadingly high NULL rate if a handful of catch-all entries fan out to many products).

If you hit a genuine blocker at any step — something wrong with these instructions, missing data, the source table not existing where expected, anything that would make proceeding unsafe — stop, write nothing further, and output status='blocked' with the blockers array populated. That is a valid, expected outcome, not a failure.

Output ONLY this JSON when done, nothing else:
{status: complete|partial|failed|blocked, rows_created, rows_mapped, taxonomy_id_range_used, findings, blockers}.
"

echo "============================"
echo "TAXONOMY EXTRACTION FINISHED"
