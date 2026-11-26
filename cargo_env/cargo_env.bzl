"""Generates a Cargo environment file and wrapper scripts for cargo builds using dependencies provided by Bazel."""

load("@bazel_lib//lib:expand_template.bzl", "expand_template")
load("@bazel_lib//lib:paths.bzl", "to_rlocation_path")
load("@bazel_skylib//lib:collections.bzl", "collections")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:shell.bzl", "shell")
load("@bazel_skylib//rules/directory:providers.bzl", "DirectoryInfo")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

# Collect each kind of search path across all targets. Both system and external
# paths use -isystem, so their relative order matters when names collide.
_INCLUDE_FLAGS = [
    ("quote_includes", "-iquote"),
    ("includes", "-I"),
    ("system_includes", "-isystem"),
    ("framework_includes", "-F"),
    ("external_includes", "-isystem"),
]

def _workspace_runfiles_path(path):
    """Map a normalized path to its runfiles-relative path.

    Main-repository paths get the _main prefix. External paths already
    include their repository name after the layout prefix.

    Examples:
    - pkg/include -> _main/pkg/include
    - external/repo/include -> repo/include
    - ../repo/include -> repo/include
    """
    if paths.starts_with(path, "external") or paths.starts_with(path, ".."):
        return path.split("/", 1)[-1]
    return paths.join("_main", path)

def _directory_runfiles_path(path):
    """Convert an execution-root directory to a runfiles-relative path."""
    normalized_path = paths.normalize(path)
    if paths.starts_with(normalized_path, "bazel-out"):
        parts = normalized_path.split("/")
        if len(parts) < 3 or parts[2] not in ["bin", "genfiles"]:
            fail("Unsupported generated directory path: {}".format(path))
        normalized_path = "/".join(parts[3:]) or "."

    return _workspace_runfiles_path(normalized_path)

def _shell_runfiles_path(path):
    return '"${RUNFILES_DIR}/"' + shell.quote(path)

def _include_flag(prefix, path):
    if paths.is_absolute(path):
        return shell.quote(prefix + path)
    return shell.quote(prefix) + _shell_runfiles_path(_directory_runfiles_path(path))

def _include_context(target):
    if DirectoryInfo in target:
        return cc_common.create_compilation_context(
            headers = target.files,
            includes = depset([target[DirectoryInfo].path]),
        )
    return target[CcInfo].compilation_context

def _make_include_args(context):
    return collections.uniq([
        _include_flag(prefix, path)
        for field, prefix in _INCLUDE_FLAGS
        for path in getattr(context, field).to_list()
    ])

def _make_export_env_arg(env_name, value):
    """Format an export statement; value must already be shell-quoted."""
    return "export {}={}".format(env_name, value)

def _make_custom_env_arg(item):
    env_name, target = item
    if DirectoryInfo in target:
        path = _directory_runfiles_path(target[DirectoryInfo].path)
    else:
        # Targets without DirectoryInfo use their repository root.
        path = target.label.repo_name or "."
    return _make_export_env_arg(env_name, _shell_runfiles_path(path))

def _get_single_file(target, env_name):
    files = target[DefaultInfo].files.to_list()
    if len(files) != 1:
        fail("env_files entry {} must provide exactly one file, got {}".format(env_name, len(files)))
    return files[0]

def _make_file_env_arg(ctx, env_name, file):
    return _make_export_env_arg(env_name, _shell_runfiles_path(to_rlocation_path(ctx, file)))

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
    include_context = cc_common.merge_compilation_contexts(compilation_contexts = [
        _include_context(target)
        for target in ctx.attr.include_directories
    ])

    # Keep the separators inside the shell assignment value.
    include_flags = shell.quote(" ").join(_make_include_args(include_context))

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

    ctx.actions.write(
        output = output,
        content = "\n".join([
            _make_export_env_arg("CFLAGS", include_flags),
            _make_export_env_arg("CXXFLAGS", include_flags),
            "\n".join(custom_env),
            "",
        ]),
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        files = env_files.values(),
        transitive_files = depset(transitive = [include_context.headers] + [target.files for target in ctx.attr.env_directories.values()]),
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
            providers = [[DirectoryInfo], [CcInfo]],
            doc = "Directory targets or C++ library targets supplying headers and compiler include paths.",
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
