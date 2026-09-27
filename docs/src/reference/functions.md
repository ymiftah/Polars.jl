# Functions

Functions that create an [`Expr`](@ref Expressions).

```@setup functions
using Polars
```

## Column references

```@docs
col
nth
element
```

To select columns by dtype, position or name pattern, see [Selectors](@ref).

## Literals & casting

```@docs
lit
when
```

`lit` also accepts `Date`, `Time` and `DateTime` values:

```@example functions
using Dates
dfdate = DataFrame((; d = [Date(2024, 3, 15), Date(2024, 3, 16), Date(2024, 3, 17)]))
filter(dfdate, col("d") == lit(Date(2024, 3, 15)))
```

A `DateTime` literal is limited to the years 1678–2262; see [Limitations](@ref).

```@example functions
df = DataFrame((; x = [1, 2, 3, 4], y = [true, false, true, false]))
select(df, when(col("y"), lit("yes"), lit("no")))
```

For casting, see [Casting](@ref casting).

## Horizontal (row-wise) reductions

```@docs
all_horizontal
any_horizontal
min_horizontal
max_horizontal
sum_horizontal
mean_horizontal
```

These reduce across expressions within each row.

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
concat_str
concat_list
```

```@example functions
df11 = DataFrame((; name = ["a", "b"], age = [1, 2]))
select(df11, format("{} is {}", col("name"), col("age")) |> alias("greeting"))
```

## Temporal constructors

```@docs
datetime
duration
date
Base.time(::Union{Real, Polars.Expr}, ::Union{Real, Polars.Expr}, ::Union{Real, Polars.Expr}, ::Union{Real, Polars.Expr})
from_epoch
```

```@example functions
dft = DataFrame((; y = [2024, 2025], m = [1, 6], d = [15, 30]))
select(dft, datetime(col("y"), col("m"), col("d"); hour = 12) |> alias("dt"))
```

## Range functions

```@docs
int_range
date_range
datetime_range
time_range
```

The per-row variants (`int_ranges`, `date_ranges`, ...) and `linear_space` are not available.

```@example functions
select(DataFrame((; x = [1])), int_range(0, len() * 5) |> alias("idx"))
```
