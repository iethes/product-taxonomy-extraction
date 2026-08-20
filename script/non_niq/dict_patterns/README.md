# Dict-column generation patterns

One JSON file per dataset (e.g. `cookiesbiscuit.json`), self-bootstrapped by the v2 QA harness
(`non_niq_qa_v2.sh`'s STEP 2c) the first time it creates a dict entry for that dataset -- do not
hand-author these unless you're correcting a bad inference.

Schema:

```json
{
  "sku_type_complete": {"sources": ["sub_brand", "variant", "total_size"], "separator": " "},
  "keywords": {"sources": ["sku_type_complete", "keywords_typo"], "separator": " "}
}
```

Each top-level key is a generated `{dataset}_dict` table column. `sources` is the ordered list of
other dict-table columns it's composed from. `separator` is how they're joined. Composition skips
any source that's null/empty -- a generated column never ends up with a literal `"null"` or a
dangling separator when one of its sources (e.g. a nullable typo column) has no value for a given
row.

One file per dataset, not one shared file, so two datasets running QA sessions concurrently never
race on the same file.
