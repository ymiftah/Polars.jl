module Dt
    using ..Polars: @wrap_simple_ops, @wrap_expr_method, @curry, API, polars_expr_t, Expr, polars_error, cast, floor_div, _time_unit_enum

    @wrap_simple_ops begin
        gen_impl_expr_dt!(polars_expr_dt_year, DateLikeNameSpace::year, "Get the year of a Date/Datetime.")
        gen_impl_expr_dt!(polars_expr_dt_month, DateLikeNameSpace::month, "Get the month of a Date/Datetime.")
        gen_impl_expr_dt!(polars_expr_dt_day, DateLikeNameSpace::day, "Get the day of a Date/Datetime.")
        gen_impl_expr_dt!(polars_expr_dt_hour, DateLikeNameSpace::hour, "Get the hour of a Datetime/Time64.")
        gen_impl_expr_dt!(polars_expr_dt_minute, DateLikeNameSpace::minute, "Get the minute of a Datetime/Time64.")
        gen_impl_expr_dt!(polars_expr_dt_second, DateLikeNameSpace::second, "Get the second of a Datetime/Time64.")
        gen_impl_expr_dt!(polars_expr_dt_weekday, DateLikeNameSpace::weekday, "Extract the ISO week day from the underlying Date representation. Can be performed on Date and Datetime.\n\nReturns the weekday number where monday = 1 and sunday = 7.")
        gen_impl_expr_dt!(polars_expr_dt_ordinal_day, DateLikeNameSpace::ordinal_day, "Get the ordinal_day of a Date/Datetime.")
        gen_impl_expr_dt!(polars_expr_dt_week, DateLikeNameSpace::week, "Extract the week from the underlying Date representation. Can be performed on Date and Datetime.\n\nReturns the ISO week number starting from 1. The return value ranges from 1 to 53. (The last week of year differs by years.)")
        gen_impl_expr_dt!(polars_expr_dt_quarter, DateLikeNameSpace::quarter, "Extract quarter from underlying NaiveDateTime representation. Quarters range from 1 to 4.")
        gen_impl_expr_dt!(polars_expr_dt_millisecond, DateLikeNameSpace::millisecond, "Get the millisecond of a Time64 (scaled from nanosecs).")
        gen_impl_expr_dt!(polars_expr_dt_microsecond, DateLikeNameSpace::microsecond, "Get the microsecond of a Time64 (scaled from nanosecs).")
        gen_impl_expr_dt!(polars_expr_dt_nanosecond, DateLikeNameSpace::nanosecond, "Get the nanosecond part of a Time64.")
        gen_impl_expr_dt!(polars_expr_dt_date, DateLikeNameSpace::date, "Get the (local) date of a Date/Datetime.")
        gen_impl_expr_dt!(polars_expr_dt_time, DateLikeNameSpace::time, "Get the (local) time of a Date/Datetime/Time.")
        gen_impl_expr_dt!(polars_expr_dt_datetime, DateLikeNameSpace::datetime, "Get the (local) datetime of a Datetime.")
        gen_impl_expr_dt!(polars_expr_dt_iso_year, DateLikeNameSpace::iso_year, "Get the iso-year of a Date/Datetime. This may not correspond with a calendar year.")
        gen_impl_expr_dt!(polars_expr_dt_is_leap_year, DateLikeNameSpace::is_leap_year, "Determine whether the year of a Date/Datetime is a leap year.")
        gen_impl_expr_dt!(polars_expr_dt_century, DateLikeNameSpace::century, "Get the century of a Date/Datetime.")
        gen_impl_expr_dt!(polars_expr_dt_millennium, DateLikeNameSpace::millennium, "Get the millennium of a Date/Datetime.")
        gen_impl_expr_dt!(polars_expr_dt_base_utc_offset, DateLikeNameSpace::base_utc_offset, "Get the base offset from UTC.")
        gen_impl_expr_dt!(polars_expr_dt_dst_offset, DateLikeNameSpace::dst_offset, "Get the additional offset from UTC currently in effect (usually due to daylight saving time).")

        gen_impl_expr_binary_dt!(polars_expr_dt_truncate, DateLikeNameSpace::truncate, "Truncate the Datetime/Date range into buckets. `b` is a duration string such as `\"1h\"`.\n\n!!! note \"Has a curried form\"\n    `truncate(every)`, for `|>` pipelines."; curried = true)
        gen_impl_expr_binary_dt!(polars_expr_dt_round, DateLikeNameSpace::round, "Round the Datetime/Date range into buckets. `b` is a duration string such as `\"1h\"`.\n\n!!! note \"Has a curried form\"\n    `round(every)`, for `|>` pipelines."; curried = true)
        gen_impl_expr_binary_dt!(polars_expr_dt_offset_by, DateLikeNameSpace::offset_by, "Offset this `Date/Datetime` by a given offset `Duration`, such as `\"-2h\"`. This will take leap years/ months into account.\n\n!!! note \"Has a curried form\"\n    `offset_by(by)`, for `|>` pipelines."; curried = true)
    end


    """
        strftime(expr::Polars.Expr, format::String)::Polars.Expr

    Convert from Date/Time/Datetime into String with the given format. See
    [chrono strftime/strptime](https://docs.rs/chrono/latest/chrono/format/strftime/index.html).

    Alias for [`to_string`](@ref).
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
        to_string(expr::Polars.Expr, format::String)::Polars.Expr

    Convert from Date/Time/Datetime into String with the given format. See
    [chrono strftime/strptime](https://docs.rs/chrono/latest/chrono/format/strftime/index.html).
    """
    to_string(expr::Expr, format::AbstractString) = strftime(expr, format)

    """
        to_string(format::String)::Base.Fix2{typeof(to_string), String}

    Curried form of [`to_string`](@ref) for use with `|>`.
    """
    to_string(format::AbstractString) = Base.Fix2(to_string, format)

    export to_string

    """
        timestamp(expr::Polars.Expr; time_unit::Symbol=:us)::Polars.Expr

    Return the timestamp (UNIX epoch) of a Datetime/Date, in `time_unit` (`:ns`, `:us`, `:ms`).
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

    Change the underlying time unit (`:ns`, `:us`, `:ms`). And update the data accordingly.
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

    Change the underlying time unit (`:ns`, `:us`, `:ms`) of the Series. This does not modify the
    data.
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

    Combine an existing Date/Datetime with a Time, creating a new Datetime value.
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

    Return the time passed since the UNIX epoch in `time_unit`: `:ns`, `:us`, `:ms`, `:s` or `:d`.
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

    Roll backward to the first day of the month.

    Note: unavailable in this build; see [Limitations](@ref).
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

    Roll forward to the last day of the month.

    Note: unavailable in this build; see [Limitations](@ref).
    """
    function month_end(::Expr)
        return error(
            "Dt.month_end is unavailable in this build: polars' `month_end` requires " *
                "the `month_end` Cargo feature, which c-polars does not currently enable. " *
                "Add it to c-polars/Cargo.toml's `polars` feature list and rebuild to enable it."
        )
    end

    @wrap_expr_method total_days(expr::Expr; fractional::Bool = false) polars_expr_dt_total_days "Express a Duration in terms of its total number of integer days.\n\nWith `fractional=true`, returns the exact value as a `Float64`."
    @curry total_days(; fractional::Bool = false)
    export total_days

    @wrap_expr_method total_hours(expr::Expr; fractional::Bool = false) polars_expr_dt_total_hours "Express a Duration in terms of its total number of integer hours.\n\nWith `fractional=true`, returns the exact value as a `Float64`."
    @curry total_hours(; fractional::Bool = false)
    export total_hours

    @wrap_expr_method total_minutes(expr::Expr; fractional::Bool = false) polars_expr_dt_total_minutes "Express a Duration in terms of its total number of integer minutes.\n\nWith `fractional=true`, returns the exact value as a `Float64`."
    @curry total_minutes(; fractional::Bool = false)
    export total_minutes

    @wrap_expr_method total_seconds(expr::Expr; fractional::Bool = false) polars_expr_dt_total_seconds "Express a Duration in terms of its total number of integer seconds.\n\nWith `fractional=true`, returns the exact value as a `Float64`."
    @curry total_seconds(; fractional::Bool = false)
    export total_seconds

    @wrap_expr_method total_milliseconds(expr::Expr; fractional::Bool = false) polars_expr_dt_total_milliseconds "Express a Duration in terms of its total number of milliseconds.\n\nWith `fractional=true`, returns the exact value as a `Float64`."
    @curry total_milliseconds(; fractional::Bool = false)
    export total_milliseconds

    @wrap_expr_method total_microseconds(expr::Expr; fractional::Bool = false) polars_expr_dt_total_microseconds "Express a Duration in terms of its total number of microseconds.\n\nWith `fractional=true`, returns the exact value as a `Float64`."
    @curry total_microseconds(; fractional::Bool = false)
    export total_microseconds

    @wrap_expr_method total_nanoseconds(expr::Expr; fractional::Bool = false) polars_expr_dt_total_nanoseconds "Express a Duration in terms of its total number of nanoseconds.\n\nWith `fractional=true`, returns the exact value as a `Float64`."
    @curry total_nanoseconds(; fractional::Bool = false)
    export total_nanoseconds

    """
        convert_time_zone(expr::Polars.Expr, tz::String)::Polars.Expr

    Change the underlying time zone of the Series. This does not modify the data.

    Note: reading a time-zone-aware result into Julia requires TimeZones.jl.
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

    Replace the time zone of a Datetime, keeping the local time. `tz = nothing` removes it.

    - `ambiguous`: how to handle an ambiguous local time: `"raise"`, `"earliest"`, `"latest"`,
      `"null"`.
    - `non_existent`: how to handle a non-existent local time: `:raise` or `:null`.
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
    ) polars_expr_dt_replace "Replace the time units of a value. Components left as `missing` are kept. `ambiguous` is as in [`replace_time_zone`](@ref)."
    @curry replace(;
        year::Expr = convert(Expr, missing), month::Expr = convert(Expr, missing),
        day::Expr = convert(Expr, missing), hour::Expr = convert(Expr, missing),
        minute::Expr = convert(Expr, missing), second::Expr = convert(Expr, missing),
        microsecond::Expr = convert(Expr, missing), ambiguous::Expr = convert(Expr, "raise")
    )
    export replace
end # module Dt

export Dt
