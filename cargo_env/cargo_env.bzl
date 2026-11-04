"""Generates a Cargo environment file and wrapper scripts for cargo builds using dependencies provided by Bazel."""

load("@bazel_lib//lib:expand_template.bzl", "expand_template")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:shell.bzl", "shell")
load("@bazel_skylib//rules/directory:providers.bzl", "DirectoryInfo")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

_CargoEnvironmentInfo = provider(
    "Configured Clang and Rust linker policy for a Cargo environment.",
    fields = {
        "clang": "Optional configured Clang binary.",
        "linker_mode": "auto, preserve, or clang_lld.",
        "standard_clang_layout": "Whether the caller selected the recognized toolchains_llvm file label.",
    },
)

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

def _make_abs_path(path):
    """Make a path absolute with $RUNFILES_DIR prefix, handling external repos."""
    if _is_file_type(path):
        path = path.path if path.is_source else path.short_path
    else:
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

    return _to_runfiles_path(path) if _is_external_or_parent_path(path) else paths.join("_main", path)

def _make_include_arg(dir):
    return "-I" + paths.join("$RUNFILES_DIR", _directory_runfiles_path(dir[DirectoryInfo]))

def _make_custom_env_arg(item):
    env_name, target = item
    if DirectoryInfo in target:
        path = paths.join("$RUNFILES_DIR", _directory_runfiles_path(target[DirectoryInfo]))
    else:
        # Targets without DirectoryInfo use their repository root.
        path = _make_abs_path(target.label.workspace_root or ".")
    return "export {}=\"{}\"".format(env_name, path)

def _make_env_arg(item):
    return "export {}={}".format(item[0], shell.quote(item[1]))

def _get_optional(optional_file):
    return [optional_file] if optional_file else []

def _cargo_env_impl(ctx):
    for env_name in ctx.attr.env:
        if env_name in ctx.attr.env_directories:
            fail("{} may not be set in both env and env_directories".format(env_name))

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

    custom_env = [
        _make_env_arg(item)
        for item in ctx.attr.env.items()
    ] + [
        _make_custom_env_arg(item)
        for item in ctx.attr.env_directories.items()
    ]
    substitutions.add("{CUSTOM_ENV}", "\n".join(custom_env))

    ctx.actions.expand_template(
        output = output,
        template = ctx.file._template,
        computed_substitutions = substitutions,
        is_executable = True,
    )

    dependencies = ctx.attr.include_directories + ctx.attr.env_directories.values() + ctx.attr.clang_runtime
    dependencies += [target for target in [ctx.attr.clang, ctx.attr.libclang, ctx.attr.openssl_dir] if target]
    runfiles = ctx.runfiles(
        files = ctx.files.include_directories + optional_clang + optional_libclang + optional_openssl_dir + ctx.files.clang_runtime,
        transitive_files = depset(transitive = [target.files for target in ctx.attr.env_directories.values()]),
    ).merge_all([target[DefaultInfo].default_runfiles for target in dependencies if target[DefaultInfo].default_runfiles])
    if ctx.attr.materialize_runtime_inputs:
        # Generated symlink artifacts force source inputs to be materialized for
        # external consumers while preserving their original runfiles paths.
        runtime_sources = depset(
            direct = [entry.target_file for entry in runfiles.symlinks.to_list() + runfiles.root_symlinks.to_list()],
            transitive = [runfiles.files],
        )
        aliases = []
        for file in runtime_sources.to_list():
            if file.is_source and not file.is_directory and file.short_path.startswith("../"):
                alias = ctx.actions.declare_file(ctx.label.name + ".runtime/" + file.short_path[3:])
                ctx.actions.symlink(output = alias, target_file = file)
                aliases.append(alias)
        runfiles = runfiles.merge(ctx.runfiles(files = aliases))

    return [
        DefaultInfo(files = depset([output]), runfiles = runfiles),
        _CargoEnvironmentInfo(clang = ctx.file.clang, linker_mode = ctx.attr.linker_mode, standard_clang_layout = ctx.attr.standard_clang_layout),
    ]

