#!/usr/bin/env bash
# Checks that cargo_env's generated env file exports usable values and paths.

set -euo pipefail

environment_file="$(rlocation "$1")"
# shellcheck source=/dev/null
source "${environment_file}"

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

# shellcheck source=/dev/null
source "$(rlocation "$2")"
[[ "${CFLAGS}" == "${CXXFLAGS}" ]]

external_headers=("${RUNFILES_DIR}"/*/include/cargo_env_source.h)
generated_headers=("${RUNFILES_DIR}"/*/_virtual_includes/*/probe/cargo_env_generated.h)
external_include="${external_headers[0]%/*}"
generated_include="${generated_headers[0]%/probe/cargo_env_generated.h}"
local_include="${RUNFILES_DIR}/_main/cargo_env/tests/testdata/local_headers"

[[ -f "${external_headers[0]}" && -f "${generated_headers[0]}" ]]

include_flags=" ${CFLAGS} "
[[ "${include_flags}" == *" -I${CUSTOM_DIRECTORY} "* ]]
[[ "${include_flags}" == *" -isystem${local_include} "* ]]
# When both directories are system includes, the local one comes first.
[[ "${include_flags}" == *" -isystem${local_include} "*"-isystem${external_include} "* ||
    "${include_flags}" == *" -I${external_include} "* ]]
[[ "${include_flags}" == *" -I${generated_include} "* ||
    "${include_flags}" == *" -isystem${generated_include} "* ]]
