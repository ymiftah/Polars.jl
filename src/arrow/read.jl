# Bulk / zero-copy Rust -> Julia materialization via the Arrow C Data Interface.
#
# Mirror image of arrow/array.jl (Julia -> Rust write path). Ownership flips here: Rust/Arrow
# owns the exported buffers, so `ExportedArray` defers/guards the `release` callback instead of
# eagerly building one. See plans/zero_copy_rust_to_julia.md for the full design rationale.

using .API:
    ArrowSchema as CArrowSchema,
    ArrowArray as CArrowArray

"""
    ExportedArray

Wraps a Rust-owned `ArrowArray` obtained from `polars_series_export_carray`. The wrapped struct's
`release` callback is invoked at most once via `release!` -- either eagerly, once the caller has
copied the data out, or from this object's finalizer if the caller keeps borrowing the raw buffers
(the true zero-copy path). `released` makes `release!` idempotent so eager release followed by a
GC-triggered finalizer call never double-frees.
"""
mutable struct ExportedArray
    carray::CArrowArray
    released::Bool

    function ExportedArray(carray::CArrowArray)
        h = new(carray, false)
        finalizer(release!, h)
        return h
    end
end

function release!(h::ExportedArray)
    h.released && return nothing
    h.released = true
    ref = Ref(h.carray)
    @ccall $(h.carray.release)(ref::Ptr{CArrowArray})::Cvoid
    return nothing
end

function _buffers(h::ExportedArray)
    ca = h.carray
    bufs = unsafe_wrap(Array, ca.buffers, Int(ca.n_buffers))
    return ca, bufs
end

"""
    isvalid(ptr::Ptr{UInt8}, i::Integer)::Bool

Bit-tests an Arrow validity/boolean bitmap (1 bit per value, 8 values per byte) at the *0-based*
logical position `i` -- the inverse of `boolbitmap`/`ValidityMap`'s packing in `arrow/array.jl`.
"""
@inline function isvalid(ptr::Ptr{UInt8}, i::Integer)
    byte = unsafe_load(ptr, 1 + (i ÷ 8))
    return Bool((byte >> (i % 8)) & 0x01)
end

const _NUMERIC_FORMATS = Dict{String, DataType}(
    "c" => Int8, "C" => UInt8,
    "s" => Int16, "S" => UInt16,
    "i" => Int32, "I" => UInt32,
    "l" => Int64, "L" => UInt64,
    "e" => Float16, "f" => Float32, "g" => Float64,
)

"""
    read_series(series::Series; zerocopy::Bool = false)

Bulk-materializes `series` into a native Julia `Vector` via the Arrow C Data Interface, or returns
`nothing` if `series`'s type isn't (yet) supported by this path -- callers should fall back to
per-element `getindex` in that case.

By default this *copies* the underlying buffer once (still zero ccalls, just one Julia-side pass)
into a freshly Julia-owned, freely mutable `Vector`. Passing `zerocopy = true` additionally allows,
for fixed-width numeric columns with no nulls, returning a `Vector` that directly aliases the
polars `Series`' own memory with no copy at all -- the returned array **must then be treated as
read-only**: it borrows live polars data and mutating it corrupts the source `Series`. `zerocopy`
is silently not honored (falls back to the safe copy) whenever the true zero-copy precondition
(no nulls, fixed-width numeric) doesn't hold.
"""
function read_series(series::Series; zerocopy::Bool = false)
    schema = polars_series_schema(series)
    fmt, is_dictionary = _schema_format!(schema)
    is_dictionary && return nothing

    if haskey(_NUMERIC_FORMATS, fmt)
        T = _NUMERIC_FORMATS[fmt]
        h = ExportedArray(polars_series_export_carray(series))
        return _read_numeric(T, h, zerocopy)
    elseif fmt == "b"
        h = ExportedArray(polars_series_export_carray(series))
        return _read_bool(h)
    elseif fmt == "tdD"
        h = ExportedArray(polars_series_export_carray(series))
        return _read_transformed(Date, Int32, h, v -> Date(1970, 1, 1) + Dates.Day(v))
    elseif fmt in ("tDn", "tDu", "tDm")
        PeriodT = fmt == "tDn" ? Dates.Nanosecond :
            fmt == "tDu" ? Dates.Microsecond : Dates.Millisecond
        h = ExportedArray(polars_series_export_carray(series))
        return _read_transformed(PeriodT, Int64, h, PeriodT)
    elseif startswith(fmt, "tsn:") || startswith(fmt, "tsu:") || startswith(fmt, "tsm:")
        tz = fmt[5:end]
        isempty(tz) || return nothing # tz-aware: needs the TimeZones extension, fall back for now
        PeriodT = fmt[3] == 'n' ? Dates.Nanosecond :
            fmt[3] == 'u' ? Dates.Microsecond : Dates.Millisecond
        h = ExportedArray(polars_series_export_carray(series))
        return _read_transformed(DateTime, Int64, h, v -> DateTime(1970, 1, 1) + PeriodT(v))
    else
        return nothing
    end
