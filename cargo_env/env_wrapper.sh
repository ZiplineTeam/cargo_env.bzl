#!/usr/bin/env bash
# Sources the Cargo environment and runs the wrapped binary.
# The rules_shell Bash launcher provides rlocation.

set -euo pipefail

# shellcheck source=/dev/null
source "$(rlocation "${ENVIRONMENT_PATH}")"
exec "$(rlocation "${BINARY_PATH}")" "$@"
