# cargo_env.bzl

Cargo is not a hermetic build system.
If some dependencies are provided by Bazel, we need to tell cargo where to find them.
We do this by creating an environment file that sets the environment variables for cargo to find these dependencies.

This environment file can be used either by wrapping binaries such as `cargo` or `rustc` with our `env_wrapper` rule.
Combine this with <https://github.com/buildbuddy-io/bazel_env.bzl> to make the wrapper binaries available on the `PATH`.

## Usage

See the [examples](examples) for a usage example.
