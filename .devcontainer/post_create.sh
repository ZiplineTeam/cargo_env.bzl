#!/usr/bin/env bash

# Setup script for devcontainer
# This script runs once when the container is first created

set -euxo pipefail

sudo mkdir -p "$HOME"/.cache
sudo chown -R "$USER":"$USER" "$HOME"/.cache

cd examples
direnv allow .envrc
direnv exec . bazel run //tools:bazel_env
direnv exec . bazel run //tools:cargo_env

echo "postCreateCommand setup complete!"
