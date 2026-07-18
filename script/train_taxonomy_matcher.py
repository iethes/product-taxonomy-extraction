#!/usr/bin/env python3
"""Trains an XGBoost classifier on training_features.parquet, held out on shopee_th_toothpaste, and reports
precision both raw and on the ground-truth-hygiene-filtered subset (parse_size self-consistency)."""
import json

import pandas as pd
import xgboost as xgb
from google.cloud import bigquery

from taxonomy_match_encoding import FEATURE_COLUMNS, encode_features

PROJECT = "sincere-hearth-273704"


def get_ground_truth_clean_product_ids(client):
    """Products whose recorded ground-truth size agrees with parse_size(sku_name) - the self-consistency
    check from v1's findings, applied up front this time instead of discovered in a costly redo round."""
    query = f"""
        SELECT DISTINCT m.product_id
        FROM `{PROJECT}.magpie_reference.product_taxonomy_map` m
        JOIN `{PROJECT}.magpie.marketshare_universe_niq` u
          ON u.product_id = m.product_id AND u.ecommerce_platform = m.platform AND u.country = m.country
        JOIN `{PROJECT}.magpie_reference.product_taxonomy` pt ON pt.taxonomy_id = m.taxonomy_id
        CROSS JOIN UNNEST([`{PROJECT}.magpie_reference.parse_size`(u.sku_name)]) AS parsed
        WHERE u.month = (SELECT MAX(month) FROM `{PROJECT}.magpie.marketshare_universe_niq`)
          AND m.master_table = 'shopee_th_toothpaste' AND m.source = 'LLM'
          AND (parsed.size_text IS NULL OR pt.size IS NULL OR parsed.size_text = pt.size)
    """
    return set(r.product_id for r in client.query(query).result())


def main():
    df = pd.read_parquet("training_features.parquet")
    df = encode_features(df)

    train_df = df[df["master_table"] != "shopee_th_toothpaste"]
    eval_df = df[df["master_table"] == "shopee_th_toothpaste"]

    model = xgb.XGBClassifier(n_estimators=200, max_depth=4, eval_metric="logloss")
    model.fit(train_df[FEATURE_COLUMNS], train_df["label"])
    model.save_model("taxonomy_matcher_model.json")

    eval_df = eval_df.copy()
    eval_df["predicted_prob"] = model.predict_proba(eval_df[FEATURE_COLUMNS])[:, 1]
    top1 = eval_df.loc[eval_df.groupby(["product_id", "platform", "country"])["predicted_prob"].idxmax()]

    client = bigquery.Client(project=PROJECT)
    clean_ids = get_ground_truth_clean_product_ids(client)

    raw_precision = (top1["label"] == 1).mean()
    clean_subset = top1[top1["product_id"].isin(clean_ids)]
    clean_precision = (clean_subset["label"] == 1).mean() if len(clean_subset) else float("nan")

    importances = dict(zip(FEATURE_COLUMNS, model.feature_importances_.tolist()))

    print(f"Held-out shopee_th_toothpaste top-1 count: {len(top1)}")
    print(f"Raw precision: {raw_precision:.4f}")
    print(f"Ground-truth-clean subset precision: {clean_precision:.4f} (n={len(clean_subset)})")
    print(f"Feature importances: {json.dumps(importances, indent=2)}")


if __name__ == "__main__":
    main()
