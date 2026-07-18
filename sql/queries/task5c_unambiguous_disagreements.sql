-- sql/queries/task5c_unambiguous_disagreements.sql
-- Task 5c: re-derive the unambiguous-bucket (candidate_count = 1) disagreements between recorded
-- product_taxonomy_map ground truth and the single brand+size candidate, and flag which ones have an
-- objectively-verifiable size mismatch: parse_size(sku_name) != product_taxonomy.size of the CURRENTLY
-- MAPPED (actual) taxonomy row. Read-only.
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
parsed_gt AS (
  SELECT g.*, parsed.size_text AS parsed_size
  FROM ground_truth g
  CROSS JOIN UNNEST([`sincere-hearth-273704.magpie_reference.parse_size`(g.sku_name)]) AS parsed
),
brand_size_pool AS (
  SELECT g.product_id, g.platform, g.country, pt.taxonomy_id AS candidate_taxonomy_id
  FROM parsed_gt g
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt
    ON pt.brand_id = g.brand_id
    AND (g.parsed_size IS NULL OR pt.size = g.parsed_size)
),
candidate_counts AS (
  SELECT product_id, platform, country, COUNT(DISTINCT candidate_taxonomy_id) AS candidate_count
  FROM brand_size_pool
  GROUP BY product_id, platform, country
),
candidates AS (
  SELECT
    g.product_id, g.platform, g.country, g.actual_taxonomy_id, g.sku_name, g.brand_id, g.parsed_size,
    pt.taxonomy_id AS candidate_taxonomy_id, dist
  FROM parsed_gt g
  JOIN `sincere-hearth-273704.magpie_reference.universe_sku_embeddings` ue
    ON ue.product_id = g.product_id AND ue.platform = g.platform AND ue.country = g.country
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt
    ON pt.brand_id = g.brand_id
    AND (g.parsed_size IS NULL OR pt.size = g.parsed_size)
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_embeddings` pte
    ON pte.taxonomy_id = pt.taxonomy_id
  CROSS JOIN UNNEST([ML.DISTANCE(ue.embedding, pte.embedding, 'COSINE')]) AS dist
  QUALIFY ROW_NUMBER() OVER (PARTITION BY g.product_id, g.platform, g.country ORDER BY dist ASC, pt.taxonomy_id ASC) = 1
),
unambiguous AS (
  SELECT c.*
  FROM candidates c
  JOIN candidate_counts cc USING (product_id, platform, country)
  WHERE cc.candidate_count = 1
)
SELECT
  u.product_id, u.platform, u.country, u.brand_id, u.sku_name, u.parsed_size,
  u.actual_taxonomy_id, pt_actual.size AS actual_size, pt_actual.canonical_name AS actual_canonical_name,
  u.candidate_taxonomy_id, pt_cand.size AS candidate_size, pt_cand.canonical_name AS candidate_canonical_name,
  u.dist,
  (u.actual_taxonomy_id != u.candidate_taxonomy_id) AS disagreement,
  (u.parsed_size IS NOT NULL AND pt_actual.size IS NOT NULL AND u.parsed_size != pt_actual.size) AS actual_size_contradicts_parsed
FROM unambiguous u
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt_actual ON pt_actual.taxonomy_id = u.actual_taxonomy_id
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt_cand ON pt_cand.taxonomy_id = u.candidate_taxonomy_id
WHERE u.actual_taxonomy_id != u.candidate_taxonomy_id
ORDER BY actual_size_contradicts_parsed DESC, u.product_id;
