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

@testset "rolling with offset and closed variants" begin
    lf = lazy(hourly_store_df())

    # Test closed parameter variants
    for closed_val in [:left, :right, :both, :none]
        r = rolling(lf, "time"; period = "3h", closed = closed_val) |>
            x -> agg(x, Polars.count(col("value"))) |>
            collect
        # Just verify it runs and produces a result
        @test size(r, 1) > 0
        @test size(r, 2) == 2
    end

    # Test offset parameter variants (positive and negative durations)
    for offset_str in ["0ns", "1h", "-1h"]
        r = rolling(lf, "time"; period = "3h", offset = offset_str) |>
            x -> agg(x, Polars.count(col("value"))) |>
            collect
        @test size(r, 1) > 0
        @test size(r, 2) == 2
    end

    # Test combination of offset and closed
    r = rolling(lf, "time"; period = "3h", offset = "1h", closed = :both) |>
        x -> agg(x, Polars.count(col("value"))) |>
        collect
    @test size(r, 1) > 0
end

@testset "group_by_dynamic with kwarg variants" begin
    lf = lazy(hourly_store_df())

    # Test closed parameter variants
    for closed_val in [:left, :right, :both, :none]
        r = group_by_dynamic(lf, "time"; every = "6h", closed = closed_val) |>
            x -> agg(x, Polars.count(col("value"))) |>
            collect
        @test size(r, 1) > 0
        @test size(r, 2) == 2
    end

    # Test label parameter variants
    for label_val in [:left, :right, :data_point]
        r = group_by_dynamic(lf, "time"; every = "6h", label = label_val) |>
            x -> agg(x, Polars.count(col("value"))) |>
            collect
        @test size(r, 1) > 0
        @test size(r, 2) == 2
    end

    # Test include_boundaries parameter
    r_with_boundaries = group_by_dynamic(lf, "time"; every = "6h", include_boundaries = true) |>
        x -> agg(x, Polars.count(col("value"))) |>
        collect
    r_without_boundaries = group_by_dynamic(lf, "time"; every = "6h", include_boundaries = false) |>
        x -> agg(x, Polars.count(col("value"))) |>
        collect
    @test size(r_with_boundaries, 1) > 0
    @test size(r_without_boundaries, 1) > 0

    # Test start_by parameter variants
    for start_by_val in [:window_bound, :data_point, :monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday]
        r = group_by_dynamic(lf, "time"; every = "1d", start_by = start_by_val) |>
            x -> agg(x, Polars.count(col("value"))) |>
            collect
        @test size(r, 1) > 0
        @test size(r, 2) == 2
    end
end
