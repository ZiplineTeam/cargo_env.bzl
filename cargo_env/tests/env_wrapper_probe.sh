#!/usr/bin/env bash
# Verifies the environment and arguments received through env_wrapper.

set -euo pipefail

expected_literal="cost \$5, \"double quotes\", 'single quotes', and {INCLUDES}"
[[ "${CUSTOM_LITERAL}" == "${expected_literal}" ]]
[[ -d "${CUSTOM_DIRECTORY}" ]]
[[ -f "${CUSTOM_DIRECTORY}/sentinel.txt" ]]
[[ -f "${GENERATED_DIRECTORY}/sentinel.txt" ]]
[[ -f "${SOURCE_DIRECTORY}/testdata/directory/sentinel.txt" ]]
[[ -f "${GENERATED_FILE}" ]]
[[ -f "${SOURCE_FILE}" ]]

# This generated dependency is supplied only by env_directories default runfiles.
[[ -f "${FILEGROUP_ROOT}/_main/cargo_env/tests/runtime_only/sentinel.txt" ]]

[[ "${CFLAGS}" == "${CXXFLAGS}" ]]
directory_flags=("-I${GENERATED_DIRECTORY}" "-I${CUSTOM_DIRECTORY}" "-I${SOURCE_DIRECTORY}")
include_flags=" ${CFLAGS} "
[[ "${include_flags}" == *" ${directory_flags[*]} "* ]]
for flag in "${directory_flags[@]}"; do
    remaining_flags=" ${include_flags#*" ${flag} "}"
    [[ "${remaining_flags}" != *" ${flag} "* ]]
done

[[ "$#" -eq 2 ]]
[[ "$1" == "argument with spaces" ]]
[[ "$2" == "second argument" ]]
