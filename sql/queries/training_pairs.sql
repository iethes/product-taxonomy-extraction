-- sql/queries/training_pairs.sql
-- One row per (product, candidate) pair: the true positive (product's actual assigned taxonomy_id) plus its
-- top-5 nearest same-brand non-matches by embedding distance (hard negatives - the confusable pairs that broke
-- v1's unsupervised ranking, now used as supervision). SQL-native features computed here; token_jaccard_stripped
-- is computed in Python afterward from the sku_text_stripped/candidate_text_stripped columns (awkward to
-- express as a BigQuery SQL expression, trivial in Python — no need to duplicate the stripping logic since
-- the already-stripped text is passed through as columns).

WITH latest_month AS (
  SELECT MAX(month) AS month FROM `sincere-hearth-273704.magpie.marketshare_universe_niq`
),
anchors AS (
  SELECT
    m.product_id, m.platform, m.country, m.master_table, m.taxonomy_id AS assigned_taxonomy_id,
    u.sku_name, u.brand_id, ue.embedding AS product_embedding
  FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
  JOIN `sincere-hearth-273704.magpie.marketshare_universe_niq` u
    ON u.product_id = m.product_id AND u.ecommerce_platform = m.platform AND u.country = m.country
  CROSS JOIN latest_month
  JOIN `sincere-hearth-273704.magpie_reference.universe_sku_embeddings` ue
    ON ue.product_id = m.product_id AND ue.platform = m.platform AND ue.country = m.country
  WHERE u.month = latest_month.month
    AND m.source = 'LLM'
    AND m.master_table LIKE 'shopee_th_%'
    AND u.brand_confidence IN ('HIGH', 'MEDIUM')
    AND u.brand_id NOT IN ('BRD-UNDEFINED', 'BRD-UNBRANDED')
),
anchors_parsed AS (
  SELECT a.*, parsed.size_text AS parsed_size, bd.canonical_name AS brand_canonical
  FROM anchors a
  CROSS JOIN UNNEST([`sincere-hearth-273704.magpie_reference.parse_size`(a.sku_name)]) AS parsed
  JOIN `sincere-hearth-273704.magpie_reference.brand_dict` bd ON bd.brand_id = a.brand_id
),
candidates AS (
  SELECT
    a.product_id, a.platform, a.country, a.master_table, a.sku_name, a.assigned_taxonomy_id,
    a.parsed_size, a.brand_canonical, a.brand_id,
    pt.taxonomy_id AS candidate_taxonomy_id,
    pt.size AS candidate_size, pt.pack_count AS candidate_pack_count,
    pt.canonical_name AS candidate_canonical_name,
    ML.DISTANCE(a.product_embedding, pte.embedding, 'COSINE') AS embedding_cosine_distance
  FROM anchors_parsed a
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt ON pt.brand_id = a.brand_id
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_embeddings` pte
    ON pte.taxonomy_id = pt.taxonomy_id
),
labeled AS (
  SELECT
    *,
    IF(candidate_taxonomy_id = assigned_taxonomy_id, 1, 0) AS label,
    ROW_NUMBER() OVER (
      PARTITION BY product_id, platform, country
      ORDER BY IF(candidate_taxonomy_id = assigned_taxonomy_id, 0, 1), embedding_cosine_distance ASC
    ) AS rn
  FROM candidates
)
SELECT
  l.product_id, l.platform, l.country, l.master_table, l.candidate_taxonomy_id AS taxonomy_id, l.label,
  l.embedding_cosine_distance,
  IF(l.parsed_size IS NULL OR l.candidate_size IS NULL, 'unknown',
     IF(l.parsed_size = l.candidate_size, 'match', 'mismatch')) AS size_match,
  REGEXP_EXTRACT(LOWER(l.sku_name), 'x\\s*(\\d+)') AS pack_multiplier_signal,
  l.candidate_pack_count,
  EDIT_DISTANCE(
    LOWER(REPLACE(REPLACE(l.sku_name, l.brand_canonical, ''), IFNULL(l.parsed_size, ''), '')),
    LOWER(REPLACE(REPLACE(l.candidate_canonical_name, l.brand_canonical, ''), IFNULL(l.parsed_size, ''), ''))
  ) AS edit_distance_stripped,
  LOWER(REPLACE(REPLACE(l.sku_name, l.brand_canonical, ''), IFNULL(l.parsed_size, ''), '')) AS sku_text_stripped,
  LOWER(REPLACE(REPLACE(l.candidate_canonical_name, l.brand_canonical, ''), IFNULL(l.parsed_size, ''), '')) AS candidate_text_stripped,
  IFNULL(bvk.variant, '') != '' AS keyword_table_hit,
  SAFE_DIVIDE(LENGTH(l.sku_name), LENGTH(l.candidate_canonical_name)) AS text_length_ratio
FROM labeled l
LEFT JOIN `sincere-hearth-273704.magpie_reference.brand_variant_keywords` bvk
  ON bvk.brand_id = l.brand_id
  AND STRPOS(LOWER(l.sku_name), LOWER(bvk.variant)) > 0
WHERE l.rn <= 6;  -- the true positive (rn could be 1 if it's also nearest) plus up to 5 hard negatives
