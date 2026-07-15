"""
    Expr

Internal structure representing a value in a Polars expression.
This should not be constructed directly but rather use helper functions
such as [`col`](@ref).
"""
mutable struct Expr <: Number
    #                  ↑
    #                  this is needed to use type promotion
    ptr::Ptr{polars_expr_t}

    Expr(ptr) = finalizer(polars_expr_destroy, new(ptr))
end

Base.unsafe_convert(::Type{Ptr{polars_expr_t}}, expr::Expr) = expr.ptr

Base.promote_rule(::Type{Expr}, ::Type{T}) where {T <: PhysicalDType} = Expr

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
    err = polars_expr_literal_utf8(s, length(s), out)
    polars_error(err)
    return Expr(out[])
end
function Base.convert(::Type{Expr}, v::AbstractVector)
    df = DataFrame((; literal = collect(v)))
    series = df[:literal]
    out = API.polars_expr_lit_series(series)
    return Expr(out)
end

Base.:(==)(a::Expr, b::Expr) = eq(a, b)
Base.isequal(a::Expr, b::Expr) = eq(a, b)
Base.isless(a::Expr, b::Expr) = Base.lt(a, b)
Base.isless(a::Expr, b) = isless(promote(a, b)...)
Base.isless(a, b::Expr) = isless(promote(a, b)...)
Base.isequal(a, b::Expr) = eq(promote(a, b)...)
Base.isequal(a::Expr, b) = eq(promote(a, b)...)

Base.:+(a::Expr, b::Expr) = add(a, b)
Base.:-(a::Expr, b::Expr) = sub(a, b)
Base.:*(a::Expr, b::Expr) = mul(a, b)
Base.:/(a::Expr, b::Expr) = div(a, b)
Base.:^(a::Expr, b::Expr) = pow(a, b)

Base.:&(a::Expr, b::Expr) = and(promote(a, b)...)
Base.:|(a::Expr, b::Expr) = or(promote(a, b)...)
Base.:&(a, b::Expr) = and(promote(a, b)...)
Base.:|(a, b::Expr) = or(promote(a, b)...)
Base.:&(a::Expr, b) = and(promote(a, b)...)
Base.:|(a::Expr, b) = or(promote(a, b)...)

"""
    col(name::String)::Polars.Expr

Returns an expression referencing a column in a dataframe. The special
column name `"*"` will select all columns in the dataframe.
"""
function col(name)
    expr = Ref{Ptr{polars_expr_t}}()
    err = polars_expr_col(name, length(name), expr)
    polars_error(err)
    return Expr(expr[])
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
    alias(expr::Polars.Expr, name::String)::Polars.Expr
    alias(alias::String)::Base.Fix2{typeof(alias), String}

Renames the result of this expression to a new name.
"""
function alias(expr, alias)
    out = Ref{Ptr{polars_expr_t}}()
    err = polars_expr_alias(expr, alias, length(alias), out)
    polars_error(err)
    return Expr(out[])
end
alias(new_name) = Base.Fix2(alias, new_name)

"""
    prefix(expr::Polars.Expr, prefix::String)::Polars.Expr
    prefix(prefix::String)::Base.Fix2{typeof(prefix), String}

Adds a prefix to the name of the resulting expression.
"""
function prefix(expr, pref)
    out = Ref{Ptr{polars_expr_t}}()
    err = polars_expr_prefix(expr, pref, length(pref), out)
    polars_error(err)
    return Expr(out[])
end
prefix(pref) = Base.Fix2(prefix, pref)

"""
    suffix(expr::Polars.Expr, suffix::String)::Polars.Expr
    suffix(suffix::String)::Base.Fix2{typeof(suffix), String}

Adds a suffix to the name of the resulting expression.
"""
function suffix(expr, suf)
    out = Ref{Ptr{polars_expr_t}}()
    err = polars_expr_suffix(expr, suf, length(suf), out)
    polars_error(err)
    return Expr(out[])
end
suffix(suf) = Base.Fix2(suffix, suf)

"""
    lit(x)::Polars.Expr

