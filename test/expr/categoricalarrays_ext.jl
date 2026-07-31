using CategoricalArrays

@testset "CategoricalArrays extension" begin
    @test Base.get_extension(Polars, :PolarsCategoricalArraysExt) !== nothing

    # upstream test_cut fixture
    df = DataFrame((; a = [-2.0, -1.0, 0.0, 1.0, 2.0]))
    vals(e) = collect(select(df, alias(e, "r"))[:r])

    # `cut` is unexported here, so with CategoricalArrays loaded the bare name is its generic --
    # this method dispatches an Expr back to this package, reaching the same implementation
    @test vals(cut(col("a"), [-1.0, 1.0])) == vals(Polars.cut(col("a"), [-1.0, 1.0]))

    # keywords pass through
    @test vals(cut(col("a"), [-1.0, 1.0]; labels = ["lo", "mid", "hi"])) ==
        vals(Polars.cut(col("a"), [-1.0, 1.0]; labels = ["lo", "mid", "hi"]))
    @test vals(cut(col("a"), [-1.0, 1.0]; left_closed = true)) ==
        vals(Polars.cut(col("a"), [-1.0, 1.0]; left_closed = true))

    # CategoricalArrays' own vector method is unaffected
    @test cut([-2.0, 0.0, 2.0], [-Inf, 0.0, Inf]) isa AbstractVector
end
