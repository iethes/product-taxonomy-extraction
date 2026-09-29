# Design: Non-NIQ Taxonomy Insert Log

**Status:** approved for planning  
**Date:** 2026-09-23

## Problem

Non-NIQ taxonomy dictionaries have two sources of truth: BigQuery and category Google Sheets. A one-way Sheet-to-BigQuery sync can replace a dictionary table without first preserving recently inserted rows. The inserted taxonomy then disappears from BigQuery.

## Decision

Create one durable, append-only BigQuery table:

```text
sincere-hearth-273704.magpie_reference.non_niq_taxonomy_insert_log
```

Schema:

| Column | Type | Meaning |
|---|---|---|
| `target_table` | `STRING` | The full BigQuery table that received the taxonomy row. |
| `created_at` | `TIMESTAMP` | Timestamp of the committed log event. |
| `row_json` | `JSON` | Originating product context and exact inserted target row. |

Partition by `DATE(created_at)`. Do not configure expiration. The table is append-only: this feature introduces no update, deletion, deduplication, replay worker, or per-category log table.

`row_json` always uses this shape:

```json
{
  "product_id": "<originating worklist product ID>",
  "ecommerce_platform": "<originating raw platform>",
  "inserted_row": {
    "<exact committed target-table columns>": "<values>"
  }
}
```

The envelope records provenance even when a category dictionary table does not contain `product_id` or platform columns. `inserted_row` remains a complete snapshot of the row written to `target_table`.

## Scope

The log records only genuinely new taxonomy rows:

- `script/non_niq/non_niq_qa_v2.sh`: new `{dataset}_dict` rows.
- `script/non_niq/non_niq_qa_v3.py`: new `{dataset}_dict` rows.
- `script/non_niq/susubayi_qa.sh`: new `susubayi` dictionary rows.
- `script/non_niq/eiger_qa.sh`: new `eiger.product_id_dict_image_qa` fixed-taxonomy rows; Eiger has no free-text dictionary table.

Existing-identity matches, re-points, filtered products, unconfident decisions that create no target row, and retries that skip an already existing target row produce no log record.

## Atomic write contract

Each eligible target insert and its log record MUST commit in the same BigQuery transaction:

```text
BEGIN TRANSACTION
  insert a new taxonomy target row
  insert its non_niq_taxonomy_insert_log row
COMMIT TRANSACTION
```

If either operation fails, the transaction rolls back. A successful target insertion therefore cannot exist without its durable log row.

`non_niq_qa_v3.py` extends its existing chunk transaction and read-back validation. The other three scripts remain agent-driven, but their prompts require this exact transaction contract and post-commit read-back. No shared helper or background process is added.

## Failure handling

- A failed target or log insert rolls back both writes.
- The product remains unresolved or blocks the run according to the existing script contract; the agent MUST NOT retry the log separately.
- A commit is accepted only after read-back confirms both the target row and a matching log row.
- BigQuery DML remains the only write mechanism. Streaming inserts are forbidden.

## Implementation files

- Add `sql/migrations/008_add_non_niq_taxonomy_insert_log.sql`.
- Update `script/non_niq/non_niq_qa_v3.py` transaction construction and commit verification.
- Update the insert contracts in:
  - `script/non_niq/non_niq_qa_v2.sh`
  - `script/non_niq/susubayi_qa.sh`
  - `script/non_niq/eiger_qa.sh`

## Verification

- Extend focused v3 tests: new dictionary writes create one matching log record in the same transaction; existing identities create neither target nor log rows.
- Extend focused Bash tests: every agent-driven script prompt requires atomic target-and-log DML and post-commit log read-back.
- The migration is schema-only. Do not insert production smoke rows solely to test it.
