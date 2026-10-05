#!/usr/bin/env bash
# Headless test entry point for humans, CI and coding agents.
#
#   tools/run_tests.sh                                  # import + script lint + unit tests + 100-turn headless sim
#   tools/run_tests.sh --suite=world_state              # forward filters to the unit runner
#   tools/run_tests.sh --suite=engine --filter=async
#   GODOT=/opt/godot/Godot_v4.7.2-stable_linux.x86_64 tools/run_tests.sh
#
# Fails if any step exits non-zero OR if Godot prints a script/parse error,
# because GDScript runtime errors do not abort the process by themselves.
set -euo pipefail

GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${ROOT}/tests/output"
mkdir -p "${LOG_DIR}"

if ! command -v "${GODOT}" >/dev/null 2>&1; then
  echo "Godot executable not found (looked for '${GODOT}'). Set GODOT=/path/to/godot (4.7+)." >&2
  exit 2
fi

VERSION="$("${GODOT}" --version 2>/dev/null | tail -n 1)"
echo "== Godot: ${VERSION}"
# The project is made with Godot 4.7.2 (project.godot, the .uid files, CI and the web export).
IFS=. read -r MAJOR MINOR _ <<<"${VERSION}"
if ! [[ "${MAJOR}" =~ ^[0-9]+$ && "${MINOR}" =~ ^[0-9]+$ ]] || (( MAJOR < 4 || (MAJOR == 4 && MINOR < 7) )); then
  echo "This project needs Godot 4.7 or newer (got '${VERSION}'). Set GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64." >&2
  exit 2
fi
echo "== Importing project (builds the class_name cache on fresh clones)"
"${GODOT}" --headless --path "${ROOT}" --import >"${LOG_DIR}/import.log" 2>&1 || true

run_step() {
  local name="$1"
  shift
  local log="${LOG_DIR}/${name}.log"
  echo
  echo "== ${name}"
  set +e
  "${GODOT}" --headless --path "${ROOT}" "$@" 2>&1 | tee "${log}"
  local status=${PIPESTATUS[0]}
  set -e
  if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "${log}"; then
    echo "!! ${name}: script errors detected in output (see ${log})" >&2
    return 1
  fi
  return "${status}"
}

status=0
run_step check_scripts --script res://tools/check_scripts.gd || status=1
run_step unit_tests --script res://tests/run_tests.gd -- "$@" || status=1
if [[ $# -eq 0 ]]; then
  run_step headless_sim --script res://tests/headless_sim_test.gd || status=1
fi

echo
if [[ ${status} -eq 0 ]]; then
  echo "ALL CHECKS PASSED"
else
  echo "CHECKS FAILED" >&2
fi
exit "${status}"
