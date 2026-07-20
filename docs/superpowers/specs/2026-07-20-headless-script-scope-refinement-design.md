# Design: Headless Script Scope Refinement — Coverage vs. Quality Fix

> Status: approved design, not yet implemented.
> Companion to [`docs/headless-runbook.md`](../../headless-runbook.md),
> [`docs/headless-scripts-flow.md`](../../headless-scripts-flow.md),
> [`script/headless_taxonomy.sh`](../../../script/headless_taxonomy.sh),
> [`script/targeted_qa_fix.sh`](../../../script/targeted_qa_fix.sh),
> [`docs/llm-extraction-rules.md`](../../llm-extraction-rules.md),
> [`docs/quality-standards.md`](../../quality-standards.md),
> [`docs/product-lifecycle.md`](../../product-lifecycle.md), and `ARCHITECTURE.md`.

---

## Problem

Four related issues found while reviewing the headless taxonomy scripts:

1. **`script/headless_taxonomy.sh` only knows how to run once.** Its prompt opens with "No category
   context file exists yet for this table — you are creating one as part of this run," and STEP 1 only
   *documents* existing state rather than acting on it. All 20 TH categories are marked "✅ ✅" complete in
   `docs/categories/STATUS.md`, so as written the script has no framing for "re-check this category for
   products that fell into the 95%-GMV scope since the last run and still have no taxonomy" — which is a
   real, recurring need (new listings appear, GMV ranks shift monthly).

2. **`script/targeted_qa_fix.sh`'s real-world usage has drifted into doing that same coverage work,
   inconsistently.** `docs/categories/th_suncare.md`'s current `## Targeted QA Fix Brief` is explicitly
   titled "NULL-COVERAGE BACKFILL" and its STEP 0 query is exactly the reference query behind this
   design — i.e., the exact job (1) describes, done through the wrong script. This matters because the two
   scripts carry different verification rigor: `targeted_qa_fix.sh` independently re-runs QA gates via
   `script/qa_report.sh` before refreshing the universe overlay; `headless_taxonomy.sh` only self-certifies
   inside the one `claude -p` call. A coverage gap closed via one script gets more scrutiny than the same
   gap closed via the other, for no principled reason — the fix is to give each script one job.

