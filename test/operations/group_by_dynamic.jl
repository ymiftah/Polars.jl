@testset "group_by_dynamic" begin
    lf = lazy(hourly_store_df())

    # basic daily bucketing
    r1 = group_by_dynamic(lf, "time"; every = "1d") |>
        x -> agg(x, Polars.sum(col("value"))) |>
        collect
    @test size(r1) == (1, 2)
    @test r1[:time] == [DateTime(2024, 1, 1)]
    @test r1[:value] == [sum(1:24)]

    # extra group-by key
    r2 = group_by_dynamic(lf, "time", ["store"]; every = "12h") |>
        x -> agg(x, Polars.sum(col("value"))) |>
        collect
    by_store_window = Dict((r2[:store][i], r2[:time][i]) => r2[:value][i] for i in eachindex(r2[:store]))
    @test by_store_window[("a", DateTime(2024, 1, 1, 0))] == sum(1:2:12)
    @test by_store_window[("a", DateTime(2024, 1, 1, 12))] == sum(13:2:24)
    @test by_store_window[("b", DateTime(2024, 1, 1, 0))] == sum(2:2:12)
    @test by_store_window[("b", DateTime(2024, 1, 1, 12))] == sum(14:2:24)

    # rolling
    r3 = rolling(lf, "time"; period = "3h") |>
        x -> agg(x, Polars.sum(col("value"))) |>
        collect
    @test size(r3) == (24, 2)
    @test r3[:value][1] == sum(2:4)
end
