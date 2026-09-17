import json
from types import SimpleNamespace

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "script" / "non_niq"))
from non_niq_qa_v3 import (
    AdapterVisionError,
    Attachment,
    DecisionValidationError,
    PreparedImage,
    build_attachment_manifest,
    build_codex_command,
    build_omp_command,
    first_complete_https_url,
    normalize_first_image_url,
    plan_attempt,
    validate_decision_batch,
    verify_adapter_vision,
)


def _packet(product_id="p-1", attachment_index=1, image_status="ready"):
    return {
        "product_id": product_id,
        "work_item_id": "work-" + product_id,
        "input_fingerprint": "fingerprint-" + product_id,
        "attachment_index": attachment_index,
        "image_status": image_status,
        "candidate_refs": {"dict:1"},
        "writable_attributes": {"brand", "sku_type"},
        "generated_attributes": {"generated_label"},
    }


def _decision(packet, kind, **fields):
    decision = {
        "product_id": packet["product_id"],
        "work_item_id": packet["work_item_id"],
        "input_fingerprint": packet["input_fingerprint"],
        "kind": kind,
        "confidence": "confident",
        "evidence": [{
            "source": "image",
            "claim": "package text matches",
            "attachment_index": packet["attachment_index"],
        }],
    }
    decision.update(fields)
    return decision


def test_shopee_quote_cleanup_uses_only_first_full_url():
    raw = 'https://down-id.img.susercontent.com/file/"id-first" \'id-second\''
    assert normalize_first_image_url(raw, "Shopee") == (
        "https://down-id.img.susercontent.com/file/id-first"
    )


def test_non_shopee_url_is_not_rewritten_as_shopee():
    url = "https://ec-mall-tokopedia-com.example/image.png"
    assert normalize_first_image_url(url, "Tokopedia") == url


def test_incomplete_or_non_https_image_is_rejected():
    assert first_complete_https_url("file/image.jpg https://") is None
    assert normalize_first_image_url("http://example.com/image.jpg", "Lazada") is None


def test_attachment_manifest_uses_product_order_and_neutral_names(tmp_path):
    (tmp_path / "two.png").write_bytes(b"two")
    (tmp_path / "one.jpg").write_bytes(b"one")
    images = [
        PreparedImage("p-2", "https://example.com/two.png", "ready", tmp_path / "two.png"),
        PreparedImage("p-1", "https://example.com/one.jpg", "ready", tmp_path / "one.jpg"),
    ]
    manifest = build_attachment_manifest(images)
    assert [(item.product_id, item.attachment_index, item.attachment_filename) for item in manifest] == [
        ("p-2", 1, "attachment-0001.png"),
        ("p-1", 2, "attachment-0002.jpg"),
    ]


def test_retry_attempt_differs_from_initial_but_replays_stably():
    row = {"product_id": "p-1", "sku_name": "Acme Wash", "platform": "Shopee"}
    initial = plan_attempt(row, {"kind": "initial"})
    retry = plan_attempt(row, {"kind": "retry"})
    assert initial.attempt_id != retry.attempt_id
    assert retry == plan_attempt(row, {"kind": "retry"})


def test_listing_change_attempt_changes_when_listing_input_changes():
    original = plan_attempt(
        {"product_id": "p-1", "sku_name": "Acme Wash", "platform": "Shopee"},
        {"kind": "listing_change"},
    )
    changed = plan_attempt(
        {"product_id": "p-1", "sku_name": "Acme Wash New", "platform": "Shopee"},
        {"kind": "listing_change"},
    )
    assert original.input_fingerprint != changed.input_fingerprint
    assert original.attempt_id != changed.attempt_id


def test_rejects_image_evidence_from_another_products_attachment():
    first = _packet("p-1", 1)
    second = _packet("p-2", 2)
    wrong = _decision(first, "map_existing", candidate_ref="dict:1")
    wrong["evidence"][0]["attachment_index"] = 2
    with pytest.raises(DecisionValidationError):
        validate_decision_batch({"decisions": [wrong, _decision(second, "map_existing", candidate_ref="dict:1")]}, [first, second])


