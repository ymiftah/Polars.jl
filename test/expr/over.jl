@testset "over" begin
    df = DataFrame((; g = ["a", "a", "b", "b", "b"], x = [1, 2, 10, 20, 30]))

    r = collect(with_columns(lazy(df), alias(over(Polars.sum(col("x")), "g"), "group_sum")))
    @test r[:group_sum] == [3, 3, 60, 60, 60]

    # Expr-valued partition columns behave the same as string column names
    r_expr = collect(with_columns(lazy(df), alias(over(Polars.sum(col("x")), col("g")), "group_sum")))
    @test r_expr[:group_sum] == r[:group_sum]

    # multi-column partition
    df2 = DataFrame((; g = ["a", "a", "b", "b"], h = ["x", "y", "x", "y"], v = [1, 2, 3, 40]))
    r2 = collect(with_columns(lazy(df2), alias(over(Polars.sum(col("v")), "g", "h"), "s")))
    @test r2[:s] == [1, 2, 3, 40] # each (g, h) pair is unique here, so the partition sum is itself

    df3 = DataFrame((; g = ["a", "a", "a"], v = [1, 2, 3]))
    r3 = collect(with_columns(lazy(df3), alias(over(Polars.sum(col("v")), "g", "g"), "s")))
    @test r3[:s] == [6, 6, 6] # duplicate partition columns collapse to the same grouping
end
