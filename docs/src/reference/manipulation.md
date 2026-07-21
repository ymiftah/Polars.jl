# Manipulation

Every function below has both a `DataFrame` method (eager) and a `LazyFrame` method (lazy,
returning another `LazyFrame` so calls chain) — see [Laziness](@ref). All of them accept either
`Expr`s or plain column-name `String`s wherever an expression is expected.

```@setup manipulation
using Polars, Chain, Dates
orders = DataFrame((;
    store = ["a", "a", "b"], product = ["x", "y", "x"],
    qty = [2, 1, 3], price = [10.0, 5.0, 10.0],
))
stores = DataFrame((; store = ["a", "b"], city = ["Springfield", "Shelbyville"]))
```

## Selecting and adding columns

`select` keeps only the given expressions; `with_columns` keeps the existing columns and adds the
given expressions alongside them.

```@example manipulation
select(orders, col("store"), col("product"))
```

```@example manipulation
with_columns(orders, (col("qty") * col("price")) |> alias("revenue"))
```

## Filtering: `filter`

Keeps rows where the given boolean expression is `true`:

```@example manipulation
filter(orders, col("qty") .> 1)
```

## Sorting: `sort`

```@example manipulation
sort(orders, col("qty"); rev = true)
```

`rev` also accepts a `Bool` vector (one entry per sort expression) for mixed ascending/descending
multi-column sorts. `stable` (default `true`) preserves the relative order of ties; `nulls_last`
(default `true`) controls where `missing` values land.

## `head` and `tail`

```@example manipulation
head(orders, 2)
```

`tail(df, n=5)` returns the last `n` rows, same default as `head`. It extends `Base.tail`, which
Julia doesn't bring into unqualified scope by default — call it as `Base.tail(orders, 2)`, not bare
`tail(orders, 2)`.

```@example manipulation
Base.tail(orders, 2)
```

## Grouping and aggregating: `group_by` + `agg`

`group_by` alone returns a `LazyGroupBy` (see [Structures](@ref)) — not useful until passed to
`agg`, which evaluates the aggregation expressions per group and returns a `LazyFrame`:

```@example manipulation
@chain orders begin
    lazy
    group_by("store")
    agg(sum(col("qty") * col("price")) |> alias("revenue"))
    collect
end
```

### Time-window variants: `group_by_dynamic` and `rolling`

Both return a `LazyGroupBy` for `agg`, just like `group_by`, but bucket rows by a time-indexed
column instead of by equality:

- `group_by_dynamic(lf, index_column; every, period=every, offset="0ns", closed=:left, label=:left, include_boundaries=false, start_by=:window_bound)`
  buckets rows into fixed, non-overlapping (by default) windows — e.g. "daily total per store".
  Takes an optional extra `group_by` vector of keys for multi-key windows (e.g. per store *and*
  per day).
- `rolling(lf, index_column; period, offset="0ns", closed=:right)` computes a sliding window
  *per row* instead of fixed buckets — e.g. "trailing 7-day total as of each row's own timestamp".

Both window sizes are duration strings (`"1d"`, `"4h"`, `"30m"`, ...). The
[Time-Series Analytics](@ref) tutorial covers this pair in depth with a larger worked example.

### Gap-filling to a regular grid: `upsample`

`upsample(df, time_column; by=String[], every, stable=true)` inserts rows so `time_column` becomes
an evenly `every`-spaced grid (a duration string) — the opposite problem from
`group_by_dynamic`/`rolling`: instead of bucketing existing rows, it fills in the gaps between
them. `time_column` must already be sorted (within each `by` group, if given); every column except
`time_column`/`by` is `missing` on the newly-inserted rows. `by` upsamples independently per group;
`stable` (default `true`) preserves original row order at some extra cost.

