@testset "replace" begin
    df = DataFrame((; x = ["a", "b", "c", "d"]))

    r = select(df, alias(Base.replace(col("x"), lit("a"), lit("A")), "r"))
    @test r[:r] == ["A", "b", "c", "d"]

    # values not found in `old` are left unchanged
    r2 = select(df, alias(Base.replace(col("x"), lit("z"), lit("Z")), "r"))
    @test r2[:r] == df[:x]

    # multi-value mapping via lit(::Vector) (see test/expr/lit_vector.jl)
    r3 = select(df, alias(Base.replace(col("x"), lit(["a", "c"]), lit(["A", "C"])), "r"))
    @test r3[:r] == ["A", "b", "C", "d"]
end

@testset "replace_strict" begin
    df = DataFrame((; x = ["a", "b", "c", "d"]))

    # without a default, an incomplete mapping errors (matches upstream polars semantics)
    @test_throws ErrorException select(df, replace_strict(col("x"), lit("a"), lit("A")))

    # unmapped values fall back to `default`
    r = select(df, alias(replace_strict(col("x"), lit("a"), lit("A"); default = lit("?")), "r"))
    @test r[:r] == ["A", "?", "?", "?"]
end

@testset "coalesce edge cases" begin
    # All-null row: coalesce should return null
    df_null = DataFrame((;
        a = Union{Int64, Missing}[missing, 2, 3],
        b = Union{Int64, Missing}[missing, missing, 30],
        c = Union{Int64, Missing}[missing, missing, missing]
    ))
    r_null = select(df_null, alias(Base.coalesce(col("a"), col("b"), col("c")), "result"))
    @test ismissing(r_null[:result][1])
    @test r_null[:result][2] == 2
    @test r_null[:result][3] == 30

    # More than 3 arguments
    df_many = DataFrame((;
        a = Union{Int64, Missing}[missing, missing, 3],
        b = Union{Int64, Missing}[missing, 2, missing],
        c = Union{Int64, Missing}[1, missing, missing]
    ))
    r_many = select(df_many, alias(Base.coalesce(col("a"), col("b"), col("c")), "result"))
    @test r_many[:result] == [1, 2, 3]

    # Single argument (coalesce of single col is identity for non-null, null for null)
    df_single = DataFrame((; x = Union{Int64, Missing}[1, missing, 3]))
    r_single = select(df_single, alias(Base.coalesce(col("x")), "result"))
    @test isequal(r_single[:result], df_single[:x])
end
