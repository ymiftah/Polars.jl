@testset "sink_ndjson" begin
    df = DataFrame((; g = ["a", "a", "b", "b", "b"], x = [1, 2, 10, 20, 30]))
    dir = mktempdir()

    pipeline(lf) = filter(lf, col("x") .> 1) |> x -> select(x, col("g"), (col("x") * 2) |> alias("x2"))

    # reference: eager collect -> write -> read
    ref_path = joinpath(dir, "ref.jsonl")
    write_ndjson(ref_path, collect(pipeline(lazy(df))))
    ref = read_ndjson(ref_path)

    # sink_ndjson: same pipeline, out-of-core write
    sink_path = joinpath(dir, "sunk.jsonl")
    sink_ndjson(pipeline(lazy(df)), sink_path)
    sunk = read_ndjson(sink_path)

    @test size(sunk) == size(ref)
    @test sunk[:g] == ref[:g]
    @test sunk[:x2] == ref[:x2]

    # DataFrame entry point agrees
    sink_path2 = joinpath(dir, "sunk_eager.jsonl")
    sink_ndjson(df, sink_path2)
    @test read_ndjson(sink_path2)[:g] == df[:g]
    @test read_ndjson(sink_path2)[:x] == df[:x]
end

@testset "sink_ndjson options" begin
    df = DataFrame((; x = collect(1:50), y = ["v$i" for i in 1:50]))
    dir = mktempdir()

    @testset "maintain_order preserves row order; false doesn't break correctness" begin
        path_ordered = joinpath(dir, "ordered.jsonl")
        sink_ndjson(df, path_ordered; maintain_order = true)
        @test read_ndjson(path_ordered)[:x] == df[:x]

        path_unordered = joinpath(dir, "unordered.jsonl")
        sink_ndjson(df, path_unordered; maintain_order = false)
        @test Set(collect(read_ndjson(path_unordered)[:x])) == Set(collect(df[:x]))
    end

    @testset "mkdir creates missing parent directories" begin
        nested = joinpath(dir, "a", "b", "c", "out.jsonl")
        @test !isdir(dirname(nested))
        sink_ndjson(df, nested; mkdir = true)
        @test isfile(nested)
        @test read_ndjson(nested)[:x] == df[:x]
    end

    @testset "mkdir=false (default) errors into a missing directory" begin
        missing_dir_path = joinpath(dir, "does", "not", "exist", "out.jsonl")
        @test_throws Exception sink_ndjson(df, missing_dir_path)
    end
end
