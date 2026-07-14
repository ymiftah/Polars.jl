@testset "scan_csv / read_csv / write_csv" begin
    df = DataFrame((; category = ["a", "b", "a", "b"], amount = [10, 20, 30, 40]))
    path = write_temp_csv(df)

    lf = scan_csv(path)
    @test lf isa Polars.LazyFrame

    all_rows = collect(lf)
    @test size(all_rows) == (4, 2)
    @test all_rows[:category] == df[:category]
    @test all_rows[:amount] == df[:amount]

    # read_csv is the eager entry point (collect ∘ scan_csv)
    eager = read_csv(path)
    @test eager isa Polars.DataFrame
    @test eager[:category] == df[:category]
    @test eager[:amount] == df[:amount]

    result = lf |>
        x -> group_by(x, "category") |>
        x -> agg(x, Polars.sum(col("amount"))) |>
        collect

    by_category = Dict(zip(result[:category], result[:amount]))
    @test by_category["a"] == 40
    @test by_category["b"] == 60
end
