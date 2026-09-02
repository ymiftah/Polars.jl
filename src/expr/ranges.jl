# Component-wise temporal constructors: `datetime`/`duration`/`date`/`Base.time`/`from_epoch`.
# Named to match `plans/parity/range_temporal_constructors.md`'s Task 2 expectation, so a future
# `range` Cargo-feature PR can append `int_range`/`date_range`/`datetime_range`/`time_range` here
# without moving anything.

"""
    datetime(year, month, day; hour=0, minute=0, second=0, microsecond=0,
             time_unit::Symbol=:us, time_zone::Union{Nothing,AbstractString}=nothing,
             ambiguous::AbstractString="raise")::Polars.Expr

Constructs a `DateTime` column from component expressions (or plain scalars). Distinct from
[`cast_datetime`](@ref), which reinterprets/casts an existing value rather than building one from
parts. `ambiguous` controls how a local time that occurs twice (a DST fall-back) resolves -- same
values as `Dt.replace_time_zone`'s `ambiguous`.

The output column is always named `"datetime"` for any non-all-literal input (an upstream Rust
`Expr::Alias(..., "datetime")` this package's binding calls unmodified, see `CLAUDE.md`) -- not the
first argument's own name (e.g. `"year"`), which a newer upstream py-polars test
(`test_datetime_name`) expects. That naming ("follow left-hand rule") is marked `// TODO: ... in
Polars 2.0` in the exact `polars-plan` version this package is pinned to (`0.54.4`) and is not yet
implemented there; confirmed live, not fixable from this package without bumping the vendored
crate version (out of scope here, see `plans/parity/tier12-sweep-temporal.md`).
"""
function datetime(
        year, month, day; hour = 0, minute = 0, second = 0, microsecond = 0,
        time_unit::Symbol = :us, time_zone::Union{Nothing, AbstractString} = nothing,
        ambiguous::AbstractString = "raise"
    )
    year = convert(Expr, year)
    month = convert(Expr, month)
    day = convert(Expr, day)
    hour = convert(Expr, hour)
    minute = convert(Expr, minute)
    second = convert(Expr, second)
    microsecond = convert(Expr, microsecond)
    unit_enum = _time_unit_enum(time_unit)
    tz = time_zone === nothing ? "" : String(time_zone)
    ambiguous = String(ambiguous)
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_datetime(
        year, month, day, hour, minute, second, microsecond, unit_enum,
        tz, ncodeunits(tz), ambiguous, ncodeunits(ambiguous), out
    )
    polars_error(err)
    return Expr(out[])
end

export datetime

"""
    duration(; weeks=0, days=0, hours=0, minutes=0, seconds=0, milliseconds=0, microseconds=0,
              nanoseconds=0, time_unit::Symbol=:us)::Polars.Expr

Constructs a `Duration` column from component expressions (or plain scalars), each may be
negative. Distinct from [`cast_duration`](@ref), which reinterprets/casts an existing value.
"""
function duration(;
        weeks = 0, days = 0, hours = 0, minutes = 0, seconds = 0,
        milliseconds = 0, microseconds = 0, nanoseconds = 0, time_unit::Symbol = :us
    )
    weeks = convert(Expr, weeks)
    days = convert(Expr, days)
    hours = convert(Expr, hours)
    minutes = convert(Expr, minutes)
    seconds = convert(Expr, seconds)
    milliseconds = convert(Expr, milliseconds)
    microseconds = convert(Expr, microseconds)
    nanoseconds = convert(Expr, nanoseconds)
    unit_enum = _time_unit_enum(time_unit)
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_duration(
        weeks, days, hours, minutes, seconds, milliseconds, microseconds, nanoseconds, unit_enum, out
    )
    polars_error(err)
    return Expr(out[])
end

export duration

"""
    date(year, month, day)::Polars.Expr

Constructs a `Date` column from component expressions (or plain scalars). Composes
[`datetime`](@ref) + `Dt.date` (this package has no separate Rust-side `Date` constructor --
neither does upstream py-polars, whose own `pl.date` does the same composition in Python), and
matches upstream's own explicit `.alias("date")` on the result -- `datetime`'s own output name
(currently always `"datetime"`, see its docstring) would otherwise leak through unchanged, since
`Dt.date` (a plain namespaced extraction) does not rename its input.
"""
date(year, month, day) = alias(Dt.date(datetime(year, month, day)), "date")

export date

const _TimeComponent = Union{Expr, Real}

"""
    Base.time(hour, minute=0, second=0, microsecond=0)::Polars.Expr

Constructs a `Dates.Time` column from component expressions (or plain scalars). Extends
`Base.time` (which takes no arguments and returns wall-clock seconds) rather than shadowing it --
same precedent as this package's `Base.get`/`Base.sort`/`Base.tail` extensions in
`src/expr/expr.jl`.

Arguments are constrained to `Expr`/`Real` rather than left untyped: `time` is both a `Base`
function and exported from here, so an `Any`-typed extension would capture *every* two-to-four
argument `time(...)` call in any downstream session, turning what should be a `MethodError` into a
confusing failure inside expression construction. Aliased to `"time"` on the result, matching
upstream's own explicit `.alias("time")` -- see [`date`](@ref)'s docstring for why this is needed
rather than relying on `datetime`'s output name.
"""
Base.time(
    hour::_TimeComponent, minute::_TimeComponent = 0,
    second::_TimeComponent = 0, microsecond::_TimeComponent = 0,
) = alias(Dt.time(datetime(1970, 1, 1; hour, minute, second, microsecond)), "time")

export time

"""
    from_epoch(expr::Polars.Expr, time_unit::Symbol=:s)::Polars.Expr

Interprets `expr` (a numeric column) as a count of `time_unit`s since the Unix epoch and
constructs the corresponding `Date`/`DateTime` column -- the inverse of `Dt.epoch`. Mirrors
upstream `pl.from_epoch`'s own scaling exactly (`py-polars/src/polars/functions/lazy.py`): `:ns`/
`:us` are a direct physical cast to `Datetime` at that same resolution; `:s`/`:ms` are scaled up
to *microseconds* first (`:s` x1_000_000, `:ms` x1_000) and always land on `Datetime(:us)` --
**not** a direct physical cast to `Datetime(:ms)`, which would silently truncate a fractional-
second/sub-millisecond input; `:d` casts to `Date`, whose physical representation is already
days-since-epoch.
"""
function from_epoch(expr::Expr, time_unit::Symbol = :s)
    if time_unit in (:ns, :us)
        return cast_datetime(expr; time_unit)
    elseif time_unit == :s
        return cast_datetime(expr * convert(Expr, 1_000_000); time_unit = :us)
    elseif time_unit == :ms
        return cast_datetime(expr * convert(Expr, 1_000); time_unit = :us)
    elseif time_unit == :d
        return cast(expr, Date)
    else
        error("unknown time_unit $time_unit, expected one of (:ns, :us, :ms, :s, :d)")
    end
end

export from_epoch
