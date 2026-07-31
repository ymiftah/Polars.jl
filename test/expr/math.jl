@testset "round / clip" begin
    df = DataFrame((; x = [1.234, -1.234, 2.5, -2.5]))

    r = select(df, alias(Base.round(col("x"), 1), "r1"))
    @test r[:r1] ≈ [1.2, -1.2, 2.5, -2.5]

    r0 = select(df, alias(Base.round(col("x")), "r0"))
    @test r0[:r0] ≈ [1.0, -1.0, 2.0, -2.0] # :half_to_even (banker's rounding)

    df_ties = DataFrame((; x = [2.5, -2.5]))
    r_away = select(df_ties, alias(Base.round(col("x"); mode = :half_away_from_zero), "r"))
    @test r_away[:r] ≈ [3.0, -3.0]

    @test_throws ErrorException Base.round(col("x"); mode = :bogus)

    df2 = DataFrame((; x = [1.0, 5.0, 10.0]))
    r_clip = select(df2, alias(clip(col("x"), lit(2.0), lit(8.0)), "c"))
    @test r_clip[:c] == [2.0, 5.0, 8.0]

    # round on an integer column is a no-op (py-polars test_round_int)
    df_int = DataFrame((; x = [1, 2, 3]))
    r_int = select(df_int, alias(Base.round(col("x")), "r"))
    @test r_int[:r] == [1, 2, 3]

    # clip: a null bound (per-row, not a scalar) passes that side through unclamped -- upstream
    # test_clip_int's exact fixture, including its own missing/mixed-bound rows
    df_clip_null = DataFrame(
        (;
            a = [1, 2, 3, 4, 5, missing],
            mn = [0, -1, 4, missing, 4, -10],
            mx = [2, 1, 8, 5, missing, 10],
        )
    )
    r_clip_null = select(df_clip_null, alias(clip(col("a"), col("mn"), col("mx")), "clip"))
    @test isequal(collect(r_clip_null[:clip]), [1, 1, 4, 4, 5, missing])
end

@testset "log / exp / sqrt / sign / %" begin
    df = DataFrame((; x = [1.0, 4.0, 9.0]))

    r = select(
        df, alias(Base.log(lit(2.0), col("x")), "log2"),
        alias(Polars.exp(col("x")), "exp"),
        alias(Base.sqrt(col("x")), "sqrt"),
        alias(Polars.sign(col("x") .- 4.0), "sign")
    )
    @test r[:log2] ≈ log2.([1.0, 4.0, 9.0])
    @test r[:exp] ≈ exp.([1.0, 4.0, 9.0])
    @test r[:sqrt] ≈ [1.0, 2.0, 3.0]
    @test r[:sign] == [-1.0, 0.0, 1.0]

    df2 = DataFrame((; x = [7, 8, 9, 10]))
    r2 = select(df2, alias(col("x") % lit(3), "m"))
    @test r2[:m] == [1, 2, 0, 1]
end

@testset "sqrt / log / abs domain edges and wrong-dtype (py-polars test_sqrt_neg_inf, test_log_exp, test_abs_non_numeric)" begin
    # sqrt of negative -> NaN, sqrt(0) -> 0, sqrt(Inf) -> Inf -- upstream's exact fixture
    df_sqrt = DataFrame((; val = [-Inf, -9.0, 0.0, 9.0, Inf]))
    r_sqrt = select(df_sqrt, alias(Base.sqrt(col("val")), "sqrt"))
    out_sqrt = collect(r_sqrt[:sqrt])
    @test isnan(out_sqrt[1]) && isnan(out_sqrt[2])
    @test out_sqrt[3] == 0.0 && out_sqrt[4] == 3.0 && isinf(out_sqrt[5]) && out_sqrt[5] > 0

    # log domain edges: log(0) -> -Inf, log(negative) -> NaN (base e via lit(exp(1.0)); note the
    # base comes first, matching Base.log(b, x) -- see CLAUDE.md's `@generate_expr_fns` note)
    df_log = DataFrame((; x = [0.0, -1.0, exp(1.0)]))
    r_log = select(df_log, alias(Base.log(lit(exp(1.0)), col("x")), "ln"))
    out_log = collect(r_log[:ln])
    @test isinf(out_log[1]) && out_log[1] < 0
    @test isnan(out_log[2])
    @test out_log[3] ≈ 1.0

    # abs: missing propagates, non-numeric (String) raises a clean PolarsError rather than
    # aborting the process (Step 5 -- process-abort check, see CLAUDE.md)
    df_abs = DataFrame((; a = [-1, 0, 1, missing]))
    r_abs = select(df_abs, alias(abs(col("a")), "a"))
    @test isequal(collect(r_abs[:a]), [1, 0, 1, missing])

    df_abs_str = DataFrame((; a = ["p", "q", "r"]))
    @test_throws PolarsError select(df_abs_str, alias(abs(col("a")), "a"))
end

@testset "is_between (py-polars test_is_between / test_is_between_data_types)" begin
    # upstream fixture is fruits_cars_df()'s A column, [1, 2, 3, 4, 5]
    df = fruits_cars_df()

    r = select(df, alias(is_between(col("A"), 2, 4), "b"))
    @test r[:b] == [false, true, true, true, false]

    r = select(df, alias(is_between(col("A"), 2, 4; closed = :both), "b"))
    @test r[:b] == [false, true, true, true, false]

    r = select(df, alias(is_between(col("A"), 2, 4; closed = :none), "b"))
    @test r[:b] == [false, false, true, false, false]

    r = select(df, alias(is_between(col("A"), 2, 4; closed = :left), "b"))
    @test r[:b] == [false, true, true, false, false]

    r = select(df, alias(is_between(col("A"), 2, 4; closed = :right), "b"))
    @test r[:b] == [false, false, true, true, false]

    @test_throws ErrorException is_between(col("A"), 2, 4; closed = :bogus)

    # non-numeric bounds: strings and dates must not be silently numeric-only
    df_types = DataFrame(
        (;
            flt = [1.4, 1.2, 2.5],
            str = ["xyz", "str", "abc"],
            dt = [Date(2020, 1, 1), Date(2020, 2, 2), Date(2020, 3, 3)],
        )
    )
    r_flt = select(df_types, alias(is_between(col("flt"), 1, 2.3), "b"))
    @test r_flt[:b] == [true, true, false]

    r_str = select(df_types, alias(is_between(col("str"), "aaa", "s"), "b"))
    @test r_str[:b] == [false, false, true]

    r_dt = select(df_types, alias(is_between(col("dt"), Date(2020, 1, 15), Date(2020, 3, 1)), "b"))
    @test r_dt[:b] == [false, true, false]
end
