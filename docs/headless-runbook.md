# Headless Taxonomy Runbook

Runnable procedure for Full Rebuild, Assessment Only, and Targeted QA Fix taxonomy sessions via headless
`claude -p`, with no human checkpoint on writes. Companion to
[`docs/claude-code-headless-orchestration.md`](claude-code-headless-orchestration.md) (general headless
mechanics) and [`docs/superpowers/specs/2026-07-14-headless-taxonomy-runbook-design.md`](superpowers/specs/2026-07-14-headless-taxonomy-runbook-design.md)
(the design this implements — read its Addendum before touching universe refresh, the target table isn't what
`CLAUDE.md` says).

## Prerequisites

- `bq`/`gcloud` on PATH, authenticated against `sincere-hearth-273704` with BigQuery Data Editor on
  `magpie_reference` and `magpie`.
- `claude` CLI installed and authenticated (headless runs bill against a separate API-rate credit pool as of
  2026-06-15 — see `docs/claude-code-headless-orchestration.md`).
- `sql/migrations/002_add_sku_block_registry.sql` and
  `sql/migrations/003_add_universe_taxonomy_overlay.sql` have been run once
  (`docs/superpowers/plans/2026-07-14-headless-taxonomy-runbook.md` Tasks 1–2).

## Shared mechanics

### Atomic SKU block claim

Never query `MAX(taxonomy_id)` directly and assume it's still current by the time you insert — two sessions
racing on that read is exactly what caused the SKU-045000 collision recorded in `docs/llm-extraction-rules.md`'s
changelog. Claim atomically instead:

```sql
BEGIN
  DECLARE next_start INT64;
  BEGIN TRANSACTION;
  SET next_start = (SELECT COALESCE(MAX(block_end), 69000) + 1 FROM `sincere-hearth-273704.magpie_reference.sku_block_registry`);
  INSERT INTO `sincere-hearth-273704.magpie_reference.sku_block_registry`
    (block_start, block_end, master_table, scenario, claimed_at, status)
  VALUES (next_start, next_start + @block_size - 1, @table, @scenario, CURRENT_TIMESTAMP(), 'ACTIVE');
  COMMIT TRANSACTION;
END;
```

Block sizes by scenario: Assessment Only claims none (read-only). Targeted QA Fix claims ~200. Full Rebuild
claims ~1,000. `claude -p` receives the claimed `[block_start, block_end]` range as a literal prompt parameter
— it never queries `MAX(taxonomy_id)` itself.

### DML-not-streaming rule

