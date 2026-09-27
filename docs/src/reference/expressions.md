# Expressions

An `Expr` describes a computation on columns; it runs when used in `select`, `with_columns`,
`filter` or `agg`. Functions that create expressions (`col`, `lit`, `when`, ...) are on the
[Functions](@ref) page.

```@setup expressions
using Polars, Dates
df = DataFrame((; x = [1, 2, 3, 4], y = [true, false, true, false]))
```

```@docs
Polars.Expr
```

## Aggregation

These return one value per group, or one value for the whole frame.

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
skew
Polars.kurtosis
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

`nan_min`/`nan_max` propagate `NaN`, where `min`/`max` ignore it:

```@example expressions
dfnan = DataFrame((; x = [1.0, NaN, 3.0]))
select(dfnan, min(col("x")) |> alias("min"), nan_min(col("x")) |> alias("nan_min"), max(col("x")) |> alias("max"), nan_max(col("x")) |> alias("nan_max"))
```

```@example expressions
df_corr = DataFrame((; x = [1.0, 2.0, 3.0, 4.0], y = [1.0, 8.0, 27.0, 64.0]))
select(
    df_corr,
    cov(col("x"), col("y")) |> alias("cov"),
    cor(col("x"), col("y")) |> alias("pearson"),
    spearman_rank_corr(col("x"), col("y")) |> alias("spearman"),
)
```

`value_counts` returns a Struct column (see [Struct](@ref expr-struct)):

```@example expressions
df5 = DataFrame((; g = ["a", "a", "b", "b", "b"]))
counts = select(df5, value_counts(col("g"); sort = true) |> alias("vc"))
select(counts, Structs.field_by_name(col("vc"), "g"), Structs.field_by_name(col("vc"), "count"))
```

```@example expressions
df_shape = DataFrame((; x = [1, 2, 3, 2, 2, 3, 0]))
select(
    df_shape,
    skew(col("x")) |> alias("skew"),
    Polars.kurtosis(col("x")) |> alias("kurtosis"),
)
```

