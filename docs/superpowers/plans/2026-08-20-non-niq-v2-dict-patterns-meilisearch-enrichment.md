# Non-NIQ v2 — Dict Patterns, Meilisearch Write-Back, Shopee Enrichment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three capabilities to `script/non_niq/non_niq_qa_v2.sh`: self-bootstrapping per-category dict-column generation rules with NOT NULL enforcement, live Meilisearch write-back for newly-minted taxonomy entries, and the Shopee `item_description`/`product_attributes_attrs` worklist enrichment already built and debugged in v1.

**Architecture:** Task 1 ports v1's existing enrichment mechanism into v2's `worklist_query()`/`build_qa_prompt()`/`main()` unchanged. Task 2 extends `build_qa_prompt()`'s STEP 2c prompt text only — no new script parameters, since the pattern-config path is computed inline from globals already in scope. Task 3 adds a new `index` subcommand to `non_niq_helper.py`, mirroring the existing `retrieve` subcommand's shape and the Windmill script's document/index conventions. Task 4 wires a new STEP 3 into `build_qa_prompt()` that calls Task 3's command in one batch at the end of a session.

**Tech Stack:** Bash (`non_niq_qa_v2.sh`), Python 3 + `google-cloud-bigquery` + `sentence-transformers` (`non_niq_helper.py`), BigQuery SQL, Meilisearch HTTP API.

**Spec:** `docs/superpowers/specs/2026-08-20-non-niq-v2-dict-patterns-meilisearch-enrichment-design.md`

## Global Constraints

- v1 (`script/non_niq/non_niq_qa.sh`) is not modified by this plan.
- No config Sheet schema changes.
- No changes to the Windmill `non_niq_embed.py` script or its manual-trigger batch sync.
- Every dict-table column on a newly created row must be non-null except `${dict_typo_col}` (resolved dynamically per category — e.g. `keywords_typo`/`keyword_typo`).
- `dict_patterns/<dataset>.json` schema: `{"<generated_column>": {"sources": ["<col>", ...], "separator": "<str>"}}`. Composition skips null/empty sources.
- Meilisearch write-back fires only for a product that (a) got a brand-new dict entry created for it this session AND (b) ended up `qa_confidence: "confident"`.
- All new batch operations (STEP 1's existing retrieval, STEP 3's new indexing) are one call for the whole qualifying set, never one call per product.
- Tests run via `bash tests/non_niq/test_non_niq_qa_v2.sh` and `python3 tests/non_niq/test_non_niq_helper.py` (or however this repo's Python tests are invoked — check for a `pytest.ini`/`pyproject.toml` test runner config first; if none, run the file directly the same way `test_non_niq_helper.py`'s own `__main__` block does).

---

### Task 1: Port Shopee description/spec enrichment into v2

**Files:**
- Modify: `script/non_niq/non_niq_qa_v2.sh` (`worklist_query()` lines 68-140, `build_qa_prompt()` STEP 0 text around lines 201-210 and STEP 2a text around lines 236-257, `main()` lines 462-467 and 508)
- Test: `tests/non_niq/test_non_niq_qa_v2.sh`

**Interfaces:**
- Produces: `worklist_query()`'s new signature `worklist_query SOURCE_TABLE QA_TABLE QA_PK_COL MONTH PLATFORM [ENRICHMENT_TABLE] [ROW_LIMIT=300] [FILTER_TABLE]` — `enrichment_table` is the new 6th positional parameter (matches v1's `worklist_query` parameter position exactly), shifting `row_limit` to 7th and `filter_table` to 8th.
- Consumes: nothing new from other tasks.

- [ ] **Step 1: Write failing tests for `worklist_query()`'s enrichment behavior**

Add to `tests/non_niq/test_non_niq_qa_v2.sh`, right after the existing `# --- worklist_query filter_table exclusion ---` block (after its `echo "PASS: worklist_query filter_table exclusion"` line, currently line 90):

