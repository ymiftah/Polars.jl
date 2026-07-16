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

Bit-packs a `Vector{Bool}` (or `Vector{Union{Bool,Missing}}`) into the Arrow "b"-format data
buffer (1 bit per value, 8 values per byte). Julia's `Vector{Bool}` is a dense byte array (1
byte per value), unlike Arrow's boolean buffers, so this cannot be passed through directly the
way fixed-width numeric buffers are. `missing` slots are packed as `0`; their real value is
irrelevant since validity is tracked separately by `ValidityMap`.
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
    if T <: Vector
        return "+l"
    end

    @assert !ismutabletype(T)
    if isstructtype(T)
        return "+s"
    end

    throw("cannot find a arrow format for type $T")
end
format(::Type{MaybeMissing{T}}) where {T} = format(T)
format(::Type{Nothing}) = "n"
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
format(::Type{Vector{UInt8}}) = "z"
format(::Type{Vector{<:Any}}) = "+l"
format(::Type{String}) = "u"
format(::Type{DateTime}) = "tsn:"
format(::Type{Date}) = "tdD"

mutable struct ArrowArray
    vm::ValidityMap

    buffers::Vector{Union{Ptr, Vector}}
    buffer_ptrs::Vector{Ptr{UInt8}}

    children::Vector{ArrowArray}
    children_ptrs::Vector{Ptr{CArrowArray}}

    carrow_array::CArrowArray
end

function release_array!(array)
    for child in array.children
        delete!(LIVE_ARRAYS, child)
    end
    return delete!(LIVE_ARRAYS, array)
end

function base_release_array(carray_ptr::Ptr{CArrowArray})
    carray = unsafe_load(carray_ptr)
    array = unsafe_pointer_to_objref(Ptr{ArrowArray}(carray.private_data))
    release_array!(array)

    return nothing
end

"""
    set_private_data!(array::ArrowArray)

Makes the arrow array Julia managed.
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
    @assert !haskey(LIVE_ARRAYS, array)

    LIVE_ARRAYS[array] = nothing
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
    return Ptr{CArrowArray}(
        Ptr{UInt8}(Base.pointer_from_objref(array)) +
            fieldoffset(ArrowArray, findfirst(==(:carrow_array), fieldnames(ArrowArray)))
    )
end

"Holds references to the live arrays whose ownership has been given through ffi."
const LIVE_ARRAYS = IdDict{ArrowArray, Nothing}()

arrowvector(v::Vector{T}) where {T <: PhysicalDType} =
    ArrowArray(ValidityMap(v), [v], [])
arrowvector(v::Vector{MaybeMissing{T}}) where {T <: PhysicalDType} =
    ArrowArray(ValidityMap(v), [v], [])

# Bool is bit-packed in Arrow's "b" format, unlike the other PhysicalDType's fixed-width
# buffers, so it needs its own data-buffer construction (see boolbitmap).
arrowvector(v::Vector{Bool}) =
    ArrowArray(ValidityMap(v), [boolbitmap(v)], [])
arrowvector(v::Vector{MaybeMissing{Bool}}) =
    ArrowArray(ValidityMap(v), [boolbitmap(v)], [])

function arrowvector(v::Vector{S}) where {S <: Union{MaybeMissing{Dates.DateTime}}}
    # the timestamps are stored as the number of nanoseconds since 1970; missing entries are
    # mapped to a dummy 0 -- the validity bitmap (built from the same `v`) marks them null, so
    # the physical value underneath is never read back.
    values = map(d -> ismissing(d) ? zero(Int64) : Dates.Nanosecond(d - Dates.DateTime(1970, 01, 01)).value, v)
    return ArrowArray(ValidityMap(v), Vector[values])
end

function arrowvector(v::Vector{S}) where {S <: Union{MaybeMissing{Dates.Date}}}
    # dates are stored as the number of days since 1970; see the DateTime method above for why
    # missing entries can be mapped to a dummy 0.
    values = map(d -> ismissing(d) ? zero(Int32) : Int32(Dates.value(d - Dates.Date(1970, 01, 01))), v)
    return ArrowArray(ValidityMap(v), Vector[values])
end

function arrowvector(v::Vector{S}) where {S <: Union{MaybeMissing{String}, String}}
    byte_lengths = map(x -> ismissing(x) ? zero(UInt32) : UInt32(sizeof(x)), v)

    # The offsets buffer contains length + 1 signed integers (either 32-bit or 64-bit, depending on the logical type),
    # which encode the start position of each slot in the data buffer.
    # The length of the value in each slot is computed using the difference between
    # the offset at that slot’s index and the subsequent offset.
    offsets = Vector{UInt32}(undef, length(v) + 1)

    # Generally the first slot in the offsets array is 0, and the last slot is the length of the values array.
    # When serializing this layout, we recommend normalizing the offsets to start at 0.
    offsets[begin] = zero(UInt32)
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

# Binary (Vector{UInt8}) columns -- structurally identical to String above (offset+data buffers),
# just with bytes already raw (no codeunits conversion) and length instead of sizeof. Without this
# method, Vector{UInt8}-element columns fall through to the generic Vector{<:Vector{T}} methods
# below (T=UInt8 unifies), which build a "+l" list-shaped array while the schema declares "z"
# (binary) -- a structural mismatch the Rust-side FFI import rejects. This method's fixed bound is
# more specific than the generic methods' free `T`, so it wins dispatch cleanly.
function arrowvector(v::Vector{S}) where {S <: Union{MaybeMissing{Vector{UInt8}}, Vector{UInt8}}}
    byte_lengths = map(x -> ismissing(x) ? zero(UInt32) : UInt32(length(x)), v)

    offsets = Vector{UInt32}(undef, length(v) + 1)
    offsets[begin] = zero(UInt32)
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

Builds a `"+l"`-format (list) `ArrowArray`: an `Int32` offsets buffer (length `length(v)+1`,
cumulative sublist lengths) plus one recursive child array holding all sublists concatenated
end-to-end. `missing` sublists contribute a zero-length span (validity is tracked separately by
the `ValidityMap`, matching the convention already used for `DateTime`/`Date` above).
"""
function arrowvector(v::Vector{<:Vector{T}}) where {T}
    offsets = Vector{Int32}(undef, length(v) + 1)
    offsets[begin] = zero(Int32)
    @views cumsum!(offsets[(begin + 1):end], length.(v))
    flattened = reduce(vcat, v; init = T[])
    return ArrowArray(ValidityMap(v), Vector[offsets], [arrowvector(flattened)])
