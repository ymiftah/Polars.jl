# FFI safety tests for the c-polars hardening pass (see plans/c_polars_hardening.md).
# Several of these exercise paths where a slip invokes undefined behaviour or aborts the whole
# process rather than raising a catchable Julia error -- so "the test process is still alive" is
# itself part of what is being asserted.

using TimeZones

@testset "empty expr list / null pointer into read_exprs (P0.3)" begin
    # `slice::from_raw_parts` requires a non-null aligned pointer even for len 0, and the Julia
    # side may pass null/dangling for an empty list -- constructing the slice regardless is UB,
    # so this must come back as a plain error return from polars itself, with the process intact.
    out = Ref{Ptr{Polars.polars_expr_t}}()
    err = Polars.API.polars_expr_sum_horizontal(Ptr{Ptr{Polars.polars_expr_t}}(C_NULL), 0, true, out)
    @test err != C_NULL # polars rejects an empty horizontal fold -- but does not crash

    err = Polars.API.polars_expr_all_horizontal(Ptr{Ptr{Polars.polars_expr_t}}(C_NULL), 0, out)
    @test err != C_NULL

    # read_names with n == 0 is a legitimate no-op, not an error
    df = DataFrame((; x = [1, 2, 3]))
    @test size(Polars.collect(Polars.drop(lazy(df), String[]))) == (3, 1)
end

@testset "unencodable cast returns an error, not a silent Unknown cast (P1.1)" begin
    # `to_dtype` must reject the dtypes it can't encode (Datetime/Duration/List/Struct) rather than
    # mapping them to `Unknown(UnknownKind::Any)`, which would turn `cast(col, Datetime)` into a
    # silent cast-to-unknown. Drive the C ABI directly: Julia's own `cast` whitelist would reject
    # these before they ever reach Rust.
    e = col("x")
    out = Ref{Ptr{Polars.polars_expr_t}}()

    for code in (
            Polars.API.PolarsValueTypeDatetime,
            Polars.API.PolarsValueTypeDuration,
            Polars.API.PolarsValueTypeList,
            Polars.API.PolarsValueTypeStruct,
            Polars.API.PolarsValueTypeUnknown,
        )
        err = Polars.API.polars_expr_cast(e, code, out)
        @test err != C_NULL
        Polars.API.polars_error_destroy(err)
    end

    # the arms that *are* encodable still work
    for code in (
            Polars.API.PolarsValueTypeInt64,
            Polars.API.PolarsValueTypeFloat64,
            Polars.API.PolarsValueTypeString,
            Polars.API.PolarsValueTypeBinary,
            Polars.API.PolarsValueTypeDate,
            Polars.API.PolarsValueTypeTime,
        )
        err = Polars.API.polars_expr_cast(e, code, out)
        @test err == C_NULL
        Polars.Expr(out[]) # roots the new handle for finalization
    end
end

@testset "invalid UTF-8 raises rather than corrupting (P0.5/P1.7)" begin
    bad = String(UInt8[0xff, 0xfe]) # not valid UTF-8
    df = DataFrame((; s = [(a = 1, b = 2)]))

    # struct_rename_fields must validate UTF-8; `from_utf8_unchecked` is UB on invalid input
    @test_throws Exception select(df, col("s") |> Structs.rename_fields([bad, "z"]))
    # struct_field_by_name must not answer with a null handle, which Julia would wrap and finalize
    @test_throws Exception select(df, col("s") |> Structs.field_by_name(bad))
end

@testset "row index offset does not wrap (P1.5)" begin
    df = DataFrame((; x = [1, 2, 3]))
    # the offset must be range-checked: an unguarded `offset as IdxSize` wraps a negative i64
    # into a huge u32
    @test_throws Exception Polars.collect(with_row_index(lazy(df), "idx"; offset = -1))

    r = Polars.collect(with_row_index(lazy(df), "idx"; offset = 10))
    @test collect(r[:idx]) == [10, 11, 12]
end

