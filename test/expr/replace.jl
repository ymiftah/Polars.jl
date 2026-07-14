@testset "replace" begin
    df = DataFrame((; x = ["a", "b", "c", "d"]))

    r = select(df, alias(Base.replace(col("x"), lit("a"), lit("A")), "r"))
    @test r[:r] == ["A", "b", "c", "d"]

    # values not found in `old` are left unchanged
    r2 = select(df, alias(Base.replace(col("x"), lit("z"), lit("Z")), "r"))
    @test r2[:r] == df[:x]
end

@testset "replace_strict" begin
    df = DataFrame((; x = ["a", "b", "c", "d"]))

    # without a default, an incomplete mapping errors (matches upstream polars semantics)
    @test_throws ErrorException select(df, replace_strict(col("x"), lit("a"), lit("A")))

    # unmapped values fall back to `default`
    r = select(df, alias(replace_strict(col("x"), lit("a"), lit("A"); default = lit("?")), "r"))
    @test r[:r] == ["A", "?", "?", "?"]
end
