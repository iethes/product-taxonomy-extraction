# Non-NIQ Taxonomy Insert Log Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve every successful non-NIQ taxonomy creation in one durable BigQuery log before a Sheet-to-BigQuery overwrite can erase it.

**Architecture:** Add one append-only `magpie_reference.non_niq_taxonomy_insert_log` table. Every newly created taxonomy target row and its log record are committed atomically; `row_json` is an envelope containing the source product/platform and the complete target row. V3 extends its existing driver transaction; v2, susubayi, and eiger require the same transaction and read-back contract in their agent prompts.

**Tech Stack:** BigQuery Standard SQL, Python 3.9+ with `google-cloud-bigquery`, Bash, pytest, shell self-tests.

**Spec:** `docs/superpowers/specs/2026-09-23-non-niq-taxonomy-insert-log-design.md`

## Global Constraints

- Create exactly one log table: `sincere-hearth-273704.magpie_reference.non_niq_taxonomy_insert_log`.
- Its only columns are `target_table STRING`, `created_at TIMESTAMP`, and `row_json JSON`.
- Partition the table by `DATE(created_at)`; configure no expiration.
- `row_json` MUST be `{"product_id": ..., "ecommerce_platform": ..., "inserted_row": {...}}`.
- Log only rows actually created in target tables; never log an existing identity, re-point, filter, or skipped retry.
- The target insert and log insert MUST be in the same BigQuery transaction. If either fails, neither may commit.
- `target_table` MUST be the full three-part BigQuery table name.
- Preserve DML-only writes; do not use the streaming API.
- No worker, retry/replay queue, deduplication mechanism, config field, helper process, or per-category log table.
- Production-code changes are limited to the four named QA scripts; supporting changes are their focused tests, the new migration, and the data dictionary.

---

### Task 1: Define the durable log table

**Files:**
- Create: `sql/migrations/008_add_non_niq_taxonomy_insert_log.sql`
- Modify: `docs/data-dictionary.md:390-413`

**Interfaces:**
- Consumes: the approved schema in `docs/superpowers/specs/2026-09-23-non-niq-taxonomy-insert-log-design.md`.
- Produces: `sincere-hearth-273704.magpie_reference.non_niq_taxonomy_insert_log(target_table, created_at, row_json)` for all four QA writers.

- [ ] **Step 1: Add the schema migration**

```sql
CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.non_niq_taxonomy_insert_log` (
  target_table STRING NOT NULL,
  created_at TIMESTAMP NOT NULL,
  row_json JSON NOT NULL
)
PARTITION BY DATE(created_at)
OPTIONS (
  description = "Append-only record of successful non-NIQ taxonomy target-table inserts."
);
```

Do not add a primary key, clustering, retention policy, `source_script`, flattened product columns, or a mutation statement.

- [ ] **Step 2: Validate the migration parses without mutating BigQuery**

Run:

```bash
bq query --use_legacy_sql=false --dry_run "$(cat sql/migrations/008_add_non_niq_taxonomy_insert_log.sql)"
```

Expected: Standard SQL dry-run succeeds; no table is created.

- [ ] **Step 3: Document the table immediately after `non_niq_qa_outbox`**

Add a `## Reference Layer — magpie_reference.non_niq_taxonomy_insert_log` section. State the one-row-per-successful-target-insert grain, list the three columns, and define `row_json` as this envelope:

```json
{
  "product_id": "originating worklist product ID",
  "ecommerce_platform": "originating raw platform",
  "inserted_row": { "exact committed target columns": "values" }
}
```

State that it is permanent append-only recovery data for dictionary rows and Eiger QA taxonomy rows, not a delivery outbox.

- [ ] **Step 4: Commit the isolated schema/documentation change**

```bash
git add sql/migrations/008_add_non_niq_taxonomy_insert_log.sql docs/data-dictionary.md
git commit -m "feat: add non-NIQ taxonomy insert log schema"
```

### Task 2: Commit v3 dictionary rows and logs together