3. **The §8 brand-GMV keyword gate risks silently dropping individual in-scope products.**
   `docs/llm-extraction-rules.md` §8's keyword guard (e.g. `has_body_wash_keyword(sku_name) = TRUE`) is a
   legitimate control on which *brands* enter the 95%-GMV rank for Pass-1-allowlist purposes (keeps an
   unrelated hand-wash-only brand out of body_wash's brand list). Nothing in the docs currently stops the
   same style of filter from being applied to decide whether an *individual* high-GMV product is worth
   extracting at all — which would silently skip real, miscategorized Mall-seller listings whose `sku_name`
   doesn't happen to match the expected keywords, before the LLM ever reads them.

4. **`ARCHITECTURE.md` and `docs/product-lifecycle.md` describe a stale universe-refresh mechanism.**
   `ARCHITECTURE.md` line 246 correctly states taxonomy columns live in
   `magpie_reference.universe_taxonomy_overlay`, joined at query time — but lines 286–303, in the same
   file, still show `UPDATE marketshare_universe u SET taxonomy_id = ...`, a direct DML write to the
   production table. `docs/product-lifecycle.md`'s §3 stage diagram and §7 worked example have the same
   stale pattern. Both contradict the overlay-table `MERGE` pattern already correct in
   `docs/headless-runbook.md`, `CLAUDE.md`, and both scripts' actual implementations.

GWP handling (`flag_GWP` products must stay in the extraction candidate set but contribute 0 to
cumulative-GMV threshold math) is not a separate defect — `ADR-005` already made this the policy
(2026-07-17 revision) — but the worklist query that drives re-runs must actually implement it, not just
state it. This falls out of item 1's fix directly.

---

## Deliverable scope

| File | Change |
|------|--------|
| `script/headless_taxonomy.sh` | Rewritten: bash pre-check gates on a live GMV/coverage query; auto-detects first-run vs. top-up scenario; prompt updated for both scenarios plus the keyword-filter fix |
| `script/targeted_qa_fix.sh` | STEP 3 prompt text narrowed to quality-standard violations; adds a wrong-tool guard against NULL-coverage briefs |
| `docs/llm-extraction-rules.md` | §8 edited to scope the keyword gate to brand-ranking only, with an explicit "never pre-filter individual products" line |
| `docs/headless-runbook.md` | "Scenario: Targeted QA Fix" and "Scenario: Full Rebuild" prose updated for the new scope boundary and re-runnability |
| `docs/headless-scripts-flow.md` | Flow diagrams/tables updated to match both scripts' new behavior |
| `docs/categories/_TEMPLATE.md` | Adds a `## Targeted QA Fix Brief` section (doesn't exist in the template today) with the scope boundary spelled out |
| `ARCHITECTURE.md` | Lines 286–303 replaced with the overlay `MERGE` pattern, consistent with line 246 |
| `docs/product-lifecycle.md` | §3 diagram and §7 worked example updated to the overlay-table pattern |

No `pipeline/*.py` changes, no schema migrations, no changes to `script/qa_report.sh`.
`docs/categories/th_suncare.md`'s existing Brief is **not** rewritten as part of this change — see Open
Follow-ups.

---

## 1. `script/headless_taxonomy.sh` — repeatable coverage-closer

### New top-level flow

```
$ ./script/headless_taxonomy.sh <TABLE> [MONTH]
        │
   no TABLE arg? ──yes──▶ print usage, exit 1
        │ no
        ▼
  MONTH="${2:-$(bq query ... SELECT FORMAT_DATE('%Y-%m', MAX(month)) FROM master_clean_niq.<table>)}"
        │
        ▼
  gap_count = bq query: COUNT(*) from the GWP-zeroed, 95%-cumulative-GMV, canonical_name IS NULL
              worklist (the reference query, parameterized by TABLE/MONTH)
        │
   gap_count == 0? ──yes──▶ print "no in-scope coverage gap for <table>/<month>", exit 0
        │ no                 (no claude -p call, no SKU claim — this is what makes re-running against an
        │                     already-complete category cheap)
        ▼
  existing_rows = bq query: COUNT(*) FROM product_taxonomy_map WHERE master_table = <table>
        │
   existing_rows == 0? ──yes──▶ SCENARIO = first_run
        │ no                     SCENARIO = top_up
        ▼
  claude -p  (prompt varies by SCENARIO, see below)
        │
        ▼
  print "TAXONOMY EXTRACTION FINISHED"
```

The gap-count and existing-rows checks are cheap `COUNT(*)` queries the wrapper runs itself — they decide
*whether to spend an LLM call at all* and *which scenario to run*, without embedding result rows into the
prompt (matching the existing pattern where the agent runs its own STEP 0/STEP 1 queries rather than
having results piped in as text).

### The worklist query (shared by the bash gap-check and the agent's own STEP 0)

Adapted from the reference query, parameterized by `${TABLE}` / `${MONTH}`:

```sql
WITH base AS (
  SELECT s.product_id, s.model_id, s.merchant_name, s.merchant_badge, s.sku_name, s.image,
         s.gmv_monthly, s.sold_monthly, s.flag_GWP,
         bd.canonical_name AS brand, pt.canonical_name AS canonical_name
  FROM `sincere-hearth-273704.master_clean_niq.${TABLE}` s
  LEFT JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_map` ptm
    ON ptm.product_id = s.product_id AND ptm.master_table = '${TABLE}'
  LEFT JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt ON pt.taxonomy_id = ptm.taxonomy_id
  LEFT JOIN `sincere-hearth-273704.magpie_reference.brand_dict` bd ON bd.brand_id = pt.brand_id
  WHERE FORMAT_DATE('%Y-%m', s.month) = '${MONTH}'
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
```

`flag_GWP` products stay in `base` and can appear in the result set (never excluded from the candidate
pool — satisfies "GWP not skipped"); they contribute `0` to both the numerator and denominator of the
cumulative-GMV calculation (satisfies "exclude GWP from the GMV calculation"). No separate GWP logic is
needed anywhere else — this query *is* the fix.

**Consistency note:** STEP 2's existing brand-scope ranking query (used to build the Official Store
Allowlist) should apply the same `CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END` zeroing for its
cumulative-GMV brand threshold, per `ADR-005`'s "GMV is still zeroed in brand ranking ... calculations."
This was already policy; it just needs to be stated in the STEP 2 instruction text so a first-run
invocation computes brand scope the same way the gap-check does.

### Scenario: `first_run`

Same as today's Full Rebuild (write `docs/categories/${TABLE}.md` from `_TEMPLATE.md`, Pass 1 + Pass 2,
claim a 2,000-slot block) — this is what happens when a category has never been touched at all. One
addition: the STEP 0 "verify table exists" and STEP 1 "check existing state" steps stay, but the framing
sentence changes from "No category context file exists yet for this table" to "This is a first-run
invocation — ${existing_rows} confirmed 0 existing `product_taxonomy_map` rows for this table" (still
re-verified live by the agent, not trusted from the wrapper's earlier count, consistent with the "never
trust a stale number" pattern already in this script and `targeted_qa_fix.sh`).

### Scenario: `top_up`

New. Applies whenever a category already has taxonomy coverage but the live worklist query still returns
rows. Prompt structure (parallels `targeted_qa_fix.sh`'s shape, but self-discovers scope instead of reading
a hand-written Brief):

1. Read `CLAUDE.md`, `ARCHITECTURE.md`, `docs/llm-extraction-rules.md`, `docs/quality-standards.md`,
   `docs/headless-runbook.md`, `docs/categories/${TABLE}.md` (existing category file — brand scope,
   allowlist, scope rules already documented there; do not rediscover from scratch).
2. Run the worklist query above (STEP 0) with `--max_rows=100000` or `--format=csv` — `bq query`'s display
   truncates to 100 rows by default, a documented prior failure mode (`th_suncare.md`'s session notes).
3. Claim `min(max(gap_count, 200), 2000)` SKU slots atomically, `scenario='taxonomy_topup'`.
4. For each worklist product: reuse-before-mint against the category's existing taxonomy first
   (`product-lifecycle.md` §4's match-or-create decision tree); only mint a new entry when no existing
   brand+line+size+pack entry fits. Read image + text directly — **never pre-filter this worklist by a
   keyword/category-relevance heuristic before evaluating a product** (see §3 below); the match-or-create
   category/type gate, applied after reading the product, is what may conclude a product doesn't belong and
   leave it NULL.
5. Write via DML only, `meta_agent='CLAUDE_CODE'`, never delete existing rows.
6. Append a dated row to `${TABLE}.md`'s `## QA History` table and commit.
7. Self-check QA gates (same as today's STEP 7), report actual numbers.
8. `status='blocked'` remains a valid, expected outcome.

Universe refresh is **not** run by this script in either scenario, unchanged from today — that stays a
separate step, matching `docs/headless-scripts-flow.md`'s existing note that `headless_taxonomy.sh` never
touches `universe_taxonomy_overlay`.

---

## 2. `script/targeted_qa_fix.sh` — narrow to quality-standard violations only

### The conflation, concretely

`docs/categories/th_suncare.md`'s current `## Targeted QA Fix Brief` opens with "**Verdict:
NULL-COVERAGE BACKFILL**" and its STEP 0 is the same reference query this design adopts for
`headless_taxonomy.sh`. That is exactly the coverage job from §1 — done through the script whose entire
premise (per its own design doc) is "correctness on a table that's already live in production." Going
forward, coverage work belongs to `headless_taxonomy.sh`'s `top_up` scenario; `targeted_qa_fix.sh` is left
with quality-standards.md's D1–D5 defects (generic-stub product lines, missing size/variant/pack-count,
wrong product line) and hard gates G1/G2/G3/G5/G6, plus `brand_mismatch` review per
`docs/brand-extraction.md` — all on rows that **already have** a `taxonomy_id`.

(D6 — "In-Scope NULL Coverage" — stops being this script's responsibility even though it's nominally one
of quality-standards.md's 6 dimensions; it's being carved out to `headless_taxonomy.sh` specifically
because closing it means creating new taxonomy rows, not fixing existing ones. `docs/quality-standards.md`
§3's D6 row gets a one-line pointer added: "Remediated via `headless_taxonomy.sh`'s top-up scenario, not
`targeted_qa_fix.sh`.")

### `script/targeted_qa_fix.sh` prompt change

STEP 3 currently reads:

> "Execute exactly the fixes described in `${category_file}`'s `## Targeted QA Fix Brief` section:
> pack-count / size / bundle corrections, **the NULL-coverage pass**, whatever that section specifies."

Change to:

> "Execute exactly the fixes described in `${category_file}`'s `## Targeted QA Fix Brief` section:
> pack-count / size / bundle / product-line / variant corrections, hard-gate violations (G1, G2, G3, G5,
> G6), `brand_mismatch` review per `docs/brand-extraction.md` — whatever that section specifies. **This
> script fixes existing taxonomy entries; it never creates coverage for products with `taxonomy_id IS
> NULL`.** If the Brief's scope is actually a NULL-coverage/unmapped-product backfill, that is a genuine
> blocker — the correct tool is `script/headless_taxonomy.sh`'s top-up scenario, not this script: stop,
> write nothing, output `status='blocked'` explaining the mismatch."

### `docs/categories/_TEMPLATE.md`

Add a `## Targeted QA Fix Brief` section (absent from the template today, only ever added ad hoc per
category) directly after `## QA History`:

```markdown
## Targeted QA Fix Brief

> Scope: quality-standard violations on products that **already have** a `taxonomy_id` — generic-stub
> product lines, missing size/variant/pack-count, wrong product line, hard-gate violations (G1, G2, G3,
> G5, G6), brand_mismatch review. Never products with `taxonomy_id IS NULL` — that coverage gap is
> `script/headless_taxonomy.sh`'s job (its live worklist query finds it automatically; no brief needed).

**Verdict:** {defect class, e.g. "D1 Tier-C generic stubs" / "D5 pack-count errors"}

{Fix A/B/C description, current-state snapshot, category-specific QA gate notes}
```

### `docs/headless-runbook.md` / `docs/headless-scripts-flow.md`

Both get the same one-line scope boundary added to their "Scenario: Targeted QA Fix" / `targeted_qa_fix.sh`
sections: *"Scope is existing-row quality defects only (quality-standards.md D1–D5, hard gates
G1/G2/G3/G5/G6, brand_mismatch). Coverage gaps (`taxonomy_id IS NULL`) are out of scope for this script —
see `headless_taxonomy.sh`'s top-up scenario."* `headless-runbook.md`'s "Scenario: Full Rebuild" section
gets a note that Full Rebuild and the new top-up mode are both implemented by the same
`headless_taxonomy.sh`, auto-selected by live state rather than chosen by the operator.

---

## 3. Keyword-relevance gate — brand ranking only, never a per-product pre-filter

`docs/llm-extraction-rules.md` §8's "Brand scope GMV threshold — filter to category sku_names first" stays
for its original purpose (keeping e.g. a hand-wash-only brand out of body_wash's brand rank). Add:

> **This keyword gate is a brand-ranking control only — it must never be used to decide whether an
> individual product gets extracted.** Every product returned by the in-scope worklist (top-95%-cumulative
> GMV, GWP-zeroed, plus official-store listings per `quality-standards.md` §2) must be read (image + text)
> by the LLM. Only the LLM's own category/type gate (`product-lifecycle.md` §4.2), applied *after* reading
> the product, may conclude a product doesn't belong to this category and leave it NULL — never a
> pre-extraction keyword/text heuristic. This matters most for high-GMV Mall-seller listings that are
> genuinely miscategorized (their `sku_name` doesn't match the category's expected keywords even though the
> product itself belongs): a keyword pre-filter would drop them before the LLM ever sees them; the
> category/type gate, applied per-product, catches them correctly.

This is a documentation-only change plus the one line already folded into §1's `top_up` scenario prompt
(item 4 in that step list). No change to `docs/quality-standards.md` §2's in-scope definition (Rule A ∪ B)
— that stays GMV/official-store-based, not keyword-based, which is already consistent with this fix.

---

## 4. GWP handling

Fully covered by §1's worklist query — no separate work item. Cross-referenced here only because it was
one of the four original asks.

---

## 5. Universe refresh docs — remove stale direct-DML language

### `ARCHITECTURE.md` lines 286–303

Replace:

```sql
### Universe Refresh

After each category, run targeted DML UPDATE:
UPDATE marketshare_universe u
SET taxonomy_id = src.taxonomy_id, sku_type_complete = src.canonical_name, ...
FROM ( ... ) src
WHERE u.product_id = src.product_id AND u.master_table = src.master_table
  AND u.ecommerce_platform = 'Shopee'
```

with a pointer consistent with line 246 and `headless-runbook.md`'s already-correct pattern:

```markdown
### Universe Refresh

Taxonomy state is never written directly onto `marketshare_universe`/`marketshare_universe_niq` (see line
246 above). A `MERGE` upserts `product_taxonomy_map` × `product_taxonomy` into
`magpie_reference.universe_taxonomy_overlay`, keyed on `(product_id, platform, country)` — see
`docs/headless-runbook.md` § Universe refresh for the exact statement. Analysts join the overlay to
`marketshare_universe` at query time; the production table's schema and rows are never altered.
```

### `docs/product-lifecycle.md`

§3's stage-flow diagram box currently reads "UNIVERSE REFRESH (targeted DML UPDATE) ... Stamp onto
`marketshare_universe`: `taxonomy_id`, `sku_type_complete`, ..." — replace with "UNIVERSE REFRESH (MERGE
into overlay) ... Upsert into `universe_taxonomy_overlay`: `taxonomy_id`, `sku_type_complete`, ...,
joined to `marketshare_universe` at query time by `(product_id, platform, country)`; no columns or rows on
`marketshare_universe` itself change."

§7's worked example currently reads "DML UPDATE stamps `marketshare_universe`: `taxonomy_id = SKU-036021`,
..." — replace with "MERGE upserts a row into `universe_taxonomy_overlay`: `taxonomy_id = SKU-036021`,
`sku_type_complete = "Shokubutsu Vacation Series Shower Cream 500ml x2"`, `brand` still comes from
`product_brand_map`/`brand_dict` unchanged. Analysts get the combined view by joining
`universe_taxonomy_overlay` to `marketshare_universe` on `(product_id, platform, country)` at query time."

`docs/llm-extraction-rules.md`'s changelog entries (lines 341, 345) and
`docs/categories/th_moisturizer_for_face.md`'s DML mention are **not** changed — they're historical
session records, not current-state instructions.

---

## Testing / Verification

Both scripts are orchestration wrappers around `bq`/`claude -p` — no unit-testable logic beyond the bash
control flow itself (matching the existing testing note in `2026-07-17-targeted-qa-fix-script-design.md`).

- `bash -n script/headless_taxonomy.sh` — syntax check.
- Run `./script/headless_taxonomy.sh` with no args → usage error, exit 1, before any `bq`/`claude` call.
- Run the new bash-side gap-count query (read-only) against an already-"✅ ✅ complete" TH category (e.g.
  `shopee_th_coffee`) and confirm it executes without needing a `claude -p` call when the gap is 0 — this is
  the concrete behavior change from §1 and is safe to verify directly (read-only `bq query`, no writes).
- Confirm `script/test_targeted_qa_fix.sh` (existing test script) still passes unmodified — the STEP 3
  prompt-text change doesn't touch any bash function it exercises.
- Doc changes (§3, §5, `_TEMPLATE.md`) are self-verifying by re-reading the edited sections for internal
  consistency (no contradiction between `ARCHITECTURE.md` line 246 and its own Universe Refresh section,
  per the original defect).
- No BQ-write-hitting test is in scope — actually running either script against a live category is a real,
  costly production action, a separate decision from writing/reviewing this design (same caveat every prior
  headless-script design in this repo carries).

---

## Open Follow-ups (explicitly out of scope for this change)

- `docs/categories/th_suncare.md`'s existing `## Targeted QA Fix Brief` is the concrete case §2 carves out —
  it is **not** rewritten as part of this design. In practice its remaining coverage gap should be closed by
  running `script/headless_taxonomy.sh shopee_th_suncare`'s new top-up scenario instead of
  `targeted_qa_fix.sh`, the next time someone works that category. Whoever runs it should replace the Brief
  section's content at that time (or remove it if nothing quality-related remains to fix).
- Block-size guidance for large coverage backfills (the "`1200 / 400` for a several-hundred-product
  backfill" example currently in `th_suncare.md`'s Brief) no longer applies to `targeted_qa_fix.sh` once
  coverage work moves out of it; `headless_taxonomy.sh`'s own `min(max(gap_count, 200), 2000)` sizing
  formula (§1) supersedes it for that use case.
