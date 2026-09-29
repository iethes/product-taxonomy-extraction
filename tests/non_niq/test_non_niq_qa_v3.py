import json
from types import SimpleNamespace
from datetime import datetime, timezone


import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "script" / "non_niq"))
import non_niq_qa_v3 as qa_v3
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
    prepare_images,
    validate_decision_batch,
    verify_adapter_vision,
)


def _packet(product_id="p-1", attachment_index=1, image_status="ready"):
    return {
        "packet_id": "packet-" + product_id,
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
        "packet_id": packet["packet_id"],
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
        "reason": None,
        "candidate_ref": None,
        "attributes": None,
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

def test_prepare_images_rejects_html_and_accepts_decodable_png(monkeypatch, tmp_path):
    class Response:
        status = 200

        def __init__(self, body):
            self.body = body

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return None

        def read(self):
            return self.body

    png_path = tmp_path / "valid.png"
    qa_v3._write_label_png(png_path, "47")
    responses = iter([
        Response(b"<html>not an image</html>"),
        Response(png_path.read_bytes()),
    ])
    monkeypatch.setattr(qa_v3.urllib.request, "urlopen", lambda *args, **kwargs: next(responses))
    rows = [
        {"product_id": "html", "image_raw": "https://example.com/html.png"},
        {"product_id": "png", "image_raw": "https://example.com/valid.png"},
    ]
    images = prepare_images(rows, _context("Tokopedia"), tmp_path / "downloads")
    assert images[("html", "", "")].image_status == "unavailable"
    assert images[("html", "", "")].local_path is None
    assert images[("png", "", "")].image_status == "ready"
    assert images[("png", "", "")].local_path is not None


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
    assert [item.local_path.name for item in manifest] == [
        "attachment-0001.png",
        "attachment-0002.jpg",
    ]


def test_retry_attempt_differs_from_initial_but_replays_stably():
    row = {"product_id": "p-1", "sku_name": "Acme Wash", "platform": "Shopee"}
    initial = plan_attempt(row, {"kind": "initial"})
    retry = plan_attempt(row, {"kind": "retry"})
    assert initial.attempt_id != retry.attempt_id
    assert retry == plan_attempt(row, {"kind": "retry"})
    assert initial.attempt_id == initial.work_item_id + ":initial-1"
    assert retry.attempt_id == retry.work_item_id + ":retry-1"


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


def test_attempt_fingerprint_changes_when_source_image_changes():
    base = {
        "product_id": "p-1",
        "platform": "Tokopedia",
        "country": "ID",
        "dataset": "babybath",
        "sku_name": "Acme Wash",
        "image_raw": "https://example.com/one.jpg",
    }
    changed_image = dict(base, image_raw="https://example.com/two.jpg")

    assert plan_attempt(base, {"kind": "initial"}).input_fingerprint != (
        plan_attempt(changed_image, {"kind": "initial"}).input_fingerprint
    )

def test_attempt_fingerprint_changes_when_downloaded_image_bytes_change():
    base = {
        "product_id": "p-1",
        "platform": "Shopee",
        "country": "ID",
        "dataset": "babybath",
        "sku_name": "Acme Wash",
        "image_raw": "https://example.com/one.jpg",
        "image_url": "https://example.com/one.jpg",
        "image_status": "ready",
        "image_sha256": "a" * 64,
    }
    changed_bytes = dict(base, image_sha256="b" * 64)

    assert plan_attempt(base, {"kind": "initial"}).input_fingerprint != (
        plan_attempt(changed_bytes, {"kind": "initial"}).input_fingerprint
    )


def test_work_item_uses_normalized_title_not_incidental_description():
    base = {
        "product_id": "p-1",
        "platform": "Shopee",
        "sku_name": "Acme   Wash",
        "item_description": "old marketing copy",
    }
    cosmetic_change = dict(base, sku_name="  Acme Wash ", item_description="new marketing copy")
    renamed = dict(base, sku_name="Acme Wash Plus")
    base_attempt = plan_attempt(base, {"kind": "initial"})
    assert base_attempt.work_item_id == plan_attempt(cosmetic_change, {"kind": "initial"}).work_item_id
    assert base_attempt.attempt_id == plan_attempt(cosmetic_change, {"kind": "initial"}).attempt_id
    assert base_attempt.work_item_id != plan_attempt(renamed, {"kind": "initial"}).work_item_id


def test_listing_change_attempt_includes_month_and_prior_snapshot():
    row = {"product_id": "p-1", "platform": "Shopee", "sku_name": "Acme Wash"}
    september = plan_attempt(
        dict(row, month="2026-09", prior_sku_name="Acme Old", prior_kategori="Old"),
        {"kind": "listing_change"},
    )
    october = plan_attempt(
        dict(row, month="2026-10", prior_sku_name="Acme Older", prior_kategori="Older"),
        {"kind": "listing_change"},
    )
    assert september.attempt_id != october.attempt_id


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
    decision["evidence"] = [{"source": "title", "claim": "wrong category", "attachment_index": None}]
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


def test_create_dict_requires_pattern_leaves_and_existing_categorical_values():
    packet = {
        **_packet(),
        "writable_attributes": {"brand", "sub_brand", "function", "packsize"},
        "generated_attributes": {"sku_type", "keywords"},
        "dict_pattern": {
            "sku_type": {
                "sources": ["sub_brand", "function", "packsize"],
                "separator": " ",
            },
            "keywords": {"sources": ["sku_type"], "separator": " "},
        },
        "allowed_categorical_values": {
            "function": {"Wash"},
        },
    }
    missing_leaf = _decision(
        packet,
        "create_dict",
        attributes={"brand": "Acme", "sub_brand": "Acme", "function": "Wash"},
    )
    with pytest.raises(DecisionValidationError):
        validate_decision_batch({"decisions": [missing_leaf]}, [packet])

    invalid_vocabulary = _decision(
        packet,
        "create_dict",
        attributes={
            "brand": "Acme",
            "sub_brand": "Acme",
            "function": "Unknown",
            "packsize": "200 ml",
        },
    )
    with pytest.raises(DecisionValidationError):
        validate_decision_batch({"decisions": [invalid_vocabulary]}, [packet])


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
    assert command[image_flag + 3] == "--"
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


def test_adapter_parser_reads_omp_final_message_text():
    raw = "\n".join([
        json.dumps({"type": "agent_start"}),
        json.dumps({
            "type": "message_end",
            "message": {
                "role": "assistant",
                "content": [{
                    "type": "text",
                    "text": '{"labels":["474747474747","747474747474"]}',
                }],
            },
        }),
        json.dumps({"type": "turn_end"}),
    ])

    assert qa_v3._parse_adapter_json(raw) == {
        "labels": ["474747474747", "747474747474"],
    }

def test_wrong_random_label_fails_before_product_decision():
    def wrong_runner(*args, **kwargs):
        return SimpleNamespace(
            returncode=0,
            stdout=json.dumps({"labels": ["wrong", "wrong"]}),
            stderr="",
        )

    with pytest.raises(AdapterVisionError):
        verify_adapter_vision("codex", wrong_runner)


def test_sentinel_png_uses_large_ocr_safe_glyphs(tmp_path):
    path = tmp_path / "probe.png"
    qa_v3._write_label_png(path, "12345678")
    image = path.read_bytes()
    width = int.from_bytes(image[16:20], "big")
    height = int.from_bytes(image[20:24], "big")
    assert width >= 900
    assert height >= 160


def test_sentinel_uses_a_schema_without_label_values_and_resamples_duplicates(monkeypatch):
    labels = []
    draws = iter([0, 0, 1, 2, 3])

    monkeypatch.setattr(qa_v3.secrets, "randbelow", lambda maximum: next(draws))

    def write_probe(path, label):
        labels.append(label)
        path.write_bytes(b"probe")

    monkeypatch.setattr(qa_v3, "_write_label_png", write_probe)

    def runner(command, **kwargs):
        schema_path = Path(command[command.index("--output-schema") + 1])
        schema = json.loads(schema_path.read_text())
        assert schema["properties"]["labels"]["items"]["type"] == "string"
        assert all(label not in schema_path.read_text() for label in labels)
        assert "RED" not in command[-1] and "BLUE" not in command[-1]
        return SimpleNamespace(
            returncode=0,
            stdout=json.dumps({"labels": ["wrong", "wrong"]}),
            stderr="",
        )

    with pytest.raises(AdapterVisionError):
        qa_v3.verify_adapter_vision("codex", runner)
    assert labels[:2] == ["RED", "BLUE"]
    assert set("".join(labels)) == set("REDBLUEGREENYELLOW")

def test_vision_sentinel_retries_one_transient_label_mismatch(monkeypatch):
    draws = iter([1, 0, 1, 0])
    written = []
    calls = []

    monkeypatch.setattr(qa_v3.secrets, "randbelow", lambda maximum: next(draws))

    def write_probe(path, label):
        written.append(label)
        path.write_bytes(b"probe")

    def runner(command, **kwargs):
        calls.append(command)
        if len(calls) == 1:
            labels = ["wrong", "wrong"]
        else:
            labels = [label.lower() for label in written[-2:]]
        return SimpleNamespace(
            returncode=0,
            stdout=json.dumps({"labels": labels}),
            stderr="",
        )

    monkeypatch.setattr(qa_v3, "_write_label_png", write_probe)
    verify_adapter_vision("codex", runner)
    assert len(calls) == 2


# --- deterministic planner ---

def _context(platform="Shopee"):
    return qa_v3.RunContext(
        project="project",
        merchant_ids=(),
        dataset="babybath",
        platform=platform,
        country="ID",
        category="Baby Bath & Shampoo",
        source_table="babybath.master_babybath_id",
        qa_table="babybath.product_id_dict_qa",
        dict_table="babybath.babybath_dict",
        filter_table="babybath.filter_babybath",
        product_id_dict="babybath.product_id_dict",
        enrichment_table=None,
        qa_identity_col="sku_type_complete",
        qa_pk_col="product_id",
        dict_identity_col="sku_type",
        dict_typo_col="keyword_typo",
        dict_has_meta=False,
        qa_columns=frozenset({
            "product_id", "ecommerce_platform", "sku_name", "brand",
            "sku_type_complete", "gmv", "url", "_meta",
        }),
        dict_columns=frozenset({"brand", "sku_type", "keyword_typo"}),
        filter_columns=frozenset({
            "product_id", "ecommerce_platform", "sku_name", "merchant_id", "url", "_meta",
        }),
        prior_mapping_columns=frozenset(),
        generated_attributes=frozenset({"sku_type"}),
        month="2026-09",
        dict_pattern={
            "sku_type": {
                "sources": ["sub_brand", "function", "packsize"],
                "separator": " ",
            },
            "keywords": {"sources": ["sku_type"], "separator": " "},
        },
        allowed_categorical_values={"function": frozenset({"Wash"})},
        prior_mapping_pk_col=None,
        prior_mapping_identity_col=None,

        meili_index="babybath_taxonomy_qa",
        taxonomy_url=None,
    )


def test_primary_filter_table_selects_only_the_dataset_owned_table():
    assert qa_v3.primary_filter_table(
        "other.reference_filter;babybath.filter_babybath",
        "babybath",
    ) == "babybath.filter_babybath"


def test_primary_filter_table_rejects_foreign_only_configuration():
    assert qa_v3.primary_filter_table(
        "other.reference_filter;another.filter_table",
        "babybath",
    ) == ""


def test_table_reference_accepts_the_real_hyphenated_project_id():
    assert qa_v3._table_reference(
        "sincere-hearth-273704",
        "babybath.filter_babybath",
    ) == "`sincere-hearth-273704.babybath.filter_babybath`"



def test_table_reference_accepts_live_numeric_enrichment_table_name():
    assert qa_v3._table_reference(
        "sincere-hearth-273704",
        "babybath.0_pipeline_babybath_shopee_id",
    ) == "`sincere-hearth-273704.babybath.0_pipeline_babybath_shopee_id`"

def test_worklist_sql_uses_source_tiers_and_keeps_tokopedia_channels_separate():
    sql = qa_v3.build_worklist_sql(
        _context("Tokopedia"),
        max_rows=10,
        kategori="",
        monthly_reverify=False,
        merchant_ids=(),
    )
    assert "s.product_tier IN ('Tier 1')" in sql
    assert "cumulative_gmv_share" not in sql
    assert "JSON_VALUE(SAFE.PARSE_JSON(_meta)" in sql
    assert "qa_status" not in sql.lower()
    assert "Tokopedia | Shop" in sql
    assert "CASE WHEN s.ecommerce_platform = 'Tokopedia | Shop'" not in sql
    assert "`project.babybath.filter_babybath`" in sql
    assert "ORDER BY priority ASC, gmv_monthly DESC" in sql
    assert "s.image AS image_raw" in sql
    assert "REPLACE(s.image" not in sql
    assert "sc.image_raw" in sql

def test_worklist_sql_scopes_qa_state_by_platform_column():
    sql = qa_v3.build_worklist_sql(
        _context("Shopee"),
        max_rows=10,
        kategori="",
        monthly_reverify=False,
        merchant_ids=(),
    )
    assert "WHERE `ecommerce_platform` = @platform" in sql
    assert "WHERE = @platform" not in sql
    tokopedia_sql = qa_v3.build_worklist_sql(
        _context("Tokopedia"),
        max_rows=10,
        kategori="",
        monthly_reverify=False,
        merchant_ids=(),
    )
    assert "WHERE `ecommerce_platform` IN ('Tokopedia', 'Tokopedia | Shop')" in tokopedia_sql
    assert "WHERE IN (" not in tokopedia_sql


def test_missing_dict_pattern_fails_before_retrieval(tmp_path):
    with pytest.raises(FileNotFoundError):
        qa_v3.load_dict_pattern("missing", tmp_path)



def test_candidate_pair_parameter_serializes_for_bigquery():
    class RecordingClient:
        def query(self, sql, job_config):
            job_config.query_parameters[0].to_api_repr()
            return SimpleNamespace(result=lambda: [])

    refs = qa_v3.resolve_candidate_refs(
        RecordingClient(),
        _context(),
        [{
            "id": "p-1", "product_id": "p-1", "ecommerce_platform": "Shopee",
            "query_sku_name": "Acme Wash",
            "candidates": [{"brand": "Acme", "sku_type": "Acme Wash"}],
        }],
    )
    assert refs == {("p-1", "Shopee", "Acme Wash"): {}}

def test_candidate_refs_and_packets_keep_raw_worklist_rows_separate(tmp_path):
    class Row:
        def __init__(self, values):
            self.values = values

        def items(self):
            return self.values.items()

    class Client:
        def query(self, sql, job_config):
            return SimpleNamespace(result=lambda: [
                Row({"brand": "Acme", "sku_type": "First"}),
                Row({"brand": "Acme", "sku_type": "Second"}),
            ])

    rows = [
        {
            "product_id": "same", "ecommerce_platform": "Tokopedia",
            "sku_name": "Shared", "priority": 0, "gmv_monthly": 10,
        },
        {
            "product_id": "same", "ecommerce_platform": "Tokopedia | Shop",
            "sku_name": "Shared", "priority": 0, "gmv_monthly": 9,
        },
    ]
    hits = [
        {
            "id": "same", "product_id": "same", "ecommerce_platform": "Tokopedia",
            "query_sku_name": "Shared",
            "candidates": [{"brand": "Acme", "sku_type": "First"}],
        },
        {
            "id": "same", "product_id": "same", "ecommerce_platform": "Tokopedia | Shop",
            "query_sku_name": "Shared",
            "candidates": [{"brand": "Acme", "sku_type": "Second"}],
        },
    ]
    refs = qa_v3.resolve_candidate_refs(Client(), _context("Tokopedia"), hits)
    assert set(refs) == {
        ("same", "Tokopedia", "Shared"),
        ("same", "Tokopedia | Shop", "Shared"),
    }
    images = {
        ("same", "Tokopedia", "Shared"): PreparedImage(
            qa_v3._packet_id(rows[0]), None, "unavailable", None,
        ),
        ("same", "Tokopedia | Shop", "Shared"): PreparedImage(
            qa_v3._packet_id(rows[1]), None, "unavailable", None,
        ),
    }
    packets = qa_v3.build_product_packets(_context("Tokopedia"), rows, refs, images)
    assert [packet["candidate_refs"] for packet in packets] == [
        set(refs[("same", "Tokopedia", "Shared")]),
        set(refs[("same", "Tokopedia | Shop", "Shared")]),
    ]
    assert len({packet["packet_id"] for packet in packets}) == 2
    assert len({packet["work_item_id"] for packet in packets}) == 2
    decisions = [
        {
            "packet_id": packet["packet_id"],
            "product_id": packet["product_id"],
            "work_item_id": packet["work_item_id"],
            "input_fingerprint": packet["input_fingerprint"],
            "kind": "map_existing",
            "confidence": "unconfident",
            "evidence": [],
            "reason": None,
            "candidate_ref": next(iter(packet["candidate_refs"])),
            "attributes": None,
        }
        for packet in packets
    ]

    assert validate_decision_batch({"decisions": decisions}, packets) == decisions


def test_decision_schema_uses_only_codex_response_format_keywords():
    path = Path(__file__).parent.parent.parent / "script" / "non_niq" / "non_niq_qa_v3_decision_schema.json"
    schema = json.loads(path.read_text())
    banned = {
        "oneOf", "anyOf", "allOf", "const", "$ref", "$defs", "not", "if", "then",
        "else", "minimum", "maximum", "minLength", "maxLength", "minItems",
        "maxItems", "minProperties", "maxProperties", "pattern", "format",
    }

    def check(node):
        if isinstance(node, dict):
            if node.get("type") == "object" and "properties" in node:
                assert set(node["properties"]) == set(node.get("required", [])), (
                    "strict-compatible objects must require every property"
                )
            for key, value in node.items():
                assert key not in banned, "schema uses Codex-rejected keyword %s" % key
                check(value)
        elif isinstance(node, list):
            for value in node:
                check(value)

    check(schema)



def test_prior_mappings_are_batched_and_attached_product_locally():
    class RecordingClient:
        def query(self, sql, job_config):
            job_config.query_parameters[0].to_api_repr()
            return SimpleNamespace(
                result=lambda: [{
                    "product_id": "first",
                    "brand": "Acme",
                    "sku_type": "Acme Wash",
                }],
            )

    context = qa_v3.RunContext(
        **{
            **_context().__dict__,
            "product_id_dict": "babybath.product_id_dict",
            "prior_mapping_pk_col": "product_id",
            "prior_mapping_identity_col": "sku_type",
        },
    )
    prior_mappings = qa_v3.resolve_prior_mappings(RecordingClient(), context, ["first"])
    row = {"product_id": "first", "sku_name": "First", "priority": 0, "gmv_monthly": 10}
    packets = qa_v3.build_product_packets(
        context,
        [row],
        {("first", "", "First"): {}},
        {("first", "", "First"): PreparedImage(qa_v3._packet_id(row), None, "unavailable", None)},
        prior_mappings,
    )
    assert packets[0]["prior_mapping"] == {
        "product_id": "first",
        "brand": "Acme",
        "sku_type": "Acme Wash",
    }

def test_readable_image_rejects_truncated_gif_jpeg_and_webp(tmp_path):
    assert not qa_v3._is_readable_image(b"GIF89a" + b"\x01\x00\x01\x00")
    assert not qa_v3._is_readable_image(
        b"\xff\xd8\xff\xc0\x00\x0b\x08\x00\x01\x00\x01\x01\x01\x11\x00"
    )
    assert not qa_v3._is_readable_image(
        b"RIFF" + b"\x08\x00\x00\x00WEBPVP8 " + b"\x00\x00\x00\x00"
    )
    invalid_gif = (
        b"GIF89a\x01\x00\x01\x00\x00\x00\x00"
        b"\x2c\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x00\x00\x3b"
    )
    assert not qa_v3._is_readable_image(invalid_gif)
    invalid_webp = b"RIFF" + (20).to_bytes(4, "little") + b"WEBPVP8X" + b"\x00" * 10
    assert not qa_v3._is_readable_image(invalid_webp)
    valid_png = tmp_path / "valid.png"
    qa_v3._write_label_png(valid_png, "12345678")
    assert qa_v3._is_readable_image(valid_png.read_bytes())
    assert not qa_v3._is_readable_image(valid_png.read_bytes() + b"junk")


def test_product_packets_are_ordered_and_candidate_refs_are_product_local(tmp_path):
    image_path = tmp_path / "one.png"
    image_path.write_bytes(b"one")
    rows = [
        {
            "product_id": "later", "sku_name": "Later", "priority": 1,
            "gmv_monthly": 9, "image_raw": "https://example.com/later.jpg",
        },
        {
            "product_id": "first", "sku_name": "First", "priority": 0,
            "gmv_monthly": 10, "image_raw": "https://example.com/first.jpg",
        },
    ]
    candidates = {
        ("first", "", "First"): {"dict:first": {"brand": "Acme"}},
        ("later", "", "Later"): {"dict:later": {"brand": "Later"}},
    }
    images = {
        ("first", "", "First"): PreparedImage(
            qa_v3._packet_id(rows[1]), "https://example.com/one.png", "ready", image_path,
        ),
        ("later", "", "Later"): PreparedImage(
            qa_v3._packet_id(rows[0]), None, "unavailable", None,
        ),
    }
    packets = qa_v3.build_product_packets(_context(), rows, candidates, images)
    assert [packet["product_id"] for packet in packets] == ["first", "later"]
    assert packets[0]["candidate_refs"] == {"dict:first"}
    assert packets[1]["candidate_refs"] == {"dict:later"}
    assert packets[0]["attachment_index"] == 1
    assert packets[1]["attachment_index"] is None
    assert packets[0]["image_raw"] == "https://example.com/first.jpg"



def test_packet_prompt_contains_self_contained_decision_protocol():
    context = _executor_context()
    packet = _commit_packet(context)

    prompt = qa_v3.build_packet_prompt(context, [packet])

    for required in (
        '{"decisions":[...]}',
        "exactly one decision per packet",
        "packet_id, product_id, work_item_id, and input_fingerprint exactly",
        "filter",
        "map_existing",
        "create_dict",
        "defer",
        "candidate_refs",
        "writable_attributes",
        "generated_attributes",
        "attachment_index",
        context.category,
        "product image first",
        "different-product freebie/GWP",
        "Do not access services",
    ):
        assert required in prompt

# --- transactional executor ---

NOW = datetime(2026, 9, 17, tzinfo=timezone.utc)


def _executor_context():
    return qa_v3.RunContext(
        **{
            **_context().__dict__,
            "qa_identity_col": "sku_type_complete",
            "dict_columns": frozenset({
                "brand", "sub_brand", "function", "packsize", "sku_type", "keywords",
            }),
            "generated_attributes": frozenset({"sku_type", "keywords"}),
            "taxonomy_url": "https://sheets.example/taxonomy",
        },
    )


def _commit_packet(context, attempt_kind="initial"):
    attempt = plan_attempt(
        {
            "product_id": "p-1",
            "platform": context.platform,
            "country": context.country,
            "dataset": context.dataset,
            "sku_name": "Acme Wash",
        },
        {"kind": attempt_kind},
    )
    return {
        "packet_id": qa_v3._packet_id({
            "product_id": "p-1",
            "ecommerce_platform": context.platform,
            "sku_name": "Acme Wash",
        }),
        "product_id": "p-1",
        "ecommerce_platform": context.platform,
        "sku_name": "Acme Wash",
        "url": "https://example.com/product",
        "merchant_id": "merchant-1",
        "gmv_monthly": 12,
        "work_item_id": attempt.work_item_id,
        "input_fingerprint": attempt.input_fingerprint,
        "attempt": attempt,
        "attempt_id": attempt.attempt_id,
        "attempt_kind": attempt.attempt_kind,
        "image_status": "ready",
        "attachment_index": 1,
        "candidate_refs": {"dict:1"},
        "candidates": {"dict:1": {"brand": "Acme", "sku_type": "Acme Wash"}},
        "writable_attributes": frozenset(
            context.dict_columns - context.generated_attributes - {"_meta"},
        ),
        "generated_attributes": context.generated_attributes,
        "dict_pattern": context.dict_pattern,
        "allowed_categorical_values": context.allowed_categorical_values,
        "prior_mapping": None,
    }


def test_retry_qa_insert_dedupes_attempt_not_title():
    context = _executor_context()
    packet = _commit_packet(context, "retry")
    decision = _decision(packet, "map_existing", candidate_ref="dict:1")
    sql, _ = qa_v3.build_chunk_script(context, [packet], [decision], NOW)
    assert "JSON_VALUE(SAFE.PARSE_JSON(_meta), '$.attempt_id')" in sql
    assert "normalized_sku_name" not in sql
    assert "qa_status" not in sql.lower()
    assert "BEGIN TRANSACTION" in sql and "COMMIT TRANSACTION" in sql


def test_unconfident_retry_metadata_is_driver_terminal():
    context = _executor_context()
    packet = _commit_packet(context, "retry")
    decision = _decision(
        packet,
        "map_existing",
        confidence="unconfident",
        candidate_ref="dict:1",
    )
    _, parameters = qa_v3.build_chunk_script(context, [packet], [decision], NOW)
    metadata = [
        json.loads(parameter.value)
        for parameter in parameters
        if isinstance(parameter.value, str) and '"attempt_id"' in parameter.value
    ]
    assert len(metadata) == 1
    assert metadata[0]["qa_confidence"] == "unconfident"
    assert metadata[0]["human_review"] is True


def test_create_dict_writes_pending_outbox_in_same_transaction():
    context = _executor_context()

    packet = _commit_packet(context)
    packet["candidate_refs"] = set()
    packet["candidates"] = {}
    decision = _decision(
        packet,
        "create_dict",
        attributes={
            "brand": "Acme",
            "sub_brand": "Acme",
            "function": "Wash",
            "packsize": "200 ml",
        },
    )
    sql, parameters = qa_v3.build_chunk_script(context, [packet], [decision], NOW)
    assert "INSERT INTO `project.magpie_reference.non_niq_qa_outbox`" in sql
    values = [str(parameter.value) for parameter in parameters]
    for parameter in parameters:
        parameter.to_api_repr()
    assert any('"meili_index"' in value for value in values)
    assert "sheet_append" in values
    assert "BEGIN TRANSACTION" in sql and "COMMIT TRANSACTION" in sql


def test_filter_insert_is_product_level_replay_safe():
    context = _executor_context()
    packet = _commit_packet(context)
    decision = _decision(packet, "filter", reason="outside category")
    sql, _ = qa_v3.build_chunk_script(context, [packet], [decision], NOW)
    assert "INSERT INTO `project.babybath.filter_babybath`" in sql
    assert "WHERE NOT EXISTS" in sql
    assert "product_id" in sql


def test_defer_generates_no_dml_or_outbox_event():
    context = _executor_context()
    packet = _commit_packet(context)
    decision = _decision(
        packet,
        "defer",
        confidence="unconfident",
        evidence=[],
        reason="image unavailable",
    )
    sql, parameters = qa_v3.build_chunk_script(context, [packet], [decision], NOW)
    assert sql == ""
    assert parameters == ()


def test_known_natural_identity_conflict_fails_before_dml():
    context = _executor_context()
    packet = _commit_packet(context)
    packet["candidates"]["dict:1"]["sku_type"] = "Acme Wash 200 ml"
    decision = _decision(
        packet,
        "create_dict",
        attributes={
            "brand": "Acme",
            "sub_brand": "Acme",
            "function": "Wash",
            "packsize": "200 ml",
        },
    )
    with pytest.raises(DecisionValidationError):
        qa_v3.build_chunk_script(context, [packet], [decision], NOW)



def test_apply_chunk_retries_the_validated_decisions_without_adapter(monkeypatch):
    context = _executor_context()
    packet = _commit_packet(context, "retry")
    decision = _decision(packet, "map_existing", candidate_ref="dict:1")
    calls = []

    class FlakyClient:
        def query(self, sql, job_config):
            calls.append(sql)
            if len(calls) == 1:
                raise TimeoutError("transient")
            return SimpleNamespace(result=lambda: [])

    monkeypatch.setattr(qa_v3, "invoke_adapter", lambda *args: pytest.fail("adapter invoked"))
    monkeypatch.setattr(qa_v3, "verify_chunk_commit", lambda *args: None)
    commit = qa_v3.apply_chunk(FlakyClient(), context, [packet], [decision], NOW)
    assert commit.attempts == (packet["attempt"],)
    assert len(calls) == 2


def test_create_dict_compares_authored_values_inside_transaction():
    context = _executor_context()
    packet = _commit_packet(context)
    packet["candidate_refs"] = set()
    packet["candidates"] = {}
    decision = _decision(
        packet,
        "create_dict",
        attributes={
            "brand": "Acme",
            "sub_brand": "Acme",
            "function": "Wash",
            "packsize": "200 ml",
        },
    )

    sql, _ = qa_v3.build_chunk_script(context, [packet], [decision], NOW)

    assert "ASSERT NOT EXISTS" in sql
    assert "IS DISTINCT FROM" in sql
    assert "SELECT r._v3_brand AS brand, r._v3_identity_value AS identity_value" in sql
    assert "non_niq_qa_identity_locks" in sql
    assert "lock_scope = 'non_niq_qa_global'" in sql

def test_create_dict_preflight_does_not_duplicate_identity_aliases():
    context = _executor_context()
    packet = _commit_packet(context)
    decision = _decision(
        packet,
        "create_dict",
        attributes={
            "brand": "Acme",
            "sub_brand": "Acme",
            "function": "Wash",
            "packsize": "200 ml",
        },
    )
    operations, _ = qa_v3._build_operations(context, [packet], [decision], NOW)
    queries = []

    class RecordingClient:
        def query(self, sql, job_config):
            queries.append(sql)
            return SimpleNamespace(result=lambda: [])
    qa_v3._preflight_create_identities(RecordingClient(), context, operations)

    assert queries[0].count("d.brand AS _v3_brand") == 1
    assert queries[0].count("d.`sku_type` AS _v3_identity_value") == 1


def test_apply_chunk_treats_existing_exact_dict_as_replay(monkeypatch):
    context = _executor_context()
    packet = _commit_packet(context)
    packet["candidate_refs"] = set()
    packet["candidates"] = {}
    decision = _decision(
        packet,
        "create_dict",
        attributes={
            "brand": "Acme",
            "sub_brand": "Acme",
            "function": "Wash",
            "packsize": "200 ml",
        },
    )

    class ExistingIdentityClient:
        def query(self, sql, job_config):
            return SimpleNamespace(result=lambda: [{
                "_v3_brand": "Acme",
                "_v3_identity_value": "Acme Wash 200 ml",
                "_v3_brand": "Acme",
                "_v3_function": "Wash",
                "_v3_keywords": "Acme Wash 200 ml",
                "_v3_packsize": "200 ml",
                "_v3_sku_type": "Acme Wash 200 ml",
                "_v3_sub_brand": "Acme",
            }])

    monkeypatch.setattr(qa_v3, "verify_chunk_commit", lambda *args: None)
    commit = qa_v3.apply_chunk(ExistingIdentityClient(), context, [packet], [decision], NOW)

    assert commit.created_dict_identities == ()
    assert commit.outbox_events == ()


# --- outbox recovery and queue-compatible CLI ---

def _pending_event(event_id, event_type, payload):
    return {
        "event_id": event_id,
        "attempt_id": "attempt-" + event_id,
        "decision_id": "decision-" + event_id,
        "event_type": event_type,
        "payload": json.dumps(payload),
        "attempts": 0,
    }


def test_drain_outbox_batches_meili_events_and_marks_them_complete(monkeypatch):
    context = _executor_context()
    events = [
        _pending_event(
            "meili-1",
            "meili_index",
            {
                "meili_url": "http://meili",
                "meili_index": "idx",
                "document": {"product_id": "p-1", "sku_name": "One"},
            },
        ),
        _pending_event(
            "meili-2",
            "meili_index",
            {
                "meili_url": "http://meili",
                "meili_index": "idx",
                "document": {"product_id": "p-2", "sku_name": "Two"},
            },
        ),
    ]
    updates = []

    class RecordingClient:
        def query(self, sql, job_config):
            if sql.startswith("SELECT event_id"):
                return SimpleNamespace(result=lambda: events)
            updates.append((sql, job_config.query_parameters))
            return SimpleNamespace(result=lambda: [])

    calls = []
    monkeypatch.setattr(
        qa_v3,
        "index_documents_strict",
        lambda documents, url, index: calls.append((documents, url, index)),
        raising=False,
    )
    qa_v3.drain_outbox(RecordingClient(), context, NOW)
    assert calls == [
        (
            [
                {"product_id": "p-1", "sku_name": "One"},
                {"product_id": "p-2", "sku_name": "Two"},
            ],
            "http://meili",
            "idx",
        ),
    ]
    assert len(updates) == 2
    assert all(
        any(parameter.value == "complete" for parameter in parameters)
        for _, parameters in updates
    )



def test_failed_strict_meili_delivery_stays_pending(monkeypatch):
    context = _executor_context()
    event = _pending_event(
        "meili-failed",
        "meili_index",
        {
            "meili_url": "http://meili",
            "meili_index": "idx",
            "document": {"product_id": "p-1", "sku_name": "One"},
        },
    )
    updates = []
    strict_calls = []

    class RecordingClient:
        def query(self, sql, job_config):
            if sql.startswith("SELECT event_id"):
                return SimpleNamespace(result=lambda: [event])
            updates.append((sql, job_config.query_parameters))
            return SimpleNamespace(result=lambda: [])

    def strict_failure(*args):
        strict_calls.append(args)
        raise RuntimeError("Meilisearch task failed")

    monkeypatch.setattr(qa_v3, "index_documents", lambda *args: None, raising=False)
    monkeypatch.setattr(qa_v3, "index_documents_strict", strict_failure, raising=False)

    with pytest.raises(RuntimeError, match="outbox delivery failed"):
        qa_v3.drain_outbox(RecordingClient(), context, NOW)

    assert strict_calls
    assert len(updates) == 1
    assert "status = 'pending'" in updates[0][0]
def test_sheet_outbox_failure_stays_pending_and_fails_the_run(monkeypatch):
    context = _executor_context()
    event = _pending_event(
        "sheet-1",
        "sheet_append",
        {
            "project": context.project,
            "dict_table": context.dict_table,
            "sheet_url": context.taxonomy_url,
            "entry": {
                "brand": "Acme",
                "identity_col": "sku_type",
                "identity_value": "Acme Wash",
            },
        },
    )
    updates = []

    class RecordingClient:
        def query(self, sql, job_config):
            if sql.startswith("SELECT event_id"):
                return SimpleNamespace(result=lambda: [event])
            updates.append((sql, job_config.query_parameters))
            return SimpleNamespace(result=lambda: [])

    monkeypatch.setattr(
        qa_v3,
        "append_sheet_new_entries_strict",
        lambda *args, **kwargs: {
            ("Acme", "sku_type", "Acme Wash"): SimpleNamespace(
                status="failed", error="write failed",
            ),
        },
        raising=False,
    )
    with pytest.raises(RuntimeError, match="outbox delivery failed"):
        qa_v3.drain_outbox(RecordingClient(), context, NOW)
    assert len(updates) == 1
    assert "status = 'pending'" in updates[0][0]
    assert "last_error" in updates[0][0]


def test_sheet_outbox_already_present_completes(monkeypatch):
    context = _executor_context()
    event = _pending_event(
        "sheet-present",
        "sheet_append",
        {
            "project": context.project,
            "dict_table": context.dict_table,
            "sheet_url": context.taxonomy_url,
            "entry": {
                "brand": "Acme",
                "identity_col": "sku_type",
                "identity_value": "Acme Wash",
            },
        },
    )
    updates = []

    class RecordingClient:
        def query(self, sql, job_config):
            if sql.startswith("SELECT event_id"):
                return SimpleNamespace(result=lambda: [event])
            updates.append(job_config.query_parameters)
            return SimpleNamespace(result=lambda: [])

    monkeypatch.setattr(
        qa_v3,
        "append_sheet_new_entries_strict",
        lambda *args, **kwargs: {
            ("Acme", "sku_type", "Acme Wash"): SimpleNamespace(
                status="already_present", error=None,
            ),
        },
        raising=False,
    )
    qa_v3.drain_outbox(RecordingClient(), context, NOW)
    assert any(
        parameter.value == "complete"
        for parameter in updates[0]
    )


def test_emit_result_starts_with_queue_signal(capsys):
    qa_v3.emit_result("babybath:shopee", "DONE", "QA v3 session finished", rows="1")
    lines = capsys.readouterr().out.splitlines()
    assert lines[0] == "QUEUE_SIGNAL: DONE"
    assert json.loads(lines[1])["signal"] == "DONE"


def test_run_drains_crash_recovery_before_planning_without_adapter(monkeypatch):
    context = _executor_context()
    calls = []
    args = SimpleNamespace(
        dataset="babybath", platform="shopee", country="ID", max_turns=500,
        max_rows=10, kategori="", dry_run=False,
    )
    monkeypatch.setattr(qa_v3, "resolve_run_context", lambda args, client: context, raising=False)
    monkeypatch.setattr(qa_v3, "verify_adapter_vision", lambda *args: pytest.fail("adapter invoked"), raising=False)
    monkeypatch.setattr(qa_v3, "drain_outbox", lambda *args: calls.append("drain"), raising=False)
    monkeypatch.setattr(qa_v3, "materialize_worklist", lambda *args: calls.append("worklist") or [], raising=False)
    monkeypatch.setattr(qa_v3, "emit_result", lambda *args, **kwargs: calls.append(args[1]), raising=False)
    assert qa_v3.run(args, client=object()) == 0
    assert calls == ["drain", "worklist", "NOTHING_TO_DO"]



def test_run_skips_adapter_for_casefold_auto_confirmation(monkeypatch):
    context = _executor_context()
    calls = []
    args = SimpleNamespace(
        dataset="babybath", platform="shopee", country="ID", max_turns=500,
        max_rows=1, kategori="", dry_run=False,
    )
    row = {
        "product_id": "p-1",
        "sku_name": "ACME Wash",
        "ecommerce_platform": "Shopee",
        "priority": 0,
        "gmv_monthly": 12,
        "image_raw": "https://example.com/product.jpg",
    }
    monkeypatch.setattr(qa_v3, "resolve_run_context", lambda args, client: context, raising=False)
    monkeypatch.setattr(qa_v3, "verify_adapter_vision", lambda *args: pytest.fail("adapter invoked"), raising=False)
    monkeypatch.setattr(qa_v3, "drain_outbox", lambda *args: calls.append("drain"), raising=False)
    monkeypatch.setattr(qa_v3, "materialize_worklist", lambda *args: calls.append("worklist") or [row], raising=False)
    monkeypatch.setattr(
        qa_v3,
        "retrieve_candidates",
        lambda *args: calls.append("retrieve") or [{
            "id": "p-1",
            "candidates": [{
                "product_id": "old-1",
                "sku_name": "Acme Wash",
                "brand": "Acme",
                "sku_type_complete": "Acme Wash",
            }],
        }],
        raising=False,
    )
    monkeypatch.setattr(
        qa_v3,
        "auto_confirm_worklist",
        lambda *args: calls.append("auto") or {("p-1", "Shopee", "ACME Wash")},
        raising=False,
    )
    monkeypatch.setattr(qa_v3, "emit_result", lambda *args, **kwargs: calls.append(args[1]), raising=False)

    assert qa_v3.run(args, client=object()) == 0
    assert calls == ["drain", "worklist", "retrieve", "auto", "DONE"]


def test_auto_confirm_uses_resolved_regional_qa_platform_column(monkeypatch):
    context = qa_v3.RunContext(**{
        **_executor_context().__dict__,
        "qa_columns": frozenset({
            "product_id", "ecommerce", "sku_name", "brand", "sku_type", "_meta",
        }),
        "qa_identity_col": "sku_type",
    })
    captured = {}

    def confirm(*args, **kwargs):
        captured["qa_platform_col"] = args[4]
        captured["qa_identity_col"] = kwargs["qa_identity_col"]
        return set()

    monkeypatch.setattr(qa_v3, "confirm_casefold_matches", confirm)
    assert qa_v3.auto_confirm_worklist(
        object(),
        context,
        [{"product_id": "p-1", "ecommerce_platform": "Lazada", "sku_name": "Acme Wash"}],
        [],
    ) == set()
    assert captured["qa_platform_col"] == "ecommerce"
    assert captured["qa_identity_col"] == "sku_type"

def test_dry_run_never_mutates_or_delivers_outbox(monkeypatch):
    context = _executor_context()
    args = SimpleNamespace(
        dataset="babybath", platform="shopee", country="ID", max_turns=500,
        max_rows=1, kategori="", dry_run=True,
    )
    packet = {
        "packet_id": qa_v3._packet_id({
            "product_id": "p-1",
            "sku_name": "Acme Wash",
        }),
        "product_id": "p-1",
        "work_item_id": "",
        "input_fingerprint": "",
        "attachment_index": None,
    }
    attempt = plan_attempt(
        {
            "product_id": "p-1",
            "sku_name": "Acme Wash",
            "priority": 0,
            "image_raw": None,
            "image_url": None,
            "image_status": "unavailable",
            "dataset": context.dataset,
            "platform": context.platform,
            "country": context.country,
        },
        {"kind": "initial"},
    )
    packet.update(work_item_id=attempt.work_item_id, input_fingerprint=attempt.input_fingerprint)
    deferred = _decision(
        packet,
        "defer",
        confidence="unconfident",
        evidence=[],
        reason="image unavailable",
    )
    monkeypatch.setattr(qa_v3, "resolve_run_context", lambda args, client: context, raising=False)
    monkeypatch.setattr(qa_v3, "verify_adapter_vision", lambda *args: None, raising=False)
    monkeypatch.setattr(
        qa_v3,
        "materialize_worklist",
        lambda *args: [{
            "product_id": "p-1", "sku_name": "Acme Wash", "priority": 0,
            "gmv_monthly": 12, "image_raw": None,
        }],
        raising=False,
    )
    monkeypatch.setattr(qa_v3, "retrieve_candidates", lambda *args: [{"id": "p-1", "candidates": []}], raising=False)
    monkeypatch.setattr(qa_v3, "resolve_candidate_refs", lambda *args: {"p-1": {}}, raising=False)
    monkeypatch.setattr(qa_v3, "resolve_prior_mappings", lambda *args: {}, raising=False)
    monkeypatch.setattr(
        qa_v3,
        "prepare_images",
        lambda *args: {"p-1": PreparedImage("p-1", None, "unavailable", None)},
        raising=False,
    )
    monkeypatch.setattr(qa_v3, "invoke_adapter", lambda *args: {"decisions": [deferred]}, raising=False)
    monkeypatch.setattr(qa_v3, "apply_chunk", lambda *args: pytest.fail("mutation invoked"), raising=False)
    monkeypatch.setattr(qa_v3, "drain_outbox", lambda *args: pytest.fail("outbox delivery invoked"), raising=False)
    signals = []
    monkeypatch.setattr(qa_v3, "emit_result", lambda table, signal, message, **fields: signals.append(signal), raising=False)
    assert qa_v3.run(args, client=object()) == 0
    assert signals == ["BLOCKED"]
