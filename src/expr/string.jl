module Strings
    using ..Polars: @wrap_simple_ops, @wrap_expr_method, @curry,
        API, polars_expr_t, Expr, polars_error, _time_unit_enum

    @wrap_simple_ops begin
        gen_impl_expr_str!(polars_expr_str_to_uppercase, StringNameSpace::uppercase, "Convert all characters to uppercase.")
        gen_impl_expr_str!(polars_expr_str_to_lowercase, StringNameSpace::lowercase, "Convert all characters to lowercase.")
        gen_impl_expr_str!(polars_expr_str_len_bytes, StringNameSpace::len_bytes, "Return the length of each string as the number of bytes.\n\nWhen working with non-ASCII text, the length in bytes is not the same as the length in characters. You may want to use [`len_chars`](@ref) instead. Note that `len_bytes` is much more performant (_O(1)_) than `len_chars` (_O(n)_).")
        gen_impl_expr_str!(polars_expr_str_len_chars, StringNameSpace::len_chars, "Return the length of each string as the number of characters.\n\nWhen working with ASCII text, use [`len_bytes`](@ref) instead to achieve equivalent output with much better performance: `len_bytes` runs in _O(1)_, while `len_chars` runs in _O(n)_.")
        gen_impl_expr_str!(polars_expr_str_escape_regex, StringNameSpace::escape_regex, "Escape all regex metacharacters in the string values.")

        gen_impl_expr_binary_str!(polars_expr_str_starts_with, StringNameSpace::starts_with, "Check if a string value starts with the `sub` string.\n\n!!! note \"Has a curried form\"\n    `starts_with(sub)`, for `|>` pipelines."; curried = true)
        gen_impl_expr_binary_str!(polars_expr_str_ends_with, StringNameSpace::ends_with, "Check if a string value ends with the `sub` string.\n\n!!! note \"Has a curried form\"\n    `ends_with(sub)`, for `|>` pipelines."; curried = true)
        gen_impl_expr_binary_str!(polars_expr_str_contains_literal, StringNameSpace::contains_literal, "Check if a string value contains a literal substring.\n\n!!! note \"Has a curried form\"\n    `contains_literal(pat)`, for `|>` pipelines."; curried = true)

        gen_impl_expr_binary_str!(polars_expr_str_strip_chars, StringNameSpace::strip_chars, "Remove leading and trailing characters.\n\n!!! note \"Has a curried form\"\n    `strip_chars(matches)`, for `|>` pipelines."; curried = true)
        gen_impl_expr_binary_str!(polars_expr_str_strip_chars_start, StringNameSpace::strip_chars_start, "Remove leading characters.\n\n!!! note \"Has a curried form\"\n    `strip_chars_start(matches)`, for `|>` pipelines."; curried = true)
        gen_impl_expr_binary_str!(polars_expr_str_strip_chars_end, StringNameSpace::strip_chars_end, "Remove trailing characters.\n\n!!! note \"Has a curried form\"\n    `strip_chars_end(matches)`, for `|>` pipelines."; curried = true)
        gen_impl_expr_binary_str!(polars_expr_str_strip_prefix, StringNameSpace::strip_prefix, "Remove prefix.\n\n!!! note \"Has a curried form\"\n    `strip_prefix(prefix)`, for `|>` pipelines."; curried = true)
        gen_impl_expr_binary_str!(polars_expr_str_strip_suffix, StringNameSpace::strip_suffix, "Remove suffix.\n\n!!! note \"Has a curried form\"\n    `strip_suffix(suffix)`, for `|>` pipelines."; curried = true)
        gen_impl_expr_binary_str!(polars_expr_str_split, StringNameSpace::split, "Split the string by a substring. The resulting dtype is `List<String>`.\n\n!!! note \"Has a curried form\"\n    `split(by)`, for `|>` pipelines."; curried = true)
        gen_impl_expr_binary_str!(polars_expr_str_extract_all, StringNameSpace::extract_all, "Extract each successive non-overlapping match in an individual string as an array.\n\n!!! note \"Has a curried form\"\n    `extract_all(pat)`, for `|>` pipelines."; curried = true)
        gen_impl_expr_binary_str!(polars_expr_str_zfill, StringNameSpace::zfill, "Pad the start of the string with zeros until it reaches the given length.\n\nA sign prefix (`-`) is handled by inserting the padding after the sign character rather than before. Strings with length equal to or greater than the given length are returned as-is.\n\n!!! note \"Has a curried form\"\n    `zfill(length)`, for `|>` pipelines."; curried = true)
    end

    # `head`/`tail` are hand-written so they are not exported (they collide with `Polars.head`).
    """
        head(expr::Polars.Expr, n::Polars.Expr)::Polars.Expr

    Take the first `n` characters of the string values.
    """
    function head(a::Expr, b::Expr)
        out = API.polars_expr_str_head(a, b)
        return Expr(out)
    end

    """
        tail(expr::Polars.Expr, n::Polars.Expr)::Polars.Expr

    Take the last `n` characters of the string values.
    """
    function tail(a::Expr, b::Expr)
        out = API.polars_expr_str_tail(a, b)
        return Expr(out)
    end

    """
        titlecase(expr::Polars.Expr)

    Convert all characters to titlecase.

    Note: unavailable in this build; see [Limitations](@ref).
    """
    function titlecase(::Expr)
        return error(
            "Strings.titlecase is unavailable in this build: polars' `to_titlecase` requires " *
                "polars' `nightly` Cargo feature and a nightly rustc, while c-polars pins a stable " *
                "toolchain. Rebuild with `cargo build --features nightly` to enable it."
        )
    end

    head(n) = Base.Fix2(head, convert(Expr, n))
    tail(n) = Base.Fix2(tail, convert(Expr, n))

    @wrap_expr_method contains(expr::Expr, pat::Expr; strict::Bool = true) polars_expr_str_contains "Check if this column of strings contains a Regex. If `strict` is `true`, then it is an error if any `pat` is an invalid regex, whereas if `strict` is `false`, an invalid regex will simply evaluate to `false`."
    @curry contains(pat; strict::Bool = true)

    @wrap_expr_method find(expr::Expr, pat::Expr; strict::Bool = true) polars_expr_str_find "Find the index of a substring defined by a regular expressions within another string value.\n\nNote: the index is 0-based."
    @curry find(pat; strict::Bool = true)

    @wrap_expr_method slice(expr::Expr, offset::Expr, length::Expr) polars_expr_str_slice "Slice the string values.\n\nNote: `offset` is 0-based; a negative `offset` counts from the end."
    @curry slice(offset, length)

    @wrap_expr_method pad_start(expr::Expr, length::Expr; fill_char::Char = ' ') polars_expr_str_pad_start "Pad the start of the string until it reaches the given length.\n\nPadding is done using the specified `fill_char`. Strings with length equal to or greater than the given length are returned as-is."
    @curry pad_start(length; fill_char::Char = ' ')

    @wrap_expr_method pad_end(expr::Expr, length::Expr; fill_char::Char = ' ') polars_expr_str_pad_end "Pad the end of the string until it reaches the given length.\n\nPadding is done using the specified `fill_char`. Strings with length equal to or greater than the given length are returned as-is."
    @curry pad_end(length; fill_char::Char = ' ')

    @wrap_expr_method replace(expr::Expr, pat::Expr, value::Expr; literal::Bool = false) polars_expr_str_replace "Replace values that match a regex `pat` with a `value`. With `literal=true`, `pat` is a plain string."
    @curry replace(pat, value; literal::Bool = false)

    @wrap_expr_method replace_all(expr::Expr, pat::Expr, value::Expr; literal::Bool = false) polars_expr_str_replace_all "Replace all values that match a regex `pat` with a `value`. With `literal=true`, `pat` is a plain string."
    @curry replace_all(pat, value; literal::Bool = false)

    @wrap_expr_method extract(expr::Expr, pat::Expr, group_index::Integer) polars_expr_str_extract "Extract a regex pattern from the a string value. If `group_index` is out of bounds, null is returned."
    @curry extract(pat, group_index::Integer)

    @wrap_expr_method count_matches(expr::Expr, pat::Expr; literal::Bool = false) polars_expr_str_count_matches "Count all successive non-overlapping regex matches. With `literal=true`, `pat` is a plain string."
    @curry count_matches(pat; literal::Bool = false)

    # Hand-written: optional `format` strings, an enum, and argument orders or integer types
    # `@wrap_expr_method` doesn't cover.
    """
        to_date(expr::Polars.Expr; format::Union{Nothing,String}=nothing, strict::Bool=true,
                exact::Bool=true)::Polars.Expr

    Convert a String column into a Date column. `format` is a chrono format string, inferred if
    `nothing`. `strict`: raise on a value that fails to parse, instead of returning null. `exact`:
    require an exact format match.
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

    Convert a String column into a Datetime column. See [`to_date`](@ref) for the keywords.
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

    Replace values that match a regex `pat` with a `value`, at most `n` times. With `literal=true`,
    `pat` is a plain string.
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

    Split by a given substring, returning exactly `n` items. If there are more possible splits, keeps
    the remainder of the string intact. The resulting dtype is `Struct`.
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

    Split exactly `n` times by a given substring. The resulting dtype is `Struct`.
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

    @wrap_expr_method join(expr::Expr, delimiter::AbstractString; ignore_nulls::Bool = true) polars_expr_str_join "Concat the values into a string array. `delimiter` is a string that will act as delimiter between values."

    """
        to_integer(expr::Polars.Expr; base::Integer=10, strict::Bool=true)::Polars.Expr

    Parse string in base radix into decimal.

    Note: unavailable in this build; see [Limitations](@ref).
    """
    function to_integer(::Expr; base::Integer = 10, strict::Bool = true)
        return error(
            "Strings.to_integer is unavailable in this build: polars' `to_integer` requires " *
                "the `string_to_integer` Cargo feature, which c-polars does not currently " *
                "enable. Add it to c-polars/Cargo.toml's `polars` feature list and rebuild to " *
                "enable it."
        )
    end

    @wrap_expr_method extract_groups(expr::Expr, pat::AbstractString) polars_expr_str_extract_groups "Extract all captures groups from a regex pattern as a struct."

    """
        reverse(expr::Polars.Expr)::Polars.Expr

    Reverse each string.

    Note: unavailable in this build; see [Limitations](@ref).
    """
    function reverse(::Expr)
        return error(
            "Strings.reverse is unavailable in this build: polars' string `reverse` requires " *
                "the `string_reverse` Cargo feature, which c-polars does not currently enable. " *
                "Add it to c-polars/Cargo.toml's `polars` feature list and rebuild to enable it."
        )
    end

    # Not exported: `contains`/`replace`/`join`/`reverse` (collide with Base) and `to_integer`.
    export slice, replace_all, extract, count_matches, to_date, to_datetime,
        pad_start, pad_end, find, replace_n, splitn, split_exact, extract_groups
end # module Strings

export Strings
