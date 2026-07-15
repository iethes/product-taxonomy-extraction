# Design: Deterministic Size Regex Pass (Rec 2, `traditional-ml-execution-model.md`)

> Status: approved design, not yet implemented.
> Implements Recommendation 2 from
> [`docs/traditional-ml-execution-model.md`](../traditional-ml-execution-model.md) ("Better size/pack regex —
> fixes the reported bug directly") — the first, cheapest item in that doc's own suggested sequencing. Also
> closes Root Cause 2/3/4 from
> [`docs/taxonomy-pipeline-improvement-recommendations.md`](../taxonomy-pipeline-improvement-recommendations.md)
> for the `size` field specifically (pack_count is explicitly deferred — see Out of scope).

---

## Why this is a pre-LLM step, and why it's the first tier to build

Every tier in `traditional-ml-execution-model.md` is a pre-LLM filter: it resolves what it can deterministically,
and only what survives reaches the expensive LLM call. This pass is Tier-1-shaped in that doc's cascade
("regex size/pack extraction → most size/pack, $0") — pure text pattern matching, no model, no training data,
no inference cost. It's first because it's the cheapest (regex, not embeddings/clustering/training) and it
directly closes the reported bug (`"KAPASITAS 2,5kg"` sitting unparsed in `sku_name`).

## Locale scope: TH + ID only

Intrepid covers 6 countries (`intrepid_pipeline_clean_product_level`, confirmed: TH, SG, ID; likely also MY/PH/VN
per the `{platform}_{country}_{category}` naming pattern in `docs/data-dictionary.md`). This pass covers **TH**
(the existing, documented market with keyword rules already in `docs/llm-extraction-rules.md`) and **ID** (the
market with the actual reported bug). MY/PH/VN keyword tables are explicitly deferred — no reported failure
there yet, and guessing at keyword lists for markets with no known bug is exactly the kind of speculative
scope this pipeline's own docs have repeatedly flagged as a problem (see "scope drift," Root Cause 3 in
`taxonomy-pipeline-improvement-recommendations.md`).

## Field scope: size only, not pack_count

`docs/llm-extraction-rules.md` §1/§2 documents an explicit priority-chain asymmetry:
- **Size**: `sku_name` text wins over image — never override a stated size with a guess. Safe for a text-only
  regex pass.
- **Pack_count**: **image is the tiebreaker** when text and image disagree, plus a long documented table of
  false-positive text patterns (GWP vs. genuine multipack, "มี N สูตรให้เลือก" selector language, promo phrasing
  like "N ฟรี M"). A SQL pass has no image access and cannot apply that judgment — it would only ever be a
  text-only guess for a field the rules doc itself says text alone isn't reliable for.

This pass extracts **size only**. Pack_count extraction is real future work but a separate, harder design (it
needs either image access or a much more conservative "skip anything ambiguous" posture) — not bolted onto this
one under time pressure.

## Mechanism

**One persistent BigQuery SQL UDF**, single source of truth, plus **one UPDATE query** run twice (once now as a
backfill, then on a recurring schedule for future NULLs) — not duplicated logic across two mechanisms.

```sql
-- sql/functions/parse_size.sql — as actually deployed (BigQuery's RE2 engine has no lookahead
-- support, and REGEXP_EXTRACT allows at most 1 capturing group per call — both required fixes
-- during implementation; see docs/plans/size-regex-pass-implementation-plan.md Task 2).
CREATE OR REPLACE FUNCTION `sincere-hearth-273704.magpie_reference.parse_size`(sku_name STRING)
RETURNS STRUCT<size_value FLOAT64, size_unit STRING, size_text STRING>
AS ((
  WITH normalized AS (
    SELECT REGEXP_REPLACE(
      sku_name,
      r'(\d+),(\d{1,2})(\s*(?:kg|g|ml|l|กรัม|ก\.|มล\.?|ลิตร))',
      r'\1.\2\3'
    ) AS s
  ),
  extracted AS (
    SELECT
      REGEXP_EXTRACT(LOWER(s), r'(\d+(?:\.\d+)?)\s*(?:kg|g|ml|l|กรัม|ก\.|มล\.?|ลิตร)') AS raw_num,
      REGEXP_EXTRACT(LOWER(s), r'\d+(?:\.\d+)?\s*(kg|g|ml|l|กรัม|ก\.|มล\.?|ลิตร)') AS raw_unit
    FROM normalized
  ),
  normalized_unit AS (
    SELECT raw_num, CASE raw_unit
      WHEN 'กรัม' THEN 'g' WHEN 'ก.' THEN 'g'
      WHEN 'มล.' THEN 'ml' WHEN 'มล' THEN 'ml'
      WHEN 'ลิตร' THEN 'l' ELSE raw_unit END AS unit
    FROM extracted
  )
  SELECT AS STRUCT
    SAFE_CAST(raw_num AS FLOAT64) AS size_value,
    unit AS size_unit,
    CASE WHEN raw_num IS NOT NULL THEN CONCAT(raw_num, unit) ELSE NULL END AS size_text
  FROM normalized_unit
));
```

