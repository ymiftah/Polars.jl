# DataFrame

An eager, columnar table: every operation on a `DataFrame` runs immediately. Every verb below also
has a `LazyFrame` method (see [LazyFrame](@ref)) that always gives identical results, so each verb
is documented here exactly once for both.

```@setup dataframe
using Polars, Chain, Dates
orders = DataFrame((;
    store = ["a", "a", "b"], product = ["x", "y", "x"],
    qty = [2, 1, 3], price = [10.0, 5.0, 10.0],
))
stores = DataFrame((; store = ["a", "b"], city = ["Springfield", "Shelbyville"]))
```

```@docs
DataFrame
```

Construct a `DataFrame` from anything implementing the [Tables.jl](https://github.com/JuliaData/Tables.jl)
interface — most commonly a `NamedTuple` of vectors (column-oriented):

```@example dataframe
df = DataFrame((; x = [1, 2, missing, 4], y = ["a", "b", "c", "d"]))
```

A `Vector` of `NamedTuple`s (row-oriented) works too, via Tables.jl's own row-to-column conversion:

```@example dataframe
DataFrame([(; x = 1, y = "a"), (; x = 2, y = "b")])
```

Columns can hold scalar/fixed-width types (`Int`, `String`, `Date`, `DateTime`, ...), `List`s
(`Vector{<:Vector{T}}`) and `Struct`s (`Vector{<:NamedTuple}` as a *column*, not the whole table —
see [Struct](@ref expr-struct)), and raw bytes as a `Binary` column via `Vector{UInt8}`. See
[Data types](@ref) for the full Julia↔polars dtype mapping.

## Attributes

`size(df)` returns `(nrows, ncols)`; columns are retrieved with `getindex`, by `Symbol` or `String`
name, returning a [`Series`](@ref):

```@example dataframe
df[:x], size(df)
```

A single cell is `df[row, col]`:

```@example dataframe
df[2, :x]
```

```@docs
Base.names
get_column
Polars.item
```

`get_column(df, name)` is a named alias for `df[name]`, for callers who prefer the py-polars-shaped
method name over indexing syntax. `Polars.item` extracts the sole value of a 1×1 frame (or, with a
`row`/`col` pair, is a thin renamed wrapper around `df[row, col]`)

```@example dataframe
Polars.item(DataFrame((; x = [42])))
```

## Descriptive

```@docs
describe
```

```@example dataframe
describe(orders)
```

`Base.:(==)(a::DataFrame, b::DataFrame)` is structural equality: same column names in the same
order, with pairwise-equal column data (`missing == missing` is treated as `true`, so the result
is always a concrete `Bool`). `Base.summary(df::DataFrame)` returns a one-line summary (e.g.
`"3×2 DataFrame"`); `Base.show` renders the full table with PrettyTables formatting. Both are
automatic in the REPL/Pluto.jl.

```@docs
Polars.native_repr
```

```@example dataframe
print(Polars.native_repr(orders))
```

`Polars.native_repr` renders `df` using polars' own Rust `Display` formatting -- the same text
`print(df)` produces in py-polars -- as an alternative to the `PrettyTables.jl`-based default
render above.

## Manipulation/selection

`select` keeps only the given expressions; `with_columns` keeps the existing columns and adds the
given expressions alongside them. Every function below accepts either `Expr`s or plain column-name
`String`s wherever an expression is expected.

```@docs
select
with_columns
```

```@example dataframe
select(orders, col("store"), col("product"))
```

```@example dataframe
with_columns(orders, (col("qty") * col("price")) |> alias("revenue"))
```

```@docs
Base.filter
```

```@example dataframe
filter(orders, col("qty") .> 1)
```

```@docs
Base.sort
```

```@example dataframe
sort(orders, col("qty"); rev = true)
```

`rev` also accepts a `Bool` vector (one entry per sort expression) for mixed ascending/descending
multi-column sorts. `stable` (default `true`) preserves the relative order of ties; `nulls_last`
(default `true`) controls where `missing` values land.

```@docs
head
tail
```

```@example dataframe
head(orders, 2)
```

```@example dataframe
tail(orders, 2)
```

```@docs
Base.unique
```

```@example dataframe
dup = DataFrame((; store = ["a", "a", "b"], product = ["x", "x", "x"]))
unique(dup; keep = :first)
```

`maintain_order = true` preserves the original row order among the kept rows (the default,
`false`, allows more optimization but gives no order guarantee).

```@docs
drop
Base.rename
drop_nulls
with_row_index
```

```@example dataframe
rename(drop(orders, ["price"]), ["qty"], ["quantity"])
```

`drop_nulls(df, subset=String[])` drops whole **rows** containing a `null` in any of the `subset`
columns — don't confuse this frame-level verb with the expression-level `drop_nulls`/`drop_nans`
(see [Expressions](@ref)), which operate within a single column's values, not across rows.

```@example dataframe
with_columns(orders, (col("qty") * col("price")) |> alias("revenue")) |> x -> drop_nulls(x, ["revenue"])
```

## Aggregation & group-by

`group_by` alone returns a `LazyGroupBy` (see [LazyFrame](@ref)) — not useful until passed to
`agg`, which evaluates the aggregation expressions per group:

```@docs
group_by
agg
```

```@example dataframe
@chain orders begin
    lazy
    group_by("store")
    agg(sum(col("qty") * col("price")) |> alias("revenue"))
    collect
end
```

`group_by(...; maintain_order = true)` preserves each group's row order, and the order groups
first appear in, through `agg`'s output (the default, `false`, allows more optimization but gives
no order guarantee).

