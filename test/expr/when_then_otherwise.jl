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
    # when(cond, then, otherwise) is a strict 3-arg function; multiple conditions can still be
    # emulated by nesting when() calls in the otherwise position (this predates and still works
    # alongside the native chained `when(pairs...; otherwise)` form tested below).
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

@testset "native chained when(pairs...; otherwise)" begin
    # the direct equivalent of py-polars' when(c1).then(v1).when(c2).then(v2)....otherwise(...)
    df = DataFrame((; x = [1, 2, 3, 4, 5]))

    r = select(
        df, alias(
            when(col("x") == 1 => "one", col("x") == 2 => "two", col("x") == 3 => "three"; otherwise = "other"),
            "label"
        )
    )
    @test r[:label] == ["one", "two", "three", "other", "other"]

    # agrees with the nested form above
    r_nested = select(
        df, alias(
            when(
                col("x") == 1, "one",
                when(col("x") == 2, "two", when(col("x") == 3, "three", "other"))
            ), "label"
        )
    )
    @test r[:label] == r_nested[:label]

    # zero pairs degenerates to `otherwise` unchanged (a sibling column keeps this from being a
    # bare unbroadcast literal select -- see the "lit" testset in literals_cast.jl)
    r_empty = select(df, col("x"), alias(when(; otherwise = "always"), "label"))
    @test r_empty[:label] == fill("always", 5)

    # a single pair matches the 3-arg when(cond, then, otherwise) form
    r_single = select(df, alias(when(col("x") == 1 => "one"; otherwise = "other"), "label"))
    r_single3 = select(df, alias(when(col("x") == 1, "one", "other"), "label"))
    @test r_single[:label] == r_single3[:label]

    # then-values and otherwise accept raw scalars, and cond can carry a null (selects otherwise)
    df_null = DataFrame((; x = [1, 2, missing, 4]))
    r_null = select(df_null, alias(when(col("x") == 1 => 100, col("x") == 2 => 200; otherwise = 0), "v"))
    @test r_null[:v] == [100, 200, 0, 0]
end

@testset "explicit missing as otherwise" begin
    # otherwise is a required positional arg (no default) -- passing missing explicitly hits
    # the Missing convert overload and produces a proper null column
    df = DataFrame((; x = [1, 2, 3, 4, 5]))

    r = select(df, alias(when(col("x") .> 2, 100, missing), "f"))
    @test isequal(collect(r[:f]), [missing, missing, 100, 100, 100])
    @test eltype(r[:f]) == Union{Missing, Int64}
end
