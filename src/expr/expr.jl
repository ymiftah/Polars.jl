"""
    Expr

Internal structure representing a value in a Polars expression.
This should not be constructed directly but rather use helper functions
such as [`col`](@ref).
"""
mutable struct Expr
    ptr::Ptr{polars_expr_t}

    Expr(ptr) = finalizer(polars_expr_destroy, new(ptr))
end

Base.unsafe_convert(::Type{Ptr{polars_expr_t}}, expr::Expr) = expr.ptr

# `Expr` has no iteration protocol, so without this method it would hit Base's generic
# `broadcastable(x) = collect(x)` fallback and fail with a confusing `MethodError: no method
# matching length(::Expr)` inside a dot-broadcast expression like `col("x") .> 1`. Wrapping in
# `Ref` marks `Expr` as a scalar for broadcasting purposes -- the same idiom
# `AbstractString`/`Symbol`/`Missing` use -- so it participates as-is instead of being iterated.
# Refer to https://docs.julialang.org/en/v1/manual/interfaces/#man-interfaces-broadcasting
Base.Broadcast.broadcastable(expr::Expr) = Ref(expr)

Base.convert(::Type{Expr}, ::Colon) = col("*")
function Base.convert(::Type{Expr}, v::Int32)
    out = polars_expr_literal_i32(v)
    return Expr(out)
end
function Base.convert(::Type{Expr}, v::Int64)
    out = polars_expr_literal_i64(v)
    return Expr(out)
end
function Base.convert(::Type{Expr}, v::UInt32)
    out = polars_expr_literal_u32(v)
    return Expr(out)
end
function Base.convert(::Type{Expr}, v::UInt64)
    out = polars_expr_literal_u64(v)
    return Expr(out)
end
function Base.convert(::Type{Expr}, v::Bool)
    out = polars_expr_literal_bool(v)
    return Expr(out)
end
function Base.convert(::Type{Expr}, f::Float32)
    out = polars_expr_literal_f32(f)
    return Expr(out)
end
function Base.convert(::Type{Expr}, f::Float64)
    out = polars_expr_literal_f64(f)
    return Expr(out)
end
function Base.convert(::Type{Expr}, ::Missing)
    out = polars_expr_literal_null()
    return Expr(out)
end
function Base.convert(::Type{Expr}, s::String)
    out = Ref{Ptr{polars_expr_t}}()
    err = polars_expr_literal_utf8(s, ncodeunits(s), out)
    polars_error(err)
    return Expr(out[])
end
function Base.convert(::Type{Expr}, v::AbstractVector)
    df = DataFrame((; literal = collect(v)))
    series = df[:literal]
    out = API.polars_expr_lit_series(series)
    return Expr(out)
end

# Date/Time/DateTime literals: there is no dedicated `polars_expr_literal_date`/etc. FFI
# primitive, so these compose the existing integer-literal + cast primitives instead, reusing the
# exact epoch-math formulas `arrowvector` (src/arrow/array.jl) already uses to encode these types
# for the Arrow C Data Interface -- same reference points, same signed-ness, same units.
#
# One consequence of building these as `cast(lit(integer), dtype)` rather than a genuine literal
# node: `Polars.Meta.is_literal` reports `false` for them (a `Cast(Literal(...))` tree, not a
# `Literal` node) -- cosmetic only, since polars' constant-folding optimizer collapses
# `Cast(Literal(...))` before execution regardless. See docs/src/limitations.md.
function Base.convert(::Type{Expr}, d::Date)
    # days since 1970-01-01, matching arrowvector(::Vector{Date})'s Int32 conversion exactly.
    days = Int32(Dates.value(d - Date(1970, 01, 01)))
    return cast(convert(Expr, days), Date)
end
function Base.convert(::Type{Expr}, t::Dates.Time)
    # nanoseconds since midnight, matching arrowvector(::Vector{Dates.Time})'s Int64 conversion.
    ns = Int64(Dates.value(t))
    return cast(convert(Expr, ns), Dates.Time)
end
function Base.convert(::Type{Expr}, dt::DateTime)
    # nanoseconds since 1970-01-01, matching arrowvector(::Vector{DateTime})'s Int64 conversion --
    # built at :ns, so this inherits that path's ~1678-2262 range limit (Int64 nanoseconds
    # overflows outside that range). See docs/src/limitations.md.
    ns = Dates.Nanosecond(dt - DateTime(1970, 01, 01)).value
    return cast_datetime(convert(Expr, ns); time_unit = :ns, time_zone = nothing)
end

# Derived comparison DSL primitives -- polars' C ABI only wraps `eq`/`lt`/`gt` directly (see
# `@wrap_simple_ops` below); `<=`/`>=`/`!=` compose them with `not`, which preserves polars' null
# propagation correctly (`not` of a null is null, matching what `<=`/`>=`/`!=` must do when an
# operand is incomparable). Not exported -- these are an internal implementation detail of the
# operators below, unlike `eq`/`gt`/`lt`, which mirror real `polars::Expr` methods 1:1.
_le(a::Expr, b::Expr) = not(gt(a, b))
_ge(a::Expr, b::Expr) = not(Base.lt(a, b))
_neq(a::Expr, b::Expr) = not(eq(a, b))

# For each `op`, this generates:
#   - `(Expr, Expr)`      -- the plain case, dispatches straight to `dsl`
#   - `(Expr, Any)` / `(Any, Expr)`  -- `convert`s the literal side to an `Expr` first
#   - `(Expr, Missing)` / `(Missing, Expr)`  -- strictly more specific than Base's own
#     `missing.jl` fallbacks (e.g. `==(::Any, ::Missing) = missing`), which would otherwise tie
#     with the `(Expr, Any)` method above and make `col("x") == missing` raise a `MethodError:
#     ambiguous`. These route `missing` through `convert(Expr, missing)` -- a real DSL null
#     literal -- so it participates in the DSL's own null-propagation instead of Julia's.
# `dsl` is looked up unqualified except `Base.lt`, which collides with an unexported internal
# `Base.lt` binding and must stay qualified (same class of gotcha as `Expr::product`/
# `Base.product`).
for (op, dsl) in (
        (:(==), :eq), (:!=, :_neq),
        (:<, :(Base.lt)), (:<=, :_le),
        (:>, :gt), (:>=, :_ge),
        (:+, :add), (:-, :sub), (:*, :mul), (:/, :div), (:^, :pow),
        (:&, :and), (:|, :or),
    )
    @eval begin
        Base.$op(a::Expr, b::Expr) = $dsl(a, b)
        Base.$op(a::Expr, b) = $dsl(a, convert(Expr, b))
        Base.$op(a, b::Expr) = $dsl(convert(Expr, a), b)
        Base.$op(a::Expr, ::Missing) = $dsl(a, convert(Expr, missing))
        Base.$op(::Missing, b::Expr) = $dsl(convert(Expr, missing), b)
    end
end

"""
    -(expr::Polars.Expr)::Polars.Expr

Unary negation.
"""
Base.:-(expr::Expr) = Expr(API.polars_expr_neg(expr))
# Not equivalent to `0 - expr`: on an unsigned-integer column, `0 - expr` silently
# wraps (e.g. `UInt8` `0-1` gives `0xff`) where this raises instead, matching upstream's own
# per-dtype overflow validation.

"""
    floor_div(a::Polars.Expr, b::Polars.Expr)::Polars.Expr
    floor_div(a, b::Polars.Expr)::Polars.Expr
    floor_div(a::Polars.Expr, b)::Polars.Expr

Elementwise floor division (`a` divided by `b`, rounded down).
"""
floor_div(a::Expr, b::Expr) = Expr(API.polars_expr_floor_div(a, b))
floor_div(a, b::Expr) = floor_div(convert(Expr, a), b)
floor_div(a::Expr, b) = floor_div(a, convert(Expr, b))
# the named-function form of
# upstream's `//` operator (not spelled as a Julia operator here to avoid claiming `÷`/`div` for
# types this package doesn't own -- see the curried-forms note near `is_in`/`fill_null` above for
# the same piracy concern applied to operators)
export floor_div

"""
    col(name::Union{String,Symbol})::Polars.Expr

Returns an expression referencing a column in a dataframe. The special
column name `"*"` will select all columns in the dataframe.
"""
function col(name::AbstractString)
    expr = Ref{Ptr{polars_expr_t}}()
    err = polars_expr_col(name, ncodeunits(name), expr)
    polars_error(err)
    return Expr(expr[])
end
col(name::Symbol) = col(String(name))

"""
    _as_expr(x)::Expr

Coerces a column reference to an `Expr`: a `String`/`Symbol` becomes `col(x)`; an existing `Expr`
passes through unchanged. Shared by every verb that accepts either a column name or a full
expression (`select`, `filter`, `group_by`, `sort`, `join`, `over`, ...), in place of each one
repeating its own `ex -> ex isa String ? col(ex) : ex` inline.

Exhaustive over the three accepted input shapes (no generic fallback method): passing anything
else raises a clear `MethodError` right at the coercion site rather than deferring to a more
confusing failure further downstream (e.g. inside a later `convert(Vector{Expr}, ...)`).
"""
_as_expr(x::AbstractString) = col(String(x))
_as_expr(x::Symbol) = col(String(x))
_as_expr(x::Expr) = x

