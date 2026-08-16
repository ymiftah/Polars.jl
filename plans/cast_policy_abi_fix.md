# Fix `scan_parquet` crashing on every call: `cast_policy` by-value struct ABI mismatch

## Status
Done. Root-caused live, fixed, header/bindings regenerated, rebuilt, live-verified (original
`debug/wip.jl` repro and several isolation cases all now succeed), regression test fixed and
passing, full suite green (2941 passed, 2 pre-existing broken, 0 failed).

The signature fix had already landed on `parity-group1-group4` (commit `78eacc0`, "fix read"), but
`c-polars/src/tests.rs`'s two direct callers of `polars_lazy_frame_scan_parquet` (Rust unit tests,
not exercised by the Julia suite) were never updated to match, breaking CI's `lint`/`rust` jobs
with `E0308: expected *const polars_cast_columns_policy_t, found polars_cast_columns_policy_t` —
fixed here by passing `&polars_cast_columns_policy_t::default()` instead of by value, plus
`cargo fmt`. All of `pre-commit run --all-files`, `cargo clippy --all-targets -- -D warnings`,
`cargo test`, `regen_header.sh` + drift checks, and the generated-bindings-up-to-date check now
pass locally, matching every step the `lint`/`rust` CI jobs run.

## Root cause

`polars_lazy_frame_scan_parquet` took `cast_policy: polars_cast_columns_policy_t` — an 11-byte,
`#[repr(C)]` struct of 11 `bool` fields — **by value**, immediately followed by the
`cloud_options`/`out` pointer arguments ([io.rs](../c-polars/src/io.rs)). Julia's `@ccall`
struct-by-value marshalling for this odd-sized (11-byte, align-1) struct did not match the
System-V x86-64 calling convention rustc generated for it, corrupting the register-passed
arguments that followed. Concretely: Julia always passed `cloud_options = C_NULL` when
`storage_options` was unset, but `resolve_cloud_options` ([io.rs:764](../c-polars/src/io.rs#L764))
received a non-null garbage pointer and dereferenced it — a segfault, or (depending on the garbage
bit pattern) Rust's null-pointer-check panic, which aborts the process even inside `guard_error`'s
`catch_unwind` since it's a non-unwinding panic.

This affected **every** `scan_parquet`/`read_parquet` call unconditionally — reproduced with a
freshly-written, minimal, valid parquet file and zero non-default options — not just the
`hive_partitioning` scenario that surfaced it (`debug/wip.jl`). `scan_parquet` was the only FFI
entry point in the codebase passing this struct by value; `scan_csv` (no such arg) worked fine on
the same file, isolating the bug to this one call site.

The existing regression test (`test/io/parquet_cast_policy.jl`) never caught this because it
called `Pl.DataFrame(x = Int32[1, 2, 3])` — a keyword-argument form the `DataFrame` API doesn't
support — which raised a `MethodError` before ever reaching `scan_parquet`. Fixed to
`Pl.DataFrame((; x = Int32[1, 2, 3]))`, matching the `test/fixtures.jl` convention.

## Fix

Pass `cast_policy` by pointer instead of by value, matching the existing convention for other
optional/complex FFI arguments (`hive_partitioning`, `n_rows`, etc.):

- `c-polars/src/io.rs`: `cast_policy: *const polars_cast_columns_policy_t`, dereferenced via
  `cast_policy.as_ref().copied().unwrap_or_default()`.
- Regenerated `c-polars/include/polars.h` (`regen_header.sh`) and `src/api/generated.jl`
  (`gen/generate.jl` + `runic -i`).
- `src/io/parquet.jl`: box the struct in a `Ref`, pass it under `GC.@preserve`, alongside the
  other preserved refs.
- `test/io/parquet_cast_policy.jl`: fixed the broken `DataFrame` construction so the testset
  actually exercises `scan_parquet` (4 subtests now cover default/`CastPolicy`/`Dict`/
  `read_parquet`-forwarding paths, all of which previously would have crashed the process).
