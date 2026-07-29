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

@testset "std / var / max / min / median / quantile against fruits_cars_df (py-polars test_std/test_var/test_max/test_min/test_median/test_quantile)" begin
    # upstream's own fixture is literally `fruits_cars_df()`'s `A` column ([1,2,3,4,5]) -- reused
    # rather than reinvented, pinning upstream's exact numeric answers as a regression floor.
    df = fruits_cars_df()

    @test only(select(df, alias(Polars.std(col("A")), "s"))[:s]) ≈ 1.5811388300841898
    @test only(select(df, alias(Polars.var(col("A")), "v"))[:v]) ≈ 2.5
    @test only(select(df, alias(Polars.max(col("A")), "m"))[:m]) == 5
    @test only(select(df, alias(Polars.min(col("A")), "m"))[:m]) == 1
    @test only(select(df, alias(median(col("A")), "m"))[:m]) == 3.0

    for (q, m, expected) in (
            (0.25, :nearest, 2), (0.24, :lower, 1), (0.26, :higher, 3),
            (0.24, :midpoint, 1.5), (0.24, :linear, 1.96),
        )
        @test only(select(df, alias(Polars.quantile(col("A"), q; method = m), "q"))[:q]) ≈ expected
    end
end
