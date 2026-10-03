#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
source script/non_niq/eiger_qa.sh

fail() { echo "FAIL: $1" >&2; exit 1; }

require_eiger_harness codex || fail "Codex must be a supported Eiger harness"
require_eiger_harness missing_harness >/dev/null 2>&1 && fail "unsupported harness must fail"

codex_prompt=$(build_qa_prompt mockplatform ID eiger.master_eiger_id eiger.filter_eiger /tmp/mock_worklist 1 eiger_mockplatform_ID codex /tmp/mock_manifest)
[[ "$codex_prompt" == *'labelled contact sheets'* ]] || fail "Codex prompt must instruct inspection of attached images"
[[ "$codex_prompt" == *'"source":"codex"'* ]] || fail "Codex writes must use codex _meta source"
[[ "$codex_prompt" == *'defer every QA/filter INSERT'* ]] || fail "Codex prompt must defer DML until ledger validation"
[[ "$codex_prompt" == *'/tmp/eiger_mockplatform_ID_eiger_decisions.jsonl'* ]] || fail "Codex prompt must retain its raw-row ledger path"
[[ "$codex_prompt" == *'no_matching_guideline_rule'* ]] || fail "Eiger prompt must filter products with no guidance rule"
[[ "$codex_prompt" == *'only (ecommerce, product_id, sku_name, _meta)'* ]] || fail "Eiger filter writes must use the filter-table schema"
[[ "$codex_prompt" != *'"source":"claude_code"'* ]] || fail "Codex prompt must not stamp Claude source"
claude_prompt=$(build_qa_prompt mockplatform ID eiger.master_eiger_id eiger.filter_eiger /tmp/mock_worklist 1 eiger_mockplatform_ID)
[[ "$claude_prompt" == *'Read tool'* ]] || fail "Claude prompt must retain its image instructions"
[[ "$claude_prompt" == *'"source":"claude_code"'* ]] || fail "Claude prompt must retain Claude _meta source"
[[ "$claude_prompt" == *'wrapper already ran one batch Meilisearch retrieval'* ]] || fail "Eiger prompt must consume wrapper-side retrieval"
[[ "$claude_prompt" != *'non_niq_helper.py retrieve'* ]] || fail "Eiger prompt must not repeat wrapper-side retrieval"
[[ "$claude_prompt" == *'eiger_mockplatform_ID_eiger_decisions.jsonl'* ]] || fail "Claude must write the raw-row decision ledger"
[[ "$claude_prompt" == *'non_niq_taxonomy_insert_log'* ]] || fail "Eiger prompt must require the shared taxonomy insert log"
[[ "$claude_prompt" == *'SAME BigQuery transaction'* ]] || fail "Eiger prompt must require atomic QA/log writes"
[[ "$claude_prompt" == *'"inserted_row"'* ]] || fail "Eiger prompt must define the inserted_row JSON envelope"

direct_result='{"status":"complete","rows_qa_confirmed":1,"rows_qa_unconfident":0,"rows_filtered":0,"rows_created_in_dict":1,"rows_unresolved":0,"findings":[],"blockers":[]}'
[[ "$(extract_result_json "$direct_result")" == "$direct_result" ]] || fail "Codex direct JSON must parse"
[[ "$(decide_queue_signal "$direct_result")" == DONE ]] || fail "complete Codex JSON must signal DONE"
[[ "$(decide_queue_signal '{"status":"partial","rows_unresolved":1}')" == DONE ]] || fail "unresolved Codex rows must release the queue task"
residual_counts_cover_worklist "$direct_result" 1 || fail "residual counts must cover Eiger worklist"
residual_counts_cover_worklist '{"rows_qa_confirmed":0.5,"rows_qa_unconfident":0.5,"rows_filtered":0,"rows_unresolved":0}' 1 && fail "fractional Eiger residual counts must block automatic-total merge"
residual_counts_cover_worklist '{"rows_qa_confirmed":0,"rows_qa_unconfident":0,"rows_filtered":0,"rows_unresolved":0}' 1 && fail "under-counted Eiger residual must block automatic-total merge"
grep -qF 'CODEX_QA_MODEL:-cx/gpt-6-sol' script/non_niq/eiger_qa.sh || fail "Eiger should default Codex to Sol"
grep -qF 'CODEX_QA_REASONING_EFFORT:-high' script/non_niq/eiger_qa.sh || fail "Eiger should default Codex to high reasoning"