**Files:**
- Modify: `script/non_niq/non_niq_qa_v3.py:1303-1801,1955-2049`
- Test: `tests/non_niq/test_non_niq_qa_v3.py:822-938`

**Interfaces:**
- Consumes: `_build_operations()` create-dictionary operations, their `packet` provenance, the exact dictionary values, and the migration table from Task 1.
- Produces: transaction SQL that inserts a new dictionary row and its `non_niq_taxonomy_insert_log` record together; `ChunkCommit` expectations that `verify_chunk_commit()` reads back.

- [ ] **Step 1: Write failing focused tests for the new v3 contract**

Add tests next to `test_create_dict_writes_pending_outbox_in_same_transaction` that build one `create_dict` packet and assert:

```python
values = [str(parameter.value) for parameter in parameters]

assert "INSERT INTO `project.magpie_reference.non_niq_taxonomy_insert_log`" in sql
assert "target_table" in sql
assert "created_at" in sql
assert "row_json" in sql
assert any('"product_id":"p-1"' in value for value in values)
assert any('"ecommerce_platform":"Shopee"' in value for value in values)
assert any('"inserted_row"' in value for value in values)
assert sql.index("INSERT INTO `project.babybath.babybath_dict`") < sql.index(
    "INSERT INTO `project.magpie_reference.non_niq_taxonomy_insert_log`"
)
```

Add a second test that passes the create identity as already existing and asserts neither an insert-log expectation nor insert-log SQL is produced. Keep the existing outbox assertions unchanged.

- [ ] **Step 2: Run the focused tests and confirm the missing log behavior fails**

Run:

```bash
./.venv/bin/python -m pytest tests/non_niq/test_non_niq_qa_v3.py -q
```

Expected: the new assertions fail because v3 does not yet reference `non_niq_taxonomy_insert_log`.

- [ ] **Step 3: Add one private table-reference helper and a log expectation type**

Near `_outbox_table()`, add:

```python
def _insert_log_table(context: RunContext) -> str:
    return _table_reference(context.project, "magpie_reference.non_niq_taxonomy_insert_log")
```

Extend `ChunkCommit` with an immutable sequence of expected log records. Each expectation must retain `target_table`, `created_at`, and the serialized envelope used by the transaction. Do not create a generic event model or reuse `OutboxEvent`: delivery events and immutable recovery rows have different contracts.

- [ ] **Step 4: Build the exact log envelope from the create operation**

Factor the existing dictionary-value construction from `build_chunk_script()` into one helper so the dictionary `INSERT` and `inserted_row` use identical values, including `_meta` when the target dictionary supports it. For each prospective new dictionary identity, construct:

```python
payload = {
    "product_id": str(packet["product_id"]),
    "ecommerce_platform": str(packet.get("ecommerce_platform") or context.platform),
    "inserted_row": dict_values,
}
```

Set `target_table` to `"%s.%s" % (context.project, context.dict_table)`. Serialize using `json.dumps(..., sort_keys=True, separators=(",", ":"), default=str)` so parameter values and expectations are deterministic.

- [ ] **Step 5: Insert the JSON log only for an actually new dictionary row**

Keep the existing `_v3_new_dict` temporary table as the authority for whether the transaction creates an identity. After the dictionary conditional insert, add an `INSERT` into `_insert_log_table(context)` that:

```sql
INSERT INTO `project.magpie_reference.non_niq_taxonomy_insert_log`
  (target_table, created_at, row_json)
SELECT @target_table, @created_at, PARSE_JSON(@row_json)
FROM _v3_new_dict
WHERE brand = @brand AND identity_value = @identity;
```

Use the same transaction and parameter builder as the dictionary insert. This `SELECT` guard is required: a second writer can make `_v3_new_dict` empty after v3 preflight, and such a skipped target insertion must not create a false audit row. Do not add a log record for `map_existing`, `filter`, or `defer` operations.

- [ ] **Step 6: Read back the committed log record**

