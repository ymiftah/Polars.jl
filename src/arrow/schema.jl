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
    fmt == "z" && return MaybeMissing{Vector{UInt8}}
    fmt == "Z" && return MaybeMissing{Vector{UInt8}}
    fmt == "vz" && return MaybeMissing{Vector{UInt8}}

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

    # Arrow spells time-of-day as time32 ("tts"/"ttm") or time64 ("ttu"/"ttn"). All four collapse
    # to `Dates.Time`, which is itself nanosecond-resolution; polars only ever produces "ttn"
    # (its `Time` is always nanoseconds since midnight), but accept the narrower encodings too.
    fmt in ("tts", "ttm", "ttu", "ttn") && return MaybeMissing{Dates.Time}

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

    # List columns materialize as plain nested `Vector`s (not `Series`) -- see `_read_list` in
    # arrow/read.jl for the bulk reader and its docstring for why this is the right contract
    # (consistent with Struct materializing as a plain `NamedTuple` just above, not a `Series`).
    if fmt in ("+l", "+L")
        schema.n_children == 1 || error(
            "malformed Arrow List schema: expected exactly 1 child, got $(schema.n_children)"
        )
        children = unsafe_load(schema.children) |> unsafe_load
        T = parse_format(children)
        return MaybeMissing{Vector{T}}
    end

    if startswith(fmt, "+w") # Fixed size list (polars' Array dtype)
        # `Series`/`getindex`/`load_value` have no materialization path for a fixed-size-list
        # element type (unlike the `+l`/`+L` List case just above) -- raise here with a clear
        # explanation rather than returning an `NTuple` type that then fails opaquely (a bare
        # `MethodError` from `getindex`) the moment anyone actually reads the column.
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

