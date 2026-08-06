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
# `@generate_expr_fns` below); `<=`/`>=`/`!=` compose them with `not`, which preserves polars' null
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

"""
    _enum_lookup(sym::Symbol, label::AbstractString, mapping::Pair{Symbol}...)

Resolves `sym` against `mapping` (each entry `:key => value`), returning the matched `value`.
Raises a plain `ErrorException` naming `label` and listing the valid keys if `sym` matches none
of them. Every `Symbol`-keyword-to-C-enum conversion in this module (`time_unit`, quantile
`method`, `strategy`, ...) goes through this instead of restating its own `if/elseif/error`
chain.
"""
function _enum_lookup(sym::Symbol, label::AbstractString, mapping::Pair{Symbol}...)
    for (key, value) in mapping
        sym === key && return value
    end
    valid = join((string(':', key) for (key, _) in mapping), ", ")
    error("unknown $label $sym, expected one of ($valid)")
end

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

"""Processes one argument node from a `@curry` target signature, returning
`(decl_node, name, forward_expr)`:
- `decl_node` is what goes in the *curry's own* signature (same node, except an `::Expr`
  annotation is stripped -- the curry accepts a bare literal there, not just an `Expr`).
- `name` is the bare argument `Symbol`, for building the curry's own signature/forwarding call.
- `forward_expr` is what gets passed to the primal at that position: the bare `name` normally, or
  `convert(Expr, name)` when the original annotation was `::Expr` (mirroring what the primal
  itself requires, since it performs no such conversion internally when it declares the arg
  `::Expr`).
Recurses through `x=default`/`x::T=default` (a `:kw` node) to reach the underlying `x`/`x::T`,
preserving the default in `decl_node`."""
function _curry_arg(node::Symbol)
    return node, node, node
end
function _curry_arg(node::Base.Expr)
    if node.head === :(::)
        name, T = node.args[1], node.args[2]
        return T === :Expr ? (name, name, Base.Expr(:call, :convert, :Expr, name)) : (node, name, name)
    elseif node.head === :kw
        inner_decl, name, forward = _curry_arg(node.args[1])
        return Base.Expr(:kw, inner_decl, node.args[2]), name, forward
    else
        error("@curry: can't process argument node $node")
    end
end

"""
    @curry f(args...; kwargs...)

Generates the curried (pipe-with-`|>`) sibling of `f`, whose primary method takes the piped
`Polars.Expr` as its first (unnamed here) argument -- i.e. expands to

    f(args...; kwargs...) = expr -> f(expr, args...; kwargs...)

plus a `"Curried form of [`f`](@ref) for use with `\\|>`."` docstring, the exact convention every
hand-written curry in this module already follows. Write the *same* argument list `f`'s own
primary method declares from its second argument onward -- including any `::Expr` annotation --
except with the leading `expr::Expr` dropped: any argument written `::Expr` here is wrapped in
`convert(Expr, ·)` before being forwarded (since the primary method requires an actual `Expr` at
that position and performs no conversion of its own), and the annotation itself is dropped from
the curry's own signature so it keeps accepting bare literals, not just `Expr`s. An argument with
any other type (or none) is forwarded as-is, on the assumption the primary method converts it
itself. For example, `contains(expr::Expr, pat::Expr; strict::Bool=true)` pairs with
`@curry contains(pat::Expr; strict::Bool=true)`, generating
`contains(pat; strict=true) = expr -> contains(expr, convert(Expr, pat); strict)`.

Not a fit for a curry whose accepted argument types are deliberately *narrower* than the primary
method's own (`sort_by`/`over` restrict their curried `by`/`partition_by` to column names, not
arbitrary `Expr`s, since an `Expr` there would be ambiguous with the piped `expr` itself) or that
splats a variable number of arguments -- both stay hand-written.
"""
macro curry(sig)
    @assert sig isa Base.Expr && sig.head === :call "@curry expects a call signature, e.g. `@curry f(x; y=1)`"
    fname = sig.args[1]
    posarg_decls, posarg_forwards = Any[], Any[]
    kwarg_decls, kwarg_forwards = Any[], Any[]
    for a in sig.args[2:end]
        if a isa Base.Expr && a.head === :parameters
            for kw in a.args
                decl, name, forward = _curry_arg(kw)
                push!(kwarg_decls, decl)
                push!(kwarg_forwards, forward === name ? name : Base.Expr(:kw, name, forward))
            end
        else
            decl, _, forward = _curry_arg(a)
            push!(posarg_decls, decl)
            push!(posarg_forwards, forward)
        end
    end

    curry_sig_args = Any[fname]
    isempty(kwarg_decls) || push!(curry_sig_args, Base.Expr(:parameters, kwarg_decls...))
    append!(curry_sig_args, posarg_decls)
    curry_sig = Base.Expr(:call, curry_sig_args...)

    call_args = Any[fname, :expr]
    append!(call_args, posarg_forwards)
    call_expr = Base.Expr(:call, call_args...)
    isempty(kwarg_forwards) || insert!(call_expr.args, 2, Base.Expr(:parameters, kwarg_forwards...))
    curry_def = Base.Expr(:(=), curry_sig, Base.Expr(:->, :expr, Base.Expr(:block, call_expr)))

    docstring = """
        $(curry_sig)::Base.Callable

    Curried form of [`$fname`](@ref) for use with `|>`.
    """
    return esc(
        quote
            Docs.@doc $docstring $curry_sig
            $curry_def
        end
    )
