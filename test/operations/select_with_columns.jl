@testset "select" begin
    df = DataFrame((; x = [1, 2, 3], y = [10, 20, 30]))

    # subset + computed/renamed column
    sel = select(df, col("x"), (col("y") * 2) |> alias("y2"))
    @test Tables.columnnames(sel) == (:x, :y2)
    @test sel[:x] == [1, 2, 3]
    @test sel[:y2] == [20, 40, 60]

    # plain String column name shorthand
    sel_str = select(df, "x")
    @test Tables.columnnames(sel_str) == (:x,)

    # wildcard selects every column
    wildcard = select(df, col("*"))
    @test Tables.columnnames(wildcard) == (:x, :y)

    # LazyFrame form agrees
    sel_lazy = select(lazy(df), col("x")) |> collect
    @test sel_lazy[:x] == sel_str[:x]

    # selecting non-existent column raises error
    @test_throws ErrorException select(df, col("nonexistent"))

    # select with zero expressions returns empty DataFrame
    df_zero = select(df)
    @test size(df_zero) == (3, 0)
end

@testset "with_columns" begin
    df = DataFrame((; x = [1, 2, 3], y = [10, 20, 30]))

    wc = with_columns(df, (col("x") + col("y")) |> alias("total"))
    @test Tables.columnnames(wc) == (:x, :y, :total)
    @test wc[:total] == [11, 22, 33]

    # multiple expressions in one call
    wc2 = with_columns(df, (col("x") * 2) |> alias("x2"), (col("y") * 2) |> alias("y2"))
    @test Tables.columnnames(wc2) == (:x, :y, :x2, :y2)
    @test wc2[:x2] == [2, 4, 6]
    @test wc2[:y2] == [20, 40, 60]

    # LazyFrame form agrees
    wc_lazy = with_columns(lazy(df), (col("x") + col("y")) |> alias("total")) |> collect
    @test wc_lazy[:total] == wc[:total]

    # with_columns overwriting an existing column name
    wc_overwrite = with_columns(df, col("x") * 10 |> alias("x"))
    @test Tables.columnnames(wc_overwrite) == (:x, :y)
    @test wc_overwrite[:x] == [10, 20, 30]  # original x values multiplied by 10
    @test wc_overwrite[:y] == [10, 20, 30]  # y unchanged
end
