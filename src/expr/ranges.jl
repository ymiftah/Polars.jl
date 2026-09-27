# Temporal constructors (`datetime`, `duration`, `date`, `Base.time`, `from_epoch`) and range
# functions (`int_range`, `date_range`, `datetime_range`, `time_range`).

"""
    datetime(year, month, day; hour=0, minute=0, second=0, microsecond=0,
             time_unit::Symbol=:us, time_zone::Union{Nothing,AbstractString}=nothing,
             ambiguous::AbstractString="raise")::Polars.Expr

Construct a column of `Datetime` from the provided components (expressions or scalars).
`ambiguous` is as in `Dt.replace_time_zone`.

Note: unless all inputs are literals, the output column is named `"datetime"`.
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

Construct a column of `Duration` from the provided components (expressions or scalars).
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

Construct a column of `Date` from the provided components (expressions or scalars). The output
column is named `"date"`.
"""
date(year, month, day) = alias(Dt.date(datetime(year, month, day)), "date")

export date

const _TimeComponent = Union{Expr, Real}

"""
    time(hour, minute=0, second=0, microsecond=0)::Polars.Expr

Construct a column of `Time` from the provided components (expressions or reals). The output
column is named `"time"`.
"""
Base.time(
    hour::_TimeComponent, minute::_TimeComponent = 0,
    second::_TimeComponent = 0, microsecond::_TimeComponent = 0,
) = alias(Dt.time(datetime(1970, 1, 1; hour, minute, second, microsecond)), "time")

export time

"""
    from_epoch(expr::Polars.Expr, time_unit::Symbol=:s)::Polars.Expr

Convert a numeric column of time since the UNIX epoch, in `time_unit` (`:ns`, `:us`, `:ms`, `:s`,
`:d`), to `Datetime` (or `Date` for `:d`). `:s` and `:ms` give a `Datetime` in microseconds.
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

"""
    int_range(start, stop; step::Integer=1, dtype::Type=Int64)::Polars.Expr

Generate a range of integers.

Note: `stop` (exclusive) is `end` upstream.
"""
function int_range(start, stop; step::Integer = 1, dtype::Type = Int64)
    start = convert(Expr, start)
    stop = convert(Expr, stop)
    dtype_enum = _plain_value_type_code(dtype)
    dtype_enum === nothing && error("could not use $dtype as an int_range dtype")
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_int_range(start, stop, Int64(step), dtype_enum, out)
    polars_error(err)
    return Expr(out[])
end

export int_range

"""
    date_range(start, stop; interval::AbstractString="1d", closed::Symbol=:both)::Polars.Expr

Create a date range column from `start`, `stop`, and `interval`.

Note: `stop` is `end` upstream. `num_samples` is not supported.
"""
function date_range(start, stop; interval::AbstractString = "1d", closed::Symbol = :both)
    start = convert(Expr, start)
    stop = convert(Expr, stop)
    closed_enum = _closed_window_enum(closed)
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_date_range(start, stop, interval, ncodeunits(interval), closed_enum, out)
    polars_error(err)
    return Expr(out[])
end

export date_range

"""
    datetime_range(start, stop; interval::AbstractString="1d", closed::Symbol=:both,
                   time_unit::Symbol=:us, time_zone::Union{Nothing,AbstractString}=nothing)::Polars.Expr

Create a datetime range from `start`, `stop`, and `interval`.

Note: `stop` is `end` upstream. `num_samples` is not supported.
"""
function datetime_range(
        start, stop; interval::AbstractString = "1d", closed::Symbol = :both,
        time_unit::Symbol = :us, time_zone::Union{Nothing, AbstractString} = nothing,
    )
    start = convert(Expr, start)
    stop = convert(Expr, stop)
    closed_enum = _closed_window_enum(closed)
    unit_enum = _time_unit_enum(time_unit)
    tz = time_zone === nothing ? "" : String(time_zone)
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_datetime_range(
        start, stop, interval, ncodeunits(interval), closed_enum, unit_enum, tz, ncodeunits(tz), out
    )
    polars_error(err)
    return Expr(out[])
end

export datetime_range

"""
    time_range(start, stop; interval::AbstractString="1d", closed::Symbol=:both)::Polars.Expr

Generate a time range.

Note: `stop` is `end` upstream.
"""
function time_range(start, stop; interval::AbstractString = "1d", closed::Symbol = :both)
    start = convert(Expr, start)
    stop = convert(Expr, stop)
    closed_enum = _closed_window_enum(closed)
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_time_range(start, stop, interval, ncodeunits(interval), closed_enum, out)
    polars_error(err)
    return Expr(out[])
end

export time_range
