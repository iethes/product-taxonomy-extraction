#!/usr/bin/env python3
"""Deterministic Python driver for non-NIQ QA v3."""

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
import tempfile
from typing import Any, Callable, Dict, List, Mapping, Optional, Sequence, Tuple
from urllib.parse import urlsplit
import zlib

from google.cloud import bigquery

from non_niq_helper import (
    MEILI_URL,
    _table_columns,
    fetch_config_csv,
    fetch_forced_merchant_ids,
    parse_categories,
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
    work_item_id = _stable_digest({
        "product_id": str(row.get("product_id", "")),
        "platform": _canonical_platform(row.get("platform", row.get("ecommerce_platform"))),
        "country": _normalize_attempt_text(row.get("country")),
        "dataset": _normalize_attempt_text(row.get("dataset")),
        "current_title": current_title,
    })
    input_fingerprint = _stable_digest({
        "work_item_id": work_item_id,
        "current_title": current_title,
        "current_category": current_category,
        "item_description": str(row.get("item_description", "")),
        "product_attributes_attrs": str(row.get("product_attributes_attrs", "")),
        "image_url": str(row.get("image", "")),
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
) -> None:
    """Raise AdapterVisionError unless both random image labels are read exactly."""
    if adapter not in {"codex", "omp"}:
        raise AdapterVisionError("unsupported adapter: %s" % adapter)
    with tempfile.TemporaryDirectory(prefix="non-niq-v3-sentinel-") as directory:
        root = Path(directory)
        first_label = "%08d" % secrets.randbelow(10 ** 8)
        second_label = first_label
        for _ in range(8):
            second_label = "%08d" % secrets.randbelow(10 ** 8)
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
            "Read the visible label in each attached image in attachment order. "
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


def _canonical_platform_sql(column: str) -> str:
    return "CASE WHEN %s = 'Tokopedia | Shop' THEN 'Tokopedia' ELSE %s END" % (
        column, column,
    )


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
    source_platform = _canonical_platform_sql("s.ecommerce_platform")
    qa_platform = _canonical_platform_sql("ecommerce_platform")
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
    merchant_clause = (
        "(r.cumulative_gmv_share <= 0.9 OR r.merchant_id IN UNNEST(@merchant_ids))"
        if merchant_ids else "r.cumulative_gmv_share <= 0.9"
    )
    reverify_cte = ""
    reverify_join = ""
    scoped_kategori = ""
    reverify_expr = "FALSE"
    reverify_prior = "NULL AS prior_sku_name, NULL AS prior_kategori"
    if monthly_reverify:
        scoped_kategori = ", s.kategori AS current_kategori"
        reverify_cte = """prior_snapshot AS (
  SELECT product_id, sku_name AS prior_sku_name, kategori AS prior_kategori
  FROM %s
  WHERE ecommerce_platform %s
    AND FORMAT_DATE('%%Y-%%m', month) < @month
  QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY month DESC) = 1
),
""" % (source, platform_match)
        reverify_join = "LEFT JOIN prior_snapshot ps ON ps.product_id = sc.product_id"
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
    %s
),
ranked AS (
  SELECT sc.*,
    SUM(sc.gmv_monthly) OVER (
      PARTITION BY sc.country, sc.category, sc.ecommerce_platform, sc.month
      ORDER BY sc.gmv_monthly DESC, sc.product_id ASC
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) / NULLIF(SUM(sc.gmv_monthly) OVER (
      PARTITION BY sc.country, sc.category, sc.ecommerce_platform, sc.month
    ), 0) AS cumulative_gmv_share
  FROM scoped sc
  %s
  %s
),
stakeholder_scope AS (
  SELECT * FROM ranked r
  WHERE %s
),
qa_title_state AS (
  SELECT DISTINCT %s AS product_id,
    %s AS ecommerce_platform,
    REGEXP_REPLACE(TRIM(sku_name), r'\\s+', ' ') AS normalized_sku_name
  FROM %s
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
        source, enrichment_join, platform_match, kategori_clause, filter_join, filter_where,
        merchant_clause, _identifier(context.qa_pk_col), qa_platform, qa,
        _identifier(context.qa_pk_col), qa_platform, qa, reverify_cte,
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
        product_id = str(result.get("id", ""))
        product_hits[product_id] = []
        for hit in result.get("candidates", []):
            brand = str(hit.get("brand", "")).strip()
            identity = str(hit.get(context.dict_identity_col, hit.get("sku_type_complete", "")).strip())
            if brand and identity:
                product_hits[product_id].append((brand, identity))
                requested.append((brand, identity))
    if not requested:
        return {product_id: {} for product_id in product_hits}
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
    for product_id, candidate_pairs in product_hits.items():
        output[product_id] = {}
        for pair in candidate_pairs:
            row = resolved.get(pair)
            if row is not None:
                reference = "dict:" + _stable_digest({
                    "brand": pair[0], "identity": pair[1],
                })[:16]
                output[product_id][reference] = row
    return output


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
    candidates: Mapping[str, Mapping[str, Mapping[str, Any]]],
    images: Mapping[str, PreparedImage],
    prior_mappings: Optional[Mapping[str, Mapping[str, Any]]] = None,
) -> List[Mapping[str, Any]]:

    """Combine ordered planning outputs into packet dictionaries bound to local attachments."""
    ordered_rows = sorted(
        rows,
        key=lambda row: (int(row.get("priority", 0)), -float(row.get("gmv_monthly", 0))),
    )
    ordered_images = [
        images.get(
            str(row["product_id"]),
            PreparedImage(str(row["product_id"]), None, "unavailable", None),
        )
        for row in ordered_rows
    ]
    attachment_by_product = {
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
        attempt_kind = (
            "listing_change" if row.get("listing_changed")
            else "retry" if int(row.get("priority", 0)) == 1
            else "initial"
        )
        attempt_row = dict(row)
        attempt_row.update({
            "dataset": context.dataset,
            "platform": context.platform,
            "country": context.country,
        })
        attempt = plan_attempt(attempt_row, {"kind": attempt_kind})
        attachment = attachment_by_product.get(product_id)
        candidate_rows = candidates.get(product_id, {})
        packets.append({
            **dict(row),
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
class ChunkCommit:
    attempts: Tuple[AttemptPlan, ...]
    created_dict_identities: Tuple[Tuple[str, str, str], ...]
    outbox_events: Tuple[OutboxEvent, ...]
    qa_writes: Tuple[Tuple[str, str, str, str, str], ...]
    filtered_products: Tuple[Tuple[str, str], ...]


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
) -> Tuple[List[Mapping[str, Any]], ChunkCommit]:
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
    outbox_events: List[OutboxEvent] = []
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
            operations.append({**base, "kind": kind})
            filtered_products.append((str(packet["product_id"]), context.platform))
            continue

        if kind == "map_existing":
            candidate = packet.get("candidates", {}).get(decision["candidate_ref"])
            _require(isinstance(candidate, Mapping), "candidate row is unavailable")
            brand = str(candidate.get("brand", "")).strip()
            identity = str(candidate.get(context.dict_identity_col, "")).strip()
            _require(brand and identity, "candidate row has no natural identity")
            dictionary_values = None
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
            created_identities.append(natural_identity)

        qa_identity = identity
        attempts.append(attempt)
        qa_writes.append((
            str(packet["product_id"]), context.platform, brand, qa_identity, attempt.attempt_id,
        ))
        operation = {
            **base,
            "kind": kind,
            "brand": brand,
            "identity": identity,
            "qa_identity": qa_identity,
            "dictionary_values": dictionary_values,
        }
        operations.append(operation)
        if kind != "create_dict":
            continue

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
        qa_writes=tuple(qa_writes),
        filtered_products=tuple(filtered_products),
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
        values[platform_column] = context.platform
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
        platform_column: context.platform,
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


def build_chunk_script(
    context: RunContext,
    packets: Sequence[Mapping[str, Any]],
    decisions: Sequence[Mapping[str, Any]],
    now: datetime,
) -> Tuple[str, Sequence[Any]]:
    """Return one parameterized transaction script and its query parameters."""
    operations, commit = _build_operations(context, packets, decisions, now)
    if not operations:
        return "", ()

    builder = _ParameterBuilder()
    statements = ["BEGIN TRANSACTION;"]
    create_operations = [item for item in operations if item["kind"] == "create_dict"]
    dict_table = _table_reference(context.project, context.dict_table)
    if create_operations:
        requested_rows = []
        for operation in create_operations:
            requested_rows.append("SELECT %s AS brand, %s AS identity_value" % (
                builder.add(operation["brand"]),
                builder.add(operation["identity"]),
            ))
        statements.extend([
            "CREATE TEMP TABLE _v3_requested_dict AS\n" + "\nUNION ALL\n".join(requested_rows) + ";",
            """CREATE TEMP TABLE _v3_existing_dict AS
SELECT d.brand, d.`%s` AS identity_value
FROM %s d
JOIN _v3_requested_dict r
  ON d.brand = r.brand AND d.`%s` = r.identity_value;""" % (
                _identifier(context.dict_identity_col), dict_table,
                _identifier(context.dict_identity_col),
            ),
            """CREATE TEMP TABLE _v3_new_dict AS
SELECT r.brand, r.identity_value
FROM _v3_requested_dict r
LEFT JOIN _v3_existing_dict e
  ON e.brand = r.brand AND e.identity_value = r.identity_value
WHERE e.brand IS NULL;""",
        ])

    for operation in (item for item in operations if item["kind"] == "filter"):
        values = _insert_values(builder, _filter_values(context, operation, now))
        product_parameter = values["product_id"][1]
        predicate = "NOT EXISTS (SELECT 1 FROM %s f WHERE f.`product_id` = %s" % (
            _table_reference(context.project, context.filter_table), product_parameter,
        )
        platform_column = _filter_platform_column(context)
        if platform_column:
            predicate += " AND %s = %s" % (
                _canonical_platform_sql("f.`%s`" % _identifier(platform_column)),
                values[platform_column][1],
            )
        predicate += ")"
        statements.append(_conditional_insert(
            _table_reference(context.project, context.filter_table), values, predicate,
        ))

    for operation in create_operations:
        dict_values = dict(operation["dictionary_values"])
        if context.dict_has_meta:
            dict_values["_meta"] = _metadata(
                now, operation["run_id"], operation["attempt"], operation["decision_id"],
                operation["confidence"], operation["human_review"],
            )
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

    qa_table = _table_reference(context.project, context.qa_table)
    qa_platform_column = _qa_platform_column(context)
    for operation in (item for item in operations if item["kind"] in {"map_existing", "create_dict"}):
        values = _insert_values(builder, _qa_values(context, operation, now))
        attempt_parameter = builder.add(operation["attempt"].attempt_id)
        predicate = """NOT EXISTS (
  SELECT 1 FROM %s q
  WHERE q.`%s` = %s
    AND %s = %s
    AND JSON_VALUE(SAFE.PARSE_JSON(_meta), '$.attempt_id') = %s
)""" % (
            qa_table, _identifier(context.qa_pk_col), values[context.qa_pk_col][1],
            _canonical_platform_sql("q.`%s`" % _identifier(qa_platform_column)),
            values[qa_platform_column][1],
            attempt_parameter,
        )
        statements.append(_conditional_insert(qa_table, values, predicate))

    for operation in create_operations:
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
                """EXISTS (
  SELECT 1 FROM _v3_new_dict n
  WHERE n.brand = %s AND n.identity_value = %s
) AND NOT EXISTS (
  SELECT 1 FROM %s o WHERE o.event_id = %s
)""" % (
                    builder.add(operation["brand"]),
                    builder.add(operation["identity"]),
                    _outbox_table(context),
                    values["event_id"][1],
                ),
            ))
    statements.append("COMMIT TRANSACTION;")
    return "\n\n".join(statements), tuple(builder.parameters)


def _preflight_create_identities(
    client, context: RunContext, operations: Sequence[Mapping[str, Any]],
) -> None:
    creates = [operation for operation in operations if operation["kind"] == "create_dict"]
    if not creates:
        return
    builder = _ParameterBuilder()
    requested = "\nUNION ALL\n".join(
        "SELECT %s AS brand, %s AS identity_value" % (
            builder.add(operation["brand"]),
            builder.add(operation["identity"]),
        )
        for operation in creates
    )
    query = """WITH requested AS (
%s
)
SELECT d.brand, d.`%s` AS identity_value
FROM %s d
JOIN requested r
  ON d.brand = r.brand AND d.`%s` = r.identity_value
""" % (
        requested,
        _identifier(context.dict_identity_col),
        _table_reference(context.project, context.dict_table),
        _identifier(context.dict_identity_col),
    )
    conflicts = list(client.query(
        query,
        job_config=bigquery.QueryJobConfig(query_parameters=builder.parameters),
    ).result())
    if conflicts:
        raise DecisionValidationError(
            "create_dict natural identity already exists in %s" % context.dict_table,
        )


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
    operations, commit = _build_operations(context, packets, decisions, now)
    if not operations:
        return commit
    _preflight_create_identities(client, context, operations)
    script, parameters = build_chunk_script(context, packets, decisions, now)
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


def verify_chunk_commit(client, context: RunContext, commit: ChunkCommit) -> None:
    """Read back exact committed QA, filter, dictionary, and outbox identities."""
    qa_table = _table_reference(context.project, context.qa_table)
    qa_platform_column = _qa_platform_column(context)
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
                _canonical_platform_sql("q.`%s`" % _identifier(qa_platform_column)),
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
    filter_platform_column = _filter_platform_column(context)
    for product_id, platform in commit.filtered_products:
        predicate = "f.`product_id` = @product_id"
        parameters = [bigquery.ScalarQueryParameter("product_id", "STRING", product_id)]
        if filter_platform_column:
            predicate += " AND %s = @platform" % _canonical_platform_sql(
                "f.`%s`" % _identifier(filter_platform_column),
            )
            parameters.append(bigquery.ScalarQueryParameter("platform", "STRING", platform))
        _assert_readback(
            client,
            "SELECT 1 FROM %s f WHERE %s LIMIT 1" % (filter_table, predicate),
            parameters,
            "filter row for product_id=%s" % product_id,
        )

    dict_table = _table_reference(context.project, context.dict_table)
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

    outbox_table = _outbox_table(context)
    for event in commit.outbox_events:
        _assert_readback(
            client,
            "SELECT 1 FROM %s WHERE event_id = @event_id AND status = 'pending' LIMIT 1" % outbox_table,
            [bigquery.ScalarQueryParameter("event_id", "STRING", event.event_id)],
            "outbox event %s" % event.event_id,
        )