Extend `verify_chunk_commit()` to require one matching row for each expected log record:

```sql
SELECT 1
FROM `project.magpie_reference.non_niq_taxonomy_insert_log`
WHERE target_table = @target_table
  AND created_at = @created_at
  AND TO_JSON_STRING(row_json) = TO_JSON_STRING(PARSE_JSON(@row_json))
LIMIT 1
```

Use the existing `_assert_readback()` pattern. Preserve the existing dictionary, QA, filter, and outbox checks.

- [ ] **Step 7: Run the focused tests and confirm the transaction contract passes**

Run:

```bash
./.venv/bin/python -m pytest tests/non_niq/test_non_niq_qa_v3.py -q
```

Expected: PASS. The test proves the created-row path emits one log statement and the known-existing path emits none.

- [ ] **Step 8: Commit the v3 transaction change**

```bash
git add script/non_niq/non_niq_qa_v3.py tests/non_niq/test_non_niq_qa_v3.py
git commit -m "feat: log non-NIQ v3 taxonomy inserts"
```

### Task 3: Require atomic logging in the agent-driven scripts

**Files:**
- Modify: `script/non_niq/non_niq_qa_v2.sh:547-595,636-670`
- Modify: `script/non_niq/susubayi_qa.sh:379-422,457-486`
- Modify: `script/non_niq/eiger_qa.sh:358-423`
- Test: `tests/non_niq/test_non_niq_qa_v2.sh:263-378`
- Test: `tests/non_niq/test_susubayi_qa.sh:42-56`
- Test: `tests/non_niq/test_eiger_qa.sh:12-25`

**Interfaces:**
- Consumes: live target-table schemas, current worklist product ID/platform, and the new log table from Task 1.
- Produces: prompts requiring each agent-created dictionary row (or Eiger QA taxonomy row) and its immutable log record to commit atomically, then be read back.

- [ ] **Step 1: Write failing prompt-contract assertions**

For all three shell tests, assert the generated prompt contains these literal contract elements:

```bash
'non_niq_taxonomy_insert_log'
'BEGIN TRANSACTION'
'COMMIT TRANSACTION'
'"product_id"'
'"ecommerce_platform"'
'"inserted_row"'
'created_at'
'row_json'
'post-commit read-back'
```

In the v2 and susubayi tests, assert the contract names the resolved `dict_table`. In the Eiger test, assert it names `eiger.product_id_dict_image_qa` and does not describe Eiger as a dictionary-table writer.

- [ ] **Step 2: Run the shell tests and confirm the contract is absent**

Run:

```bash
bash tests/non_niq/test_non_niq_qa_v2.sh
bash tests/non_niq/test_susubayi_qa.sh
bash tests/non_niq/test_eiger_qa.sh
```

Expected: the new prompt-contract assertions fail before any network, BigQuery, or agent CLI call.

- [ ] **Step 3: Add the v2 dictionary-create transaction rule**

In `build_qa_prompt()`, replace the single-row dictionary insert instruction in Step 2c with an explicit rule:

1. Build a temporary candidate row only when its natural dictionary identity is absent.
2. In one `BEGIN TRANSACTION`/`COMMIT TRANSACTION`, insert that candidate into `${PROJECT}.${dict_table}` and insert one log record into `${PROJECT}.magpie_reference.non_niq_taxonomy_insert_log`.
3. Set `target_table` to the full `${PROJECT}.${dict_table}` name and `created_at` to `CURRENT_TIMESTAMP()`.
4. Set `row_json` with `TO_JSON(STRUCT(<worklist product_id> AS product_id, <raw ecommerce_platform> AS ecommerce_platform, <exact new dict row> AS inserted_row))`.
5. Select the log insert from the pre-insert temporary candidate set, not from all dict rows, so an existing identity creates no log row.
6. After `COMMIT`, perform post-commit read-back of the dictionary row and matching log row before writing QA.

Retain the existing ten-row DML bound and do not ask the agent to create or alter the log table.