"""Shared `time_unit` resolver (`:ns`/`:us`/`:ms`) for every function accepting one -- `cast`,
[`cast_datetime`](@ref), [`cast_duration`](@ref) here, plus `Dt.timestamp` and
`Strings.to_datetime`."""
_time_unit_enum(time_unit::Symbol) = _enum_lookup(
    time_unit, "time_unit",
    :ns => API.PolarsTimeUnitNanosecond,
    :us => API.PolarsTimeUnitMicrosecond,
    :ms => API.PolarsTimeUnitMillisecond,
)

"""Shared `null_behavior` resolver (`:ignore`/`:drop`) for [`diff`](@ref) here and `Lists.diff`."""
_null_behavior_enum(null_behavior::Symbol) = _enum_lookup(
    null_behavior, "null_behavior",
    :ignore => API.PolarsNullBehaviorIgnore,
    :drop => API.PolarsNullBehaviorDrop,
)

"""
    nth(n::Int64)::Polars.Expr

Returns an expression referencing the nth column in a dataframe.
The `n` argument is *one indexing based*, meaning that columns start at 1.
Negative numbers reference columns starting from the end.
"""
function nth(n)
    n_zero = n < 0 ? n : n - 1
    expr = Ref{Ptr{polars_expr_t}}()
    err = polars_expr_nth(n_zero, expr)
    polars_error(err)
    return Expr(expr[])
end

"""
    element()::Polars.Expr

A placeholder for "the values in this group", used to build the `agg` expression passed to
[`pivot`](@ref) -- e.g. `Base.sum(element())`, `Base.first(element())` (the default).
"""
function element()
    return Expr(API.polars_expr_element())
end

"""
    len()::Polars.Expr

The number of rows in the current context: a whole frame in [`select`](@ref)/[`with_columns`](@ref),
or the current group inside [`agg`](@ref) (e.g. `agg(df, group, alias(len(), "n"))` for a group-size
count). Includes `null`s, unlike [`Polars.count`](@ref) (which only counts non-null values of a
specific expression).
"""
function len()
    return Expr(API.polars_expr_len())
end

@wrap_rename_method alias polars_expr_alias "Renames the result of this expression to a new name."
@wrap_rename_method prefix polars_expr_prefix "Adds a prefix to the name of the resulting expression."
@wrap_rename_method suffix polars_expr_suffix "Adds a suffix to the name of the resulting expression."
@wrap_rename_method prefix_fields polars_expr_prefix_fields "Adds a prefix to every *field name* of a Struct-typed expression (contrast [`prefix`](@ref), which renames the expression's own output name, not its fields)."
@wrap_rename_method suffix_fields polars_expr_suffix_fields "Adds a suffix to every *field name* of a Struct-typed expression (contrast [`suffix`](@ref), which renames the expression's own output name, not its fields)."

"""
    lit(x)::Polars.Expr

Transforms a literal value as an expression which will broadcast when used with other
expressions.
"""
function lit(v)
    return convert(Expr, v)
end

"""
Maps a Julia type to its `polars_value_type_t` C enum code for a *plain, parameter-free* dtype
match -- returns `nothing` if `dtype` isn't one of these.

Deliberately excludes `DateTime` and the duration `Period` subtypes even though polars has dtypes
for them: those need a time unit (and `DateTime` a time zone) that a bare `polars_value_type_t`
code can't carry, so `cast` and [`Selectors.by_dtype`](@ref) each handle them separately
(before/after calling this, respectively) rather than through this shared table.

Single source of truth for the plain-dtype mapping, used by both.
"""
function _plain_value_type_code(dtype)
    return if dtype == Missing
        PolarsValueTypeNull
    elseif dtype == Bool
        PolarsValueTypeBoolean
    elseif dtype == UInt8
        PolarsValueTypeUInt8
    elseif dtype == UInt16
        PolarsValueTypeUInt16
    elseif dtype == UInt32
        PolarsValueTypeUInt32
    elseif dtype == UInt64
        PolarsValueTypeUInt64
    elseif dtype == Int8
        PolarsValueTypeInt8
    elseif dtype == Int16
        PolarsValueTypeInt16
    elseif dtype == Int32
        PolarsValueTypeInt32
    elseif dtype == Int64
        PolarsValueTypeInt64
    elseif dtype == Float32
        PolarsValueTypeFloat32
    elseif dtype == Float64
        PolarsValueTypeFloat64
    elseif dtype == String
        PolarsValueTypeString
    elseif dtype == Vector{UInt8}
        PolarsValueTypeBinary
    elseif dtype == Date
        PolarsValueTypeDate
    elseif dtype == Dates.Time
        PolarsValueTypeTime
    else
        nothing
    end
end

"""
    cast(expr::Polars.Expr, dtype::Type; time_unit::Symbol=:us,
         time_zone::Union{Nothing,AbstractString}=nothing)::Polars.Expr
    cast(dtype::Type; kwargs...)::Base.Callable

Casts the series represented by the expression to the provided `dtype`.

Supported targets: `Missing`, the physical numeric types, `Bool`, `String`, `Vector{UInt8}`
(Binary), `Date`, `Dates.Time`, `DateTime` (naive or timezone-aware -- see `time_unit`/`time_zone`
below), and `Dates.Nanosecond`/`Dates.Microsecond`/`Dates.Millisecond` (Duration, resolution
implied by the chosen `Period` subtype). Any other target raises an error.

`Categorical`, `Decimal`, `List`, and `Struct` need parameters this single-type-argument form
can't carry -- see [`cast_categorical`](@ref)/[`cast_decimal`](@ref) for those.

`time_unit`/`time_zone` only apply to a `DateTime` target (ignored otherwise):
- `time_unit`: one of `:ns`, `:us` (default), `:ms`
- `time_zone`: `nothing` (default, naive) or an IANA time zone name

`strict`: if `false` (default), a value that doesn't fit the target type becomes `missing`
(e.g. an out-of-range integer overflow, or an out-of-range `Time` cast) rather than raising.
If `true`, such a value raises a `PolarsError` instead. Only applies to the plain-value-type path
below (not the `DateTime`/`Nanosecond`/`Microsecond`/`Millisecond` special cases above, which have
their own dedicated entry points and always cast non-strictly).
"""
function cast(
        expr, dtype;
        time_unit::Symbol = :us, time_zone::Union{Nothing, AbstractString} = nothing,
        strict::Bool = false
    )
    if dtype == DateTime
        return cast_datetime(expr; time_unit, time_zone)
    elseif dtype == Dates.Nanosecond
        return cast_duration(expr; time_unit = :ns)
    elseif dtype == Dates.Microsecond
        return cast_duration(expr; time_unit = :us)
    elseif dtype == Dates.Millisecond
        return cast_duration(expr; time_unit = :ms)
    end

    value_type = _plain_value_type_code(dtype)
    value_type === nothing && error("could not cast to type $dtype")

    out = Ref{Ptr{polars_expr_t}}()
    err = if strict
        API.polars_expr_strict_cast(expr, value_type, out)
    else
        API.polars_expr_cast(expr, value_type, out)
    end
    polars_error(err)
    return Expr(out[])
end
cast(dtype; kwargs...) = expr -> cast(expr, dtype; kwargs...)

"""
    cast_datetime(expr::Polars.Expr; time_unit::Symbol=:us,
                  time_zone::Union{Nothing,AbstractString}=nothing)::Polars.Expr

Casts `expr` to `Datetime(time_unit, time_zone)`.

Also reachable as `cast(expr, DateTime; time_unit, time_zone)` -- this is the underlying
implementation. `Datetime` needs its own entry point because `polars_value_type_t` (what the plain
`cast` dispatches on) can't carry a time unit or time zone.

- `time_unit`: one of `:ns`, `:us` (default), `:ms`
- `time_zone`: `nothing` (default, naive) or an IANA time zone name
"""
function cast_datetime(
        expr::Expr; time_unit::Symbol = :us, time_zone::Union{Nothing, AbstractString} = nothing
    )
    unit_enum = _time_unit_enum(time_unit)
    tz = time_zone === nothing ? "" : String(time_zone)
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_cast_datetime(expr, unit_enum, tz, ncodeunits(tz), out)
    polars_error(err)
    return Expr(out[])
end
@curry cast_datetime(; time_unit::Symbol = :us, time_zone::Union{Nothing, AbstractString} = nothing)

"""
    cast_duration(expr::Polars.Expr; time_unit::Symbol=:us)::Polars.Expr

Casts `expr` to `Duration(time_unit)`.

Also reachable via `cast(expr, Dates.Nanosecond|Microsecond|Millisecond)`, which just calls this
with the unit implied by the chosen `Period` subtype -- this named form is for when you'd rather
pass `time_unit` as a keyword.

- `time_unit`: one of `:ns`, `:us` (default), `:ms`
"""
function cast_duration(expr::Expr; time_unit::Symbol = :us)
    unit_enum = _time_unit_enum(time_unit)
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_cast_duration(expr, unit_enum, out)
    polars_error(err)
    return Expr(out[])
end
@curry cast_duration(; time_unit::Symbol = :us)

