# Claude Code Headless Mode (`claude -p`) — Unattended Execution

Companion to [`cheaper-reliable-execution-model.md`](cheaper-reliable-execution-model.md) and [`traditional-ml-execution-model.md`](traditional-ml-execution-model.md). Those two docs assumed Claude Code categorically can't run unattended on a server — that's not quite right, and this doc corrects it, then works out what running unattended actually requires.

**Revision note:** an earlier version of this doc scoped headless use to one specific scenario (an occasional, read-only category audit) and treated the high-volume, write-capable pipeline as a "bad fit." That was wrong as a categorical claim — see "Where it fits" below. Headless `-p` is viable for any workload in this pipeline; what varies is how much deterministic scaffolding has to sit around the call, not whether the call can happen unattended at all.

## Correction to the earlier premise

`claude -p "<prompt>"` (print/headless mode) **is** officially documented for unattended, scripted use — CI/CD and cron are explicitly called out as supported use cases. It runs the full agentic loop (multi-turn, tool calls, live BigQuery access) with no human present, and exits when the task finishes or `--max-turns` is hit.

Relevant flags for unattended use:

| Flag | Purpose |
|---|---|
| `-p "<prompt>"` | Run to completion, non-interactive, exit |
| `--output-format json` | Structured, parseable result (`stream-json` for long tasks) |
| `--permission-mode bypassPermissions` | Skip approval prompts (nothing to approve — no human is watching) |
| `--max-turns N` | Hard cap on the agentic loop |

So "can't automate Claude Code on a server" was overstated. The real question — addressed below — is what shape a headless invocation needs to take for a given workload, not whether it can run unattended.

## Billing changed recently — factor this in

As of **2026-06-15**, headless `claude -p` runs against a **separate API-rate credit pool**, not the interactive subscription's general usage: Pro $20/mo, Max 5x $100/mo, Max 20x $200/mo. Two things are **not confirmed** (not stated in current docs, don't assume either way):
- Whether headless runs get Batch API's -50% discount.
- Whether Claude Code's internal prompt caching matches the ~90%-cheaper hand-rolled caching design in `cheaper-reliable-execution-model.md`.

Until measured, don't carry that doc's cost table over to `-p` runs — re-measure separately.

## Where it fits

Headless `claude -p` is viable across the whole pipeline — occasional read-only category checks and the
high-volume, write-capable extraction/routing workload alike, including the category-level session scenarios
(full rebuild, targeted fix) covered in
[`docs/plans/headless-taxonomy-runbook-design.md`](plans/headless-taxonomy-runbook-design.md). What differs
between workloads is invocation shape, not eligibility.

**Occasional, read-only, judgment-heavy checks** — the clearest case, still worth calling out on its own:

```
claude -p, scoped per category, occasional (cron)
Sample top-N by GMV → assess current taxonomy mapping → decide:
patch | fresh_run | healthy → output JSON
```

