1. Materialize the raw union (skip this in your dashboard queries)

Your raw CTE unions ~48 tables and gets rescanned every time anyone opens the dashboard. Turn it into a scheduled, incrementally-refreshed table instead of a CTE:

```sql
CREATE OR REPLACE TABLE `sincere-hearth-273704.magpie_reference.taxonomy_latest_gmv`
PARTITION BY DATE(_snapshot_ts)
CLUSTER BY category
AS
WITH raw AS (
  SELECT 'shopee_id_baby_diapers' AS category, product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_id_baby_diapers`
  UNION ALL
  SELECT 'shopee_id_makeup_face', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_id_makeup_face`
  UNION ALL
  SELECT 'shopee_sg_baby_accessories', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_sg_baby_accessories`
  UNION ALL
  SELECT 'shopee_sg_beer_and_lager', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_sg_beer_and_lager`
  UNION ALL
  SELECT 'shopee_sg_beverages', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_sg_beverages`
  UNION ALL
  SELECT 'shopee_sg_breakfast_cereals', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_sg_breakfast_cereals`
  UNION ALL
  SELECT 'shopee_sg_carbonated_drink', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_sg_carbonated_drink`
  UNION ALL
  SELECT 'shopee_sg_coffee', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_sg_coffee`
  UNION ALL
  SELECT 'shopee_sg_diapers', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_sg_diapers`
  UNION ALL
  SELECT 'shopee_sg_fabric_softener', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_sg_fabric_softener`
  UNION ALL
  SELECT 'shopee_sg_facial_cleanser', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_sg_facial_cleanser`
  UNION ALL
  SELECT 'shopee_sg_facial_moisturiser', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_sg_facial_moisturiser`
  UNION ALL
  SELECT 'shopee_sg_hair_conditioner_or_treatment', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_sg_hair_conditioner_or_treatment`
  UNION ALL
  SELECT 'shopee_sg_hand_and_body_moisturiser', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_sg_hand_and_body_moisturiser`
  UNION ALL
  SELECT 'shopee_sg_health_food_drink', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_sg_health_food_drink`
  UNION ALL
  SELECT 'shopee_sg_household_cleaner', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_sg_household_cleaner`
  UNION ALL
  SELECT 'shopee_sg_infant_milk', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_sg_infant_milk`
  UNION ALL
  SELECT 'shopee_sg_laundry_detergent', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_sg_laundry_detergent`
  UNION ALL
  SELECT 'shopee_sg_liquid_soap', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_sg_liquid_soap`
  UNION ALL
  SELECT 'shopee_sg_pet_food', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_sg_pet_food`
  UNION ALL
  SELECT 'shopee_sg_shampoo', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_sg_shampoo`
  UNION ALL
  SELECT 'shopee_sg_spirits', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_sg_spirits`
  UNION ALL
  SELECT 'shopee_sg_toilet_rolls', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_sg_toilet_rolls`
  UNION ALL
  SELECT 'shopee_sg_toothpaste', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_sg_toothpaste`
  UNION ALL
  SELECT 'shopee_sg_vitamin_mineral_health_supplements', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_sg_vitamin_mineral_health_supplements`
  UNION ALL
  SELECT 'shopee_th_adult_diapers', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_th_adult_diapers`
  UNION ALL
  SELECT 'shopee_th_baby_diapers', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_th_baby_diapers`
  UNION ALL
  SELECT 'shopee_th_body_wash', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_th_body_wash`
  UNION ALL
  SELECT 'shopee_th_cleanser', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_th_cleanser`
  UNION ALL
  SELECT 'shopee_th_coffee', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_th_coffee`
  UNION ALL
  SELECT 'shopee_th_conditioner', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_th_conditioner`
  UNION ALL
  SELECT 'shopee_th_detergent', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_th_detergent`
  UNION ALL
  SELECT 'shopee_th_drinking_water', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_th_drinking_water`
  UNION ALL
  SELECT 'shopee_th_fabric_softener', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_th_fabric_softener`
  UNION ALL
  SELECT 'shopee_th_liquid_milk', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_th_liquid_milk`
  UNION ALL
  SELECT 'shopee_th_make_up_face', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_th_make_up_face`
  UNION ALL
  SELECT 'shopee_th_milk_powder', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_th_milk_powder`
  UNION ALL
  SELECT 'shopee_th_moisturizer_for_body', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_th_moisturizer_for_body`
  UNION ALL
  SELECT 'shopee_th_moisturizer_for_face', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_th_moisturizer_for_face`
  UNION ALL
  SELECT 'shopee_th_pet_food', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_th_pet_food`
  UNION ALL
  SELECT 'shopee_th_shampoo', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_th_shampoo`
  UNION ALL
  SELECT 'shopee_th_softdrink', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_th_softdrink`
  UNION ALL
  SELECT 'shopee_th_suncare', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_th_suncare`
  UNION ALL
  SELECT 'shopee_th_toothbrush', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_th_toothbrush`
  UNION ALL
  SELECT 'shopee_th_toothpaste', product_id, gmv_monthly, month FROM `sincere-hearth-273704.master_clean_niq.shopee_th_toothpaste`
),
latest AS (
  SELECT category, MAX(month) AS latest_month FROM raw GROUP BY 1
)
SELECT
  r.category, r.product_id, SUM(r.gmv_monthly) AS gmv,
  CURRENT_TIMESTAMP() AS _snapshot_ts
FROM raw r
JOIN latest l ON r.category = l.category AND r.month = l.latest_month
GROUP BY 1, 2;
```

