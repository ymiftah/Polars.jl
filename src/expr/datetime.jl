module Dt
using ..Polars: @wrap_simple_ops, @wrap_expr_method, @curry, API, polars_expr_t, Expr, polars_error, cast, floor_div, _time_unit_enum

@wrap_simple_ops begin
    gen_impl_expr_dt!(polars_expr_dt_year, DateLikeNameSpace::year, "Extracts the year component of each Date/Datetime value in `expr`.")
    gen_impl_expr_dt!(polars_expr_dt_month, DateLikeNameSpace::month, "Extracts the month component (1-12) of each Date/Datetime value in `expr`.")
    gen_impl_expr_dt!(polars_expr_dt_day, DateLikeNameSpace::day, "Extracts the day-of-month component (1-31) of each Date/Datetime value in `expr`.")
    gen_impl_expr_dt!(polars_expr_dt_hour, DateLikeNameSpace::hour, "Extracts the hour component (0-23) of each Datetime value in `expr`.")
    gen_impl_expr_dt!(polars_expr_dt_minute, DateLikeNameSpace::minute, "Extracts the minute component (0-59) of each Datetime value in `expr`.")
    gen_impl_expr_dt!(polars_expr_dt_second, DateLikeNameSpace::second, "Extracts the second component (0-59) of each Datetime value in `expr`.")
    gen_impl_expr_dt!(polars_expr_dt_weekday, DateLikeNameSpace::weekday, "Day of the week for each Date/Datetime value in `expr`: `1` (Monday) through `7` (Sunday), ISO 8601 numbering.")
    gen_impl_expr_dt!(polars_expr_dt_ordinal_day, DateLikeNameSpace::ordinal_day, "Day of the year (1-366) for each Date/Datetime value in `expr`.")
    gen_impl_expr_dt!(polars_expr_dt_week, DateLikeNameSpace::week, "ISO week number (1-53) for each Date/Datetime value in `expr`.")
    gen_impl_expr_dt!(polars_expr_dt_quarter, DateLikeNameSpace::quarter, "Quarter of the year (1-4) for each Date/Datetime value in `expr`.")
    gen_impl_expr_dt!(polars_expr_dt_millisecond, DateLikeNameSpace::millisecond, "Extracts the millisecond component (0-999, the sub-second part) of each Datetime/Time value in `expr`. See [`total_milliseconds`](@ref) for the Duration-typed equivalent.")
    gen_impl_expr_dt!(polars_expr_dt_microsecond, DateLikeNameSpace::microsecond, "Extracts the microsecond component (0-999999, the sub-second part) of each Datetime/Time value in `expr`. See [`total_microseconds`](@ref) for the Duration-typed equivalent.")
    gen_impl_expr_dt!(polars_expr_dt_nanosecond, DateLikeNameSpace::nanosecond, "Extracts the nanosecond component (0-999999999, the sub-second part) of each Datetime/Time value in `expr`. See [`total_nanoseconds`](@ref) for the Duration-typed equivalent.")
    gen_impl_expr_dt!(polars_expr_dt_date, DateLikeNameSpace::date, "Extracts the `Date` component of each Datetime value in `expr` (drops the time-of-day).")
    gen_impl_expr_dt!(polars_expr_dt_time, DateLikeNameSpace::time, "Extracts the `Dates.Time` component of each Datetime value in `expr` (drops the date).")
    gen_impl_expr_dt!(polars_expr_dt_datetime, DateLikeNameSpace::datetime, "Returns the local (wall-clock) `DateTime` value of each value in `expr`, stripping any time zone label without changing the wall-clock value -- identical to `Dt.replace_time_zone(expr, nothing)`, which is the preferred spelling.")
    gen_impl_expr_dt!(polars_expr_dt_iso_year, DateLikeNameSpace::iso_year, "ISO 8601 year of each Date/Datetime value in `expr` -- may differ from the calendar year for dates near a year boundary.")
    gen_impl_expr_dt!(polars_expr_dt_is_leap_year, DateLikeNameSpace::is_leap_year, "Whether the calendar year of each Date/Datetime value in `expr` is a leap year.")
    gen_impl_expr_dt!(polars_expr_dt_century, DateLikeNameSpace::century, "Century (e.g. `21` for years 2001-2100) of each Date/Datetime value in `expr`.")
    gen_impl_expr_dt!(polars_expr_dt_millennium, DateLikeNameSpace::millennium, "Millennium (e.g. `3` for years 2001-3000) of each Date/Datetime value in `expr`.")
    gen_impl_expr_dt!(polars_expr_dt_base_utc_offset, DateLikeNameSpace::base_utc_offset, "The base (non-DST) UTC offset of each Datetime value in `expr`, as a `Dates.Millisecond`-valued Duration. Requires a time-zone-aware Datetime; see [`replace_time_zone`](@ref).")
    gen_impl_expr_dt!(polars_expr_dt_dst_offset, DateLikeNameSpace::dst_offset, "The additional daylight-saving-time UTC offset of each Datetime value in `expr` (zero outside DST), as a `Dates.Millisecond`-valued Duration. Requires a time-zone-aware Datetime; see [`replace_time_zone`](@ref).")

    gen_impl_expr_binary_dt!(polars_expr_dt_truncate, DateLikeNameSpace::truncate, "Truncates each Date/Datetime value of `a` down to the start of the enclosing interval named by the duration string `b` (e.g. `\"1h\"` zeroes out minutes/seconds)."; curried = true)
    gen_impl_expr_binary_dt!(polars_expr_dt_round, DateLikeNameSpace::round, "Rounds each Date/Datetime value of `a` to the nearest interval named by the duration string `b`, rather than always truncating down like [`truncate`](@ref)."; curried = true)
    gen_impl_expr_binary_dt!(polars_expr_dt_offset_by, DateLikeNameSpace::offset_by, "Shifts each Date/Datetime value of `a` by the (possibly signed) duration string `b` (e.g. `\"+1d\"`, `\"-2h\"`)."; curried = true)