"""
    cast_decimal(expr::Polars.Expr, precision::Integer, scale::Integer)::Polars.Expr
    cast_decimal(precision::Integer, scale::Integer)::Base.Callable

Casts `expr` to `Decimal(precision, scale)` (`1 <= precision <= 38`; `scale` is the number of
digits after the decimal point).

Decimal columns have no dedicated Julia read path yet -- materializing one via `collect`/`getindex`
is not supported -- so this is mainly useful for writing out decimal-typed columns (e.g. to
parquet) rather than reading them back in Julia.
"""
function cast_decimal(expr::Expr, precision::Integer, scale::Integer)
    out = API.polars_expr_cast_decimal(expr, Csize_t(precision), Csize_t(scale))
    return Expr(out)
end
@curry cast_decimal(precision::Integer, scale::Integer)

"""
    cast_categorical(expr::Polars.Expr)::Polars.Expr

Casts `expr` to `Categorical`, using the global category registry shared by every Categorical
column in the session; there is no per-column category set. Reading a Categorical column back already materializes
it as `String` with no extra step (see the `Strings` namespace for string operations on it).
"""
function cast_categorical(expr::Expr)
    out = API.polars_expr_cast_categorical(expr)
    return Expr(out)
end

"""
    when(cond::Polars.Expr, then, otherwise)::Polars.Expr

Ternary conditional expression: evaluates to `then` for rows where `cond` is `true`, and to
`otherwise` otherwise. `then`/`otherwise` may be `Polars.Expr`s or literal scalars (promoted
via [`lit`](@ref)).
"""
function when(cond::Expr, then, otherwise)
    then = convert(Expr, then)
    otherwise = convert(Expr, otherwise)
    out = API.polars_expr_when_then_otherwise(cond, then, otherwise)
    return Expr(out)
end

"""
    when(pairs::Pair...; otherwise)::Polars.Expr

Chained conditional expression. Evaluates each `cond => value` pair in order and takes the first
`value` whose `cond` is `true`, falling back to `otherwise` if none match. `cond`s must be `Polars.Expr`s; `value`s and `otherwise` may be `Polars.Expr`s or
literal scalars (promoted via [`lit`](@ref)).

```julia
when(col("x") == 1 => "one", col("x") == 2 => "two"; otherwise = "other")
```
"""
function when(pairs::Pair...; otherwise)
    conds = Expr[convert(Expr, first(p)) for p in pairs]
    vals = Expr[convert(Expr, last(p)) for p in pairs]
    otherwise = convert(Expr, otherwise)
    GC.@preserve conds vals begin
        cond_ptrs = Ptr{polars_expr_t}[c.ptr for c in conds]
        val_ptrs = Ptr{polars_expr_t}[v.ptr for v in vals]
        out = API.polars_expr_when_then(cond_ptrs, val_ptrs, length(cond_ptrs), otherwise)
    end
    return Expr(out)
end

