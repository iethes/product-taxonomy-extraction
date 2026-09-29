-- Pasta Gigi Bayi: Tokopedia QA worklist
--
-- The source table already assigns product_tier from GMV. Do not recalculate
-- GMV shares here: use Tier 1 + Tier 2 directly (the top 90% population).
--
-- `Tokopedia` and `Tokopedia | Shop` are deliberately kept as separate
-- platforms. A QA row on one platform does not hide the same product ID on the
-- other platform.

WITH
  settings AS (
    SELECT
      '2026-08' AS target_month,
      ['15306258', '2291775'] AS always_review_merchant_ids
  ),

  -- 1. Get this month's in-scope listings, excluding confirmed OOS products.
  source_listings AS (
    SELECT
      s.product_id,
      s.sku_name,
      REPLACE(s.image, '"', '') AS image,
      s.url AS product_url,
      s.ecommerce_platform,  -- Keep the raw platform: no Tokopedia normalization.
      s.gmv_monthly,
      s.merchant_id,
      NULL AS item_description,          -- Not available for Tokopedia.
      NULL AS product_attributes_attrs   -- Not available for Tokopedia.
    FROM `sincere-hearth-273704.pastagigibayi.master_pastagigibayi_id` AS s
    CROSS JOIN settings
    WHERE FORMAT_DATE('%Y-%m', s.month) = settings.target_month
      AND s.ecommerce_platform IN ('Tokopedia', 'Tokopedia | Shop')
      AND (
        s.product_tier IN ('Tier 1')
        OR s.merchant_id IN UNNEST(settings.always_review_merchant_ids)
      )
      AND NOT EXISTS (
        SELECT 1
        FROM `sincere-hearth-273704.pastagigibayi.filter_pastagigibayi` AS f
        WHERE f.product_id = s.product_id
      )
  ),

  -- 2. A QA result only covers the same product, title, and raw platform.
  reviewed_titles AS (
    SELECT DISTINCT
      prod_id AS product_id,
      ecommerce_platform,
      REGEXP_REPLACE(TRIM(sku_name), r'\s+', ' ') AS normalized_sku_name
    FROM `sincere-hearth-273704.pastagigibayi.product_id_dict_qa`
    WHERE ecommerce_platform IN ('Tokopedia', 'Tokopedia | Shop')
  ),

  -- 3. Retain per-platform QA status so incomplete work can be retried.
  product_review_status AS (
    SELECT
      prod_id AS product_id,
      ecommerce_platform,
      LOGICAL_OR(
        JSON_VALUE(SAFE.PARSE_JSON(_meta), '$.qa_confidence') = 'unconfident'
        AND COALESCE(JSON_VALUE(SAFE.PARSE_JSON(_meta), '$.human_review'), 'false') != 'true'
      ) AS has_unconfident_review,
      LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '$.qa_confidence') = 'confident') AS has_confident_review,
      LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '$.human_review') = 'true') AS has_human_review
    FROM `sincere-hearth-273704.pastagigibayi.product_id_dict_qa`
    WHERE ecommerce_platform IN ('Tokopedia', 'Tokopedia | Shop')
    GROUP BY prod_id, ecommerce_platform
  ),

  -- 4. A new title has priority 0; an unconfident review has priority 1.
  review_queue AS (
    SELECT
      listing.product_id,
      listing.sku_name,
      listing.image,
      listing.product_url,
      listing.gmv_monthly,
      listing.ecommerce_platform,
      listing.merchant_id,
      listing.item_description,
      listing.product_attributes_attrs,
      FALSE AS listing_changed,
      NULL AS prior_sku_name,
      NULL AS prior_kategori,
      CASE
        WHEN title.product_id IS NULL THEN 0
        WHEN status.has_unconfident_review
          AND NOT status.has_confident_review
          AND NOT status.has_human_review THEN 1
        ELSE NULL
      END AS priority
    FROM source_listings AS listing
    LEFT JOIN reviewed_titles AS title
      ON title.product_id = listing.product_id
     AND title.ecommerce_platform = listing.ecommerce_platform
     AND title.normalized_sku_name = REGEXP_REPLACE(TRIM(listing.sku_name), r'\s+', ' ')
    LEFT JOIN product_review_status AS status
      ON status.product_id = listing.product_id
     AND status.ecommerce_platform = listing.ecommerce_platform
  )

SELECT *
FROM review_queue
-- QA candidates (priority 0, then 1) appear first; terminal rows remain visible.
ORDER BY priority IS NULL, priority, gmv_monthly DESC
LIMIT 300;
