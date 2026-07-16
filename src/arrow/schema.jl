# https://arrow.apache.org/docs/format/CDataInterface.html#
# https://arrow.apache.org/docs/format/Columnar.html#format-columnar

using .API:
    ArrowSchema as CArrowSchema,
    ArrowArray as CArrowArray

"""
    _tz_aware_datetime_type(tz::AbstractString)

Extension hook: determines the Julia element type for a timezone-aware `Datetime` column.
Errors by default, since materializing a genuinely timezone-aware value needs
`TimeZones.ZonedDateTime`, which this package does not depend on directly. Loading `TimeZones.jl`
(`using TimeZones`) activates this package's `PolarsTimeZonesExt` extension, which adds the
first-ever method for `_resolve_tz_aware_datetime_type` and makes this function return
`TimeZones.ZonedDateTime` instead of erroring.

!!! note
    This delegates to `_resolve_tz_aware_datetime_type` (declared with zero methods, just below)
    rather than being overridden directly, because Julia forbids an extension from *redefining*
    an existing same-signature method during precompilation ("Method overwriting is not permitted
    during Module precompilation") -- only adding a genuinely new method is allowed there. Leaving
    the extension point as a zero-method stub sidesteps that restriction entirely.
"""
function _tz_aware_datetime_type(tz::AbstractString)
    try
        return _resolve_tz_aware_datetime_type(tz)
    catch e
        if e isa MethodError && e.f === _resolve_tz_aware_datetime_type
            error(
                "column has timezone \"$tz\" -- load TimeZones.jl (`using TimeZones`) to read " *
                "timezone-aware Datetime columns"
            )
        end
        rethrow()
    end
end

"""Zero-method extension point -- see `_tz_aware_datetime_type`'s docstring."""
function _resolve_tz_aware_datetime_type end

function parse_format(schema)
    # Dictionary-encoded fields (e.g. low-cardinality strings) carry their
    # logical type in the referenced dictionary schema, not in `format`
    # (which only describes the physical index type).
    if schema.dictionary != C_NULL
        return parse_format(unsafe_load(schema.dictionary))
    end

    fmt = unsafe_string(schema.format)

    fmt == "n" && return MaybeMissing{Nothing}
    fmt == "b" && return MaybeMissing{Bool}
    fmt == "c" && return MaybeMissing{Int8}
    fmt == "C" && return MaybeMissing{UInt8}
    fmt == "s" && return MaybeMissing{Int16}
    fmt == "S" && return MaybeMissing{UInt16}
    fmt == "i" && return MaybeMissing{Int32}
    fmt == "I" && return MaybeMissing{UInt32}
    fmt == "l" && return MaybeMissing{Int64}
    fmt == "L" && return MaybeMissing{UInt64}
    fmt == "e" && return MaybeMissing{Float16}
    fmt == "f" && return MaybeMissing{Float32}
    fmt == "g" && return MaybeMissing{Float64}
    fmt == "U" && return MaybeMissing{String}
    fmt == "u" && return MaybeMissing{String}
    fmt == "vu" && return MaybeMissing{String}
    fmt == "z" && return Vector{UInt8}
    fmt == "Z" && return Vector{UInt8}
    fmt == "vz" && return Vector{UInt8}

    # All three resolutions collapse to the same real `Dates.DateTime` -- there's no
    # resolution-tagged DateTime type in the stdlib, and the actual resolution is re-derived at
    # runtime from the live polars value in `load_value` regardless (see series.jl/value.jl).
    #
    # The Arrow C Data Interface timestamp format is "tsX:tz" -- an empty suffix means naive, a
    # non-empty suffix is an IANA time zone name. A naive suffix maps straight to `DateTime`; a
    # non-empty one routes through `_tz_aware_datetime_type`, which errors by default (see above)
    # and is overridden by the TimeZones.jl package extension to return `ZonedDateTime`.
    for prefix in ("tsn:", "tsu:", "tsm:")
        if startswith(fmt, prefix)
            tz = fmt[(length(prefix) + 1):end]
            T = isempty(tz) ? Dates.DateTime : _tz_aware_datetime_type(tz)
            return MaybeMissing{T}
        end
    end

    fmt == "tdD" && return MaybeMissing{Date}

    # Unlike Datetime, the stdlib's Period subtypes are themselves genuinely resolution-specific
    # real types, so these use them directly instead of a custom wrapper.
    fmt == "tDm" && return MaybeMissing{Dates.Millisecond}
    fmt == "tDu" && return MaybeMissing{Dates.Microsecond}
    fmt == "tDn" && return MaybeMissing{Dates.Nanosecond}

    if fmt == "+s" # Struct type
        children = unsafe_wrap(
            Array,
            schema.children,
            schema.n_children,
        )
        names_types = map(children) do schema
            schema = unsafe_load(schema)
            (
                Symbol(unsafe_string(schema.name)),
                parse_format(schema),
            )
        end
        names = Tuple(first.(names_types))
        types = Tuple{last.(names_types)...}
        return MaybeMissing{NamedTuple{names, types}}
    end

    # List but which are stored as Series
    # NOTE: we may want to change this if the arrow implementation
    # ....  is not specific to Polars.jl anymore.
    if fmt in ("+l", "+L")
        @assert schema.n_children == 1
        children = unsafe_load(schema.children) |> unsafe_load
        T = parse_format(children)
        return MaybeMissing{Series{T}}
    end

    if startswith(fmt, "+w") # Fixed size list
        @assert schema.n_children
        children = unsafe_load(schema.children) |> unsafe_load
        T = parse_format(children)
        N = parse(Int, fmt[4:end])
        return MaybeMissing{NTuple{N, T}}
    end

    error("unknow schema format $fmt")