end

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
    alias(expr::Polars.Expr, alias::String)::Polars.Expr
    alias(alias::String)::Base.Fix2{typeof(alias), String}

Renames the result of this expression to a new name.
"""
function alias(expr, alias)
    out = Ref{Ptr{polars_expr_t}}()
    err = polars_expr_alias(expr, alias, ncodeunits(alias), out)
    polars_error(err)
    return Expr(out[])
end
alias(new_name) = Base.Fix2(alias, new_name)

"""
    prefix(expr::Polars.Expr, pref::String)::Polars.Expr
    prefix(pref::String)::Base.Fix2{typeof(prefix), String}

Adds a prefix to the name of the resulting expression.
"""
function prefix(expr, pref)
    out = Ref{Ptr{polars_expr_t}}()
    err = polars_expr_prefix(expr, pref, ncodeunits(pref), out)
    polars_error(err)
    return Expr(out[])
end
prefix(pref) = Base.Fix2(prefix, pref)

"""
    suffix(expr::Polars.Expr, suf::String)::Polars.Expr
    suffix(suf::String)::Base.Fix2{typeof(suffix), String}

Adds a suffix to the name of the resulting expression.
"""
function suffix(expr, suf)
    out = Ref{Ptr{polars_expr_t}}()
    err = polars_expr_suffix(expr, suf, ncodeunits(suf), out)
    polars_error(err)
    return Expr(out[])
end
suffix(suf) = Base.Fix2(suffix, suf)

"""
    to_lowercase(expr::Polars.Expr)::Polars.Expr

Lowercases the name of the resulting expression.
"""
function to_lowercase(expr)
    return Expr(polars_expr_to_lowercase(expr))
end

"""
    to_uppercase(expr::Polars.Expr)::Polars.Expr

