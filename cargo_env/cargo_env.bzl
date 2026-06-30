"""Generates a Cargo environment file and wrapper scripts for cargo builds using dependencies provided by Bazel."""

load("@bazel_lib//lib:expand_template.bzl", "expand_template")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//rules/directory:providers.bzl", "DirectoryInfo")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

def _is_file_type(path):
    return type(path) == "File"

def _to_runfiles_path(path, is_main_repo_file = False):
    """Convert execution-root path to runfiles-relative.

    Examples:
    - foo -> _main/foo for files in the main repository
    - external/foo -> foo for external repositories
    - ../foo -> foo for generated files
    """
    if paths.starts_with(path, "external") or paths.starts_with(path, ".."):
        return path.split("/", 1)[-1]
    if is_main_repo_file:
        return paths.join("_main", path)
    return path

def _make_abs_path(path):
    """Make a path absolute with $RUNFILES_DIR prefix, handling external repos."""
    return paths.join("$RUNFILES_DIR", _make_runfiles_path(path))

def _make_runfiles_path(path):
    """Make a path relative to the runfiles root."""
    is_main_repo_file = False
    if _is_file_type(path):
        is_main_repo_file = path.owner and path.owner.workspace_root == ""
        path = path.path if path.is_source else path.short_path
    else:
        path = getattr(path, "path", path)

    return _to_runfiles_path(path, is_main_repo_file)

def _make_include_arg(dir):
    return "-I" + _make_abs_path(dir[DirectoryInfo])

def _validate_relative_subpath(env_name, subpath):
    if paths.is_absolute(subpath) or subpath == ".." or paths.starts_with(subpath, "../") or "/../" in subpath:
        fail("env_directory_subpaths entry for {} must be a relative path within the env_directories target".format(env_name))

def _make_directory_env_arg(item, subpaths):
    env_name, target = item
    path = target.label.workspace_root or "."
    if env_name in subpaths:
        subpath = subpaths[env_name]
        _validate_relative_subpath(env_name, subpath)
        if not target.label.workspace_root:
            path = "_main"
        path = paths.join(path, subpath)
    return "export {}=\"{}\"".format(env_name, _make_abs_path(path))

def _make_file_env_arg(item):
    runfiles_path = _make_runfiles_path(item[1])
    return "export {}=\"$(rlocation \"{}\" 2> /dev/null || printf '%s\\n' \"{}\")\"".format(
        item[0],
        runfiles_path,
        paths.join("$RUNFILES_DIR", runfiles_path),
    )

def _get_env_file(target, env_name):
    if DefaultInfo in target:
        executable = target[DefaultInfo].files_to_run.executable
        if executable:
            return executable

    files = target.files.to_list()
    if len(files) != 1:
        fail("env_files entry for {} must provide exactly one file, but {} files were found".format(env_name, len(files)))
    return files[0]

def _get_env_file_runfiles(targets):
    runfiles = []
    for target in targets:
        if DefaultInfo in target:
            runfiles.append(target[DefaultInfo].default_runfiles)
    return runfiles

def _get_optional(optional_file):
    return [optional_file] if optional_file else []

def _cargo_env_impl(ctx):
    output = ctx.actions.declare_file("%s.env" % ctx.attr.name)
    substitutions = ctx.actions.template_dict()

    for env_name in ctx.attr.env_directory_subpaths:
        if env_name not in ctx.attr.env_directories:
            fail("env_directory_subpaths entry for {} must have a matching env_directories entry".format(env_name))

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

    env_file_entries = [
        (env_name, _get_env_file(target, env_name))
        for env_name, target in ctx.attr.env_files.items()
    ]
    custom_env = [
        _make_directory_env_arg(item, ctx.attr.env_directory_subpaths)
        for item in ctx.attr.env_directories.items()
    ] + [
        _make_file_env_arg(item)
        for item in env_file_entries
    ]
    substitutions.add("{CUSTOM_ENV}", "\n".join(custom_env))

    ctx.actions.expand_template(
        output = output,
        template = ctx.file._template,
        computed_substitutions = substitutions,
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        files = ctx.files.include_directories + optional_clang + optional_libclang + optional_openssl_dir + [file for _, file in env_file_entries],
        transitive_files = depset(transitive = [target.files for target in ctx.attr.env_directories.values()]),
    ).merge_all(
        _get_env_file_runfiles(ctx.attr.env_files.values()),
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
        "env_directory_subpaths": attr.string_dict(
            default = {},
            doc = "Map of env_directories environment variable names to relative subpaths under their target repository root. Example: {\"PROTOC_INCLUDE\": \"src\"}",
        ),
        "env_files": attr.string_keyed_label_dict(
            allow_files = True,
            cfg = "exec",
            default = {},
            doc = "Map of environment variable names to single file targets in the exec configuration. The path will be the file path. Example: {\"MY_TOOL\": \"@my_tool//:binary\"}",
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
        env_directory_subpaths = {
            "SOME_PACKAGE_PATH": "include",
        },
        env_files = {
            "SOME_TOOL": "@some_tool//:binary",
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
