"""
    Series(name::String, values::Vector{T})::Series{T}

A series is a collection of values used as columns inside a [`DataFrame`](@ref).
"""
mutable struct Series{T} <: AbstractVector{T}
    ptr::Ptr{polars_series_t}
    null_count::Int
    length::Int
    # Raw top-level Arrow format string captured once at construction (`""` for a
    # dictionary-encoded column) -- lets `read_series` dispatch directly instead of re-fetching
    # and re-parsing the schema via `polars_series_schema` on every `collect`/`copy`.
    fmt::String

    function Series(ptr)
        ptr == C_NULL && error("cannot build a Series from a null pointer")

        # No finalizer is registered yet at this point, so an error anywhere below (e.g.
        # `load_series_schema`/`parse_format` throwing on an unsupported dtype such as a
        # fixed-size list, see `src/arrow/schema.jl`) would otherwise leak `ptr` -- catch, destroy
        # the still-owned pointer, and rethrow the original error.
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

# `getindex` below takes a single linear index, which is what `IndexLinear` declares -- without it
# `Series` inherits `AbstractArray`'s `IndexCartesian` default and generic Base code goes through
# the (slower, and for a vector entirely pointless) cartesian machinery.
Base.IndexStyle(::Type{<:Series}) = IndexLinear()

"""
    Polars.item(series::Series)

Returns the sole value of a length-1 `series`, and errors for any other length.
"""
function item(series::Series)
    length(series) == 1 || error("item() requires a Series of length 1, got length $(length(series))")
    return series[1]
end
# No `Base.eltype(::Series{T}) where {T} = T` method is needed: `Series{T} <: AbstractVector{T}`
# gets it for free from `AbstractArray`'s own default (`eltype(::Type{<:AbstractArray{T}}) where
# T = T`), which folds to the same `Core.Const` field-type extraction.

# Defined explicitly so generic code calling `copy` (rather than `collect`) on an
# `AbstractVector` still hits the bulk `read_series` path, instead of falling back to the default
# `AbstractArray` `copy`, which loops over `getindex` one element at a time.
#
# The comment sits above the docstring, not between it and the definition, to ensure Documenter
# can locate the docstring.
"""
    Base.copy(series::Series)

Materializes `series` into a native Julia `Vector`, same as [`collect`](@ref).
"""
Base.copy(series::Series) = collect(series)

"""
    _series_getter(::Type{T})

Compile-time dispatch table from a physical dtype `T` to its `polars_series_get_*` ccall
wrapper, one method per type. `T` is known at compile time inside each `getindex` specialization
(see below), so this call constant-folds to a direct, inlinable reference to the right ccall
wrapper -- unlike a name-based `getproperty(API, name)` lookup, which is a runtime global
resolution returning an un-inferred `Function` that can be neither inlined nor specialized.
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

    # `parse_format` wraps every nesting level in `MaybeMissing` (it cannot know a child's real
    # null count from the schema alone), while `load_value` builds the row from the *child
    # series'* own null-count-narrowed type. `Vector` is invariant, so the narrower result is not
    # a subtype of the declared `T` -- convert so `Series{T} <: AbstractVector{T}`'s `s[i]::T`
    # promise actually holds. A no-op whenever the two already agree.
    return convert(T, load_value(value_at_index))
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
    dtype(series::Series)::API.polars_value_type_t

Returns the raw polars dtype code of `series`, as one of the `API.PolarsValueType*` enum values
(e.g. `API.PolarsValueTypeInt64`). This is the low-level dtype code, not a Julia `Type` -- for
plain dtypes it agrees with `eltype(series)` (modulo `missing`-wrapping), but it also distinguishes
cases the `Series{T}` type parameter can't represent on its own, e.g. Datetime (no time
unit/timezone) or Categorical (no `T` at all, since categorical columns don't materialize to
Julia -- see `docs/src/limitations.md`).
"""
function dtype(series)
    return API.polars_series_type(series)
end

"""
    name(series::Series)::String

Returns the name of this polars series.
"""
function name(series)
    ptr = Ref{Ptr{UInt8}}()
    return GC.@preserve series begin
        len = polars_series_name(series, ptr)
        unsafe_string(ptr[], len)
    end
end
