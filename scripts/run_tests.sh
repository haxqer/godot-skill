#!/usr/bin/env bash
# Run every test module and fail if any of them fails.
#
# Each tests/test_*.py exits non-zero on failure, but a plain `for` loop would
# swallow that, so results are collected and reported here. Tests that need a
# local `godot` CLI skip themselves with a notice when it is missing, so this is
# safe to run without Godot installed — it just covers less.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! command -v "${GODOT_BIN:-godot}" >/dev/null 2>&1; then
  echo "warning: ${GODOT_BIN:-godot} not found on PATH; Godot-dependent tests will skip" >&2
fi

passed=()
failed=()

for test_file in tests/test_*.py; do
  echo "=== ${test_file}"
  if python3 "${test_file}"; then
    passed+=("${test_file}")
  else
    failed+=("${test_file}")
  fi
done

echo
echo "${#passed[@]} passed, ${#failed[@]} failed"

if [[ ${#failed[@]} -gt 0 ]]; then
  printf 'FAILED: %s\n' "${failed[@]}" >&2
  exit 1
fi