Transforms a literal value as an expression which will broadcast when used with other
expressions.
"""
function lit(v)
    return convert(Expr, v)
end

"""
    cast(expr::Polars.Expr, dtype::Type)::Polars.Expr
    cast(dtype::Type)::Base.Fix2{typeof(cast), ::Type}

Casts the series represented by the expression with provided the datatype.
"""
function cast(expr, dtype)
    value_type = if dtype == Missing
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
    else
        error("could not cast to type $dtype")
    end

    casted = API.polars_expr_cast(expr, value_type)
    return Expr(casted)
end
cast(dtype) = Base.Fix2(cast, dtype)

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

macro generate_expr_fns(ex)
    @assert ex.head === :block
    out = Base.Expr(:block)
    for call in ex.args
        call isa Base.Expr || continue
        cname = call.args[2]
        fname = last(last(call.args).args)
        if __module__ == Polars && isdefined(Base, fname)
            fname = Base.Expr(:(.), :Base, QuoteNode(fname))
        end
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
        # Export Expr symbols
        if fname isa Symbol # && __module__ != Polars
            namespace = string(first(last(call.args).args))
            namespace_type = namespace == "Expr" ? "enum" : "struct"
            rust_doc_url = "https://docs.rs/polars/latest/polars/prelude/$(namespace_type).$(namespace).html#method.$fname"
            string_sig = replace(string(sig), "Expr" => "Polars.Expr")
            docstring = """
                $(string_sig)::Polars.Expr

            Refer to [the polars documentation]($rust_doc_url).
            """
            push!(
                out.args, quote
                    Docs.@doc $docstring $(QuoteNode(fname))
                end
            )
            push!(out.args, :(export $fname))
        end
    end
    return esc(out)
end

# We just copy the rust code here and generate functions on the fly.
@generate_expr_fns begin
    gen_impl_expr!(polars_expr_keep_name, Expr::keep_name)

    gen_impl_expr!(polars_expr_sum, Expr::sum)
    gen_impl_expr!(polars_expr_mean, Expr::mean)
    gen_impl_expr!(polars_expr_median, Expr::median)
    gen_impl_expr!(polars_expr_min, Expr::min)
    gen_impl_expr!(polars_expr_max, Expr::max)
    gen_impl_expr!(polars_expr_arg_min, Expr::arg_min)
    gen_impl_expr!(polars_expr_arg_max, Expr::arg_max)
    gen_impl_expr!(polars_expr_nan_min, Expr::nan_min)
    gen_impl_expr!(polars_expr_nan_max, Expr::nan_max)

    gen_impl_expr!(polars_expr_floor, Expr::floor)
    gen_impl_expr!(polars_expr_ceil, Expr::ceil)
    gen_impl_expr!(polars_expr_abs, Expr::abs)
    gen_impl_expr!(polars_expr_cos, Expr::cos)
    gen_impl_expr!(polars_expr_sin, Expr::sin)
    gen_impl_expr!(polars_expr_tan, Expr::tan)
    gen_impl_expr!(polars_expr_cosh, Expr::cosh)
    gen_impl_expr!(polars_expr_sinh, Expr::sinh)
    gen_impl_expr!(polars_expr_tanh, Expr::tanh)

    gen_impl_expr!(polars_expr_sqrt, Expr::sqrt)
    gen_impl_expr!(polars_expr_sign, Expr::sign)
    gen_impl_expr!(polars_expr_exp, Expr::exp)

    gen_impl_expr!(polars_expr_n_unique, Expr::n_unique)
    gen_impl_expr!(polars_expr_unique, Expr::unique)
    gen_impl_expr!(polars_expr_is_duplicated, Expr::is_duplicated)
    gen_impl_expr!(polars_expr_is_unique, Expr::is_unique)
    gen_impl_expr!(polars_expr_count, Expr::count)
    gen_impl_expr!(polars_expr_first, Expr::first)
    gen_impl_expr!(polars_expr_last, Expr::last)

    gen_impl_expr!(polars_expr_not, Expr::not)
    gen_impl_expr!(polars_expr_is_finite, Expr::is_finite)
    gen_impl_expr!(polars_expr_is_infinite, Expr::is_infinite)
    gen_impl_expr!(polars_expr_is_nan, Expr::is_nan)
    gen_impl_expr!(polars_expr_is_null, Expr::is_null)
    gen_impl_expr!(polars_expr_is_not_null, Expr::is_not_null)
    gen_impl_expr!(polars_expr_null_count, Expr::null_count)
    gen_impl_expr!(polars_expr_drop_nans, Expr::drop_nans)
    gen_impl_expr!(polars_expr_drop_nulls, Expr::drop_nulls)

    gen_impl_expr!(polars_expr_implode, Expr::implode)
    gen_impl_expr!(polars_expr_flatten, Expr::flatten)
    gen_impl_expr!(polars_expr_reverse, Expr::reverse)

    gen_impl_expr_binary!(polars_expr_eq, Expr::eq)
    gen_impl_expr_binary!(polars_expr_lt, Expr::lt)
    gen_impl_expr_binary!(polars_expr_gt, Expr::gt)
    gen_impl_expr_binary!(polars_expr_or, Expr::or)
    gen_impl_expr_binary!(polars_expr_xor, Expr::xor)
    gen_impl_expr_binary!(polars_expr_and, Expr::and)

    gen_impl_expr_binary!(polars_expr_pow, Expr::pow)
    gen_impl_expr_binary!(polars_expr_add, Expr::add)
    gen_impl_expr_binary!(polars_expr_sub, Expr::sub)
    gen_impl_expr_binary!(polars_expr_mul, Expr::mul)
    gen_impl_expr_binary!(polars_expr_div, Expr::div)

    gen_impl_expr_binary!(polars_expr_fill_null, Expr::fill_null)
    gen_impl_expr_binary!(polars_expr_fill_nan, Expr::fill_nan)
    gen_impl_expr_binary!(polars_expr_is_in, Expr::is_in)

    gen_impl_expr_binary!(polars_expr_shift, Expr::shift)
    gen_impl_expr_binary!(polars_expr_pct_change, Expr::pct_change)

    gen_impl_expr_binary!(polars_expr_log, Expr::log)
    gen_impl_expr_binary!(polars_expr_rem, Expr::rem)
end

# Curried (Fix2-style) forms for the binary namespace-free ops above that have no natural
# operator equivalent (unlike +/-/*//, which already read fluently as infix). Each promotes a
# literal second argument via `convert(Expr, ...)`, matching Python polars' `.is_in([1,2,3])`,
# `.fill_null(0)`, etc. `log`/`rem` (and, elsewhere, `replace`/`diff`) are deliberately excluded --
# not because of dispatch ambiguity (Julia always prefers Base's existing concrete-type methods,
# e.g. `log(::Float64)`, over anything added here, so no ambiguity error would ever occur), but
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
with via `isdefined(Base, :product)`). This matches the `Base.sum`/`Base.mean` precedent: since
`prod` is an exported Base name, plain `prod(expr)` resolves here with no qualification needed,
unlike the `Base.product(...)`-qualification this used to require.
"""
Base.prod(expr::Expr) = Expr(API.polars_expr_product(expr))

