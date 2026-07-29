using Artifacts

# Resolve the native `libpolars` shared library.
#
# Priority: a local `cargo build` (the dev loop -- `release/` first, then `debug/`), then the
# prebuilt artifact published as a GitHub Release asset on this repo and pinned by the root
# `Artifacts.toml`.
#
# The registered `libpolars_jll` is deliberately NOT used. It is built from the original upstream
# repo (`Pangoraw/Polars.jl`) and exports ~153 symbols against the 298 this fork needs, so it fails
# at `ccall` time rather than at load time -- a late, confusing failure that only ever reached
# outside users, since every checkout and CI job here has a local build that shadowed it.
#
# Self-hosted artifacts work for an unregistered package because Pkg fetches artifacts by URL with
# no registry lookup; a package *dependency* could only ever be resolved through a registry.
const libpolars_artifacts_toml = joinpath(@__DIR__, "..", "..", "Artifacts.toml")
const libpolars_file_name = "libpolars" * (Sys.iswindows() ? ".dll" : Sys.isapple() ? ".dylib" : ".so")
const libpolars_local_release_path = joinpath(@__DIR__, "..", "..", "c-polars", "target", "release", libpolars_file_name)
const libpolars_local_debug_path = joinpath(@__DIR__, "..", "..", "c-polars", "target", "debug", libpolars_file_name)

@static if isfile(libpolars_local_release_path)
    const libpolars = libpolars_local_release_path
elseif isfile(libpolars_local_debug_path)
    const libpolars = libpolars_local_debug_path
elseif artifact_meta("libpolars", libpolars_artifacts_toml) !== nothing
    # This guard is load-bearing. Pkg silently skips a non-lazy artifact when no entry matches the
    # host platform, so without it an unsupported platform hits a bare `@artifact_str` failure
    # instead of the actionable message below.
    const libpolars = joinpath(artifact"libpolars", Sys.iswindows() ? "bin" : "lib", libpolars_file_name)
else
    error(
        "Polars.jl: no prebuilt `libpolars` is available for this platform ($(Sys.MACHINE)), " *
            "and no local build was found. Build one from source with " *
            "`cd c-polars && cargo build --release`."
    )
end
