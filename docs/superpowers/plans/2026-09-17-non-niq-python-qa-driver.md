# Non-NIQ Python QA Driver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver an opt-in Python v3 Non-NIQ QA driver that batches deterministic work, delegates only multimodal decisions to Codex or OMP, and makes every production mutation replay-safe.

**Architecture:** `script/non_niq/non_niq_qa_v3.py` keeps the existing queue invocation contract while owning read-only planning, one-image preparation, native harness attachments, decision validation, BigQuery DML, read-back, and durable side effects. A single BigQuery outbox records Meilisearch and Sheet work in the same transaction as QA/dictionary/filter mutations; v3 recovers that outbox before planning new products. V2 remains unmodified rollback.

**Tech Stack:** Python 3.9+ standard library, existing `google-cloud-bigquery`, `google-api-python-client`, `sentence-transformers`, Meilisearch HTTP API, Codex CLI, OMP CLI, BigQuery Standard SQL, pytest.

**Spec:** `docs/superpowers/specs/2026-09-17-non-niq-python-qa-driver-design.md`

## Global Constraints

- Do not modify `script/non_niq/non_niq_qa_v2.sh`, `script/non_niq/non_niq_qa.sh`, or `script/non_niq/queue_worker.sh`; select v3 through the existing `NON_NIQ_QA_SCRIPT` hook.
- Preserve the queue positional invocation: `<DATASET> <PLATFORM> [COUNTRY] [MAX_TURNS] [MAX_ROWS] [KATEGORI]`; v3 accepts it even where `MAX_TURNS` does not constrain a harness.
- `AGENT_HARNESS` is exactly `codex` or `omp` in v3. Claude remains available through v2.
- All production BigQuery mutations use Standard SQL DML, never the streaming API.
- Never write source-table `qa_status`. Never modify `product_id_dict` mapping tables.
- Every `_meta` read uses `JSON_VALUE(SAFE.PARSE_JSON(_meta), '$.field')`; never use bare `JSON_VALUE(_meta, ...)` or `SAFE.JSON_VALUE`.
- Keep Tokopedia canonicalization: source `Tokopedia | Shop` is `Tokopedia` for matching/writing.
- The v3 worklist remains source `master_table_prod`, post-filter top-90%-cumulative-GMV plus merchant allowlist, with current-title QA matching.
- Dictionary/QA/filter schemas and dictionary identity columns are resolved live. Interpolate a column identifier only after it exists in the live schema and matches `^[A-Za-z_][A-Za-z0-9_]*$`.
- The generated-column pattern must already exist at `script/non_niq/dict_patterns/<dataset>.json`; v3 fails before agent work when it does not.
- One image maximum per product. Shopee alone strips quote noise and takes the first `*.img.susercontent.com/file/` URL; non-Shopee platforms take the first already-valid HTTPS URL unchanged.
- A filter is confident-only and requires image evidence tied to that product's attachment index. `defer` writes nothing and yields `BLOCKED` after all safe products finish.
- Agents receive no operational write or data-service authority. Local path text is audit data, not visual input; use Codex `--image` and OMP `@file` attachments.
- A selected adapter must pass the random-label, no-write vision sentinel before production packet processing.
- A decision is accepted only when it matches the strict four-way union (`filter`, `map_existing`, `create_dict`, `defer`), has exact work-item/fingerprint echoes, and has valid product-local attachment evidence.
- QA replay deduplication is by product, canonical platform, and `_meta.attempt_id`; it is never deduplicated by product/title alone.
- A chunk transaction writes dictionary/QA/filter records and pending outbox records atomically. Read back committed writes before declaring the chunk complete.
- V3 emits `DONE` only when all mutations are verified and scoped outbox events are complete. It has no `partial -> DONE` path.
- Preserve v2’s non-fatal `append_sheet_new_entries()` contract. V3 uses a new strict helper with per-identity outcomes.
- Do not add dependencies: use dataclasses, hashlib, json, pathlib, subprocess, urllib, and existing project packages.
- Target the repository’s Python 3.9+ runtime (`pyproject.toml` and `uv.lock`). `AGENTS.md`’s macOS-only Python 3.8.12 path is unavailable and conflicts with that lock; the user approved this resolution on 2026-09-17.

---

## File Structure