Every headless-triggered insert into `product_taxonomy`/`product_taxonomy_map` must use `bq query` DML
(`INSERT INTO ... VALUES` or `INSERT ... SELECT`), never the streaming `insert_rows_json` API. DML rows are
immediately queryable (`docs/llm-extraction-rules.md`'s Streaming Buffer rule) — this is what makes a single
unattended run (claim → extract → QA gate → refresh, no 90-minute pause) possible at all.

### QA-gate-as-code

Bash function running these checks, non-zero exit blocks the refresh step:

```bash
# Usage: run_qa_gates <table> [--skip-coexistence]
# --skip-coexistence: use for Full Rebuild's pre-delete gate pass (Scenario: Full Rebuild, step 4) — HUMAN+LLM
# coexistence is EXPECTED and correct at that point (the narrowly-scoped delete hasn't run yet), not a real
# failure. Omit the flag for the post-delete pass (step 6) and for Targeted QA Fix, where coexistence is
# always a genuine bug. Policy revised 2026-07-16 (manager-confirmed): HUMAN rows are deleted only where they
# duplicate an existing LLM row for the same product — not a blanket supersede of every HUMAN row in the
# category — so post-delete coexistence should genuinely reach 0, this isn't a permanently-skipped check.
run_qa_gates() {
  local table="$1"
  local skip_coexistence="${2:-}"

  local dual_mapped
  dual_mapped=$(bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=csv \
    "SELECT COUNT(*) FROM (
       SELECT product_id FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy_map\`
       WHERE master_table = '${table}' AND source = 'LLM' GROUP BY product_id HAVING COUNT(*) > 1
     )" | tail -1)
  if [ "$dual_mapped" != "0" ]; then
    echo "QA GATE FAILED: ${dual_mapped} dual-mapped LLM products for ${table}"; return 1
  fi

  if [ "$skip_coexistence" != "--skip-coexistence" ]; then
    local human_llm_coexist
    human_llm_coexist=$(bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=csv \
      "SELECT COUNT(*) FROM (
         SELECT product_id FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy_map\`
         WHERE master_table = '${table}'
         GROUP BY product_id HAVING COUNTIF(source='LLM') > 0 AND COUNTIF(source='HUMAN') > 0
       )" | tail -1)
    if [ "$human_llm_coexist" != "0" ]; then
      echo "QA GATE FAILED: ${human_llm_coexist} products with HUMAN+LLM co-existence for ${table}"; return 1
    fi
  fi

  local placeholder_leak
  placeholder_leak=$(bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=csv \
    "SELECT COUNT(*) FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy\` pt
     JOIN \`sincere-hearth-273704.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
     WHERE m.master_table = '${table}'
       AND REGEXP_CONTAINS(LOWER(pt.canonical_name), r'\\b(undefined|null|n/a|tbd|all variants?|all sizes?|multiple variants?|multiple sizes?)\\b')" | tail -1)
  if [ "$placeholder_leak" != "0" ]; then
    echo "QA GATE FAILED: ${placeholder_leak} placeholder-leak canonical names for ${table}"; return 1
  fi

  # Added 2026-07-15 after shopee_sg_shampoo attempt #2 wrote 934 entries with product_line NULL on 100%
  # of them (normal baseline elsewhere in product_taxonomy is ~9%) — the extraction wrote good canonical_name
  # text but never decomposed it into the structured fields.
  #
  # Fixed 2026-07-16: the original version joined through product_taxonomy_map and counted map ROWS, which
  # fans out per product — a handful of legitimate is_multi_size catch-all entries (each covering hundreds of
  # products under one intentionally-NULL product_line, e.g. one Milbon entry covering 768 products) skewed
  # the percentage to 53% even after every real entry had been correctly backfilled (true rate: 0%). Now
  # counts DISTINCT taxonomy entries and excludes is_multi_size catch-alls from the denominator entirely —
  # those are supposed to be NULL, not a sign the extraction skipped the field. Threshold (50%) is deliberately
  # generous relative to the ~9% real-world baseline, to catch "field was ignored entirely" without
  # false-positiving on genuinely messy long-tail categories.
  local structured_fields_missing_pct
  structured_fields_missing_pct=$(bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=csv \
    "SELECT CAST(ROUND(100 * COUNTIF(product_line IS NULL) / COUNT(*)) AS INT64)
     FROM (
       SELECT DISTINCT pt.taxonomy_id, pt.product_line, pt.is_multi_size
       FROM \`sincere-hearth-273704.magpie_reference.product_taxonomy\` pt
       JOIN \`sincere-hearth-273704.magpie_reference.product_taxonomy_map\` m ON m.taxonomy_id = pt.taxonomy_id
       WHERE m.master_table = '${table}' AND m.source = 'LLM'
     )
     WHERE is_multi_size IS NOT TRUE" | tail -1)
  if [ -n "$structured_fields_missing_pct" ] && [ "$structured_fields_missing_pct" -gt 50 ]; then
    echo "QA GATE FAILED: ${structured_fields_missing_pct}% of LLM entries for ${table} have NULL product_line — extraction likely wrote canonical_name only, never decomposed into structured fields"; return 1
  fi

  echo "QA gates passed for ${table}"
  return 0
}
```

**Found via the `shopee_sg_shampoo` attempt #2 report (2026-07-15):** the dual-mapped check was originally
unscoped (no `source = 'LLM'` filter), so it double-counted the same legitimate HUMAN+LLM mid-rebuild
coexistence the second gate already exists to check — 847 products, not a real bug, but the unscoped query
couldn't tell the difference and would have blocked a wrapper that ran it naively. Scoped now. The
`--skip-coexistence` flag is the second half of the same fix — without it, `run_qa_gates()` as a single
all-or-nothing function couldn't express "coexistence is fine right now, check again after the delete,"
even though the Full Rebuild scenario's own prose already assumed that two-phase behavior.

(3 checks from `CLAUDE.md`'s QA Gates section, minus the NULL-size gate — that one needs manual judgment per
row per `CLAUDE.md`'s own caveat "or document why each NULL is legitimate," not a hard pass/fail — plus the G7
placeholder-leak check from `docs/taxonomy-pipeline-improvement-recommendations.md` Recommendation 1.)

### `claude -p` invocation contract

- `--output-format json`
- `--permission-mode bypassPermissions`
- `--max-turns N` (cap; documented per scenario below)
- Prompt receives the claimed `[block_start, block_end]` range as a literal parameter
- Required output shape:
  ```json
  {
    "status": "complete | partial | failed | blocked",
    "rows_created": 0,
    "rows_mapped": 0,
    "taxonomy_id_range_used": "SKU-XXXXXX-SKU-YYYYYY",
    "findings": [],
    "blockers": []
  }
  ```

**`blocked` is a distinct, legitimate outcome, not a failure** — added after the `shopee_sg_shampoo` attempt
2026-07-15, where the agent found real blockers (undocumented existing rows, ambiguous scope, infeasible scale
for a single session) and correctly stopped before writing anything, but had no schema slot for "stopped for a
real reason" and returned free-text prose instead of JSON. `status='blocked'` with a populated `blockers` array
lets the wrapper tell "asked a legitimate question" apart from "tried and failed" — see Error handling below for
how each is handled differently (a `blocked` outcome with zero rows written means the claimed block is still
valid and reusable for a retry; `failed`/`partial` should burn the block).

**The prompt must tell the agent it performs extraction itself.** The `shopee_sg_shampoo` attempt stalled
partly because the prompt didn't say this explicitly, and the agent pattern-matched to `CLAUDE.md`'s documented
"`ANTHROPIC_API_KEY` not set in subprocess" pitfall — which is about the *external Python pipeline's*
subprocess-based LLM calls, not applicable here. Every Full Rebuild / Targeted QA Fix prompt must state
plainly: *you* read product images and text directly with your own multimodal capabilities; you do not invoke
external scripts or need any API key beyond your own session auth.

**How to actually fetch a product image.** This environment has no tool that reads a remote image URL directly
for vision — `WebFetch` returns text, not pixels. `master_clean_niq.shopee_{country}_{category}` has an
undocumented `image` column (a direct CDN URL, not listed in `ARCHITECTURE.md`/`data-dictionary.md`'s schema
tables) that sometimes has literal embedded double-quotes corrupting naive parsing — strip those first. The
working pattern, confirmed in the `shopee_sg_facial_moisturiser` session: `curl -sL -o /tmp/img.jpg "<url>"` then use
the `Read` tool on the local file — reading a local file renders it for vision; reading a remote URL does not.
Do this two-step curl-then-Read for every image check. If `master_clean_niq` genuinely lacks the `image` column
for a given table, that is a real blocker — but check this table and this column before concluding images are
unavailable; do not stop at `raw_niq_history` (which only ever carries `product_specification`/
`product_description`, never an image URL) or at `intrepid_pipeline_clean_product_level` (a different, off-limits
dataset per `CLAUDE.md`).

### Universe refresh

**No `ALTER TABLE` on `marketshare_universe_niq`.** That table (the real FMCG output table — see
`docs/superpowers/specs/2026-07-14-headless-taxonomy-runbook-design.md` Addendum for why it's this one, not
`magpie.marketshare_universe`) is a shared, 10.9M-row production table. Instead of adding taxonomy columns to
it directly, taxonomy state lives in a separate overlay table,
`magpie_reference.universe_taxonomy_overlay` (`sql/migrations/003_add_universe_taxonomy_overlay.sql`), keyed
identically to `product_taxonomy_map`. This is the same pattern the pipeline already uses everywhere else —
`product_taxonomy_map` itself is an overlay on source data, not a column added to the source tables. Anyone
wanting combined data joins the two tables at query time on `(product_id, platform, country)`; the production
table's schema never changes. Farsight refresh is dropped (see the Addendum — same table-repurposing problem,
no `_niq` equivalent exists there).