`unique` is documented on the [DataFrame](@ref) page. In `agg`, it returns a List per group:

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
is_between
eq
Base.lt
gt
or
xor
and
```

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

```@example expressions
df7 = DataFrame((; x = [1, 1, 2, 3, 3, 3]))
select(df7, col("x"), is_duplicated(col("x")) |> alias("dup"), is_unique(col("x")) |> alias("uniq"))
```

```@example expressions
dfbetween = DataFrame((; x = [1, 2, 3, 4, 5]))
select(dfbetween, col("x"), is_between(col("x"), 2, 4) |> alias("between"))
```

See also [Named binary functions](@ref).

## Computation

```@docs
Base.abs
floor
ceil
sqrt
cbrt
exp
sign
cos
sin
tan
cot
cosh
sinh
tanh
arccos
arccosh
arcsinh
arctanh
degrees
radians
arctan2
dot
entropy
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
rolling_mean
rolling_sum
rolling_min
rolling_max
rolling_std
rolling_var
ewm_mean
ewm_std
ewm_var
rank
null_count
has_nulls
drop_nans
Base.replace
replace_strict
fill_null
forward_fill
backward_fill
fill_nan
Base.coalesce
```

```@example expressions
select(df, ((col("x") + 1) * 2) |> alias("plus_one_times_two"), (col("x") ^ 2) |> alias("squared"))
```

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

!!! note "`log` takes the base first"
    `log(base, x)` follows `Base.log`, unlike polars' `Expr.log(base)`: `log(lit(2), col("x"))` is
    the base-2 logarithm.

```@example expressions
dfmath2 = DataFrame((; x = [1.0, 100.0], theta = [1.0, 0.0]))
select(
    dfmath2,
    arccos(col("theta")) |> alias("arccos"), degrees(col("theta")) |> alias("degrees"), radians(col("theta")) |> alias("radians"),
    log10(col("x")) |> alias("log10"), log1p(col("x")) |> alias("log1p"),
)
```

```@example expressions
dfflags2 = DataFrame((; x = Union{Float64, Missing}[1.0, NaN, Inf, missing]))
select(dfflags2, null_count(col("x")) |> alias("nulls"), drop_nans(col("x")) |> alias("no_nans"))
```

```@example expressions
dfnan2 = DataFrame((; x = [1.0, NaN, 3.0]))
select(dfnan2, fill_nan(col("x"), lit(0.0)) |> alias("filled"))
```

```@example expressions
dfshift = DataFrame((; x = [10, 20, 30]))
select(dfshift, shift(col("x"), lit(1)) |> alias("shifted"), pct_change(col("x"), lit(1)) |> alias("pct_change"))
```

```@example expressions
df11 = DataFrame((; a = [missing, 2, missing], b = [1, missing, missing], c = [9, 9, 9]))
select(df11, coalesce(col("a"), col("b"), col("c")) |> alias("first_non_null"))
```

```@example expressions
df12 = DataFrame((; x = [missing, 1.0, missing, missing, 4.0, missing]))
select(df12, interpolate(col("x")) |> alias("linear"), interpolate(col("x"); method = :nearest) |> alias("nearest"))
```

```@example expressions
df6 = DataFrame((; x = ["a", "b", "c", "d"]))
select(df6, replace(col("x"), lit(["a", "c"]), lit(["A", "C"])) |> alias("r"))
```

```@example expressions
select(df6, replace_strict(col("x"), lit("a"), lit("A"); default = lit("?")) |> alias("r"))
```

`fill_null` also takes a fill `strategy`:

```@example expressions
dffs = DataFrame((; x = [1, missing, missing, 4]))
select(dffs, fill_null(col("x"); strategy = :forward) |> alias("ffill"))
```

[`forward_fill`](@ref)/[`backward_fill`](@ref) are shorthands for the `:forward`/`:backward`
strategies.

Rolling statistics use the `window_size` values ending at each row (or centered on it, with
`center = true`):

```@example expressions
dfroll = DataFrame((; x = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]))
select(
    dfroll,
    col("x"),
    rolling_mean(col("x"), 3) |> alias("rolling_mean"),
    rolling_mean(col("x"), 3; center = true) |> alias("centered"),
)
```

```@example expressions
select(dfroll, rolling_std(col("x"), 3) |> alias("std"), rolling_var(col("x"), 3; ddof = 0) |> alias("var_pop"))
```

Exponentially weighted statistics take exactly one of `com`, `span`, `half_life`, `alpha`:

```@example expressions
dfewm = DataFrame((; x = [2.0, 5.0, 3.0]))
select(
    dfewm,
    col("x"),
    ewm_mean(col("x"); alpha = 0.5) |> alias("ewm_mean"),
    ewm_std(col("x"); alpha = 0.5) |> alias("ewm_std"),
)
```

`ewm_mean_by` is not available.

## Manipulation/selection

```@docs
implode
flatten
reverse
is_in
top_k
top_k_by
bottom_k_by
arg_sort
gather
gather_every
Base.get(::Polars.Expr, ::Any)
limit
slice
sort_by
over
as_struct
sample_n
sample_frac
rle
rle_id
arg_unique
to_physical
lower_bound
upper_bound
extend_constant
shuffle
Base.reshape
```

The `Expr` methods of `filter`, `sort`, `head` and `tail` are documented with the frame methods
on the [DataFrame](@ref) page.

```@example expressions
df5 = DataFrame((; g = ["a", "a", "b", "b", "b"], x = [3, 1, 10, 20, 5]))
select(df5, top_k_by(col("x"), 2, col("x")) |> alias("top2"))
```

```@example expressions
dfshape = DataFrame((; x = [10, 20, 30]))
select(dfshape, reverse(col("x")) |> alias("reversed"))
```

```@example expressions
imploded = select(dfshape, implode(col("x")) |> alias("x"))
select(imploded, flatten(col("x")) |> alias("flattened"))
```

```@example expressions
df2 = DataFrame((; g = ["a", "a", "b", "b"], x = [1, 2, 3, 4]))
select(df2, col("x"), over(sum(col("x")), "g") |> alias("group_sum"))
```

```@example expressions
df3 = DataFrame((; g = ["a", "a", "b", "b", "b"], t = [2, 1, 3, 1, 2], x = [20, 10, 30, 5, 15]))
select(df3, col("x") |> sort_by("t"; rev = true))
```

```@example expressions
with_columns(df3, (sum(col("x")) |> over("g")) |> alias("group_total"))
```

```@example expressions
df4 = DataFrame((; x = collect(1:10)))
select(df4, sample_n(col("x"), 3; seed = 42))
```

Row indices in expressions (`gather`, `get`, `slice`, `arg_sort`, ...) are 0-based, so
`gather(x, arg_sort(y))` needs no offset. Column positions (`nth`, `Selectors.by_index`) are
1-based.

```@example expressions
df_gather = DataFrame((; x = [10, 20, 30, 40]))
select(df_gather, gather(col("x"), lit([0, -1])) |> alias("first_last"))
```

```@example expressions
select(df_gather, gather_every(col("x"), 2) |> alias("every_other"))
```

### Run-length encoding: `rle`/`rle_id`

```@example expressions
df5 = DataFrame((; x = [1, 1, 2, 2, 2, 3]))
select(df5, rle(col("x")))
```

```@example expressions
select(df5, col("x"), rle_id(col("x")) |> alias("run_id"))
```

## Binning

```@docs
Polars.cut
qcut
qcut_uniform
```

The result is a categorical column, read into Julia as `String`s:

```@example expressions
dfcut = DataFrame((; x = [-2, -1, 0, 1, 2]))
select(dfcut, col("x"), Polars.cut(col("x"), [-1.0, 1.0]) |> alias("cut"))
```

```@example expressions
select(dfcut, col("x"), qcut(col("x"), [0.25, 0.50]) |> alias("qcut"))
```

```@example expressions
select(dfcut, col("x"), qcut_uniform(col("x"), 2; labels = ["low", "high"]) |> alias("qcut_uniform"))
```

## Name

```@docs
alias
prefix
suffix
prefix_fields
suffix_fields
to_lowercase
to_uppercase
keep_name
```

```@example expressions
dfk = DataFrame((; x = [1, 2, 3]))
select(dfk, keep_name(alias(col("x"), "renamed")))
```

```@example expressions
dfs = DataFrame((; x = [(a = 1, b = 2)]))
select(dfs, prefix_fields(col("x"), "p_"))
```

## [Casting](@id casting)

```@docs
cast
cast_datetime
cast_duration
cast_decimal
cast_categorical
```

```@example expressions
dfc = DataFrame((; ns = Int64[0, 3_600_000_000_000]))
select(dfc, cast_duration(col("ns"); time_unit = :ns) |> alias("d"))
```

## Named binary functions

Operators have named-function equivalents, useful when the operation is chosen at runtime.

| Function | Operator equivalent |
|---|---|
| `eq(a, b)` | `a .== b` |
| `gt(a, b)` | `a .> b` |
| `and(a, b)` | `a .& b` |
| `or(a, b)` | `a .\| b` |
| `add(a, b)`, `sub(a, b)`, `mul(a, b)`, `div(a, b)`, `pow(a, b)` | `+`, `-`, `*`, `/`, `^` |
| `xor(a, b)` | *(no operator equivalent)* |
| `Base.lt(a, b)` | *(no infix operator; use `.>` and flip arguments)* |

```@example expressions
comparisons = Dict("gt" => gt, "eq" => eq)
op = comparisons["gt"] # picked at runtime, e.g. from user input
select(df, op(col("x"), lit(2)) |> alias("cmp"))
```

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

`lt` must be called as `Base.lt`:

```@example expressions
select(df, Base.lt(col("x"), lit(3)))
```

## Curried forms for pipe-based composition

Functions taking an expression and further arguments have a curried form: `f(args...)` returns a
function of the expression, for `expr |> f(args...)`.

| Function | Curried form |
|---|---|
| `is_in(expr, values)` | `is_in(values)` (a `Vector` is imploded, see below) |
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
| `rolling_mean(expr, window_size; ...)` | `rolling_mean(window_size; ...)`, and the other `rolling_*` |
| `ewm_mean(expr; ...)` | `ewm_mean(; ...)`, and `ewm_std`/`ewm_var` |
| `Polars.cut(expr, breaks; labels, left_closed)` | `Polars.cut(breaks; labels, left_closed)` |
| `qcut(expr, probs; labels, left_closed, allow_duplicates)` | `qcut(probs; labels, left_closed, allow_duplicates)` |
| `qcut_uniform(expr, n_bins; labels, left_closed, allow_duplicates)` | `qcut_uniform(n_bins; labels, left_closed, allow_duplicates)` |
| `is_between(expr, lower, upper; closed)` | `is_between(lower, upper; closed)` |
| `skew(expr; bias)` | `skew(; bias)` |
| `Polars.kurtosis(expr; fisher, bias)` | `Polars.kurtosis(; fisher, bias)` |
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

The curried `over` and `sort_by` take column names only. `log`, `rem`, `replace`, `diff` and
`round` have no curried form.

```@example expressions
df13 = DataFrame((; g = ["a", "a", "b"], x = [3, 1, 2]))
select(df13, col("x") |> arg_sort(descending = true) |> alias("order"), col("x") |> cum_max() |> alias("running_max"))
```

## `lit(::Vector)` for multi-value membership and replacement

`lit` of a `Vector` is a column literal. For `is_in`, wrap it in `implode` (polars deprecates the
bare form); `replace` takes it directly.

```@example expressions
df8 = DataFrame((; x = [1, 2, 3, 4]))
filter(df8, is_in(col("x"), implode(lit([2, 4]))))
```