Infrequent (per category, weekly/monthly — not per product), genuinely judgment-heavy (deciding "does this
category need a full rerun" isn't a bounded rule), and cheap at this scale (50 products, one category, one run)
regardless of the unconfirmed Batch/caching questions above.

**High-volume, write-capable extraction (~1.2M products)** — also viable headless, but not as one big free-text
`-p` call per product. The constraints below are about *how* to invoke `-p` at this volume, not reasons to
exclude this workload from headless operation:

- **Cost**: every `-p` invocation pays agentic-loop overhead (tool round trips, context re-reads) even for
  steps meant to be $0 — exact brand match, regex size extraction. Don't route those through `-p` per product;
  keep them as plain deterministic code (per `traditional-ml-execution-model.md`), and reserve `-p` calls for
  the genuinely judgment-heavy step (disambiguation, structured extraction).
- **Reliability**: schema-force the output of any `-p` call feeding a downstream decision. Free-text output
  choosing what to do next reintroduces the wrong-but-plausible-answer risk that bounded/deterministic steps
  exist to avoid — that property has to be preserved by keeping those steps as code, not by keeping `-p` away
  from the pipeline entirely.
- **Unconfirmed economics at scale**: the -50%/-90% cost stack in `cheaper-reliable-execution-model.md` assumes
  direct API control (Batch submission, manual cache-control headers) that `-p` may not expose the same way —
  re-measure rather than assume it holds at high volume.

**The pattern that resolves this**: a deterministic wrapper handles the mechanical, high-volume, or
collision-prone steps (BQ lookups, ID allocation, QA gates, refresh DML) in plain code around the call, and
`-p` is invoked narrowly for the judgment-only step, schema-forced output required.
[`docs/plans/headless-taxonomy-runbook-design.md`](plans/headless-taxonomy-runbook-design.md) applies exactly
this pattern to category-level session scenarios (Full Rebuild, Assessment Only, Targeted QA Fix) — same shape,
one level up from per-product extraction steps. This generalizes: `-p` is viable for any step in the pipeline
as long as each invocation stays scoped to the judgment step, with deterministic/schema-checked scaffolding
around it.

## Recommendation

| # | Recommendation | Feasibility | Difficulty | Cost |
|---|---|---|---|---|
| 1 | Adopt `claude -p` for occasional, read-only category audits (script below) | High | Low | $ |
| 2 | Provision a **separate read-only** GCP service account for audit runs (BigQuery Data Viewer only) — do not reuse the write-capable `openclaw@...` account | High | Low (one-time IAM setup) | $0 |
| 3 | Audit output is JSON-only, decision + `proposed_patch_sql`; **never** let a read-only audit run execute UPDATE/INSERT — this is a rule about this specific scenario's scope, not a limit on headless mode generally (see `headless-taxonomy-runbook-design.md` for the write-scenario case) | High | Low | $0 |
| 4 | Audit patch application stays a separate, human-reviewed step (existing interactive Claude Code flow or a small apply script) | High | Low | $0 |
| 5 | For the high-volume bulk runtime, keep the deterministic/embedding/Batch-API steps from `traditional-ml-execution-model.md` as plain code — invoke `-p` only for the judgment-only step (schema-forced output), not as a free-text loop deciding what happens next | High | Medium | avoids re-inflating cost |
| 6 | Before trusting `-p` economics at any scale beyond a handful of categories/products, measure actual token/turn cost per run and confirm (or rule out) Batch/caching access in headless mode — applies to the occasional audit case and to any judgment-only step in the bulk pipeline alike | Medium | Low | $ (one measurement pass) |

## Reference implementation

```bash
#!/usr/bin/env bash
# scripts/audit_category.sh <table> [gmv_month]
set -euo pipefail
TABLE="$1"
MONTH="${2:-$(date +%Y-%m-01)}"
OUT_DIR="audits/${TABLE}"
mkdir -p "$OUT_DIR"

GOOGLE_APPLICATION_CREDENTIALS=/tmp/audit_readonly_creds.json \
claude -p --output-format json --permission-mode bypassPermissions "
Quality assessment for ${TABLE} — sample top 50 products by GMV ${MONTH}, review current taxonomy mapping.
Run the existing brand-match / size-extraction / embedding-match / clustering / classification / structured-extraction
cascade documented in traditional-ml-execution-model.md as an assessment pass. If confidence stays low, flag for human QA.
Output ONLY this JSON, nothing else: {category, decision: patch|fresh_run|healthy, confidence, findings: [...], proposed_patch_sql: null|string}.
Do NOT run any UPDATE/INSERT/DELETE. Read-only assessment only — patching happens in a separate reviewed step.
" > "${OUT_DIR}/$(date +%Y-%m-%d).json"
```

```
# crontab — one line per category, staggered
0 6 * * 1 /path/to/scripts/audit_category.sh shopee_th_softdrink
0 6 * * 2 /path/to/scripts/audit_category.sh shopee_th_body_wash
```

Read-only enforcement is the service account's IAM role, not `bypassPermissions` — that flag only skips interactive prompts, it has no bearing on what the credential is allowed to do in BigQuery.

This reference implementation is the **read-only audit** case specifically. For the write-capable case
(category-level full rebuild and targeted fixes, judgment-only `-p` calls wrapped in deterministic
claim/gate/refresh scaffolding), see
[`docs/plans/headless-taxonomy-runbook-design.md`](plans/headless-taxonomy-runbook-design.md) — same pattern,
different credential (write-capable), different wrapper (claim + QA gates + refresh instead of read-only
sampling).

## What's still unverified

- Actual token/turn cost of a real read-only audit run (worked example above is illustrative, not measured).
- Whether `-p` headless runs get Batch API or comparable caching economics — don't assume either.
- The read-only service account referenced in the script doesn't exist yet — needs to be created in GCP before this is runnable, not something to script around.
- Actual token/turn cost of a judgment-only `-p` call within the bulk pipeline, at per-product volume — not
  measured; don't assume it scales the same way the occasional, low-volume audit case does.
