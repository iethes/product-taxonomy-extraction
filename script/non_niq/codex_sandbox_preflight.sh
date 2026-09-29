#!/usr/bin/env bash

# Source from both the direct QA runner and its queue worker. A host-wide bubblewrap
# failure must be detected before the worker claims any task.
codex_sandbox_preflight() {
  [[ "$(uname -s)" == "Linux" ]] || return 0
  command -v bwrap >/dev/null 2>&1 || return 0  # Codex may use its bundled helper.
  local error
  if ! error=$(bwrap --ro-bind / / --dev-bind /dev /dev --proc /proc -- /bin/true 2>&1); then
    echo "Codex Linux sandbox cannot start: ${error}" >&2
    echo "Repair bubblewrap/user-namespace support on this host before running QA. On Ubuntu 24.04, load the bwrap-userns-restrict AppArmor profile described at https://developers.openai.com/codex/sandboxing." >&2
    return 1
  fi
}