```text
sql/migrations/006_add_non_niq_qa_outbox.sql
    Durable BigQuery post-commit outbox table.

script/non_niq/non_niq_helper.py
    Existing helper plus strict Sheet append outcomes used only by v3.

script/non_niq/non_niq_qa_v3_decision_schema.json
    Codex output schema; documents the same discriminated protocol checked locally for OMP.

script/non_niq/non_niq_qa_v3.py
    New opt-in driver: pure planning helpers, image/attachment handling, adapters, BigQuery executor,
    outbox recovery, CLI, and queue-compatible stdout contract.

tests/non_niq/test_non_niq_helper.py
    Existing helper tests extended for strict Sheet outcomes.

tests/non_niq/test_non_niq_qa_v3.py
    New isolated tests for v3 pure logic, adapters, transaction/outbox command construction, and driver flow.

docs/data-dictionary.md
    Documents `magpie_reference.non_niq_qa_outbox`.
```

---

### Task 1: Durable outbox schema and data dictionary

**Files:**
- Create: `sql/migrations/006_add_non_niq_qa_outbox.sql`
- Modify: `docs/data-dictionary.md`

**Interfaces:**
- Produces the table consumed by `non_niq_qa_v3.py`:
  `sincere-hearth-273704.magpie_reference.non_niq_qa_outbox`.
- Event uniqueness is enforced by transactional `INSERT ... WHERE NOT EXISTS (event_id)`, not a BigQuery primary key.

- [ ] **Step 1: Add the migration with the exact outbox table**

```sql
CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.non_niq_qa_outbox` (
  event_id STRING NOT NULL,
  attempt_id STRING NOT NULL,
  decision_id STRING NOT NULL,
  dataset STRING NOT NULL,
  platform STRING NOT NULL,
  country STRING NOT NULL,
  event_type STRING NOT NULL,
  payload STRING NOT NULL,
  status STRING NOT NULL,
  attempts INT64 NOT NULL,
  last_error STRING,
  created_at TIMESTAMP NOT NULL,
  completed_at TIMESTAMP
)
PARTITION BY DATE(created_at)
CLUSTER BY status, dataset, platform, country
OPTIONS (
  description = "Durable post-commit Meilisearch and Sheets delivery events for non_niq_qa_v3.py. event_id is conditionally unique in driver DML."
);
```

- [ ] **Step 2: Add the data-dictionary section**

Document event types `meili_index` and `sheet_append`, statuses `pending` and `complete`, JSON-string payload, retry/error semantics, and the invariant that pending events are recovered before new work is planned.

- [ ] **Step 3: Validate the migration parses as Standard SQL**

Run:

```bash
bq query --use_legacy_sql=false --dry_run "$(cat sql/migrations/006_add_non_niq_qa_outbox.sql)"
```

Expected: the command accepts the DDL without a SQL parse error.

- [ ] **Step 4: Commit the durable schema**

```bash
git add sql/migrations/006_add_non_niq_qa_outbox.sql docs/data-dictionary.md
git commit -m "feat: add non-NIQ QA outbox schema"
```

---

### Task 2: Strict Sheet append outcomes without changing v2 behavior

**Files:**
- Modify: `script/non_niq/non_niq_helper.py:286-409`
- Modify: `tests/non_niq/test_non_niq_helper.py`

**Interfaces:**
- Produces:

```python
@dataclass(frozen=True)
class SheetAppendOutcome:
    status: str  # "appended" | "already_present" | "failed"
    error: Optional[str] = None

SheetEntryKey = Tuple[str, str, str]

def append_sheet_new_entries_strict(
    project: str,
    dict_table: str,
    sheet_url: str,
    entries: Sequence[Mapping[str, str]],
    client=None,
    service=None,
) -> Dict[SheetEntryKey, SheetAppendOutcome]:
    """Return an explicit outcome for every supplied dictionary identity."""
