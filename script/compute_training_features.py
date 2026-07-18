#!/usr/bin/env python3
"""Runs sql/queries/training_pairs.sql and writes the raw labeled pairs to a local parquet file. Deliberately
does NOT compute derived features here (e.g. token_jaccard_stripped, the categorical encodings) - that logic
lives once, in script/taxonomy_match_encoding.py (Task 4), shared with the scoring script (Task 5) so training
and inference can never silently compute a feature two different ways."""
import pandas as pd
from google.cloud import bigquery

PROJECT = "sincere-hearth-273704"
OUTPUT_PATH = "training_features.parquet"


def main():
    client = bigquery.Client(project=PROJECT)
    with open("sql/queries/training_pairs.sql") as f:
        query = f.read()
    df = client.query(query).to_dataframe()
    df.to_parquet(OUTPUT_PATH, index=False)
    print(f"Wrote {len(df)} training pairs ({df['label'].sum()} positive) to {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