```@example manipulation
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

All but `crossjoin` take a key expression (or one `String` column name) shared by both sides, or a
separate expression per side when the join columns are named differently:
`innerjoin(a, b, col("id_a"), col("id_b"))`.

```@example manipulation
innerjoin(orders, stores, col("store"))
```

### `join_asof`

`join_asof(a, b, on; by_left=String[], by_right=String[], strategy=:backward)` matches each row of
`a` to the *nearest* row of `b` by a sorted key (typically a timestamp), rather than an exact
match — the workhorse for aligning time series that don't share tick timestamps. `strategy` is one
of `:backward` (default: latest `b` row `<=` the `a` key), `:forward` (earliest `b` row `>=` the
key), or `:nearest`. Both frames must already be sorted on `on`. `by_left`/`by_right` add an
equality group-by (e.g. match within the same `store`) applied before the asof match. See the
[Time-Series Analytics](@ref) tutorial for a full example.

## Concatenating: `concat`

Stacks frames vertically (rows), matching columns by position — all frames need the same number of
columns with compatible types:

```@example manipulation
concat([orders, orders])
```

## Removing duplicates: `unique`

`unique(df, subset=String[]; keep=:any)` removes duplicate rows, considering only `subset` columns
if given (all columns otherwise). `keep` picks which duplicate survives: `:first`, `:last`, `:none`
(drop every duplicate, keeping only rows that were already unique), or `:any` (default — no order
guarantee, allows more optimization). Unlike `tail`/`rename` below, `unique` is called bare — Base
brings it into scope without qualification.

```@example manipulation
dup = DataFrame((; store = ["a", "a", "b"], product = ["x", "x", "x"]))
unique(dup; keep = :first)
```

## Columns and rows: `drop`, `rename`, `drop_nulls`, `with_row_index`

- `drop(df, columns::Vector{String})` removes the given columns.
- `rename(df, existing::Vector{String}, new::Vector{String}; strict=true)` renames columns,
  pairing `existing[i]` to `new[i]` by **position**, not by a `Dict`. `strict=false` silently
  ignores any `existing` name not present in the frame instead of erroring. Like `tail`, this
  extends `Base.rename`, which needs explicit qualification — call it as `Base.rename(...)`, not
  bare `rename(...)`.
- `drop_nulls(df, subset=String[])` drops whole **rows** containing a `null` in any of the
  `subset` columns (all columns if not given) — don't confuse this frame-level verb with the
  expression-level `drop_nulls`/`drop_nans` in [Expressions](@ref), which operate within a single
  column's values, not across rows.
- `with_row_index(df, name="index"; offset=0)` adds a row-index column.

```@example manipulation
Base.rename(drop(orders, ["price"]), ["qty"], ["quantity"])
```

```@example manipulation
with_columns(orders, (col("qty") * col("price")) |> alias("revenue")) |> x -> drop_nulls(x, ["revenue"])
```

## Reshaping: `explode`, `unpivot`, and `pivot`

`explode(df, columns::Vector{String})` turns each element of a list-typed column into its own row
(other columns are repeated to match) — the natural inverse of `implode` inside a `group_by` +
`agg`:

```@example manipulation
per_store = @chain orders begin
    lazy
    group_by("store")
    agg(implode(col("product")) |> alias("products"))
    collect
end
explode(per_store, ["products"])
```

`unpivot(df, index::Vector{String}; on=String[], variable_name=nothing, value_name=nothing)`
melts wide columns into long format: `index` columns are repeated, and the melted (`on`) columns
— all non-`index` columns by default — become two new columns holding the original column name
(`variable_name`, default `"variable"`) and its value (`value_name`, default `"value"`).

```@example manipulation
wide = DataFrame((; id = [1, 2], a = [10, 20], b = [100, 200]))
unpivot(wide, ["id"])
```

`pivot(df, on, index, values; agg=Base.first(element()), maintain_order=true, separator="_", column_naming=:auto)`
is `unpivot`'s inverse: long to wide. It creates one new column per distinct value of `on`, groups
the remaining rows by `index`, and aggregates each group's `values` column with `agg` — an
expression built from `element()`, a placeholder for "the values in this group" (see
[Expressions](@ref)). `on`/`index`/`values` each accept a single column name or a `Vector` of
names. When there's more than one `values` column (or `column_naming=:combine`), output column
names combine the value column and the `on` value, joined by `separator` (default `"_"`).
**Eager-only** (no `LazyFrame` method) — the distinct `on` values must be computed upfront before
the plan can be built.

```@example manipulation
pivot(orders, "product", "store", "qty"; agg = Base.sum(element()))
```

Without an explicit `agg`, duplicate `(on, index)` pairs collapse to the *first* matching value
rather than erroring — pass `agg` explicitly (e.g. `Base.sum(element())`) whenever more than one
row can share the same `on`/`index` combination.

## Unnest: `unnest`

`unnest(df, columns::Vector{String}; separator=nothing)` is the row-preserving counterpart to
`explode`: it replaces each struct-typed column in `columns` with one new column per struct field
(in field order), in place of the original column. It's the read-side inverse of `as_struct` (see
[Structs](@ref)), which builds a struct column out of expressions.

```@example manipulation
people = DataFrame((; id = [1, 2], info = [(name = "Alice", age = 30), (name = "Bob", age = 25)]))
unnest(people, ["info"])
```

Without `separator`, the new columns are named after the bare struct fields, as above. With
`separator`, each is named `"<column><separator><field>"` instead — useful for unnesting multiple
struct columns whose field names would otherwise collide:

```@example manipulation
unnest(people, ["info"]; separator = "_")
```

Unnesting a column name absent from the frame, or one that isn't struct-typed, errors rather than
silently doing nothing; likewise, two unnested fields ending up with the same name (or colliding
with an existing column) errors instead of silently overwriting. `unnest` also has a `LazyFrame`
method (`unnest(lf, columns; separator=nothing)`), unlike `pivot` above.
