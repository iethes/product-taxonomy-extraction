"""
Unit tests for script/migrate_category_docs_to_bq_2026_07_29.py's pure functions.

Uses stdlib unittest (not pytest) -- this environment has no python3-venv and no
sudo, so pytest can't be installed without a system-level package change. Run:
python3 script/test_migrate_category_docs_to_bq_2026_07_29.py -v
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
from migrate_category_docs_to_bq_2026_07_29 import (
    derive_country, classify_status, parse_qa_history_table, build_reality_note,
)


class TestDeriveCountry(unittest.TestCase):
    def test_niq_prefixes(self):
        self.assertEqual(derive_country("shopee_sg_shampoo"), "SG")
        self.assertEqual(derive_country("shopee_th_coffee"), "TH")
        self.assertEqual(derive_country("shopee_id_baby_diapers"), "ID")

    def test_custom_suffixes(self):
        self.assertEqual(derive_country("makanankucing_my"), "MY")
        self.assertEqual(derive_country("makanankucing_sg"), "SG")
        self.assertEqual(derive_country("makanananjing_my"), "MY")

    def test_unrecognized_raises(self):
        with self.assertRaises(ValueError):
            derive_country("totally_unknown_table")


class TestClassifyStatus(unittest.TestCase):
    def test_reset_pending_redo(self):
        self.assertEqual(classify_status(live_rows=0, orphan_rows=0, doc_claims_complete=True), "reset_pending_redo")
        self.assertEqual(classify_status(live_rows=5, orphan_rows=5, doc_claims_complete=True), "reset_pending_redo")

    def test_partial_loss(self):
        self.assertEqual(classify_status(live_rows=74, orphan_rows=10, doc_claims_complete=True), "partial_loss")

    def test_active(self):
        self.assertEqual(classify_status(live_rows=4527, orphan_rows=0, doc_claims_complete=True), "active")

    def test_not_started(self):
        self.assertEqual(classify_status(live_rows=0, orphan_rows=0, doc_claims_complete=False), "not_started")


class TestParseQaHistoryTable(unittest.TestCase):
    def test_extracts_rows(self):
        markdown = """# Category

## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| 2026-06-21 | Pass 1 | old finding | old resolution |
| 2026-06-23 | QA Gate A | another finding | another resolution |

---

## Next section
"""
        rows = parse_qa_history_table(markdown)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0], {
            "date": "2026-06-21", "pass_name": "Pass 1",
            "finding": "old finding", "resolution": "old resolution",
        })
        self.assertEqual(rows[1]["date"], "2026-06-23")

    def test_skips_template_placeholder(self):
        markdown = """## QA History

| Date | Pass | Finding | Resolution |
|------|------|---------|------------|
| YYYY-MM-DD | Initial | {finding} | {fix} |
| YYYY-MM-DD | QA Gate A | {finding} | {fix} |

---
"""
        self.assertEqual(parse_qa_history_table(markdown), [])

    def test_no_section_returns_empty(self):
        self.assertEqual(parse_qa_history_table("# Category\nNo history section here.\n"), [])


class TestBuildRealityNote(unittest.TestCase):
    def test_reset_pending_redo(self):
        note = build_reality_note("reset_pending_redo", live_rows=196, orphan_rows=59)
        self.assertIn("## Data Reality Check", note)
        self.assertIn("196", note)
        self.assertIn("59", note)
        self.assertIn("reset for redo", note)

    def test_partial_loss(self):
        note = build_reality_note("partial_loss", live_rows=74, orphan_rows=0)
        self.assertIn("partially recovered", note)

    def test_active_returns_empty(self):
        self.assertEqual(build_reality_note("active", live_rows=4527, orphan_rows=0), "")


if __name__ == "__main__":
    unittest.main()
