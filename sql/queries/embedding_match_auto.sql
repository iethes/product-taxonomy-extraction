-- sql/queries/embedding_match_auto.sql
-- Auto-match: for a given master_table's currently-unmapped products, find a confident brand+size-filtered
-- nearest-neighbor match against the existing taxonomy and write it directly — skipping Tier 5 (LLM) for
-- that product. Never touches an already-mapped product (m.taxonomy_id IS NULL guard).
-- Params: @table STRING, @auto_match_max_distance FLOAT64, @meta_agent STRING

INSERT INTO `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
  (product_id, master_table, platform, country, taxonomy_id, source, confidence, meta_agent, mapped_at)
SELECT
  u.product_id, u.master_table, u.ecommerce_platform, u.country,
  pt.taxonomy_id, 'EMBEDDING_MATCH', FORMAT('%.2f', 1 - dist), @meta_agent, CURRENT_TIMESTAMP()
FROM `sincere-hearth-273704.magpie.marketshare_universe_niq` u
JOIN `sincere-hearth-273704.magpie_reference.universe_sku_embeddings` ue
  ON ue.product_id = u.product_id AND ue.platform = u.ecommerce_platform AND ue.country = u.country
LEFT JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
  ON m.product_id = u.product_id AND m.platform = u.ecommerce_platform AND m.country = u.country
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
  AND m.taxonomy_id IS NULL
QUALIFY ROW_NUMBER() OVER (PARTITION BY u.product_id, u.ecommerce_platform, u.country ORDER BY dist ASC) = 1
  AND dist <= @auto_match_max_distance;
