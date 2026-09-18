# Design: Non-NIQ Python Decision Driver

**Status:** Approved design; awaiting spec review  
**Date:** 2026-09-17

## Goal

Replace the agent-operated shell workflow in `script/non_niq/non_niq_qa_v2.sh` with an opt-in Python v3 driver that keeps deterministic work in Python and delegates only multimodal taxonomy judgment to Codex or OMP.

The design optimizes agent-token use without weakening the existing QA invariants:

- current-title stakeholder worklist selection;
- insert-only QA confidence/retry semantics;
- dictionary natural-identity safety;
- DML-only writes;
- Meilisearch and Sheet synchronization;
- filter-table terminal exclusions.

## Scope and non-goals

### In scope

- New `script/non_niq/non_niq_qa_v3.py` entry point.
- Codex and OMP decision-only adapters.
- Python-owned BigQuery, image preparation, Meilisearch, Sheets, validation, and queue signals.
- Attempt-level replay safety and a durable BigQuery outbox.
- One-image-per-product download policy.
- Strict Sheet append results for the v3 outbox path.
- Opt-in rollout through existing `NON_NIQ_QA_SCRIPT` selection.

### Out of scope

- Replacing `non_niq_qa_v2.sh`.
- Changing `queue_worker.sh` or its task encoding.
- Giving agents write, operational-network, BigQuery, Meilisearch, or Sheets authority.
- Broad changes to legacy `non_niq_qa.sh` or unrelated NIQ flows.
- Adding a human review UI.

`non_niq_qa_v2.sh` remains the rollback path. Its existing non-fatal Sheet append behavior remains unchanged.

## Architecture

`non_niq_qa_v3.py` is the sole production orchestrator for v3. It reuses appropriate functions from `non_niq_helper.py` rather than moving working config, embedding, Meilisearch, or Sheet code merely to change language.

```text
preflight
  -> recover durable outbox
  -> materialize worklist
  -> batch retrieval and candidate resolution
  -> prepare ordered product chunks
  -> attach one local image per product to selected harness
  -> parse and validate decision-only response
  -> transactional BigQuery mutation plus outbox events
  -> read-back verification
  -> drain outbox
  -> queue signal
```

The driver is explicit rather than configurable-by-convention. It has two named adapter paths, `codex` and `omp`; it has no generic arbitrary-agent-command mode.

## Strict run flow

### 1. Preflight

Before materializing a worklist or invoking an agent, the driver resolves and validates:

- active config-Sheet row;
- source, QA, dictionary, and own-dataset filter tables;
- QA primary key and dictionary identity/typo columns;
- dictionary `_meta` capability;
- platform canonicalization, including `Tokopedia | Shop` to `Tokopedia`;
- latest source month, merchant force-include IDs, and optional category shard;
- required dictionary generated-column pattern and live writable schema;
- selected harness adapter and native image capability;
- durable outbox table availability;
- optional `taxonomy_url`; absence disables only the Sheet side effect, matching v2.

A missing or invalid prerequisite emits `FAILED` before agent work or production mutation.

### 2. Durable outbox recovery

The driver drains pending outbox events for its dataset/platform/country scope before normal planning. It groups pending events by target:

- one batch Meilisearch upsert per index;
- one strict Sheet append batch per taxonomy Sheet.

An event becomes complete only after its side effect reports success or an idempotent already-present result. A remaining failed or pending event emits `FAILED`, never `DONE`.

### 3. Worklist and retrieval

The v3 worklist preserves v2 semantics:

- source is `master_table_prod`;
- latest month is platform-scoped;
- confirmed filter-table products are removed before calculating the cumulative-GMV rank;
- normal scope is top 90% cumulative GMV plus configured client/competitor merchants;
- current title QA matching uses product ID, canonical platform, and whitespace-normalized `sku_name`;
- retry state aggregates the entire insert-only QA history with `JSON_VALUE(SAFE.PARSE_JSON(_meta), ...)`;
- mapping tables are read-only;
- `qa_status` is never written.

Python batch-embeds titles and retrieves candidate documents. It resolves each candidate to an immutable driver-owned `candidate_ref`, mapped to an exact dictionary row and fingerprint. Agents may select only candidate references included in that product's frozen packet.

