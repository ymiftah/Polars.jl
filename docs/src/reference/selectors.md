# Selectors

The `Selectors` namespace (py-polars' `polars.selectors`) selects columns by dtype, name, position
or name pattern. A `Selector` can be used wherever an `Expr` is accepted.

```@setup selectors
using Polars
```

```@docs
Polars.Selector
Selectors
```

## Basic usage

```@example selectors
df = DataFrame((; a = [1, 2, 3], b = [1.0, 2.0, 3.0], s = ["x", "y", "z"], flag = [true, false, true]))
select(df, Selectors.numeric())
```

## Dtype-family selectors

```@docs
Selectors.all
Selectors.numeric
Selectors.integer
Selectors.unsigned_integer
Selectors.signed_integer
Selectors.float
Selectors.string
Selectors.boolean
Selectors.binary
Selectors.date
Selectors.time
Selectors.datetime
Selectors.duration
Selectors.temporal
Selectors.categorical
Selectors.decimal
Selectors.struct_
Selectors.list
Selectors.array
Selectors.nested
Selectors.by_dtype
```

```@example selectors
select(df, Selectors.string())
```

```@example selectors
select(df, Selectors.by_dtype(Int64, Float64))
```

## Name/position selectors

```@docs
Selectors.by_name
Selectors.by_index
Selectors.matches
Selectors.starts_with
Selectors.ends_with
Selectors.contains
exclude
```

```@example selectors
select(df, Selectors.starts_with("f"))
```

`exclude` takes either names or types; to exclude both, combine two calls with `&`:
`exclude("a") & exclude(Int64)`.

## Combining selectors

Selectors combine with `|`, `&`, `-` and `xor`:

```@docs
Base.:|(::Polars.Selector, ::Polars.Selector)
Base.:&(::Polars.Selector, ::Polars.Selector)
Base.:-(::Polars.Selector, ::Polars.Selector)
```

```@example selectors
select(df, Selectors.numeric() | Selectors.boolean())
```

```@example selectors
select(df, Selectors.all() - Selectors.numeric())
```

Python's `cs.numeric() ^ cs.string()` is `xor(a, b)` (or `a ⊻ b`) in Julia, since `^` is
exponentiation.

Note: `datetime()` and `duration()` match any time unit and time zone, and `list()` and `array()`
any inner type; there are no parameterized forms.