@testset "values larger than one callback chunk are not truncated (P1.6)" begin
    # `Write::write` may report a short count and silently drop the tail. Must be `write_all`.
    big = "x"^(1024 * 1024)
    @test collect(DataFrame((; s = [big]))[:s])[1] == big

    bin = rand(UInt8, 1024 * 1024)
    @test collect(DataFrame((; b = [bin]))[:b])[1] == bin
end

@testset "non-ASCII strings cross the FFI boundary intact" begin
    # The ABI wants a byte length, so every string argument travels as `ncodeunits(s)`; a
    # `length(s)` character count truncates any non-ASCII argument mid-string.
    df = DataFrame((; s = [(café = 1, ω = 2)]))
    renamed = select(df, col("s") |> Structs.rename_fields(["日本語", "naïve"]))
    @test collect(renamed[:s])[1] == (; 日本語 = 1, naïve = 2)

    @test collect(select(df, col("s") |> Structs.field_by_name("café"))[:café]) == [1]

    # value_counts' `name` argument travels the same (ptr, len) path; it names the count field of
    # the resulting struct rather than the column itself
    d = DataFrame((; x = [1, 1, 2]))
    vc = select(d, Polars.value_counts(col("x"); name = "número"))
    @test :número in keys(collect(vc[:x])[1])

    # col/alias/lit(::String) are the highest-traffic (ptr, len) sites of all
    caf = DataFrame((; café = [1, 2]))
    @test collect(select(caf, col("café"))[:café]) == [1, 2]
    @test collect(select(caf, col("café") |> alias("naïve"))[:naïve]) == [1, 2]
    @test collect(select(caf, col("café"), lit("ω") |> alias("l"))[:l]) == ["ω", "ω"]
    @test collect(select(caf, col("café") |> Polars.prefix("π_"))[:π_café]) == [1, 2]
end

@testset "non-ASCII file paths" begin
    df = DataFrame((; x = [1, 2, 3]))
    mktempdir() do dir
        p = joinpath(dir, "données_café.parquet")
        write_parquet(p, df)
        @test collect(Polars.collect(scan_parquet(p))[:x]) == [1, 2, 3]

        c = joinpath(dir, "données_café.csv")
        write_csv(c, df)
        @test collect(Polars.collect(scan_csv(c))[:x]) == [1, 2, 3]
    end
end

@testset "tail/rename are reachable unqualified (Julia-side P0.1)" begin
    # Both names are unexported Base bindings (`Base.tail`/`Base.rename`). Extending them without
    # a local binding to `export` would leave plain `tail(df, n)`/`rename(df, ...)` raising
    # `UndefVarError` even though the `Base.`-qualified call works.
    df = DataFrame((; x = [1, 2, 3, 4, 5]))
    @test collect(tail(df, 2)[:x]) == [4, 5]
    @test Tables.columnnames(rename(df, ["x"], ["y"])) == (:y,)
end

@testset "String/binary/list write path uses 64-bit offsets (Julia-side P0.7)" begin
    # `format(String)`/`format(Vector{UInt8})`/list columns declare the large-offset Arrow formats
    # ("U"/"Z"/"+L") and build `Int64` offset buffers to match. The 32-bit-offset formats
    # ("u"/"z"/"+l") would cap a column's total byte length (or, for lists, total flattened element
    # count) at 2^31/2^32, past which `cumsum!` silently wraps and corrupts every later offset.
    # This doesn't fabricate multi-GB data (impractical for a test) -- it locks in the format
    # constants themselves and exercises the actual round trip through polars.
    @test Polars.format(String) == "U"
    @test Polars.format(Vector{UInt8}) == "Z"
    @test Polars.format(Vector{Int}) == "+L"
    @test Polars.format(Vector{Vector{Int}}) == "+L"

    df = DataFrame((; s = ["hello", "café", missing], x = [[1, 2, 3], [4], Int[]]))
    @test isequal(collect(df[:s]), ["hello", "café", missing])
    @test collect(df[:x])[1] == [1, 2, 3]

    mktempdir() do dir
        p = joinpath(dir, "t.parquet")
        write_parquet(p, df)
        r = read_parquet(p)
        @test isequal(collect(r[:s]), ["hello", "café", missing])
        @test collect(r[:x])[1] == [1, 2, 3]
    end
