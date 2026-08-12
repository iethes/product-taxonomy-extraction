import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "script" / "non_niq"))
from non_niq_helper import (
    parse_categories, pick_column, QA_PK_CANDIDATES, DICT_IDENTITY_CANDIDATES, DICT_TYPO_CANDIDATES,
    _format_query_text, retrieve_candidates,
)
import non_niq_helper

SAMPLE_CSV = """country,category_1,category_2,category,dataset,is_active,ecommerce_platform,raw_table,children,filter_column,filter_value,,0,exclude_tiktok,variant,filter_variant,phasing,1,2-1,2-2,2-3,5,9,double_date,is_daily,10,9_table,table,master_table_prod,product_id_dict_qa,product_id_dict,product_id_dict_image_qa,product_id_image_taxonomy,dict,filter_table,sku_type_complete,PIC,isDoubleDate,keywords,taxonomy_url ,taxonomy_spreadsheet_id, taxonomy_sheet_name,labelling_config,last_active_month,qa_ai_labelling
ID,Mom & Baby,Baby Care,Baby Bath & Shampoo,babybath,TRUE,shopee,babybath.raw_babybath_shopee,,,,,,,,,,,,,,,,,,,master_babybath_id_dev,babybath.9_babybath_id,babybath.master_babybath_id,babybath.product_id_dict_qa,babybath.product_id_dict,-,-,babybath.babybath_dict,babybath.filter_babybath,sku_type_complete,David,-,,,,,,,
ID,Mom & Baby,Baby Care,Baby Bath & Shampoo,babybath,FALSE,lazada,babybath.raw_babybath_lazada,,,,,,,,,,,,,,,,,,,master_babybath_id_dev,babybath.9_babybath_id,babybath.master_babybath_id,babybath.product_id_dict_qa,babybath.product_id_dict,-,-,babybath.babybath_dict,babybath.filter_babybath,sku_type_complete,David,-,,,,,,,
US,Mom & Baby,Baby Care,Baby Bath & Shampoo,babybath,TRUE,shopee,babybath.raw_babybath_shopee_us,,,,,,,,,,,,,,,,,,,master_babybath_us_dev,babybath.9_babybath_us,babybath.master_babybath_us,babybath.product_id_dict_qa,babybath.product_id_dict,-,-,babybath.babybath_dict,babybath.filter_babybath,sku_type_complete,David,-,,,,,,,
ID,Beauty,Skincare,Facial Serum,facialserum,TRUE,shopee,facialserum.raw_facialserum_shopee,,,,,,,,,,,,,,,,,,,master_facialserum_id_dev,facialserum.9_facialserum_id,facialserum.master_facialserum_id,facialserum.product_id_dict_qa,-,-,-,facialserum.facialserum_dict,facialserum.filter_facialserum,sku_type_complete,David,-,,,,,,,
"""

# --- parse_categories ---

def test_filters_to_active_id_rows_only():
    rows = parse_categories(SAMPLE_CSV, country="ID")
    assert len(rows) == 2

def test_row_shape():
    rows = parse_categories(SAMPLE_CSV, country="ID")
    babybath = next(r for r in rows if r["dataset"] == "babybath")
    assert babybath["category"] == "Baby Bath & Shampoo"
    assert babybath["ecommerce_platform"] == "shopee"
    assert babybath["product_id_dict_qa"] == "babybath.product_id_dict_qa"
    assert babybath["product_id_dict"] == "babybath.product_id_dict"
    assert babybath["dict"] == "babybath.babybath_dict"
    assert babybath["filter_table"] == "babybath.filter_babybath"

def test_dash_means_not_configured():
    rows = parse_categories(SAMPLE_CSV, country="ID")
    facialserum = next(r for r in rows if r["dataset"] == "facialserum")
    assert facialserum["product_id_dict"] == "-"

def test_target_categories_filter():
    rows = parse_categories(SAMPLE_CSV, country="ID", target_categories=["Facial Serum"])
    assert len(rows) == 1
    assert rows[0]["dataset"] == "facialserum"

# --- pick_column ---

def test_pick_column_first_match_wins():
    assert pick_column({"product_id", "sku_name"}, QA_PK_CANDIDATES, "qa pk") == "product_id"
    assert pick_column({"prod_id", "sku_name"}, QA_PK_CANDIDATES, "qa pk") == "prod_id"

def test_pick_column_raises_when_no_candidate_present():
    try:
        pick_column({"totally_different_col"}, QA_PK_CANDIDATES, "qa pk")
        assert False, "should have raised"
    except ValueError as e:
        assert "qa pk" in str(e)

