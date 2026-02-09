"""Generates a Cargo environment file and wrapper scripts for cargo builds using dependencies provided by Bazel."""

load("@bazel_lib//lib:expand_template.bzl", "expand_template")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//rules/directory:providers.bzl", "DirectoryInfo")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

def _is_file_type(path):
    return type(path) == "File"

def _to_runfiles_path(path):
    """Convert execution-root path to runfiles-relative.

    Examples:
    - external/foo -> foo for external repositories
    - ../foo -> foo for generated files
    """
    if paths.starts_with(path, "external") or paths.starts_with(path, ".."):
        return path.split("/", 1)[-1]
    return path

def _make_abs_path(path):
    """Make a path absolute with $RUNFILES_DIR prefix, handling external repos."""
    if _is_file_type(path):
        path = path.path if path.is_source else path.short_path
    else:
        path = getattr(path, "path", path)

    return paths.join("$RUNFILES_DIR", _to_runfiles_path(path))

def _make_include_arg(dir):
    return "-I" + _make_abs_path(dir[DirectoryInfo])

def _make_custom_env_arg(item):
    return "export {}=\"{}\"".format(item[0], _make_abs_path(item[1].label.workspace_root or "."))

def _get_optional(optional_file):
    return [optional_file] if optional_file else []

def _cargo_env_impl(ctx):
    output = ctx.actions.declare_file("%s.env" % ctx.attr.name)
    substitutions = ctx.actions.template_dict()

    substitutions.add_joined(
        "{INCLUDES}",
        depset(ctx.attr.include_directories),
        join_with = " ",
        map_each = _make_include_arg,
    )

    optional_clang = _get_optional(ctx.file.clang)
    substitutions.add_joined(
        "{CLANG_PATH}",
        depset(optional_clang),
        join_with = "",  # dummy
        map_each = _make_abs_path,
    )

    optional_libclang = _get_optional(ctx.file.libclang)
    substitutions.add_joined(
        "{LIBCLANG_PATH}",
        depset(optional_libclang),
        join_with = "",  # dummy
        map_each = _make_abs_path,
    )

    optional_openssl_dir = _get_optional(ctx.file.openssl_dir)
    substitutions.add_joined(
        "{OPENSSL_DIR}",
        depset(optional_openssl_dir),
        join_with = "",  # dummy
        map_each = _make_abs_path,
    )

    substitutions.add_joined(
        "{CUSTOM_ENV}",
        depset(ctx.attr.env_directories.items()),
        join_with = "\n",
        map_each = _make_custom_env_arg,
    )

    ctx.actions.expand_template(
        output = output,
        template = ctx.file._template,
        computed_substitutions = substitutions,
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        files = ctx.files.include_directories + optional_clang + optional_libclang + optional_openssl_dir,
        transitive_files = depset(transitive = [target.files for target in ctx.attr.env_directories.values()]),
    )

    return [DefaultInfo(files = depset([output]), runfiles = runfiles)]

cargo_env = rule(
    implementation = _cargo_env_impl,
    attrs = {
        "clang": attr.label(
            allow_single_file = True,
            doc = "The clang binary.",
        ),
        "env_directories": attr.string_keyed_label_dict(
            default = {},
            doc = "Map of environment variable names to filegroup targets. The path will be the repo/package root of the target. Example: {\"MY_LIB_PATH\": \"@my_lib//:source_files\"}",
        ),
        "include_directories": attr.label_list(
            default = [],
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
    doc = """Generates a Cargo environment file for cargo builds.

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

def env_wrapper(name, binary, environment, visibility = None, **kwargs):
    # This is unfortunate, but `rules_shell` still uses the native
    # implementation of `sh_binary` which does not support `RunEnvironmentInfo`.
    # So we need to generate this wrapper.
    wrapped_name = "_{}_wrapped".format(name)
    expand_template(
        name = wrapped_name,
        out = wrapped_name + ".sh",
        template = "@cargo_env.bzl//cargo_env:env_wrapper.sh",
        substitutions = {
            "${BINARY_PATH}": "$(rlocationpath {})".format(binary),
            "${ENVIRONMENT_PATH}": "$(rlocationpath {})".format(environment),
        },
        data = [binary, environment],
        **kwargs
    )

    sh_binary(
        name = name,
        srcs = [wrapped_name],
        data = [binary, environment],
        deps = ["@bazel_tools//tools/bash/runfiles"],
        visibility = visibility,
        **kwargs
    )
