# Bulk and zero-copy Rust -> Julia reads via the Arrow C Data Interface (the reverse of
# arrow/array.jl). Rust owns the exported buffers; `ExportedArray` calls their `release` callback.

using .API:
    ArrowArray as CArrowArray,
    ArrowSchema as CArrowSchema

"""
    ExportedArray

Wraps a Rust-owned `ArrowArray` from `polars_series_export_carray`. `release!` calls its release
callback at most once (`released`): eagerly after copying, or from the finalizer. `borrowed` marks
a handle whose buffers a returned `Vector` still aliases, so it must not be released eagerly.
"""
mutable struct ExportedArray
    carray::CArrowArray
    released::Bool
    borrowed::Bool

    function ExportedArray(carray::CArrowArray)
        h = new(carray, false, false)
        finalizer(release!, h)
        return h
    end
end

function release!(h::ExportedArray)
    h.released && return nothing
    h.released = true
    ref = Ref(h.carray)
    GC.@preserve ref _release_or_throw(h.carray.release, Base.unsafe_convert(Ptr{CArrowArray}, ref))
    return nothing
end

"""
Roots each zero-copy-borrowed `ExportedArray` while a returned `Vector` aliases its buffers. (A
closure capture alone is not a reliable keepalive: the compiler may elide it.)
"""
const LIVE_BORROWED_ARRAYS = IdDict{ExportedArray, Nothing}()
"Guards `LIVE_BORROWED_ARRAYS` against concurrent root/unroot from separate Julia tasks."
const LIVE_BORROWED_ARRAYS_LOCK = ReentrantLock()

function _buffers(h::ExportedArray)
    return _buffers(h.carray)
end

"""`_buffers` for a child `CArrowArray`, which is released with its parent."""
function _buffers(ca::CArrowArray)
    bufs = unsafe_wrap(Array, ca.buffers, Int(ca.n_buffers))
    return ca, bufs
end

"""
    isvalid(ptr::Ptr{UInt8}, i::Integer)::Bool

Bit-tests an Arrow validity or boolean bitmap at the 0-based position `i`.
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

"""Exports `series` via `polars_series_export_carray` as an `ExportedArray`."""
function _export_carray(series::Series)
    out = Ref{CArrowArray}()
    err = polars_series_export_carray(series, out)
    polars_error(err)
    return ExportedArray(out[])
end

"""
    read_series(series::Series; zerocopy::Bool = false)

Read `series` into a `Vector` in bulk, or return `nothing` if its dtype isn't supported (use
`getindex` per element instead).

