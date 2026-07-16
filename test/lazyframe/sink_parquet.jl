@testset "sink_parquet" begin
    df = DataFrame((; g = ["a", "a", "b", "b", "b"], x = [1, 2, 10, 20, 30]))
    dir = mktempdir()

    pipeline(lf) = filter(lf, col("x") .> 1) |> x -> select(x, col("g"), (col("x") * 2) |> alias("x2"))

    # reference: eager collect -> write -> read
    ref_path = joinpath(dir, "ref.parquet")
    write_parquet(ref_path, collect(pipeline(lazy(df))))
    ref = read_parquet(ref_path)

    # sink_parquet: same pipeline, out-of-core write
    sink_path = joinpath(dir, "sunk.parquet")
    sink_parquet(pipeline(lazy(df)), sink_path)
    sunk = read_parquet(sink_path)

    @test size(sunk) == size(ref)
    @test sunk[:g] == ref[:g]
    @test sunk[:x2] == ref[:x2]

    # DataFrame entry point agrees
    sink_path2 = joinpath(dir, "sunk_eager.parquet")
    sink_parquet(df, sink_path2)
    @test read_parquet(sink_path2)[:g] == df[:g]
    @test read_parquet(sink_path2)[:x] == df[:x]
end

@testset "sink_parquet options" begin
    df = DataFrame((; g = ["a", "a", "b", "b", "b"], x = [1, 2, 10, 20, 30]))
    dir = mktempdir()

    @testset "compression/statistics/row_group_size passthrough" begin
        path = joinpath(dir, "opts.parquet")
        sink_parquet(
            df, path; compression = :gzip, compression_level = 4, statistics = false,
            row_group_size = 2
        )
        @test read_parquet(path)[:x] == df[:x]
    end

    @testset "compression round-trips for every algorithm" begin
        for c in (:uncompressed, :snappy, :gzip, :brotli, :zstd, :lz4_raw)
            path = joinpath(dir, "c_$c.parquet")
            sink_parquet(df, path; compression = c)
            df2 = read_parquet(path)
            @test df2[:x] == df[:x]
            @test df2[:g] == df[:g]
        end
    end

    @testset "data_page_size accepted" begin
        path = joinpath(dir, "dps.parquet")
        sink_parquet(df, path; data_page_size = 1024)
        @test read_parquet(path)[:x] == df[:x]
    end

    @testset "maintain_order preserves row order; false doesn't break correctness" begin
        path_ordered = joinpath(dir, "ordered.parquet")
        sink_parquet(df, path_ordered; maintain_order = true)
        @test read_parquet(path_ordered)[:x] == df[:x]

        path_unordered = joinpath(dir, "unordered.parquet")
        sink_parquet(df, path_unordered; maintain_order = false)
        @test Set(collect(read_parquet(path_unordered)[:x])) == Set(collect(df[:x]))
    end

    @testset "mkdir creates missing parent directories" begin
        nested = joinpath(dir, "a", "b", "c", "out.parquet")
        @test !isdir(dirname(nested))
        sink_parquet(df, nested; mkdir = true)
        @test isfile(nested)
        @test read_parquet(nested)[:x] == df[:x]
    end

    @testset "mkdir=false (default) errors into a missing directory" begin
        missing_dir_path = joinpath(dir, "does", "not", "exist", "out.parquet")
        @test_throws Exception sink_parquet(df, missing_dir_path)
    end
end