end

@testset "fixed-size-list schema: valid single-child schema resolves; a malformed one raises a clear error, not a TypeError (Julia-side P0.2)" begin
    # `Lists.to_array`/`concat_arr` (see test/datatypes/lists.jl, test/expr/horizontal.jl) already
    # exercise `parse_format`'s "+w:N" arm end-to-end against a real polars-produced schema. This
    # testset instead drives `parse_format` directly against a hand-built schema, to cover the
    # malformed-input guard (`n_children != 1`) that a real polars schema should never actually
    # trigger -- a slip there must reach its own clear "malformed Arrow FixedSizeList schema"
    # message rather than dying earlier in a `TypeError` (asserting on a bare `Int64` `n_children`
    # field, say, instead of a comparison against it) or an out-of-bounds pointer read.
    child = Polars.ArrowSchema(; format = "i", name = "item")

    # well-formed: exactly one child resolves to Vector{T}, same as the List arm just above it
    sch_ok = Polars.ArrowSchema(; format = "+w:4", name = "col", children = [child])
    csch_ok = unsafe_load(Base.unsafe_convert(Ptr{Polars.API.ArrowSchema}, sch_ok))
    @test Polars.parse_format(csch_ok) == Polars.MaybeMissing{Vector{Polars.MaybeMissing{Int32}}}

    # malformed: zero children
    sch_bad = Polars.ArrowSchema(; format = "+w:4", name = "col", children = Polars.ArrowSchema[])
    csch_bad = unsafe_load(Base.unsafe_convert(Ptr{Polars.API.ArrowSchema}, sch_bad))
    @test_throws Exception Polars.parse_format(csch_bad)
    try
        Polars.parse_format(csch_bad)
    catch e
        @test !(e isa TypeError)
    end
end

@testset "GC stress: Value accessors survive interleaved GC" begin
    # The `Value` ccalls (polars_value_duration_get/datetime_get/date_get/time_get) pass `value`
    # itself, not the raw `value.ptr`, so the `unsafe_convert`-based rooting keeps the wrapper (and
    # the Rust-owned pointee) alive for the ccall's duration. Passing the bare pointer instead
    # would let a GC running on another thread mid-ccall finalize (and destroy) the `Value` while
    # Rust is still using it. That race can't be reproduced deterministically (it needs an unlucky
    # concurrent GC), but repeatedly materializing every affected accessor with a `GC.gc()` forced
    # in between at least exercises those call sites under GC pressure.
    #
    # The companion guarantee -- the Series constructor destroying its owned pointer when
    # `parse_format` throws on an unsupported dtype (`src/series.jl`) -- has no independent test
    # here: there's no way to construct a genuinely *malformed*-schema `Series` (as opposed to one
    # with a merely-unsupported dtype, e.g. Decimal) through this package's public API (see the
    # fixed-size-list testset above, which drives that case directly against a hand-built schema
    # instead), so the only assertion available is that ordinary construction installs a working
    # finalizer, which the rest of this suite
    # already exercises continuously.
    df = DataFrame(
        (;
            dt = [DateTime(2024, 1, 1) + Dates.Day(i) for i in 1:50],
            dt2 = [DateTime(2024, 1, 1) for _ in 1:50],
            d = [Date(2024, 1, 1) + Dates.Day(i) for i in 1:50],
            t = [Dates.Time(0, 0, 0) + Dates.Second(i) for i in 1:50],
        )
    )
    # Duration columns have no write-side arrow support (see test/datatypes/series.jl) -- derive
    # one from datetime subtraction instead, same as that file does.
    dur = select(df, (col("dt") - col("dt2")) |> alias("dur"))[:dur]
    for i in 1:50
        v = df[:dt][i]
        GC.gc()
        @test v isa DateTime

        v = df[:d][i]
        GC.gc()
        @test v isa Date

        v = df[:t][i]
        GC.gc()
        @test v isa Dates.Time

        v = dur[i]
        GC.gc()
        @test v isa Dates.Nanosecond
    end
