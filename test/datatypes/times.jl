@testset "Time dtype roundtrip" begin
    times = [Time(0, 0, 0), Time(1, 2, 3), Time(23, 59, 59, 999, 999, 999), Time(12, 30)]
    df = DataFrame((; t = times, i = collect(1:4)))

    @test eltype(df[:t]) == Time
    # nanosecond-exact: `Dates.value(t)` is the total ns since midnight, not the ns component
    @test collect(df[:t]) == times
    @test df[:t][3] == Time(23, 59, 59, 999, 999, 999)
end

@testset "Time with missing" begin
    times = Vector{Union{Missing, Time}}([Time(1, 0, 0), missing, Time(2, 0, 0)])
    df = DataFrame((; t = times))

    @test isequal(collect(df[:t]), times)
    @test ismissing(df[:t][2])
end

@testset "Time sort/join (polars-ops gather over Time)" begin
    # These exercise polars-ops' `take_chunked_unchecked`, whose Time arm is compiled out unless
    # the `dtype-time` feature is on -- falling through to `_ => unreachable!()`, i.e. a process
    # abort rather than a catchable error. See c-polars/Cargo.toml.
    times = [Time(0, 0, 0), Time(1, 2, 3), Time(23, 59), Time(12, 30)]
    df = DataFrame((; t = times, i = collect(1:4)))

    @test collect(sort(df, "t")[:t]) == sort(times)
    @test collect(sort(df, "t"; rev = true)[:t]) == sort(times; rev = true)

    a = DataFrame((; t = [Time(1, 0, 0), Time(2, 0, 0)], v = [10, 20]))
    b = DataFrame((; t = [Time(2, 0, 0), Time(1, 0, 0)], w = ["x", "y"]))
    j = sort(innerjoin(a, b, "t"), "t")
    @test collect(j[:t]) == [Time(1, 0, 0), Time(2, 0, 0)]
    @test collect(j[:w]) == ["y", "x"]
end

@testset "Time nested in list/struct (value materialization path)" begin
    times = [Time(0, 0, 0), Time(1, 2, 3), Time(23, 59, 59, 999, 999, 999)]
    df = DataFrame((; t = times, i = collect(1:3)))

    # struct field -> polars_value_time_get via load_value(::Value{Dates.Time})
    s = select(df, as_struct(col("t"), col("i")) |> alias("s"))
    @test collect(s[:s])[2].t == Time(1, 2, 3)

    # list element -> polars_value_list_type reports Time
    l = select(df, implode(col("t")) |> alias("l"))
    @test collect(collect(l[:l])[1]) == times
end

@testset "Time cast" begin
    # DataType::Time is always nanoseconds since midnight
    df = DataFrame((; n = Int64[3_723_000_000_000]))
    @test collect(select(df, cast(col("n"), Time) |> alias("t"))[:t]) == [Time(1, 2, 3)]

    # ...and back out to the physical integer
    tdf = DataFrame((; t = [Time(1, 2, 3)]))
    @test collect(select(tdf, cast(col("t"), Int64) |> alias("n"))[:n]) == [3_723_000_000_000]

    # out-of-range nanoseconds (negative, or >= 24h) -> missing, not an error. Upstream py-polars'
    # test_invalid_casts expects this to raise (its plain `.cast()` defaults to strict=True) --
    # our cast() always uses CastOptions::NonStrict (see plans/parity/batch-6-replace-whenthen-
    # cast.md's already-flagged "no strict cast option exposed" gap; this is the same root cause,
    # not a new one, so it's captured here as our own actual behavior rather than re-flagged).
    df_bad = DataFrame((; a = Int64[-1, 24 * 60 * 60 * 1_000_000_000]))
    r_bad = select(df_bad, alias(cast(col("a"), Time), "t"))
    @test all(ismissing, collect(r_bad[:t]))

    # the largest in-range value casts cleanly
    df_max = DataFrame((; a = Int64[24 * 60 * 60 * 1_000_000_000 - 1]))
    @test only(collect(select(df_max, alias(cast(col("a"), Time), "t"))[:t])) == Time(23, 59, 59, 999, 999, 999)
end

@testset "Dt.date / Dt.time: component extraction from Datetime" begin
    dts = [DateTime(2024, 3, 15, 10, 30, 45), DateTime(2023, 1, 1, 0, 0, 0)]
    df = DataFrame((; dt = dts))

    d = collect(select(df, Dt.date(col("dt")) |> alias("d"))[:d])
    @test d == Date.(dts)

    t = collect(select(df, Dt.time(col("dt")) |> alias("t"))[:t])
    @test t == Dates.Time.(dts)
end

@testset "Time file roundtrip" begin
    times = [Time(0, 0, 0), Time(1, 2, 3), Time(23, 59, 59, 999, 999, 999)]
    df = DataFrame((; t = times))

    mktempdir() do dir
        p = joinpath(dir, "t.parquet")
        write_parquet(p, df)
        @test collect(Polars.collect(scan_parquet(p))[:t]) == times

        ip = joinpath(dir, "t.arrow")
        write_ipc(ip, df)
        @test collect(Polars.collect(scan_ipc(ip))[:t]) == times
    end
end