```bash
# --- worklist_query enrichment (item_description/product_attributes_attrs, ported from v1) ---
q_enriched=$(worklist_query "cookiesbiscuit.master_cookiesbiscuit_id" "cookiesbiscuitlemonilo.product_id_dict_qa" "prod_id" "2026-07" "shopee" "0_pipeline_cookiesbiscuit_shopee_id")
echo "$q_enriched" | grep -q "enrichment_dedup AS" || fail "worklist_query (v2) must create an enrichment_dedup CTE for deduplication"
echo "$q_enriched" | grep -q "QUALIFY ROW_NUMBER() OVER (PARTITION BY item_itemid ORDER BY timestamp DESC) = 1" || fail "worklist_query (v2) must dedupe enrichment table to latest row per item_itemid"
echo "$q_enriched" | grep -q "FROM \`sincere-hearth-273704.cookiesbiscuit.0_pipeline_cookiesbiscuit_shopee_id\`" || fail "worklist_query (v2) must reference the enrichment table in enrichment_dedup CTE"
echo "$q_enriched" | grep -q "LEFT JOIN enrichment_dedup e ON CAST(e.item_itemid AS STRING) = s.product_id" || fail "worklist_query (v2) must join the dedup CTE on item_itemid = product_id"
echo "$q_enriched" | grep -q "e.item_description, e.product_attributes_attrs" || fail "worklist_query (v2) must select item_description/product_attributes_attrs from the enrichment_dedup CTE"
echo "$q_enriched" | grep -q "sc.item_description, sc.product_attributes_attrs" || fail "worklist_query (v2) must carry item_description/product_attributes_attrs through to the final SELECT"
echo "$q_enriched" | grep -qF "STRING_AGG(CONCAT(JSON_VALUE(a,'\$.name'),'=',JSON_VALUE(a,'\$.value')), '; ')" || fail "worklist_query (v2)'s enrichment_dedup CTE must project product_attributes_attrs down to a compact name=value string via STRING_AGG"
echo "$q_enriched" | grep -qF "COALESCE(" || fail "worklist_query (v2) must try raw SAFE.PARSE_JSON first and fall back to a normalized parse"
echo "$q_enriched" | grep -qF "SAFE.PARSE_JSON(product_attributes_attrs)," || fail "worklist_query (v2)'s COALESCE must try the raw product_attributes_attrs first, so already-valid JSON is never run through Python-repr normalization"
echo "$q_enriched" | grep -qF "CHR(39), CHR(34)" || fail "worklist_query (v2)'s Python-repr fallback must swap single quotes for double quotes"
echo "$q_enriched" | grep -qF "': None', ': null'" || fail "worklist_query (v2)'s Python-repr fallback must normalize None/True/False to JSON's null/true/false"

# Non-Shopee platform -> no join, NULL columns instead, even if an enrichment_table value is passed.
q_noenrich=$(worklist_query "cookiesbiscuit.master_cookiesbiscuit_id" "cookiesbiscuitlemonilo.product_id_dict_qa" "prod_id" "2026-07" "blibli" "0_pipeline_cookiesbiscuit_blibli_id")
if echo "$q_noenrich" | grep -q "enrichment_dedup AS"; then
  fail "worklist_query (v2) must never build the enrichment CTE for a non-Shopee platform"
fi
echo "$q_noenrich" | grep -q "NULL AS item_description, NULL AS product_attributes_attrs" || fail "worklist_query (v2) must select NULL item_description/product_attributes_attrs for non-Shopee platforms"

# No enrichment table given at all (Sheet's "0" column empty) -> same NULL fallback, even for Shopee.
q_missing=$(worklist_query "cookiesbiscuit.master_cookiesbiscuit_id" "cookiesbiscuitlemonilo.product_id_dict_qa" "prod_id" "2026-07" "shopee")
if echo "$q_missing" | grep -q "enrichment_dedup AS"; then
  fail "worklist_query (v2) must not attempt a join when no enrichment_table is given"
fi
echo "$q_missing" | grep -q "NULL AS item_description, NULL AS product_attributes_attrs" || fail "worklist_query (v2) must select NULL item_description/product_attributes_attrs when enrichment_table is omitted"

# enrichment_table literal string "null" (jq -r on a missing/null JSON key) must be treated the
# same as an unconfigured enrichment_table -- consistency with main()'s three-sentinel guard.
q_null_sentinel=$(worklist_query "cookiesbiscuit.master_cookiesbiscuit_id" "cookiesbiscuitlemonilo.product_id_dict_qa" "prod_id" "2026-07" "shopee" "null")
if echo "$q_null_sentinel" | grep -q "enrichment_dedup AS"; then
  fail "worklist_query (v2) must treat the literal string 'null' the same as an unconfigured enrichment_table"
fi
echo "$q_null_sentinel" | grep -q "NULL AS item_description, NULL AS product_attributes_attrs" || fail "worklist_query (v2) must select NULL item_description/product_attributes_attrs when enrichment_table is the literal string 'null'"
echo "PASS: worklist_query enrichment"
```

Also fix the one existing call site whose positional args shift because `enrichment_table` is inserted at position 6. Find this line (currently line 82):

```bash
q_filtered=$(worklist_query "cookiesbiscuit.master_cookiesbiscuit_id" "cookiesbiscuitlemonilo.product_id_dict_qa" "prod_id" "2026-07" "shopee" "300" "cookiesbiscuitlemonilo.filter_cookiesbiscuit")
```

Replace with (empty string inserted for the new `enrichment_table` position):

```bash
q_filtered=$(worklist_query "cookiesbiscuit.master_cookiesbiscuit_id" "cookiesbiscuitlemonilo.product_id_dict_qa" "prod_id" "2026-07" "shopee" "" "300" "cookiesbiscuitlemonilo.filter_cookiesbiscuit")
```

- [ ] **Step 2: Run the test file, confirm the new tests fail**

