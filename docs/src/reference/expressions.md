# Expressions

An `Expr` is an unevaluated column computation — the building block of every polars query.
Expressions are only run when they appear in `select`, `with_columns`, `filter`, or `agg`; until
then, they're just plans describing what to compute. For expressions that *construct* a column
reference or literal from scratch (`col`, `lit`, `when`, ...), see [Functions](@ref).

```@setup expressions
using Polars, Dates
df = DataFrame((; x = [1, 2, 3, 4], y = [true, false, true, false]))
```

```@docs
Polars.Expr
```

## Aggregation

These collapse a column to a single value per group (or one value total for the whole dataframe).

```@docs
sum
min
max
arg_min
arg_max
nan_min
nan_max
mean
median
std
var
quantile
cov
cor
spearman_rank_corr
count
n_unique
Base.first
Base.last
prod
value_counts
```

```@example expressions
select(df, sum(col("x")) |> alias("sum"), mean(col("x")) |> alias("mean"), std(col("x")) |> alias("std"))
```

```@example expressions
dfagg = DataFrame((; x = [3, 1, 4, 2]))
select(
    dfagg,
    min(col("x")) |> alias("min"), max(col("x")) |> alias("max"),
    arg_min(col("x")) |> alias("arg_min"), arg_max(col("x")) |> alias("arg_max"),
    count(col("x")) |> alias("count"), n_unique(col("x")) |> alias("n_unique"),
    first(col("x")) |> alias("first"), last(col("x")) |> alias("last"),
)
```

Unlike `min`/`max`, which ignore `NaN` (it never wins the comparison), `nan_min`/`nan_max`
propagate it — if any value in the group is `NaN`, the result is `NaN`:

```@example expressions
dfnan = DataFrame((; x = [1.0, NaN, 3.0]))
select(dfnan, min(col("x")) |> alias("min"), nan_min(col("x")) |> alias("nan_min"), max(col("x")) |> alias("max"), nan_max(col("x")) |> alias("nan_max"))
```

`cov`/`cor` take two columns rather than one; `cor` is the Pearson correlation coefficient (a
constant column gives `NaN` rather than an error). `spearman_rank_corr` measures monotonic rather
than strictly linear association, so a curved-but-monotonic relationship can score `1.0` there
even though its Pearson correlation is lower:

```@example expressions
df_corr = DataFrame((; x = [1.0, 2.0, 3.0, 4.0], y = [1.0, 8.0, 27.0, 64.0]))
select(
    df_corr,
    cov(col("x"), col("y")) |> alias("cov"),
    cor(col("x"), col("y")) |> alias("pearson"),
    spearman_rank_corr(col("x"), col("y")) |> alias("spearman"),
)
```

`value_counts(expr; sort=false, parallel=false, name="count", normalize=false)` counts occurrences
of each unique value, returning a **Struct** column — a value/count pair per row, with the count
field named `name`. Unpack it with `Structs.field_by_name` (see [`struct`](@ref expr-struct)):

```@example expressions
df5 = DataFrame((; g = ["a", "a", "b", "b", "b"]))
counts = select(df5, value_counts(col("g"); sort = true) |> alias("vc"))
select(counts, Structs.field_by_name(col("vc"), "g"), Structs.field_by_name(col("vc"), "count"))
```

`unique` (distinct values of a column) is documented once, on the [DataFrame](@ref) page (it shares
a name with the frame-level row-dedup verb) — inside `agg`, per-group results are automatically
collected into a `List` (see [`list`](@ref expr-list)) so the aggregation still produces one row
per group:

```@example expressions
dfu = DataFrame((; g = ["a", "a", "b"], x = [1, 1, 2]))
collect(agg(group_by(lazy(dfu), "g"), unique(col("x")) |> alias("distinct_x")))
```

## Boolean

```@docs
not
is_finite
is_infinite
is_nan
is_null
is_not_null
is_duplicated
is_unique
eq
Base.lt
gt
or
xor
and
```