```

- `append_sheet_new_entries()` remains non-raising and returns an integer for v2 callers.

- [ ] **Step 1: Write failing strict-outcome tests**

Add fake-client/fake-Sheets tests for one exact identity:

```python
entry = {
    "brand": "Acme",
    "identity_col": "sku_type",
    "identity_value": "Acme Wash 200 ml",
}
key = ("Acme", "sku_type", "Acme Wash 200 ml")
```

Use the existing fake Sheets request chain to prove: an existing matching row returns `already_present`; a successful append returns `appended`; a Sheets exception returns `failed`; and the legacy wrapper returns `0` for that same exception.

- [ ] **Step 2: Run the new tests and confirm the strict helper is absent**

Run:

```bash
pytest tests/non_niq/test_non_niq_helper.py -k strict_append -v
```

Expected: collection/import failure for `append_sheet_new_entries_strict`.

- [ ] **Step 3: Implement strict planning, lookup, and append result mapping**

Extract the shared identity validation and Sheet header lookup from the legacy wrapper. In the strict helper:

- reject missing/invalid Sheet targets, unsupported identity columns, missing headers, missing authoritative dict rows, BigQuery errors, and Sheets errors as `failed` outcomes;
- return `already_present` before issuing an append for an exact `(brand, identity_col, identity_value)` Sheet match;
- issue one append request for all remaining entries and return `appended` for only those entries after it succeeds;
- never catch errors in a way that turns a real failure into `already_present`.

Keep the legacy wrapper as:

```python
def append_sheet_new_entries(
    project, dict_table, dataset, sheet_url, entries, client=None, service=None,
):
    try:
        outcomes = append_sheet_new_entries_strict(
            project, dict_table, sheet_url, entries, client=client, service=service,
        )
    except Exception as error:
        print(f"  WARNING: append-sheet failed (non-fatal): {type(error).__name__}: {error}")
        return 0
    return sum(outcome.status == "appended" for outcome in outcomes.values())
```

- [ ] **Step 4: Run focused helper tests**

Run:

```bash
pytest tests/non_niq/test_non_niq_helper.py -k "strict_append or append_sheet" -v
```

Expected: all strict and legacy append tests pass.

- [ ] **Step 5: Commit the strict Sheet boundary**

```bash
git add script/non_niq/non_niq_helper.py tests/non_niq/test_non_niq_helper.py
git commit -m "feat: add strict non-NIQ Sheet append outcomes"
```

---

### Task 3: Define the v3 decision protocol and pure replay/image primitives

**Files:**
- Create: `script/non_niq/non_niq_qa_v3_decision_schema.json`
- Create: `script/non_niq/non_niq_qa_v3.py`
- Create: `tests/non_niq/test_non_niq_qa_v3.py`

**Interfaces:**

```python
@dataclass(frozen=True)
class PreparedImage:
    product_id: str
    image_url: Optional[str]
    image_status: str
    local_path: Optional[Path]

@dataclass(frozen=True)
class Attachment:
    product_id: str
    attachment_index: int
    attachment_filename: str
    sha256: str
    local_path: Path

@dataclass(frozen=True)
class AttemptPlan:
    work_item_id: str
    input_fingerprint: str
    attempt_id: str
    attempt_kind: str  # initial | retry | listing_change

class DecisionValidationError(ValueError):
    pass

def first_complete_https_url(image_raw: str) -> Optional[str]:
    \"\"\"Return the first parseable HTTPS URL without rewriting it.\"\"\"

def normalize_first_image_url(image_raw: Optional[str], platform: str) -> Optional[str]:
    \"\"\"Apply the platform-specific one-image policy.\"\"\"

def build_attachment_manifest(images: Sequence[PreparedImage]) -> Tuple[Attachment, ...]:
    \"\"\"Assign frozen one-based attachment indexes in packet order.\"\"\"

def plan_attempt(row: Mapping[str, Any], qa_state: Mapping[str, Any]) -> AttemptPlan:
    \"\"\"Return the stable initial, retry, or listing-change attempt.\"\"\"

def validate_decision_batch(raw: Mapping[str, Any], packets: Sequence[Mapping[str, Any]]) -> List[Mapping[str, Any]]:
    \"\"\"Return exact packet-bound decisions or raise DecisionValidationError.\"\"\"
```

- [ ] **Step 1: Write the decision-schema file before code**

Create a root object with only `decisions`, an array whose item is `oneOf` four objects. Every branch requires `product_id`, `work_item_id`, `input_fingerprint`, `kind`, `confidence`, and `evidence`; every object has `additionalProperties: false`.

Use branch-specific required fields:

```json
{"kind": "filter", "reason": "out of scope", "confidence": "confident"}
{"kind": "map_existing", "candidate_ref": "dict:1"}
{"kind": "create_dict", "attributes": {"brand": "Acme"}}
{"kind": "defer", "reason": "image unavailable", "confidence": "unconfident"}
```

Define each evidence item as `{source, claim}` plus `attachment_index` only for `source: "image"`.

- [ ] **Step 2: Write failing pure tests**

Cover these exact contracts:

```python
def test_shopee_quote_cleanup_uses_only_first_full_url():
    raw = 'https://down-id.img.susercontent.com/file/"id-first" \'id-second\''
    assert normalize_first_image_url(raw, "Shopee") == (
        "https://down-id.img.susercontent.com/file/id-first"
    )

