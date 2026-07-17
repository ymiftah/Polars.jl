@testset "empty/edge cases" begin
    df = DataFrame((; x = [1, 2, 3], g = ["a", "b", "c"]))

    # filter producing zero rows keeps the column count and allows column access
    empty_df = filter(df, col("x") > 100)
    @test size(empty_df) == (0, 2)
    @test empty_df[:x] == Int[]
    @test empty_df[:g] == String[]

    # group_by over zero rows
    gb_empty = group_by(lazy(empty_df), "g") |> x -> agg(x, Polars.sum(col("x"))) |> collect
    @test size(gb_empty) == (0, 2)

    # selecting zero expressions
    zero_col = select(df, Polars.Expr[])
    @test size(zero_col) == (0, 0)
end
