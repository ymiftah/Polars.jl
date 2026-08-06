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
    # A subtype test in this untyped fallback, rather than a `format(::Type{Vector{<:Any}})`
    # method, is what catches every list column (`Vector{Int}`, `Vector{Vector{Int}}`, ...):
    # `Vector{<:Any}` collapses to the bare UnionAll `Vector`, so a `Type{Vector{<:Any}}` signature
    # matches only the literal unparameterized `Vector` value, never a concrete `Vector{X}`.
    if T <: Vector
        return "+L" # large-list (Int64 offsets) -- see the arrowvector methods below for why
    end

    # An immutable struct type maps to Arrow's Struct layout; a *mutable* one deliberately does
    # not (its fields can change under the buffers this package builds from them). An error ensures
    # this invariant is checked at runtime for user input, not disabled via assertions.
    if isstructtype(T) && !ismutabletype(T)
        return "+s"
    end

    error("cannot find an Arrow format for type $T")
end
format(::Type{MaybeMissing{T}}) where {T} = format(T)
# `MaybeMissing{Any}` (i.e. `Union{Any, Union{Any,Missing}}`) collapses to the literal type `Any`
# -- so without this method, `format(Any)` dispatches to the `MaybeMissing{T}` method above with
# `T = Any` solved from that same collapse, whose body calls `format(Any)` again: unconditional
# infinite recursion (a `StackOverflowError`, not a catchable error) for any column whose Tables.jl
# element type is bare `Any` -- e.g. a `Vector{<:NamedTuple}` built from row literals with
# differently-typed fields across rows, which never unify to a concrete common type. This
# concrete signature is strictly more specific than the `Type{MaybeMissing{T}} where T` method
# above and wins dispatch outright, breaking the self-match before it recurses.
format(::Type{Any}) = error(
    "cannot find an Arrow format for column type Any -- every element of a NamedTuple/struct " *
        "field (or other column) must share one concrete Julia type; a mix of concretely-typed " *
        "values and bare `missing` needs the column declared as `Union{T,Missing}`, not `Any`"
)
format(::Type{Nothing}) = "n"
# `MaybeMissing{Missing}` (i.e. `Union{Missing,Missing}`) collapses to the literal type `Missing`
# -- the same collapse hazard as the `Any` guard above, one level down: without this concrete
# method, `format(Missing)` (reached from a bare `Vector{Missing}` column, e.g.
# `DataFrame((; a = [missing, missing]))`) dispatches to the `MaybeMissing{T}` method with `T`
# solved from that same collapse, which Julia cannot bind, raising `UndefVarError: T not defined
# in static parameter matching` instead of working. With this method present, `arrowvector`
# dispatches `Vector{Missing}` to one of the existing `Vector{Union{Missing,T}}` numeric methods
# (Julia picks *some* concrete `T` satisfying that bound, arbitrarily) -- whichever placeholder
# "data" bytes that method writes for the all-invalid slots are never read back, since every
# position is marked invalid in the validity bitmap and this method's "n" format code is what the
# receiving side actually keys off of. Live-verified end-to-end (construction, group_by/filter,
# parquet round-trip) rather than assumed correct from the dispatch alone.
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

