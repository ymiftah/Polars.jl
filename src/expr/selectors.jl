# The `Selector` type and its set operators, then the `Selectors` module of constructors (which
# imports `Selector`, so it must come second).

"""
    Selector

A column selector. Can be used anywhere an `Expr` is accepted, and combined with `|`, `&`, `-`
and `xor`.

Note: combining a `Selector` with an `Expr` is a `MethodError`; convert the `Expr` side first
(e.g. `Selectors.by_name("x")` instead of `col("x")`).
"""
struct Selector
    expr::Expr
end

_as_expr(s::Selector) = s.expr

"""
Combines two selectors with one of the `polars_expr_selector_*` set operations.
"""
function _combine_selectors(f, a::Selector, b::Selector)
    out = Ref{Ptr{polars_expr_t}}()
    err = f(a.expr, b.expr, out)
    polars_error(err)
    return Selector(Expr(out[]))
end

"""
    a::Selector | b::Selector

Union: columns matched by either `a` or `b`.
"""
Base.:|(a::Selector, b::Selector) = _combine_selectors(polars_expr_selector_union, a, b)

"""
    a::Selector & b::Selector

Intersection: columns matched by both `a` and `b`.
"""
Base.:&(a::Selector, b::Selector) = _combine_selectors(polars_expr_selector_intersect, a, b)

"""
    a::Selector - b::Selector

Difference: columns matched by `a` but not by `b`.
"""
Base.:-(a::Selector, b::Selector) = _combine_selectors(polars_expr_selector_difference, a, b)

"""
    xor(a::Selector, b::Selector)

Exclusive or: columns matched by exactly one of `a` and `b`.
"""
Base.xor(a::Selector, b::Selector) = _combine_selectors(polars_expr_selector_exclusive_or, a, b)

