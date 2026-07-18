-- sql/queries/pilot_validate_th_toothpaste.sql
-- Read-only. For every shopee_th_toothpaste product already correctly mapped by an LLM session, find its
-- brand+size-filtered embedding top-1 and compare to the known-correct taxonomy_id. Since this ground truth
-- is already right, any mismatch here is a real false positive — this measures both auto-match precision and
-- audit-mode false-positive rate at once, across a range of candidate thresholds.
--
-- Deviation from the task-5 brief (2026-07-18): the brief's original text filtered the universe join with
-- `AND u.month = (SELECT MAX(month) FROM ...)` inline in the JOIN...ON clause. That errors on this project's
-- BigQuery engine with "Unsupported subquery with table in join predicate." Restructured below as a 1-row
-- `latest_month` CTE CROSS JOINed in, with the comparison moved to WHERE — an inner join, so moving an
-- equality condition from ON to WHERE does not change results. Semantics are otherwise unchanged from the brief.
--
-- 2026-07-18 update (task 5b): the universe_sku_embeddings rows for shopee_th_toothpaste were recomputed from
-- master_clean_niq.shopee_th_toothpaste.sku_name_EN (machine-translated English) instead of raw
-- marketshare_universe_niq.sku_name (often untranslated/mixed Thai-English) — see script/embedding_worker.py.
-- This query also now adds a candidate_count dimension: candidate_count = 1 means brand+size uniquely
-- identifies one taxonomy entry (alternative-1 fast path); candidate_count > 1 means the embedding still has to
-- rank between 2+ same-brand-size candidates (the harder bucket where the 98% precision bar genuinely matters).
-- GROUPING SETS produces both the per-bucket and the overall (bucket = NULL) rows in one pass.
--
-- The unambiguous (candidate_count = 1) bucket is NOT guaranteed 100% by construction: candidate_count = 1
-- means the brand+size filter yields exactly one candidate, but that candidate is only correct if the
-- ground-truth taxonomy_id was actually in the brand+size pool (the prior pilot found ~12% "structural miss"
-- cases where it wasn't). The alternative-1 fast path also auto-matches its single candidate regardless of
-- embedding distance, so measuring it at a distance-gated threshold understates its true volume/precision.
-- The sentinel threshold 2.0 (COSINE distance's theoretical max) below is an "ungated" row per bucket — it
-- captures every candidate regardless of distance, giving the true unambiguous-bucket volume/precision and the
-- true ungated overall precision, alongside the distance-gated rows used to find the ambiguous-bucket cutoff.
-- The low end is sampled finer (0.02 steps) than the original pilot's 0.05 steps, since EN-translated text is
-- expected to compress distances toward zero relative to the original run's 0.07 observed minimum, and the
-- ambiguous-bucket 0.98 crossover (if any) needs to be pinpointed, not bracketed by wide steps.

WITH latest_month AS (
  SELECT MAX(month) AS month FROM `sincere-hearth-273704.magpie.marketshare_universe_niq`
),
ground_truth AS (
  SELECT m.product_id, m.platform, m.country, m.taxonomy_id AS actual_taxonomy_id,
         u.sku_name, u.brand_id
  FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
  JOIN `sincere-hearth-273704.magpie.marketshare_universe_niq` u
    ON u.product_id = m.product_id AND u.ecommerce_platform = m.platform AND u.country = m.country
  CROSS JOIN latest_month
  WHERE m.master_table = 'shopee_th_toothpaste'
    AND m.source = 'LLM'
    AND u.month = latest_month.month
    AND u.brand_confidence IN ('HIGH', 'MEDIUM')
    AND u.brand_id NOT IN ('BRD-UNDEFINED', 'BRD-UNBRANDED')
),
brand_size_pool AS (
  -- Every taxonomy entry that passes the brand+size filter for a product, BEFORE any embedding ranking.
  -- Used only to count how many candidates each product has to disambiguate between.
  SELECT g.product_id, g.platform, g.country, pt.taxonomy_id AS candidate_taxonomy_id
  FROM ground_truth g
  CROSS JOIN UNNEST([`sincere-hearth-273704.magpie_reference.parse_size`(g.sku_name)]) AS parsed
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt
    ON pt.brand_id = g.brand_id
    AND (parsed.size_text IS NULL OR pt.size = parsed.size_text)
),
candidate_counts AS (
  SELECT product_id, platform, country, COUNT(DISTINCT candidate_taxonomy_id) AS candidate_count
  FROM brand_size_pool
  GROUP BY product_id, platform, country
),
candidates AS (
  SELECT
    g.product_id, g.platform, g.country, g.actual_taxonomy_id,
    pt.taxonomy_id AS candidate_taxonomy_id, dist
  FROM ground_truth g
  JOIN `sincere-hearth-273704.magpie_reference.universe_sku_embeddings` ue
    ON ue.product_id = g.product_id AND ue.platform = g.platform AND ue.country = g.country
  CROSS JOIN UNNEST([`sincere-hearth-273704.magpie_reference.parse_size`(g.sku_name)]) AS parsed
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt
    ON pt.brand_id = g.brand_id
    AND (parsed.size_text IS NULL OR pt.size = parsed.size_text)
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_embeddings` pte
    ON pte.taxonomy_id = pt.taxonomy_id
  CROSS JOIN UNNEST([ML.DISTANCE(ue.embedding, pte.embedding, 'COSINE')]) AS dist
  -- tie-break on taxonomy_id for determinism (the original pilot's QUALIFY had no tiebreaker and wobbled
  -- ±1-2 rows run-to-run on exact-tied distances)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY g.product_id, g.platform, g.country ORDER BY dist ASC, pt.taxonomy_id ASC) = 1
)
SELECT
  CASE WHEN cc.candidate_count = 1 THEN 'unambiguous' ELSE 'ambiguous' END AS bucket,
  threshold,
  COUNT(*) AS candidates_under_threshold,
  COUNTIF(c.candidate_taxonomy_id = c.actual_taxonomy_id) AS correct,
  SAFE_DIVIDE(COUNTIF(c.candidate_taxonomy_id = c.actual_taxonomy_id), COUNT(*)) AS precision
FROM candidates c
JOIN candidate_counts cc USING (product_id, platform, country)
CROSS JOIN UNNEST([0.02, 0.04, 0.06, 0.08, 0.10, 0.12, 0.15, 0.20, 0.25, 0.30, 2.0]) AS threshold
WHERE c.dist <= threshold
GROUP BY GROUPING SETS (
  (CASE WHEN cc.candidate_count = 1 THEN 'unambiguous' ELSE 'ambiguous' END, threshold),
  (threshold)
)
ORDER BY bucket, threshold;
