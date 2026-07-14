@testset "std / var" begin
    df = DataFrame((; x = [1.0, 2.0, 3.0]))

    r = select(df, Polars.std(col("x")) |> alias("s"), Polars.var(col("x")) |> alias("v"))
    @test only(r[:s]) == 1.0
    @test only(r[:v]) == 1.0

    r0 = select(df, Polars.std(col("x"); ddof = 0) |> alias("s0"), Polars.var(col("x"); ddof = 0) |> alias("v0"))
    @test only(r0[:s0]) ≈ sqrt(2 / 3)
    @test only(r0[:v0]) ≈ 2 / 3

    # a single-element group has undefined variance at the default ddof=1
    df_single = DataFrame((; x = [5.0]))
    r_single = select(df_single, Polars.std(col("x")) |> alias("s"))
    @test ismissing(only(r_single[:s]))
end

@testset "quantile" begin
    df = DataFrame((; x = [1.0, 2.0, 3.0, 4.0]))

    @test only(select(df, Polars.quantile(col("x"), 0.4; method = :nearest))[:x]) == 2.0
    @test only(select(df, Polars.quantile(col("x"), 0.4; method = :lower))[:x]) == 2.0
    @test only(select(df, Polars.quantile(col("x"), 0.4; method = :higher))[:x]) == 3.0
    @test only(select(df, Polars.quantile(col("x"), 0.4; method = :midpoint))[:x]) == 2.5
    @test only(select(df, Polars.quantile(col("x"), 0.4; method = :linear))[:x]) ≈ 2.2
    @test only(select(df, Polars.quantile(col("x"), 0.4; method = :equiprobable))[:x]) == 2.0

    # default method is :nearest
    @test only(select(df, Polars.quantile(col("x"), 0.5))[:x]) ==
          only(select(df, Polars.quantile(col("x"), 0.5; method = :nearest))[:x])

    @test_throws ErrorException Polars.quantile(col("x"), 0.5; method = :bogus)
end
