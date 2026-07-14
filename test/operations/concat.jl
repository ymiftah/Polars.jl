@testset "concat" begin
    a = DataFrame((; id = [1, 2], name = ["x", "y"]))
    b = DataFrame((; id = [3, 4], name = ["z", "w"]))

    r = concat([a, b])
    @test size(r) == (4, 2)
    @test r[:id] == [1, 2, 3, 4]
    @test r[:name] == ["x", "y", "z", "w"]

    # LazyFrame entry point agrees, and stacks the first frame (regression: previously the
    # first frame in the list was silently dropped)
    r_lazy = concat([lazy(a), lazy(b)]) |> collect
    @test r_lazy[:id] == r[:id]
    @test r_lazy[:name] == r[:name]

    # concatenating a frame with itself doubles it, including the first occurrence
    r_self = concat([a, a])
    @test size(r_self) == (4, 2)
    @test r_self[:id] == [1, 2, 1, 2]

    # single-frame concat is a no-op
    r_single = concat([a])
    @test size(r_single) == (2, 2)
    @test r_single[:id] == [1, 2]
end
