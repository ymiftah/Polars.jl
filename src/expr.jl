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
    gen_impl_expr!(polars_expr_product, Expr::product)
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

export replace_strict

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

export over

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
without any extra qualification (unlike e.g. `Base.product`, `diff` is an *exported* Base name).
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
        contains(expr::Polars.Expr, other::Polars.Expr; nulls_equal::Bool=true)::Polars.Expr

    Check if the list array contains an element. If `nulls_equal` is `true` (default),
    `null` values are considered equal for the containment check.
    """
    function contains(expr::Expr, other::Expr; nulls_equal::Bool = true)
        out = API.polars_expr_list_contains(expr, other, nulls_equal)
        return Expr(out)
    end

    export get, contains
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
        slice(expr::Polars.Expr, offset::Polars.Expr, length::Polars.Expr)::Polars.Expr

    Extracts a substring starting at `offset` (0-indexed; negative indexes from the end) with
    the given `length` (extends to the end of the string if `length` is `null`).
    """
    function slice(expr::Expr, offset::Expr, length::Expr)
        out = API.polars_expr_str_slice(expr, offset, length)
        return Expr(out)
    end

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
        replace_all(expr::Polars.Expr, pat::Polars.Expr, value::Polars.Expr; literal::Bool=false)::Polars.Expr

    Replaces all matches of `pat` with `value`. If `literal` is `true`, `pat` is treated as a
    plain substring rather than a regex.
    """
    function replace_all(expr::Expr, pat::Expr, value::Expr; literal::Bool = false)
        out = API.polars_expr_str_replace_all(expr, pat, value, literal)
        return Expr(out)
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
        count_matches(expr::Polars.Expr, pat::Polars.Expr; literal::Bool=false)::Polars.Expr

    Counts the number of non-overlapping matches of `pat`. If `literal` is `true`, `pat` is
    treated as a plain substring rather than a regex.
    """
    function count_matches(expr::Expr, pat::Expr; literal::Bool = false)
        out = API.polars_expr_str_count_matches(expr, pat, literal)
        return Expr(out)
    end

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

export col, alias, prefix, suffix, lit, cast, when,
    Lists, Strings, Dt, Structs
