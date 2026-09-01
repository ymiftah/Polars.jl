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
neither does upstream py-polars, whose own `pl.date` does the same composition in Python).
"""
date(year, month, day) = Dt.date(datetime(year, month, day))

export date

"""
    Base.time(hour, minute=0, second=0, microsecond=0)::Polars.Expr

Constructs a `Dates.Time` column from component expressions (or plain scalars). Extends
`Base.time` (which takes no arguments and returns wall-clock seconds) rather than shadowing it --
same precedent as this package's `Base.get`/`Base.sort`/`Base.tail` extensions in
`src/expr/expr.jl`.
"""
Base.time(hour, minute = 0, second = 0, microsecond = 0) =
    Dt.time(datetime(1970, 1, 1; hour, minute, second, microsecond))

export time

"""
    from_epoch(expr::Polars.Expr, time_unit::Symbol=:s)::Polars.Expr

Interprets `expr` (an integer column) as a count of `time_unit`s since the Unix epoch and
constructs the corresponding `Date`/`DateTime` column -- the inverse of `Dt.epoch`, whose own
scaling logic for `:s`/`:d` this mirrors. One of `:ns`, `:us`, `:ms` (direct physical cast to
`Datetime`), `:s` (scaled to `:ms` first -- `Datetime` has no seconds-resolution variant), or `:d`
(cast to `Date`, whose physical representation is already days-since-epoch).
"""
function from_epoch(expr::Expr, time_unit::Symbol = :s)
    if time_unit in (:ns, :us, :ms)
        return cast_datetime(expr; time_unit)
    elseif time_unit == :s
        return cast_datetime(expr * convert(Expr, 1_000); time_unit = :ms)
    elseif time_unit == :d
        return cast(expr, Date)
    else
        error("unknown time_unit $time_unit, expected one of (:ns, :us, :ms, :s, :d)")
    end
end

export from_epoch
