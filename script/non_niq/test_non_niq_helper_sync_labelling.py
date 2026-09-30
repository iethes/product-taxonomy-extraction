#!/usr/bin/env python3
"""Runnable self-check for non_niq_helper.py's update-labelling sync helpers -- no framework, no
network. Covers the tricky bits: worklist-identity normalization (never a wildcard-matching blank
identity), duplicate-row tie-breaking (most non-null fields, then latest _meta timestamp), and the
tier-bucket boundary math.
"""
from non_niq_helper import (
    build_worklist_identity, _non_null_count, select_duplicates_to_delete, tier_for_share,
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

# Malformed/missing _meta must not raise -- treated as an empty timestamp, not a crash.
missing_meta = {"product_id": "3", "brand": "C"}
has_meta = {"product_id": "3", "brand": "C", "_meta": "not json"}
to_delete = select_duplicates_to_delete({("3", "Shopee", "widget"): [missing_meta, has_meta]})
assert len(to_delete) == 1

# A single row (no duplicate) is never touched.
assert select_duplicates_to_delete({("4", "Shopee", "widget"): [complete]}) == []

# tier_for_share: cumulative-GMV-share bucket boundaries.
assert tier_for_share(0.0) == "Tier 1"
assert tier_for_share(0.8) == "Tier 1"
assert tier_for_share(0.8000001) == "Tier 2"
assert tier_for_share(0.9) == "Tier 2"
assert tier_for_share(0.9000001) == "Tier 3"
assert tier_for_share(1.0) == "Tier 3"

from non_niq_helper import (
    _platform_filter_sql, build_dedupe_lookup_sql, build_dedupe_delete_sql,
    build_master_sync_sql, build_tier_recalc_sql, build_tier_null_sql,
)

# _platform_filter_sql: Tokopedia's own first-party channel stays in the same population.
assert _platform_filter_sql("Tokopedia") == "IN ('Tokopedia', 'Tokopedia | Shop')"
assert _platform_filter_sql("Shopee") == "= @platform"

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
assert "FORMAT_DATE('%Y-%m', m.month) = @month" in sync_sql

sync_sql_no_extras = build_master_sync_sql("proj.ds.master", "sku_type", False, False)
assert "qa_status" not in sync_sql_no_extras
assert "source_pid" not in sync_sql_no_extras

tier_sql = build_tier_recalc_sql(
    "proj.ds.master", "proj.ds.filter", "IN ('Tokopedia', 'Tokopedia | Shop')",
)
assert "product_tier = t.new_tier" in tier_sql
assert "ecommerce_platform IN ('Tokopedia', 'Tokopedia | Shop')" in tier_sql
assert "NOT IN (SELECT product_id FROM `proj.ds.filter`)" in tier_sql
# The SQL's hardcoded CASE boundaries must match tier_for_share's thresholds exactly -- these two
# are independent representations of the same rule (one runs server-side over a whole partition,
# one is the pure Python mirror tested above), so a change to one without the other must fail here.
assert "cum_share <= 0.8 THEN 'Tier 1'" in tier_sql
assert "cum_share <= 0.9 THEN 'Tier 2'" in tier_sql

tier_null_sql = build_tier_null_sql("proj.ds.master", "proj.ds.filter", "= @platform")
assert "SET m.product_tier = NULL" in tier_null_sql
assert "ecommerce_platform = @platform" in tier_null_sql
assert "IN (SELECT product_id FROM `proj.ds.filter`)" in tier_null_sql

print("OK")
