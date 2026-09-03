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

@testset "join options: suffix, coalesce, validate, nulls_equal" begin
    a = DataFrame((; id = [1, 2, 3], name = ["x", "y", "z"]))
    b = DataFrame((; id = [2, 3, 4], val = [20, 30, 40]))

    # suffix: default is "_right"; a custom suffix is honored
    r_default = outerjoin(a, b, col("id"))
    @test "id_right" in Polars.names(r_default)

    r_suffix = outerjoin(a, b, col("id"); suffix = "_b")
    @test "id_b" in Polars.names(r_suffix)
    @test !("id_right" in Polars.names(r_suffix))

    # coalesce: default (:join_specific) coalesces the join key for inner/left/right, but *not*
    # for outer (matches upstream's own `JoinCoalesce::coalesce` table -- Full only coalesces
    # under :coalesce_columns, not :join_specific)
    r_coalesce_default = innerjoin(a, b, col("id"))
    @test Polars.names(r_coalesce_default) == ["id", "name", "val"]
    @test "id_right" in Polars.names(outerjoin(a, b, col("id")))

    # :keep_columns keeps both id columns even for a join type that would otherwise coalesce
    r_keep = innerjoin(a, b, col("id"); coalesce = :keep_columns)
    @test "id_right" in Polars.names(r_keep)

    # :coalesce_columns forces coalescing, including for outer (where :join_specific doesn't)
    r_force_coalesce = innerjoin(a, b, col("id"); coalesce = :coalesce_columns)
    @test Polars.names(r_force_coalesce) == ["id", "name", "val"]
    r_outer_force_coalesce = outerjoin(a, b, col("id"); coalesce = :coalesce_columns)
    @test !("id_right" in Polars.names(r_outer_force_coalesce))

    @test_throws Exception innerjoin(a, b, col("id"); coalesce = :bogus)

    # validate: :many_to_many (default) never raises; :one_to_one raises when a key repeats
    dup_a = DataFrame((; id = [1, 1, 2], v = [1, 2, 3]))
    dup_b = DataFrame((; id = [1, 2], w = [10, 20]))
    @test size(innerjoin(dup_a, dup_b, col("id"); validate = :many_to_many)) == (3, 3)
    @test_throws PolarsError innerjoin(dup_a, dup_b, col("id"); validate = :one_to_one)
    @test_throws PolarsError innerjoin(dup_a, dup_b, col("id"); validate = :one_to_many)
    # dup_b's key is unique, so many_to_one (checks uniqueness on the right) passes
    @test size(innerjoin(dup_a, dup_b, col("id"); validate = :many_to_one)) == (3, 3)
    @test_throws Exception innerjoin(a, b, col("id"); validate = :bogus)

    # nulls_equal: default false means a null key on both sides never matches
    a_null = DataFrame((; id = [1, missing], v = [10, 20]))
    b_null = DataFrame((; id = [1, missing], w = [100, 200]))
    r_no_match = innerjoin(a_null, b_null, col("id"))
    @test size(r_no_match) == (1, 3)

    r_match = innerjoin(a_null, b_null, col("id"); nulls_equal = true)
    @test size(r_match) == (2, 3)

    # joining on the same key expression twice is a Step-5 abort-safety check: a clean
    # PolarsError ("already joined on"), not a crash (py-polars test_join_raise_on_redundant_keys)
    left = DataFrame((; a = [1, 2, 3], b = [3, 4, 5], c = [5, 6, 7]))
    right = DataFrame((; a = [2, 3, 4], c = [4, 5, 6]))
    @test_throws PolarsError outerjoin(left, right, [col("a"), col("a")]; coalesce = :coalesce_columns)
end

@testset "rightjoin: coalesce column ordering and differently-named keys" begin
    # rightjoin's coalesced result keeps the RIGHT table's copy of the key (opposite of
    # inner/left, which keep the left's) -- column order interleaves left-then-right per side
    # (py-polars test_right_join_schemas)
    a = DataFrame((; a = [1, 2, 3], b = [1, 2, 3]))
    b = DataFrame((; a = [1, 3], b = [1, 3], c = [1, 3]))
    r_coalesce = rightjoin(a, b, col("a"))
    @test Tables.columnnames(r_coalesce) == (:b, :a, :b_right, :c)
    r_keep = rightjoin(a, b, col("a"); coalesce = :keep_columns)
    @test Tables.columnnames(r_keep) == (:a, :b, :a_right, :b_right, :c)

    # differently-named keys: rightjoin keeps both key columns regardless of coalesce (there's
    # nothing to coalesce when the names differ), and the right table's rows all survive
    # (py-polars test_join_right_different_key)
    df = DataFrame((; foo = [1, 2, 3], ham1 = ["a", "b", "c"]))
    other = DataFrame((; apple = ["x", "y", "z"], ham2 = ["a", "b", "d"]))
    r_diffkey = rightjoin(df, other, col("ham1"), col("ham2"))
    @test Tables.columnnames(r_diffkey) == (:foo, :apple, :ham2)
    @test isequal(collect(r_diffkey[:foo]), [1, 2, missing])
end