def test_tokopedia_url_is_not_rewritten_as_shopee():
    url = "https://ec-mall-tokopedia-com.example/image.png"
    assert normalize_first_image_url(url, "Tokopedia") == url

def test_retry_attempt_differs_from_initial_but_replays_stably():
    initial = plan_attempt(row, {"kind": "initial"})
    retry = plan_attempt(row, {"kind": "retry"})
    assert initial.attempt_id != retry.attempt_id
    assert retry == plan_attempt(row, {"kind": "retry"})

def test_rejects_image_evidence_from_another_products_attachment():
    with pytest.raises(DecisionValidationError):
        validate_decision_batch(raw_cross_attached_result, packets)
```

Also test malformed/non-HTTPS URLs, unavailable image requiring unconfident map/create or defer, confident filter requiring matching image evidence, unknown candidate refs, generated dict attributes, cross-verdict fields, duplicate/missing product decisions, and stable listing-change generation.

- [ ] **Step 3: Run the pure test file and confirm it fails before implementation**

Run:

```bash
pytest tests/non_niq/test_non_niq_qa_v3.py -k "image or attempt or decision" -v
```

Expected: import failure because `non_niq_qa_v3.py` does not yet exist.

- [ ] **Step 4: Implement only pure data and validation functions**

Use `dataclasses`, `hashlib.sha256`, `json.dumps(value, sort_keys=True, separators=(",", ":"))`, `urllib.parse.urlsplit`, and `pathlib`.

Implement image policy exactly:

```python
if platform == "Shopee":
    cleaned = image_raw.replace('"', '').replace("'", '')
    match = re.search(r"https://[^\s]+\.img\.susercontent\.com/file/[^\s]+", cleaned)
    return match.group(0) if match else None
return first_complete_https_url(image_raw)
```

Do not synthesize any later bare image IDs. Build attachment indexes in frozen packet order, use neutral names `attachment-0001.<suffix>`, and validate that every readable-image non-defer decision cites its own attachment index.

- [ ] **Step 5: Run the focused pure suite**

Run:

```bash
pytest tests/non_niq/test_non_niq_qa_v3.py -k "image or attempt or decision" -v
```

Expected: all pure protocol tests pass.

- [ ] **Step 6: Commit the protocol foundation**

```bash
git add script/non_niq/non_niq_qa_v3.py script/non_niq/non_niq_qa_v3_decision_schema.json tests/non_niq/test_non_niq_qa_v3.py
git commit -m "feat: add non-NIQ v3 decision protocol"
```

---

### Task 4: Add native Codex/OMP adapters and vision sentinel gate

**Files:**
- Modify: `script/non_niq/non_niq_qa_v3.py`
- Modify: `tests/non_niq/test_non_niq_qa_v3.py`

**Interfaces:**

```python
class AdapterVisionError(RuntimeError):
    pass

def build_codex_command(prompt: str, schema_path: Path, output_path: Path, attachments: Sequence[Attachment]) -> List[str]:
    \"\"\"Build Codex's one ordered native image invocation.\"\"\"

def build_omp_command(prompt: str, attachments: Sequence[Attachment]) -> List[str]:
    \"\"\"Build OMP's one ordered native image invocation.\"\"\"

def verify_adapter_vision(adapter: str, run_command: Callable[..., CompletedProcess]) -> None:
    \"\"\"Raise AdapterVisionError unless both random image labels are read exactly.\"\"\"

def invoke_adapter(adapter: str, packet_prompt: str, attachments: Sequence[Attachment]) -> Mapping[str, Any]:
    \"\"\"Return the adapter's parsed final response only.\"\"\"
```

- [ ] **Step 1: Write failing adapter tests**

```python
def test_codex_command_passes_images_in_attachment_index_order():
    command = build_codex_command(
        "decide", SCHEMA_PATH, OUTPUT_PATH, [attachment_1, attachment_2],
    )
    image_flag = command.index("--image")
    assert command[image_flag + 1:image_flag + 3] == [
        str(attachment_1.local_path), str(attachment_2.local_path),
    ]

def test_omp_command_uses_native_at_file_arguments_in_order():
    command = build_omp_command("decide", [attachment_1, attachment_2])
    assert [arg for arg in command if arg.startswith("@")][-2:] == [
        f"@{attachment_1.local_path}", f"@{attachment_2.local_path}",
    ]