"""
    Selectors

Column selectors. Every function returns a [`Selector`](@ref).

| Function | Selects |
|---|---|
| `all()`, `empty()` | every column, no column |
| `numeric()`, `integer()`, `unsigned_integer()`, `signed_integer()`, `float()` | numeric dtypes |
| `string()`, `boolean()`, `binary()` | `String`/`Bool`/`Vector{UInt8}` columns |
| `date()`, `time()`, `datetime()`, `duration()`, `temporal()` | temporal dtypes |
| `categorical()`, `decimal()` | Categorical/Decimal columns |
| `struct_()`, `list()`, `array()`, `nested()` | nested dtypes |
| `by_dtype(dtypes...)` | the given Julia types |
| `by_name(names...; strict=true)` | the given column names |
| `by_index(indices...; strict=true)` | the given column positions |
| `matches(pattern)` | column names matching a regex |
| `starts_with(...)`, `ends_with(...)`, `contains(...)` | column names by literal substring |

Note: `by_index` is 1-based, like [`Polars.nth`](@ref).
"""
module Selectors

    using ..Polars: API, polars_expr_t, Expr, Selector, polars_error, _name_ptrs,
        _plain_value_type_code
    using Dates: DateTime, Nanosecond, Microsecond, Millisecond

    _wrap(ptr) = Selector(Expr(ptr))

    """
        all()::Selector

    Select all columns.
    """
    all() = _wrap(API.polars_expr_selector_all())

    """
        empty()::Selector

    Select no columns.
    """
    empty() = _wrap(API.polars_expr_selector_empty())

    _dtype_simple(kind) = _wrap(API.polars_expr_selector_dtype_simple(kind))

    """
        numeric()::Selector

    Select all numeric columns.
    """
    numeric() = _dtype_simple(API.PolarsDtypeSelectorKindNumeric)

    """
        integer()::Selector

    Select all integer columns.
    """
    integer() = _dtype_simple(API.PolarsDtypeSelectorKindInteger)

    """
        unsigned_integer()::Selector

    Select all unsigned integer columns.
    """
    unsigned_integer() = _dtype_simple(API.PolarsDtypeSelectorKindUnsignedInteger)

    """
        signed_integer()::Selector

    Select all signed integer columns.
    """
    signed_integer() = _dtype_simple(API.PolarsDtypeSelectorKindSignedInteger)

    """
        float()::Selector

    Select all float columns.
    """
    float() = _dtype_simple(API.PolarsDtypeSelectorKindFloat)

    """
        temporal()::Selector

    Select all temporal columns (Date, Datetime, Duration, Time).
    """
    temporal() = _dtype_simple(API.PolarsDtypeSelectorKindTemporal)

    """
        categorical()::Selector

    Select all categorical columns.
    """
    categorical() = _dtype_simple(API.PolarsDtypeSelectorKindCategorical)

    """
        decimal()::Selector

    Select all decimal columns.
    """
    decimal() = _dtype_simple(API.PolarsDtypeSelectorKindDecimal)

    """
        nested()::Selector

    Select all nested columns (List, Array, Struct).
    """
    nested() = _dtype_simple(API.PolarsDtypeSelectorKindNested)

    """
        struct_()::Selector

    Select all struct columns.
    """
    struct_() = _dtype_simple(API.PolarsDtypeSelectorKindStruct)

    """
        datetime()::Selector

    Select all datetime columns, with any time unit and time zone.
    """
    datetime() = _dtype_simple(API.PolarsDtypeSelectorKindDatetime)

    """
        duration()::Selector

    Select all duration columns, with any time unit.
    """
    duration() = _dtype_simple(API.PolarsDtypeSelectorKindDuration)

    """
        list()::Selector

    Select all list columns.
    """
    list() = _dtype_simple(API.PolarsDtypeSelectorKindList)

    """
        array()::Selector

    Select all array columns.
    """
    array() = _dtype_simple(API.PolarsDtypeSelectorKindArray)

    """
    Selector for a single `polars_value_type_t`.
    """
    function _dtype_one(value_type)
        value_types = API.polars_value_type_t[value_type]
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_selector_dtype_any_of(value_types, length(value_types), out)
        polars_error(err)
        return _wrap(out[])
    end

    """
        string()::Selector

    Select all string columns.
    """
    string() = _dtype_one(API.PolarsValueTypeString)

    """
        boolean()::Selector

    Select all boolean columns.
    """
    boolean() = _dtype_one(API.PolarsValueTypeBoolean)

    """
        binary()::Selector

    Select all binary columns.
    """
    binary() = _dtype_one(API.PolarsValueTypeBinary)

    """
        date()::Selector

    Select all date columns.
    """
    date() = _dtype_one(API.PolarsValueTypeDate)

    """
        time()::Selector

    Select all time columns.
    """
    time() = _dtype_one(API.PolarsValueTypeTime)

    """
    Maps a Julia type to the `polars_value_type_t` for [`by_dtype`](@ref). `DateTime` and `Period`
    types map to codes that the Rust side rejects (they need a time unit).
    """
    function _by_dtype_value_type(dtype)
        plain = _plain_value_type_code(dtype)
        plain !== nothing && return plain
        return if dtype == DateTime
            API.PolarsValueTypeDatetime
        elseif dtype in (Nanosecond, Microsecond, Millisecond)
            API.PolarsValueTypeDuration
        else
            error("Selectors.by_dtype: unsupported dtype $dtype")
        end
    end

    """
        by_dtype(dtypes...)::Selector

    Select all columns of the given Julia types, e.g. `by_dtype(Int64, Float64)`.

    Note: `DateTime`, `Period` types, `Decimal`, `List` and `Struct` are not supported; use
    [`datetime`](@ref), [`duration`](@ref), [`decimal`](@ref), [`list`](@ref) or
    [`struct_`](@ref).
    """
    function by_dtype(dtypes...)
        value_types = API.polars_value_type_t[_by_dtype_value_type(dt) for dt in dtypes]
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_selector_dtype_any_of(value_types, length(value_types), out)
        polars_error(err)
        return _wrap(out[])
    end

    """
        by_name(names::AbstractString...; strict::Bool=true)::Selector

    Select all columns with the given names. With `strict=true`, a missing column is an error.
    """
    function by_name(names::Vector{String}; strict::Bool = true)
        out = Ref{Ptr{polars_expr_t}}()
        owned, ptrs, lens = _name_ptrs(names)
        err = GC.@preserve owned begin
            API.polars_expr_selector_by_name(ptrs, lens, length(ptrs), strict, out)
        end
        polars_error(err)
        return _wrap(out[])
    end
    by_name(names::AbstractString...; strict::Bool = true) =
        by_name(collect(String, names); strict)

    """
        by_index(indices::Integer...; strict::Bool=true)::Selector

    Select all columns at the given positions. With `strict=true`, an out-of-range index is an
    error.

    Note: indices are 1-based; negative indices count from the end.
    """
    function by_index(indices::Vector{<:Integer}; strict::Bool = true)
        zero_based = Int64[i < 0 ? Int64(i) : Int64(i) - 1 for i in indices]
        out = API.polars_expr_selector_by_index(zero_based, length(zero_based), strict)
        return _wrap(out)
    end
    by_index(indices::Integer...; strict::Bool = true) = by_index(collect(Int, indices); strict)

    function _matches_kind(kind, pattern::AbstractString)
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_selector_matches(kind, pattern, ncodeunits(pattern), out)
        polars_error(err)
        return _wrap(out[])
    end

    """
        matches(pattern::AbstractString)::Selector

    Select all columns whose name matches the regex `pattern`.
    """
    matches(pattern::AbstractString) = _matches_kind(API.PolarsSelectorMatchKindRegex, pattern)

    """
        starts_with(prefixes::AbstractString...)::Selector

    Select all columns whose name starts with one of `prefixes`.
    """
    function starts_with(prefixes::AbstractString...)
        isempty(prefixes) &&
            throw(ArgumentError("Selectors.starts_with requires at least one prefix"))
        return reduce(|, _matches_kind(API.PolarsSelectorMatchKindStartsWith, p) for p in prefixes)
    end

    """
        ends_with(suffixes::AbstractString...)::Selector

    Select all columns whose name ends with one of `suffixes`.
    """
    function ends_with(suffixes::AbstractString...)
        isempty(suffixes) && throw(ArgumentError("Selectors.ends_with requires at least one suffix"))
        return reduce(|, _matches_kind(API.PolarsSelectorMatchKindEndsWith, p) for p in suffixes)
    end

    """
        contains(substrings::AbstractString...)::Selector

    Select all columns whose name contains one of `substrings`.
    """
    function contains(substrings::AbstractString...)
        isempty(substrings) &&
            throw(ArgumentError("Selectors.contains requires at least one substring"))
        return reduce(|, _matches_kind(API.PolarsSelectorMatchKindContains, p) for p in substrings)
    end

    export numeric, integer, unsigned_integer, signed_integer, boolean, binary,
        temporal, categorical, date, datetime, duration, decimal, struct_, list, array, nested,
        by_dtype, by_name, by_index, matches, starts_with, ends_with
    # Not exported (collide with Base): `all`, `float`, `string`, `time`, `contains`, `empty`.

end # module Selectors

"""
    exclude(names::AbstractString...)::Selector
    exclude(dtypes::Type...)::Selector
    exclude()::Selector

Select all columns except the given names or dtypes. Names that are not present are ignored.
"""
exclude(names::AbstractString...) = Selectors.all() - Selectors.by_name(names...; strict = false)
exclude(dtypes::Type...) = Selectors.all() - Selectors.by_dtype(dtypes...)
exclude() = Selectors.all()
export exclude, Selectors
