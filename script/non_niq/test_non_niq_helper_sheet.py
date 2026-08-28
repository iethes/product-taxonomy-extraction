#!/usr/bin/env python3
"""Runnable self-check for non_niq_helper.py's Sheets write-back helpers -- no framework, no
network. Covers the two genuinely tricky bits: case-insensitive/reordered column mapping (the
actual bug being fixed -- a dict table's column order never matches its Sheet's) and gid parsing
from a taxonomy_url that may or may not include one.
"""
from non_niq_helper import _map_row_to_header, _parse_sheet_url

# Mirrors the real susububuk_dict-vs-Sheet mismatch: BigQuery order is
# keywords/keyword_typo/sku_type_complete, the Sheet's header order is
# Keyword_Typo/SKU_type_complete/Keywords, plus a Sheet-only _meta column with no BQ counterpart.
row = {"keywords": "susu bubuk", "keyword_typo": "susu bubok", "sku_type_complete": "Milk Powder"}
header = ["Keyword_Typo", "SKU_type_complete", "Keywords", "_meta"]
assert _map_row_to_header(row, header) == ["susu bubok", "Milk Powder", "susu bubuk", ""]

assert _parse_sheet_url(
    "https://docs.google.com/spreadsheets/d/1zOKCQhlqfw96K4BOzRRcsPmEe0nn3ET3cRa0m_P0b1s/edit?gid=0#gid=0"
) == ("1zOKCQhlqfw96K4BOzRRcsPmEe0nn3ET3cRa0m_P0b1s", 0)

assert _parse_sheet_url(
    "https://docs.google.com/spreadsheets/d/1x6b_qxq_qSHbII3wfV1toMdn5IQzT5dqs_phHCAbo8U/edit?usp=sharing"
) == ("1x6b_qxq_qSHbII3wfV1toMdn5IQzT5dqs_phHCAbo8U", 0)

assert _parse_sheet_url(
    "https://docs.google.com/spreadsheets/d/1jhbERXiRJ9bgm4eSmueoHcZQvKl_zcAdl71o5HSFP9w/edit?pli=1&gid=12246726#gid=12246726"
) == ("1jhbERXiRJ9bgm4eSmueoHcZQvKl_zcAdl71o5HSFP9w", 12246726)

print("OK")