# Exercise main() end to end with local fake CLIs; no BigQuery, Sheet, image download,
# Codex API, or production writes are made. Use a distinct platform/temp tag.
mock_dir=$(mktemp -d)
trap 'rm -rf "$mock_dir" /tmp/eiger_mockplatform_ID_full_worklist.jsonl /tmp/eiger_mockplatform_ID_residual_worklist.jsonl /tmp/eiger_mockplatform_ID_worklist.jsonl /tmp/eiger_mockplatform_ID_candidates.jsonl /tmp/eiger_mockplatform_ID_eiger_decisions.jsonl; rm -f /tmp/eiger_mockplatform_ID_codex_final.* /tmp/eiger_mockplatform_ID_codex_stdout.*' EXIT
printf '%s\n' '{"type":"thread.started"}' '{"type":"turn.started"}' \
  '{"type":"error","message":"Selected model is at capacity. Please try a different model."}' \
  > "$mock_dir/capacity.jsonl"
: > "$mock_dir/empty_final.json"
is_eiger_codex_startup_capacity_failure "$mock_dir/capacity.jsonl" "$mock_dir/empty_final.json" \
  || fail "startup-only capacity failure should be retryable"
printf '%s\n' '{"type":"item.completed","item":{"type":"command_execution"}}' >> "$mock_dir/capacity.jsonl"
is_eiger_codex_startup_capacity_failure "$mock_dir/capacity.jsonl" "$mock_dir/empty_final.json" \
  && fail "capacity error after tool activity must not be retried"
cat > "$mock_dir/bwrap" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
cat > "$mock_dir/bq" <<'MOCK'
#!/usr/bin/env bash
last_arg="${@: -1}"
if [[ " $* " == *' --format=csv '* ]]; then
  if [[ "$last_arg" == *'non_niq_taxonomy_insert_log'* ]]; then
    printf 'f0_\n%s\n' "${EIGER_LOG_GAP_COUNT:-0}"
  else
    printf 'f0_\n2026-08\n'
  fi
elif [[ "${EIGER_PARTIAL:-}" == 1 || "${EIGER_UNDERCOUNT:-}" == 1 ]]; then
  printf '[{"product_id":"auto-id","sku_name":"Eiger automatic product","image":"https://example.invalid/auto.jpg","ecommerce_platform":"Shopee"},{"product_id":"residual-id","sku_name":"Eiger residual product","image":"https://example.invalid/residual.jpg","ecommerce_platform":"Shopee"}]\n'
else
  printf '[{"product_id":"mock-id","sku_name":"Eiger mock product","image":"https://example.invalid/mock.jpg","ecommerce_platform":"Shopee"}]\n'
