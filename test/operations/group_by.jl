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

    # empty frame group_by should return empty result
    df_empty = DataFrame((; key = String[], value = Int64[]))
    result_empty = group_by(lazy(df_empty), "key") |> x -> agg(x, Polars.sum(col("value"))) |> collect
    @test size(result_empty) == (0, 2)
end

@testset "group_by with additional agg scenarios" begin
    lf = lazy(DataFrame((;
        cat = ["A", "B", "A", "B", "A"],
        x = [1, 2, 3, 4, 5],
        y = [10.0, 20.0, 30.0, 40.0, 50.0]
    )))

    # Group by with multiple aggregation types
    result = group_by(lf, "cat") |>
        x -> agg(x,
            Polars.count(col("x")) |> alias("count"),
            Polars.sum(col("x")) |> alias("sum_x"),
            mean(col("y")) |> alias("mean_y"),
            max(col("x")) |> alias("max_x"),
            min(col("x")) |> alias("min_x")
        ) |> collect

    # Check aggregations for category A: [1, 3, 5] -> count=3, sum=9, mean_y=30, max=5, min=1
    a_row = findfirst(==(["A"]), [[result[:cat][i]] for i in 1:size(result)[1]])
    @test result[:count][a_row] == 3
    @test result[:sum_x][a_row] == 9
    @test result[:mean_y][a_row] == 30.0
    @test result[:max_x][a_row] == 5
    @test result[:min_x][a_row] == 1
end