The data is copied. With `zerocopy = true`, a fixed-width numeric column without nulls is returned
as a `Vector` that aliases the series' memory; it must not be mutated. Otherwise `zerocopy` has no
effect.
"""
function read_series(series::Series; zerocopy::Bool = false)
    return _dispatch_read(series.fmt, series, zerocopy)
end

"""Dispatches on the Arrow format string `fmt` to a bulk reader (`nothing` if unsupported). Exports
the array once and releases it afterwards, unless the result borrows its buffers (`h.borrowed`)."""
function _dispatch_read(fmt::String, series::Series, zerocopy::Bool)
    isempty(fmt) && return nothing # dictionary-encoded -- see `load_series_schema`'s sentinel
    fmt in ("+l", "+L") && return _read_list(series, fmt)

    h = _export_carray(series)
    ca, bufs = _buffers(h)
    out = _read_view_dispatch(fmt, ca, bufs, zerocopy, h)
    h.borrowed || release!(h)
    return out
end

"""Reads a leaf (non-List/Struct/dictionary) column from an exported `(ca, bufs)` by format
string, or returns `nothing`. A function barrier over the runtime `fmt`. `keepalive` is the
`ExportedArray` to root for a zero-copy result; with `nothing`, the data is always copied."""
function _read_view_dispatch(
        fmt::String, ca::CArrowArray, bufs::Vector, zerocopy::Bool,
        keepalive::Union{ExportedArray, Nothing}
    )
    if haskey(_NUMERIC_FORMATS, fmt)
        T = _NUMERIC_FORMATS[fmt]
        return _read_numeric(T, ca, bufs, zerocopy, keepalive)
    elseif fmt == "b"
        return _read_bool(ca, bufs)
    elseif fmt == "vu" # Utf8View, what polars exports for String
        return _read_view(String, ca, bufs)
    elseif fmt == "vz" # BinaryView, what polars exports for Binary
        return _read_view(Vector{UInt8}, ca, bufs)
    elseif fmt in ("u", "U") # Utf8/LargeUtf8 (Int32/Int64 offsets)
        return _read_offset(String, fmt == "u" ? Int32 : Int64, ca, bufs)
    elseif fmt in ("z", "Z") # Binary/LargeBinary
        return _read_offset(Vector{UInt8}, fmt == "z" ? Int32 : Int64, ca, bufs)
    elseif fmt == "tdD"
        return _read_transformed(Date, Int32, ca, bufs, v -> Date(1970, 1, 1) + Dates.Day(v))
    elseif fmt in ("ttu", "ttn")
        # time64 in nanoseconds or microseconds; time32 ("tts"/"ttm") is not handled here.
        NsPer = fmt == "ttn" ? 1 : 1000
        return _read_transformed(Dates.Time, Int64, ca, bufs, v -> Dates.Time(Dates.Nanosecond(v * NsPer)))
    elseif fmt in ("tDn", "tDu", "tDm")
        PeriodT = fmt == "tDn" ? Dates.Nanosecond :
            fmt == "tDu" ? Dates.Microsecond : Dates.Millisecond
        return _read_transformed(PeriodT, Int64, ca, bufs, PeriodT)
    elseif startswith(fmt, "tsn:") || startswith(fmt, "tsu:") || startswith(fmt, "tsm:")
        tz = fmt[5:end]
        isempty(tz) || return nothing # tz-aware: needs the TimeZones extension, fall back for now
        PeriodT = fmt[3] == 'n' ? Dates.Nanosecond :
            fmt[3] == 'u' ? Dates.Microsecond : Dates.Millisecond
        return _read_transformed(DateTime, Int64, ca, bufs, v -> DateTime(1970, 1, 1) + PeriodT(v))
    else
        return nothing
    end
end

function _read_numeric(
        ::Type{T}, ca::CArrowArray, bufs::Vector, zerocopy::Bool,
        keepalive::Union{ExportedArray, Nothing}
    ) where {T}
    n = Int(ca.length)

    n == 0 && return T[]

    data_ptr = Ptr{T}(bufs[2]) + Int(ca.offset) * sizeof(T)

    if ca.null_count == 0
        # Without a `keepalive` to root, copy.
        if zerocopy && keepalive !== nothing
            keepalive.borrowed = true # tells `_dispatch_read` not to eagerly release `keepalive`
            arr = unsafe_wrap(Array, data_ptr, n; own = false)
            # Root only once `arr`, whose finalizer unroots it, exists.
            lock(LIVE_BORROWED_ARRAYS_LOCK) do
                LIVE_BORROWED_ARRAYS[keepalive] = nothing
            end
            # Unroot and release `keepalive` once `arr` is collected. The lock taken in this
            # finalizer guards only a non-yielding `delete!`; keep `release!` outside it.
            finalizer(arr) do _
                lock(LIVE_BORROWED_ARRAYS_LOCK) do
                    delete!(LIVE_BORROWED_ARRAYS, keepalive)
                end
                release!(keepalive)
            end
            return arr
        end
        out = Vector{T}(undef, n)
        unsafe_copyto!(pointer(out), data_ptr, n)
        return out
    end

    validity_ptr = Ptr{UInt8}(bufs[1])
    offset = Int(ca.offset)
    out = Vector{Union{T, Missing}}(undef, n)
    for i in 0:(n - 1)
        out[i + 1] = isvalid(validity_ptr, offset + i) ? unsafe_load(data_ptr, i + 1) : missing
    end
    return out
end

function _read_bool(ca::CArrowArray, bufs::Vector)
    n = Int(ca.length)
    offset = Int(ca.offset)

    n == 0 && return Bool[]

    data_ptr = Ptr{UInt8}(bufs[2])

    if ca.null_count == 0
        out = Vector{Bool}(undef, n)
        for i in 0:(n - 1)
            out[i + 1] = isvalid(data_ptr, offset + i)
        end
        return out
    end

    validity_ptr = Ptr{UInt8}(bufs[1])
    out = Vector{Union{Bool, Missing}}(undef, n)
    for i in 0:(n - 1)
        out[i + 1] = isvalid(validity_ptr, offset + i) ? isvalid(data_ptr, offset + i) : missing
    end
    return out
end

"""
    _read_transformed(::Type{OutT}, ::Type{RawT}, ca, bufs, transform)

