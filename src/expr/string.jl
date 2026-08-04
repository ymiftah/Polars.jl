module Strings
using ..Polars: @generate_expr_fns, API, polars_expr_t, Expr, polars_error

@generate_expr_fns begin
    gen_impl_expr_str!(polars_expr_str_to_uppercase, StringNameSpace::uppercase, "Converts each string of `expr` to uppercase.")
    gen_impl_expr_str!(polars_expr_str_to_lowercase, StringNameSpace::lowercase, "Converts each string of `expr` to lowercase.")
    gen_impl_expr_str!(polars_expr_str_len_bytes, StringNameSpace::len_bytes, "Length of each string of `expr`, in bytes. Differs from [`len_chars`](@ref) for non-ASCII text (a multi-byte UTF-8 character counts as more than one byte but one char).")
    gen_impl_expr_str!(polars_expr_str_len_chars, StringNameSpace::len_chars, "Length of each string of `expr`, in Unicode characters. Differs from [`len_bytes`](@ref) for non-ASCII text.")
    # gen_impl_expr_str!(polars_expr_str_explode, StringNameSpace::explode)

    gen_impl_expr_binary_str!(polars_expr_str_starts_with, StringNameSpace::starts_with, "Row-wise boolean flag: `true` where `a` starts with the literal (non-regex) substring `b`.\n\n!!! note \"Has a curried form\"\n    `starts_with(pat)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_str!(polars_expr_str_ends_with, StringNameSpace::ends_with, "Row-wise boolean flag: `true` where `a` ends with the literal (non-regex) substring `b`.\n\n!!! note \"Has a curried form\"\n    `ends_with(pat)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_str!(
        polars_expr_str_contains_literal,
        StringNameSpace::contains_literal,
        "Row-wise boolean flag: `true` where `a` contains the literal (non-regex) substring `b`. For a regex match, use [`contains`](@ref).\n\n!!! note \"Has a curried form\"\n    `contains_literal(pat)` -- see [Curried forms for pipe-based composition](@ref)."
    )

    gen_impl_expr_binary_str!(polars_expr_str_strip_chars, StringNameSpace::strip_chars, "Removes any leading/trailing characters of `a` that appear in `b` (a string of characters to strip, not a substring to match).\n\n!!! note \"Has a curried form\"\n    `strip_chars(chars)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_str!(polars_expr_str_strip_chars_start, StringNameSpace::strip_chars_start, "Like [`strip_chars`](@ref), but only strips leading characters.\n\n!!! note \"Has a curried form\"\n    `strip_chars_start(chars)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_str!(polars_expr_str_strip_chars_end, StringNameSpace::strip_chars_end, "Like [`strip_chars`](@ref), but only strips trailing characters.\n\n!!! note \"Has a curried form\"\n    `strip_chars_end(chars)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_str!(polars_expr_str_strip_prefix, StringNameSpace::strip_prefix, "Removes the literal prefix `b` from `a` if present (no-op otherwise).\n\n!!! note \"Has a curried form\"\n    `strip_prefix(prefix)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_str!(polars_expr_str_strip_suffix, StringNameSpace::strip_suffix, "Removes the literal suffix `b` from `a` if present (no-op otherwise).\n\n!!! note \"Has a curried form\"\n    `strip_suffix(suffix)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_str!(polars_expr_str_split, StringNameSpace::split, "Splits each string of `a` on the literal (non-regex) substring `b`, returning a `List` of substrings (see [List](@ref expr-list)).\n\n!!! note \"Has a curried form\"\n    `split(by)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_str!(polars_expr_str_extract_all, StringNameSpace::extract_all, "Extracts every non-overlapping match of the regex `b` from `a`, returning a `List` of matches per row (see [List](@ref expr-list)).\n\n!!! note \"Has a curried form\"\n    `extract_all(pat)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_str!(polars_expr_str_zfill, StringNameSpace::zfill, "Left-pads each string of `a` with `'0'` up to a total width of `b` characters (a leading `+`/`-` sign, if present, stays before the padding).\n\n!!! note \"Has a curried form\"\n    `zfill(width)` -- see [Curried forms for pipe-based composition](@ref).")
end

# `head`/`tail` are pulled out of the `@generate_expr_fns` block (rather than generated via
# `gen_impl_expr_binary_str!`, like the other binary ops above) because they collide with
# `Polars`'s own top-level `head`/`tail` (for `DataFrame`/`LazyFrame`) -- not Base names, so the
# macro's own Base-collision check can't catch them, and they must never be exported: designed for
# qualified use (`Strings.head`), matching `contains`/`replace` below.
"""
    head(expr::Polars.Expr, n::Polars.Expr)::Polars.Expr

First `n` characters of each string in `expr` (negative `n` keeps all but the last `|n|`
characters; fewer than `n` characters if the string is shorter).
"""
function head(a::Expr, b::Expr)
    out = API.polars_expr_str_head(a, b)
    return Expr(out)
