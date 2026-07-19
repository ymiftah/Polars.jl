# Regression tests for the c-polars hardening pass (see plans/c_polars_hardening.md).
# Several of these exercise paths that previously invoked undefined behaviour or aborted the whole
# process rather than raising a catchable Julia error -- so "the test process is still alive" is
# itself part of what is being asserted.

using TimeZones

@testset "empty expr list / null pointer into read_exprs (P0.3)" begin
    # `slice::from_raw_parts` requires a non-null aligned pointer even for len 0, and the Julia
    # side may pass null/dangling for an empty list. Pre-fix this was UB; it must now be a plain
    # error return from polars itself, with the process intact.
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
    # `to_dtype` used to map Datetime/Duration/List/Struct to `Unknown(UnknownKind::Any)`, so
    # `cast(col, Datetime)` silently became a cast-to-unknown. Drive the C ABI directly: Julia's
    # own `cast` whitelist would reject these before they ever reach Rust.
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

    # struct_rename_fields used from_utf8_unchecked -> UB on invalid input
    @test_throws Exception select(df, col("s") |> Structs.rename_fields([bad, "z"]))
    # struct_field_by_name returned a null handle, which Julia then wrapped and finalized
    @test_throws Exception select(df, col("s") |> Structs.field_by_name(bad))
end

@testset "row index offset does not wrap (P1.5)" begin
    df = DataFrame((; x = [1, 2, 3]))
    # `offset as IdxSize` silently wrapped a negative i64 into a huge u32
    @test_throws Exception Polars.collect(with_row_index(lazy(df), "idx"; offset = -1))

    r = Polars.collect(with_row_index(lazy(df), "idx"; offset = 10))
    @test collect(r[:idx]) == [10, 11, 12]
end

@testset "values larger than one callback chunk are not truncated (P1.6)" begin
    # `Write::write` may report a short count; the tail was silently dropped. Must be `write_all`.
    big = "x"^(1024 * 1024)
    @test collect(DataFrame((; s = [big]))[:s])[1] == big

    bin = rand(UInt8, 1024 * 1024)
    @test collect(DataFrame((; b = [bin]))[:b])[1] == bin
end

@testset "non-ASCII strings cross the FFI boundary intact" begin
    # The Julia side passed `length(s)` (character count) where the ABI wants a byte length, so
    # any non-ASCII argument was truncated mid-string.
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
    # Both used to extend an unexported Base binding (Base.tail/Base.rename) with no local
    # binding to `export`, so plain `tail(df, n)`/`rename(df, ...)` raised UndefVarError even
    # though `Base.tail(df, n)` worked.
    df = DataFrame((; x = [1, 2, 3, 4, 5]))
    @test collect(tail(df, 2)[:x]) == [4, 5]
    @test Tables.columnnames(rename(df, ["x"], ["y"])) == (:y,)
end

@testset "String/binary/list write path uses 64-bit offsets (Julia-side P0.7)" begin
    # `format(String)`/`format(Vector{UInt8})`/list columns used to declare the 32-bit-offset
    # Arrow formats ("u"/"z"/"+l") while building `UInt32`/`Int32` offset buffers -- a column
    # whose total byte length (or, for lists, total flattened element count) crosses 2^31/2^32
    # would silently wrap `cumsum!` and corrupt every offset past that point. Switched to the
    # large-offset formats ("U"/"Z"/"+L") with `Int64` offsets, which have no such practical
    # limit. This doesn't fabricate multi-GB data (impractical for a test) -- it locks in the
    # format constants themselves and exercises the actual round trip through polars.
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

@testset "fixed-size-list schema raises a clear error, not a TypeError (Julia-side P0.2)" begin
    # `@assert schema.n_children` (an Int64) instead of `@assert schema.n_children == 1` blew up
    # with a TypeError before ever reaching the "not supported" message. There's no way to
    # construct an Array-dtype column through this package's own API (only reachable by scanning
    # a file written by another Arrow implementation), so drive `parse_format` directly against a
    # hand-built schema.
    child = Polars.ArrowSchema(; format = "i", name = "item")
    sch = Polars.ArrowSchema(; format = "+w4", name = "col", children = [child])
    csch = unsafe_load(Base.unsafe_convert(Ptr{Polars.API.ArrowSchema}, sch))
    @test_throws Exception Polars.parse_format(csch)
    try
        Polars.parse_format(csch)
    catch e
        @test !(e isa TypeError)
    end
end

@testset "GC stress: Value accessors survive interleaved GC (P1 GC use-after-free fix)" begin
    # `Value` ccalls (polars_value_duration_get/datetime_get/date_get/time_get) used to pass the
    # raw `value.ptr` instead of `value` itself, bypassing the `unsafe_convert`-based rooting that
    # keeps the wrapper (and the Rust-owned pointee) alive for the ccall's duration -- a GC
    # running on another thread mid-ccall could finalize (and destroy) the `Value` while Rust was
    # still using it. This doesn't deterministically reproduce that race (it needs an unlucky
    # concurrent GC), but repeatedly materializing every accessor affected by the fix with a
    # `GC.gc()` forced in between at least exercises the fixed call sites under GC pressure.
    #
    # The companion fix -- the Series constructor leaking its owned pointer when `parse_format`
    # throws on an unsupported dtype (`src/series.jl`) -- has no independent regression test here:
    # there's no way to construct a genuinely unsupported-dtype `Series` through this package's
    # public API (see the fixed-size-list testset above), so the only assertion available for that
    # fix is that ordinary construction still installs a working finalizer, which the rest of this
    # suite already exercises continuously.
    df = DataFrame((;
        dt = [DateTime(2024, 1, 1) + Dates.Day(i) for i in 1:50],
        dt2 = [DateTime(2024, 1, 1) for _ in 1:50],
        d = [Date(2024, 1, 1) + Dates.Day(i) for i in 1:50],
        t = [Dates.Time(0, 0, 0) + Dates.Second(i) for i in 1:50],
    ))
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

@testset "_read_offset: classic Utf8/LargeUtf8 bulk reader (Julia-side P1.2)" begin
    # polars itself only ever exports the view formats ("vu"/"vz"), which `_read_view` handles
    # and the "string/binary" testset in datatypes/series.jl exercises live -- `_read_offset`
    # (classic Utf8/LargeUtf8/Binary/LargeBinary, Int32/Int64 offset buffers) is unreachable
    # through the normal polars-backed API, so it's driven directly here against a hand-built
    # `ArrowArray` to confirm the offset arithmetic itself is correct.
    noop_release(::Ptr{Polars.API.ArrowArray}) = nothing
    # `@cfunction` normally needs a name resolvable at top level; `$noop_release` (interpolating
    # the function *value*) uses the runtime closure-cfunction form instead, since this local
    # function is only defined inside the enclosing `@testset`'s local scope. That form returns a
    # GC-tracked `Base.CFunction` box (not a raw `Ptr{Cvoid}`), so it must be explicitly converted
    # and kept alive as long as the C struct holding its address might be invoked.
    noop_box = @cfunction($noop_release, Cvoid, (Ptr{Polars.API.ArrowArray},))
    noop_ptr = Base.unsafe_convert(Ptr{Cvoid}, noop_box)

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
        GC.@preserve keepalive noop_box begin
            h = Polars.ExportedArray(ca)
            result = Polars._read_offset(String, OffT, h)
            @test isequal(result, strs)
        end
    end
end
