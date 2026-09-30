#!/usr/bin/env python3
"""Runnable self-check for non_niq_helper.py's update-labelling sync helpers -- no framework, no
network. Covers the tricky bits: worklist-identity normalization (never a wildcard-matching blank
identity), duplicate-row tie-breaking (most non-null fields, then latest _meta timestamp, never a
legacy human-authored row), the tier-bucket boundary math, and per-platform tier scoping.
"""
from non_niq_helper import (
    build_worklist_identity, _non_null_count, select_duplicates_to_delete, tier_for_share,
    _row_delete_key,
)

# build_worklist_identity: normalizes whitespace, rejects blank product_id/sku_name.
assert build_worklist_identity(
    {"product_id": "1", "ecommerce_platform": "Shopee", "sku_name": "  Widget   A  "}
) == ("1", "Shopee", "Widget A")
assert build_worklist_identity(
    {"product_id": "", "ecommerce_platform": "Shopee", "sku_name": "Widget"}
) is None
assert build_worklist_identity(
    {"product_id": "1", "ecommerce_platform": "Shopee", "sku_name": "   "}
) is None

# _non_null_count ignores None, blank strings, and the literal "nan" text some legacy exports use.
assert _non_null_count({"a": "x", "b": None, "c": "", "d": "nan", "e": "y"}) == 2

# select_duplicates_to_delete: more complete row wins regardless of _meta timestamp.
sparse = {"product_id": "1", "brand": "A", "sku_type_complete": None,
          "_meta": '{"timestamp":"2026-09-29T00:00:00Z"}'}
complete = {"product_id": "1", "brand": "A", "sku_type_complete": "Widget",
            "_meta": '{"timestamp":"2026-09-01T00:00:00Z"}'}
assert select_duplicates_to_delete({("1", "Shopee", "widget"): [sparse, complete]}) == [sparse]

# Equal completeness -> latest _meta.timestamp wins, older one is deleted.
older = {"product_id": "2", "brand": "B", "_meta": '{"timestamp":"2026-09-01T00:00:00Z"}'}
newer = {"product_id": "2", "brand": "B", "_meta": '{"timestamp":"2026-09-29T00:00:00Z"}'}
assert select_duplicates_to_delete({("2", "Shopee", "widget"): [older, newer]}) == [older]

# A row with NO _meta key at all is the null-meta/human-row signal -- the group is skipped
# entirely (see the dedicated human_row/agent_row test below), never a crash and never a delete.
missing_meta = {"product_id": "3", "brand": "C"}
has_meta = {"product_id": "3", "brand": "C", "_meta": "not json"}
to_delete = select_duplicates_to_delete({("3", "Shopee", "widget"): [missing_meta, has_meta]})
assert to_delete == []

# A single row (no duplicate) is never touched.
assert select_duplicates_to_delete({("4", "Shopee", "widget"): [complete]}) == []

# A group containing a legacy human-authored row (no _meta at all) must NEVER be touched, even
# though it's a "duplicate" -- this repo has a documented history of human-row data loss, and an
# agent write must never be allowed to silently outrank a human one via the dedupe path.
human_row = {"product_id": "5", "brand": "D", "sku_type_complete": "Widget"}
agent_row = {"product_id": "5", "brand": "D", "sku_type_complete": "Widget",
             "_meta": '{"timestamp":"2026-09-29T00:00:00Z","qa_confidence":"confident"}'}
assert select_duplicates_to_delete({("5", "Shopee", "widget"): [human_row, agent_row]}) == []
# Same rule when the human row has an explicit blank _meta string rather than a missing key.
human_row_blank = {"product_id": "5b", "brand": "D", "_meta": ""}
assert select_duplicates_to_delete({("5b", "Shopee", "widget"): [human_row_blank, agent_row]}) == []

# Non-dict _meta JSON (a bare number, a list) must not raise AttributeError on .get -- treated as
# no timestamp, not a crash.
weird_meta_a = {"product_id": "6", "brand": "E", "_meta": "123"}
weird_meta_b = {"product_id": "6", "brand": "E", "_meta": "[1,2]"}
to_delete = select_duplicates_to_delete({("6", "Shopee", "widget"): [weird_meta_a, weird_meta_b]})
assert len(to_delete) == 1

# A full tie (identical non-null count, no usable timestamp on either row) must still resolve the
# same way regardless of input order -- never depend on whatever order BigQuery happens to return.
tie_a = {"product_id": "7", "brand": "F", "extra": "1", "_meta": '{"timestamp":"2026-01-01T00:00:00Z"}'}
tie_b = {"product_id": "7", "brand": "F", "extra": "2", "_meta": '{"timestamp":"2026-01-01T00:00:00Z"}'}
result_forward = select_duplicates_to_delete({("7", "Shopee", "widget"): [tie_a, tie_b]})
result_reversed = select_duplicates_to_delete({("7", "Shopee", "widget"): [tie_b, tie_a]})
assert result_forward == result_reversed

