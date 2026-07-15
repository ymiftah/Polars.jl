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
