# Prompt: Update the Deployed `non_niq_embed` Windmill Script's Embedding Model

> Paste everything below the line into a fresh Claude session with access to the Windmill instance
> (or hand it to whoever manages Windmill deployments). It's self-contained. This is a small,
> targeted follow-up to the original deploy — see `docs/windmill-non-niq-embed-prompt.md` for how
> `non_niq_embed` got onto Windmill in the first place; this doc does not re-explain that context.

---

## What changed and why

The `product-taxonomy-extraction` repo's side of this pipeline (`script/non_niq/non_niq_helper.py`)
switched its embedding model from `intfloat/multilingual-e5-large` (560M params, 1024-dim) to
`intfloat/multilingual-e5-small` (118M params, 384-dim) — same E5 family, same `query:`/`passage:`
asymmetric-retrieval prefix convention, ~3x faster CPU encode, no measurable retrieval-quality loss
at the top-10 cutoff this pipeline actually uses in production (Meilisearch hybrid search dilutes
the vector signal 50/50 with BM25 keyword match anyway, so the smaller model's slightly lower raw
embedding quality doesn't show up in top-10 retrieval — decided via a real-data eval against the
`lighting` category's confirmed QA rows, not reproduced here).

**The deployed Windmill script must switch to the same model.** Two separate processes write
`_vectors.default` into the same `{dataset}_taxonomy_qa` Meilisearch indexes — this repo's own
`index` command (called from `non_niq_qa_v2.sh`, per-category, on new QA-confirmed entries) and
Windmill's `non_niq_embed.py` `mode="sync"` (manual-trigger whole-corpus resync). Meilisearch's
`userProvided` embedder has one fixed `dimensions` value per index. If the two writers disagree —
one embedding at 1024-dim, the other at 384-dim — `ensure_index`'s settings PATCH and/or the
following documents POST will fail dimension validation, or worse, silently mix incompatible
vectors into the same index.

## Your task

1. Open the currently-deployed `non_niq_embed` Windmill script (the one `docs/windmill-non-niq-embed-prompt.md`'s
   original prompt deployed — same workspace, same folder, don't create a new one).
2. Change exactly two lines:
   ```python
   MODEL_NAME = "intfloat/multilingual-e5-small"
   EMBED_DIM = 384
   ```
   (currently `"intfloat/multilingual-e5-large"` / `1024`). Nothing else in the script changes —
   same `extra_requirements`, same `# py311` pin, same torch wheel URL, same four modes, same
   `is_confirmed` logic, same batching. This is a two-constant edit, not a redeploy-from-scratch.
3. Deploy the updated script.
4. **Run `mode="sync"` for every active category once step 3 is live.** All 12 `*_taxonomy_qa`
   indexes on the shared Meilisearch instance (`ac`, `airpurifier`, `babybath`, `babycreamlotion`,
   `blender`, `coffee`, `cookiesbiscuit`, `keripikkerupuk`, `kopi`, `lighting`, `susububuk`,
   `telonoil`) have already been deleted and recreated at `dimensions: 384` from the
   `product-taxonomy-extraction` repo side — they're empty right now, waiting on this script's sync
   to backfill them from BigQuery. Until you run sync, `retrieve` in production returns clean empty
   candidates for every category (an already-handled degradation, not an error) — so there's no
   dimension-conflict risk on this step, just an open gap until you run it. Run it per-dataset
   (`main(mode="sync", dataset="ac")`, etc., or however this workspace's UI iterates the active-category
   list) rather than assuming a single no-args call covers all of them, unless you've confirmed the
   no-`dataset` path already loops every active category (it does, per the script body below — but
   verify against the current config Sheet's active-category list before assuming full coverage).

## Out of scope for this handoff

- Do not create or delete any index yourself — all 12 already exist, pre-created at 384-dim (see
  step 4). `mode="sync"`'s own `ensure_index` call against them is a no-op create (they already
  exist) plus a settings PATCH (already correct) — you're only expected to run sync, not manage
  index lifecycle.
- Everything in `docs/windmill-non-niq-embed-prompt.md`'s own "Out of scope" section still applies
  (read-only against BigQuery, don't touch non-`*_taxonomy_qa` indexes, no schedule/cron trigger).