"""
    std(expr::Polars.Expr; ddof::Integer=1)::Polars.Expr

Standard deviation of the values, with `ddof` degrees of freedom subtracted (defaults to
`ddof=1`, matching `Statistics.std`).
"""
function std(expr::Expr; ddof::Integer = 1)
    out = API.polars_expr_std(expr, UInt8(ddof))
    return Expr(out)
end

"""
    var(expr::Polars.Expr; ddof::Integer=1)::Polars.Expr

Variance of the values, with `ddof` degrees of freedom subtracted (defaults to `ddof=1`,
matching `Statistics.var`).
"""
function var(expr::Expr; ddof::Integer = 1)
    out = API.polars_expr_var(expr, UInt8(ddof))
    return Expr(out)
end

"""
    quantile(expr::Polars.Expr, q; method::Symbol=:nearest)::Polars.Expr

Computes the `q`-th quantile (`q` an `Expr` or a numeric literal in `[0, 1]`) of the values,
using the given interpolation `method`: one of `:nearest` (default), `:lower`, `:higher`,
`:midpoint`, `:linear`, `:equiprobable`.
"""
function quantile(expr::Expr, q; method::Symbol = :nearest)
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

"""
    quantile(q; method::Symbol=:nearest)::Base.Callable

Curried form of [`quantile`](@ref) for use with `|>` -- e.g. `col("x") |> quantile(0.5)`.
"""
quantile(q; method::Symbol = :nearest) = expr -> quantile(expr, q; method = method)

