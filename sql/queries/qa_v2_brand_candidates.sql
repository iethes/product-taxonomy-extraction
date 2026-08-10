-- sql/queries/qa_v2_brand_candidates.sql
-- For each worklist taxonomy_id, the top @n brand_dict entries (excluding its own brand_id) closest by
-- normalized edit distance to its own resolved brand name, capped at normalized_distance < 0.4. Surfaces
-- brand_id misattribution / brand-dict aliasing candidates for the QA judge -- reference only. See
-- docs/superpowers/specs/2026-08-10-targeted-qa-fix-v2-design.md.
-- Params: @taxonomy_ids ARRAY<STRING>, @n INT64

SELECT worklist_taxonomy_id, candidate_brand_id, candidate_canonical_name, normalized_distance
FROM (
  SELECT
    base.taxonomy_id AS worklist_taxonomy_id,
    cand.brand_id AS candidate_brand_id,
    cand.canonical_name AS candidate_canonical_name,
    SAFE_DIVIDE(
      EDIT_DISTANCE(base_brand.canonical_name, cand.canonical_name),
      GREATEST(LENGTH(base_brand.canonical_name), LENGTH(cand.canonical_name))
    ) AS normalized_distance
  FROM `sincere-hearth-273704.magpie_reference.product_taxonomy` base
  JOIN `sincere-hearth-273704.magpie_reference.brand_dict` base_brand ON base_brand.brand_id = base.brand_id
  JOIN `sincere-hearth-273704.magpie_reference.brand_dict` cand ON cand.brand_id != base.brand_id
  WHERE base.taxonomy_id IN UNNEST(@taxonomy_ids)
)
WHERE normalized_distance < 0.4
QUALIFY ROW_NUMBER() OVER (PARTITION BY worklist_taxonomy_id ORDER BY normalized_distance ASC) <= @n
