#!/usr/bin/env python3
"""Deterministic Python driver for non-NIQ QA v3."""

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
from hashlib import sha256
import json
import os
from pathlib import Path
import re
import secrets
import struct
import subprocess
import sys
import tempfile
from typing import Any, Callable, Dict, List, Mapping, Optional, Sequence, Set, Tuple
import urllib.request
from urllib.parse import urlsplit
import zlib

from google.cloud import bigquery
from non_niq_helper import (
    MEILI_URL,
    _table_columns,
    append_sheet_new_entries_strict,
    fetch_config_csv,
    fetch_forced_merchant_ids,
    index_documents_strict,
    parse_categories,
    retrieve_candidates,
    confirm_casefold_matches,
    sync_labelling,
    worklist_row_key,
)


@dataclass(frozen=True)
class PreparedImage:
    product_id: str
    image_url: Optional[str]
    image_status: str
    local_path: Optional[Path]


@dataclass(frozen=True)
class Attachment:
    product_id: str
    attachment_index: int
    attachment_filename: str
    sha256: str
    local_path: Path


@dataclass(frozen=True)
class AttemptPlan:
    work_item_id: str
    input_fingerprint: str
    attempt_id: str
    attempt_kind: str


class AdapterVisionError(RuntimeError):
    pass


class DecisionValidationError(ValueError):
    pass


def _stable_digest(value: Mapping[str, Any]) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"), default=str)
    return sha256(encoded.encode("utf-8")).hexdigest()

def _packet_id(row: Mapping[str, Any]) -> str:
    """Return an opaque adapter identifier for one raw worklist row."""
    return _stable_digest({"worklist_row_key": worklist_row_key(row)})


def first_complete_https_url(image_raw: Optional[str]) -> Optional[str]:
    """Return the first complete HTTPS URL without rewriting it."""
    if not image_raw:
        return None
    for match in re.finditer(r"https://[^\s\"']+", image_raw):
        candidate = match.group(0)
        parsed = urlsplit(candidate)
        if parsed.scheme == "https" and parsed.netloc:
            return candidate
    return None


def normalize_first_image_url(image_raw: Optional[str], platform: str) -> Optional[str]:
    """Apply the one-image platform policy."""
    if not image_raw:
        return None
    if platform == "Shopee":
        cleaned = image_raw.replace('"', "").replace("'", "")
        match = re.search(r"https://[^\s]+\.img\.susercontent\.com/file/[^\s]+", cleaned)
        return match.group(0) if match else None
    return first_complete_https_url(image_raw)


def build_attachment_manifest(images: Sequence[PreparedImage]) -> Tuple[Attachment, ...]:
    """Assign frozen one-based attachment indexes in packet order."""
    attachments = []
    for image in images:
        if image.image_status != "ready" or image.local_path is None:
            continue
        attachment_index = len(attachments) + 1
        suffix = Path(urlsplit(image.image_url or "").path).suffix.lower() or ".img"
        filename = "attachment-%04d%s" % (attachment_index, suffix)
        image_bytes = image.local_path.read_bytes()
        local_path = image.local_path.with_name(filename)
        if local_path != image.local_path:
            if local_path.exists():
                local_path.unlink()
            try:
                os.link(image.local_path, local_path)
            except OSError:
                local_path.write_bytes(image_bytes)
        attachments.append(Attachment(
            product_id=image.product_id,
            attachment_index=attachment_index,
            attachment_filename=filename,
            sha256=sha256(image_bytes).hexdigest(),
            local_path=local_path,
        ))
    return tuple(attachments)


def _normalize_attempt_text(value: Any) -> str:
    return re.sub(r"\s+", " ", str(value or "").strip())


def _canonical_platform(value: Any) -> str:
    platform = _normalize_attempt_text(value)
    return "Tokopedia" if platform == "Tokopedia | Shop" else platform


def plan_attempt(row: Mapping[str, Any], qa_state: Mapping[str, Any]) -> AttemptPlan:
    """Return the stable logical initial, retry, or listing-change attempt."""
    attempt_kind = str(qa_state.get("kind", "initial"))
    if attempt_kind not in {"initial", "retry", "listing_change"}:
        raise ValueError("unsupported attempt kind: %s" % attempt_kind)

    current_title = _normalize_attempt_text(row.get("sku_name"))
    current_category = _normalize_attempt_text(row.get("kategori"))
    platform = _normalize_attempt_text(
        row.get("ecommerce_platform") or row.get("platform")
    )
    work_item_id = _stable_digest({
        "product_id": str(row.get("product_id", "")),
        "platform": platform,
        "country": _normalize_attempt_text(row.get("country")),
        "dataset": _normalize_attempt_text(row.get("dataset")),
        "current_title": current_title,
    })
    image_raw = row.get("image_raw", row.get("image"))
    image_url = row.get("image_url")
    if image_url is None:
        image_url = normalize_first_image_url(image_raw, platform)
    input_fingerprint = _stable_digest({
        "work_item_id": work_item_id,
        "current_title": current_title,
        "current_category": current_category,
        "item_description": str(row.get("item_description", "")),
        "product_attributes_attrs": str(row.get("product_attributes_attrs", "")),
        "image_raw": str(image_raw or ""),
        "image_url": str(image_url or ""),
        "image_status": str(row.get("image_status", "")),
        "image_sha256": str(row.get("image_sha256", "")),
    })
    if attempt_kind in {"initial", "retry"}:
        attempt_id = "%s:%s-1" % (work_item_id, attempt_kind)
    else:
        generation = _stable_digest({
            "month": str(row.get("month", "")),
            "prior_title": _normalize_attempt_text(row.get("prior_sku_name")),
            "current_title": current_title,
            "prior_category": _normalize_attempt_text(row.get("prior_kategori")),
            "current_category": current_category,
        })
        attempt_id = "%s:listing-change:%s:%s" % (
            work_item_id, str(row.get("month", "")), generation,
        )
    return AttemptPlan(
        work_item_id=work_item_id,
        input_fingerprint=input_fingerprint,
        attempt_id=attempt_id,
        attempt_kind=attempt_kind,
    )


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise DecisionValidationError(message)


def _has_own_image_evidence(
    evidence: Sequence[Mapping[str, Any]], attachment_index: Any, image_ready: bool,
) -> bool:
    has_own_image = False
    for item in evidence:
        _require(isinstance(item, Mapping), "evidence item must be an object")
        source = item.get("source")
        _require(isinstance(source, str) and source, "evidence source is required")
        claim = item.get("claim")
        _require(isinstance(claim, str) and claim, "evidence claim is required")
        if source == "image":
            _require(image_ready, "image evidence requires a readable attachment")
            _require(
                isinstance(attachment_index, int) and not isinstance(attachment_index, bool) and attachment_index > 0,
                "packet has no valid attachment index",
            )
            _require(
                set(item) == {"source", "claim", "attachment_index"},
                "image evidence has unexpected fields",
            )
            item_index = item.get("attachment_index")
            _require(
                isinstance(item_index, int) and not isinstance(item_index, bool) and item_index > 0,
                "image evidence attachment_index must be a positive integer",
            )
            _require(
                item_index == attachment_index,
                "image evidence cites another product attachment",
            )
            has_own_image = True
        else:
            _require(set(item) == {"source", "claim", "attachment_index"}, "text evidence has unexpected fields")
            _require(item.get("attachment_index") is None, "text evidence must use null attachment_index")
    return has_own_image


def validate_decision_batch(
    raw: Mapping[str, Any], packets: Sequence[Mapping[str, Any]],
) -> List[Mapping[str, Any]]:
    """Return exact packet-bound decisions or raise DecisionValidationError."""
    _require(isinstance(raw, Mapping) and set(raw) == {"decisions"}, "result must contain only decisions")
    decisions = raw["decisions"]
    _require(isinstance(decisions, list), "decisions must be an array")
    _require(len(decisions) == len(packets), "every packet needs exactly one decision")
    packets_by_id = {}
    for packet in packets:
        packet_id = packet.get("packet_id")
        _require(isinstance(packet_id, str) and packet_id, "packet_id is required")
        _require(packet_id not in packets_by_id, "duplicate packet_id")
        packets_by_id[packet_id] = packet
    decisions_by_id = {}
    required_fields = {
        "packet_id", "product_id", "work_item_id", "input_fingerprint", "kind",
        "confidence", "evidence", "reason", "candidate_ref", "attributes",
    }
    branch_field = {
        "filter": "reason",
        "map_existing": "candidate_ref",
        "create_dict": "attributes",
        "defer": "reason",
    }
    for decision in decisions:
        _require(isinstance(decision, Mapping), "decision must be an object")
        packet_id = decision.get("packet_id")
        _require(packet_id in packets_by_id, "decision packet_id is not in this batch")
        _require(packet_id not in decisions_by_id, "duplicate decision packet_id")
        packet = packets_by_id[packet_id]
        _require(decision.get("product_id") == packet.get("product_id"), "product_id does not match its packet")
        for field in ("work_item_id", "input_fingerprint"):
            _require(
                decision.get(field) == packet.get(field),
                "%s does not match its packet" % field,
            )
        kind = decision.get("kind")
        _require(kind in branch_field, "unsupported decision kind")
        _require(set(decision) == required_fields, "decision has missing or unexpected fields")
        for field in ("reason", "candidate_ref", "attributes"):
            if field == branch_field[kind]:
                _require(decision.get(field) is not None, "%s is required for %s" % (field, kind))
            else:
                _require(decision.get(field) is None, "%s must be null for %s" % (field, kind))
        confidence = decision.get("confidence")
        _require(confidence in {"confident", "unconfident"}, "unsupported confidence")
        evidence = decision.get("evidence")
        _require(isinstance(evidence, list), "evidence must be an array")
        image_ready = packet.get("image_status") == "ready"
        has_own_image = _has_own_image_evidence(
            evidence, packet.get("attachment_index"), image_ready,
        )

        if kind == "filter":
            _require(confidence == "confident", "filter must be confident")
            _require(isinstance(decision.get("reason"), str) and decision["reason"], "filter reason is required")
            _require(image_ready, "filter requires a readable image")
            _require(has_own_image, "filter requires its own image evidence")
        elif kind == "map_existing":
            _require(decision.get("candidate_ref") in packet.get("candidate_refs", set()), "unknown candidate_ref")
            _require(not image_ready or has_own_image, "readable image requires its own evidence")
        elif kind == "create_dict":
            attributes = decision.get("attributes")
            _require(isinstance(attributes, Mapping) and attributes, "create_dict attributes are required")
            writable = packet.get("writable_attributes", set())
            generated = packet.get("generated_attributes", set())
            _require(set(attributes).issubset(writable), "create_dict includes a non-writable attribute")
            _require(not (set(attributes) & set(generated)), "create_dict includes a generated attribute")
            _require(
                all(isinstance(value, str) and value.strip() for value in attributes.values()),
                "attributes must be non-empty strings",
            )
            pattern = packet.get("dict_pattern", {})
            _require(isinstance(pattern, Mapping), "packet dict pattern is invalid")
            try:
                required_leaves = _pattern_leaf_sources(pattern)
            except (KeyError, TypeError, ValueError) as error:
                raise DecisionValidationError("packet dict pattern is invalid") from error
            _require(
                required_leaves.issubset(attributes),
                "create_dict omits a required generated-pattern leaf",
            )
            allowed_values = packet.get("allowed_categorical_values", {})
            _require(isinstance(allowed_values, Mapping), "packet categorical vocabulary is invalid")
            for attribute, values in allowed_values.items():
                if attribute in attributes:
                    _require(
                        attributes[attribute] in values,
                        "create_dict uses an unknown categorical value: %s" % attribute,
                    )
            _require(not image_ready or has_own_image, "readable image requires its own evidence")
        else:
            _require(confidence == "unconfident", "defer must be unconfident")
            _require(isinstance(decision.get("reason"), str) and decision["reason"], "defer reason is required")

        if not image_ready and kind in {"map_existing", "create_dict"}:
            _require(confidence == "unconfident", "unavailable image cannot produce a confident decision")
        decisions_by_id[packet_id] = decision

    return [decisions_by_id[packet["packet_id"]] for packet in packets]


