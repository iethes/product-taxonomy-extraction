-- sql/queries/headless_v2_candidate_products.sql
-- For each worklist product (raw, unmapped -- no product_taxonomy row exists for it yet), the top @n
-- reference candidates from product_taxonomy rows scoped to @scope_tables (this table + fuzzy-matched
-- sibling tables), review_confidence='confident' only. Tier A (brand-scoped, via product_brand_map)
-- preferred; Tier B (pure text) fills remaining slots for a product with no Tier A rows. Reference/format
-- context only -- never a basis for an autonomous write. See
-- docs/superpowers/specs/2026-08-21-headless-taxonomy-v2-cross-market-candidates-design.md.
-- Params: @product_ids ARRAY<STRING>, @sku_names ARRAY<STRING> (parallel, same order as @product_ids),
--         @this_table STRING, @scope_tables ARRAY<STRING>, @n INT64

WITH worklist AS (
  SELECT product_id, sku_name
  FROM UNNEST(@product_ids) AS product_id WITH OFFSET pid_pos
  JOIN UNNEST(@sku_names) AS sku_name WITH OFFSET sku_pos ON pid_pos = sku_pos
),
worklist_brand AS (
  SELECT product_id, brand_id
  FROM `sincere-hearth-273704.magpie_reference.product_brand_map`
  WHERE master_table = @this_table AND product_id IN UNNEST(@product_ids)
),
candidate_pool AS (
  SELECT DISTINCT pt.taxonomy_id, pt.brand_id, pt.canonical_name, m.master_table AS source_table
  FROM `sincere-hearth-273704.magpie_reference.product_taxonomy` pt
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m ON m.taxonomy_id = pt.taxonomy_id
  WHERE m.master_table IN UNNEST(@scope_tables)
    AND JSON_VALUE(pt._meta, '$.review_confidence') = 'confident'
),
tier_a AS (
  SELECT w.product_id AS worklist_product_id, c.taxonomy_id AS candidate_taxonomy_id,
    c.canonical_name AS candidate_canonical_name, c.source_table,
    SAFE_DIVIDE(EDIT_DISTANCE(w.sku_name, c.canonical_name), GREATEST(LENGTH(w.sku_name), LENGTH(c.canonical_name))) AS normalized_distance,
    'brand_match' AS match_tier
  FROM worklist w
  JOIN worklist_brand wb ON wb.product_id = w.product_id
  JOIN candidate_pool c ON c.brand_id = wb.brand_id
),
tier_b AS (
  SELECT w.product_id AS worklist_product_id, c.taxonomy_id AS candidate_taxonomy_id,
    c.canonical_name AS candidate_canonical_name, c.source_table,
    SAFE_DIVIDE(EDIT_DISTANCE(w.sku_name, c.canonical_name), GREATEST(LENGTH(w.sku_name), LENGTH(c.canonical_name))) AS normalized_distance,
    'text_only' AS match_tier
  FROM worklist w
  CROSS JOIN candidate_pool c
  WHERE w.product_id NOT IN (SELECT worklist_product_id FROM tier_a)
)
SELECT worklist_product_id, candidate_taxonomy_id, candidate_canonical_name, source_table, match_tier, normalized_distance
FROM (SELECT * FROM tier_a UNION ALL SELECT * FROM tier_b)
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY worklist_product_id ORDER BY (match_tier != 'brand_match'), normalized_distance ASC
) <= @n
