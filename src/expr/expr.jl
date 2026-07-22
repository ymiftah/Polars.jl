"""
    Expr

Internal structure representing a value in a Polars expression.
This should not be constructed directly but rather use helper functions
such as [`col`](@ref).

!!! note "Not `<: Number`, not sortable/hashable as a DSL value"
    Earlier versions of this package made `Expr <: Number` purely so that mixed arguments (e.g.
    `col("x") + 1`) would reach the operators below via Julia's `Number`-specific promotion
    fallbacks. That piggybacked correctness on a lie -- an `Expr` is not a number, and the
    supertype silently broke `isequal`/`isless`'s contracts (both must return `Bool`; both
    returned another `Expr` instead, matching the DSL's `==`/`<` behavior) and let `Expr` values
    leak into arbitrary generic `Number` code paths that assume real arithmetic semantics. Every
    operator below is now defined explicitly instead (`Expr`-`Expr` and both mixed-argument
    orders), so no promotion machinery is needed. `isless`/`isequal` are deliberately *not*
    defined for `Expr`: `Expr`s are therefore not valid `sort`/`Dict`/`Set` keys. Both fail loudly
    rather than silently misbehaving -- `isless` with a clear `MethodError` (no fallback exists in
    Base for arbitrary types), `isequal` with a `TypeError` (Base's own generic fallback is
    `isequal(x, y) = (x == y)::Bool`, and our `==` returns an `Expr`, which fails that type
    assertion). This matches Python polars, where `Expr.__eq__` also builds a new expression
    rather than comparing identity.
"""
mutable struct Expr
    ptr::Ptr{polars_expr_t}

    Expr(ptr) = finalizer(polars_expr_destroy, new(ptr))
end

Base.unsafe_convert(::Type{Ptr{polars_expr_t}}, expr::Expr) = expr.ptr

# `Expr <: Number` used to make Julia's default `broadcastable(x::Number) = x` fallback treat an
# `Expr` as a scalar during dot-broadcasting (e.g. `col("x") .> 1`, used throughout this package's
# own tests). Without a supertype, `Expr` would instead hit Base's generic
# `broadcastable(x) = collect(x)` fallback for otherwise-unmatched types, which tries to iterate
# it and fails with a confusing `MethodError: no method matching length(::Expr)`. `Ref(expr)`
# matches how `AbstractString`/`Symbol`/`Missing`/etc. (also not `<: Number`) opt into the same
# scalar-broadcasting behavior.
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

"""Derived comparison DSL primitives -- polars' C ABI only wraps `eq`/`lt`/`gt` directly (see
`@generate_expr_fns` below); `<=`/`>=`/`!=` compose them with `not`, which preserves polars' null
propagation correctly (`not` of a null is null, matching what `<=`/`>=`/`!=` must do when an
operand is incomparable). Not exported -- these are an internal implementation detail of the
operators below, unlike `eq`/`gt`/`lt`, which mirror real `polars::Expr` methods 1:1."""
_le(a::Expr, b::Expr) = not(gt(a, b))
_ge(a::Expr, b::Expr) = not(Base.lt(a, b))
_neq(a::Expr, b::Expr) = not(eq(a, b))

