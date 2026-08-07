module Strings
using ..Polars: @generate_expr_fns, @gen_expr_fn, @curry,
    API, polars_expr_t, Expr, polars_error, _time_unit_enum

@generate_expr_fns begin
    gen_impl_expr_str!(polars_expr_str_to_uppercase, StringNameSpace::uppercase, "Converts each string of `expr` to uppercase.")
    gen_impl_expr_str!(polars_expr_str_to_lowercase, StringNameSpace::lowercase, "Converts each string of `expr` to lowercase.")
    gen_impl_expr_str!(polars_expr_str_len_bytes, StringNameSpace::len_bytes, "Length of each string of `expr`, in bytes. Differs from [`len_chars`](@ref) for non-ASCII text (a multi-byte UTF-8 character counts as more than one byte but one char).")
    gen_impl_expr_str!(polars_expr_str_len_chars, StringNameSpace::len_chars, "Length of each string of `expr`, in Unicode characters. Differs from [`len_bytes`](@ref) for non-ASCII text.")
    # gen_impl_expr_str!(polars_expr_str_explode, StringNameSpace::explode)

    gen_impl_expr_binary_str_curried!(polars_expr_str_starts_with, StringNameSpace::starts_with, "Row-wise boolean flag: `true` where `a` starts with the literal (non-regex) substring `b`.\n\n!!! note \"Has a curried form\"\n    `starts_with(pat)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_str_curried!(polars_expr_str_ends_with, StringNameSpace::ends_with, "Row-wise boolean flag: `true` where `a` ends with the literal (non-regex) substring `b`.\n\n!!! note \"Has a curried form\"\n    `ends_with(pat)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_str_curried!(
        polars_expr_str_contains_literal,
        StringNameSpace::contains_literal,
        "Row-wise boolean flag: `true` where `a` contains the literal (non-regex) substring `b`. For a regex match, use [`contains`](@ref).\n\n!!! note \"Has a curried form\"\n    `contains_literal(pat)` -- see [Curried forms for pipe-based composition](@ref)."
    )

    gen_impl_expr_binary_str_curried!(polars_expr_str_strip_chars, StringNameSpace::strip_chars, "Removes any leading/trailing characters of `a` that appear in `b` (a string of characters to strip, not a substring to match).\n\n!!! note \"Has a curried form\"\n    `strip_chars(chars)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_str_curried!(polars_expr_str_strip_chars_start, StringNameSpace::strip_chars_start, "Like [`strip_chars`](@ref), but only strips leading characters.\n\n!!! note \"Has a curried form\"\n    `strip_chars_start(chars)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_str_curried!(polars_expr_str_strip_chars_end, StringNameSpace::strip_chars_end, "Like [`strip_chars`](@ref), but only strips trailing characters.\n\n!!! note \"Has a curried form\"\n    `strip_chars_end(chars)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_str_curried!(polars_expr_str_strip_prefix, StringNameSpace::strip_prefix, "Removes the literal prefix `b` from `a` if present (no-op otherwise).\n\n!!! note \"Has a curried form\"\n    `strip_prefix(prefix)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_str_curried!(polars_expr_str_strip_suffix, StringNameSpace::strip_suffix, "Removes the literal suffix `b` from `a` if present (no-op otherwise).\n\n!!! note \"Has a curried form\"\n    `strip_suffix(suffix)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_str_curried!(polars_expr_str_split, StringNameSpace::split, "Splits each string of `a` on the literal (non-regex) substring `b`, returning a `List` of substrings (see [List](@ref expr-list)).\n\n!!! note \"Has a curried form\"\n    `split(by)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_str_curried!(polars_expr_str_extract_all, StringNameSpace::extract_all, "Extracts every non-overlapping match of the regex `b` from `a`, returning a `List` of matches per row (see [List](@ref expr-list)).\n\n!!! note \"Has a curried form\"\n    `extract_all(pat)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_str_curried!(polars_expr_str_zfill, StringNameSpace::zfill, "Left-pads each string of `a` with `'0'` up to a total width of `b` characters (a leading `+`/`-` sign, if present, stays before the padding).\n\n!!! note \"Has a curried form\"\n    `zfill(width)` -- see [Curried forms for pipe-based composition](@ref).")
end

# `head`/`tail` are pulled out of the `@generate_expr_fns` block (rather than generated via
# `gen_impl_expr_binary_str_curried!`, like the other binary ops above) because they collide with
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

# The `Fix2`-style curries for the binary namespace ops above (e.g. `col("s") |>
# Strings.starts_with("foo")`) are generated by `@generate_expr_fns`'s `curried` variant, right
# next to each primal in the block above. `head`/`tail` are the exception, hand-written both
# above and here since they're pulled out of the macro block entirely (see the comment there).
head(n) = Base.Fix2(head, convert(Expr, n))
tail(n) = Base.Fix2(tail, convert(Expr, n))

