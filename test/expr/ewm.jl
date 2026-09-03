# py-polars/tests/unit/operations/test_ewm.py

@testset "ewm_mean: alpha/com parameterization, adjust true/false (py-polars test_ewm_mean)" begin
    df = DataFrame((; x = [2, 5, 3]))

    r = select(df, alias(ewm_mean(col("x"); alpha = 0.5, adjust = true), "r"))
    @test r[:r] ≈ [2.0, 4.0, 3.4285714285714284]

    # ignore_nulls makes no difference on null-free input
    r2 = select(df, alias(ewm_mean(col("x"); alpha = 0.5, adjust = true, ignore_nulls = false), "r"))
    @test r2[:r] ≈ r[:r]

    r_com = select(df, alias(ewm_mean(col("x"); com = 2.0, adjust = true), "r"))
    @test r_com[:r] ≈ [2.0, 3.8, 3.421053] atol = 1.0e-6

    r_noadjust = select(df, alias(ewm_mean(col("x"); alpha = 0.5, adjust = false), "r"))
    @test r_noadjust[:r] ≈ [2.0, 3.5, 3.25]
end

@testset "ewm_mean: min_samples (py-polars test_ewm_mean)" begin
    df = DataFrame((; x = [2, 3, 5, 7, 4]))

    r2 = select(df, alias(ewm_mean(col("x"); alpha = 0.5, min_samples = 2), "r"))
    @test approx_or_missing(r2[:r], [missing, 2.6666666666666665, 4.0, 5.6, 4.774193548387097])

    r3 = select(df, alias(ewm_mean(col("x"); alpha = 0.5, min_samples = 3), "r"))
    @test approx_or_missing(r3[:r], [missing, missing, 4.0, 5.6, 4.774193548387097])
end

@testset "ewm_mean: null propagation, ignore_nulls true/false (py-polars test_ewm_mean)" begin
    df = DataFrame((; x = Union{Float64, Missing}[missing, 1.0, 5.0, 7.0, missing, 2.0, 5.0, 4.0]))

    r_ignore = select(df, alias(ewm_mean(col("x"); alpha = 0.5, ignore_nulls = true), "r"))
    @test approx_or_missing(
        r_ignore[:r],
        [
            missing, 1.0, 3.6666666666666665, 5.571428571428571, missing,
            3.6666666666666665, 4.354838709677419, 4.174603174603175,
        ]
    )

    r_noignore = select(df, alias(ewm_mean(col("x"); alpha = 0.5, ignore_nulls = false), "r"))
    @test approx_or_missing(
        r_noignore[:r],
        [
            missing, 1.0, 3.666666666666667, 5.571428571428571, missing,
            3.08695652173913, 4.2, 4.092436974789916,
        ]
    )

    r_noadjust_ignore = select(df, alias(ewm_mean(col("x"); alpha = 0.5, adjust = false, ignore_nulls = true), "r"))
    @test approx_or_missing(r_noadjust_ignore[:r], [missing, 1.0, 3.0, 5.0, missing, 3.5, 4.25, 4.125])

    r_noadjust_noignore = select(df, alias(ewm_mean(col("x"); alpha = 0.5, adjust = false, ignore_nulls = false), "r"))
    @test approx_or_missing(r_noadjust_noignore[:r], [missing, 1.0, 3.0, 5.0, missing, 3.0, 4.0, 4.0])
end

