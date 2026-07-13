@testset "scan_parquet" begin
    dir = mktempdir()
    write_parquet(
        joinpath(mkpath(joinpath(dir, "year=2023")), "part.parquet"),
        DataFrame((; category = ["a", "b", "a", "b"], amount = [10, 20, 30, 40]))
    )
    write_parquet(
        joinpath(mkpath(joinpath(dir, "year=2024")), "part.parquet"),
        DataFrame((; category = ["a", "b", "a", "b"], amount = [100, 200, 300, 400]))
    )

    lf = scan_parquet(dir)
    @test lf isa Polars.LazyFrame

    all_rows = collect(lf)
    @test size(all_rows) == (8, 3)
    @test Set(all_rows[:year]) == Set([2023, 2024])

    result = lf |>
        x -> filter(x, col("year") == 2024) |>
        x -> group_by(x, "category") |>
        x -> agg(x, Polars.sum(col("amount"))) |>
        collect

    by_category = Dict(zip(result[:category], result[:amount]))
    @test by_category["a"] == 400
    @test by_category["b"] == 600
end
