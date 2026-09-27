"""
    Series(name::String, values::Vector{T})::Series{T}

The columnar data type for a [`DataFrame`](@ref).
"""
mutable struct Series{T} <: AbstractVector{T}
    ptr::Ptr{polars_series_t}
    null_count::Int
    length::Int
    # Top-level Arrow format string (`""` for a dictionary-encoded column), cached for
    # `read_series`.
    fmt::String

    function Series(ptr)
        ptr == C_NULL && error("cannot build a Series from a null pointer")

        # No finalizer yet: destroy `ptr` if reading the schema fails.
        try
            schema_out = Ref{CArrowSchema}()
            err = polars_series_schema(ptr, schema_out)
            polars_error(err)
            _, T, fmt = load_series_schema(schema_out[])

            len = polars_series_length(ptr)
            null_count = polars_series_null_count(ptr)

            T = iszero(null_count) ? nomissing(T) : T

            series = new{T}(ptr, null_count, len, fmt)

            return finalizer(polars_series_destroy, series)
        catch
            API.polars_series_destroy(ptr)
            rethrow()
        end
    end
end

function Series(name, values)
    name = Symbol(name)
    table = NamedTuple((name => values,))
    df = DataFrame(table)
    return df[name]
end

Base.unsafe_convert(::Type{Ptr{polars_series_t}}, series::Series) = series.ptr

Base.size(series::Series) = (series.length,)

Base.IndexStyle(::Type{<:Series}) = IndexLinear()

"""
    Polars.item(series::Series)

Return the sole value of a length-1 `series`; errors for any other length.
"""
function item(series::Series)
    length(series) == 1 || error("item() requires a Series of length 1, got length $(length(series))")
    return series[1]
end
"""
    Base.copy(series::Series)

Materialize `series` into a `Vector`, same as `collect`.
"""
Base.copy(series::Series) = collect(series)

"""
    _series_getter(::Type{T})

The `polars_series_get_*` binding for physical type `T`, resolved at compile time.
"""
_series_getter(::Type{Bool}) = API.polars_series_get_bool
_series_getter(::Type{Int8}) = API.polars_series_get_i8
_series_getter(::Type{Int16}) = API.polars_series_get_i16
_series_getter(::Type{Int32}) = API.polars_series_get_i32
_series_getter(::Type{Int64}) = API.polars_series_get_i64
_series_getter(::Type{UInt8}) = API.polars_series_get_u8
_series_getter(::Type{UInt16}) = API.polars_series_get_u16
_series_getter(::Type{UInt32}) = API.polars_series_get_u32
_series_getter(::Type{UInt64}) = API.polars_series_get_u64
_series_getter(::Type{Float32}) = API.polars_series_get_f32
_series_getter(::Type{Float64}) = API.polars_series_get_f64

function Base.getindex(series::Series{MT}, index::Integer) where {MT <: Union{MaybeMissing{Integer}, MaybeMissing{AbstractFloat}}}
    checkbounds(series, index)
    index = index - 1

    if series.null_count > 0 && polars_series_is_null(series, index)
        return missing
    end

    T = nomissing(MT)
    out = Ref{T}()

    f = _series_getter(T)
    err = f(series, index, out)
    polars_error(err)
    return out[]
end

function Base.getindex(series::Series{MT}, index::Integer) where {MT <: Union{MaybeMissing{Dates.TimeType}, Dates.TimeType, MaybeMissing{Dates.Period}, Dates.Period}}
    checkbounds(series, index)
    index = index - 1

    if series.null_count > 0 && polars_series_is_null(series, index)
        return missing
    end

    T = nomissing(MT)

    out = Ref{Ptr{polars_value_t}}()
    err = polars_series_get(series, index, out)
    polars_error(err)
    value_at_index = Value{T}(out[], series)

    return load_value(value_at_index)
end


function Base.getindex(series::Series{MT}, index::Integer) where {MT <: Union{MaybeMissing{Vector}, MaybeMissing{String}, MaybeMissing{NamedTuple}}}
    checkbounds(series, index)
    index = index - 1

    if series.null_count > 0 && polars_series_is_null(series, index)
        return missing
    end

    T = nomissing(MT)

    out = Ref{Ptr{polars_value_t}}()
    err = polars_series_get(series, index, out)
    polars_error(err)
    value_at_index = Value{T}(out[], series)

    # `load_value` may return a narrower element type than `T` (it knows the child's null
    # count); convert so `s[i]::T` holds.
    return convert(T, load_value(value_at_index))
end

# The Null dtype has no buffers; every element is null.
function Base.getindex(series::Series{Union{Missing, Nothing}}, index::Integer)
    checkbounds(series, index)
    return missing
end

# Zero-copy slicing via `Series::slice`.
function Base.getindex(series::Series, r::UnitRange)
    checkbounds(series, r)
    offset = first(r) - 1
    len = length(r)
    return Series(polars_series_slice(series, offset, len))
end

"""
    dtype(series::Series)::API.polars_value_type_t

Get datatype of series, as a `API.PolarsValueType*` enum value.
"""
function dtype(series)
    return API.polars_series_type(series)
end

"""
    name(series::Series)::String

Name of series.
"""
function name(series)
    ptr = Ref{Ptr{UInt8}}()
    return GC.@preserve series begin
        len = polars_series_name(series, ptr)
        unsafe_string(ptr[], len)
    end
end
