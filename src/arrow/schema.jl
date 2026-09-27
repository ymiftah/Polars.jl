# https://arrow.apache.org/docs/format/CDataInterface.html#
# https://arrow.apache.org/docs/format/Columnar.html#format-columnar

using .API:
    ArrowSchema as CArrowSchema,
    ArrowArray as CArrowArray

"""
    _tz_aware_datetime_type(tz::AbstractString)

The Julia element type for a timezone-aware `Datetime` column: `TimeZones.ZonedDateTime` when
TimeZones.jl is loaded, an error otherwise.

The extension adds a method to the zero-method `_resolve_tz_aware_datetime_type`, since an
extension may not redefine an existing method during precompilation.
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

"""Zero-method extension point for `PolarsTimeZonesExt`; see `_tz_aware_datetime_type`."""
function _resolve_tz_aware_datetime_type end

function parse_format(schema)
    # A dictionary-encoded field's logical type is in its dictionary schema; `format` is the
    # index type.
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
    fmt == "z" && return MaybeMissing{Vector{UInt8}}
    fmt == "Z" && return MaybeMissing{Vector{UInt8}}
    fmt == "vz" && return MaybeMissing{Vector{UInt8}}

    # "tsX:tz": every time unit maps to `DateTime` (the unit is read from each value). A
    # non-empty `tz` is timezone-aware.
    for prefix in ("tsn:", "tsu:", "tsm:")
        if startswith(fmt, prefix)
            tz = fmt[(length(prefix) + 1):end]
            T = isempty(tz) ? Dates.DateTime : _tz_aware_datetime_type(tz)
            return MaybeMissing{T}
        end
    end

    fmt == "tdD" && return MaybeMissing{Date}

    # time32 ("tts"/"ttm") and time64 ("ttu"/"ttn") all map to `Dates.Time`; polars produces
    # "ttn".
    fmt in ("tts", "ttm", "ttu", "ttn") && return MaybeMissing{Dates.Time}

    # Durations map to the `Period` type of their unit.
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

    # List columns materialize as nested `Vector`s (see `_read_list` in arrow/read.jl).
    if fmt in ("+l", "+L")
        schema.n_children == 1 || error(
            "malformed Arrow List schema: expected exactly 1 child, got $(schema.n_children)"
        )
        children = unsafe_load(schema.children) |> unsafe_load
        T = parse_format(children)
        return MaybeMissing{Vector{T}}
    end

    if startswith(fmt, "+w") # Fixed size list (polars' Array dtype)
        # Array columns have no read path; raise a clear error here.
        error(
            "Array dtype (fixed-size list, arrow format \"$fmt\") is not supported -- " *
                "Polars.jl cannot materialize it into a Julia value yet. Cast to a List " *
                "column (e.g. `Lists.explode`/an ordinary variable-length list) instead."
        )
    end

    error("unknown schema format $fmt")
end

"""
    Internal API

Returns `(name, T, fmt)`: the Julia element type `T` from `parse_format`, and the top-level Arrow
format string `fmt` (`""` for a dictionary-encoded column), which `Series` caches for
`read_series`.

!!! warning
    The schema should not be used afterwards.
"""
function load_series_schema(schema::CArrowSchema)
    fmt = schema.dictionary != C_NULL ? "" : unsafe_string(schema.format)
    res = (unsafe_string(schema.name), parse_format(schema), fmt)

    schema_ref = Ref(schema)
    GC.@preserve schema_ref _release_or_throw(schema.release, Base.unsafe_convert(Ptr{CArrowSchema}, schema_ref))

    return res
end

"""
    Internal API

!!! warning
    The schema should not be used afterwards as it is freed within
    the function
"""
function load_dataframe_schema(schema::CArrowSchema)
    # Errors, not `@assert`s: this validates data from across the FFI boundary.
    fmt = unsafe_string(schema.format)
    fmt == "+s" || error("invalid polars schema: expected a struct format \"+s\", got \"$fmt\"")

    name = unsafe_string(schema.name)
    name == "polars.dataframe" ||
        error("invalid polars schema: expected the name \"polars.dataframe\", got \"$name\"")

    NT = parse_format(schema)
    NT = nomissing(NT)
    NT <: NamedTuple || error("invalid polars schema: expected a NamedTuple type, got $NT")
    names, types = NT.parameters

    # Release after reading the names and types.
    schema_ref = Ref(schema)
    GC.@preserve schema_ref _release_or_throw(schema.release, Base.unsafe_convert(Ptr{CArrowSchema}, schema_ref))

    return Tables.Schema(names, types)
end

"""
    ArrowSchema(; format, name, children=ArrowSchema[])

A Julia managed ArrowSchema valid according to the arrow C data interface.
"""
mutable struct ArrowSchema
    format::String
    name::String
    # Encoded metadata bytes (see `_encode_metadata`); the C `metadata` pointer aliases them.
    metadata::Union{Nothing, Vector{UInt8}}
    flags::Int64
    children::Vector{ArrowSchema}
    dictionary::Union{Nothing, ArrowSchema}

    children_pointers::Vector{Ptr{CArrowSchema}}
    carrow_schema::CArrowSchema
end

"""
    _encode_metadata(pairs)::Vector{UInt8}

