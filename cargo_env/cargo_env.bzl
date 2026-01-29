"""Generates a Cargo environment file for cargo builds using dependencies provided by Bazel."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//rules/directory:providers.bzl", "DirectoryInfo")

def _to_runfiles_path(path):
    """Convert execution-root path to runfiles-relative (external/foo -> ../foo)."""
    if paths.starts_with(path, "external"):
        return paths.join("..", *path.split("/")[1:])
    return path

def _make_abs_path(path):
    """Make a path absolute with $PWD prefix, handling external repos."""
    return paths.join("$PWD", _to_runfiles_path(path))

def _cargo_env_impl(ctx):
    output = ctx.actions.declare_file("%s.env" % ctx.attr.name)
    substitutions = ctx.actions.template_dict()

    include_directories = [
        "-I" + _make_abs_path(dir[DirectoryInfo].path)
        for dir in ctx.attr.include_directories
    ]
    substitutions.add("{INCLUDES}", " ".join(include_directories))

    clang_path = _make_abs_path(ctx.file.clang.path) if ctx.file.clang else ""
    substitutions.add("{CLANG_PATH}", clang_path)

    if not ctx.file.libclang:
        fail("libclang not provided")
    substitutions.add("{LIBCLANG_PATH}", _make_abs_path(ctx.file.libclang.path))

    openssl_dir = _make_abs_path(ctx.file.openssl_dir.short_path) if ctx.file.openssl_dir else ""
    substitutions.add("{OPENSSL_DIR}", openssl_dir)

    # Generate custom environment variables from env_directories
    custom_env_lines = [
        "export {}=\"{}\"".format(name, _make_abs_path(target.label.workspace_root or "."))
        for name, target in ctx.attr.env_directories.items()
    ]
    env_directory_files = [
        f
        for target in ctx.attr.env_directories.values()
        for f in target.files.to_list()
    ]

    substitutions.add("{CUSTOM_ENV}", "\n".join(custom_env_lines))

    ctx.actions.expand_template(
        output = output,
        template = ctx.file._template,
        computed_substitutions = substitutions,
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        files = ctx.files.include_directories +
                ([ctx.file.clang] if ctx.file.clang else []) +
                ([ctx.file.libclang] if ctx.file.libclang else []) +
                ([ctx.file.openssl_dir] if ctx.file.openssl_dir else []) +
                env_directory_files,
    )

    return [DefaultInfo(executable = output, runfiles = runfiles)]

cargo_env = rule(
    implementation = _cargo_env_impl,
    attrs = {
        "clang": attr.label(
            allow_single_file = True,
            doc = "The clang binary.",
        ),
        "env_directories": attr.string_keyed_label_dict(
            doc = "Map of environment variable names to filegroup targets. The path will be the repo/package root of the target. Example: {\"MY_LIB_PATH\": \"@my_lib//:source_files\"}",
        ),
        "include_directories": attr.label_list(
            mandatory = True,
            providers = [DirectoryInfo],
            doc = "Include directories for C++ to find.",
        ),
        "libclang": attr.label(
            allow_single_file = True,
            doc = "libclang shared library (libclang.so).",
        ),
        "openssl_dir": attr.label(
            allow_single_file = True,
            doc = "The OpenSSL directory.",
        ),
        "_template": attr.label(
            allow_single_file = True,
            default = ":template.env",
        ),
    },
    executable = True,
    doc = """Generates a Cargo environment file for cargo builds using dependencies provided by Bazel.

    An example of using this rule is:
    ```
    cargo_env(
        name = "cargo_env",
        clang = "@llvm_toolchain_llvm//:bin/clang",
        include_directories = ["@my_library//:headers_directory"],
        libclang = "@llvm_toolchain_llvm//:lib/libclang.so",
        openssl_dir = "@openssl//:gen_dir",
        env_directories = {
            "SOME_PACKAGE_PATH": "@some_package//:source_files",
        },
    )
    ```
    """,
)