Bulk copy of a column whose physical values (`RawT`) are transformed elementwise into `OutT`, e.g.
days since epoch into `Date`.
"""
function _read_transformed(::Type{OutT}, ::Type{RawT}, ca::CArrowArray, bufs::Vector, transform) where {OutT, RawT}
    n = Int(ca.length)

    n == 0 && return OutT[]

    data_ptr = Ptr{RawT}(bufs[2]) + Int(ca.offset) * sizeof(RawT)

    if ca.null_count == 0
        out = Vector{OutT}(undef, n)
        for i in 1:n
            out[i] = transform(unsafe_load(data_ptr, i))
        end
        return out
    end

    validity_ptr = Ptr{UInt8}(bufs[1])
    offset = Int(ca.offset)
    out = Vector{Union{OutT, Missing}}(undef, n)
    for i in 0:(n - 1)
        out[i + 1] = isvalid(validity_ptr, offset + i) ? transform(unsafe_load(data_ptr, i + 1)) : missing
    end
    return out
end

"""
    _materialize(::Type{String}, ptr::Ptr{UInt8}, len::Integer)
    _materialize(::Type{Vector{UInt8}}, ptr::Ptr{UInt8}, len::Integer)

Copies `len` bytes at `ptr` into a `String` or `Vector{UInt8}`.
"""
_materialize(::Type{String}, ptr::Ptr{UInt8}, len::Integer) = unsafe_string(ptr, len)
function _materialize(::Type{Vector{UInt8}}, ptr::Ptr{UInt8}, len::Integer)
    out = Vector{UInt8}(undef, len)
    unsafe_copyto!(pointer(out), ptr, len)
    return out
end

"""
    _view_bytes(views_ptr::Ptr{UInt8}, i::Integer, data_ptrs::Vector{Ptr{UInt8}})

Decodes the 16-byte Arrow view struct at 0-based position `i`: an `Int32` length, then either 12
bytes of inline data (`length <= 12`) or a 4-byte prefix, an `Int32` buffer index and an `Int32`
offset. Returns `(len, ptr)` with `ptr` pointing at the bytes.
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
    _read_view(::Type{T}, ca, bufs) where {T <: Union{String, Vector{UInt8}}}

Bulk reader for the Arrow view formats "vu" (Utf8View) and "vz" (BinaryView), which polars
exports for String and Binary.

Buffers: validity, views, the data buffers, then a trailing sizes buffer (not needed here).
"""
function _read_view(::Type{T}, ca::CArrowArray, bufs::Vector) where {T <: Union{String, Vector{UInt8}}}
    n = Int(ca.length)

    n == 0 && return T[]

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
    return out
end

"""
    _read_offset(::Type{T}, ::Type{OffT}, ca, bufs) where {T <: Union{String, Vector{UInt8}}, OffT <: Union{Int32, Int64}}

