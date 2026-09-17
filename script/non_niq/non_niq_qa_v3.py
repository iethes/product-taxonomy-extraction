#!/usr/bin/env python3
"""Deterministic Python driver for non-NIQ QA v3."""

from dataclasses import dataclass
from hashlib import sha256
import json
from pathlib import Path
import re
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple
from urllib.parse import urlsplit


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


def _has_own_image_evidence(evidence: Sequence[Mapping[str, Any]], attachment_index: Any) -> bool:
    has_own_image = False
    for item in evidence:
        _require(isinstance(item, Mapping), "evidence item must be an object")
        source = item.get("source")
        _require(isinstance(source, str) and source, "evidence source is required")
        claim = item.get("claim")
        _require(isinstance(claim, str) and claim, "evidence claim is required")
        if source == "image":
            _require(
                set(item) == {"source", "claim", "attachment_index"},
                "image evidence has unexpected fields",
            )
            _require(
                item.get("attachment_index") == attachment_index,
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
        has_own_image = _has_own_image_evidence(evidence, packet.get("attachment_index"))
        image_ready = packet.get("image_status") == "ready"

        if kind == "filter":
            _require(confidence == "confident", "filter must be confident")
            _require(isinstance(decision.get("reason"), str) and decision["reason"], "filter reason is required")
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
