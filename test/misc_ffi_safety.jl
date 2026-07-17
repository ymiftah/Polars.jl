# Regression tests for the c-polars hardening pass (see plans/c_polars_hardening.md).
# Several of these exercise paths that previously invoked undefined behaviour or aborted the whole
# process rather than raising a catchable Julia error -- so "the test process is still alive" is
# itself part of what is being asserted.

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
