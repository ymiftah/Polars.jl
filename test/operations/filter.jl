@testset "filter" begin
    df = DataFrame((; x = [1, 2, 3, 3.1, missing]))

    @test filter(df, col("x") >= 2) |> size == (3, 1)
    @test filter(df, col("x") > 2) |> size == (2, 1)
    @test filter(df, col("x") == 2) |> size == (1, 1)

    @test filter(df, col("x") |> is_null) |> size == (1, 1)
    @test filter(df, col("x") |> is_null |> Polars.not) |> size == (4, 1)

    # LazyFrame form agrees
    @test filter(lazy(df), col("x") >= 2) |> collect |> size == (3, 1)
end