Returns `(name, T, fmt)`: `T` is the same fully-resolved Julia element type `parse_format` always
computed; `fmt` is the raw top-level Arrow format string (`""` for a dictionary-encoded column --
`read.jl`'s `_dispatch_read` treats this as its "unsupported, fall back" sentinel) -- cheap to
carry alongside `T` since `schema.format` is already being read here, and lets `Series` cache it
at construction time so `read_series` doesn't need to re-fetch and re-parse the schema on every
`collect`.

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
    # Real errors rather than `@assert`s: these validate data that just crossed the FFI boundary
    # (the one place a silently-disabled check would turn a malformed schema into a segfault),
    # not an invariant this package establishes itself.
    fmt = unsafe_string(schema.format)
    fmt == "+s" || error("invalid polars schema: expected a struct format \"+s\", got \"$fmt\"")

    name = unsafe_string(schema.name)
    name == "polars.dataframe" ||
        error("invalid polars schema: expected the name \"polars.dataframe\", got \"$name\"")

    NT = parse_format(schema)
    NT = nomissing(NT)
    NT <: NamedTuple || error("invalid polars schema: expected a NamedTuple type, got $NT")
    names, types = NT.parameters

    # Explicitely release after reading the schema names and types
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
    # Holds the already-*encoded* metadata bytes (see `_encode_metadata`), not the raw input --
    # this is what the `Cstring`-typed C field's pointer aliases, so it must stay alive exactly
    # like `format`/`name` do for their own C string pointers.
    metadata::Union{Nothing, Vector{UInt8}}
    flags::Int64
    children::Vector{ArrowSchema}
    dictionary::Union{Nothing, ArrowSchema}

    children_pointers::Vector{Ptr{CArrowSchema}}
    carrow_schema::CArrowSchema
end

"""
    _encode_metadata(pairs)::Vector{UInt8}

Encodes an ordered collection of `key => value` string pairs (e.g. a `Vector{Pair}` or `Dict`)
into the Arrow C Data Interface's binary `metadata` format: an `Int32` pair count, then per pair
an `Int32` key byte-length + key bytes + `Int32` value byte-length + value bytes, all in native
endianness -- *not* NUL-terminated, unlike a plain C string.
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

Writes `C_NULL` into the `release` field of the `CArrowSchema`/`CArrowArray` pointed to by `ptr`,
in place. The Arrow C Data Interface requires a producer's release callback to mark the structure
released this way (so a later consumer can detect it rather than blindly re-invoking a dangling
callback); shared between `base_release_schema` (here) and `base_release_array`
(arrow/array.jl) since both C structs share the same trailing `(release, private_data)` layout.
"""
function _mark_released!(ptr::Ptr{T}) where {T}
    offset = fieldoffset(T, Base.fieldindex(T, :release))
    unsafe_store!(Ptr{Ptr{Cvoid}}(Ptr{UInt8}(ptr) + offset), C_NULL)
    return nothing
end

"""
    _release_or_throw(release::Ptr{Cvoid}, structptr::Ptr)

Calls the Arrow C Data Interface release callback `release` on `structptr`, or throws if
`release` is already `C_NULL`. Per the spec, consumers SHOULD check for a released structure
before touching it; without this, a structure released twice would invoke a dangling function
pointer -- a segfault, not a catchable Julia error.
"""
function _release_or_throw(release::Ptr{Cvoid}, structptr::Ptr)
    release == C_NULL && error("Arrow C Data Interface structure was already released")
    @ccall $(release)(structptr::Ptr{Cvoid})::Cvoid
    return nothing
end

"""
    release_schema!(schema::ArrowSchema)

Unroots `schema` from `LIVE_SCHEMAS` (a no-op if `schema` was never rooted -- i.e. it is a child,
kept alive only transitively through its parent's `children` field; see `root!`). Guarded by
`LIVE_SCHEMAS_LOCK` since `release_schema!` can run from `base_release_schema`, invoked by Rust's
own release callback on whatever thread drops the schema, racing a concurrent Julia-side release.
"""
function release_schema!(schema)
    lock(LIVE_SCHEMAS_LOCK) do
        delete!(LIVE_SCHEMAS, schema)
    end
    return nothing
end

"""
    base_release_schema(schema_ptr::Ptr{CArrowSchema})

The producer-side release callback installed on every `ArrowSchema` (see `set_private_data!`). Per
the Arrow C Data Interface, a producer's release callback MUST walk all children structures and
call their own release callbacks, MUST free any data area it owns directly, and MUST mark the
structure released (`release = NULL`). Recursion through the whole tree falls out for free here:
every `ArrowSchema` this package builds shares this same callback, so invoking a child's callback
walks *its* children in turn, all the way down to the leaves -- no explicit recursion needed on
the Julia side (contrast with the old `release_schema!`, which had to recurse because every level
used to root itself independently in `LIVE_SCHEMAS`).
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

Installs the release callback and `private_data` pointer on `schema`'s C struct -- required at
every nesting level, since `base_release_schema` may end up invoking any schema's callback while
walking down from an ancestor (see its docstring). Does **not** root `schema` in `LIVE_SCHEMAS`;
see `root!` for that.
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

Registers `schema` in `LIVE_SCHEMAS`, keeping it (and everything reachable through its `children`
field) alive from the Julia GC's perspective until Rust invokes its release callback. Only ever
needed for the top-level schema handed across the FFI boundary (see `arrowtable`) -- children are
kept alive transitively through their parent's `children::Vector{ArrowSchema}` field, so rooting
every nesting level independently (the old behavior) was both unnecessary and the reason
`release_schema!` used to have to recurse.
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
    # See the matching comment on `unsafe_convert(::Type{Ptr{CArrowArray}}, ...)` in arrow/array.jl
    # for why this is `Base.fieldindex` rather than a runtime `findfirst`.
    return Ptr{CArrowSchema}(
        Ptr{UInt8}(Base.pointer_from_objref(schema)) +
            fieldoffset(ArrowSchema, Base.fieldindex(ArrowSchema, :carrow_schema))
    )
end

"Holds references to the live schemas whose ownership has been given through ffi."
const LIVE_SCHEMAS = IdDict{ArrowSchema, Nothing}()
"""Guards `LIVE_SCHEMAS`: the release callback (`base_release_schema`) can be invoked by Rust on
whatever thread drops the schema, racing a concurrent Julia-side insert/release."""
const LIVE_SCHEMAS_LOCK = ReentrantLock()