Deployed to `sincere-hearth-273704.magpie_reference.parse_size` and validated against the 5-case test block
below — all pass, including the price-not-a-size negative case.

**Unit keywords, case-insensitive:**
- Universal/ASCII: `ml`, `g`, `l`, `kg`
- TH (`docs/llm-extraction-rules.md` §9 + body_wash changelog entry): `มล.` (ml), `กรัม`/`ก.` (g — the short form
  that broke Thai soap size extraction once already, per the Jun 23 changelog entry), `ลิตร` (L)
- ID precursor keywords (`kapasitas`, `berat`, `isi`, `ukuran`) — boost confidence when present, not required
  for a match, since a bare `\d+\s*(kg|g|ml|l)` pattern is usually unambiguous on its own

**Decimal normalization:** comma is treated as a decimal separator only when followed by 1-2 digits directly
before a unit keyword (`2,5kg` → `2.5kg`), which distinguishes it from thousands-grouping commas (`1,000`)
without needing an explicit locale parameter per call.

**Fill query** (`sql/queries/backfill_size_regex.sql`), run once as backfill, then on a schedule:

```sql
UPDATE `magpie_reference.product_taxonomy` t
SET size = parsed.parsed.size_text, updated_at = CURRENT_TIMESTAMP()
FROM (
  SELECT taxonomy_id, magpie_reference.parse_size(ANY_VALUE(src.sku_name)) AS parsed
  FROM `magpie_reference.product_taxonomy` pt
  JOIN `magpie_reference.product_taxonomy_map` m USING (taxonomy_id)
  JOIN <source table resolved via master_table/platform/country, per ADR-006> src
    ON src.product_id = m.product_id
  WHERE pt.size IS NULL
  GROUP BY taxonomy_id
) parsed
WHERE t.taxonomy_id = parsed.taxonomy_id
  AND parsed.parsed.size_value IS NOT NULL;
```

**Safety guard:** `WHERE pt.size IS NULL` is the entire overwrite-protection mechanism — this pass never touches
a row any prior process (LLM or human) already set a size on. Matches the fill-only-if-missing rule already
established in `taxonomy-pipeline-improvement-recommendations.md` Recommendation 4.

**Recurring cadence:** a native BigQuery scheduled query (`bq mk --transfer_config`, documented as a snippet in
`docs/llm-extraction-rules.md`, not committed as a script) running the same fill query periodically. No cron
box, no external repo, no new infra class — reuses a BQ-native feature rather than building one.

**Audit trail:** none added beyond what already exists — `updated_at` on the touched rows plus BigQuery's own
job history (`INFORMATION_SCHEMA.JOBS`) is sufficient to see what a given scheduled run touched. No new
`size_source` provenance column; add one later only if this proves insufficient in practice.

## The runnable check

Embedded as a comment block in `sql/functions/parse_size.sql`, and run once for real before trusting the
backfill:

