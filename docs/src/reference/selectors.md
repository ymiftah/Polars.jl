# Selectors

The `Selectors` namespace (py-polars' `polars.selectors`, conventionally imported there as `cs`) selects columns by dtype, name, position, or name pattern, instead of writing out `col(...)` calls by hand. Every function returns a `Selector`, which can be passed anywhere an `Expr` is accepted (`select`, `with_columns`, `filter`, `sort`, ...) and combined with set algebra (`|`, `&`, `-`, `xor`).

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

!!! warning "`array()` currently matches zero columns in this build"
    `dtype-array` is not enabled in `c-polars/Cargo.toml`'s feature list, so upstream's own
    `Array`-dtype matcher compiles to a safe always-`false` fallback instead of a real check — it
    never crashes, it just never selects anything. See [Limitations](@ref).

`all`/`float`/`string`/`time`/`contains` are deliberately not exported from `Selectors` itself (they'd clobber `Base.all`/`Base.float`/`Base.string`/`Base.time`/`Base.contains`) — always call them qualified, e.g. `Selectors.string()`. Everything else *is* exported from `Selectors`, so `using Polars.Selectors` also brings those in unqualified if you prefer that style; this page always uses the qualified form, which works either way.

```@example selectors
select(df, Selectors.string())
```

```@example selectors
select(df, Selectors.by_dtype(Int64, Float64))
```

`Datetime`/duration `Period` subtypes/`Decimal`/`List`/`Struct` need parameters a plain dtype code can't carry, so passing one of those to `by_dtype` (e.g. `by_dtype(DateTime)`) raises a `PolarsError` — use `datetime()`/`duration()`/`decimal()`/`list()`/`struct_()` instead.

## Name/position selectors

```@docs
Selectors.by_name
Selectors.by_index
Selectors.matches
Selectors.starts_with
Selectors.ends_with
Selectors.contains
```

```@example selectors
select(df, Selectors.starts_with("f"))
```

`strict` (default `true`) controls what happens when a name/index doesn't exist: `by_name`/`by_index` raise a `PolarsError`; passing `strict=false` silently skips it instead.

!!! note "`by_index` is 1-based, unlike py-polars' 0-based `cs.by_index`"
    Matches this package's own `nth` (see [Functions](@ref)) — 1-based indexing is the convention everywhere else in this Julia package. Negative indices count back from the end (`by_index(-1)` is the last column, same as `nth(-1)`).

## Combining selectors

Selectors combine with `|` (union), `&` (intersection), `-` (difference), and `xor` (exclusive or) — each returns another `Selector`:

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

!!! note "Julia's `xor`, not `^`"
    Python's `cs.numeric() ^ cs.string()` maps to Julia's `xor(a, b)`/`a ⊻ b` — see its docs on the
    [Expressions](@ref) page, in [Boolean](@ref) — **not** `^`, which always means exponentiation
    in Julia.

!!! warning "Mixing a `Selector` with a plain `Expr` is a `MethodError`"
    `Selectors.numeric() | col("x")` has genuinely ambiguous intent — does `col("x")` mean "the column named x" or "select by name x"? No method exists for the mixed case, in either argument order, on purpose: combine two `Selector`s (e.g. `Selectors.numeric() | Selectors.by_name("x")`), not a `Selector` and a bare `Expr`.

## Scope

- `datetime()`/`duration()` match *any* time unit/time zone — there is no equivalent of py-polars' `cs.datetime(time_unit="ms")` matching one specific unit.
- `list()`/`array()` match *any* inner dtype — there is no recursive `cs.list(cs.numeric())`-style inner-selector composition.