`is_finite`/`is_infinite`/`is_nan`/`is_null`/`is_not_null` are row-wise boolean flags; `not` negates
a boolean expression, matching polars' three-valued logic (`not` of `null` is `null`, not `true`):

```@example expressions
dfflags = DataFrame((; x = Union{Float64, Missing}[1.0, NaN, Inf, missing]))
select(
    dfflags,
    col("x"), is_finite(col("x")) |> alias("finite"), is_infinite(col("x")) |> alias("infinite"),
    is_nan(col("x")) |> alias("nan"), is_null(col("x")) |> alias("null"), is_not_null(col("x")) |> alias("not_null"),
)
```

```@example expressions
select(df, not(col("y")) |> alias("not_y"))
```

`is_duplicated`/`is_unique` are row-wise flags — the expression-level companion to `unique` (see
[DataFrame](@ref)):

```@example expressions
df7 = DataFrame((; x = [1, 1, 2, 3, 3, 3]))
select(df7, col("x"), is_duplicated(col("x")) |> alias("dup"), is_unique(col("x")) |> alias("uniq"))
```

`eq`/`Base.lt`/`gt`/`or`/`xor`/`and` are named-function equivalents of the comparison/logical
operators (`.==`, `.>`, `.\|`, `.&`) — see [Named binary functions](@ref) below for when to reach
for them over the operator form. `Selectors` (see [Selectors](@ref)) also overload `\|`/`&`/`-`/
`xor` for set algebra over *columns matched*, rather than *row values* — the `xor` docstring above
covers both meanings.

## Computation

Math, rounding, and other elementwise numeric transforms.

```@docs
Base.abs
floor
ceil
sqrt
exp
sign
cos
sin
tan
cosh
sinh
tanh
arccos
degrees
radians
Base.log10
Base.log1p
pow
add
sub
mul
Base.div
Base.round
clip
Base.rem
Base.log
Base.diff
pct_change
shift
interpolate
cum_sum
cum_prod
cum_min
cum_max
cum_count
rank
null_count
has_nulls
drop_nans
Base.replace
replace_strict
fill_null
fill_nan
Base.coalesce
```

```@example expressions
select(df, ((col("x") + 1) * 2) |> alias("plus_one_times_two"), (col("x") ^ 2) |> alias("squared"))
```

The named unary/binary functions work the same as their operator forms:

```@example expressions
dfmath = DataFrame((; x = [-4.0, 9.0, 2.5]))
select(
    dfmath,
    abs(col("x")) |> alias("abs"), floor(col("x")) |> alias("floor"), ceil(col("x")) |> alias("ceil"),
    sqrt(abs(col("x"))) |> alias("sqrt"), exp(col("x")) |> alias("exp"), sign(col("x")) |> alias("sign"),
)
```

```@example expressions
select(dfmath, pow(col("x"), lit(2.0)) |> alias("squared"), log(lit(2.0), abs(col("x"))) |> alias("log2"), rem(col("x"), lit(3.0)) |> alias("rem3"))
```

```@example expressions
dftrig = DataFrame((; theta = [0.0, pi / 2, pi]))
select(
    dftrig,
    cos(col("theta")) |> alias("cos"), sin(col("theta")) |> alias("sin"), tan(col("theta")) |> alias("tan"),
    cosh(col("theta")) |> alias("cosh"), sinh(col("theta")) |> alias("sinh"), tanh(col("theta")) |> alias("tanh"),
)
```

`arccos`/`degrees`/`radians` round out the trigonometry family; `log10`/`log1p` round out `log`
(`log10` is pure Julia composition over the binary `log` -- there is no dedicated `Expr::log10`
upstream).

!!! note "`log` takes the base first"
    `log(base, x)` matches `Base.log`'s own argument order (`log(2, 8) == 3`), **not** polars'
    `Expr.log(base)`, which takes the value first. Since both arguments are expressions, a flipped
    call is silently wrong rather than an error -- write `log(lit(2), col("x"))` for log base 2.

