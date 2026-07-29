#!/usr/bin/env julia

"""
Regenerate the root `Artifacts.toml` from a directory of built libpolars tarballs.

Usage:  julia .github/scripts/update_artifacts_toml.jl <version> <tarball-dir> <artifacts-toml>

Called by the `publish` job of `.github/workflows/Release-libpolars.yml` after the release assets
have been uploaded. Tarballs are expected to be named exactly as the `build` job produces them:

    libpolars.v<version>.<triplet>.tar.gz        e.g. libpolars.v0.2.0.x86_64-linux-gnu.tar.gz

Two hashes go into each entry, and they are not interchangeable:

  * `sha256`        -- of the compressed tarball as downloaded. Integrity of the transfer.
  * `git-tree-sha1` -- of the *extracted* tree. This is the content address Pkg installs under,
                       i.e. `~/.julia/artifacts/<git-tree-sha1>/`.

`Tar.tree_hash` over a `gzip -dc` pipe computes the latter without unpacking to disk and without
pulling in a non-stdlib dependency (the more commonly cited recipe uses `Inflate.inflate_gzip`).
This was checked against `Pkg.GitTools.tree_hash` on the extracted directory and matches byte for
byte.

Platform tags are derived by parsing the triplet rather than hand-maintained, so adding a target to
the build matrix needs no change here:

    "x86_64-linux-gnu"     -> arch = x86_64, os = linux, libc = glibc
    "aarch64-apple-darwin" -> arch = aarch64, os = macos

Entries are written with `Pkg.Artifacts.bind_artifact!` rather than by formatting TOML by hand, so
the file shape stays whatever Pkg itself considers canonical.
"""

import Pkg
using Pkg.Artifacts: bind_artifact!
using Base.BinaryPlatforms: Platform
using Tar, SHA

const REPO = get(ENV, "GITHUB_REPOSITORY", "ymiftah/Polars.jl")
const ARTIFACT_NAME = "libpolars"
const TARBALL_RE = r"^libpolars\.v(.+)\.(.+)\.tar\.gz$"

"""Content address of the extracted tree, without unpacking to disk."""
tree_hash(tarball) = Base.SHA1(open(io -> Tar.tree_hash(io), `gzip -dc $tarball`))

function main(version::AbstractString, tarball_dir::AbstractString, artifacts_toml::AbstractString)
    tarballs = sort(filter(f -> endswith(f, ".tar.gz"), readdir(tarball_dir; join = true)))
    isempty(tarballs) && error("no .tar.gz files found in $tarball_dir")

    # Rewrite from scratch. `bind_artifact!(force=true)` replaces a matching platform entry, but it
    # would silently leave behind entries for platforms that have been dropped from the matrix.
    isfile(artifacts_toml) && rm(artifacts_toml)

    for tarball in tarballs
        m = match(TARBALL_RE, basename(tarball))
        m === nothing && error("unexpected tarball name: $(basename(tarball))")
        tarball_version, triplet = m.captures

        tarball_version == version || error(
            "version mismatch: $(basename(tarball)) carries v$tarball_version, expected v$version"
        )

        platform = parse(Platform, triplet)
        tree = tree_hash(tarball)
        sha256sum = bytes2hex(open(sha256, tarball))
        url = "https://github.com/$REPO/releases/download/" *
            "libpolars-v$version/$(basename(tarball))"

        bind_artifact!(
            artifacts_toml,
            ARTIFACT_NAME,
            tree;
            platform = platform,
            download_info = [(url, sha256sum)],
            # Non-lazy: Pkg fetches the matching platform's artifact at `add`/`instantiate` time,
            # matching JLL behaviour. Lazy would need a LazyArtifacts dependency and would move the
            # download into precompilation.
            lazy = false,
            force = true,
        )

        @info "bound $ARTIFACT_NAME" triplet platform tree sha256 = sha256sum url
    end

    @info "wrote $artifacts_toml"
    print(read(artifacts_toml, String))
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    if length(ARGS) != 3
        println(stderr, "usage: update_artifacts_toml.jl <version> <tarball-dir> <artifacts-toml>")
        exit(2)
    end
    exit(main(ARGS[1], ARGS[2], ARGS[3]))
end