end

@testset "GC stress: tz-aware Value accessor survives interleaved GC (P1 fix, PolarsTimeZonesExt)" begin
    # Same rationale as above, for the extension's `load_value(::Value{ZonedDateTime})` method,
    # which also fixed a cross-statement borrow: `polars_value_time_zone` returns a pointer into
    # `value`'s Rust-owned memory, and the subsequent `unsafe_string` call (itself a GC point) used
    # to read through it outside of any `GC.@preserve`.
    df = DataFrame((; t = [DateTime(2024, 6, 15, 12, 0, 0) + Dates.Hour(i) for i in 1:50]))
    utc = select(df, alias(Dt.replace_time_zone(col("t"), "UTC"), "t"))
    for i in 1:50
        v = utc[:t][i]
        GC.gc()
        @test v isa ZonedDateTime
    end
end

# `@cfunction` needs a name resolvable at top level, so this release callback -- a no-op, only
# present to satisfy `ArrowArray`'s release-pointer field contract and never actually invoked
# below -- must live outside the `@testset`'s local scope rather than as a closure.
_noop_release_offset_carray(::Ptr{Polars.API.ArrowArray}) = nothing

@testset "_read_offset: classic Utf8/LargeUtf8 bulk reader (Julia-side P1.2)" begin
    # polars itself only ever exports the view formats ("vu"/"vz"), which `_read_view` handles
    # and the "string/binary" testset in datatypes/series.jl exercises live -- `_read_offset`
    # (classic Utf8/LargeUtf8/Binary/LargeBinary, Int32/Int64 offset buffers) is unreachable
    # through the normal polars-backed API, so it's driven directly here against a hand-built
    # `ArrowArray` to confirm the offset arithmetic itself is correct.
    noop_ptr = @cfunction(_noop_release_offset_carray, Cvoid, (Ptr{Polars.API.ArrowArray},))

    function make_offset_carray(::Type{OffT}, strs::Vector{Union{String, Missing}}) where {OffT}
        n = length(strs)
        nc = count(ismissing, strs)
        validity = zeros(UInt8, cld(n, 8))
        for i in 0:(n - 1)
            ismissing(strs[i + 1]) || (validity[1 + i ÷ 8] |= UInt8(1) << (i % 8))
        end
        lens = [ismissing(s) ? 0 : sizeof(s) for s in strs]
        offsets = Vector{OffT}(undef, n + 1)
        offsets[1] = 0
        cumsum!(@view(offsets[2:end]), lens)
        data = reduce(vcat, (codeunits(s) for s in strs if !ismissing(s)); init = UInt8[])
        bufptrs = Ptr{Cvoid}[nc > 0 ? pointer(validity) : C_NULL, pointer(offsets), pointer(data)]
        ca = Polars.API.ArrowArray(n, nc, 0, 3, 0, pointer(bufptrs), C_NULL, C_NULL, noop_ptr, C_NULL)
        return ca, (validity, offsets, data, bufptrs) # keep the backing arrays alive
    end

    strs = Union{String, Missing}["hi", missing, "café", "", "x"^30]
    for OffT in (Int32, Int64)
        ca, keepalive = make_offset_carray(OffT, strs)
        GC.@preserve keepalive begin
            h = Polars.ExportedArray(ca)
            ca2, bufs = Polars._buffers(h)
            result = Polars._read_offset(String, OffT, ca2, bufs)
            @test isequal(result, strs)
        end
    end
end

