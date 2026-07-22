# `polars.selectors` / py-polars' `cs.*` -- select columns by dtype/name/position/pattern instead
# of writing out `col(...)` calls by hand, and combine selections with set algebra (`|`/`&`/`-`/
# `xor`). See `plans/definitive_guide_gap_closure.md`'s Phase 2 for the full design writeup this
# file implements.
#
# This file has two parts, in this order (the ordering is load-bearing -- see below):
#
#   1. Top-level code (this section, directly in `module Polars`, mirroring how `Expr` itself is
#      defined top-level in `expr/expr.jl`): the `Selector` type, its `_as_expr` method (easy to
#      miss since `_as_expr`'s other methods live in `expr/expr.jl`, a different file -- this is
#      the one that lets a bare `Selector` flow straight into `select`/`with_columns`/`filter`/...
#      exactly like an `Expr`), and the `|`/`&`/`-`/`xor` combinator operators.
#   2. `module Selectors` (below): the namespace of constructor functions (`all`, `numeric`,
#      `by_name`, ...) that build `Selector` values, mirroring the `Structs`/`Dt`/`Lists`/`Strings`
#      namespace-submodule pattern -- qualified-use only (`Selectors.numeric()`), matching
#      py-polars' own `import polars.selectors as cs` convention and avoiding clashes with
#      `string`/`float`/`all`/`time`/`contains` (all real `Base` exports).
#
# `Selector` must be defined before `module Selectors` opens (part 2 does `using ..Polars:
# Selector`, which resolves against the enclosing `Polars` module's namespace *as built so far* --
# same file, sequential top-to-bottom evaluation, same trick `Structs`'s `using ..Polars:
# _name_ptrs` already relies on for a name defined in a different, earlier-included file).

"""
    Selector

A column selector (py-polars' `cs.*` / `polars.selectors`) -- wraps a `Polars.Expr` under the
hood (`Selector::` is itself just another `Expr` variant on the Rust side), but is kept as a
distinct Julia type rather than returned as a plain `Expr` so that `|`/`&`/`-`/`xor` can mean
selector set-algebra (union/intersect/difference/exclusive-or over the *columns* a selector would
match) without colliding with what those operators already mean for two `Expr`s (elementwise
boolean logic over column *values*). Never constructed directly -- build one via the
[`Selectors`](@ref) namespace (`Selectors.numeric()`, `Selectors.by_name(...)`, etc.) and pass it
anywhere an `Expr` is accepted (`select`, `with_columns`, `filter`, `sort`, ...); it composes via
[`_as_expr`](@ref) exactly like a `String`/`Symbol`/`Expr` column reference does.

!!! note "Mixing a `Selector` with a plain `Expr` via `|`/`&`/`-`/`xor` is a `MethodError`, not a promotion"
    `numeric() | col("x")` has genuinely ambiguous intent (does `col("x")` mean "the column named
    x" or "select by name x"?), so no method exists for it in either argument order -- this is
    deliberate, not an oversight. Combine two `Selector`s, or convert one side to a `Selector`
    yourself first (e.g. `Selectors.by_name("x")` instead of `col("x")`).
"""
struct Selector
    expr::Expr
end

_as_expr(s::Selector) = s.expr

"""Builds the `Selector` produced by combining `a`/`b` through the raw `f`
(`polars_expr_selector_union`/`_intersect`/`_difference`/`_exclusive_or`), which fail with a
`PolarsError` (not a crash) if either side is not actually a `Selector`-backed `Expr` -- see
`expect_selector` on the Rust side. That path is normally unreachable from pure Julia (the
operator methods below only ever get called with two real `Selector`s -- anything else is already
a `MethodError` before this function runs), but stays fallible here so the C ABI's own invariant
is still honored end to end."""
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

Difference: columns matched by `a` but not by `b`. `Selectors.all() - Selectors.numeric()`
selects every non-numeric column.
"""
Base.:-(a::Selector, b::Selector) = _combine_selectors(polars_expr_selector_difference, a, b)

"""
    xor(a::Selector, b::Selector)

