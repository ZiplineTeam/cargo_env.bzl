#!/usr/bin/env bash
# Runs the env_wrapper launcher and verifies it resolves runfiles.

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

wrapped_binary="$(rlocation "$1")"
"${wrapped_binary}" "argument with spaces" "second argument"