@testset "producer release callback marks release=NULL, recurses through children (Arrow C Data Interface conformance)" begin
    # Per the spec, a producer's release callback MUST walk all children invoking their own
    # release callback, and MUST mark the released structure's `release` member NULL. Build a
    # 2-level ArrowSchema/ArrowArray tree directly (bypassing `arrowtable`, which would also root
    # them -- irrelevant to what's being tested here), invoke the top-level release callback as
    # Rust would, and confirm both effects on both levels.
    child_schema = Polars.ArrowSchema(; format = "i", name = "child")
    parent_schema = Polars.ArrowSchema(; format = "+s", name = "parent", children = [child_schema])
    parent_schema_ptr = Base.unsafe_convert(Ptr{Polars.API.ArrowSchema}, parent_schema)
    child_schema_ptr = Base.unsafe_convert(Ptr{Polars.API.ArrowSchema}, child_schema)
    @test unsafe_load(parent_schema_ptr).release != C_NULL
    @test unsafe_load(child_schema_ptr).release != C_NULL
    release = unsafe_load(parent_schema_ptr).release
    ccall(release, Cvoid, (Ptr{Polars.API.ArrowSchema},), parent_schema_ptr)
    @test unsafe_load(parent_schema_ptr).release == C_NULL
    @test unsafe_load(child_schema_ptr).release == C_NULL
    # a consumer trying to release an already-released structure gets a catchable error, not a
    # segfault from invoking a dangling function pointer (Arrow C Data Interface conformance: SHOULD
    # check for a released structure).
    @test_throws ErrorException Polars._release_or_throw(unsafe_load(parent_schema_ptr).release, parent_schema_ptr)

    child_array = Polars.ArrowArray(Polars.ValidityMap(3, 0, UInt8[]), [Int64[1, 2, 3]])
    parent_array = Polars.ArrowArray(Polars.ValidityMap(3, 0, UInt8[]), [], [child_array])
    parent_array_ptr = Base.unsafe_convert(Ptr{Polars.API.ArrowArray}, parent_array)
    child_array_ptr = Base.unsafe_convert(Ptr{Polars.API.ArrowArray}, child_array)
    @test unsafe_load(parent_array_ptr).release != C_NULL
    @test unsafe_load(child_array_ptr).release != C_NULL
    release = unsafe_load(parent_array_ptr).release
    ccall(release, Cvoid, (Ptr{Polars.API.ArrowArray},), parent_array_ptr)
    @test unsafe_load(parent_array_ptr).release == C_NULL
    @test unsafe_load(child_array_ptr).release == C_NULL
    @test_throws ErrorException Polars._release_or_throw(unsafe_load(parent_array_ptr).release, parent_array_ptr)
end

@testset "ArrowSchema metadata: spec-conformant binary encoding, not a C string (D5 conformance)" begin
    # the Arrow C Data Interface's metadata field is a length-prefixed binary blob (int32 pair
    # count, then per-pair int32 key length + key bytes + int32 value length + value bytes) --
    # not a NUL-terminated C string. A plain string is rejected outright rather than silently
    # emitting the wrong encoding.
    @test_throws ErrorException Polars.ArrowSchema(; format = "i", name = "x", metadata = "oops")

    schema = Polars.ArrowSchema(; format = "i", name = "x", metadata = ["a" => "1", "bb" => "22"])
    io = IOBuffer(schema.metadata)
    n = read(io, Int32)
    @test n == 2
    decoded = Pair{String, String}[]
    for _ in 1:n
        klen = read(io, Int32)
        k = String(read(io, klen))
        vlen = read(io, Int32)
        v = String(read(io, vlen))
        push!(decoded, k => v)
    end
    @test decoded == ["a" => "1", "bb" => "22"]

    # end-to-end: a top-level "+s" schema carrying non-empty metadata is accepted by
    # `polars_dataframe_new_from_carrow` without erroring, and the resulting DataFrame is correct.
    col_schema = Polars.column_schema(:x, Int64)
    top_schema = Polars.ArrowSchema(;
        format = "+s", name = "polars.dataframe", metadata = ["k" => "v"], children = [col_schema],
    )
    array = Polars.ArrowArray(
        Polars.ValidityMap(3, 0, UInt8[]), [], [Polars.arrowvector(Int64[1, 2, 3])],
    )
    Polars.root!(top_schema)
    Polars.root!(array)
    out = Ref{Ptr{Polars.API.polars_dataframe_t}}()
    df = try
        err = Polars.API.polars_dataframe_new_from_carrow(top_schema, array, out)
        Polars.polars_error(err)
        Polars.DataFrame(out[])
    catch
        # Mirror `DataFrame(table)`'s own failure handling: without this, a throw here would
        # strand `array` in `LIVE_ARRAYS` for the rest of the session and break the unrelated
        # `isempty(LIVE_ARRAYS)` assertions in test/dataframe/gc.jl.
        Polars.release_array!(array)
        rethrow()
    finally
        Polars.release_schema!(top_schema)
    end
    @test size(df) == (3, 1)
    @test collect(df[:x]) == [1, 2, 3]
