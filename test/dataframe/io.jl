alleq(a, b) = length(a) == length(b) && all(isequal(a[i], b[i]) for i in eachindex(a))

@testset "Date" begin
    dates = [Date(2024, 1, 1), Date(2024, 1, 2), Date(2024, 1, 3)]
    df = DataFrame((; d = dates))

    @test Polars.schema(df).types == (Date,)
    @test df[:d] == dates

    path = write_temp_parquet(df)
    df2 = read_parquet(path)
    @test df2[:d] == dates
end

@testset "parquet round-trip across dtypes" begin
    df = DataFrame(
        (;
            i = [1, 2, 3, missing],
            f = [1.5, 2.5, missing, 4.5],
            b = [true, false, true, missing],
            s = ["a", "b", missing, "d"],
            d = [Date(2024, 1, 1), Date(2024, 1, 2), missing, Date(2024, 1, 4)],
            dt = [DateTime(2024, 1, 1, 1), missing, DateTime(2024, 1, 1, 3), DateTime(2024, 1, 1, 4)],
        )
    )

    path = write_temp_parquet(df)
    df2 = read_parquet(path)

    @test size(df2) == size(df)
    @test alleq(df2[:i], df[:i])
    @test alleq(df2[:f], df[:f])
    @test alleq(df2[:b], df[:b])
    @test alleq(df2[:s], df[:s])
    @test alleq(df2[:d], df[:d])
    @test alleq(df2[:dt], df[:dt])
end

@testset "write_parquet options" begin
    df = DataFrame((; x = collect(1:200), y = string.(1:200)))
    dir = mktempdir()

    @testset "compression round-trips for every algorithm" begin
        for c in (:uncompressed, :snappy, :gzip, :brotli, :zstd, :lz4_raw)
            path = joinpath(dir, "c_$c.parquet")
            write_parquet(path, df; compression = c)
            df2 = read_parquet(path)
            @test df2[:x] == df[:x]
            @test df2[:y] == df[:y]
        end
    end

    @testset "compression_level rejected for non-leveled algorithms" begin
        for c in (:uncompressed, :snappy, :lz4_raw)
            @test_throws Exception write_parquet(
                joinpath(dir, "bad.parquet"), df; compression = c, compression_level = 3
            )
        end
    end

    @testset "compression_level tunes zstd output size" begin
        # Needs data that's redundant enough for zstd to work with but not so uniform that
        # parquet's own dictionary/RLE encoding collapses it before compression level matters —
        # distinct random word combinations from a small shared vocabulary fit that shape.
        words = ["the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog", "and", "cat"]
        compressible = DataFrame((; s = [join(rand(words, 30), ' ') for _ in 1:20_000]))
        p1 = joinpath(dir, "zstd1.parquet")
        p22 = joinpath(dir, "zstd22.parquet")
        write_parquet(p1, compressible; compression = :zstd, compression_level = 1)
        write_parquet(p22, compressible; compression = :zstd, compression_level = 22)
        @test filesize(p22) < filesize(p1)
        @test read_parquet(p22)[:s] == compressible[:s]
    end

    @testset "statistics=false still round-trips" begin
        path = joinpath(dir, "nostat.parquet")
        write_parquet(path, df; statistics = false)
        @test read_parquet(path)[:x] == df[:x]
    end

    @testset "row_group_size / data_page_size accepted" begin
        path = joinpath(dir, "rg.parquet")
        write_parquet(path, df; row_group_size = 50, data_page_size = 1024)
        df2 = read_parquet(path)
        @test size(df2) == size(df)
    end
end