end

# The `Fix2`-style curries for the binary namespace ops above (e.g. `col("d") |>
# Dt.truncate("1mo")`) are generated by `@wrap_simple_ops`'s `curried` variant, right next to
# each primal in the block above.

"""
    strftime(expr::Polars.Expr, format::String)::Polars.Expr

Formats a Date/Datetime/Duration/Time expression using a `chrono`-style format string
(e.g. `"%Y-%m-%d"`).
"""
function strftime(expr::Expr, format::AbstractString)
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_dt_strftime(expr, format, ncodeunits(format), out)
    polars_error(err)
    return Expr(out[])
end

"""
    strftime(format::String)::Base.Fix2{typeof(strftime), String}

Curried form of [`strftime`](@ref) for use with `|>`.
"""
strftime(format::AbstractString) = Base.Fix2(strftime, format)

export strftime

"""
    timestamp(expr::Polars.Expr; time_unit::Symbol=:us)::Polars.Expr

Number of `time_unit`s (one of `:ns`, `:us` (default), `:ms`) since the Unix epoch
(1970-01-01) for each Date/Datetime value in `expr`.
"""
function timestamp(expr::Expr; time_unit::Symbol = :us)
    time_unit_enum = _time_unit_enum(time_unit)
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_dt_timestamp(expr, time_unit_enum, out)
    polars_error(err)
    return Expr(out[])
end

"""
    timestamp(; time_unit::Symbol=:us)::Base.Callable

Curried form of [`timestamp`](@ref) for use with `|>`.
"""
timestamp(; time_unit::Symbol = :us) = expr -> timestamp(expr; time_unit)

export timestamp

"""
    cast_time_unit(expr::Polars.Expr; time_unit::Symbol)::Polars.Expr

Changes the underlying `time_unit` (one of `:ns`, `:us`, `:ms`) of `expr` and **rescales the
data** accordingly (e.g. casting `:ms` to `:ns` multiplies each value by `1_000_000`). Compare
[`with_time_unit`](@ref), which relabels without rescaling.
"""
function cast_time_unit(expr::Expr; time_unit::Symbol)
    time_unit_enum = _time_unit_enum(time_unit)
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_dt_cast_time_unit(expr, time_unit_enum, out)
    polars_error(err)
    return Expr(out[])
end

"""
    cast_time_unit(; time_unit::Symbol)::Base.Callable

Curried form of [`cast_time_unit`](@ref) for use with `|>`.
"""
cast_time_unit(; time_unit::Symbol) = expr -> cast_time_unit(expr; time_unit)

export cast_time_unit

"""
    with_time_unit(expr::Polars.Expr; time_unit::Symbol)::Polars.Expr

Relabels the underlying `time_unit` (one of `:ns`, `:us`, `:ms`) of `expr` **without touching the
data** -- e.g. reinterpreting values already at `:ms` as if they were `:ns`, changing what they
mean rather than converting them. Compare [`cast_time_unit`](@ref), which rescales.
"""
function with_time_unit(expr::Expr; time_unit::Symbol)
    time_unit_enum = _time_unit_enum(time_unit)
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_dt_with_time_unit(expr, time_unit_enum, out)
    polars_error(err)
    return Expr(out[])
end

"""
    with_time_unit(; time_unit::Symbol)::Base.Callable

Curried form of [`with_time_unit`](@ref) for use with `|>`.
"""
with_time_unit(; time_unit::Symbol) = expr -> with_time_unit(expr; time_unit)

export with_time_unit