def test_wrong_random_label_fails_before_product_decision():
    with pytest.raises(AdapterVisionError):
        verify_adapter_vision("codex", fake_runner_returning_wrong_label)
```

Include a two-product fixture with different local image bytes. Deliberately swap attachment order in the fake output and assert validation rejects a decision that cites the other product's index.

- [ ] **Step 2: Run adapter tests and confirm missing functions fail**

Run:

```bash
pytest tests/non_niq/test_non_niq_qa_v3.py -k "adapter or attachment or sentinel" -v
```

Expected: failure because adapter functions are not implemented.

- [ ] **Step 3: Implement adapters without operational tools**

Build Codex commands with `codex exec --ephemeral --sandbox read-only --output-schema script/non_niq/non_niq_qa_v3_decision_schema.json --output-last-message /tmp/non_niq_v3_result.json --image attachment-0001.jpg attachment-0002.jpg decide`.

Build OMP commands with `omp --print --mode json --no-tools --no-session @attachment-0001.jpg @attachment-0002.jpg decide`. Extract its final assistant result and pass it through `validate_decision_batch`; do not accept JSONL progress output as a decision.

For each selected adapter, generate two probe images with cryptographically random visible labels and neutral filenames. Use the same image-only label question for both. Fail unless both parsed labels equal the labels rendered in their attached images. Run this before any production worklist operation.
For Codex, pass `-c sandbox_workspace_write.network_access=false` and a sanitized subprocess environment containing harness authentication only; remove Google credential/config variables and the Sheets key path. For OMP, `--no-tools` is mandatory. Neither adapter receives the BigQuery client, Meilisearch URL, Sheet URL, DML text, or an executable task list.

- [ ] **Step 4: Run adapter tests**

Run:

```bash
pytest tests/non_niq/test_non_niq_qa_v3.py -k "adapter or attachment or sentinel" -v
```

Expected: all adapter command, sentinel, and cross-association tests pass.

- [ ] **Step 5: Commit the adapter boundary**

```bash
git add script/non_niq/non_niq_qa_v3.py tests/non_niq/test_non_niq_qa_v3.py
git commit -m "feat: add native non-NIQ v3 agent adapters"
```

---

### Task 5: Implement read-only run planning and packet construction

**Files:**
- Modify: `script/non_niq/non_niq_qa_v3.py`
- Modify: `tests/non_niq/test_non_niq_qa_v3.py`

**Interfaces:**

```python
@dataclass(frozen=True)
class RunContext:
    dataset: str
    platform: str
    country: str
    source_table: str
    qa_table: str
    dict_table: str
    filter_table: str
    qa_pk_col: str
    dict_identity_col: str
    dict_typo_col: str
    dict_has_meta: bool
    month: str
    meili_index: str
    taxonomy_url: Optional[str]


def resolve_run_context(args, client) -> RunContext:
    """Resolve live config, schemas, month, merchant IDs, and dict pattern."""

def build_worklist_sql(context: RunContext, max_rows: int, kategori: str, monthly_reverify: bool, merchant_ids: Sequence[str]) -> str:
    """Return the stakeholder-aligned v3 worklist SQL."""

def materialize_worklist(client, sql: str) -> List[Mapping[str, Any]]:
    """Return ordered worklist rows."""

def resolve_candidate_refs(client, context: RunContext, hits: Sequence[Mapping[str, Any]]) -> Mapping[str, Mapping[str, Any]]:
    """Resolve only exact live dictionary rows into product-local references."""

def build_product_packets(context: RunContext, rows, candidates, images) -> List[Mapping[str, Any]]:
    """Combine planning outputs into immutable packet dictionaries."""
