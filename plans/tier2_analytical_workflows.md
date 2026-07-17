# Tier 2: is_unique/is_duplicated, sample_n/sample_frac, sink_csv/sink_ipc

## Status
Tier 1 (`sort_by`, `arg_sort`, `top_k`, `value_counts`) is done, pushed as `9957e32` on
`scan-parquet`, 445/445 tests pass — including a fix to `polars_value_struct_get` (previously
panicked across the FFI boundary on any non-Int64 struct field; now delegates to polars-core's
`_iter_struct_av()`). This plan covers **Tier 2** from the "importance in analytical workflows"
prioritization: `is_duplicated`/`is_unique` (data quality), `sample_n`/`sample_frac` (exploration,
train/test splits), `sink_csv`/`sink_ipc` (more out-of-core sinks, matching the user's stated
streaming/parquet focus).

## Research findings (confirmed against vendored polars 0.54.4 source)

**`is_duplicated`/`is_unique`** — `Expr::is_duplicated(self) -> Self` /
`Expr::is_unique(self) -> Self` in `polars-plan/src/dsl/mod.rs`, both gated by
`#[cfg(feature = "is_unique")]` (ordinary compile-time gate, not a runtime panic — need to add
`"is_unique"` to `c-polars/Cargo.toml`'s feature list). Both are plain unary `Expr -> Expr`, fit
the existing `gen_impl_expr!` macro directly (same block as `unique`/`n_unique` at
[expr.rs:377-378](c-polars/src/expr.rs#L377)).

**`sample_n`/`sample_frac`** — `polars-plan/src/dsl/random.rs`:
```rust
pub fn sample_n(self, n: Expr, with_replacement: bool, shuffle: bool, seed: Option<u64>) -> Self
pub fn sample_frac(self, frac: Expr, with_replacement: bool, shuffle: bool, seed: Option<u64>) -> Self
```
No `#[cfg]` directly on these methods, but the containing `mod random;` declaration is gated by
`#[cfg(feature = "random")]` in all three crates that matter (`polars-plan/src/dsl/mod.rs:37`,
`polars-plan/src/dsl/function_expr/mod.rs:19`, `polars-expr/src/dispatch/mod.rs:117`) — confirmed
via grep for the `"activate .. feature"` runtime-panic pattern CLAUDE.md warns about: **zero
hits** in any random-related file. Safe compile-time-only gate; add `"random"` to
`c-polars/Cargo.toml`.

Both are hand-written (extra scalar args beyond the macro's plain unary/binary shape), following
the `polars_expr_diff`/`polars_expr_rank` pattern
([expr.rs:534](c-polars/src/expr.rs#L534)/[expr.rs:567](c-polars/src/expr.rs#L567)): clone self +
the `n`/`frac` Expr, pass `with_replacement`/`shuffle` as plain `bool`. The `Option<u64>` seed
follows the **nullable-pointer convention** already established for `replace_strict`'s optional
`default` param (`*const polars_expr_t` — null means `None`) — here `seed: *const u64`, null means
`None`, else deref-read the `u64`.

**`sink_csv`/`sink_ipc`** — mirror `polars_lazy_frame_sink_parquet`
([lib.rs:411](c-polars/src/lib.rs#L411)) exactly, swapping
`FileWriteFormat::Parquet(Arc::new(ParquetWriteOptions::default()))` for
`FileWriteFormat::Csv(CsvWriterOptions::default())` / `FileWriteFormat::Ipc(IpcWriterOptions::default())`
(both have `Default` impls, confirmed in `polars-io-0.54.4/src/csv/write/options.rs` and
`.../ipc/write.rs`). `Csv` needs the already-active `csv` feature; `Ipc` needs a **new** `"ipc"`
feature (not yet in `c-polars/Cargo.toml`). No panic risk found in either writer's source.

## Items

### T2.1 — `is_duplicated` / `is_unique`
- Cargo: add `"is_unique"` feature.
- Rust ([expr.rs](c-polars/src/expr.rs), next to `unique`/`n_unique`):
  `gen_impl_expr!(polars_expr_is_duplicated, Expr::is_duplicated);`
  `gen_impl_expr!(polars_expr_is_unique, Expr::is_unique);`
- Header/API.jl: prototype + ccall matching neighboring no-arg expr fns (e.g. `polars_expr_unique`).
- Julia ([expr.jl](src/expr.jl)): slots into the main `@generate_expr_fns` unary block — no
  Base collision (`isdefined(Base, :is_unique/:is_duplicated)` both `false`), auto-exported.
- Test: extend `test/expr/null_handling.jl` or a new testset in `test/expr/statistics.jl` — a
  fixture with duplicate rows, assert the boolean masks match hand-computed expectations.

### T2.2 — `sample_n` / `sample_frac`
- Cargo: add `"random"` feature.
- Rust ([expr.rs](c-polars/src/expr.rs)): hand-written, following `polars_expr_diff`'s shape:
  ```rust
  pub unsafe extern "C" fn polars_expr_sample_n(
      expr: *const polars_expr_t, n: *const polars_expr_t,
      with_replacement: bool, shuffle: bool, seed: *const u64,
  ) -> *const polars_expr_t {
      let seed = if seed.is_null() { None } else { Some(*seed) };
      make_expr((*expr).inner.clone().sample_n((*n).inner.clone(), with_replacement, shuffle, seed))
  }
  ```
  same shape for `polars_expr_sample_frac` with `frac` in place of `n`.
- Header/API.jl: prototype + ccall (note the `seed::Ptr{UInt64}` param, null via `C_NULL`).
- Julia ([expr.jl](src/expr.jl)): hand-written (extra args beyond macro shape):
  ```julia
  function sample_n(expr::Expr, n; with_replacement::Bool=false, shuffle::Bool=false, seed::Union{Nothing,Integer}=nothing)
      n = convert(Expr, n)
      seed_ref = seed === nothing ? Ptr{UInt64}(C_NULL) : Ref(UInt64(seed))
      out = API.polars_expr_sample_n(expr, n, with_replacement, shuffle, seed === nothing ? Ptr{UInt64}(C_NULL) : seed_ref)
      return Expr(out)
  end
  ```
  (careful with `GC.@preserve seed_ref` if using a `Ref` — keep it alive across the ccall) and the
  `sample_frac` sibling. No Base collision. Export both.
- Test: new testset in `test/expr/statistics.jl` or a new `test/expr/sample.jl` — assert
  `sample_n(col("x"), 3)` returns exactly 3 rows; `with_replacement=true` can return duplicates;
  same `seed` gives reproducible output (call twice, compare); `sample_frac` returns
  `round(Int, frac * nrow)` rows on a fixture sized so that's exact.

### T2.3 — `sink_csv` / `sink_ipc`
- Cargo: add `"ipc"` feature (`csv` already active).
- Rust ([lib.rs](c-polars/src/lib.rs)): `polars_lazy_frame_sink_csv`/`polars_lazy_frame_sink_ipc`,
  copying `polars_lazy_frame_sink_parquet` exactly except for the `file_format` line.
- Julia ([Polars.jl](src/Polars.jl)): `sink_csv`/`sink_ipc`, mirroring `sink_parquet`
  ([Polars.jl:261](src/Polars.jl#L261)) exactly (both the `LazyFrame` and `DataFrame` sibling
  methods). Export both.
- **Confirmed: no IPC read path exists at all yet** (`scan_ipc`/`read_ipc` — zero hits). But
  `LazyFrame::scan_ipc(path, IpcScanOptions::default(), UnifiedScanArgs::default())` mirrors
  `scan_csv`'s existing one-liner shape exactly (`polars-lazy-0.54.4/src/scan/ipc.rs`) — cheap
  enough to add alongside `sink_ipc` so the round-trip test is real, not a byte-count proxy.
  Add `polars_lazy_frame_scan_ipc` (copy `polars_lazy_frame_scan_csv`'s structure, swap
  `DslBuilder::scan_csv(sources, CsvReadOptions::default(), ...)` for
  `LazyFrame::scan_ipc(PlRefPath::new(path), IpcScanOptions::default(), UnifiedScanArgs::default())`)
  and Julia `scan_ipc(path)` / `read_ipc(path) = collect(scan_ipc(path))`, mirroring
  `scan_csv`/`read_csv` exactly. `read_csv` already exists for the CSV side.
- Test: extend `test/lazyframe/sink_parquet.jl` (or new sibling file) — build a small pipeline,
  `sink_csv`/`sink_ipc` to a temp path, read back via `read_csv`/`read_ipc`, compare against the
  eager `collect`-then-`write_*`-then-`read_*` equivalent on the same pipeline.

## Cargo.toml changes
Add to `c-polars/Cargo.toml`'s `polars` feature list: `"is_unique", "random", "ipc"`.

## Verification
Build (`cd c-polars && cargo build -j 1`, memory-safety-tripped Monitor pattern — check `free -m`
before launching, abort if available memory drops below ~1GB during the build), restart Julia,
exercise live before writing each test:
- T2.1: `select(df, is_duplicated(col("x")), is_unique(col("x")))` on a fixture with dupes.
- T2.2: `select(df, sample_n(col("x"), 3))` → 3 rows; same `seed=42` twice → identical output.
- T2.3: pipeline → `sink_csv`/`sink_ipc` → read back → compare against eager equivalent.

Then run the full suite via the scratch-env workaround
(`Pkg.develop(path="."); Pkg.add(["Aqua","Test","Tables","Dates"])` in a throwaway env under the
scratchpad directory — never `Pkg.test()`, never `--project=test` directly).

## Suggested order
T2.1 (smallest, two one-liners) → T2.3 (mechanical, mirrors sink_parquet exactly, high value given
user's streaming focus) → T2.2 (most new surface: nullable-pointer seed marshaling is a new
pattern for a *scalar* arg, though the convention itself is already established for Expr args).
