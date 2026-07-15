-- sql/functions/parse_size.sql
--
-- Deterministic size extractor. TH + ID unit keywords. Comma-as-decimal normalized only when it
-- precedes a unit keyword within 1-2 digits (distinguishes "2,5kg" from "1,000" thousands grouping).
-- Never guesses — returns NULL fields when no confident number+unit pair is found.

CREATE OR REPLACE FUNCTION `sincere-hearth-273704.magpie_reference.parse_size`(sku_name STRING)
RETURNS STRUCT<size_value FLOAT64, size_unit STRING, size_text STRING>
AS ((
  WITH normalized AS (
    SELECT REGEXP_REPLACE(
      sku_name,
      r'(\d+),(\d{1,2})(\s*(?:kg|g|ml|l|กรัม|ก\.|มล\.?|ลิตร))',
      r'\1.\2\3'
    ) AS s
  ),
  extracted AS (
    SELECT
      REGEXP_EXTRACT(LOWER(s), r'(\d+(?:\.\d+)?)\s*(?:kg|g|ml|l|กรัม|ก\.|มล\.?|ลิตร)') AS raw_num,
      REGEXP_EXTRACT(LOWER(s), r'\d+(?:\.\d+)?\s*(kg|g|ml|l|กรัม|ก\.|มล\.?|ลิตร)') AS raw_unit
    FROM normalized
  ),
  normalized_unit AS (
    SELECT
      raw_num,
      CASE raw_unit
        WHEN 'กรัม' THEN 'g'
        WHEN 'ก.' THEN 'g'
        WHEN 'มล.' THEN 'ml'
        WHEN 'มล' THEN 'ml'
        WHEN 'ลิตร' THEN 'l'
        ELSE raw_unit
      END AS unit
    FROM extracted
  )
  SELECT AS STRUCT
    SAFE_CAST(raw_num AS FLOAT64) AS size_value,
    unit AS size_unit,
    CASE WHEN raw_num IS NOT NULL THEN CONCAT(raw_num, unit) ELSE NULL END AS size_text
  FROM normalized_unit
));

-- ── Runnable check — run this block after creating the function above, before Task 3 depends on it ──
WITH cases AS (
  SELECT * FROM UNNEST([
    STRUCT('KAPASITAS 2,5kg Mesin Cuci Mini' AS sku_name, '2.5kg' AS expected),
    STRUCT('Sabun Mandi Cair 250ml' AS sku_name, '250ml' AS expected),
    STRUCT('โฟมล้างหน้า 100 มล.' AS sku_name, '100ml' AS expected),
    STRUCT('สบู่ก้อน 105ก.' AS sku_name, '105g' AS expected),
    STRUCT('Harga Promo Rp 1,000,000' AS sku_name, CAST(NULL AS STRING) AS expected)
  ])
)
SELECT
  sku_name,
  expected,
  `sincere-hearth-273704.magpie_reference.parse_size`(sku_name).size_text AS actual,
  expected IS NOT DISTINCT FROM `sincere-hearth-273704.magpie_reference.parse_size`(sku_name).size_text AS pass
FROM cases;
