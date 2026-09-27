# Limitations

Known gaps in Polars.jl.

## I/O

- CSV scans have no `hive_partitioning` option: polars' CSV reader always disables it.
- `allow_missing_columns` covers files that lack a column of the reference schema (the first file
  scanned), not files with extra columns. `scan_parquet` handles extra columns with
  `allow_extra_columns`; `scan_csv` and `scan_ipc` don't support it.

## Data types

- `Decimal` columns can be cast to and queried, but not read into Julia. Cast them to `Float64` or
  `String` first.
- `Array` (fixed-size list) columns can be built (`Lists.to_array`, `concat_arr`, `reshape`) and
  selected (`Selectors.array()`), but not read into Julia, and `collect_schema` fails on a frame
  that contains one. There is no `.arr` namespace.
- `lit(::DateTime)` has nanosecond precision, which limits it to the years 1678–2262; outside that
  range it raises `InexactError`. The same applies to `DateTime` columns built from Julia vectors.
- Comparing a column against a `DateTime` literal works whatever the column's time unit, but a join
  on `Datetime` keys with different time units raises. Cast one side with
  `cast_datetime(expr; time_unit)` first.
- `Meta.is_literal` returns `false` for `Date`, `Time` and `DateTime` literals, which are built as a
  cast of an integer literal.

## Missing features

- These functions are not compiled into the default build and raise an error: `Strings.titlecase`
  (needs polars' `nightly` feature), `Strings.to_integer` (`string_to_integer`), `Strings.reverse`
  (`string_reverse`), `Dt.month_start` and `Dt.month_end`. See [Developer](@ref) to build with
  them.
- Joins have no `slice` option, since polars panics on it. Use `head` or `tail` on the result.
- Some other polars capabilities are not compiled in. If you hit an "activate 'X' feature" error,
  please open an issue.

## Exports

These names are not exported, because they collide with `Base` or leave the name to an extension
package. Call them qualified.

| Name | Call as | Reason |
|---|---|---|
| `item` | `Polars.item(...)` | Generic name |
| `version` | `Polars.version()` | Generic name |
| `kurtosis` | `Polars.kurtosis(...)` | StatsBase.jl's `kurtosis`, extended when it is loaded |
| `cut` | `Polars.cut(...)` | CategoricalArrays.jl's `cut`, extended when it is loaded |
| `lt` | `Base.lt(...)` | Unexported `Base` name |
| `Dt.time` | `Dt.time(...)` | `Base.time` |
| `Strings.contains`/`replace`/`join`/`reverse` | `Strings.foo(...)` | `Base` names |
| `Lists.tail`/`shift`/`gather`/`gather_every`/`sample_n`/`union`/`std`/`var`/`agg`/`get`/`contains`/`head` | `Lists.foo(...)` | `Base` or `Polars` names |
| `Lists.apply` | `Lists.apply(...)` | Qualified by design |
| `Selectors.all`/`float`/`string`/`time`/`contains`/`empty` | `Selectors.foo(...)` | `Base` names |
| `Meta` (submodule) | `Polars.Meta.foo(...)` | `Base.Meta` |

## Performance

Each eager `DataFrame` operation runs as its own lazy query, so the optimizer only sees one step at
a time. Build the whole query on a `LazyFrame` and `collect` once for full optimization.

## Memory and concurrency

- No handle (`DataFrame`, `LazyFrame`, `Series`, `Expr`) is safe to share between Julia tasks
  without synchronization. Give each task its own handle (`clone` a `LazyFrame`), or use a lock.
- polars runs its own thread pool, independent of `JULIA_NUM_THREADS` and sized by the
  `POLARS_MAX_THREADS` environment variable (default: the number of CPUs). Running many queries
  from several Julia tasks can oversubscribe the machine.
- `DataFrame(table)` shares memory with numeric columns (`Int64`, `Float64`, ..., with or without
  `missing`) instead of copying them: mutating the source `Vector` afterwards changes the
  `DataFrame`. Other column types are copied.
- `read_series(s; zerocopy = true)` returns a `Vector` that shares memory with the series when it
  is numeric without nulls. Don't mutate it.
