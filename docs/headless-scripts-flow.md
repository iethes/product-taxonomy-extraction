# Headless Taxonomy Scripts — Flow & Table Reference

Companion to [`docs/headless-runbook.md`](headless-runbook.md) (the procedure both scripts implement). This
doc walks through what actually happens, step by step, when you run
[`script/headless_taxonomy.sh`](../script/headless_taxonomy.sh) (Full Rebuild) or
[`script/targeted_qa_fix.sh`](../script/targeted_qa_fix.sh) (Targeted QA Fix) — including every BigQuery table
and local file each one reads from or writes to.

**The one structural difference to hold onto:** `headless_taxonomy.sh` is a single `claude -p` call and
nothing else — every step, including its own self-QA-check, happens *inside* that one LLM session, and the
script does nothing after it returns. `targeted_qa_fix.sh` also runs one `claude -p` call, but wraps it in
deterministic bash on both sides that independently re-verifies the agent's work before anything reaches the
production overlay table — see [`docs/superpowers/specs/2026-07-17-targeted-qa-fix-script-design.md`](superpowers/specs/2026-07-17-targeted-qa-fix-script-design.md)
for why.

---

## `script/headless_taxonomy.sh` — Coverage Closer (Full Rebuild + Top-Up)

Auto-detects scenario from live state before invoking `claude -p`: if the live 95%-cumulative-GMV
(GWP-zeroed) worklist for `<TABLE>` has 0 products with no `taxonomy_id`, the script exits immediately —
no SKU claim, no LLM call, safe to re-run against any category regardless of `docs/categories/STATUS.md`.
Otherwise it picks **first-run** (0 existing `source='LLM'` `product_taxonomy_map` rows — full Pass 1/Pass 2
rebuild, shown below) or **top-up** (existing LLM rows present — closes just the live gap via
reuse-before-mint, smaller SKU block sized to the gap). The check is scoped to `source='LLM'` specifically —
pre-existing `source='HUMAN'` keyword-seed rows (the norm for most categories before Phase 5 ever runs) don't
count as prior LLM coverage and must not misroute a genuine first pass into top-up.

**Priority is coverage, not precision.** Both scenarios' prompts instruct bulk-first processing (grouped SQL
text-matching against existing/newly-built taxonomy, not one image read per product) and explicitly forbid
self-limiting to a small sample — the whole live worklist should be attempted within the session's turn
budget. Per-row quality (exact product_line wording, variant capture, pack-count edge cases) is intentionally
deprioritized here; that's `targeted_qa_fix.sh`'s job. Hard gates (G1, G2, G4, G5) are the exception — those
are structural invariants and always apply, even in a speed-first pass.

`MAX_TURNS` is an optional 3rd argument (default 300) for scaling the session budget on a large gap — e.g.
`./script/headless_taxonomy.sh shopee_th_suncare "" 800`.

```
$ ./script/headless_taxonomy.sh <TABLE> [MONTH] [MAX_TURNS]
        │
   no TABLE arg? ──yes──▶ print usage, exit 1
        │ no
        ▼
  print "<TABLE>" / "TAXONOMY EXTRACTION STARTED"
        │
        ▼
┌────────────────────────────────────────────────────────────────────────┐
│  claude -p --max-turns 300        (ONE LLM session — no wrapper logic  │
│                                     before or after this call)         │
│                                                                          │
│  Reads first: CLAUDE.md, ARCHITECTURE.md, docs/data-dictionary.md,     │
│  docs/llm-extraction-rules.md, docs/quality-standards.md,              │
│  docs/headless-runbook.md, docs/brand-extraction.md,                   │
│  docs/categories/_TEMPLATE.md, docs/categories/STATUS.md               │
│                                                                          │
│  STEP 0  verify the source table exists in master_clean_niq             │
│          (blocker if it doesn't — never falls back to another dataset) │
│  STEP 1  check existing product_taxonomy_map state — do NOT assume 0/0 │
│  STEP 2  compute the real 95%-cumulative-GMV brand scope + official-   │
│          store allowlist from master_clean_niq.<table>;                │
│          write + commit docs/categories/<table>.md                     │
│  STEP 3  claim a 2,000-slot SKU block (atomic sku_block_registry txn,  │
│          scenario='full_rebuild')                                      │
│  STEP 4  Pass 1 — build taxonomy from the Official Store Allowlist     │
│          only, not the full Mall-badged pool                           │
│  STEP 5  Pass 2 — route resellers primarily via bulk SQL text-match    │
│          against the Pass 1 taxonomy; images only where ambiguous      │
│  STEP 6  populate product_line/sub_line/variant as structured columns  │
│          (never delete any existing row — that's a separate,           │
│          deliberately manual/wrapper-side step, not done here)         │
│  STEP 7  self-check the QA gates from docs/headless-runbook.md         │
│          (dual-mapped scoped to source='LLM', placeholder-leak);       │
│          report the actual numbers, don't just assert "gates passed"   │
│                                                                          │
│  Output ONE JSON object:                                                │
│  {status, rows_created, rows_mapped, taxonomy_id_range_used,           │
│   findings, blockers}   (status='blocked' is a valid, expected outcome)│
└────────────────────────────────────────────────────────────────────────┘
        │
        ▼
  print "TAXONOMY EXTRACTION FINISHED"
```