Encodes `key => value` string pairs into the Arrow C Data Interface `metadata` format: an `Int32`
pair count, then per pair an `Int32` key length, the key bytes, an `Int32` value length and the
value bytes, in native endianness.
"""
function _encode_metadata(pairs)
    io = IOBuffer()
    write(io, Int32(length(pairs)))
    for (k, v) in pairs
        kb = codeunits(String(k))
        vb = codeunits(String(v))
        write(io, Int32(length(kb)))
        write(io, kb)
        write(io, Int32(length(vb)))
        write(io, vb)
    end
    return take!(io)
end

"""
    _mark_released!(ptr::Ptr{T}) where {T}

Marks the `CArrowSchema`/`CArrowArray` at `ptr` as released by setting its `release` field to
`C_NULL`, as the Arrow C Data Interface requires.
"""
function _mark_released!(ptr::Ptr{T}) where {T}
    offset = fieldoffset(T, Base.fieldindex(T, :release))
    unsafe_store!(Ptr{Ptr{Cvoid}}(Ptr{UInt8}(ptr) + offset), C_NULL)
    return nothing
end

"""
    _release_or_throw(release::Ptr{Cvoid}, structptr::Ptr)

Calls the release callback `release` on `structptr`, or throws if the structure is already
released (`release == C_NULL`).
"""
function _release_or_throw(release::Ptr{Cvoid}, structptr::Ptr)
    release == C_NULL && error("Arrow C Data Interface structure was already released")
    @ccall $(release)(structptr::Ptr{Cvoid})::Cvoid
    return nothing
end

"""
    release_schema!(schema::ArrowSchema)

Unroots `schema` from `LIVE_SCHEMAS` (a no-op for a child schema, which is never rooted). Takes
`LIVE_SCHEMAS_LOCK`, since Rust may call the release callback from any thread.
"""
function release_schema!(schema)
    lock(LIVE_SCHEMAS_LOCK) do
        delete!(LIVE_SCHEMAS, schema)
    end
    return nothing
end

"""
    base_release_schema(schema_ptr::Ptr{CArrowSchema})

The release callback installed on every `ArrowSchema`: releases the children, unroots the schema
and marks it released, as the Arrow C Data Interface requires.
"""
function base_release_schema(schema_ptr::Ptr{CArrowSchema})
    cschema = unsafe_load(schema_ptr)
    schema = unsafe_pointer_to_objref(Ptr{ArrowSchema}(cschema.private_data))

    for child in schema.children
        child_ptr = Base.unsafe_convert(Ptr{CArrowSchema}, child)
        release = unsafe_load(child_ptr).release
        release != C_NULL && @ccall $(release)(child_ptr::Ptr{CArrowSchema})::Cvoid
    end

    _mark_released!(schema_ptr)
    _mark_released!(Base.unsafe_convert(Ptr{CArrowSchema}, schema))

    release_schema!(schema)
    return nothing
end

"""
    set_private_data!(schema::ArrowSchema)

Installs the release callback and `private_data` pointer on `schema`'s C struct, at every nesting
level. Does not root `schema`; see `root!`.
"""
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
    return nothing
end

"""
    root!(schema::ArrowSchema)

Registers the top-level `schema` in `LIVE_SCHEMAS`, keeping it and its children alive until Rust
calls its release callback.
"""
function root!(schema::ArrowSchema)
    lock(LIVE_SCHEMAS_LOCK) do
        @assert !haskey(LIVE_SCHEMAS, schema)
        LIVE_SCHEMAS[schema] = nothing
    end
    return nothing
end

function ArrowSchema(; format, name, metadata = nothing, flags = 0, children = ArrowSchema[], dictionary = nothing)
    metadata isa AbstractString && error(
        "ArrowSchema metadata must be `nothing` or an ordered collection of `key => value` " *
            "string pairs (e.g. a `Vector{Pair{String,String}}` or `Dict`), not a plain string -- " *
            "the Arrow C Data Interface metadata field is a length-prefixed binary encoding, not " *
            "a C string"
    )
    encoded_metadata = isnothing(metadata) ? nothing : _encode_metadata(metadata)

    children_pointers = [
        Base.unsafe_convert(Ptr{CArrowSchema}, child)
            for child in children
    ]
    schema = ArrowSchema(
        format,
        name,
        encoded_metadata,
        flags,
        children,
        dictionary,
        children_pointers,
        CArrowSchema(
            Base.unsafe_convert(Cstring, format),
            Base.unsafe_convert(Cstring, name),
            isnothing(encoded_metadata) ? C_NULL : pointer(encoded_metadata),
            flags,
            length(children),
            pointer(children_pointers),
            isnothing(dictionary) ? C_NULL : error("unsupported dictionary"),
            C_NULL,
            C_NULL,
        )
    )
    set_private_data!(schema)
    return schema
end

function Base.unsafe_convert(::Type{Ptr{CArrowSchema}}, schema::ArrowSchema)
    # `Base.fieldindex` constant-folds; see the `CArrowArray` method in arrow/array.jl.
    return Ptr{CArrowSchema}(
        Ptr{UInt8}(Base.pointer_from_objref(schema)) +
            fieldoffset(ArrowSchema, Base.fieldindex(ArrowSchema, :carrow_schema))
    )
end

"Holds references to the live schemas whose ownership has been given through ffi."
const LIVE_SCHEMAS = IdDict{ArrowSchema, Nothing}()
"""Guards `LIVE_SCHEMAS`; Rust may call the release callback from any thread."""
const LIVE_SCHEMAS_LOCK = ReentrantLock()
