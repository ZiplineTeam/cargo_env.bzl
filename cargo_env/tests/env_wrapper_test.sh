#!/usr/bin/env bash
# Runs the env_wrapper launcher and verifies it resolves runfiles.

set -euo pipefail

wrapped_binary="$(rlocation "$1")"
"${wrapped_binary}" "argument with spaces" "second argument"

# Exercise standalone discovery without the outer test launcher's environment.
standalone_wrapper="${TEST_TMPDIR}/wrapper"
ln -s "${wrapped_binary}" "${standalone_wrapper}"
ln -s "${RUNFILES_DIR}" "${standalone_wrapper}.runfiles"
(
    cd "${TEST_TMPDIR}"
    env -i PATH="${PATH}" "${standalone_wrapper}" "argument with spaces" "second argument"
)
