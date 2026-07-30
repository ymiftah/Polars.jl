using StatsBase

@testset "StatsBase extension" begin
    @test Base.get_extension(Polars, :PolarsStatsBaseExt) !== nothing

    # upstream test_skew / test_kurtosis fixture
    df = DataFrame((; x = [1.0, 2.0, 3.0, 2.0, 2.0, 3.0, 0.0]))
    val(e) = only(select(df, alias(e, "r"))[:r])

    # StatsBase owns `kurtosis`/`skewness` (they are not re-exports of Statistics'), so these are
    # methods added to StatsBase's own generics -- reaching the same implementation as the
    # Polars-qualified calls
    @test val(StatsBase.kurtosis(col("x"))) == val(Polars.kurtosis(col("x")))
    @test val(StatsBase.skewness(col("x"))) == val(Polars.skew(col("x")))

    # keywords pass through
    @test val(StatsBase.kurtosis(col("x"); fisher = false)) ==
        val(Polars.kurtosis(col("x"); fisher = false))
    @test val(StatsBase.skewness(col("x"); bias = false)) ==
        val(Polars.skew(col("x"); bias = false))

    # StatsBase's own vector methods are unaffected
    @test StatsBase.kurtosis([1.0, 2.0, 3.0, 2.0, 2.0, 3.0, 0.0]) ≈ val(Polars.kurtosis(col("x")))
end
