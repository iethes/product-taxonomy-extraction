# Design: Non-NIQ QA — Description/Specs Enrichment, Discord Notification, Result Summary

Status: APPROVED | Date: 2026-08-13

## Background

Three small, mostly-independent improvements to the Non-NIQ QA harness (`script/non_niq/non_niq_qa.sh` + `script/non_niq/non_niq_helper.py`, built per `docs/superpowers/specs/2026-08-06-non-niq-agentic-qa-design.md`):

1. Feed Claude's match/create decision (STEP 2 of the prompt) an additional real signal — Shopee's `item_description`/`product_attributes_attrs` — instead of just `sku_name` + image.
2. Post a human-auditable Discord message every time the harness mints a genuinely new taxonomy entry.
3. Make the final session output actually readable (cost, per-model cost, turn count) instead of a raw JSON dump.

All three touch the same two files and are small enough for one implementation plan.

## Improvement 1 — Description/specs enrichment

**Confirmed live, not assumed:** the config Sheet's `"0"` column holds a per-(dataset, platform) enrichment table name (e.g. `0_pipeline_babybath_shopee_id`). Checked real schemas:
- `babybath.0_pipeline_babybath_shopee_id` (Shopee) **has** `item_description` and `product_attributes_attrs`.
- `bbcream.0_pipeline_bbcream_blibli_id` (Blibli) has neither — entirely different, platform-specific scrape columns.

So this is **Shopee-only by data availability**, not a scoping choice. All active ID Shopee rows currently have a non-empty `"0"` value (checked).

**Mechanism — plain SQL, no Python involved** (per explicit decision: this is a BigQuery `LEFT JOIN` by `product_id`, nothing model/embedding-related, so it belongs in `worklist_query()` directly):

```sql
LEFT JOIN `{PROJECT}.{dataset}.{enrichment_table}` e
  ON CAST(e.item_itemid AS STRING) = s.product_id   -- only present when platform = Shopee
```