Uppercases the name of the resulting expression.
"""
function to_uppercase(expr)
    return Expr(polars_expr_to_uppercase(expr))
end

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

macro generate_expr_fns(ex)
    @assert ex.head === :block
    out = Base.Expr(:block)
    for call in ex.args
        call isa Base.Expr || continue
        cname = call.args[2]
        # Fixed position, not `last(call.args)`: an optional 4th arg (the description below)
        # would otherwise become `last(call.args)` itself once present, silently corrupting
        # `orig_fname`/`namespace` extraction below (this broke once already -- see
        # plans/docstring_and_examples_coverage.md's "Rebaseline" section).
        ns_fname_node = call.args[3]
        orig_fname = last(ns_fname_node.args)
        # Optional 4th call arg: a hand-written description, e.g.
        # `gen_impl_expr!(polars_expr_sum, Expr::sum, "Sums the non-null values...")`, threaded
        # into the docstring below instead of the bare Rust-doc-link fallback.
        desc = length(call.args) >= 4 ? call.args[4] : nothing
        # A name colliding with an existing Base binding is never exported here -- for the
        # top-level `Polars` module that's because the function below is instead defined as a new
        # `Base.fname` method (which already works unqualified via Base's own export, see
        # CLAUDE.md's sharp-edges note); for a namespace submodule (`Lists`/`Strings`/`Dt`), the
        # function stays a wholly unrelated local binding (never Base-qualified -- extending e.g.
        # `Base.get`/`Base.max` with unrelated list/string semantics would be actively wrong), just
        # not exported, since it's designed for qualified use (`Lists.get`) and `using
        # Polars.Lists` would otherwise clash with Base's own same-named export.
        base_collision = isdefined(Base, orig_fname)
        base_qualified = __module__ == Polars && base_collision
        fname = base_qualified ? Base.Expr(:(.), :Base, QuoteNode(orig_fname)) : orig_fname
        sig = Base.Expr(:call, fname)
        gen_name = string(first(call.args))
        @assert occursin("gen", gen_name)
        # "curried" is opt-in on top of "binary" (e.g. `gen_impl_expr_binary_curried!`): besides
        # the plain `(a::Expr, b::Expr)` method, also emits `orig_fname(b) = Base.Fix2(orig_fname,
        # convert(Expr, b))` -- the `Base.Fix2`-style curry every binary op with a natural
        # "value to curry in" needs for `|>` pipelines (`col("x") |> is_in([1, 2])`), previously
        # hand-written next to each macro-generated primal. Guarded against `base_qualified`, not
        # the weaker `base_collision`: a namespace submodule (`split` in `Strings`, `round` in
        # `Dt`) can collide with a Base name and still curry unqualified fine, since its primal
        # is already its own wholly local binding there (see the base-collision note above) that
        # the unqualified `orig_fname` in the curry correctly picks up; only the top-level
        # `Polars`-module + collision case (`base_qualified`) would need `Base.orig_fname`
        # qualification this curry doesn't attempt, so it's excluded instead.
        curried = occursin("curried", gen_name)
        if curried
            @assert occursin("binary", gen_name) "the curried variant is only defined for binary generators"
            @assert !base_qualified "curried Fix2 form not supported for a Base-qualified name ($orig_fname); write it by hand"
        end
        if occursin("binary", gen_name)
            push!(sig.args, Base.Expr(:(::), :a, :Expr), Base.Expr(:(::), :b, :Expr))
            body = quote
                out = API.$(cname)(a, b)
                Expr(out)
            end
        else
            push!(sig.args, Base.Expr(:(::), :expr, :Expr))
            body = quote
                out = API.$(cname)(expr)
                Expr(out)
            end
        end
        push!(out.args, Base.Expr(:function, sig, body))
        # Attach a docstring regardless of Base collision -- documented under the plain,
        # unqualified name (`orig_fname`), not `Base.fname`: that's how `fname` resolves inside
        # this module anyway (every module sees Base unqualified), and it's what `?fname` in the
        # REPL expects.
        namespace = string(first(ns_fname_node.args))
        namespace_type = namespace == "Expr" ? "enum" : "struct"
        rust_doc_url = "https://docs.rs/polars/latest/polars/prelude/$(namespace_type).$(namespace).html#method.$orig_fname"
        string_sig = replace(string(sig), "Expr" => "Polars.Expr")
        docstring = if desc === nothing
            """
                $(string_sig)::Polars.Expr

            Refer to [the polars documentation]($rust_doc_url).
            """
        else
            """
                $(string_sig)::Polars.Expr

            $desc

            See also [the polars documentation]($rust_doc_url).
            """
        end
        push!(
            out.args, quote
                Docs.@doc $docstring $sig
            end
        )
        base_collision || push!(out.args, :(export $orig_fname))
        if curried
            curry_sig = Base.Expr(:call, orig_fname, :b)
            curry_body = :(Base.Fix2($orig_fname, convert(Expr, b)))
            push!(out.args, Base.Expr(:(=), curry_sig, curry_body))
            curry_docstring = """
                $(orig_fname)(b)::Base.Callable

            Curried form of [`$orig_fname`](@ref) for use with `|>`.
            """
            push!(
                out.args, quote
                    Docs.@doc $curry_docstring $curry_sig
                end
            )
        end
    end
    return esc(out)
end

# We just copy the rust code here and generate functions on the fly.
@generate_expr_fns begin
    gen_impl_expr!(polars_expr_keep_name, Expr::keep_name, "Keeps `expr`'s original column name, overriding any rename that would otherwise result from the operation it's applied to (e.g. after an arithmetic operator or a namespaced function call).")

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
    gen_impl_expr!(polars_expr_degrees, Expr::degrees, "Converts each value of `expr` from radians to degrees.")
    gen_impl_expr!(polars_expr_radians, Expr::radians, "Converts each value of `expr` from degrees to radians.")

    gen_impl_expr!(polars_expr_sqrt, Expr::sqrt, "Square root of each value of `expr`.")
    gen_impl_expr!(polars_expr_sign, Expr::sign, "Sign of each value of `expr`: `-1`, `0`, or `1` (float dtypes only; `NaN` maps to `NaN`).")
    gen_impl_expr!(polars_expr_exp, Expr::exp, "`e` raised to each value of `expr`.")
    gen_impl_expr!(polars_expr_log1p, Expr::log1p, "Natural logarithm of `1 + expr`, elementwise -- more accurate than `log(lit(ℯ), expr + 1)` for values near zero.")

    gen_impl_expr!(polars_expr_rle, Expr::rle, "Run-length-encodes `expr`: collapses each run of consecutive identical values into one row, a `Struct{len, value}` (see [Struct](@ref expr-struct)) holding the run's length and the repeated value. Consecutive `null`s form a run like any other value.")
    gen_impl_expr!(polars_expr_rle_id, Expr::rle_id, "Maps each value of `expr` to a 0-indexed run ID: rows in the same run of consecutive identical values share an ID, which increments at each run boundary. Unlike [`rle`](@ref), the column keeps its length -- one output row per input row.")

    gen_impl_expr!(polars_expr_n_unique, Expr::n_unique, "Counts the number of distinct values in `expr` (`null` counts as one distinct value), one result per group (or a single overall count outside a `group_by`).")
    gen_impl_expr!(polars_expr_unique, Expr::unique, "Returns the distinct values of `expr` (order not guaranteed), shortening the column. Inside `agg`, per-group distinct values are automatically collected into a `List` (see [List](@ref expr-list)) so the aggregation still produces one row per group.")
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

    gen_impl_expr_binary_curried!(polars_expr_fill_null, Expr::fill_null, "Replaces every `null` value in `a` with the corresponding value of `b` (a literal via `lit`, or another expression).\n\n!!! note \"Has a curried form\"\n    `fill_null(value)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_curried!(polars_expr_fill_nan, Expr::fill_nan, "Replaces every `NaN` value in `a` with the corresponding value of `b`.\n\n!!! note \"Has a curried form\"\n    `fill_nan(value)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_curried!(polars_expr_is_in, Expr::is_in, "Row-wise boolean flag: `true` where the value of `a` appears in `b` (typically `implode(lit(values))`, or another column); see the `lit(::Vector)` section below for how to build `b`.\n\n!!! note \"Has a curried form\"\n    `is_in(values)` -- see [Curried forms for pipe-based composition](@ref).")

    gen_impl_expr_binary_curried!(polars_expr_shift, Expr::shift, "Shifts `a`'s values down by `b` rows (negative `b` shifts up), filling the vacated positions with `null`.\n\n!!! note \"Has a curried form\"\n    `shift(n)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_curried!(polars_expr_pct_change, Expr::pct_change, "Percent change between each value of `a` and the value `b` rows earlier: `(a[i] - a[i-b]) / a[i-b]`.\n\n!!! note \"Has a curried form\"\n    `pct_change(n)` -- see [Curried forms for pipe-based composition](@ref).")

    gen_impl_expr_binary!(polars_expr_rem, Expr::rem, "Remainder of `a / b` (elementwise), matching the sign of `a` -- the named-function form of `Base.rem` extended to `Expr` arguments.")
end

"""
    flatten(expr::Polars.Expr; empty_as_null::Bool=true, keep_nulls::Bool=true)::Polars.Expr

