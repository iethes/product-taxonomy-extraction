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

WITH latest_month AS (
  SELECT MAX(month) AS month FROM `sincere-hearth-273704.magpie.marketshare_universe_niq`
),
candidates AS (
  SELECT
    m.product_id, m.platform, m.country, m.taxonomy_id AS actual_taxonomy_id,
    pt.taxonomy_id AS candidate_taxonomy_id, dist
  FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
  JOIN `sincere-hearth-273704.magpie.marketshare_universe_niq` u
    ON u.product_id = m.product_id AND u.ecommerce_platform = m.platform AND u.country = m.country
  CROSS JOIN latest_month
  JOIN `sincere-hearth-273704.magpie_reference.universe_sku_embeddings` ue
    ON ue.product_id = m.product_id AND ue.platform = m.platform AND ue.country = m.country
  CROSS JOIN UNNEST([`sincere-hearth-273704.magpie_reference.parse_size`(u.sku_name)]) AS parsed
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt
    ON pt.brand_id = u.brand_id
    AND (parsed.size_text IS NULL OR pt.size = parsed.size_text)
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_embeddings` pte
    ON pte.taxonomy_id = pt.taxonomy_id
  CROSS JOIN UNNEST([ML.DISTANCE(ue.embedding, pte.embedding, 'COSINE')]) AS dist
  WHERE m.master_table = 'shopee_th_toothpaste'
    AND m.source = 'LLM'
    AND u.month = latest_month.month
    AND u.brand_confidence IN ('HIGH', 'MEDIUM')
    AND u.brand_id NOT IN ('BRD-UNDEFINED', 'BRD-UNBRANDED')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY m.product_id, m.platform, m.country ORDER BY dist ASC) = 1
)
SELECT
  threshold,
  COUNT(*) AS candidates_under_threshold,
  COUNTIF(candidate_taxonomy_id = actual_taxonomy_id) AS correct,
  SAFE_DIVIDE(COUNTIF(candidate_taxonomy_id = actual_taxonomy_id), COUNT(*)) AS precision
FROM candidates, UNNEST([0.05, 0.10, 0.15, 0.20, 0.25, 0.30]) AS threshold
WHERE dist <= threshold
GROUP BY threshold
ORDER BY threshold;
