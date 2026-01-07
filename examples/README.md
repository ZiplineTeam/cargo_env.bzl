# Cargo Env Examples

This folder contains examples of how to use the `cargo_env` rule.

## Usage

All dependencies are provided by Bazel, so you can run all tests using the following command:

```bash
bazel test //...
```

To make this work with `cargo`, you need to prepare your environment to use the `bazel_env` and our `cargo_env` rule.

```bash
bazel run //tools:bazel_env  # To setup bazel_env which provides a cargo binary
bazel run //tools:cargo_env  # To setup cargo_env which provides cargo dependencies not available in the system
direnv allow .envrc  # To allow the environment to be used by cargo
```

Now you can use `cargo` as usual:

```bash
cargo test
```

> [!NOTE]
> We don't have `cargo` not any of the rust dependencies installed in the system.
> All of these dependencies are provided by Bazel and `bazel_env` and `cargo_env` make them available to `cargo`.
