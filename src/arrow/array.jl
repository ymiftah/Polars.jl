using .API:
    ArrowSchema as CArrowSchema,
    ArrowArray as CArrowArray

## Validity Map (*heavily* inspired by Arrow.jl)

struct ValidityMap
    ℓ::Int
    nc::Int
    data::Vector{UInt8}
end

function ValidityMap(v)
    T = eltype(v)
    if !(T >: Missing)
        return ValidityMap(length(v), 0, UInt8[])
    end

    ℓ = length(v)
    nc = 0

    blen = cld(ℓ, 8)
    rest = ℓ % 8
    bits = Vector{UInt8}(undef, blen)

    b = 0x00
    for i in eachindex(v)
        i -= 1

        @inbounds if !ismissing(v[i + 1])
            b |= 0x01 << (i % 8)
        end

        @inbounds if (i + 1) % 8 == 0
            bits[1 + i ÷ 8] = b
            nc += Base.count_zeros(b)
            b = 0x00
        end
    end
    rest != 0 && (@inbounds bits[end] = b; nc += Base.count_zeros(b) - (8 - rest))

    return ValidityMap(ℓ, nc, bits)
end

function isvalid(vm::ValidityMap, i)
    i -= 1
    b = vm.data[1 + i ÷ 8]
    return Bool((b >> (i % 8)) & 0x01)
end

"""
    boolbitmap(v)::Vector{UInt8}

Bit-packs a `Vector{Bool}` (or `Vector{Union{Bool,Missing}}`) into an Arrow "b"-format data
buffer. `missing` slots are packed as `0` (validity is tracked by `ValidityMap`).
"""
function boolbitmap(v)
    ℓ = length(v)
    blen = cld(ℓ, 8)
    bits = Vector{UInt8}(undef, blen)

    b = 0x00
    for i in eachindex(v)
        i -= 1

        @inbounds val = v[i + 1]
        @inbounds if !ismissing(val) && val
            b |= 0x01 << (i % 8)
        end

        @inbounds if (i + 1) % 8 == 0
            bits[1 + i ÷ 8] = b
            b = 0x00
        end
    end
    rest = ℓ % 8
    rest != 0 && (@inbounds bits[end] = b)

    return bits
end

function validitybuffer(vm::ValidityMap)
    iszero(vm.nc) && return Ptr{UInt8}(C_NULL)
    return pointer(vm.data)
end

function format(T)
    # A subtype test: a `Type{Vector{<:Any}}` signature would match only the bare `Vector`.
    if T <: Vector
        return "+L" # large-list (Int64 offsets)
    end

    # Immutable struct types map to Arrow's Struct layout; mutable ones are not supported.
    if isstructtype(T) && !ismutabletype(T)
        return "+s"
    end

    error("cannot find an Arrow format for type $T")
end
format(::Type{MaybeMissing{T}}) where {T} = format(T)
# `MaybeMissing{Any}` is `Any`: without this method `format(Any)` would recurse forever through the
# `MaybeMissing{T}` method.
format(::Type{Any}) = error(
    "cannot find an Arrow format for column type Any -- every element of a NamedTuple/struct " *
        "field (or other column) must share one concrete Julia type; a mix of concretely-typed " *
        "values and bare `missing` needs the column declared as `Union{T,Missing}`, not `Any`"
)
format(::Type{Nothing}) = "n"
# `MaybeMissing{Missing}` is `Missing`, for which the `MaybeMissing{T}` method can't bind `T`. A
# `Vector{Missing}` column is written by a numeric `arrowvector` method, but every slot is invalid
# and the "n" format is what is read.
format(::Type{Missing}) = "n"
format(::Type{Bool}) = "b"
format(::Type{Int8}) = "c"
format(::Type{UInt8}) = "C"
format(::Type{Int16}) = "s"
format(::Type{UInt16}) = "S"
format(::Type{Int32}) = "i"
format(::Type{UInt32}) = "I"
format(::Type{Int64}) = "l"
format(::Type{UInt64}) = "L"
format(::Type{Float16}) = "e"
format(::Type{Float32}) = "f"
format(::Type{Float64}) = "g"
format(::Type{Vector{UInt8}}) = "Z" # large-binary (Int64 offsets)
format(::Type{String}) = "U" # large-utf8 (Int64 offsets)
format(::Type{DateTime}) = "tsn:"
format(::Type{Date}) = "tdD"
format(::Type{Dates.Time}) = "ttn"

