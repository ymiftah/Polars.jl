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

    for closed_val in [:left, :right, :both, :none]
        r = rolling(lf, "time"; period = "3h", closed = closed_val) |>
            x -> agg(x, Polars.count(col("value"))) |>
            collect
        @test size(r)[1] > 0
        @test size(r)[2] == 2
    end

    for offset_str in ["0ns", "1h", "-1h"]
        r = rolling(lf, "time"; period = "3h", offset = offset_str) |>
            x -> agg(x, Polars.count(col("value"))) |>
            collect
        @test size(r)[1] > 0
        @test size(r)[2] == 2
    end

    r = rolling(lf, "time"; period = "3h", offset = "1h", closed = :both) |>
        x -> agg(x, Polars.count(col("value"))) |>
        collect
    @test size(r)[1] > 0
end

@testset "group_by_dynamic with kwarg variants" begin
    lf = lazy(hourly_store_df())

    for closed_val in [:left, :right, :both, :none]
        r = group_by_dynamic(lf, "time"; every = "6h", closed = closed_val) |>
            x -> agg(x, Polars.count(col("value"))) |>
            collect
        @test size(r)[1] > 0
        @test size(r)[2] == 2
    end

    for label_val in [:left, :right, :data_point]
        r = group_by_dynamic(lf, "time"; every = "6h", label = label_val) |>
            x -> agg(x, Polars.count(col("value"))) |>
            collect
        @test size(r)[1] > 0
        @test size(r)[2] == 2
    end

    r_with_boundaries = group_by_dynamic(lf, "time"; every = "6h", include_boundaries = true) |>
        x -> agg(x, Polars.count(col("value"))) |>
        collect
    r_without_boundaries = group_by_dynamic(lf, "time"; every = "6h", include_boundaries = false) |>
        x -> agg(x, Polars.count(col("value"))) |>
        collect
    @test size(r_with_boundaries)[1] > 0
    @test size(r_without_boundaries)[1] > 0

    for start_by_val in [:window_bound, :data_point, :monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday]
        r = group_by_dynamic(lf, "time"; every = "1d", start_by = start_by_val) |>
            x -> agg(x, Polars.count(col("value"))) |>
            collect
        @test size(r)[1] > 0
        @test size(r)[2] == 2
    end
end

@testset "group_by_dynamic/rolling duration strings survive GC pressure" begin
    # `every`/`period`/`offset` are passed to the FFI as raw (pointer, len) pairs, so the ccall
    # site must hold them in `GC.@preserve` -- nothing else roots them past their last "normal"
    # Julia-side use. Build them via `join`/`string` (not literals -- to defeat any accidental
    # string interning) and force collection *between* construction and the ccall to make an
    # unrooted string get freed if it can be.
    lf = lazy(hourly_store_df())

    every = join(["1", "d"])
    period = join(["3", "h"])
    offset = join(["0", "ns"])
    GC.gc(true)

    r1 = group_by_dynamic(lf, "time"; every) |>
        x -> agg(x, Polars.sum(col("value"))) |>
        collect
    @test size(r1) == (1, 2)

    r2 = rolling(lf, "time"; period, offset) |>
        x -> agg(x, Polars.count(col("value"))) |>
        collect
    @test size(r2)[1] > 0
end

@testset "group_by_dynamic abort-safety: negative every, and every/column-kind mismatch" begin
    # a non-positive `every` is a clean PolarsError, not a crash (py-polars test_group_by_dynamic_validation)
    df = DataFrame((; index = [0, 0, 1, 1], group = ["banana", "pear", "banana", "pear"], weight = [2, 3, 5, 7]))
    @test_throws PolarsError agg(
        group_by_dynamic(lazy(df), "index", ["group"]; every = "-1i", period = "2i"), col("weight")
    ) |> collect

    # a parsed-integer duration ("Ni") against a temporal column, and a calendar duration ("Nd")
    # against a plain integer column, are each the wrong convention for that column's kind --
    # both raise cleanly (the same domain-mismatch class `upsample` hits, see batch 10's
    # test/operations/frame_verbs.jl upsample testset) (py-polars test_group_by_dynamic_invalid)
    df_temporal = DataFrame((; values = [1, 4], times = [DateTime(2020, 1, 3), DateTime(2020, 1, 1)]))
    df_temporal_sorted = sort(df_temporal, col("times"))
    @test_throws PolarsError agg(
        group_by_dynamic(lazy(df_temporal_sorted), "times"; every = "3000i"),
        Base.sum(col("values")) |> alias("sum"),
    ) |> collect

    df_indexed = with_row_index(df_temporal)
    @test_throws PolarsError agg(
        group_by_dynamic(lazy(df_indexed), "index"; every = "3000d"),
        Base.sum(col("values")) |> alias("sum"),
    ) |> collect
end
