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
    to_date(; format::Union{Nothing,String}=nothing, strict::Bool=true, exact::Bool=true)::Base.Callable

Curried form of [`to_date`](@ref) for use with `|>`.
"""
function to_date(; format::Union{Nothing, String} = nothing, strict::Bool = true, exact::Bool = true)
    return expr -> to_date(expr; format, strict, exact)
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

"""
    to_datetime(; format::Union{Nothing,String}=nothing, time_unit::Symbol=:us,
                strict::Bool=true, exact::Bool=true)::Base.Callable

Curried form of [`to_datetime`](@ref) for use with `|>`.
"""
function to_datetime(
        ; format::Union{Nothing, String} = nothing, time_unit::Symbol = :us,
        strict::Bool = true, exact::Bool = true
    )
    return expr -> to_datetime(expr; format, time_unit, strict, exact)
end

export contains, slice, replace, replace_all, extract, count_matches, to_date, to_datetime
end # module Strings