```sql
WITH cases AS (
  SELECT * FROM UNNEST([
    STRUCT('KAPASITAS 2,5kg Mesin Cuci Mini' AS sku_name, '2.5kg' AS expected),
    STRUCT('Sabun Mandi Cair 250ml' AS sku_name, '250ml' AS expected),
    STRUCT('โฟมล้างหน้า 100 มล.' AS sku_name, '100ml' AS expected),
    STRUCT('สบู่ก้อน 105ก.' AS sku_name, '105g' AS expected),
    STRUCT('Harga Promo Rp 1,000,000' AS sku_name, CAST(NULL AS STRING) AS expected)
  ])
)
SELECT sku_name, expected, magpie_reference.parse_size(sku_name).size_text AS actual,
       expected IS NOT DISTINCT FROM magpie_reference.parse_size(sku_name).size_text AS pass
FROM cases;
-- expect: pass = TRUE on every row, including the deliberate non-size false-positive check (a price, not a size)
```

The price/false-positive case is the important one — it's the guard against the UDF inventing a "size" out of
an unrelated large number.

## Out of scope

- Pack_count extraction — deferred, separate future design (image-tiebreaker + false-positive-pattern
  complexity documented in `docs/llm-extraction-rules.md` §1 makes this meaningfully harder than size).
- Canonical_name string rebuild (stripping literal `"Undefined"` tokens) — that's Stage 05 insertion-code logic
  in the external Mac pipeline repo, not reachable from this repo.
- MY/PH/VN locale keyword tables — no reported bug yet; add when evidenced, not speculatively.
- Any change to the external Python Phase 5 pipeline to make it *consult* this pass's output before calling the
  LLM — this design is self-contained in BigQuery; wiring it into the multimodal pipeline's decision logic is a
  separate, cross-repo follow-up.
- A new provenance/audit column on `product_taxonomy` — `updated_at` + BQ job history is enough for now.

## Deliverables

1. `sql/functions/parse_size.sql` — the UDF, with the embedded test-case block above.
2. `sql/queries/backfill_size_regex.sql` — the fill-if-null UPDATE query (run once manually as the backfill).
3. A new short subsection in `docs/llm-extraction-rules.md` §2 (Size), documenting that a regex pre-pass now
   runs before/independent of LLM extraction, so future session briefs and the headless runbook both know this
   exists and don't re-derive sizes it already resolved. Includes the `bq mk --transfer_config` snippet for the
   recurring schedule.

## Addendum (found during plan-writing, 2026-07-14)

Two corrections surfaced while writing the implementation plan — recorded here rather than silently
rewriting the sections above:

1. **Guard bug:** `WHERE pt.size IS NULL` alone is wrong — it would overwrite the intentionally-NULL `size` on
   `is_multi_size=TRUE` / `is_bundle=TRUE` entries (per CLAUDE.md's own QA gate 3: `size IS NULL AND
   is_multi_size IS NOT TRUE`). The fill query's guard must be
   `WHERE pt.size IS NULL AND pt.is_multi_size IS NOT TRUE AND pt.is_bundle IS NOT TRUE`.
2. **Mechanism simplification:** the "<source table resolved via master_table/platform/country>" placeholder in
   the fill query is resolved — `magpie.marketshare_universe` already has `sku_name` and already denormalizes
   NIQ + whatever else it currently covers into one table (`ARCHITECTURE.md`), so the fill query is a static
   join against it, not the dynamic per-master_table `EXECUTE IMMEDIATE` scripting originally sketched.
3. **Open question, not yet resolved:** `docs/sku-taxonomy-quality-scan-2026-04.md` — the doc that reported the
   original bug — records `marketshare_universe` as **718M rows / 700GB live**, not the ~9.96M the schema/
   `ARCHITECTURE.md` describe, and states plainly that whether the Indonesian-language rows are genuine
   `country='ID'` data or Thai/SG listings with untranslated Indonesian text is **"not determinable from this
   sample."** The implementation plan makes resolving this its first task and gates the ID part of the locale
   scope on the answer, rather than assuming TH+ID as settled fact.

## Relationship to the headless runbook design

Not a dependency in either direction, but a natural future integration point:
[`docs/plans/headless-taxonomy-runbook-design.md`](headless-taxonomy-runbook-design.md)'s deterministic wrapper
(claim → judgment-only `claude -p` call → QA gates → refresh) could run this fill query as an additional
pre-step before invoking `claude -p`, so the LLM call never has to re-derive a size this pass already resolved
for free. Not designed here — flagged for whoever implements the runbook next.
