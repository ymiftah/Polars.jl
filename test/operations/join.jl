@testset "innerjoin" begin
    a = DataFrame((; id = [1, 2, 3], name = ["x", "y", "z"]))
    b = DataFrame((; id = [2, 3, 4], val = [20, 30, 40]))

    # single key, same name on both sides
    r = innerjoin(a, b, col("id"))
    @test r[:id] == [2, 3]
    @test r[:name] == ["y", "z"]
    @test r[:val] == [20, 30]

    # LazyFrame entry point agrees
    r_lazy = innerjoin(lazy(a), lazy(b), col("id"), col("id")) |> collect
    @test r_lazy[:id] == r[:id]
    @test r_lazy[:name] == r[:name]
    @test r_lazy[:val] == r[:val]

    # multi-key join
    a2 = DataFrame((; k1 = [1, 1, 2], k2 = ["x", "y", "x"], v = [10, 20, 30]))
    b2 = DataFrame((; k1 = [1, 1, 2], k2 = ["x", "y", "z"], w = [100, 200, 300]))
    r2 = innerjoin(a2, b2, [col("k1"), col("k2")])
    @test r2[:k1] == [1, 1]
    @test r2[:k2] == ["x", "y"]
    @test r2[:v] == [10, 20]
    @test r2[:w] == [100, 200]

    # differently-named keys on each side
    a3 = DataFrame((; id_a = [1, 2, 3], name = ["x", "y", "z"]))
    b3 = DataFrame((; id_b = [2, 3, 4], val = [20, 30, 40]))
    r3 = innerjoin(a3, b3, col("id_a"), col("id_b"))
    @test size(r3) == (2, 3)
    @test r3[:name] == ["y", "z"]
    @test r3[:val] == [20, 30]

    # no matching rows -> empty result, correct column count preserved
    a4 = DataFrame((; id = [1, 2, 3], v = [10, 20, 30]))
    b4 = DataFrame((; id = [4, 5, 6], w = [100, 200, 300]))
    r4 = innerjoin(a4, b4, col("id"))
    @test size(r4) == (0, 3)
end