- `dataset` is derived from `${source_table%%.*}` (bash parameter expansion) — no new function parameter needed, `source_table` is already `{dataset}.master_..._dev`.
- `enrichment_table` is a **new parameter** to `worklist_query()`, sourced from the Sheet's `"0"` column — added to `non_niq_helper.py`'s `ROW_FIELDS` (kept as the literal key `"0"`, not renamed, to avoid an unnecessary translation layer; `main()` reads it via `jq -r '."0"'`).
- The join is conditional in bash: only built when `platform_titlecase == "Shopee"` and `enrichment_table` is non-empty and not `"-"`. Otherwise the query selects `NULL AS item_description, NULL AS product_attributes_attrs` directly — same output shape either way, so the prompt text doesn't need a platform-conditional branch.
- Both columns flow through the whole CTE chain (`base` → `with_cumulative` → `scoped` → `prioritized`, added explicitly to `prioritized`'s SELECT list alongside `ecommerce_platform`) into the worklist Claude reads in STEP 0.
- STEP 2a's relevance/brand/type judgment instruction gets one added line: use `item_description`/`product_attributes_attrs` as additional signal when present (Shopee), alongside the image and `sku_name` — never as a substitute for actually looking at the image.

## Improvement 2 — Discord notification on taxonomy creation

**Trigger:** immediately after STEP 2c's two-step create (Step A + Step B) finishes writing a new `{dataset}_dict` row — before the QA-table pointer write.

**Who sends it:** Python, not Claude — reads the row back from BigQuery after Claude writes it, so the message reflects what's actually persisted, not Claude's self-report.

**New `non_niq_helper.py` command:**
```
non_niq_helper.py notify-discord --dict-table PROJECT.dataset.dict_table \
  --brand "<brand>" --identity-col sku_type --identity-value "<value>" --dataset <dataset>
```
- `identity_col` is validated against the known candidate set (`sku_type`, `sku_type_complete`) before being interpolated as a column identifier in SQL — it can only ever come from this project's own resolved config, but it's cheap defensive discipline for anything landing in a query string.
- Query: `SELECT * FROM {dict_table} WHERE brand = @brand AND {identity_col} = @identity_value LIMIT 1` (brand/value bound as query parameters; only the column name itself is interpolated, after validation).
- Formats every **non-null** column from the row into an aligned monospace table inside a triple-backtick code fence (Discord doesn't render pipe-table markdown as an actual table — a code block is what's actually legible), preceded by a `**AI QA**` header line and the dataset name for context.
- **Discord's hard 2000-character content limit** is a real platform constraint independent of "retain full information": individual very-long cell values (e.g. free-text `ingredients`) get truncated with `...` rather than dropping whole rows or columns, so the row's full *shape* stays visible even if one field's text is shortened.
- POSTs `{"content": message}` to `os.environ["DISCORD_WEBHOOK_URL"]`.
- **Non-fatal by construction:** catches its own request errors, prints a warning to stderr, and always exits 0 — this guarantees a Discord outage can never block or fail a QA session, without depending on the prompt telling Claude to ignore a failure it might not reliably ignore.

**Secret handling:** `DISCORD_WEBHOOK_URL` is a bearer credential (pasted in chat during this design session) — never hardcoded into a committed file. Added to `.env.example` as a blank placeholder; the real value goes in the user's local, gitignored `.env`. `non_niq_qa.sh` currently doesn't source `load_env.sh` at all (only the queue worker does) — it starts doing so near the top, so `DISCORD_WEBHOOK_URL` (and anything else in `.env`) is available whether the script is run directly or via the queue worker. Sourcing it twice (queue worker already did it before invoking this script) is harmless — `load_env.sh` is a plain `set -a; source .env; set +a`.

## Improvement 3 — Human-readable final session result

Currently `main()` just does `echo "$claude_output"` — the raw `claude -p --output-format json` envelope. `decide_queue_signal()` already has to dig into it (extract `.result`, fall back to regex-extracting a bare `{...}` blob if Claude wrapped it in prose) — that extraction logic is pulled into a new shared function, `extract_result_json()`, so it's written once, and `decide_queue_signal()` is refactored to call it instead of duplicating the try/fallback logic.

**Real envelope fields, confirmed live** (`claude -p --output-format json` on a trivial call):
- `total_cost_usd` — top-level float.
- `modelUsage` — object keyed by model name (e.g. `"claude-sonnet-5"`), each with `costUSD`, `inputTokens`, `outputTokens`, `cacheReadInputTokens`, `cacheCreationInputTokens`. Iterated generically (`jq`'s `to_entries[]`), not hardcoded to one model name, so it stays correct if the model changes or (unusually) more than one shows usage.
- `num_turns`, `duration_ms` — also surfaced, both free (already in the envelope) and useful (turns used vs. the `max_turns` budget passed in).

**New function**, `format_result_summary(claude_output)`:
- Calls `extract_result_json()` for the inner status object (`status`, `rows_qa_confirmed`, `rows_qa_unconfident`, `rows_filtered`, `rows_created_in_dict`, `findings`, `blockers`).
- Reads `total_cost_usd`, `modelUsage`, `num_turns`, `duration_ms` directly from the outer `$claude_output`.
- Prints a labeled block (status line, counts line, turns/duration/cost line, per-model cost lines, findings in full, blockers in full or `(none)`).

**Printed alongside the raw JSON, not replacing it** — `non_niq_queue_worker.sh`'s `persist_final_status()` stores whatever `non_niq_qa.sh` prints as `last_result` in Postgres; keeping the raw envelope preserves full machine-parseable detail (including metadata the summary doesn't surface) while the summary makes a log/terminal actually readable at a glance. Nothing existing is removed, only added.

## Definition of done

- [ ] `non_niq_helper.py`'s `ROW_FIELDS` includes `"0"`; `parse_categories` output carries it through unchanged.
- [ ] `worklist_query()` takes an `enrichment_table` parameter, conditionally joins only for Shopee, and always outputs `item_description`/`product_attributes_attrs` (NULL when not applicable) through to the final SELECT.
- [ ] STEP 2a's prompt instruction mentions using description/specs as additional signal when present.
- [ ] `non_niq_helper.py` has a `notify-discord` command: reads the row back from BQ, formats a code-fenced markdown table with an `**AI QA**` header, truncates long cell values (not whole rows/columns) to respect Discord's 2000-char limit, posts to `DISCORD_WEBHOOK_URL`, never exits non-zero.
- [ ] `.env.example` has a blank `DISCORD_WEBHOOK_URL=` line; `non_niq_qa.sh` sources `load_env.sh`.
- [ ] STEP 2c's "mint new entry" branch calls `notify-discord` after Step B, before the QA-table write.
- [ ] `extract_result_json()` exists and is used by both `decide_queue_signal()` and the new `format_result_summary()` — no duplicated extraction logic.
- [ ] `format_result_summary()` surfaces status/counts/findings/blockers (from the inner result) and turns/duration/total cost/per-model cost (from the outer envelope), printed after (not instead of) the raw `claude_output` echo.
