import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "script" / "niq"))
from headless_v2_worklist import (
    parse_table_name, jaccard_similarity, find_sibling_tables, build_candidate_products_query,
    build_topup_worklist_query, extract_official_store_merchants,
    build_first_run_candidate_pool_query, build_brief_markdown_query,
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


_SAMPLE_BRIEF_EXCERPT = """
## Official Store Allowlist (Pass 1)

| Brand | brand_id | Official Store Merchant Name |
|-------|----------|------------------------------|
| Lifree | `BRD-GLOBAL-00024` | `Lifree Official Store` |
| Lifree / Certainty / CHARM (parent co.) | — | `Unicharm Official Shop`, `Unicharm Authorized Partner Jawa Tengah` |
| Confidence | `BRD-TH-03303` | `Confidence Official Shop` |

**Excluded multi-brand retailers (never Pass 1, regardless of Mall badge)** — confirmed by sampling:
- **Pharmacy chains:** every `Apotek *` store

---

## Scale
"""


def test_build_topup_worklist_query_reuses_v1_shape():
    sql, params = build_topup_worklist_query("shopee_th_suncare", "2026-06", 500)
    assert "master_clean_niq.shopee_th_suncare" in sql
    assert "cumulative_gmv_pct <= 95" in sql
    assert "canonical_name IS NULL" in sql
    assert "CASE WHEN flag_GWP THEN 0 ELSE gmv_monthly END" in sql
    param_names = {p.name for p in params}
    assert param_names == {"month", "block_size"}


def test_extract_official_store_merchants_gets_pass1_column_only():
    merchants = extract_official_store_merchants(_SAMPLE_BRIEF_EXCERPT)
    assert "Lifree Official Store" in merchants
    assert "Unicharm Official Shop" in merchants
    assert "Unicharm Authorized Partner Jawa Tengah" in merchants
    assert "Confidence Official Shop" in merchants
    # brand_id backtick tokens and the excluded-retailer bullet list must NOT leak in
    assert "BRD-GLOBAL-00024" not in merchants
    assert "Apotek *" not in merchants


def test_extract_official_store_merchants_empty_when_section_missing():
    assert extract_official_store_merchants("# Some other doc\nNo allowlist here.") == []


def test_build_first_run_candidate_pool_query_excludes_official_stores():
    sql, params = build_first_run_candidate_pool_query(
        "shopee_id_adult_diapers", "2026-06", ["Lifree Official Store"], 2000,
    )
    assert "master_clean_niq.shopee_id_adult_diapers" in sql
    assert "NOT IN UNNEST(@exclude_merchants)" in sql
    assert "cumulative_gmv_pct <= 95" in sql
    param_names = {p.name for p in params}
    assert param_names == {"month", "exclude_merchants", "block_size"}


def test_build_brief_markdown_query_scopes_to_brief_task_type():
    sql, params = build_brief_markdown_query("master_clean_niq.shopee_id_adult_diapers")
    assert "task_type = 'BRIEF'" in sql
    assert {p.name for p in params} == {"category_key"}


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print(f"PASS: {name}")
    print("ALL TESTS PASSED")