# Every arithmetic/comparison/logical operator needs five methods -- `Expr`-`Expr`, both
# mixed-argument orders (`Expr(x) op literal` and `literal op Expr(x)`), and both `Missing`
# orders -- now that `Expr` isn't `<: Number` and can no longer piggyback on Julia's
# `Number`-specific promotion fallbacks (see the struct docstring above). `dsl` is looked up
# unqualified except `Base.lt`, which -- unlike `eq`/`gt`/`add`/... -- collides with an
# *unexported* internal `Base.lt` binding, so `@generate_expr_fns` qualified its own definition to
# `Base.lt` and it must be called that way too (the same class of gotcha as
# `Expr::product`/`Base.product` documented in CLAUDE.md, just for an operator this package still
# needs to call internally rather than export).
#
# The dedicated `(Expr, Missing)`/`(Missing, Expr)` pair exists only to resolve a method
# ambiguity, not to add new behavior: `Base.$op(a::Expr, b) = ...` (b unconstrained) is exactly as
# specific as Base's own `missing.jl` fallbacks (e.g. `==(::Any, ::Missing) = missing`,
# `<(::Any, ::Missing) = missing`) for a literal `missing` second argument, so
# `col("x") == missing` raised `MethodError: ==(::Expr, ::Missing) is ambiguous` without these --
# Julia's own suggested fix is to add the strictly-more-specific `(Expr, Missing)` method, which
# routes through `convert(Expr, missing)` (a real DSL null literal) same as any other literal,
# rather than short-circuiting to Julia's `missing`-propagation the way plain `Any` values never
# would have reached anyway.
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
expression (`select`, `filter`, `group_by`, `sort`, `join`, `over`, ...) in place of each one
repeating its own `ex -> ex isa String ? col(ex) : ex` inline. Exhaustive over the three accepted
input shapes (no generic fallback method): passing anything else raises a clear `MethodError`
right at the coercion site rather than deferring to a more confusing failure further downstream
(e.g. inside a later `convert(Vector{Expr}, ...)`).
"""
_as_expr(x::AbstractString) = col(String(x))
_as_expr(x::Symbol) = col(String(x))
_as_expr(x::Expr) = x

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
match -- returns `nothing` if `dtype` isn't one of these. This deliberately excludes `DateTime` and
the duration `Period` subtypes even though polars has dtypes for them: those need a time unit (and
`DateTime` a time zone) that a bare `polars_value_type_t` code can't carry, so `cast` and
[`Selectors.by_dtype`](@ref) each handle them separately (before/after calling this, respectively)
rather than through this shared table. Single source of truth for the plain-dtype mapping, used by
both.
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

Casts the series represented by the expression to the provided `dtype`. Supports `Missing`, the
physical numeric types, `Bool`, `String`, `Vector{UInt8}` (Binary), `Date`, `Dates.Time`,
`DateTime` (naive or timezone-aware -- see `time_unit`/`time_zone` below), and
`Dates.Nanosecond`/`Dates.Microsecond`/`Dates.Millisecond` (Duration, resolution implied by the
chosen `Period` subtype) -- `Categorical`, `Decimal`, `List`, and `Struct` need parameters this
single-type-argument form can't carry; see [`cast_categorical`](@ref)/[`cast_decimal`](@ref) for
those. Any other target raises an error. `time_unit`/`time_zone` only apply to a `DateTime`
target (ignored otherwise): `time_unit` is one of `:ns`, `:us` (default), `:ms`; `time_zone` is
`nothing` (default, naive) or an IANA time zone name.
"""
function cast(
        expr, dtype;
        time_unit::Symbol = :us, time_zone::Union{Nothing, AbstractString} = nothing
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
    err = API.polars_expr_cast(expr, value_type, out)
    polars_error(err)
    return Expr(out[])
end
cast(dtype; kwargs...) = expr -> cast(expr, dtype; kwargs...)

"""
    cast_datetime(expr::Polars.Expr; time_unit::Symbol=:us,
                  time_zone::Union{Nothing,AbstractString}=nothing)::Polars.Expr

Casts `expr` to `Datetime(time_unit, time_zone)`. Also reachable as `cast(expr, DateTime;
time_unit, time_zone)`; this is the underlying implementation (`polars_value_type_t`, used by the
plain `cast`, can't carry a time unit or time zone, so `Datetime` needs its own entry point).
`time_unit` is one of `:ns`, `:us` (default), `:ms`; `time_zone` is `nothing` (default, naive) or
an IANA time zone name.
"""
function cast_datetime(
        expr::Expr; time_unit::Symbol = :us, time_zone::Union{Nothing, AbstractString} = nothing
    )
    unit_enum = if time_unit == :ns
        API.PolarsTimeUnitNanosecond
    elseif time_unit == :us
        API.PolarsTimeUnitMicrosecond
    elseif time_unit == :ms
        API.PolarsTimeUnitMillisecond
    else
        error("unknown time_unit $time_unit, expected one of (:ns, :us, :ms)")
    end
    tz = time_zone === nothing ? "" : String(time_zone)
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_cast_datetime(expr, unit_enum, tz, ncodeunits(tz), out)
    polars_error(err)
    return Expr(out[])
end

"""
    cast_duration(expr::Polars.Expr; time_unit::Symbol=:us)::Polars.Expr

Casts `expr` to `Duration(time_unit)`. Also reachable via `cast(expr,
Dates.Nanosecond|Microsecond|Millisecond)`, which just calls this with the unit implied by the
chosen `Period` subtype -- this named form is for when you'd rather pass `time_unit` as a keyword.
`time_unit` is one of `:ns`, `:us` (default), `:ms`.
"""
function cast_duration(expr::Expr; time_unit::Symbol = :us)
    unit_enum = if time_unit == :ns
        API.PolarsTimeUnitNanosecond
    elseif time_unit == :us
        API.PolarsTimeUnitMicrosecond
    elseif time_unit == :ms
        API.PolarsTimeUnitMillisecond
    else
        error("unknown time_unit $time_unit, expected one of (:ns, :us, :ms)")
    end
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_cast_duration(expr, unit_enum, out)
    polars_error(err)
    return Expr(out[])
end
cast_duration(; time_unit::Symbol = :us) = expr -> cast_duration(expr; time_unit)

"""
    cast_decimal(expr::Polars.Expr, precision::Integer, scale::Integer)::Polars.Expr
    cast_decimal(precision::Integer, scale::Integer)::Base.Callable

Casts `expr` to `Decimal(precision, scale)` (`1 <= precision <= 38`; `scale` is the number of
digits after the decimal point). Decimal columns have no dedicated Julia read path yet --
materializing one via `collect`/`getindex` is not supported -- so this is mainly useful for
writing out decimal-typed columns (e.g. to parquet) rather than reading them back in Julia.
"""
function cast_decimal(expr::Expr, precision::Integer, scale::Integer)
    out = API.polars_expr_cast_decimal(expr, Csize_t(precision), Csize_t(scale))
    return Expr(out)
end
cast_decimal(precision::Integer, scale::Integer) = expr -> cast_decimal(expr, precision, scale)

"""
    cast_categorical(expr::Polars.Expr)::Polars.Expr

Casts `expr` to `Categorical`, using the global category registry shared by every Categorical
column in the session (matching py-polars' default `Categorical` behavior -- there is no
per-column category set in this wrapper). Reading a Categorical column back already materializes
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

Chained conditional expression -- the native equivalent of py-polars'
`when(c1).then(v1).when(c2).then(v2)....otherwise(...)` builder. Evaluates each `cond => value`
pair in order and takes the first `value` whose `cond` is `true`; falls back to `otherwise` if
none match. `cond`s must be `Polars.Expr`s; `value`s and `otherwise` may be `Polars.Expr`s or
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

    gen_impl_expr!(polars_expr_sqrt, Expr::sqrt, "Square root of each value of `expr`.")
    gen_impl_expr!(polars_expr_sign, Expr::sign, "Sign of each value of `expr`: `-1`, `0`, or `1` (float dtypes only; `NaN` maps to `NaN`).")
    gen_impl_expr!(polars_expr_exp, Expr::exp, "`e` raised to each value of `expr`.")

    gen_impl_expr!(polars_expr_n_unique, Expr::n_unique, "Counts the number of distinct values in `expr` (`null` counts as one distinct value), one result per group (or a single overall count outside a `group_by`).")
    gen_impl_expr!(polars_expr_unique, Expr::unique, "Returns the distinct values of `expr` (order not guaranteed), shortening the column. Inside `agg`, per-group distinct values are automatically collected into a `List` (see [Lists](@ref)) so the aggregation still produces one row per group.")
    gen_impl_expr!(polars_expr_is_duplicated, Expr::is_duplicated, "Row-wise boolean flag: `true` for every occurrence of a value that appears more than once in `expr`. See [`is_unique`](@ref) for the complementary flag.")
    gen_impl_expr!(polars_expr_is_unique, Expr::is_unique, "Row-wise boolean flag: `true` for every value that appears exactly once in `expr`. See [`is_duplicated`](@ref) for the complementary flag.")
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
    gen_impl_expr!(polars_expr_drop_nans, Expr::drop_nans, "Removes `NaN` values from `expr`, shortening the column. Compare the frame-level `drop_nulls` (see [Manipulation](@ref)), which drops whole rows instead of individual values.")
    gen_impl_expr!(polars_expr_drop_nulls, Expr::drop_nulls, "Removes `null` values from `expr`, shortening the column -- the expression-level counterpart to the frame-level `drop_nulls` (see [Manipulation](@ref)), which drops whole rows instead of individual values.")

    gen_impl_expr!(polars_expr_implode, Expr::implode, "Collects every value of `expr` in the current context (or per group, inside `agg`) into a single `List` value (see [Lists](@ref)).")
    gen_impl_expr!(polars_expr_flatten, Expr::flatten, "Explodes a `List`-typed `expr` back into one row per element -- the expression-level inverse of [`implode`](@ref).")
    gen_impl_expr!(polars_expr_reverse, Expr::reverse, "Reverses the row order of `expr`'s values.")

    gen_impl_expr_binary!(polars_expr_eq, Expr::eq, "Elementwise equality between `a` and `b` -- the named-function form of `a .== b` (see [Named binary functions](@ref)). Comparing against `null` gives `null`, not `false` (three-valued logic).")
    gen_impl_expr_binary!(polars_expr_lt, Expr::lt, "Elementwise `a < b` -- the named-function form of the `<` operator. Bound as `Base.lt` since plain `lt` is an unexported internal `Base` binding; call it qualified (`Base.lt(a, b)`), or use `.>` with the arguments flipped.")
    gen_impl_expr_binary!(polars_expr_gt, Expr::gt, "Elementwise `a > b` -- the named-function form of `a .> b`.")
    gen_impl_expr_binary!(polars_expr_or, Expr::or, "Elementwise logical OR between two boolean expressions -- the named-function form of `a .| b`.")
    gen_impl_expr_binary!(polars_expr_xor, Expr::xor, "Elementwise logical XOR between two boolean expressions. Has no operator equivalent in this package -- must be called by name.")
    gen_impl_expr_binary!(polars_expr_and, Expr::and, "Elementwise logical AND between two boolean expressions -- the named-function form of `a .& b`.")

    gen_impl_expr_binary!(polars_expr_pow, Expr::pow, "Elementwise `a ^ b` -- the named-function form of the `^` operator.")
    gen_impl_expr_binary!(polars_expr_add, Expr::add, "Elementwise `a + b` -- the named-function form of the `+` operator.")
    gen_impl_expr_binary!(polars_expr_sub, Expr::sub, "Elementwise `a - b` -- the named-function form of the `-` operator.")
    gen_impl_expr_binary!(polars_expr_mul, Expr::mul, "Elementwise `a * b` -- the named-function form of the `*` operator.")
    gen_impl_expr_binary!(polars_expr_div, Expr::div, "Elementwise `a / b` -- the named-function form of the `/` operator.")

    gen_impl_expr_binary!(polars_expr_fill_null, Expr::fill_null, "Replaces every `null` value in `a` with the corresponding value of `b` (a literal via `lit`, or another expression). Has a curried form `fill_null(value)` for `|>` pipelines -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary!(polars_expr_fill_nan, Expr::fill_nan, "Replaces every `NaN` value in `a` with the corresponding value of `b`. Has a curried form `fill_nan(value)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary!(polars_expr_is_in, Expr::is_in, "Row-wise boolean flag: `true` where the value of `a` appears in `b` (typically `implode(lit(values))`, or another column). Has a curried form `is_in(values)` -- see [Curried forms for pipe-based composition](@ref) and the `lit(::Vector)` section below for how to build `b`.")

    gen_impl_expr_binary!(polars_expr_shift, Expr::shift, "Shifts `a`'s values down by `b` rows (negative `b` shifts up), filling the vacated positions with `null`. Has a curried form `shift(n)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary!(polars_expr_pct_change, Expr::pct_change, "Percent change between each value of `a` and the value `b` rows earlier: `(a[i] - a[i-b]) / a[i-b]`. Has a curried form `pct_change(n)` -- see [Curried forms for pipe-based composition](@ref).")

    gen_impl_expr_binary!(polars_expr_log, Expr::log, "Logarithm of `a` with base `b` (e.g. `log(expr, lit(2))` for log base 2; use `lit(ℯ)` for natural log). Bound as `Base.log`, an exported Base name, so it works unqualified.")
    gen_impl_expr_binary!(polars_expr_rem, Expr::rem, "Remainder of `a / b` (elementwise), matching the sign of `a` -- the named-function form of `Base.rem` extended to `Expr` arguments.")
end

# Curried (Fix2-style) forms for the binary namespace-free ops above that have no natural
# operator equivalent (unlike +/-/*//, which already read fluently as infix). Each promotes a
# literal second argument via `convert(Expr, ...)`, matching Python polars' `.is_in([1,2,3])`,
# `.fill_null(0)`, etc. `log`/`rem` (and, elsewhere, `replace`/`diff`/`round`) are deliberately
# excluded -- not because of dispatch ambiguity (Julia always prefers Base's existing concrete-type
# methods, e.g. `log(::Float64)`, over anything added here, so no ambiguity error would ever occur), but
# because a curry that's actually useful for plain numeric literals has to accept an untyped or
# broadly-typed argument, and that means claiming argument-type combinations Base currently leaves
# undefined (e.g. `log(1, 2)` on two bare `Int`s -- currently a MethodError). That's real type
# piracy regardless of whether it happens to work today: it silently changes global Base behavior
# outside this package's own types, which Aqua's piracy check flags and which is fragile against
# future Base/other-package additions for the same combination. A curry typed narrowly to `Expr`
# would avoid the piracy but would then only accept already-constructed `Expr`s, not bare literals
# -- defeating the actual ergonomic goal, so it isn't worth doing either.
is_in(other::AbstractVector) = Base.Fix2(is_in, implode(convert(Expr, other)))
is_in(other) = Base.Fix2(is_in, convert(Expr, other))
fill_null(value) = Base.Fix2(fill_null, convert(Expr, value))
fill_nan(value) = Base.Fix2(fill_nan, convert(Expr, value))

"""
    fill_null(expr::Polars.Expr; strategy::Symbol, limit::Union{Nothing,Integer}=nothing)::Polars.Expr
    fill_null(; strategy::Symbol, limit::Union{Nothing,Integer}=nothing)

Replaces every `null` value in `expr` using a fill *strategy* instead of a fixed value (see the
2-arg `fill_null(expr, value)` above for that form). `strategy` is one of `:forward`/`:backward`
(propagate the nearest non-null value in that direction -- `limit` caps how many consecutive
nulls a single value may fill, `nothing` for unlimited), `:mean`/`:min`/`:max` (the column's own
aggregate), or `:zero`/`:one` (a fixed numeric fill, dtype-appropriate). `limit` only applies to
`:forward`/`:backward` and is ignored otherwise. Has a curried form (2nd method) for `|>`
pipelines.
"""
function fill_null(expr::Expr; strategy::Symbol, limit::Union{Nothing, Integer} = nothing)
    strategy_enum = if strategy == :backward
        API.PolarsFillNullStrategyBackward
    elseif strategy == :forward
        API.PolarsFillNullStrategyForward
    elseif strategy == :mean
        API.PolarsFillNullStrategyMean
    elseif strategy == :min
        API.PolarsFillNullStrategyMin
    elseif strategy == :max
        API.PolarsFillNullStrategyMax
    elseif strategy == :zero
        API.PolarsFillNullStrategyZero
    elseif strategy == :one
        API.PolarsFillNullStrategyOne
    else
        error("unknown fill_null strategy=$strategy, expected one of (:forward, :backward, :mean, :min, :max, :zero, :one)")
    end
    limit_ref = limit === nothing ? Ptr{UInt32}(C_NULL) : Ref(UInt32(limit))
    out = GC.@preserve limit_ref API.polars_expr_fill_null_with_strategy(expr, strategy_enum, limit_ref)
    return Expr(out)
end
fill_null(; strategy::Symbol, limit::Union{Nothing, Integer} = nothing) =
    expr -> fill_null(expr; strategy, limit)
shift(n) = Base.Fix2(shift, convert(Expr, n))
pct_change(n) = Base.Fix2(pct_change, convert(Expr, n))

"""
    round(expr::Polars.Expr, decimals::Integer=0; mode::Symbol=:half_to_even)::Polars.Expr

Rounds to `decimals` decimal places, breaking ties according to `mode`: one of
`:half_to_even` (default, banker's rounding), `:half_away_from_zero`, `:to_zero`.
"""
function Base.round(expr::Expr, decimals::Integer = 0; mode::Symbol = :half_to_even)
    mode_enum = if mode == :half_to_even
        API.PolarsRoundModeHalfToEven
    elseif mode == :half_away_from_zero
        API.PolarsRoundModeHalfAwayFromZero
    elseif mode == :to_zero
        API.PolarsRoundModeToZero
    else
        error(
            "unknown round mode $mode, expected one of " *
                "(:half_to_even, :half_away_from_zero, :to_zero)"
        )
    end
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

"""
    clip(min, max)::Base.Callable

Curried form of [`clip`](@ref) for use with `|>` -- e.g. `col("x") |> clip(0, 10)`.
"""
clip(min, max) = expr -> clip(expr, min, max)

export clip

"""
    replace(expr::Polars.Expr, old, new)::Polars.Expr

Replaces values equal to `old` with the corresponding `new` value (`old`/`new` are typically
list-typed expressions built via [`Lists.implode`](@ref)/[`implode`](@ref) for multi-value
mappings). Values not found in `old` are left unchanged. Extends `Base.replace` — `isdefined(Base,
:replace)` is `true`, matching the `Base.diff`/`Base.round`/`Base.log` precedent.
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

"""
    replace_strict(old, new; default=nothing)::Base.Callable

Curried form of [`replace_strict`](@ref) for use with `|>`.
"""
replace_strict(old, new; default = nothing) = expr -> replace_strict(expr, old, new; default = default)

export replace_strict

"""
    prod(expr::Polars.Expr)::Polars.Expr

Product of the values.

Extends `Base.prod` (hand-written outside the `@generate_expr_fns` block rather than
auto-qualified, so it lands on the *exported* `Base.prod` -- not the unexported, unrelated
internal `Base.product` binding the Rust method name `Expr::product` would otherwise collide
with via `isdefined(Base, :product)`). This matches the `Base.sum` precedent: since `prod` is an
exported Base name, plain `prod(expr)` resolves here with no qualification needed, unlike the
`Base.product(...)`-qualification this used to require. `mean`/`median`/`std`/`var`/`quantile`
follow the analogous pattern one level up, against `Statistics` instead of `Base` -- see their
docstrings below.
"""
Base.prod(expr::Expr) = Expr(API.polars_expr_product(expr))

import Statistics: mean, median, std, var, quantile

"""
    mean(expr::Polars.Expr)::Polars.Expr
    median(expr::Polars.Expr)::Polars.Expr

Arithmetic mean / median of the values. Extends `Statistics.mean`/`Statistics.median` (rather
than the `@generate_expr_fns` block above, which would otherwise define brand-new top-level
`mean`/`median` bindings that *look* like the Statistics stdlib functions but aren't actually
the same generic -- so `using Statistics, Polars` would force callers to disambiguate with
`Polars.mean`/`Statistics.mean` even though nothing about the two ever needs to differ). Adding
an `Expr` method to the real `Statistics.mean`/`Statistics.median` instead means the two packages
share one generic function with no clash, and this package still re-exports the name so plain
`mean(col("x"))` works with just `using Polars` -- `using Statistics` is not required.
"""
Statistics.mean(expr::Expr) = Expr(API.polars_expr_mean(expr))
Statistics.median(expr::Expr) = Expr(API.polars_expr_median(expr))

"""
    std(expr::Polars.Expr; ddof::Integer=1)::Polars.Expr

Standard deviation of the values, with `ddof` degrees of freedom subtracted (defaults to
`ddof=1`). Extends `Statistics.std` (see the [`mean`](@ref)/[`median`](@ref) docstring above for
why).

!!! note
    No curried (`|>`) form: `Statistics.std(; ddof=2)` with no positional argument at all would
    be type piracy (nothing in that signature mentions `Expr`) -- use `x -> std(x; ddof=2)`
    instead.
"""
function Statistics.std(expr::Expr; ddof::Integer = 1)
    out = API.polars_expr_std(expr, UInt8(ddof))
    return Expr(out)
end

"""
    var(expr::Polars.Expr; ddof::Integer=1)::Polars.Expr

Variance of the values, with `ddof` degrees of freedom subtracted (defaults to `ddof=1`).
Extends `Statistics.var` -- see [`std`](@ref)'s docstring for why there's no curried form.
"""
function Statistics.var(expr::Expr; ddof::Integer = 1)
    out = API.polars_expr_var(expr, UInt8(ddof))
    return Expr(out)
end

"""
    quantile(expr::Polars.Expr, q; method::Symbol=:nearest)::Polars.Expr

Computes the `q`-th quantile (`q` an `Expr` or a numeric literal in `[0, 1]`) of the values,
using the given interpolation `method`: one of `:nearest` (default), `:lower`, `:higher`,
`:midpoint`, `:linear`, `:equiprobable`. Extends `Statistics.quantile` -- see [`std`](@ref)'s
docstring for why there's no curried form (`q |> quantile(0.5)`-style currying would need a
piratical zero-`Expr`-argument method).
"""
function Statistics.quantile(expr::Expr, q; method::Symbol = :nearest)
    q = convert(Expr, q)
    method_enum = if method == :nearest
        API.PolarsQuantileMethodNearest
    elseif method == :lower
        API.PolarsQuantileMethodLower
    elseif method == :higher
        API.PolarsQuantileMethodHigher
    elseif method == :midpoint
        API.PolarsQuantileMethodMidpoint
    elseif method == :linear
        API.PolarsQuantileMethodLinear
    elseif method == :equiprobable
        API.PolarsQuantileMethodEquiprobable
    else
        error(
            "unknown quantile method $method, expected one of " *
                "(:nearest, :lower, :higher, :midpoint, :linear, :equiprobable)"
        )
    end
    out = API.polars_expr_quantile(expr, q, method_enum)
    return Expr(out)
end

export mean, median, std, var, quantile

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
    partition_by = map(_as_expr, partition_by)
    partition_by = convert(Vector{Expr}, collect(partition_by))
    mapping_enum = if mapping_strategy == :group_to_rows
        API.PolarsWindowMappingGroupsToRows
    elseif mapping_strategy == :explode
        API.PolarsWindowMappingExplode
    elseif mapping_strategy == :join
        API.PolarsWindowMappingJoin
    else
        error("unknown over mapping_strategy=$mapping_strategy, expected one of (:group_to_rows, :explode, :join)")
    end
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
over(partition_by::Union{String, Symbol}...; kwargs...) =
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
    by = map(_as_expr, by)
    by = convert(Vector{Expr}, collect(by))
    n_by = length(by)
    descending = rev isa Bool ? fill(rev, n_by) : rev
    @assert length(descending) == n_by "rev must have the same length as the number of by expressions (got $n_by by expressions and $(length(descending)) rev)"
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
function sort_by(by::Union{String, Symbol}...; rev = false, nulls_last::Bool = false, maintain_order::Bool = false)
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

"""
    arg_sort(; descending::Bool=false, nulls_last::Bool=false)::Base.Callable

Curried form of [`arg_sort`](@ref) for use with `|>`.
"""
arg_sort(; descending::Bool = false, nulls_last::Bool = false) = expr -> arg_sort(expr; descending, nulls_last)

export arg_sort

"""
    top_k(expr::Polars.Expr, k)::Polars.Expr

Returns the `k` largest elements of `expr` (not necessarily sorted; combine with [`sort_by`](@ref)
if order matters).
"""
function top_k(expr::Expr, k)
    k = convert(Expr, k)
    out = API.polars_expr_top_k(expr, k)
    return Expr(out)
end

"""
    top_k(k)::Base.Fix2{typeof(top_k)}

Curried form of [`top_k`](@ref) for use with `|>` -- e.g. `col("x") |> top_k(3)`.
"""
top_k(k) = Base.Fix2(top_k, convert(Expr, k))

export top_k

"""
    value_counts(expr::Polars.Expr; sort::Bool=false, parallel::Bool=false, name::String="count",
                 normalize::Bool=false)::Polars.Expr

Counts the occurrences of each unique value in `expr`, returning a `Struct` column mapping value
to count (field `name`, default `"count"`). If `sort` is `true`, results are sorted by count
descending. If `normalize` is `true`, counts become fractions of the total instead.
"""
function value_counts(
        expr::Expr; sort::Bool = false, parallel::Bool = false, name::String = "count",
        normalize::Bool = false
    )
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_value_counts(expr, sort, parallel, name, ncodeunits(name), normalize, out)
    polars_error(err)
    return Expr(out[])
end

"""
    value_counts(; sort::Bool=false, parallel::Bool=false, name::String="count",
                 normalize::Bool=false)::Base.Callable

Curried form of [`value_counts`](@ref) for use with `|>`.
"""
function value_counts(; sort::Bool = false, parallel::Bool = false, name::String = "count", normalize::Bool = false)
    return expr -> value_counts(expr; sort, parallel, name, normalize)
end

export value_counts

"""
    sample_n(expr::Polars.Expr, n; with_replacement::Bool=false, shuffle::Bool=false,
             seed::Union{Nothing,Integer}=nothing)::Polars.Expr

Randomly samples `n` values from `expr`. If `seed` is given, sampling is reproducible.
"""
function sample_n(
        expr::Expr, n; with_replacement::Bool = false, shuffle::Bool = false,
        seed::Union{Nothing, Integer} = nothing
    )
    n = convert(Expr, n)
    seed_ref = seed === nothing ? Ptr{UInt64}(C_NULL) : Ref(UInt64(seed))
    out = GC.@preserve seed_ref API.polars_expr_sample_n(expr, n, with_replacement, shuffle, seed_ref)
    return Expr(out)
end

"""
    sample_n(n; with_replacement::Bool=false, shuffle::Bool=false,
             seed::Union{Nothing,Integer}=nothing)::Base.Callable

Curried form of [`sample_n`](@ref) for use with `|>`.
"""
function sample_n(n; with_replacement::Bool = false, shuffle::Bool = false, seed::Union{Nothing, Integer} = nothing)
    return expr -> sample_n(expr, n; with_replacement, shuffle, seed)
end

export sample_n

"""
    sample_frac(expr::Polars.Expr, frac; with_replacement::Bool=false, shuffle::Bool=false,
                seed::Union{Nothing,Integer}=nothing)::Polars.Expr

Randomly samples a `frac` fraction of the values from `expr`. If `seed` is given, sampling is
reproducible.
"""
function sample_frac(
        expr::Expr, frac; with_replacement::Bool = false, shuffle::Bool = false,
        seed::Union{Nothing, Integer} = nothing
    )
    frac = convert(Expr, frac)
    seed_ref = seed === nothing ? Ptr{UInt64}(C_NULL) : Ref(UInt64(seed))
    out = GC.@preserve seed_ref API.polars_expr_sample_frac(expr, frac, with_replacement, shuffle, seed_ref)
    return Expr(out)
end

"""
    sample_frac(frac; with_replacement::Bool=false, shuffle::Bool=false,
                seed::Union{Nothing,Integer}=nothing)::Base.Callable

Curried form of [`sample_frac`](@ref) for use with `|>`.
"""
function sample_frac(
        frac; with_replacement::Bool = false, shuffle::Bool = false, seed::Union{Nothing, Integer} = nothing
    )
    return expr -> sample_frac(expr, frac; with_replacement, shuffle, seed)
end

export sample_frac

function _expr_vector(args)
    exprs = map(_as_expr, args)
    return convert(Vector{Expr}, collect(exprs))
end

"""
    coalesce(exprs::Expr...)::Polars.Expr

Returns the first non-null value among `exprs`, evaluated left to right. Extends `Base.coalesce`,
matching the `Base.replace`/`Base.round`/`Base.diff` precedent (`coalesce` is an *exported* Base
name; the signature is kept to plain `Expr` — not `Union{Expr,String}` — since Aqua's piracy
check treats a Union with any foreign member, e.g. `String`, as foreign, which would flag this as
type piracy against `Base.coalesce`).
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
    method_enum = if method == :linear
        API.PolarsInterpolationMethodLinear
    elseif method == :nearest
        API.PolarsInterpolationMethodNearest
    else
        error("unknown interpolation method $method, expected one of (:linear, :nearest)")
    end
    out = API.polars_expr_interpolate(expr, method_enum)
    return Expr(out)
end

"""
    interpolate(; method::Symbol=:linear)::Base.Callable

Curried form of [`interpolate`](@ref) for use with `|>`.
"""
interpolate(; method::Symbol = :linear) = expr -> interpolate(expr; method)

export interpolate

"""
    cum_sum(expr::Polars.Expr; reverse::Bool=false)::Polars.Expr

Cumulative sum of the values. If `reverse` is `true`, accumulates from the last value to the
first.
"""
cum_sum(expr::Expr; reverse::Bool = false) = Expr(API.polars_expr_cum_sum(expr, reverse))

"""
    cum_prod(expr::Polars.Expr; reverse::Bool=false)::Polars.Expr

Cumulative product of the values. If `reverse` is `true`, accumulates from the last value to
the first.
"""
cum_prod(expr::Expr; reverse::Bool = false) = Expr(API.polars_expr_cum_prod(expr, reverse))

"""
    cum_min(expr::Polars.Expr; reverse::Bool=false)::Polars.Expr

Cumulative minimum of the values. If `reverse` is `true`, accumulates from the last value to
the first.
"""
cum_min(expr::Expr; reverse::Bool = false) = Expr(API.polars_expr_cum_min(expr, reverse))

"""
    cum_max(expr::Polars.Expr; reverse::Bool=false)::Polars.Expr

Cumulative maximum of the values. If `reverse` is `true`, accumulates from the last value to
the first.
"""
cum_max(expr::Expr; reverse::Bool = false) = Expr(API.polars_expr_cum_max(expr, reverse))

"""
    cum_count(expr::Polars.Expr; reverse::Bool=false)::Polars.Expr

Cumulative count of non-null values. If `reverse` is `true`, accumulates from the last value to
the first.
"""
cum_count(expr::Expr; reverse::Bool = false) = Expr(API.polars_expr_cum_count(expr, reverse))

"""
    cum_sum(; reverse::Bool=false)::Base.Callable
    cum_prod(; reverse::Bool=false)::Base.Callable
    cum_min(; reverse::Bool=false)::Base.Callable
    cum_max(; reverse::Bool=false)::Base.Callable
    cum_count(; reverse::Bool=false)::Base.Callable

Curried forms of [`cum_sum`](@ref)/[`cum_prod`](@ref)/[`cum_min`](@ref)/[`cum_max`](@ref)/
[`cum_count`](@ref) for use with `|>`.
"""
cum_sum(; reverse::Bool = false) = expr -> cum_sum(expr; reverse)
cum_prod(; reverse::Bool = false) = expr -> cum_prod(expr; reverse)
cum_min(; reverse::Bool = false) = expr -> cum_min(expr; reverse)
cum_max(; reverse::Bool = false) = expr -> cum_max(expr; reverse)
cum_count(; reverse::Bool = false) = expr -> cum_count(expr; reverse)

export cum_sum, cum_prod, cum_min, cum_max, cum_count

"""
    diff(expr::Polars.Expr, n=1; null_behavior::Symbol=:ignore)::Polars.Expr

Computes the first discrete difference between shifted items (`expr[i] - expr[i - n]`).
`null_behavior` is one of `:ignore` (default, pads the first `n` values with `null`) or `:drop`
(drops the first `n` values instead).

Extends `Base.diff` with a method for `Polars.Expr`, so plain `diff(expr, ...)` dispatches here
without any extra qualification (`diff` is an *exported* Base name, like `sum`/`prod`/`mean`).
"""
function Base.diff(expr::Expr, n = 1; null_behavior::Symbol = :ignore)
    n = convert(Expr, n)
    behavior = if null_behavior == :ignore
        API.PolarsNullBehaviorIgnore
    elseif null_behavior == :drop
        API.PolarsNullBehaviorDrop
    else
        error("unknown null_behavior $null_behavior, expected one of (:ignore, :drop)")
    end
    out = API.polars_expr_diff(expr, n, behavior)
    return Expr(out)
end

"""
    rank(expr::Polars.Expr; method::Symbol=:dense, descending::Bool=false)::Polars.Expr

Assigns ranks to the values, dealing with ties according to `method`: one of `:average`,
`:min`, `:max`, `:dense` (default), `:ordinal`.
"""
function rank(expr::Expr; method::Symbol = :dense, descending::Bool = false)
    method_enum = if method == :average
        API.PolarsRankMethodAverage
    elseif method == :min
        API.PolarsRankMethodMin
    elseif method == :max
        API.PolarsRankMethodMax
    elseif method == :dense
        API.PolarsRankMethodDense
    elseif method == :ordinal
        API.PolarsRankMethodOrdinal
    else
        error("unknown rank method $method, expected one of (:average, :min, :max, :dense, :ordinal)")
    end
    out = API.polars_expr_rank(expr, method_enum, descending)
    return Expr(out)
end

"""
    rank(; method::Symbol=:dense, descending::Bool=false)::Base.Callable

Curried form of [`rank`](@ref) for use with `|>`.
"""
rank(; method::Symbol = :dense, descending::Bool = false) = expr -> rank(expr; method, descending)

export rank

export col, alias, prefix, suffix, to_lowercase, to_uppercase, lit, cast, when, element,
    cast_datetime, cast_duration, cast_decimal, cast_categorical,
    Lists, Strings, Dt, Structs, Selectors
# `Meta` (`src/expr/meta.jl`) is deliberately NOT exported here, unlike its siblings above --
# `Base.Meta` is itself an *exported* Base submodule (`Base.isexported(Base, :Meta) == true`,
# unlike the plain-function collisions `@generate_expr_fns` guards against elsewhere), so
# `export Meta` here would make plain `using Polars` immediately ambiguous-error on the bare name
# `Meta` in the importing module, not just risk shadowing it. Always reachable fully qualified as
# `Polars.Meta.output_name(...)` etc., same as any non-exported submodule.