- [ ] **Step 4: Apply the same minimal dictionary-create rule to susubayi**

Add the same contract to susubayi Step 2c, substituting `${DATASET}`/`${dict_table}` as already used by that prompt. Correct its old direct dict insertion wording so no branch permits a standalone target-table insert.

- [ ] **Step 5: Add Eiger’s fixed-taxonomy QA transaction rule**

In Eiger Step 2d, require the existing INSERT into `${QA_TABLE}` and a log INSERT to commit in the same transaction. Its log row uses:

```text
target_table = sincere-hearth-273704.eiger.product_id_dict_image_qa
row_json = {product_id, ecommerce_platform, inserted_row: exact QA row}
```

Keep Eiger’s filter writes outside this log; only its new taxonomy QA row is in scope. After commit, require post-commit read-back of both rows before Meilisearch indexing.

- [ ] **Step 6: Add the shared hard rule to all three prompts**

State exactly: a failure to write or read back the log rolls back/invalidates the taxonomy insert; do not retry the log separately; report the product unresolved or blocked under the script’s existing result contract. Do not add any retry queue, worker, or recovery action.

- [ ] **Step 7: Run focused shell tests and confirm the three contracts pass**

Run:

```bash
bash tests/non_niq/test_non_niq_qa_v2.sh && \
bash tests/non_niq/test_susubayi_qa.sh && \
bash tests/non_niq/test_eiger_qa.sh
```

Expected: PASS. These are pure local prompt/flow tests and perform no production writes.

- [ ] **Step 8: Commit the agent-contract updates**

```bash
git add script/non_niq/non_niq_qa_v2.sh script/non_niq/susubayi_qa.sh script/non_niq/eiger_qa.sh \
  tests/non_niq/test_non_niq_qa_v2.sh tests/non_niq/test_susubayi_qa.sh tests/non_niq/test_eiger_qa.sh
git commit -m "feat: require non-NIQ taxonomy insert logs"
```

### Task 4: Run the complete focused verification set

**Files:**
- No source changes expected.

**Interfaces:**
- Consumes: the migration from Task 1, v3 implementation from Task 2, and agent contracts from Task 3.
- Produces: evidence that the local unit and prompt contracts are coherent without adding production rows.

- [ ] **Step 1: Parse the schema migration again**

Run:

```bash
bq query --use_legacy_sql=false --dry_run "$(cat sql/migrations/008_add_non_niq_taxonomy_insert_log.sql)"
```

Expected: Standard SQL parse succeeds with no mutation.

- [ ] **Step 2: Run Python and shell focused tests together**

Run:

```bash
./.venv/bin/python -m pytest tests/non_niq/test_non_niq_qa_v3.py -q && \
bash tests/non_niq/test_non_niq_qa_v2.sh && \
bash tests/non_niq/test_susubayi_qa.sh && \
bash tests/non_niq/test_eiger_qa.sh
```

Expected: all commands pass. No network, LLM, Sheet, or production DML test is introduced.

- [ ] **Step 3: Inspect only the intended diff and commit any corrective change**

If verification exposed a defect, make the smallest correction in the owning task’s files, rerun that task’s focused test, then commit it with a message describing the corrected contract. Do not broaden scope.

## Plan Self-Review

- **Spec coverage:** Task 1 implements the single permanent table and documents it. Task 2 atomically logs v3 dictionary creations and verifies read-back. Task 3 covers every named agent-driven script, including Eiger’s QA-table taxonomy rows. Task 4 verifies migration syntax plus all focused behavior. Existing identities, re-points, filters, and skipped retries remain unlogged.
- **Placeholder scan:** Every task names its exact files, interfaces, command, expected outcome, and commit boundary. JSON examples use descriptive values only.
- **Type consistency:** The migration, v3 helper, prompt contract, and read-back all use `target_table`, `created_at`, and `row_json`; the envelope consistently uses `product_id`, `ecommerce_platform`, and `inserted_row`.