def test_dict_identity_candidates_prefer_complete():
    assert pick_column({"sku_type", "sku_type_complete"}, DICT_IDENTITY_CANDIDATES, "dict identity") == "sku_type_complete"
    assert pick_column({"sku_type"}, DICT_IDENTITY_CANDIDATES, "dict identity") == "sku_type"

def test_dict_typo_candidates():
    assert pick_column({"keyword_typo"}, DICT_TYPO_CANDIDATES, "dict typo") == "keyword_typo"
    assert pick_column({"keywords_typo"}, DICT_TYPO_CANDIDATES, "dict typo") == "keywords_typo"

# --- E5 prefix formatting ---

def test_format_query_text_for_search_queries():
    assert _format_query_text("baby shampoo") == "query: baby shampoo"

# --- retrieve_candidates ---

class _FakeVector(list):
    """A list that also answers .tolist(), matching the numpy-array shape retrieve_candidates
    calls .tolist() on -- real SentenceTransformer.encode() returns numpy arrays, not plain lists."""
    def tolist(self):
        return list(self)

class _FakeModel:
    """Deterministic stand-in for SentenceTransformer -- avoids a real model load in tests."""
    def encode(self, texts, **kwargs):
        return [_FakeVector([float(len(t))]) for t in texts]

def test_retrieve_candidates_preserves_order_and_shape(monkeypatch):
    calls = []

    def fake_meili_request(meili_url, method, path, body=None):
        calls.append((path, body["q"]))
        return {"hits": [{"product_id": "p-" + body["q"], "sku_name": body["q"], "brand": "B", "sku_type_complete": "T"}]}

    monkeypatch.setattr(non_niq_helper, "_meili_request", fake_meili_request)
    lines = [{"id": "1", "text": "shampoo a"}, {"id": "2", "text": "shampoo b"}]
    results = retrieve_candidates(lines, "http://fake", "babybath_taxonomy_qa", limit=5, model=_FakeModel())

    assert [r["id"] for r in results] == ["1", "2"]
    assert results[0]["candidates"][0]["sku_name"] == "shampoo a"
    assert results[1]["candidates"][0]["sku_name"] == "shampoo b"
    assert all(path == "/indexes/babybath_taxonomy_qa/search" for path, _ in calls)

def test_retrieve_candidates_one_failure_does_not_abort_batch(monkeypatch):
    def flaky_meili_request(meili_url, method, path, body=None):
        if body["q"] == "shampoo a":
            raise RuntimeError("Meilisearch unreachable: simulated")
        return {"hits": [{"product_id": "p2", "sku_name": body["q"], "brand": "B", "sku_type_complete": "T"}]}

    monkeypatch.setattr(non_niq_helper, "_meili_request", flaky_meili_request)
    lines = [{"id": "1", "text": "shampoo a"}, {"id": "2", "text": "shampoo b"}]
    results = retrieve_candidates(lines, "http://fake", "babybath_taxonomy_qa", limit=5, model=_FakeModel())

    assert results[0]["candidates"] == []
    assert len(results[1]["candidates"]) == 1

# --- categories CLI (same invocation shape non_niq_qa.sh actually uses: plain argv, no Windmill) ---

def test_cli_categories_prints_json():
    import os, tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False) as f:
        f.write(SAMPLE_CSV)
        path = f.name
    try:
        out = subprocess.run(
            [sys.executable, str(Path(__file__).parent.parent.parent / "script" / "non_niq" / "non_niq_helper.py"),
             "categories", "--country", "ID", "--csv-file", path],
            capture_output=True, text=True, check=True,
        )
        rows = json.loads(out.stdout)
        assert len(rows) == 2
    finally:
        os.unlink(path)

class _Monkeypatch:
    """Minimal stand-in for pytest's monkeypatch fixture -- this repo's tests run as plain
    functions under a bare __main__ runner, no pytest. setattr saves the original so later tests
    never see a patch applied by an earlier one."""
    def __init__(self):
        self._saved = []

    def setattr(self, obj, name, value):
        self._saved.append((obj, name, getattr(obj, name)))
        setattr(obj, name, value)

    def undo(self):
        for obj, name, value in reversed(self._saved):
            setattr(obj, name, value)


if __name__ == "__main__":
    import inspect
    for name, fn in list(globals().items()):
        if not name.startswith("test_"):
            continue
        if "monkeypatch" in inspect.signature(fn).parameters:
            mp = _Monkeypatch()
            try:
                fn(mp)
            finally:
                mp.undo()
        else:
            fn()
        print(f"PASS: {name}")
    print("ALL TESTS PASSED")