# Arrow Duration. Needed ahead of the `isstructtype` fallback, since a `Period` is a struct.
format(::Type{Dates.Millisecond}) = "tDm"
format(::Type{Dates.Microsecond}) = "tDu"
format(::Type{Dates.Nanosecond}) = "tDn"
format(::Type{P}) where {P <: Dates.Period} = error(
    "Arrow has no Duration unit for $P -- polars' Duration is Millisecond, Microsecond or " *
        "Nanosecond only. Convert the column first, e.g. " *
        "`Dates.Millisecond.(column)` for a Day/Hour/Minute/Second column."
)

mutable struct ArrowArray
    vm::ValidityMap

    buffers::Vector{Union{Ptr, Vector}}
    buffer_ptrs::Vector{Ptr{UInt8}}

    children::Vector{ArrowArray}
    children_ptrs::Vector{Ptr{CArrowArray}}

    carrow_array::CArrowArray
end

"""
    release_array!(array::ArrowArray)

Unroots `array` from `LIVE_ARRAYS` (a no-op for a child array, which is never rooted). Takes
`LIVE_ARRAYS_LOCK`, since Rust may call the release callback from any thread.
"""
function release_array!(array)
    lock(LIVE_ARRAYS_LOCK) do
        delete!(LIVE_ARRAYS, array)
    end
    return nothing
end

"""
    base_release_array(carray_ptr::Ptr{CArrowArray})

The release callback installed on every `ArrowArray`: releases the children, unroots the array
and marks it released, as the Arrow C Data Interface requires.
"""
function base_release_array(carray_ptr::Ptr{CArrowArray})
    carray = unsafe_load(carray_ptr)
    array = unsafe_pointer_to_objref(Ptr{ArrowArray}(carray.private_data))

    for child in array.children
        child_ptr = Base.unsafe_convert(Ptr{CArrowArray}, child)
        release = unsafe_load(child_ptr).release
        release != C_NULL && @ccall $(release)(child_ptr::Ptr{CArrowArray})::Cvoid
    end

    _mark_released!(carray_ptr)
    _mark_released!(Base.unsafe_convert(Ptr{CArrowArray}, array))

    release_array!(array)
    return nothing
end

"""
    set_private_data!(array::ArrowArray)

Installs the release callback and `private_data` pointer on `array`'s C struct, at every nesting
level. Does not root `array`; see `root!`.
"""
function set_private_data!(array::ArrowArray)
    base_release_ptr = @cfunction base_release_array Cvoid (Ptr{CArrowArray},)

    array.carrow_array = CArrowArray(
        array.carrow_array.length,
        array.carrow_array.null_count,
        array.carrow_array.offset,
        array.carrow_array.n_buffers,
        array.carrow_array.n_children,
        array.carrow_array.buffers,
        array.carrow_array.children,
        array.carrow_array.dictionary,
        base_release_ptr,
        pointer_from_objref(array),
    )
    return nothing
end

"""
    root!(array::ArrowArray)

Registers the top-level `array` in `LIVE_ARRAYS`, keeping it and its children alive until Rust
calls its release callback.
"""
function root!(array::ArrowArray)
    lock(LIVE_ARRAYS_LOCK) do
        @assert !haskey(LIVE_ARRAYS, array)
        LIVE_ARRAYS[array] = nothing
    end
    return nothing
end

function ArrowArray(vm::ValidityMap, buffers, children = [])
    buffer_ptrs = [
        validitybuffer(vm),
        (
            buffer isa Ptr ? Ptr{UInt8}(buffer) : Ptr{UInt8}(pointer(buffer))
                for buffer in buffers
        )...,
    ]
    children_ptrs = [Base.unsafe_convert(Ptr{CArrowArray}, children) for children in children]

    array = ArrowArray(
        vm,
        buffers,
        buffer_ptrs,
        children,
        children_ptrs,
        CArrowArray(
            vm.ℓ,
            vm.nc,
            0,
            length(buffer_ptrs),
            length(children_ptrs),
            pointer(buffer_ptrs),
            pointer(children_ptrs),
            C_NULL,
            C_NULL,
            C_NULL,
        )
    )
    set_private_data!(array)
    return array
end

Base.cconvert(::Type{CArrowArray}, array::ArrowArray) = array
Base.unsafe_convert(::Type{CArrowArray}, array::ArrowArray) = array.carrow_array

function Base.unsafe_convert(::Type{Ptr{CArrowArray}}, array::ArrowArray)
    # `Base.fieldindex` with constant arguments folds away at compile time.
    return Ptr{CArrowArray}(
        Ptr{UInt8}(Base.pointer_from_objref(array)) +
            fieldoffset(ArrowArray, Base.fieldindex(ArrowArray, :carrow_array))
    )