2. A progress view (your existing logic, pointed at the materialized table)

```sql
CREATE OR REPLACE VIEW `sincere-hearth-273704.magpie_reference.v_taxonomy_progress` AS
WITH ranked AS (
  SELECT *,
    SUM(gmv) OVER (PARTITION BY category ORDER BY gmv DESC, product_id)
      / NULLIF(SUM(gmv) OVER (PARTITION BY category), 0) AS cum_frac
  FROM `sincere-hearth-273704.magpie_reference.taxonomy_latest_gmv`
),
scope_a AS (SELECT * FROM ranked WHERE cum_frac <= 0.95),
dedup_map AS (
  SELECT *, ROW_NUMBER() OVER (
    PARTITION BY product_id, master_table
    ORDER BY CASE source WHEN 'LLM' THEN 0 ELSE 1 END, taxonomy_id
  ) AS rn
  FROM `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
),
labelled AS (
  SELECT s.*, m.taxonomy_id, pt._meta
  FROM scope_a s
  LEFT JOIN (SELECT * FROM dedup_map WHERE rn = 1) m
    ON s.product_id = m.product_id AND s.category = m.master_table
  LEFT JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` pt
    ON m.taxonomy_id = pt.taxonomy_id
)
SELECT
  DATETIME_TRUNC(CURRENT_DATETIME(), HOUR) AS snapshoted_at,
  category,
  COUNT(*) AS in_scope_95gmv_products,
  COUNTIF(taxonomy_id IS NOT NULL) AS labelled_products,
  ROUND(SAFE_DIVIDE(COUNTIF(taxonomy_id IS NOT NULL), COUNT(*)) * 100, 1) AS pct_95gmv_labelled,
  ROUND(SAFE_DIVIDE(SUM(IF(taxonomy_id IS NOT NULL, gmv, 0)), SUM(gmv)) * 100, 1) AS pct_gmv_labelled,
  ROUND(SAFE_DIVIDE(COUNTIF(JSON_VALUE(_meta, '$.review_confidence') = 'confident'), COUNTIF(taxonomy_id IS NOT NULL)) * 100, 1) AS pct_labelled_confident,
  ROUND(SAFE_DIVIDE(COUNTIF(JSON_VALUE(_meta, '$.review_confidence') = 'unconfident'), COUNTIF(taxonomy_id IS NOT NULL)) * 100, 1) AS pct_labelled_unconfident
FROM labelled
GROUP BY category;
```

3. A history table + BigQuery Scheduled Query (this is what gives you "progress," not just a snapshot)

```sql
CREATE TABLE IF NOT EXISTS `sincere-hearth-273704.magpie_reference.taxonomy_progress_history` (
  snapshoted_at DATETIME,
  category STRING,
  in_scope_95gmv_products INT64,
  labelled_products INT64,
  pct_95gmv_labelled FLOAT64,
  pct_gmv_labelled FLOAT64,
  pct_labelled_confident FLOAT64,
  pct_labelled_unconfident FLOAT64,
)
PARTITION BY DATETIME_TRUNC(snapshoted_at, HOUR)
CLUSTER BY category;
```

4. Scheduled script

```sql
INSERT INTO `sincere-hearth-273704.magpie_reference.taxonomy_progress_history`
SELECT * FROM `sincere-hearth-273704.magpie_reference.v_taxonomy_progress`;
```
