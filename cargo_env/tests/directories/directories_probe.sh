#!/usr/bin/env bash
# Checks that every directory exported by cargo_env exists in the runfiles.

set -euo pipefail

[[ -f "${SOURCE_DIRECTORY}/sentinel.txt" ]] || {
    echo >&2 "SOURCE_DIRECTORY does not exist: ${SOURCE_DIRECTORY}"
    exit 1
}
[[ -f "${GENERATED_DIRECTORY}/sentinel.txt" ]] || {
    echo >&2 "GENERATED_DIRECTORY does not exist: ${GENERATED_DIRECTORY}"
    exit 1
}

read -ra include_flags <<< "${CFLAGS}"
[[ "${#include_flags[@]}" -eq 2 ]]
for flag in "${include_flags[@]}"; do
    include_directory="${flag#-I}"
    [[ -f "${include_directory}/sentinel.txt" ]] || {
        echo >&2 "include directory does not exist: ${include_directory}"
        exit 1
    }
done
