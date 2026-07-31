module Strings
using ..Polars: @generate_expr_fns, API, polars_expr_t, Expr, polars_error

@generate_expr_fns begin
    gen_impl_expr_str!(polars_expr_str_to_uppercase, StringNameSpace::uppercase, "Converts each string of `expr` to uppercase.")
    gen_impl_expr_str!(polars_expr_str_to_lowercase, StringNameSpace::lowercase, "Converts each string of `expr` to lowercase.")
    gen_impl_expr_str!(polars_expr_str_len_bytes, StringNameSpace::len_bytes, "Length of each string of `expr`, in bytes. Differs from [`len_chars`](@ref) for non-ASCII text (a multi-byte UTF-8 character counts as more than one byte but one char).")
    gen_impl_expr_str!(polars_expr_str_len_chars, StringNameSpace::len_chars, "Length of each string of `expr`, in Unicode characters. Differs from [`len_bytes`](@ref) for non-ASCII text.")
    # gen_impl_expr_str!(polars_expr_str_explode, StringNameSpace::explode)

    gen_impl_expr_binary_str!(polars_expr_str_starts_with, StringNameSpace::starts_with, "Row-wise boolean flag: `true` where `a` starts with the literal (non-regex) substring `b`. Has a curried form `starts_with(pat)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_str!(polars_expr_str_ends_with, StringNameSpace::ends_with, "Row-wise boolean flag: `true` where `a` ends with the literal (non-regex) substring `b`. Has a curried form `ends_with(pat)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_str!(
        polars_expr_str_contains_literal,
        StringNameSpace::contains_literal,
        "Row-wise boolean flag: `true` where `a` contains the literal (non-regex) substring `b`. For a regex match, use [`contains`](@ref). Has a curried form `contains_literal(pat)` -- see [Curried forms for pipe-based composition](@ref)."
    )

    gen_impl_expr_binary_str!(polars_expr_str_strip_chars, StringNameSpace::strip_chars, "Removes any leading/trailing characters of `a` that appear in `b` (a string of characters to strip, not a substring to match). Has a curried form `strip_chars(chars)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_str!(polars_expr_str_strip_prefix, StringNameSpace::strip_prefix, "Removes the literal prefix `b` from `a` if present (no-op otherwise). Has a curried form `strip_prefix(prefix)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_str!(polars_expr_str_strip_suffix, StringNameSpace::strip_suffix, "Removes the literal suffix `b` from `a` if present (no-op otherwise). Has a curried form `strip_suffix(suffix)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_str!(polars_expr_str_split, StringNameSpace::split, "Splits each string of `a` on the literal (non-regex) substring `b`, returning a `List` of substrings (see [List](@ref expr-list)). Has a curried form `split(by)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_str!(polars_expr_str_extract_all, StringNameSpace::extract_all, "Extracts every non-overlapping match of the regex `b` from `a`, returning a `List` of matches per row (see [List](@ref expr-list)). Has a curried form `extract_all(pat)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_str!(polars_expr_str_zfill, StringNameSpace::zfill, "Left-pads each string of `a` with `'0'` up to a total width of `b` characters (a leading `+`/`-` sign, if present, stays before the padding). Has a curried form `zfill(width)` -- see [Curried forms for pipe-based composition](@ref).")
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
    Upstream `StringNameSpace::to_titlecase` sits behind polars' own `nightly` Cargo feature
    (it still depends on unstable stdlib internals as of polars 0.54.4), and this repo pins a
    stable toolchain deliberately -- so `c-polars` does not compile the symbol and no binding for
    it is generated. To enable it, build `c-polars` with a nightly toolchain and
    `cargo build --features nightly`, then regenerate the bindings.

This method exists only to fail with that explanation: without it, calling `Strings.titlecase`
raises a bare `UndefVarError` for a missing `ccall` symbol, which says nothing about why.
"""
function titlecase(::Expr)
    return error(
        "Strings.titlecase is unavailable in this build: polars' `to_titlecase` requires " *
            "polars' `nightly` Cargo feature and a nightly rustc, while c-polars pins a stable " *
            "toolchain (see CLAUDE.md). Rebuild with `cargo build --features nightly` to enable it."
    )
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
    pad_start(expr::Polars.Expr, length::Integer; fill_char::Char=' ')::Polars.Expr

Pads each string of `expr` on the left with `fill_char` until it reaches `length` characters
(no-op for a string already at least that long).
"""
function pad_start(expr::Expr, length::Integer; fill_char::Char = ' ')
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_str_pad_start(expr, convert(Expr, length), codepoint(fill_char), out)
    polars_error(err)
    return Expr(out[])
end

"""
    pad_start(length::Integer; fill_char::Char=' ')::Base.Callable

Curried form of [`pad_start`](@ref) for use with `|>`.
"""
pad_start(length::Integer; fill_char::Char = ' ') = expr -> pad_start(expr, length; fill_char)

"""
    pad_end(expr::Polars.Expr, length::Integer; fill_char::Char=' ')::Polars.Expr

Pads each string of `expr` on the right with `fill_char` until it reaches `length` characters
(no-op for a string already at least that long).
"""
function pad_end(expr::Expr, length::Integer; fill_char::Char = ' ')
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_str_pad_end(expr, convert(Expr, length), codepoint(fill_char), out)
    polars_error(err)
    return Expr(out[])
end

"""
    pad_end(length::Integer; fill_char::Char=' ')::Base.Callable

Curried form of [`pad_end`](@ref) for use with `|>`.
"""
pad_end(length::Integer; fill_char::Char = ' ') = expr -> pad_end(expr, length; fill_char)

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
    join(expr::Polars.Expr; ignore_nulls::Bool=false)::Polars.Expr

!!! warning "Unavailable in this build"
    Upstream `StringNameSpace::join` (concatenating a whole String column into one value) sits
    behind polars' own `concat_str` Cargo feature, which is not enabled in this build. To
    enable it, add `"concat_str"` to `c-polars/Cargo.toml`'s `polars` feature list, rebuild
    `c-polars`, and regenerate the bindings.

This method exists only to fail with that explanation: without it, calling `Strings.join`
raises a bare `UndefVarError` for a missing `ccall` symbol, which says nothing about why.
"""
function join(::Expr; ignore_nulls::Bool = false)
    return error(
        "Strings.join is unavailable in this build: polars' string `join` requires " *
            "the `concat_str` Cargo feature, which c-polars does not currently enable " *
            "(see CLAUDE.md). Add it to c-polars/Cargo.toml's `polars` feature list and " *
            "rebuild to enable it."
    )
end

"""
    to_integer(expr::Polars.Expr; base::Integer=10, strict::Bool=true)::Polars.Expr

!!! warning "Unavailable in this build"
    Upstream `StringNameSpace::to_integer` sits behind polars' own `string_to_integer` Cargo
    feature, which is not enabled in this build. To enable it, add `"string_to_integer"` to
    `c-polars/Cargo.toml`'s `polars` feature list, rebuild `c-polars`, and regenerate the
    bindings.

This method exists only to fail with that explanation: without it, calling
`Strings.to_integer` raises a bare `UndefVarError` for a missing `ccall` symbol, which says
nothing about why.
"""
function to_integer(::Expr; base::Integer = 10, strict::Bool = true)
    return error(
        "Strings.to_integer is unavailable in this build: polars' `to_integer` requires " *
            "the `string_to_integer` Cargo feature, which c-polars does not currently " *
            "enable (see CLAUDE.md). Add it to c-polars/Cargo.toml's `polars` feature list " *
            "and rebuild to enable it."
    )
end

"""
    extract_groups(expr::Polars.Expr, pat::AbstractString)::Polars.Expr

!!! warning "Unavailable in this build"
    Upstream `StringNameSpace::extract_groups` sits behind polars' own `extract_groups` Cargo
    feature, which is not enabled in this build. To enable it, add `"extract_groups"` to
    `c-polars/Cargo.toml`'s `polars` feature list, rebuild `c-polars`, and regenerate the
    bindings.

This method exists only to fail with that explanation: without it, calling
`Strings.extract_groups` raises a bare `UndefVarError` for a missing `ccall` symbol, which
says nothing about why.
"""
function extract_groups(::Expr, ::AbstractString)
    return error(
        "Strings.extract_groups is unavailable in this build: polars' `extract_groups` " *
            "requires the `extract_groups` Cargo feature, which c-polars does not currently " *
            "enable (see CLAUDE.md). Add it to c-polars/Cargo.toml's `polars` feature list " *
            "and rebuild to enable it."
    )
end

"""
    reverse(expr::Polars.Expr)::Polars.Expr

!!! warning "Unavailable in this build"
    Upstream `StringNameSpace::reverse` sits behind polars' own `string_reverse` Cargo
    feature, which is not enabled in this build. To enable it, add `"string_reverse"` to
    `c-polars/Cargo.toml`'s `polars` feature list, rebuild `c-polars`, and regenerate the
    bindings.

This method exists only to fail with that explanation: without it, calling `Strings.reverse`
raises a bare `UndefVarError` for a missing `ccall` symbol, which says nothing about why.
"""
function reverse(::Expr)
    return error(
        "Strings.reverse is unavailable in this build: polars' string `reverse` requires " *
            "the `string_reverse` Cargo feature, which c-polars does not currently enable " *
            "(see CLAUDE.md). Add it to c-polars/Cargo.toml's `polars` feature list and " *
            "rebuild to enable it."
    )
end

# `contains`/`replace`/`join`/`reverse` are intentionally not exported -- they collide with
# `Base.contains`/`Base.replace`/`Base.join`/`Base.reverse` and are designed for qualified use
# (`Strings.contains`, etc.); `using Polars.Strings` would otherwise clash with those.
# `to_integer`/`extract_groups` are unavailable in this build (see above), so are left
# unexported too.
export slice, replace_all, extract, count_matches, to_date, to_datetime, find, pad_start, pad_end
end # module Strings
