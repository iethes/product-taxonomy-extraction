# eiger Image-Taxonomy QA Script Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `script/non_niq/eiger_qa.sh`, a dedicated agentic QA script for eiger (Outdoor
Equipment & Supplies) that categorizes products via a fixed guidance-doc taxonomy tree instead of
a free-text dict table, plus the one supporting `non_niq_helper.py` change and handoff doc it needs.

**Architecture:** Three independent, sequentially-buildable pieces: (1) a small backward-compatible
change to `non_niq_helper.py`'s Meilisearch indexing so eiger's extra taxonomy fields flow through,
(2) the new `eiger_qa.sh` script itself (worklist query + agentic prompt + orchestration, closely
modeled on `non_niq_qa_v2.sh`'s scaffolding), (3) a self-contained handoff doc for a downstream
reader with none of this session's context.

**Tech Stack:** Bash (`set -euo pipefail`), `bq` CLI (BigQuery), Python 3 (`google-cloud-bigquery`,
`sentence-transformers`) via this repo's `.venv`, Meilisearch (hybrid search), `claude -p` subprocess.

**Spec:** [`docs/superpowers/specs/2026-09-02-eiger-image-taxonomy-qa-design.md`](../specs/2026-09-02-eiger-image-taxonomy-qa-design.md)

## Global Constraints

- Never write to `qa_status` on `eiger.master_eiger_id` — a separate external process owns it.
- All BigQuery writes use `bq query` DML, never the streaming API (90-minute streaming-buffer rule).
- The agentic prompt must forbid backgrounding any tool call or ending the turn before the full
  worklist is processed — this is a one-shot session with no resume path.
- Every `_meta` write is a JSON string (`{"source":"claude_code","timestamp":"..."}` baseline,
  `qa_confidence`/`human_review` added by the confidence loop) — never a bare string.
- `eiger.brand_store_product_fix` is read-only reference data — this project never writes to it
  or expands its coverage.
- The `index_documents()` change in `non_niq_helper.py` must be backward compatible: every
  existing dataset's 4-field `{product_id, sku_name, sku_type_complete, brand}` calls must
  produce byte-identical output to today.
- No new bash-level test infra — `non_niq_qa_v2.sh`/v1 have none (thin orchestration over a live
  `claude -p` call, not independently testable), and `eiger_qa.sh` follows the same convention.

---

## Task 1: `non_niq_helper.py` — pass extra fields through to the Meilisearch index

**Files:**
- Modify: `script/non_niq/non_niq_helper.py:215-256` (`ensure_index`, `index_documents`)
- Test: `tests/non_niq/test_non_niq_helper.py`

**Interfaces:**
- Consumes: nothing new — same `_meili_request` helper already used throughout the file.
- Produces: `index_documents(lines, meili_url, meili_index, model=None)` now accepts lines with
  arbitrary extra keys (beyond `product_id`/`sku_name`/`sku_type_complete`/`brand`) and stores
  them verbatim on the Meilisearch document. `ensure_index(meili_url, index_uid)`'s
  `searchableAttributes` now includes `"product_type"`. Both are used, unmodified in call shape,
  by Task 2's `eiger_qa.sh` STEP 1/STEP 3.

- [ ] **Step 1: Write the two failing tests**

Add to `tests/non_niq/test_non_niq_helper.py`, directly below the existing
`test_index_documents_doc_shape` test:

```python
def test_index_documents_passes_through_extra_fields(monkeypatch):
    posted = []
    def fake_meili_request(meili_url, method, path, body=None):
        if method == "GET":
            return {"results": [{"uid": "eiger_taxonomy_qa"}]}
        if method == "POST" and path.endswith("/documents"):
            posted.append(body)
        return {}
    monkeypatch.setattr(non_niq_helper, "_meili_request", fake_meili_request)
    lines = [{
        "product_id": 999, "sku_name": "Eiger Trail Shoes", "sku_type_complete": "Hiking",
        "brand": "Eiger", "mgh_2": "Mountaineering", "mgh_3": "FOOTWEAR", "mgh_4": "Shoes",
        "product_type": "Low-cut shoes",
    }]
    count = non_niq_helper.index_documents(lines, "http://fake", "eiger_taxonomy_qa", model=_FakeModel())
    assert count == 1
    doc = posted[0][0]
    assert doc["mgh_2"] == "Mountaineering"
    assert doc["mgh_3"] == "FOOTWEAR"
    assert doc["mgh_4"] == "Shoes"
    assert doc["product_type"] == "Low-cut shoes"
    assert doc["product_id"] == "999"

def test_index_documents_default_shape_unchanged_without_extra_fields(monkeypatch):
    posted = []
    def fake_meili_request(meili_url, method, path, body=None):
        if method == "GET":
            return {"results": [{"uid": "babybath_taxonomy_qa"}]}
        if method == "POST" and path.endswith("/documents"):
            posted.append(body)
        return {}
    monkeypatch.setattr(non_niq_helper, "_meili_request", fake_meili_request)
    lines = [{"product_id": 1, "sku_name": "p", "sku_type_complete": "T", "brand": "B"}]
    non_niq_helper.index_documents(lines, "http://fake", "babybath_taxonomy_qa", model=_FakeModel())
    doc = posted[0][0]
    assert set(doc.keys()) == {"product_id", "sku_name", "sku_type_complete", "brand", "_vectors"}

def test_ensure_index_searchable_attributes_includes_product_type(monkeypatch):
    patches = []
    def fake_meili_request(meili_url, method, path, body=None):
        if method == "GET":
            return {"results": [{"uid": "eiger_taxonomy_qa"}]}
        if method == "PATCH":
            patches.append(body)
        return {}
    monkeypatch.setattr(non_niq_helper, "_meili_request", fake_meili_request)
    non_niq_helper.ensure_index("http://fake", "eiger_taxonomy_qa")
    assert "product_type" in patches[0]["searchableAttributes"]
    assert "sku_name" in patches[0]["searchableAttributes"]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `.venv/bin/python3 tests/non_niq/test_non_niq_helper.py`
Expected: `test_index_documents_passes_through_extra_fields` fails with a `KeyError` (extra fields
not in `doc`), `test_ensure_index_searchable_attributes_includes_product_type` fails an assert
(`"product_type" not in [...]`). `test_index_documents_default_shape_unchanged_without_extra_fields`
passes already (documents current behavior) — that's fine, it becomes the regression guard.

- [ ] **Step 3: Implement the change**

In `script/non_niq/non_niq_helper.py`, replace the `ensure_index` settings call:

```python
    _meili_request(meili_url, "PATCH", f"/indexes/{index_uid}/settings", {
        "searchableAttributes": ["sku_name", "sku_type_complete", "brand"],
        "embedders": {"default": {"source": "userProvided", "dimensions": EMBED_DIM}},
    })
```

with:

```python
    _meili_request(meili_url, "PATCH", f"/indexes/{index_uid}/settings", {
        "searchableAttributes": ["sku_name", "sku_type_complete", "brand", "product_type"],
        "embedders": {"default": {"source": "userProvided", "dimensions": EMBED_DIM}},
    })
```

Replace the `index_documents` docstring and doc-construction block:

```python
def index_documents(lines, meili_url, meili_index, model=None):
    """lines: list of {"product_id","sku_name","sku_type_complete","brand"} -- the shape v2's
    STEP 3 batches up from its own session writes. Embeds sku_name as an E5 passage (corpus side),
```

with:

```python
def index_documents(lines, meili_url, meili_index, model=None):
    """lines: list of {"product_id","sku_name","sku_type_complete","brand"} plus any optional
    extra fields (e.g. eiger_qa.sh's mgh_2/mgh_3/mgh_4/product_type) -- the shape v2's STEP 3
    batches up from its own session writes. Extra fields are passed through to the indexed
    Meilisearch document unchanged, so a later retrieve() call's candidates[] carries them
    automatically (Meilisearch returns full stored documents on search, not just
    searchableAttributes). Embeds sku_name as an E5 passage (corpus side),
```

and the doc-construction list:

```python
    docs = [
        {
            "product_id": str(l["product_id"]),
            "sku_name": l["sku_name"],
            "sku_type_complete": l["sku_type_complete"],
            "brand": l["brand"],
            "_vectors": {"default": vec.tolist()},
        }
        for l, vec in zip(lines, vectors)
    ]
```

with:

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

- [ ] **Step 4: Run all tests to verify they pass**

Run: `.venv/bin/python3 tests/non_niq/test_non_niq_helper.py`
Expected: `ALL TESTS PASSED` (every existing test still passes — in particular
`test_index_documents_doc_shape` and `test_index_documents_batches_at_batch_size`, which prove
the change is backward compatible for every other dataset's calling shape).

- [ ] **Step 5: Commit**

```bash
git add script/non_niq/non_niq_helper.py tests/non_niq/test_non_niq_helper.py
git commit -m "$(cat <<'EOF'
Pass extra fields through to the Meilisearch index in index_documents()

eiger's QA needs mgh_2/mgh_3/mgh_4/product_type carried on indexed
documents, not just the sku_type_complete/brand shape every other
dataset uses. Spreads the whole input line into the document instead
of naming four fields -- backward compatible, every existing caller
keeps passing exactly its current 4 fields.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Mcu8zuyutEPGDbk5iNm8SK
EOF
)"
```

---

## Task 2: `script/non_niq/eiger_qa.sh` — the dedicated script

**Files:**
- Create: `script/non_niq/eiger_qa.sh`

**Interfaces:**
- Consumes: `script/lib/common.sh`'s `log()` and `emit_result()` (unchanged, no new interface);
  `non_niq_helper.py`'s `categories`, `retrieve`, `index` CLI subcommands (unchanged call shape);
  Task 1's `index_documents()` extra-fields passthrough (called via the `index` CLI subcommand,
  not directly).
- Produces: `script/non_niq/eiger_qa.sh <PLATFORM> [COUNTRY] [MAX_TURNS] [MAX_ROWS]`, an
  executable entrypoint. Prints `QUEUE_SIGNAL: <DONE|FAILED|BLOCKED|NOTHING_TO_DO>` on stdout
  (same contract as `non_niq_qa_v2.sh`, so any existing queue consumer parses it identically) and
  one `emit_result` JSON line.

- [ ] **Step 1: Write `script/non_niq/eiger_qa.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: script/non_niq/eiger_qa.sh <PLATFORM> [COUNTRY] [MAX_TURNS] [MAX_ROWS]
# e.g.  script/non_niq/eiger_qa.sh shopee
#       script/non_niq/eiger_qa.sh tokopedia ID 300 300
#
# Dedicated agentic QA script for eiger (Outdoor Equipment & Supplies) -- NOT a config variant of
# non_niq_qa_v2.sh. eiger has no free-text taxonomy dict table (Sheet's dict/product_id_dict
# columns are both '-', eiger.product_id_dict doesn't exist in BigQuery); categorization instead
# follows a fixed enumerated tree (docs/eiger_labelling_guidance.csv) and brand is constrained,
# for a small set of known multi-brand resellers, by eiger.brand_store_product_fix. See
# docs/superpowers/specs/2026-09-02-eiger-image-taxonomy-qa-design.md for the full design this
# implements, and docs/eiger-qa-handoff.md for a self-contained summary.
#
# Reuses non_niq_qa_v2.sh's scaffolding (worklist materialization shape, retry-once confidence
# loop, _meta conventions, result-summary/queue-signal plumbing) verbatim where it fits.

PROJECT="sincere-hearth-273704"
MEILI_URL="http://34.124.146.29:7700"
MEILI_INDEX="eiger_taxonomy_qa"

# eiger's real QA table -- the Sheet's own product_id_dict_image_qa column is correct but
# currently unread by non_niq_helper.py's ROW_FIELDS (see the design spec's Risks section), so
# it's hardcoded here rather than resolved from the Sheet like non_niq_qa_v2.sh's qa_table.
QA_TABLE="eiger.product_id_dict_image_qa"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PYTHON_BIN="${REPO_ROOT}/.venv/bin/python3"
GUIDANCE_CSV="${REPO_ROOT}/docs/eiger_labelling_guidance.csv"

source "${REPO_ROOT}/script/lib/common.sh"

# Identical to non_niq_qa_v2.sh's -- Tokopedia's own first-party channel carries a distinct
# 'Tokopedia | Shop' ecommerce_platform value with no separate config Sheet row.
platform_match_clause() {
  local platform_titlecase="$1"
  if [[ "$platform_titlecase" == "Tokopedia" ]]; then
    echo "IN ('Tokopedia', 'Tokopedia | Shop')"
  else
    echo "= '${platform_titlecase}'"
  fi
}

default_month_query() {
  local source_table="$1" platform="$2"
  local platform_titlecase="${platform^}"
  echo "SELECT FORMAT_DATE('%Y-%m', MAX(month)) FROM \`${PROJECT}.${source_table}\` WHERE ecommerce_platform $(platform_match_clause "$platform_titlecase")"
}

# Given the Sheet's raw filter_table cell (possibly ";"-separated), returns the ONE table living
# in this row's own dataset. Identical to non_niq_qa_v2.sh's.
primary_filter_table() {
  local filter_table_config="$1" dataset="$2"
  local entry
  IFS=';' read -ra entries <<< "$filter_table_config"
  for entry in "${entries[@]}"; do
    if [[ "$entry" == "${dataset}."* ]]; then
      echo "$entry"
      return 0
    fi
  done
  echo "${entries[0]}"
}

# Scope: product_tier = 'Tier 1' on master_table_prod, same convention as non_niq_qa_v2.sh.
# Unlike v2's generic version, qa_pk_col is not a parameter -- product_id is a fixed, confirmed
# column on QA_TABLE, so the non_niq_helper.py INFORMATION_SCHEMA round-trip v2 needs for
# per-category schema variance is skipped entirely.
worklist_query() {
  local source_table="$1" month="$2" platform="$3" enrichment_table="$4" row_limit="$5" filter_table="$6"
  local platform_titlecase="${platform^}"
  local dataset="${source_table%%.*}"
  local enrichment_cte_and_join="" enrichment_join="" enrichment_select="NULL AS item_description, NULL AS product_attributes_attrs"
  if [[ "$platform_titlecase" == "Shopee" && -n "$enrichment_table" && "$enrichment_table" != "-" && "$enrichment_table" != "null" ]]; then
    # Ported verbatim from non_niq_qa_v2.sh's worklist_query -- same live-confirmed
    # Python-repr-vs-JSON fallback for product_attributes_attrs.
    enrichment_cte_and_join="enrichment_dedup AS (
  SELECT item_itemid, item_description,
    (SELECT STRING_AGG(CONCAT(JSON_VALUE(a,'\$.name'),'=',JSON_VALUE(a,'\$.value')), '; ')
     FROM UNNEST(JSON_QUERY_ARRAY(COALESCE(
       SAFE.PARSE_JSON(product_attributes_attrs),
       SAFE.PARSE_JSON(REPLACE(REPLACE(REPLACE(REPLACE(product_attributes_attrs, ': None', ': null'), ': True', ': true'), ': False', ': false'), CHR(39), CHR(34)))
     ))) a) AS product_attributes_attrs
  FROM \`${PROJECT}.${dataset}.${enrichment_table}\`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY item_itemid ORDER BY timestamp DESC) = 1
),
"
    enrichment_join="LEFT JOIN enrichment_dedup e ON CAST(e.item_itemid AS STRING) = s.product_id"
    enrichment_select="e.item_description, e.product_attributes_attrs"
  fi
  cat <<SQL
WITH ${enrichment_cte_and_join}scoped AS (
  SELECT s.product_id, s.sku_name, REPLACE(s.image, '"', '') AS image, s.ecommerce_platform,
         s.qa_status, s.gmv_monthly, s.brand, s.mgh_2, s.mgh_3, s.mgh_4, s.product_type,
         s.sku_type_complete, s.brand_store, ${enrichment_select}
  FROM \`${PROJECT}.${source_table}\` s
  ${enrichment_join}
  WHERE s.product_tier = 'Tier 1'
    AND FORMAT_DATE('%Y-%m', s.month) = '${month}'
    AND s.ecommerce_platform $(platform_match_clause "$platform_titlecase")
),
qa_state AS (
  -- Order-independent LOGICAL_OR flags over the WHOLE per-product history, same fan-out-bug fix
  -- non_niq_qa_v2.sh uses (project memory project_non_niq_qa_state_fanout_bug.md) -- QA_TABLE is
  -- insert-only, a raw un-deduped join would leak resolved products back into the worklist.
  SELECT
    product_id,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.qa_confidence') = 'unconfident'
               AND COALESCE(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.human_review'), 'false') != 'true') AS has_unconfident_pending,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.qa_confidence') = 'confident') AS has_confident,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.human_review') = 'true') AS has_terminal
  FROM \`${PROJECT}.${QA_TABLE}\`
  GROUP BY product_id
),
filter_state AS (
  SELECT DISTINCT product_id FROM \`${PROJECT}.${filter_table}\`
),
prioritized AS (
  SELECT sc.product_id, sc.sku_name, sc.image, sc.gmv_monthly, sc.ecommerce_platform,
         sc.item_description, sc.product_attributes_attrs, sc.brand, sc.mgh_2, sc.mgh_3,
         sc.mgh_4, sc.product_type, sc.sku_type_complete, sc.brand_store,
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
SELECT * FROM prioritized
WHERE priority IS NOT NULL
ORDER BY priority ASC, gmv_monthly DESC
LIMIT ${row_limit}
SQL
}

build_qa_prompt() {
  local platform="$1" country="$2" source_table="$3" filter_table="$4" worklist_file="$5"
  local worklist_count="$6" tmp_tag="$7"

  cat <<PROMPT
Eiger agentic QA session (image-taxonomy category, dedicated script -- NOT non_niq_qa_v2.sh) for
platform=${platform}, country=${country}. See
docs/superpowers/specs/2026-09-02-eiger-image-taxonomy-qa-design.md for the full design this
implements -- read it in full before starting if you have not already. Unlike every other
non-NIQ category, eiger has no free-text taxonomy dict table: categorization follows a fixed
enumerated tree (docs/eiger_labelling_guidance.csv) and brand is constrained, for a small set of
known multi-brand resellers, by eiger.brand_store_product_fix.

Resolved for this run: source_table=${PROJECT}.${source_table} (master_table_prod, Tier-1
scoped), qa_table=${PROJECT}.${QA_TABLE}, filter_table (write target)=${PROJECT}.${filter_table},
guidance_csv=${GUIDANCE_CSV}, brand_fix_table=${PROJECT}.eiger.brand_store_product_fix,
meilisearch_index=${MEILI_INDEX} (at ${MEILI_URL}).

STEP 0 -- The full worklist has ALREADY been materialized for you at
${worklist_file}, exactly ${worklist_count} rows, one JSON object per line (JSONL) -- do NOT
query BigQuery to re-fetch it, and do NOT trust any other row count than ${worklist_count}. Read
the file (in slices if it's too large for one Read) rather than querying BigQuery for it. Each
line has: product_id, sku_name, image, gmv_monthly, ecommerce_platform, item_description,
product_attributes_attrs, brand, mgh_2, mgh_3, mgh_4, product_type, sku_type_complete,
brand_store, priority. The brand/mgh_2/mgh_3/mgh_4/product_type/sku_type_complete/brand_store
fields are this product's EXISTING values on the source table (from a prior/legacy labelling
pass) -- a starting hypothesis to verify against the image and the guidance doc in STEP 2, not
a ground truth to copy blindly. It is already scoped to product_tier = 'Tier 1' and prioritized
(unreviewed rows before agent-flagged-unconfident retry rows, both by gmv_monthly descending) --
process it in that order. If you cannot account for all ${worklist_count} rows by the end of
your turn budget, explicitly report status: partial (or status: blocked if you cannot proceed at
all) -- never silently process a subset and report status: complete.

STEP 1 -- Retrieve Meilisearch candidates for the WHOLE worklist in ONE batch call, never one
call per product:
  1. Derive /tmp/${tmp_tag}_worklist.jsonl from ${worklist_file} (STEP 0's file) --
     one line per worklist product: {"id": "<product_id>", "text": "<sku_name>"}. Run:
       jq -c '{id: .product_id, text: .sku_name}' ${worklist_file} > /tmp/${tmp_tag}_worklist.jsonl
  2. Run:
     ${PYTHON_BIN} ${REPO_ROOT}/script/non_niq/non_niq_helper.py retrieve \\
       --input-file /tmp/${tmp_tag}_worklist.jsonl \\
       --output-file /tmp/${tmp_tag}_candidates.jsonl \\
       --meili-index ${MEILI_INDEX}
     Run this synchronously and wait for it to finish before continuing -- never background this
     call or any other tool call in this session.
  3. Read back /tmp/${tmp_tag}_candidates.jsonl -- one line per product:
     {"id": "<product_id>", "candidates": [{"product_id","sku_name","brand","sku_type_complete",
     "mgh_2","mgh_3","mgh_4","product_type"}, ...]}. Each product's candidates are already the
     top hybrid-search results (confirmed past-QA'd products with the SAME taxonomy fields this
     session writes) from ${MEILI_INDEX} -- use them as grounding context for STEP 2b/2c (e.g. "a
     very similar past product was categorized as mgh_4=X, product_type=Y"), never as a
     substitute for actually checking the guidance doc yourself. An empty candidates array means
     retrieval failed for this product -- treat it the same as "no candidates found", do not
     block on it.

STEP 2 -- For each product in the worklist, in order:

  2a. RELEVANT to this category (outdoor equipment & supplies / Eiger-adjacent apparel, gear,
      footwear)? This judgment is MULTIMODAL -- you must actually LOOK at the product image, not
      just read its URL. Download it to a local file and then open that file with the Read tool:
        curl -sSL --max-time 30 "<image_url>" -o /tmp/${tmp_tag}_<product_id>.jpg
        (then: Read /tmp/${tmp_tag}_<product_id>.jpg)
      Do this BEFORE making any relevance / brand / category judgment for the product. If the
      download fails, or the downloaded file is not a readable image, say so explicitly in your
      reasoning for that product and treat it as TEXT-ONLY -- grounds to mark it unconfident in
      2d.
      NO  -> write {product_id, ecommerce_platform, sku_name, reason} to
             \`${PROJECT}.${filter_table}\`, _meta stamped
             '{"source":"claude_code","timestamp":"<now, ISO 8601 UTC>"}' (see the _meta format
             rule below), do NOT write to \`${QA_TABLE}\`. Move to the next product. Use the
             worklist row's OWN \`ecommerce_platform\` value verbatim.
      YES -> continue to 2b.

  2b. Guidance-doc taxonomy path. Read ${GUIDANCE_CSV} in full (1061 rows, columns: mgh_2,
      mgh_3, mgh_4, product_type, "Product Style" -- the 5th column's header is literally
      "Product Style", trailing empty columns in the file are not used). Using the image +
      sku_name + item_description/product_attributes_attrs (Shopee-only, NULL elsewhere -- treat
      NULL as no extra signal) + this product's existing brand/mgh_2/mgh_3/mgh_4/product_type/
      sku_type_complete from the worklist row as a starting hypothesis to verify (NOT to copy
      blindly -- it may be wrong or stale) + STEP 1's candidates as grounding context, determine:
        - mgh_2: one of the 5 values that appear in the guidance CSV (Active, Lifestyle,
          Mountaineering, Riding, Tactical).
        - mgh_3, mgh_4, product_type: each MUST be chosen from values that actually co-occur
          with your prior choices as a real row in the guidance CSV -- never free-typed. If you
          are unsure between two candidate rows, prefer the one whose product_type most
          specifically matches the product (the CSV often lists near-duplicate product_type
          spellings, e.g. "Low-cut shoes" vs "Low Cut Shoes" -- match meaning, not exact string).
        - Product Style: among ONLY the Product Style values listed for your exact
          mgh_2/mgh_3/mgh_4/product_type combination in the CSV, pick the best fit. The CSV
          itself lists catch-all options ("Not assigned", "N/A", "Mix") at most leaf
          combinations -- if no more specific style clearly fits, use one of these catch-alls
          rather than treating this as a blocker. There is no valid "no guidance match" outcome
          once mgh_2/mgh_3/mgh_4/product_type are chosen correctly.
      Write the chosen Product Style value to BOTH sku_type_complete and keywords when you write
      this product's row in 2d (do not write anything to vlookup, color, or gender -- leave them
      out of the INSERT, they are unused by this pipeline).

  2c. Brand resolution. First check: does this product's brand_store (the worklist row's own
      brand_store field) match a brand_store value in \`${PROJECT}.eiger.brand_store_product_fix\`?
      Query it: \`SELECT * FROM \\\`${PROJECT}.eiger.brand_store_product_fix\\\` WHERE brand_store =
      '<brand_store>'\`.
        MATCH FOUND (one or more rows) -> brand MUST come from this table -- never invent a
          brand for this store. Prefer an exact \`url\` match to this product's own URL if one
          exists among the returned rows; otherwise, use the product's image/sku_name to pick
          the best-fitting brand among the store's listed brands in the result set.
        NO MATCH -> this store is not a known multi-brand reseller. Brand resolution is the
          worklist row's existing \`brand\` value, verified against the image/sku_name (correct
          it if the image clearly shows a different, real brand; otherwise keep it) -- same as
          any other field in 2b's prior-value verification.
      \`eiger.brand_store_product_fix\` is read-only reference data -- never write to it, and
      never treat a NO MATCH as license to invent a brand not actually visible in the
      image/sku_name/existing value.

  2d. Write + self-QA. Having determined brand (2c), mgh_2/mgh_3/mgh_4/product_type/Product
      Style (2b), INSERT one new row into \`${QA_TABLE}\`:
        (product_id, ecommerce_platform, brand, sku_name, sku_type_complete, mgh_2, mgh_3,
         mgh_4, product_type, image, keywords, timestamp, _meta)
      -- sku_type_complete and keywords both get the Product Style value from 2b; timestamp =
      CURRENT_TIMESTAMP(); image = the worklist row's own image URL; vlookup, color, gender are
      left out of the column list entirely (NULL).
      This table is INSERT-ONLY -- never UPDATE or DELETE an existing row, even a wrong one; a
      correction is a new row with the same product_id and a newer timestamp.
      Then, as an explicit, separate judgment (not folded into 2a-2c's reasoning), state how
      confident you are in the decision you just made for this product:
      - If this is the product's FIRST time being processed this session (no qa_confidence value
        existed for it before this run, i.e. it was priority 0 in the worklist): _meta =
        '{"source":"claude_code","qa_confidence":"confident","timestamp":"<now, ISO 8601 UTC>"}'
        if confident, or
        '{"source":"claude_code","qa_confidence":"unconfident","human_review":false,"timestamp":"<now>"}'
        if not.
      - If this product ALREADY had a qa_confidence:'unconfident', human_review:false row before
        this run (i.e. this is its one allowed retry, priority 1 in the worklist): and you are
        STILL unconfident after redoing 2a-2c with full multimodal effort, write _meta =
        '{"source":"claude_code","qa_confidence":"unconfident","human_review":true,"timestamp":"<now>"}'
        -- this is terminal, the product will not re-enter future worklists for this script.
        If you ARE confident on this retry, write the confident shape as above.

STEP 3 -- Meilisearch write-back for newly-confident categorizations. After STEP 2 finishes,
products that ended up recorded \`qa_confidence: "confident"\` in STEP 2d (whether first-time or
retry) are worth making searchable for future sessions. Filtered-out and unconfident products are
skipped -- never index an unconfident guess.
  1. Build one JSONL file of every qualifying product from this session, one line each -- you
     already have these values from your own STEP 2 writes, no requery needed:
     {"product_id": "<product_id>", "sku_name": "<sku_name>", "sku_type_complete": "<value written>",
      "brand": "<value written>", "mgh_2": "<value written>", "mgh_3": "<value written>",
      "mgh_4": "<value written>", "product_type": "<value written>"}
     at /tmp/${tmp_tag}_new_entries.jsonl. If there are zero qualifying products, skip this step
     entirely -- do not run the command below with an empty or missing file.
  2. Run ONE batch call (never one call per product):
     ${PYTHON_BIN} ${REPO_ROOT}/script/non_niq/non_niq_helper.py index \\
       --input-file /tmp/${tmp_tag}_new_entries.jsonl \\
       --meili-index ${MEILI_INDEX}
     Run this synchronously and wait for it to finish, same as every other tool call this
     session.

Hard rules, never relaxed:
- NEVER background any tool call and NEVER end your turn to wait for one to finish -- this is a
  single one-shot session with no way to resume and no notification will ever arrive. Always
  issue tool calls synchronously and wait for each one's real result before proceeding. Ending
  your turn before the full worklist is processed is not a valid outcome under any circumstance.
- All writes use bq query DML, never the streaming API -- CLAUDE.md's 90-minute streaming-buffer
  rule. The very next run's retry-cap logic depends on reading back this run's QA rows reliably.
- Never write to \`qa_status\` on the source table (master_table_prod). A separate QA-labelling
  update process reads \`${QA_TABLE}\` independently and flips \`qa_status\` to 'Reviewed' once a
  product has a row there.
- Every _meta read you do yourself (e.g. checking whether a product already has an unconfident
  row) must use JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.field'), never bare JSON_VALUE(_meta, ...)
  and never SAFE.JSON_VALUE(...) -- the latter LOOKS right but is not valid BigQuery syntax
  ("SAFE with function json_value is not supported"). Some existing _meta values on legacy human-
  labelled rows are NOT this pipeline's JSON shape at all (e.g. {"name":...,"role":"QAFREELANCE",
  ...}) -- SAFE.PARSE_JSON handles those fine, and JSON_VALUE for a field that isn't present
  simply returns NULL, which is correct/intended (those legacy rows have no qa_confidence, so
  they never satisfy the retry-eligible branch and are treated as already-resolved).
- Every _meta WRITE must be a JSON string, never a bare string. Baseline format:
    {"source":"claude_code","timestamp":"<now, ISO 8601 UTC>"}
  e.g. {"source":"claude_code","timestamp":"2026-09-02T19:19:06Z"}.
- Attempt to resolve the ENTIRE worklist within your turn budget this session -- do not
  self-limit to a small sample. Stop early only when genuinely low on turns, and say so honestly
  in findings.

If you hit a genuine blocker -- something wrong with these instructions, missing data, anything
that would make proceeding unsafe -- stop and output status='blocked' with the blockers array
populated. That is a valid, expected outcome.

Output ONLY this JSON when done, nothing else (rows_created_in_dict here means "rows this
session newly indexed into Meilisearch in STEP 3" -- eiger has no separate dict-table insert
event to count):
{status: complete|partial|failed|blocked, rows_qa_confirmed, rows_qa_unconfident, rows_filtered, rows_created_in_dict, findings, blockers}.
PROMPT
}

extract_json_object() {
  local text="$1"
  printf '%s' "$text" | grep -Pzo '(?s)\{.*\}' | tr -d '\0'
}

# Identical to non_niq_qa_v2.sh's -- shared contract, not shared code.
extract_result_json() {
  local claude_output="$1"
  local result_json
  result_json=$(echo "$claude_output" | jq -r '.result // empty' 2>/dev/null) || result_json=""
  if [[ -z "$result_json" ]]; then
    echo ""
    return
  fi
  if ! echo "$result_json" | jq -e . >/dev/null 2>&1; then
    local extracted
    extracted=$(extract_json_object "$result_json")
    if [[ -n "$extracted" ]] && echo "$extracted" | jq -e . >/dev/null 2>&1; then
      result_json="$extracted"
    fi
  fi
  echo "$result_json"
}

decide_queue_signal() {
  local claude_output="$1"
  local result_json
  result_json=$(extract_result_json "$claude_output")
  if [[ -z "$result_json" ]]; then
    echo "FAILED"
    return
  fi
  local status
  status=$(echo "$result_json" | jq -r '.status // empty' 2>/dev/null) || status=""
  case "$status" in
    blocked) echo "BLOCKED" ;;
    complete|partial) echo "DONE" ;;
    *) echo "FAILED" ;;
  esac
}

format_result_summary() {
  local claude_output="$1"
  local result_json
  result_json=$(extract_result_json "$claude_output")

  local status rows_confirmed rows_unconfident rows_filtered rows_created findings blockers
  if [[ -z "$result_json" ]]; then
    status="unknown"
    rows_confirmed="?"
    rows_unconfident="?"
    rows_filtered="?"
    rows_created="?"
    findings="(unparseable)"
    blockers="(unparseable)"
  else
    status=$(echo "$result_json" | jq -r '.status // "unknown"' 2>/dev/null) || status="unknown"
    rows_confirmed=$(echo "$result_json" | jq -r '.rows_qa_confirmed // "?"' 2>/dev/null) || rows_confirmed="?"
    rows_unconfident=$(echo "$result_json" | jq -r '.rows_qa_unconfident // "?"' 2>/dev/null) || rows_unconfident="?"
    rows_filtered=$(echo "$result_json" | jq -r '.rows_filtered // "?"' 2>/dev/null) || rows_filtered="?"
    rows_created=$(echo "$result_json" | jq -r '.rows_created_in_dict // "?"' 2>/dev/null) || rows_created="?"
    findings=$(echo "$result_json" | jq -r '
      if .findings == null then "(none)"
      elif (.findings | type) == "array" then (.findings | join("\n"))
      else (.findings | tostring) end' 2>/dev/null) || findings="(unparseable)"
    blockers=$(echo "$result_json" | jq -r '
      if .blockers == null or (.blockers | length) == 0 then "(none)"
      elif (.blockers | type) == "array" then (.blockers | join("\n"))
      else (.blockers | tostring) end' 2>/dev/null) || blockers="(unparseable)"
  fi

  local num_turns duration_ms total_cost
  num_turns=$(echo "$claude_output" | jq -r '.num_turns // "?"' 2>/dev/null) || num_turns="?"
  duration_ms=$(echo "$claude_output" | jq -r '.duration_ms // "?"' 2>/dev/null) || duration_ms="?"
  total_cost=$(echo "$claude_output" | jq -r '.total_cost_usd // "?"' 2>/dev/null) || total_cost="?"

  local per_model
  per_model=$(echo "$claude_output" | jq -r '
    (.modelUsage // {}) | to_entries[] |
    "  \(.key): $\(.value.costUSD) (in: \(.value.inputTokens) tok, out: \(.value.outputTokens) tok, cache_read: \(.value.cacheReadInputTokens) tok, cache_creation: \(.value.cacheCreationInputTokens) tok)"
  ' 2>/dev/null) || per_model=""
  [[ -z "$per_model" ]] && per_model="  (no model usage reported)"

  cat <<SUMMARY

=== eiger QA Session Result ===
Status: ${status}
Confirmed: ${rows_confirmed} | Unconfident: ${rows_unconfident} | Filtered: ${rows_filtered} | Indexed: ${rows_created}

Turns used: ${num_turns} | Duration: ${duration_ms}ms | Total cost: \$${total_cost}

Per-model cost:
${per_model}

Findings:
${findings}

Blockers:
${blockers}
SUMMARY
}

main() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <PLATFORM> [COUNTRY] [MAX_TURNS] [MAX_ROWS]" >&2
    exit 1
  fi
  local platform="$1" country="${2:-ID}" max_turns="${3:-300}" max_rows="${4:-300}"
  country="${country^^}"

  log INFO "Resolving config Sheet row for eiger/${platform}/${country}..."
  local category_json
  category_json=$("$PYTHON_BIN" "$(dirname "$0")/non_niq_helper.py" categories --country "$country" \
    | jq -c --arg pl "$platform" '.[] | select(.dataset == "eiger" and .ecommerce_platform == $pl)')
  if [[ -z "$category_json" ]]; then
    echo "No active config Sheet row for dataset=eiger platform=${platform} country=${country}" >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "eiger:${platform}" "FAILED" "No active config Sheet row for country=${country}"
    exit 1
  fi

  local source_table filter_table_config enrichment_table
  source_table=$(echo "$category_json" | jq -r '.master_table_prod')
  filter_table_config=$(echo "$category_json" | jq -r '.filter_table')
  enrichment_table=$(echo "$category_json" | jq -r '."0"')
  local filter_table
  filter_table=$(primary_filter_table "$filter_table_config" "eiger")
  log INFO "Config resolved: source_table=${source_table}, qa_table=${QA_TABLE}, filter_table=${filter_table}"

  local t
  for t in "source_table=$source_table" "filter_table=$filter_table"; do
    if [[ "${t#*=}" == "-" || "${t#*=}" == "null" || -z "${t#*=}" ]]; then
      echo "Config Sheet row for dataset=eiger platform=${platform} has unconfigured ${t%%=*} ('${t#*=}') -- cannot run eiger QA." >&2
      echo "QUEUE_SIGNAL: FAILED"
      emit_result "eiger:${platform}" "FAILED" "Unconfigured ${t%%=*} in config Sheet row"
      exit 1
    fi
  done

  log INFO "Querying BigQuery for the latest month on ${source_table}/${platform}..."
  local month
  if ! month=$(bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=csv \
    "$(default_month_query "$source_table" "$platform")" | tail -1); then
    echo "bq query failed while resolving the latest month for ${source_table}/${platform} -- see bq's error above." >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "eiger:${platform}" "FAILED" "bq query failed resolving latest month for ${source_table}/${platform}"
    exit 1
  fi
  log INFO "Latest month resolved: ${month}"

  local tmp_tag="eiger_${platform}_${country}"
  local query
  query=$(worklist_query "$source_table" "$month" "$platform" "$enrichment_table" "$max_rows" "$filter_table")

  log INFO "Querying BigQuery to materialize the worklist (product_tier=Tier 1, limit=${max_rows})..."
  local worklist_file="/tmp/${tmp_tag}_full_worklist.jsonl"
  if ! bq query --use_legacy_sql=false --project_id="${PROJECT}" --format=json --max_rows=1000000 \
    "$query" | jq -c '.[]' > "$worklist_file"; then
    echo "bq query failed while materializing the worklist for eiger/${platform}/${country} -- see bq's error above." >&2
    echo "QUEUE_SIGNAL: FAILED"
    emit_result "eiger:${platform}" "FAILED" "bq query failed materializing worklist for eiger/${platform}/${country}"
    exit 1
  fi

  local worklist_count
  worklist_count=$(wc -l < "$worklist_file" | tr -d ' ')

  if [[ "$worklist_count" == "0" ]]; then
    echo "No in-scope worklist for eiger/${platform}/${country}/${month} (product_tier=Tier 1) -- nothing to do."
    rm -f "$worklist_file"
    echo "QUEUE_SIGNAL: NOTHING_TO_DO"
    emit_result "eiger:${platform}" "NOTHING_TO_DO" "No in-scope worklist for eiger/${platform}/${country}/${month}"
    exit 0
  fi

  log INFO "Worklist materialized: ${worklist_count} rows (eiger/${platform}/${country}, month=${month})"

  local prompt
  prompt=$(build_qa_prompt "$platform" "$country" "$source_table" "$filter_table" "$worklist_file" "$worklist_count" "$tmp_tag")

  log INFO "Delegating to claude (max_turns=${max_turns}) -- embeds+retrieves via Meilisearch, then runs the per-product QA loop. No further progress output until it returns."

  local claude_output
  claude_output=$(claude -p --output-format json --permission-mode bypassPermissions --max-turns "$max_turns" "$prompt") || true
  log INFO "claude subprocess returned, formatting summary..."
  echo "$claude_output"
  format_result_summary "$claude_output"

  local signal
  signal=$(decide_queue_signal "$claude_output")
  echo "QUEUE_SIGNAL: ${signal}"
  emit_result "eiger:${platform}" "$signal" "eiger QA session finished"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
```

- [ ] **Step 2: Make it executable and syntax-check it**

Run:
```bash
chmod +x script/non_niq/eiger_qa.sh
bash -n script/non_niq/eiger_qa.sh
```
Expected: `chmod` prints nothing (success); `bash -n` prints nothing and exits 0 (no output means
no syntax errors).

- [ ] **Step 3: Verify the SQL functions against real BigQuery, without running `main()`**

The script's `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]` guard means sourcing it does not
auto-invoke `main`. This sandbox's `gcloud` user auth is expired (confirmed earlier this
session), but the service-account key `keys/client-util.json` (same one `non_niq_helper.py`
itself already uses for Sheets access) is a valid, already-proven credential for BigQuery — use
it via the Python client to actually execute (not just dry-run) `worklist_query`'s SQL, since
these are cheap, side-effect-free `SELECT` statements:

```bash
source script/non_niq/eiger_qa.sh
month=$(python3 - <<'EOF'
from google.cloud import bigquery
from google.oauth2 import service_account
creds = service_account.Credentials.from_service_account_file("keys/client-util.json")
client = bigquery.Client(project="sincere-hearth-273704", credentials=creds)
q = "SELECT FORMAT_DATE('%Y-%m', MAX(month)) FROM \`sincere-hearth-273704.eiger.master_eiger_id\` WHERE ecommerce_platform = 'Shopee'"
print(list(client.query(q).result())[0][0])
EOF
)
echo "month resolved: $month"

query=$(worklist_query "eiger.master_eiger_id" "$month" "shopee" "0_pipeline_eiger_shopee_id" "5" "eiger.filter_eiger")
echo "$query" > /tmp/eiger_verify_query.sql
python3 - <<'EOF'
from google.cloud import bigquery
from google.oauth2 import service_account
creds = service_account.Credentials.from_service_account_file("keys/client-util.json")
client = bigquery.Client(project="sincere-hearth-273704", credentials=creds)
query = open("/tmp/eiger_verify_query.sql").read()
rows = list(client.query(query).result())
print(f"rows returned: {len(rows)}")
for r in rows[:2]:
    print(dict(r))
EOF
```

Expected: the query executes without a BigQuery error (proves every column reference —
`s.brand_store`, the `qa_state`/`filter_state` CTEs against `QA_TABLE`/`filter_table`, the
Shopee enrichment join — is valid against the real schemas), and prints 0-5 rows shaped like
`{'product_id': ..., 'sku_name': ..., ..., 'brand_store': ..., 'priority': 0 or 1}`. Zero rows
is an acceptable outcome (per the spec's "Live data confirmed" section, only ~9 Tier-1 Shopee
rows are currently `qa_status='Not Reviewed'`) — the check that matters is "no BigQuery error",
not a nonzero row count.

Repeat the same check once more for a non-Shopee platform (e.g. `"lazada"`, no enrichment table
argument needed — pass `"-"` as the 4th `worklist_query` argument) to confirm the
enrichment-skipping branch also produces valid SQL:

```bash
query=$(worklist_query "eiger.master_eiger_id" "$month" "lazada" "-" "5" "eiger.filter_eiger")
echo "$query" > /tmp/eiger_verify_query_lazada.sql
python3 - <<'EOF'
from google.cloud import bigquery
from google.oauth2 import service_account
creds = service_account.Credentials.from_service_account_file("keys/client-util.json")
client = bigquery.Client(project="sincere-hearth-273704", credentials=creds)
query = open("/tmp/eiger_verify_query_lazada.sql").read()
rows = list(client.query(query).result())
print(f"rows returned: {len(rows)}")
EOF
```

Expected: executes without error, same "0 rows is fine, error is not" standard.

- [ ] **Step 4: Commit**

```bash
git add script/non_niq/eiger_qa.sh
git commit -m "$(cat <<'EOF'
Add dedicated eiger_qa.sh for eiger's image-taxonomy QA

eiger has no free-text dict table -- categorization follows a fixed
guidance-doc tree (docs/eiger_labelling_guidance.csv) and brand is
constrained by eiger.brand_store_product_fix for known multi-brand
resellers. Reuses non_niq_qa_v2.sh's worklist/confidence-loop/result-
summary scaffolding verbatim; STEP 1 (Meilisearch corpus) and STEP 2
(categorization) are eiger-specific, per the design spec.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Mcu8zuyutEPGDbk5iNm8SK
EOF
)"
```

---

## Task 3: `docs/eiger-qa-handoff.md` — self-contained handoff doc

**Files:**
- Create: `docs/eiger-qa-handoff.md`

**Interfaces:**
- Consumes: nothing (pure documentation).
- Produces: a reference doc other tasks/readers link to; no code interface.

- [ ] **Step 1: Verify the Meilisearch backfill query runs, before writing the doc that ships it**

```bash
python3 - <<'EOF'
from google.cloud import bigquery
from google.oauth2 import service_account
creds = service_account.Credentials.from_service_account_file("keys/client-util.json")
client = bigquery.Client(project="sincere-hearth-273704", credentials=creds)
q = """
SELECT product_id, sku_name, brand, product_type, sku_type_complete, mgh_2, mgh_3, mgh_4
FROM `sincere-hearth-273704.eiger.product_id_dict_image_qa`
WHERE product_type IS NOT NULL
  AND sku_type_complete NOT IN ('-', '{Defining Process}')
QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY timestamp DESC NULLS LAST) = 1
"""
rows = list(client.query(q).result())
print(f"backfill row count: {len(rows)}")
print(dict(rows[0]))
EOF
```

Expected: executes without error, prints a row count (a majority of the 30,083-row table minus
the ~42% placeholder/NULL rows the spec identified — a few thousand to ~20,000 is the plausible
range; the exact count is not asserted, only that the query runs and returns real rows). This
query becomes the copy-pasteable block in the handoff doc — do NOT run `non_niq_helper.py index`
against it as part of this task. Actually populating the shared `eiger_taxonomy_qa` Meilisearch
index is a one-time deployment action with real side effects on a service other running
pipelines may query — leave it for the user (or whoever picks up the handoff doc) to trigger
explicitly when ready, not something this plan executes automatically.

- [ ] **Step 2: Write `docs/eiger-qa-handoff.md`**

```markdown
# Handoff: eiger image-taxonomy QA

> Self-contained — assumes no context from the session that built this. If you're reading this
> to run or maintain `script/non_niq/eiger_qa.sh`, or to hook it into a Windmill-driven task
> queue, this is everything you need. Full design rationale:
> [`docs/superpowers/specs/2026-09-02-eiger-image-taxonomy-qa-design.md`](superpowers/specs/2026-09-02-eiger-image-taxonomy-qa-design.md).

## What this is

`eiger` (Outdoor Equipment & Supplies, ID, platforms lazada/shopee/tiktok/tokopedia) is a
non-NIQ agentic QA category like `cookiesbiscuit`/`babybath`/etc., run via
`script/non_niq/non_niq_qa_v2.sh` for every other dataset — **except eiger has no free-text
taxonomy dict table**, so it gets its own script, `script/non_niq/eiger_qa.sh`:

```
script/non_niq/eiger_qa.sh <PLATFORM> [COUNTRY] [MAX_TURNS] [MAX_ROWS]
# e.g. script/non_niq/eiger_qa.sh shopee ID 300 300
```

If you already know `non_niq_qa_v2.sh`: the worklist materialization shape (Tier-1 scoped,
priority 0/1 via `_meta.qa_confidence`, filter-table exclusion), the retry-once confidence loop,
and the `_meta` JSON conventions are identical. What's different is STEP 1 (the Meilisearch
corpus) and STEP 2 (how a product gets categorized) — see below.

## Real table names (the Sheet is wrong/incomplete for two of these)

| Concept | v2's Sheet column | eiger's real table | Notes |
|---|---|---|---|
| Source (Tier-1 scoped) | `master_table_prod` | `eiger.master_eiger_id` | Correctly configured in the Sheet |
| QA output | `product_id_dict_qa` | `eiger.product_id_dict_image_qa` | Sheet's `product_id_dict_qa` is `-`; the real table lives under the Sheet's `product_id_dict_image_qa` column, which `non_niq_helper.py`'s `ROW_FIELDS` doesn't read yet — `eiger_qa.sh` hardcodes the table name as a constant instead |
| Taxonomy dict | `dict` | *(none)* | eiger has no free-text dict table at all — see below |
| Filter/exclusion | `filter_table` | `eiger.filter_eiger` | Correctly configured in the Sheet |

`eiger.product_id_dict` does not exist in BigQuery. `eiger.product_id_dict_image` exists but is
sparse and unused by this pipeline — don't confuse it with `product_id_dict_image_qa`.

## `eiger.product_id_dict_image_qa` schema

`product_id, ecommerce_platform, brand, sku_name, sku_type_complete, vlookup, mgh_2, mgh_3,
mgh_4, product_type, image, keywords, color, _meta, timestamp, gender`

Insert-only (many historical rows per product, same convention as every other dataset's QA
table). `vlookup`, `color`, `gender` are unused by `eiger_qa.sh` — always left NULL. 30,083
existing rows are from a prior human-QA-freelance process; ~42% have NULL or placeholder
(`'-'`, `'{Defining Process}'`) `sku_type_complete` — those are pre-existing gaps, not something
this script backfills.

## Categorization rule: guidance-doc tree, not free text

`docs/eiger_labelling_guidance.csv` (1061 rows, columns `mgh_2, mgh_3, mgh_4, product_type,
Product Style`) is the ONLY valid source of category values. A product's `mgh_2 → mgh_3 → mgh_4
→ product_type → Product Style` path must be one that actually exists as a row in this CSV —
never free-typed at any level. The CSV's own catch-all leaf values (`Not assigned`, `N/A`,
`Mix`) mean there is always a valid Product Style once the four-level path is right. Product
Style gets written to both `sku_type_complete` and `keywords` on the QA table.

## Brand rule: `eiger.brand_store_product_fix` for known multi-brand resellers only

`eiger.brand_store_product_fix` (`brand_store, brand, url, ...`, 203 rows / 119 stores / 179
brands) is a strict override list for a small set of stores — like "Decathlon" — that sell many
different sub-brands under one storefront. If a product's `brand_store` appears in this table,
its brand MUST come from this table (matched by `url` first, else by disambiguating among that
store's listed brands using the product's own image/text). For every other store (the large
majority — only ~20 of eiger's ~250 Tier-1 merchants are covered here), brand comes from normal
image/text judgment, same as any other dataset. This table is read-only reference data — never
write to it or try to expand its coverage.

## Meilisearch: one-time corpus backfill

Index name: `eiger_taxonomy_qa`. It starts empty — before running `eiger_qa.sh` for the first
time, seed it from the 30,083 existing (human-labelled) QA rows, filtered to ones with a real
categorization:

```sql
SELECT product_id, sku_name, brand, product_type, sku_type_complete, mgh_2, mgh_3, mgh_4
FROM `sincere-hearth-273704.eiger.product_id_dict_image_qa`
WHERE product_type IS NOT NULL
  AND sku_type_complete NOT IN ('-', '{Defining Process}')
QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY timestamp DESC NULLS LAST) = 1
```

Run it, save the output as JSONL (one row per line), then:

```bash
.venv/bin/python3 script/non_niq/non_niq_helper.py index \
  --input-file <backfill.jsonl> --meili-index eiger_taxonomy_qa
