#!/usr/bin/env bash
set -uo pipefail
set +e
f=bazel_tools/tools/bash/runfiles/runfiles.bash
# shellcheck disable=SC1090
# shuck: disable=C002
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null ||
 # shellcheck disable=SC1090
 # shuck: disable=C002
 source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null ||
 # shellcheck disable=SC1090
 # shuck: disable=C002
 source "$0.runfiles/$f" 2>/dev/null ||
 # shellcheck disable=SC1090
 # shuck: disable=C002
 source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || exit 1
set -e
wrapped="$(rlocation "$1")"
"$wrapped"
