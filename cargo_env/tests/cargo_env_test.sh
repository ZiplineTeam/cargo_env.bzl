#!/usr/bin/env bash
# Checks that cargo_env's generated env file exports usable values and paths.

set -euo pipefail

environment_file="$(rlocation "$1")"
# shellcheck source=/dev/null
source "${environment_file}"

expected_literal="cost \$5, \"double quotes\", and 'single quotes'"
[[ "${CUSTOM_LITERAL}" == "${expected_literal}" ]]

[[ -d "${CUSTOM_DIRECTORY}" ]]
[[ -f "${CUSTOM_DIRECTORY}/sentinel.txt" ]]
[[ -f "${GENERATED_DIRECTORY}/sentinel.txt" ]]
[[ -f "${SOURCE_DIRECTORY}/testdata/directory/sentinel.txt" ]]
[[ -f "${GENERATED_FILE}" ]]
[[ -f "${SOURCE_FILE}" ]]

# This generated dependency is supplied only by env_directories default runfiles.
[[ -f "${FILEGROUP_ROOT}/_main/cargo_env/tests/runtime_only/sentinel.txt" ]]

filegroup_file="${RUNFILES_DIR}/_main/cargo_env/tests/testdata/filegroup/sentinel.txt"
[[ -f "${filegroup_file}" ]]
filegroup_runfiles_root="${FILEGROUP_ROOT%/.}"
[[ "${filegroup_runfiles_root}" -ef "${RUNFILES_DIR}" ]]
case "${filegroup_file}" in
    "${filegroup_runfiles_root}"/*) ;;
    *)
        echo >&2 "filegroup file is not beneath FILEGROUP_ROOT: ${filegroup_file}"
        exit 1
        ;;
esac
