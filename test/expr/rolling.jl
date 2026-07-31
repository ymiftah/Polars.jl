@testset "rolling_min / rolling_max / rolling_sum / rolling_mean (py-polars test_rolling_ints)" begin
    df = DataFrame((; a = [1, 2, 3, 2, 1]))

    r = select(df, alias(rolling_min(col("a"), 2), "r"))
    @test isequal(r[:r], [missing, 1, 2, 2, 1])

    r = select(df, alias(rolling_max(col("a"), 2), "r"))
    @test isequal(r[:r], [missing, 2, 3, 3, 2])

    r = select(df, alias(rolling_sum(col("a"), 2), "r"))
    @test isequal(r[:r], [missing, 3, 5, 5, 3])

    r = select(df, alias(rolling_mean(col("a"), 2), "r"))
    @test approx_or_missing(r[:r], [missing, 1.5, 2.5, 2.5, 1.5])
end

@testset "rolling_std / rolling_var, incl. ddof (py-polars test_rolling_ints)" begin
    df = DataFrame((; a = [1, 2, 3, 2, 1]))

    r = select(df, alias(rolling_std(col("a"), 2), "r"))
    @test r[:r][2] ≈ 0.7071067811865476

    r = select(df, alias(rolling_var(col("a"), 2), "r"))
    @test r[:r][2] ≈ 0.5

    r = select(df, alias(rolling_std(col("a"), 2; ddof = 0), "r"))
    @test r[:r][2] ≈ 0.5

    r = select(df, alias(rolling_var(col("a"), 2; ddof = 0), "r"))
    @test r[:r][2] ≈ 0.25
end

@testset "rolling_std null handling (py-polars test_rolling_std_nulls_min_samples_1_20076)" begin
    df = DataFrame((; a = Union{Int, Missing}[1, 2, missing, 4]))

    r = select(df, alias(rolling_std(col("a"), 3; min_samples = 1), "r"))
    @test approx_or_missing(r[:r], [missing, 0.7071067811865476, 0.7071067811865476, 1.4142135623730951])
end

@testset "rolling_var / rolling_std stability on constant input (py-polars test_rolling_var_stability_12905)" begin
    df = DataFrame((; a = fill(36743.6, 10)))

    r = select(df, alias(rolling_var(col("a"), 12; min_samples = 2), "r"))
    @test sum(skipmissing(r[:r])) == 0.0

    r = select(df, alias(rolling_std(col("a"), 12; min_samples = 2), "r"))
    @test sum(skipmissing(r[:r])) == 0.0
end

@testset "min_samples defaults to window_size" begin
    df = DataFrame((; a = collect(1:10)))

    # default min_samples == window_size == 3, so the first 2 rows are null
    r = select(df, alias(rolling_sum(col("a"), 3), "r"))
    @test ismissing(r[:r][1]) && ismissing(r[:r][2]) && r[:r][3] == 6

    # min_samples = 1 relaxes that -- the first row already has a (partial) result
    r = select(df, alias(rolling_sum(col("a"), 3; min_samples = 1), "r"))
    @test r[:r][1] == 1 && r[:r][2] == 3 && r[:r][3] == 6
end

@testset "rolling_median / rolling_quantile (py-polars test_rolling_ints)" begin
    df = DataFrame((; a = Float64[1, 2, 3, 2, 1]))

    r = select(df, alias(rolling_median(col("a"), 4), "r"))
    @test isequal(collect(r[:r]), [missing, missing, missing, 2.0, 2.0])

    r = select(df, alias(rolling_quantile(col("a"), 3, 0.0; method = :nearest), "r"))
    @test isequal(collect(r[:r]), [missing, missing, 1.0, 2.0, 1.0])

    r = select(df, alias(rolling_quantile(col("a"), 3, 0.0; method = :lower), "r"))
    @test isequal(collect(r[:r]), [missing, missing, 1.0, 2.0, 1.0])

    r = select(df, alias(rolling_quantile(col("a"), 3, 0.0; method = :higher), "r"))
    @test isequal(collect(r[:r]), [missing, missing, 1.0, 2.0, 1.0])

    # rolling_median is exactly rolling_quantile(0.5, :linear) -- upstream documents this directly
    r_median = select(df, alias(rolling_median(col("a"), 3; min_samples = 1), "r"))
    r_quantile_linear = select(df, alias(rolling_quantile(col("a"), 3, 0.5; min_samples = 1, method = :linear), "r"))
    @test collect(r_median[:r]) == collect(r_quantile_linear[:r])

    @test_throws ErrorException rolling_quantile(col("a"), 3, 0.5; method = :bogus)

    # curried forms for |> pipelines
    r_curried_med = select(df, alias(col("a") |> rolling_median(3; min_samples = 1), "r"))
    @test collect(r_curried_med[:r]) == collect(r_median[:r])

    r_curried_quant = select(df, alias(col("a") |> rolling_quantile(3, 0.9; min_samples = 1), "r"))
    @test isequal(collect(r_curried_quant[:r]), [1.0, 2.0, 3.0, 3.0, 3.0])
end

@testset "center shifts the window (verified live, no upstream fixture in this file)" begin
    df = DataFrame((; a = collect(1.0:6.0)))

    # window_size=3, center=false (default): each result lands on the window's last row
    r = select(df, alias(rolling_min(col("a"), 3), "r"))
    @test isequal(r[:r], [missing, missing, 1.0, 2.0, 3.0, 4.0])

    # center=true: each result is instead labelled at the window's middle row
    r = select(df, alias(rolling_min(col("a"), 3; center = true), "r"))
    @test isequal(r[:r], [missing, 1.0, 2.0, 3.0, 4.0, missing])
end