fi
MOCK
cat > "$mock_dir/python" <<'MOCK'
#!/usr/bin/env bash
case " $* " in
  *" categories "*)
    printf '[{"dataset":"eiger","ecommerce_platform":"mockplatform","master_table_prod":"eiger.master_eiger_id","filter_table":"eiger.filter_eiger","0":"-"}]\n'
    ;;
  *" retrieve "*)
    out_file=""
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == --output-file ]]; then out_file="$2"; break; fi
      shift
    done
    if [[ "${EIGER_PARTIAL:-}" == 1 || "${EIGER_UNDERCOUNT:-}" == 1 ]]; then
      printf '%s\n' '{"id":"auto-id","product_id":"auto-id","ecommerce_platform":"Shopee","candidates":[{"product_id":"old-id","sku_name":"eiger automatic product","brand":"Eiger","sku_type_complete":"Eiger Automatic Product","mgh_2":"Lifestyle","mgh_3":"Outerwear","mgh_4":"Jacket","product_type":"Jacket"}]}' > "$out_file"
    else
      printf '%s\n' '{"id":"mock-id","product_id":"mock-id","ecommerce_platform":"Shopee","candidates":[{"product_id":"old-id","sku_name":"eiger mock product","brand":"Eiger","sku_type_complete":"Eiger Mock Product","mgh_2":"Lifestyle","mgh_3":"Outerwear","mgh_4":"Jacket","product_type":"Jacket"}]}' > "$out_file"
    fi
    ;;
  *" auto-confirm "*)
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == --residual-file ]]; then residual_file="$2"; break; fi
      shift
    done
    if [[ "${EIGER_PARTIAL:-}" == 1 || "${EIGER_UNDERCOUNT:-}" == 1 ]]; then
      printf '%s\n' '{"product_id":"residual-id","sku_name":"Eiger residual product","image":"https://example.invalid/residual.jpg","ecommerce_platform":"Shopee"}' > "$residual_file"
      printf '%s\n' '{"confirmed":1,"residual":1}'
    else
      : > "$residual_file"
      printf '%s\n' '{"confirmed":1,"residual":0}'
    fi
    ;;
  *)
    out_dir=""
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == --output-dir ]]; then out_dir="$2"; break; fi
      shift
    done
    mkdir -p "$out_dir"
    printf '{"row_number":1,"product_id":"mock-id","image_status":"readable"}\n' > "$out_dir/manifest.jsonl"
    : > "$out_dir/sheet_001.jpg"
    printf '{"manifest":"%s/manifest.jsonl","sheets":["%s/sheet_001.jpg"],"readable":1,"failed":0}\n' "$out_dir" "$out_dir"
    ;;
esac
MOCK
cat > "$mock_dir/codex" <<'MOCK'
#!/usr/bin/env bash
printf 'CALLED' > "$EIGER_TEST_CODEX_MARKER"
out_file=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --output-last-message ]]; then out_file="$2"; break; fi
  shift
done
    if [[ "${EIGER_PARTIAL:-}" == 1 || "${EIGER_UNDERCOUNT:-}" == 1 ]]; then
      printf '{"product_id":"residual-id","ecommerce_platform":"Shopee","sku_name":"Eiger residual product","decision":"qa_confident","image_observation":"product visible","title_evidence":"Eiger residual product","identity_rationale":"mock fixture","intended_table_values":{"brand":"Eiger"}}\n' > /tmp/eiger_mockplatform_ID_eiger_decisions.jsonl
    else
      printf '{"product_id":"mock-id","ecommerce_platform":"Shopee","sku_name":"Eiger mock product","decision":"qa_confident","image_observation":"product visible","title_evidence":"Eiger mock product","identity_rationale":"mock fixture","intended_table_values":{"brand":"Eiger"}}\n' > /tmp/eiger_mockplatform_ID_eiger_decisions.jsonl
    fi
    if [[ "${EIGER_UNDERCOUNT:-}" == 1 ]]; then
      printf '%s\n' '{"status":"complete","rows_qa_confirmed":0,"rows_qa_unconfident":0,"rows_filtered":0,"rows_created_in_dict":0,"rows_unresolved":0,"findings":[],"blockers":[]}' > "$out_file"
    else
      printf '%s\n' '{"status":"complete","rows_qa_confirmed":1,"rows_qa_unconfident":0,"rows_filtered":0,"rows_created_in_dict":1,"rows_unresolved":0,"findings":[],"blockers":[]}' > "$out_file"
    fi
    printf '%s\n' '{"type":"thread.started"}' '{"type":"item.completed","item":{"type":"agent_message","text":"done"}}'
