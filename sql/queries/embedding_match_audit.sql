-- sql/queries/embedding_match_audit.sql
-- Audit: for a given master_table's already-LLM-mapped products, find each product's true top-1 brand+size-
-- filtered nearest neighbor, then flag (never auto-fix) any case where that top-1 disagrees with the existing
-- mapping. Params: @table STRING, @audit_flag_max_distance FLOAT64

INSERT INTO `sincere-hearth-273704.magpie_reference.taxonomy_match_audit_flags`
  (product_id, platform, country, current_taxonomy_id, suggested_taxonomy_id, distance, flagged_at)
SELECT product_id, platform, country, current_taxonomy_id, suggested_taxonomy_id, distance, CURRENT_TIMESTAMP()
FROM (
  SELECT
    u.product_id, u.ecommerce_platform AS platform, u.country,
    m.taxonomy_id AS current_taxonomy_id, pt.taxonomy_id AS suggested_taxonomy_id, dist AS distance
  FROM `sincere-hearth-273704.magpie.marketshare_universe_niq` u
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
    ON m.product_id = u.product_id AND m.platform = u.ecommerce_platform AND m.country = u.country
  JOIN `sincere-hearth-273704.magpie_reference.universe_sku_embeddings` ue
    ON ue.product_id = u.product_id AND ue.platform = u.ecommerce_platform AND ue.country = u.country
  CROSS JOIN UNNEST([`sincere-hearth-273704.magpie_reference.parse_size`(u.sku_name)]) AS parsed
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt
    ON pt.brand_id = u.brand_id
    AND (parsed.size_text IS NULL OR pt.size = parsed.size_text)
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_embeddings` pte
    ON pte.taxonomy_id = pt.taxonomy_id
  CROSS JOIN UNNEST([ML.DISTANCE(ue.embedding, pte.embedding, 'COSINE')]) AS dist
  WHERE u.brand_confidence IN ('HIGH', 'MEDIUM')
    AND u.brand_id NOT IN ('BRD-UNDEFINED', 'BRD-UNBRANDED')
    AND u.master_table = @table
    AND u.month = (SELECT MAX(month) FROM `sincere-hearth-273704.magpie.marketshare_universe_niq`)
    AND m.source = 'LLM'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY u.product_id, u.ecommerce_platform, u.country ORDER BY dist ASC) = 1
)
WHERE suggested_taxonomy_id != current_taxonomy_id
  AND distance <= @audit_flag_max_distance;
