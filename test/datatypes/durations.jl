# `Dt.total_*` Duration-decomposition family -- see `plans/definitive_guide_gap_closure.md`'s
# Phase 5. There is no direct `arrowvector` construction path for a Duration column (unlike
# `Date`/`Dates.Time`/`DateTime`), so every Duration column here is built the same way the
# existing "Time cast" testset in `times.jl` builds a Time column: cast an `Int64` column via
# `cast(col(...), Dates.Nanosecond|Microsecond|Millisecond)`.

@testset "Dt.total_*: nanosecond resolution, both fractional values, negative durations" begin
    # 1s, 1.5s, -1s, -1.5s, 0s -- picked so integer truncation direction (toward zero, not floor)
    # is unambiguous for the negative fractional cases (confirmed live before writing these
    # assertions, not assumed: -1.5s truncates to -1, not -2).
    ns = Int64[1_000_000_000, 1_500_000_000, -1_000_000_000, -1_500_000_000, 0]
    df = select(DataFrame((; n = ns)), cast(col("n"), Dates.Nanosecond) |> alias("d"))

    @test collect(select(df, Dt.total_seconds(col("d")) |> alias("x"))[:x]) == [1, 1, -1, -1, 0]
    @test collect(select(df, Dt.total_seconds(col("d"); fractional = true) |> alias("x"))[:x]) ==
        [1.0, 1.5, -1.0, -1.5, 0.0]

    @test collect(select(df, Dt.total_milliseconds(col("d")) |> alias("x"))[:x]) ==
        [1000, 1500, -1000, -1500, 0]
    @test collect(select(df, Dt.total_microseconds(col("d")) |> alias("x"))[:x]) ==
        [1_000_000, 1_500_000, -1_000_000, -1_500_000, 0]
    @test collect(select(df, Dt.total_nanoseconds(col("d")) |> alias("x"))[:x]) == ns

    # Sub-unit durations truncate to 0 in the coarser units.
    @test collect(select(df, Dt.total_minutes(col("d")) |> alias("x"))[:x]) == [0, 0, 0, 0, 0]
    @test collect(select(df, Dt.total_hours(col("d")) |> alias("x"))[:x]) == [0, 0, 0, 0, 0]
    @test collect(select(df, Dt.total_days(col("d")) |> alias("x"))[:x]) == [0, 0, 0, 0, 0]

    # Curried form, matching the rest of Dt's own convention.
    @test collect(select(df, col("d") |> Dt.total_seconds(fractional = true) |> alias("x"))[:x]) ==
        [1.0, 1.5, -1.0, -1.5, 0.0]
end

@testset "Dt.total_*: millisecond and microsecond source resolution (resolution-correct, not just resolution-dependent)" begin
    ms = Int64[1000, 1500, -500]
    ms_df = select(DataFrame((; n = ms)), cast(col("n"), Dates.Millisecond) |> alias("d"))
    @test eltype(ms_df[:d]) == Dates.Millisecond
    @test collect(select(ms_df, Dt.total_seconds(col("d")) |> alias("x"))[:x]) == [1, 1, 0]
    @test collect(select(ms_df, Dt.total_milliseconds(col("d")) |> alias("x"))[:x]) == ms
    @test collect(select(ms_df, Dt.total_microseconds(col("d")) |> alias("x"))[:x]) ==
        [1_000_000, 1_500_000, -500_000]
    @test collect(select(ms_df, Dt.total_nanoseconds(col("d")) |> alias("x"))[:x]) ==
        [1_000_000_000, 1_500_000_000, -500_000_000]

    us = Int64[1_000_000, 1_500_000, -500_000]
    us_df = select(DataFrame((; n = us)), cast(col("n"), Dates.Microsecond) |> alias("d"))
    @test eltype(us_df[:d]) == Dates.Microsecond
    @test collect(select(us_df, Dt.total_seconds(col("d")) |> alias("x"))[:x]) == [1, 1, 0]
    @test collect(select(us_df, Dt.total_milliseconds(col("d")) |> alias("x"))[:x]) == [1000, 1500, -500]
    @test collect(select(us_df, Dt.total_microseconds(col("d")) |> alias("x"))[:x]) == us
end

@testset "Dt.total_*: empty frame and null Duration entry" begin
    empty_df = select(DataFrame((; n = Int64[])), cast(col("n"), Dates.Nanosecond) |> alias("d"))
    @test isempty(collect(select(empty_df, Dt.total_seconds(col("d")) |> alias("x"))[:x]))

    n = Vector{Union{Missing, Int64}}([1_000_000_000, missing])
    null_df = select(DataFrame((; n = n)), cast(col("n"), Dates.Nanosecond) |> alias("d"))
    out = collect(select(null_df, Dt.total_seconds(col("d")) |> alias("x"))[:x])
    @test isequal(out, [1, missing])
end

@testset "Duration sort/join (polars-ops gather over Duration)" begin
    # Direct Duration-column template of `times.jl`'s own "Time sort/join (polars-ops gather over
    # Time)" testset -- both exercise polars-ops' `take_chunked_unchecked`, which has a
    # `#[cfg(feature = "dtype-duration")]`-gated `Duration` arm falling through to
    # `_ => unreachable!()` (a process abort, not a catchable error) if that feature were ever
    # off. Unlike `dtype-time` historically, `dtype-duration` was confirmed (via
    # `cargo tree -e features -i polars-ops` and the actual build fingerprints, not just the
    # declared `features = [...]` list) to already be transitively active before this task's
    # Cargo.toml change -- it's part of `dtype-slim`, itself part of the `polars` crate's own
    # `default` features. Kept as an explicit regression guard regardless.
    ns = Int64[500, 100, 300, 200]
    df = select(DataFrame((; n = ns, i = collect(1:4))), cast(col("n"), Dates.Nanosecond) |> alias("d"), col("i"))
    durations = collect(df[:d])

    @test collect(sort(df, "d")[:d]) == sort(durations)
    @test collect(sort(df, "d"; rev = true)[:d]) == sort(durations; rev = true)

    a = select(
        DataFrame((; n = Int64[100, 200], v = [10, 20])),
        cast(col("n"), Dates.Nanosecond) |> alias("d"), col("v")
    )
    b = select(
        DataFrame((; n = Int64[200, 100], w = ["x", "y"])),
        cast(col("n"), Dates.Nanosecond) |> alias("d"), col("w")
    )
    j = sort(innerjoin(a, b, "d"), "d")
    @test collect(j[:d]) == [Dates.Nanosecond(100), Dates.Nanosecond(200)]
    @test collect(j[:w]) == ["y", "x"]
end
