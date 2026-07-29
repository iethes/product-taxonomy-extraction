# AGENTS.md — Guide for AI Agents Collaborating on This Pipeline

This document is for Claude Code sessions, Codex agents, or any AI agent picking up work on the Marketshare Universe pipeline.
CLAUDE.md is a symbolic link to AGENTS.md

---

## Before You Do Anything

Read in this order:
1. [`ARCHITECTURE.md`](ARCHITECTURE.md) — data model and BigQuery layout
2. [`docs/data-dictionary.md`](docs/data-dictionary.md) — every table and column
3. [`docs/llm-extraction-rules.md`](docs/llm-extraction-rules.md) — mandatory extraction rules
4. The category file in [`docs/categories/shopee_th_{category}.md`](docs/categories/) for your target category

---

## Environment Setup (always run at session start)

```python
import os
os.environ['PATH'] = '/Users/magpie/google-cloud-sdk/bin:' + os.environ.get('PATH', '')

PYTHON = '/Users/magpie/.pyenv/versions/3.8.12/bin/python3'
BQ_BIN = '/Users/magpie/google-cloud-sdk/bin/bq'
CREDS_FILE = '/tmp/brand_audit_creds.json'  # copy from ~/Downloads before running
SERVICE_ACCOUNT = 'openclaw@magpie-openclaw.iam.gserviceaccount.com'

BQ_PROJECT   = 'sincere-hearth-273704'
BQ_SOURCE    = 'sincere-hearth-273704.master_clean_niq'
BQ_REFERENCE = 'sincere-hearth-273704.magpie_reference'
BQ_UNIVERSE  = 'sincere-hearth-273704.magpie'
BQ_RAW_HIST  = 'sincere-hearth-273704.raw_niq_history'
```

**ANTHROPIC_API_KEY must be set in the subprocess environment for Phase 5 LLM calls:**
```python
env = os.environ.copy()
env['ANTHROPIC_API_KEY'] = os.environ['ANTHROPIC_API_KEY']
subprocess.run([...], env=env)
```

If the API key is not in the subprocess environment, LLM calls fail silently and scripts fall back to text routing — producing generic canonical names. Always verify with a test call before running a full batch.

---

## SKU Block Management (CRITICAL)

Before inserting any new `product_taxonomy` rows, **query the current MAX immediately**:

```python
from google.cloud import bigquery
client = bigquery.Client(project='sincere-hearth-273704')
result = list(client.query(
    "SELECT MAX(taxonomy_id) as m FROM `sincere-hearth-273704.magpie_reference.product_taxonomy`"
).result())
current_max = result[0].m  # e.g. 'SKU-058455'
# next_id = int(current_max.replace('SKU-', '')) + 1
# Assign a 1000-slot block: next_id to next_id+999
```

**Never use AGENTS.md or any static file as the source of truth for the current MAX SKU.** Those notes are written at session end and may be stale if a parallel session ran in between. Query BQ directly.

See [`docs/categories/STATUS.md`](docs/categories/STATUS.md) for the current SKU allocation map — never trust a static number here, always query BQ.

---

## meta_agent Rule

Every row you write to `product_taxonomy` or `product_taxonomy_map` **must** have `meta_agent` set:
- Claude Code sessions: `meta_agent = 'CLAUDE_CODE'`
- Codex agents: `meta_agent = 'CODEX'`
- Human scripts: `meta_agent = 'HUMAN'`

Never leave `meta_agent = NULL` on new rows.

---

## Streaming Buffer Rule

BigQuery has a ~90-minute streaming buffer. After inserting rows via the Streaming API (`insert_rows_json`):
- **Do NOT query, update, or delete those rows for 90 minutes**
- Schedule cleanup scripts to run after the buffer clears
- DML-inserted rows (via `bq query`) are immediately visible and can be operated on right away

---

## QA Gates

See [`docs/quality-standards.md`](docs/quality-standards.md) §4 (Hard Gates) for the full checklist. The gates in `AGENTS.md` are a subset; `quality-standards.md` is the single source of truth.

---

## Universe Refresh Pattern

