-- sql/queries/qa_v2_taxonomy_candidates.sql
-- For each worklist taxonomy_id, the top @n other product_taxonomy rows sharing the same brand_id, restricted
-- to review_confidence='confident', ranked by normalized edit distance on canonical_name. Reference/format
-- context for the QA judge only -- never a basis for an autonomous decision. See
-- docs/superpowers/specs/2026-08-10-targeted-qa-fix-v2-design.md.
-- Params: @taxonomy_ids ARRAY<STRING>, @n INT64

SELECT worklist_taxonomy_id, candidate_taxonomy_id, candidate_canonical_name, normalized_distance
FROM (
  SELECT
    base.taxonomy_id AS worklist_taxonomy_id,
    cand.taxonomy_id AS candidate_taxonomy_id,
    cand.canonical_name AS candidate_canonical_name,
    SAFE_DIVIDE(
      EDIT_DISTANCE(base.canonical_name, cand.canonical_name),
      GREATEST(LENGTH(base.canonical_name), LENGTH(cand.canonical_name))
    ) AS normalized_distance
  FROM `sincere-hearth-273704.magpie_reference.product_taxonomy` base
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy` cand
    ON cand.brand_id = base.brand_id
    AND cand.taxonomy_id != base.taxonomy_id
    AND JSON_VALUE(cand._meta, '$.review_confidence') = 'confident'
  WHERE base.taxonomy_id IN UNNEST(@taxonomy_ids)
)
QUALIFY ROW_NUMBER() OVER (PARTITION BY worklist_taxonomy_id ORDER BY normalized_distance ASC) <= @n