Exclusive or: columns matched by exactly one of `a`/`b`. Note this is Julia's `xor`/`⊻`, not `^`
-- `^` always means exponentiation in Julia, unlike Python's `cs.numeric() ^ cs.string()`.
"""
Base.xor(a::Selector, b::Selector) = _combine_selectors(polars_expr_selector_exclusive_or, a, b)

"""
    Selectors

Column selectors, mirroring py-polars' `polars.selectors` (conventionally imported as `cs` there;
here just used qualified, `Selectors.numeric()`, matching `Structs`/`Dt`/`Lists`/`Strings`'s own
qualified-use convention -- and avoiding clobbering `Base.all`/`Base.string`/`Base.float`/
`Base.time`/`Base.contains`, which several selector names would otherwise collide with).

Every function here returns a [`Selector`](@ref), which can be passed anywhere an `Expr` is
accepted (`select`, `with_columns`, `filter`, `sort`, ...) and combined with `|`/`&`/`-`/`xor`.

| Function | Selects |
|---|---|
| `all()` | every column |
| `numeric()`, `integer()`, `unsigned_integer()`, `signed_integer()`, `float()` | numeric dtype families |
| `string()`, `boolean()`, `binary()` | `String`/`Bool`/`Vector{UInt8}` columns |
| `date()`, `time()`, `datetime()`, `duration()` | temporal dtypes (`datetime`/`duration` match any time unit/zone) |
| `temporal()` | any of the above temporal dtypes |
| `categorical()`, `decimal()` | Categorical/Decimal columns |
| `struct_()`, `list()`, `array()`, `nested()` | nested dtypes (`struct_`/`list`/`array` match any inner type) |
| `by_dtype(dtypes...)` | explicit Julia dtype(s), e.g. `by_dtype(Int64, String)` |
| `by_name(names...; strict=true)` | explicit column names |
| `by_index(indices...; strict=true)` | explicit column positions (1-based, see below) |
| `matches(pattern)` | column names matching a regex |
| `starts_with(prefixes...)`, `ends_with(suffixes...)`, `contains(substrings...)` | column names by literal substring (regex-escaped internally, not user-facing regex) |

!!! note "`by_index` is 1-based here, unlike py-polars' 0-based `cs.by_index`"
    Matches this package's own [`nth`](@ref) (`src/expr/expr.jl`), which already made the same
    call for the same reason: 1-based indexing is the convention everywhere else in this Julia
    package. Negative indices still count back from the end unchanged (`by_index(-1)` is the last
    column, same as `nth(-1)`).

!!! note "Scope: no per-unit/zone temporal matching, no recursive nested-selector composition"
    `datetime()`/`duration()` match *any* time unit/time zone (no `cs.datetime(time_unit="ms")`
    equivalent), and `list()`/`array()` match *any* inner dtype (no `cs.list(cs.numeric())`
    nesting) -- both are real, deliberate scope cuts for this first cut, not oversights.