_cargo_env_rule = rule(
    implementation = _cargo_env_impl,
    attrs = {
        "clang_runtime": attr.label_list(allow_files = True, doc = "Extra Clang runtime inputs, including resource headers for nonstandard layouts."),
        "materialize_runtime_inputs": attr.bool(default = True, doc = "Materialize declared external source runfiles through generated symlinks, including non-header resources."),
        "linker_mode": attr.string(
            default = "auto",
            values = ["auto", "preserve", "clang_lld"],
            doc = "Rust Cargo linker policy. auto selects Clang/LLD for the recognized toolchains_llvm layout on Linux x86_64; preserve leaves Cargo linker configuration intact; clang_lld explicitly selects this supported linker mode.",
        ),
        "standard_clang_layout": attr.bool(default = False),
        "clang": attr.label(
            allow_single_file = True,
            doc = "The clang binary.",
        ),
        "env": attr.string_dict(
            default = {},
            doc = "Map of environment variable names to literal values.",
        ),
        "env_directories": attr.string_keyed_label_dict(
            default = {},
            doc = "Map of environment variable names to targets. Uses DirectoryInfo.path when available; otherwise uses the target repository root. Example: {\"MY_INCLUDE_PATH\": \"@my_package//:include_directory\"}",
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
        env = {
            "SOME_VALUE": "value",
        },
        env_directories = {
            "SOME_PACKAGE_PATH": "@some_package//:source_files",
        },
    )
    ```
    """,
)

def cargo_env(name, clang = None, clang_runtime = None, linker_mode = "auto", **kwargs):
    """Generate a dependency environment, declaring optional Clang runtime files.

    Args:
        name: Target name.
        clang: Optional Clang binary label. Configurable labels require explicit runtime inputs.
        clang_runtime: Additional runtime targets, such as the compiler resource headers.
        linker_mode: auto, preserve, or clang_lld; see the README for policy and platform scope.
        **kwargs: Remaining cargo environment rule attributes.
    """
    clang_label = native.package_relative_label(clang) if type(clang) in ["string", "Label"] else None
    standard_clang_layout = clang_label != None and clang_label.package == "" and clang_label.name == "bin/clang"
    if clang_runtime == None:
        clang_runtime = [Label("@@{}//:include".format(clang_label.repo_name))] if standard_clang_layout else []
    _cargo_env_rule(
        name = name,
        clang = clang,
        clang_runtime = clang_runtime,
        linker_mode = linker_mode,
        standard_clang_layout = standard_clang_layout,
        **kwargs
    )

def _rlocation_path(file, workspace):
    return file.short_path[3:] if file.short_path.startswith("../") else workspace + "/" + file.short_path

def _rust_environment_impl(ctx):
    rust = ctx.attr.rust_toolchain[platform_common.ToolchainInfo]
    info = ctx.attr.environment[_CargoEnvironmentInfo] if _CargoEnvironmentInfo in ctx.attr.environment else None
    env = ctx.actions.declare_file(ctx.label.name + ".env")
    content = "source \"$(rlocation {})\"\n".format(shell.quote(_rlocation_path(ctx.file.environment, ctx.workspace_name)))
    extra_files = []
    supported_target = rust.target_triple.str == "x86_64-unknown-linux-gnu"
    if info and info.linker_mode == "clang_lld" and not info.clang:
        fail("clang_lld linker mode requires the clang attribute")
    configure_linker = info and info.clang and (
        info.linker_mode == "clang_lld" or
        (info.linker_mode == "auto" and info.standard_clang_layout and supported_target)
    )
    if configure_linker:
        if not supported_target:
            fail("clang_lld linker mode currently supports only x86_64-unknown-linux-gnu; use preserve for other targets")
        cc_toolchain = ctx.toolchains["@bazel_tools//tools/cpp:toolchain_type"]
        if not cc_toolchain:
            fail("Configured Clang linker mode requires a C++ toolchain")
        clang = info.clang
        llvm_files = [f for f in cc_toolchain.cc.all_files.to_list() if f.owner.workspace_name == clang.owner.workspace_name]
        lld = [f for f in llvm_files if f.basename == "ld.lld"]
        if len(lld) != 1:
            fail("Configured Clang linker mode requires one declared ld.lld beside Clang; found {}".format(len(lld)))
        linker = ctx.actions.declare_file(ctx.label.name + "/clang")
        ctx.actions.write(
            output = linker,
            content = "#!/usr/bin/env bash\nset -euo pipefail\nexec \"${CLANG_PATH:?}\" --ld-path=\"${_CARGO_ENV_LLD:?}\" \"$@\"\n",
            is_executable = True,
        )
        target = rust.target_triple.str.upper().replace("-", "_")
        variable = "CARGO_TARGET_{}_LINKER".format(target)
        content += "export _CARGO_ENV_LLD=\"$(rlocation {})\"\n".format(shell.quote(_rlocation_path(lld[0], ctx.workspace_name)))
        content += "if [ \"${" + variable + "+x}\" != x ]; then\n"
        content += "  export {}=\"$(rlocation {})\"\nfi\n".format(variable, shell.quote(_rlocation_path(linker, ctx.workspace_name)))
        extra_files = [linker] + llvm_files
    ctx.actions.write(output = env, content = content)
    runfiles = ctx.runfiles(files = [ctx.file.environment] + extra_files, transitive_files = rust.all_files)
    original_runfiles = ctx.attr.environment[DefaultInfo].default_runfiles
    if original_runfiles:
        runfiles = runfiles.merge(original_runfiles)
    return [DefaultInfo(files = depset([env]), runfiles = runfiles)]

_rust_environment = rule(
    implementation = _rust_environment_impl,
    attrs = {
        "environment": attr.label(allow_single_file = True),
        "rust_toolchain": attr.label(),
    },
    toolchains = [config_common.toolchain_type("@bazel_tools//tools/cpp:toolchain_type", mandatory = False)],
)

def env_wrapper(name, binary, environment, visibility = None, rust_runtime = True, **kwargs):
    """Wrap a command with a Cargo dependency environment.

    Args:
        name: Wrapper target name.
        binary: Command label to wrap.
        environment: Generated Cargo environment or shell environment file.
        visibility: Wrapper target visibility.
        rust_runtime: Add the selected Rust runtime for the standard upstream Cargo wrapper;
            requires rules_rust's public current_rust_toolchain alias (0.75.0 or newer).
            Disable for older toolchains or custom integration.
        **kwargs: Other wrapper target attributes.
    """
    binary_label = native.package_relative_label(binary)
    if rust_runtime and binary_label.package == "tools/upstream_wrapper" and binary_label.name == "cargo":
        rust_environment = "_{}_rust_environment".format(name)
        _rust_environment(
            name = rust_environment,
            environment = environment,
            rust_toolchain = Label("@@{}//rust/toolchain:current_rust_toolchain".format(binary_label.repo_name)),
            tags = kwargs.get("tags", []),
        )
        environment = ":" + rust_environment

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
