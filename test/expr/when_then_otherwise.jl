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

@testset "chained multi-condition when (via nesting)" begin
    # when(cond, then, otherwise) is a strict 3-arg function -- no chained .when().then()
    # builder syntax exists (confirmed: no such method anywhere in src/expr/expr.jl). Multiple
    # conditions are emulated by nesting when() calls in the otherwise position, matching how
    # Python's chained when().then().when().then().otherwise() is idiomatically ported here.
    df = DataFrame((; x = [1, 2, 3, 4, 5]))

    r = select(
        df, alias(
            when(
                col("x") == 1, "one",
                when(col("x") == 2, "two", when(col("x") == 3, "three", "other"))
            ), "label"
        )
    )
    @test r[:label] == ["one", "two", "three", "other", "other"]
end

@testset "explicit missing as otherwise" begin
    # otherwise is a required positional arg (no default) -- passing missing explicitly hits
    # the Missing convert overload and produces a proper null column
    df = DataFrame((; x = [1, 2, 3, 4, 5]))

    r = select(df, alias(when(col("x") .> 2, 100, missing), "f"))
    @test isequal(collect(r[:f]), [missing, missing, 100, 100, 100])
    @test eltype(r[:f]) == Union{Missing, Int64}
end
