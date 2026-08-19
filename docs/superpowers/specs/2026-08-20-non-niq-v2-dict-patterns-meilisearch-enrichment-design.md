# Design: Non-NIQ QA v2 — Dict-Column Patterns, Meilisearch Write-Back, Shopee Enrichment

Status: APPROVED | Date: 2026-08-20

## Background

Three additions to `script/non_niq/non_niq_qa_v2.sh` (v2 only — v1's `non_niq_qa.sh` is not in scope for this work) + `script/non_niq/non_niq_helper.py`, built per `docs/superpowers/specs/2026-08-06-non-niq-agentic-qa-design.md` (shared decision tree/confidence loop) and reusing prior art from `docs/superpowers/specs/2026-08-13-non-niq-enrichment-discord-summary-design.md` (Improvement 1 there is ported wholesale — see Improvement 3 below).

1. When STEP 2c mints a new `{dataset}_dict` row, generated columns (e.g. `sku_type_complete`, `keywords`) must follow a real per-category composition pattern instead of ad-hoc free-text, and every column except the typo column must end up non-null.
2. When that new dict row corresponds to a product QA'd confidently this session, push it into Meilisearch so it's searchable by future sessions — currently nothing in this repo writes to Meilisearch at all.
3. Feed v2's worklist the same Shopee `item_description`/`product_attributes_attrs` signal v1 already has.

All three touch `non_niq_qa_v2.sh`'s `worklist_query()`/`build_qa_prompt()`/`main()` and, for #2, add a new subcommand to `non_niq_helper.py`.

## Improvement 1 — Self-bootstrapping per-category dict-column patterns

**Problem:** `build_qa_prompt()`'s STEP 2c Step A/B (`non_niq_qa_v2.sh:260-272`) tells Claude to insert `brand + ${dict_identity_col} + keywords` and then "populate the remaining attribute columns... GROUNDED on existing dict rows." There is no rule for how generated columns (`sku_type_complete`, `keywords`) are actually composed from other columns, and no NOT NULL enforcement. This varies per category — confirmed live no such config exists anywhere in the repo today (no Sheet column, no JSON/YAML, nothing hardcoded) — and categories can't be enumerated in advance (e.g. a category like `blender` doesn't exist yet in this repo but will follow its own pattern once it does).

**Mechanism — self-bootstrapping JSON, one file per dataset:**

- New path: `script/non_niq/dict_patterns/<dataset>.json`. One file per dataset (not one shared config) so two datasets running concurrently never race on the same file — a real risk given this pipeline's history of concurrent-session bugs (`project_non_niq_qa_concurrent_session_launch_gap.md`).
- Schema:
  ```json
  {
    "sku_type_complete": {"sources": ["sub_brand", "variant", "total_size"], "separator": " "},
    "keywords": {"sources": ["sku_type_complete", "keywords_typo"], "separator": " "}
  }
  ```
  Each key is a generated dict-table column; `sources` is the ordered list of other dict-table columns it's composed from; `separator` is how they're joined. Composition skips any source that's null/empty and joins only the remaining non-empty parts — this is how a generated column (e.g. `keywords`) can validly source from the nullable typo column without ever producing a literal `"null"` or a dangling separator when no typo variant exists for that entry. The generated column itself is still subject to the universal NOT NULL rule below (it just won't include a typo segment when there isn't one).
- STEP 2c Step A, extended: before creating a new dict row, Read `script/non_niq/dict_patterns/${dataset}.json`.
  - **Exists** → follow it mechanically: populate every listed `sources` column first (grounded via `SELECT DISTINCT <column> FROM ${dict_table}`, same technique Step B already uses), then compose the generated columns per the file's `separator` rule.
  - **Missing** → infer the pattern by sampling ~10-20 existing rows from `${dict_table}` (same grounding technique), then Write the inferred pattern to this path in the schema above so the next session for this dataset reads it instead of re-inferring.
- **NOT NULL rule (universal, not config-driven):** every dict-table column must be non-null on the new row except `${dict_typo_col}` (already resolved dynamically via `non_niq_helper.py columns`, e.g. `keywords_typo`/`keyword_typo`). After the insert, verify with an explicit `SELECT` — never trust `bq`'s "affected rows" report (`feedback_bq_parameter_double_colon_bug.md`) — for any NULL in a non-typo column on the just-inserted row, and fix any found (grounded via `SELECT DISTINCT`, same as today) before moving to the next product.

## Improvement 2 — Meilisearch write-back

**Problem:** confirmed live, nothing in this repo writes to Meilisearch. `non_niq_helper.py:7-9` states explicitly it "only ever READS from Meilisearch (the `retrieve` command), never writes to it" — indexing is a separate, not-yet-deployed Windmill script (`docs/windmill-non-niq-embed-prompt.md`, `non_niq_embed.py`) with a `mode="sync"` that does a **manual-trigger, whole-corpus batch** re-embed per dataset — no scheduling, someone has to click "Run" in the Windmill UI. A newly-created taxonomy entry is invisible to future QA sessions' Meilisearch candidate retrieval until someone happens to do that.

**Decision (explicit user choice over two other options — trigger the Windmill batch job remotely, or no new mechanism at all):** live single-doc/small-batch upsert from the harness itself, reusing the SentenceTransformer model `non_niq_helper.py` already loads for `retrieve`, in the exact doc shape/index conventions the Windmill script uses so both write into a compatible index.

**New `non_niq_helper.py` subcommand**, mirroring `retrieve`'s existing CLI shape:
```
non_niq_helper.py index --input-file DOCS.jsonl --meili-index IDX [--meili-url URL]
```
- Input JSONL, one line per product: `{"product_id","sku_name","sku_type_complete","brand"}`.
- Internally: `ensure_index()` (create + configure the index if missing — ported from `docs/windmill-non-niq-embed-prompt.md`'s version: `searchableAttributes: ["sku_name","sku_type_complete","brand"]`, `embedders: {"default": {"source":"userProvided","dimensions": EMBED_DIM}}`), E5 **passage**-formatted embedding (`_format_passage_text` — new in `non_niq_helper.py`, mirrors the existing `_format_query_text`; `retrieve` embeds queries, `index` embeds corpus, E5 is asymmetric so the prefix must differ), batched `POST /indexes/{idx}/documents` at the existing `BATCH_SIZE`, doc shape `{"product_id": str, "sku_name", "sku_type_complete", "brand", "_vectors": {"default": [...]}}` — identical to `sync_category`'s doc shape in the Windmill script.
- Update the stale `non_niq_helper.py:7-9` comment to reflect that indexing now has two paths: this harness's incremental write-back, and Windmill's independent manual whole-corpus resync (both remain valid; they don't conflict — Meilisearch upserts are idempotent by `product_id`, the declared `primaryKey`).

**Trigger condition** (matches the literal ask — "if you create new sku_type_complete... insert into meilisearch too", not every match): a product qualifies only if, this session, (a) STEP 2c's NO branch created a brand-new dict entry for it, AND (b) STEP 2d recorded it `qa_confidence: confident`. This mirrors the Windmill sync's own `is_confirmed()` gate — never index an unconfident guess.

**New STEP 3 in `build_qa_prompt()`**, after the STEP 2 loop finishes: batch, not per-product. Rationale — model load dominates cost, not the embedding call itself, and STEP 1 already established the "batch, never per-product tool calls" pattern for exactly this reason. Claude derives one JSONL of every qualifying product from this session (`product_id`, `sku_name`, `sku_type_complete`, `brand` — values it already has from its own STEP 2 writes, no requery needed) and makes one `index` call.

## Improvement 3 — Shopee description/spec enrichment (ported from v1)

Straight port of v1's already-built, already-debugged enrichment (`non_niq_qa.sh:63-99`, from `docs/superpowers/specs/2026-08-13-non-niq-enrichment-discord-summary-design.md` Improvement 1) — no new design, no re-debugging.

- Port the `enrichment_cte_and_join`/`enrichment_join`/`enrichment_select` block verbatim into v2's `worklist_query()`, plugged into v2's `scoped` CTE (v2 has no GMV-percentile step, but the join is orthogonal to that — it attaches by `product_id` regardless of how the row got scoped). Same Shopee-only gate, same `QUALIFY ROW_NUMBER() OVER (PARTITION BY item_itemid ORDER BY timestamp DESC) = 1` dedup (confirmed live: ~108 history rows per item on the `0_pipeline_*` table), same `COALESCE`-based Python-repr-vs-JSON fallback for `product_attributes_attrs` (~94% of populated rows are Python `repr()`, not valid JSON), same `STRING_AGG` projection to a compact `name=value; name=value` string.
- `main()`: thread `enrichment_table=$(echo "$category_json" | jq -r '."0"')` through to `worklist_query`, same Sheet field v1 already reads via `ROW_FIELDS`.
- `build_qa_prompt()`: same STEP 0 schema-line addition (`item_description`, `product_attributes_attrs` now present on each worklist row) and the same STEP 2a instruction extension (use them as additional signal alongside the image and `sku_name`, never as a substitute for looking at the image; NULL on non-Shopee platforms).
- v2 already has both prerequisites v1 had to learn the hard way this enrichment needs: `--max_rows=1000000` on the materializing `bq query` (`non_niq_qa_v2.sh:492`) and file-materialization instead of handing Claude raw SQL to re-run (`non_niq_qa_v2.sh:487-497`) — so the "18-320x worklist size blowup, truncated runs silently marked done" failure mode v1 hit does not need rediscovering.

## Testing

- `tests/non_niq/test_non_niq_qa_v2.sh`:
  - `worklist_query()` includes the enrichment CTE/join/dedup when platform is Shopee and `enrichment_table` is set, and selects `NULL AS item_description, NULL AS product_attributes_attrs` otherwise (mirrors v1's existing enrichment tests).
  - `build_qa_prompt()`'s prompt text contains: the `dict_patterns/${dataset}.json` path and read/infer/write-back instruction, the NOT NULL verification rule naming `${dict_typo_col}` as the sole exception, the STEP 3 batch-index instruction and its trigger condition (new dict entry AND confident), and the item_description/product_attributes_attrs STEP 0/2a additions.
  - `main()` wiring: `enrichment_table` resolved from `."0"` and threaded into `worklist_query`.
- `non_niq_helper.py` tests: new coverage for the `index` subcommand — doc shape (`product_id` as string, `_vectors.default` present and correctly dimensioned), `ensure_index()` idempotency (no-op if the index already exists with the right settings), batching at `BATCH_SIZE`, and `_format_passage_text`'s `"passage: "` prefix vs `_format_query_text`'s `"query: "` prefix. Mock the Meilisearch HTTP calls (same approach as any existing `retrieve`/`_meili_request` tests).
- Manual/live verification (not automatable in this test suite): run v2 against a real never-before-configured dataset once to confirm the pattern-inference-and-write-back path actually produces a sane `dict_patterns/<dataset>.json`, and confirm one `index` call against the real Meilisearch instance is visible via `curl http://34.124.146.29:7700/indexes/{idx}/documents/{product_id}`.

## Non-goals

- v1 (`non_niq_qa.sh`) is unchanged by this work.
- No changes to the Windmill `non_niq_embed.py` script or its manual-trigger batch sync — it continues to exist independently as a periodic whole-corpus resync; this design only adds an incremental path that the harness itself drives.
- No Sheet schema changes — `dict_patterns/*.json` lives in the repo, not the config Sheet.
