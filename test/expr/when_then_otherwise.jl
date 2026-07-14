@testset "when / then / otherwise" begin
    df = DataFrame((; x = [1, 2, 3, 4]))

    r = select(df, alias(when(col("x") .> 2, lit("hi"), lit("lo")), "f"))
    @test r[:f] == ["lo", "lo", "hi", "hi"]

    # then/otherwise accept raw scalars, promoted via convert(Expr, ...)
    r2 = select(df, alias(when(col("x") .> 2, "hi", "lo"), "f"))
    @test r2[:f] == r[:f]

    r3 = select(df, alias(when(col("x") .> 2, 100, 0), "f"))
    @test r3[:f] == [0, 0, 100, 100]

    # a null in the condition selects the otherwise branch (matches upstream polars semantics)
    df_null = DataFrame((; x = [1, 2, missing, 4]))
    r4 = select(df_null, alias(when(col("x") .> 2, 100, 0), "f"))
    @test r4[:f] == [0, 0, 0, 100]
end