# tier_for_share: cumulative-GMV-share bucket boundaries.
assert tier_for_share(0.0) == "Tier 1"
assert tier_for_share(0.8) == "Tier 1"
assert tier_for_share(0.8000001) == "Tier 2"
assert tier_for_share(0.9) == "Tier 2"
assert tier_for_share(0.9000001) == "Tier 3"
assert tier_for_share(1.0) == "Tier 3"

# _row_delete_key: the exact tuple the DELETE statement matches on -- used to guard against ever
# deleting a row whose key collides with the row being kept.
key_row = {"product_id": "1", "ecommerce_platform": "Shopee", "sku_name": "Widget", "_meta": "{}"}
assert _row_delete_key(key_row, "product_id", "ecommerce_platform") == ("1", "Shopee", "Widget", "{}")

from non_niq_helper import (
    _raw_platform_values, build_dedupe_lookup_sql, build_dedupe_delete_sql,
    build_master_sync_sql, build_tier_recalc_sql, build_tier_null_sql,
)

# _raw_platform_values: Tokopedia's own first-party channel is windowed SEPARATELY from Tokopedia,
# never combined into one umbrella population -- combining them corrupts both platforms' tier
# (non_niq_qa_v2.sh:232-234). Every other platform is just itself.
assert _raw_platform_values("Tokopedia") == ("Tokopedia", "Tokopedia | Shop")
assert _raw_platform_values("Shopee") == ("Shopee",)

lookup_sql = build_dedupe_lookup_sql("proj.ds.qa", "product_id", "ecommerce_platform")
assert "FROM `proj.ds.qa` q" in lookup_sql
assert "q.product_id = i.product_id" in lookup_sql
assert "q.ecommerce_platform = i.platform" in lookup_sql

delete_sql = build_dedupe_delete_sql("proj.ds.qa", "product_id", "ecommerce_platform")
assert "DELETE FROM `proj.ds.qa`" in delete_sql
assert "product_id AS pid" in delete_sql
assert "IN UNNEST(@to_delete)" in delete_sql

sync_sql = build_master_sync_sql("proj.ds.master", "sku_type_complete", True, True)
assert "m.sku_type_complete = s.sku_type_complete" in sync_sql
assert "m.qa_status = 'Reviewed'" in sync_sql
assert "m.source_pid = s.source_pid" in sync_sql
# PARSE_DATE (not FORMAT_DATE) so the month predicate stays sargable against the table's own
# month-partitioning -- FORMAT_DATE on every row disables partition pruning entirely.
assert "m.month = PARSE_DATE('%Y-%m', @month)" in sync_sql
assert "FORMAT_DATE" not in sync_sql

sync_sql_no_extras = build_master_sync_sql("proj.ds.master", "sku_type", False, False)
assert "qa_status" not in sync_sql_no_extras
assert "source_pid" not in sync_sql_no_extras

# build_tier_recalc_sql now takes an EXACT platform value (parameterized as @platform, never a
# literal umbrella IN-clause) and aggregates GMV per product_id before windowing, so a master table
# with duplicate product_id rows (confirmed live on real data) doesn't blow up BigQuery's "UPDATE
# must match at most one source row" constraint.
tier_sql = build_tier_recalc_sql("proj.ds.master", "proj.ds.filter")
assert "product_tier = t.new_tier" in tier_sql
assert "ecommerce_platform = @platform" in tier_sql
assert "GROUP BY product_id" in tier_sql
assert "NOT IN (SELECT product_id FROM `proj.ds.filter`)" in tier_sql
assert "cum_share <= 0.8 THEN 'Tier 1'" in tier_sql
assert "cum_share <= 0.9 THEN 'Tier 2'" in tier_sql
assert "PARSE_DATE('%Y-%m', @month)" in tier_sql
assert "FORMAT_DATE" not in tier_sql
assert "Tokopedia" not in tier_sql  # never a literal platform value -- always @platform

tier_null_sql = build_tier_null_sql("proj.ds.master", "proj.ds.filter")
assert "SET m.product_tier = NULL" in tier_null_sql
assert "ecommerce_platform = @platform" in tier_null_sql
assert "IN (SELECT product_id FROM `proj.ds.filter`)" in tier_null_sql
assert "PARSE_DATE('%Y-%m', @month)" in tier_null_sql
assert "Tokopedia" not in tier_null_sql

print("OK")
