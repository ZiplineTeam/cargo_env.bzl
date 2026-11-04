# Cargo_env.bzl

Cargo is not a hermetic build system.
If some dependencies are provided by Bazel, we need to tell cargo where to find them.
We do this by creating an environment file that sets the environment variables for cargo to find these dependencies.

This environment file can be used either by wrapping binaries such as `cargo` or `rustc` with our `env_wrapper` rule.
Combine this with <https://github.com/buildbuddy-io/bazel_env.bzl> to make the wrapper binaries available on the `PATH`.
Find more examples on how to use `bazel_env.bzl` in <https://github.com/hofbi/bazel-ide>.

## Usage

See our [examples](./examples/) for how to use this with [rules_rust](https://github.com/bazelbuild/rules_rust) and [rules_rs](https://github.com/hermeticbuild/rules_rs).

## Runtime inputs and repository caching

Cargo and its build scripts open files outside Bazel actions. With
`--experimental_remote_repo_contents_cache`, declaring a source file as a
runfile alone can leave its contents virtual. `cargo_env` therefore adds generated
symlink artifacts for every declared external source runtime file. The aliases
retain the original include and runtime paths, cover resources without header
extensions, and do not copy their contents. Dependency default runfiles and
runfiles symlink targets are included. Generated files and directory artifacts
remain generated inputs and are not flattened into source aliases.

This adds one symlink action per external source runtime file. Setting
`materialize_runtime_inputs = False` disables these aliases when the caller can
guarantee that its dependencies are already materialized. It does not make
undeclared files available.

For the standard `@rules_rust//tools/upstream_wrapper:cargo` binary,
`env_wrapper` also declares the selected Rust toolchain's complete runtime files.
This requires the public `current_rust_toolchain` alias in rules_rust 0.75.0 or
newer, or the equivalent API supplied by rules_rs. Set `rust_runtime = False` on
`env_wrapper` to retain the previous integration for older or custom toolchains.
Other wrapped commands keep their existing toolchain behavior.

## Rust linker policy

`cargo_env(linker_mode = "auto")` selects configured Clang and LLD for Cargo on
`x86_64-unknown-linux-gnu` when `clang` uses the recognized
`@llvm_toolchain_llvm//:bin/clang` layout. That layout also supplies resource
headers from the same repository's `:include` target. Other layouts and
platforms keep their existing linker configuration. Configurable `clang` labels
need explicit `clang_runtime` inputs and an explicit linker mode when desired.

The linker shim is named `clang` so rustc selects the correct linker flavor. It
uses the matching declared `ld.lld` from the selected C++ toolchain. This policy
uses the configured LLVM distribution rather than Rust's bundled linker helpers;
it does not restore those helpers to the Rust sysroot.

An existing `CARGO_TARGET_<TRIPLE>_LINKER` value, including an explicitly empty
value, is preserved. Cargo command-line `--config` overrides also take precedence.
The generated default is an environment variable, so it takes precedence over
linker values in Cargo configuration files. Use `linker_mode = "preserve"` if
`.cargo/config.toml` or another Cargo configuration file should choose the linker.
This is an intentional linker policy, not a transparent configuration fallback.

`linker_mode = "clang_lld"` explicitly requests this mode for nonstandard labels.
It currently supports Linux x86_64 and requires a matching C++ toolchain with
exactly one declared `ld.lld` beside the configured Clang. `clang_runtime` can
supply extra runtime inputs for those labels. Unsupported explicit configurations
fail during analysis rather than silently choosing an unrelated system linker.