### 4. One-image preparation

Every platform downloads at most one image per product. The raw source value is retained as `image_raw` for audit.

#### Shopee

For canonical platform `Shopee` only:

1. Strip source quote noise.
2. Extract the first complete HTTPS `*.img.susercontent.com/file/...` URL.
3. Download that one URL.
4. Do not reconstruct or download later bare image IDs.

This repairs source values such as a quote embedded after `/file/`, and it selects only the first URL from a multi-image raw field.

#### Other platforms

For Tokopedia and every other platform:

1. Find the first already-complete, parseable HTTPS URL.
2. Download that exact URL unchanged.
3. Do not apply Shopee quote/token repair, infer an image ID, rewrite a host, or concatenate tokens.

The downloaded response must be HTTP-successful and decode as an image. HTML/error bodies are unreadable images. No readable image sets `image_status` to `unavailable`.

### 5. Native multimodal adapter gate

A local path written into prompt text is not visual input. The driver uses the harness-native attachment mechanism:

- Codex: `codex exec --image <file>`.
- OMP: `omp @<file> ...`.

Before the selected adapter receives any production product, v3 performs a no-write vision sentinel probe. It creates two images with different random labels using neutral filenames and the same prompt. The label values appear nowhere except visibly in their respective images. The harness must return the exact visible label for both probes.

- Codex uses `--output-schema` for the probe and production decision response.
- OMP uses `--print --mode json --no-tools --no-session`; its adapter extracts the final response and validates it against the same local schema.

A failed probe, unavailable attachment capability, invalid output, or wrong label emits `FAILED` before the worklist is processed.

#### Chunk attachment manifest

For each readable product image, the driver creates an immutable manifest entry:

```json
{
  "product_id": "...",
  "attachment_index": 1,
  "attachment_filename": "attachment-0001.jpg",
  "sha256": "...",
  "local_path": "..."
}
```

`attachment_index` is the one-based position in the frozen chunk manifest. The driver builds Codex `--image` flags or OMP `@file` arguments in ascending `attachment_index` order, then gives each product packet its own index and filename. No-image packets have no attachment index.

The response schema requires image-derived evidence to name an `attachment_index`. The driver accepts it only when it equals that decision's packet index. A product can never use another product's attachment as evidence.

For production chunks, exactly one downloaded local image per product is attached through this manifest. Textual local paths are audit metadata only.

## Decision protocol

The driver supplies each product packet with `work_item_id`, `input_fingerprint`, source signals, image state, immutable attachment metadata, prior mapping, candidate summaries/references, and writable dictionary attribute rules.

The selected agent must return exactly one decision per supplied product. It echoes `work_item_id` and `input_fingerprint`; mismatches are rejected.

All variants share:

```json
{
  "product_id": "...",
  "work_item_id": "...",
  "input_fingerprint": "...",
  "kind": "filter | map_existing | create_dict | defer",
  "confidence": "confident | unconfident",
  "evidence": [
    {"source": "image", "attachment_index": 1, "claim": "Brand and size are visible"}
  ]
}
```

Each evidence item has `source`, `claim`, and—only when `source` is `image`—an `attachment_index`. For a readable image, every non-defer decision requires an image evidence item whose index exactly matches that packet. An unavailable-image `map_existing` or `create_dict` can contain non-image evidence only and must be unconfident.

The JSON schema uses a discriminated union with `additionalProperties: false`. Cross-verdict fields are rejected.

### `filter`

```json
{
  "kind": "filter",
  "reason": "Out of scope: facial sunscreen, not baby sunscreen",
  "confidence": "confident"
}
```

A filter requires a reason, `confidence: "confident"`, a readable attached image, and an image-evidence index matching its packet. It cannot include candidate, mapping, or dictionary fields. It is the only terminal filter-table exclusion path.

### `map_existing`

```json
{
  "kind": "map_existing",
  "candidate_ref": "dict:17",
  "confidence": "confident"
}
```

A map requires a packet-provided `candidate_ref`. It cannot include free-form `brand` or `sku_type_complete`. The driver resolves and revalidates the selected exact dictionary row, then derives the QA values itself. When an image is readable, its evidence must reference this product's attachment index.

### `create_dict`

