# Cheaper, Faster, More Reliable Than Interactive Claude Code — Is It Possible?

> Follow-up to [`docs/taxonomy-pipeline-improvement-recommendations.md`](taxonomy-pipeline-improvement-recommendations.md).
> That doc assumed the current execution model (interactive Claude Code sessions).
> This doc questions the execution model itself.

---

## The question as posed vs. the question that matters

The framing was: *"Claude Code works but can't be automated; a plain API script can be automated but works worse; both options are expensive."* That's a real observation, but it sets up a false choice — Claude Code (interactive, unautomatable) vs. a naive API script (automatable, worse). There's a third option that's cheaper than both and more reliable than the script you tried: **rebuild the specific things that made Claude Code work, using API-native building blocks that are deployable, batchable, and cheap.**

Claude Code isn't a special model — it's Sonnet/Opus plus four things your script almost certainly didn't have:

| What Claude Code has | What it does for this pipeline |
|---|---|
| **Live tool use against BigQuery** | Checks `MAX(taxonomy_id)`, existing taxonomy entries for a brand, before deciding match-or-create |
| **Full domain context loaded** | `AGENTS.md`, `llm-extraction-rules.md`, the per-category `docs/categories/*.md` file — all in context, every call |
| **Free-text generation, no schema** | Nothing stops it from writing `"Undefined"` into a slot — same risk your script has |
| **A human watching** | The interactive session's "measure → triage → fix" loop (`docs/quality-standards.md`) catches errors like the ones you found, because someone is reading the output |

A one-shot Python script calling the API almost certainly dropped #1 and #2 (thinner prompt, no live DB lookup) and definitely dropped #4 (nobody's watching). That's why it was "way worse" — it wasn't a fair fight between "Claude Code" and "the API," it was a fight between a fully-provisioned agent and a bare LLM call.

`★ Insight ─────────────────────────────────────`
This is a common trap: comparing an interactive coding agent to a naive script convinces people the agent has some irreproducible magic, when usually the gap is entirely in *scaffolding* — retrieval, tool access, structured output, and verification — not the model. Once you rebuild the scaffolding with API primitives, the gap mostly closes, and you gain the thing interactive sessions can never give you: determinism and unattended operation.
`─────────────────────────────────────────────────`

---

## The core redesign: you probably don't need an "agent" at all

The match-or-create decision (`docs/product-lifecycle.md §4`) *looks* like it needs an agent — "check if this exists, then decide" sounds like a tool-calling loop. It doesn't. Split it into two halves that don't need to talk to each other mid-call:

```
┌─────────────────────────────────────────────────────────────────┐
│  YOUR HARNESS (plain Python — cheap, deterministic, no LLM)     │
│                                                                   │
│  1. Resolve brand_id (already done — Stages 02-03, string match) │
│  2. Query BigQuery: existing product_taxonomy candidates for     │
│     this brand_id + category (a handful of rows, not millions)   │
│  3. Build ONE prompt: static cached rules + candidate list +     │
│     this product's image + sku_name                              │
└──────────────────────────────┬────────────────────────────────────┘
                                │  single call, no back-and-forth
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  ONE Claude call, forced JSON schema (output_config.format)      │
│  Returns: {action: "match"|"create"|"unresolved",                │
│            taxonomy_id: string|null,                             │
│            product_line: string|null, size: string|null,         │
│            pack_count: integer|null, brand_from_image: string}   │
└──────────────────────────────┬────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  YOUR HARNESS applies the decision — INSERT/UPDATE BigQuery       │
│  using the SKU-block pre-allocation pattern already in AGENTS.md │
└─────────────────────────────────────────────────────────────────┘
```

The "does this exist already" lookup — the part that made you reach for an agent — is a SQL query. Your harness runs it before the LLM call, not the LLM. This turns a multi-turn agentic loop into **one batchable, cacheable, schema-enforced call per product**. That's the whole trick: you don't need Claude Code, Managed Agents, or any agent framework for the bulk of the work — you need a well-engineered single-call pipeline.

