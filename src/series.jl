"""
    Series(name::String, values::Vector{T})::Series{T}

A series is a collection of values used as columns inside a [`DataFrame`](@ref).
"""
mutable struct Series{T} <: AbstractVector{T}
    ptr::Ptr{polars_series_t}
    null_count::Int
    length::Int

    function Series(ptr)
        @assert ptr != C_NULL

        schema = polars_series_schema(ptr)
        _, T = load_series_schema(schema)

        len = polars_series_length(ptr)
        null_count = polars_series_null_count(ptr)

        T = iszero(null_count) ? nomissing(T) : T

        series = new{T}(ptr, null_count, len)

        return finalizer(polars_series_destroy, series)
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
Base.eltype(::Series{T}) where {T} = T

function Base.getindex(series::Series{MT}, index) where {MT <: Union{MaybeMissing{Integer}, MaybeMissing{AbstractFloat}}}
    index = index - 1

    if series.null_count > 0 && polars_series_is_null(series, index)
        return missing
    end

    T = nomissing(MT)
    out = Ref{T}()

    letter = T <: AbstractFloat ? "f" :
        T <: Signed ? "i" : "u"
    name = T == Bool ? :polars_series_get_bool : Symbol("polars_series_get_", letter, 8sizeof(T))
    f = getproperty(API, name)

    err = f(series, index, out)
    polars_error(err)
    return out[]
end

function Base.getindex(series::Series{MT}, index) where {MT <: Union{MaybeMissing{Dates.TimeType}, Dates.TimeType, MaybeMissing{Dates.Period}, Dates.Period}}
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


function Base.getindex(series::Series{MT}, index) where {MT <: Union{MaybeMissing{Series}, MaybeMissing{String}, MaybeMissing{NamedTuple}, MaybeMissing{Vector{UInt8}}}}
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

# The Null dtype (produced by e.g. `lit(missing)`/`cast(expr, Missing)`) has no data/validity
# buffers at all -- every element is unconditionally null, so there's nothing to fetch from Rust.
function Base.getindex(series::Series{Union{Missing, Nothing}}, index)
    checkbounds(series, index)
    return missing
end

"""
    name(series::Series)::String

Returns the name of this polars series.
"""
function name(series)
    ptr = Ref{Ptr{UInt8}}()
    len = polars_series_name(series, ptr)
    return unsafe_string(ptr[], len)
end