**What the script itself does *not* do:** it never reads the JSON output, never re-runs the QA gates, never
marks a `sku_block_registry` row `FAILED_QA`, and never touches `universe_taxonomy_overlay`. All of that —
matching `docs/headless-runbook.md`'s Full Rebuild scenario steps 3–8 — is left as a separate, human-triggered
step after this script exits. This is the main thing `targeted_qa_fix.sh` (below) does differently.

### Tables & files touched

| Access | Table / file | Used for |
|---|---|---|
| Read | `sincere-hearth-273704.master_clean_niq.<table>` | STEP 0 existence check; STEP 2 brand-GMV ranking and `merchant_badge='Shopee Mall'` allowlist query |
| Read | `sincere-hearth-273704.magpie_reference.product_taxonomy_map` | STEP 1 existing-state check; Pass 2 text-matching against the Pass 1 taxonomy |
| Read | `docs/categories/STATUS.md`, `docs/categories/_TEMPLATE.md` | confirm the table isn't already done; template shape for the new category file |
| Write | `docs/categories/<table>.md` | created fresh and committed (STEP 2) — no pre-existing file is assumed |
| Write (INSERT, atomic txn) | `sincere-hearth-273704.magpie_reference.sku_block_registry` | claims a 2,000-slot block, `scenario='full_rebuild'` (STEP 3) |
| Write (INSERT, DML only) | `sincere-hearth-273704.magpie_reference.product_taxonomy` | new canonical entries from Pass 1 + Pass 2 (STEPs 4–6) |
| Write (INSERT, DML only) | `sincere-hearth-273704.magpie_reference.product_taxonomy_map` | new product→taxonomy rows from Pass 1 + Pass 2 (STEPs 4–6) |
| **Not touched** | `sincere-hearth-273704.magpie.marketshare_universe_niq`, `sincere-hearth-273704.magpie_reference.universe_taxonomy_overlay` | universe refresh is a separate step, not part of this script |

---

## `script/targeted_qa_fix.sh` — Targeted QA Fix

Scope is existing-row quality defects only (`docs/quality-standards.md` D1–D5, hard gates G1/G2/G3/G5/G6,
`brand_mismatch` review). Coverage gaps (`taxonomy_id IS NULL`) are out of scope for this script — see
`script/headless_taxonomy.sh`'s top-up scenario above.

Two modes, chosen by `has_real_brief()`: **Brief mode** executes a human-written `## Targeted QA Fix Brief`
section verbatim (original behavior). **Auto-discovery mode** (default when no real Brief exists) finds its
own work — a live, incremental review of `product_taxonomy` entries not yet confidently reviewed
(`product_taxonomy._meta`), via Tier 1 SQL regex checks (duplicate brand tokens, stub/placeholder leaks,
field-order violations, brand casing, excess content) and Tier 2 LLM judgment for what regex can't catch.

```
$ ./script/targeted_qa_fix.sh <TABLE>
        │
   no TABLE arg? ──yes──▶ print usage, exit 1
        │ no
        ▼
  resolve_category_file(TABLE)
  try docs/categories/<TABLE>.md, then docs/categories/<TABLE minus "shopee_">.md
        │
   not found? ──yes──▶ ERROR "write the category file first", exit 1
        │ found
        ▼
  build_prompt(TABLE, category_file)     [pure string-building, no side effects]
        │
        ▼
┌────────────────────────────────────────────────────────────────────────┐
│  claude -p --max-turns 30         (AGENT-SIDE — one LLM session)       │
│                                                                          │
│  Reads first: CLAUDE.md, ARCHITECTURE.md, docs/llm-extraction-rules.md,│
│  docs/headless-runbook.md, docs/quality-standards.md, and the resolved │
│  category file's '## Targeted QA Fix Brief' section (the actual scope  │
│  of this session — missing/empty section is a genuine blocker)         │
│                                                                          │
│  STEP 1  sanity-check the brief's stated current-state numbers against │
│          a live query (product_taxonomy_map counts)                    │
│  STEP 2  claim a 200-slot SKU block (atomic sku_block_registry txn,    │
│          scenario='targeted_qa_fix')                                   │
│  STEP 3  execute exactly the fixes described in the Brief section      │
│  STEP 4  write via DML only, meta_agent='CLAUDE_CODE', never delete an │
│          existing row unless the brief explicitly says to              │
│  STEP 5  does NOT touch universe_taxonomy_overlay itself               │
│  STEP 6  append a dated row to the category file's QA History table,   │
│          commit the file                                               │
│                                                                          │
│  Output ONE JSON object:                                                │
│  {status, rows_created, rows_mapped, taxonomy_id_range_used,           │
│   findings, blockers}                                                  │
└────────────────────────────────────────────────────────────────────────┘
        │
        ▼
  extract .result from the CLI's --output-format json envelope
        │
   empty / unparseable? ──yes──▶ mark_failed_qa(TABLE), exit 1
        │ no
        ▼
  decide_next_step(result_json)          (WRAPPER-SIDE — pure function, no BQ/claude)
        │
        ├─ status=blocked ────────────────▶ print blockers, exit 0
        │                                    (block stays ACTIVE — safe to reuse)
        │
        ├─ status=failed, or malformed ───▶ mark_failed_qa(TABLE), exit 1
        │
        ├─ complete/partial,
        │  rows_created=0 ────────────────▶ "nothing to gate", exit 0
        │                                    (block stays ACTIVE)
        │
        └─ complete/partial, rows_created>0
                │
                ▼
        ./script/qa_report.sh <TABLE>       (WRAPPER-SIDE — independent re-check;
        (4 gates, no --skip-coexistence:     does NOT trust the agent's self-report)
         dual-mapped, HUMAN+LLM coexistence,
         placeholder-leak, structured-fields)
                │
          exit ≠ 0? ──yes──▶ mark_failed_qa(TABLE), exit 1
                │ exit 0
                ▼
        run_universe_refresh(TABLE)
        MERGE → universe_taxonomy_overlay (sincere-hearth-273704 only, no farsight)
                │
                ▼
        "FINISHED — universe refreshed", exit 0
```