```

This is a real write to a shared Meilisearch instance (`http://34.124.146.29:7700`) — run it
once, deliberately, not as part of any automated pipeline. Going forward, `eiger_qa.sh`'s own
STEP 3 keeps the index updated incrementally after every session (newly-confident rows only).

## What was deliberately NOT done

- `non_niq_helper.py`'s `ROW_FIELDS` still doesn't read the Sheet's `product_id_dict_image_qa`/
  `product_id_image_taxonomy` columns — `eiger_qa.sh` hardcodes the real QA table name as a
  constant instead. If you "fix" `ROW_FIELDS` later, update `eiger_qa.sh`'s `QA_TABLE` constant
  to read from the Sheet too, or the two will drift.
- `eiger.brand_store_product_fix`'s coverage gap (20/250 Tier-1 stores) is not addressed —
  accepted as-is per explicit product decision.
- Legacy `product_id_dict_image_qa` rows with placeholder/NULL `sku_type_complete` (~42%) are
  not backfilled or corrected — out of scope, `eiger_qa.sh` only processes the current Tier-1
  worklist going forward.
- No wiring into `script/non_niq/queue_worker.sh` or the task-queue submitter UI — this script is
  run directly for now (`script/non_niq/eiger_qa.sh <platform> ...`), same as any other
  dataset's script before it's queue-integrated.
```

- [ ] **Step 3: Commit**

```bash
git add docs/eiger-qa-handoff.md
git commit -m "$(cat <<'EOF'
Add self-contained handoff doc for eiger's image-taxonomy QA

For a reader with none of the design session's context: real table
names vs. the Sheet's stale columns, the guidance-doc categorization
rule, the brand-fix-table rule, and the one-time Meilisearch backfill
command.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Mcu8zuyutEPGDbk5iNm8SK
EOF
)"
```
