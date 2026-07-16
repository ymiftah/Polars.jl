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

    # multi-key join with nulls in key columns (nulls should not match)
    a5 = DataFrame((; k1 = [1, 1, 2, missing], k2 = ["x", "y", "x", "x"], v = [10, 20, 30, 40]))
    b5 = DataFrame((; k1 = [1, 2, missing], k2 = ["x", "x", "x"], w = [100, 200, 300]))
    r5 = innerjoin(a5, b5, [col("k1"), col("k2")])
    # a: (1,x,10) (1,y,20) (2,x,30) (missing,x,40); b: (1,x,100) (2,x,200) (missing,x,300)
    # only (1,x) and (2,x) match on both sides; (1,y) has no partner; missing never matches
    @test size(r5) == (2, 4)
    @test r5[:k1] == [1, 2]
    @test r5[:k2] == ["x", "x"]
    @test r5[:v] == [10, 30]
    @test r5[:w] == [100, 200]
end

@testset "leftjoin / rightjoin / outerjoin / semijoin / antijoin" begin
    a = DataFrame((; id = [1, 2, 3], name = ["x", "y", "z"]))
    b = DataFrame((; id = [2, 3, 4], val = [20, 30, 40]))

    r_left = leftjoin(a, b, col("id"))
    @test size(r_left) == (3, 3)
    @test r_left[:id] == [1, 2, 3]
    @test isequal(r_left[:val], [missing, 20, 30])

    r_right = rightjoin(a, b, col("id"))
    @test size(r_right) == (3, 3)
    @test r_right[:id] == [2, 3, 4]
    @test isequal(r_right[:name], ["y", "z", missing])  # left column has null for non-matching rows

    r_full = outerjoin(a, b, col("id"))
    @test size(r_full) == (4, 4) # keys not coalesced by default: id, name, id_right, val
    # id (left) is missing for the right-only row (id 4, which shows up in id_right instead);
    # row order isn't guaranteed, so compare as sets
    @test Set(skipmissing(r_full[:id])) == Set([1, 2, 3])
    @test count(ismissing, r_full[:id]) == 1
    @test Set(skipmissing(r_full[:id_right])) == Set([2, 3, 4])
    @test count(ismissing, r_full[:id_right]) == 1

    r_semi = semijoin(a, b, col("id"))
    @test size(r_semi) == (2, 2) # only left columns
    @test r_semi[:id] == [2, 3]

    r_anti = antijoin(a, b, col("id"))
    @test size(r_anti) == (1, 2)
    @test r_anti[:id] == [1]

    # LazyFrame entry points agree
    @test collect(leftjoin(lazy(a), lazy(b), col("id")))[:val] |> collect |> x -> isequal(x, [missing, 20, 30])
end

@testset "crossjoin" begin
    a = DataFrame((; id = [1, 2], v = ["x", "y"]))
    b = DataFrame((; bid = [10, 20, 30]))

    r = crossjoin(a, b)
    @test size(r) == (6, 3) # 2 * 3 rows, Cartesian product

    # Verify all pairs appear exactly once: (1,x,10), (1,x,20), (1,x,30), (2,y,10), (2,y,20), (2,y,30)
    pairs = [(r[:id][i], r[:v][i], r[:bid][i]) for i in 1:6]
    expected_pairs = Set([
        (1, "x", 10), (1, "x", 20), (1, "x", 30),
        (2, "y", 10), (2, "y", 20), (2, "y", 30)
    ])
    @test Set(pairs) == expected_pairs
end

@testset "join_asof" begin
    trades = DataFrame(
        (;
            time = [DateTime(2024, 1, 1, 9, 0, 1), DateTime(2024, 1, 1, 9, 0, 3), DateTime(2024, 1, 1, 9, 0, 7)],
            price = [100.0, 101.0, 102.0],
        )
    )
    quotes = DataFrame(
        (;
            time = [
                DateTime(2024, 1, 1, 9, 0, 0), DateTime(2024, 1, 1, 9, 0, 2),
                DateTime(2024, 1, 1, 9, 0, 4), DateTime(2024, 1, 1, 9, 0, 6),
            ],
            bid = [10.0, 11.0, 12.0, 13.0],
        )
    )

    r_back = join_asof(trades, quotes, "time")
    @test r_back[:bid] == [10.0, 11.0, 13.0]

    r_fwd = join_asof(trades, quotes, "time"; strategy = :forward)
    @test isequal(r_fwd[:bid], [11.0, 12.0, missing])

    # by-group matching
    trades2 = DataFrame(
        (;
            g = ["a", "a", "b"],
            time = [DateTime(2024, 1, 1, 9, 0, 1), DateTime(2024, 1, 1, 9, 0, 5), DateTime(2024, 1, 1, 9, 0, 3)],
        )
    )
    quotes2 = DataFrame(
        (;
            g = ["a", "a", "b", "b"],
            time = [
                DateTime(2024, 1, 1, 9, 0, 0), DateTime(2024, 1, 1, 9, 0, 4),
                DateTime(2024, 1, 1, 9, 0, 0), DateTime(2024, 1, 1, 9, 0, 2),
            ],
            val = [1, 2, 3, 4],
        )
    )
    r_by = join_asof(trades2, quotes2, "time"; by_left = ["g"], by_right = ["g"])
    @test r_by[:val] == [1, 2, 4]

    # nearest strategy: matches to the nearest row (either before or after); ties (9:00:01 is
    # equidistant from 9:00:00/9:00:02, 9:00:03 from 9:00:02/9:00:04) break toward the later quote
    r_nearest = join_asof(trades, quotes, "time"; strategy = :nearest)
    @test r_nearest[:bid] == [11.0, 12.0, 13.0]
end
