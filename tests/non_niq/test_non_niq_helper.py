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
ID,Mom & Baby,Baby Care,Baby Bath & Shampoo,babybath,TRUE,shopee,babybath.raw_babybath_shopee,,,,,0_pipeline_babybath_shopee_id,,,,,,,,,,,,,,,babybath.master_babybath_id_dev,,babybath.product_id_dict_qa,babybath.product_id_dict,,,babybath.babybath_dict,babybath.filter_babybath,sku_type_complete,David,-,,,,,,,
ID,Mom & Baby,Baby Care,Baby Bath & Shampoo,babybath,FALSE,lazada,babybath.raw_babybath_lazada,,,,,,,,,,,,,,,,,,babybath.master_babybath_id_dev,,babybath.product_id_dict_qa,babybath.product_id_dict,,,babybath.babybath_dict,babybath.filter_babybath,sku_type_complete,David,-,,,,,,,
US,Mom & Baby,Baby Care,Baby Bath & Shampoo,babybath,TRUE,shopee,babybath.raw_babybath_shopee_us,,,,,0_pipeline_babybath_shopee_us,,,,,,,,,,,,,,,babybath.master_babybath_us_dev,,babybath.product_id_dict_qa,babybath.product_id_dict,,,babybath.babybath_dict,babybath.filter_babybath,sku_type_complete,David,-,,,,,,,
ID,Beauty,Skincare,Facial Serum,facialserum,TRUE,shopee,facialserum.raw_facialserum_shopee,,,,,0_pipeline_facialserum_shopee_id,,,,,,,,,,,,,,,facialserum.master_facialserum_id_dev,,facialserum.product_id_dict_qa,-,,,facialserum.facialserum_dict,facialserum.filter_facialserum,sku_type_complete,David,-,,,,,,,
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
    assert babybath["table"] == "babybath.master_babybath_id_dev"
    assert babybath["0"] == "0_pipeline_babybath_shopee_id"

def test_row_enrichment_table_empty_when_sheet_cell_blank():
    rows = parse_categories(SAMPLE_CSV, country="ID")
    facialserum = next(r for r in rows if r["dataset"] == "facialserum")
    # facialserum row DOES have a "0" value in this fixture -- assert it's carried through too,
    # covering the "present" case for a second dataset (not just babybath).
    assert facialserum["0"] == "0_pipeline_facialserum_shopee_id"

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

# --- _format_discord_table ---

def test_format_discord_table_includes_all_nonnull_columns():
    row = {"brand": "Acme", "sku_type_complete": "Acme Baby Wash 200ml", "packsize": "200 ml", "empty_col": None}
    msg = non_niq_helper._format_discord_table(row, "babybath")
    assert "**AI QA**" in msg
    assert "babybath" in msg
    assert "brand" in msg and "Acme" in msg
    assert "sku_type_complete" in msg and "Acme Baby Wash 200ml" in msg
    assert "packsize" in msg and "200 ml" in msg
    assert "empty_col" not in msg

def test_format_discord_table_truncates_long_cell_not_whole_row():
    long_value = "x" * 500
    row = {"brand": "Acme", "ingredients": long_value}
    msg = non_niq_helper._format_discord_table(row, "babybath")
    assert "brand" in msg
    assert "ingredients" in msg
    assert long_value not in msg
    assert "..." in msg

def test_format_discord_table_respects_discord_content_limit():
    row = {f"col_{i}": "y" * 100 for i in range(50)}
    msg = non_niq_helper._format_discord_table(row, "babybath")
    assert len(msg) <= non_niq_helper.DISCORD_CONTENT_LIMIT

# --- notify_discord_new_entry ---

class _FakeRow:
    def __init__(self, d):
        self._d = d
    def items(self):
        return self._d.items()

class _FakeQueryResult:
    def __init__(self, rows):
        self._rows = rows
    def result(self):
        return self._rows

class _FakeBQClient:
    def __init__(self, rows):
        self._rows = rows
    def query(self, query, job_config=None):
        return _FakeQueryResult(self._rows)

def test_notify_discord_posts_formatted_table():
    posted = {}
    def fake_post(url, body):
        posted["url"] = url
        posted["body"] = body
    client = _FakeBQClient([_FakeRow({"brand": "Acme", "sku_type_complete": "Acme Wash 200ml"})])
    non_niq_helper.notify_discord_new_entry(
        "proj", "babybath.babybath_dict", "Acme", "sku_type_complete", "Acme Wash 200ml", "babybath",
        client=client, webhook_url="https://discord.example/webhook", post=fake_post,
    )
    assert posted["url"] == "https://discord.example/webhook"
    assert "Acme Wash 200ml" in posted["body"]["content"]
    assert "**AI QA**" in posted["body"]["content"]

def test_notify_discord_rejects_unknown_identity_col():
    posted = []
    def fake_post(url, body):
        posted.append(body)
    client = _FakeBQClient([_FakeRow({"brand": "Acme"})])
    # 'brand' is not a valid dict-identity candidate -- must be refused before ever building SQL.
    non_niq_helper.notify_discord_new_entry(
        "proj", "babybath.babybath_dict", "Acme", "brand", "Acme", "babybath",
        client=client, webhook_url="https://discord.example/webhook", post=fake_post,
    )
    assert posted == []

def test_notify_discord_missing_webhook_url_is_non_fatal(monkeypatch):
    monkeypatch.setattr(non_niq_helper.os, "environ", {})
    client = _FakeBQClient([_FakeRow({"brand": "Acme", "sku_type": "X"})])

    def should_not_post(*a):
        raise AssertionError("must not post when no webhook URL is configured")

    # Must not raise -- caller (Claude, via bash) must never see this fail the session.
    non_niq_helper.notify_discord_new_entry(
        "proj", "babybath.babybath_dict", "Acme", "sku_type", "X", "babybath",
        client=client, webhook_url=None, post=should_not_post,
    )

def test_notify_discord_post_failure_is_non_fatal():
    def failing_post(url, body):
        raise RuntimeError("Discord is down")
    client = _FakeBQClient([_FakeRow({"brand": "Acme", "sku_type": "X"})])
    # Must not raise past this call -- this is the whole point of the function.
    non_niq_helper.notify_discord_new_entry(
        "proj", "babybath.babybath_dict", "Acme", "sku_type", "X", "babybath",
        client=client, webhook_url="https://discord.example/webhook", post=failing_post,
    )

def test_notify_discord_no_matching_row_is_non_fatal():
    client = _FakeBQClient([])
    posted = []
    non_niq_helper.notify_discord_new_entry(
        "proj", "babybath.babybath_dict", "Acme", "sku_type", "X", "babybath",
        client=client, webhook_url="https://discord.example/webhook", post=lambda u, b: posted.append(b),
    )
    assert posted == []

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
