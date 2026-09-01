# Functions

Top-level functions that construct an [`Expr`](@ref Expressions) from scratch — column references,
literals, conditionals, and row-wise reductions across several expressions at once.

```@setup functions
using Polars
```

## Column references

```@docs
col
nth
element
```

`col(name)` references a column by name (or `"*"` for all); `nth(n)` references the `n`th column
(1-indexed; negative counts from the end). `element()` is a placeholder for "the values in this
group", used to build `pivot`'s `agg` argument (see [DataFrame](@ref)).

To reference columns *by dtype, position, or name pattern* instead of one at a time, see
[Selectors](@ref).

## Literals & casting

```@docs
lit
when
```

`lit(x)` turns a scalar value into an expression (broadcasts in operations); it also accepts a
`Dates.Date`/`Dates.Time`/`Dates.DateTime` directly:

```@example functions
using Dates
dfdate = DataFrame((; d = [Date(2024, 3, 15), Date(2024, 3, 16), Date(2024, 3, 17)]))
filter(dfdate, col("d") == lit(Date(2024, 3, 15)))
```

!!! note "Two caveats"
    - `Polars.Meta.is_literal(lit(Date(...)))` is `false` — see [Meta](@ref expr-meta) and
      [Limitations](@ref).
    - A `DateTime` literal is built at nanosecond resolution, so it inherits the same
      ~1678–2262 range limit as any other nanosecond-precision `DateTime` column in this package
      — see [Limitations](@ref).

`when(cond, then, otherwise)` — ternary: evaluates to `then` where `cond` is true, `otherwise`
elsewhere. Both branches can be `Expr`s or scalar values (promoted via `lit`). A chained
`when(pairs...; otherwise)` form is also available for multi-branch conditionals.

```@example functions
df = DataFrame((; x = [1, 2, 3, 4], y = [true, false, true, false]))
select(df, when(col("y"), lit("yes"), lit("no")))
```

For `cast`/`cast_datetime`/`cast_duration`/`cast_decimal`/`cast_categorical`, see
[Casting](@ref casting) on the Expressions page.

## Horizontal (row-wise) reductions

```@docs
all_horizontal
any_horizontal
min_horizontal
max_horizontal
sum_horizontal
mean_horizontal
```

Each takes a list of expressions and reduces **across them, per row** — the row-wise counterpart to
the (per-column, per-group) aggregation functions on the [Expressions](@ref) page. Each defaults to
an output name matching its own function name (`"all"`, `"min"`, `"sum"`, ...) unless `alias`ed.
`sum_horizontal`/`mean_horizontal` take an `ignore_nulls` keyword (default `true`: treat nulls as
`0`/exclude them from the average; `false`: any null in a row makes that row's result `null`).

```@example functions
df10 = DataFrame((; a = [1, 2, missing], b = [4, missing, 6], c = [7, 8, 9]))
select(
    df10,
    min_horizontal(col("a"), col("b"), col("c")) |> alias("row_min"),
    sum_horizontal(col("a"), col("b"), col("c")) |> alias("row_sum"),
)
```

## String & array combination

```@docs
format
concat_arr
```

`format(fmt, args...)` fills a `{}`-templated string with `args`, one per placeholder, row-wise —
the row-wise counterpart of `Base.string` over several columns. `concat_arr(exprs...)` combines
`exprs` row-wise into a fixed-size `Array` column; see its docstring for the current limitation on
materializing/introspecting an `Array`-dtype result.

```@example functions
df11 = DataFrame((; name = ["a", "b"], age = [1, 2]))
select(df11, format("{} is {}", col("name"), col("age")) |> alias("greeting"))
```

## Temporal constructors

```@docs
datetime
duration
date
Base.time(::Any, ::Any, ::Any, ::Any)
from_epoch
```

`datetime`/`date`/`Base.time` build a `Datetime`/`Date`/`Dates.Time` column from component
expressions (year/month/day, hour/minute/second/microsecond); `duration` builds a `Duration`
column from a set of unit-named components. `from_epoch` is the inverse of `Dt.epoch`: it
interprets an integer column as a count of `time_unit`s since the Unix epoch.

```@example functions
dft = DataFrame((; y = [2024, 2025], m = [1, 6], d = [15, 30]))
select(dft, datetime(col("y"), col("m"), col("d"); hour = 12) |> alias("dt"))
```