One `MERGE` handles insert, update, and stale-row cleanup atomically (replaces the two-step NULLIFY+UPDATE
pattern from `CLAUDE.md`, which doesn't apply here since there's no column-nulling to do — a stale row is
removed from the overlay table outright):

```sql
MERGE `sincere-hearth-273704.magpie_reference.universe_taxonomy_overlay` t
USING (
  SELECT m.product_id, m.platform, m.country, m.master_table,
         pt.taxonomy_id, pt.canonical_name, m.source, m.confidence, m.meta_agent
  FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt ON m.taxonomy_id = pt.taxonomy_id
  WHERE m.master_table = @table
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY m.product_id, m.platform, m.country
    ORDER BY CASE m.source WHEN 'LLM' THEN 0 ELSE 1 END, m.taxonomy_id
  ) = 1
) src
ON t.product_id = src.product_id AND t.platform = src.platform AND t.country = src.country
  AND t.master_table = @table
WHEN MATCHED THEN UPDATE SET
  taxonomy_id = src.taxonomy_id,
  sku_type_complete = src.canonical_name,
  taxonomy_source = src.source,
  taxonomy_confidence = src.confidence,
  taxonomy_meta_agent = src.meta_agent,
  updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED BY SOURCE AND t.master_table = @table THEN DELETE
WHEN NOT MATCHED BY TARGET THEN INSERT
  (product_id, platform, country, master_table, taxonomy_id, sku_type_complete,
   taxonomy_source, taxonomy_confidence, taxonomy_meta_agent, updated_at)
  VALUES (src.product_id, src.platform, src.country, src.master_table, src.taxonomy_id, src.canonical_name,
          src.source, src.confidence, src.meta_agent, CURRENT_TIMESTAMP());
```

