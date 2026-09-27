# [Struct](@id expr-struct)

The `Structs` namespace operates on Struct columns.

```@setup structs
using Polars
```

## Constructing a Struct column

A column of `NamedTuple`s becomes a Struct column:

```@example structs
df = DataFrame((; s = [(a = 1, b = "x"), (a = 2, b = "y"), (a = 3, b = "z")]))
```

`as_struct` (see [Expressions](@ref)) builds one from expressions:

```@example structs
df2 = DataFrame((; x = [1, 2, 3], y = ["p", "q", "r"]))
combined = select(df2, as_struct(col("x"), col("y")) |> alias("s"))
select(combined, Structs.field_by_name(col("s"), "x"), Structs.field_by_name(col("s"), "y"))
```

## Field access

```@docs
Polars.Structs.field_by_name
Polars.Structs.field_by_index
Polars.Structs.rename_fields
```

```@example structs
select(df, Structs.field_by_name(col("s"), "a"), Structs.field_by_name(col("s"), "b"))
```

`prefix_fields` and `suffix_fields` are under [Name](@ref).

## Unpacking a whole Struct column

`unnest` (see [DataFrame](@ref)) replaces a Struct column with one column per field.
