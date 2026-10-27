#!/usr/bin/env bash
# Checks that cargo_env's generated env file exports usable values and paths.

set -uo pipefail
set +e
f=bazel_tools/tools/bash/runfiles/runfiles.bash
# shellcheck disable=SC1090
# shuck: disable=C160
source "${RUNFILES_DIR:-/dev/null}/$f" 2> /dev/null ||
    source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2> /dev/null ||
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

RUNFILES_DIR=${RUNFILES_DIR:-${TEST_SRCDIR}}
export RUNFILES_DIR

environment_file="$(rlocation "$1")"
# shellcheck source=/dev/null
source "${environment_file}"

expected_literal="cost \$5, \"double quotes\", and 'single quotes'"
[[ "${CUSTOM_LITERAL}" == "${expected_literal}" ]]

[[ -d "${CUSTOM_DIRECTORY}" ]]
[[ -f "${CUSTOM_DIRECTORY}/sentinel.txt" ]]

filegroup_file="${RUNFILES_DIR}/_main/cargo_env/tests/testdata/filegroup/sentinel.txt"
[[ -f "${filegroup_file}" ]]
# shuck: disable=C156
filegroup_root="${FILEGROUP_ROOT%/.}"
[[ "${filegroup_root}" -ef "${RUNFILES_DIR}" ]]
case "${filegroup_file}" in
    "${filegroup_root}"/*) ;;
    *)
        echo >&2 "filegroup file is not beneath FILEGROUP_ROOT: ${filegroup_file}"
        exit 1
        ;;
esac
