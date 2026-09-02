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

@testset "sink_parquet partitioned by key" begin
    df = DataFrame((; g = ["a", "a", "b", "b", "b"], x = [1, 2, 10, 20, 30]))

    @testset "single key produces g=.../00000000.parquet layout" begin
        dir = mktempdir()
        sink_parquet(df, PartitionByKey(dir; by = "g"))

        @test isfile(joinpath(dir, "g=a", "00000000.parquet"))
        @test isfile(joinpath(dir, "g=b", "00000000.parquet"))

        rt = collect(scan_parquet(dir; hive_partitioning = true))
        @test size(rt) == size(df)
        @test sort(collect(rt[:x])) == sort(collect(df[:x]))
        @test sort(collect(rt[:g])) == sort(collect(df[:g]))
    end

    @testset "include_key=false omits the key column from file contents" begin
        dir = mktempdir()
        sink_parquet(df, PartitionByKey(dir; by = "g", include_key = false))

        leaf = read_parquet(joinpath(dir, "g=a", "00000000.parquet"))
        @test names(leaf) == ["x"]
    end

    @testset "multiple keys nest directories" begin
        dfd = DataFrame((; d = [Date(2024, 1, 1), Date(2024, 2, 1), Date(2024, 2, 15)], v = [1, 2, 3]))
        dir = mktempdir()
        sink_parquet(
            dfd,
            PartitionByKey(dir; by = [Dt.year(col("d")) |> alias("year"), Dt.month(col("d")) |> alias("month")])
        )

        @test isfile(joinpath(dir, "year=2024", "month=1", "00000000.parquet"))
        @test isfile(joinpath(dir, "year=2024", "month=2", "00000000.parquet"))
    end

    @testset "max_rows_per_file spills a partition across numbered files" begin
        big = DataFrame((; g = fill("a", 100), x = collect(1:100)))
        dir = mktempdir()
        sink_parquet(big, PartitionByKey(dir; by = "g", max_rows_per_file = 30))

        files = readdir(joinpath(dir, "g=a"))
        @test length(files) == 4 # 30, 30, 30, 10

        rt = collect(scan_parquet(dir; hive_partitioning = true))
        @test sort(collect(rt[:x])) == sort(collect(big[:x]))
    end

    @testset "empty by errors" begin
        @test_throws Exception PartitionByKey(mktempdir(); by = String[])
    end

    @testset "non-elementwise key expression errors catchably" begin
        dir = mktempdir()
        @test_throws Exception sink_parquet(df, PartitionByKey(dir; by = sum(col("x")) |> alias("s")))
    end

    @testset "mkdir keyword is not accepted (upstream ignores it for partitioned sinks)" begin
        dir = mktempdir()
        @test_throws Exception sink_parquet(df, PartitionByKey(dir; by = "g"); mkdir = true)
    end

    @testset "non-ASCII base path and key value round-trip" begin
        dir = mktempdir()
        target_dir = joinpath(dir, "café-dir")
        mkpath(target_dir)
        dfu = DataFrame((; g = ["café", "café", "naïve"], x = [1, 2, 3]))
        sink_parquet(dfu, PartitionByKey(target_dir; by = "g"))

        rt = collect(scan_parquet(target_dir; hive_partitioning = true))
        @test size(rt) == size(dfu)
        @test sort(collect(rt[:g])) == sort(collect(dfu[:g]))
    end

    @testset "DataFrame entry point agrees with LazyFrame" begin
        dir = mktempdir()
        sink_parquet(lazy(df), PartitionByKey(dir; by = "g"))
        rt = collect(scan_parquet(dir; hive_partitioning = true))
        @test sort(collect(rt[:x])) == sort(collect(df[:x]))
    end
end

@testset "write_parquet routes cloud URIs to sink_parquet instead of a local file" begin
    df = DataFrame((; x = [1, 2, 3]))
    dir = mktempdir()

    cd(dir) do
        try
            write_parquet("s3://some-bucket/out.parquet", df)
        catch
            # Expected: this attempts a real network call via sink_parquet and fails without
            # credentials/network access -- that's fine, we're not asserting upload success.
        end
    end
    @test isempty(readdir(dir))
    @test !isdir(joinpath(dir, "s3:"))

    # a plain local path takes the same entry point and still writes normally
    local_path = joinpath(dir, "out.parquet")
    write_parquet(local_path, df)
    @test read_parquet(local_path)[:x] == df[:x]
end

@testset "large all-true Boolean column round-trips without panicking (py-polars test_sink_boolean_panic_25806)" begin
    # upstream's regression is specifically about a boolean-encoding panic at a large
    # (>morsel-size) row count in the streaming sink engine; this wrapper doesn't expose that
    # engine's internals directly, so this is a black-box round-trip smoke test at a comparable
    # scale rather than a reproduction of the exact original crash path.
    df = DataFrame((; bool = fill(true, 300_000)))
    path = mktempdir() * "/large_bool.parquet"
    write_parquet(path, df)
    r = read_parquet(path)
    @test size(r) == size(df)
    @test all(collect(r[:bool]))
end