def test_rejects_foreign_image_evidence_after_own_attachment_evidence():
    first = _packet("p-1", 1)
    second = _packet("p-2", 2)
    decision = _decision(first, "map_existing", candidate_ref="dict:1")
    decision["evidence"].append({
        "source": "image",
        "claim": "different product",
        "attachment_index": 2,
    })
    with pytest.raises(DecisionValidationError):
        validate_decision_batch({"decisions": [decision, _decision(second, "map_existing", candidate_ref="dict:1")]}, [first, second])


def test_confident_filter_requires_own_image_evidence():
    packet = _packet()
    decision = _decision(packet, "filter", reason="outside category")
    decision["evidence"] = [{"source": "title", "claim": "wrong category"}]
    with pytest.raises(DecisionValidationError):
        validate_decision_batch({"decisions": [decision]}, [packet])


def test_filter_rejects_image_evidence_without_a_readable_attachment():
    packet = _packet(attachment_index=None, image_status="unavailable")
    decision = _decision(packet, "filter", reason="outside category")
    with pytest.raises(DecisionValidationError):
        validate_decision_batch({"decisions": [decision]}, [packet])


def test_unavailable_image_cannot_produce_confident_mapping():
    packet = _packet(image_status="unavailable")
    decision = _decision(packet, "map_existing", candidate_ref="dict:1")
    with pytest.raises(DecisionValidationError):
        validate_decision_batch({"decisions": [decision]}, [packet])


def test_rejects_unknown_candidate_and_generated_attribute():
    packet = _packet()
    unknown = _decision(packet, "map_existing", candidate_ref="dict:missing")
    with pytest.raises(DecisionValidationError):
        validate_decision_batch({"decisions": [unknown]}, [packet])

    generated = _decision(packet, "create_dict", attributes={"generated_label": "forbidden"})
    with pytest.raises(DecisionValidationError):
        validate_decision_batch({"decisions": [generated]}, [packet])


def test_defer_is_unconfident_and_never_requires_an_attachment():
    packet = _packet(image_status="unavailable")
    deferred = _decision(
        packet,
        "defer",
        confidence="unconfident",
        evidence=[],
        reason="image unavailable",
    )
    assert validate_decision_batch({"decisions": [deferred]}, [packet]) == [deferred]

# --- native adapter boundary ---

def _attachment(tmp_path, product_id, attachment_index):
    local_path = tmp_path / ("%s.png" % product_id)
    local_path.write_bytes(product_id.encode("utf-8"))
    return Attachment(
        product_id=product_id,
        attachment_index=attachment_index,
        attachment_filename="attachment-%04d.png" % attachment_index,
        sha256="hash-" + product_id,
        local_path=local_path,
    )


def test_codex_command_passes_images_in_attachment_index_order(tmp_path):
    first = _attachment(tmp_path, "p-1", 1)
    second = _attachment(tmp_path, "p-2", 2)
    command = build_codex_command(
        "decide",
        Path(__file__).parent.parent.parent / "script" / "non_niq" / "non_niq_qa_v3_decision_schema.json",
        tmp_path / "result.json",
        [first, second],
    )
    image_flag = command.index("--image")
    assert command[image_flag + 1:image_flag + 3] == [
        str(first.local_path), str(second.local_path),
    ]
    assert command[command.index("--sandbox") + 1] == "read-only"
    assert "sandbox_workspace_write.network_access=false" in command


def test_omp_command_uses_native_at_file_arguments_in_order(tmp_path):
    first = _attachment(tmp_path, "p-1", 1)
    second = _attachment(tmp_path, "p-2", 2)
    command = build_omp_command("decide", [first, second])
    assert [arg for arg in command if arg.startswith("@")] == [
        "@%s" % first.local_path, "@%s" % second.local_path,
    ]
    assert "--no-tools" in command
    assert "--no-session" in command


def test_wrong_random_label_fails_before_product_decision():
    def wrong_runner(*args, **kwargs):
        return SimpleNamespace(
            returncode=0,
            stdout=json.dumps({"labels": ["wrong", "wrong"]}),
            stderr="",
        )

    with pytest.raises(AdapterVisionError):
        verify_adapter_vision("codex", wrong_runner)
