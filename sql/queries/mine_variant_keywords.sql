-- sql/queries/mine_variant_keywords.sql
-- Re-minable anytime product_taxonomy.variant changes - truncate and repopulate, not incremental.

TRUNCATE TABLE `sincere-hearth-273704.magpie_reference.brand_variant_keywords`;

INSERT INTO `sincere-hearth-273704.magpie_reference.brand_variant_keywords`
  (brand_id, variant, product_count, computed_at)
SELECT brand_id, variant, COUNT(*) AS product_count, CURRENT_TIMESTAMP()
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy`
WHERE variant IS NOT NULL AND TRIM(variant) != ''
GROUP BY brand_id, variant;