### Time-window variants

Both bucket rows by a time-indexed column instead of by equality, and both return a `LazyGroupBy`
for `agg` just like `group_by`:

```@docs
group_by_dynamic
rolling
```

`group_by_dynamic` buckets rows into fixed, non-overlapping (by default) windows — e.g. "daily
total per store". `rolling` computes a sliding window *per row* instead — e.g. "trailing 7-day
total as of each row's own timestamp". Both window sizes are duration strings (`"1d"`, `"4h"`,
`"30m"`, ...). The [Time-Series Analytics](@ref) tutorial covers this pair in depth.

### Gap-filling to a regular grid

```@docs
upsample
```

The opposite problem from `group_by_dynamic`/`rolling`: instead of bucketing existing rows, it
fills in the gaps between them.

```@example dataframe
gaps = DataFrame((; time = DateTime(2024, 1, 1, 0) .+ Hour.([0, 2, 3]), v = [1, 2, 3]))
upsample(gaps, "time"; every = "1h")
```

Pair with `interpolate` (see [Expressions](@ref)) to fill the resulting `missing` values.

## Joins

| Function | Kept rows |
|---|---|
| `innerjoin` | rows with a match on both sides |
| `leftjoin` | all left rows, `missing` on the right where unmatched |
| `rightjoin` | all right rows, `missing` on the left where unmatched |
| `outerjoin` | all rows from both sides |
| `semijoin` | left rows *that have* a match (right columns dropped) |
| `antijoin` | left rows *without* a match (right columns dropped) |
| `crossjoin` | Cartesian product — every left row × every right row |

```@docs
innerjoin
leftjoin
rightjoin
outerjoin
semijoin
antijoin
crossjoin
join_asof
```

All but `crossjoin` take a key expression (or one `String` column name) shared by both sides, or a
separate expression per side when the join columns are named differently:

```@example dataframe
innerjoin(orders, stores, col("store"))
```

`join_asof` is the workhorse for aligning time series that don't share tick timestamps — see the
[Time-Series Analytics](@ref) tutorial for a full example.

Every join verb accepts `suffix`, `coalesce`, `validate`, and `nulls_equal` (see each function's
own docstring above for the exact semantics); `join_asof` additionally accepts `tolerance`,
`allow_eq`, and `check_sortedness`. None currently accepts `slice` -- see
[Limitations](@ref) for why.

## Combining frames

```@docs
concat
```

Stacks frames vertically (rows), matching columns by position — all frames need the same number of
columns with compatible types:

```@example dataframe
concat([orders, orders])
```

```@docs
hstack
vstack
```

Unlike `concat`, `hstack`/`vstack` are **eager-only** (no `LazyFrame` method) and take their second
argument in a different shape:

```@example dataframe
hstack(orders, [Series("note", ["rush", "-", "-"])])
```

```@example dataframe
vstack(orders, orders)
```

## Reshaping

`explode(df, columns::Vector{String})` turns each element of a list-typed column into its own row
(other columns are repeated to match) — the natural inverse of `implode` inside a `group_by` +
`agg`:

```@docs
explode
```

```@example dataframe
per_store = @chain orders begin
    lazy
    group_by("store")
    agg(implode(col("product")) |> alias("products"))
    collect
end
explode(per_store, ["products"])
```

```@docs
unpivot
pivot
```

`unpivot` melts wide columns into long format; `pivot` is its inverse (long to wide). `pivot` is
**eager-only** (no `LazyFrame` method) — the distinct `on` values must be computed upfront before
the plan can be built.

```@example dataframe
wide = DataFrame((; id = [1, 2], a = [10, 20], b = [100, 200]))
unpivot(wide, ["id"])
```

```@example dataframe
pivot(orders, "product", "store", "qty"; agg = Base.sum(element()))
```

Without an explicit `agg`, duplicate `(on, index)` pairs collapse to the *first* matching value
rather than erroring — pass `agg` explicitly whenever more than one row can share the same
`on`/`index` combination.

```@docs
unnest
```

The row-preserving counterpart to `explode`: it replaces each struct-typed column with one new
column per struct field, in place of the original column — the read-side inverse of `as_struct`
(see [Struct](@ref expr-struct)).

```@example dataframe
people = DataFrame((; id = [1, 2], info = [(name = "Alice", age = 30), (name = "Bob", age = 25)]))
unnest(people, ["info"])
```

```@docs
Base.transpose
```

Turns each row into a new column (casting across the original column dtypes to a common supertype
first) — same idea as a matrix transpose. **Eager-only**, like `pivot`.

```@example dataframe
numbers = DataFrame((; a = [1, 2, 3], b = [10, 20, 30]))
transpose(numbers)
```

## Tables.jl integration

`DataFrame` implements the [Tables.jl](https://github.com/JuliaData/Tables.jl) column-access
interface (`Tables.istable`, `Tables.columns`, `Tables.schema`, ...), so it interoperates with any
package that consumes Tables.jl sources (CSV.jl writers, DataFrames.jl's `DataFrame(polars_df)`,
Pluto.jl's table viewer, etc.).

```@docs
Polars.schema
```

`Tables.schema(df)` refines each column's `eltype` using its actual null count — unlike
`collect_schema` on a `LazyFrame` (see [LazyFrame](@ref)), which hasn't executed the query yet and
so must conservatively report every column as nullable.

```@example dataframe
import Tables
Tables.schema(df)
```
