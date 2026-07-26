@testset "Binary (Vector{UInt8}) type" begin
    # Test construction of a Series with binary data
    bytes_data = Vector{UInt8}[UInt8[1, 2, 3], UInt8[4, 5], UInt8[]]
    s = Series(:bytes, bytes_data)
    @test collect(s)[1] == UInt8[1, 2, 3]
    @test collect(s)[2] == UInt8[4, 5]
    @test collect(s)[3] == UInt8[]
end

@testset "Binary data with nulls" begin
    # Test Vector{UInt8} with missing values
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

    # `eltype(s)` must include `Missing` whenever the series actually has nulls -- it used to be
    # bare `Vector{UInt8}` regardless of null count, violating the `AbstractVector` eltype
    # contract (indexing a null slot returns `missing`, which then doesn't match `eltype`).
    @test eltype(s) == Union{Missing, Vector{UInt8}}
    @test ismissing(s[2])

    no_nulls = Series(:binary_col2, Vector{UInt8}[UInt8[1, 2], UInt8[3]])
    @test eltype(no_nulls) == Vector{UInt8}
end

@testset "Binary DataFrame round-trip through parquet" begin
    # Create a DataFrame with binary column
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

    # Write to temporary parquet file
    temp_file = mktempdir() * "/binary_test.parquet"
    write_parquet(temp_file, df)

    # Read back and verify
    df_read = read_parquet(temp_file)
    @test size(df_read) == size(df)
    @test Polars.name(df_read[:id]) == "id"
    @test Polars.name(df_read[:data]) == "data"

    # Verify the binary data matches
    data_read = collect(df_read[:data])
    @test data_read[1] == UInt8[0x48, 0x65, 0x6c, 0x6c, 0x6f]
    @test ismissing(data_read[2])
    @test data_read[3] == UInt8[0x57, 0x6f, 0x72, 0x6c, 0x64]
end

@testset "Empty binary Series" begin
    # Test empty binary column
    empty_bytes = Vector{UInt8}[]
    s = Series(:empty_binary, empty_bytes)
    @test size(s) == (0,)
    @test eltype(s) == Vector{UInt8}
    # `collect(s)`'s eltype matches `eltype(s)` itself (no `Missing` -- an empty column has
    # trivially zero nulls) now that P1.2's bulk binary reader returns a concretely-typed `T[]`
    # for the n==0 case, same as the numeric bulk path always has. This used to assert
    # `Union{Missing, Vector{UInt8}}` instead, which was never anything but an accident of the
    # old per-element fallback's empty-comprehension type-inference quirk -- it didn't match
    # `eltype(s)` and no other empty-series test in this suite expects a spurious `Missing`.
    @test eltype(collect(s)) == Vector{UInt8}
end
