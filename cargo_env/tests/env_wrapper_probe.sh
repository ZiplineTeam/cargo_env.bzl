#!/usr/bin/env bash
# Verifies the environment and arguments received through env_wrapper.

set -euo pipefail

expected_literal="cost \$5, \"double quotes\", and 'single quotes'"
[[ "${CUSTOM_LITERAL}" == "${expected_literal}" ]]
[[ -d "${CUSTOM_DIRECTORY}" ]]
[[ -f "${CUSTOM_DIRECTORY}/sentinel.txt" ]]
[[ -f "${GENERATED_DIRECTORY}/sentinel.txt" ]]
[[ -f "${SOURCE_DIRECTORY}/testdata/directory/sentinel.txt" ]]

read -ra include_flags <<< "${CFLAGS}"
[[ "${#include_flags[@]}" -eq 3 ]]

has_include_directory() {
    local expected_directory="$1"
    local flag
    for flag in "${include_flags[@]}"; do
        if [[ "${flag}" == "-I${expected_directory}" ]]; then
            return 0
        fi
    done
    return 1
}

for directory in "${CUSTOM_DIRECTORY}" "${GENERATED_DIRECTORY}" "${SOURCE_DIRECTORY}"; do
    has_include_directory "${directory}"
done

[[ "$#" -eq 2 ]]
[[ "$1" == "argument with spaces" ]]
[[ "$2" == "second argument" ]]