# We just copy the rust code here and generate functions on the fly.
@wrap_simple_ops begin
    gen_impl_expr!(polars_expr_keep_name, Expr::keep_name, "Keeps `expr`'s original column name, overriding any rename that would otherwise result from the operation it's applied to (e.g. after an arithmetic operator or a namespaced function call).")
    gen_impl_expr!(polars_expr_to_lowercase, Expr::to_lowercase, "Lowercases the name of the resulting expression.")
    gen_impl_expr!(polars_expr_to_uppercase, Expr::to_uppercase, "Uppercases the name of the resulting expression.")

    gen_impl_expr!(polars_expr_sum, Expr::sum, "Sums the non-null values of `expr`, one result per group (or a single overall value outside a `group_by`).")
    gen_impl_expr!(polars_expr_min, Expr::min, "Returns the minimum non-null value of `expr`, one result per group (or a single overall value outside a `group_by`). Like other aggregations, `NaN` values are ignored -- see [`nan_min`](@ref) to propagate `NaN` into the result instead.")
    gen_impl_expr!(polars_expr_max, Expr::max, "Returns the maximum non-null value of `expr`, one result per group (or a single overall value outside a `group_by`). Like other aggregations, `NaN` values are ignored -- see [`nan_max`](@ref) to propagate `NaN` into the result instead.")
    gen_impl_expr!(polars_expr_arg_min, Expr::arg_min, "Returns the (0-indexed) row position of the minimum value of `expr` within its group.")
    gen_impl_expr!(polars_expr_arg_max, Expr::arg_max, "Returns the (0-indexed) row position of the maximum value of `expr` within its group.")
    gen_impl_expr!(polars_expr_nan_min, Expr::nan_min, "Like [`min`](@ref), but propagates `NaN`: if any value in the group is `NaN`, the result is `NaN` instead of the ordinary minimum.")
    gen_impl_expr!(polars_expr_nan_max, Expr::nan_max, "Like [`max`](@ref), but propagates `NaN`: if any value in the group is `NaN`, the result is `NaN` instead of the ordinary maximum.")

    gen_impl_expr!(polars_expr_floor, Expr::floor, "Rounds each value of `expr` down to the nearest integer.")
    gen_impl_expr!(polars_expr_ceil, Expr::ceil, "Rounds each value of `expr` up to the nearest integer.")
    gen_impl_expr!(polars_expr_abs, Expr::abs, "Absolute value of each value of `expr`.")
    gen_impl_expr!(polars_expr_cos, Expr::cos, "Cosine of each value of `expr`, in radians.")
    gen_impl_expr!(polars_expr_sin, Expr::sin, "Sine of each value of `expr`, in radians.")
    gen_impl_expr!(polars_expr_tan, Expr::tan, "Tangent of each value of `expr`, in radians.")
    gen_impl_expr!(polars_expr_cosh, Expr::cosh, "Hyperbolic cosine of each value of `expr`.")
    gen_impl_expr!(polars_expr_sinh, Expr::sinh, "Hyperbolic sine of each value of `expr`.")
    gen_impl_expr!(polars_expr_tanh, Expr::tanh, "Hyperbolic tangent of each value of `expr`.")
    gen_impl_expr!(polars_expr_arccos, Expr::arccos, "Inverse cosine of each value of `expr`, in radians.")
    gen_impl_expr!(polars_expr_arcsin, Expr::arcsin, "Inverse sine of each value of `expr`, in radians.")
    gen_impl_expr!(polars_expr_arctan, Expr::arctan, "Inverse tangent of each value of `expr`, in radians.")
    gen_impl_expr!(polars_expr_arccosh, Expr::arccosh, "Inverse hyperbolic cosine of each value of `expr`.")
    gen_impl_expr!(polars_expr_arcsinh, Expr::arcsinh, "Inverse hyperbolic sine of each value of `expr`.")
    gen_impl_expr!(polars_expr_arctanh, Expr::arctanh, "Inverse hyperbolic tangent of each value of `expr`.")
    gen_impl_expr!(polars_expr_cot, Expr::cot, "Cotangent of each value of `expr`, in radians.")
    gen_impl_expr!(polars_expr_degrees, Expr::degrees, "Converts each value of `expr` from radians to degrees.")
    gen_impl_expr!(polars_expr_radians, Expr::radians, "Converts each value of `expr` from degrees to radians.")

    gen_impl_expr!(polars_expr_sqrt, Expr::sqrt, "Square root of each value of `expr`.")
    gen_impl_expr!(polars_expr_cbrt, Expr::cbrt, "Cube root of each value of `expr`.")
    gen_impl_expr!(polars_expr_sign, Expr::sign, "Sign of each value of `expr`: `-1`, `0`, or `1` (float dtypes only; `NaN` maps to `NaN`).")
    gen_impl_expr!(polars_expr_exp, Expr::exp, "`e` raised to each value of `expr`.")
    gen_impl_expr!(polars_expr_log1p, Expr::log1p, "Natural logarithm of `1 + expr`, elementwise -- more accurate than `log(lit(ℯ), expr + 1)` for values near zero.")

    gen_impl_expr!(polars_expr_rle, Expr::rle, "Run-length-encodes `expr`: collapses each run of consecutive identical values into one row, a `Struct{len, value}` (see [Struct](@ref expr-struct)) holding the run's length and the repeated value. Consecutive `null`s form a run like any other value.")
    gen_impl_expr!(polars_expr_rle_id, Expr::rle_id, "Maps each value of `expr` to a 0-indexed run ID: rows in the same run of consecutive identical values share an ID, which increments at each run boundary. Unlike [`rle`](@ref), the column keeps its length -- one output row per input row.")

    gen_impl_expr!(polars_expr_n_unique, Expr::n_unique, "Counts the number of distinct values in `expr` (`null` counts as one distinct value), one result per group (or a single overall count outside a `group_by`).")
    gen_impl_expr!(polars_expr_is_duplicated, Expr::is_duplicated, "Row-wise boolean flag: `true` for every occurrence of a value that appears more than once in `expr`. See [`is_unique`](@ref) for the complementary flag.")
    gen_impl_expr!(polars_expr_is_unique, Expr::is_unique, "Row-wise boolean flag: `true` for every value that appears exactly once in `expr`. See [`is_duplicated`](@ref) for the complementary flag.")
    gen_impl_expr!(polars_expr_is_first_distinct, Expr::is_first_distinct, "Row-wise boolean flag: `true` only for the first occurrence of each distinct value in `expr`. See [`is_last_distinct`](@ref) for the complementary flag.")
    gen_impl_expr!(polars_expr_is_last_distinct, Expr::is_last_distinct, "Row-wise boolean flag: `true` only for the last occurrence of each distinct value in `expr`. See [`is_first_distinct`](@ref) for the complementary flag.")
    gen_impl_expr!(polars_expr_count, Expr::count, "Counts the number of non-null values in `expr`, one result per group (or a single overall count outside a `group_by`). See [`null_count`](@ref) for the complementary count.")
    gen_impl_expr!(polars_expr_first, Expr::first, "Returns the first value of `expr` within its group, by row order (not sorted order).")
    gen_impl_expr!(polars_expr_last, Expr::last, "Returns the last value of `expr` within its group, by row order (not sorted order).")

    gen_impl_expr!(polars_expr_not, Expr::not, "Logical negation of a boolean expression: `true`↔`false`, and `null` stays `null` (matches polars' three-valued logic). There is no unary operator form -- `not` must be called directly.")
    gen_impl_expr!(polars_expr_is_finite, Expr::is_finite, "Row-wise boolean flag: `true` where the (float) value is finite (neither `±Inf` nor `NaN`); `null` stays `null`.")
    gen_impl_expr!(polars_expr_is_infinite, Expr::is_infinite, "Row-wise boolean flag: `true` where the (float) value is `Inf` or `-Inf`; `null` stays `null`.")
    gen_impl_expr!(polars_expr_is_nan, Expr::is_nan, "Row-wise boolean flag: `true` where the (float) value is `NaN`; `null` stays `null` (a `null` is not `NaN`).")
    gen_impl_expr!(polars_expr_is_null, Expr::is_null, "Row-wise boolean flag: `true` where the value is `null`.")
    gen_impl_expr!(polars_expr_is_not_null, Expr::is_not_null, "Row-wise boolean flag: `true` where the value is not `null`.")
    gen_impl_expr!(polars_expr_null_count, Expr::null_count, "Counts the number of `null` values in `expr`, one result per group (or a single overall count outside a `group_by`). See [`count`](@ref) for the complementary count.")
    gen_impl_expr!(polars_expr_drop_nans, Expr::drop_nans, "Removes `NaN` values from `expr`, shortening the column. Compare the frame-level `drop_nulls` (see [DataFrame](@ref)), which drops whole rows instead of individual values.")
    gen_impl_expr!(polars_expr_drop_nulls, Expr::drop_nulls, "Removes `null` values from `expr`, shortening the column -- the expression-level counterpart to the frame-level `drop_nulls` (see [DataFrame](@ref)), which drops whole rows instead of individual values.")

    gen_impl_expr!(polars_expr_implode, Expr::implode, "Collects every value of `expr` in the current context (or per group, inside `agg`) into a single `List` value (see [List](@ref expr-list)).")
    gen_impl_expr!(polars_expr_reverse, Expr::reverse, "Reverses the row order of `expr`'s values.")

    gen_impl_expr!(polars_expr_arg_unique, Expr::arg_unique, "The row indices of the first occurrence of each distinct value of `expr`, in order of first appearance.")
    gen_impl_expr!(polars_expr_to_physical, Expr::to_physical, "The physical (storage) representation of `expr` -- e.g. a `Date` becomes its `Int32` days-since-epoch, a `Categorical` its `UInt32` index. Leaves already-physical dtypes unchanged.")
    gen_impl_expr!(polars_expr_lower_bound, Expr::lower_bound, "A single-row column holding the smallest value `expr`'s dtype can represent.")
    gen_impl_expr!(polars_expr_upper_bound, Expr::upper_bound, "A single-row column holding the largest value `expr`'s dtype can represent.")

    gen_impl_expr_binary!(polars_expr_eq, Expr::eq, "Elementwise equality between `a` and `b` -- the named-function form of `a .== b` (see [Named binary functions](@ref)). Comparing against `null` gives `null`, not `false` (three-valued logic).")
    gen_impl_expr_binary!(polars_expr_lt, Expr::lt, "Elementwise `a < b` -- the named-function form of the `<` operator. Call it qualified as `Base.lt(a, b)`, or use `.>` with the arguments flipped.")
    gen_impl_expr_binary!(polars_expr_gt, Expr::gt, "Elementwise `a > b` -- the named-function form of `a .> b`.")
    gen_impl_expr_binary!(polars_expr_or, Expr::or, "Elementwise logical OR between two boolean expressions -- the named-function form of `a .| b`.")
    gen_impl_expr_binary!(polars_expr_xor, Expr::xor, "Elementwise logical XOR between two boolean expressions. Has no operator equivalent in this package -- must be called by name.")
    gen_impl_expr_binary!(polars_expr_and, Expr::and, "Elementwise logical AND between two boolean expressions -- the named-function form of `a .& b`.")

    gen_impl_expr_binary!(polars_expr_pow, Expr::pow, "Elementwise `a ^ b` -- the named-function form of the `^` operator.")
    gen_impl_expr_binary!(polars_expr_add, Expr::add, "Elementwise `a + b` -- the named-function form of the `+` operator.")
    gen_impl_expr_binary!(polars_expr_sub, Expr::sub, "Elementwise `a - b` -- the named-function form of the `-` operator.")
    gen_impl_expr_binary!(polars_expr_mul, Expr::mul, "Elementwise `a * b` -- the named-function form of the `*` operator.")
    gen_impl_expr_binary!(polars_expr_div, Expr::div, "Elementwise `a / b` -- the named-function form of the `/` operator.")
    # `floor_div` is hand-written below (near the operator overload loop), not generated here --
    # it needs literal-argument `convert` overloads the macro's plain `(Expr, Expr)` shape can't
    # express (mirroring `is_in`/`fill_null`'s own curried forms further down).

    gen_impl_expr_binary!(polars_expr_fill_null, Expr::fill_null, "Replaces every `null` value in `a` with the corresponding value of `b` (a literal via `lit`, or another expression).\n\n!!! note \"Has a curried form\"\n    `fill_null(value)` -- see [Curried forms for pipe-based composition](@ref)."; curried = true)
    gen_impl_expr_binary!(polars_expr_fill_nan, Expr::fill_nan, "Replaces every `NaN` value in `a` with the corresponding value of `b`.\n\n!!! note \"Has a curried form\"\n    `fill_nan(value)` -- see [Curried forms for pipe-based composition](@ref)."; curried = true)
    gen_impl_expr_binary!(polars_expr_is_in, Expr::is_in, "Row-wise boolean flag: `true` where the value of `a` appears in `b` (typically `implode(lit(values))`, or another column); see the `lit(::Vector)` section below for how to build `b`.\n\n!!! note \"Has a curried form\"\n    `is_in(values)` -- see [Curried forms for pipe-based composition](@ref)."; curried = true)

    gen_impl_expr_binary!(polars_expr_shift, Expr::shift, "Shifts `a`'s values down by `b` rows (negative `b` shifts up), filling the vacated positions with `null`.\n\n!!! note \"Has a curried form\"\n    `shift(n)` -- see [Curried forms for pipe-based composition](@ref)."; curried = true)
    gen_impl_expr_binary!(polars_expr_pct_change, Expr::pct_change, "Percent change between each value of `a` and the value `b` rows earlier: `(a[i] - a[i-b]) / a[i-b]`.\n\n!!! note \"Has a curried form\"\n    `pct_change(n)` -- see [Curried forms for pipe-based composition](@ref)."; curried = true)

    gen_impl_expr_binary!(polars_expr_rem, Expr::rem, "Remainder of `a / b` (elementwise), matching the sign of `a` -- the named-function form of `Base.rem` extended to `Expr` arguments.")

    gen_impl_expr_binary!(polars_expr_arctan2, Expr::arctan2, "Two-argument inverse tangent: `arctan2(y, x)` is the angle in radians between the positive x-axis and the point `(x, y)`, using both signs to pick the correct quadrant. Note the `y`-then-`x` argument order, matching upstream polars and C's `atan2`.")
    gen_impl_expr_binary!(polars_expr_dot, Expr::dot, "The dot product of two columns: the sum of their elementwise product, as a single row.")
end

"""
    entropy(expr::Polars.Expr; base::Real=ℯ, normalize::Bool=true)::Polars.Expr
    entropy(; base::Real=ℯ, normalize::Bool=true)

The Shannon entropy of `expr`'s value distribution, as a single row. `base` is the logarithm base
(`ℯ` for nats, `2` for bits); `normalize=true` normalizes the counts into probabilities first.

!!! note "Has a curried form"
    The keyword-only method above, for `|>` pipelines.
"""
function entropy(expr::Expr; base::Real = ℯ, normalize::Bool = true)
    return Expr(API.polars_expr_entropy(expr, Float64(base), normalize))
end
@curry entropy(; base::Real = ℯ, normalize::Bool = true)

"""
    extend_constant(expr::Polars.Expr, value, n)::Polars.Expr

Appends `n` copies of `value` to the end of `expr`. `value` and `n` may be expressions or plain
scalars; `value` may be `missing`, which appends nulls.
"""
function extend_constant(expr::Expr, value, n)
    return Expr(
        API.polars_expr_extend_constant(expr, convert(Expr, value), convert(Expr, n)),
    )