```@example expressions
dfmath2 = DataFrame((; x = [1.0, 100.0], theta = [1.0, 0.0]))
select(
    dfmath2,
    arccos(col("theta")) |> alias("arccos"), degrees(col("theta")) |> alias("degrees"), radians(col("theta")) |> alias("radians"),
    log10(col("x")) |> alias("log10"), log1p(col("x")) |> alias("log1p"),
)
```

`null_count` counts nulls the way `count` counts non-nulls:

```@example expressions
dfflags2 = DataFrame((; x = Union{Float64, Missing}[1.0, NaN, Inf, missing]))
select(dfflags2, null_count(col("x")) |> alias("nulls"), drop_nans(col("x")) |> alias("no_nans"))
```

`fill_nan` replaces `NaN` values, the `NaN`-specific counterpart to `fill_null`:

```@example expressions
dfnan2 = DataFrame((; x = [1.0, NaN, 3.0]))
select(dfnan2, fill_nan(col("x"), lit(0.0)) |> alias("filled"))
```

`shift`/`pct_change` look back (or, with a negative argument, ahead) within the column:

```@example expressions
dfshift = DataFrame((; x = [10, 20, 30]))
select(dfshift, shift(col("x"), lit(1)) |> alias("shifted"), pct_change(col("x"), lit(1)) |> alias("pct_change"))
```

`coalesce(exprs...)` returns the first non-null value among `exprs`, evaluated left to right:

```@example expressions
df11 = DataFrame((; a = [missing, 2, missing], b = [1, missing, missing], c = [9, 9, 9]))
select(df11, coalesce(col("a"), col("b"), col("c")) |> alias("first_non_null"))
```

`interpolate(expr; method=:linear)` fills `null`s by interpolating between the surrounding non-null
values (`:linear` or `:nearest`); pairs naturally with `upsample` (see [DataFrame](@ref)):

```@example expressions
df12 = DataFrame((; x = [missing, 1.0, missing, missing, 4.0, missing]))
select(df12, interpolate(col("x")) |> alias("linear"), interpolate(col("x"); method = :nearest) |> alias("nearest"))
```

`replace`/`replace_strict` replace values by an explicit old→new mapping, unlike `fill_null`'s
fixed/strategy-based fill:

```@example expressions
df6 = DataFrame((; x = ["a", "b", "c", "d"]))
select(df6, replace(col("x"), lit(["a", "c"]), lit(["A", "C"])) |> alias("r"))
```

```@example expressions
select(df6, replace_strict(col("x"), lit("a"), lit("A"); default = lit("?")) |> alias("r"))
```

`replace_strict`'s strict counterpart raises an error rather than silently passing values through
when `default` is omitted **and** the mapping doesn't cover every value in the column (matches
upstream polars semantics).

`fill_null` also has a keyword form (a fill *strategy* instead of a fixed value):

```@example expressions
dffs = DataFrame((; x = [1, missing, missing, 4]))
select(dffs, fill_null(col("x"); strategy = :forward) |> alias("ffill"))
```

## Manipulation/selection

```@docs
implode
flatten
reverse
is_in
top_k
arg_sort
gather
gather_every
sort_by
over
as_struct
sample_n
sample_frac
rle
rle_id
```

`reverse` reverses row order; `flatten` is the expression-level inverse of `implode` — it explodes
a `List`-typed column back into one row per element (see [`list`](@ref expr-list)):

```@example expressions
dfshape = DataFrame((; x = [10, 20, 30]))
select(dfshape, reverse(col("x")) |> alias("reversed"))
```

```@example expressions
imploded = select(dfshape, implode(col("x")) |> alias("x"))
select(imploded, flatten(col("x")) |> alias("flattened"))
```

`over(expr, partition_by...)` broadcasts a per-group result back to all rows in the group; `rank`
ranks within a group:

```@example expressions
df2 = DataFrame((; g = ["a", "a", "b", "b"], x = [1, 2, 3, 4]))
select(df2, col("x"), over(sum(col("x")), "g") |> alias("group_sum"))
```

`sort_by(expr, by...)` sorts `expr`'s values according to a *different* expression/column than
`expr` itself — typically used inside `agg`/`over` for "most recent row per group" or "top N per
group" style queries:

```@example expressions
df3 = DataFrame((; g = ["a", "a", "b", "b", "b"], t = [2, 1, 3, 1, 2], x = [20, 10, 30, 5, 15]))
select(df3, col("x") |> sort_by("t"; rev = true))
```

```@example expressions
with_columns(df3, (sum(col("x")) |> over("g")) |> alias("group_total"))
```

`sample_n`/`sample_frac` randomly sample values, both accepting a `seed` for reproducibility:

```@example expressions
df4 = DataFrame((; x = collect(1:10)))
select(df4, sample_n(col("x"), 3; seed = 42))
```

`gather(expr, idx)` takes values by index; `gather_every(expr, n; offset)` takes every `n`th value.

`gather`'s indices are **0-based**, and negative indices count from the end. `nth` and
`Selectors.by_index` are 1-based instead, because they pick a column from a position written
literally in the call, where Julia's own 1-based convention applies. `gather`'s `idx` is data
rather than a literal — it usually comes from `arg_sort`, `arg_min` or `arg_max`, which return
0-based positions — so `gather` shares their convention and `gather(x, arg_sort(y))` composes
without an offset.

```@example expressions
df_gather = DataFrame((; x = [10, 20, 30, 40]))
select(df_gather, gather(col("x"), lit([0, -1])) |> alias("first_last"))
```

```@example expressions
select(df_gather, gather_every(col("x"), 2) |> alias("every_other"))
```

By default (`null_on_oob = false`), an out-of-bounds `gather` index raises rather than silently
returning `missing`; pass `null_on_oob = true` to get `missing` for out-of-range positions instead.

### Run-length encoding: `rle`/`rle_id`

`rle` collapses consecutive runs of identical values into one row per run (a `Struct{len, value}`
— see [Struct](@ref expr-struct)); `rle_id` instead keeps one row per input row, mapping each to a 0-indexed
run ID that increments at every run boundary:

```@example expressions
df5 = DataFrame((; x = [1, 1, 2, 2, 2, 3]))
select(df5, rle(col("x")))
```

```@example expressions
select(df5, col("x"), rle_id(col("x")) |> alias("run_id"))
```

## Name

```@docs
alias
prefix
suffix
to_lowercase
to_uppercase
keep_name
```

```@example expressions
dfk = DataFrame((; x = [1, 2, 3]))
select(dfk, keep_name(alias(col("x"), "renamed")))
```

## [Casting](@id casting)

```@docs
cast
cast_datetime
cast_duration
cast_decimal
cast_categorical
```

`cast(expr, dtype)` handles every plain, parameter-free dtype (`Bool`, `Int64`, `Float64`,
`String`, ...); `cast_datetime`/`cast_duration`/`cast_categorical`/`cast_decimal` cover the
dtypes that need extra parameters a single-type argument can't carry (time unit/zone, precision/
scale).

```@example expressions
dfc = DataFrame((; ns = Int64[0, 3_600_000_000_000]))
select(dfc, cast_duration(col("ns"); time_unit = :ns) |> alias("d"))
```

## Named binary functions

Every arithmetic/comparison/logical operator has a named-function equivalent. These matter when an
expression is built programmatically — e.g. picking which comparison to apply from a variable
instead of hardcoding an infix operator.

| Function | Operator equivalent |
|---|---|
| `eq(a, b)` | `a .== b` |
| `gt(a, b)` | `a .> b` |
| `and(a, b)` | `a .& b` |
| `or(a, b)` | `a .\| b` |
| `add(a, b)`, `sub(a, b)`, `mul(a, b)`, `div(a, b)`, `pow(a, b)` | `+`, `-`, `*`, `/`, `^` |
| `xor(a, b)` | *(no operator equivalent)* |
| `Base.lt(a, b)` | `<` (or use `.>` and flip arguments; `<` is not exported from Base) |