Explodes a `List`-typed `expr` back into one row per element -- the expression-level inverse of
[`implode`](@ref). `empty_as_null`: an empty list produces one `null` row when `true` (default),
rather than disappearing. `keep_nulls`: a `null` list entry produces one `null` row when `true`
(default), rather than disappearing.
"""
function flatten(expr::Expr; empty_as_null::Bool = true, keep_nulls::Bool = true)
    out = API.polars_expr_flatten(expr, empty_as_null, keep_nulls)
    return Expr(out)
end
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
# generated by `@generate_expr_fns`'s `curried` variant, right next to each primal above (search
# `_curried!`). This is the one exception -- `is_in` also needs an `AbstractVector`-specific
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

"""
    shift_and_fill(expr::Polars.Expr, n, fill_value)::Polars.Expr

Like [`shift`](@ref), but the positions vacated by the shift are filled with `fill_value`
instead of `missing`.
"""
function shift_and_fill(expr::Expr, n, fill_value)
    out = API.polars_expr_shift_and_fill(expr, convert(Expr, n), convert(Expr, fill_value))
    return Expr(out)
end
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

"""
    clip(expr::Polars.Expr, min, max)::Polars.Expr

Clips the values to the `[min, max]` range (values outside are set to the nearest bound).
"""
function clip(expr::Expr, min, max)
    min = convert(Expr, min)
    max = convert(Expr, max)
    out = API.polars_expr_clip(expr, min, max)
    return Expr(out)
end

@curry clip(min, max)

export clip

"""
    clip_min(expr::Polars.Expr, min)::Polars.Expr