"""
module Selectors

    using ..Polars: API, polars_expr_t, Expr, Selector, polars_error, _name_ptrs,
        _plain_value_type_code
    using Dates: DateTime, Nanosecond, Microsecond, Millisecond

    _wrap(ptr) = Selector(Expr(ptr))

    """
        all()::Selector

    Selects every column (`Selector::Wildcard` upstream) -- the identity element for
    [`Base.:&`](@ref)/[`Base.xor`](@ref), and `all() - s` is how you'd complement any other selector
    `s` (e.g. `all() - numeric()` selects every non-numeric column).
    """
    all() = _wrap(API.polars_expr_selector_all())

    _dtype_simple(kind) = _wrap(API.polars_expr_selector_dtype_simple(kind))

    """
        numeric()::Selector

    Selects columns of any numeric dtype (integer, unsigned integer, or float).
    """
    numeric() = _dtype_simple(API.PolarsDtypeSelectorKindNumeric)

    """
        integer()::Selector

    Selects columns of any integer dtype (signed or unsigned).
    """
    integer() = _dtype_simple(API.PolarsDtypeSelectorKindInteger)

    """
        unsigned_integer()::Selector

    Selects columns of any unsigned integer dtype (`UInt8`/`UInt16`/`UInt32`/`UInt64`).
    """
    unsigned_integer() = _dtype_simple(API.PolarsDtypeSelectorKindUnsignedInteger)

    """
        signed_integer()::Selector

    Selects columns of any signed integer dtype (`Int8`/`Int16`/`Int32`/`Int64`).
    """
    signed_integer() = _dtype_simple(API.PolarsDtypeSelectorKindSignedInteger)

    """
        float()::Selector

    Selects columns of any float dtype (`Float32`/`Float64`). Not exported (would clobber
    `Base.float`) -- use qualified, `Selectors.float()`.
    """
    float() = _dtype_simple(API.PolarsDtypeSelectorKindFloat)

    """
        temporal()::Selector

    Selects columns of any temporal dtype (Date, Datetime, Duration, or Time).
    """
    temporal() = _dtype_simple(API.PolarsDtypeSelectorKindTemporal)

    """
        categorical()::Selector

    Selects Categorical-dtype columns.
    """
    categorical() = _dtype_simple(API.PolarsDtypeSelectorKindCategorical)

    """
        decimal()::Selector

    Selects Decimal-dtype columns (any precision/scale).
    """
    decimal() = _dtype_simple(API.PolarsDtypeSelectorKindDecimal)

    """
        nested()::Selector

    Selects columns of any nested dtype (List, Array, or Struct).
    """
    nested() = _dtype_simple(API.PolarsDtypeSelectorKindNested)

    """
        struct_()::Selector

    Selects Struct-dtype columns (any field set). Trailing underscore because `struct` is a reserved
    word in Julia.
    """
    struct_() = _dtype_simple(API.PolarsDtypeSelectorKindStruct)

    """
        datetime()::Selector

    Selects Datetime-dtype columns, matching any time unit and any time zone (including naive).
    Matching a *specific* time unit/zone is not exposed in this first cut -- see [`Selectors`](@ref)'s
    scope note.
    """
    datetime() = _dtype_simple(API.PolarsDtypeSelectorKindDatetime)

    """
        duration()::Selector

    Selects Duration-dtype columns, matching any time unit. Matching a *specific* time unit is not
    exposed in this first cut -- see [`Selectors`](@ref)'s scope note.
    """
    duration() = _dtype_simple(API.PolarsDtypeSelectorKindDuration)

    """
        list()::Selector

    Selects List-dtype columns, matching any inner dtype. Recursive inner-selector composition (e.g.
    `cs.list(cs.numeric())` in py-polars) is not exposed in this first cut -- see
    [`Selectors`](@ref)'s scope note.
    """
    list() = _dtype_simple(API.PolarsDtypeSelectorKindList)

    """
        array()::Selector

    Selects Array-dtype columns, matching any inner dtype and any width. Recursive inner-selector
    composition is not exposed in this first cut -- see [`Selectors`](@ref)'s scope note.

    !!! warning "Currently matches zero columns in this build"
        `dtype-array` is not in `c-polars/Cargo.toml`'s feature list, so upstream's own
        `DataTypeSelector::Array` matcher compiles to its safe `#[cfg(not(feature = "dtype-array"))]`
        fallback (always `false`) rather than a real check -- this compiles and runs without
        crashing, it just never matches anything. Not fixed here: enabling `dtype-array` is out of
        scope for this phase (would also force a full dependency rebuild) and this package has no
        write-side support for constructing an Array-dtype column at all yet either. See
        [Limitations](@ref) for the tracked entry.
    """
    array() = _dtype_simple(API.PolarsDtypeSelectorKindArray)

    """Builds a single-dtype selector directly from an already-resolved `polars_value_type_t` enum
    value (as opposed to [`by_dtype`](@ref), which maps *Julia types* to that enum -- these fixed
    wrappers already know their enum value, so they bypass that mapping rather than round-tripping
    through it)."""
    function _dtype_one(value_type)
        value_types = API.polars_value_type_t[value_type]
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_selector_dtype_any_of(value_types, length(value_types), out)
        polars_error(err)
        return _wrap(out[])
    end

    """
        string()::Selector

    Selects `String`-dtype columns. Not exported (would clobber `Base.string`) -- use qualified,
    `Selectors.string()`.
    """
    string() = _dtype_one(API.PolarsValueTypeString)

    """
        boolean()::Selector

    Selects `Bool`-dtype columns.
    """
    boolean() = _dtype_one(API.PolarsValueTypeBoolean)

    """
        binary()::Selector

    Selects Binary (`Vector{UInt8}`)-dtype columns.
    """
    binary() = _dtype_one(API.PolarsValueTypeBinary)

    """
        date()::Selector

    Selects `Date`-dtype columns.
    """
    date() = _dtype_one(API.PolarsValueTypeDate)

    """
        time()::Selector

    Selects `Dates.Time`-dtype columns. Not exported (would clobber `Base.time`) -- use qualified,
    `Selectors.time()`.
    """
    time() = _dtype_one(API.PolarsValueTypeTime)

    """
    Maps a Julia type to the `polars_value_type_t` C enum code [`by_dtype`](@ref) sends across the
    FFI boundary. Delegates the plain, parameter-free dtypes to `Polars._plain_value_type_code` --
    the same table `cast` uses, kept in one place rather than duplicated here -- and handles the
    two parametrized-in-Rust exceptions itself: `DateTime`/duration `Period` subtypes reach the
    Rust side's own `to_dtype`, which deliberately rejects them, since Datetime/Duration need a
    time unit (and Datetime a time zone) that a bare type code can't carry (use
    [`datetime`](@ref)/[`duration`](@ref) instead) -- surfacing a real `PolarsError` rather than
    failing earlier in Julia with an unrelated kind of error.
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

    Selects columns whose dtype is one of `dtypes`, given as Julia types (e.g.
    `by_dtype(Int64, Float64)`, matching the same type spellings [`cast`](@ref) accepts). `Datetime`,
    duration `Period` subtypes, `Decimal`, `List`, and `Struct` need parameters a plain dtype code
    can't carry, so passing one of those (e.g. `by_dtype(DateTime)`) raises a `PolarsError` -- use
    [`datetime`](@ref)/[`duration`](@ref)/[`decimal`](@ref)/[`list`](@ref)/[`struct_`](@ref) instead.
    `by_dtype()` (no dtypes) is a valid selector that matches zero columns, same as any other
    selector with nothing to match.

    !!! note "A single argument is deliberately *not* also accepted as a collection"
        Unlike some other verbs in this package, there is no second `by_dtype(dtypes::AbstractVector)`
        method: with one, dispatching `by_dtype(dtypes)` on a *single* bare type (the most natural
        call, e.g. `by_dtype(DateTime)`) is ambiguous with dispatching it as a one-element varargs
        call, and Julia resolves that ambiguity by treating the single argument as the iterable itself
        -- silently trying to iterate `DateTime` (a `Type`, not a collection) rather than treating it
        as one dtype. Always call with each dtype as its own argument.
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

    Selects the given column names explicitly. If `strict` (default), selecting a name absent from
    the frame raises a `PolarsError` at `select`/`with_columns`/... time; if not, a missing name is
    silently skipped. `by_name()` (no names) is a valid selector that matches zero columns.
    """
    function by_name(names::Vector{String}; strict::Bool = true)
        out = Ref{Ptr{polars_expr_t}}()
        GC.@preserve names begin
            ptrs, lens = _name_ptrs(names)
            err = API.polars_expr_selector_by_name(ptrs, lens, length(ptrs), strict, out)
        end
        polars_error(err)
        return _wrap(out[])
    end
    by_name(names::AbstractString...; strict::Bool = true) =
        by_name(collect(String, names); strict)

    """
        by_index(indices::Integer...; strict::Bool=true)::Selector

    Selects columns by position. **1-based**, matching this package's own [`nth`](@ref) (py-polars'
    own `cs.by_index` is 0-based -- see [`Selectors`](@ref)'s note on this divergence). Negative
    indices count from the end (`by_index(-1)` is the last column, same as `nth(-1)`). If `strict`
    (default), an out-of-range index raises a `PolarsError`; if not, it is silently skipped.
    """
    function by_index(indices::Vector{<:Integer}; strict::Bool = true)
        zero_based = Int64[i < 0 ? Int64(i) : Int64(i) - 1 for i in indices]
        out = API.polars_expr_selector_by_index(zero_based, length(zero_based), strict)
        return _wrap(out)
    end
    by_index(indices::Integer...; strict::Bool = true) = by_index(collect(Integer, indices); strict)

    function _matches_kind(kind, pattern::AbstractString)
        out = Ref{Ptr{polars_expr_t}}()
        err = API.polars_expr_selector_matches(kind, pattern, ncodeunits(pattern), out)
        polars_error(err)
        return _wrap(out[])
    end

    """
        matches(pattern::AbstractString)::Selector

    Selects column names matching the regex `pattern` (used verbatim, unanchored -- the underlying
    polars regex engine, not Julia's `Regex`/PCRE).
    """
    matches(pattern::AbstractString) = _matches_kind(API.PolarsSelectorMatchKindRegex, pattern)

    """
        starts_with(prefixes::AbstractString...)::Selector

    Selects column names starting with any of `prefixes` (a literal substring match, not a regex --
    any regex metacharacters in `prefixes` are matched literally, escaped on the Rust side). At least
    one prefix is required.
    """
    function starts_with(prefixes::AbstractString...)
        isempty(prefixes) &&
            throw(ArgumentError("Selectors.starts_with requires at least one prefix"))
        return reduce(|, _matches_kind(API.PolarsSelectorMatchKindStartsWith, p) for p in prefixes)
    end

    """
        ends_with(suffixes::AbstractString...)::Selector

    Selects column names ending with any of `suffixes` (a literal substring match, not a regex -- any
    regex metacharacters in `suffixes` are matched literally, escaped on the Rust side). At least one
    suffix is required.
    """
    function ends_with(suffixes::AbstractString...)
        isempty(suffixes) && throw(ArgumentError("Selectors.ends_with requires at least one suffix"))
        return reduce(|, _matches_kind(API.PolarsSelectorMatchKindEndsWith, p) for p in suffixes)
    end

    """
        contains(substrings::AbstractString...)::Selector

    Selects column names containing any of `substrings` anywhere (a literal substring match, not a
    regex -- any regex metacharacters in `substrings` are matched literally, escaped on the Rust
    side). At least one substring is required. Not exported (would clobber `Base.contains`) -- use
    qualified, `Selectors.contains(...)`.
    """
    function contains(substrings::AbstractString...)
        isempty(substrings) &&
            throw(ArgumentError("Selectors.contains requires at least one substring"))
        return reduce(|, _matches_kind(API.PolarsSelectorMatchKindContains, p) for p in substrings)
    end

    export numeric, integer, unsigned_integer, signed_integer, boolean, binary,
        temporal, categorical, date, datetime, duration, decimal, struct_, list, array, nested,
        by_dtype, by_name, by_index, matches, starts_with, ends_with
    # `all`/`float`/`string`/`time`/`contains` are deliberately *not* exported -- each collides with
    # an exported `Base` binding (`Base.all`/`Base.float`/`Base.string`/`Base.time`/`Base.contains`),
    # so `using Polars.Selectors` would otherwise clash with those (same reasoning as `Lists`'
    # `get`/`contains`/`head`, `Strings`' none, `Dt`'s none -- this namespace collides the most since
    # it mirrors so much of `Base`'s own vocabulary). Qualified use (`Selectors.all()`, etc.) always
    # works regardless.

end # module Selectors