end

"""
    shuffle(expr::Polars.Expr; seed::Union{Nothing,Integer}=nothing)::Polars.Expr

Randomly permutes `expr`'s values. `seed` makes the permutation reproducible; `nothing` (the
default) draws a fresh seed from the OS each call.
"""
function shuffle(expr::Expr; seed::Union{Nothing, Integer} = nothing)
    seed_ref = seed === nothing ? Ptr{UInt64}(C_NULL) : Ref(UInt64(seed))
    out = GC.@preserve seed_ref API.polars_expr_shuffle(expr, seed_ref)
    return Expr(out)
end

"""
    Base.reshape(expr::Polars.Expr, dims::Integer...)::Polars.Expr

Reshapes `expr` into an `Array`-dtype column of the given dimensions. A `-1` as the *first*
dimension is inferred from the length (only that position; a `-1` elsewhere raises a
`PolarsError`). **Building the plan and `collect`ing it both succeed, but nothing that
needs to resolve the `Array` dtype does**: `collect_schema`, `schema`, and indexing into a
collected `DataFrame`'s `Array` column all raise an `ErrorException` from the Arrow schema parser,
which does not yet recognize the fixed-size-list format (`"+w:N"`) -- this is a package
limitation, not a query error. Use [`explain`](@ref) to confirm the plan was built, or cast the
result away from `Array` before inspecting it. Extends `Base.reshape` rather than shadowing it,
the same way `Base.get`/`Base.sort`/`Base.tail` are extended elsewhere in this file.
"""
function Base.reshape(expr::Expr, dims::Integer...)
    dims_vec = Int64[Int64(d) for d in dims]
    out = GC.@preserve dims_vec API.polars_expr_reshape(expr, pointer(dims_vec), length(dims_vec))
    return Expr(out)
end

export entropy, extend_constant, shuffle

"""
    unique(expr::Polars.Expr; maintain_order::Bool=false)::Polars.Expr

Returns the distinct values of `expr`, shortening the column. Inside `agg`, per-group distinct
values are automatically collected into a `List` (see [List](@ref expr-list)) so the aggregation
still produces one row per group.

`maintain_order` (default `false`) preserves the order values first appear in; the default allows
more optimization but does not guarantee any particular order. This is a separate, hand-written
method (not `@generate_expr_fns`-derived like most other `Expr` methods) precisely because it
needs this extra keyword, dispatching between polars' own `Expr::unique`/`Expr::unique_stable`.

!!! note
    Extends `Base.unique` (which otherwise operates on collections); `unique` collides with an
    exported `Base` name, so this is `Base.unique(...)`, not a plain `function unique(...)` -- see
    the matching note on [`tail`](@ref)'s definition for why that distinction matters.
"""
Base.unique(expr::Expr; maintain_order::Bool = false) =
    Expr(maintain_order ? API.polars_expr_unique_stable(expr) : API.polars_expr_unique(expr))

@wrap_expr_method flatten(expr::Expr; empty_as_null::Bool = true, keep_nulls::Bool = true) polars_expr_flatten "Explodes a `List`-typed `expr` back into one row per element -- the expression-level inverse of [`implode`](@ref). `empty_as_null`: an empty list produces one `null` row when `true` (default), rather than disappearing. `keep_nulls`: a `null` list entry produces one `null` row when `true` (default), rather than disappearing."
export flatten

"""
    all(expr::Polars.Expr; ignore_nulls::Bool=true)::Polars.Expr

Whether every value of `expr` is `true`, one result per group (or a single overall value outside
a `group_by`). If `ignore_nulls` is `false`, three-valued (Kleene) logic applies: a `null` present
with no `false` value makes the result `null`. Extends `Base.all` (a Base-exported name) rather
than being a plain function, so it's reachable unqualified -- see [`any`](@ref) for the
complementary reduction, and the top-level [`all_horizontal`](@ref)/[`any_horizontal`](@ref) for
the row-wise (not per-column) versions across multiple expressions.
"""
Base.all(expr::Expr; ignore_nulls::Bool = true) = Expr(API.polars_expr_all(expr, ignore_nulls))

"""
    any(expr::Polars.Expr; ignore_nulls::Bool=true)::Polars.Expr

Whether any value of `expr` is `true`, one result per group (or a single overall value outside
a `group_by`). If `ignore_nulls` is `false`, three-valued (Kleene) logic applies: a `null` present
with no `true` value makes the result `null`. See [`all`](@ref) for the complementary reduction.
"""
Base.any(expr::Expr; ignore_nulls::Bool = true) = Expr(API.polars_expr_any(expr, ignore_nulls))

"""
    log(base::Polars.Expr, x::Polars.Expr)::Polars.Expr

Logarithm of `x` in base `base` -- e.g. `log(lit(2), col("x"))` for log base 2. For the natural
logarithm, use `lit(ℯ)`.

!!! note "The base comes first"
    Argument order matches `Base.log(b, x)`, where the base is the first argument
    (`log(2, 8) == 3`). Both arguments are expressions, so writing them the other way round
    produces a different number rather than an error.
"""
function Base.log(base::Expr, x::Expr)
    out = API.polars_expr_log(x, base)
    return Expr(out)
end

"""
    log10(expr::Polars.Expr)::Polars.Expr

Base-10 logarithm of each value of `expr`.
"""
Base.log10(expr::Expr) = log(convert(Expr, 10), expr)

"""
    has_nulls(expr::Polars.Expr)::Polars.Expr

Whether `expr` contains any `null` value, one result per group (or a single overall value outside
a `group_by`).
"""
has_nulls(expr::Expr) = null_count(expr) > 0
export has_nulls

# The plain `Fix2`-style curries for `is_in`/`fill_null`/`fill_nan`/`shift`/`pct_change` are
# generated by `@wrap_simple_ops` from each primal's own `curried = true` option, right next to it
# in the block above. This is the one exception -- `is_in` also needs an `AbstractVector`-specific
# overload (more specific than the macro-generated `is_in(b) = Base.Fix2(is_in, convert(Expr,
# b))`, so it dispatches ahead of it) that `implode`s the vector into a single list-typed `Expr`
# first: the plain `convert(Expr, ::AbstractVector)` above builds a per-row *Series* literal
# instead, the wrong shape for `is_in`'s membership check against `b`.
is_in(other::AbstractVector) = Base.Fix2(is_in, implode(convert(Expr, other)))

# `log`/`rem` (and, elsewhere, `replace`/`diff`/`round`) deliberately get no curry at all. It isn't
# a dispatch-ambiguity concern, Julia always prefers Base's own concrete-type methods (e.g.
# `log(::Float64)`) over anything added here, so no ambiguity would occur. It's type piracy: a
# curry that's actually useful for plain numeric literals needs an untyped or broadly-typed second
# argument, which means claiming argument-type combinations Base currently leaves undefined (e.g.
# `log(1, 2)` on two bare `Int`s is a `MethodError` today). That silently changes global Base
# behavior for types this package doesn't own -- Aqua's piracy check flags it, and it's fragile
# against future Base/other-package additions for the same combination.
#
# A curry typed narrowly to `Expr` would avoid the piracy, but would then only accept
# already-constructed `Expr`s, not bare literals -- defeating the ergonomic point of currying at
# all, so it isn't worth doing either.

"""
    fill_null(expr::Polars.Expr; strategy::Symbol, limit::Union{Nothing,Integer}=nothing)::Polars.Expr
    fill_null(; strategy::Symbol, limit::Union{Nothing,Integer}=nothing)

Replaces every `null` value in `expr` using a fill *strategy* instead of a fixed value (see the
2-arg `fill_null(expr, value)` above for that form).

`strategy` is one of:
- `:forward`/`:backward` -- propagate the nearest non-null value in that direction; `limit` caps
  how many consecutive nulls a single value may fill (`nothing` for unlimited)
- `:mean`/`:min`/`:max` -- the column's own aggregate
- `:zero`/`:one` -- a fixed numeric fill, dtype-appropriate

`limit` only applies to `:forward`/`:backward` and is ignored otherwise.

!!! note "Has a curried form"
    The keyword-only method above, for `|>` pipelines.
"""
function fill_null(expr::Expr; strategy::Symbol, limit::Union{Nothing, Integer} = nothing)
    strategy_enum = _enum_lookup(
        strategy, "fill_null strategy",
        :backward => API.PolarsFillNullStrategyBackward,
        :forward => API.PolarsFillNullStrategyForward,
        :mean => API.PolarsFillNullStrategyMean,
        :min => API.PolarsFillNullStrategyMin,
        :max => API.PolarsFillNullStrategyMax,
        :zero => API.PolarsFillNullStrategyZero,
        :one => API.PolarsFillNullStrategyOne,
    )
    limit_ref = limit === nothing ? Ptr{UInt32}(C_NULL) : Ref(UInt32(limit))
    out = GC.@preserve limit_ref API.polars_expr_fill_null_with_strategy(expr, strategy_enum, limit_ref)
    return Expr(out)
end
@curry fill_null(; strategy::Symbol, limit::Union{Nothing, Integer} = nothing)