```json
{
  "kind": "create_dict",
  "attributes": {
    "brand": "Example",
    "product_type": "Baby Shampoo",
    "size": "200 ml"
  },
  "confidence": "confident"
}
```

A creation can include only live writable, non-generated dictionary attributes. The driver rejects unsupported columns, invented generated fields, missing required sources, and invalid categorical vocabulary. It generates identity/composite values from the approved per-dataset pattern. When an image is readable, its evidence must reference this product's attachment index.

### `defer`

```json
{
  "kind": "defer",
  "reason": "Image unavailable; relevance cannot be determined safely",
  "confidence": "unconfident"
}
```

A defer requires a reason and has no candidate, mapping, or dictionary fields. It writes nothing and is non-terminal.

When no image is readable, `map_existing` and `create_dict` are permitted only with `unconfident` confidence. If relevance itself cannot be established safely, the agent must return `defer`, never `filter`.

## Attempt and replay model

### Stable IDs

The driver derives:

- `work_item_id`: dataset, canonical platform, country, product ID, and normalized current title;
- `input_fingerprint`: canonical frozen product packet inputs;
- `attempt_id`: stable identity for one logical attempt;
- `decision_id`: hash of `attempt_id` and the canonical validated decision;
- `run_id`: execution UUID for audit only.

Logical attempts are:

| Kind | Trigger | Generation input |
|---|---|---|
| `initial` | No matching current-title QA row | `work_item_id + initial` |
| `retry` | Existing pending agent-unconfident state | `work_item_id + retry-1` |
| `listing_change` | Monthly reverify detects source title/category change | `work_item_id + month + normalized prior/current title/category` |

The planner excludes an attempt only after recovery handles its required durable side effects. A new retry or listing-change generation has a different attempt ID and may insert another QA row for the same product/title.

### Transactional DML

Each valid chunk uses one BigQuery transaction.

- Filter insert: conditional product-level filter-table insert, matching current v2 terminal filter semantics.
- Dictionary create: conditional natural-identity insert using `brand + resolved dictionary identity`; an existing identity with conflicting authored attributes aborts the chunk.
- QA insert: conditional only on `product ID + canonical platform + _meta.attempt_id`, never on title alone.
- Outbox insert: insert all needed durable side-effect events as pending in the same transaction.

Where a table has `_meta`, driver-generated JSON includes valid source/timestamp metadata plus `run_id`, `attempt_id`, `attempt_kind`, and `decision_id`. QA rows also include the existing confidence fields. On an unconfident retry, the driver derives `human_review: true`; agents do not control it.

Any transaction failure rolls back dictionary, QA, filter, and outbox state together. Transient DML retries reuse the already-validated decision batch; they never need a second agent call.

After commit, the driver reads back every intended dictionary, QA, and filter mutation. Local records are useful diagnostics, but recovery authority is BigQuery only.

## Durable post-commit outbox

`magpie_reference.non_niq_qa_outbox` holds every post-commit side effect. Its schema is:

| Column | Type | Meaning |
|---|---|---|
| `event_id` | STRING | Stable hash of decision ID and event type; conditional-insert dedupe key. |
| `attempt_id`, `decision_id` | STRING | Links the event to its immutable decision. |
| `dataset`, `platform`, `country` | STRING | Recovery scope. |
| `event_type` | STRING | `meili_index` or `sheet_append`. |
| `payload` | STRING | Serialized JSON of driver-derived identity and target details. |
| `status` | STRING | `pending` or `complete`. |
| `attempts` | INT64 | Failed-delivery count. |
| `last_error` | STRING | Most recent delivery failure, or NULL. |
| `created_at`, `completed_at` | TIMESTAMP | Lifecycle timestamps; `completed_at` is NULL while pending. |

The transaction conditionally inserts by `event_id`; BigQuery does not supply an enforced unique constraint for this table.

A newly created dictionary identity gets:

- one `meili_index` event only when its final QA confidence is confident;
- one `sheet_append` event only when the active config provides a `taxonomy_url`.

When no taxonomy URL is configured, v3 logs the skipped Sheet side effect and creates no Sheet event, matching v2. If a Sheet event already exists but its configured target later disappears, strict delivery fails and leaves that event pending.

