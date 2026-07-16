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
end

@testset "Binary DataFrame round-trip through parquet" begin
    # Create a DataFrame with binary column
    df = DataFrame((;
        id = [1, 2, 3],
        data = Union{Vector{UInt8}, Missing}[
            UInt8[0x48, 0x65, 0x6c, 0x6c, 0x6f],  # "Hello"
            missing,
            UInt8[0x57, 0x6f, 0x72, 0x6c, 0x64],  # "World"
        ],
    ))

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
    @test eltype(collect(s)) == Union{Missing, Vector{UInt8}}
end