Clips values below `min` up to `min` (values `>= min`, and any `missing`, pass through
unchanged). The single-sided counterpart to [`clip`](@ref); see [`clip_max`](@ref) for the
upper-bound-only form.
"""
clip_min(expr::Expr, min) = Expr(API.polars_expr_clip_min(expr, convert(Expr, min)))

@curry clip_min(min)

"""
    clip_max(expr::Polars.Expr, max)::Polars.Expr

Clips values above `max` down to `max` (values `<= max`, and any `missing`, pass through
unchanged). The single-sided counterpart to [`clip`](@ref); see [`clip_min`](@ref) for the
lower-bound-only form.
"""
clip_max(expr::Expr, max) = Expr(API.polars_expr_clip_max(expr, convert(Expr, max)))

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

"""
    gather(expr::Polars.Expr, idx; null_on_oob::Bool=false)::Polars.Expr

Take values by index. `idx` is an expression, or an integer vector promoted via [`lit`](@ref).

`null_on_oob` sets the behaviour when an index is out of bounds: `true` gives `missing`, `false`
(the default) raises a [`PolarsError`](@ref) when the result is collected.

!!! note "Indices are 0-based"
    `idx` is 0-based, and negative indices count from the end. This differs from
    [`Polars.nth`](@ref) and `Selectors.by_index`, which are 1-based: those select a column from a
    position the caller writes literally, whereas `idx` here is data, and usually comes from
    [`arg_sort`](@ref), `arg_min` or `arg_max`, which return 0-based positions. Sharing one
    convention lets `gather(x, arg_sort(y))` compose without an offset.
"""
function gather(expr::Expr, idx; null_on_oob::Bool = false)
    idx = convert(Expr, idx)
    out = API.polars_expr_gather(expr, idx, null_on_oob)
    return Expr(out)
end

export gather

"""
    gather_every(expr::Polars.Expr, n::Integer; offset::Integer=0)::Polars.Expr

Take every `n`th value. `offset` is the starting index, 0-based.
"""
function gather_every(expr::Expr, n::Integer; offset::Integer = 0)
    out = API.polars_expr_gather_every(expr, n, offset)
    return Expr(out)
end

export gather_every


"""
    item(expr::Polars.Expr; allow_empty::Bool=false)::Polars.Expr

The aggregation form of `item`: raises unless `expr` evaluates to exactly one value (per group, or
overall). If `allow_empty` is `true`, zero values is also accepted and produces `missing` instead
of raising -- more than one value always raises regardless. Distinct from `Polars.item` on a
`DataFrame`/`Series` (a `(1,1)`-shape accessor, not an aggregation).
"""
item(expr::Expr; allow_empty::Bool = false) = Expr(API.polars_expr_item(expr, allow_empty))


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
    exprs = _expr_vector((first, rest...))
    GC.@preserve exprs begin
        ptrs = Ptr{polars_expr_t}[e.ptr for e in exprs]
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_coalesce(ptrs, length(ptrs), out)
        polars_error(err)
    end
    return Expr(out[])
end

"""
    as_struct(exprs...)::Polars.Expr