The `AND t.master_table = @table` condition on the `WHEN NOT MATCHED BY SOURCE` branch is load-bearing — this
overlay table holds rows for every category, and without that condition BigQuery would try to delete every
other category's rows too (they're also "not matched" by a `src` that's filtered to just `@table`).

(Join key is `product_id + platform + country` — the real ADR-006 composite key, not `master_table` alone,
matching the correction already proven in `docs/superpowers/plans/2026-07-14-size-regex-pass.md`'s backfill query
this same session.)

## Scenario: Assessment Only

Read-only — no SKU claim, no writes, no QA gates, no universe refresh. This is the existing pattern from
[`docs/claude-code-headless-orchestration.md`](claude-code-headless-orchestration.md)'s reference
implementation almost verbatim; this section is a pointer, not a re-implementation.

```bash
GOOGLE_APPLICATION_CREDENTIALS=/tmp/audit_readonly_creds.json \
claude -p --output-format json --permission-mode bypassPermissions "
Quality assessment for ${TABLE} — sample top 50 products by GMV ${MONTH}, review current taxonomy mapping
against magpie_reference.product_taxonomy_map and product_taxonomy.
Output ONLY this JSON, nothing else: {category, decision: patch|fresh_run|healthy, confidence, findings: [...], proposed_patch_sql: null|string}.
Do NOT run any UPDATE/INSERT/DELETE. Read-only assessment only.
" > "audits/${TABLE}/$(date +%Y-%m-%d).json"
```

## Scenario: Targeted QA Fix

Small SKU block (~200), narrow prompt scope (specific flagged products, not a full category rebuild), QA gates
scoped to affected `product_id`s only, universe refresh runs but only touches the products actually rerouted.

**Scope boundary:** this scenario fixes existing-row quality defects only — `docs/quality-standards.md`
§3's D1–D5 dimensions (generic-stub product lines, missing size/variant/pack-count, wrong product line) and
§4's hard gates G1/G2/G3/G5/G6, plus `brand_mismatch` review per `docs/brand-extraction.md`.
Coverage gaps (products with `taxonomy_id IS NULL`) are explicitly out of scope for this script — see
"Scenario: Full Rebuild" below, which now also covers re-running against an already-complete category to
close a live coverage gap.

**Since 2026-07-21, this scenario has two modes** (`script/targeted_qa_fix.sh` picks automatically):
- **Brief mode** (unchanged): `docs/categories/<table>.md` has a filled-in `## Targeted QA Fix Brief` section
  — executes exactly what it specifies.
- **Auto-discovery mode** (new default when no real Brief exists): reviews `product_taxonomy` entries the
  category hasn't confidently reviewed yet, tracked via `product_taxonomy._meta`, against a two-tier SQL +
  LLM checklist, and fixes what it finds — no human-written Brief required. See
  [docs/superpowers/specs/2026-07-21-taxonomy-review-loop-design.md](superpowers/specs/2026-07-21-taxonomy-review-loop-design.md)
  for the full mechanics.

