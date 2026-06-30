#!/usr/bin/env bash
# Verifies that env_files entries export runnable runfiles paths.
set -uo pipefail

set +e
f=bazel_tools/tools/bash/runfiles/runfiles.bash
# shellcheck disable=SC1090
# shuck: disable=C160
source "${RUNFILES_DIR:-/dev/null}/$f" 2> /dev/null ||
    source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2> /dev/null ||
    # shuck: disable=C160
    source "$0.runfiles/$f" 2> /dev/null ||
    source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2> /dev/null ||
    source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2> /dev/null ||
    {
        echo >&2 "ERROR: cannot find $f"
        exit 1
    }
# shuck: disable=C159
f=
set -e

set -o pipefail

# shuck: disable=C002
source "$1"

[[ -x "${TEST_TOOL}" ]]
[[ "$("${TEST_TOOL}")" == "env_files_test_tool" ]]
[[ "$(cat "${TEST_FILE}")" == "env_files_test_tool" ]]
[[ "$(cat "${TEST_MAIN_REPO_DIR}/env_files_test_tool_data.txt")" == "env_files_test_tool" ]]
