"""Generates a Cargo environment file for cargo builds using dependencies provided by Bazel."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//rules/directory:providers.bzl", "DirectoryInfo")
load("@rules_cc//cc:defs.bzl", "CcInfo")

def _replace_leading_external_directory(path):
    if paths.starts_with(path, "external"):
        return paths.join("..", *path.split("/")[1:])
    return path

def _cargo_env_impl(ctx):
    output = ctx.actions.declare_file("%s.env" % ctx.attr.name)
    substitutions = ctx.actions.template_dict()

    include_directories = []
    all_header_files = []
    for directory in ctx.attr.include_directories:
        if CcInfo in directory:
            cc_info = directory[CcInfo]
            all_includes = depset(transitive = [
                cc_info.compilation_context.includes,
                cc_info.compilation_context.system_includes,
                cc_info.compilation_context.framework_includes,
                cc_info.compilation_context.external_includes,
                cc_info.compilation_context.quote_includes,
            ]).to_list()
            all_header_files.extend(cc_info.compilation_context.headers.to_list())
            include_directories.extend([
                paths.join("-I$PWD", _replace_leading_external_directory(include))
                for include in all_includes
            ])
            print(include_directories)
            print(all_header_files)
        else:
            include_directories.append(
                paths.join("-I$PWD", _replace_leading_external_directory(directory[DirectoryInfo].path)),
            )

    substitutions.add("{INCLUDES}", " ".join(include_directories))

    clang_path = paths.join("$PWD", _replace_leading_external_directory(ctx.file.clang.path)) if ctx.file.clang else ""
    substitutions.add("{CLANG_PATH}", clang_path)

    libclang_path = paths.join("$PWD", _replace_leading_external_directory(ctx.file.libclang.path)) if ctx.file.libclang else fail("libclang not provided")
    substitutions.add("{LIBCLANG_PATH}", libclang_path)

    openssl_dir = paths.join("$PWD", _replace_leading_external_directory(ctx.file.openssl_dir.short_path)) if ctx.file.openssl_dir else ""
    substitutions.add("{OPENSSL_DIR}", openssl_dir)

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
                all_header_files,
    )

    return [DefaultInfo(executable = output, runfiles = runfiles)]

cargo_env = rule(
    implementation = _cargo_env_impl,
    attrs = {
        "clang": attr.label(
            allow_single_file = True,
            doc = "The clang binary.",
        ),
        "include_directories": attr.label_list(
            mandatory = True,
            providers = [[DirectoryInfo], [CcInfo]],
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
    )
    ```
    """,
)