Bulk reader for the Arrow offset formats (Utf8/LargeUtf8/Binary/LargeBinary). Buffers: validity,
`length + 1` offsets of type `OffT`, and the data.
"""
function _read_offset(::Type{T}, ::Type{OffT}, ca::CArrowArray, bufs::Vector) where {T <: Union{String, Vector{UInt8}}, OffT}
    n = Int(ca.length)

    n == 0 && return T[]

    offsets_ptr = Ptr{OffT}(bufs[2]) + Int(ca.offset) * sizeof(OffT)
    data_ptr = Ptr{UInt8}(bufs[3])

    if ca.null_count == 0
        out = Vector{T}(undef, n)
        for i in 1:n
            lo = unsafe_load(offsets_ptr, i)
            hi = unsafe_load(offsets_ptr, i + 1)
            out[i] = _materialize(T, data_ptr + lo, Int(hi - lo))
        end
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
    return out
end

"""
    _read_list(series::Series, fmt::String)

Bulk reader for the Arrow List formats (`"+l"` Int32 / `"+L"` Int64 offsets). Reads the whole
child column once, then copies out one `Vector` per row.

Only leaf child types are supported; nested lists, structs and dictionary-encoded children return
`nothing` (per-element fallback).

The row element type comes from `parse_format(child_schema)`, which is always `MaybeMissing`; the
child data is widened to match so the result has the declared `eltype`.
"""
function _read_list(series::Series, fmt::String)
    schema_out = Ref{CArrowSchema}()
    err = polars_series_schema(series, schema_out)
    polars_error(err)
    schema = schema_out[]
    child_schema = unsafe_load(unsafe_load(schema.children, 1))
    is_dict_child = child_schema.dictionary != C_NULL
    child_fmt = is_dict_child ? "" : unsafe_string(child_schema.format)
    unsupported = is_dict_child || startswith(child_fmt, "+l") || startswith(child_fmt, "+L") || child_fmt == "+s"
    # For a leaf format `parse_format` only reads `format`/`dictionary`, before `schema` is
    # released.
    ElemT = unsupported ? Missing : parse_format(child_schema)
    schema_ref = Ref(schema)
    GC.@preserve schema_ref _release_or_throw(schema.release, Base.unsafe_convert(Ptr{CArrowSchema}, schema_ref))
    unsupported && return nothing

    h = _export_carray(series)
    ca, bufs = _buffers(h)

    child_ca, child_bufs = _buffers(unsafe_load(unsafe_load(ca.children, 1)))
    child_data_raw = _read_view_dispatch(child_fmt, child_ca, child_bufs, false, nothing)
    if child_data_raw === nothing # defensive: shouldn't happen given the pre-check above
        release!(h)
        return nothing
    end
    child_data = eltype(child_data_raw) === ElemT ? child_data_raw : convert(Vector{ElemT}, child_data_raw)

    n = Int(ca.length)
    if n == 0
        release!(h)
        return Vector{ElemT}[]
    end

    OffT = fmt == "+l" ? Int32 : Int64
    offsets_ptr = Ptr{OffT}(bufs[2]) + Int(ca.offset) * sizeof(OffT)

    if ca.null_count == 0
        out = Vector{Vector{ElemT}}(undef, n)
        for i in 1:n
            lo = unsafe_load(offsets_ptr, i)
            hi = unsafe_load(offsets_ptr, i + 1)
            out[i] = child_data[(Int(lo) + 1):Int(hi)]
        end
        release!(h)
        return out
    end

    validity_ptr = Ptr{UInt8}(bufs[1])
    offset = Int(ca.offset)
    out = Vector{Union{Vector{ElemT}, Missing}}(undef, n)
    for i in 0:(n - 1)
        if isvalid(validity_ptr, offset + i)
            lo = unsafe_load(offsets_ptr, i + 1)
            hi = unsafe_load(offsets_ptr, i + 2)
            out[i + 1] = child_data[(Int(lo) + 1):Int(hi)]
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
