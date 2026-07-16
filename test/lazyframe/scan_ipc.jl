@testset "scan_ipc / read_ipc / write_ipc basic" begin
    # Create a test DataFrame
    df = DataFrame((;
        id = [1, 2, 3, 4, 5],
        name = ["alice", "bob", "charlie", "diana", "eve"],
        value = [10.5, 20.0, 30.5, 40.0, 50.5],
    ))

    # Write to temporary IPC file
    temp_file = mktempdir() * "/test.ipc"
    write_ipc(temp_file, df)

    # Read back via read_ipc (eager)
    df_read = read_ipc(temp_file)
    @test size(df_read) == size(df)
    @test Tables.columnnames(df_read) == Tables.columnnames(df)
    @test df_read[:id] == df[:id]
    @test df_read[:name] == df[:name]
    @test df_read[:value] == df[:value]

    # Read back via scan_ipc + collect (lazy)
    df_scanned = scan_ipc(temp_file) |> collect
    @test size(df_scanned) == size(df)
    @test isequal(df_scanned[:id], df_read[:id])
    @test isequal(df_scanned[:name], df_read[:name])
    @test isequal(df_scanned[:value], df_read[:value])
end

@testset "scan_ipc with n_rows option" begin
    # Create a test DataFrame with more rows
    df = DataFrame((;
        id = collect(1:20),
        val = randn(20),
    ))

    temp_file = mktempdir() * "/test_nrows.ipc"
    write_ipc(temp_file, df)

    # scan_ipc with n_rows limit
    df_limited = scan_ipc(temp_file; n_rows = 5) |> collect
    @test size(df_limited) == (5, 2)
    @test df_limited[:id] == 1:5
end

@testset "scan_ipc with row_index option" begin
    df = DataFrame((;
        a = [10, 20, 30],
        b = ["x", "y", "z"],
    ))

    temp_file = mktempdir() * "/test_rowindex.ipc"
    write_ipc(temp_file, df)

    # scan_ipc with row_index
    df_indexed = scan_ipc(temp_file; row_index_name = "idx") |> collect
    @test Tables.columnnames(df_indexed) == (:idx, :a, :b)
    @test df_indexed[:idx] == UInt32[0, 1, 2]
    @test df_indexed[:a] == [10, 20, 30]
end

@testset "read_ipc / write_ipc round-trip with nulls" begin
    df = DataFrame((;
        id = [1, 2, 3],
        data = Union{String, Missing}["hello", missing, "world"],
    ))

    temp_file = mktempdir() * "/test_nulls.ipc"
    write_ipc(temp_file, df)

    df_read = read_ipc(temp_file)
    @test size(df_read) == size(df)
    @test df_read[:id] == [1, 2, 3]
    data_read = collect(df_read[:data])
    @test data_read[1] == "hello"
    @test ismissing(data_read[2])
    @test data_read[3] == "world"
end

@testset "write_ipc with compression options" begin
    df = DataFrame((; x = collect(1:100), y = randn(100)))

    temp_dir = mktempdir()

    # Test different compression algorithms
    for compression in [:uncompressed, :lz4, :zstd]
        temp_file = temp_dir * "/test_$compression.ipc"
        write_ipc(temp_file, df; compression = compression)

        # Verify the file was written and can be read back
        df_read = read_ipc(temp_file)
        @test size(df_read) == size(df)
        @test df_read[:x] == df[:x]
    end
end
