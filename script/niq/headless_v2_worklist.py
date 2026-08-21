#!/usr/bin/env python3
"""Builds the candidate-enriched worklist for headless_taxonomy_v2.sh -- all pure SQL/Python, no LLM calls.
Candidates come from the current table AND fuzzy-matched sibling category tables in other countries. See
docs/superpowers/specs/2026-08-21-headless-taxonomy-v2-cross-market-candidates-design.md."""
import re

PROJECT = "sincere-hearth-273704"
_SAFE_TABLE_NAME = re.compile(r"^[a-zA-Z0-9_]+$")
_STOPWORDS = {"for", "and", "or", "of", "the", "a"}


def _validate_table(table):
    if not _SAFE_TABLE_NAME.match(table):
        raise ValueError(f"Unsafe table value for table-name interpolation: {table!r}")


def parse_table_name(table_name):
    """table_name like 'shopee_id_adult_diapers' -> ('shopee', 'id', frozenset({'adult', 'diapers'}))."""
    parts = table_name.split("_")
    platform, country = parts[0], parts[1]
    category_tokens = frozenset(p for p in parts[2:] if p not in _STOPWORDS)
    return platform, country, category_tokens


def jaccard_similarity(a, b):
    if not a and not b:
        return 0.0
    union = a | b
    if not union:
        return 0.0
    return len(a & b) / len(union)


def find_sibling_tables(this_table, all_tables, threshold=0.5):
    """Same platform, different country, category-slug Jaccard similarity >= threshold. Returns
    [(table_name, score), ...] sorted by score descending."""
    platform, country, tokens = parse_table_name(this_table)
    siblings = []
    for other in all_tables:
        if other == this_table:
            continue
        o_platform, o_country, o_tokens = parse_table_name(other)
        if o_platform != platform or o_country == country:
            continue
        score = jaccard_similarity(tokens, o_tokens)
        if score >= threshold:
            siblings.append((other, score))
    siblings.sort(key=lambda pair: -pair[1])
    return siblings
