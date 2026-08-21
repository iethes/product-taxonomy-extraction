import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "script" / "niq"))
from headless_v2_worklist import (
    parse_table_name, jaccard_similarity, find_sibling_tables, build_candidate_products_query,
)


def test_parse_table_name_splits_platform_country_category():
    platform, country, tokens = parse_table_name("shopee_id_adult_diapers")
    assert platform == "shopee"
    assert country == "id"
    assert tokens == frozenset({"adult", "diapers"})


def test_parse_table_name_strips_stopwords_from_category_tokens():
    _, _, tokens = parse_table_name("shopee_id_hand_and_body_lotion")
    assert tokens == frozenset({"hand", "body", "lotion"})


def test_jaccard_similarity_identical_sets_is_one():
    assert jaccard_similarity(frozenset({"a", "b"}), frozenset({"a", "b"})) == 1.0


def test_jaccard_similarity_disjoint_sets_is_zero():
    assert jaccard_similarity(frozenset({"a"}), frozenset({"b"})) == 0.0


def test_jaccard_similarity_diapers_vs_adult_diapers_matches_at_half():
    score = jaccard_similarity(frozenset({"diapers"}), frozenset({"adult", "diapers"}))
    assert score == 0.5


def test_jaccard_similarity_baby_vs_adult_diapers_excluded_below_half():
    score = jaccard_similarity(frozenset({"baby", "diapers"}), frozenset({"adult", "diapers"}))
    assert round(score, 2) == 0.33
    assert score < 0.5


def test_jaccard_similarity_hand_and_body_lotion_vs_moisturiser_matches():
    _, _, a = parse_table_name("shopee_id_hand_and_body_lotion")
    _, _, b = parse_table_name("shopee_sg_hand_and_body_moisturiser")
    assert jaccard_similarity(a, b) == 0.5


def test_find_sibling_tables_matches_adult_diapers_across_countries():
    all_tables = [
        "shopee_id_adult_diapers", "shopee_th_adult_diapers", "shopee_sg_diapers",
        "shopee_id_baby_diapers", "shopee_th_baby_diapers", "shopee_id_toothpaste",
    ]
    siblings = find_sibling_tables("shopee_id_adult_diapers", all_tables)
    sibling_names = {name for name, score in siblings}
    assert sibling_names == {"shopee_th_adult_diapers", "shopee_sg_diapers"}


def test_find_sibling_tables_excludes_self():
    all_tables = ["shopee_id_adult_diapers", "shopee_th_adult_diapers"]
    siblings = find_sibling_tables("shopee_id_adult_diapers", all_tables)
    assert "shopee_id_adult_diapers" not in {name for name, score in siblings}


def test_find_sibling_tables_excludes_same_country():
    all_tables = ["shopee_id_adult_diapers", "shopee_id_baby_diapers"]
    siblings = find_sibling_tables("shopee_id_adult_diapers", all_tables)
    assert siblings == []


def test_find_sibling_tables_excludes_different_platform():
    all_tables = ["shopee_id_adult_diapers", "lazada_th_adult_diapers"]
    siblings = find_sibling_tables("shopee_id_adult_diapers", all_tables)
    assert siblings == []


def test_find_sibling_tables_sorts_by_score_descending():
    all_tables = ["shopee_id_adult_diapers", "shopee_th_adult_diapers", "shopee_sg_diapers"]
    siblings = find_sibling_tables("shopee_id_adult_diapers", all_tables)
    scores = [score for name, score in siblings]
    assert scores == sorted(scores, reverse=True)


def test_build_candidate_products_query_binds_all_params():
    sql, params = build_candidate_products_query(
        product_ids=["P1", "P2"], sku_names=["Sku One", "Sku Two"],
        this_table="shopee_id_adult_diapers", scope_tables=["shopee_id_adult_diapers", "shopee_th_adult_diapers"],
    )
    param_names = {p.name for p in params}
    assert param_names == {"product_ids", "sku_names", "this_table", "scope_tables", "n"}
    n_param = next(p for p in params if p.name == "n")
    assert n_param.value == 5


def test_build_candidate_products_query_sql_covers_both_tiers():
    sql, params = build_candidate_products_query(["P1"], ["Sku"], "t", ["t"])
    assert "brand_match" in sql
    assert "text_only" in sql
    assert "review_confidence" in sql
    assert "source_table" in sql
    assert "EDIT_DISTANCE" in sql


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print(f"PASS: {name}")
    print("ALL TESTS PASSED")
