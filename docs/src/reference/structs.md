# Structs

The `Structs` namespace provides operations on struct-typed columns (records / named tuples). Struct columns arise from certain polars operations (e.g. `value_counts` — see [Expressions](@ref) — or joins that bring together multiple column sources), from external data, or can be constructed directly from a `Vector{<:NamedTuple}` column, as shown below.

```@setup structs
using Polars
```

## Constructing a Struct column

`DataFrame(table)` accepts a `Vector{<:NamedTuple}` column directly — each `NamedTuple`'s fields become the struct's fields:

```@example structs
df = DataFrame((; s = [(a = 1, b = "x"), (a = 2, b = "y"), (a = 3, b = "z")]))
```

Building a struct column from existing expressions works the same way via `as_struct(exprs...)`
(see [Expressions](@ref)) — one field per input, named after each input's own output name. Its
`@example` output below is truncated (the raw `NamedTuple` type doesn't print field values), so
it's shown unpacked via `Structs.field_by_name` right after construction:

```@example structs
df2 = DataFrame((; x = [1, 2, 3], y = ["p", "q", "r"]))
combined = select(df2, as_struct(col("x"), col("y")) |> alias("s"))
select(combined, Structs.field_by_name(col("s"), "x"), Structs.field_by_name(col("s"), "y"))
```

## Field access

| Function | Purpose |
|---|---|
| `Structs.field_by_name(expr, name)` | extract a named field |
| `Structs.field_by_index(expr, index)` | extract by position (0-indexed) |
| `Structs.rename_fields(expr, new_names)` | rename fields (provide `Vector{String}` of new names in order) |

```@example structs
select(df, Structs.field_by_name(col("s"), "a"), Structs.field_by_name(col("s"), "b"))
```

Notes:

- Struct extraction returns a `Series` of the field type.
- `Structs.rename_fields` reorders fields in the new order given.

## Unpacking a whole Struct column: `unnest`

`as_struct` (above) is the write-side operation: expressions in, one Struct column out. The
read-side counterpart is `unnest` (see [Manipulation](@ref)), which goes the other way — a
Struct column in, one plain column per field out.
