#!/usr/bin/env bash
set -euo pipefail
# Structural self-test for non_niq_qa_v2_merchant_list.sh and non_niq_qa_v2_waterheater_multi.sh --
# both carry their own independent copy of v2's build_qa_prompt()/main() (not sourced from
# non_niq_qa_v2.sh), so the insert-log requirement and its code-side backstop had to be ported by
# hand. Grep-only: these scripts have no existing fake-CLI functional harness to extend, and the
# wiring pattern itself is already exercised end to end by test_eiger_qa.sh /
# taxonomy_insert_log_gap_query's coverage in script/lib/common.sh --self-test.
# Run: bash tests/non_niq/test_non_niq_qa_v2_variants.sh

cd "$(dirname "$0")/../.."

fail() { echo "FAIL: $1" >&2; exit 1; }

for script in script/non_niq/non_niq_qa_v2_merchant_list.sh script/non_niq/non_niq_qa_v2_waterheater_multi.sh; do
  bash -n "$script" || fail "$script must be syntactically valid"
  src=$(cat "$script")
  grep -qF 'source "${REPO_ROOT}/script/lib/common.sh"' <<< "$src" \
    || fail "$script must source common.sh (where taxonomy_insert_log_gap_query lives)"
  grep -qF '2c.1. Mandatory durable insert log for every NEW dictionary row' <<< "$src" \
    || fail "$script's prompt must require the shared taxonomy insert log (2c.1)"
  grep -qF 'do not INSERT yet' <<< "$src" \
    || fail "$script's Step A must defer the dictionary INSERT so 2c.1 logs the one true inserted row"
  grep -qF "run_start=\$(date -u" <<< "$src" \
    || fail "$script's main() must capture run_start before dispatching the agent"
  grep -qF 'taxonomy_insert_log_gap_query "\`${PROJECT}.${dict_table}\`"' <<< "$src" \
    || fail "$script's main() must run the shared insert-log gap check against this dataset's dict_table"
  if grep -qF 'gap_count" != "0"' <<< "$src" && grep -qF 'residual_valid=false' <<< "$src"; then
    :
  else
    fail "$script's main() must block the queue signal when the gap check finds an unlogged dictionary row"
  fi
  echo "PASS: $script insert-log wiring"
done

echo "ALL TESTS PASSED"