@testset "crossjoin" begin
    a = DataFrame((; id = [1, 2], v = ["x", "y"]))
    b = DataFrame((; bid = [10, 20, 30]))

    r = crossjoin(a, b)
    @test size(r) == (6, 3) # 2 * 3 rows, Cartesian product

    # Verify all pairs appear exactly once: (1,x,10), (1,x,20), (1,x,30), (2,y,10), (2,y,20), (2,y,30)
    pairs = [(r[:id][i], r[:v][i], r[:bid][i]) for i in 1:6]
    expected_pairs = Set(
        [
            (1, "x", 10), (1, "x", 20), (1, "x", 30),
            (2, "y", 10), (2, "y", 20), (2, "y", 30),
        ]
    )
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

    # by_left/by_right also accept Symbol column identifiers
    r_by_sym = join_asof(trades2, quotes2, "time"; by_left = [:g], by_right = [:g])
    @test r_by_sym[:val] == r_by[:val]

    # nearest strategy: matches to the nearest row (either before or after); ties (9:00:01 is
    # equidistant from 9:00:00/9:00:02, 9:00:03 from 9:00:02/9:00:04) break toward the later quote
    r_nearest = join_asof(trades, quotes, "time"; strategy = :nearest)
    @test r_nearest[:bid] == [11.0, 12.0, 13.0]
end

@testset "join_asof options: tolerance, allow_eq, suffix, nulls_equal" begin
    trades = DataFrame(
        (;
            time = [DateTime(2024, 1, 1, 9, 0, 1), DateTime(2024, 1, 1, 9, 0, 3), DateTime(2024, 1, 1, 9, 0, 7)],
            price = [100.0, 101.0, 102.0],
        )
    )
    quotes = DataFrame(
        (;
            time = [DateTime(2024, 1, 1, 9, 0, 0), DateTime(2024, 1, 1, 9, 0, 2)],
            bid = [10.0, 11.0],
        )
    )

    # no tolerance (default): every left row matches the nearest earlier quote, however far
    r_no_tolerance = join_asof(trades, quotes, "time")
    @test r_no_tolerance[:bid] == [10.0, 11.0, 11.0]

    # tolerance caps how far a match may be: the third trade (9:00:07) is >2s past its nearest
    # quote (9:00:02), so it gets `missing` instead
    r_tolerance = join_asof(trades, quotes, "time"; tolerance = "2s")
    @test isequal(collect(r_tolerance[:bid]), [10.0, 11.0, missing])

    # an invalid tolerance string raises a catchable PolarsError, not a crash
    @test_throws PolarsError join_asof(trades, quotes, "time"; tolerance = "not_a_duration")

    # allow_eq = false: an exact key match no longer counts, so a trade must match a *strictly
    # earlier* quote
    exact = DataFrame((; time = [DateTime(2024, 1, 1, 9, 0, 0)], v = [1]))
    quotes_exact = DataFrame((; time = [DateTime(2024, 1, 1, 9, 0, 0)], bid = [99.0]))
    r_allow_eq = join_asof(exact, quotes_exact, "time"; allow_eq = true)
    @test r_allow_eq[:bid] == [99.0]
    r_no_allow_eq = join_asof(exact, quotes_exact, "time"; allow_eq = false)
    @test isequal(collect(r_no_allow_eq[:bid]), [missing])

    # suffix: default "_right" on a colliding non-key column name
    a_collide = DataFrame((; time = [DateTime(2024, 1, 1, 9, 0, 1)], bid = [1.0]))
    r_suffix_default = join_asof(a_collide, quotes, "time")
    @test "bid_right" in Polars.names(r_suffix_default)
    r_suffix_custom = join_asof(a_collide, quotes, "time"; suffix = "_q")
    @test "bid_q" in Polars.names(r_suffix_custom)
    @test !("bid_right" in Polars.names(r_suffix_custom))

    # nulls_equal: a null asof key matches nothing regardless (asof needs an orderable value),
    # but nulls_equal is exercised here for API-surface coverage/no-crash, matching the other
    # join verbs' own convention
    @test join_asof(trades, quotes, "time"; nulls_equal = true)[:bid] == r_no_tolerance[:bid]

    # maintain_order: exercised for API-surface coverage/no-crash, same convention as the other
    # join verbs
    @test join_asof(trades, quotes, "time"; maintain_order = :left)[:bid] == r_no_tolerance[:bid]
end

@testset "maintain_order across join variants" begin
    # crossjoin: :none/:left/:left_right give left-major row order (every b-row for a given
    # a-row before advancing a); :right/:right_left give right-major order -- matches upstream's
    # own primary/secondary iteration pattern (py-polars test_cross_join_maintain_order_24663)
    a = DataFrame((; x = [0, 1, 2]))
    b = DataFrame((; y = [0, 1]))
    left_major = [(x, y) for x in 0:2 for y in 0:1]
    right_major = [(x, y) for y in 0:1 for x in 0:2]
    for mo in (:none, :left, :left_right)
        r = crossjoin(a, b; maintain_order = mo)
        @test collect(zip(r[:x], r[:y])) == left_major
    end
    for mo in (:right, :right_left)
        r = crossjoin(a, b; maintain_order = mo)
        @test collect(zip(r[:x], r[:y])) == right_major
    end

    # innerjoin: :left preserves the left frame's key order even when the right frame's rows
    # arrive in a different order
    c = DataFrame((; k = [1, 2, 3], v = ["a", "b", "c"]))
    d = DataFrame((; k = [3, 2, 1], w = ["x", "y", "z"]))
    r_left = innerjoin(c, d, col("k"); maintain_order = :left)
    @test r_left[:k] == [1, 2, 3]
    @test r_left[:w] == ["z", "y", "x"]

    # an unknown maintain_order value is a clear ArgumentError-style error, not a crash
    @test_throws ErrorException innerjoin(c, d, col("k"); maintain_order = :bogus)
end
