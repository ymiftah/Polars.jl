@testset "shift / pct_change" begin
    df = DataFrame((; x = [1, 2, 4, 10, 20]))

    r = select(df, alias(shift(col("x"), lit(1)), "sh"), alias(pct_change(col("x"), lit(1)), "pc"))
    @test isequal(r[:sh], [missing, 1, 2, 4, 10])
    @test isequal(r[:pc], [missing, 1.0, 1.0, 1.5, 1.0])
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

@testset "order/window ops compose with over()" begin
    df = DataFrame((; g = ["a", "a", "a", "b", "b"], x = [1, 2, 4, 10, 20]))

    r = collect(with_columns(lazy(df), alias(over(cum_sum(col("x")), "g"), "cs")))
    @test r[:cs] == [1, 3, 7, 10, 30]
end