end

"Holds references to the live arrays whose ownership has been given through ffi."
const LIVE_ARRAYS = IdDict{ArrowArray, Nothing}()
"""Guards `LIVE_ARRAYS`; Rust may call the release callback from any thread."""
const LIVE_ARRAYS_LOCK = ReentrantLock()

arrowvector(v::Vector{T}) where {T <: PhysicalDType} =
    ArrowArray(ValidityMap(v), [v], [])
arrowvector(v::Vector{MaybeMissing{T}}) where {T <: PhysicalDType} =
    ArrowArray(ValidityMap(v), [v], [])

# Bool is bit-packed in Arrow's "b" format (see `boolbitmap`).
arrowvector(v::Vector{Bool}) =
    ArrowArray(ValidityMap(v), [boolbitmap(v)], [])
arrowvector(v::Vector{MaybeMissing{Bool}}) =
    ArrowArray(ValidityMap(v), [boolbitmap(v)], [])

function arrowvector(v::Vector{S}) where {S <: Union{MaybeMissing{Dates.DateTime}}}
    # Nanoseconds since 1970. Missing entries are 0 (marked null in the validity bitmap).
    values = map(d -> ismissing(d) ? zero(Int64) : Dates.Nanosecond(d - Dates.DateTime(1970, 01, 01)).value, v)
    return ArrowArray(ValidityMap(v), Vector[values])
end

function arrowvector(v::Vector{S}) where {S <: Union{MaybeMissing{Dates.Date}}}
    # Days since 1970. Missing entries are 0.
    values = map(d -> ismissing(d) ? zero(Int32) : Int32(Dates.value(d - Dates.Date(1970, 01, 01))), v)
    return ArrowArray(ValidityMap(v), Vector[values])
end

function arrowvector(v::Vector{S}) where {S <: Union{MaybeMissing{Dates.Time}, Dates.Time}}
    # Nanoseconds since midnight (`Dates.value`, not the `Dates.Nanosecond` component). Missing
    # entries are 0.
    values = map(t -> ismissing(t) ? zero(Int64) : Int64(Dates.value(t)), v)
    return ArrowArray(ValidityMap(v), Vector[values])
end

function arrowvector(v::Vector{S}) where {P <: Union{Dates.Millisecond, Dates.Microsecond, Dates.Nanosecond}, S <: MaybeMissing{P}}
    # An Int64 count of the Duration's unit. Missing entries are 0.
    values = map(d -> ismissing(d) ? zero(Int64) : Int64(Dates.value(d)), v)
    return ArrowArray(ValidityMap(v), Vector[values])
end

function arrowvector(v::Vector{S}) where {S <: Union{MaybeMissing{String}, String}}
    # Int64 offsets, as large-utf8 ("U") requires.
    byte_lengths = map(x -> ismissing(x) ? zero(Int64) : Int64(sizeof(x)), v)

    # length + 1 offsets: the start of each slot in the data buffer, then the end.
    offsets = Vector{Int64}(undef, length(v) + 1)

    offsets[begin] = zero(Int64)
    @views cumsum!(offsets[(begin + 1):end], byte_lengths[begin:end])

    value_buffer = Vector{UInt8}(undef, sum(byte_lengths))

    for (i, s) in enumerate(v)
        ismissing(s) && continue
        copyto!(
            @view(value_buffer[(1 + offsets[i]):offsets[i + 1]]),
            codeunits(s)
        )
    end

    return ArrowArray(ValidityMap(v), Vector[offsets, value_buffer], [])
end

# Binary (`Vector{UInt8}`) columns: the same layout as String. More specific than the list
# methods below, which would otherwise match.
function arrowvector(v::Vector{S}) where {S <: Union{MaybeMissing{Vector{UInt8}}, Vector{UInt8}}}
    # Int64 offsets, as large-binary ("Z") requires.
    byte_lengths = map(x -> ismissing(x) ? zero(Int64) : Int64(length(x)), v)

    offsets = Vector{Int64}(undef, length(v) + 1)
    offsets[begin] = zero(Int64)
    @views cumsum!(offsets[(begin + 1):end], byte_lengths[begin:end])

    value_buffer = Vector{UInt8}(undef, sum(byte_lengths))

    for (i, s) in enumerate(v)
        ismissing(s) && continue
        copyto!(
            @view(value_buffer[(1 + offsets[i]):offsets[i + 1]]),
            s
        )
    end

    return ArrowArray(ValidityMap(v), Vector[offsets, value_buffer], [])
