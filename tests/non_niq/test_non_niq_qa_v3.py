import json
from types import SimpleNamespace

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


def test_sentinel_uses_a_schema_without_label_values_and_resamples_duplicates(monkeypatch):
    labels = []
    draws = iter([7, 7, 8])

    def write_probe(path, label):
        labels.append(label)
        path.write_bytes(b"probe")

    def runner(command, **kwargs):
        schema_path = Path(command[command.index("--output-schema") + 1])
        schema = json.loads(schema_path.read_text())
        assert schema["properties"]["labels"]["items"]["type"] == "string"
        assert all(label not in schema_path.read_text() for label in labels)
        return SimpleNamespace(
            returncode=0,
            stdout=json.dumps({"labels": ["wrong", "wrong"]}),
            stderr="",
        )

    monkeypatch.setattr(qa_v3.secrets, "randbelow", lambda maximum: next(draws))
    monkeypatch.setattr(qa_v3, "_write_label_png", write_probe)
    with pytest.raises(AdapterVisionError):
        verify_adapter_vision("codex", runner)
    assert labels == ["00000007", "00000008"]


# --- deterministic planner ---

def _context(platform="Shopee"):
    return qa_v3.RunContext(
        project="project",
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

def test_worklist_sql_preserves_v2_scope_and_tokopedia_canonicalization():
    sql = qa_v3.build_worklist_sql(
        _context("Tokopedia"),
        max_rows=10,
        kategori="",
        monthly_reverify=False,
        merchant_ids=(),
    )
    assert "r.cumulative_gmv_share <= 0.9" in sql
    assert "JSON_VALUE(SAFE.PARSE_JSON(_meta)" in sql
    assert "qa_status" not in sql.lower()
    assert "Tokopedia | Shop" in sql
    assert "`project.babybath.filter_babybath`" in sql
    assert "ORDER BY priority ASC, gmv_monthly DESC" in sql

    assert "s.image AS image_raw" in sql
    assert "REPLACE(s.image" not in sql
    assert "sc.image_raw" in sql


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
        [{"id": "p-1", "candidates": [{"brand": "Acme", "sku_type": "Acme Wash"}]}],
    )
    assert refs == {"p-1": {}}



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
    packets = qa_v3.build_product_packets(
        context,
        [{"product_id": "first", "sku_name": "First", "priority": 0, "gmv_monthly": 10}],
        {"first": {}},
        {"first": PreparedImage("first", None, "unavailable", None)},
        prior_mappings,
    )
    assert packets[0]["prior_mapping"] == {
        "product_id": "first",
        "brand": "Acme",
        "sku_type": "Acme Wash",
    }


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
        "first": {"dict:first": {"brand": "Acme"}},
        "later": {"dict:later": {"brand": "Later"}},
    }
    images = {
        "first": PreparedImage("first", "https://example.com/one.png", "ready", image_path),
        "later": PreparedImage("later", None, "unavailable", None),
    }
    packets = qa_v3.build_product_packets(_context(), rows, candidates, images)
    assert [packet["product_id"] for packet in packets] == ["first", "later"]
    assert packets[0]["candidate_refs"] == {"dict:first"}
    assert packets[1]["candidate_refs"] == {"dict:later"}
    assert packets[0]["attachment_index"] == 1
    assert packets[1]["attachment_index"] is None
    assert packets[0]["image_raw"] == "https://example.com/first.jpg"
