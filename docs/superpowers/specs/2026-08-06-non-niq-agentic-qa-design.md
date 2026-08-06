# Design: Non-NIQ Agentic QA (Phase 1)

Status: DRAFT (pending user review) | Date: 2026-08-06

## Background

[Epic #1](https://github.com/iethes/product-taxonomy-extraction/issues/1) splits the Non-NIQ agentic labelling work into Phase 0 (POC, closed), Phase 1 ([Agentic QA — issue #2](https://github.com/iethes/product-taxonomy-extraction/issues/2)), Phase 2 (Agentic labelling — not yet opened). This spec is the concrete implementation design for **Phase 1 / issue #2**.

Phase 0's POC (`babycologne`, text-only Tier 1 SQL matching) confirmed the review verdict: text extraction alone can't resolve brand/sku_type in two edge cases — multi-brand SEO stuffing and no-brand-in-name SKUs — both of which only resolve from the product image. The POC's brute keyword scoring also proved a weak retrieval mechanism generally (16% sku_type exact match vs. human QA). This spec replaces it with a real hybrid retrieval layer (Meilisearch) and implements #2's full decision tree on top.

## Scope

Full Phase 1 build, per issue #2: decision tree (relevance → correct/re-point → match-or-create), filter-table writes, two-step taxonomy creation with attribute grounding, `_meta` stamping. Indonesia only. Rollout order (lead-picked, lowest cross-category friction first):

1. Baby Bath & Shampoo (`babybath`)
2. Baby & Kids Lotion (`babycreamlotion`)
3. Baby & Kids Sunscreen (`babysunscreen`)
4. Kid Suplement (`kidsuplement`) — *sic*, matches the actual Sheet spelling
5. Multivitamin (`multivitamin`)
6. Baby Hair Treatment (`babyhairtreatment`) — **shares `babybath`'s dict + QA table**, only its filter table differs; no separate Meilisearch index needed, reuses `babybath_taxonomy_qa`
7. Telon Oil (`telonoil`)
8. Facial Serum (`facialserum`)
9. Moisturizer (`mosturizer`)
10. Body Lotion (`bodylotion`)
11. Formula Milk (`susubayi`)

10 distinct datasets, 10 Meilisearch indexes (babyhairtreatment reuses babybath's).

**Config source:** the [pipeline config Sheet](https://docs.google.com/spreadsheets/d/1faNuuyFlYz4v-MdJO6lOaS_OZr6TZCSaIozRJl5kn3I) — one row per (category, ecommerce_platform). Relevant columns confirmed against a live export: `country`, `category`, `dataset`, `is_active`, `ecommerce_platform`, `table` (source), `product_id_dict_qa`, `product_id_dict`, `dict`, `filter_table`.

**Schema reality check (queried live, 2026-08-06):** only 4 of 11 categories have a populated `product_id_dict` (mapping) table — `susubayi`, `multivitamin`, `telonoil`, `kidsuplement`. The other 7 have `-` (no mapping table configured at all). Decision-tree step 2 ("is the existing mapping correct?") only applies to those 4; the other 7 skip straight to step 3 (match-or-create) for every in-scope row — this is first-pass labelling+QA combined, not correction of prior output.

## Non-goals

- Cross-category federated search. Issue #2 is explicit: irrelevant products are written to the filter table and **dropped** ("do NOT create a taxonomy entry; stop") — never re-routed to a different category's taxonomy. No need to search across categories to find a product's "true home."
- Any change to the existing unrelated Meilisearch indexes on the shared instance (`facialserum_taxonomy`, `multivitamin_taxonomy`, `susubayi_dict_keywords`, etc.) — confirmed these belong to a different project, not touched.
- A human-facing review UI. `human_review = true` is a terminal flag only; where humans actually pick those up is an existing out-of-band process, not built here.
- Reorganizing existing NIQ scripts (`script/niq/`, `script/test/` split) — explicitly deferred, only `script/non_niq/` is in scope now.

## Architecture

### Directory layout

```
script/non_niq/
  non_niq_qa.sh              # main harness — branches headless_taxonomy.sh + targeted_qa_fix.sh patterns
  non_niq_queue_worker.sh    # separate polling loop; same task_queue table as NIQ, own script_type lane
  non_niq_embed.py           # single file, Windmill-deployable (main() entrypoint); embed() also
                              # imported directly by non_niq_qa.sh's python helper for query-time vectors
  non_niq_sheet.py           # config Sheet reader — replaces config/tables.py's hardcoded list for this project
```

Everything else in `script/` stays exactly where it is.

### Execution model

- `non_niq_queue_worker.sh`: new, separate worker loop on Hetzner. Claims rows from the **same** `p4ct2g2urhzcfnz.task_queue` Postgres table the NIQ worker uses, filtered to `script_type = 'non_niq_qa'` — a logically separate lane on shared storage, never claims NIQ rows or vice versa. One row per (category, platform).
- `non_niq_embed.py`'s batch run (dict→Meilisearch sync) is **not** queued through `task_queue` and **not** scheduled — deployed to Windmill purely for convenient manual triggering (click "Run" instead of SSH+run on Hetzner). No cron. Query-time embedding (per QA batch) happens in-process inside `non_niq_qa.sh`'s Python helper by importing `embed()` from the same file — same Hetzner box, no network hop.

### Retrieval engine — Meilisearch hybrid

- **Index naming:** `{dataset}_taxonomy_qa` (new convention, distinct from the unrelated existing indexes).
- **Corpus:** `{dataset}.product_id_dict_qa` rows — **confirmed exemplars**, not raw dict entries. This mirrors the "QA examples (RAG)" pattern the epic says the current Gemini engine already uses (previously-QA'd rows as few-shot examples), reimplemented on Meilisearch.
- **Documents:** `product_id`, `sku_name`, `sku_type_complete`, `brand`.
- **Hybrid search:** vector search on `_vectors.default` (`userProvided` embedder, `multilingual-e5-large` via `sentence-transformers` — already a repo dependency), embedded from `sku_name` only. Keyword search on `sku_name`, `sku_type_complete`, `brand` (`searchableAttributes`).
- **Sync job (`non_niq_embed.py main()`):** reads `product_id_dict_qa` for each active category, filters to **confirmed rows only** — excludes rows where `_meta` marks our own `qa_confidence = 'unconfident'`, so the RAG corpus never feeds the model its own shaky guesses back as ground truth. Full upsert every run (all target tables are under 50k rows — idempotent upsert by `product_id`, no incremental-diff logic needed at this scale). **Manual trigger only** — run on demand from Windmill's UI before a `non_niq_qa.sh` run, no schedule.
- **Query-time:** for each worklist batch, `non_niq_qa.sh`'s Python helper embeds the batch's `sku_name`s in-process, hybrid-searches the category's index, returns top-N candidates as RAG context for the Claude decision call — replacing the POC's brute SQL keyword scoring.

### Decision tree (per issue #2, mapped onto Non-NIQ schema)

```
1. RELEVANT to this category? (multimodal: image + sku_name + item_description/specs)
   NO  → write {product_id, ecommerce_platform, sku_name, reason} to filter_table,
         _meta stamped, do NOT create a taxonomy entry. STOP.
   YES ↓

2. Does product_id_dict exist for this category (Sheet col != '-')?
   NO  → skip to step 3 (no existing mapping to check)
   YES → is the existing mapping CORRECT?
         YES → write SAME values to product_id_dict_qa. Go to step 4 (self-QA still runs).
         NO  → continue to step 3

3. Retrieve top-N candidates (Meilisearch hybrid, previous section) + read full dict row
   for grounding attribute vocabulary. Does a TRUE matching taxonomy record exist?
   YES → write CORRECTED values (re-pointed) to product_id_dict_qa.
   NO  → two-step create in {dataset}_dict:
         Step A: brand + sku_type/sku_type_complete + keywords, _meta='claude_code' stamped here
         Step B: remaining attribute columns, grounded on existing dict rows' vocabulary +
                 formatting (query distinct existing values per column, prefer reuse over invention)
         → write values pointing at the new entry to product_id_dict_qa.

4. Self-QA: explicit follow-up asks the model to state confidence on the decision just made.
   → confident   OR   unconfident
```

### Confidence loop — no new columns, reuse `_meta`

`_meta` on `product_id_dict_qa` is **already JSON** in production (confirmed live) — `{"source": "labeling"}` for machine rows, `{"name","email","role","timestamp","isCorrect"?}` for human QA. No new columns; extend the same shape:

```
confident:                {"source":"claude_code","qa_confidence":"confident","timestamp":...}
unconfident, 1st attempt: {"source":"claude_code","qa_confidence":"unconfident","human_review":false,"timestamp":...}
unconfident, retry:       {"source":"claude_code","qa_confidence":"unconfident","human_review":true,"timestamp":...}  -- terminal
```

Retry cap = 1, expressed with no separate counter: "is this the row's first agent-written QA row, or does one already exist?" is the only state needed.
- First attempt (row has no QA-table entry yet, or `qa_status = 'Not Reviewed'`): full multimodal pass → self-QA. Unconfident → written with `human_review:false`, re-enters the queue once.
- Retry attempt (row already has a `qa_confidence:'unconfident', human_review:false` QA-table row): full multimodal pass again → self-QA again. Still unconfident → `human_review:true`, terminal, drops out of the agent's queue permanently.

### Worklist / priority queue

Scope exactly as #2 specifies: latest available month, top 90% cumulative GMV per `ecommerce_platform` (source table's own scoping query — GMV lives there, not on the QA table, so this is unaffected by `product_id_dict_qa`'s inconsistent legacy `gmv`/`daily_gmv`/absent columns across categories).

Priority order within scope:
```
priority 0 (highest): qa_status = 'Not Reviewed' AND no product_id_dict_qa row yet for this product_id
priority 1:            product_id_dict_qa row exists, JSON_VALUE(_meta,'$.qa_confidence')='unconfident'
                        AND JSON_VALUE(_meta,'$.human_review') != 'true'
(excluded entirely):   JSON_VALUE(_meta,'$.human_review') = 'true'  -- terminal, needs a human
ORDER BY priority ASC, gmv_monthly DESC
```

### Filter table

One target category (`babysunscreen`) lists two filter tables: `babysunscreen.filter_babysunscreen;sunscreen.filter_sunscreen_hanasui`. Investigated live rather than guessed — these are **not** duplicates or a platform split (checked: both tables mix all platforms). `sunscreen` is a **separate, fully active category dataset** (it has its own complete pipeline — `0_pipeline` through `9_`, same as `babysunscreen`) for general/adult Sunscreen, distinct from Baby & Kids Sunscreen. `filter_sunscreen_hanasui` is that other category's own filter table, cross-referenced here because Hanasui-brand products were apparently getting mislabeled into `babysunscreen` and someone already filters them under the general Sunscreen category instead of duplicating the work.

**Rule:** write new agent-flagged irrelevant products only to the table in the row's **own dataset** (`{dataset}.filter_*` — the first-listed one is always this). Any additional cross-dataset table is **read-only reference**: check it too before flagging, so a product someone already filtered under a different category's effort doesn't get redundantly (or inconsistently) re-flagged here — but never write there. This generalizes past `babysunscreen` to any category that lists a second, foreign-dataset filter table.

## Success criteria (from issue #2, unchanged)

- QA agreement rate — agent vs. existing human QA
- Disagreement triage — agent wrong vs. human wrong, both counted honestly
- Filter precision/recall — false positives (wrongly filtered) and false negatives (junk that got through) both tracked
- Taxonomy-creation quality — genuinely new (not a retrieval miss) and fully populated across all dict columns, not just identity

## Definition of done

- [ ] `script/non_niq/` scaffolded: `non_niq_qa.sh`, `non_niq_queue_worker.sh`, `non_niq_embed.py`, `non_niq_sheet.py`
- [ ] `non_niq_embed.py` deployed to Windmill, scheduled sync populates all 10 `{dataset}_taxonomy_qa` indexes
- [ ] `non_niq_queue_worker.sh` claiming `script_type='non_niq_qa'` rows from shared `task_queue`, running on Hetzner
- [ ] Decision tree implemented in order: relevance → correctness (where applicable) → match-or-create
- [ ] Irrelevant products written to filter table with reason, never given a taxonomy entry
- [ ] Two-step create (identity → grounded attributes) implemented
- [ ] Confidence loop: 1 retry cap, `_meta`-encoded state, terminal `human_review` flag
- [ ] Mapping table (`product_id_dict`) never modified — corrections only land in `product_id_dict_qa`
- [ ] Results compared against existing human QA for the first rollout category (`babybath`); agreement rate, disagreement triage, filter precision/recall reported before continuing down the rollout list

## Config Sheet access

`non_niq_sheet.py` reads the **published CSV export**, read-only — it's the only thing this project ever needs from the Sheet. The Sheets API (write access) is not used: nothing in this design writes back to the config Sheet itself (filter-table writes go to the BQ filter table, not the Sheet). Revisit only if a future requirement needs the harness to write into the Sheet.
