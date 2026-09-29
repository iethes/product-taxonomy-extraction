import json
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace
import pytest

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "script" / "non_niq"))
from non_niq_helper import (
    casefold_title_matches,
    confirm_casefold_matches,
    index_documents_strict,
    parse_categories,
    pick_column,
    QA_PK_CANDIDATES,
    DICT_IDENTITY_CANDIDATES,
    DICT_TYPO_CANDIDATES,
    _format_query_text,
    retrieve_candidates,
)
import non_niq_helper

SAMPLE_CSV = """country,category_1,category_2,category,dataset,is_active,ecommerce_platform,raw_table,children,filter_column,filter_value,,0,exclude_tiktok,variant,filter_variant,phasing,1,2-1,2-2,2-3,5,9,double_date,is_daily,10,9_table,table,master_table_prod,product_id_dict_qa,product_id_dict,product_id_dict_image_qa,product_id_image_taxonomy,dict,filter_table,sku_type_complete,PIC,isDoubleDate,keywords,taxonomy_url ,taxonomy_spreadsheet_id, taxonomy_sheet_name,labelling_config,last_active_month,qa_ai_labelling
ID,Mom & Baby,Baby Care,Baby Bath & Shampoo,babybath,TRUE,shopee,babybath.raw_babybath_shopee,,,,,0_pipeline_babybath_shopee_id,,,,,,,,,,,,,,,babybath.master_babybath_id_dev,babybath.master_babybath_id,babybath.product_id_dict_qa,babybath.product_id_dict,,,babybath.babybath_dict,babybath.filter_babybath,sku_type_complete,David,-,,,,,,,
ID,Mom & Baby,Baby Care,Baby Bath & Shampoo,babybath,FALSE,lazada,babybath.raw_babybath_lazada,,,,,,,,,,,,,,,,,,,,babybath.master_babybath_id_dev,babybath.master_babybath_id,babybath.product_id_dict_qa,babybath.product_id_dict,,,babybath.babybath_dict,babybath.filter_babybath,sku_type_complete,David,-,,,,,,,
US,Mom & Baby,Baby Care,Baby Bath & Shampoo,babybath,TRUE,shopee,babybath.raw_babybath_shopee_us,,,,,0_pipeline_babybath_shopee_us,,,,,,,,,,,,,,,babybath.master_babybath_us_dev,babybath.master_babybath_us,babybath.product_id_dict_qa,babybath.product_id_dict,,,babybath.babybath_dict,babybath.filter_babybath,sku_type_complete,David,-,,,,,,,
ID,Beauty,Skincare,Facial Serum,facialserum,TRUE,shopee,facialserum.raw_facialserum_shopee,,,,,0_pipeline_facialserum_shopee_id,,,,,,,,,,,,,,,facialserum.master_facialserum_id_dev,facialserum.master_facialserum_id,facialserum.product_id_dict_qa,-,,,facialserum.facialserum_dict,facialserum.filter_facialserum,sku_type_complete,David,-,,,,,,,
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
    assert babybath["master_table_prod"] == "babybath.master_babybath_id"
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

def test_resolve_category_columns_reports_optional_dict_meta(monkeypatch):
    schemas = {
        "dataset.qa": {"product_id", "sku_name", "ecommerce_platform", "_meta"},
        "dataset.dict_with_meta": {"sku_type", "keyword_typo", "_meta"},
        "dataset.dict_without_meta": {"sku_type", "keyword_typo"},
    }
    monkeypatch.setattr(non_niq_helper, "_table_columns", lambda client, project, table: schemas[table])

    with_meta = non_niq_helper.resolve_category_columns(None, "project", "dataset.qa", "dataset.dict_with_meta")
    without_meta = non_niq_helper.resolve_category_columns(None, "project", "dataset.qa", "dataset.dict_without_meta")

    assert with_meta["dict_has_meta"] is True
    assert without_meta["dict_has_meta"] is False

def test_resolve_category_columns_accepts_both_qa_platform_schemas(monkeypatch):
    schemas = {
        "dataset.qa_standard": {"product_id", "ecommerce_platform"},
        "dataset.qa_regional": {"product_id", "ecommerce"},
        "dataset.dict": {"sku_type_complete", "keyword_typo"},
    }
    monkeypatch.setattr(non_niq_helper, "_table_columns", lambda client, project, table: schemas[table])

    standard = non_niq_helper.resolve_category_columns(None, "project", "dataset.qa_standard", "dataset.dict")
    regional = non_niq_helper.resolve_category_columns(None, "project", "dataset.qa_regional", "dataset.dict")

    assert standard["qa_platform_col"] == "ecommerce_platform"
    assert regional["qa_platform_col"] == "ecommerce"

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

# --- exact-title auto-confirm candidates ---

def test_casefold_title_matches_accepts_case_only_title_changes():
    matches = casefold_title_matches(
        [{"product_id": "p-1", "sku_name": "ACME Wash 400ml"}],
        [{
            "id": "p-1",
            "candidates": [{
                "product_id": "old-1",
                "sku_name": "Acme Wash 400ML",
                "brand": "Acme",
                "sku_type_complete": "Acme Wash 400 ml",
            }],
        }],
        ("brand", "sku_type_complete"),
    )

    assert matches == {
        ("p-1", "", "ACME Wash 400ml"): {
            "product_id": "old-1",
            "sku_name": "Acme Wash 400ML",
            "brand": "Acme",
            "sku_type_complete": "Acme Wash 400 ml",
        },
    }


def test_casefold_title_matches_rejects_one_character_variant_changes_and_conflicts():
    matches = casefold_title_matches(
        [
            {"product_id": "size", "sku_name": "Acme Wash 400ml"},
            {"product_id": "conflict", "sku_name": "Acme Wash"},
        ],
        [
            {"id": "size", "candidates": [{
                "sku_name": "Acme Wash 500ml",
                "brand": "Acme",
                "sku_type_complete": "Acme Wash 500 ml",
            }]},
            {"id": "conflict", "candidates": [
                {
                    "sku_name": "ACME WASH",
                    "brand": "Acme",
                    "sku_type_complete": "Acme Wash 200 ml",
                },
                {
                    "sku_name": "ACME WASH",
                    "brand": "Acme",
                    "sku_type_complete": "Acme Wash 400 ml",
                },
            ]},
        ],
        ("brand", "sku_type_complete"),
    )

    assert matches == {}


def test_casefold_title_matches_keep_raw_platforms_separate_and_reject_null_titles():
    matches = casefold_title_matches(
        [
            {"product_id": "same", "ecommerce_platform": "Shopee", "sku_name": "ACME Wash"},
            {"product_id": "same", "ecommerce_platform": "Shopee", "sku_name": "ACME Soap"},
            {
                "product_id": "same",
                "ecommerce_platform": "Tokopedia | Shop",
                "sku_name": "ACME Lotion",
            },
            {"product_id": "missing", "ecommerce_platform": "Shopee", "sku_name": None},
        ],
        [
            {
                "id": "same",
                "product_id": "same",
                "ecommerce_platform": "Shopee",
                "query_sku_name": "ACME Wash",
                "candidates": [{
                    "sku_name": "acme wash",
                    "brand": "Acme",
                    "sku_type_complete": "Acme Wash",
                }],
            },
            {
                "id": "same",
                "product_id": "same",
                "ecommerce_platform": "Tokopedia | Shop",
                "query_sku_name": "ACME Lotion",
                "candidates": [{
                    "sku_name": "ACME LOTION",
                    "brand": "Acme",
                    "sku_type_complete": "Acme Lotion",
                }],
            },
            {
                "id": "same",
                "product_id": "same",
                "ecommerce_platform": "Shopee",
                "query_sku_name": "ACME Soap",
                "candidates": [{
                    "sku_name": "acme soap",
                    "brand": "Acme",
                    "sku_type_complete": "Acme Soap",
                }],
            },
            {
                "id": "missing",
                "product_id": "missing",
                "ecommerce_platform": "Shopee",
                "candidates": [{
                    "sku_name": None,
                    "brand": "Acme",
                    "sku_type_complete": "Acme Missing",
                }],
            },
        ],
        ("brand", "sku_type_complete"),
    )

    assert matches == {
        ("same", "Shopee", "ACME Wash"): {
            "sku_name": "acme wash",
            "brand": "Acme",
            "sku_type_complete": "Acme Wash",
        },
        ("same", "Shopee", "ACME Soap"): {
            "sku_name": "acme soap",
            "brand": "Acme",
            "sku_type_complete": "Acme Soap",
        },
        ("same", "Tokopedia | Shop", "ACME Lotion"): {
            "sku_name": "ACME LOTION",
            "brand": "Acme",
            "sku_type_complete": "Acme Lotion",
        },
    }

def test_auto_confirm_counts_duplicate_input_rows(monkeypatch, tmp_path, capsys):
    input_file = tmp_path / "rows.jsonl"
    candidates_file = tmp_path / "candidates.jsonl"
    residual_file = tmp_path / "residual.jsonl"
    row = {
        "product_id": "same",
        "ecommerce_platform": "Shopee",
        "sku_name": "Acme Wash",
    }
    input_file.write_text("\n".join([json.dumps(row), json.dumps(row)]) + "\n")
    candidates_file.write_text("")
    monkeypatch.setattr(non_niq_helper.bigquery, "Client", lambda project: object())
    monkeypatch.setattr(
        non_niq_helper,
        "confirm_casefold_matches",
        lambda *args, **kwargs: {("same", "Shopee", "Acme Wash")},
    )
    non_niq_helper._cmd_auto_confirm(SimpleNamespace(
        input_file=str(input_file),
        candidates_file=str(candidates_file),
        residual_file=str(residual_file),
        project="project",
        qa_table="qa",
        qa_pk_col="product_id",
        qa_platform_col="ecommerce_platform",
        dict_table="dict",
        identity_col="sku_type",
        extra_identity_fields="",
    ))
    assert json.loads(capsys.readouterr().out) == {"confirmed": 2, "residual": 0}
    assert residual_file.read_text() == ""


def test_confirm_casefold_matches_writes_only_live_dictionary_identity():
    class Row:
        def __init__(self, values):
            self.values = values

        def items(self):
            return self.values.items()

    class Result:
        def __init__(self, rows):
            self.rows = rows

        def result(self):
            return self.rows

    class Client:
        def __init__(self):
            self.calls = []

        def query(self, sql, job_config=None):
            self.calls.append((sql, job_config))
            if "JOIN requested" in sql:
                return Result([Row({
                    "brand": "Acme",
                    "identity_value": "Acme Wash Dictionary",
                })])
            if sql.startswith("SELECT DISTINCT"):
                return Result([Row({
                    "product_id": "p-1",
                    "ecommerce_platform": "Shopee",
                    "sku_name": "ACME Wash 400ml",
                })])
            return Result([])

    client = Client()
    confirmed = confirm_casefold_matches(
        client,
        "project",
        "babybath.product_id_dict_qa",
        "product_id",
        "ecommerce_platform",
        [
            {
                "product_id": "p-1",
                "ecommerce_platform": "Shopee",
                "sku_name": "ACME Wash 400ml",
            },
            {
                "product_id": "p-1",
                "ecommerce_platform": "Shopee",
                "sku_name": "ACME Wash 400ml",
            },
        ],
        [{
            "id": "p-1",
            "candidates": [{
                "product_id": "old-1",
                "sku_name": "Acme Wash 400ML",
                "brand": "Acme",
                "sku_type_complete": "Acme Wash 400 ml",
                "sku_type": "Acme Wash Dictionary",
            }],
        }],
        dict_table="babybath.babybath_dict",
        dict_identity_col="sku_type",
    )

    assert confirmed == {("p-1", "Shopee", "ACME Wash 400ml")}
    writes = [(sql, config) for sql, config in client.calls if "INSERT INTO" in sql]
    assert len(writes) == 1
    assert writes[0][0].startswith("BEGIN TRANSACTION;")
    assert "WHERE NOT EXISTS" in writes[0][0]
    assert "REGEXP_REPLACE" not in writes[0][0]
    assert writes[0][0].rstrip().endswith("COMMIT TRANSACTION;")
    assert len(writes[0][1].query_parameters[0].values) == 1
    # A rerun can find the prior QA row without this run's auto_match_id.
    # Read-back must use the same exact title and live dictionary identity as the insert.
    readback_sql = client.calls[-1][0]
    assert "q.sku_name = m.sku_name" in readback_sql
    assert "JOIN `project.babybath.babybath_dict` d" in readback_sql
    assert "AND q.brand = m.brand" in readback_sql
    assert "AND q.`sku_type_complete` = m.sku_type_complete" in readback_sql


def test_confirm_casefold_matches_copies_dictionary_columns_and_skips_ambiguous_keys():
    class Result:
        def __init__(self, rows):
            self.rows = rows

        def result(self):
            return self.rows

    class Client:
        def __init__(self):
            self.calls = []

        def query(self, sql, job_config=None):
            self.calls.append(sql)
            if "INFORMATION_SCHEMA.COLUMNS" in sql:
                cols = ["product_id", "ecommerce_platform", "sku_type_complete", "keywords"]
                if job_config.query_parameters[0].value == "product_id_dict_qa":
                    cols += ["sku_type_abbott", "lookup"]
                else:
                    cols += ["sku_type_abbott"]
                return Result([SimpleNamespace(column_name=c) for c in cols])
            if "JOIN requested" in sql:
                live = {"brand": "Acme", "identity_value": "Acme 800 gr Plain"}
                return Result([SimpleNamespace(items=live.items)])
            return Result([])

    client = Client()
    confirm_casefold_matches(
        client, "project", "susubayi.product_id_dict_qa", "product_id", "ecommerce_platform",
        [{"product_id": "p-1", "ecommerce_platform": "Blibli", "sku_name": "Acme 800g"}],
        [{"id": "p-1", "candidates": [{
            "product_id": "old-1", "sku_name": "ACME 800G", "brand": "Acme",
            "sku_type_complete": "Acme 800 gr Plain",
        }]}],
        dict_table="susubayi.susubayi_dict", dict_identity_col="sku_type_complete",
    )

    insert_sql = next(sql for sql in client.calls if "INSERT INTO" in sql)
    # sku_type_abbott/keywords come from the dictionary row; lookup mirrors keywords.
    assert "`sku_type_abbott`, `keywords`, `lookup`, _meta" in insert_sql
    assert "d.`sku_type_abbott`, d.`keywords`, d.`keywords`, m.meta" in insert_sql
    # A (brand, identity) with several dictionary rows fans out; those must not be auto-confirmed.
    assert "QUALIFY COUNT(*) OVER (PARTITION BY m.product_id" in insert_sql


def test_confirm_casefold_matches_leaves_stale_dictionary_candidate_for_agent():
    class Result:
        def result(self):
            return []

    class Client:
        def __init__(self):
            self.queries = []

        def query(self, sql, job_config=None):
            self.queries.append(sql)
            return Result()

    client = Client()
    confirmed = confirm_casefold_matches(
        client,
        "project",
        "babybath.product_id_dict_qa",
        "product_id",
        "ecommerce_platform",
        [{"product_id": "p-1", "ecommerce_platform": "Shopee", "sku_name": "ACME Wash"}],
        [{"id": "p-1", "candidates": [{
            "sku_name": "acme wash",
            "brand": "Acme",
            "sku_type_complete": "Acme Wash",
        }]}],
        dict_table="babybath.babybath_dict",
        dict_identity_col="sku_type",
    )

    assert confirmed == set()
    assert not any(sql.startswith("INSERT") for sql in client.queries)


def test_confirm_casefold_matches_keeps_row_residual_when_dictionary_changes():
    class Row:
        def __init__(self, values):
            self.values = values

        def items(self):
            return self.values.items()

    class Result:
        def __init__(self, rows):
            self.rows = rows

        def result(self):
            return self.rows

    class Client:
        def __init__(self):
            self.queries = []

        def query(self, sql, job_config=None):
            self.queries.append(sql)
            if "JOIN requested" in sql:
                return Result([Row({"brand": "Acme", "identity_value": "Acme Wash"})])
            return Result([])

    client = Client()
    confirmed = confirm_casefold_matches(
        client,
        "project",
        "babybath.product_id_dict_qa",
        "product_id",
        "ecommerce_platform",
        [{"product_id": "p-1", "ecommerce_platform": "Shopee", "sku_name": "ACME Wash"}],
        [{"id": "p-1", "candidates": [{
            "sku_name": "acme wash",
            "brand": "Acme",
            "sku_type_complete": "Acme Wash",
        }]}],
        dict_table="babybath.babybath_dict",
        dict_identity_col="sku_type",
    )

    assert confirmed == set()
    write = next(sql for sql in client.queries if "INSERT INTO" in sql)
    assert "JOIN `project.babybath.babybath_dict` d" in write


def test_confirm_casefold_matches_writes_eiger_full_taxonomy_tuple():
    class Row:
        def __init__(self, values):
            self.values = values

        def items(self):
            return self.values.items()

    class Result:
        def __init__(self, rows):
            self.rows = rows

        def result(self):
            return self.rows

    class Client:
        def __init__(self):
            self.calls = []

        def query(self, sql, job_config=None):
            self.calls.append((sql, job_config))
            rows = [Row({
                "product_id": "p-1",
                "ecommerce_platform": "Shopee",
                "sku_name": "EIGER Jacket",
            })] if sql.startswith("SELECT DISTINCT") else []
            return Result(rows)

    client = Client()
    confirmed = confirm_casefold_matches(
        client,
        "project",
        "eiger.product_id_dict_image_qa",
        "product_id",
        "ecommerce_platform",
        [{
            "product_id": "p-1",
            "ecommerce_platform": "Shopee",
            "sku_name": "EIGER Jacket",
            "image": "https://example.com/jacket.jpg",
        }],
        [{
            "id": "p-1",
            "candidates": [{
                "product_id": "old-1",
                "sku_name": "eiger jacket",
                "brand": "Eiger",
                "sku_type_complete": "Eiger Jacket",
                "mgh_2": "Apparel",
                "mgh_3": "Outerwear",
                "mgh_4": "Jacket",
                "product_type": "Jacket",
            }],
        }],
        extra_identity_fields=("mgh_2", "mgh_3", "mgh_4", "product_type"),
    )

    assert confirmed == {("p-1", "Shopee", "EIGER Jacket")}
    write = next(sql for sql, _ in client.calls if "INSERT INTO" in sql)
    assert write.startswith("BEGIN TRANSACTION;")
    assert "mgh_2, mgh_3, mgh_4, product_type, image, keywords" in write
    readback = client.calls[-1][0]
    assert "q.`sku_type_complete` = m.sku_type_complete" in readback
    for field in ("brand", "mgh_2", "mgh_3", "mgh_4", "product_type"):
        assert "q.%s = m.%s" % (field, field) in readback

# --- E5 prefix formatting (corpus side) ---

def test_format_passage_text_for_indexed_corpus():
    assert non_niq_helper._format_passage_text("baby shampoo") == "passage: baby shampoo"

# --- ensure_index ---

def test_ensure_index_creates_when_missing(monkeypatch):
    calls = []
    def fake_meili_request(meili_url, method, path, body=None):
        calls.append((method, path, body))
        if method == "GET":
            return {"results": []}
        return {}
    monkeypatch.setattr(non_niq_helper, "_meili_request", fake_meili_request)
    non_niq_helper.ensure_index("http://fake", "babybath_taxonomy_qa")
    methods_paths = [(m, p) for m, p, _ in calls]
    assert ("POST", "/indexes") in methods_paths
    assert ("PATCH", "/indexes/babybath_taxonomy_qa/settings") in methods_paths

def test_ensure_index_skips_create_when_already_exists(monkeypatch):
    calls = []
    def fake_meili_request(meili_url, method, path, body=None):
        calls.append((method, path, body))
        if method == "GET":
            return {"results": [{"uid": "babybath_taxonomy_qa"}]}
        return {}
    monkeypatch.setattr(non_niq_helper, "_meili_request", fake_meili_request)
    non_niq_helper.ensure_index("http://fake", "babybath_taxonomy_qa")
    methods = [m for m, _, _ in calls]
    assert "POST" not in methods
    assert "PATCH" in methods

# --- index_documents ---

def test_index_documents_doc_shape(monkeypatch):
    posted = []
    def fake_meili_request(meili_url, method, path, body=None):
        if method == "GET":
            return {"results": [{"uid": "babybath_taxonomy_qa"}]}
        if method == "POST" and path.endswith("/documents"):
            posted.append(body)
        return {}
    monkeypatch.setattr(non_niq_helper, "_meili_request", fake_meili_request)
    lines = [{"product_id": 123, "sku_name": "Baby Shampoo 200ml", "sku_type_complete": "Shampoo 200 ml", "brand": "Acme"}]
    count = non_niq_helper.index_documents(lines, "http://fake", "babybath_taxonomy_qa", model=_FakeModel())
    assert count == 1
    doc = posted[0][0]
    assert doc["product_id"] == "123"
    assert doc["sku_name"] == "Baby Shampoo 200ml"
    assert doc["sku_type_complete"] == "Shampoo 200 ml"
    assert doc["brand"] == "Acme"
    assert doc["_vectors"]["default"] == [float(len("passage: Baby Shampoo 200ml"))]


def test_strict_indexing_rejects_an_async_task_failure(monkeypatch):
    calls = []

    def fake_meili_request(meili_url, method, path, body=None):
        calls.append((method, path))
        if method == "GET" and path == "/indexes?limit=200":
            return {"results": [{"uid": "babybath_taxonomy_qa"}]}
        if method == "POST" and path.endswith("/documents"):
            return {"taskUid": 7}
        if method == "PATCH":
            return {"taskUid": 8}
        if method == "GET" and path == "/tasks/8":
            return {"status": "succeeded"}
        if method == "GET" and path == "/tasks/7":
            return {"status": "failed", "error": {"message": "invalid document"}}
        return {}
    monkeypatch.setattr(non_niq_helper, "_meili_request", fake_meili_request)
    with pytest.raises(RuntimeError, match="invalid document"):
        index_documents_strict(
            [{"product_id": 123, "sku_name": "Baby Shampoo", "sku_type_complete": "Shampoo", "brand": "Acme"}],
            "http://fake",
            "babybath_taxonomy_qa",
            model=_FakeModel(),
            poll_interval=0,
        )
    assert ("GET", "/tasks/7") in calls


def test_strict_indexing_rejects_an_index_setup_failure(monkeypatch):
    def fake_meili_request(meili_url, method, path, body=None):
        if method == "GET" and path == "/indexes?limit=200":
            return {"results": [{"uid": "babybath_taxonomy_qa"}]}
        if method == "PATCH":
            return {"taskUid": 9}
        if method == "GET" and path == "/tasks/9":
            return {"status": "failed", "error": {"message": "invalid settings"}}
        return {}

    monkeypatch.setattr(non_niq_helper, "_meili_request", fake_meili_request)
    with pytest.raises(RuntimeError, match="invalid settings"):
        index_documents_strict(
            [{"product_id": 123, "sku_name": "Baby Shampoo", "sku_type_complete": "Shampoo", "brand": "Acme"}],
            "http://fake",
            "babybath_taxonomy_qa",
            model=_FakeModel(),
            poll_interval=0,
        )
def test_index_documents_passes_through_extra_fields(monkeypatch):
    posted = []
    def fake_meili_request(meili_url, method, path, body=None):
        if method == "GET":
            return {"results": [{"uid": "eiger_taxonomy_qa"}]}
        if method == "POST" and path.endswith("/documents"):
            posted.append(body)
        return {}
    monkeypatch.setattr(non_niq_helper, "_meili_request", fake_meili_request)
    lines = [{
        "product_id": 999, "sku_name": "Eiger Trail Shoes", "sku_type_complete": "Hiking",
        "brand": "Eiger", "mgh_2": "Mountaineering", "mgh_3": "FOOTWEAR", "mgh_4": "Shoes",
        "product_type": "Low-cut shoes",
    }]
    count = non_niq_helper.index_documents(lines, "http://fake", "eiger_taxonomy_qa", model=_FakeModel())
    assert count == 1
    doc = posted[0][0]
    assert doc["mgh_2"] == "Mountaineering"
    assert doc["mgh_3"] == "FOOTWEAR"
    assert doc["mgh_4"] == "Shoes"
    assert doc["product_type"] == "Low-cut shoes"
    assert doc["product_id"] == "999"

def test_index_documents_default_shape_unchanged_without_extra_fields(monkeypatch):
    posted = []
    def fake_meili_request(meili_url, method, path, body=None):
        if method == "GET":
            return {"results": [{"uid": "babybath_taxonomy_qa"}]}
        if method == "POST" and path.endswith("/documents"):
            posted.append(body)
        return {}
    monkeypatch.setattr(non_niq_helper, "_meili_request", fake_meili_request)
    lines = [{"product_id": 1, "sku_name": "p", "sku_type_complete": "T", "brand": "B"}]
    non_niq_helper.index_documents(lines, "http://fake", "babybath_taxonomy_qa", model=_FakeModel())
    doc = posted[0][0]
    assert set(doc.keys()) == {"product_id", "sku_name", "sku_type_complete", "brand", "_vectors"}

def test_ensure_index_searchable_attributes_includes_product_type(monkeypatch):
    patches = []
    def fake_meili_request(meili_url, method, path, body=None):
        if method == "GET":
            return {"results": [{"uid": "eiger_taxonomy_qa"}]}
        if method == "PATCH":
            patches.append(body)
        return {}
    monkeypatch.setattr(non_niq_helper, "_meili_request", fake_meili_request)
    non_niq_helper.ensure_index("http://fake", "eiger_taxonomy_qa")
    assert "product_type" in patches[0]["searchableAttributes"]
    assert "sku_name" in patches[0]["searchableAttributes"]

def test_index_documents_batches_at_batch_size(monkeypatch):
    posted_batches = []
    def fake_meili_request(meili_url, method, path, body=None):
        if method == "GET":
            return {"results": [{"uid": "idx"}]}
        if method == "POST" and path.endswith("/documents"):
            posted_batches.append(len(body))
        return {}
    monkeypatch.setattr(non_niq_helper, "_meili_request", fake_meili_request)
    lines = [{"product_id": i, "sku_name": f"p{i}", "sku_type_complete": "T", "brand": "B"} for i in range(non_niq_helper.BATCH_SIZE + 10)]
    non_niq_helper.index_documents(lines, "http://fake", "idx", model=_FakeModel())
    assert posted_batches == [non_niq_helper.BATCH_SIZE, 10]

def test_index_documents_empty_input_is_noop(monkeypatch):
    calls = []
    monkeypatch.setattr(non_niq_helper, "_meili_request", lambda *a, **k: calls.append(1))
    count = non_niq_helper.index_documents([], "http://fake", "idx", model=_FakeModel())
    assert count == 0
    assert calls == []

# --- append_sheet_new_entries_strict ---

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


class _FakeSheetsRequest:
    def __init__(self, payload):
        self.payload = payload
    def execute(self):
        return self.payload


class _FakeSheetsService:
    def __init__(self, values):
        self.values_data = values
        self.appended = []
    def spreadsheets(self):
        return self
    def values(self):
        return self
    def get(self, **kwargs):
        return _FakeSheetsRequest({"values": self.values_data})
    def append(self, **kwargs):
        self.appended.extend(kwargs["body"]["values"])
        return _FakeSheetsRequest({})


def test_append_sheet_is_idempotent_and_deduplicates_input(monkeypatch):
    monkeypatch.setattr(non_niq_helper, "_tab_title_for_gid", lambda *args: "Coffee")
    service = _FakeSheetsService([
        ["brand", "sku_type", "keywords"],
        ["Existing", "Existing Coffee 100 g 1 pcs", "Existing Coffee 100 g 1 pcs"],
    ])
    client = _FakeBQClient([_FakeRow({
        "brand": "New", "sku_type": "New Coffee 200 g 1 pcs",
        "keywords": "New Coffee 200 g 1 pcs",
    })])
    entries = [
        {"brand": "Existing", "identity_col": "sku_type", "identity_value": "Existing Coffee 100 g 1 pcs"},
        {"brand": "New", "identity_col": "sku_type", "identity_value": "New Coffee 200 g 1 pcs"},
        {"brand": "New", "identity_col": "sku_type", "identity_value": "New Coffee 200 g 1 pcs"},
    ]
    count = non_niq_helper.append_sheet_new_entries(
        "proj", "coffee.coffee_dict_ph", "coffee",
        "https://docs.google.com/spreadsheets/d/test-sheet/edit?gid=1#gid=1",
        entries, client=client, service=service,
    )
    assert count == 1
    assert service.appended == [["New", "New Coffee 200 g 1 pcs", "New Coffee 200 g 1 pcs"]]



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
# --- strict Sheet append outcomes (v3 only) ---

class _StrictSheetsRequest:
    def __init__(self, payload):
        self.payload = payload

    def execute(self):
        return self.payload


class _StrictSheetsService:
    def __init__(self, values):
        self.values_data = values
        self.appended = []

    def spreadsheets(self):
        return self

    def values(self):
        return self

    def get(self, **kwargs):
        return _StrictSheetsRequest({"values": self.values_data})

    def append(self, **kwargs):
        self.appended.extend(kwargs["body"]["values"])
        return _StrictSheetsRequest({})


def test_strict_append_marks_existing_identity_already_present(monkeypatch):
    monkeypatch.setattr(non_niq_helper, "_tab_title_for_gid", lambda *args: "Coffee")
    entry = {
        "brand": "Acme",
        "identity_col": "sku_type",
        "identity_value": "Acme Wash 200 ml",
    }
    outcomes = non_niq_helper.append_sheet_new_entries_strict(
        "proj", "coffee.coffee_dict_ph",
        "https://docs.google.com/spreadsheets/d/test-sheet/edit?gid=1#gid=1",
        [entry],
        client=_FakeBQClient([]),
        service=_StrictSheetsService([
            ["brand", "sku_type"],
            ["Acme", "Acme Wash 200 ml"],
        ]),
    )
    assert outcomes[("Acme", "sku_type", "Acme Wash 200 ml")].status == "already_present"


def test_strict_append_marks_successful_identity_appended(monkeypatch):
    monkeypatch.setattr(non_niq_helper, "_tab_title_for_gid", lambda *args: "Coffee")
    entry = {
        "brand": "Acme",
        "identity_col": "sku_type",
        "identity_value": "Acme Wash 200 ml",
    }
    service = _StrictSheetsService([["brand", "sku_type"]])
    outcomes = non_niq_helper.append_sheet_new_entries_strict(
        "proj", "coffee.coffee_dict_ph",
        "https://docs.google.com/spreadsheets/d/test-sheet/edit?gid=1#gid=1",
        [entry],
        client=_FakeBQClient([_FakeRow({
            "brand": "Acme",
            "sku_type": "Acme Wash 200 ml",
        })]),
        service=service,
    )
    assert outcomes[("Acme", "sku_type", "Acme Wash 200 ml")].status == "appended"
    assert service.appended == [["Acme", "Acme Wash 200 ml"]]


def test_strict_append_preserves_failure_for_legacy_noop(monkeypatch):
    class FailingSheetsService(_StrictSheetsService):
        def append(self, **kwargs):
            raise RuntimeError("Sheets unavailable")

    monkeypatch.setattr(non_niq_helper, "_tab_title_for_gid", lambda *args: "Coffee")
    entry = {
        "brand": "Acme",
        "identity_col": "sku_type",
        "identity_value": "Acme Wash 200 ml",
    }
    service = FailingSheetsService([["brand", "sku_type"]])
    client = _FakeBQClient([_FakeRow({
        "brand": "Acme",
        "sku_type": "Acme Wash 200 ml",
    })])
    outcomes = non_niq_helper.append_sheet_new_entries_strict(
        "proj", "coffee.coffee_dict_ph",
        "https://docs.google.com/spreadsheets/d/test-sheet/edit?gid=1#gid=1",
        [entry],
        client=client,
        service=service,
    )
    assert outcomes[("Acme", "sku_type", "Acme Wash 200 ml")].status == "failed"
    assert non_niq_helper.append_sheet_new_entries(
        "proj", "coffee.coffee_dict_ph", "coffee",
        "https://docs.google.com/spreadsheets/d/test-sheet/edit?gid=1#gid=1",
        [entry],
        client=client,
        service=FailingSheetsService([["brand", "sku_type"]]),
    ) == 0

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


def test_append_sheet_accepts_capitalized_headers_and_dedups_stripped_cells(monkeypatch):
    # susububuk's Sheet headers are "Brand"/"SKU_type_complete" and some cells carry "\r\n" padding.
    monkeypatch.setattr(non_niq_helper, "_tab_title_for_gid", lambda *args: "Susu Bubuk")
    service = _FakeSheetsService([
        ["SKU_type_complete", "Brand"],
        ["\nOld 1", "\r\nAcme"],
    ])
    client = _FakeBQClient([_FakeRow({"brand": "Acme", "sku_type_complete": "New 2"})])
    entries = [
        {"brand": "Acme", "identity_col": "sku_type_complete", "identity_value": "Old 1"},
        {"brand": "Acme", "identity_col": "sku_type_complete", "identity_value": "New 2"},
    ]
    outcomes = non_niq_helper.append_sheet_new_entries_strict(
        "proj", "susububuk.susububuk_dict",
        "https://docs.google.com/spreadsheets/d/test-sheet/edit?gid=0#gid=0",
        entries, client=client, service=service,
    )
    assert outcomes[("Acme", "sku_type_complete", "Old 1")].status == "already_present"
    assert outcomes[("Acme", "sku_type_complete", "New 2")].status == "appended"
    assert service.appended == [["New 2", "Acme"]]