### This directly fixes the bug you found

`sku_type_complete = "No Brand Washing Machine Undefined Undefined"` is a free-text-generation failure. With `output_config.format` (or `strict: true` tool use) forcing a JSON schema where `size` and `product_line` are typed as `string | null`, the model has no way to write the word `"Undefined"` into those fields — it either returns a real string or `null`, and your harness builds the canonical name by joining only the non-null parts. This isn't a prompting fix, it's a structural one: the failure mode is no longer representable.

---

## The cost stack — three levers, all compatible with each other

### 1. Batch API — 50% off, built for exactly this job

Async, up to 100,000 requests or 256MB per batch, most complete within an hour (max 24h), results kept 29 days. Every feature you need works inside it: vision, tools, structured outputs, prompt caching. For 1.2M products that's ~12 batches — run them overnight, poll in the morning. This is a much better fit than real-time calls for a pipeline that's already run in discrete category-by-category passes, not live traffic.

### 2. Prompt caching — the big one, given your prompt shape

Your rules content (`docs/llm-extraction-rules.md`, per-category context) is large, static, and identical across every call in a category. That's the textbook case for caching: cache reads cost **~10% of base input price**; cache writes cost 1.25× (5-min TTL) or 2× (1-hour TTL) once. Put the static rules + category context in the `system` block with a `cache_control` breakpoint; put the varying image + sku_name after it. Every call after the first in that category reads the rules at 90% off.

**Caveat worth checking, not assuming:** cache TTL tops out at 1 hour; Batch API jobs can take up to 24h. If a batch is large enough to spread across many hours, calls late in the batch may miss the cache and re-pay the write cost. Verify actual hit rate via `usage.cache_read_input_tokens` in the batch results rather than assuming it — if hit rate is low, splitting into smaller, faster-processing batches (or re-warming the cache mid-batch) recovers most of the savings.

### 3. Tiered model routing — you already do this for brand; extend it to taxonomy

`docs/data-dictionary.md` shows brand resolution already uses a cheap-first cascade (BRAND_FIELD/PRODUCT_NAME_SCAN string matching resolves 75–90% of products with zero LLM calls). Phase 5 taxonomy extraction doesn't have an equivalent cheap tier — every product goes through the expensive multimodal path. Two concrete splits:

