-- sql/queries/00_discovery_id_scope_check.sql
-- Read-only. Run each SELECT below in order; dry-run first.

-- 1a. Cheap: latest month partition present in marketshare_universe.
SELECT MAX(month) AS latest_month
FROM `sincere-hearth-273704.magpie.marketshare_universe`;

-- 1b. Country breakdown for that one month partition only (narrow columns, partition-filtered).
DECLARE latest_month DATE;
SET latest_month = (SELECT MAX(month) FROM `sincere-hearth-273704.magpie.marketshare_universe`);

SELECT
  country,
  COUNT(*) AS row_count,
  COUNTIF(sku_name IS NOT NULL) AS sku_name_populated
FROM `sincere-hearth-273704.magpie.marketshare_universe`
WHERE month = latest_month
GROUP BY country
ORDER BY row_count DESC;

-- 1c. If 'ID' appeared in 1b: sample 20 sku_names to eyeball language plausibility.
SELECT product_id, master_table, sku_name
FROM `sincere-hearth-273704.magpie.marketshare_universe`
WHERE month = latest_month AND country = 'ID'
LIMIT 20;

-- 1d. Eligible NULL-size taxonomy rows by country (cheap — reference tables only, no universe join).
SELECT
  m.country,
  COUNT(DISTINCT pt.taxonomy_id) AS eligible_null_size_taxonomy_ids
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy` pt
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
  ON m.taxonomy_id = pt.taxonomy_id
WHERE pt.size IS NULL
  AND pt.is_multi_size IS NOT TRUE
  AND pt.is_bundle IS NOT TRUE
  AND m.country IN ('TH', 'ID')
GROUP BY m.country;

-- 1e. Of those, how many resolve to a real sku_name via marketshare_universe (confirms Task 3's join
--     actually works before committing to it). Partition-filtered to latest_month.
SELECT
  m.country,
  COUNT(DISTINCT pt.taxonomy_id) AS eligible,
  COUNT(DISTINCT IF(u.sku_name IS NOT NULL, pt.taxonomy_id, NULL)) AS resolvable_via_universe
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy` pt
JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
  ON m.taxonomy_id = pt.taxonomy_id
LEFT JOIN `sincere-hearth-273704.magpie.marketshare_universe` u
  ON u.product_id = m.product_id
  AND u.master_table = m.master_table
  AND u.month = latest_month
WHERE pt.size IS NULL
  AND pt.is_multi_size IS NOT TRUE
  AND pt.is_bundle IS NOT TRUE
  AND m.country IN ('TH', 'ID')
GROUP BY m.country;
