module Dt
using ..Polars: @generate_expr_fns, API, polars_expr_t, Expr, polars_error

@generate_expr_fns begin
    gen_impl_expr_dt!(polars_expr_dt_year, DateLikeNameSpace::year, "Extracts the year component of each Date/Datetime value in `expr`.")
    gen_impl_expr_dt!(polars_expr_dt_month, DateLikeNameSpace::month, "Extracts the month component (1-12) of each Date/Datetime value in `expr`.")
    gen_impl_expr_dt!(polars_expr_dt_day, DateLikeNameSpace::day, "Extracts the day-of-month component (1-31) of each Date/Datetime value in `expr`.")
    gen_impl_expr_dt!(polars_expr_dt_hour, DateLikeNameSpace::hour, "Extracts the hour component (0-23) of each Datetime value in `expr`.")
    gen_impl_expr_dt!(polars_expr_dt_minute, DateLikeNameSpace::minute, "Extracts the minute component (0-59) of each Datetime value in `expr`.")
    gen_impl_expr_dt!(polars_expr_dt_second, DateLikeNameSpace::second, "Extracts the second component (0-59) of each Datetime value in `expr`.")
    gen_impl_expr_dt!(polars_expr_dt_weekday, DateLikeNameSpace::weekday, "Day of the week for each Date/Datetime value in `expr`: `1` (Monday) through `7` (Sunday), ISO 8601 numbering.")
    gen_impl_expr_dt!(polars_expr_dt_ordinal_day, DateLikeNameSpace::ordinal_day, "Day of the year (1-366) for each Date/Datetime value in `expr`.")

    gen_impl_expr_binary_dt!(polars_expr_dt_truncate, DateLikeNameSpace::truncate, "Truncates each Date/Datetime value of `a` down to the start of the enclosing interval named by the duration string `b` (e.g. `\"1h\"` zeroes out minutes/seconds). Has a curried form `truncate(every)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_dt!(polars_expr_dt_round, DateLikeNameSpace::round, "Rounds each Date/Datetime value of `a` to the nearest interval named by the duration string `b`, rather than always truncating down like [`truncate`](@ref). Has a curried form `round(every)` -- see [Curried forms for pipe-based composition](@ref).")
    gen_impl_expr_binary_dt!(polars_expr_dt_offset_by, DateLikeNameSpace::offset_by, "Shifts each Date/Datetime value of `a` by the (possibly signed) duration string `b` (e.g. `\"+1d\"`, `\"-2h\"`). Has a curried form `offset_by(by)` -- see [Curried forms for pipe-based composition](@ref).")
end

# Curried (Fix2-style) forms, e.g. `col("d") |> Dt.truncate("1mo")`.
truncate(every) = Base.Fix2(truncate, convert(Expr, every))
round(every) = Base.Fix2(round, convert(Expr, every))
offset_by(by) = Base.Fix2(offset_by, convert(Expr, by))

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
end # module Dt