After every category insertion, refresh the overlay table. Taxonomy state lives in a separate overlay table (`magpie_reference.universe_taxonomy_overlay`), not as columns on `marketshare_universe` — see Migration 003 and `docs/headless-runbook.md` § Universe refresh for the rationale.

One MERGE handles insert, update, and stale-row cleanup atomically:

```sql
MERGE `sincere-hearth-273704.magpie_reference.universe_taxonomy_overlay` t
USING (
  SELECT m.product_id, m.platform, m.country, m.master_table,
         pt.taxonomy_id, pt.canonical_name, m.source, m.confidence, m.meta_agent
  FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt
    ON m.taxonomy_id = pt.taxonomy_id
  WHERE m.master_table = @table
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY m.product_id, m.platform, m.country
    ORDER BY CASE m.source WHEN 'LLM' THEN 0 ELSE 1 END, m.taxonomy_id
  ) = 1
) src
ON t.product_id = src.product_id AND t.platform = src.platform AND t.country = src.country
  AND t.master_table = @table
WHEN MATCHED THEN UPDATE SET
  taxonomy_id = src.taxonomy_id,
  sku_type_complete = src.canonical_name,
  taxonomy_source = src.source,
  taxonomy_confidence = src.confidence,
  taxonomy_meta_agent = src.meta_agent,
  updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED BY SOURCE AND t.master_table = @table THEN DELETE
WHEN NOT MATCHED BY TARGET THEN INSERT
  (product_id, platform, country, master_table, taxonomy_id, sku_type_complete,
   taxonomy_source, taxonomy_confidence, taxonomy_meta_agent, updated_at)
  VALUES (src.product_id, src.platform, src.country, src.master_table, src.taxonomy_id, src.canonical_name,
          src.source, src.confidence, src.meta_agent, CURRENT_TIMESTAMP());
```

Join key is `(product_id, platform, country)` — the ADR-006 composite key. The `AND t.master_table = @table` condition on `WHEN NOT MATCHED BY SOURCE` is load-bearing: without it BigQuery would delete every other category's rows too.

**Farsight variant:** same MERGE targeting `magpie-farsight.universe.universe_taxonomy_overlay`. For multi-model products, add `QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id, category_3, month ORDER BY taxonomy_id) = 1` to the src subquery.

**Tables with multi-category NIQ mapping** (e.g., `shopee_th_body_wash` maps to 6 NIQ category_3 values): Use the NIQ join in src subquery — do NOT hardcode `category_3 = '...'`.
---

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| `bq` not found | Use full path `/Users/magpie/google-cloud-sdk/bin/bq` |
| Wrong Python | Use `/Users/magpie/.pyenv/versions/3.8.12/bin/python3` |
| Credential not found | `cp "/Users/magpie/Downloads/Magpie OpenClaw.json" /tmp/brand_audit_creds.json` |
| API key not set in subprocess | Pass `env=env` with `ANTHROPIC_API_KEY` set — never rely on `os.environ['ANTHROPIC_API_KEY']` alone |
| SKU collision | Always query `MAX(taxonomy_id)` from BQ immediately before first insert |
| Farsight DML error "must match at most one source row" | Add `QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id, category_3, month) = 1` to src subquery |
| Multi-category refresh misses rows | Use NIQ join in src subquery, not `category_3 = '...'` hardcode |
| Generic canonical names everywhere | API auth error → text fallback. Verify API key is in subprocess env |
| `merchant_badge = 'Mall'` | Wrong — it's `merchant_badge = 'Shopee Mall'` |
| `ecommerce_platform = 'shopee'` | Wrong — it's `'Shopee'` (capital S) |
| bq CLI `--file` flag | bq CLI doesn't support `--file` for stdin. Use: `echo "SELECT..." \| bq query --nouse_legacy_sql` |
| Wrong GROUP BY in reroute query | `GROUP BY product_id` ONLY — not (product_id, taxonomy_id, confidence). Otherwise a product with N existing map rows generates N new rows. |
| Canonical name has "(N packs of M)" suffix | Use `x{TOTAL}` only. Strip via `REGEXP_REPLACE(canonical_name, r" \(\d+ packs of \d+\)$", "")` |