### Tables & files touched

| Access | Table / file | Used for |
|---|---|---|
| Read | `docs/categories/<table>.md` | resolved category file; agent reads its `## Targeted QA Fix Brief` section for the actual scope |
| Read (agent-side, STEP 1) | `sincere-hearth-273704.magpie_reference.product_taxonomy_map` | sanity-check the brief's stated current-state numbers |
| Write (INSERT, atomic txn, agent-side STEP 2) | `sincere-hearth-273704.magpie_reference.sku_block_registry` | claims a 200-slot block, `scenario='targeted_qa_fix'` |
| Write (DML, agent-side STEPs 3–4) | `sincere-hearth-273704.magpie_reference.product_taxonomy`, `product_taxonomy_map` | the fixes described in the brief — pack-count/size/bundle corrections, reroutes, new entries |
| Write (agent-side STEP 6) | `docs/categories/<table>.md` | appends a dated `QA History` row, commits the file |
| Read (wrapper-side, via `./script/qa_report.sh`) | `product_taxonomy_map`, `product_taxonomy` JOIN `product_taxonomy_map` | the 4 independent QA gates — dual-mapped, HUMAN+LLM coexistence, placeholder-leak, structured-fields NULL% |
| Write (UPDATE, wrapper-side `mark_failed_qa`) | `sincere-hearth-273704.magpie_reference.sku_block_registry` | sets the most recent `ACTIVE`/`targeted_qa_fix` block for the table to `FAILED_QA` on any failure path |
| Write (MERGE, wrapper-side `run_universe_refresh`, only if gates pass) | `sincere-hearth-273704.magpie_reference.universe_taxonomy_overlay` | reads from `product_taxonomy_map` JOIN `product_taxonomy`, upserts/deletes rows for `<table>` only |
| **Not touched** | `sincere-hearth-273704.magpie.marketshare_universe_niq` (no `ALTER`/`UPDATE`), any `magpie-farsight` table | overlay-table design — see the design spec's "Farsight is intentionally dropped" note |

---

## Shared conventions

Both scripts follow the same rules, inherited from `docs/headless-runbook.md`:

- **Atomic SKU claim, never `MAX(taxonomy_id)` directly** — a `BEGIN ... DECLARE next_start ... BEGIN
  TRANSACTION ... COMMIT TRANSACTION; END;` block against `sku_block_registry`, DECLARE always before BEGIN
  TRANSACTION (a real BigQuery scripting syntax error otherwise).
- **DML only, never the streaming API** — every `product_taxonomy`/`product_taxonomy_map` write is immediately
  queryable, no 90-minute streaming-buffer wait.
- **`meta_agent='CLAUDE_CODE'`** on every row either script writes.
- **Never delete an existing row** unless explicitly instructed to (Full Rebuild's HUMAN-row cleanup and
  Targeted QA Fix's brief-specified deletes are both separate, deliberate exceptions — not a default).
- **`status='blocked'` is a valid, expected outcome**, not a failure — both prompts tell the agent to stop and
  report rather than guess when something is genuinely wrong or ambiguous.

## Key difference

| | `headless_taxonomy.sh` | `targeted_qa_fix.sh` |
|---|---|---|
| SKU block size | 2,000 slots | 200 slots |
| `--max-turns` | 300 | 30 |
| Category file | created fresh by the agent | must already exist, with a `## Targeted QA Fix Brief` section |
| QA gates | self-checked *inside* the LLM session only | self-checked by the agent, then **independently re-run** by the wrapper via `./script/qa_report.sh` before anything downstream happens |
| `FAILED_QA` marking | not implemented in this script | wrapper-side, on any malformed/failed/gate-failure path |
| Universe refresh | not implemented in this script (separate manual step) | wrapper-side `MERGE` into `universe_taxonomy_overlay`, gated on the independent QA re-check passing |
