#!/usr/bin/env python3
"""Manual smoke test for Meilisearch hybrid search against a *_taxonomy_qa index -- prints the
index's doc count (0 means Windmill's mode="sync" hasn't backfilled it yet) then runs one query
through the exact retrieve_candidates() path non_niq_qa.sh uses in production.

Usage:
  python3 test_meili_hybrid_search.py --index lighting_taxonomy_qa --query "ไฟฉายคาดหัว"
  python3 test_meili_hybrid_search.py --index babybath_taxonomy_qa --query "baby shampoo 200ml" --limit 5
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from non_niq_helper import MEILI_URL, _meili_request, retrieve_candidates


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--index", required=True)
    p.add_argument("--query", required=True)
    p.add_argument("--limit", type=int, default=10)
    p.add_argument("--meili-url", default=MEILI_URL)
    args = p.parse_args()

    stats = _meili_request(args.meili_url, "GET", f"/indexes/{args.index}/stats")
    print(f"index={args.index} docs={stats.get('numberOfDocuments')}")

    results = retrieve_candidates(
        [{"id": "test", "text": args.query}], args.meili_url, args.index, limit=args.limit,
    )
    candidates = results[0]["candidates"]
    print(f"query={args.query!r} -> {len(candidates)} candidate(s)")
    for c in candidates:
        print(f"  {c.get('sku_type_complete')!r:50s} brand={c.get('brand')!r} sku_name={c.get('sku_name')!r}")


if __name__ == "__main__":
    main()