Re-points, filters, and deferrals enqueue no event.

Outbox actions are idempotent. A crash after an external call but before marking its event complete retries the same action safely. The driver reports `FAILED` while an event is pending/failed rather than silently reporting completed work.

## Strict Sheet append path

The existing `append_sheet_new_entries()` remains unchanged because v2 intentionally catches all errors and returns zero.

V3 uses a distinct strict helper that returns an outcome for each outbox identity:

- `appended`: Sheets append succeeded;
- `already_present`: exact `(brand, identity column, identity value)` already exists in the target Sheet;
- `failed`: missing configuration, header mismatch, absent authoritative dict row, BigQuery failure, or Sheets API failure.

Only `appended` and `already_present` mark a Sheet outbox event complete. A failure remains pending with its error detail.

## Errors and queue signals

| Condition | Signal | Mutation behavior |
|---|---|---|
| No worklist and no pending outbox event | `NOTHING_TO_DO` | None |
| All work committed, read back, and outbox events complete | `DONE` | Complete |
| Config/schema/adapter/decision/DML/outbox failure | `FAILED` | No unsafe further mutation |
| Any `defer` after all other safe rows are processed | `BLOCKED` | Deferred rows have no writes |

V3 has no `partial -> DONE` path. Earlier successfully committed chunks remain replay-safe when a later chunk fails. A defer never becomes a terminal filter entry.

## Rollout

1. Add v3 without editing v2 or `queue_worker.sh`.
2. Select it via the existing `NON_NIQ_QA_SCRIPT` environment variable.
3. Run a small real-worklist dry run: packet preparation and adapter decision validation, with no writes.
4. Run one small Codex production chunk; verify QA/dictionary/filter/outbox read-back and complete outbox effects.
5. Run an OMP no-write vision/JSON adapter probe, then one small OMP production chunk.
6. Enable v3 queue work only after both harnesses pass their respective proof runs.
7. Retain v2 as rollback throughout the opt-in period.

## Verification plan

### Pure tests

- Shopee first-URL cleanup: quote noise and multi-image source values.
- Non-Shopee direct HTTPS extraction without Shopee rewriting.
- Image malformed/non-HTTPS/unreadable paths.
- Attempt planning for initial, retry, listing change, and same-attempt replay.
- Decision union acceptance and rejection, including cross-verdict fields.
- Candidate-reference resolution and stale-reference rejection.
- Dictionary natural-identity conflict detection.
- Strict Sheet outcomes: appended, already present, and failed.
- Outbox event construction, grouping, retry, and completion marking.

### Driver tests with fakes

- Agent adapters receive native image attachment inputs and no write authority.
- Attachment manifests preserve product-to-image order; a response that cites another product's distinctive image index is rejected.
- Two-product fixture chunks with deliberately swapped distinctive images prove both CLI argument construction and cross-association rejection.
- Failed vision sentinel blocks production work.
- Invalid agent output reaches no DML.
- Transaction failure creates no committed outbox completion.
- Committed attempt with pending outbox resumes side effects without a second agent call.
- A retry attempt inserts after an initial unconfident attempt; replay of that retry does not duplicate QA.
- An unconfident filter is rejected; a defer writes nothing and returns `BLOCKED` after safe rows finish.

### Live proof

- Codex dry run and small production chunk prove attachment, decision validation, read-back, and outbox completion.
- OMP uses its native image attachment path and passes the same no-write random-label vision probe before a small production chunk.
- V2 remains selectable throughout all proof runs.

## Operational proof record

On 2026-09-18 UTC, migration `006_add_non_niq_qa_outbox.sql` was deployed to
`magpie_reference.non_niq_qa_outbox`. Codex and OMP each completed native-attachment
sentinel, dry-run, and non-dry invocations for `babybath shopee ID` at workload
`500 10`.

Every invocation emitted `NOTHING_TO_DO`: no eligible current-title QA work existed.
Before and after the non-dry runs, v3-scoped QA, dictionary, filter, and outbox counts
for that scope were all zero. Therefore no live product decision, transactional mutation,
read-back, or outbox delivery was exercised.

Do not enable the v3 queue for this scope until an eligible work item has completed the
small Codex and OMP production chunks. V2 remains the selectable rollback path.