end

"""Reads the format string and releases the schema; the array export (if any) is independent."""
function _schema_format!(schema::CArrowSchema)
    is_dictionary = schema.dictionary != C_NULL
    fmt = is_dictionary ? "" : unsafe_string(schema.format)
    ref = Ref(schema)
    @ccall $(schema.release)(ref::Ptr{CArrowSchema})::Cvoid
    return fmt, is_dictionary
end

function _read_numeric(::Type{T}, h::ExportedArray, zerocopy::Bool) where {T}
    ca, bufs = _buffers(h)
    n = Int(ca.length)

    if n == 0
        release!(h)
        return T[]
    end

    data_ptr = Ptr{T}(bufs[2]) + Int(ca.offset) * sizeof(T)

    if ca.null_count == 0
        if zerocopy
            arr = unsafe_wrap(Array, data_ptr, n; own = false)
            finalizer(_ -> (h; nothing), arr) # keeps h (and its buffers) alive as long as arr is
            return arr
        end
        out = Vector{T}(undef, n)
        unsafe_copyto!(pointer(out), data_ptr, n)
        release!(h)
        return out
    end

    validity_ptr = Ptr{UInt8}(bufs[1])
    offset = Int(ca.offset)
    out = Vector{Union{T, Missing}}(undef, n)
    for i in 0:(n - 1)
        out[i + 1] = isvalid(validity_ptr, offset + i) ? unsafe_load(data_ptr, i + 1) : missing
    end
    release!(h)
    return out
end

function _read_bool(h::ExportedArray)
    ca, bufs = _buffers(h)
    n = Int(ca.length)
    offset = Int(ca.offset)

    if n == 0
        release!(h)
        return Bool[]
    end

    data_ptr = Ptr{UInt8}(bufs[2])

    if ca.null_count == 0
        out = Vector{Bool}(undef, n)
        for i in 0:(n - 1)
            out[i + 1] = isvalid(data_ptr, offset + i)
        end
        release!(h)
        return out
    end

    validity_ptr = Ptr{UInt8}(bufs[1])
    out = Vector{Union{Bool, Missing}}(undef, n)
    for i in 0:(n - 1)
        out[i + 1] = isvalid(validity_ptr, offset + i) ? isvalid(data_ptr, offset + i) : missing
    end
    release!(h)
    return out
end

"""
    _read_transformed(::Type{OutT}, ::Type{RawT}, h, transform)

Shared bulk-copy loop for columns whose physical (`RawT`) representation needs an elementwise
transform into the logical Julia type `OutT` -- e.g. Arrow's "days/ns since epoch" ints into
`Date`/`DateTime`/`Period`. Always copies (no zero-copy variant: the logical and physical
representations differ in width/shape).
"""
function _read_transformed(::Type{OutT}, ::Type{RawT}, h::ExportedArray, transform) where {OutT, RawT}
    ca, bufs = _buffers(h)
    n = Int(ca.length)

    if n == 0
        release!(h)
        return OutT[]
    end

    data_ptr = Ptr{RawT}(bufs[2]) + Int(ca.offset) * sizeof(RawT)

    if ca.null_count == 0
        out = Vector{OutT}(undef, n)
        for i in 1:n
            out[i] = transform(unsafe_load(data_ptr, i))
        end
        release!(h)
        return out
    end

    validity_ptr = Ptr{UInt8}(bufs[1])
    offset = Int(ca.offset)
    out = Vector{Union{OutT, Missing}}(undef, n)
    for i in 0:(n - 1)
        out[i + 1] = isvalid(validity_ptr, offset + i) ? transform(unsafe_load(data_ptr, i + 1)) : missing
    end
    release!(h)
    return out
end

function Base.collect(series::Series)
    out = read_series(series)
    out !== nothing && return out
    return [series[i] for i in eachindex(series)]
end

Base.Vector(series::Series) = collect(series)