"""
    combine(expr::Polars.Expr, time::Polars.Expr; time_unit::Symbol=:us)::Polars.Expr

Combines a Date/Datetime `expr` with a Time `time`, producing a new Datetime at the given
`time_unit` (one of `:ns`, `:us` (default), `:ms`).
"""
function combine(expr::Expr, time::Expr; time_unit::Symbol = :us)
    time_unit_enum = _time_unit_enum(time_unit)
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_dt_combine(expr, time, time_unit_enum, out)
    polars_error(err)
    return Expr(out[])
end

"""
    combine(time::Polars.Expr; time_unit::Symbol=:us)::Base.Callable

Curried form of [`combine`](@ref) for use with `|>`.
"""
combine(time::Expr; time_unit::Symbol = :us) = expr -> combine(expr, time; time_unit)

export combine

"""
    epoch(expr::Polars.Expr, time_unit::Symbol=:us)::Polars.Expr

Number of `time_unit`s since the Unix epoch (1970-01-01) for each Date/Datetime value in
`expr`. `time_unit` is one of `:ns`, `:us` (default), `:ms`, `:s`, or `:d` (whole days).

For `:ns`/`:us`/`:ms` this is exactly [`timestamp`](@ref); `:s` and `:d` are derived from the
millisecond timestamp by (floored) integer division, matching whole seconds/days since the
epoch.
"""
function epoch(expr::Expr, time_unit::Symbol = :us)
    if time_unit in (:ns, :us, :ms)
        return timestamp(expr; time_unit)
    elseif time_unit == :s
        return floor_div(timestamp(expr; time_unit = :ms), convert(Expr, 1_000))
    elseif time_unit == :d
        days = floor_div(timestamp(expr; time_unit = :ms), convert(Expr, 1_000 * 3600 * 24))
        return cast(days, Int32)
    else
        error("unknown time_unit $time_unit, expected one of (:ns, :us, :ms, :s, :d)")
    end
end

export epoch

"""
    month_start(expr::Polars.Expr)::Polars.Expr

!!! warning "Unavailable in this build"
    See [Developer](@ref) for why, and how to enable it.
"""
function month_start(::Expr)
    return error(
        "Dt.month_start is unavailable in this build: polars' `month_start` requires " *
            "the `month_start` Cargo feature, which c-polars does not currently enable. " *
            "Add it to c-polars/Cargo.toml's `polars` feature list and rebuild to enable it."
    )
end

"""
    month_end(expr::Polars.Expr)::Polars.Expr

!!! warning "Unavailable in this build"
    See [Developer](@ref) for why, and how to enable it.
"""
function month_end(::Expr)
    return error(
        "Dt.month_end is unavailable in this build: polars' `month_end` requires " *
            "the `month_end` Cargo feature, which c-polars does not currently enable. " *
            "Add it to c-polars/Cargo.toml's `polars` feature list and rebuild to enable it."
    )
end

@wrap_expr_method total_days(expr::Expr; fractional::Bool = false) polars_expr_dt_total_days "Total number of whole days represented by each Duration value in `expr` (truncated toward zero). Pass `fractional=true` for the exact value as a `Float64` instead."
@curry total_days(; fractional::Bool = false)
export total_days

@wrap_expr_method total_hours(expr::Expr; fractional::Bool = false) polars_expr_dt_total_hours "Total number of whole hours represented by each Duration value in `expr` (truncated toward zero). Pass `fractional=true` for the exact value as a `Float64` instead."
@curry total_hours(; fractional::Bool = false)
export total_hours

@wrap_expr_method total_minutes(expr::Expr; fractional::Bool = false) polars_expr_dt_total_minutes "Total number of whole minutes represented by each Duration value in `expr` (truncated toward zero). Pass `fractional=true` for the exact value as a `Float64` instead."
@curry total_minutes(; fractional::Bool = false)
export total_minutes

@wrap_expr_method total_seconds(expr::Expr; fractional::Bool = false) polars_expr_dt_total_seconds "Total number of whole seconds represented by each Duration value in `expr` (truncated toward zero). Pass `fractional=true` for the exact value as a `Float64` instead."
@curry total_seconds(; fractional::Bool = false)
export total_seconds

@wrap_expr_method total_milliseconds(expr::Expr; fractional::Bool = false) polars_expr_dt_total_milliseconds "Total number of whole milliseconds represented by each Duration value in `expr` (truncated toward zero). Pass `fractional=true` for the exact value as a `Float64` instead."
@curry total_milliseconds(; fractional::Bool = false)
export total_milliseconds

@wrap_expr_method total_microseconds(expr::Expr; fractional::Bool = false) polars_expr_dt_total_microseconds "Total number of whole microseconds represented by each Duration value in `expr` (truncated toward zero). Pass `fractional=true` for the exact value as a `Float64` instead."
@curry total_microseconds(; fractional::Bool = false)
export total_microseconds