Run: `bash tests/non_niq/test_non_niq_qa_v2.sh`
Expected: FAIL at the new `worklist_query enrichment` block (function doesn't build the enrichment CTE yet), and/or the shifted `q_filtered` assertions failing because `"300"` is currently read as `enrichment_table` doesn't exist as a concept yet — actually this call will still "pass" syntactically today since extra positional args just fall into unused local vars; the NEW enrichment assertions are what must fail. Confirm the failure message names the enrichment block, not the pre-existing filter_table block.

- [ ] **Step 3: Implement — modify `worklist_query()`**

Replace the whole `worklist_query()` function (current lines 68-140) with:

```bash
worklist_query() {
  local source_table="$1" qa_table="$2" qa_pk_col="$3" month="$4" platform="$5" enrichment_table="${6:-}"
  # Same LIMIT rationale as v1: a single agent session's turn budget can't process an unbounded
  # worklist. 300 is the same safe default.
  local row_limit="${7:-300}"
  local filter_table="${8:-}"
  local platform_titlecase="${platform^}"
  # item_description/product_attributes_attrs enrichment is Shopee-only by data availability --
  # ported VERBATIM from non_niq_qa.sh's worklist_query (v1), already debugged there (confirmed
  # live: non-Shopee 0_pipeline_* tables have a different schema with no description/specs
  # columns at all). dataset is derived from source_table (already "{dataset}.master_..." per
  # master_table_prod's own convention) rather than a separate parameter.
  local dataset="${source_table%%.*}"
  local enrichment_cte_and_join="" enrichment_join="" enrichment_select="NULL AS item_description, NULL AS product_attributes_attrs"
  if [[ "$platform_titlecase" == "Shopee" && -n "$enrichment_table" && "$enrichment_table" != "-" && "$enrichment_table" != "null" ]]; then
    # enrichment_table is a history table with multiple rows per item_itemid (confirmed live on
    # v1: ~108 rows per item avg). Dedupe to latest row per item before joining.
    # product_attributes_attrs is raw Shopee attribute JSON, projected down to a compact
    # "name=value; name=value" string -- same COALESCE-based Python-repr-vs-JSON fallback v1 uses
    # (confirmed live there: ~94% of populated rows are Python repr(), not valid JSON, so a bare
    # SAFE.PARSE_JSON alone would null out almost all real signal).
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
  # image carries the same live-observed embedded-double-quote artifact v1 found and fixed --
  # stripping here, once, rather than relying on the prompt to strip it per-product.
  #
  # filter_table exclusion: same rationale as v1 -- STEP 2a's NO branch writes ONLY to the filter
  # table, never to qa_table, so a product already confirmed out-of-scope must be excluded here
  # explicitly (qa_status alone can't be relied on for this -- this harness never writes it; a
  # separate external process owns that). SELECT DISTINCT absorbs filter_table's own known
  # duplicate-row issue -- existence is all that matters, not row count.
  local filter_cte="" filter_join="" filter_priority_check=""
  if [[ -n "$filter_table" && "$filter_table" != "-" && "$filter_table" != "null" ]]; then
    filter_cte="filter_state AS (
  SELECT DISTINCT product_id FROM \`${PROJECT}.${filter_table}\`
),
"
    filter_join="LEFT JOIN filter_state fs ON fs.product_id = sc.product_id"
    filter_priority_check="WHEN fs.product_id IS NOT NULL THEN NULL
      "
  fi
  cat <<SQL
WITH ${enrichment_cte_and_join}scoped AS (
  SELECT s.product_id, s.sku_name, REPLACE(s.image, '"', '') AS image, s.ecommerce_platform, s.qa_status, s.gmv_monthly, ${enrichment_select}
  FROM \`${PROJECT}.${source_table}\` s
  ${enrichment_join}
  WHERE s.product_tier = 'Tier 1'
    AND FORMAT_DATE('%Y-%m', s.month) = '${month}'
    AND s.ecommerce_platform $(platform_match_clause "$platform_titlecase")
),
qa_state AS (
  -- product_id_dict_qa is INSERT-ONLY -- a product can have many historical rows, not one. A raw
  -- SELECT (no dedup) fans out the LEFT JOIN below: a product with an OLD unconfident row and a
  -- NEWER confident row would match on the old row too, leaking a resolved product back into the
  -- worklist as priority=1 forever. Confirmed live (project memory
  -- project_non_niq_qa_state_fanout_bug.md): a 380-row v2 worklist was 100% already-resolved this
  -- way (332 confident, 48 terminal, 0 genuinely retry-eligible). Deduping to the "latest row by
  -- timestamp" is NOT the fix -- also confirmed live (same memory): product_id_dict_qa has no
  -- timestamp COLUMN (only inside _meta JSON, absent entirely on legacy rows), and "latest row"
  -- ordering was caught silently UN-TERMINATING products whenever a later write landed after a
  -- human_review:true row. The correct fix is order-independent aggregate flags over the WHOLE
  -- history per product: has this product EVER been confident, EVER gone terminal, EVER had a
  -- still-pending unconfident row -- gate priority 1 on pending-and-never-resolved, not on
  -- whichever row happens to sort last.
  SELECT
    ${qa_pk_col} AS product_id,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.qa_confidence') = 'unconfident'
               AND COALESCE(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.human_review'), 'false') != 'true') AS has_unconfident_pending,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.qa_confidence') = 'confident') AS has_confident,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '\$.human_review') = 'true') AS has_terminal
  FROM \`${PROJECT}.${qa_table}\`
  GROUP BY ${qa_pk_col}
),
${filter_cte}prioritized AS (
  SELECT sc.product_id, sc.sku_name, sc.image, sc.gmv_monthly, sc.ecommerce_platform,
         sc.item_description, sc.product_attributes_attrs,
    CASE
      ${filter_priority_check}WHEN qs.product_id IS NULL AND sc.qa_status = 'Not Reviewed' THEN 0
      WHEN qs.has_unconfident_pending AND NOT qs.has_confident AND NOT qs.has_terminal THEN 1
      ELSE NULL
    END AS priority
  FROM scoped sc
  LEFT JOIN qa_state qs ON qs.product_id = sc.product_id
  ${filter_join}
)
SELECT * FROM prioritized
WHERE priority IS NOT NULL
ORDER BY priority ASC, gmv_monthly DESC
LIMIT ${row_limit}
SQL
}
```

Note this changes `scoped`'s `FROM` clause to alias the source table as `s` (needed for the enrichment join's `s.product_id` reference) and qualifies every column in `scoped`'s SELECT/WHERE with `s.` — purely mechanical, behavior-preserving when `enrichment_select`/`enrichment_join` are empty.

- [ ] **Step 4: Run the test file, confirm the enrichment tests and the shifted filter_table test now pass**

