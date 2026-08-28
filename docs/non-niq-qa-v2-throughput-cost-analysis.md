# non_niq_qa_v2.sh vs. headless_taxonomy_v2.sh — Why One Does 300 and the Other Does 2000

> Companion to [`docs/cheaper-reliable-execution-model.md`](cheaper-reliable-execution-model.md) (same underlying
> insight — agent cost is a scaffolding problem, not a model problem — applied here to two *already-agentic*
> scripts instead of "agent vs. plain API script").

## TL;DR

Both scripts hand a worklist to `claude -p --max-turns 300`. The gap isn't the model, the turn limit, or the
worklist size — it's what one "turn" is spent *doing*:

| | `non_niq_qa_v2.sh` | `headless_taxonomy_v2.sh` |
|---|---|---|
| Unit of work | **1 product** | **1 brand+line group** (can hold 1–hundreds of products) |
| Vision read | **Mandatory, every product** (STEP 2a) | **Exception only**, when text is genuinely ambiguous |
| Candidate retrieval | In-session Meilisearch call (STEP 1) | Pre-computed **before** `claude -p` even starts, baked into the prompt |
| New-entry grounding | Per-column `SELECT DISTINCT` **per new row** | Per-**group**, bulk `INSERT`/`UPDATE` covering every matching product |
| ID allocation | Per-row DML on the dict table | **One** atomic SKU-block claim per session, regardless of product count |
| Explicit instruction | "For each product in the worklist, in order" (STEP 2) | *"Do NOT process the live worklist one product at a time"* (STEP 1) |

Turns scale with **decisions**, not **products**. `non_niq_qa_v2.sh` makes one decision per product, always
vision-grounded. `headless_taxonomy_v2.sh` makes one decision per *group*, and real catalogs cluster heavily by
brand+line+pack-variant — group count is a small fraction of product count. That ratio is the entire reason
2000 fits where 300–500 doesn't.

---

## 1. The fundamental difference, with receipts

### 1a. Mandatory per-product vision read

`non_niq_qa_v2.sh` STEP 2a is unconditional:

> "This judgment is MULTIMODAL — you must actually LOOK at the product image... Do this BEFORE making any
> relevance / brand / sku_type judgment for the product."

Every single worklist row costs one `curl` + one `Read` of an image, no exception path. Vision tokens are the
most expensive token class per unit of signal — this alone is likely the single largest per-row cost driver.

`headless_taxonomy_v2.sh`'s top-up prompt (STEP 1c) inverts this:

> "Only read an individual product's image when text signals... are genuinely insufficient... look for other
> unresolved worklist rows with a similar sku_name pattern and batch them under the same new entry rather than
> reading and minting one at a time."

Most products are routed by **text matching against pre-attached candidates**, never touching vision at all.

### 1b. Per-row BigQuery round-trips vs. bulk SQL

`non_niq_qa_v2.sh`'s new-dict-entry path (STEP 2c, "NO" branch) is a sequential chain, once per product that
needs it:
1. Read `dict_patterns/${dataset}.json`
2. `SELECT DISTINCT <column>` — once per attribute column that needs grounding (susububuk_dict alone has 29
   columns; lighting_dict, cookiesbiscuit_dict etc. each have their own width)
3. `INSERT` the new row
4. A follow-up `SELECT` to verify no column came back `NULL` ("never trust bq's affected rows report")
5. Fix any `NULL` found, grounded the same way
6. A separate write to `qa_table` pointing at the new entry

None of this is batched across products — even two worklist products that turn out to need the *same* new
entry each walk this chain independently, because the prompt frames the loop as "for each product... in
order," not "group first, then decide."

`headless_taxonomy_v2.sh`'s top-up STEP 1a/1b is explicit about the opposite:

> "group worklist products by their matched candidate's taxonomy_id and write ONE UPDATE/INSERT per
> taxonomy_id covering every matching product, never per-row"
> "mint ONE new taxonomy entry per group, mapping every matching product to it in one bulk statement"

### 1c. Candidate retrieval: in-session vs. pre-computed

`non_niq_qa_v2.sh` STEP 1 still runs a live batch call *inside* the session
(`non_niq_helper.py retrieve`) and then reads the output file back — a real round trip, even though it's
correctly batched to one call for the whole worklist.

`headless_taxonomy_v2.sh` skips this category of cost entirely: `headless_v2_worklist.py` computes up to 5
ranked candidates per product (including cross-market fuzzy matches from sibling category tables in other
countries) **before `claude -p` is invoked at all**, and the result is embedded directly as `${worklist_json}`
in the prompt text. Zero in-session retrieval turns, at any worklist size.

