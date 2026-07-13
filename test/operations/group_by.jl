@testset "group_by" begin
    lf = lazy(fruits_cars_df())

    # single key
    result = group_by(lf, "fruits") |> x -> agg(x, Polars.sum(col("A"))) |> collect
    by_fruit = Dict(zip(result[:fruits], result[:A]))
    @test by_fruit["banana"] == 1 + 2 + 5
    @test by_fruit["apple"] == 3 + 4

    # multi-key grouping
    result2 = group_by(lf, "fruits", "cars") |>
        x -> agg(x, Polars.sum(col("A")) |> alias("sumA")) |>
        collect
    by_pair = Dict(zip(zip(result2[:fruits], result2[:cars]), result2[:sumA]))
    @test by_pair[("banana", "beetle")] == 1 + 5
    @test by_pair[("banana", "audi")] == 2
    @test by_pair[("apple", "beetle")] == 3 + 4

    # multiple aggregations in one agg call
    result3 = group_by(lf, "fruits") |>
        x -> agg(
        x, Polars.sum(col("A")) |> alias("sumA"),
        mean(col("B")) |> alias("meanB"),
        n_unique(col("cars")) |> alias("n_cars")
    ) |>
        collect
    by_fruit3 = Dict(
        result3[:fruits][i] =>
            (result3[:sumA][i], result3[:meanB][i], result3[:n_cars][i]) for i in eachindex(result3[:fruits])
    )
    @test by_fruit3["banana"] == (8, (5 + 4 + 1) / 3, 2)
    @test by_fruit3["apple"] == (7, (3 + 2) / 2, 1)

    # null key grouping
    df_null = DataFrame((; key = ["a", "a", missing, missing, "b"], value = [1, 2, 3, 4, 5]))
    result4 = group_by(lazy(df_null), "key") |> x -> agg(x, Polars.sum(col("value"))) |> collect
    by_key = Dict(zip(result4[:key], result4[:value]))
    @test by_key["a"] == 3
    @test by_key["b"] == 5
    @test by_key[missing] == 7
end