MOCK
chmod +x "$mock_dir/bwrap" "$mock_dir/bq" "$mock_dir/python" "$mock_dir/codex"


output=$(
  PYTHON_BIN="$mock_dir/python"
  EIGER_TEST_CODEX_MARKER="$mock_dir/codex_called"
  export EIGER_TEST_CODEX_MARKER
  PATH="$mock_dir:$PATH"
  AGENT_HARNESS=codex
  main mockplatform ID 1 1
) || fail "mock Eiger automatic-confirmation run must complete"
[[ ! -f "$mock_dir/codex_called" ]] || fail "all automatic exact-title matches must skip Codex"
[[ "$output" == *'QUEUE_SIGNAL: DONE'* ]] || fail "mock automatic confirmation must report DONE"
[[ "$output" != *'Delegating to claude'* ]] || fail "all automatic matches must not invoke Claude"

partial_output=$(
  EIGER_PARTIAL=1
  export EIGER_PARTIAL
  PYTHON_BIN="$mock_dir/python"
  EIGER_TEST_CODEX_MARKER="$mock_dir/codex_called"
  export EIGER_TEST_CODEX_MARKER
  PATH="$mock_dir:$PATH"
  AGENT_HARNESS=codex
  prepare_eiger_codex_gcloud_runtime() { printf '%s\n%s\n' "$mock_dir" "$mock_dir/adc.json"; }
  main mockplatform ID 1 2
) || fail "mock Eiger mixed automatic/residual run must complete"
[[ -f "$mock_dir/codex_called" ]] || fail "residual work must invoke Codex"
[[ "$partial_output" == *'QUEUE_SIGNAL: DONE'* ]] || fail "residual Codex completion must stay DONE after automatic totals merge"

undercount_output=$(
  EIGER_PARTIAL=1
  EIGER_UNDERCOUNT=1
  export EIGER_PARTIAL EIGER_UNDERCOUNT
  PYTHON_BIN="$mock_dir/python"
  EIGER_TEST_CODEX_MARKER="$mock_dir/codex_called"
  export EIGER_TEST_CODEX_MARKER
  PATH="$mock_dir:$PATH"
  AGENT_HARNESS=codex
  prepare_eiger_codex_gcloud_runtime() { printf '%s\n%s\n' "$mock_dir" "$mock_dir/adc.json"; }
  main mockplatform ID 1 2
) || fail "under-counted residual run must complete"
[[ "$undercount_output" == *'QUEUE_SIGNAL: DONE'* ]] || fail "under-counted residual must still release the queue task (findings-only audit, never a hard block)"
[[ "$undercount_output" == *'"rows_qa_confirmed":1'* ]] || fail "under-counted residual must still merge automatic confirmations (the merge is unconditional now)"

log_gap_output=$(
  EIGER_PARTIAL=1
  EIGER_LOG_GAP_COUNT=1
  export EIGER_PARTIAL EIGER_LOG_GAP_COUNT
  PYTHON_BIN="$mock_dir/python"
  EIGER_TEST_CODEX_MARKER="$mock_dir/codex_called"
  export EIGER_TEST_CODEX_MARKER
  PATH="$mock_dir:$PATH"
  AGENT_HARNESS=codex
  prepare_eiger_codex_gcloud_runtime() { printf '%s\n%s\n' "$mock_dir" "$mock_dir/adc.json"; }
  main mockplatform ID 1 2
) || fail "a complete residual run with an insert-log gap must still complete"
[[ "$log_gap_output" == *'QUEUE_SIGNAL: DONE'* ]] || fail "an insert-log gap must never block the queue -- it's a findings-only audit"
[[ "$log_gap_output" == *'non_niq_taxonomy_insert_log entry'* ]] || fail "the result must still explain the insert-log gap in findings"

echo "ALL EIGER QA TESTS PASSED"