SCHEMA_PATH = Path(__file__).with_name("non_niq_qa_v3_decision_schema.json")
_PIXEL_DIGITS = {
    "0": ("01110", "10001", "10011", "10101", "11001", "10001", "01110"),
    "1": ("00100", "01100", "00100", "00100", "00100", "00100", "01110"),
    "2": ("01110", "10001", "00001", "00010", "00100", "01000", "11111"),
    "3": ("11110", "00001", "00001", "01110", "00001", "00001", "11110"),
    "4": ("00010", "00110", "01010", "10010", "11111", "00010", "00010"),
    "5": ("11111", "10000", "10000", "11110", "00001", "00001", "11110"),
    "6": ("01110", "10000", "10000", "11110", "10001", "10001", "01110"),
    "7": ("11111", "00001", "00010", "00100", "01000", "01000", "01000"),
    "8": ("01110", "10001", "10001", "01110", "10001", "10001", "01110"),
    "9": ("01110", "10001", "10001", "01111", "00001", "00001", "01110"),
    "A": ("01110", "10001", "10001", "11111", "10001", "10001", "10001"),
    "B": ("11110", "10001", "10001", "11110", "10001", "10001", "11110"),
}


def build_codex_command(
    prompt: str, schema_path: Path, output_path: Path, attachments: Sequence[Attachment],
) -> List[str]:
    """Build Codex's one ordered native image invocation."""
    return [
        "codex", "exec", "--ephemeral", "--sandbox", "read-only",
        "-c", "sandbox_workspace_write.network_access=false",
        "--output-schema", str(schema_path),
        "--output-last-message", str(output_path),
        "--image",
        *[str(attachment.local_path) for attachment in attachments],
        "--",
        prompt,
    ]


def build_omp_command(prompt: str, attachments: Sequence[Attachment]) -> List[str]:
    """Build OMP's one ordered native image invocation."""
    return [
        "omp", "--print", "--mode", "json", "--no-tools", "--no-session",
        *["@" + str(attachment.local_path) for attachment in attachments],
        prompt,
    ]


def _adapter_env() -> Dict[str, str]:
    allowed = {
        "PATH", "HOME", "TMPDIR", "LANG", "LC_ALL", "CODEX_HOME",
        "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "ANTHROPIC_OAUTH_TOKEN",
        "GEMINI_API_KEY", "OMP_PROFILE", "PI_CODING_AGENT_DIR",
    }
    return {key: value for key, value in os.environ.items() if key in allowed}


def _write_label_png(path: Path, label: str) -> None:
    scale = 20
    width = 24 + max(len(label), 8) * scale * 6
    height = 24 + 7 * scale
    pixels = bytearray(b"\xff\xff\xff" * width * height)
    color = {
        "RED": b"\xff\x00\x00",
        "BLUE": b"\x00\x00\xff",
        "GREEN": b"\x00\xaa\x00",
        "YELLOW": b"\xff\xd0\x00",
    }.get(label)
    if color is not None:
        pattern = secrets.token_bytes(8)
        for y in range(12, height - 12):
            for x in range(12, width - 12):
                offset = (y * width + x) * 3
                pixels[offset:offset + 3] = color
        for block_index, marker in enumerate(pattern):
            block_color = b"\x00\x00\x00" if marker & 1 else b"\xff\xff\xff"
            x_start = 24 + block_index * scale * 6
            for y in range(24, 24 + scale):
                for x in range(x_start, x_start + scale):
                    offset = (y * width + x) * 3
                    pixels[offset:offset + 3] = block_color
    else:
        for char_index, digit in enumerate(label):
            glyph = _PIXEL_DIGITS[digit]
            for row_index, row in enumerate(glyph):
                for column_index, pixel in enumerate(row):
                    if pixel != "1":
                        continue
                    x0 = 12 + char_index * scale * 6 + column_index * scale
                    y0 = 12 + row_index * scale
                    for y in range(y0, y0 + scale):
                        for x in range(x0, x0 + scale):
                            offset = (y * width + x) * 3
                            pixels[offset:offset + 3] = b"\x00\x00\x00"

    def chunk(name: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data)) + name + data +
            struct.pack(">I", zlib.crc32(name + data) & 0xffffffff)
        )

    rows = b"".join(
        b"\x00" + pixels[row * width * 3:(row + 1) * width * 3]
        for row in range(height)
    )
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n" +
        chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) +
        chunk(b"IDAT", zlib.compress(rows)) +
        chunk(b"IEND", b"")
    )

_SENTINEL_COLORS = ("RED", "BLUE", "GREEN", "YELLOW")


def _sentinel_label() -> str:
    return _SENTINEL_COLORS[secrets.randbelow(len(_SENTINEL_COLORS))]


def _parse_adapter_json(text: str) -> Mapping[str, Any]:
    candidates = [text]
    candidates.extend(reversed([line for line in text.splitlines() if line.strip()]))
    for candidate in candidates:
        try:
            decoded = json.loads(candidate)
        except (TypeError, ValueError):
            continue
        if isinstance(decoded, Mapping) and "labels" in decoded:
            return decoded
        if isinstance(decoded, Mapping) and "decisions" in decoded:
            return decoded
        if isinstance(decoded, Mapping):
            message = decoded.get("message")
            if isinstance(message, Mapping):
                content = message.get("content")
                if isinstance(content, Sequence):
                    for item in reversed(content):
                        if not isinstance(item, Mapping) or not isinstance(item.get("text"), str):
                            continue
                        try:
                            nested = json.loads(item["text"])
                        except ValueError:
                            continue
                        if isinstance(nested, Mapping):
                            return nested
            for key in ("result", "message", "content"):
                value = decoded.get(key)
                if isinstance(value, str):
                    try:
                        nested = json.loads(value)
                    except ValueError:
                        continue
                    if isinstance(nested, Mapping):
                        return nested
    raise AdapterVisionError("adapter returned no parseable JSON result")


