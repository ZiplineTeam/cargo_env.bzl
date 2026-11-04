"""Runfiles fixtures whose source files are absent from DefaultInfo.files."""

def _runtime_only_impl(ctx):
    return [DefaultInfo(
        files = depset(),
        runfiles = ctx.runfiles(
            files = [ctx.file.src],
            root_symlinks = {"fsw64354_runtime_only_link": ctx.file.link, "fsw64354 runtime link": ctx.file.link},
        ),
    )]

runtime_only = rule(
    doc = "Expose source inputs only through ordinary and root-symlink runfiles.",
    implementation = _runtime_only_impl,
    attrs = {"src": attr.label(allow_single_file = True), "link": attr.label(allow_single_file = True)},
)
