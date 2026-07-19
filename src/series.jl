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

        # No finalizer is registered yet at this point, so an error anywhere below (e.g.
        # `load_series_schema`/`parse_format` throwing on an unsupported dtype such as a
        # fixed-size list, see `src/arrow/schema.jl`) would otherwise leak `ptr` -- catch, destroy
        # the still-owned pointer, and rethrow the original error.
        try
            schema_out = Ref{CArrowSchema}()
            err = polars_series_schema(ptr, schema_out)
            polars_error(err)
            _, T = load_series_schema(schema_out[])

            len = polars_series_length(ptr)
            null_count = polars_series_null_count(ptr)

            T = iszero(null_count) ? nomissing(T) : T

            series = new{T}(ptr, null_count, len)

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
# No `Base.eltype(::Series{T}) where {T} = T` needed: `Series{T} <: AbstractVector{T}` already
# gets this for free from `AbstractArray`'s own default (`eltype(::Type{<:AbstractArray{T}}) where
# T = T`), which resolves identically -- verified via `@code_typed`, both fold to the same
# `Core.Const` field-type extraction. The explicit method here was pure duplication.

"""
    Base.copy(series::Series)

Materializes `series` into a native Julia `Vector`, same as [`collect`](@ref) -- lets generic
code that calls `copy` on an `AbstractVector` (rather than `collect` specifically) still hit the
bulk `read_series` path instead of falling back to the default `AbstractArray` `copy`
implementation, which would loop over `getindex` one element at a time.
"""
Base.copy(series::Series) = collect(series)

"""
    _series_getter(::Type{T})

Compile-time dispatch table from a physical dtype `T` to its `polars_series_get_*` ccall
wrapper, one method per type. This replaces building a `Symbol` from string pieces and resolving
it via `getproperty(API, name)` at every single element access -- that was a dynamic (runtime)
global lookup returning an un-inferred `Function`, so the actual ccall couldn't be inlined or
specialized. Since `T` is known at compile time inside each `getindex` specialization (see below),
this call constant-folds to a direct, inlinable reference to the right ccall wrapper instead.
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


function Base.getindex(series::Series{MT}, index::Integer) where {MT <: Union{MaybeMissing{Series}, MaybeMissing{String}, MaybeMissing{NamedTuple}, MaybeMissing{Vector{UInt8}}}}
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
function Base.getindex(series::Series{Union{Missing, Nothing}}, index::Integer)
    checkbounds(series, index)
    return missing
end

# Zero-copy row-range slicing, backed by polars_series_slice (Rust's Series::slice, an
# Arc-refcount clone under the hood -- no data copy).
function Base.getindex(series::Series, r::UnitRange)
    checkbounds(series, r)
    offset = first(r) - 1
    len = length(r)
    return Series(polars_series_slice(series, offset, len))
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
