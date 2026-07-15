@testset "sink_csv" begin
    df = DataFrame((; g = ["a", "a", "b", "b", "b"], x = [1, 2, 10, 20, 30]))
    dir = mktempdir()

    pipeline(lf) = filter(lf, col("x") .> 1) |> x -> select(x, col("g"), (col("x") * 2) |> alias("x2"))

    # reference: eager collect -> write -> read
    ref_path = joinpath(dir, "ref.csv")
    write_csv(ref_path, collect(pipeline(lazy(df))))
    ref = read_csv(ref_path)

    # sink_csv: same pipeline, out-of-core write
    sink_path = joinpath(dir, "sunk.csv")
    sink_csv(pipeline(lazy(df)), sink_path)
    sunk = read_csv(sink_path)

    @test size(sunk) == size(ref)
    @test sunk[:g] == ref[:g]
    @test sunk[:x2] == ref[:x2]

    # DataFrame entry point agrees
    sink_path2 = joinpath(dir, "sunk_eager.csv")
    sink_csv(df, sink_path2)
    @test read_csv(sink_path2)[:g] == df[:g]
    @test read_csv(sink_path2)[:x] == df[:x]
end

@testset "sink_csv options" begin
    # `y` uses non-numeric-looking strings deliberately -- CSV has no explicit schema, so a
    # string column of purely numeric-looking values (e.g. "1", "2", ...) round-trips back as an
    # inferred integer column, losing the original string dtype. Not a compression concern.
    df = DataFrame((; x = collect(1:50), y = ["v$i" for i in 1:50]))
    dir = mktempdir()

    @testset "compression round-trips" begin
        for c in (:uncompressed, :gzip, :zstd)
            path = joinpath(dir, "c_$c.csv")
            sink_csv(df, path; compression = c)
            df2 = read_csv(path)
            @test df2[:x] == df[:x]
            @test df2[:y] == df[:y]
        end
    end

    @testset "formatting options passthrough" begin
        path = joinpath(dir, "fmt.csv")
        sink_csv(df, path; separator = ';', quote_style = :always)
        @test occursin(";", read(path, String))
        @test read_csv(path; separator = ';')[:x] == df[:x]
    end

    @testset "mkdir creates missing parent directories" begin
        nested = joinpath(dir, "a", "b", "c", "out.csv")
        @test !isdir(dirname(nested))
        sink_csv(df, nested; mkdir = true)
        @test isfile(nested)
        @test read_csv(nested)[:x] == df[:x]
    end

    @testset "mkdir=false (default) errors into a missing directory" begin
        missing_dir_path = joinpath(dir, "does", "not", "exist", "out.csv")
        @test_throws Exception sink_csv(df, missing_dir_path)
    end
end
