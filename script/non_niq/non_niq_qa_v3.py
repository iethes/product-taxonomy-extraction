#!/usr/bin/env python3
"""Deterministic Python driver for non-NIQ QA v3."""

from dataclasses import dataclass
from hashlib import sha256
import json
import os
from pathlib import Path
import re
import secrets
import struct
import subprocess
import tempfile
from typing import Any, Callable, Dict, List, Mapping, Optional, Sequence, Tuple
from urllib.parse import urlsplit
import zlib


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
        suffix = Path(urlsplit(image.image_url or "").path).suffix.lower() or ".img"
        attachments.append(Attachment(
            product_id=image.product_id,
            attachment_index=len(attachments) + 1,
            attachment_filename="attachment-%04d%s" % (len(attachments) + 1, suffix),
            sha256=sha256(image.local_path.read_bytes()).hexdigest(),
            local_path=image.local_path,
        ))
    return tuple(attachments)


def plan_attempt(row: Mapping[str, Any], qa_state: Mapping[str, Any]) -> AttemptPlan:
    """Return a stable initial, retry, or listing-change attempt."""
    attempt_kind = str(qa_state.get("kind", "initial"))
    if attempt_kind not in {"initial", "retry", "listing_change"}:
        raise ValueError("unsupported attempt kind: %s" % attempt_kind)
    work_item_id = _stable_digest({
        "product_id": str(row.get("product_id", "")),
        "platform": str(row.get("platform", row.get("ecommerce_platform", ""))),
        "country": str(row.get("country", "")),
        "dataset": str(row.get("dataset", "")),
    })
    input_fingerprint = _stable_digest({
        "product_id": str(row.get("product_id", "")),
        "sku_name": str(row.get("sku_name", "")),
        "kategori": str(row.get("kategori", "")),
        "item_description": str(row.get("item_description", "")),
        "product_attributes_attrs": str(row.get("product_attributes_attrs", "")),
    })
    return AttemptPlan(
        work_item_id=work_item_id,
        input_fingerprint=input_fingerprint,
        attempt_id=_stable_digest({
            "work_item_id": work_item_id,
            "input_fingerprint": input_fingerprint,
            "attempt_kind": attempt_kind,
        }),
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
            _require(set(item) == {"source", "claim"}, "text evidence has unexpected fields")
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
        product_id = packet.get("product_id")
        _require(isinstance(product_id, str) and product_id, "packet product_id is required")
        _require(product_id not in packets_by_id, "duplicate packet product_id")
        packets_by_id[product_id] = packet

    decisions_by_id = {}
    common_fields = {
        "product_id", "work_item_id", "input_fingerprint", "kind", "confidence", "evidence",
    }
    allowed_fields = {
        "filter": common_fields | {"reason"},
        "map_existing": common_fields | {"candidate_ref"},
        "create_dict": common_fields | {"attributes"},
        "defer": common_fields | {"reason"},
    }
    for decision in decisions:
        _require(isinstance(decision, Mapping), "decision must be an object")
        product_id = decision.get("product_id")
        _require(product_id in packets_by_id, "decision product_id is not in this packet")
        _require(product_id not in decisions_by_id, "duplicate decision product_id")
        packet = packets_by_id[product_id]
        for field in ("work_item_id", "input_fingerprint"):
            _require(
                decision.get(field) == packet.get(field),
                "%s does not match its packet" % field,
            )
        kind = decision.get("kind")
        _require(kind in allowed_fields, "unsupported decision kind")
        _require(set(decision) == allowed_fields[kind], "decision has missing or unexpected fields")
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
            _require(all(isinstance(value, str) for value in attributes.values()), "attributes must be strings")
            _require(not image_ready or has_own_image, "readable image requires its own evidence")
        else:
            _require(confidence == "unconfident", "defer must be unconfident")
            _require(isinstance(decision.get("reason"), str) and decision["reason"], "defer reason is required")

        if not image_ready and kind in {"map_existing", "create_dict"}:
            _require(confidence == "unconfident", "unavailable image cannot produce a confident decision")
        decisions_by_id[product_id] = decision

    return [decisions_by_id[packet["product_id"]] for packet in packets]


SCHEMA_PATH = Path(__file__).with_name("non_niq_qa_v3_decision_schema.json")
_PIXEL_DIGITS = {
    "0": ("111", "101", "101", "101", "111"),
    "1": ("010", "110", "010", "010", "111"),
    "2": ("111", "001", "111", "100", "111"),
    "3": ("111", "001", "111", "001", "111"),
    "4": ("101", "101", "111", "001", "001"),
    "5": ("111", "100", "111", "001", "111"),
    "6": ("111", "100", "111", "101", "111"),
    "7": ("111", "001", "010", "010", "010"),
    "8": ("111", "101", "111", "101", "111"),
    "9": ("111", "101", "111", "001", "111"),
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
    scale = 12
    width = 24 + len(label) * 48
    height = 84
    pixels = bytearray(b"\xff\xff\xff" * width * height)
    for char_index, digit in enumerate(label):
        glyph = _PIXEL_DIGITS[digit]
        for row_index, row in enumerate(glyph):
            for column_index, pixel in enumerate(row):
                if pixel != "1":
                    continue
                x0 = 12 + char_index * 48 + column_index * scale
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


def verify_adapter_vision(
    adapter: str,
    run_command: Callable[..., subprocess.CompletedProcess] = _run_command,
) -> None:
    """Raise AdapterVisionError unless both random image labels are read exactly."""
    if adapter not in {"codex", "omp"}:
        raise AdapterVisionError("unsupported adapter: %s" % adapter)
    with tempfile.TemporaryDirectory(prefix="non-niq-v3-sentinel-") as directory:
        root = Path(directory)
        labels = ["%08d" % secrets.randbelow(10 ** 8) for _ in range(2)]
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
            "Read the visible label in each attached image in attachment order. "
            "Return JSON only: {\"labels\":[\"first\",\"second\"]}."
        )
        output_path = root / "result.json"
        if adapter == "codex":
            command = [
                "codex", "exec", "--ephemeral", "--sandbox", "read-only",
                "-c", "sandbox_workspace_write.network_access=false",
                "--output-last-message", str(output_path),
                "--image", *[str(item.local_path) for item in attachments], prompt,
            ]
        else:
            command = build_omp_command(prompt, attachments)
        result = run_command(command, env=_adapter_env())
        if result.returncode:
            raise AdapterVisionError(
                "%s sentinel failed: %s" % (adapter, result.stderr.strip())
            )
        text = output_path.read_text() if output_path.exists() else result.stdout
        parsed = _parse_adapter_json(text)
        if parsed.get("labels") != labels:
            raise AdapterVisionError("adapter did not read both image labels exactly")


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
