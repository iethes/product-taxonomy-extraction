import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image

from script.non_niq import prepare_codex_image_sheets as sheets


class PrepareCodexImageSheetsTest(unittest.TestCase):
    def test_sheets_keep_an_exact_product_mapping_and_mark_failed_images(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            worklist = root / "worklist.jsonl"
            worklist.write_text(
                "".join(
                    json.dumps({
                        "product_id": str(100 + index),
                        "image": "bad" if index == 3 else "https://example.test/%s.jpg" % index,
                    })
                    + "\n"
                    for index in range(11)
                )
            )

            def fake_download(url):
                return Image.new("RGB", (100, 100), "blue")

            with patch.object(sheets, "download_image", side_effect=fake_download):
                result = sheets.prepare(worklist, root / "output")

            self.assertEqual((result["readable"], result["failed"]), (10, 1))
            self.assertEqual(len(result["sheets"]), 2)
            manifest = [json.loads(line) for line in Path(result["manifest"]).read_text().splitlines()]
            self.assertEqual([entry["product_id"] for entry in manifest], [str(100 + i) for i in range(11)])
            self.assertEqual((manifest[0]["sheet"], manifest[0]["panel"]), ("sheet_001.jpg", 1))
            self.assertEqual((manifest[10]["sheet"], manifest[10]["panel"]), ("sheet_002.jpg", 1))
            self.assertEqual(manifest[3]["image_status"], "failed")
            for sheet_path in result["sheets"]:
                with Image.open(sheet_path) as sheet:
                    self.assertEqual(sheet.size, (1600, 2400))
                    sheet.verify()

    def test_all_invalid_images_stop_before_codex_starts(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            worklist = root / "worklist.jsonl"
            worklist.write_text('{"product_id":"1","image":"bad"}\n')
            with patch.object(sheets, "download_image", side_effect=ValueError("invalid image")):
                with self.assertRaisesRegex(RuntimeError, "all 1 worklist images failed"):
                    sheets.prepare(worklist, root / "output")

    def test_serialized_url_list_uses_its_first_url(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            worklist = root / "worklist.jsonl"
            first_url = "https://images.tokopedia.net/img/first.jpeg"
            second_url = "https://images.tokopedia.net/img/second.jpeg"
            worklist.write_text(json.dumps({
                "product_id": "tokopedia-product",
                "image": "['%s', '%s']" % (first_url, second_url),
            }) + "\n")
            downloaded_urls = []

            def fake_download(url):
                downloaded_urls.append(url)
                return Image.new("RGB", (100, 100), "blue")

            with patch.object(sheets, "download_image", side_effect=fake_download):
                result = sheets.prepare(worklist, root / "output")

            self.assertEqual(downloaded_urls, [first_url])
            manifest = [json.loads(line) for line in Path(result["manifest"]).read_text().splitlines()]
            self.assertEqual(manifest[0]["image_url"], first_url)

    def test_missing_image_uses_tokopedia_product_page_image(self):
        product_url = "https://www.tokopedia.com/store/product"
        image_url = "https://images.tokopedia.net/product.jpg"
        with patch.object(sheets, "fetch_tokopedia_open_graph_image", return_value=image_url), \
             patch.object(sheets, "download_image", return_value=Image.new("RGB", (100, 100), "blue")):
            resolved_url, image = sheets.download_worklist_image(None, product_url)
        self.assertEqual(resolved_url, image_url)
        image.close()

    def test_jsonl_loader_preserves_a_unicode_line_separator_inside_text(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            worklist = root / "worklist.jsonl"
            worklist.write_text(json.dumps({
                "product_id": "unicode-separator",
                "image": "https://example.test/image.jpg",
                "item_description": "first paragraph\u2028second paragraph",
            }, ensure_ascii=False) + "\n")
            with patch.object(sheets, "download_image", return_value=Image.new("RGB", (100, 100), "blue")):
                result = sheets.prepare(worklist, root / "output")
            self.assertEqual(result["readable"], 1)


if __name__ == "__main__":
    unittest.main()
