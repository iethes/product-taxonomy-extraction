#!/usr/bin/env python3
"""Single source of truth for taxonomy-match feature encoding, shared by train_taxonomy_matcher.py and
score_taxonomy_candidates.py so the two can never silently compute a feature differently. A shared BigQuery
table function was considered for the upstream SQL too, but BigQuery rejects correlated table-function calls
(same restriction as LATERAL) - the SQL queries stay separate, this module is what stays shared."""
import re

FEATURE_COLUMNS = [
    "embedding_cosine_distance",
    "edit_distance_stripped",
    "token_jaccard_stripped",
    "keyword_table_hit",
    "text_length_ratio",
    "size_match_code",
    "pack_signal_present",
    "pack_match_code",
]


def token_jaccard(a, b):
    tokens_a = set(re.findall(r"\w+", str(a)))
    tokens_b = set(re.findall(r"\w+", str(b)))
    if not tokens_a or not tokens_b:
        return 0.0
    return len(tokens_a & tokens_b) / len(tokens_a | tokens_b)


def encode_features(df):
    """Takes the raw output of training_pairs.sql or candidate_scoring_pairs.sql and returns a copy with
    FEATURE_COLUMNS populated, ready for model.fit / model.predict_proba."""
    df = df.copy()
    df["token_jaccard_stripped"] = df.apply(
        lambda r: token_jaccard(r["sku_text_stripped"], r["candidate_text_stripped"]), axis=1
    )
    df["size_match_code"] = df["size_match"].map({"match": 1, "mismatch": -1, "unknown": 0})
    df["keyword_table_hit"] = df["keyword_table_hit"].astype(int)
    df["pack_signal_present"] = df["pack_multiplier_signal"].notna().astype(int)
    df["pack_match_code"] = 0
    has_both = df["pack_multiplier_signal"].notna() & df["candidate_pack_count"].notna()
    df.loc[has_both, "pack_match_code"] = (
        df.loc[has_both, "pack_multiplier_signal"].astype(float)
        == df.loc[has_both, "candidate_pack_count"].astype(float)
    ).astype(int) * 2 - 1
    return df
