# Design: `eiger_qa.sh` — dedicated agentic QA script for eiger's image-taxonomy category

## Motivation

`script/non_niq/non_niq_qa_v2.sh` (v2) is generic across "non-NIQ" categories, but that
genericity assumes every category has: a free-text taxonomy dict table (`dict` Sheet column,
matched via Meilisearch candidate retrieval + human-authored `dict_patterns/*.json` generation
rules) and, optionally, a prior product_id→taxonomy mapping table (`product_id_dict`).

`eiger` (Outdoor Equipment & Supplies, ID, 4 platforms: lazada/shopee/tiktok/tokopedia) has
neither. Confirmed live via the Sheet CSV and BigQuery `INFORMATION_SCHEMA`:

- Sheet's `dict` and `product_id_dict` columns are both `-` for every eiger row.
- `eiger.product_id_dict` does not exist in BigQuery at all.
- Categorization instead follows a fixed, enumerated taxonomy tree
  (`docs/eiger_labelling_guidance.csv`, 1061 rows: `mgh_2 → mgh_3 → mgh_4 → product_type →
  Product Style`) that must be matched exactly, not free-text-generated.
- Brand is constrained, for a small set of known multi-brand resellers, by
  `eiger.brand_store_product_fix` (203 rows / 119 stores / 179 brands) rather than free text.
- The real QA/dict-equivalent tables are `eiger.product_id_dict_image_qa` (per-product QA
  output, 30,083 existing rows, human-labelled) and `eiger.product_id_dict_image` (a sparser
  per-product corpus table) — not the Sheet's `product_id_dict_qa`/`dict` columns, which are
  stale placeholders for this row.

Because the retrieval corpus, the candidate-matching logic, and the categorization decision
tree are all genuinely different (not just different table names), this is a new script,
`script/non_niq/eiger_qa.sh`, rather than a v2 config variant. It reuses v2's scaffolding
(worklist materialization shape, retry-once confidence loop, `_meta` conventions, result-summary
and queue-signal plumbing, `script/lib/common.sh` logging) verbatim where it fits, and replaces
only STEP 1 (Meilisearch corpus) and STEP 2 (categorization) with eiger-specific logic.

## Non-goals

- Not changing `non_niq_qa_v2.sh` or any other dataset's behavior, except one small additive
  change to `non_niq_helper.py`'s `index_documents()` (see Component 3) that is backward
  compatible with every existing caller.
- Not attempting to fix or expand `eiger.brand_store_product_fix` — used strictly as-is, per
  explicit user decision. Products from stores not in that table use the same brand-inference
  approach `master_eiger_id.brand` already reflects today (image/text judgment); this script
  does not change how those are resolved.
- Not touching `master_eiger_id.qa_status`, or writing to `product_taxonomy`/
  `product_taxonomy_map` (a different, unrelated pipeline documented in `CLAUDE.md` — eiger's
  QA lands in the non-NIQ family's own tables, following its own `_meta` convention, not
  `meta_agent`).
- Not resolving the ~42% of legacy `product_id_dict_image_qa` rows with NULL/placeholder
  (`'-'`, `'{Defining Process}'`) `sku_type_complete` — those are pre-existing data quality gaps
  in the human-labelled history, out of scope for this script (which only processes the current
  Tier-1 worklist going forward).

## Live data confirmed this session (ground truth for implementation)

- `eiger.master_eiger_id` (source, Tier-1 scoped): latest month, Tier 1 rows = 5,503 across all
  platforms, **100%** already carry non-null `brand/mgh_2/mgh_3/mgh_4/product_type/
  sku_type_complete` (from an existing/legacy labelling pass). Only ~60 Tier-1 rows currently
  show `qa_status = 'Not Reviewed'` — the realistic initial worklist is small, not hundreds of
  rows per platform. This is an observation for expectation-setting, not a design constraint.
