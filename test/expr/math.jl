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
end

@testset "log / exp / sqrt / sign / %" begin
    df = DataFrame((; x = [1.0, 4.0, 9.0]))

    r = select(
        df, alias(Base.log(col("x"), lit(2.0)), "log2"),
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
