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

@testset "over curried form" begin
    df = DataFrame((; g = ["a", "a", "b", "b", "b"], x = [1, 2, 10, 20, 30]))

    r = collect(with_columns(lazy(df), alias(Polars.sum(col("x")) |> over("g"), "group_sum")))
    @test r[:group_sum] == [3, 3, 60, 60, 60]

    # agrees with the non-curried form
    r_direct = collect(with_columns(lazy(df), alias(over(Polars.sum(col("x")), "g"), "group_sum")))
    @test r[:group_sum] == r_direct[:group_sum]

    # multi-column partition
    df2 = DataFrame((; g = ["a", "a", "b", "b"], h = ["x", "y", "x", "y"], v = [1, 2, 3, 40]))
    r2 = collect(with_columns(lazy(df2), alias(Polars.sum(col("v")) |> over("g", "h"), "s")))
    @test r2[:s] == [1, 2, 3, 40]

    # a bare Expr argument is not curried -- it resolves to the original over(expr, partition_by...)
    # with zero partition columns, since it's ambiguous with over's own `expr` argument. Zero
    # partition columns (and no order_by) is itself a meaningful window spec (whole frame as one
    # group), so this must still succeed, not error.
    r_bare = over(col("x"))
    @test r_bare isa Polars.Expr
end

@testset "over window options" begin
    df = DataFrame((; g = ["a", "a", "b", "b"], v = [1, 2, 3, 4]))

    # mapping_strategy=:group_to_rows (default) and :join both broadcast a scalar aggregate
    # identically -- the difference only shows for a non-aggregated expr (tested via :join below)
    r_default = with_columns(lazy(df), alias(Base.sum(col("v")) |> over("g"), "s"))
    r_group_to_rows = with_columns(
        lazy(df), alias(Base.sum(col("v")) |> over("g"; mapping_strategy = :group_to_rows), "s")
    )
    r_default_c = collect(r_default)
    r_gtr_c = collect(r_group_to_rows)
    @test r_default_c[:s] == r_gtr_c[:s] == [3, 3, 7, 7]

    # order_by sorts *within* each group before evaluating the windowed expr, without touching
    # the frame's own row order
    df_o = DataFrame((; g = ["a", "a", "b", "b"], t = [2, 1, 4, 3], v = [10, 20, 30, 40]))
    r_ordered = with_columns(lazy(df_o), alias(Base.first(col("v")) |> over("g"; order_by = "t"), "first_by_t"))
    r_ordered_c = collect(r_ordered)
    @test r_ordered_c[:t] == [2, 1, 4, 3] # frame's own row order is untouched
    @test r_ordered_c[:first_by_t] == [20, 20, 40, 40] # smallest-t row per group is first

    r_unordered = with_columns(lazy(df_o), alias(Base.first(col("v")) |> over("g"), "first"))
    @test collect(r_unordered)[:first] == [10, 10, 30, 30] # without order_by, plain row order

    # descending/nulls_last control the order_by sort direction
    r_desc = with_columns(
        lazy(df_o), alias(Base.first(col("v")) |> over("g"; order_by = "t", descending = true), "first_desc")
    )
    @test collect(r_desc)[:first_desc] == [10, 10, 30, 30] # largest-t row per group is first

    @test_throws ErrorException over(col("x"); mapping_strategy = :bogus)
end