"""
    forward_fill(expr::Polars.Expr; limit::Union{Nothing,Integer}=nothing)::Polars.Expr
    forward_fill(; limit::Union{Nothing,Integer}=nothing)

Fills every `null` value in `expr` with the last non-null value seen before it. `limit` caps
how many consecutive nulls a single value may fill (`nothing` for unlimited). Shorthand for
`fill_null(expr; strategy=:forward, limit)`.

!!! note "Has a curried form"
    The keyword-only method above, for `|>` pipelines.
"""
forward_fill(expr::Expr; limit::Union{Nothing, Integer} = nothing) = fill_null(expr; strategy = :forward, limit)
@curry forward_fill(; limit::Union{Nothing, Integer} = nothing)

"""
    backward_fill(expr::Polars.Expr; limit::Union{Nothing,Integer}=nothing)::Polars.Expr
    backward_fill(; limit::Union{Nothing,Integer}=nothing)

Fills every `null` value in `expr` with the next non-null value found after it. `limit` caps
how many consecutive nulls a single value may fill (`nothing` for unlimited). Shorthand for
`fill_null(expr; strategy=:backward, limit)`.

!!! note "Has a curried form"
    The keyword-only method above, for `|>` pipelines.
"""
backward_fill(expr::Expr; limit::Union{Nothing, Integer} = nothing) = fill_null(expr; strategy = :backward, limit)
@curry backward_fill(; limit::Union{Nothing, Integer} = nothing)

export forward_fill, backward_fill

@wrap_expr_method shift_and_fill(expr::Expr, n::Expr, fill_value::Expr) polars_expr_shift_and_fill "Like [`shift`](@ref), but the positions vacated by the shift are filled with `fill_value` instead of `missing`."
export shift_and_fill

"""
    round(expr::Polars.Expr, decimals::Integer=0; mode::Symbol=:half_to_even)::Polars.Expr

Rounds to `decimals` decimal places, breaking ties according to `mode`: one of
`:half_to_even` (default, banker's rounding), `:half_away_from_zero`, `:to_zero`.
"""
function Base.round(expr::Expr, decimals::Integer = 0; mode::Symbol = :half_to_even)
    mode_enum = _enum_lookup(
        mode, "round mode",
        :half_to_even => API.PolarsRoundModeHalfToEven,
        :half_away_from_zero => API.PolarsRoundModeHalfAwayFromZero,
        :to_zero => API.PolarsRoundModeToZero,
    )
    out = API.polars_expr_round(expr, UInt32(decimals), mode_enum)
    return Expr(out)
end

@wrap_expr_method clip(expr::Expr, min::Expr, max::Expr) polars_expr_clip "Clips the values to the `[min, max]` range (values outside are set to the nearest bound)."
@curry clip(min, max)
export clip

@wrap_expr_method clip_min(expr::Expr, min::Expr) polars_expr_clip_min "Clips values below `min` up to `min` (values `>= min`, and any `missing`, pass through unchanged). The single-sided counterpart to [`clip`](@ref); see [`clip_max`](@ref) for the upper-bound-only form."
@curry clip_min(min)

@wrap_expr_method clip_max(expr::Expr, max::Expr) polars_expr_clip_max "Clips values above `max` down to `max` (values `<= max`, and any `missing`, pass through unchanged). The single-sided counterpart to [`clip`](@ref); see [`clip_min`](@ref) for the lower-bound-only form."
@curry clip_max(max)

export clip_min, clip_max

"""
    is_between(expr::Polars.Expr, lower_bound, upper_bound; closed::Symbol=:both)::Polars.Expr

Check if the values are between `lower_bound` and `upper_bound` (accepted as expressions or
literals). Returns a `Boolean` expression.

`closed` controls which sides of the interval are inclusive: `:both` (default), `:left`, `:right`,
or `:none`.

If `lower_bound` is greater than `upper_bound`, the result is `false` everywhere, since no value
can satisfy the condition.
"""
function is_between(expr::Expr, lower_bound, upper_bound; closed::Symbol = :both)
    lower_bound = convert(Expr, lower_bound)
    upper_bound = convert(Expr, upper_bound)
    closed_enum = _enum_lookup(
        closed, "closed",
        :both => API.PolarsClosedIntervalBoth,
        :left => API.PolarsClosedIntervalLeft,
        :right => API.PolarsClosedIntervalRight,
        :none => API.PolarsClosedIntervalNone,
    )
    out = API.polars_expr_is_between(expr, lower_bound, upper_bound, closed_enum)
    return Expr(out)
end

@curry is_between(lower_bound, upper_bound; closed::Symbol = :both)

export is_between

"""
    replace(expr::Polars.Expr, old, new)::Polars.Expr

Replaces values equal to `old` with the corresponding `new` value (`old`/`new` are typically
list-typed expressions built via [`implode`](@ref) for multi-value mappings). Values not found in
`old` are left unchanged.

"""
function Base.replace(expr::Expr, old, new)
    old = convert(Expr, old)
    new = convert(Expr, new)
    out = API.polars_expr_replace(expr, old, new)
    return Expr(out)
end

"""
    replace_strict(expr::Polars.Expr, old, new; default=nothing)::Polars.Expr

Like [`replace`](@ref), but values not found in `old` become `null` unless `default` is given,
in which case they take that value instead.
"""
function replace_strict(expr::Expr, old, new; default = nothing)
    old = convert(Expr, old)
    new = convert(Expr, new)
    default_expr = default === nothing ? nothing : convert(Expr, default)
    default_ptr = default_expr === nothing ? C_NULL : default_expr.ptr
    out = GC.@preserve default_expr API.polars_expr_replace_strict(expr, old, new, default_ptr)
    return Expr(out)
end

@curry replace_strict(old, new; default = nothing)

export replace_strict

"""
    prod(expr::Polars.Expr)::Polars.Expr

Product of the values.

"""
Base.prod(expr::Expr) = Expr(API.polars_expr_product(expr))


"""
    over(expr::Polars.Expr, partition_by...; mapping_strategy::Symbol=:group_to_rows,
         order_by=nothing, descending::Bool=false, nulls_last::Bool=false)::Polars.Expr

Applies `expr` within groups defined by `partition_by` (columns or expressions), broadcasting
the per-group result back over every row of that group — e.g. `sum(col("x")) |> over("g")`
returns, per row, the sum of `x` within that row's `g` group.

- `mapping_strategy`: how the per-group result maps back onto rows -- `:group_to_rows` (default,
  one output value per input row, in the original row order), `:explode` (concatenate each
  group's result in group order -- only sensible when the frame is already sorted by
  `partition_by`), or `:join` (collect each group's result into a list, joined back onto every
  row of that group).
- `order_by`: an optional column/expression (string/symbol/`Expr`) to sort by *within* each
  group before evaluating `expr`, without affecting the frame's own row order. At least one of
  `partition_by`/`order_by` must be given. `descending`/`nulls_last` control that ordering.
"""
function over(
        expr::Expr, partition_by...;
        mapping_strategy::Symbol = :group_to_rows,
        order_by = nothing,
        descending::Bool = false,
        nulls_last::Bool = false
    )
    partition_by = _expr_vector(partition_by)
    mapping_enum = _enum_lookup(
        mapping_strategy, "over mapping_strategy",
        :group_to_rows => API.PolarsWindowMappingGroupsToRows,
        :explode => API.PolarsWindowMappingExplode,
        :join => API.PolarsWindowMappingJoin,
    )
    order_by_expr = order_by === nothing ? nothing : _as_expr(order_by)
    GC.@preserve partition_by order_by_expr begin
        partition_ptrs = Ptr{polars_expr_t}[p.ptr for p in partition_by]
        order_by_ptr = order_by_expr === nothing ? Ptr{polars_expr_t}(C_NULL) : order_by_expr.ptr
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_over(
            expr, partition_ptrs, length(partition_ptrs), order_by_ptr,
            descending, nulls_last, mapping_enum, out
        )
        polars_error(err)
    end
    return Expr(out[])
end

"""
    over(partition_by::Union{String,Symbol}...; kwargs...)::Base.Callable

Curried form of [`over`](@ref) for use with `|>`, mirroring Python polars' `.over("g")` — e.g.
`sum(col("x")) |> over("g")`. Only accepts column-name strings/symbols, not `Expr` partition keys
(an `Expr` argument is ambiguous with `over`'s own `expr` argument and always resolves to that
instead); for expression-valued partition keys, call `over(expr, partition_by...)` directly.
`kwargs` (`mapping_strategy`/`order_by`/`descending`/`nulls_last`) forward to `over` unchanged.
"""
over(partition_by::Vararg{ColId}; kwargs...) =
    expr -> over(expr, partition_by...; kwargs...)

export over

"""
    sort_by(expr::Polars.Expr, by...; rev=false, nulls_last::Bool=false, maintain_order::Bool=false)::Polars.Expr

Sorts the values of `expr` according to `by` (columns or expressions), rather than by `expr`'s
own values -- typically used inside [`over`](@ref)/[`agg`](@ref) for "most recent row per group",
"top N per group", etc. `rev` is either a single `Bool` (applied to every `by` expression) or a
`Vector{Bool}` the same length as `by`.
"""
function sort_by(expr::Expr, by...; rev = false, nulls_last::Bool = false, maintain_order::Bool = false)
    by = _expr_vector(by)
    n_by = length(by)
    descending = rev isa Bool ? fill(rev, n_by) : rev
    # See `_sort!` in sort.jl: user-argument validation gets a real exception, not an `@assert`.
    length(descending) == n_by || throw(
        ArgumentError(
            "rev must have one entry per by expression (got $n_by by expressions and " *
                "$(length(descending)) rev)"
        )
    )
    GC.@preserve by begin
        by_ptrs = Ptr{polars_expr_t}[e.ptr for e in by]
        out = API.polars_expr_sort_by(expr, by_ptrs, n_by, descending, nulls_last, maintain_order)
    end
    return Expr(out)
