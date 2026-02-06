#!/usr/bin/env bash
# --- begin runfiles.bash initialization v3 ---
# Copy-pasted from the Bazel Bash runfiles library v3.
set -uo pipefail
set +e
f=bazel_tools/tools/bash/runfiles/runfiles.bash
# shellcheck disable=SC1090
source "${RUNFILES_DIR:-/dev/null}/$f" 2> /dev/null ||
    source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2> /dev/null ||
    source "$0.runfiles/$f" 2> /dev/null ||
    source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2> /dev/null ||
    source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2> /dev/null ||
    {
        echo >&2 "ERROR: cannot find $f"
        exit 1
    }
f=
set -e
# --- end runfiles.bash initialization v3 ---

set -o pipefail

# When running under `bazel run`, `RUNFILES_DIR` is not set, but `PWD` refers
# to the execution root of the binary we are executing. When running standalone
# from the wrapper created by `bazel_env`, `PWD` refers to the workspace root,
# but `RUNFILES_DIR` is set correctly.
#
# We need this variable because the `export` lines in the ${ENVIRONMENT_PATH} file
# refer to it.
RUNFILES_DIR=${RUNFILES_DIR:-${PWD}/..}

# shellcheck source=/dev/null
source "$(rlocation "${ENVIRONMENT_PATH}")"
exec "$(rlocation "${BINARY_PATH}")" "$@"