end
function arrowvector(v::Vector{S}) where {T, S <: MaybeMissing{Vector{T}}}
    lengths = map(x -> ismissing(x) ? 0 : length(x), v)
    offsets = Vector{Int32}(undef, length(v) + 1)
    offsets[begin] = zero(Int32)
    @views cumsum!(offsets[(begin + 1):end], lengths)
    flattened = reduce(vcat, (ismissing(x) ? T[] : x for x in v); init = T[])
    return ArrowArray(ValidityMap(v), Vector[offsets], [arrowvector(flattened)])
end

"""
    arrowvector(v::Vector{<:NamedTuple})::ArrowArray

Builds a `"+s"`-format (struct) `ArrowArray`: no buffers of its own, plus one recursive child
array per field, built from that field's values across all rows.
"""
function arrowvector(v::Vector{<:NamedTuple})
    NT = eltype(v)
    children = [arrowvector([getfield(row, fname) for row in v]) for fname in fieldnames(NT)]
    return ArrowArray(ValidityMap(v), Vector[], children)
end

"""
    column_schema(name, type)::ArrowSchema

Recursively builds the (possibly nested) `ArrowSchema` for a column of the given Julia element
`type`, attaching a child schema for `List` (`"+l"`) and one per field for `Struct` (`"+s"`)
columns -- `format(type)` alone only reports the outer shape, not its children.
"""
function column_schema(name, type)
    fmt = format(type)
    if fmt == "+l"
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

# Encodes the provided table to an ArrowArray
# this code should not fail as it can leak memory
# by populating LIVE_SCHEMAS or LIVE_ARRAYS with
# handles which are not given back to the caller
# in case of failure.
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

    ℓ = Tables.rowcount(Tables.columns(table))
    array = ArrowArray(
        ValidityMap(ℓ, 0, UInt8[]), [], [
            arrowvector(t)
                for t in Tables.columns(table)
        ]
    )

    return array, schema
end
