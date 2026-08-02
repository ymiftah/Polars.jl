@testset "shift / pct_change" begin
    df = DataFrame((; x = [1, 2, 4, 10, 20]))

    r = select(df, alias(shift(col("x"), lit(1)), "sh"), alias(pct_change(col("x"), lit(1)), "pc"))
    @test isequal(r[:sh], [missing, 1, 2, 4, 10])
    @test isequal(r[:pc], [missing, 1.0, 1.0, 1.5, 1.0])
end

@testset "shift_and_fill: like shift, but vacated positions get a value instead of missing (see plans/parity/gap_closure_scope.md)" begin
    df = DataFrame((; x = [1, 2, 3]))

    r = select(df, alias(shift_and_fill(col("x"), 1, 99), "sh"))
    @test collect(r[:sh]) == [99, 1, 2]

    # negative n shifts the other direction
    r_neg = select(df, alias(shift_and_fill(col("x"), -1, 99), "sh"))
    @test collect(r_neg[:sh]) == [2, 3, 99]
end

@testset "cumulative aggregates" begin
    df = DataFrame((; x = [1, 2, 4, 10, 20]))

    r = select(
        df, alias(cum_sum(col("x")), "cs"), alias(cum_prod(col("x")), "cp"),
        alias(cum_min(col("x")), "cmn"), alias(cum_max(col("x")), "cmx"),
        alias(cum_count(col("x")), "cc")
    )
    @test r[:cs] == [1, 3, 7, 17, 37]
    @test r[:cp] == [1, 2, 8, 80, 1600]
    @test r[:cmn] == [1, 1, 1, 1, 1]
    @test r[:cmx] == [1, 2, 4, 10, 20]
    @test r[:cc] == [1, 2, 3, 4, 5]

    r_rev = select(df, alias(cum_sum(col("x"); reverse = true), "cs_rev"))
    @test r_rev[:cs_rev] == [37, 36, 34, 30, 20]
end

@testset "cum_count with nulls: nulls don't increment the running count (py-polars test_cum_count_single_arg)" begin
    df = DataFrame((; a = Union{Missing, Int}[5, 5, missing]))
    r = select(df, alias(cum_count(col("a")), "c"), alias(cum_count(col("a"); reverse = true), "cr"))
    @test collect(r[:c]) == [1, 2, 2]
    @test collect(r[:cr]) == [2, 1, 0]
end

@testset "diff" begin
    df = DataFrame((; x = [1, 2, 4, 10, 20]))

    r = select(df, alias(diff(col("x"), lit(1)), "d"))
    @test isequal(r[:d], [missing, 1, 2, 6, 10])

    # :drop shortens the result instead of padding with null
    r_drop = select(df, alias(diff(col("x"), lit(1); null_behavior = :drop), "d"))
    @test r_drop[:d] == [1, 2, 6, 10]

    @test_throws ErrorException diff(col("x"), lit(1); null_behavior = :bogus)
end

@testset "rank" begin
    df = DataFrame((; x = [3, 1, 4, 1, 5]))

    r = select(
        df, alias(rank(col("x")), "dense"), alias(rank(col("x"); method = :ordinal), "ordinal"),
        alias(rank(col("x"); method = :min), "min"), alias(rank(col("x"); method = :max), "max"),
        alias(rank(col("x"); method = :average), "average"),
        alias(rank(col("x"); descending = true), "descending")
    )
    @test r[:dense] == [2, 1, 3, 1, 4]
    @test r[:ordinal] == [3, 1, 4, 2, 5]
    @test r[:min] == [3, 1, 4, 1, 5]
    @test r[:max] == [3, 2, 4, 2, 5]
    @test r[:average] == [3.0, 1.5, 4.0, 1.5, 5.0]
    @test r[:descending] == [3, 4, 2, 4, 1]

    @test_throws ErrorException rank(col("x"); method = :bogus)
end

@testset "rank on empty/all-null input: nulls stay null, aren't ranked (py-polars test_rank_nulls)" begin
    @test isempty(collect(select(DataFrame((; x = Int[])), alias(rank(col("x")), "r"))[:r]))

    r1 = select(DataFrame((; x = Union{Missing, Int}[missing])), alias(rank(col("x")), "r"))
    @test isequal(collect(r1[:r]), [missing])

    r2 = select(DataFrame((; x = Union{Missing, Int}[missing, missing])), alias(rank(col("x")), "r"))
    @test isequal(collect(r2[:r]), [missing, missing])
end

@testset "order/window ops compose with over()" begin
    df = DataFrame((; g = ["a", "a", "a", "b", "b"], x = [1, 2, 4, 10, 20]))

    r = collect(with_columns(lazy(df), alias(over(cum_sum(col("x")), "g"), "cs")))
    @test r[:cs] == [1, 3, 7, 10, 30]
end

@testset "rle / rle_id (API gap batch four, Phase 1; fixture mirrors py-polars' test_rle.py)" begin
    # Upstream's exact fixture (`test_rle`/`test_rle_id` in py-polars' test_rle.py): the value `1`
    # appears on *both sides* of a `null`, proving a null breaks a run rather than merging the two
    # separate runs of `1` into one.
    df = DataFrame((; a = [1, 1, 2, 1, missing, 1, 3, 3]))

    r = select(df, alias(rle(col("a")), "r"))
    struct_vals = collect(r[:r])
    @test [s.len for s in struct_vals] == UInt32[2, 1, 1, 1, 1, 2]
    @test isequal([s.value for s in struct_vals], [1, 2, 1, missing, 1, 3])

    r_id = select(df, alias(rle_id(col("a")), "id"))
    @test r_id[:id] == UInt32[0, 0, 1, 2, 3, 4, 5, 5]

    # test_empty_rle_21787: empty Int64 column -> both rle and rle_id produce empty results
    df_empty = DataFrame((; a = Int[]))
    r_empty = select(df_empty, alias(rle(col("a")), "r"))
    @test isempty(collect(r_empty[:r]))
    r_empty_id = select(df_empty, alias(rle_id(col("a")), "id"))
    @test isempty(collect(r_empty_id[:id]))
end