export std, var, quantile

"""
    over(expr::Polars.Expr, partition_by...)::Polars.Expr

Applies `expr` within groups defined by `partition_by` (columns or expressions), broadcasting
the per-group result back over every row of that group — e.g. `sum(col("x")) |> over("g")`
returns, per row, the sum of `x` within that row's `g` group.
"""
function over(expr::Expr, partition_by...)
    partition_by = map(ex -> ex isa String ? col(ex) : ex, partition_by)
    partition_by = convert(Vector{Expr}, collect(partition_by))
    GC.@preserve partition_by begin
        partition_ptrs = Ptr{polars_expr_t}[p.ptr for p in partition_by]
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_over(expr, partition_ptrs, length(partition_ptrs), out)
        polars_error(err)
    end
    return Expr(out[])
end

"""
    over(partition_by::String...)::Base.Callable

Curried form of [`over`](@ref) for use with `|>`, mirroring Python polars' `.over("g")` — e.g.
`sum(col("x")) |> over("g")`. Only accepts column-name strings, not `Expr` partition keys (an
`Expr` argument is ambiguous with `over`'s own `expr` argument and always resolves to that
instead); for expression-valued partition keys, call `over(expr, partition_by...)` directly.
"""
over(partition_by::String...) = expr -> over(expr, partition_by...)

export over

"""
    sort_by(expr::Polars.Expr, by...; rev=false, nulls_last::Bool=false, maintain_order::Bool=false)::Polars.Expr

Sorts the values of `expr` according to `by` (columns or expressions), rather than by `expr`'s
own values -- typically used inside [`over`](@ref)/[`agg`](@ref) for "most recent row per group",
"top N per group", etc. `rev` is either a single `Bool` (applied to every `by` expression) or a
`Vector{Bool}` the same length as `by`.
"""
function sort_by(expr::Expr, by...; rev = false, nulls_last::Bool = false, maintain_order::Bool = false)
    by = map(ex -> ex isa String ? col(ex) : ex, by)
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
    sort_by(by::String...; rev=false, nulls_last::Bool=false, maintain_order::Bool=false)::Base.Callable