```@example expressions
comparisons = Dict("gt" => gt, "eq" => eq)
op = comparisons["gt"] # picked at runtime, e.g. from user input
select(df, op(col("x"), lit(2)) |> alias("cmp"))
```

`xor` has no operator form at all, so it's the only one of these that must be called by name:

```@example expressions
select(df, xor(col("y"), lit(true)) |> alias("not_y"))
```

```@example expressions
dfbin = DataFrame((; a = [1, 2, 3], b = [3, 2, 1]))
select(dfbin, eq(col("a"), col("b")) |> alias("eq"), and(col("a") .> 1, col("b") .> 1) |> alias("and"), or(col("a") .> 2, col("b") .> 2) |> alias("or"))
```

```@example expressions
select(dfbin, add(col("a"), col("b")) |> alias("add"), sub(col("a"), col("b")) |> alias("sub"), mul(col("a"), col("b")) |> alias("mul"), div(col("a"), col("b")) |> alias("div"))
```

`Base.lt` is bound under `Base.lt` (not plain `lt`) since the bare name collides with an
*unexported* internal `Base` binding — call it qualified, or use `.>` with the arguments flipped:

```@example expressions
select(df, Base.lt(col("x"), lit(3)))
```

The product aggregation is bound to `prod` (an *exported* Base name, like `sum`/`mean`), so plain
`prod(expr)` resolves with no qualification, same as the rest of the [Aggregation](@ref) table
above.

## Curried forms for pipe-based composition

Most binary `Expr` functions — anything that takes an expression plus one or more extra arguments
with no natural operator equivalent — have a curried (`Base.Fix2`-style) form: call it with just
the extra arguments to get back a one-argument function, for `expr |> f(args...)` instead of
`f(expr, args...)`. This reads naturally inside a `@chain` or a long `|>` pipeline, mirroring
Python polars' fluent `.method(...)` chaining style.

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
| `Statistics.std(expr; ddof)`, `Statistics.var(expr; ddof)` | `std(; ddof)`, `var(; ddof)` |

```@example expressions
df9 = DataFrame((; x = [1, 2, 3, 4, missing]))
filter(df9, col("x") |> is_in([2, 4]))
```

```@example expressions
select(df9, col("x") |> fill_null(0) |> clip(0, 3))
```

**`over`/`sort_by`'s curried forms only accept column-name `String`s, not `Expr`s** — passing an
`Expr` is ambiguous with the non-curried form's own leading `expr` argument, and always resolves to
that instead. For expression-valued partition/sort keys, call the non-curried
`over(expr, partition_by...)` / `sort_by(expr, by...)` directly.

**Deliberately not curried:** `log`, `rem`, `replace`, `diff`, `round` — call these in their full,
non-curried form (`f(expr, args...)`). See [Developer](@ref) for why.

```@example expressions
df13 = DataFrame((; g = ["a", "a", "b"], x = [3, 1, 2]))
select(df13, col("x") |> arg_sort(descending = true) |> alias("order"), col("x") |> cum_max() |> alias("running_max"))
```

## `lit(::Vector)` for multi-value membership and replacement

A plain Julia `Vector` can be wrapped in `lit(...)` to build a multi-value literal expression. The
two functions that consume it have different conventions:

- `is_in(expr, values)`: wrap the vector in `implode(lit(...))` — `is_in(col("x"), implode(lit([2,
  4])))`. Polars emits a deprecation warning for the bare `is_in(col("x"), lit([2, 4]))` form, so
  prefer the `implode`-wrapped one.
- `replace(expr, old, new)`: use `lit([...])` directly, with no `implode` wrapping.

```@example expressions
df8 = DataFrame((; x = [1, 2, 3, 4]))
filter(df8, is_in(col("x"), implode(lit([2, 4]))))
```
