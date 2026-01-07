# cargo_env.bzl

Cargo is not a hermetic build system.
If some dependencies are removed from the system and provided them via Bazel, we need to tell cargo where to find them.
We do this by creating a `.envrc.cargo` file with paths to the Bazel-provided dependencies.
Combined with <https://github.com/buildbuddy-io/bazel_env.bzl>, this allows cargo to find dependencies provided by Bazel.

## Usage

See the [examples](examples) for a usage example.
