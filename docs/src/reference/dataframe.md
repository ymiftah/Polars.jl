# DataFrame

Operations on a `DataFrame` run immediately. Most verbs below also have a `LazyFrame` method (see
[LazyFrame](@ref)) with the same behavior, documented here once for both.

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

A `DataFrame` can be built from any [Tables.jl](https://github.com/JuliaData/Tables.jl) table, such
as a `NamedTuple` of vectors:

```@example dataframe
df = DataFrame((; x = [1, 2, missing, 4], y = ["a", "b", "c", "d"]))
```

or a `Vector` of `NamedTuple`s:

```@example dataframe
DataFrame([(; x = 1, y = "a"), (; x = 2, y = "b")])
```

A column of vectors becomes a List column, and a column of `NamedTuple`s a Struct column. See
[Data types](@ref) for the full mapping.

## Attributes

`size(df)` is `(nrows, ncols)`. Indexing by name returns a [`Series`](@ref):

```@example dataframe
df[:x], size(df)
```

and `df[row, col]` a single value:

```@example dataframe
df[2, :x]
```

```@docs
Base.names
get_column
Polars.item
```

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

`a == b` compares column names and data, treating missing values as equal. `summary(df)` returns
e.g. `"3×2 DataFrame"`.

```@docs
Polars.native_repr
```

```@example dataframe
print(Polars.native_repr(orders))
```

## Manipulation/selection

Wherever an expression is expected, a column name (`String` or `Symbol`) also works.

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

`limit` is an alias for `head`. `reverse` reverses the row order (see [Expressions](@ref) for both
docstrings):

```@example dataframe
reverse(orders)
```

```@docs
Base.unique
```

```@example dataframe
dup = DataFrame((; store = ["a", "a", "b"], product = ["x", "x", "x"]))
unique(dup; keep = :first)
```

```@docs
drop
Base.rename
drop_nulls
with_row_index
```

```@example dataframe
rename(drop(orders, ["price"]), ["qty"], ["quantity"])
```

`drop_nulls` on a frame drops rows; the `Expr` method (see [Expressions](@ref)) drops values
within one column.

```@example dataframe
with_columns(orders, (col("qty") * col("price")) |> alias("revenue")) |> x -> drop_nulls(x, ["revenue"])
```

## Whole-frame computation

`null_count`, `count`, `fill_null` and `fill_nan` also apply to a whole frame (docstrings in
[Expressions](@ref)):

```@example dataframe
null_count(orders)
```

## Aggregation & group-by

`group_by` returns a `LazyGroupBy` (see [LazyFrame](@ref)), aggregated with `agg`:

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

### Time-window variants

Both group rows by windows over a time column and return a `LazyGroupBy`:

```@docs
group_by_dynamic
rolling
```

`group_by_dynamic` uses regular windows (e.g. daily); `rolling` uses one window ending at each row
(e.g. the trailing 7 days). See the [Time-Series Analytics](@ref) tutorial.

### Gap-filling to a regular grid

```@docs
upsample
```

```@example dataframe
gaps = DataFrame((; time = DateTime(2024, 1, 1, 0) .+ Hour.([0, 2, 3]), v = [1, 2, 3]))
upsample(gaps, "time"; every = "1h")
```

`interpolate` (see [Expressions](@ref)) can fill the new missing values.

## Joins

| Function | Kept rows |
|---|---|
| `innerjoin` | rows with a match on both sides |
| `leftjoin` | all left rows, `missing` on the right where unmatched |
| `rightjoin` | all right rows, `missing` on the left where unmatched |
| `outerjoin` | all rows from both sides |
| `semijoin` | left rows *that have* a match (right columns dropped) |
| `antijoin` | left rows *without* a match (right columns dropped) |
| `crossjoin` | every left row with every right row |

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

The join key is one expression (or column name) for both sides, or one per side:

```@example dataframe
innerjoin(orders, stores, col("store"))
```

See the [Time-Series Analytics](@ref) tutorial for `join_asof`.

## Combining frames

```@docs
concat
```

```@example dataframe
concat([orders, orders])
```

```@docs
hstack
vstack
```

`hstack` and `vstack` take a `DataFrame` only:

```@example dataframe
hstack(orders, [Series("note", ["rush", "-", "-"])])
```

```@example dataframe
vstack(orders, orders)
```

## Reshaping

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

```@example dataframe
wide = DataFrame((; id = [1, 2], a = [10, 20], b = [100, 200]))
unpivot(wide, ["id"])
```

```@example dataframe
pivot(orders, "product", "store", "qty"; agg = Base.sum(element()))
```

The default `agg` takes the first value of each group.

```@docs
unnest
```

```@example dataframe
people = DataFrame((; id = [1, 2], info = [(name = "Alice", age = 30), (name = "Bob", age = 25)]))
unnest(people, ["info"])
```

```@docs
Base.transpose
```

```@example dataframe
numbers = DataFrame((; a = [1, 2, 3], b = [10, 20, 30]))
transpose(numbers)
```

## Tables.jl integration

`DataFrame` implements the [Tables.jl](https://github.com/JuliaData/Tables.jl) interface, so it
works with packages that consume tables (DataFrames.jl, CSV.jl, ...).

```@docs
Polars.schema
```

```@example dataframe
import Tables
Tables.schema(df)
```
