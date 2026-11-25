"""Generates a Cargo environment file and wrapper scripts for cargo builds using dependencies provided by Bazel."""

load("@bazel_lib//lib:expand_template.bzl", "expand_template")
load("@bazel_lib//lib:paths.bzl", "to_rlocation_path")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:shell.bzl", "shell")
load("@bazel_skylib//rules/directory:providers.bzl", "DirectoryInfo")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

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
        path = paths.join("$RUNFILES_DIR", _to_runfiles_path(target.label.workspace_root or "."))
    return _make_export_env_arg(env_name, '"{}"'.format(path))

def _get_single_file(target, env_name):
    files = target[DefaultInfo].files.to_list()
    if len(files) != 1:
        fail("env_files entry {} must provide exactly one file, got {}".format(env_name, len(files)))
    return files[0]

def _make_file_env_arg(ctx, env_name, file):
    path = paths.join("$RUNFILES_DIR", to_rlocation_path(ctx, file))
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
    _check_unique_env_names([
        ("env", ctx.attr.env),
        ("env_directories", ctx.attr.env_directories),
        ("env_files", ctx.attr.env_files),
    ])

    env_files = {
        env_name: _get_single_file(target, env_name)
        for env_name, target in ctx.attr.env_files.items()
    }

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
        _make_file_env_arg(ctx, env_name, file)
        for env_name, file in env_files.items()
    ]
    substitutions.add("{CUSTOM_ENV}", "\n".join(custom_env))

    ctx.actions.expand_template(
        output = output,
        template = ctx.file._template,
        computed_substitutions = substitutions,
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        files = ctx.files.include_directories + env_files.values(),
        transitive_files = depset(transitive = [target.files for target in ctx.attr.env_directories.values()]),
    )

    # Directory targets may carry runtime dependencies outside DefaultInfo.files,
    # for example a filegroup's data. Preserve those files and runfiles mappings.
    runfiles = runfiles.merge_all([
        target[DefaultInfo].default_runfiles
        for target in ctx.attr.env_files.values() + ctx.attr.env_directories.values()
    ])

    return [DefaultInfo(files = depset([output]), runfiles = runfiles)]

cargo_env = rule(
    implementation = _cargo_env_impl,
    attrs = {
        "env": attr.string_dict(
            default = {},
            doc = "Map of environment variable names to literal values.",
        ),
        "env_directories": attr.string_keyed_label_dict(
            default = {},
            doc = "Map of environment variable names to targets. Uses DirectoryInfo.path when available; otherwise uses the target repository root. Includes the target files and default runfiles. Example: {\"MY_INCLUDE_PATH\": \"@my_package//:include_directory\"}",
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
    # Embed both runfiles paths so the wrapper also works outside bazel run.
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
        use_bash_launcher = True,
        visibility = visibility,
        **kwargs
    )
