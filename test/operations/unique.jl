@testset "unique operations on DataFrame" begin
    df = DataFrame((;
        a = [1, 1, 2, 2, 3],
        b = ["x", "x", "y", "y", "z"],
        val = [10, 20, 30, 40, 50]
    ))

    # unique on single column with keep=:first
    r_first = unique(df, ["a"]; keep = :first)
    @test size(r_first) == (3, 3)
    @test r_first[:a] == [1, 2, 3]
    @test r_first[:val] == [10, 30, 50]  # first occurrence of each a value

    # unique on single column with keep=:last
    r_last = unique(df, ["a"]; keep = :last)
    @test size(r_last) == (3, 3)
    @test r_last[:a] == [1, 2, 3]
    @test r_last[:val] == [20, 40, 50]  # last occurrence of each a value

    # unique on multi-column subset
    r_multi = unique(df, ["a", "b"]; keep = :first)
    @test size(r_multi) == (3, 3)  # (1,x), (2,y), (3,z)
    @test r_multi[:a] == [1, 2, 3]
    @test r_multi[:b] == ["x", "y", "z"]
end

@testset "n_unique" begin
    df = DataFrame((;
        x = [1, 1, 2, 2, 3],
        y = ["a", "a", "b", "b", "c"]
    ))

    # n_unique in expression form (via group_by)
    result = group_by(lazy(df), "y") |>
        x -> agg(x, n_unique(col("x")) |> alias("n_unique_x")) |>
        collect

    # Check that distinct count is correct for each group
    by_y = Dict(zip(result[:y], result[:n_unique_x]))
    @test by_y["a"] == 1  # group "a" has only value 1
    @test by_y["b"] == 1  # group "b" has only value 2
    @test by_y["c"] == 1  # group "c" has only value 3

    # Test on full column
    df_vals = DataFrame((; vals = [1, 1, 2, 2, 3, missing, missing]))
    n_uniq = select(lazy(df_vals), n_unique(col("vals")) |> alias("nuniq")) |> collect
    @test n_uniq[:nuniq][1] == 4  # distinct values: 1, 2, 3, missing
end

@testset "is_unique / is_duplicated" begin
    df = DataFrame((;
        a = [1, 1, 2, 3, 3],
        b = ["x", "x", "y", "z", "z"]
    ))

    # is_unique on column 'a'
    r_unique = select(df, is_unique(col("a")) |> alias("is_unique_a"))
    @test r_unique[:is_unique_a] == [false, false, true, false, false]

    # is_duplicated on column 'a'
    r_dup = select(df, is_duplicated(col("a")) |> alias("is_dup_a"))
    @test r_dup[:is_dup_a] == [true, true, false, true, true]

    # is_unique on multi-column subset
    r_unique_multi = select(df, is_unique(col("a"), col("b")) |> alias("is_unique_pair"))
    @test r_unique_multi[:is_unique_pair] == [false, false, true, false, false]
end

@testset "approx_n_unique" begin
    df = DataFrame((; x = collect(1:100)))

    # Approximate unique count on large column
    approx_result = select(lazy(df), approx_n_unique(col("x")) |> alias("approx_nuniq")) |> collect
    approx_count = approx_result[:approx_nuniq][1]

    # Approximate count should be close to the true count (100)
    # Allow some tolerance in the approximation
    @test 80 < approx_count < 120
end

@testset "unique_counts" begin
    df = DataFrame((;
        x = [1, 1, 1, 2, 2, 3],
        y = ["a", "a", "b", "b", "c", "c"]
    ))

    # Get counts of unique values in column x
    result = select(df, unique_counts(col("x")) |> alias("counts"))
    counts = result[:counts]

    # Should have counts for each row corresponding to how many times that value appears
    @test counts == [3, 3, 3, 2, 2, 1]  # 1 appears 3 times, 2 appears 2 times, 3 appears 1 time
end