Curried form of [`sort_by`](@ref) for use with `|>` — e.g. `col("x") |> sort_by("y"; rev=true)`.
Only accepts column-name strings, not `Expr` by-keys (an `Expr` argument is ambiguous with
`sort_by`'s own `expr` argument and always resolves to that instead); for expression-valued
by-keys, call `sort_by(expr, by...; kwargs...)` directly.
"""
function sort_by(by::String...; rev = false, nulls_last::Bool = false, maintain_order::Bool = false)
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
    err = API.polars_expr_value_counts(expr, sort, parallel, name, length(name), normalize, out)
    polars_error(err)
    return Expr(out[])
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

export rank

module Lists
    using ..Polars: @generate_expr_fns, API, polars_expr_t, Expr

    @generate_expr_fns begin
        gen_impl_expr_list!(polars_expr_list_lengths, ListNameSpace::lengths)
        gen_impl_expr_list!(polars_expr_list_max, ListNameSpace::max)
        gen_impl_expr_list!(polars_expr_list_min, ListNameSpace::min)
        gen_impl_expr_list!(polars_expr_list_arg_max, ListNameSpace::arg_max)
        gen_impl_expr_list!(polars_expr_list_arg_min, ListNameSpace::arg_min)
        gen_impl_expr_list!(polars_expr_list_sum, ListNameSpace::sum)
        gen_impl_expr_list!(polars_expr_list_mean, ListNameSpace::mean)
        gen_impl_expr_list!(polars_expr_list_reverse, ListNameSpace::reverse)
        gen_impl_expr_list!(polars_expr_list_unique, ListNameSpace::unique)
        gen_impl_expr_list!(polars_expr_list_unique_stable, ListNameSpace::unique_stable)
        gen_impl_expr_list!(polars_expr_list_first, ListNameSpace::first)
        gen_impl_expr_list!(polars_expr_list_last, ListNameSpace::last)

        gen_impl_expr_binary_list!(polars_expr_list_head, ListNameSpace::head)
    end

    """
        head(n)::Base.Fix2{typeof(head)}

    Curried form of `head` for use with `|>` -- e.g. `col("x") |> Lists.head(2)`.
    """
    head(n) = Base.Fix2(head, convert(Expr, n))

    """
        get(expr::Polars.Expr, index::Polars.Expr; null_on_oob::Bool=false)::Polars.Expr

    Get items in every sublist by index. If `null_on_oob` is `false` (default), an
    out-of-bounds index raises an error; if `true`, it returns `null` instead (more
    expensive, per the polars documentation).
    """
    function get(expr::Expr, index::Expr; null_on_oob::Bool = false)
        out = API.polars_expr_list_get(expr, index, null_on_oob)
        return Expr(out)
    end

    """
        get(index; null_on_oob::Bool=false)::Base.Callable

    Curried form of [`get`](@ref) for use with `|>` -- e.g. `col("x") |> Lists.get(0)`.
    """
    get(index; null_on_oob::Bool = false) = expr -> get(expr, convert(Expr, index); null_on_oob)

    """
        contains(expr::Polars.Expr, other::Polars.Expr; nulls_equal::Bool=true)::Polars.Expr

    Check if the list array contains an element. If `nulls_equal` is `true` (default),
    `null` values are considered equal for the containment check.
    """
    function contains(expr::Expr, other::Expr; nulls_equal::Bool = true)
        out = API.polars_expr_list_contains(expr, other, nulls_equal)
        return Expr(out)
    end

    """
        contains(other; nulls_equal::Bool=true)::Base.Callable

    Curried form of [`contains`](@ref) for use with `|>`.
    """
    contains(other; nulls_equal::Bool = true) = expr -> contains(expr, convert(Expr, other); nulls_equal)

    export get, contains, head
end # module Lists

module Strings
    using ..Polars: @generate_expr_fns, API, polars_expr_t, Expr, polars_error

    @generate_expr_fns begin
        gen_impl_expr_str!(polars_expr_str_to_uppercase, StringNameSpace::uppercase)
        gen_impl_expr_str!(polars_expr_str_to_lowercase, StringNameSpace::lowercase)
        gen_impl_expr_str!(polars_expr_str_to_titlecase, StringNameSpace::titlecase)
        gen_impl_expr_str!(polars_expr_str_len_bytes, StringNameSpace::len_bytes)
        gen_impl_expr_str!(polars_expr_str_len_chars, StringNameSpace::len_chars)
        # gen_impl_expr_str!(polars_expr_str_explode, StringNameSpace::explode)

        gen_impl_expr_binary_str!(polars_expr_str_starts_with, StringNameSpace::starts_with)
        gen_impl_expr_binary_str!(polars_expr_str_ends_with, StringNameSpace::ends_with)
        gen_impl_expr_binary_str!(
            polars_expr_str_contains_literal,
            StringNameSpace::contains_literal
        )

        gen_impl_expr_binary_str!(polars_expr_str_strip_chars, StringNameSpace::strip_chars)
        gen_impl_expr_binary_str!(polars_expr_str_strip_prefix, StringNameSpace::strip_prefix)
        gen_impl_expr_binary_str!(polars_expr_str_strip_suffix, StringNameSpace::strip_suffix)
        gen_impl_expr_binary_str!(polars_expr_str_split, StringNameSpace::split)
        gen_impl_expr_binary_str!(polars_expr_str_extract_all, StringNameSpace::extract_all)
        gen_impl_expr_binary_str!(polars_expr_str_zfill, StringNameSpace::zfill)
        gen_impl_expr_binary_str!(polars_expr_str_head, StringNameSpace::head)
        gen_impl_expr_binary_str!(polars_expr_str_tail, StringNameSpace::tail)
    end

    # Curried (Fix2-style) forms for the binary namespace ops above, e.g.
    # `col("s") |> Strings.starts_with("foo")`, mirroring Python polars' fluent `.starts_with(...)`.
    starts_with(pat) = Base.Fix2(starts_with, convert(Expr, pat))
    ends_with(pat) = Base.Fix2(ends_with, convert(Expr, pat))
    contains_literal(pat) = Base.Fix2(contains_literal, convert(Expr, pat))
    strip_chars(matches) = Base.Fix2(strip_chars, convert(Expr, matches))
    strip_prefix(prefix) = Base.Fix2(strip_prefix, convert(Expr, prefix))
    strip_suffix(suffix) = Base.Fix2(strip_suffix, convert(Expr, suffix))
    split(by) = Base.Fix2(split, convert(Expr, by))
    extract_all(pat) = Base.Fix2(extract_all, convert(Expr, pat))
    zfill(len) = Base.Fix2(zfill, convert(Expr, len))
    head(n) = Base.Fix2(head, convert(Expr, n))
    tail(n) = Base.Fix2(tail, convert(Expr, n))

    """
        contains(expr::Polars.Expr, pat::Polars.Expr; strict::Bool=true)::Polars.Expr

    Check if the string contains a match for the regex `pat`. If `strict` is `true` (default),
    an invalid regex raises an error; if `false`, it returns `null` instead. For a plain
    substring (non-regex) check, use [`contains_literal`](@ref).
    """
    function contains(expr::Expr, pat::Expr; strict::Bool = true)
        out = API.polars_expr_str_contains(expr, pat, strict)
        return Expr(out)
    end

    """
        contains(pat; strict::Bool=true)::Base.Callable

    Curried form of [`contains`](@ref) for use with `|>`.
    """
    contains(pat; strict::Bool = true) = expr -> contains(expr, convert(Expr, pat); strict)

    """
        slice(expr::Polars.Expr, offset::Polars.Expr, length::Polars.Expr)::Polars.Expr

    Extracts a substring starting at `offset` (0-indexed; negative indexes from the end) with
    the given `length` (extends to the end of the string if `length` is `null`).
    """
    function slice(expr::Expr, offset::Expr, length::Expr)
        out = API.polars_expr_str_slice(expr, offset, length)
        return Expr(out)
    end

    """
        slice(offset, length)::Base.Callable

    Curried form of [`slice`](@ref) for use with `|>`.
    """
    slice(offset, length) = expr -> slice(expr, convert(Expr, offset), convert(Expr, length))

    """
        replace(expr::Polars.Expr, pat::Polars.Expr, value::Polars.Expr; literal::Bool=false)::Polars.Expr

    Replaces the first match of `pat` with `value`. If `literal` is `true`, `pat` is treated as
    a plain substring rather than a regex.
    """
    function replace(expr::Expr, pat::Expr, value::Expr; literal::Bool = false)
        out = API.polars_expr_str_replace(expr, pat, value, literal)
        return Expr(out)
    end

    """
        replace(pat, value; literal::Bool=false)::Base.Callable

    Curried form of [`replace`](@ref) for use with `|>`.
    """
    function replace(pat, value; literal::Bool = false)
        return expr -> replace(expr, convert(Expr, pat), convert(Expr, value); literal)
    end

    """
        replace_all(expr::Polars.Expr, pat::Polars.Expr, value::Polars.Expr; literal::Bool=false)::Polars.Expr

    Replaces all matches of `pat` with `value`. If `literal` is `true`, `pat` is treated as a
    plain substring rather than a regex.
    """
    function replace_all(expr::Expr, pat::Expr, value::Expr; literal::Bool = false)
        out = API.polars_expr_str_replace_all(expr, pat, value, literal)
        return Expr(out)
    end

    """
        replace_all(pat, value; literal::Bool=false)::Base.Callable

    Curried form of [`replace_all`](@ref) for use with `|>`.
    """
    function replace_all(pat, value; literal::Bool = false)
        return expr -> replace_all(expr, convert(Expr, pat), convert(Expr, value); literal)
    end

    """
        extract(expr::Polars.Expr, pat::Polars.Expr, group_index::Integer)::Polars.Expr

    Extracts the capture group numbered `group_index` (0 = the whole match) from the first
    match of the regex `pat`.
    """
    function extract(expr::Expr, pat::Expr, group_index::Integer)
        out = API.polars_expr_str_extract(expr, pat, group_index)
        return Expr(out)
    end

    """
        extract(pat, group_index::Integer)::Base.Callable

    Curried form of [`extract`](@ref) for use with `|>`.
    """
    extract(pat, group_index::Integer) = expr -> extract(expr, convert(Expr, pat), group_index)

    """
        count_matches(expr::Polars.Expr, pat::Polars.Expr; literal::Bool=false)::Polars.Expr

    Counts the number of non-overlapping matches of `pat`. If `literal` is `true`, `pat` is
    treated as a plain substring rather than a regex.
    """
    function count_matches(expr::Expr, pat::Expr; literal::Bool = false)
        out = API.polars_expr_str_count_matches(expr, pat, literal)
        return Expr(out)
    end

    """
        count_matches(pat; literal::Bool=false)::Base.Callable

    Curried form of [`count_matches`](@ref) for use with `|>`.
    """
    count_matches(pat; literal::Bool = false) = expr -> count_matches(expr, convert(Expr, pat); literal)

    """
        to_date(expr::Polars.Expr; format::Union{Nothing,String}=nothing, strict::Bool=true,
                exact::Bool=true)::Polars.Expr

    Parses a String column into a `Date`. `format` is a `chrono`-style format string (e.g.
    `"%Y-%m-%d"`); if not given, polars attempts to infer it. If `strict` is `true` (default),
    a value that fails to parse raises an error; if `false`, it becomes `null`. If `exact` is
    `true` (default), the entire string must match `format`.
    """
    function to_date(expr::Expr; format::Union{Nothing, String} = nothing, strict::Bool = true, exact::Bool = true)
        format_str = something(format, "")
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_str_to_date(expr, format_str, length(format_str), strict, exact, out)
        polars_error(err)
        return Expr(out[])
    end

    """
        to_datetime(expr::Polars.Expr; format::Union{Nothing,String}=nothing,
                    time_unit::Symbol=:us, strict::Bool=true, exact::Bool=true)::Polars.Expr

    Parses a String column into a `Datetime`. `time_unit` is one of `:ns`, `:us` (default),
    `:ms`. See [`to_date`](@ref) for `format`/`strict`/`exact`.
    """
    function to_datetime(
            expr::Expr; format::Union{Nothing, String} = nothing, time_unit::Symbol = :us,
            strict::Bool = true, exact::Bool = true
        )
        time_unit_enum = if time_unit == :ns
            API.PolarsTimeUnitNanosecond
        elseif time_unit == :us
            API.PolarsTimeUnitMicrosecond
        elseif time_unit == :ms
            API.PolarsTimeUnitMillisecond
        else
            error("unknown time_unit $time_unit, expected one of (:ns, :us, :ms)")
        end
        format_str = something(format, "")
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_str_to_datetime(
            expr, format_str, length(format_str), time_unit_enum, strict, exact, out
        )
        polars_error(err)
        return Expr(out[])
    end

    export contains, slice, replace, replace_all, extract, count_matches, to_date, to_datetime
end # module Strings

module Dt
    using ..Polars: @generate_expr_fns, API, polars_expr_t, Expr, polars_error

    @generate_expr_fns begin
        gen_impl_expr_dt!(polars_expr_dt_year, DateLikeNameSpace::year)
        gen_impl_expr_dt!(polars_expr_dt_month, DateLikeNameSpace::month)
        gen_impl_expr_dt!(polars_expr_dt_day, DateLikeNameSpace::day)
        gen_impl_expr_dt!(polars_expr_dt_hour, DateLikeNameSpace::hour)
        gen_impl_expr_dt!(polars_expr_dt_minute, DateLikeNameSpace::minute)
        gen_impl_expr_dt!(polars_expr_dt_second, DateLikeNameSpace::second)
        gen_impl_expr_dt!(polars_expr_dt_weekday, DateLikeNameSpace::weekday)
        gen_impl_expr_dt!(polars_expr_dt_ordinal_day, DateLikeNameSpace::ordinal_day)

        gen_impl_expr_binary_dt!(polars_expr_dt_truncate, DateLikeNameSpace::truncate)
        gen_impl_expr_binary_dt!(polars_expr_dt_round, DateLikeNameSpace::round)
        gen_impl_expr_binary_dt!(polars_expr_dt_offset_by, DateLikeNameSpace::offset_by)
    end

    # Curried (Fix2-style) forms, e.g. `col("d") |> Dt.truncate("1mo")`.
    truncate(every) = Base.Fix2(truncate, convert(Expr, every))
    round(every) = Base.Fix2(round, convert(Expr, every))
    offset_by(by) = Base.Fix2(offset_by, convert(Expr, by))

    """
        strftime(expr::Polars.Expr, format::String)::Polars.Expr

    Formats a Date/Datetime/Duration/Time expression using a `chrono`-style format string
    (e.g. `"%Y-%m-%d"`).
    """
    function strftime(expr::Expr, format::AbstractString)
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_dt_strftime(expr, format, length(format), out)
        polars_error(err)
        return Expr(out[])
    end

    """
        strftime(format::String)::Base.Fix2{typeof(strftime), String}

    Curried form of [`strftime`](@ref) for use with `|>`.
    """
    strftime(format::AbstractString) = Base.Fix2(strftime, format)

    export strftime
end # module Dt

module Structs
    using ..Polars: Expr, API

    """
        field_by_name(expr::Polars.Expr, name::String)::Polars.Expr
        field_by_name(name::String)::Base.Fix2{typeof(field_by_name), String}

    Returns a new series corresponding to values of the selected field.
    """
    function field_by_name(expr, name)
        field = API.polars_expr_struct_field_by_name(expr, name, length(name))
        return Expr(field)
    end
    field_by_name(name) = Base.Fix2(field_by_name, name)

    """
        field_by_index(expr::Polars.Expr, index::Integer)::Polars.Expr
        field_by_index(index::Integer)::Base.Fix2{typeof(field_by_index), Integer}

    Returns a new series corresponding to values of the selected field.
    """
    function field_by_index(expr, fieldidx)
        field = API.polars_expr_struct_field_by_index(expr, fieldidx)
        return Expr(field)
    end
    field_by_index(fieldidx) = Base.Fix2(field_by_index, fieldidx)

    """
        rename_fields(expr::Polars.Expr, new_names::Vector{String})::Polars.Expr
        rename_fields(new_names::Vector{String})::Base.Fix2{typeof(rename_fields), Vector{String}}

    Renames the fields of the struct series with the provided new names.
    """
    function rename_fields(expr, new_names)
        new_names = convert(Vector{String}, new_names)
        new_struct = API.polars_expr_struct_rename_fields(expr, new_names, length.(new_names), length(new_names))
        @assert new_struct != C_NULL "failed to rename fields"
        return Expr(new_struct)
    end
    rename_fields(new_names) = Base.Fix2(rename_fields, new_names)

    export field_by_name, field_by_index, rename_fields

end # module Structs

export col, alias, prefix, suffix, lit, cast, when, element,
    Lists, Strings, Dt, Structs