```

- [ ] **Step 1: Write failing planner tests from v2 invariants**

Assert the generated SQL contains and behaviorally preserves:

```python
assert "r.cumulative_gmv_share <= 0.9" in sql
assert "JSON_VALUE(SAFE.PARSE_JSON(_meta)" in sql
assert "qa_status" not in sql.lower()
assert "Tokopedia | Shop" in sql
assert "ORDER BY priority ASC, gmv_monthly DESC" in sql
```

Use fake BigQuery rows to prove packets are priority/GMV ordered, candidate refs are product-local, primary filter table stays in the dataset's own namespace, and absent dict-pattern JSON fails before retrieval/agent invocation.

- [ ] **Step 2: Run planner tests and confirm they fail**

Run:

```bash
pytest tests/non_niq/test_non_niq_qa_v3.py -k "context or worklist or packet or candidate" -v
```

Expected: failure because run-context and planner functions are absent.

- [ ] **Step 3: Port deterministic v2 planning into Python**

Use direct imports from `non_niq_helper.py` for category config, live column resolution, forced merchants, `retrieve_candidates`, and existing constants. Do not shell out to `non_niq_qa_v2.sh`.

Port the v2 CTE sequence into `build_worklist_sql` in this exact order: `enrichment_dedup` when Shopee enrichment is configured, `filter_state` when a filter table exists, `scoped`, `ranked`, `stakeholder_scope`, `qa_title_state`, `qa_state`, `prior_snapshot` when monthly reverify is enabled, and `prioritized`. The outer query is exactly:

```sql
SELECT * FROM prioritized
WHERE priority IS NOT NULL
ORDER BY priority ASC, gmv_monthly DESC
LIMIT @row_limit
```

Keep pre-filter ranking, title normalization, whole-history `LOGICAL_OR` retry flags, optional monthly listing-change inputs, and merchant force inclusion. Extend planning to compute the current logical `AttemptPlan` and skip an attempt only when no pending matching outbox event remains.

Resolve prior mapping/table shape and dictionary candidate rows in batch before packet creation. Each packet receives only its own candidate refs, prior mapping, live writable columns, generated-pattern sources, and allowed categorical vocabulary.

- [ ] **Step 4: Run planner tests**

Run:

```bash
pytest tests/non_niq/test_non_niq_qa_v3.py -k "context or worklist or packet or candidate" -v
```

Expected: all planner and packet tests pass without network or BigQuery access.

- [ ] **Step 5: Commit deterministic planning**

```bash
git add script/non_niq/non_niq_qa_v3.py tests/non_niq/test_non_niq_qa_v3.py
git commit -m "feat: add non-NIQ v3 worklist planner"
```

---

### Task 6: Implement transactional decisions, attempt-level QA writes, and read-back

**Files:**
- Modify: `script/non_niq/non_niq_qa_v3.py`
- Modify: `tests/non_niq/test_non_niq_qa_v3.py`

**Interfaces:**

```python
@dataclass(frozen=True)
class OutboxEvent:
    event_id: str
    attempt_id: str
    decision_id: str
    event_type: str
    payload: str

@dataclass(frozen=True)
class ChunkCommit:
    attempts: Tuple[AttemptPlan, ...]
    created_dict_identities: Tuple[Tuple[str, str, str], ...]
    outbox_events: Tuple[OutboxEvent, ...]

def build_chunk_script(context: RunContext, packets, decisions, now: datetime) -> Tuple[str, Sequence[Any]]:
    \"\"\"Return one parameterized transaction script and its query parameters.\"\"\"

def apply_chunk(client, context: RunContext, packets, decisions, now: datetime) -> ChunkCommit:
    \"\"\"Execute build_chunk_script with bounded transient retries.\"\"\"

def verify_chunk_commit(client, context: RunContext, commit: ChunkCommit) -> None:
    \"\"\"Read back all expected mutations by identity and attempt ID.\"\"\"
```

- [ ] **Step 1: Write failing transaction-plan tests**

Use a recording fake client. Assert the submitted script has one `BEGIN TRANSACTION`/`COMMIT TRANSACTION`, includes all needed DML, and never contains source-table `qa_status` or mapping-table mutation.

```python
def test_retry_qa_insert_dedupes_attempt_not_title():
    sql, _ = build_chunk_script(context, [retry_packet], [retry_decision], NOW)
    assert "JSON_VALUE(SAFE.PARSE_JSON(_meta), '$.attempt_id')" in sql
    assert "normalized_sku_name" not in sql

def test_create_dict_writes_pending_outbox_in_same_transaction():
    sql, _ = build_chunk_script(context, [create_packet], [create_decision], NOW)
    assert "INSERT INTO `sincere-hearth-273704.magpie_reference.non_niq_qa_outbox`" in sql
    assert "BEGIN TRANSACTION" in sql and "COMMIT TRANSACTION" in sql

def test_defer_generates_no_dml_or_outbox_event():
    sql, parameters = build_chunk_script(context, [defer_packet], [defer_decision], NOW)
    assert sql == ""
    assert parameters == ()
