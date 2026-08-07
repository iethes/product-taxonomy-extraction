#!/usr/bin/env bash
set -euo pipefail

# Usage: script/non_niq/non_niq_qa.sh <DATASET> <PLATFORM> [MAX_TURNS]
# e.g.  script/non_niq/non_niq_qa.sh babybath shopee
#       script/non_niq/non_niq_qa.sh babybath shopee 400
#
# Agentic QA harness for one (dataset, platform) pair -- issue #2's decision tree (relevance ->
# correct/re-point -> match-or-create), Meilisearch hybrid retrieval instead of the POC's brute
# keyword scoring, confidence loop encoded in product_id_dict_qa's existing _meta JSON.
# See docs/superpowers/specs/2026-08-06-non-niq-agentic-qa-design.md for the full design.

PROJECT="sincere-hearth-273704"
MEILI_URL="http://34.124.146.29:7700"

default_month_query() {
  local source_table="$1"
  echo "SELECT FORMAT_DATE('%Y-%m', MAX(month)) FROM \`${PROJECT}.${source_table}\`"
}

# Scope per issue #2: latest month, top 90% cumulative GMV per ecommerce_platform (NOT the epic's
# general 95% -- QA uses a different threshold on purpose). Priority: rows with no QA-table entry
# yet come first (priority 0), then rows the agent already marked unconfident but hasn't yet
# capped out on retry (priority 1) -- human_review=true rows are excluded entirely, they're
# terminal. Every _meta read uses SAFE.JSON_VALUE -- _meta is not always valid JSON in production
# (empty strings, literal "nan" both observed live) and bare JSON_VALUE raises on malformed input.
worklist_query() {
  local source_table="$1" qa_table="$2" qa_pk_col="$3" month="$4" platform="$5"
  cat <<SQL
WITH base AS (
  SELECT s.product_id, s.sku_name, s.image, s.ecommerce_platform, s.qa_status,
         COALESCE(s.flag_GWP, FALSE) OR REGEXP_CONTAINS(UPPER(s.sku_name), r'\[NOT FOR SALE\]|\[GWP\]') AS flag_GWP,
         s.gmv_monthly
  FROM \`${PROJECT}.${source_table}\` s
  WHERE FORMAT_DATE('%Y-%m', s.month) = '${month}' AND s.ecommerce_platform = '${platform}'
),
with_cumulative AS (
  SELECT *,
    ROUND(100.0 * SUM(CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END)
            OVER (ORDER BY gmv_monthly DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
          / NULLIF(SUM(CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END) OVER (), 0), 2) AS cumulative_gmv_pct
  FROM base
),
scoped AS (
  SELECT * FROM with_cumulative WHERE cumulative_gmv_pct <= 90
),
qa_state AS (
  SELECT ${qa_pk_col} AS product_id,
         SAFE.JSON_VALUE(_meta, '\$.qa_confidence') AS qa_confidence,
         SAFE.JSON_VALUE(_meta, '\$.human_review') AS human_review
  FROM \`${PROJECT}.${qa_table}\`
)
SELECT sc.product_id, sc.sku_name, sc.image, sc.gmv_monthly,
  CASE
    WHEN qs.product_id IS NULL AND sc.qa_status = 'Not Reviewed' THEN 0
    WHEN qs.qa_confidence = 'unconfident' AND COALESCE(qs.human_review, 'false') != 'true' THEN 1
    ELSE NULL
  END AS priority
FROM scoped sc
LEFT JOIN qa_state qs ON qs.product_id = sc.product_id
WHERE (qs.product_id IS NULL AND sc.qa_status = 'Not Reviewed')
   OR (qs.qa_confidence = 'unconfident' AND COALESCE(qs.human_review, 'false') != 'true')
ORDER BY priority ASC, gmv_monthly DESC
SQL
}

# Given the Sheet's raw filter_table cell (possibly ";"-separated, e.g. a category cross-
# referencing another category's filter table), returns the ONE table living in this row's own
# dataset -- the only one this harness ever writes to. Any other semicolon-separated entry is
# read-only reference (checked before flagging, per the spec, but never written to) and is
# intentionally not returned by this function.
primary_filter_table() {
  local filter_table_config="$1" dataset="$2"
  local entry
  IFS=';' read -ra entries <<< "$filter_table_config"
  for entry in "${entries[@]}"; do
    if [[ "$entry" == "${dataset}."* ]]; then
      echo "$entry"
      return 0
    fi
  done
  echo "${entries[0]}"
}
