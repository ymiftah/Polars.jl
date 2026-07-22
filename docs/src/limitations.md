# Limitations

Known gaps and sharp edges in Polars.jl worth skimming before you hit them.

## I/O limitations

- **CSV scanning has no `hive_partitioning` option, unlike parquet/IPC.** This is a real gap in
  upstream, not a scope choice: `polars_lazy::frame::LazyCsvReader` (the builder `scan_csv` uses)
  hardcodes hive-partitioning off internally and doesn't expose a way to override it.

- **`allow_missing_columns` (parquet/CSV/IPC scan options) only covers files *missing* a column
  present in the reference schema, not files with an *extra* column beyond it.** That's a separate
  `ExtraColumnsPolicy` this wrapper doesn't expose. The reference schema is whichever file/fragment
  gets scanned first, so ordering matters when relying on this option.

- ~~List and Struct columns cannot be constructed from Julia arrays.~~ **Resolved.**
  `DataFrame(table)` now accepts `Vector{<:Vector{T}}` (including the nullable
  `Vector{Union{Missing,Vector{T}}}` case) for List columns and `Vector{<:NamedTuple}` for Struct
  columns, alongside the scalar/fixed-width types it already supported
  (`Vector{Int}`, `Vector{String}`, `Vector{Date}`, `Vector{DateTime}`, etc.). See the examples in
  [Structs](@ref).

## Date/time limitations

- ~~`Series{Datetime{Res}}`/`Series{Duration{Res}}` don't support `collect()` or broadcasting.~~
  **Resolved.** Datetime and Duration columns now report their real, plain `Dates.DateTime`/
  `Dates.Period` `eltype` (there was never a genuine need for the internal wrapper types this used
  to report — the actual resolution is re-derived at runtime from the underlying polars value
  regardless), so `collect`, `copy`, and broadcasts all work directly. No workaround needed
  anymore.

## Expression/function limitations

- **`Strings.titlecase` is broken.** The upstream polars function requires an internal "nightly" Cargo feature that this package deliberately doesn't enable (see Build environment in the project notes). The binding exists but will error at runtime.

- **`Base.lt(expr1, expr2)` needs explicit qualification.** It collides with an unexported `Base`
  name. Use `Base.lt(col("x"), lit(2))` instead of `col("x") < lit(2)` (or use `.>` and flip the
  operands). The product aggregation used to have the same problem (`Base.product`) but has since
  been renamed to `prod`, an exported Base name — plain `prod(col("x"))` now works with no
  qualification.

- **`Base.tail(df, n)` and `Base.rename(df, existing, new)` also need explicit qualification**,
  for the same reason as `lt` above — bare `tail(df, 2)` / `rename(df, ...)` raise
  `UndefVarError`. `unique`, `drop`, `drop_nulls`, `with_row_index`, `explode`, `unpivot`, and
  `pivot` do **not** have this problem and can be called bare. See [Manipulation](@ref).

## Feature coverage

- Some polars capabilities are behind Cargo features that aren't enabled by default (see `c-polars/Cargo.toml`). If you hit a "activate 'X' feature" panic message, the feature needs to be added there and `c-polars/` rebuilt.

- **`Selectors.array()` matches zero columns, always.** `dtype-array` is not in `c-polars/Cargo.toml`'s feature list, so upstream's own `DataTypeSelector::Array` matcher compiles to its safe `#[cfg(not(feature = "dtype-array"))]` fallback (always `false`) rather than a real dtype check — unlike the "activate 'X' feature" panics mentioned above, this doesn't crash or error, it silently selects nothing. Not planned to be fixed by enabling the feature in this phase (that would also force a full dependency rebuild), and this package has no write-side support for constructing an Array-dtype column at all yet either — `Selectors.list()`/`struct_()`/`nested()`/etc. are unaffected and work correctly.

- The test suite has gaps — some operations have shipped with zero automated test coverage. Verify new operations end-to-end in a live session before assuming they work.

## Performance notes

- Eager `DataFrame` operations (via `collect ∘ op ∘ lazy`) are not as query-optimized as operations built directly on lazy frames — the optimizer only sees the outer `lazy()` call and the final `collect`, not the intermediate steps. For performance-critical workflows, construct the full query on `LazyFrame` before collecting.

## Concurrency

- **No handle is safe to share across Julia tasks/threads without external synchronization.**
  `DataFrame`/`LazyFrame`/`Series`/`Expr`/`Value` are thin wrappers around a raw pointer with no
  internal locking; concurrent mutation (or a mutation racing a read) from two tasks on the *same*
  handle is a data race, same as any other unsynchronized shared mutable Julia object. Give each
  task/thread its own handle (`clone()` a `LazyFrame` if you need to fan a query out), or
  synchronize access yourself.

- **The only internal locks are for Arrow C Data Interface bookkeeping, not query concurrency.**
  `LIVE_SCHEMAS`/`LIVE_ARRAYS` (`src/arrow/schema.jl`, `src/arrow/array.jl`) are guarded by their
  own `ReentrantLock`s because Rust's release callback can fire on whatever thread drops the
  imported/exported array — this only protects that GC-keepalive bookkeeping, not your data.

- **polars' own parallelism (rayon) is independent of Julia's thread pool.** `multithreaded` is
  hard-enabled on the Rust side for the operations that support it (e.g. `unique`, `pivot`); it
  runs on rayon's own thread pool, sized by `POLARS_MAX_THREADS` (or the number of CPUs if unset)
  regardless of `JULIA_NUM_THREADS`. Running many polars queries concurrently from several Julia
  tasks can oversubscribe the machine (Julia threads × rayon threads) — set `POLARS_MAX_THREADS`
  explicitly if that's a concern.
