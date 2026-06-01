# Cargo Env Examples

This folder contains examples of how to use the `cargo_env` rule with [rules_rust](https://github.com/bazelbuild/rules_rust) and [rules_rs](https://github.com/hermeticbuild/rules_rs).
Usage is as documented below for both examples in the respective subfolders.

## Usage

All dependencies are provided by Bazel, so you can run all tests using the following command:

```shell
bazel test //...
```

To make this work with `cargo`, you need to prepare your environment to use the `bazel_env` and our `cargo_env` rule.

```shell
bazel run //tools:bazel_env # To setup bazel_env which provides the cargo binary wrapped with the cargo_env environment variables
direnv allow .envrc         # To allow the environment to be used by cargo
```

Now you can use `cargo` as usual:

```shell
cargo test
```

> [!NOTE]
> We don't have `cargo` not any of the rust dependencies installed in the system.
> All of these dependencies are provided by Bazel and `bazel_env` and `cargo_env` make them available to `cargo`.