Unroots `array` from `LIVE_ARRAYS` (a no-op if `array` was never rooted -- i.e. it is a child,
kept alive only transitively through its parent's `children` field; see `root!`). Guarded by
`LIVE_ARRAYS_LOCK` since the release callback (`base_release_array`) can be invoked by Rust on
whatever thread drops the array, racing a concurrent Julia-side release.
"""
function release_array!(array)
    lock(LIVE_ARRAYS_LOCK) do
        delete!(LIVE_ARRAYS, array)
    end
    return nothing
end

"""
    base_release_array(carray_ptr::Ptr{CArrowArray})

The producer-side release callback installed on every `ArrowArray` (see `set_private_data!`). Per
the Arrow C Data Interface, a producer's release callback MUST walk all children structures and
call their own release callbacks, MUST free any data area it owns directly, and MUST mark the
structure released (`release = NULL`). Recursion through the whole tree falls out for free here:
every `ArrowArray` this package builds shares this same callback, so invoking a child's callback
walks *its* children in turn, all the way down to the leaves -- no explicit recursion needed on
the Julia side.
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

Installs the release callback and `private_data` pointer on `array`'s C struct -- required at
every nesting level, since `base_release_array` may end up invoking any array's callback while
walking down from an ancestor (see its docstring). Does **not** root `array` in `LIVE_ARRAYS`;
see `root!` for that.
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

Registers `array` in `LIVE_ARRAYS`, keeping it (and everything reachable through its `children`
field) alive from the Julia GC's perspective until Rust invokes its release callback. Only ever
needed for the top-level array handed across the FFI boundary (see `arrowtable`) -- children are
kept alive transitively through their parent's `children::Vector{ArrowArray}` field, so rooting
every nesting level independently would be redundant.
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
    # `Base.fieldindex` (as in `_mark_released!`) rather than `findfirst` over `fieldnames`: with
    # both arguments constant it folds away at compile time instead of searching on every single
    # conversion -- and this is the hot path every ccall taking an array goes through.
    return Ptr{CArrowArray}(
        Ptr{UInt8}(Base.pointer_from_objref(array)) +
            fieldoffset(ArrowArray, Base.fieldindex(ArrowArray, :carrow_array))
    )
end

"Holds references to the live arrays whose ownership has been given through ffi."
const LIVE_ARRAYS = IdDict{ArrowArray, Nothing}()
"""Guards `LIVE_ARRAYS`: the release callback (`base_release_array`) can be invoked by Rust on
whatever thread drops the array, racing a concurrent Julia-side insert/release."""
const LIVE_ARRAYS_LOCK = ReentrantLock()

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

function arrowvector(v::Vector{S}) where {S <: Union{MaybeMissing{Dates.Time}, Dates.Time}}
    # time-of-day is stored as nanoseconds since midnight (arrow time64, format "ttn"), matching
    # polars' `Time`; see the DateTime method above for why missing entries can be mapped to 0.
    # NB: `Dates.value(t)` is the *total* nanoseconds; `Dates.Nanosecond(t)` would be the 0-999
    # nanosecond component accessor instead.
    values = map(t -> ismissing(t) ? zero(Int64) : Int64(Dates.value(t)), v)
    return ArrowArray(ValidityMap(v), Vector[values])
end

function arrowvector(v::Vector{S}) where {S <: Union{MaybeMissing{String}, String}}
    # `format(String) == "U"` (large-utf8) needs Int64 offsets -- a plain `UInt32` offset here
    # would silently wrap (`cumsum!` overflow, corrupting every offset past the wraparound point)
    # once the column's total byte length crosses 4 GiB. Int64 offsets have no such practical
    # limit.
    byte_lengths = map(x -> ismissing(x) ? zero(Int64) : Int64(sizeof(x)), v)

    # The offsets buffer contains length + 1 signed integers (either 32-bit or 64-bit, depending on the logical type),
    # which encode the start position of each slot in the data buffer.
    # The length of the value in each slot is computed using the difference between
    # the offset at that slot’s index and the subsequent offset.
    offsets = Vector{Int64}(undef, length(v) + 1)

    # Generally the first slot in the offsets array is 0, and the last slot is the length of the values array.
    # When serializing this layout, we recommend normalizing the offsets to start at 0.
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

# Binary (Vector{UInt8}) columns -- structurally identical to String above (offset+data buffers),
# just with bytes already raw (no codeunits conversion) and length instead of sizeof. Without this
# method, Vector{UInt8}-element columns fall through to the generic Vector{<:Vector{T}} methods
# below (T=UInt8 unifies), which build a "+L" list-shaped array while the schema declares "Z"
# (large-binary) -- a structural mismatch the Rust-side FFI import rejects. This method's fixed
# bound is more specific than the generic methods' free `T`, so it wins dispatch cleanly.
function arrowvector(v::Vector{S}) where {S <: Union{MaybeMissing{Vector{UInt8}}, Vector{UInt8}}}
    # Int64 offsets to match `format(Vector{UInt8}) == "Z"` (large-binary) -- see the String
    # method above for why a 32-bit offset would be unsafe.
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

Builds a `"+L"`-format (large-list) `ArrowArray`: an `Int64` offsets buffer (length
`length(v)+1`, cumulative sublist lengths) plus one recursive child array holding all sublists
concatenated end-to-end. `missing` sublists contribute a zero-length span (validity is tracked
separately by the `ValidityMap`, matching the convention already used for `DateTime`/`Date`
above). Int64 (rather than the plain list format's Int32) offsets avoid a silent `cumsum!`
overflow once the total flattened element count crosses 2^31 -- see the same reasoning on the
String/binary `arrowvector` methods above.
"""
function arrowvector(v::Vector{<:Vector{T}}) where {T}
    offsets = Vector{Int64}(undef, length(v) + 1)
    offsets[begin] = zero(Int64)
    @views cumsum!(offsets[(begin + 1):end], length.(v))
    # `reduce(vcat, v; init = T[])` degrades to an O(n^2) left-fold concatenation -- it misses
    # Base's optimized single-allocation `vcat(v...)` since it goes through the `init` keyword.
    # The cumulative offsets just computed already give the total flattened length, so preallocate
    # once and copy each sublist into place instead.
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
    # See the non-missing method above for why this avoids `reduce(vcat, ...; init = T[])`.
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
`type`, attaching a child schema for `List` (`"+L"`) and one per field for `Struct` (`"+s"`)
columns -- `format(type)` alone only reports the outer shape, not its children.
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

Normalizes one Tables.jl column to a concrete `Vector`. Tables.jl only promises its columns are
`AbstractVector`s, but every `arrowvector` method above is written against a real `Vector` buffer
(it takes `pointer`s into it, or indexes it directly), so anything else -- a range, a `SubArray`,
another package's column type, or one of this package's own `Series` -- is materialized once here.
Done at the call site rather than as an `arrowvector(::AbstractVector)` fallback, which would
recurse forever for a `Vector` element type that has no method.
"""
_as_vector(column::Vector) = column
_as_vector(column::AbstractVector) = collect(column)

"""
    arrowtable(table, table_name)::Tuple{ArrowArray, ArrowSchema}

Encodes `table` (any Tables.jl-compatible source) into a top-level `ArrowArray`/`ArrowSchema` pair,
ready to hand across the FFI boundary. Only these two top-level objects are ever rooted (via
`root!`, called here only once every column/schema has been built without error) -- everything
built along the way (`column_schema`'s recursive children, each column's `arrowvector(t)`) is an
ordinary, never-rooted Julia value until it becomes reachable from one of these two, so a throw
partway through (an out-of-range `DateTime`, an unsupported dtype, ...) simply leaves unreferenced
garbage for the GC to collect -- nothing is ever registered in `LIVE_SCHEMAS`/`LIVE_ARRAYS` that
isn't given back to the caller.
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

    # Fetch each column by *name*, through the Tables.jl `AbstractColumns` interface, so the
    # columns line up with the schema children built above regardless of the source's own ordering.
    # Iterating a columns object directly is not part of that interface: it happens to work for a
    # `NamedTuple` and fails for anything else, including this package's own `DataFrameColumns`.
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
