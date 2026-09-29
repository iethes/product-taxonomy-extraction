#!/usr/bin/env python3
"""Attach worklist images to Codex without using its sandboxed file viewer.

Codex's Linux image-viewing helper can fail before opening an existing file when
bubblewrap cannot configure loopback. This program downloads and validates each
worklist image in the wrapper process, then creates labelled contact sheets for
``codex exec --image``. A manifest retains the exact panel-to-product mapping.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from html.parser import HTMLParser
from io import BytesIO
import json
from pathlib import Path
import re
from typing import Optional
import urllib.parse
import urllib.request

from PIL import Image, ImageDraw, ImageFont, ImageOps, UnidentifiedImageError


MAX_IMAGE_BYTES = 12 * 1024 * 1024
MAX_PAGE_BYTES = 2 * 1024 * 1024
CELL_WIDTH = 800
CELL_HEIGHT = 480
HEADER_HEIGHT = 44
SHEET_COLUMNS = 2
SHEET_ROWS = 5
SHEET_SIZE = SHEET_COLUMNS * SHEET_ROWS
HTTP_URL_PATTERN = re.compile(r"https?://[^\s\"']+")


def first_http_image_url(image_value: object) -> str:
    """Extract the first complete HTTP(S) URL from a source image field.

    Source tables are inconsistent: most rows contain one URL, while Tokopedia
    commonly stores a Python- or JSON-serialized list of product-image URLs.
    The worklist must retain that raw value for its later QA insert, but a
    contact sheet needs one concrete URL. Regex extraction deliberately avoids
    evaluating the source string as a Python literal.
    """
    raw = str(image_value or "")
    for match in HTTP_URL_PATTERN.finditer(raw):
        candidate = match.group(0)
        parsed = urllib.parse.urlparse(candidate)
        if parsed.scheme in {"http", "https"} and parsed.netloc:
            return candidate
    raise ValueError("image URL is absent or does not use HTTP(S)")


class _OpenGraphImageParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.image_url: Optional[str] = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, Optional[str]]]) -> None:
        if tag.lower() != "meta" or self.image_url is not None:
            return
        attributes = {name.lower(): value for name, value in attrs}
        key = (attributes.get("property") or attributes.get("name") or "").lower()
        if key in {"og:image", "twitter:image"} and attributes.get("content"):
            self.image_url = attributes["content"]


def fetch_tokopedia_open_graph_image(product_url: object) -> str:
    """Resolve a source-null Tokopedia image from the product page's Open Graph tag."""
    parsed = urllib.parse.urlparse(str(product_url or ""))
    hostname = (parsed.hostname or "").lower()
    if parsed.scheme not in {"http", "https"} or not (
        hostname == "tokopedia.com" or hostname.endswith(".tokopedia.com")
    ):
        raise ValueError("image is absent and product URL is not a Tokopedia HTTP(S) page")
    request = urllib.request.Request(parsed.geturl(), headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(request, timeout=30) as response:
        page = response.read(MAX_PAGE_BYTES + 1)
    if len(page) > MAX_PAGE_BYTES:
        raise ValueError("Tokopedia product page exceeds 2 MiB")
    parser = _OpenGraphImageParser()
    parser.feed(page.decode("utf-8", errors="replace"))
    if parser.image_url is None:
        raise ValueError("Tokopedia product page has no Open Graph image")
    return first_http_image_url(parser.image_url)


def download_image(url: str) -> Image.Image:
    url = first_http_image_url(url)
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = response.read(MAX_IMAGE_BYTES + 1)
    if len(payload) > MAX_IMAGE_BYTES:
        raise ValueError("image exceeds 12 MiB")
    with Image.open(BytesIO(payload)) as source:
        source.load()
        return ImageOps.exif_transpose(source).convert("RGB")


def download_worklist_image(image_value: object, product_url: object) -> tuple[str, Image.Image]:
    """Download a source image or fall back to a Tokopedia product-page image."""
    try:
        image_url = first_http_image_url(image_value)
    except ValueError:
        image_url = fetch_tokopedia_open_graph_image(product_url)
    return image_url, download_image(image_url)


def _font() -> ImageFont.ImageFont:
    font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    try:
        return ImageFont.truetype(font_path, 27)
    except OSError:
        return ImageFont.load_default()


def make_sheet(
    rows: list[dict], images: list[Optional[Image.Image]], destination: Path
) -> None:
    if not 1 <= len(rows) <= SHEET_SIZE or len(rows) != len(images):
        raise ValueError("sheet needs one to ten images, aligned with its rows")
    sheet = Image.new("RGB", (CELL_WIDTH * SHEET_COLUMNS, CELL_HEIGHT * SHEET_ROWS), "white")
    draw = ImageDraw.Draw(sheet)
    font = _font()
    for index, (row, image) in enumerate(zip(rows, images)):
        x = (index % SHEET_COLUMNS) * CELL_WIDTH
        y = (index // SHEET_COLUMNS) * CELL_HEIGHT
        draw.rectangle((x, y, x + CELL_WIDTH - 1, y + CELL_HEIGHT - 1), outline="black", width=2)
        label = f"ROW {row['row_number']:03d}  product_id {row['product_id']}"
        draw.text((x + 12, y + 7), label, fill="black", font=font)
        if image is None:
            draw.text((x + 18, y + HEADER_HEIGHT + 30), "IMAGE UNAVAILABLE", fill="red", font=font)
            continue
        fitted = ImageOps.contain(image, (CELL_WIDTH - 20, CELL_HEIGHT - HEADER_HEIGHT - 20))
        image_x = x + (CELL_WIDTH - fitted.width) // 2
        image_y = y + HEADER_HEIGHT + (CELL_HEIGHT - HEADER_HEIGHT - fitted.height) // 2
        sheet.paste(fitted, (image_x, image_y))
    sheet.save(destination, format="JPEG", quality=88, optimize=True)


def prepare(worklist: Path, output_dir: Path) -> dict:
    output_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    output_dir.chmod(0o700)
    # JSONL is delimited by LF bytes. str.splitlines() also splits valid U+2028
    # characters inside a JSON string, corrupting otherwise valid worklists.
    rows = [json.loads(line) for line in worklist.read_text().split("\n") if line.strip()]
    if not rows:
        raise ValueError("worklist is empty")

    manifest_path = output_dir / "manifest.jsonl"
    sheets: list[str] = []
    readable = 0
    failed = 0
    with manifest_path.open("w") as manifest, ThreadPoolExecutor(max_workers=8) as pool:
        for start in range(0, len(rows), SHEET_SIZE):
            chunk = rows[start : start + SHEET_SIZE]
            sheet_number = start // SHEET_SIZE + 1
            sheet_path = output_dir / f"sheet_{sheet_number:03d}.jpg"
            futures = []
            for row in chunk:
                futures.append(pool.submit(
                    download_worklist_image,
                    row.get("image"),
                    row.get("product_url", row.get("url")),
                ))
            prepared_rows: list[dict] = []
            images: list[Optional[Image.Image]] = []
            for offset, (row, future) in enumerate(zip(chunk, futures)):
                entry = {
                    "row_number": start + offset + 1,
                    "product_id": str(row["product_id"]),
                    "sheet": sheet_path.name,
                    "panel": offset + 1,
                }
                try:
                    image_url, image = future.result()
                    entry["image_status"] = "readable"
                    entry["image_url"] = image_url
                    readable += 1
                except (OSError, ValueError, UnidentifiedImageError) as exc:
                    image = None
                    entry["image_status"] = "failed"
                    entry["error"] = str(exc)[:180]
                    failed += 1
                prepared_rows.append(entry)
                images.append(image)
                manifest.write(json.dumps(entry, ensure_ascii=False) + "\n")
            make_sheet(prepared_rows, images, sheet_path)
            sheets.append(str(sheet_path))
            for image in images:
                if image is not None:
                    image.close()

    if readable == 0:
        raise RuntimeError(f"all {failed} worklist images failed to download or decode")
    return {"manifest": str(manifest_path), "sheets": sheets, "readable": readable, "failed": failed}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worklist", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(prepare(args.worklist, args.output_dir)))


if __name__ == "__main__":
    main()
