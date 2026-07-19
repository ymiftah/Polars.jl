# Bulk / zero-copy Rust -> Julia materialization via the Arrow C Data Interface.
#
# Mirror image of arrow/array.jl (Julia -> Rust write path). Ownership flips here: Rust/Arrow
# owns the exported buffers, so `ExportedArray` defers/guards the `release` callback instead of
# eagerly building one. See plans/zero_copy_rust_to_julia.md for the full design rationale.

using .API: ArrowArray as CArrowArray

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

"""Exports `series`' data via `polars_series_export_carray` and wraps the result as an
[`ExportedArray`](@ref), hoisting the out-param `Ref` + error-check dance shared by every
`read_series` branch below."""
function _export_carray(series::Series)
    out = Ref{CArrowArray}()
    err = polars_series_export_carray(series, out)
    polars_error(err)
    return ExportedArray(out[])
end

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
    return _dispatch_read(series.fmt, series, zerocopy)
end

"""Dispatches on a raw Arrow format string (`series.fmt`, cached at `Series` construction time --
see `load_series_schema`) to the matching bulk reader, or `nothing` if unsupported. A function
barrier: `fmt` is dynamic (a runtime `String`), so keeping the big format-string comparison chain
in its own small function lets each branch's body still compile fully type-stable once inlined."""
function _dispatch_read(fmt::String, series::Series, zerocopy::Bool)
    isempty(fmt) && return nothing # dictionary-encoded -- see `load_series_schema`'s sentinel

    if haskey(_NUMERIC_FORMATS, fmt)
        T = _NUMERIC_FORMATS[fmt]
        h = _export_carray(series)
        return _read_numeric(T, h, zerocopy)
    elseif fmt == "b"
        h = _export_carray(series)
        return _read_bool(h)
    elseif fmt == "vu" # Utf8View -- what polars actually produces for every String series
        h = _export_carray(series)
        return _read_view(String, h)
    elseif fmt == "vz" # BinaryView -- what polars actually produces for every Binary series
        h = _export_carray(series)
        return _read_view(Vector{UInt8}, h)
    elseif fmt in ("u", "U") # classic Utf8/LargeUtf8 (Int32/Int64 offsets) -- not produced by
        # polars itself (it always exports "vu"), but a defensive fallback for any other Arrow
        # producer this path might see in the future.
        h = _export_carray(series)
        return _read_offset(String, fmt == "u" ? Int32 : Int64, h)
    elseif fmt in ("z", "Z") # classic Binary/LargeBinary -- see the "u"/"U" note above.
        h = _export_carray(series)
        return _read_offset(Vector{UInt8}, fmt == "z" ? Int32 : Int64, h)
    elseif fmt == "tdD"
        h = _export_carray(series)
        return _read_transformed(Date, Int32, h, v -> Date(1970, 1, 1) + Dates.Day(v))
    elseif fmt in ("ttu", "ttn")
        # time64: nanoseconds ("ttn", what polars produces) or microseconds ("ttu"). The time32
        # encodings ("tts"/"ttm") are Int32-backed and fall through to the generic path below.
        NsPer = fmt == "ttn" ? 1 : 1000
        h = _export_carray(series)
        return _read_transformed(Dates.Time, Int64, h, v -> Dates.Time(Dates.Nanosecond(v * NsPer)))
    elseif fmt in ("tDn", "tDu", "tDm")
        PeriodT = fmt == "tDn" ? Dates.Nanosecond :
            fmt == "tDu" ? Dates.Microsecond : Dates.Millisecond
        h = _export_carray(series)
        return _read_transformed(PeriodT, Int64, h, PeriodT)
    elseif startswith(fmt, "tsn:") || startswith(fmt, "tsu:") || startswith(fmt, "tsm:")
        tz = fmt[5:end]
        isempty(tz) || return nothing # tz-aware: needs the TimeZones extension, fall back for now
        PeriodT = fmt[3] == 'n' ? Dates.Nanosecond :
            fmt[3] == 'u' ? Dates.Microsecond : Dates.Millisecond
        h = _export_carray(series)
        return _read_transformed(DateTime, Int64, h, v -> DateTime(1970, 1, 1) + PeriodT(v))
    else
        return nothing
    end
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

"""
    _materialize(::Type{String}, ptr::Ptr{UInt8}, len::Integer)
    _materialize(::Type{Vector{UInt8}}, ptr::Ptr{UInt8}, len::Integer)

Copies `len` raw bytes starting at `ptr` into an owned Julia `String`/`Vector{UInt8}`. Shared by
both the view-array (`_read_view`) and classic offset-array (`_read_offset`) bulk readers below.
"""
_materialize(::Type{String}, ptr::Ptr{UInt8}, len::Integer) = unsafe_string(ptr, len)
function _materialize(::Type{Vector{UInt8}}, ptr::Ptr{UInt8}, len::Integer)
    out = Vector{UInt8}(undef, len)
    unsafe_copyto!(pointer(out), ptr, len)
    return out
end