```

Also test filter is product-level deduped, same attempt replay is a no-op, retry has a new attempt ID, listing change has a new generation ID, natural-identity dict conflicts fail before DML, and transaction retry reuses validated decisions without invoking an adapter.

- [ ] **Step 2: Run transaction tests and confirm they fail**

Run:

```bash
pytest tests/non_niq/test_non_niq_qa_v3.py -k "chunk or transaction or replay or outbox" -v
```

Expected: failure because executor functions are absent.

- [ ] **Step 3: Implement parameterized chunk DML**

Build one Standard SQL script per valid chunk. Use query parameters for all values; only validated live-schema identifiers are interpolated.

The script must:

1. begin a transaction;
2. conditionally insert a terminal filter row for confident `filter` decisions;
3. conditionally insert new dictionary identities, then resolve whether each identity was pre-existing or newly created;
4. conditionally insert QA rows using `(qa_pk, canonical platform, JSON_VALUE(SAFE.PARSE_JSON(_meta), '$.attempt_id'))` as the replay guard;
5. stamp valid JSON `_meta` with source, timestamp, run ID, attempt ID, attempt kind, decision ID, confidence, and driver-derived retry `human_review` value;
6. conditionally insert `sheet_append` for new identities with configured taxonomy URLs and `meili_index` only for confident new identities;
7. commit.

After commit, query QA/filter/dictionary/outbox state by the intended IDs and fail if any expected write is absent or differs from the driver-derived values.

- [ ] **Step 4: Run transaction and replay tests**

Run:

```bash
pytest tests/non_niq/test_non_niq_qa_v3.py -k "chunk or transaction or replay or outbox" -v
```

Expected: all transaction construction, replay, and read-back tests pass.

- [ ] **Step 5: Commit the safe mutation boundary**

```bash
git add script/non_niq/non_niq_qa_v3.py tests/non_niq/test_non_niq_qa_v3.py
git commit -m "feat: add replay-safe non-NIQ v3 writes"
```

---

### Task 7: Recover outbox events and wire the queue-compatible CLI

**Files:**
- Modify: `script/non_niq/non_niq_qa_v3.py`
- Modify: `tests/non_niq/test_non_niq_qa_v3.py`

**Interfaces:**

```python
def drain_outbox(client, context: RunContext, now: datetime) -> None:
    """Deliver scoped pending events or raise a delivery error."""

def emit_result(table: str, signal: str, message: str, **fields: str) -> None:
    """Print the queue-compatible structured JSON result."""

def run(args) -> int:
    """Run one queue-compatible v3 session."""

def main() -> None:
    """Parse arguments and exit with run()'s status."""