def _run_command(command: Sequence[str], env: Mapping[str, str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        list(command), capture_output=True, check=False, env=dict(env), text=True,
    )


def _write_probe_schema(path: Path) -> None:
    path.write_text(json.dumps({
        "type": "object",
        "additionalProperties": False,
        "required": ["labels"],
        "properties": {
            "labels": {
                "type": "array",
                "minItems": 2,
                "maxItems": 2,
                "items": {"type": "string"},
            },
        },
    }))


def verify_adapter_vision(
    adapter: str,
    run_command: Callable[..., subprocess.CompletedProcess] = _run_command,
    _retry_mismatch: bool = True,
) -> None:
    """Raise AdapterVisionError unless both random image labels are read exactly."""
    if adapter not in {"codex", "omp"}:
        raise AdapterVisionError("unsupported adapter: %s" % adapter)
    with tempfile.TemporaryDirectory(prefix="non-niq-v3-sentinel-") as directory:
        root = Path(directory)
        first_label = _sentinel_label()
        second_label = first_label
        for _ in range(8):
            second_label = _sentinel_label()
            if second_label != first_label:
                break
        if second_label == first_label:
            raise AdapterVisionError("could not generate distinct sentinel labels")
        labels = [first_label, second_label]
        attachments = []
        for index, label in enumerate(labels, 1):
            path = root / ("attachment-%04d.png" % index)
            _write_label_png(path, label)
            attachments.append(Attachment(
                product_id="sentinel-%d" % index,
                attachment_index=index,
                attachment_filename=path.name,
                sha256=sha256(path.read_bytes()).hexdigest(),
                local_path=path,
            ))
        prompt = (
            "Read the visible color in each attached image in attachment order. "
            "Return JSON only: {\"labels\":[\"first\",\"second\"]}."
        )
        output_path = root / "result.json"
        command = (
            build_codex_command(
                prompt, root / "probe-schema.json", output_path, attachments,
            )
            if adapter == "codex"
            else build_omp_command(prompt, attachments)
        )
        if adapter == "codex":
            _write_probe_schema(root / "probe-schema.json")
        result = run_command(command, env=_adapter_env())
        if result.returncode:
            raise AdapterVisionError(
                "%s sentinel failed: %s" % (adapter, result.stderr.strip())
            )
        text = output_path.read_text() if output_path.exists() else result.stdout
        parsed = _parse_adapter_json(text)
        received = parsed.get("labels")
        normalized_received = (
            [label.upper() for label in received]
            if isinstance(received, list) and all(isinstance(label, str) for label in received)
            else received
        )
        if normalized_received != labels:
            if _retry_mismatch:
                return verify_adapter_vision(adapter, run_command, _retry_mismatch=False)
            raise AdapterVisionError(
                "adapter label mismatch: expected=%s received=%s" % (
                    labels, parsed.get("labels"),
                ),
            )


def invoke_adapter(
    adapter: str, packet_prompt: str, attachments: Sequence[Attachment],
) -> Mapping[str, Any]:
    """Return the adapter's parsed final response only."""
    if adapter not in {"codex", "omp"}:
        raise AdapterVisionError("unsupported adapter: %s" % adapter)
    with tempfile.TemporaryDirectory(prefix="non-niq-v3-result-") as directory:
        output_path = Path(directory) / "result.json"
        command = (
            build_codex_command(packet_prompt, SCHEMA_PATH, output_path, attachments)
            if adapter == "codex"
            else build_omp_command(packet_prompt, attachments)
        )
        result = _run_command(command, _adapter_env())
        if result.returncode:
            raise AdapterVisionError(
                "%s invocation failed: %s" % (adapter, result.stderr.strip())
            )
        text = output_path.read_text() if output_path.exists() else result.stdout
        return _parse_adapter_json(text)


PROJECT = "sincere-hearth-273704"
_IDENTIFIER = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_TABLE_COMPONENT = re.compile(r"^[A-Za-z0-9_]+$")
_PROJECT_ID = re.compile(r"^[a-z][a-z0-9-]{4,28}[a-z0-9]$")
_CATEGORICAL_ATTRIBUTES = frozenset({
    "age_group",
    "bundle_type",
    "category",
    "fragrance_group",
    "function",
    "group_scent",
    "packaging",
    "sub_category",
    "variant",
    "variant_group",
})


def _identifier(value: str) -> str:
    if not _IDENTIFIER.fullmatch(value):
        raise ValueError("invalid identifier: %r" % value)
    return value


def _table_component(value: str) -> str:
    if not _TABLE_COMPONENT.fullmatch(value):
        raise ValueError("invalid table component: %r" % value)
    return value


def _project_identifier(value: str) -> str:
    if not _PROJECT_ID.fullmatch(value):
        raise ValueError("invalid project ID: %r" % value)
    return value


def _table_reference(project: str, table: str) -> str:
    parts = table.split(".")
    if len(parts) != 2:
        raise ValueError("table must be dataset.table: %r" % table)
    return "`%s.%s.%s`" % (
        _project_identifier(project), _table_component(parts[0]), _table_component(parts[1]),
    )


def _configured_table(value: Any, label: str) -> str:
    table = str(value or "").strip()
    if not table or table in {"-", "null"}:
        raise ValueError("%s is not configured" % label)
    _table_reference(PROJECT, table)
    return table


def primary_filter_table(filter_table_config: str, dataset: str) -> str:
    """Return the configured filter table owned by this dataset, if any."""
    tables = [entry.strip() for entry in str(filter_table_config or "").split(";") if entry.strip()]
    for table in tables:
        if table.startswith(dataset + "."):
            return table
    return ""


def _validate_dict_pattern(pattern: Mapping[str, Any]) -> Mapping[str, Any]:
    if not pattern:
        raise ValueError("dict pattern must not be empty")
    for target, definition in pattern.items():
        _identifier(str(target))
        if not isinstance(definition, Mapping):
            raise ValueError("dict pattern definition must be an object: %s" % target)
        if set(definition) != {"sources", "separator"}:
            raise ValueError("dict pattern must contain sources and separator: %s" % target)
        sources = definition["sources"]
        if not isinstance(sources, list) or not sources or not all(
            isinstance(source, str) and _IDENTIFIER.fullmatch(source) for source in sources
        ):
            raise ValueError("dict pattern sources must be non-empty identifiers: %s" % target)
        if not isinstance(definition["separator"], str):
            raise ValueError("dict pattern separator must be a string: %s" % target)
    _pattern_leaf_sources(pattern)
    return pattern


def _pattern_leaf_sources(pattern: Mapping[str, Any]) -> frozenset:
    leaves = set()
    active = set()

    def visit(target: str) -> None:
        if target in active:
            raise ValueError("dict pattern has a generated-column cycle: %s" % target)
        active.add(target)
        for source in pattern[target]["sources"]:
            if source in pattern:
                visit(source)
            else:
                leaves.add(source)
        active.remove(target)

    for target in pattern:
        visit(target)
    return frozenset(leaves)


def compose_generated_attributes(
    attributes: Mapping[str, str], pattern: Mapping[str, Any],
) -> Mapping[str, str]:
    """Generate deterministic dictionary columns from their validated leaf values."""
    values = {key: str(value).strip() for key, value in attributes.items()}

    def compose(target: str) -> str:
        if target in values:
            return values[target]
        definition = pattern[target]
        components = []
        for source in definition["sources"]:
            value = compose(source) if source in pattern else values.get(source, "")
            if value:
                components.append(value)
        value = definition["separator"].join(components)
        if not value:
            raise DecisionValidationError(
                "generated dictionary attribute is empty: %s" % target,
            )
        values[target] = value
        return value

    return {target: compose(target) for target in pattern}


def load_dict_pattern(dataset: str, root: Optional[Path] = None) -> Mapping[str, Any]:
    """Load the category's required generated-column pattern before retrieval."""
    root = root or Path(__file__).with_name("dict_patterns")
    path = Path(root) / (dataset + ".json")
    with path.open() as handle:
        pattern = json.load(handle)
    if not isinstance(pattern, Mapping):
        raise ValueError("dict pattern must be an object: %s" % path)
    return _validate_dict_pattern(pattern)


@dataclass(frozen=True)
class RunContext:
    project: str
    dataset: str
    platform: str
    country: str
    category: str
    merchant_ids: Tuple[str, ...]
    source_table: str
    qa_table: str
    dict_table: str
    filter_table: str
    product_id_dict: str
    enrichment_table: Optional[str]
    qa_pk_col: str
    dict_identity_col: str
    dict_typo_col: str
    qa_identity_col: str
    dict_has_meta: bool
    qa_columns: frozenset
    dict_columns: frozenset
    filter_columns: frozenset
    prior_mapping_columns: frozenset
    generated_attributes: frozenset
    dict_pattern: Mapping[str, Mapping[str, Any]]
    allowed_categorical_values: Mapping[str, frozenset]
    prior_mapping_pk_col: Optional[str]
    prior_mapping_identity_col: Optional[str]
    month: str
    meili_index: str
    taxonomy_url: Optional[str]



def _platform_match_sql(platform: str) -> str:
    if platform == "Tokopedia":
        return "IN ('Tokopedia', 'Tokopedia | Shop')"
    return "= @platform"




def build_worklist_parameters(
    context: RunContext,
    max_rows: int,
    kategori: str,
    merchant_ids: Sequence[str],
) -> Sequence[bigquery.QueryParameter]:
    return [
        bigquery.ScalarQueryParameter("month", "STRING", context.month),
        bigquery.ScalarQueryParameter("platform", "STRING", context.platform),
        bigquery.ScalarQueryParameter("row_limit", "INT64", max_rows),
        bigquery.ScalarQueryParameter("kategori", "STRING", kategori),
        bigquery.ArrayQueryParameter("merchant_ids", "STRING", list(merchant_ids)),
    ]


def build_worklist_sql(
    context: RunContext,
    max_rows: int,
    kategori: str,
    monthly_reverify: bool,
    merchant_ids: Sequence[str],
) -> str:
    """Return the v2-equivalent, parameterized stakeholder worklist query."""
    if max_rows <= 0:
        raise ValueError("max_rows must be positive")
    source = _table_reference(context.project, context.source_table)
    qa = _table_reference(context.project, context.qa_table)
    filter_table = _table_reference(context.project, context.filter_table)
    platform_match = _platform_match_sql(context.platform)
    # Keep Tokopedia and Tokopedia | Shop distinct. The config's single "tokopedia"
    # entry selects both raw source values, but QA state must never cross-suppress them.
    source_platform = "s.ecommerce_platform"
    qa_platform_column = _qa_platform_column(context)
    qa_platform = "`%s`" % _identifier(qa_platform_column)
    filter_cte = """filter_state AS (
  SELECT DISTINCT product_id FROM %s
),
""" % filter_table
    filter_join = "LEFT JOIN filter_state fs ON fs.product_id = sc.product_id"
    filter_where = "WHERE fs.product_id IS NULL"
    enrichment_cte = ""
    enrichment_join = ""
    enrichment_select = "NULL AS item_description, NULL AS product_attributes_attrs"
    if context.platform == "Shopee" and context.enrichment_table:
        enrichment = _table_reference(
            context.project,
            "%s.%s" % (context.dataset, _table_component(context.enrichment_table)),
        )

        enrichment_cte = """enrichment_dedup AS (
  SELECT item_itemid, item_description,
    (SELECT STRING_AGG(CONCAT(JSON_VALUE(a, '$.name'), '=', JSON_VALUE(a, '$.value')), '; ')
     FROM UNNEST(JSON_QUERY_ARRAY(COALESCE(
       SAFE.PARSE_JSON(product_attributes_attrs),
       SAFE.PARSE_JSON(REPLACE(REPLACE(REPLACE(REPLACE(product_attributes_attrs, ': None', ': null'), ': True', ': true'), ': False', ': false'), CHR(39), CHR(34)))
     ))) a) AS product_attributes_attrs
  FROM %s
  QUALIFY ROW_NUMBER() OVER (PARTITION BY item_itemid ORDER BY timestamp DESC) = 1
),
""" % enrichment
        enrichment_join = "LEFT JOIN enrichment_dedup e ON CAST(e.item_itemid AS STRING) = s.product_id"
        enrichment_select = "e.item_description, e.product_attributes_attrs"
    kategori_clause = "AND s.kategori = @kategori" if kategori else ""
    merchant_clause = "s.product_tier IN ('Tier 1')"
    if merchant_ids:
        merchant_clause = "(%s OR s.merchant_id IN UNNEST(@merchant_ids))" % merchant_clause
    reverify_cte = ""
    reverify_join = ""
    scoped_kategori = ""
    reverify_expr = "FALSE"
    reverify_prior = "NULL AS prior_sku_name, NULL AS prior_kategori"
    if monthly_reverify:
        scoped_kategori = ", s.kategori AS current_kategori"
        reverify_cte = """prior_snapshot AS (
  SELECT product_id, ecommerce_platform, sku_name AS prior_sku_name, kategori AS prior_kategori
  FROM %s
  WHERE ecommerce_platform %s
    AND FORMAT_DATE('%%Y-%%m', month) < @month
  QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id, ecommerce_platform ORDER BY month DESC) = 1
),
""" % (source, platform_match)
        reverify_join = "LEFT JOIN prior_snapshot ps ON ps.product_id = sc.product_id AND ps.ecommerce_platform = sc.ecommerce_platform"
        reverify_expr = (
            "(ps.product_id IS NOT NULL AND "
            "(ps.prior_sku_name IS DISTINCT FROM sc.sku_name OR "
            "ps.prior_kategori IS DISTINCT FROM sc.current_kategori))"
        )
        reverify_prior = "ps.prior_sku_name, ps.prior_kategori"
    return """WITH %s%s%s scoped AS (
  SELECT s.product_id, s.sku_name, s.image AS image_raw,
         %s AS ecommerce_platform,
         s.country, s.category, s.month, s.gmv_monthly, s.merchant_id,
         %s%s

  FROM %s s
  %s
  WHERE FORMAT_DATE('%%Y-%%m', s.month) = @month
    AND s.ecommerce_platform %s
    AND %s
    %s
),
stakeholder_scope AS (
  SELECT sc.*
  FROM scoped sc
  %s
  %s
),
qa_title_state AS (
  SELECT DISTINCT %s AS product_id,
    %s AS ecommerce_platform,
    REGEXP_REPLACE(TRIM(sku_name), r'\\s+', ' ') AS normalized_sku_name
  FROM %s
  WHERE %s %s
),
qa_state AS (
  SELECT
    %s AS product_id,
    %s AS ecommerce_platform,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '$.qa_confidence') = 'unconfident'
               AND COALESCE(JSON_VALUE(SAFE.PARSE_JSON(_meta), '$.human_review'), 'false') != 'true') AS has_unconfident_pending,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '$.qa_confidence') = 'confident') AS has_confident,
    LOGICAL_OR(JSON_VALUE(SAFE.PARSE_JSON(_meta), '$.human_review') = 'true') AS has_terminal
  FROM %s
  WHERE %s %s
  GROUP BY 1, 2
),
%sprioritized AS (
  SELECT sc.product_id, sc.sku_name, sc.image_raw, sc.gmv_monthly, sc.ecommerce_platform, sc.merchant_id,
         sc.item_description, sc.product_attributes_attrs,
         %s AS listing_changed, %s,
    CASE
      WHEN qts.product_id IS NULL THEN 0
      WHEN qs.has_unconfident_pending AND NOT qs.has_confident AND NOT qs.has_terminal THEN 1
      WHEN %s THEN 0
      ELSE NULL
    END AS priority
  FROM stakeholder_scope sc
  LEFT JOIN qa_title_state qts
    ON qts.product_id = sc.product_id
   AND qts.ecommerce_platform = sc.ecommerce_platform
   AND qts.normalized_sku_name = REGEXP_REPLACE(TRIM(sc.sku_name), r'\\s+', ' ')
  LEFT JOIN qa_state qs
    ON qs.product_id = sc.product_id
   AND qs.ecommerce_platform = sc.ecommerce_platform
  %s
)
SELECT * FROM prioritized
WHERE priority IS NOT NULL
ORDER BY priority ASC, gmv_monthly DESC
LIMIT @row_limit
""" % (
        enrichment_cte, filter_cte, "", source_platform, enrichment_select, scoped_kategori,
        source, enrichment_join, platform_match, merchant_clause, kategori_clause, filter_join, filter_where,
        _identifier(context.qa_pk_col), qa_platform, qa, qa_platform, platform_match,
        _identifier(context.qa_pk_col), qa_platform, qa, qa_platform, platform_match, reverify_cte,
        reverify_expr, reverify_prior, reverify_expr, reverify_join,
    )


def materialize_worklist(
    client, sql: str, parameters: Sequence[bigquery.QueryParameter] = (),
) -> List[Mapping[str, Any]]:
    """Return ordered worklist rows from one parameterized query."""
    job_config = bigquery.QueryJobConfig(query_parameters=list(parameters))
    return [dict(row.items()) for row in client.query(sql, job_config=job_config).result()]


def _first_available(
    columns: frozenset, candidates: Sequence[str], label: str,
) -> str:
    for candidate in candidates:
        if candidate in columns:
            return candidate
    raise ValueError("%s has none of %s" % (label, ", ".join(candidates)))


def _load_allowed_categorical_values(
    client, project: str, dict_table: str, dict_columns: frozenset,
) -> Mapping[str, frozenset]:
    categorical_columns = sorted(_CATEGORICAL_ATTRIBUTES & dict_columns)
    if not categorical_columns:
        return {}
    table = _table_reference(project, dict_table)
    selections = [
        "SELECT '%s' AS attribute, CAST(`%s` AS STRING) AS value FROM %s" % (
            column, _identifier(column), table,
        )
        for column in categorical_columns
    ]
    query = """SELECT attribute, value
FROM (%s)
WHERE NULLIF(TRIM(value), '') IS NOT NULL
GROUP BY attribute, value
""" % "\nUNION ALL\n".join(selections)
    values = {column: set() for column in categorical_columns}
    for row in client.query(query).result():
        row_values = dict(row.items())
        values[str(row_values["attribute"])].add(str(row_values["value"]))
    return {
        column: frozenset(column_values)
        for column, column_values in values.items()
    }


def _configured_optional_table(value: Any, label: str) -> Optional[str]:
    if str(value or "").strip() in {"", "-", "null"}:
        return None
    return _configured_table(value, label)


def resolve_run_context(args: Any, client) -> RunContext:
    """Resolve live config, schemas, month, merchant IDs, and dict pattern."""
    country = str(args.country).upper()
    requested_platform = str(args.platform).lower()
    configs = parse_categories(fetch_config_csv(), country=country)
    config = next(
        (
            item for item in configs
            if item["dataset"] == args.dataset and item["ecommerce_platform"].lower() == requested_platform
        ),
        None,
    )
    if config is None:
        raise ValueError("no active config for %s/%s/%s" % (args.dataset, args.platform, country))
    dataset = str(config["dataset"])
    source_table = _configured_table(config["master_table_prod"], "master_table_prod")
    qa_table = _configured_table(config["product_id_dict_qa"], "product_id_dict_qa")
    dict_table = _configured_table(config["dict"], "dict")
    filter_table = _configured_table(
        primary_filter_table(config["filter_table"], dataset), "filter_table",
    )
    pattern = load_dict_pattern(dataset)

    qa_columns = frozenset(_table_columns(client, PROJECT, qa_table))
    dict_columns = frozenset(_table_columns(client, PROJECT, dict_table))
    filter_columns = frozenset(_table_columns(client, PROJECT, filter_table))
    qa_pk_col = _first_available(
        qa_columns, ("product_id", "prod_id"), qa_table + " primary key",
    )
    qa_identity_col = _first_available(
        qa_columns, ("sku_type_complete", "sku_type"), qa_table + " identity",
    )
    dict_identity_col = _first_available(
        dict_columns, ("sku_type_complete", "sku_type"), dict_table + " identity",
    )
    dict_typo_col = _first_available(
        dict_columns, ("keywords_typo", "keyword_typo"), dict_table + " typo",
    )
    pattern_columns = frozenset(pattern)
    missing_pattern_columns = pattern_columns - dict_columns
    missing_pattern_leaves = _pattern_leaf_sources(pattern) - dict_columns
    if missing_pattern_columns or missing_pattern_leaves:
        raise ValueError(
            "dict pattern does not match %s: missing generated=%s leaves=%s" % (
                dict_table, sorted(missing_pattern_columns), sorted(missing_pattern_leaves),
            ),
        )
    if "product_id" not in filter_columns:
        raise ValueError("%s has no product_id column" % filter_table)
    product_id_dict = _configured_optional_table(
        config.get("product_id_dict", ""), "product_id_dict",
    )
    prior_mapping_columns = frozenset()
    prior_mapping_pk_col = None
    prior_mapping_identity_col = None
    if product_id_dict:
        prior_mapping_columns = frozenset(
            _table_columns(client, PROJECT, product_id_dict),
        )
        prior_mapping_pk_col = _first_available(
            prior_mapping_columns, ("product_id", "prod_id"),
            product_id_dict + " primary key",
        )
        prior_mapping_identity_col = _first_available(
            prior_mapping_columns, ("sku_type_complete", "sku_type"),
            product_id_dict + " identity",
        )
        if "brand" not in prior_mapping_columns:
            raise ValueError("%s has no brand column" % product_id_dict)
    allowed_categorical_values = _load_allowed_categorical_values(
        client, PROJECT, dict_table, dict_columns,
    )
    platform = str(config["ecommerce_platform"]).capitalize()
    platform_match = _platform_match_sql(platform)
    month_query = (
        "SELECT FORMAT_DATE('%%Y-%%m', MAX(month)) AS month "
        "FROM %s WHERE ecommerce_platform %s"
    ) % (_table_reference(PROJECT, source_table), platform_match)
    month_params = [] if platform == "Tokopedia" else [
        bigquery.ScalarQueryParameter("platform", "STRING", platform),
    ]
    month_rows = list(client.query(
        month_query, job_config=bigquery.QueryJobConfig(query_parameters=month_params),
    ).result())
    if not month_rows or not month_rows[0].month:
        raise ValueError("no source month for %s/%s" % (source_table, platform))
    try:
        merchant_ids = fetch_forced_merchant_ids(country, config["category"], platform)
    except Exception:
        merchant_ids = []
    return RunContext(
        project=PROJECT,
        dataset=dataset,
        platform=platform,
        country=country,
        category=str(config["category"]),
        merchant_ids=tuple(merchant_ids),
        source_table=source_table,
        qa_table=qa_table,
        dict_table=dict_table,
        filter_table=filter_table,
        product_id_dict=product_id_dict or "",
        enrichment_table=(
            None if str(config.get("0", "")) in {"", "-", "null"}
            else _table_component(str(config["0"]))
        ),
        qa_identity_col=qa_identity_col,
        qa_pk_col=qa_pk_col,
        dict_identity_col=dict_identity_col,
        dict_typo_col=dict_typo_col,
        dict_has_meta="_meta" in dict_columns,
        qa_columns=qa_columns,
        dict_columns=dict_columns,
        filter_columns=filter_columns,
        prior_mapping_columns=prior_mapping_columns,
        generated_attributes=pattern_columns,
        dict_pattern=pattern,
        allowed_categorical_values=allowed_categorical_values,
        prior_mapping_pk_col=prior_mapping_pk_col,
        prior_mapping_identity_col=prior_mapping_identity_col,
        month=str(month_rows[0].month),
        meili_index=dataset + "_taxonomy_qa",
        taxonomy_url=str(config.get("taxonomy_url", "") or "") or None,
    )


def resolve_candidate_refs(
    client, context: RunContext, hits: Sequence[Mapping[str, Any]],
) -> Mapping[str, Mapping[str, Mapping[str, Any]]]:
    """Resolve retrieved candidate identities to exact live dictionary rows in one query."""
    requested = []
    product_hits = {}
    for result in hits:
        row_key = worklist_row_key(result)
        product_hits[row_key] = []
        for hit in result.get("candidates", []):
            brand = str(hit.get("brand", "")).strip()
            identity = str(hit.get(context.dict_identity_col, hit.get("sku_type_complete", "")).strip())
            if brand and identity:
                product_hits[row_key].append((brand, identity))
                requested.append((brand, identity))
    if not requested:
        return {row_key: {} for row_key in product_hits}
    pairs = sorted(set(requested))
    query = """WITH requested AS (
  SELECT brand, identity_value
  FROM UNNEST(@candidate_pairs)
)
SELECT d.*
FROM %s d
JOIN requested r
  ON d.brand = r.brand AND d.%s = r.identity_value
""" % (_table_reference(context.project, context.dict_table), _identifier(context.dict_identity_col))
    parameter = bigquery.ArrayQueryParameter(
        "candidate_pairs",
        "STRUCT",
        [
            bigquery.StructQueryParameter(
                None,
                bigquery.ScalarQueryParameter("brand", "STRING", brand),
                bigquery.ScalarQueryParameter("identity_value", "STRING", identity),
            )
            for brand, identity in pairs
        ],
    )
    rows = list(client.query(
        query, job_config=bigquery.QueryJobConfig(query_parameters=[parameter]),
    ).result())
    resolved = {
        (
            str(dict(row.items())["brand"]),
            str(dict(row.items())[context.dict_identity_col]),
        ): dict(row.items())
        for row in rows
    }
    output = {}
    for row_key, candidate_pairs in product_hits.items():
        output[row_key] = {}
        for pair in candidate_pairs:
            row = resolved.get(pair)
            if row is not None:
                reference = "dict:" + _stable_digest({
                    "brand": pair[0], "identity": pair[1],
                })[:16]
                output[row_key][reference] = row
    return output


def auto_confirm_worklist(
    client, context: RunContext, rows: Sequence[Mapping[str, Any]],
    candidate_hits: Sequence[Mapping[str, Any]],
) -> Set[Tuple[str, str, str]]:
    """Confirm live dictionary candidates that exactly casefold-match the source title."""
    return confirm_casefold_matches(
        client,
        context.project,
        context.qa_table,
        context.qa_pk_col,
        _qa_platform_column(context),
        rows,
        candidate_hits,
        qa_identity_col=context.qa_identity_col,
        dict_table=context.dict_table,
        dict_identity_col=context.dict_identity_col,
    )


def resolve_prior_mappings(
    client, context: RunContext, product_ids: Sequence[str],
) -> Mapping[str, Mapping[str, Any]]:
    """Read configured product mappings in one batch without mutating them."""
    if not context.product_id_dict:
        return {}
    if not context.prior_mapping_pk_col or not context.prior_mapping_identity_col:
        raise ValueError("product_id_dict shape is unresolved")
    ids = sorted({str(product_id) for product_id in product_ids if str(product_id)})
    if not ids:
        return {}
    query = """SELECT *
FROM %s
WHERE `%s` IN UNNEST(@product_ids)
""" % (
        _table_reference(context.project, context.product_id_dict),
        _identifier(context.prior_mapping_pk_col),
    )
    parameter = bigquery.ArrayQueryParameter("product_ids", "STRING", ids)
    output = {}
    for row in client.query(
        query, job_config=bigquery.QueryJobConfig(query_parameters=[parameter]),
    ).result():
        row_values = dict(row.items())
        product_id = str(row_values[context.prior_mapping_pk_col])
        if product_id in output:
            raise ValueError("product_id_dict has multiple rows for product_id=%s" % product_id)
        output[product_id] = row_values
    return output


def build_product_packets(
    context: RunContext,
    rows: Sequence[Mapping[str, Any]],
    candidates: Mapping[Tuple[str, str, str], Mapping[str, Mapping[str, Any]]],
    images: Mapping[Tuple[str, str, str], PreparedImage],
    prior_mappings: Optional[Mapping[str, Mapping[str, Any]]] = None,
) -> List[Mapping[str, Any]]:
    """Combine ordered planning outputs into packet dictionaries bound to local attachments."""
    ordered_rows = sorted(
        rows,
        key=lambda row: (int(row.get("priority", 0)), -float(row.get("gmv_monthly", 0))),
    )
    ordered_images = [
        images.get(
            worklist_row_key(row),
            PreparedImage(_packet_id(row), None, "unavailable", None),
        )
        for row in ordered_rows
    ]
    attachment_by_packet = {
        attachment.product_id: attachment
        for attachment in build_attachment_manifest(ordered_images)
    }
    writable_attributes = frozenset(
        context.dict_columns - context.generated_attributes - {"_meta"}
    )
    prior_mappings = prior_mappings or {}
    packets = []

    for row, image in zip(ordered_rows, ordered_images):
        product_id = str(row["product_id"])
        row_key = worklist_row_key(row)
        packet_id = _packet_id(row)
        attempt_kind = (
            "listing_change" if row.get("listing_changed")
            else "retry" if int(row.get("priority", 0)) == 1
            else "initial"
        )
        attempt_row = dict(row)
        attachment = attachment_by_packet.get(image.product_id)
        attempt_row.update({
            "dataset": context.dataset,
            "platform": str(row.get("ecommerce_platform") or context.platform),
            "country": context.country,
            "image_url": image.image_url,
            "image_status": image.image_status,
            "image_sha256": attachment.sha256 if attachment else "",
        })
        attempt = plan_attempt(attempt_row, {"kind": attempt_kind})
        candidate_rows = candidates.get(row_key, {})
        packets.append({
            **dict(row),
            "packet_id": packet_id,
            "product_id": product_id,
            "work_item_id": attempt.work_item_id,
            "input_fingerprint": attempt.input_fingerprint,
            "attempt": attempt,
            "attempt_id": attempt.attempt_id,
            "attempt_kind": attempt.attempt_kind,
            "image_url": image.image_url,
            "image_status": image.image_status,
            "attachment_index": attachment.attachment_index if attachment else None,
            "attachment": attachment,
            "image_raw": row.get("image_raw"),
            "candidate_refs": set(candidate_rows),
            "candidates": candidate_rows,
            "prior_mapping": prior_mappings.get(product_id),
            "writable_attributes": writable_attributes,
            "generated_attributes": context.generated_attributes,
            "dict_pattern": context.dict_pattern,
            "allowed_categorical_values": context.allowed_categorical_values,
        })
    return packets


@dataclass(frozen=True)
class OutboxEvent:
    event_id: str
    attempt_id: str
    decision_id: str
    event_type: str
    payload: str


@dataclass(frozen=True)
class TaxonomyInsertLog:
    target_table: str
    row_json: str


@dataclass(frozen=True)
class ChunkCommit:
    attempts: Tuple[AttemptPlan, ...]
    created_dict_identities: Tuple[Tuple[str, str, str], ...]
    outbox_events: Tuple[OutboxEvent, ...]
    taxonomy_insert_logs: Tuple[TaxonomyInsertLog, ...]

    qa_writes: Tuple[Tuple[str, str, str, str, str], ...]
    filtered_products: Tuple[Tuple[str, str], ...]
    qa_expected: Tuple[Mapping[str, Any], ...] = ()
    filter_expected: Tuple[Mapping[str, Any], ...] = ()
    dict_expected: Tuple[Mapping[str, Any], ...] = ()


class _ParameterBuilder:
    def __init__(self) -> None:
        self.parameters: List[bigquery.QueryParameter] = []

    def add(self, value: Any, parameter_type: str = "STRING") -> str:
        name = "p_%d" % len(self.parameters)
        self.parameters.append(
            bigquery.ScalarQueryParameter(name, parameter_type, value),
        )
        return "@" + name


def _timestamp(now: datetime) -> str:
    if now.tzinfo is None:
        now = now.replace(tzinfo=timezone.utc)
    return now.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def _metadata(
    now: datetime, run_id: str, attempt: AttemptPlan, decision_id: str, confidence: str,
    human_review: bool,
) -> str:
    return json.dumps({
        "source": "non_niq_qa_v3",
        "timestamp": _timestamp(now),
        "run_id": run_id,
        "attempt_id": attempt.attempt_id,
        "attempt_kind": attempt.attempt_kind,
        "decision_id": decision_id,
        "qa_confidence": confidence,
        "human_review": human_review,
    }, sort_keys=True, separators=(",", ":"))


def _filter_platform_column(context: RunContext) -> Optional[str]:
    for column in ("ecommerce_platform", "ecommerce"):
        if column in context.filter_columns:
            return column
    return None


def _qa_platform_column(context: RunContext) -> str:
    for column in ("ecommerce_platform", "ecommerce"):
        if column in context.qa_columns:
            return column
    raise ValueError("%s has no platform column" % context.qa_table)


def _build_operations(
    context: RunContext,
    packets: Sequence[Mapping[str, Any]],
    decisions: Sequence[Mapping[str, Any]],
    now: datetime,
    existing_identities: Sequence[Tuple[str, str, str]] = (),
) -> Tuple[List[Mapping[str, Any]], ChunkCommit]:
    existing_identities = set(existing_identities)
    validated = validate_decision_batch({"decisions": list(decisions)}, packets)
    run_id = _stable_digest({
        "dataset": context.dataset,
        "platform": context.platform,
        "country": context.country,
        "attempts": [packet["attempt_id"] for packet in packets],
        "timestamp": _timestamp(now),
    })[:24]
    operations: List[Mapping[str, Any]] = []
    attempts: List[AttemptPlan] = []
    created_identities: List[Tuple[str, str, str]] = []
    qa_writes: List[Tuple[str, str, str, str, str]] = []
    filtered_products: List[Tuple[str, str]] = []
    qa_expected: List[Mapping[str, Any]] = []
    filter_expected: List[Mapping[str, Any]] = []
    dict_expected: List[Mapping[str, Any]] = []
    outbox_events: List[OutboxEvent] = []
    taxonomy_insert_logs: List[TaxonomyInsertLog] = []

    seen_identities = set()

    for packet, decision in zip(packets, validated):
        kind = decision["kind"]
        if kind == "defer":
            continue
        attempt = packet.get("attempt")
        _require(isinstance(attempt, AttemptPlan), "packet attempt is invalid")
        decision_id = _stable_digest({
            "attempt_id": attempt.attempt_id,
            "decision": decision,
        })
        confidence = str(decision["confidence"])
        human_review = attempt.attempt_kind == "retry" and confidence == "unconfident"
        base = {
            "packet": packet,
            "decision": decision,
            "attempt": attempt,
            "decision_id": decision_id,
            "confidence": confidence,
            "human_review": human_review,
            "run_id": run_id,
        }
        if kind == "filter":
            operation = {**base, "kind": kind}
            operations.append(operation)
            filtered_products.append((
                str(packet["product_id"]),
                str(packet.get("ecommerce_platform") or context.platform),
            ))
            filter_expected.append(_filter_values(context, operation, now))
            continue

        if kind == "map_existing":
            candidate = packet.get("candidates", {}).get(decision["candidate_ref"])
            _require(isinstance(candidate, Mapping), "candidate row is unavailable")
            brand = str(candidate.get("brand", "")).strip()
            identity = str(candidate.get(context.dict_identity_col, "")).strip()
            _require(brand and identity, "candidate row has no natural identity")
            dictionary_values = None
            natural_identity = None
            is_existing = False
        else:
            attributes = decision["attributes"]
            generated = compose_generated_attributes(attributes, context.dict_pattern)
            dictionary_values = {**attributes, **generated}

            brand = str(dictionary_values.get("brand", "")).strip()
            identity = str(dictionary_values.get(context.dict_identity_col, "")).strip()
            _require(brand and identity, "create_dict requires brand and dictionary identity")
            natural_identity = (brand, context.dict_identity_col, identity)
            _require(
                natural_identity not in seen_identities,
                "duplicate dictionary identity in one chunk",
            )
            seen_identities.add(natural_identity)
            for candidate in packet.get("candidates", {}).values():
                if (
                    str(candidate.get("brand", "")).strip() == brand
                    and str(candidate.get(context.dict_identity_col, "")).strip() == identity
                ):
                    raise DecisionValidationError(
                        "create_dict natural identity already exists in packet candidates",
                    )
            is_existing = natural_identity in existing_identities
            if not is_existing and context.dict_has_meta:
                dictionary_values["_meta"] = _metadata(
                    now, run_id, attempt, decision_id, confidence, human_review,
                )
            if not is_existing:
                created_identities.append(natural_identity)

        qa_identity = identity
        attempts.append(attempt)
        qa_writes.append((
            str(packet["product_id"]),
            str(packet.get("ecommerce_platform") or context.platform),
            brand,
            qa_identity,
            attempt.attempt_id,
        ))
        operation = {
            **base,
            "kind": kind,
            "brand": brand,
            "identity": identity,
            "qa_identity": qa_identity,
            "dictionary_values": dictionary_values,
            "existing_identity": is_existing,
        }
        operations.append(operation)
        qa_expected.append(_qa_values(context, operation, now))
        if kind == "create_dict":
            dict_expected.append({
                "brand": brand,
                context.dict_identity_col: identity,
                **(dictionary_values or {}),
            })
        if kind != "create_dict" or is_existing:
            continue
        taxonomy_insert_logs.append(TaxonomyInsertLog(
            target_table="%s.%s" % (context.project, context.dict_table),
            row_json=json.dumps({
                "product_id": str(packet["product_id"]),
                "ecommerce_platform": str(
                    packet.get("ecommerce_platform") or context.platform
                ),
                "inserted_row": dict(dictionary_values),
            }, sort_keys=True, separators=(",", ":"), default=str),
        ))

        identity_entry = {
            "brand": brand,
            "identity_col": context.dict_identity_col,
            "identity_value": identity,
        }
        if context.taxonomy_url:
            payload = json.dumps({
                "project": context.project,
                "dict_table": context.dict_table,
                "sheet_url": context.taxonomy_url,
                "entry": identity_entry,
            }, sort_keys=True, separators=(",", ":"))
            event_id = _stable_digest({
                "attempt_id": attempt.attempt_id,
                "decision_id": decision_id,
                "event_type": "sheet_append",
                "payload": payload,
            })
            outbox_events.append(OutboxEvent(
                event_id, attempt.attempt_id, decision_id, "sheet_append", payload,
            ))
        if confidence == "confident":
            payload = json.dumps({
                "meili_url": MEILI_URL,
                "meili_index": context.meili_index,
                "document": {
                    "product_id": str(packet["product_id"]),
                    "sku_name": str(packet.get("sku_name", "")),
                    "sku_type_complete": qa_identity,
                    "brand": brand,
                },
            }, sort_keys=True, separators=(",", ":"))
            event_id = _stable_digest({
                "attempt_id": attempt.attempt_id,
                "decision_id": decision_id,
                "event_type": "meili_index",
                "payload": payload,
            })
            outbox_events.append(OutboxEvent(
                event_id, attempt.attempt_id, decision_id, "meili_index", payload,
            ))

    return operations, ChunkCommit(
        attempts=tuple(attempts),
        created_dict_identities=tuple(created_identities),
        outbox_events=tuple(outbox_events),
        taxonomy_insert_logs=tuple(taxonomy_insert_logs),
        qa_writes=tuple(qa_writes),
        filtered_products=tuple(filtered_products),
        qa_expected=tuple(qa_expected),
        filter_expected=tuple(filter_expected),
        dict_expected=tuple(dict_expected),
    )
def _conditional_insert(
    table: str,
    values: Mapping[str, Tuple[str, str]],
    predicate: str,
) -> str:
    columns = ", ".join("`%s`" % _identifier(column) for column in values)
    selected = ", ".join(parameter for _, parameter in values.values())
    return "INSERT INTO %s (%s)\nSELECT %s\nWHERE %s;" % (
        table, columns, selected, predicate,
    )


def _insert_values(
    builder: _ParameterBuilder, values: Mapping[str, Any],
) -> Mapping[str, Tuple[str, str]]:
    return {
        column: ("STRING", builder.add(value))
        for column, value in values.items()
    }


def _filter_values(
    context: RunContext, operation: Mapping[str, Any],
    now: datetime,
) -> Mapping[str, Any]:
    packet = operation["packet"]
    values = {"product_id": str(packet["product_id"])}
    platform_column = _filter_platform_column(context)
    if platform_column:
        values[platform_column] = str(packet.get("ecommerce_platform") or context.platform)
    for column, packet_column in (
        ("sku_name", "sku_name"),
        ("merchant_id", "merchant_id"),
        ("url", "url"),
        ("reason", None),
    ):
        if column not in context.filter_columns:
            continue
        values[column] = (
            operation["decision"]["reason"] if packet_column is None
            else str(packet.get(packet_column, ""))
        )
    if "_meta" in context.filter_columns:
        values["_meta"] = _metadata(
            now, operation["run_id"], operation["attempt"], operation["decision_id"],
            operation["confidence"], operation["human_review"],
        )
    return values


def _qa_values(
    context: RunContext, operation: Mapping[str, Any], now: datetime,
) -> Mapping[str, Any]:
    packet = operation["packet"]
    platform_column = _qa_platform_column(context)
    required = {
        context.qa_pk_col: str(packet["product_id"]),
        platform_column: str(packet.get("ecommerce_platform") or context.platform),
        "brand": operation["brand"],
        context.qa_identity_col: operation["qa_identity"],
        "_meta": _metadata(
            now, operation["run_id"], operation["attempt"], operation["decision_id"],
            operation["confidence"], operation["human_review"],
        ),
    }
    if not set(required).issubset(context.qa_columns):
        raise ValueError("%s is missing a required v3 QA column" % context.qa_table)
    values = dict(required)
    if "sku_name" in context.qa_columns:
        values["sku_name"] = str(packet.get("sku_name", ""))
    if "url" in context.qa_columns:
        values["url"] = str(packet.get("url", ""))
    if "gmv" in context.qa_columns:
        values["gmv"] = str(packet.get("gmv_monthly", ""))
    return values


def _outbox_table(context: RunContext) -> str:
    return _table_reference(context.project, "magpie_reference.non_niq_qa_outbox")

def _insert_log_table(context: RunContext) -> str:
    return _table_reference(context.project, "magpie_reference.non_niq_taxonomy_insert_log")

def _identity_lock_table(context: RunContext) -> str:
    return _table_reference(context.project, "magpie_reference.non_niq_qa_identity_locks")


def build_chunk_script(
    context: RunContext,
    packets: Sequence[Mapping[str, Any]],
    decisions: Sequence[Mapping[str, Any]],
    now: datetime,
    existing_identities: Sequence[Tuple[str, str, str]] = (),
) -> Tuple[str, Sequence[Any]]:
    """Return one parameterized transaction script and its query parameters."""
    operations, commit = _build_operations(
        context, packets, decisions, now, existing_identities,
    )
    if not operations:
        return "", ()

    builder = _ParameterBuilder()
    statements = ["BEGIN TRANSACTION;"]
    create_operations = [item for item in operations if item["kind"] == "create_dict"]
    if create_operations:
        statements.append(
            "UPDATE %s SET touched_at = CURRENT_TIMESTAMP() "
            "WHERE lock_scope = 'non_niq_qa_global';" % _identity_lock_table(context)
        )
    dict_table = _table_reference(context.project, context.dict_table)
    if create_operations:
        authored_columns = sorted({
            column
            for operation in create_operations
            for column in operation["dictionary_values"]
            if column != "_meta"
        })
        requested_rows = []
        for operation in create_operations:
            fields = [
                "%s AS _v3_brand" % builder.add(operation["brand"]),
                "%s AS _v3_identity_value" % builder.add(operation["identity"]),
            ]
            authored = operation["dictionary_values"]
            for column in authored_columns:
                present = column in authored
                value = authored.get(column)
                fields.extend([
                    "%s AS `_v3_value_%s`" % (builder.add(value), _identifier(column)),
                    "%s AS `_v3_has_%s`" % (
                        "TRUE" if present else "FALSE", _identifier(column),
                    ),
                ])
            requested_rows.append("SELECT " + ", ".join(fields))
        statements.append(
            "CREATE TEMP TABLE _v3_requested_dict AS\n"
            + "\nUNION ALL\n".join(requested_rows) + ";"
        )
        conflict_terms = []
        for column in authored_columns:
            conflict_terms.append(
                "(r.`_v3_has_%s` AND d.`%s` IS DISTINCT FROM r.`_v3_value_%s`)" % (
                    _identifier(column), _identifier(column), _identifier(column),
                )
            )
        statements.append(
            """ASSERT NOT EXISTS (
  SELECT 1
  FROM %s d
  JOIN _v3_requested_dict r
    ON d.brand = r._v3_brand
   AND d.`%s` = r._v3_identity_value
  WHERE %s
) AS 'existing dictionary identity has conflicting authored attributes';""" % (
                dict_table,
                _identifier(context.dict_identity_col),
                " OR ".join(conflict_terms),
            )
        )
        statements.append(
            """CREATE TEMP TABLE _v3_new_dict AS
SELECT r._v3_brand AS brand, r._v3_identity_value AS identity_value
FROM _v3_requested_dict r
LEFT JOIN %s d
  ON d.brand = r._v3_brand AND d.`%s` = r._v3_identity_value
WHERE d.brand IS NULL;""" % (
                dict_table, _identifier(context.dict_identity_col),
            )
        )

    for operation in (item for item in operations if item["kind"] == "filter"):
        values = _insert_values(builder, _filter_values(context, operation, now))
        product_parameter = values["product_id"][1]
        predicate = "NOT EXISTS (SELECT 1 FROM %s f WHERE f.`product_id` = %s" % (
            _table_reference(context.project, context.filter_table), product_parameter,
        )
        platform_column = _filter_platform_column(context)
        if platform_column:
            predicate += " AND %s = %s" % (
                "f.`%s`" % _identifier(platform_column),
                values[platform_column][1],
            )
        predicate += ")"
        statements.append(_conditional_insert(
            _table_reference(context.project, context.filter_table), values, predicate,
        ))

    new_log_operations = (
        (operation, log)
        for operation, log in zip(
            (item for item in create_operations if not item["existing_identity"]),
            commit.taxonomy_insert_logs,
        )
    )
    for operation in create_operations:
        dict_values = dict(operation["dictionary_values"])
        if not set(dict_values).issubset(context.dict_columns):
            raise ValueError("create_dict values do not match %s schema" % context.dict_table)
        values = _insert_values(builder, dict_values)
        statements.append(_conditional_insert(
            dict_table,
            values,
            "NOT EXISTS (SELECT 1 FROM %s d WHERE d.brand = %s AND d.`%s` = %s)" % (
                dict_table, values["brand"][1],
                _identifier(context.dict_identity_col),
                values[context.dict_identity_col][1],
            ),
        ))
        if operation["existing_identity"]:
            continue
        _, log = next(new_log_operations)
        target_parameter = builder.add(log.target_table)
        row_parameter = builder.add(log.row_json)
        statements.append(
            """INSERT INTO %s (target_table, created_at, row_json)
SELECT %s, CURRENT_TIMESTAMP(), PARSE_JSON(%s)
WHERE EXISTS (
  SELECT 1 FROM _v3_new_dict
  WHERE brand = %s AND identity_value = %s
);""" % (
                _insert_log_table(context),
                target_parameter,
                row_parameter,
                values["brand"][1],
                values[context.dict_identity_col][1],
            )
        )

    qa_table = _table_reference(context.project, context.qa_table)
    qa_platform_column = _qa_platform_column(context)
    for operation in (
        item for item in operations if item["kind"] in {"map_existing", "create_dict"}
    ):
        values = _insert_values(builder, _qa_values(context, operation, now))
        attempt_parameter = builder.add(operation["attempt"].attempt_id)
        predicate = """NOT EXISTS (
  SELECT 1 FROM %s q
  WHERE q.`%s` = %s
    AND %s = %s
    AND JSON_VALUE(SAFE.PARSE_JSON(_meta), '$.attempt_id') = %s
)""" % (
            qa_table, _identifier(context.qa_pk_col), values[context.qa_pk_col][1],
            "q.`%s`" % _identifier(qa_platform_column),
            values[qa_platform_column][1],
            attempt_parameter,
        )
        statements.append(_conditional_insert(qa_table, values, predicate))

    for operation in create_operations:
        if operation["existing_identity"]:
            continue
        for event in commit.outbox_events:
            if event.attempt_id != operation["attempt"].attempt_id:
                continue
            values = _insert_values(builder, {
                "event_id": event.event_id,
                "attempt_id": event.attempt_id,
                "decision_id": event.decision_id,
                "dataset": context.dataset,
                "platform": context.platform,
                "country": context.country,
                "event_type": event.event_type,
                "payload": event.payload,
                "status": "pending",
                "last_error": None,
            })
            values["attempts"] = ("INT64", builder.add(0, "INT64"))
            values["created_at"] = ("TIMESTAMP", builder.add(now, "TIMESTAMP"))
            values["completed_at"] = ("TIMESTAMP", builder.add(None, "TIMESTAMP"))
            statements.append(_conditional_insert(
                _outbox_table(context),
                values,
                """NOT EXISTS (
  SELECT 1 FROM %s o WHERE o.event_id = %s
)""" % (
                    _outbox_table(context),
                    values["event_id"][1],
                ),
            ))
    statements.append("COMMIT TRANSACTION;")
    return "\n\n".join(statements), tuple(builder.parameters)


def _preflight_create_identities(
    client, context: RunContext, operations: Sequence[Mapping[str, Any]],
) -> Tuple[Tuple[str, str, str], ...]:
    creates = [operation for operation in operations if operation["kind"] == "create_dict"]
    if not creates:
        return ()
    authored_columns = sorted({
        column
        for operation in creates
        for column in operation["dictionary_values"]
        if column not in {"_meta", "brand", context.dict_identity_col}
    })
    builder = _ParameterBuilder()
    requested = "\nUNION ALL\n".join(
        "SELECT %s AS _v3_brand, %s AS _v3_identity_value" % (
            builder.add(operation["brand"]),
            builder.add(operation["identity"]),
        )
        for operation in creates
    )
    selected = ", ".join(
        "d.`%s` AS `_v3_%s`" % (_identifier(column), _identifier(column))
        for column in authored_columns
    )
    query = """WITH requested AS (
%s
)
SELECT d.brand AS _v3_brand,
       d.`%s` AS _v3_identity_value%s
FROM %s d
JOIN requested r
  ON d.brand = r._v3_brand AND d.`%s` = r._v3_identity_value
""" % (
        requested,
        _identifier(context.dict_identity_col),
        ",\n       " + selected if selected else "",
        _table_reference(context.project, context.dict_table),
        _identifier(context.dict_identity_col),
    )
    rows = [
        dict(row.items())
        for row in client.query(
            query,
            job_config=bigquery.QueryJobConfig(query_parameters=builder.parameters),
        ).result()
    ]
    by_identity = {
        (str(row["_v3_brand"]), str(row["_v3_identity_value"])): row
        for row in rows
    }
    exact = []
    for operation in creates:
        key = (operation["brand"], operation["identity"])
        row = by_identity.get(key)
        if row is None:
            continue
        authored = {
            column: value
            for column, value in operation["dictionary_values"].items()
            if column != "_meta"
        }
        conflicts = [
            column for column, value in authored.items()
            if row.get("_v3_" + column) != value
        ]
        if conflicts:
            raise DecisionValidationError(
                "create_dict natural identity conflicts on %s in %s"
                % (", ".join(conflicts), context.dict_table),
            )
        exact.append((operation["brand"], context.dict_identity_col, operation["identity"]))
    return tuple(exact)


def _is_transient(error: Exception) -> bool:
    if isinstance(error, (ConnectionError, TimeoutError)):
        return True
    status = getattr(error, "code", None)
    status = status() if callable(status) else status
    return status in {429, 500, 502, 503, 504}


def apply_chunk(
    client,
    context: RunContext,
    packets: Sequence[Mapping[str, Any]],
    decisions: Sequence[Mapping[str, Any]],
    now: datetime,
) -> ChunkCommit:
    """Execute one validated chunk with bounded transient retries and read-back."""
    operations, _ = _build_operations(context, packets, decisions, now)
    if not operations:
        return ChunkCommit(
            attempts=(),
            created_dict_identities=(),
            outbox_events=(),
            taxonomy_insert_logs=(),
            qa_writes=(),
            filtered_products=(),
        )
    existing_identities = _preflight_create_identities(client, context, operations)
    operations, commit = _build_operations(
        context, packets, decisions, now, existing_identities,
    )
    script, parameters = build_chunk_script(
        context, packets, decisions, now, existing_identities,
    )
    for attempt_number in range(3):
        try:
            client.query(
                script,
                job_config=bigquery.QueryJobConfig(query_parameters=list(parameters)),
            ).result()
            break
        except Exception as error:
            if attempt_number == 2 or not _is_transient(error):
                raise
    verify_chunk_commit(client, context, commit)
    return commit


def _assert_readback(
    client, query: str, parameters: Sequence[bigquery.QueryParameter], label: str,
) -> None:
    rows = list(client.query(
        query,
        job_config=bigquery.QueryJobConfig(query_parameters=list(parameters)),
    ).result())
    if not rows:
        raise RuntimeError("missing committed %s" % label)



def _assert_exact_mapping(
    client, table: str, alias: str, values: Mapping[str, Any], label: str,
) -> None:
    predicates = []
    parameters = []
    for index, column in enumerate(sorted(values)):
        name = "expected_%d" % index
        predicates.append(
            "%s.`%s` IS NOT DISTINCT FROM @%s" % (
                alias, _identifier(column), name,
            )
        )
        parameters.append(
            bigquery.ScalarQueryParameter(
                name, "STRING", None if values[column] is None else str(values[column]),
            )
        )
    _assert_readback(
        client,
        "SELECT 1 FROM %s %s WHERE %s LIMIT 1" % (
            table, alias, " AND ".join(predicates),
        ),
        parameters,
        label,
    )
def verify_chunk_commit(client, context: RunContext, commit: ChunkCommit) -> None:
    """Read back exact committed QA, filter, dictionary, and outbox identities."""
    qa_table = _table_reference(context.project, context.qa_table)
    qa_platform_column = _qa_platform_column(context)
    for expected in commit.qa_expected:
        _assert_exact_mapping(
            client, qa_table, "q", expected,
            "exact QA row for product_id=%s" % expected.get(context.qa_pk_col),
        )
    for product_id, platform, brand, qa_identity, attempt_id in commit.qa_writes:
        _assert_readback(
            client,
            """SELECT 1
FROM %s q
WHERE q.`%s` = @product_id
  AND %s = @platform
  AND q.`brand` = @brand
  AND q.`%s` = @qa_identity
  AND JSON_VALUE(SAFE.PARSE_JSON(_meta), '$.attempt_id') = @attempt_id
LIMIT 1""" % (
                qa_table, _identifier(context.qa_pk_col),
                "q.`%s`" % _identifier(qa_platform_column),
                _identifier(context.qa_identity_col),
            ),
            [
                bigquery.ScalarQueryParameter("product_id", "STRING", product_id),
                bigquery.ScalarQueryParameter("platform", "STRING", platform),
                bigquery.ScalarQueryParameter("brand", "STRING", brand),
                bigquery.ScalarQueryParameter("qa_identity", "STRING", qa_identity),
                bigquery.ScalarQueryParameter("attempt_id", "STRING", attempt_id),
            ],
            "QA row for attempt_id=%s" % attempt_id,
        )

    filter_table = _table_reference(context.project, context.filter_table)
    for expected in commit.filter_expected:
        _assert_exact_mapping(
            client, filter_table, "f", expected,
            "exact filter row for product_id=%s" % expected.get("product_id"),
        )
    filter_platform_column = _filter_platform_column(context)
    for product_id, platform in commit.filtered_products:
        predicate = "f.`product_id` = @product_id"
        parameters = [bigquery.ScalarQueryParameter("product_id", "STRING", product_id)]
        if filter_platform_column:
            predicate += " AND f.`%s` = @platform" % _identifier(filter_platform_column)
            parameters.append(bigquery.ScalarQueryParameter("platform", "STRING", platform))
        _assert_readback(
            client,
            "SELECT 1 FROM %s f WHERE %s LIMIT 1" % (filter_table, predicate),
            parameters,
            "filter row for product_id=%s" % product_id,
        )

    dict_table = _table_reference(context.project, context.dict_table)
    for expected in commit.dict_expected:
        _assert_exact_mapping(
            client, dict_table, "d", expected,
            "exact dictionary row for %s/%s" % (
                expected.get("brand"), expected.get(context.dict_identity_col),
            ),
        )
    for brand, identity_column, identity_value in commit.created_dict_identities:
        _assert_readback(
            client,
            "SELECT 1 FROM %s d WHERE d.`brand` = @brand AND d.`%s` = @identity LIMIT 1" % (
                dict_table, _identifier(identity_column),
            ),
            [
                bigquery.ScalarQueryParameter("brand", "STRING", brand),
                bigquery.ScalarQueryParameter("identity", "STRING", identity_value),
            ],
            "dictionary identity %s/%s" % (brand, identity_value),
        )

    insert_log_table = _insert_log_table(context)
    for log in commit.taxonomy_insert_logs:
        _assert_readback(
            client,
            """SELECT 1
FROM %s
WHERE target_table = @target_table
  AND TO_JSON_STRING(row_json) = TO_JSON_STRING(PARSE_JSON(@row_json))
LIMIT 1""" % insert_log_table,
            [
                bigquery.ScalarQueryParameter("target_table", "STRING", log.target_table),
                bigquery.ScalarQueryParameter("row_json", "STRING", log.row_json),
            ],
            "taxonomy insert log for %s" % log.target_table,
        )

    outbox_table = _outbox_table(context)
    for event in commit.outbox_events:
        _assert_readback(
            client,
            """SELECT 1
FROM %s
WHERE event_id = @event_id
  AND attempt_id = @attempt_id
  AND event_type = @event_type
  AND payload = @payload
  AND status = 'pending'
LIMIT 1""" % outbox_table,
            [
                bigquery.ScalarQueryParameter("event_id", "STRING", event.event_id),
                bigquery.ScalarQueryParameter("attempt_id", "STRING", event.attempt_id),
                bigquery.ScalarQueryParameter("event_type", "STRING", event.event_type),
                bigquery.ScalarQueryParameter("payload", "STRING", event.payload),
            ],
            "outbox event %s" % event.event_id,
        )

def _is_readable_image(image_bytes: bytes) -> bool:
    """Validate common image containers without adding a decoder dependency."""
    if image_bytes.startswith(b"\x89PNG\r\n\x1a\n"):
        if len(image_bytes) < 33 or image_bytes[12:16] != b"IHDR":
            return False
        width, height = struct.unpack(">II", image_bytes[16:24])
        if not width or not height:
            return False
        index = 8
        saw_idat = False
        saw_iend = False
        idat_parts = []
        while index + 8 <= len(image_bytes):
            length = struct.unpack(">I", image_bytes[index:index + 4])[0]
            end = index + 12 + length
            if end > len(image_bytes):
                return False
            chunk_type = image_bytes[index + 4:index + 8]
            chunk_data = image_bytes[index + 8:index + 8 + length]
            if chunk_type == b"IDAT":
                saw_idat = True
                idat_parts.append(chunk_data)
            if chunk_type == b"IEND":
                saw_iend = True
                index = end
                break
            index = end
        try:
            return (
                saw_idat and saw_iend and index == len(image_bytes)
                and bool(zlib.decompress(b"".join(idat_parts)))
            )
        except zlib.error:
            return False

    if image_bytes[:6] in {b"GIF87a", b"GIF89a"}:
        if len(image_bytes) < 13:
            return False
        width, height = struct.unpack("<HH", image_bytes[6:10])
        if not width or not height:
            return False
        index = 13
        packed = image_bytes[10]
        if packed & 0x80:
            index += 3 * (2 ** ((packed & 0x07) + 1))
        if index > len(image_bytes):
            return False
        saw_image = False
        while index < len(image_bytes):
            block = image_bytes[index]
            index += 1
            if block == 0x3B:
                return saw_image and index == len(image_bytes)
            if block == 0x2C:
                if index + 9 > len(image_bytes):
                    return False
                packed = image_bytes[index + 8]
                index += 9
                if packed & 0x80:
                    index += 3 * (2 ** ((packed & 0x07) + 1))
                if index >= len(image_bytes):
                    return False
                index += 1
                saw_data = False
                while True:
                    if index >= len(image_bytes):
                        return False
                    size = image_bytes[index]
                    index += 1
                    if size == 0:
                        break
                    saw_data = True
                    index += size
                    if index > len(image_bytes):
                        return False
                if not saw_data:
                    return False
                saw_image = True
                continue
            if block == 0x21:
                if index >= len(image_bytes):
                    return False
                index += 1
            else:
                return False
            while True:
                if index >= len(image_bytes):
                    return False
                size = image_bytes[index]
                index += 1
                if size == 0:
                    break
                index += size
                if index > len(image_bytes):
                    return False
        return False

    if image_bytes.startswith(b"\xff\xd8"):
        index = 2
        saw_frame = False
        while index + 1 < len(image_bytes):
            if image_bytes[index] != 0xFF:
                index += 1
                continue
            marker = image_bytes[index + 1]
            if marker == 0x00 or marker == 0xFF:
                index += 1
                continue
            index += 2
            if marker == 0xD9:
                return saw_frame and index == len(image_bytes)
            if marker in {0xD8} or 0xD0 <= marker <= 0xD7:
                continue
            if index + 2 > len(image_bytes):
                return False
            length = struct.unpack(">H", image_bytes[index:index + 2])[0]
            if length < 2 or index + length > len(image_bytes):
                return False
            if marker == 0xDA:
                index += length
                while index + 1 < len(image_bytes):
                    if image_bytes[index] != 0xFF:
                        index += 1
                        continue
                    next_marker = image_bytes[index + 1]
                    if next_marker == 0x00 or 0xD0 <= next_marker <= 0xD7:
                        index += 2
                        continue
                    if next_marker == 0xD9:
                        return saw_frame and index + 2 == len(image_bytes)
                    break
                return False
            if marker in (
                set(range(0xC0, 0xC4)) | set(range(0xC5, 0xC8)) |
                set(range(0xC9, 0xCC)) | set(range(0xCD, 0xD0))
            ):
                if length < 7:
                    return False
                height, width = struct.unpack(">HH", image_bytes[index + 3:index + 7])
                saw_frame = bool(width and height)
            index += length
        return False

    if len(image_bytes) < 20 or image_bytes[:4] != b"RIFF" or image_bytes[8:12] != b"WEBP":
        return False
    riff_size = struct.unpack("<I", image_bytes[4:8])[0]
    if riff_size + 8 != len(image_bytes):
        return False
    index = 12
    saw_frame = False
    while index + 8 <= len(image_bytes):
        chunk_type = image_bytes[index:index + 4]
        length = struct.unpack("<I", image_bytes[index + 4:index + 8])[0]
        end = index + 8 + length + (length & 1)
        if end > len(image_bytes):
            return False
        if chunk_type == b"VP8X":
            if length < 10:
                return False
        elif chunk_type == b"VP8 ":
            payload = image_bytes[index + 8:index + 8 + length]
            saw_frame = length >= 10 and payload[3:6] == b"\x9d\x01\x2a"
        elif chunk_type == b"VP8L":
            payload = image_bytes[index + 8:index + 8 + length]
            saw_frame = length >= 5 and payload[0] == 0x2f
        index = end
    return saw_frame and index == len(image_bytes)


def prepare_images(
    rows: Sequence[Mapping[str, Any]], context: RunContext, directory: Path,
) -> Mapping[Tuple[str, str, str], PreparedImage]:
    """Download at most one normalized, readable image per raw worklist row."""
    directory.mkdir(parents=True, exist_ok=True)
    images = {}
    for position, row in enumerate(rows, 1):
        row_key = worklist_row_key(row)
        packet_id = _packet_id(row)
        image_url = normalize_first_image_url(row.get("image_raw"), context.platform)
        if not image_url:
            images[row_key] = PreparedImage(packet_id, None, "unavailable", None)
            continue
        suffix = Path(urlsplit(image_url).path).suffix.lower() or ".img"
        local_path = directory / ("image-%04d%s" % (position, suffix))
        try:
            request = urllib.request.Request(image_url, headers={"User-Agent": "non-niq-qa-v3"})
            with urllib.request.urlopen(request, timeout=30) as response:
                status = getattr(response, "status", 200)
                if not 200 <= status < 300:
                    raise ValueError("HTTP status %s" % status)
                image_bytes = response.read()
            if not _is_readable_image(image_bytes):
                raise ValueError("downloaded body is not a readable image")
            local_path.write_bytes(image_bytes)
        except Exception:
            images[row_key] = PreparedImage(packet_id, image_url, "unavailable", None)
        else:
            images[row_key] = PreparedImage(packet_id, image_url, "ready", local_path)
    return images


def build_packet_prompt(
    context: RunContext, packets: Sequence[Mapping[str, Any]],
) -> str:
    """Build an audit-only decision prompt without data-service or write authority."""
    prompt_packets = []
    for packet in packets:
        prompt_packets.append({
            "packet_id": packet["packet_id"],
            "product_id": packet["product_id"],
            "ecommerce_platform": packet.get("ecommerce_platform"),
            "work_item_id": packet["work_item_id"],
            "input_fingerprint": packet["input_fingerprint"],
            "sku_name": packet.get("sku_name"),
            "item_description": packet.get("item_description"),
            "product_attributes_attrs": packet.get("product_attributes_attrs"),
            "prior_mapping": packet.get("prior_mapping"),
            "image_status": packet["image_status"],
            "attachment_index": packet["attachment_index"],
            "candidates": packet["candidates"],
            "candidate_refs": sorted(packet["candidate_refs"]),
            "writable_attributes": sorted(packet["writable_attributes"]),
            "generated_attributes": sorted(packet["generated_attributes"]),
            "dict_pattern": packet["dict_pattern"],
            "allowed_categorical_values": {
                name: sorted(values)
                for name, values in packet["allowed_categorical_values"].items()
            },
        })
    return """You are a decision-only multimodal taxonomy reviewer for the supplied category.
Return JSON only, as {"decisions":[...]}, with exactly one decision per packet and no prose.

Use only each packet's supplied fields and its attached image. Do not access services, invoke
tools, write data, or propose operational actions. Assess category relevance from the packet
signals and attached image, never from a filename or URL alone. When the evidence is insufficient,
defer rather than guessing or filtering.

Read the product image first for category relevance, brand, product line, and variant. Use the
title and structured packet attributes as supporting signals; a title keyword alone is not enough
to filter. For size, prefer an explicit title value, then the image and other supplied signals.
For pack count, the image resolves ambiguity in title multipliers; distinguish same-product
multipacks from a different-product freebie/GWP. Preserve exact observed wording and units, never
invent a size or variant, and never use a generic category word as a product line when a grounded
line is unavailable.
Every decision must echo packet_id, product_id, work_item_id, and input_fingerprint exactly;
include confidence and an evidence array. An image-evidence item must cite only that packet's
attachment_index. Never cite another packet's attachment. A ready image must be inspected before
any non-defer decision. With image_status="unavailable", filter is forbidden and map_existing or
create_dict must be unconfident.

The exact object contract is:
- every decision contains exactly these keys: packet_id, product_id, work_item_id,
  input_fingerprint, kind, confidence, evidence, reason, candidate_ref, attributes;
- the branch field holds a value and the other two branch fields are null: filter and defer
  use reason; map_existing uses candidate_ref; create_dict uses attributes;
- evidence items always carry source, claim, and attachment_index: image evidence uses that
  packet's integer attachment_index, non-image evidence uses attachment_index null.

The only decision shapes are:
- filter: kind="filter", confidence="confident", a specific reason, and matching image evidence;
  use only when the product is confidently out of the supplied category.
- map_existing: kind="map_existing" and a candidate_ref from that packet's candidate_refs only.
- create_dict: kind="create_dict" and attributes containing only writable_attributes, never
  generated_attributes. Supply every required source in dict_pattern; use an allowed categorical
  value exactly when the packet gives a vocabulary, and never invent a value.
- defer: kind="defer", confidence="unconfident", and a specific reason. It has no candidate_ref
  or attributes.

Category: %s

PACKETS:
""" % context.category + json.dumps({
            "dataset": context.dataset,
            "platform": context.platform,
            "country": context.country,
            "packets": prompt_packets,
        }, sort_keys=True, separators=(",", ":"), default=str)


def _pending_outbox_events(client, context: RunContext) -> List[Mapping[str, Any]]:
    query = """SELECT event_id, attempt_id, decision_id, event_type, payload, attempts
FROM %s
WHERE status = 'pending'
  AND dataset = @dataset
  AND platform = @platform
  AND country = @country
ORDER BY created_at, event_id""" % _outbox_table(context)
    parameters = [
        bigquery.ScalarQueryParameter("dataset", "STRING", context.dataset),
        bigquery.ScalarQueryParameter("platform", "STRING", context.platform),
        bigquery.ScalarQueryParameter("country", "STRING", context.country),
    ]
    return [
        dict(row.items())
        for row in client.query(
            query, job_config=bigquery.QueryJobConfig(query_parameters=parameters),
        ).result()
    ]


def _mark_outbox_event(
    client, context: RunContext, event_id: str, status: str, now: datetime,
    error: Optional[str] = None,
) -> None:
    if status not in {"pending", "complete"}:
        raise ValueError("unsupported outbox status: %s" % status)
    query = """UPDATE %s
SET status = @status,
    attempts = attempts + 1,
    last_error = @last_error,
    completed_at = @completed_at
WHERE event_id = @event_id
  AND status = 'pending'
  AND dataset = @dataset
  AND platform = @platform
  AND country = @country""" % _outbox_table(context)
    parameters = [
        bigquery.ScalarQueryParameter("status", "STRING", status),
        bigquery.ScalarQueryParameter("last_error", "STRING", error),
        bigquery.ScalarQueryParameter(
            "completed_at", "TIMESTAMP", now if status == "complete" else None,
        ),
        bigquery.ScalarQueryParameter("event_id", "STRING", event_id),
        bigquery.ScalarQueryParameter("dataset", "STRING", context.dataset),
        bigquery.ScalarQueryParameter("platform", "STRING", context.platform),
        bigquery.ScalarQueryParameter("country", "STRING", context.country),
    ]
    client.query(
        query, job_config=bigquery.QueryJobConfig(query_parameters=parameters),
    ).result()


def _outbox_failure(
    client, context: RunContext, event: Mapping[str, Any], now: datetime, error: str,
) -> str:
    _mark_outbox_event(client, context, str(event["event_id"]), "pending", now, error)
    return "%s: %s" % (event["event_id"], error)


def drain_outbox(client, context: RunContext, now: datetime) -> None:
    """Deliver scoped pending events or raise after retaining every delivery failure."""
    meili_groups: Dict[Tuple[str, str], List[Tuple[Mapping[str, Any], Mapping[str, Any]]]] = {}
    sheet_groups: Dict[Tuple[str, str, str], List[Tuple[Mapping[str, Any], Mapping[str, Any]]]] = {}
    failures = []
    for event in _pending_outbox_events(client, context):
        try:
            payload = json.loads(str(event["payload"]))
            if not isinstance(payload, Mapping):
                raise ValueError("payload is not an object")
            if event["event_type"] == "meili_index":
                key = (str(payload["meili_url"]), str(payload["meili_index"]))
                document = payload["document"]
                if not isinstance(document, Mapping):
                    raise ValueError("meili document is not an object")
                meili_groups.setdefault(key, []).append((event, document))
            elif event["event_type"] == "sheet_append":
                key = (
                    str(payload["project"]),
                    str(payload["dict_table"]),
                    str(payload["sheet_url"]),
                )
                entry = payload["entry"]
                if not isinstance(entry, Mapping):
                    raise ValueError("sheet entry is not an object")
                sheet_groups.setdefault(key, []).append((event, entry))
            else:
                raise ValueError("unsupported outbox event type: %s" % event["event_type"])
        except Exception as error:
            failures.append(_outbox_failure(
                client, context, event, now, "%s: %s" % (type(error).__name__, error),
            ))

    for (meili_url, meili_index), deliveries in meili_groups.items():
        try:
            index_documents_strict(
                [dict(document) for _, document in deliveries], meili_url, meili_index,
            )
        except Exception as error:
            message = "%s: %s" % (type(error).__name__, error)
            for event, _ in deliveries:
                failures.append(_outbox_failure(client, context, event, now, message))
        else:
            for event, _ in deliveries:
                _mark_outbox_event(client, context, str(event["event_id"]), "complete", now)

    for (project, dict_table, sheet_url), deliveries in sheet_groups.items():
        entries = [dict(entry) for _, entry in deliveries]
        try:
            outcomes = append_sheet_new_entries_strict(
                project, dict_table, sheet_url, entries, client=client,
            )
        except Exception as error:
            outcomes = {}
            message = "%s: %s" % (type(error).__name__, error)
            for event, _ in deliveries:
                failures.append(_outbox_failure(client, context, event, now, message))
            continue
        for event, entry in deliveries:
            key = (
                str(entry.get("brand", "")).strip(),
                str(entry.get("identity_col", "")).strip(),
                str(entry.get("identity_value", "")).strip(),
            )
            outcome = outcomes.get(key)
            if outcome and outcome.status in {"appended", "already_present"}:
                _mark_outbox_event(client, context, str(event["event_id"]), "complete", now)
            else:
                error = getattr(outcome, "error", None) or "missing sheet append outcome"
                failures.append(_outbox_failure(client, context, event, now, str(error)))

    if failures:
        raise RuntimeError("outbox delivery failed: " + "; ".join(failures))


def _chunked(values: Sequence[Mapping[str, Any]], size: int) -> Sequence[Sequence[Mapping[str, Any]]]:
    return [values[index:index + size] for index in range(0, len(values), size)]


def _queue_table_name(context: RunContext) -> str:
    parts = [context.dataset, context.platform.lower()]
    if context.country != "ID":
        parts.append(context.country)
    return ":".join(parts)


def emit_result(table: str, signal: str, message: str, **fields: str) -> None:
    """Print the queue signal followed by its machine-readable result."""
    print("QUEUE_SIGNAL: %s" % signal)
    print(json.dumps({
        "timestamp": _timestamp(datetime.now(timezone.utc)),
        "table": table,
        "signal": signal,
        "message": message,
        **fields,
    }, sort_keys=True, separators=(",", ":")))


def run(args: Any, client=None) -> int:
    """Run one queue-compatible v3 session."""
    table = "%s:%s" % (args.dataset, str(args.platform).lower())
    try:
        client = client or bigquery.Client(project=PROJECT)
        context = resolve_run_context(args, client)
        table = _queue_table_name(context)
        adapter = os.environ.get("AGENT_HARNESS", "codex")
        if not args.dry_run:
            drain_outbox(client, context, datetime.now(timezone.utc))

        worklist_sql = build_worklist_sql(
            context,
            int(args.max_rows),
            str(args.kategori or ""),
            os.environ.get("MONTHLY_REVERIFY") == "1",
            context.merchant_ids,
        )
        rows = materialize_worklist(
            client,
            worklist_sql,
            build_worklist_parameters(
                context, int(args.max_rows), str(args.kategori or ""), context.merchant_ids,
            ),
        )
        if not rows:
            emit_result(table, "NOTHING_TO_DO", "No eligible non-NIQ QA work")
            return 0

        blocked = False
        auto_confirmed = set()
        auto_confirmed_rows = 0
        adapter_verified = False
        for row_chunk in _chunked(rows, 10):
            retrieval_lines = [
                {
                    "id": str(row["product_id"]),
                    "product_id": str(row["product_id"]),
                    "ecommerce_platform": str(row.get("ecommerce_platform", "")),
                    "text": str(row.get("sku_name", "")),
                }
                for row in row_chunk
            ]
            candidate_hits = retrieve_candidates(
                retrieval_lines, MEILI_URL, context.meili_index,
            )
            confirmed_in_chunk = set()
            if not args.dry_run:
                confirmed_in_chunk = auto_confirm_worklist(
                    client, context, row_chunk, candidate_hits,
                )
                auto_confirmed.update(confirmed_in_chunk)
                auto_confirmed_rows += sum(
                    worklist_row_key(row) in confirmed_in_chunk for row in row_chunk
                )
            row_chunk = [
                row for row in row_chunk
                if worklist_row_key(row) not in auto_confirmed
            ]
            if not row_chunk:
                continue
            pending_keys = {worklist_row_key(row) for row in row_chunk}
            pending_ids = {key[0] for key in pending_keys}
            candidate_hits = [
                hit for hit in candidate_hits
                if worklist_row_key(hit) in pending_keys
            ]
            candidates = resolve_candidate_refs(client, context, candidate_hits)
            prior_mappings = resolve_prior_mappings(
                client, context, [line["id"] for line in retrieval_lines if line["id"] in pending_ids],
            )
            if not adapter_verified:
                if adapter not in {"codex", "omp"}:
                    raise ValueError("AGENT_HARNESS must be codex or omp for v3")
                verify_adapter_vision(adapter)
                adapter_verified = True
            with tempfile.TemporaryDirectory(prefix="non-niq-v3-images-") as directory:
                images = prepare_images(row_chunk, context, Path(directory))
                packets = build_product_packets(
                    context, row_chunk, candidates, images, prior_mappings,
                )
                attachments = [
                    packet["attachment"] for packet in packets if packet["attachment"] is not None
                ]
                raw_decisions = invoke_adapter(
                    adapter, build_packet_prompt(context, packets), attachments,
                )
                decisions = validate_decision_batch(raw_decisions, packets)
                blocked = blocked or any(
                    decision["kind"] == "defer" for decision in decisions
                )
                if not args.dry_run:
                    apply_chunk(client, context, packets, decisions, datetime.now(timezone.utc))
                    drain_outbox(client, context, datetime.now(timezone.utc))

        sync_summary = {"duplicates_removed": 0, "master_rows_updated": 0, "tier_recalc": {"ran": False, "filtered_count": 0}}
        if not args.dry_run:
            try:
                sync_summary = sync_labelling(
                    client, context.project, context.qa_table, context.qa_pk_col,
                    _qa_platform_column(context), context.source_table, context.filter_table,
                    rows, context.month, context.platform, context.country, context.category,
                    qa_identity_col=context.qa_identity_col,
                )
            except Exception as sync_error:
                # Best-effort, same non-fatal contract as the bash side's Sheet write-back --
                # the QA writes already succeeded; this is downstream propagation, not part of
                # the QA session's own pass/fail.
                sync_summary = {"error": "%s: %s" % (type(sync_error).__name__, sync_error)}

        signal = "BLOCKED" if blocked else "DONE"
        message = "QA v3 session blocked on deferred products" if blocked else "QA v3 session finished"
        emit_result(
            table, signal, message, rows=str(len(rows)),
            rows_auto_confirmed=str(auto_confirmed_rows),
            sync_labelling=json.dumps(sync_summary, sort_keys=True, separators=(",", ":")),
        )
        return 0
    except Exception as error:
        emit_result(table, "FAILED", "%s: %s" % (type(error).__name__, error))
        return 1


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dataset")
    parser.add_argument("platform")
    parser.add_argument("country", nargs="?", default="ID")
    parser.add_argument("max_turns", nargs="?", type=int, default=500)
    parser.add_argument("max_rows", nargs="?", type=int, default=300)
    parser.add_argument("kategori", nargs="?", default="")
    parser.add_argument("--dry-run", action="store_true")
    sys.exit(run(parser.parse_args()))


if __name__ == "__main__":
    main()