1. Claim a ~200-slot block (Shared mechanics § Atomic SKU block claim, `@block_size = 200`, `@scenario =
   'targeted_qa_fix'`).
2. Run `qa_report.sh @table` *before* invoking `claude -p` and pass its output into the prompt as
   gate-directed scope: entry-level gate failures (placeholder-leak, structured-fields NULL%, 'all
   variant/size' name, canonical_name fields, garbled brand text) become explicit fix targets; map-level
   failures (dual-mapped, HUMAN+LLM coexistence, duplicate product_id, duplicate product+taxon) are
   report-only, since this scenario never deletes a `product_taxonomy_map` row. See
   [docs/superpowers/specs/2026-07-23-qa-fix-gate-direction-and-coverage-design.md](superpowers/specs/2026-07-23-qa-fix-gate-direction-and-coverage-design.md)
   for the full mechanics. Since
   [docs/superpowers/specs/2026-07-23-qa-fix-throughput-diagnosis-design.md](superpowers/specs/2026-07-23-qa-fix-throughput-diagnosis-design.md),
   a confirmed permanent false positive on an entry-level gate (e.g. an all-numeral brand tripping the
   letters-only `garbled brand text` check) can be recorded once in `magpie_reference.qa_gate_exceptions` so
   later sessions stop re-verifying it every run.
3. Invoke `claude -p` with the claimed range and the specific fix list (pack-count corrections, wrong-size
   reroutes, bundle tagging — see the Notion doc's Example C pattern), `--max-turns 30`.
4. Run QA gates (Shared mechanics § QA-gate-as-code) scoped to `master_table = @table` — the gate queries
   already scope by `master_table`, no change needed for the narrower fix scope.
5. If gates pass, run universe refresh (Shared mechanics § Universe refresh) for `@table`.
6. If `claude -p` fails or gates fail, mark the claimed block `FAILED_QA` in `sku_block_registry`:
   ```sql
   UPDATE `sincere-hearth-273704.magpie_reference.sku_block_registry`
   SET status = 'FAILED_QA' WHERE block_start = @claimed_block_start AND master_table = @table;
   ```
7. Regardless of outcome (blocked, failed, noop, or refreshed), run `qa_coverage_report.sh @table` and report
   the pending-review count — this always fires, via an `EXIT` trap in `script/targeted_qa_fix.sh`, not a
   conditional step an operator has to remember to run. Since
   [docs/superpowers/specs/2026-07-23-qa-fix-throughput-diagnosis-design.md](superpowers/specs/2026-07-23-qa-fix-throughput-diagnosis-design.md),
   this report splits into four buckets, not three — a freshly-fixed row awaiting its next re-review
   ("fixed pending recheck") is reported separately from a row that has been genuinely reviewed and still
   isn't confident, so real fix throughput within a session is visible instead of hidden inside a single
   "unconfident" number.

## Scenario: Full Rebuild

`script/headless_taxonomy.sh` implements two scenarios, auto-selected from live BigQuery state rather than
chosen by the operator — the script itself checks whether any `source='LLM'` `product_taxonomy_map` rows
exist for the target table and picks accordingly. **This check is scoped to `source='LLM'` specifically, not
any row** — almost every category has `source='HUMAN'` keyword-seed rows before Phase 5 ever runs (see
`docs/quality-standards.md`'s coverage table), and treating those as evidence of prior LLM coverage misroutes
a genuine first pass into the top-up scenario (caught live against `shopee_sg_diapers`, which had 908 HUMAN
rows and 0 LLM rows — the agent correctly detected the mismatch and returned `status='blocked'` rather than
proceed):

- **First run** (0 existing LLM rows): full SKU block (~2,000 slots), rebuilds a category's taxonomy from
  scratch, re-extracts via Pass 1 (official stores) + Pass 2 (reseller routing), then QA gates. This is the
  procedure documented below.
- **Top-up** (existing LLM rows present): the script always re-checks whether the live 95%-cumulative-GMV
  (GWP-zeroed) worklist still has products with no `taxonomy_id`, regardless of `docs/categories/STATUS.md`
  marking the category "complete" — categories accumulate new listings over time. If the live gap is 0, the
  script exits immediately with no SKU claim and no `claude -p` call. If the gap is nonzero, it claims a
  smaller block (sized to the gap, floor 200 / cap 2,000) and works only that live gap via reuse-before-mint
  against the category's existing taxonomy — never a full Pass 1/Pass 2 re-extraction.

**Priority is coverage, not precision.** Both scenarios' prompts require bulk-first processing — grouped SQL
text-matching against existing/newly-built taxonomy, not one image read per product — and explicitly forbid
self-limiting to a small sample; the agent should attempt the entire live worklist within its turn budget,
not silently mirror an older, smaller session-size convention from the category's own QA History. (Caught
live against `shopee_th_suncare`: a top-up run resolved only 31 of 790 in-scope rows, having matched an old
`targeted_qa_fix.sh`-era cadence of 33–58/session instead of using this scenario's real budget.) Per-row
quality — exact `product_line` wording, variant capture, pack-count edge cases — is intentionally
deprioritized here; that precision work belongs to `targeted_qa_fix.sh`, scoped by GMV impact. Hard gates
(G1, G2, G4, G5) are the one exception: those are structural invariants and always apply, even in a
speed-first pass.

`MAX_TURNS` is an optional 3rd CLI argument (`<TABLE> [MONTH] [MAX_TURNS]`, default 300) for scaling the
session's turn budget on a large gap, e.g. `./script/headless_taxonomy.sh shopee_th_suncare "" 800`.

The rest of this section describes the first-run procedure.

**Worked example: `shopee_sg_shampoo`.** Attempt #1 (2026-07-15) claimed a real block (`SKU-069001`–
`SKU-070000`, still `ACTIVE`, zero rows written) and correctly stopped itself before writing anything — see
`docs/categories/shopee_sg_shampoo.md`'s QA History for what it found (2,255 undocumented existing `HUMAN` rows,
ambiguous extraction-ownership instructions, a 187,902-row official-store pool too large to vision-read in one
session). The category file and the prompt below are both corrected as a result. **Do not run the `claude -p`
step without deciding to actually kick off SG's first taxonomy extraction** — it's a real, costly LLM session
that writes to production once it starts.

1. The block is already claimed — reuse it, don't claim a new one (verify first, don't just trust this doc):
   ```bash
   bq query --use_legacy_sql=false --project_id=sincere-hearth-273704 --format=pretty \
     "SELECT block_start, block_end, status FROM \`sincere-hearth-273704.magpie_reference.sku_block_registry\` WHERE master_table = 'shopee_sg_shampoo'"
   ```
   Expected: `69001, 70000, ACTIVE`. If it shows `FAILED_QA`/`COMPLETE` instead, claim a fresh block per Shared
   mechanics § Atomic SKU block claim before proceeding.