end

"""
    tail(expr::Polars.Expr, n::Polars.Expr)::Polars.Expr

Last `n` characters of each string in `expr` (negative `n` skips the first `|n|` characters
instead; fewer than `n` characters if the string is shorter).
"""
function tail(a::Expr, b::Expr)
    out = API.polars_expr_str_tail(a, b)
    return Expr(out)
end

"""
    titlecase(expr::Polars.Expr)

!!! warning "Unavailable in a default build"
    See [Developer](@ref) for why, and how to enable it.
"""
function titlecase(::Expr)
    return error(
        "Strings.titlecase is unavailable in this build: polars' `to_titlecase` requires " *
            "polars' `nightly` Cargo feature and a nightly rustc, while c-polars pins a stable " *
            "toolchain. Rebuild with `cargo build --features nightly` to enable it."
    )
end

# Curried (Fix2-style) forms for the binary namespace ops above, e.g.
# `col("s") |> Strings.starts_with("foo")`, mirroring Python polars' fluent `.starts_with(...)`.
starts_with(pat) = Base.Fix2(starts_with, convert(Expr, pat))
ends_with(pat) = Base.Fix2(ends_with, convert(Expr, pat))
contains_literal(pat) = Base.Fix2(contains_literal, convert(Expr, pat))
strip_chars(matches) = Base.Fix2(strip_chars, convert(Expr, matches))
strip_chars_start(matches) = Base.Fix2(strip_chars_start, convert(Expr, matches))
strip_chars_end(matches) = Base.Fix2(strip_chars_end, convert(Expr, matches))
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
    find(expr::Polars.Expr, pat::Polars.Expr; strict::Bool=true)::Polars.Expr

Index of the start of the first match of the regex `pat` in each string of `expr` (`null` if
there is no match). If `strict` is `true` (default), an invalid regex raises an error; if
`false`, it returns `null` instead. For a plain substring (non-regex) search, build the
literal-search equivalent via [`contains_literal`](@ref) instead.
"""
function find(expr::Expr, pat::Expr; strict::Bool = true)
    out = API.polars_expr_str_find(expr, pat, strict)
    return Expr(out)
end

"""
    find(pat; strict::Bool=true)::Base.Callable

Curried form of [`find`](@ref) for use with `|>`.
"""
find(pat; strict::Bool = true) = expr -> find(expr, convert(Expr, pat); strict)

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
    pad_start(expr::Polars.Expr, length; fill_char::Char=' ')::Polars.Expr

Pads each string of `expr` on the left with `fill_char` until it reaches `length` characters
(no-op for a string already at least that long). `length` is an integer literal or an
expression (e.g. another column), giving a per-row target length.
"""
function pad_start(expr::Expr, length; fill_char::Char = ' ')
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_str_pad_start(expr, convert(Expr, length), codepoint(fill_char), out)
    polars_error(err)
    return Expr(out[])
end

"""
    pad_start(length; fill_char::Char=' ')::Base.Callable

Curried form of [`pad_start`](@ref) for use with `|>`.
"""
pad_start(length; fill_char::Char = ' ') = expr -> pad_start(expr, length; fill_char)

"""
    pad_end(expr::Polars.Expr, length; fill_char::Char=' ')::Polars.Expr

Pads each string of `expr` on the right with `fill_char` until it reaches `length` characters
(no-op for a string already at least that long). `length` is an integer literal or an
expression (e.g. another column), giving a per-row target length.
"""
function pad_end(expr::Expr, length; fill_char::Char = ' ')
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_str_pad_end(expr, convert(Expr, length), codepoint(fill_char), out)
    polars_error(err)
    return Expr(out[])
end

"""
    pad_end(length; fill_char::Char=' ')::Base.Callable

Curried form of [`pad_end`](@ref) for use with `|>`.
"""
pad_end(length; fill_char::Char = ' ') = expr -> pad_end(expr, length; fill_char)

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
    err = API.polars_expr_str_to_date(expr, format_str, ncodeunits(format_str), strict, exact, out)
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
        expr, format_str, ncodeunits(format_str), time_unit_enum, strict, exact, out
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

"""
    replace_n(expr::Polars.Expr, pat::Polars.Expr, value::Polars.Expr, n::Integer; literal::Bool=false)::Polars.Expr

Replaces the first `n` matches of `pat` with `value` (a negative `n` behaves like
[`replace_all`](@ref)). If `literal` is `true`, `pat` is treated as a plain substring rather than
a regex.
"""
function replace_n(expr::Expr, pat::Expr, value::Expr, n::Integer; literal::Bool = false)
    out = API.polars_expr_str_replace_n(expr, pat, value, literal, Int64(n))
    return Expr(out)
end