@gen_expr_fn contains(expr::Expr, pat::Expr; strict::Bool = true) polars_expr_str_contains "Check if the string contains a match for the regex `pat`. If `strict` is `true` (default), an invalid regex raises an error; if `false`, it returns `null` instead. For a plain substring (non-regex) check, use [`contains_literal`](@ref)."
@curry contains(pat; strict::Bool = true)

@gen_expr_fn find(expr::Expr, pat::Expr; strict::Bool = true) polars_expr_str_find "Index of the start of the first match of the regex `pat` in each string of `expr` (`null` if there is no match). If `strict` is `true` (default), an invalid regex raises an error; if `false`, it returns `null` instead. For a plain substring (non-regex) search, build the literal-search equivalent via [`contains_literal`](@ref) instead."
@curry find(pat; strict::Bool = true)

@gen_expr_fn slice(expr::Expr, offset::Expr, length::Expr) polars_expr_str_slice "Extracts a substring starting at `offset` (0-indexed; negative indexes from the end) with the given `length` (extends to the end of the string if `length` is `null`)."
@curry slice(offset, length)

@gen_expr_fn pad_start(expr::Expr, length::Expr; fill_char::Char = ' ') polars_expr_str_pad_start "Pads each string of `expr` on the left with `fill_char` until it reaches `length` characters (no-op for a string already at least that long). `length` is an integer literal or an expression (e.g. another column), giving a per-row target length."
@curry pad_start(length; fill_char::Char = ' ')

@gen_expr_fn pad_end(expr::Expr, length::Expr; fill_char::Char = ' ') polars_expr_str_pad_end "Pads each string of `expr` on the right with `fill_char` until it reaches `length` characters (no-op for a string already at least that long). `length` is an integer literal or an expression (e.g. another column), giving a per-row target length."
@curry pad_end(length; fill_char::Char = ' ')

@gen_expr_fn replace(expr::Expr, pat::Expr, value::Expr; literal::Bool = false) polars_expr_str_replace "Replaces the first match of `pat` with `value`. If `literal` is `true`, `pat` is treated as a plain substring rather than a regex."
@curry replace(pat, value; literal::Bool = false)

@gen_expr_fn replace_all(expr::Expr, pat::Expr, value::Expr; literal::Bool = false) polars_expr_str_replace_all "Replaces all matches of `pat` with `value`. If `literal` is `true`, `pat` is treated as a plain substring rather than a regex."
@curry replace_all(pat, value; literal::Bool = false)

@gen_expr_fn extract(expr::Expr, pat::Expr, group_index::Integer) polars_expr_str_extract "Extracts the capture group numbered `group_index` (0 = the whole match) from the first match of the regex `pat`."
@curry extract(pat, group_index::Integer)

@gen_expr_fn count_matches(expr::Expr, pat::Expr; literal::Bool = false) polars_expr_str_count_matches "Counts the number of non-overlapping matches of `pat`. If `literal` is `true`, `pat` is treated as a plain substring rather than a regex."
@curry count_matches(pat; literal::Bool = false)

# Everything below stays hand-written: each needs marshalling `@gen_expr_fn`'s annotation-driven
# table (see `_marshal_arg`) deliberately does not cover.
#   - `to_date`/`to_datetime`: `format` is `Union{Nothing,String}`, collapsed to `""` via
#     `something(format, "")` before the `(ptr, len)` pair is taken -- the length must come from
#     the collapsed value, not the original `nothing`. `to_datetime` also resolves an enum.
#   - `replace_n`: the C parameter order (`pat, value, literal, n`) differs from the Julia one
#     (`pat, value, n; literal`), and `n` needs `Int64`.
#   - `splitn`/`split_exact`: `n` needs `Csize_t`.
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
    time_unit_enum = _time_unit_enum(time_unit)
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

@gen_expr_fn join(expr::Expr, delimiter::AbstractString; ignore_nulls::Bool = true) polars_expr_str_join "Aggregates every string value of `expr` (across *all* rows, or per group inside `agg`) into a single value, joined by `delimiter`. If `ignore_nulls` is `true` (default), `null` values are skipped; if `false`, any `null` poisons the whole result to `null`. Distinct from [`Lists.join`](@ref) (joins each row's own list independently, not an aggregation across rows)."

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

@gen_expr_fn extract_groups(expr::Expr, pat::AbstractString) polars_expr_str_extract_groups "Extracts every named capture group of the regex `pat` from the first match within each string of `expr`, into a `Struct` (see [Struct](@ref expr-struct)) with one field per named group. `pat` must be a plain string (not an `Expr`): the regex is compiled once, at plan time, to determine the output `Struct`'s field names."

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
