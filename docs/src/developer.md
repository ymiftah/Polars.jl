# Developer

Notes for contributors. For building `c-polars` and regenerating the bindings, see
[`c-polars/README.md`](https://github.com/ymiftah/Polars.jl/blob/main/c-polars/README.md).

## Architecture

Polars.jl calls the Rust `polars` crate through a hand-written C ABI (`c-polars/`). All query logic
runs in polars; the Julia side builds expressions and moves data across the boundary. Eager
`DataFrame` operations are implemented as `collect ∘ op ∘ lazy`, so eager and lazy forms of an
operation give the same result.

The Julia bindings in `src/api/generated.jl` are generated from `c-polars/include/polars.h`, which
is itself generated from the Rust source. Neither file is edited by hand.

## Error handling

Every fallible C function returns a `*const polars_error_t` (null on success) and writes its result
through an out-parameter. The Julia side turns an error into a `PolarsError` carrying polars' error
message.

## Memory management

`DataFrame`, `LazyFrame`, `Series`, `Expr` and `Value` wrap a pointer to a Rust allocation, freed by
a finalizer. The locks around `LIVE_SCHEMAS` and `LIVE_ARRAYS` (`src/arrow/`) protect the
bookkeeping for Arrow release callbacks, which Rust may call from any thread; they don't make the
handles thread-safe.

## Distributing the native library

`libpolars` is not taken from the registered `libpolars_jll`, which is built from the original
upstream repository and lacks part of the C ABI this package needs. Binaries are built by the
`Release libpolars` workflow, published as GitHub Release assets of this repository, and pinned by
the root `Artifacts.toml`.

`gen/prologue.jl` looks for a local `cargo build --release`, then `cargo build`, then the artifact.
On platforms without an artifact, loading raises an error asking for a source build.

A change under `c-polars/` reaches users only once a new release is cut:

1. Bump `version` in `c-polars/Cargo.toml` and merge.
2. Run the **Release libpolars** workflow from `main`. It builds every target, checks the exported
   symbols against the header, and publishes the tag `libpolars-v<version>`.
3. Commit the `Artifacts.toml` from the run summary (or its downloadable artifact) in a PR. The
   workflow can't push it itself: `main` is protected, and a PR opened with `GITHUB_TOKEN` wouldn't
   trigger the required checks.

## Cargo features

Some polars functions are behind Cargo features that `c-polars/Cargo.toml` doesn't enable. The
wrappers exist but raise an error:

- `Strings.to_integer` needs `string_to_integer`, `Strings.reverse` needs `string_reverse`, and
  `Dt.month_start`/`Dt.month_end` need their own features. Add the feature to the `polars`
  dependency in `c-polars/Cargo.toml`, rebuild, and regenerate the bindings.
- `Strings.titlecase` needs polars' `nightly` feature, which requires a nightly `rustc`
  (`cargo build --features nightly`). The package builds with the stable toolchain.

## API design

- `Base.lt` is used qualified, since `lt` is an unexported `Base` name. The product aggregation is
  `prod` rather than `product` for the same reason.
- `log`, `rem`, `replace`, `diff` and `round` have no curried form: one that accepted bare numbers
  would be type piracy on `Base`.
- `Polars.Meta` is not exported, because `Base.Meta` is.
