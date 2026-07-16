@testset "unique operations on DataFrame" begin
    df = DataFrame(
        (;
            a = [1, 1, 2, 2, 3],
            b = ["x", "x", "y", "y", "z"],
            val = [10, 20, 30, 40, 50],
        )
    )

    # unique on single column with keep=:first (row order among groups is not guaranteed
    # without a maintain_order kwarg, which unique doesn't expose -- sort before comparing)
    r_first = sort(unique(df, ["a"]; keep = :first), col("a"))
    @test size(r_first) == (3, 3)
    @test r_first[:a] == [1, 2, 3]
    @test r_first[:val] == [10, 30, 50]  # first occurrence of each a value

    # unique on single column with keep=:last (row order among groups is not guaranteed
    # without a maintain_order kwarg, which unique doesn't expose -- sort before comparing)
    r_last = sort(unique(df, ["a"]; keep = :last), col("a"))
    @test size(r_last) == (3, 3)
    @test r_last[:a] == [1, 2, 3]
    @test r_last[:val] == [20, 40, 50]  # last occurrence of each a value

    # unique on multi-column subset
    r_multi = sort(unique(df, ["a", "b"]; keep = :first), col("a"))
    @test size(r_multi) == (3, 3)  # (1,x), (2,y), (3,z)
    @test r_multi[:a] == [1, 2, 3]
    @test r_multi[:b] == ["x", "y", "z"]
end

@testset "n_unique" begin
    df = DataFrame(
        (;
            x = [1, 1, 2, 2, 3],
            y = ["a", "a", "b", "b", "c"],
        )
    )

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
    df = DataFrame(
        (;
            a = [1, 1, 2, 3, 3],
            b = ["x", "x", "y", "z", "z"],
        )
    )

    # is_unique on column 'a'
    r_unique = select(df, is_unique(col("a")) |> alias("is_unique_a"))
    @test r_unique[:is_unique_a] == [false, false, true, false, false]

    # is_duplicated on column 'a'
    r_dup = select(df, is_duplicated(col("a")) |> alias("is_dup_a"))
    @test r_dup[:is_dup_a] == [true, true, false, true, true]

    # is_unique on multi-column subset: is_unique takes a single Expr, so combine columns
    # via as_struct first (matches (a,b) pair uniqueness)
    r_unique_multi = select(df, is_unique(as_struct(col("a"), col("b"))) |> alias("is_unique_pair"))
    @test r_unique_multi[:is_unique_pair] == [false, false, true, false, false]
end

# TODO: approx_n_unique not exposed in Polars.jl (no such function in src/), see plans/test_porting.md
# TODO: unique_counts not exposed in Polars.jl (no such function in src/), see plans/test_porting.md