end

"""
    arrowvector(v::Vector{<:Vector})::ArrowArray

Builds a `"+L"`-format (large-list) `ArrowArray`: `Int64` offsets plus one child array holding
all sublists concatenated. A `missing` sublist has length zero.
"""
function arrowvector(v::Vector{<:Vector{T}}) where {T}
    offsets = Vector{Int64}(undef, length(v) + 1)
    offsets[begin] = zero(Int64)
    @views cumsum!(offsets[(begin + 1):end], length.(v))
    # Preallocate from the offsets; `reduce(vcat, v; init = T[])` would be O(n^2).
    flattened = Vector{T}(undef, Int(offsets[end]))
    i = 1
    for x in v
        copyto!(flattened, i, x, 1, length(x))
        i += length(x)
    end
    return ArrowArray(ValidityMap(v), Vector[offsets], [arrowvector(flattened)])
end
function arrowvector(v::Vector{S}) where {T, S <: MaybeMissing{Vector{T}}}
    lengths = map(x -> ismissing(x) ? 0 : length(x), v)
    offsets = Vector{Int64}(undef, length(v) + 1)
    offsets[begin] = zero(Int64)
    @views cumsum!(offsets[(begin + 1):end], lengths)
    # Preallocate from the offsets, as above.
    flattened = Vector{T}(undef, Int(offsets[end]))
    i = 1
    for x in v
        ismissing(x) && continue
        copyto!(flattened, i, x, 1, length(x))
        i += length(x)
    end
    return ArrowArray(ValidityMap(v), Vector[offsets], [arrowvector(flattened)])
end

"""
    arrowvector(v::Vector{T})::ArrowArray

Fallback: the `"+s"` (struct) layout for a `NamedTuple` or other immutable struct element type,
with one child array per field. Children are widened to `MaybeMissing` so that a `missing` row
has a placeholder value. Any other element type raises via `format`.
"""
function arrowvector(v::Vector{T}) where {T}
    fmt = format(T) # raises for an element type with no Arrow mapping at all
    fmt == "+s" || error(
        "no arrowvector method for column element type $T (arrow format \"$fmt\") -- this is a " *
            "gap in Polars.jl's Arrow write path, not a problem with your data"
    )
    S = nonmissingtype(T)
    children = [
        arrowvector(
            MaybeMissing{fieldtype(S, fname)}[
                ismissing(row) ? missing : getfield(row, fname) for row in v
            ]
        ) for fname in fieldnames(S)
    ]
    return ArrowArray(ValidityMap(v), Vector[], children)
end

"""
    column_schema(name, type)::ArrowSchema

Recursively builds the `ArrowSchema` for a column of element type `type`, including child schemas
for List (`"+L"`) and Struct (`"+s"`) columns.
"""
function column_schema(name, type)
    fmt = format(type)
    if fmt == "+L"
        T = nonmissingtype(type)
        return ArrowSchema(; format = fmt, name = string(name), children = [column_schema("item", eltype(T))])
    elseif fmt == "+s"
        T = nonmissingtype(type)
        children = [column_schema(string(fname), fieldtype(T, fname)) for fname in fieldnames(T)]
        return ArrowSchema(; format = fmt, name = string(name), children)
    else
        return ArrowSchema(; format = fmt, name = string(name))
    end
end

"""
    _as_vector(column)::Vector

Converts a Tables.jl column to a `Vector`, which every `arrowvector` method requires.
"""
_as_vector(column::Vector) = column
_as_vector(column::AbstractVector) = collect(column)

"""
    arrowtable(table, table_name)::Tuple{ArrowArray, ArrowSchema}

Encodes a Tables.jl `table` into a top-level `ArrowArray`/`ArrowSchema` pair for the FFI. The two
are rooted only after every column has been built, so an error partway leaves nothing rooted.
"""
function arrowtable(table, table_name)
    tschema = Tables.schema(table)

    children = map(zip(tschema.names, tschema.types)) do (name, type)
        column_schema(name, type)
    end

    schema = ArrowSchema(;
        format = "+s",
        name = table_name,
        children
    )

    # Fetch columns by name through the Tables.jl interface, matching the schema children.
    cols = Tables.columns(table)
    ℓ = Tables.rowcount(cols)
    array = ArrowArray(
        ValidityMap(ℓ, 0, UInt8[]), [], [
            arrowvector(_as_vector(Tables.getcolumn(cols, name)))
                for name in tschema.names
        ]
    )

    root!(schema)
    root!(array)

    return array, schema
end
