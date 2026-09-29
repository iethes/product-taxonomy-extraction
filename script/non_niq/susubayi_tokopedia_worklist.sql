-- Worklist query generated from script/non_niq/susubayi_qa.sh for:
--   ./script/non_niq/susubayi_qa.sh tokopedia
-- Resolved 2026-09-18: country=ID, month=2026-08, MAX_ROWS=300.
-- Tokopedia scope: product_tier IN ('Tier 1') OR principal = 'Official Store', plus the
-- configured merchant allowlist, regardless of gmv_monthly. Both 'Tokopedia' and
-- 'Tokopedia | Shop' source values match.

WITH scoped AS (
  SELECT s.product_id, s.sku_name, REPLACE(s.image, '"', '') AS image,
         s.ecommerce_platform,
         s.qa_status, s.gmv_monthly, NULL AS item_description, NULL AS product_attributes_attrs
  FROM `sincere-hearth-273704.susubayi.master_susubayi_id` s

  WHERE ((s.product_tier IN ('Tier 1') OR s.principal = 'Official Store') OR s.merchant_id IN ("11068432","12986932","2288160","2589683","3650675","3823913","3824444","3950239","6673792","6685466","763506"))
    AND FORMAT_DATE('%Y-%m', s.month) = '2026-08'
    AND s.ecommerce_platform IN ('Tokopedia', 'Tokopedia | Shop')
),
qa_title_state AS (
  SELECT DISTINCT product_id, ecommerce_platform,
    REGEXP_REPLACE(TRIM(sku_name), r'\s+', ' ') AS normalized_sku_name
  FROM `sincere-hearth-273704.susubayi.product_id_dict_qa`
  WHERE ecommerce_platform IN ('Tokopedia', 'Tokopedia | Shop')
),
qa_state AS (
  SELECT
    product_id AS product_id, ecommerce_platform,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '$.qa_confidence') = 'unconfident'
               AND COALESCE(JSON_VALUE(SAFE.PARSE_JSON(_meta), '$.human_review'), 'false') != 'true') AS has_unconfident_pending,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '$.qa_confidence') = 'confident') AS has_confident,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '$.human_review') = 'true') AS has_terminal
  FROM `sincere-hearth-273704.susubayi.product_id_dict_qa`
  WHERE ecommerce_platform IN ('Tokopedia', 'Tokopedia | Shop')
  GROUP BY product_id, ecommerce_platform
),
filter_state AS (
  SELECT DISTINCT product_id FROM `sincere-hearth-273704.susubayi.filter_susubayi_wyeth`
),
prioritized AS (
  SELECT sc.product_id, sc.sku_name, sc.image, sc.gmv_monthly, sc.ecommerce_platform,
         sc.item_description, sc.product_attributes_attrs,
    CASE
      WHEN fs.product_id IS NOT NULL THEN NULL
      WHEN qts.product_id IS NULL THEN 0
      WHEN qs.has_unconfident_pending AND NOT qs.has_confident AND NOT qs.has_terminal THEN 1
      ELSE NULL
    END AS priority
  FROM scoped sc
  LEFT JOIN qa_title_state qts
    ON qts.product_id = sc.product_id
   AND qts.ecommerce_platform = sc.ecommerce_platform
   AND qts.normalized_sku_name = REGEXP_REPLACE(TRIM(sc.sku_name), r'\s+', ' ')
  LEFT JOIN qa_state qs
    ON qs.product_id = sc.product_id
   AND qs.ecommerce_platform = sc.ecommerce_platform
  LEFT JOIN filter_state fs ON fs.product_id = sc.product_id
)
SELECT * FROM prioritized
WHERE priority IS NOT NULL
ORDER BY priority ASC, gmv_monthly DESC
LIMIT 300
;
