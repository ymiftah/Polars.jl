module PolarsTimeZonesExt

using Polars, TimeZones, Dates

# Enables timezone-aware Datetime columns (see `Polars._tz_aware_datetime_type`).
Polars._resolve_tz_aware_datetime_type(::AbstractString) = ZonedDateTime

function Polars.load_value(value::Polars.Value{ZonedDateTime})
    # A null value can still carry its column's dtype.
    Polars.polars_value_type(value) == Polars.PolarsValueTypeNull && return missing

    v = Ref{Int64}()
    err = Polars.polars_value_datetime_get(value, v)
    Polars.polars_error(err)

    tu = Polars.polars_value_time_unit(value)
    naive_utc = if tu == Polars.PolarsTimeUnitNanosecond
        Dates.DateTime(1970, 1, 1) + Dates.Nanosecond(v[])
    elseif tu == Polars.PolarsTimeUnitMicrosecond
        Dates.DateTime(1970, 1, 1) + Dates.Microsecond(v[])
    elseif tu == Polars.PolarsTimeUnitMillisecond
        Dates.DateTime(1970, 1, 1) + Dates.Millisecond(v[])
    else
        error("invalid datetime")
    end

    # The pointer borrows from `value`, so keep it rooted until `unsafe_string` has copied it.
    tz = GC.@preserve value begin
        tz_ptr = Ref{Ptr{UInt8}}()
        tz_len = Polars.polars_value_time_zone(value, tz_ptr)
        tz_len == 0 && error("expected a timezone-aware datetime value, got a naive one")
        unsafe_string(tz_ptr[], tz_len)
    end

    utc = ZonedDateTime(naive_utc, tz"UTC")
    return astimezone(utc, TimeZone(tz))
end

end # module
