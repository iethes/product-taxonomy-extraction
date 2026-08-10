import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "script" / "niq"))
from qa_v2_worklist import (
    _validate_table, build_worklist_query, build_pending_recheck_query, build_tier1_sweep_query,
    build_taxonomy_candidates_query, build_brand_candidates_query, build_sample_sku_names_query,
    build_promote_query, clean_taxonomy_ids, assemble_worklist_json, TIER1_FLAG_COLUMNS,
)

def test_validate_table_accepts_safe_name():
    _validate_table("shopee_th_toothpaste")  # must not raise

def test_validate_table_rejects_unsafe_name():
    try:
        _validate_table("shopee_th_toothpaste`; DROP TABLE x;--")
        assert False, "expected ValueError"
    except ValueError:
        pass

def test_build_worklist_query_orders_never_reviewed_before_unconfident():
    sql, params = build_worklist_query("shopee_th_toothpaste", 200)
    assert "tier_rank ASC, gmv DESC" in sql
    assert "pt._meta IS NULL" in sql
    assert "review_confidence" in sql
    param_names = {p.name for p in params}
    assert param_names == {"table", "block_size"}

def test_build_pending_recheck_query_scopes_to_pending_bucket():
    sql, params = build_pending_recheck_query("shopee_th_toothpaste")
    assert "review_confidence') IS NULL" in sql
    assert "_meta IS NOT NULL" in sql
    assert {p.name for p in params} == {"table"}

def test_build_tier1_sweep_query_binds_taxonomy_ids_array():
    sql, params = build_tier1_sweep_query(["SKU-000001", "SKU-000002"])
    assert "UNNEST(@taxonomy_ids)" in sql
    assert len(params) == 1
    assert params[0].name == "taxonomy_ids"
    assert params[0].values == ["SKU-000001", "SKU-000002"]

def test_build_taxonomy_candidates_query_defaults_n_to_5():
    sql, params = build_taxonomy_candidates_query(["SKU-000001"])
    n_param = next(p for p in params if p.name == "n")
    assert n_param.value == 5

def test_build_brand_candidates_query_defaults_n_to_3():
    sql, params = build_brand_candidates_query(["SKU-000001"])
    n_param = next(p for p in params if p.name == "n")
    assert n_param.value == 3

def test_build_sample_sku_names_query_rejects_unsafe_table():
    try:
        build_sample_sku_names_query("bad`table", ["SKU-000001"])
        assert False, "expected ValueError"
    except ValueError:
        pass

def test_build_promote_query_sets_confident():
    sql, params = build_promote_query(["SKU-000001"])
    assert "'confident' AS review_confidence" in sql
    assert params[0].values == ["SKU-000001"]

def test_clean_taxonomy_ids_excludes_any_flagged_row():
    rows = [
        {"taxonomy_id": "SKU-1", **{f: False for f in TIER1_FLAG_COLUMNS}},
        {"taxonomy_id": "SKU-2", **{f: False for f in TIER1_FLAG_COLUMNS}, "null_size": True},
    ]
    assert clean_taxonomy_ids(rows) == ["SKU-1"]

def test_assemble_worklist_json_defaults_missing_candidates_to_empty():
    rows = [{"taxonomy_id": "SKU-1", "canonical_name": "Brand Product 100g", "tier": "unlabelled", "gmv": 500}]
    result = assemble_worklist_json(rows, {}, {}, {}, {})
    assert result == [{
        "taxonomy_id": "SKU-1", "canonical_name": "Brand Product 100g", "tier": "unlabelled", "gmv": 500,
        "tier1_flags": {}, "taxonomy_candidates": [], "brand_candidates": [], "sample_sku_names": [],
    }]

if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print(f"PASS: {name}")
    print("ALL TESTS PASSED")