Run: `bash tests/non_niq/test_non_niq_qa_v2.sh`
Expected: `PASS: worklist_query enrichment` prints, `PASS: worklist_query filter_table exclusion` still passes. (Later blocks will still fail until Steps 5-9 below — that's expected at this point.)

- [ ] **Step 5: Write failing tests for `build_qa_prompt()`'s STEP 0/2a enrichment text**

In `tests/non_niq/test_non_niq_qa_v2.sh`, find this block (currently lines 120-122):

```bash
if echo "$prompt" | grep -q "item_description\|product_attributes_attrs"; then
  fail "prompt (v2) must not reference the Shopee enrichment feature -- not carried over from v1"
fi
```

Replace with:

```bash
echo "$prompt" | grep -q "item_description, product_attributes_attrs, priority" || fail "STEP 0 must list item_description/product_attributes_attrs in the worklist row shape"
echo "$prompt" | grep -q "product_attributes_attrs" || fail "STEP 2a must mention product_attributes_attrs as additional signal alongside item_description"
echo "$prompt" | grep -qi "Shopee-only signal and NULL on other platforms" || fail "STEP 2a must note item_description/product_attributes_attrs are Shopee-only and NULL elsewhere"
```

- [ ] **Step 6: Run the test file, confirm the new prompt assertions fail**

Run: `bash tests/non_niq/test_non_niq_qa_v2.sh`
Expected: FAIL at the new STEP 0/STEP 2a assertions (the prompt text doesn't mention these fields yet).

- [ ] **Step 7: Implement — extend `build_qa_prompt()`'s STEP 0 and STEP 2a text**

In the `cat <<PROMPT ... PROMPT` heredoc inside `build_qa_prompt()`, find the STEP 0 paragraph (currently):

```
STEP 0 -- The full worklist has ALREADY been materialized for you at
${worklist_file}, exactly ${worklist_count} rows, one JSON object per line (JSONL) -- do NOT query
BigQuery to re-fetch it, and do NOT trust any other row count than ${worklist_count}. Read the file
(in slices if it's too large for one Read) rather than querying BigQuery for it. Each line has:
product_id, sku_name, image, gmv_monthly, ecommerce_platform, priority. It is already scoped to
```

Replace the "Each line has:" sentence with:

```
product_id, sku_name, image, gmv_monthly, ecommerce_platform, item_description,
product_attributes_attrs, priority. It is already scoped to
```

Find the STEP 2a paragraph (currently):

```
      Then, with the image + sku_name together -- does this product genuinely belong in
      "${dataset}"?
```

Replace with:

```
      Then, with the image + sku_name + item_description + product_attributes_attrs together (the
      worklist's own columns; product_attributes_attrs is a compact "name=value; name=value" string
      of the product's real Shopee attributes, e.g. brand/size -- not raw JSON;
      item_description/product_attributes_attrs are Shopee-only signal and NULL on other platforms
      -- treat NULL as simply having no extra signal, not as a problem) -- does this product
      genuinely belong in "${dataset}"?
```

- [ ] **Step 8: Run the test file, confirm the prompt assertions now pass**

Run: `bash tests/non_niq/test_non_niq_qa_v2.sh`
Expected: `PASS: build_qa_prompt` (or the assertions leading up to it) now clear the STEP 0/2a checks.

- [ ] **Step 9: Write failing tests for `main()`'s enrichment_table wiring**

Find this block in `tests/non_niq/test_non_niq_qa_v2.sh` (currently around line 207):

```bash
if echo "$script_src" | grep -q "DISCORD_WEBHOOK_URL\|load_env.sh\|notify-discord\|notify_discord\|enrichment_table"; then
  fail "non_niq_qa_v2.sh must not reference Discord notification, load_env.sh, or the v1 enrichment feature"
fi
```

Replace with:

```bash
if echo "$script_src" | grep -q "DISCORD_WEBHOOK_URL\|load_env.sh\|notify-discord\|notify_discord"; then
  fail "non_niq_qa_v2.sh must not reference Discord notification or load_env.sh"
fi
grep -qF "enrichment_table=\$(echo \"\$category_json\" | jq -r '.\"0\"')" <<< "$script_src" || fail "main() (v2) must resolve enrichment_table from the Sheet's \"0\" column, same as v1"
grep -qF '"$enrichment_table" "$max_rows" "$filter_table")' <<< "$script_src" || fail "main() (v2) must thread enrichment_table through to worklist_query"
```

- [ ] **Step 10: Run the test file, confirm it fails**

Run: `bash tests/non_niq/test_non_niq_qa_v2.sh`
Expected: FAIL at the two new `main()` wiring assertions.

- [ ] **Step 11: Implement — resolve and thread `enrichment_table` through `main()`**

Find (current lines 462-467):

```bash
  local source_table qa_table dict_table filter_table_config product_id_dict
  source_table=$(echo "$category_json" | jq -r '.master_table_prod')
  qa_table=$(echo "$category_json" | jq -r '.product_id_dict_qa')
  dict_table=$(echo "$category_json" | jq -r '.dict')
  filter_table_config=$(echo "$category_json" | jq -r '.filter_table')
  product_id_dict=$(echo "$category_json" | jq -r '.product_id_dict')
```

Replace with:

```bash
  local source_table qa_table dict_table filter_table_config product_id_dict enrichment_table
  source_table=$(echo "$category_json" | jq -r '.master_table_prod')
  qa_table=$(echo "$category_json" | jq -r '.product_id_dict_qa')
  dict_table=$(echo "$category_json" | jq -r '.dict')
  filter_table_config=$(echo "$category_json" | jq -r '.filter_table')
  product_id_dict=$(echo "$category_json" | jq -r '.product_id_dict')
  enrichment_table=$(echo "$category_json" | jq -r '."0"')
```

Find (current line 508):

```bash
  query=$(worklist_query "$source_table" "$qa_table" "$qa_pk_col" "$month" "$platform" "$max_rows" "$filter_table")
```

Replace with:

```bash
  query=$(worklist_query "$source_table" "$qa_table" "$qa_pk_col" "$month" "$platform" "$enrichment_table" "$max_rows" "$filter_table")
```

- [ ] **Step 12: Run the full test file, confirm everything passes**

Run: `bash tests/non_niq/test_non_niq_qa_v2.sh`
Expected: `ALL TESTS PASSED (part 1: SQL builders)` and `ALL TESTS PASSED (part 2: prompt + main)`.

- [ ] **Step 13: Commit**

```bash
git add script/non_niq/non_niq_qa_v2.sh tests/non_niq/test_non_niq_qa_v2.sh
git commit -m "Port Shopee item_description/product_attributes_attrs enrichment from v1 to v2"
```

---

### Task 2: Self-bootstrapping per-category dict-column patterns

**Files:**
- Modify: `script/non_niq/non_niq_qa_v2.sh` (`build_qa_prompt()` STEP 2c text, currently lines 271-283 in the file as it stands after Task 1 — re-locate by searching for `two-step create in`)
- Create: `script/non_niq/dict_patterns/README.md`
- Test: `tests/non_niq/test_non_niq_qa_v2.sh`

**Interfaces:**
- Consumes: nothing from Task 1 (independent prompt-text region).
- Produces: nothing consumed by later tasks (Task 4's STEP 3 is independent of this section).

- [ ] **Step 1: Write failing tests for the dict-pattern instructions**

Add to `tests/non_niq/test_non_niq_qa_v2.sh`, in the `build_qa_prompt` test section (after the existing `echo "$prompt" | grep -qF "Never write to \`qa_status\`"` assertion, before `prompt_nodict=$(build_qa_prompt ...)`):

```bash
echo "$prompt" | grep -qF "script/non_niq/dict_patterns/cookiesbiscuit.json" || fail "Step A must reference this dataset's dict_patterns config path"
echo "$prompt" | grep -qF '"sources"' || fail "Step A must describe the dict_patterns JSON schema's sources key"
echo "$prompt" | grep -qF '"separator"' || fail "Step A must describe the dict_patterns JSON schema's separator key"
echo "$prompt" | grep -qi "sample ~10-20 existing rows" || fail "Step A must instruct inferring the pattern by sampling existing dict rows when no config exists"
echo "$prompt" | grep -qi "skipping any source that's null/empty" || fail "Step A must state that composition skips null/empty sources"
echo "$prompt" | grep -qF "non-null EXCEPT keywords_typo" || fail "Step B must state the universal NOT NULL rule naming the resolved typo column"
if echo "$prompt" | grep -qi "REPO_ROOT}/script/non_niq/dict_patterns/\${dataset}"; then
  fail "prompt must interpolate the real dataset name into the dict_patterns path, not leave a literal \${dataset} placeholder"
fi
```

- [ ] **Step 2: Run the test file, confirm the new assertions fail**

Run: `bash tests/non_niq/test_non_niq_qa_v2.sh`
Expected: FAIL at the new Step A/B assertions.

- [ ] **Step 3: Implement — extend STEP 2c's Step A/B text**

In `build_qa_prompt()`'s heredoc, find (this text is unchanged by Task 1, so it's still at its original location — search for `two-step create in`):

```
      NO  -> two-step create in \`${PROJECT}.${dict_table}\`:
             Step A: insert brand + ${dict_identity_col} + keywords (+ ${dict_typo_col} if you
                     have common misspellings), _meta stamped
                     '{"source":"claude_code","timestamp":"<now, ISO 8601 UTC>"}' here (see the
                     _meta format rule below -- NOT the bare string "claude_code", that is not
                     valid JSON).
             Step B: populate the remaining attribute columns for this dict's schema, GROUNDED on
                     existing dict rows' actual vocabulary and formatting -- query
                     \`SELECT DISTINCT <column> FROM ${PROJECT}.${dict_table}\` per attribute column
                     before writing a new value, prefer an existing value over inventing one, and
                     match existing formatting exactly (e.g. "150 ml" not "150ml").
             Then write brand/${qa_identity_col} values pointing at the new entry to
             \`${PROJECT}.${qa_table}\`.
```

Replace with:

```
      NO  -> two-step create in \`${PROJECT}.${dict_table}\`:
             Step A: FIRST resolve this category's generated-column pattern. Read
                     ${REPO_ROOT}/script/non_niq/dict_patterns/${dataset}.json.
                     - EXISTS -> follow it mechanically: each key is a generated column (e.g.
                       sku_type_complete, keywords), its "sources" is the ordered list of other
                       dict-table columns it's composed from, "separator" is how they're joined.
                       Populate every listed source column first (grounded via
                       \`SELECT DISTINCT <column> FROM ${PROJECT}.${dict_table}\`, same technique
                       as Step B below), skipping any source that's null/empty when composing --
                       never emit a literal "null" or a dangling separator.
                     - MISSING -> infer the pattern yourself: sample ~10-20 existing rows from
                       \`${PROJECT}.${dict_table}\` and work out how sku_type_complete/keywords
                       (and any other generated columns this category has) are actually composed
                       from other columns. Then Write your inferred pattern to
                       ${REPO_ROOT}/script/non_niq/dict_patterns/${dataset}.json in the schema
                       above, so the next session for this dataset reads it instead of
                       re-inferring.
                     Then insert brand + ${dict_identity_col} + keywords (+ ${dict_typo_col} if
                     you have common misspellings) into \`${PROJECT}.${dict_table}\`, _meta
                     stamped '{"source":"claude_code","timestamp":"<now, ISO 8601 UTC>"}' here
                     (see the _meta format rule below -- NOT the bare string "claude_code", that
                     is not valid JSON).
             Step B: populate the remaining attribute columns for this dict's schema, GROUNDED on
                     existing dict rows' actual vocabulary and formatting -- query
                     \`SELECT DISTINCT <column> FROM ${PROJECT}.${dict_table}\` per attribute column
                     before writing a new value, prefer an existing value over inventing one, and
                     match existing formatting exactly (e.g. "150 ml" not "150ml"). Every column
                     on the new row must be non-null EXCEPT ${dict_typo_col} -- after inserting,
                     verify with a \`SELECT\` for any NULL in a non-\`${dict_typo_col}\` column on
                     the just-inserted row (never trust bq's "affected rows" report as proof the
                     row is complete), and fix any NULL found (grounded via SELECT DISTINCT, same
                     as above) before moving on.
             Then write brand/${qa_identity_col} values pointing at the new entry to
             \`${PROJECT}.${qa_table}\`.
```

- [ ] **Step 4: Run the test file, confirm the new assertions pass**

Run: `bash tests/non_niq/test_non_niq_qa_v2.sh`
Expected: all `build_qa_prompt` assertions pass.

- [ ] **Step 5: Create the dict_patterns directory with a README documenting the schema**

Create `script/non_niq/dict_patterns/README.md`:

```markdown
# Dict-column generation patterns

One JSON file per dataset (e.g. `cookiesbiscuit.json`), self-bootstrapped by the v2 QA harness
(`non_niq_qa_v2.sh`'s STEP 2c) the first time it creates a dict entry for that dataset -- do not
hand-author these unless you're correcting a bad inference.

Schema:

```json
{
  "sku_type_complete": {"sources": ["sub_brand", "variant", "total_size"], "separator": " "},
  "keywords": {"sources": ["sku_type_complete", "keywords_typo"], "separator": " "}
}
```

Each top-level key is a generated `{dataset}_dict` table column. `sources` is the ordered list of
other dict-table columns it's composed from. `separator` is how they're joined. Composition skips
any source that's null/empty -- a generated column never ends up with a literal `"null"` or a
dangling separator when one of its sources (e.g. a nullable typo column) has no value for a given
row.

One file per dataset, not one shared file, so two datasets running QA sessions concurrently never
race on the same file.
```

- [ ] **Step 6: Commit**

```bash
git add script/non_niq/non_niq_qa_v2.sh script/non_niq/dict_patterns/README.md tests/non_niq/test_non_niq_qa_v2.sh
git commit -m "Add self-bootstrapping per-category dict-column pattern config to v2's dict creation step"
```

---

### Task 3: Add Meilisearch `index` subcommand to `non_niq_helper.py`

**Files:**
- Modify: `script/non_niq/non_niq_helper.py`
- Test: `tests/non_niq/test_non_niq_helper.py`

**Interfaces:**
- Produces: `index_documents(lines, meili_url, meili_index, model=None) -> int` (embeds + upserts, returns doc count), `ensure_index(meili_url, index_uid) -> None`, `_format_passage_text(text) -> str`, CLI subcommand `non_niq_helper.py index --input-file DOCS.jsonl --meili-index IDX [--meili-url URL]` reading JSONL of `{"product_id","sku_name","sku_type_complete","brand"}`. Task 4 (v2's STEP 3 prompt text) calls this CLI shape.
- Consumes: existing `_meili_request(meili_url, method, path, body=None)`, `MODEL_NAME`, `BATCH_SIZE`.

- [ ] **Step 1: Write failing tests**

Add to `tests/non_niq/test_non_niq_helper.py`, after the existing `# --- retrieve_candidates ---` section (after `test_retrieve_candidates_one_failure_does_not_abort_batch`, before `# --- _format_discord_table ---`):

```python
# --- E5 prefix formatting (corpus side) ---

def test_format_passage_text_for_indexed_corpus():
    assert non_niq_helper._format_passage_text("baby shampoo") == "passage: baby shampoo"

# --- ensure_index ---

def test_ensure_index_creates_when_missing(monkeypatch):
    calls = []
    def fake_meili_request(meili_url, method, path, body=None):
        calls.append((method, path, body))
        if method == "GET":
            return {"results": []}
        return {}
    monkeypatch.setattr(non_niq_helper, "_meili_request", fake_meili_request)
    non_niq_helper.ensure_index("http://fake", "babybath_taxonomy_qa")
    methods_paths = [(m, p) for m, p, _ in calls]
    assert ("POST", "/indexes") in methods_paths
    assert ("PATCH", "/indexes/babybath_taxonomy_qa/settings") in methods_paths

def test_ensure_index_skips_create_when_already_exists(monkeypatch):
    calls = []
    def fake_meili_request(meili_url, method, path, body=None):
        calls.append((method, path, body))
        if method == "GET":
            return {"results": [{"uid": "babybath_taxonomy_qa"}]}
        return {}
    monkeypatch.setattr(non_niq_helper, "_meili_request", fake_meili_request)
    non_niq_helper.ensure_index("http://fake", "babybath_taxonomy_qa")
    methods = [m for m, _, _ in calls]
    assert "POST" not in methods
    assert "PATCH" in methods

# --- index_documents ---

def test_index_documents_doc_shape(monkeypatch):
    posted = []
    def fake_meili_request(meili_url, method, path, body=None):
        if method == "GET":
            return {"results": [{"uid": "babybath_taxonomy_qa"}]}
        if method == "POST" and path.endswith("/documents"):
            posted.append(body)
        return {}
    monkeypatch.setattr(non_niq_helper, "_meili_request", fake_meili_request)
    lines = [{"product_id": 123, "sku_name": "Baby Shampoo 200ml", "sku_type_complete": "Shampoo 200 ml", "brand": "Acme"}]
    count = non_niq_helper.index_documents(lines, "http://fake", "babybath_taxonomy_qa", model=_FakeModel())
    assert count == 1
    doc = posted[0][0]
    assert doc["product_id"] == "123"
    assert doc["sku_name"] == "Baby Shampoo 200ml"
    assert doc["sku_type_complete"] == "Shampoo 200 ml"
    assert doc["brand"] == "Acme"
    assert doc["_vectors"]["default"] == [float(len("passage: Baby Shampoo 200ml"))]

def test_index_documents_batches_at_batch_size(monkeypatch):
    posted_batches = []
    def fake_meili_request(meili_url, method, path, body=None):
        if method == "GET":
            return {"results": [{"uid": "idx"}]}
        if method == "POST" and path.endswith("/documents"):
            posted_batches.append(len(body))
        return {}
    monkeypatch.setattr(non_niq_helper, "_meili_request", fake_meili_request)
    lines = [{"product_id": i, "sku_name": f"p{i}", "sku_type_complete": "T", "brand": "B"} for i in range(non_niq_helper.BATCH_SIZE + 10)]
    non_niq_helper.index_documents(lines, "http://fake", "idx", model=_FakeModel())
    assert posted_batches == [non_niq_helper.BATCH_SIZE, 10]

def test_index_documents_empty_input_is_noop(monkeypatch):
    calls = []
    monkeypatch.setattr(non_niq_helper, "_meili_request", lambda *a, **k: calls.append(1))
    count = non_niq_helper.index_documents([], "http://fake", "idx", model=_FakeModel())
    assert count == 0
    assert calls == []
```

- [ ] **Step 2: Run the test file, confirm it fails**

Run: `python3 tests/non_niq/test_non_niq_helper.py`
Expected: `AttributeError: module 'non_niq_helper' has no attribute '_format_passage_text'` (or similar for `ensure_index`/`index_documents`), since none of these exist yet.

- [ ] **Step 3: Implement — add `EMBED_DIM`, `_format_passage_text`, `ensure_index`, `index_documents`**

In `script/non_niq/non_niq_helper.py`, add after the existing `BATCH_SIZE = 256` line (line 46):

```python
EMBED_DIM = 1024
```

Add after `_format_query_text` (current lines 129-132), before `_meili_request`:

```python
def _format_passage_text(text):
    """Format text for the indexed corpus side (E5 asymmetric retrieval) -- mirrors
    non_niq_embed.py's Windmill-deployed version, kept in sync by convention (both index the same
    Meilisearch corpus, so both must embed with the same asymmetric prefix)."""
    return f"passage: {text}"
```

Add after `retrieve_candidates` (current lines 150-169), as a new section:

```python
# ---------------------------------------------------------------------------
# Indexing: embed + upsert newly-minted taxonomy entries into Meilisearch
# ---------------------------------------------------------------------------

def ensure_index(meili_url, index_uid):
    """Create the index if it doesn't exist yet, then (re-)apply settings either way -- cheap and
    idempotent, so no need to branch on whether settings already match. Same conventions as
    non_niq_embed.py's Windmill-deployed version (docs/windmill-non-niq-embed-prompt.md), so a
    v2-created index and a Windmill-synced index are interchangeable."""
    existing = _meili_request(meili_url, "GET", "/indexes?limit=200")
    uids = {r["uid"] for r in existing.get("results", [])}
    if index_uid not in uids:
        _meili_request(meili_url, "POST", "/indexes", {"uid": index_uid, "primaryKey": "product_id"})
    _meili_request(meili_url, "PATCH", f"/indexes/{index_uid}/settings", {
        "searchableAttributes": ["sku_name", "sku_type_complete", "brand"],
        "embedders": {"default": {"source": "userProvided", "dimensions": EMBED_DIM}},
    })


def index_documents(lines, meili_url, meili_index, model=None):
    """lines: list of {"product_id","sku_name","sku_type_complete","brand"} -- the shape v2's
    STEP 3 batches up from its own session writes. Embeds sku_name as an E5 passage (corpus side),
    upserts into meili_index (creating/configuring it first if needed), batched at BATCH_SIZE -- a
    1024-dim vector serialises to ~20KB of JSON, so a single POST for a large batch would blow
    past Meilisearch's 100MB payload limit. Returns the number of documents submitted; a caller
    with zero qualifying products should simply not call this (STEP 3's prompt instructs that),
    but an empty list is handled as a no-op regardless."""
    if not lines:
        return 0
    model = model or SentenceTransformer(MODEL_NAME)
    ensure_index(meili_url, meili_index)
    texts = [_format_passage_text(l["sku_name"]) for l in lines]
    vectors = model.encode(texts, batch_size=BATCH_SIZE, show_progress_bar=False, normalize_embeddings=True)
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
    for i in range(0, len(docs), BATCH_SIZE):
        _meili_request(meili_url, "POST", f"/indexes/{meili_index}/documents", docs[i:i + BATCH_SIZE])
    return len(docs)
```

Add a new CLI wrapper after `_cmd_retrieve` (current lines 261-267):

```python
def _cmd_index(args):
    lines = [json.loads(l) for l in open(args.input_file) if l.strip()]
    count = index_documents(lines, args.meili_url, args.meili_index)
    print(f"Indexed {count} products -> {args.meili_index}")
```

In `main()`, add a new subparser after the `ret_p` block (current lines 289-294):

```python
    index_p = sub.add_parser("index")
    index_p.add_argument("--input-file", required=True)
    index_p.add_argument("--meili-index", required=True)
    index_p.add_argument("--meili-url", default=MEILI_URL)
```

And add the dispatch branch after `elif args.command == "retrieve": _cmd_retrieve(args)` (current line 310):

```python
    elif args.command == "index":
        _cmd_index(args)
```

Finally, update the stale module docstring (current lines 7-9):

```
Meilisearch *indexing* (embedding the {dataset}_taxonomy_qa corpus) is Windmill's job now, deployed
separately -- see docs/windmill-non-niq-embed-prompt.md for that script. This helper only ever
READS from Meilisearch (the `retrieve` command), never writes to it.
```

Replace with:

```
Meilisearch: this helper both reads (the `retrieve` command, used every QA session) and writes
(the `index` command, called once at the end of a v2 QA session for newly-minted taxonomy entries
-- see non_niq_qa_v2.sh's STEP 3). Windmill's non_niq_embed.py (docs/windmill-non-niq-embed-prompt.md)
remains a separate, manual-trigger whole-corpus resync -- the two write paths don't conflict,
Meilisearch upserts are idempotent by product_id (the index's declared primaryKey).
```

And extend the subcommand list docstring (after the existing `retrieve` entry, current lines 22-31) with:

```
  index --input-file DOCS.jsonl --meili-index IDX [--meili-url URL]
      Embeds each product's sku_name as an E5 passage (asymmetric retrieval -- corpus side, not
      query side) and upserts into Meilisearch, creating/configuring the index first if it
      doesn't exist yet. Input: one {"product_id","sku_name","sku_type_complete","brand"} per
      line. Batched at BATCH_SIZE per POST (a 1024-dim vector serialises to ~20KB of JSON, so a
      single POST would blow past Meilisearch's 100MB payload limit above a few thousand rows).
```

- [ ] **Step 4: Run the test file, confirm it passes**

Run: `python3 tests/non_niq/test_non_niq_helper.py`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add script/non_niq/non_niq_helper.py tests/non_niq/test_non_niq_helper.py
git commit -m "Add Meilisearch index subcommand to non_niq_helper.py"
```

---

### Task 4: Wire batched Meilisearch write-back into v2's prompt (STEP 3)

**Files:**
- Modify: `script/non_niq/non_niq_qa_v2.sh` (`build_qa_prompt()`)
- Test: `tests/non_niq/test_non_niq_qa_v2.sh`

**Interfaces:**
- Consumes: Task 3's CLI shape `non_niq_helper.py index --input-file DOCS.jsonl --meili-index IDX`.
- Produces: nothing consumed by other tasks (last task in this plan).

- [ ] **Step 1: Write failing tests**

Add to `tests/non_niq/test_non_niq_qa_v2.sh`, in the `build_qa_prompt` test section (after the assertions added in Task 2, before `prompt_nodict=$(build_qa_prompt ...)`):

```bash
echo "$prompt" | grep -qF "STEP 3 -- Meilisearch write-back" || fail "prompt must include STEP 3 for Meilisearch write-back"
echo "$prompt" | grep -qF "non_niq_helper.py index" || fail "STEP 3 must invoke non_niq_helper.py's index subcommand"
echo "$prompt" | grep -qF -- "--meili-index cookiesbiscuit_taxonomy_qa" || fail "STEP 3 must pass the resolved meili_index to the index command"
echo "$prompt" | grep -qi "never index an unconfident guess" || fail "STEP 3 must explicitly exclude unconfident guesses from indexing"
echo "$prompt" | grep -qi "zero qualifying products, skip" || fail "STEP 3 must instruct skipping the call entirely when there's nothing to index"
echo "$prompt" | grep -qi "never one call per product" || fail "STEP 3 must state the batch-not-per-product rule, same as STEP 1"
```

- [ ] **Step 2: Run the test file, confirm it fails**

Run: `bash tests/non_niq/test_non_niq_qa_v2.sh`
Expected: FAIL at the new STEP 3 assertions (STEP 3 doesn't exist in the prompt yet).

- [ ] **Step 3: Implement — add STEP 3 to `build_qa_prompt()`**

In the heredoc, find the boundary between STEP 2's content and the "Hard rules, never relaxed:" section (STEP 2's last paragraph is 2d's self-QA instructions, ending with the confident-retry sentence; "Hard rules" immediately follows with a blank line between). Insert a new STEP 3 block right before `Hard rules, never relaxed:`:

```
STEP 3 -- Meilisearch write-back for newly-minted taxonomy entries. After STEP 2 finishes, some
products may have (a) required a brand-new \`${dict_table}\` entry (STEP 2c's NO branch) AND
(b) ended up recorded \`qa_confidence: "confident"\` in STEP 2d -- these are the ones worth making
searchable for future sessions. Every other product (re-points, filtered-out, unconfident) is
skipped -- never index an unconfident guess.
  1. Build one JSONL file of every qualifying product from this session, one line each --
     you already have these values from your own STEP 2 writes, no requery needed:
     {"product_id": "<product_id>", "sku_name": "<sku_name>", "sku_type_complete": "<value written to qa_table>", "brand": "<value written to qa_table>"}
     at /tmp/${dataset}_${platform}_${country}_v2_new_entries.jsonl. If there are zero qualifying
     products, skip this step entirely -- do not run the command below with an empty or missing
     file.
  2. Run ONE batch call (never one call per product -- same rationale as STEP 1, model load
     dominates cost, not the embedding itself):
     ${PYTHON_BIN} ${REPO_ROOT}/script/non_niq/non_niq_helper.py index \\
       --input-file /tmp/${dataset}_${platform}_${country}_v2_new_entries.jsonl \\
       --meili-index ${meili_index}
     Run this synchronously and wait for it to finish, same as every other tool call this session.

```

- [ ] **Step 4: Run the test file, confirm it passes**

Run: `bash tests/non_niq/test_non_niq_qa_v2.sh`
Expected: `ALL TESTS PASSED (part 1: SQL builders)` and `ALL TESTS PASSED (part 2: prompt + main)`.

- [ ] **Step 5: Run the full non_niq test suite (both scripts + helper) to confirm no cross-task regressions**

Run: `bash tests/non_niq/test_non_niq_qa_v2.sh && bash tests/non_niq/test_non_niq_qa.sh && python3 tests/non_niq/test_non_niq_helper.py`
Expected: all three pass.

- [ ] **Step 6: Commit**

```bash
git add script/non_niq/non_niq_qa_v2.sh tests/non_niq/test_non_niq_qa_v2.sh
git commit -m "Add batched Meilisearch write-back (STEP 3) to v2's QA prompt"
```
