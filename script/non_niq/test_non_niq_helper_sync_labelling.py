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

print("OK")