"""
    replace_n(pat, value, n::Integer; literal::Bool=false)::Base.Callable

Curried form of [`replace_n`](@ref) for use with `|>`.
"""
function replace_n(pat, value, n::Integer; literal::Bool = false)
    return expr -> replace_n(expr, convert(Expr, pat), convert(Expr, value), n; literal)
end

"""
    splitn(expr::Polars.Expr, by::Polars.Expr, n::Integer)::Polars.Expr

Splits each string of `expr` on the literal substring `by` into a `Struct` (see
[Struct](@ref expr-struct)) of exactly `n` fields -- if more than `n-1` splits are possible, the
remainder of the string is kept intact in the final field. Distinct from the `List`-returning
[`split`](@ref), which returns a variable number of pieces.
"""
function splitn(expr::Expr, by::Expr, n::Integer)
    out = API.polars_expr_str_splitn(expr, by, Csize_t(n))
    return Expr(out)
end

"""
    splitn(by, n::Integer)::Base.Callable

Curried form of [`splitn`](@ref) for use with `|>`.
"""
splitn(by, n::Integer) = expr -> splitn(expr, convert(Expr, by), n)

"""
    split_exact(expr::Polars.Expr, by::Polars.Expr, n::Integer)::Polars.Expr

Splits each string of `expr` on the literal substring `by` into a `Struct` (see
[Struct](@ref expr-struct)) of exactly `n + 1` fields, from exactly `n` split points -- if fewer
than `n` splits are possible, the missing trailing fields get `missing` (unlike [`splitn`](@ref),
which instead keeps the remainder intact in its final field and produces `n` fields total, not
`n + 1`).
"""
function split_exact(expr::Expr, by::Expr, n::Integer)
    out = API.polars_expr_str_split_exact(expr, by, Csize_t(n))
    return Expr(out)
end

"""
    split_exact(by, n::Integer)::Base.Callable

Curried form of [`split_exact`](@ref) for use with `|>`.
"""
split_exact(by, n::Integer) = expr -> split_exact(expr, convert(Expr, by), n)

"""
    join(expr::Polars.Expr, delimiter::AbstractString; ignore_nulls::Bool=true)::Polars.Expr

Aggregates every string value of `expr` (across *all* rows, or per group inside `agg`) into a
single value, joined by `delimiter`. If `ignore_nulls` is `true` (default), `null` values are
skipped; if `false`, any `null` poisons the whole result to `null`. Distinct from
[`Lists.join`](@ref) (joins each row's own list independently, not an aggregation across rows).
"""
function join(expr::Expr, delimiter::AbstractString; ignore_nulls::Bool = true)
    delimiter = String(delimiter)
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_str_join(expr, delimiter, ncodeunits(delimiter), ignore_nulls, out)
    polars_error(err)
    return Expr(out[])
end

"""
    to_integer(expr::Polars.Expr; base::Integer=10, strict::Bool=true)::Polars.Expr

!!! warning "Unavailable in this build"
    See [Developer](@ref) for why, and how to enable it.
"""
function to_integer(::Expr; base::Integer = 10, strict::Bool = true)
    return error(
        "Strings.to_integer is unavailable in this build: polars' `to_integer` requires " *
            "the `string_to_integer` Cargo feature, which c-polars does not currently " *
            "enable. Add it to c-polars/Cargo.toml's `polars` feature list and rebuild to " *
            "enable it."
    )
end

"""
    extract_groups(expr::Polars.Expr, pat::AbstractString)::Polars.Expr

Extracts every named capture group of the regex `pat` from the first match within each string of
`expr`, into a `Struct` (see [Struct](@ref expr-struct)) with one field per named group. `pat`
must be a plain string (not an `Expr`): the regex is compiled once, at plan time, to determine the
output `Struct`'s field names.
"""
function extract_groups(expr::Expr, pat::AbstractString)
    pat = String(pat)
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_str_extract_groups(expr, pat, ncodeunits(pat), out)
    polars_error(err)
    return Expr(out[])
end

"""
    reverse(expr::Polars.Expr)::Polars.Expr

!!! warning "Unavailable in this build"
    See [Developer](@ref) for why, and how to enable it.
"""
function reverse(::Expr)
    return error(
        "Strings.reverse is unavailable in this build: polars' string `reverse` requires " *
            "the `string_reverse` Cargo feature, which c-polars does not currently enable. " *
            "Add it to c-polars/Cargo.toml's `polars` feature list and rebuild to enable it."
    )
end

# `contains`/`replace`/`join`/`reverse` are intentionally not exported -- they collide with
# `Base.contains`/`Base.replace`/`Base.join`/`Base.reverse` and are designed for qualified use
# (`Strings.contains`, etc.); `using Polars.Strings` would otherwise clash with those.
# `to_integer` is unavailable in this build (see above), so is left unexported too.
export slice, replace_all, extract, count_matches, to_date, to_datetime,
    pad_start, pad_end, find, replace_n, splitn, split_exact, extract_groups
end # module Strings
