@testset "lit(::Vector)" begin
    # scalar lit still works (regression check)
    df = DataFrame((; x = [1, 2, 3, 4]))
    @test collect(select(df, alias(col("x") .> lit(2), "gt2"))[:gt2]) == [false, false, true, true]

    # is_in against a flat list literal: the recommended, non-deprecated form wraps the literal
    # in implode() to disambiguate row-wise membership from elementwise broadcast (polars itself
    # emits a deprecation warning for the bare `is_in(col, lit(vector))` form as of this version)
    r1 = filter(df, is_in(col("x"), implode(lit([2, 4]))))
    @test r1[:x] == [2, 4]

    # replace has no such ambiguity -- plain lit(::Vector) is used directly
    df2 = DataFrame((; x = ["a", "b", "c", "d"]))
    r2 = select(df2, alias(Base.replace(col("x"), lit(["a", "c"]), lit(["A", "C"])), "r"))
    @test r2[:r] == ["A", "b", "C", "d"]

    # broader element-type coverage
    df3 = DataFrame((; x = [1.5, 2.5, 3.5]))
    r3 = filter(df3, is_in(col("x"), implode(lit([1.5, 3.5]))))
    @test r3[:x] == [1.5, 3.5]

    df4 = DataFrame((; x = ["a", "b", "c"]))
    r4 = filter(df4, is_in(col("x"), implode(lit(["b", "c"]))))
    @test r4[:x] == ["b", "c"]

    # Union{Missing,T} vectors round-trip through the literal correctly
    r5 = select(DataFrame((; a = [1])), alias(implode(lit(Union{Int, Missing}[1, missing, 3])), "v"))
    @test isequal(collect(only(r5[:v])), [1, missing, 3])
end
