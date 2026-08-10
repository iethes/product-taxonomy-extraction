-- sql/queries/qa_v2_tier1_sweep.sql
-- Tier-1 mechanical defect sweep, scoped to an explicit taxonomy_id list (the current worklist batch) rather
-- than a whole master_table -- see docs/superpowers/specs/2026-08-10-targeted-qa-fix-v2-design.md.
-- Ported verbatim from script/niq/targeted_qa_fix.sh's STEP 2 (same ten flags, same regex bodies).
-- Params: @taxonomy_ids ARRAY<STRING>

SELECT pt.taxonomy_id, pt.canonical_name, bd.canonical_name AS brand,
  REGEXP_CONTAINS(LOWER(pt.canonical_name), r'\b(undefined|null|n/a|tbd|all variants?|all sizes?|multiple variants?|multiple sizes?)\b') AS stub_leak,
  (LENGTH(pt.canonical_name) - LENGTH(REPLACE(pt.canonical_name, bd.canonical_name, ''))) / GREATEST(LENGTH(bd.canonical_name),1) >= 2 AS duplicate_brand,
  NOT STARTS_WITH(LOWER(TRIM(pt.canonical_name)), LOWER(bd.canonical_name)) AS wrong_field_order,
  (STARTS_WITH(LOWER(pt.canonical_name), LOWER(bd.canonical_name)) AND NOT STARTS_WITH(pt.canonical_name, bd.canonical_name)) AS brand_casing_mismatch,
  (ARRAY_LENGTH(REGEXP_EXTRACT_ALL(pt.canonical_name, r'\d+\s*(?:ml|g|kg|l|L)\b')) > 1 OR ARRAY_LENGTH(REGEXP_EXTRACT_ALL(pt.canonical_name, r'x\d+\b')) > 1) AS excess_content,
  (
    (SELECT LOGICAL_OR(LOWER(pt.canonical_name) NOT LIKE CONCAT('%', w, '%'))
     FROM UNNEST(SPLIT(LOWER(pt.product_line), ' ')) w WHERE w != '')
    OR (pt.sub_line IS NOT NULL AND (SELECT LOGICAL_OR(LOWER(pt.canonical_name) NOT LIKE CONCAT('%', w, '%'))
        FROM UNNEST(SPLIT(LOWER(pt.sub_line), ' ')) w WHERE w != ''))
    OR (pt.variant IS NOT NULL AND (SELECT LOGICAL_OR(LOWER(pt.canonical_name) NOT LIKE CONCAT('%', w, '%'))
        FROM UNNEST(SPLIT(LOWER(pt.variant), ' ')) w WHERE w != ''))
    OR (pt.size IS NOT NULL AND NOT LOWER(pt.canonical_name) LIKE CONCAT('%', LOWER(pt.size), '%'))
    OR (pt.pack_count > 1 AND pt.is_bundle IS NOT TRUE AND NOT LOWER(pt.canonical_name) LIKE CONCAT('%x', CAST(pt.pack_count AS STRING), '%'))
  ) AND NOT REGEXP_CONTAINS(LOWER(pt.canonical_name), r'\(all\s+(variants?|sizes?)\b|\bmultiple\s+(variants?|sizes?)\b') AS canonical_field_mismatch,
  (pt.size IS NULL AND pt.is_multi_size IS NOT TRUE) AS null_size,
  NOT REGEXP_CONTAINS(bd.canonical_name, r'[\p{L}]') AS garbage_brand,
  (pt.size IS NOT NULL AND REGEXP_CONTAINS(LOWER(pt.size), r'\b(pcs?|capsules?|sachets?|packets?|tablets?|pieces?|units?|ea|count)\b') AND NOT REGEXP_CONTAINS(LOWER(pt.size), r'\d+(\.\d+)?\s*(ml|g|kg|l|oz|lb)\b')) AS count_as_size,
  (REGEXP_CONTAINS(pt.canonical_name, r'(?i)\b(ready stock|100%\s*original|direct from|fast shipping|local seller|\w+\s+seller|latest packaging|similar to)\b') OR REGEXP_CONTAINS(pt.canonical_name, r'[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}]')) AS provenance_leak
FROM `sincere-hearth-273704.magpie_reference.product_taxonomy` pt
JOIN `sincere-hearth-273704.magpie_reference.brand_dict` bd ON bd.brand_id = pt.brand_id
WHERE pt.taxonomy_id IN UNNEST(@taxonomy_ids)
GROUP BY 1,2,3,pt.product_line,pt.sub_line,pt.variant,pt.size,pt.pack_count,pt.is_multi_size,pt.is_bundle
