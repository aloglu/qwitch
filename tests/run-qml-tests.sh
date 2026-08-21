#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_config="$(mktemp -d -t qwitch-qml-tests.XXXXXX)"
trap 'rm -rf -- "$test_config"' EXIT

cp "$project_dir/Panel.qml" "$project_dir/Model.js" "$test_config/"
cp "$project_dir/tests/qml/shell.qml" "$test_config/"
cp -a /usr/share/omarchy/shell/Commons /usr/share/omarchy/shell/Ui "$test_config/"

set +e
output="$(timeout 15s quickshell --path "$test_config/shell.qml" --no-color 2>&1)"
status=$?
set -e

printf '%s\n' "$output"

if [[ $status -ne 0 ]] || grep -q "QWITCH_QML_TESTS_FAILED" <<<"$output" \
    || ! grep -q "QWITCH_QML_TESTS_PASSED" <<<"$output"; then
  exit 1
fi