end

"""
    sort_by(by::Union{String,Symbol}...; rev=false, nulls_last::Bool=false, maintain_order::Bool=false)::Base.Callable

Curried form of [`sort_by`](@ref) for use with `|>` — e.g. `col("x") |> sort_by("y"; rev=true)`.
Only accepts column-name strings/symbols, not `Expr` by-keys (an `Expr` argument is ambiguous
with `sort_by`'s own `expr` argument and always resolves to that instead); for expression-valued
by-keys, call `sort_by(expr, by...; kwargs...)` directly.
"""
function sort_by(by::Vararg{ColId}; rev = false, nulls_last::Bool = false, maintain_order::Bool = false)
    return expr -> sort_by(expr, by...; rev, nulls_last, maintain_order)
end

export sort_by

"""
    arg_sort(expr::Polars.Expr; descending::Bool=false, nulls_last::Bool=false)::Polars.Expr

Returns the index values that would sort `expr`.
"""
function arg_sort(expr::Expr; descending::Bool = false, nulls_last::Bool = false)
    out = API.polars_expr_arg_sort(expr, descending, nulls_last)
    return Expr(out)
end

@curry arg_sort(; descending::Bool = false, nulls_last::Bool = false)

export arg_sort

@wrap_expr_method gather(expr::Expr, idx::Expr; null_on_oob::Bool = false) polars_expr_gather "Take values by index. `idx` is an expression, or an integer vector promoted via [`lit`](@ref).\n\n`null_on_oob` sets the behaviour when an index is out of bounds: `true` gives `missing`, `false` (the default) raises a [`PolarsError`](@ref) when the result is collected.\n\n!!! note \"Indices are 0-based\"\n    `idx` is 0-based, and negative indices count from the end. This differs from [`Polars.nth`](@ref) and `Selectors.by_index`, which are 1-based: those select a column from a position the caller writes literally, whereas `idx` here is data, and usually comes from [`arg_sort`](@ref), `arg_min` or `arg_max`, which return 0-based positions. Sharing one convention lets `gather(x, arg_sort(y))` compose without an offset."

export gather

@wrap_expr_method gather_every(expr::Expr, n::Integer; offset::Integer = 0) polars_expr_gather_every "Take every `n`th value. `offset` is the starting index, 0-based."

export gather_every

"""
    filter(expr::Polars.Expr, predicate)::Polars.Expr

Filters `expr`'s own values by `predicate`, both evaluated in the same context -- typically inside
[`agg`](@ref)/[`over`](@ref), e.g. `Polars.sum(filter(col("x"), col("x") .> 0))`. `predicate`
accepts anything `_as_expr` does (an `Expr`, a [`Selector`](@ref), or a column-name
`String`/`Symbol`).

Distinct from `filter` on a `LazyFrame`/`DataFrame`, which filters a whole frame's rows -- this
filters one expression's values without touching the rest of the row.
"""
function Base.filter(expr::Expr, predicate)
    predicate = _as_expr(predicate)
    return Expr(API.polars_expr_filter(expr, predicate))
end
# A separate, more specific method for `String`/`SubString{String}` predicates: without it,
# `filter(expr::Expr, ::String)` is ambiguous with `Base.filter(f, s::Union{SubString{String},
# String})` (character-filtering a string) -- both match equally well, since the generic method
# above accepts `predicate::Any`. Mirrors `Base.filter(df::LazyFrame,
# ::Union{SubString{String},String})` in src/select.jl, same reasoning.
Base.filter(expr::Expr, predicate::Union{SubString{String}, String}) =
    Expr(API.polars_expr_filter(expr, _as_expr(predicate)))

"""
    sort(expr::Polars.Expr; rev::Bool=false, nulls_last::Bool=false, multithreaded::Bool=true, maintain_order::Bool=false)::Polars.Expr

Sorts `expr`'s own values, as opposed to [`sort_by`](@ref) (sorts by a different key) or `sort` on
a `LazyFrame`/`DataFrame` (sorts whole rows).
"""
function Base.sort(
        expr::Expr;
        rev::Bool = false, nulls_last::Bool = false, multithreaded::Bool = true,
        maintain_order::Bool = false
    )
    out = API.polars_expr_sort(expr, rev, nulls_last, multithreaded, maintain_order)
    return Expr(out)
end

"""
    head(expr::Polars.Expr, n::Union{Nothing,Integer}=nothing)::Polars.Expr

Returns the first `n` values of `expr`'s result (default: polars' own default of 10). Distinct
from `head` on a `LazyFrame`/`DataFrame`, which takes the first `n` whole rows.
"""
function head(expr::Expr, n::Union{Nothing, Integer} = nothing)
    n_ref = n === nothing ? Ptr{Csize_t}(C_NULL) : Ref(Csize_t(n))
    out = GC.@preserve n_ref API.polars_expr_head(expr, n_ref)
    return Expr(out)
end

"""
    tail(expr::Polars.Expr, n::Union{Nothing,Integer}=nothing)::Polars.Expr

Returns the last `n` values of `expr`'s result (default: polars' own default of 10). Distinct from
`tail` on a `LazyFrame`/`DataFrame`, which takes the last `n` whole rows.

!!! note
    Extends `Base.tail` (which otherwise operates on `Tuple`/`NamedTuple`), matching the
    `LazyFrame`/`DataFrame` method in `src/select.jl` -- a plain (non-`Base.`-qualified)
    `function tail(...)` here would instead create a *new*, separate binding that shadows
    `Base.tail` for the rest of the module, breaking `import Base: tail` wherever it runs next.
"""
function Base.tail(expr::Expr, n::Union{Nothing, Integer} = nothing)
    n_ref = n === nothing ? Ptr{Csize_t}(C_NULL) : Ref(Csize_t(n))
    out = GC.@preserve n_ref API.polars_expr_tail(expr, n_ref)
    return Expr(out)
end

"""
    limit(expr::Polars.Expr, n::Union{Nothing,Integer}=nothing)::Polars.Expr

Alias for [`head`](@ref) (matching upstream, where `Expr.limit` is itself just an alias for
`Expr.head`).
"""
limit(expr::Expr, n::Union{Nothing, Integer} = nothing) = head(expr, n)

export limit
# `head`/`tail` are already exported centrally in src/Polars.jl (shared with the
# LazyFrame/DataFrame methods in src/select.jl) -- no separate export needed here.

"""
    slice(expr::Polars.Expr, offset, length)::Polars.Expr

Slices `expr`'s own result: `length` values starting at `offset` (0-based; `offset` may be
negative, counting from the end). `offset`/`length` accept anything `lit` does (an `Expr`, or a
literal value promoted via `convert(Expr, ...)`).
"""
function slice(expr::Expr, offset, length)
    offset = convert(Expr, offset)
    length = convert(Expr, length)
    out = API.polars_expr_slice(expr, offset, length)
    return Expr(out)
end

export slice

"""
    get(expr::Polars.Expr, index; null_on_oob::Bool=false)::Polars.Expr

The scalar counterpart to [`gather`](@ref) (which takes a vector of indices): returns the single
value of `expr` at `index` (0-based; negative counts from the end). `null_on_oob` sets the
behaviour when `index` is out of bounds: `true` gives `missing`, `false` (the default) raises a
[`PolarsError`](@ref) when the result is collected.

!!! note
    Extends `Base.get` -- already exported by `Base` itself, so no separate `export` is needed
    (or possible) here; see the matching note on [`tail`](@ref) above for why this must be
    `Base.get(...)`, not a plain `function get(...)`.
"""
function Base.get(expr::Expr, index; null_on_oob::Bool = false)
    index = convert(Expr, index)
    out = API.polars_expr_get(expr, index, null_on_oob)
    return Expr(out)
end

"""
    top_k_by(expr::Polars.Expr, k, by...; rev=false)::Polars.Expr

Returns the `k` rows of `expr` with the largest values of `by` (columns or expressions) -- the
`by`-key counterpart to [`top_k`](@ref), analogous to how [`sort_by`](@ref) relates to `sort`.
`rev` is either a single `Bool` (applied to every `by` expression) or a `Vector{Bool}` the same
length as `by`.
"""
function top_k_by(expr::Expr, k, by...; rev = false)
    k = convert(Expr, k)
    by = _expr_vector(by)
    n_by = length(by)
    descending = rev isa Bool ? fill(rev, n_by) : rev
    length(descending) == n_by || throw(
        ArgumentError(
            "rev must have one entry per by expression (got $n_by by expressions and " *
                "$(length(descending)) rev)"
        )
    )
    owned, by_ptrs = _handle_ptrs(by, Ptr{polars_expr_t})
    GC.@preserve owned begin
        out = API.polars_expr_top_k_by(expr, k, by_ptrs, n_by, descending)
    end
    return Expr(out)
