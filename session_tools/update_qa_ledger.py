#!/usr/bin/env python3
import json, sys

ledger, chunk = sys.argv[1:3]
rows = {}
try:
    for line in open(ledger):
        item = json.loads(line)
        rows[str(item['product_id'])] = item
except FileNotFoundError:
    pass
chunk_rows = []
for line in open(chunk):
    item = json.loads(line)
    rows[str(item['product_id'])] = item
    chunk_rows.append(item)
with open(ledger, 'w') as f:
    for item in rows.values():
        f.write(json.dumps(item, ensure_ascii=False, separators=(',', ':')) + '\n')
for item in chunk_rows:
    print(json.dumps(item, ensure_ascii=False, separators=(',', ':')))