@testset "ewm_mean: leading nulls, min_samples interaction (py-polars test_ewm_mean_leading_nulls / test_ewm_mean_min_samples)" begin
    for min_samples in (1, 2, 3)
        df = DataFrame((; x = [1, 2, 3, 4]))
        r = select(df, alias(ewm_mean(col("x"); com = 3, min_samples, ignore_nulls = false), "r"))
        @test count(ismissing, r[:r]) == min_samples - 1
    end

    df_leading = DataFrame((; x = Union{Float64, Missing}[missing, 1.0, 1.0, 1.0]))
    r1 = select(df_leading, alias(ewm_mean(col("x"); alpha = 0.5, min_samples = 1, ignore_nulls = true), "r"))
    @test isequal(r1[:r], [missing, 1.0, 1.0, 1.0])

    r2 = select(df_leading, alias(ewm_mean(col("x"); alpha = 0.5, min_samples = 2, ignore_nulls = true), "r"))
    @test isequal(r2[:r], [missing, missing, 1.0, 1.0])

    df_gaps = DataFrame((; x = Union{Float64, Missing}[1.0, missing, 2.0, missing, 3.0]))
    r3 = select(df_gaps, alias(ewm_mean(col("x"); alpha = 0.5, min_samples = 1, ignore_nulls = true), "r"))
    @test approx_or_missing(r3[:r], [1.0, missing, 1.6666666666666665, missing, 2.4285714285714284])

    r4 = select(df_gaps, alias(ewm_mean(col("x"); alpha = 0.5, min_samples = 2, ignore_nulls = true), "r"))
    @test approx_or_missing(r4[:r], [missing, missing, 1.6666666666666665, missing, 2.4285714285714284])
end

@testset "ewm_std / ewm_var: relationship and value (py-polars test_ewm_std_var)" begin
    df = DataFrame((; a = [2, 5, 3]))

    r_var = select(df, alias(ewm_var(col("a"); alpha = 0.5, ignore_nulls = false), "v"))
    r_std = select(df, alias(ewm_std(col("a"); alpha = 0.5, ignore_nulls = false), "s"))
    # first element is null, not 0.0 -- the unbiased (sample) variance of one observation is
    # undefined (polars-compute 0.55: cov.rs no longer special-cases non_null_count == 1 to 0.0)
    @test approx_or_missing(r_var[:v], [missing, 4.5, 1.9285714285714284])
    @test approx_or_missing(r_std[:s] .^ 2, r_var[:v])
end

@testset "ewm_std / ewm_var: with nulls, ignore_nulls true/false (py-polars test_ewm_std_var_with_nulls)" begin
    df = DataFrame((; a = Union{Float64, Missing}[2, 5, missing, 3]))

    r_var_ignore = select(df, alias(ewm_var(col("a"); alpha = 0.5, ignore_nulls = true), "v"))
    r_std_ignore = select(df, alias(ewm_std(col("a"); alpha = 0.5, ignore_nulls = true), "s"))
    @test approx_or_missing(r_var_ignore[:v], [missing, 4.5, missing, 1.9285714285714284])
    @test approx_or_missing(r_std_ignore[:s] .^ 2, r_var_ignore[:v])

    r_var_noignore = select(df, alias(ewm_var(col("a"); alpha = 0.5, ignore_nulls = false), "v"))
    r_std_noignore = select(df, alias(ewm_std(col("a"); alpha = 0.5, ignore_nulls = false), "s"))
    @test approx_or_missing(r_var_noignore[:v], [missing, 4.5, missing, 1.7307692307692313])
    @test approx_or_missing(r_std_noignore[:s] .^ 2, r_var_noignore[:v])
end

@testset "ewm parameter validation (py-polars test_ewm_param_validation)" begin
    df = DataFrame((; x = collect(0:9)))

    # exactly one of com/span/half_life/alpha
    @test_throws ErrorException ewm_std(col("x"); com = 0.5, alpha = 0.5)
    @test_throws ErrorException ewm_mean(col("x"); span = 1.5, half_life = 0.75)
    @test_throws ErrorException ewm_var(col("x"); alpha = 0.5, span = 1.5)
    @test_throws ErrorException ewm_mean(col("x"))

    # domain validation
    @test_throws ErrorException ewm_std(col("x"); com = -0.5)
    @test_throws ErrorException ewm_mean(col("x"); span = 0.5)
    @test_throws ErrorException ewm_var(col("x"); half_life = 0)

    for bad_alpha in (-0.5, -0.0000001, 0.0, 1.0000001, 1.5)
        @test_throws ErrorException ewm_std(col("x"); alpha = bad_alpha)
    end
end

@testset "ewm_mean curried form" begin
    df = DataFrame((; x = [2, 5, 3]))
    r_direct = select(df, alias(ewm_mean(col("x"); alpha = 0.5), "r"))
    r_curried = select(df, alias(col("x") |> ewm_mean(; alpha = 0.5), "r"))
    @test r_direct[:r] == r_curried[:r]
end
