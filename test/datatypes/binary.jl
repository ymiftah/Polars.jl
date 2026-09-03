@testset "Binary (Vector{UInt8}) type" begin
    bytes_data = Vector{UInt8}[UInt8[1, 2, 3], UInt8[4, 5], UInt8[]]
    s = Series(:bytes, bytes_data)
    @test collect(s)[1] == UInt8[1, 2, 3]
    @test collect(s)[2] == UInt8[4, 5]
    @test collect(s)[3] == UInt8[]
end

@testset "Binary data with nulls" begin
    bytes_data = Union{Vector{UInt8}, Missing}[
        UInt8[1, 2, 3],
        missing,
        UInt8[255, 254],
    ]
    s = Series(:binary_col, bytes_data)
    values = collect(s)
    @test values[1] == UInt8[1, 2, 3]
    @test ismissing(values[2])
    @test values[3] == UInt8[255, 254]

    # `eltype(s)` must include `Missing` whenever the series actually has nulls, or the
    # `AbstractVector` eltype contract is violated: indexing a null slot returns `missing`, which
    # a bare `Vector{UInt8}` eltype wouldn't cover.
    @test eltype(s) == Union{Missing, Vector{UInt8}}
    @test ismissing(s[2])

    no_nulls = Series(:binary_col2, Vector{UInt8}[UInt8[1, 2], UInt8[3]])
    @test eltype(no_nulls) == Vector{UInt8}
end

@testset "Binary DataFrame round-trip through parquet" begin
    df = DataFrame(
        (;
            id = [1, 2, 3],
            data = Union{Vector{UInt8}, Missing}[
                UInt8[0x48, 0x65, 0x6c, 0x6c, 0x6f],  # "Hello"
                missing,
                UInt8[0x57, 0x6f, 0x72, 0x6c, 0x64],  # "World"
            ],
        )
    )

    temp_file = mktempdir() * "/binary_test.parquet"
    write_parquet(temp_file, df)

    df_read = read_parquet(temp_file)
    @test size(df_read) == size(df)
    @test Polars.name(df_read[:id]) == "id"
    @test Polars.name(df_read[:data]) == "data"

    data_read = collect(df_read[:data])
    @test data_read[1] == UInt8[0x48, 0x65, 0x6c, 0x6c, 0x6f]
    @test ismissing(data_read[2])
    @test data_read[3] == UInt8[0x57, 0x6f, 0x72, 0x6c, 0x64]
end

@testset "Binary literal comparison and String<->Binary cast (py-polars test_binary_filter, test_string_to_binary)" begin
    # a bare `Vector{UInt8}` passed to `lit` is ambiguous with a numeric array literal (one row
    # per byte), so it does NOT produce a single-row Binary scalar -- wrapping it in a one-element
    # `Series` first is the correct idiom for a Binary literal, matching how a Binary *column* is
    # itself built from a `Vector{Vector{UInt8}}` (one `Vector{UInt8}` per row)
    df = DataFrame(
        (;
            name = ["a", "b", "c", "d"],
            content = Vector{UInt8}[
                UInt8[0x61, 0x61], UInt8[0x61, 0x61, 0x61, 0x62, 0x62, 0x62],
                UInt8[0x61, 0x61], UInt8[0xc6, 0x69, 0xea],
            ],
        )
    )
    target = Series(:_, [UInt8[0xc6, 0x69, 0xea]])
    r = filter(df, col("content") == target)
    @test collect(r[:name]) == ["d"]

    # String -> Binary -> String round-trips, including an empty string, `missing`, and a
    # non-ASCII-unsafe multi-byte value
    s = Union{String, Missing}["", missing, "\x01\x02"]
    df2 = DataFrame((; data = s))
    to_binary = select(df2, cast(col("data"), Vector{UInt8}) |> alias("b"))
    @test isequal(collect(to_binary[:b]), Union{Missing, Vector{UInt8}}[UInt8[], missing, UInt8[0x01, 0x02]])
    back_to_string = select(to_binary, cast(col("b"), String) |> alias("s"))
    @test isequal(collect(back_to_string[:s]), s)
end

@testset "Empty binary Series" begin
    empty_bytes = Vector{UInt8}[]
    s = Series(:empty_binary, empty_bytes)
    @test size(s) == (0,)
    @test eltype(s) == Vector{UInt8}
    # `collect(s)`'s eltype matches `eltype(s)` itself -- no `Missing`, since an empty column has
    # trivially zero nulls. The bulk binary reader returns a concretely-typed `T[]` for the n == 0
    # case, same as the numeric bulk path, so no spurious `Missing` leaks in from an
    # empty-comprehension's inferred element type.
    @test eltype(collect(s)) == Vector{UInt8}
end