end

export top_k_by

"""
    bottom_k_by(expr::Polars.Expr, k, by...; rev=false)::Polars.Expr

Returns the `k` rows of `expr` with the smallest values of `by` (columns or expressions) -- the
complement of [`top_k_by`](@ref).
"""
function bottom_k_by(expr::Expr, k, by...; rev = false)
    k = convert(Expr, k)
    by = _expr_vector(by)
    n_by = length(by)
    descending = rev isa Bool ? fill(rev, n_by) : rev
    length(descending) == n_by || throw(
        ArgumentError(
            "rev must have one entry per by expression (got $n_by by expressions and " *
                "$(length(descending)) rev)"
        )
    )
    owned, by_ptrs = _handle_ptrs(by, Ptr{polars_expr_t})
    GC.@preserve owned begin
        out = API.polars_expr_bottom_k_by(expr, k, by_ptrs, n_by, descending)
    end
    return Expr(out)
end

export bottom_k_by

@wrap_expr_method item(expr::Expr; allow_empty::Bool = false) polars_expr_item "The aggregation form of `item`: raises unless `expr` evaluates to exactly one value (per group, or overall). If `allow_empty` is `true`, zero values is also accepted and produces `missing` instead of raising -- more than one value always raises regardless. Distinct from `Polars.item` on a `DataFrame`/`Series` (a `(1,1)`-shape accessor, not an aggregation)."


"""Coerces an iterable of column references (names, `Expr`s, `Selector`s) into a `Vector{Expr}`
ready to have its pointers marshalled. A typed comprehension rather than
`convert(Vector{Expr}, collect(map(_as_expr, args)))`: same result, one allocation instead of
three, and it lands on `Vector{Expr}` directly even when `args` is empty (where `collect` would
otherwise produce a `Vector{Union{}}`)."""
_expr_vector(args) = Expr[_as_expr(arg) for arg in args]

"""
    coalesce(exprs::Expr...)::Polars.Expr

Returns the first non-null value among `exprs`, evaluated left to right.
"""
function Base.coalesce(first::Expr, rest::Expr...)
    owned, ptrs = _handle_ptrs(_expr_vector((first, rest...)), Ptr{polars_expr_t})
    GC.@preserve owned begin
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_coalesce(ptrs, length(ptrs), out)
        polars_error(err)
    end
    return Expr(out[])
end

@wrap_multi_expr_function as_struct polars_expr_as_struct false "Collects `exprs` (columns or expressions) into a single `Struct`-typed expression, one field per input (named after each input's own output name). The write-side counterpart to [`Structs.field_by_name`](@ref)/[`Structs.field_by_index`](@ref)."

export as_struct

@wrap_multi_expr_function concat_list polars_expr_concat_list false "Horizontally concatenates the `List`-typed `exprs` into a single `List` per row (row `i`'s output is every input's row-`i` list, in order, flattened one level). Distinct from [`Lists.join`](@ref Polars.Lists.join) (string-joins one row's own list into a scalar) and [`concat`](@ref) (stacks whole frames, not per-row lists). Errors if `exprs` is empty."

export concat_list

"""
    concat_str(exprs...; separator::AbstractString="", ignore_nulls::Bool=false)::Polars.Expr

Row-wise (horizontal) string concatenation across `exprs` (columns or expressions -- non-string
dtypes are cast to string first), joined by `separator`. If `ignore_nulls` is `false` (default),
any `null` in a row makes that row's whole result `null`; if `true`, `null`s are skipped (treated
as empty) instead. Distinct from [`Strings.join`](@ref Polars.Strings.join) (an aggregation across *all* rows into one
value) and [`Lists.join`](@ref Polars.Lists.join) (joins each row's own list independently) -- this concatenates
sibling columns within each row.
"""
function concat_str(exprs...; separator::AbstractString = "", ignore_nulls::Bool = false)
    owned, ptrs = _handle_ptrs(_expr_vector(exprs), Ptr{polars_expr_t})
    separator = String(separator)
    GC.@preserve owned begin
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_concat_str(
            ptrs, length(ptrs), separator, ncodeunits(separator), ignore_nulls, out
        )
        polars_error(err)
    end
    return Expr(out[])
end

export concat_str

"""
    format(fmt::AbstractString, args...)::Polars.Expr

Formats `args` into `fmt`, where each `{}` placeholder consumes one argument in order. Each
argument is an `Expr`, or a `String`/`Symbol` naming a column (as in [`col`](@ref)) -- a bare
numeric literal is **not** accepted here, unlike some other functions in this package; wrap it in
[`lit`](@ref) first. The number of `{}` placeholders must equal the number of `args`, or a
`PolarsError` is raised. `fmt` also accepts upstream's `{0}`/`{name}` forms (positional/named
placeholders, matching `args` by index or resolving `name` directly as a column reference) --
but not mixed with bare `{}` in the same call. The row-wise counterpart of `Base.string` over
several columns; see also [`concat_str`](@ref), which joins with a fixed separator instead of a
template.
"""
function format(fmt::AbstractString, args...)
    owned, ptrs = _handle_ptrs(_expr_vector(args), Ptr{polars_expr_t})
    fmt = String(fmt)
    GC.@preserve owned begin
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_format(fmt, ncodeunits(fmt), ptrs, length(ptrs), out)
        polars_error(err)
    end
    return Expr(out[])
end

export format

@wrap_multi_expr_function concat_arr polars_expr_concat_arr false "Horizontally concatenates `exprs` into a single fixed-size `Array` column, one element per input expression -- the `Array`-dtype counterpart of [`concat_list`](@ref). All inputs must share a dtype. **Building the plan and `collect`ing it both succeed, but nothing that needs to resolve the `Array` dtype does**: `collect_schema`, `schema`, and indexing into a collected `DataFrame`'s `Array` column all raise an `ErrorException` from the Arrow schema parser, which does not yet recognize the fixed-size-list format -- this is a package limitation, not a query error. Use [`explain`](@ref) to confirm the plan was built, or cast the result away from `Array` before inspecting it."

export concat_arr

@wrap_multi_expr_function all_horizontal polars_expr_all_horizontal false "Row-wise (horizontal) boolean AND across `exprs`. The output column is named `\"all\"` unless [`alias`](@ref)ed."
@wrap_multi_expr_function any_horizontal polars_expr_any_horizontal false "Row-wise (horizontal) boolean OR across `exprs`. The output column is named `\"any\"` unless [`alias`](@ref)ed."
@wrap_multi_expr_function min_horizontal polars_expr_min_horizontal false "Row-wise (horizontal) minimum across `exprs`. The output column is named `\"min\"` unless [`alias`](@ref)ed."
@wrap_multi_expr_function max_horizontal polars_expr_max_horizontal false "Row-wise (horizontal) maximum across `exprs`. The output column is named `\"max\"` unless [`alias`](@ref)ed."
@wrap_multi_expr_function sum_horizontal polars_expr_sum_horizontal true "Row-wise (horizontal) sum across `exprs`. If `ignore_nulls` is `true` (default), nulls are treated as `0`; if `false`, any null in a row makes that row's sum `null`."
@wrap_multi_expr_function mean_horizontal polars_expr_mean_horizontal true "Row-wise (horizontal) mean across `exprs`. If `ignore_nulls` is `true` (default), nulls are excluded from the average; if `false`, any null in a row makes that row's mean `null`."

export all_horizontal, any_horizontal, min_horizontal, max_horizontal, sum_horizontal, mean_horizontal

"""
    interpolate(expr::Polars.Expr; method::Symbol=:linear)::Polars.Expr

Fills `null`s by interpolating between the surrounding non-null values, using `method`: `:linear`
(default) or `:nearest`. Leading/trailing `null`s (with no non-null value on one side) remain
`null`.
"""
function interpolate(expr::Expr; method::Symbol = :linear)
    method_enum = _enum_lookup(
        method, "interpolation method",
        :linear => API.PolarsInterpolationMethodLinear,
        :nearest => API.PolarsInterpolationMethodNearest,
    )
    out = API.polars_expr_interpolate(expr, method_enum)
    return Expr(out)
end

@curry interpolate(; method::Symbol = :linear)

export interpolate

"""
    diff(expr::Polars.Expr, n=1; null_behavior::Symbol=:ignore)::Polars.Expr

Computes the first discrete difference between shifted items (`expr[i] - expr[i - n]`).
`null_behavior` is one of `:ignore` (default, pads the first `n` values with `null`) or `:drop`
(drops the first `n` values instead).
"""
function Base.diff(expr::Expr, n = 1; null_behavior::Symbol = :ignore)
    n = convert(Expr, n)
    behavior = _null_behavior_enum(null_behavior)
    out = API.polars_expr_diff(expr, n, behavior)
    return Expr(out)
end

# `to_lowercase`/`to_uppercase` are exported by `@wrap_simple_ops` itself (they're generated in
# this file's block alongside `keep_name`), so they are deliberately absent here.
export col, alias, prefix, suffix, prefix_fields, suffix_fields, lit, cast, when, element, len,
    cast_datetime, cast_duration, cast_decimal, cast_categorical
