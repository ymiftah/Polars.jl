# Limitations

Known gaps and sharp edges in Polars.jl worth skimming before you hit them.

## I/O limitations

- **CSV scanning has no `hive_partitioning` option, unlike parquet/IPC.** Hive partitioning is
  always disabled for CSV scans, with no way to turn it on. See [Developer](@ref) for why.

- **`allow_missing_columns` (parquet/CSV/IPC scan options) only covers files *missing* a column
  present in the reference schema, not files with an *extra* column beyond it.** The reference
  schema is whichever file/fragment gets scanned first, so ordering matters when relying on this
  option.

- **A `Decimal`-typed column can be queried/cast (`cast_decimal`, `Selectors.decimal()`) but not
  materialized back into Julia.** Reading its values (`df[:col]`) raises an error — there's no
  Julia-side decimal type this package maps it to yet, unlike every other dtype in
  [Data types](@ref). Keep decimal columns on the lazy/query side (cast to `Float64`/`String`
  before collecting if you need the values in Julia).

## Date/time limitations

- **A `lit(dt::DateTime)` literal is built at nanosecond resolution and inherits that
  representation's ~1678–2262 range limit.** `lit(DateTime(2300, 1, 1))` raises `InexactError`
  rather than silently producing a wrong value. The same limit applies to any nanosecond-precision
  `DateTime` column built from a plain Julia `Vector{DateTime}`. `lit(d::Date)` has no equivalent
  practical limit (`Int32` days-since-epoch covers a range of several million years);
  `lit(t::Dates.Time)` is nanoseconds-since-midnight, bounded by a single day and never overflows
  `Int64`.

- **A `:ns`-resolution `DateTime` literal compares transparently against a column at a different
  native resolution (e.g. `:us`), but `join`ing on mismatched resolutions errors.** A `filter`/`==`
  comparison between a `lit(dt::DateTime)` (always `:ns`) and a `:us` column works with no
  extra step — polars aligns the units itself. `innerjoin`/etc. on a Datetime key does not do this
  alignment: joining two frames whose Datetime key columns are at different `time_unit`s raises a
  `PolarsError` ("datatypes of join keys don't match") rather than silently producing wrong
  matches — cast one side to the other's resolution first (`cast_datetime(expr; time_unit)`).

## Expression/function limitations

- **`Strings.titlecase` is broken.** The binding exists but errors at runtime. See
  [Developer](@ref) for why.

- **`Base.lt(expr1, expr2)` needs explicit qualification.** It collides with an unexported `Base`
  name. Use `Base.lt(col("x"), lit(2))` instead of `col("x") < lit(2)` (or use `.>` and flip the
  operands).

- **`Polars.Meta.is_literal` reports `false` for a `Date`/`Time`/`DateTime` literal**
  (`lit(Date(2024, 1, 1))`, etc.), diverging from py-polars. These are built as a cast over an
  integer literal rather than a genuine `Literal` node (see [Literals & casting](@ref)), so
  `is_literal` correctly reports what the expression tree actually contains. This is cosmetic
  only and has no effect on query results or performance.

## Feature coverage

- Some polars capabilities aren't compiled into this package's build. If you hit an "activate 'X'
  feature" panic message, please open an issue.

- **`Selectors.array()` is unavailable in this build** and raises an error rather than selecting
  columns; there is also no write-side support for constructing an `Array`-dtype column yet.
  `Selectors.list()`/`struct_()`/`nested()`/etc. are unaffected and work correctly.

## Performance notes

- Eager `DataFrame` operations are not as query-optimized as operations built directly on lazy
  frames — the optimizer only sees the outer `lazy()` call and the final `collect`, not the
  intermediate steps. For performance-critical workflows, construct the full query on `LazyFrame`
  before collecting.

## Concurrency

- **No handle is safe to share across Julia tasks/threads without external synchronization.**
  `DataFrame`/`LazyFrame`/`Series`/`Expr`/`Value` have no internal locking; concurrent mutation (or
  a mutation racing a read) from two tasks on the *same* handle is a data race, same as any other
  unsynchronized shared mutable Julia object. Give each task/thread its own handle (`clone()` a
  `LazyFrame` if you need to fan a query out), or synchronize access yourself.

- **polars' own parallelism is independent of Julia's thread pool.** Operations that support it
  run multithreaded regardless of `JULIA_NUM_THREADS`, sized by the `POLARS_MAX_THREADS`
  environment variable (or the number of CPUs if unset). Running many polars queries concurrently
  from several Julia tasks can oversubscribe the machine — set `POLARS_MAX_THREADS` explicitly if
  that's a concern.

- **`DataFrame(table)` aliases fixed-width numeric column `Vector`s rather than copying them** —
  mutating the source `Vector` afterwards mutates the `DataFrame` too; see [Developer](@ref) for
  exactly which column types this applies to.

See [Developer](@ref) for the implementation detail behind these gaps, plus notes on memory
management, error handling, and internal Cargo feature configuration.
