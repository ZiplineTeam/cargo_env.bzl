"""Generates a Cargo environment file and wrapper scripts for cargo builds using dependencies provided by Bazel."""

load("@bazel_lib//lib:expand_template.bzl", "expand_template")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:shell.bzl", "shell")
load("@bazel_skylib//rules/directory:providers.bzl", "DirectoryInfo")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

def _is_file_type(path):
    return type(path) == "File"

def _is_external_or_parent_path(path):
    return paths.starts_with(path, "external") or paths.starts_with(path, "..")

def _to_runfiles_path(path):
    """Convert execution-root path to runfiles-relative.

    Examples:
    - external/foo -> foo for external repositories
    - ../foo -> foo for generated files
    """
    return path.split("/", 1)[-1] if _is_external_or_parent_path(path) else path

def _workspace_runfiles_path(path):
    """Map a repository-relative path to its runfiles-relative path.

    Main-repository paths get the _main prefix; external and generated paths
    keep the repository-relative path after their existing prefix is removed.

    Examples:
    - pkg/include -> _main/pkg/include
    - external/repo/include -> repo/include
    - ../repo/include -> repo/include
    """
    return _to_runfiles_path(path) if _is_external_or_parent_path(path) else paths.join("_main", path)

def _file_runfiles_path(file):
    path = file.path if file.is_source else file.short_path
    return _workspace_runfiles_path(path)

def _make_abs_path(path):
    """Make a path absolute with $RUNFILES_DIR prefix, handling external repos."""
    if _is_file_type(path):
        return paths.join("$RUNFILES_DIR", _file_runfiles_path(path))

    path = getattr(path, "path", path)
    return paths.join("$RUNFILES_DIR", _to_runfiles_path(path))

def _directory_runfiles_path(directory):
    """Convert a DirectoryInfo execution-root path to a runfiles-relative path."""
    path = directory.path
    if paths.starts_with(path, "bazel-out"):
        parts = path.split("/")
        if len(parts) < 4 or parts[0] != "bazel-out" or not parts[1] or parts[2] != "bin":
            fail("Unsupported generated DirectoryInfo path: {}".format(path))
        path = "/".join(parts[3:])
        if not path:
            fail("Generated DirectoryInfo path has no package-relative path: {}".format(directory.path))

    return _workspace_runfiles_path(path)

def _make_include_arg(dir):
    return "-I" + paths.join("$RUNFILES_DIR", _directory_runfiles_path(dir[DirectoryInfo]))

def _make_export_env_arg(env_name, value):
    """Format an export statement; value must already be shell-quoted."""
    return "export {}={}".format(env_name, value)

def _make_custom_env_arg(item):
    env_name, target = item
    if DirectoryInfo in target:
        path = paths.join("$RUNFILES_DIR", _directory_runfiles_path(target[DirectoryInfo]))
    else:
        # Targets without DirectoryInfo use their repository root.
        path = _make_abs_path(target.label.workspace_root or ".")
    return _make_export_env_arg(env_name, '"{}"'.format(path))

def _get_single_file(target, env_name):
    files = target[DefaultInfo].files.to_list()
    if len(files) != 1:
        fail("env_files entry {} must provide exactly one file, got {}".format(env_name, len(files)))
    return files[0]

def _make_file_env_arg(item):
    env_name, target = item
    path = _make_abs_path(_get_single_file(target, env_name))
    return _make_export_env_arg(env_name, '"{}"'.format(path))

def _make_env_arg(item):
    return _make_export_env_arg(item[0], shell.quote(item[1]))

def _check_unique_env_names(envs):
    seen = {}
    for source, env in envs:
        for env_name in env:
            if env_name in seen:
                fail("{} is set in both {} and {}".format(env_name, seen[env_name], source))
            seen[env_name] = source

def _cargo_env_impl(ctx):
    deprecated_env = {
        "CLANG_PATH": ctx.attr.clang,
        "LIBCLANG_PATH": ctx.attr.libclang,
        "OPENSSL_DIR": ctx.attr.openssl_dir,
    }
    deprecated_env = {env_name: target for env_name, target in deprecated_env.items() if target}

    _check_unique_env_names([
        ("env", ctx.attr.env),
        ("env_directories", ctx.attr.env_directories),
        ("env_files", ctx.attr.env_files),
        ("deprecated attributes", deprecated_env),
    ])

    env_file_items = ctx.attr.env_files.items() + deprecated_env.items()
    env_file_targets = [target for _, target in env_file_items]
    env_file_outputs = [
        _get_single_file(target, env_name)
        for env_name, target in env_file_items
    ]

    output = ctx.actions.declare_file("%s.env" % ctx.attr.name)
    substitutions = ctx.actions.template_dict()

    substitutions.add_joined(
        "{INCLUDES}",
        depset(ctx.attr.include_directories),
        join_with = " ",
        map_each = _make_include_arg,
    )

    custom_env = [
        _make_env_arg(item)
        for item in ctx.attr.env.items()
    ] + [
        _make_custom_env_arg(item)
        for item in ctx.attr.env_directories.items()
    ] + [
        _make_file_env_arg(item)
        for item in env_file_items
    ]
    substitutions.add("{CUSTOM_ENV}", "\n".join(custom_env))

    ctx.actions.expand_template(
        output = output,
        template = ctx.file._template,
        computed_substitutions = substitutions,
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        files = ctx.files.include_directories + env_file_outputs,
        # TODO: Consider merging default_runfiles for env_directories too.
        transitive_files = depset(transitive = [target.files for target in ctx.attr.env_directories.values()]),
    )
    runfiles = runfiles.merge_all([
        target[DefaultInfo].default_runfiles
        for target in env_file_targets
    ])

    return [DefaultInfo(files = depset([output]), runfiles = runfiles)]

cargo_env = rule(
    implementation = _cargo_env_impl,
    attrs = {
        "clang": attr.label(
            allow_single_file = True,
            doc = 'Deprecated: use env_files = {"CLANG_PATH": ...} instead.',
        ),
        "env": attr.string_dict(
            default = {},
            doc = "Map of environment variable names to literal values.",
        ),
        "env_directories": attr.string_keyed_label_dict(
            default = {},
            doc = "Map of environment variable names to targets. Uses DirectoryInfo.path when available; otherwise uses the target repository root. Example: {\"MY_INCLUDE_PATH\": \"@my_package//:include_directory\"}",
        ),
        "env_files": attr.string_keyed_label_dict(
            allow_files = True,
            default = {},
            doc = "Map of environment variable names to targets that provide exactly one file. The file path is resolved through runfiles.",
        ),
        "include_directories": attr.label_list(
            default = [],
            providers = [DirectoryInfo],
            doc = "Include directories for C++ to find.",
        ),
        "libclang": attr.label(
            allow_single_file = True,
            doc = 'Deprecated: use env_files = {"LIBCLANG_PATH": ...} instead.',
        ),
        "openssl_dir": attr.label(
            allow_single_file = True,
            doc = 'Deprecated: use env_files = {"OPENSSL_DIR": ...} instead.',
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
        include_directories = ["@my_library//:headers_directory"],
        env = {
            "SOME_VALUE": "value",
        },
        env_directories = {
            "SOME_PACKAGE_PATH": "@some_package//:source_files",
        },
        env_files = {
            "SOME_FILE_PATH": "@some_package//:generated_file",
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
