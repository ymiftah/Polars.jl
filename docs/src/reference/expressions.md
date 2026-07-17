# Expressions

An `Expr` is an unevaluated column computation — the building block of every polars query. Expressions are only run when they appear in `select`, `with_columns`, `filter`, or `agg`; until then, they're just plans describing what to compute.

```@setup expressions
using Polars
```

## Column references

| Function | Purpose |
|---|---|
| `col(name)` | reference a column by name (or "*" for all) |
| `nth(n)` | reference the nth column (1-indexed; negative from end) |
| `element()` | placeholder for "the values in this group"; used to build `pivot`'s `agg` argument (see [Manipulation](@ref)) |

## Literals & casting

| Function | Purpose |
|---|---|
| `lit(x)` | turn a scalar value into an expression (broadcasts in operations) |
| `cast(expr, dtype)` | cast to a different type (Bool, Int64, Float64, String, etc.) |
| `alias(expr, name)` | rename the result |
| `prefix(expr, str)` | prepend to the name |
| `suffix(expr, str)` | append to the name |
| `keep_name(expr)` | keep the input's original name through an operation that would otherwise rename it |

## Conditional logic

`when(cond, then, otherwise)` — ternary: evaluates to `then` where `cond` is true, `otherwise` elsewhere. Both branches can be `Expr`s or scalar values (promoted via `lit`).

```@example expressions
df = DataFrame((; x = [1, 2, 3, 4], y = [true, false, true, false]))
select(df, when(col("y"), lit("yes"), lit("no")))
```

## Aggregation functions

These collapse a column to a single value per group (or one value total for the whole dataframe):

| Function | Purpose |
|---|---|
| `sum`, `prod`, `mean`, `median`, `min`, `max` | basic stats |
| `arg_min`, `arg_max` | index of min/max value |
| `nan_min`, `nan_max` | min/max ignoring NaN |
| `std`, `var` | standard deviation, variance (ddof=1 by default) |
| `quantile(expr, q)` | qth quantile |
| `count` | number of non-null values |
| `n_unique` | count distinct values |
| `first`, `last` | first/last value |
| `unique` | distinct values (returns a list) |

```@example expressions
select(df, sum(col("x")) |> alias("sum"), mean(col("x")) |> alias("mean"), std(col("x")) |> alias("std"))
```

## Horizontal (row-wise) reductions

