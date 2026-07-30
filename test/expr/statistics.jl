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

@testset "cov / cor" begin
    # upstream test_corr
    df = DataFrame((; a = [1, 2, 4], b = [-1, 23, 8]))
    r = select(df, Polars.cor(col("a"), col("b")) |> alias("c"))
    @test only(r[:c]) ≈ 0.18898223650461357

    # upstream test_correlation_cast_supertype -- mixed Int/Float must work
    df_mixed = DataFrame((; a = [1, 8, 3], b = [4.0, 5.0, 2.0]))
    r_mixed = select(df_mixed, Polars.cor(col("a"), col("b")) |> alias("c"))
    @test only(r_mixed[:c]) ≈ 0.5447047794019219

    # upstream test_corr_nan -- zero variance gives NaN, not an error or null
    df_const = DataFrame((; a = [1.0, 1.0], b = [1.0, 2.0]))
    r_const = select(df_const, Polars.cor(col("a"), col("b")) |> alias("c"))
    @test isnan(only(r_const[:c]))

    # upstream test_corr_cov_lit_produces_zero_nan_26633 -- constant literal against a column
    df_lit = DataFrame((; a = [1, 2, 3]))
    r_lit = select(df_lit, Polars.cov(lit(1), col("a")) |> alias("c"))
    @test only(r_lit[:c]) ≈ 0.0

    # ddof=0 (population) is smaller in magnitude than ddof=1 (sample) for the same data
    df_ddof = DataFrame((; a = [1.0, 2.0, 4.0], b = [-1.0, 23.0, 8.0]))
    r1 = select(df_ddof, Polars.cov(col("a"), col("b"); ddof = 1) |> alias("c"))
    r0 = select(df_ddof, Polars.cov(col("a"), col("b"); ddof = 0) |> alias("c"))
    @test abs(only(r0[:c])) < abs(only(r1[:c]))
end

@testset "spearman_rank_corr" begin
    # y = x^3 is monotonic but nonlinear: spearman is exactly 1.0, pearson is not
    df = DataFrame((; x = [1.0, 2.0, 3.0, 4.0], y = [1.0, 8.0, 27.0, 64.0]))
    r_spearman = select(df, spearman_rank_corr(col("x"), col("y")) |> alias("s"))
    r_pearson = select(df, Polars.cor(col("x"), col("y")) |> alias("p"))
    @test only(r_spearman[:s]) ≈ 1.0
    @test only(r_pearson[:p]) < 1.0

    # propagate_nans: true makes any NaN produce NaN; false (the default) ranks NaN above every
    # finite value instead, so a NaN at the largest position preserves the perfect rank correlation
    dn = DataFrame((; x = [1.0, 2.0, 3.0, NaN], y = [1.0, 8.0, 27.0, NaN]))
    @test isnan(only(select(dn, spearman_rank_corr(col("x"), col("y"); propagate_nans = true) |> alias("s"))[:s]))
    @test only(select(dn, spearman_rank_corr(col("x"), col("y")) |> alias("s"))[:s]) ≈ 1.0
end

@testset "skew (py-polars test_skew)" begin
    df = DataFrame((; a = [1, 2, 3, 2, 2, 3, 0]))

    @test only(select(df, alias(skew(col("a")), "s"))[:s]) ≈ -0.5953924651018018
    @test only(select(df, alias(skew(col("a"); bias = true), "s"))[:s]) ≈ -0.5953924651018018
    @test only(select(df, alias(skew(col("a"); bias = false), "s"))[:s]) ≈ -0.7717168360221258
end

@testset "kurtosis (py-polars test_kurtosis / test_kurtosis_same_vals)" begin
    df = DataFrame((; a = [1, 2, 3, 2, 2, 3, 0]))

    @test only(select(df, alias(kurtosis(col("a")), "k"))[:k]) ≈ -0.6406250000000004
    @test only(select(df, alias(kurtosis(col("a"); fisher = true, bias = true), "k"))[:k]) ≈ -0.6406250000000004

    # non-default fisher/bias combinations -- exercised, not just the default
    kf = only(select(df, alias(kurtosis(col("a"); fisher = false), "k"))[:k])
    kb = only(select(df, alias(kurtosis(col("a"); bias = false), "k"))[:k])
    @test kf ≈ only(select(df, alias(kurtosis(col("a")), "k"))[:k]) + 3.0
    @test kb != only(select(df, alias(kurtosis(col("a")), "k"))[:k])

    # constant input gives NaN, not an error
    df_const = DataFrame((; a = fill(1.0042855193121334, 11)))
    @test isnan(only(select(df_const, alias(kurtosis(col("a")), "k"))[:k]))
end
