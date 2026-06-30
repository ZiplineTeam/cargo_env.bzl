#!/usr/bin/env bash
# Test fixture for env_files path exports.
set -euo pipefail

readonly data_runfile="_main/cargo_env/env_files_test_tool_data.txt"

resolve_data_path() {
    if [[ -n "${RUNFILES_MANIFEST_FILE:-}" ]]; then
        grep -sm1 "^${data_runfile} " "${RUNFILES_MANIFEST_FILE}" | cut -f2- -d' '
    else
        printf '%s\n' "${RUNFILES_DIR}/${data_runfile}"
    fi
}

data_path="$(resolve_data_path)"
readonly data_path

cat "${data_path}"
