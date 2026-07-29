# Self-hosted libpolars binaries

## Status

Done — `libpolars-v0.2.0` published, `Artifacts.toml` committed, resolution switched off
`libpolars_jll`. Follow-up (not done): the `artifact` CI job and `check_header_drift.py --lib`, see
"Remaining" below.

## Problem

`pkg> add https://github.com/ymiftah/Polars.jl` — the command the docs give — produced a broken
install. `Project.toml` depended on the registered `libpolars_jll`, which resolves to v0.1.1+0,
built by Yggdrasil from `Pangoraw/Polars.jl@1860f4dd` (the *original* upstream). That binary exports
~153 symbols; this fork's `src/api/generated.jl` declares **298** `@ccall`s against it. The missing
~145 fail at first call rather than at load, so the failure was late and confusing.

It stayed invisible because `gen/prologue.jl` shadows the JLL with a local `cargo build` when one
exists, and every CI job builds first. The JLL path was dead code on every machine that had ever
worked on this repo, and the only path outside users got. Flagged but deferred in
`plans/review_four_fixes.md:88` ("the dependency is effectively decorative").

## Approach

Drop `libpolars_jll`. Build the library in CI, publish per-platform tarballs as GitHub Release
assets on this repo, pin them from a root `Artifacts.toml`.

This works for an **unregistered** package because Pkg fetches artifacts **by URL**, with no
registry lookup. A package *dependency* could only ever be resolved through a registry — which is
why "make our own JLL" would have forced users to `registry add` first, and why the Yggdrasil route
(perfectly viable, and the likely endgame at General-registration time) was not needed now.

Tarballs use exact JLL layout (`lib/libpolars.so`), so swapping to a Yggdrasil-built
`libpolars_jll` later is close to a drop-in.

## Shape

- **`Artifacts.toml`** (root, generated — do not hand-edit): one entry per platform, non-lazy so Pkg
  fetches at `add`/`instantiate` time, matching JLL behaviour.
- **`gen/prologue.jl`** → pasted into `src/api/generated.jl`: local `target/release` → local
  `target/debug` → `artifact"libpolars"` → clear "build from source" error.
- **`.github/workflows/Release-libpolars.yml`**: `workflow_dispatch` only; matrix build, symbol
  parity gate, release creation, `Artifacts.toml` generation.
- **`.github/scripts/update_artifacts_toml.jl`**: both hashes via stdlibs only, entries written with
  `Pkg.Artifacts.bind_artifact!`, platform tags derived by parsing the triplet.

Platforms: `x86_64-linux-gnu` (glibc ≥ 2.34, measured via `objdump -T`, not assumed from the build
host) and `aarch64-apple-darwin`. Everything else gets the actionable error. Adding a target is one
matrix row plus one `Artifacts.toml` entry.

## Things that bit, worth not rediscovering

- **`artifact_meta(...) !== nothing` in the prologue is load-bearing.** Pkg *silently skips* a
  non-lazy artifact when no entry matches the host platform. Without the guard, an unsupported
  platform gets a bare `@artifact_str` failure instead of the "build from source" message.
- **A `workflow_dispatch`-only workflow on a feature branch cannot be triggered at all.** GitHub
  only exposes dispatch for workflows present on the *default* branch. Testing one pre-merge needs a
  temporary branch-scoped `push:` trigger.
- **CI cannot commit `Artifacts.toml`.** `main` is protected and `github-actions[bot]` is not an
  admin, so a direct push is rejected; and a CI-opened PR never runs the required status checks,
  because events raised with `GITHUB_TOKEN` do not trigger workflows. The workflow hands the file
  back via the run summary and a downloadable artifact instead.
- **Deleting your local build does not switch Polars to the artifact until something forces
  recompilation.** The `@static if` branch result changes but no source file does, and a precompile
  cache cannot track an `isfile` check. Pre-existing behaviour, not introduced here. Touch a source
  file, or `Base.compilecache`, if you need to flip deliberately.
- **Do not park `c-polars/target` in `/tmp` to test the artifact branch.** `/tmp` is tmpfs here
  (7.6 G) and that tree is ~5.8 G — it exhausts RAM and takes the session down. Use a
  `git worktree`, which has no `target/` at all.
- `strip = "symbols"` + thin LTO preserves the full dynamic symbol table (verified: 298 on both
  targets). This was the highest-risk assumption; the release profile had never been run before.

## Release procedure

See "Distributing the native library" in `docs/src/developer.md`. Short version: bump
`c-polars/Cargo.toml`, merge, dispatch **Release libpolars**, commit the `Artifacts.toml` it emits.

**Any change under `c-polars/` is invisible to outside users until a release is cut**, since
`Artifacts.toml` pins a fixed tag.

## Remaining

1. `--lib PATH` mode on `c-polars/check_header_drift.py`: assert every header-declared symbol is
   present in a built library's dynamic symbol table. The script already computes `header_symbols`,
   so this is small.
2. An `artifact` job in `Tests.yml` (push-only) that deliberately does *not* build `c-polars`, so
   the shipped path is actually exercised — no current job tests it. Keep it off PRs: a commit
   changing Rust without a matching release will fail it, which is correct signal but must not
   block merges.
