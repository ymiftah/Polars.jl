"""
    Polars.Value{T}

Internal type which represents a reference to a value of type `T` in a series or as a field to
a struct.
"""
mutable struct Value{T}
    ptr::Ptr{polars_value_t}
    parent::Union{Series, Value}

    Value{T}(ptr, parent) where {T} =
        finalizer(polars_value_destroy, new{T}(ptr, parent))
end

Base.unsafe_convert(::Type{Ptr{polars_value_t}}, value::Value) = value.ptr

"""
    _value_getter(::Type{T})

Compile-time dispatch table from a physical dtype `T` to its `polars_value_get_*` ccall
wrapper -- the `Value` counterpart to `_series_getter` in `series.jl` (see its docstring for why
this replaces a runtime `Symbol`-and-`getproperty` lookup).
"""
_value_getter(::Type{Bool}) = API.polars_value_get_bool
_value_getter(::Type{Int8}) = API.polars_value_get_i8
_value_getter(::Type{Int16}) = API.polars_value_get_i16
_value_getter(::Type{Int32}) = API.polars_value_get_i32
_value_getter(::Type{Int64}) = API.polars_value_get_i64
_value_getter(::Type{UInt8}) = API.polars_value_get_u8
_value_getter(::Type{UInt16}) = API.polars_value_get_u16
_value_getter(::Type{UInt32}) = API.polars_value_get_u32
_value_getter(::Type{UInt64}) = API.polars_value_get_u64
_value_getter(::Type{Float32}) = API.polars_value_get_f32
_value_getter(::Type{Float64}) = API.polars_value_get_f64

"""
    load_value(v::Value{T})::T

Materializes the polars value as a Julia value of type `T`.

!!! note
    This is an internal API.
"""
function load_value(value::Value{T}) where {T <: PhysicalDType}
    polars_value_type(value) == PolarsValueTypeNull && return missing

    f = _value_getter(T)
    out = Ref{T}()
    err = f(value, out)
    polars_error(err)

    return out[]
end

function load_value(value::Value{String})
    polars_value_type(value) == PolarsValueTypeNull && return missing

    io = Ref(IOBuffer())
    callback = _io_callback()

    err = polars_value_string_get(value, io, callback)
    polars_error(err)

    return String(take!(io[]))
end

function load_value(value::Value{Vector{UInt8}})
    polars_value_type(value) == PolarsValueTypeNull && return missing

    io = Ref(IOBuffer())
    callback = _io_callback()

    err = polars_value_binary_get(value, io, callback)
    polars_error(err)

    return take!(io[])
end

function load_value(value::Value{S}) where {S <: Series}
    polars_value_type(value) == PolarsValueTypeNull && return missing

    out = Ref{Ptr{polars_series_t}}()

    err = polars_value_list_get(value, out)
    polars_error(err)

    return Series(out[])
end

function load_value(value::Value{NT}) where {NT <: NamedTuple}
    polars_value_type(value) == PolarsValueTypeNull && return missing

    _, types = NT.parameters
    types = types.parameters

    field_values = map(enumerate(types)) do args
        field_index, T = args
        field_value_out = Ref{Ptr{polars_value_t}}()
        err = polars_value_struct_get(value, field_index - 1, field_value_out)
        polars_error(err)
        field_value = field_value_out[]

        # NOTE: Polars cannot figure the type of a single value whose type is null?
        if polars_value_type(field_value) == PolarsValueTypeUnknown
            return missing
        end

        T = nomissing(T)
        load_value(Value{T}(field_value, value))
    end

    return NT(field_values)
end

function load_value(value::Value{TT}) where {TT <: Dates.Period}
    # Unlike a bare untyped null (`PolarsValueTypeUnknown`, already caught one level up by the
    # NamedTuple loader), a null value in a *schema-typed* slot -- e.g. a struct field declared
    # Duration -- reports its real dtype even while null, so this guard (present on every other
    # `load_value` method) is required here too; without it, `polars_value_duration_get` errors
    # with a confusing "value is not of type duration" instead of returning `missing`.
    polars_value_type(value) == PolarsValueTypeNull && return missing

    v = Ref{Int64}()
    err = polars_value_duration_get(value, v)
    polars_error(err)

    tu = polars_value_time_unit(value)
    if tu == API.PolarsTimeUnitNanosecond
        return Dates.Nanosecond(v[])
    elseif tu == API.PolarsTimeUnitMicrosecond
        return Dates.Microsecond(v[])
    elseif tu == API.PolarsTimeUnitMillisecond
        return Dates.Millisecond(v[])
    end

    error("invalid duration")
end

function load_value(value::Value{Dates.DateTime})
    # See the matching comment on the `Dates.Period` method above.
    polars_value_type(value) == PolarsValueTypeNull && return missing

    v = Ref{Int64}()
    err = polars_value_datetime_get(value, v)
    polars_error(err)

    tu = polars_value_time_unit(value)
    if tu == API.PolarsTimeUnitNanosecond
        return DateTime(1970, 01, 01) + Dates.Nanosecond(v[])
    elseif tu == API.PolarsTimeUnitMicrosecond
        return DateTime(1970, 01, 01) + Dates.Microsecond(v[])
    elseif tu == API.PolarsTimeUnitMillisecond
        return DateTime(1970, 01, 01) + Dates.Millisecond(v[])
    end

    error("invalid datetime")
end

function load_value(value::Value{Date})
    # See the matching comment on the `Dates.Period` method above.
    polars_value_type(value) == PolarsValueTypeNull && return missing

    v = Ref{Int32}()
    err = polars_value_date_get(value, v)
    polars_error(err)
    return Date(1970, 01, 01) + Dates.Day(v[])
end

function load_value(value::Value{Dates.Time})
    # See the matching comment on the `Dates.Period` method above.
    polars_value_type(value) == PolarsValueTypeNull && return missing

    v = Ref{Int64}()
    err = polars_value_time_get(value, v)
    polars_error(err)
    # polars' `Time` is always nanoseconds since midnight (it carries no TimeUnit, unlike
    # Datetime/Duration), and `Dates.Time` is nanosecond-resolution too, so this is exact.
    return Dates.Time(Dates.Nanosecond(v[]))
end