```

- [ ] **Step 1: Write failing outbox and CLI tests**

Add recording-fake tests proving all six contracts: pending Meilisearch events are batched then completed; Sheet events complete only for `appended` or `already_present`; Sheet failures remain pending and make the run fail; a defer yields `BLOCKED` after safe products; dry-run never calls mutation/outbox delivery; and stdout starts with the queue signal then a JSON result.

Assert startup drains scoped pending events before `materialize_worklist`, and that a crash-equivalent pending event completes without an adapter invocation.

- [ ] **Step 2: Run CLI/outbox tests and confirm failure**

Run:

```bash
pytest tests/non_niq/test_non_niq_qa_v3.py -k "drain or signal or dry_run or blocked" -v
```

Expected: failure because outbox and CLI functions are absent.

- [ ] **Step 3: Implement durable recovery and `main()`**

For pending events:

- group `meili_index` payloads by index and call existing `index_documents` once per group;
- group `sheet_append` payloads by Sheet/dictionary target and call `append_sheet_new_entries_strict`;
- mark only successful or already-present Sheet entries complete;
- leave failures pending, increment `attempts`, record `last_error`, and return `FAILED`.

`main()` parses the v2-compatible positionals plus `--dry-run`, runs the selected adapter sentinel, drains outbox, plans bounded ordered chunks, prepares/downloads images, invokes the adapter, validates decisions, applies and verifies chunks, drains new events, and prints exactly:

```text
QUEUE_SIGNAL: DONE
{"timestamp":"2026-09-17T00:00:00Z","table":"babybath:shopee","signal":"DONE","message":"QA v3 session finished"}
```

Return `NOTHING_TO_DO`, `DONE`, `FAILED`, or `BLOCKED` exactly as specified. In dry-run, permit planning, image preparation, sentinel, and decision validation but never call BigQuery DML, Meilisearch indexing, Sheets append, or outbox status updates.

- [ ] **Step 4: Run the full new v3 test file**

Run:

```bash
pytest tests/non_niq/test_non_niq_qa_v3.py -v
```

Expected: all isolated v3 tests pass.

- [ ] **Step 5: Run impacted existing regression tests**

Run:

```bash
pytest tests/non_niq/test_non_niq_helper.py -v && bash tests/non_niq/test_non_niq_qa_v2.sh
```

Expected: helper and v2 contracts pass unchanged.

- [ ] **Step 6: Commit the runnable v3 driver**

```bash
git add script/non_niq/non_niq_qa_v3.py tests/non_niq/test_non_niq_qa_v3.py
git commit -m "feat: add opt-in non-NIQ Python QA driver"
```

---

### Task 8: Execute controlled proof runs and record operational use

**Files:**
- Modify: `docs/superpowers/specs/2026-09-17-non-niq-python-qa-driver-design.md`

**Interfaces:**
- Proves `non_niq_qa_v3.py` can be selected directly and v2 remains unchanged fallback.

- [ ] **Step 1: Run static checks before live access**

Run:

```bash
PYTHON=.venv/bin/python3
"$PYTHON" -m py_compile script/non_niq/non_niq_qa_v3.py script/non_niq/non_niq_helper.py
"$PYTHON" -m pytest tests/non_niq/test_non_niq_qa_v3.py tests/non_niq/test_non_niq_helper.py -v
bash tests/non_niq/test_non_niq_qa_v2.sh
```

Expected: all commands exit zero.

- [ ] **Step 2: Run a Codex dry run on a bounded real workload**

Run:

```bash
AGENT_HARNESS=codex .venv/bin/python3 script/non_niq/non_niq_qa_v3.py babybath shopee ID 500 10 --dry-run
```

Expected: Codex passes the native image sentinel and v3 prints a non-mutating result. Verify no new QA/dict/filter/outbox row was written.

- [ ] **Step 3: Run one Codex production chunk and read back state**

Run:

```bash
AGENT_HARNESS=codex .venv/bin/python3 script/non_niq/non_niq_qa_v3.py babybath shopee ID 500 10
```

Expected: every committed QA row has an `attempt_id`, `decision_id`, and valid confidence metadata; each created dict identity has the correct completed or pending outbox events; pending outbox must cause `FAILED`, not `DONE`.

- [ ] **Step 4: Run OMP capability proof and bounded production chunk**

Run:

```bash
AGENT_HARNESS=omp .venv/bin/python3 script/non_niq/non_niq_qa_v3.py babybath shopee ID 500 10 --dry-run
AGENT_HARNESS=omp .venv/bin/python3 script/non_niq/non_niq_qa_v3.py babybath shopee ID 500 10
```

Expected: OMP passes the native attachment sentinel and strict local decision validation before either run can mutate data.

- [ ] **Step 5: Record successful proof details in the spec**

Add an `Implementation proof` subsection with the exact date, harness, command form, emitted signal, committed-row counts, and whether each outbox event completed. Do not claim a harness is production-ready without recorded command output.

- [ ] **Step 6: Commit proof documentation**

```bash
git add docs/superpowers/specs/2026-09-17-non-niq-python-qa-driver-design.md
git commit -m "docs: record non-NIQ v3 proof runs"
```

---

## Plan Self-Review

**Spec coverage:**

- Python-only deterministic driver, v2 rollback, unchanged queue contract: Tasks 3, 5, and 7.
- First-image platform policy and product/image attachment binding: Tasks 3 and 4.
- Codex/OMP native multimodal proof: Task 4, then Task 8.
- Strict decision union, confident terminal filters, and no-write defer: Task 3 and Task 7.
- Attempt-level retry/listing-change replay: Task 3, Task 5, and Task 6.
- Atomic DML, read-back, and no mapping/qa_status mutation: Task 6.
- Durable BigQuery outbox and idempotent post-commit recovery: Task 1, Task 6, and Task 7.
- Strict Sheets distinction while preserving v2’s wrapper: Task 2 and Task 7.
- Dry run and controlled live evidence: Task 8.

**Placeholder scan:** no placeholder terms or unspecified validation/error-handling steps remain. Every external boundary has an explicit accepting result, rejecting result, and queue signal.

**Type consistency:** `Attachment` drives manifest construction, adapter CLI order, and evidence checks. `AttemptPlan` drives QA metadata and replay guard. `OutboxEvent` is created only by `apply_chunk` and completed only by `drain_outbox`. `RunContext` is the only table/config input to planner, executor, and recovery functions.