- `eiger.product_id_dict_image_qa` schema: `product_id, ecommerce_platform, brand, sku_name,
  sku_type_complete, vlookup, mgh_2, mgh_3, mgh_4, product_type, image, keywords, color, _meta,
  timestamp, gender`. `vlookup` and `color` are 100% NULL across all 30,083 existing rows.
  `sku_type_complete` always equals `keywords` when non-null (34% NULL, ~8% explicit
  `'{Defining Process}'`/`'-'` placeholders).
- `eiger.product_id_dict_image` schema: `product_id, sku_name, shopid, ecommerce_platform,
  image, est_prodName, brand, color, mgh_3, mgh_4, product_type, sku_type_complete, timestamp,
  mgh_2, brand_ori, brand_meili, gender` — sparser than the QA table (most non-key fields NULL).
- `eiger.brand_store_product_fix` schema: `number_order, brand_store, brand, url, url_title,
  image, mgh_2, potential_variant, notes`.
- `eiger.filter_eiger` schema: `ecommerce, product_id, sku_name, _meta` (already correctly
  configured in the Sheet, reused as-is).
- Sheet config (all 4 eiger/ID platform rows): `master_table_prod=eiger.master_eiger_id`,
  `filter_table=eiger.filter_eiger` (both correct), `product_id_dict_qa=-`, `product_id_dict=-`,
  `dict=-`, `product_id_dict_image_qa=eiger.product_id_dict_image_qa` (correct but currently
  unread by `non_niq_helper.py`'s `ROW_FIELDS`), `product_id_image_taxonomy=-` in the Sheet
  (the real table, per the user, is `eiger.product_id_dict_image`), `labelling_config=
  eiger_categorization_image_taxonomy`, `qa_ai_labelling=TRUE`.

## Architecture

```
script/non_niq/eiger_qa.sh          <- new, dedicated script (this design)
script/non_niq/non_niq_helper.py    <- one additive change (Component 3)
script/lib/common.sh                <- reused unchanged (log(), emit_result())
docs/eiger_labelling_guidance.csv   <- existing, read directly by the agent (not embedded)
docs/eiger-qa-handoff.md            <- new, self-contained handoff doc (Component 6)
```

`eiger_qa.sh` does NOT read `product_id_dict_qa`/`dict`/`product_id_dict` from the Sheet at all
(they're stale `-` placeholders for this dataset). It reads `master_table_prod`, `filter_table`,
and the `"0"` enrichment-table column from the Sheet via `non_niq_helper.py categories` (those
three ARE correctly configured), and hardcodes the one real QA table name
(`eiger.product_id_dict_image_qa`) as a script constant, with a comment explaining why (the
Sheet's own `product_id_dict_image_qa` column is correct but currently unread by
`non_niq_helper.py`'s `ROW_FIELDS` — see Risks). `eiger.product_id_dict_image` (the sparser
per-product corpus table named in "Live data confirmed") is background context only — no
component in this design reads or writes it, so it is not referenced anywhere in the script.

`qa_pk_col` is hardcoded to `product_id` (confirmed present on
`product_id_dict_image_qa`) — the `non_niq_helper.py columns` INFORMATION_SCHEMA round-trip v2
needs (because its dict/qa schemas vary per category) is skipped entirely; eiger's schema is
fixed and known.

## Components

### 1. Script signature and main flow

```
script/non_niq/eiger_qa.sh <PLATFORM> [COUNTRY] [MAX_TURNS] [MAX_ROWS]
```

`DATASET` is not a parameter — hardcoded `"eiger"` throughout (this script only ever runs for
this one dataset; a `DATASET` parameter would be an unused abstraction). `KATEGORI` is dropped —
eiger's Sheet rows carry no `kategori` value. Defaults match v2: `COUNTRY=ID`, `MAX_TURNS=300`,
`MAX_ROWS=300`.

`main()` mirrors v2's shape: resolve Sheet config → resolve latest month → build worklist query
→ materialize worklist to `/tmp/eiger_${platform}_${country}_worklist.jsonl` → build prompt →
invoke `claude -p --output-format json --permission-mode bypassPermissions --max-turns
"$max_turns"` synchronously → `format_result_summary` → `emit_result`. `extract_result_json`,
`decide_queue_signal`, `format_result_summary`, `extract_json_object` are copied verbatim from v2 (same output JSON
shape `{status, rows_qa_confirmed, rows_qa_unconfident, rows_filtered, rows_created_in_dict,
findings, blockers}`, for consistency with every other queue consumer that already parses this
shape) — but `rows_created_in_dict` is repointed to mean "rows this session newly indexed into
Meilisearch" (Component 3/STEP 3's qualifying set: confident AND first-time-processed), since
eiger has no dict-table-insert event to count; `extract_rows_created` is unused (its only
caller in v2, the Sheet write-back step, doesn't apply here — see below) so it is not copied.
No Sheet write-back step (v2's final
`append-sheet` call) — eiger's `taxonomy_url` Sheet column is empty (`""`) for all 4 rows, so
this step is dropped rather than guarded with a no-op check that never fires.

### 2. Worklist query

Same shape as v2's `worklist_query()`: `scoped` CTE (Tier-1, latest month, platform, Shopee-only
enrichment join), `qa_state` CTE (order-independent `LOGICAL_OR` flags over `_meta.qa_confidence`
/`_meta.human_review` — this logic is generic over any qa_table with a `_meta` JSON column,
reused unchanged), `filter_state` CTE (against `eiger.filter_eiger`), `prioritized` CTE assigning
priority 0 (never QA'd) / 1 (unconfident retry-eligible) / NULL (excluded).

One addition: the `scoped` CTE's SELECT also carries the row's own existing `brand, mgh_2,
mgh_3, mgh_4, product_type, sku_type_complete, brand_store` from `master_eiger_id` — this
dataset's stand-in for v2's STEP 2b "prior mapping check" (there is no separate
`product_id_dict` to check against, but `master_eiger_id` itself already carries a legacy/prior
categorization for essentially all Tier-1 rows, per the "100% non-null" finding above). The
worklist JSONL's per-line schema becomes: `product_id, sku_name, image, gmv_monthly,
ecommerce_platform, item_description, product_attributes_attrs, brand, mgh_2, mgh_3, mgh_4,
product_type, sku_type_complete, brand_store, priority`.

```sql
WITH {enrichment_cte_and_join}scoped AS (
  SELECT s.product_id, s.sku_name, REPLACE(s.image, '"', '') AS image, s.ecommerce_platform,
         s.qa_status, s.gmv_monthly, s.brand, s.mgh_2, s.mgh_3, s.mgh_4, s.product_type,
         s.sku_type_complete, s.brand_store, {enrichment_select}
  FROM `sincere-hearth-273704.eiger.master_eiger_id` s
  {enrichment_join}
  WHERE s.product_tier = 'Tier 1'
    AND FORMAT_DATE('%Y-%m', s.month) = '{month}'
    AND s.ecommerce_platform {platform_match_clause}
),
qa_state AS (
  SELECT product_id,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '$.qa_confidence') = 'unconfident'
               AND COALESCE(JSON_VALUE(SAFE.PARSE_JSON(_meta), '$.human_review'), 'false') != 'true') AS has_unconfident_pending,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '$.qa_confidence') = 'confident') AS has_confident,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '$.human_review') = 'true') AS has_terminal
  FROM `sincere-hearth-273704.eiger.product_id_dict_image_qa`
  GROUP BY product_id
),
filter_state AS (
  SELECT DISTINCT product_id FROM `sincere-hearth-273704.eiger.filter_eiger`
),
prioritized AS (
  SELECT sc.*,
    CASE
      WHEN fs.product_id IS NOT NULL THEN NULL
      WHEN qs.product_id IS NULL AND sc.qa_status = 'Not Reviewed' THEN 0
      WHEN qs.has_unconfident_pending AND NOT qs.has_confident AND NOT qs.has_terminal THEN 1
      ELSE NULL
    END AS priority
  FROM scoped sc
  LEFT JOIN qa_state qs ON qs.product_id = sc.product_id
  LEFT JOIN filter_state fs ON fs.product_id = sc.product_id
)
SELECT * FROM prioritized WHERE priority IS NOT NULL
ORDER BY priority ASC, gmv_monthly DESC
LIMIT {row_limit}
```

(Enrichment CTE/join for Shopee `item_description`/`product_attributes_attrs` copied verbatim
from v2 — same live-confirmed Python-repr-vs-JSON fallback, same reasoning.)

### 3. Meilisearch corpus

New index: `eiger_taxonomy_qa`.

**One-time backfill** (documented as a copy-pasteable command block in the handoff doc, not a
persisted script file — it runs once): seed the index from the existing 30,083-row
`product_id_dict_image_qa`, filtered to rows with a real (non-placeholder) categorization:

```sql
SELECT product_id, sku_name, brand, product_type, sku_type_complete, mgh_2, mgh_3, mgh_4
FROM `sincere-hearth-273704.eiger.product_id_dict_image_qa`
WHERE product_type IS NOT NULL
  AND sku_type_complete NOT IN ('-', '{Defining Process}')
QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY timestamp DESC NULLS LAST) = 1
```

piped to a JSONL file, then:

```
${PYTHON_BIN} script/non_niq/non_niq_helper.py index \
  --input-file <backfill.jsonl> --meili-index eiger_taxonomy_qa
```

**Code change required** — `index_documents()` in `non_niq_helper.py` currently hardcodes the
document shape to exactly `{product_id, sku_name, sku_type_complete, brand}`. Change it to
spread every field present on each input line through to the Meilisearch document, instead of
naming only those four:

```python
docs = [
    {
        **l,
        "product_id": str(l["product_id"]),
        "_vectors": {"default": vec.tolist()},
    }
    for l, vec in zip(lines, vectors)
]
```

This is backward compatible — every existing dataset's STEP 3 keeps passing exactly its current
4-field lines, output unchanged. Eiger's STEP 3 (below) passes the extra `mgh_2/mgh_3/mgh_4/
product_type` fields, which now flow through to the index and, since Meilisearch returns full
stored documents on search (not just `searchableAttributes`), are automatically available on
every future `retrieve` call's `candidates[]` with no change needed to `retrieve_candidates()`.

`ensure_index()`'s `searchableAttributes` gets `"product_type"` added to the existing
`["sku_name", "sku_type_complete", "brand"]` default — harmless for other datasets (an
undefined field on their documents is simply ignored by Meilisearch), needed for eiger so hybrid
search can match on product_type text too.

### 4. Categorization decision tree (replaces v2 STEP 2b/2c)

STEP 0 (worklist materialization) and STEP 1 (batch Meilisearch retrieve) keep v2's shape,
pointed at `eiger_taxonomy_qa`.

STEP 2, per product:

- **2a. Relevance** — unchanged from v2 (multimodal image download + judgment; NO → write to
  `eiger.filter_eiger`).
- **2b. Guidance-doc taxonomy lookup** — the agent is told to Read
  `docs/eiger_labelling_guidance.csv` directly (materialized file, same "Read it, don't
  re-derive" convention as STEP 0's worklist — 1061 rows is small enough to Read whole, not
  worth chunking). Using the image + `sku_name` + enrichment fields + the worklist row's own
  existing `brand/mgh_2/mgh_3/mgh_4/product_type/sku_type_complete` as a starting hypothesis to
  verify (this dataset's "prior mapping check" — see Component 2), the agent picks
  `mgh_2 → mgh_3 → mgh_4 → product_type` as one real path that exists in the CSV (never
  free-typed at any level — each choice is constrained to values that co-occur with the prior
  choices in the CSV), then, among that exact path's listed `Product Style` options, picks the
  best-fitting one (the CSV's own "Not assigned"/"N/A"/"Mix" catch-all values mean there is no
  genuine dead end once the four-level path is right — the prompt states this explicitly so the
  agent never treats "no good Product Style fit" as a blocker). The chosen `Product Style` value
  is written to both `sku_type_complete` and `keywords` on `product_id_dict_image_qa` (the one
  pattern that was consistent in the legacy data whenever populated — see the schema-facts
  section above).
- **2c. Brand resolution** — if the product's `brand_store` (from the worklist row, sourced from
  `master_eiger_id.brand_store`) matches an entry in `eiger.brand_store_product_fix`, brand MUST
  come from that table: match by exact `url` first (the fix table is keyed partly by product
  URL), else by `brand_store` among that store's listed brands using the product's own signal
  (image/sku_name) to disambiguate — never invent a brand for these ~20 known multi-brand-reseller
  stores. For every other `brand_store` (not in the fix table — the large majority), brand
  resolution is unchanged from what `master_eiger_id.brand` already reflects: verify the
  existing value against image/text judgment, correct if wrong, same as any other field in 2b's
  prior-mapping check. `eiger.brand_store_product_fix` is used strictly read-only and as-is per
  explicit decision — no attempt to fix/expand its coverage.
- **2d. Self-QA / confidence loop** — unchanged from v2 (`_meta.qa_confidence`, retry-once,
  `human_review` terminal flag).

STEP 3 (Meilisearch write-back) — same shape as v2, but the JSONL lines carry the extra fields:
`{"product_id", "sku_name", "sku_type_complete", "brand", "mgh_2", "mgh_3", "mgh_4",
"product_type"}`, relying on Component 3's `index_documents()` change to pass them through.

### 5. `_meta` convention

Unchanged from v2 — same baseline `{"source":"claude_code","timestamp":"<ISO 8601 UTC>"}`, same
`qa_confidence`/`human_review` additions on 2d's write. `vlookup` and `color` columns are left
untouched (NULL) — they're 100% unused in the existing 30,083 rows and out of scope per the
"Product Style scope" decision (only `sku_type_complete`/`keywords` carry the guidance-doc
value).

### 6. Windmill-Claude handoff doc

New file, `docs/eiger-qa-handoff.md`, following the `docs/windmill-app-prompt.md`/
`docs/non-niq-queue-submitter-handoff.md` convention (self-contained, no assumed repo context).
Contents: the real table schemas (Component "Live data confirmed" section), the guidance-doc
rule and where to find `docs/eiger_labelling_guidance.csv`, the brand-fix-table rule and its
known coverage gap (20/250 stores), the Meilisearch one-time backfill command block, and what's
different from `non_niq_qa_v2.sh` for a reader who knows v2 but not this design. Also notes the
`non_niq_helper.py ROW_FIELDS` ROW_FIELDS still doesn't carry `product_id_dict_image_qa`/
`product_id_image_taxonomy` from the Sheet — intentionally not fixed by this design (those two
real table names are hardcoded constants in `eiger_qa.sh` instead, per Architecture above) — so
a future reader doesn't "fix" the Sheet-reading gap and end up drifting from the hardcoded
constants without updating both.

## Testing

Matches this repo's existing convention: `non_niq_qa_v2.sh`/v1 have no bash-level test file
(they're thin orchestration over `claude -p`, not independently testable without a live LLM
call) — `eiger_qa.sh` follows the same pattern, no new test infra invented for it.
`non_niq_helper.py`'s pure-Python pieces are unit tested in `tests/non_niq/test_non_niq_helper.py`
— add one test there for the `index_documents()` change: a line with extra fields
(`mgh_2`/`product_type`) produces a document containing those fields, and a line with only the
original 4 fields produces exactly the original 4-plus-`_vectors` shape (regression guard for
every other dataset's unchanged behavior).

## Risks / open items carried forward (not blocking)

- The Sheet's `product_id_dict_image_qa`/`product_id_image_taxonomy` columns remain unread by
  `non_niq_helper.py` (Architecture section) — acceptable since `eiger_qa.sh` hardcodes the real
  table names directly; flagged in the handoff doc so it isn't "fixed" inconsistently later.
- `brand_store_product_fix`'s narrow coverage (20/250 Tier-1 stores) is a known, accepted gap
  per explicit user decision — not addressed by this script.
- Legacy `product_id_dict_image_qa` rows with placeholder/NULL `sku_type_complete` (~42%) are
  not backfilled/corrected by this design — the Meilisearch seed query filters them out of the
  retrieval corpus, but the rows themselves are untouched.
