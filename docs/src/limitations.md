# Limitations

Known gaps and sharp edges in Polars.jl worth skimming before you hit them.

## I/O limitations

- **CSV scanning has no `hive_partitioning` option, unlike parquet/IPC.** Hive partitioning is
  always disabled for CSV scans, with no way to turn it on. See [Developer](@ref) for why.

- **`allow_missing_columns` (parquet/CSV/IPC scan options) only covers files *missing* a column
  present in the reference schema, not files with an *extra* column beyond it.** The reference
  schema is whichever file/fragment gets scanned first, so ordering matters when relying on this
  option. `scan_parquet` additionally takes `allow_extra_columns` for the converse case (an extra
  column is silently dropped rather than raising) — **`scan_csv`/`scan_ipc` have no equivalent.**
  See [Developer](@ref) for why.

- **A `Decimal`-typed column can be queried/cast (`cast_decimal`, `Selectors.decimal()`) but not
  materialized back into Julia.** Reading its values (`df[:col]`) raises an error — there's no
  Julia-side decimal type this package maps it to yet, unlike every other dtype in
  [Data types](@ref). Keep decimal columns on the lazy/query side (cast to `Float64`/`String`
  before collecting if you need the values in Julia).

- **An `Array` (fixed-size list)-typed column can be selected/built from an existing List column
  (`Selectors.array()`, `Lists.to_array`) but not materialized back into Julia**, same shape of gap
  as `Decimal` above — the Arrow schema decoder recognizes the format but has no read path for it
  yet. Select/pass the column onward instead of collecting its values directly (e.g. write straight
  to parquet, or cast to a `String`/scalar column first).

- **A `Categorical`/`Enum`-typed column materializes as plain `String`/`missing` by default, and
  as a `CategoricalArrays.CategoricalArray` once `CategoricalArrays.jl` is loaded** (`using
  CategoricalArrays`) — see [Developer](@ref) for the extension mechanism. Either way, `dtype`
  cannot distinguish a Categorical/Enum column from a plain String one; only the Arrow schema
  carries that distinction, and this package doesn't expose it directly. The `CategoricalArray`'s
  levels are derived only from the values that actually appear in the column being read (in
  `CategoricalArrays.categorical`'s own default order) — a category defined elsewhere in the
  global category registry but never used in this particular column does not appear as a level.

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

- **No `slice` option on any join verb** (`innerjoin`, `leftjoin`, ..., `join_asof`). Verified live
  that `JoinArgs.slice` panics unconditionally in the current polars version regardless of collect
  engine (`"impl error: slice is not handled"`) — caught cleanly as a `PolarsError`, not a crash,
  but there is no working codepath behind it to expose. `head`/`tail` on the joined result cover
  the common cases (e.g. `head(innerjoin(a, b, "k"), 10)`); there is no offset+length frame-level
  `slice` yet either (see `plans/parity/api_gap_audit.md`'s Group 6).

- **`Polars.Meta.is_literal` reports `false` for a `Date`/`Time`/`DateTime` literal**
  (`lit(Date(2024, 1, 1))`, etc.), diverging from py-polars. These are built as a cast over an
  integer literal rather than a genuine `Literal` node (see [Literals & casting](@ref)), so
  `is_literal` correctly reports what the expression tree actually contains. This is cosmetic
  only and has no effect on query results or performance.

## Exports

A number of functions and one whole submodule are deliberately not exported — always reached
qualified (`Polars.foo(...)` or `Namespace.foo(...)`) even after `using Polars`. Two reasons
account for all of them:

- **Name collision with an existing `Base` binding** (exported or not) — exporting would shadow,
  or conflict with, that name in every module that does `using Polars`.
- **Deliberately left open for an extension package's own generic** — the bare name resolves to
  that package's function once its extension is loaded (StatsBase.jl, CategoricalArrays.jl), and
  to nothing at all otherwise; the qualified `Polars.foo(...)` form works either way.

| Name | Reached as | Why |
|---|---|---|
| `item` (`DataFrame`/`Series`/`Expr` aggregation) | `Polars.item(...)` | Generic, collision-prone name |
| `version` | `Polars.version()` | Generic, collision-prone name |
| `kurtosis` | `Polars.kurtosis(...)` | Left open for StatsBase.jl's own `kurtosis` |
| `cut` | `Polars.cut(...)` | Left open for CategoricalArrays.jl's own `cut` |
| `Base.lt` | `Base.lt(...)` | Collides with an unexported internal `Base` binding |
| `Dt.time` | `Dt.time(...)` | Collides with `Base.time` |
| `Strings.contains`/`replace`/`join`/`reverse` | `Strings.foo(...)` | Collide with the matching `Base` names |
| `Lists.tail`/`shift`/`gather`/`gather_every`/`sample_n`/`union`/`std`/`var`/`agg`/`get`/`contains`/`head` | `Lists.foo(...)` | Collide with the matching top-level `Polars`/`Base` names |
| `Lists.apply` | `Lists.apply(...)` | Deliberately left qualified-only (no collision) |
| `Selectors.all`/`float`/`string`/`time`/`contains` | `Selectors.foo(...)` | Collide with the matching `Base` names |
| `Meta` (whole submodule) | `Polars.Meta.foo(...)` | `Base.Meta` is itself an exported `Base` submodule; exporting `Meta` too would make plain `using Polars` immediately ambiguous-error on the bare name |

See [Developer](@ref) for the full API-design rationale behind these choices.

## Feature coverage

- Some polars capabilities aren't compiled into this package's build. If you hit an "activate 'X'
  feature" panic message, please open an issue.

- **No `.arr` namespace (operations on Array-dtype columns) and no direct construction from raw
  Julia nested data.** `Selectors.array()` and `Lists.to_array` (List → Array, given a fixed width)
  cover selection and List-to-Array construction — there is simply nothing else that operates on an
  Array column once built, and no path straight from a Julia nested literal to one.

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
