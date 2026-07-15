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
