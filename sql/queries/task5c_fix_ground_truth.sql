-- sql/queries/task5c_fix_ground_truth.sql
-- Task 5c: fix 4 product_taxonomy_map rows in shopee_th_toothpaste's unambiguous bucket whose recorded
-- taxonomy_id points to a size that objectively contradicts the product's own parse_size(sku_name), AND
-- whose sole unambiguous brand+size candidate spot-checks clean (no false product-line/pack-count claim).
-- Guarded by matching the exact pre-verified old taxonomy_id, so this is a no-op if the row already changed.

-- 10390380966: Colgate MaxFresh Peppermint Ice 155g Pack 2 -- was SKU-047039 (150g, generic), fix to
-- SKU-055000 (Colgate MaxFresh Toothpaste 155g x2) -- exact line + size + pack match.
UPDATE `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
SET taxonomy_id = 'SKU-055000',
    confidence = '0.95',
    llm_raw = TO_JSON_STRING(STRUCT('task5c_ground_truth_size_fix' AS method,
      'recorded size 150g (SKU-047039) contradicts parse_size(sku_name)=155g; repointed to sole unambiguous brand+size candidate SKU-055000 (Colgate MaxFresh Toothpaste 155g x2)' AS reason)),
    meta_agent = 'CLAUDE_CODE',
    mapped_at = CURRENT_TIMESTAMP()
WHERE master_table = 'shopee_th_toothpaste'
  AND product_id = '10390380966' AND platform = 'Shopee' AND country = 'TH'
  AND taxonomy_id = 'SKU-047039';

-- 21024306852: Colgate Advance Whitening 135g -- was SKU-001044 (150g catch-all), fix to SKU-047037
-- (Colgate Toothpaste 135g) -- correct size, sole 135g candidate, generic name doesn't assert a wrong line.
UPDATE `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
SET taxonomy_id = 'SKU-047037',
    confidence = '0.95',
    llm_raw = TO_JSON_STRING(STRUCT('task5c_ground_truth_size_fix' AS method,
      'recorded size 150g (SKU-001044) contradicts parse_size(sku_name)=135g; repointed to sole unambiguous brand+size candidate SKU-047037 (Colgate Toothpaste 135g)' AS reason)),
    meta_agent = 'CLAUDE_CODE',
    mapped_at = CURRENT_TIMESTAMP()
WHERE master_table = 'shopee_th_toothpaste'
  AND product_id = '21024306852' AND platform = 'Shopee' AND country = 'TH'
  AND taxonomy_id = 'SKU-001044';

-- 47754649733: Colgate Himalayan Rose Salt 140g -- was SKU-055011 (150g "Colgate Salt Toothpaste"), fix to
-- SKU-047038 (Colgate Toothpaste 140g) -- correct size, sole 140g candidate; loses "Salt" specificity but
-- corrects an objectively wrong size, no false claim introduced.
UPDATE `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
SET taxonomy_id = 'SKU-047038',
    confidence = '0.95',
    llm_raw = TO_JSON_STRING(STRUCT('task5c_ground_truth_size_fix' AS method,
      'recorded size 150g (SKU-055011) contradicts parse_size(sku_name)=140g; repointed to sole unambiguous brand+size candidate SKU-047038 (Colgate Toothpaste 140g)' AS reason)),
    meta_agent = 'CLAUDE_CODE',
    mapped_at = CURRENT_TIMESTAMP()
WHERE master_table = 'shopee_th_toothpaste'
  AND product_id = '47754649733' AND platform = 'Shopee' AND country = 'TH'
  AND taxonomy_id = 'SKU-055011';

-- 54756259132: Colgate Herbs & Salt Formula 75g -- was SKU-055001 (150g "Colgate Salt Herbal Toothpaste"),
-- fix to SKU-047033 (Colgate Toothpaste 75g) -- correct size, sole 75g candidate; loses "Salt Herbal"
-- specificity but corrects an objectively wrong size (150g vs the stated 75g).
UPDATE `sincere-hearth-273704.magpie_reference.product_taxonomy_map`
SET taxonomy_id = 'SKU-047033',
    confidence = '0.95',
    llm_raw = TO_JSON_STRING(STRUCT('task5c_ground_truth_size_fix' AS method,
      'recorded size 150g (SKU-055001) contradicts parse_size(sku_name)=75g; repointed to sole unambiguous brand+size candidate SKU-047033 (Colgate Toothpaste 75g)' AS reason)),
    meta_agent = 'CLAUDE_CODE',
    mapped_at = CURRENT_TIMESTAMP()
WHERE master_table = 'shopee_th_toothpaste'
  AND product_id = '54756259132' AND platform = 'Shopee' AND country = 'TH'
  AND taxonomy_id = 'SKU-055001';