2. Invoke `claude -p` — corrected prompt, addressing all three blockers attempt #1 found:
   ```bash
   claude -p --output-format json --permission-mode bypassPermissions --max-turns 200 "
   Full Rebuild session for shopee_sg_shampoo. Read docs/categories/shopee_sg_shampoo.md in full, including the Scale
   and 'Existing HUMAN rows' sections — both are load-bearing, not background.

   You perform extraction yourself, directly, using your own multimodal reading of product images and text.
   You do not invoke external scripts or subprocesses and do not need any API key beyond your own session
   auth — CLAUDE.md's ANTHROPIC_API_KEY note is about a different, external pipeline that does not exist here.

   You have been pre-assigned SKU block SKU-069001–SKU-070000 (already claimed in sku_block_registry, status
   ACTIVE) — use only this range, never query MAX(taxonomy_id) yourself.

   Pass 1: build taxonomy ONLY from the Official Store Allowlist merchant names listed in shopee_sg_shampoo.md — not
   all 187,902 Shopee-Mall-badged rows, just those specific merchant names.

   Pass 2: route the remaining official-store-eligible-but-unmatched and reseller products primarily via bulk
   SQL text-matching of sku_name against the Pass 1 taxonomy you just built. Only read product images for
   individual products where text matching is genuinely ambiguous — do not vision-read the full candidate pool.

   For every taxonomy entry, populate product_line, sub_line, and variant as their own structured columns —
   do NOT leave them NULL while folding that same information into canonical_name as free text. canonical_name
   should be a human-readable composite of the structured fields, not a replacement for populating them.
   product_line is the on-label product line name per docs/llm-extraction-rules.md §3 (e.g. "Intensive Care
   Deep Restore", not a generic category word). Worked example: for a product whose canonical_name would read
   "Amos Professional PURE SMART Line dandruff care Shampoo FRESH 500ml", set product_line = "PURE SMART Line
   dandruff care Shampoo" and variant = "FRESH", not NULL/NULL with that text only living in canonical_name.
   This was gotten wrong in a prior run against this exact category (100% NULL on all 3 fields) — read
   shopee_sg_shampoo.md's Taxonomy Design Notes for the full finding before starting.

   2,255 existing source='HUMAN' rows exist in product_taxonomy_map for this category. Do NOT delete any of
   them yourself. The wrapper deletes HUMAN rows after your run, but only the ones that duplicate a product
   you've also mapped with an LLM row — never a blanket delete of every HUMAN row in the category (see
   shopee_sg_shampoo.md's "Existing HUMAN rows" section for the exact scope).

   Write via bq query DML only, never the streaming API.

   If you hit a genuine blocker (something wrong with the instructions above, missing data, anything that
   would make proceeding unsafe) — stop, do not write anything, and output status='blocked' with the blockers
   array populated. That is a valid, expected outcome, not a failure.

   Output ONLY this JSON when done, nothing else:
   {status: complete|partial|failed|blocked, rows_created, rows_mapped, taxonomy_id_range_used, findings, blockers}.
   "
   ```
