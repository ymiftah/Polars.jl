@testset "sink_ipc / scan_ipc / read_ipc" begin
    df = DataFrame((; g = ["a", "a", "b", "b", "b"], x = [1, 2, 10, 20, 30]))
    dir = mktempdir()

    pipeline(lf) = filter(lf, col("x") .> 1) |> x -> select(x, col("g"), (col("x") * 2) |> alias("x2"))

    # reference: eager equivalent of the same pipeline
    ref = collect(pipeline(lazy(df)))

    # sink_ipc: same pipeline, out-of-core write
    sink_path = joinpath(dir, "sunk.arrow")
    sink_ipc(pipeline(lazy(df)), sink_path)
    sunk = read_ipc(sink_path)

    @test size(sunk) == size(ref)
    @test sunk[:g] == ref[:g]
    @test sunk[:x2] == ref[:x2]

    # scan_ipc is lazy: collecting it agrees with read_ipc
    @test collect(scan_ipc(sink_path))[:g] == sunk[:g]
    @test collect(scan_ipc(sink_path))[:x2] == sunk[:x2]

    # DataFrame entry point agrees
    sink_path2 = joinpath(dir, "sunk_eager.arrow")
    sink_ipc(df, sink_path2)
    @test read_ipc(sink_path2)[:g] == df[:g]
    @test read_ipc(sink_path2)[:x] == df[:x]
end

@testset "write_ipc" begin
    df = DataFrame((; x = collect(1:100), y = string.(1:100)))
    dir = mktempdir()

    @testset "compression round-trips for every algorithm" begin
        for c in (:uncompressed, :lz4, :zstd)
            path = joinpath(dir, "c_$c.arrow")
            write_ipc(path, df; compression = c)
            df2 = read_ipc(path)
            @test df2[:x] == df[:x]
            @test df2[:y] == df[:y]
        end
    end

    @testset "compression_level tunes zstd output size" begin
        words = ["the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog", "and", "cat"]
        compressible = DataFrame((; s = [join(rand(words, 30), ' ') for _ in 1:20_000]))
        p1 = joinpath(dir, "zstd1.arrow")
        p22 = joinpath(dir, "zstd22.arrow")
        write_ipc(p1, compressible; compression = :zstd, compression_level = 1)
        write_ipc(p22, compressible; compression = :zstd, compression_level = 22)
        @test filesize(p22) < filesize(p1)
        @test read_ipc(p22)[:s] == compressible[:s]
    end

    @testset "record_batch_size accepted" begin
        path = joinpath(dir, "rb.arrow")
        write_ipc(path, df; record_batch_size = 10)
        @test read_ipc(path)[:x] == df[:x]
    end

    @testset "write_ipc(io::IO, df) works" begin
        io = IOBuffer()
        write_ipc(io, df)
        @test io.size > 0
    end
end

@testset "scan_ipc / sink_ipc options" begin
    @testset "n_rows / row_index_name / row_index_offset" begin
        dir = mktempdir()
        path = joinpath(dir, "basic.arrow")
        write_ipc(path, DataFrame((; a = [1, 2, 3])))
        @test size(read_ipc(path; n_rows = 2)) == (2, 1)
        idx = read_ipc(path; row_index_name = "idx", row_index_offset = 10)
        @test Tables.columnnames(idx)[1] == :idx
        @test Vector(idx[:idx]) == [10, 11, 12]
    end

    @testset "hive_partitioning" begin
        dir = mktempdir()
        write_ipc(joinpath(mkpath(joinpath(dir, "year=2023")), "part.arrow"), DataFrame((; x = [1, 2])))
        write_ipc(joinpath(mkpath(joinpath(dir, "year=2024")), "part.arrow"), DataFrame((; x = [3, 4])))
        with_hive = read_ipc(dir)
        @test Set(Tables.columnnames(with_hive)) == Set([:x, :year])
        without_hive = read_ipc(dir; hive_partitioning = false)
        @test Set(Tables.columnnames(without_hive)) == Set([:x])
    end

    @testset "allow_missing_columns" begin
        multi = mkpath(joinpath(mktempdir(), "multi"))
        write_ipc(joinpath(multi, "f1.arrow"), DataFrame((; x = [1, 2], y = [3, 4])))
        write_ipc(joinpath(multi, "f2.arrow"), DataFrame((; x = [5, 6])))
        @test_throws Exception collect(scan_ipc(joinpath(multi, "*.arrow")))
        df = read_ipc(joinpath(multi, "*.arrow"); allow_missing_columns = true)
        @test size(df) == (4, 2)
    end

    @testset "sink_ipc mkdir" begin
        dir = mktempdir()
        df = DataFrame((; x = [1, 2, 3]))
        nested = joinpath(dir, "a", "b", "c", "out.arrow")
        @test !isdir(dirname(nested))
        sink_ipc(df, nested; mkdir = true)
        @test isfile(nested)
        @test read_ipc(nested)[:x] == df[:x]

        missing_dir_path = joinpath(dir, "does", "not", "exist", "out.arrow")
        @test_throws Exception sink_ipc(df, missing_dir_path)
    end
end