- **Size/pack from text alone** (the bug you found): a cheap regex pass, or Haiku 4.5 (**$1/$5 per 1M tokens** vs. Sonnet's $3/$15) for a text-only call, before ever touching an image. Recommendation 4 in the prior doc already proposed this — it's now clearly the cheap tier this pipeline is missing.
- **Multimodal decision** (brand-from-image, product line, match-or-create): stays on Sonnet — the existing ADR-005 already documented that Haiku was unreliable for Thai text + image disambiguation, and that reasoning holds. This is genuinely the tier that needs the stronger model.

### Worked example (illustrative — re-run with your real prompt sizes)

Assume: 5,000-token static rules block (cached), ~1,650 tokens of variable input per product (sku_name + one product image at standard resolution), ~150 tokens of structured JSON output, Sonnet pricing ($3/$15 per 1M).

| Setup | Input cost/call | Output cost/call | Total/call | × 1.2M products |
|---|---:|---:|---:|---:|
| Naive real-time, no caching | $0.0200 | $0.0023 | $0.0222 | **~$26,600** |
| + prompt caching | $0.0065 | $0.0023 | $0.0087 | **~$10,400** |
| + Batch API (50% off) | $0.0032 | $0.0011 | $0.0044 | **~$5,200** |

That's a ~5x reduction from stacking caching + batch alone — before even counting the tiered-routing win of skipping the multimodal call entirely for products a cheap text pass can already resolve. And note: **1.2M is very likely an overcount of what actually needs the expensive call.** Per `docs/quality-standards.md §2`, the in-scope set for full extraction is top-95%-GMV products plus official-store listings — a fraction of total catalog, which is why `product_taxonomy_map` sits at ~140K rows today, not 1.2M. Route by that same scope definition and the real multimodal-call volume — and cost — drops further.

---

## Deployment — you don't need Claude Code running anywhere

None of the above needs the Claude Code CLI, a Claude Code subscription, or an interactive session. It's:

- A Python service using the Anthropic SDK (`anthropic.Anthropic()`), calling BigQuery via `google-cloud-bigquery` (already what the pipeline's scripts do per `AGENTS.md`)
- Batch requests submitted via `client.messages.batches.create(...)`, polled, results applied
- Run on whatever you already use for scheduled jobs — cron, Airflow, Cloud Run Jobs, GitHub Actions on a schedule. Nothing here needs an interactive terminal or a monthly seat license.

**If you want a hosted, managed version of "an agent with tools, running on a schedule"** — Anthropic's Managed Agents product does exist for this: you define a persisted Agent (model, system prompt, tools) once, then either start Sessions per run or set up a scheduled **Deployment** that fires a session on a cron cadence automatically, with no human present. This is the closest thing to "Claude Code, but headless and automatable" if you decide you genuinely need live agentic tool use rather than the harness-does-the-lookup design above. Given the analysis in this doc, **we don't think you need it for the bulk extraction** — reserve it (or a similar bespoke tool-loop) for the smaller, genuinely open-ended slice: QA triage review of flagged D1 Tier-C/D6-NULL products, where a human-in-the-loop-style judgment call is actually needed.

---

## Recommendations

| # | Recommendation | Feasibility | Difficulty | Cost impact |
|---|-----------------|:---:|:---:|:---:|
| 1 | Split match-or-create into harness-side BQ lookup + single structured LLM call (no agent loop) | High | Medium | Enables everything below |
| 2 | Force JSON schema output (`output_config.format`) — eliminates placeholder-leakage structurally | High | Low | $ (fixes Rec. 1 from the prior doc at the API level, not just the prompt level) |
| 3 | Move the bulk extraction workload onto Batch API | High | Low–Med | **−50%** on all token cost |
| 4 | Cache the static rules/category-context block | High | Low | **−~90%** on the cached portion of input cost |
| 5 | Add a cheap text-only tier (regex → Haiku) for size/pack before any multimodal call | High | Low–Med | Cuts multimodal call volume; Haiku is 3× cheaper than Sonnet per token when it is used |
| 6 | Scope the multimodal pass to the documented in-scope set (top-95% GMV + official stores), not the full catalog | High | Low | Cuts call *volume*, independent of per-call savings above |
| 7 | Automate the D1–D6 QA gates from `quality-standards.md` as code, run after each batch | High | Medium | Replaces the "human watching an interactive session" reliability factor with a repeatable check |
| 8 | Reserve an agent (Managed Agents or a bespoke tool loop) only for QA triage / ambiguous-case review | Medium | Medium | Small slice of volume — expensive-per-call is fine here because volume is low |

### Why this is more reliable, not just cheaper

The reliability gap you saw wasn't "API worse than Claude Code" in general — it was specifically: no schema enforcement (→ `"Undefined"` leaks), and no automated verification (→ nobody caught it until this scan). Recommendations 2 and 7 close exactly those two gaps with code, not with a person watching a terminal — which means the fix holds at 1.2M products the same way it holds at 12.

---

## What to verify before committing

- **Re-measure your actual prompt token counts** with `client.messages.count_tokens(...)` against your real system prompt and a real product image — the worked example above uses assumed numbers.
- **Confirm cache hit rate inside a real batch run** via `usage.cache_read_input_tokens` rather than assuming the 90% figure holds across a multi-hour batch.
- **Prototype the schema-enforced single-call design on one already-completed category** (e.g. `th_body_wash`, which has full LLM extraction and a scorecard in `docs/categories/STATUS.md`) and compare its D1–D6 scores against the existing Claude-Code-produced results before rolling out further — that's your apples-to-apples reliability check.