3. **If `status='blocked'`:** stop. Do not run QA gates or refresh. Report the `blockers` array to a human —
   this is a real question, not an error to route around. The claimed block stays `ACTIVE` (nothing was
   written) and is safe to reuse once the blocker is resolved — do not mark it `FAILED_QA`.
4. **If `status='complete'` or `'partial'` with `rows_created > 0`:** run `run_qa_gates shopee_sg_shampoo
   --skip-coexistence` (Shared mechanics § QA-gate-as-code). Coexistence is expected to still be true at this
   point — the delete in step 5 hasn't run yet.
5. If that passes, delete the HUMAN rows that duplicate an existing LLM row for the same product — **and only
   those** (policy confirmed 2026-07-16: not a blanket supersede of every HUMAN row in the category):
   ```sql
   DELETE FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
   WHERE master_table = 'shopee_sg_shampoo' AND source = 'HUMAN'
     AND product_id IN (
       SELECT product_id FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
       WHERE master_table = 'shopee_sg_shampoo' AND source = 'LLM'
     );
   ```
   HUMAN rows for products with **no** LLM row are left untouched — deleting those would leave that product
   with no taxonomy at all, worse than the keyword-seed routing it has today.
6. Run `run_qa_gates shopee_sg_shampoo` (no flag) — coexistence should now genuinely be 0, since step 5 deleted
   exactly the overlapping set. If it isn't 0, something inserted new HUMAN/LLM overlap between steps 4 and 6 —
   investigate before refresh, don't assume the gate is wrong.
7. If gates pass, run universe refresh for `shopee_sg_shampoo` (Shared mechanics § Universe refresh).
8. On any real failure (non-`blocked` bad output, persistent gate failure after step 6), mark the block
   `FAILED_QA` — same pattern as Targeted QA Fix step 5. Don't do this for a `blocked` outcome with zero rows
   written (step 3) — that block is still good.

## Error handling