Collects `exprs` (columns or expressions) into a single `Struct`-typed expression, one field per
input (named after each input's own output name). The write-side counterpart to
[`Structs.field_by_name`](@ref)/[`Structs.field_by_index`](@ref).
"""
function as_struct(exprs...)
    exprs = _expr_vector(exprs)
    GC.@preserve exprs begin
        ptrs = Ptr{polars_expr_t}[e.ptr for e in exprs]
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_as_struct(ptrs, length(ptrs), out)
        polars_error(err)
    end
    return Expr(out[])
end

export as_struct

"""
    all_horizontal(exprs...)::Polars.Expr

Row-wise (horizontal) boolean AND across `exprs`. The output column is named `"all"` unless
[`alias`](@ref)ed.
"""
function all_horizontal(exprs...)
    exprs = _expr_vector(exprs)
    GC.@preserve exprs begin
        ptrs = Ptr{polars_expr_t}[e.ptr for e in exprs]
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_all_horizontal(ptrs, length(ptrs), out)
        polars_error(err)
    end
    return Expr(out[])
end

"""
    any_horizontal(exprs...)::Polars.Expr

Row-wise (horizontal) boolean OR across `exprs`. The output column is named `"any"` unless
[`alias`](@ref)ed.
"""
function any_horizontal(exprs...)
    exprs = _expr_vector(exprs)
    GC.@preserve exprs begin
        ptrs = Ptr{polars_expr_t}[e.ptr for e in exprs]
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_any_horizontal(ptrs, length(ptrs), out)
        polars_error(err)
    end
    return Expr(out[])
end

"""
    min_horizontal(exprs...)::Polars.Expr

Row-wise (horizontal) minimum across `exprs`. The output column is named `"min"` unless
[`alias`](@ref)ed.
"""
function min_horizontal(exprs...)
    exprs = _expr_vector(exprs)
    GC.@preserve exprs begin
        ptrs = Ptr{polars_expr_t}[e.ptr for e in exprs]
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_min_horizontal(ptrs, length(ptrs), out)
        polars_error(err)
    end
    return Expr(out[])
end

"""
    max_horizontal(exprs...)::Polars.Expr

Row-wise (horizontal) maximum across `exprs`. The output column is named `"max"` unless
[`alias`](@ref)ed.
"""
function max_horizontal(exprs...)
    exprs = _expr_vector(exprs)
    GC.@preserve exprs begin
        ptrs = Ptr{polars_expr_t}[e.ptr for e in exprs]
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_max_horizontal(ptrs, length(ptrs), out)
        polars_error(err)
    end
    return Expr(out[])
end

"""
    sum_horizontal(exprs...; ignore_nulls::Bool=true)::Polars.Expr

Row-wise (horizontal) sum across `exprs`. If `ignore_nulls` is `true` (default), nulls are
treated as `0`; if `false`, any null in a row makes that row's sum `null`.
"""
function sum_horizontal(exprs...; ignore_nulls::Bool = true)
    exprs = _expr_vector(exprs)
    GC.@preserve exprs begin
        ptrs = Ptr{polars_expr_t}[e.ptr for e in exprs]
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_sum_horizontal(ptrs, length(ptrs), ignore_nulls, out)
        polars_error(err)
    end
    return Expr(out[])
end

"""
    mean_horizontal(exprs...; ignore_nulls::Bool=true)::Polars.Expr

Row-wise (horizontal) mean across `exprs`. If `ignore_nulls` is `true` (default), nulls are
excluded from the average; if `false`, any null in a row makes that row's mean `null`.
"""
function mean_horizontal(exprs...; ignore_nulls::Bool = true)
    exprs = _expr_vector(exprs)
    GC.@preserve exprs begin
        ptrs = Ptr{polars_expr_t}[e.ptr for e in exprs]
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_mean_horizontal(ptrs, length(ptrs), ignore_nulls, out)
        polars_error(err)
    end
    return Expr(out[])
end

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