### 1d. SKU/ID allocation

`headless_taxonomy_v2.sh` claims one atomic block (`BEGIN TRANSACTION ... COMMIT`) **once per session**,
sized to the scenario (2000 for first-run, `gap_count` clamped to 200–2000 for top-up) — a fixed cost
independent of how many products are actually processed. `non_niq_qa_v2.sh` has no equivalent block-claim
step; each dict-table insert and each qa-table write is its own DML statement, so this cost *does* scale with
row count (though it's a cheap one relative to vision + grounding).

---

## 2. How many products can one `non_niq_qa_v2.sh` session actually finish?

**Corrected against real measured usage (superseding an earlier, wrong estimate in this doc's first draft):**
a session usually finishes the **full ~300-product worklist**, and turn budget is **not** the binding
constraint — sessions consistently land in the **10–100 turns** range out of the 300 available, nowhere close
to exhausting it. All sessions take roughly the same **20–30 minutes** wall-clock, largely independent of how
many turns were actually used.

This means the earlier draft's per-path turn-cost model (curl+Read+grounding-chain arithmetic, landing on
"15–120 products, turn-limited") was a reasoned model built from the prompt text alone, and it was wrong —
real sessions aren't turn-starved. Two things follow from that:

- The architectural gap in §1 (mandatory vision, per-row grounding queries, in-session retrieval, per-row DML)
  is real and still explains *why* `headless_taxonomy_v2.sh` gets more product-coverage per unit of session
  budget — it just shows up almost entirely as **$ cost per product** and **turn headroom left unused**, not
  as a practical risk of `non_niq_qa_v2.sh` running out of turns mid-worklist at current worklist sizes
  (300–500 rows).
- Something *other* than the agentic reasoning/turn loop is setting the ~20–30 minute floor per session, since
  turn count varies 10x (10–100) while wall-clock barely moves. The likely candidates, in rough order of
  suspicion, are network I/O for the ~300 sequential-ish image downloads (STEP 2a's `curl`), BigQuery
  round-trip latency on the many small per-product/per-column queries (§1b), and fixed session startup/model-load
  overhead. This is worth profiling directly (timestamp the curl calls vs. the BQ calls vs. everything else) if
  squeezing more sessions into a 5-hour window becomes the goal — see §3.

To sanity-check a specific run: compare `num_turns` in the result JSON against the 300 budget (should be well
under), and sum `rows_qa_confirmed + rows_qa_unconfident + rows_filtered` against `worklist_count` from the
"Worklist materialized: N rows" log line (should be at or near equal, given completion is now the norm, not
the exception).

---

## 3. How many products fit in a 5-hour Claude Code window?

**Empirically measured, per-worker:** 300 minutes ÷ ~20–30 min/session ≈ **10 sessions/window**, each finishing
~300 products (§2) →

> **1 worker ≈ 10 sessions × 300 products ≈ 3,000 products per 5-hour window.**

This is a directly measured number, not a Fermi estimate — it supersedes the earlier, unverified $-budget
planning table this section originally had (an educated guess at the $200 Max plan's 5-hour $-equivalent
budget, since Anthropic doesn't publish one). The operationally useful ceiling turned out to be a **concurrent-
worker limit observed directly against the account**, not a dollar figure:

> **Parallel workers: 2 is the practical ceiling.** Running 2 concurrent `non_niq_qa_v2.sh` sessions works;
> pushing to more workers starts hitting the account's usage limit. This makes 2 the recommended cap, not a
> conservative guess — going beyond it has been observed to start throttling rather than adding throughput.

At the ceiling: up to **~6,000 products/5-hour window across 2 workers** — treat this as an optimistic upper
bound rather than a guaranteed 2×, since "starts to hit the limit" at 2 workers means the second worker's
sessions may occasionally get throttled or interrupted rather than running completely clean. In practice,
expect somewhere between 3,000 (if the second worker is frequently limited) and 6,000 (if it mostly isn't).

Going past 2 parallel workers is not recommended based on current observation — it burns through the shared
5-hour usage pool faster without a corresponding gain in completed sessions, and increases the chance any given
session gets interrupted mid-run.

**For comparison, `headless_taxonomy_v2.sh`** processes up to 2000 products in the *same* 300-turn budget by
collapsing per-product decisions into per-group ones (§1). If a real catalog's 2000 in-scope products cluster
into, say, 100–300 distinct brand+line groups, that's roughly 0.1–0.5 turns/product for the bulk-matched
majority — one to two **orders of magnitude** more turn-efficient than `non_niq_qa_v2.sh`'s per-product model,
and correspondingly cheaper per product processed (far fewer vision reads, no per-row grounding queries).

---

## 4. Why the cost is high, the gotchas, and how to improve it

### Gotchas (concrete, tied to the code)

| # | Gotcha | Where |
|---|---|---|
| 1 | Vision read is unconditional — every product, no cheap text-only exception path | STEP 2a |
| 2 | New-entry grounding queries scale with dict-table width, per new row (susububuk_dict: 29 columns) | STEP 2c, Step B |
| 3 | No cross-product batching even when several worklist rows resolve to the same new/existing entry | STEP 2 framing ("for each product... in order") |
| 4 | Candidate retrieval happens in-session, not pre-computed like `headless_v2_worklist.py` | STEP 1 |
| 5 | Unconfident retries reprocess the **same product with full multimodal effort again** in a future session — a hidden 2× vision cost on any product that flip-flops | STEP 2d |
| 6 | Turn budget (300) is generously oversized for actual usage (real sessions land at 10–100) — this isn't a problem in itself, but it means the ~20–30 min/session wall-clock floor is coming from somewhere *other* than the agentic loop (image I/O, BQ round-trips, or fixed overhead — see §2), and that's the thing worth profiling if more sessions/window is the goal, not turn count | observed, §2 |
| 7 | A session can report `status: complete` while only ever having a tiny worklist to work with — the real `susububuk/tiktok` example (`Confirmed:1\|Unconfident:1\|Created:1`) had just 2 eligible products that day. Throughput in that case is bottlenecked by *available worklist* (how many products are still unresolved), not session capacity — worth distinguishing from a genuinely under-provisioned run when reading a "complete" result | `worklist_query()`, result JSON |

### How to improve — in order of leverage

| # | Change | Why it helps | Effort |
|---|---|---|---|
| 1 | **Bulk-first restructure of STEP 2**, mirroring `headless_taxonomy_v2.sh`'s STEP 1(a)-(d): group worklist products by sku_name/brand pattern *before* the per-product loop; batch-write obvious re-points/creates; reserve full per-product 2a–2d only for genuinely ambiguous rows | Directly copies the pattern already proven to give headless its throughput edge — highest single lever | Medium |
| 2 | **Pre-compute dict-attribute grounding once per session** (not per new row) — have `non_niq_helper.py` run all the category's `SELECT DISTINCT <column>` queries up front and bake the results into the prompt, the same way `headless_v2_worklist.py` pre-fetches candidates | Eliminates the single most expensive per-row cost chain (§1b) entirely | Low–Medium |
| 3 | **Add a text-only exception path before vision** — skip the mandatory image read when `sku_name` + `item_description` + `product_attributes_attrs` already unambiguously match an existing dict entry (mirrors headless's STEP 1c) | Cuts the most expensive token class for the (likely large) fraction of products that don't need it | Medium |
| 4 | **Batch image downloads** — instruct STEP 2a to curl a batch of images in parallel tool calls up front, then Read them in a batch, rather than interleaving one curl+Read pair per product | Turn count already has slack (§2), but this directly attacks the ~20–30 min wall-clock floor if image I/O turns out to be the dominant time cost — more sessions fit per 5-hour window | Low |
| 5 | **Profile the ~20–30 min/session wall-clock floor directly** — timestamp curl calls, BQ round-trips, and reasoning turns separately for one real session to find what's actually consuming the time, since turn count (§2) rules out the agentic loop itself as the driver | The highest-leverage lever for the *actually*-binding constraint in §3 (sessions/5-hour window), now that turn exhaustion is confirmed not to be it | Low |
| 6 | **Track create-rate and unconfident-rate per run** (already in the result JSON — `rows_created_in_dict`, `rows_qa_unconfident`) and treat a persistently high create-rate as a signal to do a one-time bulk dict-seed pass for that category, rather than continuously re-discovering the same missing coverage product-by-product forever | Converts a recurring per-session cost into a one-time fixed cost, same insight as headless's pre-seeded category briefs | Medium |

None of this requires abandoning the agentic-QA design (`docs/superpowers/specs/2026-08-06-non-niq-agentic-qa-design.md`)
— it's the same "coverage over precision, bulk over per-row" shift `headless_taxonomy_v2.sh` already made for the
NIQ pipeline, applied to the non-NIQ one. `script/niq/targeted_qa_fix.sh`'s split (bulk-first extraction, separate
precision-focused follow-up scoped by GMV impact) is the existing template for how to keep both without giving
up the multimodal grounding that makes `non_niq_qa_v2.sh` more reliable than a naive per-row LLM call.