end

@testset "_name_ptrs hands back the vector its pointers point into" begin
    # The pointers in `ptrs` are raw interior pointers into `owned`'s strings. Nothing else
    # references `owned` when the input isn't already a `Vector{String}` (it is built right here),
    # so returning it is what lets every caller root the *right* object in its `GC.@preserve`.
    # Preserving only the caller's own argument would leave the pointers dangling for a
    # `Vector{Symbol}`, with each call site's `Ref` allocation sitting between the conversion and
    # the ccall as a live GC safepoint.
    strs = ["alpha", "beta"]
    owned, ptrs, lens = Polars._name_ptrs(strs)
    @test owned === strs # already-owned input is passed straight through, not copied
    @test ptrs == Ptr{UInt8}[pointer(s) for s in strs]
    @test lens == Csize_t[5, 4]

    syms = [:alpha, :beta]
    owned_syms, ptrs_syms, lens_syms = Polars._name_ptrs(syms)
    @test owned_syms isa Vector{String}
    @test owned_syms == ["alpha", "beta"]
    # the load-bearing assertion: the pointers address `owned_syms`, not some temporary
    @test ptrs_syms == Ptr{UInt8}[pointer(s) for s in owned_syms]
    @test lens_syms == Csize_t[5, 4]

    # non-ASCII names are measured in bytes (ncodeunits), not characters
    owned_utf8, _, lens_utf8 = Polars._name_ptrs([:é, Symbol("日本")])
    @test owned_utf8 == ["é", "日本"]
    @test lens_utf8 == Csize_t[2, 6]

    # empty input is a valid no-op, not an error
    owned_empty, ptrs_empty, lens_empty = Polars._name_ptrs(Symbol[])
    @test owned_empty == String[]
    @test isempty(ptrs_empty)
    @test isempty(lens_empty)
end

@testset "Symbol column names survive a GC between marshalling and the ccall" begin
    # Every verb below takes a `Vector{<:ColId}` and marshals it through `_name_ptrs`. With a
    # `Vector{Symbol}` that conversion allocates, and only the `GC.@preserve` around the ccall
    # keeps the converted strings from being reclaimed before polars reads them -- reclaiming them
    # is a use-after-free that surfaces as garbage column names or a crash, nondeterministically.
    # Forcing a full GC on each iteration makes the window as hostile as it can be made from Julia.
    df = DataFrame((; a = [1, 2, 3], b = ["x", "y", "z"], c = [1.5, 2.5, 3.5]))
    lists = DataFrame((; g = ["p", "q"], l = [[1, 2], [3]]))
    wide = DataFrame((; id = [1, 2], m = [10, 20], n = [30, 40]))

    for _ in 1:25
        GC.gc(true)

        @test names(drop(df, [:b])) == ["a", "c"]
        @test names(Base.rename(df, [:a], [:renamed])) == ["renamed", "b", "c"]
        @test size(Base.unique(df, [:a])) == (3, 3)
        @test size(drop_nulls(df, [:a])) == (3, 3)
        @test names(transpose(df; new_col_names = [:r1, :r2, :r3])) == ["r1", "r2", "r3"]

        @test size(explode(lists, [:l])) == (3, 2)
        long = unpivot(wide, [:id]; on = [:m, :n])
        @test size(long) == (4, 3)

        # selector/struct paths marshal names through the same helper
        @test sort(names(select(df, Selectors.by_name("a", "c")))) == ["a", "c"]
    end
end