end

"""
    Internal API

!!! warning
    The schema should not be used afterwards.
"""
function load_series_schema(schema::CArrowSchema)
    res = unsafe_string(schema.name) => parse_format(schema)

    schema_ref = Ref(schema)
    @ccall $(schema.release)(schema_ref::Ptr{CArrowSchema})::Cvoid

    return res
end

"""
    Internal API

!!! warning
    The schema should not be used afterwards.
"""
function load_dataframe_schema(schema::CArrowSchema)
    fmt = unsafe_string(schema.format)
    @assert fmt == "+s" "invalid polars schema"

    name = unsafe_string(schema.name)
    @assert name == "polars.dataframe" "invalid polars schema"

    NT = parse_format(schema)
    NT = nomissing(NT)
    @assert NT <: NamedTuple
    names, types = NT.parameters

    schema_ref = Ref(schema)
    @ccall $(schema.release)(schema_ref::Ptr{CArrowSchema})::Cvoid

    return Tables.Schema(names, types)
end

"""
    ArrowSchema(; format, name, children=ArrowSchema[])

A Julia managed ArrowSchema valid according to the arrow C data interface.
"""
mutable struct ArrowSchema
    format::String
    name::String
    metadata::Union{Nothing, String}
    flags::Int64
    children::Vector{ArrowSchema}
    dictionary::Union{Nothing, ArrowSchema}

    children_pointers::Vector{Ptr{CArrowSchema}}
    carrow_schema::CArrowSchema
end

function release_schema!(schema)
    for child in schema.children
        delete!(LIVE_SCHEMAS, child)
    end
    return delete!(LIVE_SCHEMAS, schema)
end

function base_release_schema(schema_ptr::Ptr{CArrowSchema})
    cschema = unsafe_load(schema_ptr)
    schema = unsafe_pointer_to_objref(Ptr{ArrowSchema}(cschema.private_data))
    release_schema!(schema)
    return nothing
end

function set_private_data!(schema::ArrowSchema)
    base_release_ptr = @cfunction base_release_schema Cvoid (Ptr{CArrowSchema},)
    schema.carrow_schema = CArrowSchema(
        schema.carrow_schema.format,
        schema.carrow_schema.name,
        schema.carrow_schema.metadata,
        schema.carrow_schema.flags,
        schema.carrow_schema.n_children,
        schema.carrow_schema.children,
        schema.carrow_schema.dictionary,
        base_release_ptr,
        pointer_from_objref(schema),
    )
    @assert !haskey(LIVE_SCHEMAS, schema)
    LIVE_SCHEMAS[schema] = nothing
    return nothing
end

function ArrowSchema(; format, name, metadata = nothing, flags = 0, children = ArrowSchema[], dictionary = nothing)
    children_pointers = [
        Base.unsafe_convert(Ptr{CArrowSchema}, child)
            for child in children
    ]
    schema = ArrowSchema(
        format,
        name,
        metadata,
        flags,
        children,
        dictionary,
        children_pointers,
        CArrowSchema(
            Base.unsafe_convert(Cstring, format),
            Base.unsafe_convert(Cstring, name),
            isnothing(metadata) ? C_NULL : Base.unsafe_convert(Ptr{UInt8}, metadata),
            flags,
            length(children),
            pointer(children_pointers),
            isnothing(dictionary) ? C_NULL : throw("unsupported dictionary"),
            C_NULL,
            C_NULL,
        )
    )
    set_private_data!(schema)
    return schema
end

function Base.unsafe_convert(::Type{Ptr{CArrowSchema}}, schema::ArrowSchema)
    return Ptr{CArrowSchema}(
        Ptr{UInt8}(Base.pointer_from_objref(schema)) +
            fieldoffset(ArrowSchema, findfirst(==(:carrow_schema), fieldnames(ArrowSchema)))
    )
end

"Holds references to the live schemas whose ownership has been given through ffi."
const LIVE_SCHEMAS = IdDict{ArrowSchema, Nothing}()
