-- sql/queries/backfill_size_regex.sql
-- Fill-if-null size backfill. Same query runs once now (backfill) and later on a BigQuery
-- scheduled query (recurring) — see docs/llm-extraction-rules.md §2 for the schedule command.
--
-- Country filter is TH-only, per docs/plans/size-regex-pass-findings.md: ID has zero rows in
-- product_taxonomy_map today (no Intrepid/ID taxonomy extraction has ever run), so an ID filter
-- here would be a no-op. Revisit once that changes.
--
-- Join key is (product_id, platform, country) — marketshare_universe has no master_table column
-- (live schema drift from docs, see findings file); ecommerce_platform in that table corresponds
-- to product_taxonomy_map.platform, and this is the actual ADR-006 composite key anyway.

DECLARE latest_month DATE;
SET latest_month = (SELECT MAX(month) FROM `sincere-hearth-273704.magpie.marketshare_universe`);

UPDATE `sincere-hearth-273704.magpie_reference.product_taxonomy` t
SET size = parsed.parsed.size_text, updated_at = CURRENT_TIMESTAMP()
FROM (
  SELECT
    pt.taxonomy_id,
    `sincere-hearth-273704.magpie_reference.parse_size`(ANY_VALUE(u.sku_name)) AS parsed
  FROM `sincere-hearth-273704.magpie_reference.product_taxonomy` pt
  JOIN `sincere-hearth-273704.magpie_reference.product_taxonomy_map` m
    ON m.taxonomy_id = pt.taxonomy_id
  JOIN `sincere-hearth-273704.magpie.marketshare_universe` u
    ON u.product_id = m.product_id
    AND u.ecommerce_platform = m.platform
    AND u.country = m.country
    AND u.month = latest_month
  WHERE pt.size IS NULL
    AND pt.is_multi_size IS NOT TRUE
    AND pt.is_bundle IS NOT TRUE
    AND m.country = 'TH'
  GROUP BY pt.taxonomy_id
) parsed
WHERE t.taxonomy_id = parsed.taxonomy_id
  AND parsed.parsed.size_value IS NOT NULL;