"""
    _view_bytes(views_ptr::Ptr{UInt8}, i::Integer, data_ptrs::Vector{Ptr{UInt8}})

Decodes the 16-byte Arrow "view" struct at 0-based logical position `i`: an `Int32` length,
followed either by 12 bytes of inline data (`length <= 12`) or by a 4-byte prefix (ignored here
-- the real bytes are read from the referenced data buffer instead), an `Int32` buffer index, and
an `Int32` offset (`length > 12`). Returns `(len, ptr)`, where `ptr` points at the actual byte
data -- either into the view struct itself (inline case) or into
`data_ptrs[buffer_index + 1]` (out-of-line case).
"""
@inline function _view_bytes(views_ptr::Ptr{UInt8}, i::Integer, data_ptrs::Vector{Ptr{UInt8}})
    base = views_ptr + 16 * i
    len = unsafe_load(Ptr{Int32}(base))
    len <= 12 && return Int(len), base + 4
    buf_idx = unsafe_load(Ptr{Int32}(base + 8))
    off = unsafe_load(Ptr{Int32}(base + 12))
    return Int(len), data_ptrs[buf_idx + 1] + off
end

"""
    _read_view(::Type{T}, h::ExportedArray) where {T <: Union{String, Vector{UInt8}}}

Bulk reader for Arrow's view-array formats ("vu" Utf8View / "vz" BinaryView) -- what polars
actually exports for every String/Binary series (confirmed live: `polars_series_schema` reports
"vu"/"vz" even for a `Series` built from this package's own classic-offset ("U"/"Z") write path,
since polars re-encodes to its native view representation on import). Replaces materializing
string/binary columns one element at a time through `polars_series_get` + `polars_value_*_get` +
an `IOBuffer` -- 2 ccalls and an allocation per row -- with a single bulk pass directly over the
exported Arrow buffers.

The C Data Interface's convention for a variadic buffer count: `buffers[0]` = validity,
`buffers[1]` = views, `buffers[2..end-1]` = the data buffers (zero or more, each up to ~2 GiB),
`buffers[end]` = a required trailing sizes buffer (one `Int64` per data buffer) that this reader
doesn't need to consult -- each view's `(buffer_index, offset, length)` is self-contained and
never crosses a buffer boundary.
"""
function _read_view(::Type{T}, h::ExportedArray) where {T <: Union{String, Vector{UInt8}}}
    ca, bufs = _buffers(h)
    n = Int(ca.length)

    if n == 0
        release!(h)
        return T[]
    end

    views_ptr = Ptr{UInt8}(bufs[2])
    n_data_buffers = Int(ca.n_buffers) - 3 # validity + views + the trailing sizes buffer
    data_ptrs = Ptr{UInt8}[Ptr{UInt8}(bufs[2 + k]) for k in 1:n_data_buffers]
    offset = Int(ca.offset)

    if ca.null_count == 0
        out = Vector{T}(undef, n)
        for i in 0:(n - 1)
            len, ptr = _view_bytes(views_ptr, offset + i, data_ptrs)
            out[i + 1] = _materialize(T, ptr, len)
        end
        release!(h)
        return out
    end

    validity_ptr = Ptr{UInt8}(bufs[1])
    out = Vector{Union{T, Missing}}(undef, n)
    for i in 0:(n - 1)
        if isvalid(validity_ptr, offset + i)
            len, ptr = _view_bytes(views_ptr, offset + i, data_ptrs)
            out[i + 1] = _materialize(T, ptr, len)
        else
            out[i + 1] = missing
        end
    end
    release!(h)
    return out
end

"""
    _read_offset(::Type{T}, ::Type{OffT}, h::ExportedArray) where {T <: Union{String, Vector{UInt8}}, OffT <: Union{Int32, Int64}}

Bulk reader for Arrow's classic offset-array formats (Utf8/LargeUtf8/Binary/LargeBinary):
`buffers[0]` = validity, `buffers[1]` = `length(v)+1` cumulative `OffT` offsets, `buffers[2]` =
the single concatenated data buffer. Not reachable from polars itself (it always exports the view
formats `_read_view` handles -- see that docstring), but kept for robustness against any other
Arrow C Data Interface producer this path might one day see.
"""
function _read_offset(::Type{T}, ::Type{OffT}, h::ExportedArray) where {T <: Union{String, Vector{UInt8}}, OffT}
    ca, bufs = _buffers(h)
    n = Int(ca.length)

    if n == 0
        release!(h)
        return T[]
    end

    offsets_ptr = Ptr{OffT}(bufs[2]) + Int(ca.offset) * sizeof(OffT)
    data_ptr = Ptr{UInt8}(bufs[3])

    if ca.null_count == 0
        out = Vector{T}(undef, n)
        for i in 1:n
            lo = unsafe_load(offsets_ptr, i)
            hi = unsafe_load(offsets_ptr, i + 1)
            out[i] = _materialize(T, data_ptr + lo, Int(hi - lo))
        end
        release!(h)
        return out
    end

    validity_ptr = Ptr{UInt8}(bufs[1])
    offset = Int(ca.offset)
    out = Vector{Union{T, Missing}}(undef, n)
    for i in 0:(n - 1)
        if isvalid(validity_ptr, offset + i)
            lo = unsafe_load(offsets_ptr, i + 1)
            hi = unsafe_load(offsets_ptr, i + 2)
            out[i + 1] = _materialize(T, data_ptr + lo, Int(hi - lo))
        else
            out[i + 1] = missing
        end
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