`all_horizontal`, `any_horizontal`, `min_horizontal`, `max_horizontal`, `sum_horizontal`, and
`mean_horizontal` all take a list of expressions and reduce **across them, per row** — the row-wise
counterpart to the (per-column, per-group) aggregation functions above. Each defaults to an output
name matching its own function name (`"all"`, `"min"`, `"sum"`, ...) unless `alias`ed.
`sum_horizontal`/`mean_horizontal` take an `ignore_nulls` keyword (default `true`: treat nulls as
`0`/exclude them from the average; `false`: any null in a row makes that row's result `null`).

```@example expressions
df10 = DataFrame((; a = [1, 2, missing], b = [4, missing, 6], c = [7, 8, 9]))
select(
    df10,
    min_horizontal(col("a"), col("b"), col("c")) |> alias("row_min"),
    sum_horizontal(col("a"), col("b"), col("c")) |> alias("row_sum"),
)
```

## Math & type inspection

| Unary | Binary | |
|---|---|---|
| `abs`, `floor`, `ceil`, `sqrt`, `exp` | `pow`, `log` (base e; or with base arg), `rem`, `shift` | arithmetic via `+`, `-`, `*`, `/`, `^` |
| `sign`, `is_finite`, `is_infinite`, `is_nan` | `fill_null(expr, value)`, `fill_nan(expr, value)` | comparison via `.>`, `.>=`, `.==`, etc. |
| `round(expr, decimals)`, `clip(expr, min, max)` | | logical via `.&`, `.|` |
| `not` | | |
| `is_null`, `is_not_null`, `null_count` | | |
| `drop_nans`, `drop_nulls` | `pct_change(expr, n)` | |

```@example expressions
select(df, ((col("x") + 1) * 2) |> alias("plus_one_times_two"), (col("x") ^ 2) |> alias("squared"))
```

## Named binary functions

Every arithmetic/comparison/logical operator has a named-function equivalent. These matter when an
expression is built programmatically — e.g. picking which comparison to apply from a variable
instead of hardcoding an infix operator:

| Function | Operator equivalent |
|---|---|
| `eq(a, b)` | `a .== b` |
| `gt(a, b)` | `a .> b` |
| `and(a, b)` | `a .& b` |
| `or(a, b)` | `a .\| b` |
| `add(a, b)`, `sub(a, b)`, `mul(a, b)`, `div(a, b)`, `pow(a, b)` | `+`, `-`, `*`, `/`, `^` |
| `xor(a, b)` | *(no operator equivalent)* |

```@example expressions
comparisons = Dict("gt" => gt, "eq" => eq)
op = comparisons["gt"] # picked at runtime, e.g. from user input
select(df, op(col("x"), lit(2)) |> alias("cmp"))
```

`xor` has no operator form at all, so it's the only one of these that must be called by name:

```@example expressions
select(df, xor(col("y"), lit(true)) |> alias("not_y"))
```

## Combining columns: `coalesce`

`coalesce(exprs...)` returns the first non-null value among `exprs`, evaluated left to right —
extends `Base.coalesce` (an exported Base name, so it works bare like `sum`/`mean`/`prod`; unlike
plain `Base.coalesce`, this method is restricted to `Expr` arguments only, to avoid Aqua flagging
it as type piracy against Base's own version, which still works unchanged on plain Julia values).

```@example expressions
df11 = DataFrame((; a = [missing, 2, missing], b = [1, missing, missing], c = [9, 9, 9]))
select(df11, coalesce(col("a"), col("b"), col("c")) |> alias("first_non_null"))
```

## Filling gaps: `interpolate`

`interpolate(expr; method=:linear)` fills `null`s by interpolating between the surrounding
non-null values: `:linear` (default) or `:nearest`. Leading/trailing `null`s with no non-null
value on one side stay `null`. Pairs naturally with `upsample` (see [Manipulation](@ref)) to
gap-fill a time series to a regular grid and then interpolate the inserted values.

```@example expressions
df12 = DataFrame((; x = [missing, 1.0, missing, missing, 4.0, missing]))
select(df12, interpolate(col("x")) |> alias("linear"), interpolate(col("x"); method = :nearest) |> alias("nearest"))
```

## Shaping & rearranging

| Function | Purpose |
|---|---|
| `implode` | collect a column into a list (use within `group_by` + `agg`) |
| `flatten` | explode a list column back to rows |
| `reverse` | reverse the order |
| `is_in(expr, values)` | check membership |
| `top_k(expr, k)` | the `k` largest elements (not necessarily sorted — combine with `sort_by`) |
| `arg_sort(expr; descending=false, nulls_last=false)` | index values that would sort `expr` |
| `as_struct(exprs...)` | collect `exprs` into one Struct-typed expression, one field per input (see [Structs](@ref)) |

## Windowing and ranking

| Function | Purpose |
|---|---|
| `over(expr, partition_by...)` | broadcast a per-group result back to all rows in the group |
| `rank(method=:dense)` | rank within a group (dense/ordinal/min/max/average methods) |
| `cum_sum`, `cum_prod`, `cum_min`, `cum_max`, `cum_count` | cumulative operations (can reverse=true) |
| `diff(n)` | discrete difference with prior n rows |

```@example expressions
df2 = DataFrame((; g = ["a", "a", "b", "b"], x = [1, 2, 3, 4]))
select(df2, col("x"), over(sum(col("x")), "g") |> alias("group_sum"))
```

## Curried forms for pipe-based composition

Most binary `Expr` functions — anything that takes an expression plus one or more extra
arguments with no natural operator equivalent — have a curried (`Base.Fix2`-style) form: call it
with just the extra arguments to get back a one-argument function, for `expr |> f(args...)`
instead of `f(expr, args...)`. This reads naturally inside a `@chain` or a long `|>` pipeline,
mirroring Python polars' fluent `.method(...)` chaining style.

| Function | Curried form |
|---|---|
| `is_in(expr, values)` | `is_in(values)` — a bare `Vector` is auto-wrapped in `implode(...)` (see `lit(::Vector)` below) |
| `fill_null(expr, value)` | `fill_null(value)` |
| `fill_nan(expr, value)` | `fill_nan(value)` |
| `shift(expr, n)` | `shift(n)` |
| `pct_change(expr, n)` | `pct_change(n)` |
| `clip(expr, min, max)` | `clip(min, max)` |
| `replace_strict(expr, old, new; default)` | `replace_strict(old, new; default)` |
| `quantile(expr, q; method)` | `quantile(q; method)` |
| `top_k(expr, k)` | `top_k(k)` |
| `sample_n(expr, n; ...)` | `sample_n(n; ...)` |
| `sample_frac(expr, frac; ...)` | `sample_frac(frac; ...)` |
| `over(expr, partition_by...)` | `over(partition_by::String...)` |
| `sort_by(expr, by...; ...)` | `sort_by(by::String...; ...)` |
| `arg_sort(expr; descending, nulls_last)` | `arg_sort(; descending, nulls_last)` |
| `rank(expr; method, descending)` | `rank(; method, descending)` |
| `value_counts(expr; sort, parallel, name, normalize)` | `value_counts(; sort, parallel, name, normalize)` |
| `interpolate(expr; method)` | `interpolate(; method)` |
| `cum_sum`/`cum_prod`/`cum_min`/`cum_max`/`cum_count(expr; reverse)` | `cum_sum`/`cum_prod`/`cum_min`/`cum_max`/`cum_count(; reverse)` |
| `std(expr; ddof)`, `var(expr; ddof)` | `std(; ddof)`, `var(; ddof)` |

```@example expressions
df9 = DataFrame((; x = [1, 2, 3, 4, missing]))
filter(df9, col("x") |> is_in([2, 4]))
```

```@example expressions
select(df9, col("x") |> fill_null(0) |> clip(0, 3))
```

**`over`/`sort_by`'s curried forms only accept column-name `String`s, not `Expr`s** — passing an `Expr` is ambiguous with the non-curried form's own leading `expr` argument, and always resolves to that instead. For expression-valued partition/sort keys, call the non-curried `over(expr, partition_by...)` / `sort_by(expr, by...)` directly.

**Deliberately not curried:** `log`, `rem`, `replace`, `diff`, `round`. These are `Base`-qualified,
and since `Expr <: Number` (for promotion — see [Structures](@ref)), an untyped 1-argument curry
would be genuinely ambiguous with Base's own generic methods for `Number` — a real dispatch
conflict, not just a style mismatch (e.g. a `round(decimals::Integer)` curry would collide with
Base's own existing `round(::Integer)` method).

```@example expressions
df13 = DataFrame((; g = ["a", "a", "b"], x = [3, 1, 2]))
select(df13, col("x") |> arg_sort(descending = true) |> alias("order"), col("x") |> cum_max() |> alias("running_max"))
```

`sort_by(expr, by...)` sorts `expr`'s values according to a *different* expression/column than `expr` itself — typically used inside `agg`/`over` for "most recent row per group" or "top N per group" style queries:

```@example expressions
df3 = DataFrame((; g = ["a", "a", "b", "b", "b"], t = [2, 1, 3, 1, 2], x = [20, 10, 30, 5, 15]))
select(df3, col("x") |> sort_by("t"; rev = true))
```

```@example expressions
with_columns(df3, (sum(col("x")) |> over("g")) |> alias("group_total"))
```

## Sampling

| Function | Purpose |
|---|---|
| `sample_n(expr, n; with_replacement=false, shuffle=false, seed=nothing)` | randomly sample `n` values |
| `sample_frac(expr, frac; with_replacement=false, shuffle=false, seed=nothing)` | randomly sample a `frac` fraction of values |

Both accept a `seed` for reproducible sampling.

```@example expressions
df4 = DataFrame((; x = collect(1:10)))
select(df4, sample_n(col("x"), 3; seed = 42))
```

## Counting occurrences: `value_counts`

`value_counts(expr; sort=false, parallel=false, name="count", normalize=false)` counts occurrences of each unique value, returning a **Struct** column — a value/count pair per row, with the count field named `name` (default `"count"`). Unpack it with `Structs.field_by_name` (see [Structs](@ref)). If `sort` is `true`, rows come back ordered by count descending; if `normalize` is `true`, counts become fractions of the total.

```@example expressions
df5 = DataFrame((; g = ["a", "a", "b", "b", "b"]))
counts = select(df5, value_counts(col("g"); sort = true) |> alias("vc"))
select(counts, Structs.field_by_name(col("vc"), "g"), Structs.field_by_name(col("vc"), "count"))
```

## Replacing values: `replace` and `replace_strict`

`Base.replace(expr, old, new)` replaces values equal to `old` with the corresponding `new` value, leaving anything not found in `old` unchanged. It extends `Base.replace`, which — unlike `lt` below — *is* auto-visible bare (no `Base.` qualification needed at the call site), same precedent as `Base.diff`/`Base.round`/`Base.log`/`Base.prod`. `old`/`new` are typically `lit(vector)` for multi-value mappings.

`replace_strict(expr, old, new; default=nothing)` is the strict counterpart: a value not found in `old` becomes `default` if given — but if `default` is omitted **and** the mapping doesn't cover every value in the column, it raises an error rather than silently passing values through (matches upstream polars semantics; this is stricter than "falls back to `null`").

```@example expressions
df6 = DataFrame((; x = ["a", "b", "c", "d"]))
select(df6, Base.replace(col("x"), lit(["a", "c"]), lit(["A", "C"])) |> alias("r"))
```

```@example expressions
select(df6, replace_strict(col("x"), lit("a"), lit("A"); default = lit("?")) |> alias("r"))
```

## Duplicate detection: `is_duplicated` and `is_unique`

Row-wise boolean flags — the expression-level companion to `unique` in [Manipulation](@ref), useful for inspecting duplicates before deciding how to dedupe:

```@example expressions
df7 = DataFrame((; x = [1, 1, 2, 3, 3, 3]))
select(df7, col("x"), is_duplicated(col("x")) |> alias("dup"), is_unique(col("x")) |> alias("uniq"))
```

## `lit(::Vector)` for multi-value membership and replacement

A plain Julia `Vector` can be wrapped in `lit(...)` to build a multi-value literal expression. The two functions that consume it have different conventions:

- `is_in(expr, values)`: wrap the vector in `implode(lit(...))` — `is_in(col("x"), implode(lit([2, 4])))`. Polars emits a deprecation warning for the bare `is_in(col("x"), lit([2, 4]))` form, so prefer the `implode`-wrapped one.
- `Base.replace(expr, old, new)`: use `lit([...])` directly, with no `implode` wrapping — see the example above.

```@example expressions
df8 = DataFrame((; x = [1, 2, 3, 4]))
filter(df8, is_in(col("x"), implode(lit([2, 4]))))
```

## Operator overloading gotchas

Most functions work through operator overloading (`+`, `-`, `*`, `/`, `^`, `.>`, `.==`, etc.), but one collides with an unexported `Base` name and requires qualification:

- `Base.lt(expr1, expr2)` for `<` (or use `.>` and flip arguments; `<` is not exported from Base)

```@example expressions
select(df, Base.lt(col("x"), lit(3)))
```

This used to also apply to the product aggregation, which collided with an unexported internal
`Base.product` binding — it's since been renamed to `prod` (an *exported* Base name, like
`sum`/`mean`), so plain `prod(expr)` now resolves with no qualification, same as the rest of the
[Aggregation functions](@ref) table above.