@wrap_expr_method total_nanoseconds(expr::Expr; fractional::Bool = false) polars_expr_dt_total_nanoseconds "Total number of whole nanoseconds represented by each Duration value in `expr` (truncated toward zero). Pass `fractional=true` for the exact value as a `Float64` instead."
@curry total_nanoseconds(; fractional::Bool = false)
export total_nanoseconds

"""
    convert_time_zone(expr::Polars.Expr, tz::String)::Polars.Expr

Re-labels a Datetime expression's instant into a different IANA time zone `tz` (e.g.
`"America/New_York"`) -- the underlying instant is unchanged, only the display/interpretation
changes. Compare [`replace_time_zone`](@ref), which does the opposite (preserves the
wall-clock value, changes the instant).

!!! note
    Reading the *result* back into Julia (e.g. via `df[:col]`) needs `TimeZones.jl` loaded
    (`using TimeZones`) -- a naive read otherwise errors with an explanatory message.
"""
function convert_time_zone(expr::Expr, tz::AbstractString)
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_dt_convert_time_zone(expr, tz, ncodeunits(tz), out)
    polars_error(err)
    return Expr(out[])
end

"""
    convert_time_zone(tz::String)::Base.Fix2{typeof(convert_time_zone), String}

Curried form of [`convert_time_zone`](@ref) for use with `|>`.
"""
convert_time_zone(tz::AbstractString) = Base.Fix2(convert_time_zone, tz)

export convert_time_zone

"""
    replace_time_zone(expr::Polars.Expr, tz::Union{Nothing,String} = nothing;
                       ambiguous::String = "raise", non_existent::Symbol = :raise)::Polars.Expr

Attaches, strips (`tz = nothing`), or re-attaches a time zone label to the expression's
*local wall-clock* values -- unlike [`convert_time_zone`](@ref), which preserves the instant
and only changes the label.

`ambiguous` controls how a local time that occurs twice (e.g. a DST fall-back) is resolved:
one of `"raise"`, `"earliest"`, `"latest"`, `"null"`. `non_existent` controls how a local time
that never occurs (e.g. a DST spring-forward gap) is resolved: `:raise` or `:null`.
"""
function replace_time_zone(
        expr::Expr, tz::Union{Nothing, AbstractString} = nothing;
        ambiguous::AbstractString = "raise", non_existent::Symbol = :raise
    )
    non_existent_enum = if non_existent == :raise
        API.PolarsNonExistentRaise
    elseif non_existent == :null
        API.PolarsNonExistentNull
    else
        error("unknown non_existent mode $non_existent, expected one of (:raise, :null)")
    end

    tz_str = tz === nothing ? "" : tz
    out = Ref{Ptr{polars_expr_t}}()
    err = API.polars_expr_dt_replace_time_zone(
        expr, tz_str, ncodeunits(tz_str), convert(Expr, ambiguous), non_existent_enum, out
    )
    polars_error(err)
    return Expr(out[])
end

"""
    replace_time_zone(tz::Union{Nothing,String} = nothing; ambiguous::String = "raise",
                       non_existent::Symbol = :raise)::Base.Callable

Curried form of [`replace_time_zone`](@ref) for use with `|>`.
"""
function replace_time_zone(
        tz::Union{Nothing, AbstractString} = nothing;
        ambiguous::AbstractString = "raise", non_existent::Symbol = :raise
    )
    return expr -> replace_time_zone(expr, tz; ambiguous, non_existent)
end

export replace_time_zone

@wrap_expr_method replace(
    expr::Expr;
    year::Expr = convert(Expr, missing), month::Expr = convert(Expr, missing),
    day::Expr = convert(Expr, missing), hour::Expr = convert(Expr, missing),
    minute::Expr = convert(Expr, missing), second::Expr = convert(Expr, missing),
    microsecond::Expr = convert(Expr, missing), ambiguous::Expr = convert(Expr, "raise")
) polars_expr_dt_replace "Replaces the given date/time components of each value in `expr` with new ones. Each of `year`/`month`/`day`/`hour`/`minute`/`second`/`microsecond` may be a plain integer or a full column expression; the default `missing` keeps that component's existing value unchanged. `ambiguous` controls how a resulting local time that occurs twice (e.g. a DST fall-back) is resolved, same values as [`replace_time_zone`](@ref)'s `ambiguous`."
@curry replace(;
    year::Expr = convert(Expr, missing), month::Expr = convert(Expr, missing),
    day::Expr = convert(Expr, missing), hour::Expr = convert(Expr, missing),
    minute::Expr = convert(Expr, missing), second::Expr = convert(Expr, missing),
    microsecond::Expr = convert(Expr, missing), ambiguous::Expr = convert(Expr, "raise")
)
export replace
end # module Dt

export Dt