- **`status='blocked'` is not a failure.** Confirmed live 2026-07-15 (`shopee_sg_shampoo` attempt #1): a
  careful agent can find real, legitimate reasons to stop before writing anything — undocumented existing
  state, ambiguous instructions, infeasible scope for one session. Zero rows written means the claimed block
  is still valid and unused — **do not mark it `FAILED_QA`**, leave it `ACTIVE` and reuse it once the blocker
  is resolved. Report the `blockers` array to a human; this is a real question needing an answer, not an error
  to route around.
- `claude -p` exits non-zero, hits `--max-turns` without completing, or returns genuinely malformed/missing-field
  JSON (not a well-formed `status='blocked'` response) → abort **before** QA gates and refresh. Mark the
  claimed block `FAILED_QA`:
  ```sql
  UPDATE `sincere-hearth-273704.magpie_reference.sku_block_registry`
  SET status = 'FAILED_QA' WHERE block_start = @claimed_block_start AND master_table = @table;
  ```
  Never reused, never deleted — a burned block is free, a reused one is a collision. Log the raw `claude -p`
  output for follow-up.
- QA gates fail post-run → same abort-before-refresh behavior. New rows stay in `product_taxonomy` /
  `product_taxonomy_map` but never reach `universe_taxonomy_overlay` — a bad run is inert, not silently live to
  analysts.
- The refresh `MERGE` itself fails (BQ error, e.g. "must match at most one source row for each target row") →
  the `QUALIFY ROW_NUMBER()` clause in the `USING` subquery already guards against the multi-model-variant
  version of this error (the same fix `CLAUDE.md`'s farsight troubleshooting entry documents for the old
  NULLIFY+UPDATE pattern — same root cause, applies equally to `MERGE`'s `USING` subquery).

## Queue Mode

An alternative to running `headless_taxonomy.sh` / `targeted_qa_fix.sh` by hand: submit them as
priority-queued tasks and let one or more `script/queue_worker.sh` processes pull and run them. See
`docs/superpowers/specs/2026-07-27-task-queue-design.md` for the full design.

### Setup

1. `psql` must be installed and on `$PATH` (or run it via `docker run --rm postgres:16 psql ...` if you'd rather not install it).
2. Copy `.env.example` to `.env` and set `QUEUE_DATABASE_URL`. Also set `QUEUE_SCHEMA` if your `task_queue` table lives in a non-default schema (the current deployment uses a NocoDB-hosted Postgres, schema `p4ct2g2urhzcfnz` — not `public`).
3. Apply the one-time migration: `source script/load_env.sh; QUEUE_TABLE="${QUEUE_SCHEMA:-public}.task_queue"; queue_psql "CREATE UNIQUE INDEX IF NOT EXISTS one_running_task_per_table ON ${QUEUE_TABLE} (table_name) WHERE status = 'running';"`. All queue tooling reads/writes the fully-qualified `${QUEUE_TABLE}`, never bare `task_queue` and never a `SET search_path` — see the design spec for why (a live-confirmed leak across this PgBouncer's pooled connections, not a style preference).

**Never manage queue rows through NocoDB's own grid UI** if `task_queue` happens to live in a NocoDB-hosted database (as the current deployment does) — NocoDB soft-deletes (sets its own `__nc_deleted` flag) without touching `status`, so a row "deleted" that way would still read `status='queued'` and the worker would still claim and run it. Always use `queue_ctl.sh cancel` to remove a queued task.

### Submitting and managing tasks

```bash
source script/load_env.sh
script/queue_ctl.sh submit shopee_th_shampoo headless_taxonomy --priority 200
script/queue_ctl.sh submit shopee_th_shampoo targeted_qa_fix --loop-count 1 --priority 100
script/queue_ctl.sh list --status queued
script/queue_ctl.sh priority <id> 500
script/queue_ctl.sh cancel <id>
```

The same operations are also exposed as a Windmill UI, built separately against the same Postgres
table — see the design spec's §7 for the UI's own build prompt.

### Running workers

```bash
source script/load_env.sh
script/queue_worker.sh
```

Each worker is a long-running loop: it claims the highest-priority queued task for a table no other
worker currently holds, runs the appropriate script up to `loop_count` times (stopping early if the
script's own live pre-check finds nothing left to do), and persists the result. Run multiple instances
(tmux, nohup, systemd — your choice) to process several categories concurrently; two workers will never
claim the same `table_name` at once — see the design spec's §3 for why.

### `loop_count` guidance

- `headless_taxonomy.sh` tasks and `targeted_qa_fix.sh` auto-discovery-mode tasks can self-detect
  "nothing left to do" (a live `gap_count`/worklist-count pre-check re-run at the start of every
  iteration) — `loop_count = 3` (the default) is safe and will stop itself early once the category is
  caught up.
- `targeted_qa_fix.sh` **brief-mode** tasks (a hand-written `## Targeted QA Fix Brief` section) cannot
  self-detect completion — set `--loop-count 1` for those unless you specifically know the brief needs
  multiple passes, or the wrapper will simply re-run the same brief redundantly.
