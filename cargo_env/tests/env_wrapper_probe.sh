#!/usr/bin/env bash
# Verifies the environment and arguments received through env_wrapper.

set -euo pipefail

expected_literal="cost \$5, \"double quotes\", and 'single quotes'"
[[ "${CUSTOM_LITERAL}" == "${expected_literal}" ]]
[[ -d "${CUSTOM_DIRECTORY}" ]]
[[ -f "${CUSTOM_DIRECTORY}/sentinel.txt" ]]
[[ "$#" -eq 2 ]]
[[ "$1" == "argument with spaces" ]]
[[ "$2" == "second argument" ]]
