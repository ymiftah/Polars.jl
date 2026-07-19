module PolarsTimeZonesExt

using Polars, TimeZones, Dates

# Activates timezone-aware Datetime column support -- see `Polars._tz_aware_datetime_type`'s
# docstring (src/arrow/schema.jl) for why this adds the first-ever method for
# `_resolve_tz_aware_datetime_type` rather than redefining `_tz_aware_datetime_type` directly
# (the latter would be a same-signature method *overwrite*, which Julia forbids during
# precompilation).
Polars._resolve_tz_aware_datetime_type(::AbstractString) = ZonedDateTime

function Polars.load_value(value::Polars.Value{ZonedDateTime})
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

    # `polars_value_time_zone` returns a pointer into `value`'s Rust-owned memory; `unsafe_string`
    # is itself an allocating call (a GC point), so the whole borrow must stay inside one
    # `GC.@preserve value` block -- otherwise `value` could be finalized (destroying the Rust-side
    # data the pointer refers to) between the ccall and `unsafe_string` reading through it.
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
