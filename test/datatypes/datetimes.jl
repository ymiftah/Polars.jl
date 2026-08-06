@testset "Dt namespace" begin
    df = hourly_store_df() # time: 2024-01-01T00:00 .. 2024-01-01T23:00, hourly (Monday)

    r = select(
        df, alias(Dt.year(col("time")), "y"),
        alias(Dt.month(col("time")), "mo"),
        alias(Dt.day(col("time")), "d"),
        alias(Dt.hour(col("time")), "h"),
        alias(Dt.minute(col("time")), "mi"),
        alias(Dt.second(col("time")), "s"),
        alias(Dt.weekday(col("time")), "wd"),
        alias(Dt.ordinal_day(col("time")), "od")
    )
    @test all(==(2024), r[:y])
    @test all(==(1), r[:mo])
    @test all(==(1), r[:d])
    @test collect(r[:h]) == collect(0:23)
    @test all(==(0), r[:mi])
    @test all(==(0), r[:s])
    @test all(==(1), r[:wd]) # 2024-01-01 was a Monday
    @test all(==(1), r[:od])

    r2 = select(
        df, alias(Dt.truncate(col("time"), lit("6h")), "trunc"),
        alias(Dt.round(col("time"), lit("6h")), "round"),
        alias(Dt.offset_by(col("time"), lit("1d")), "offset"),
        alias(Dt.strftime(col("time"), "%Y-%m-%d %H:%M:%S"), "fmt")
    )
    @test r2[:trunc][1] == DateTime(2024, 1, 1, 0)
    @test r2[:trunc][8] == DateTime(2024, 1, 1, 6) # hour 7 truncates down to the 6h bucket
    @test r2[:round][1] == DateTime(2024, 1, 1, 0)
    @test r2[:round][4] == DateTime(2024, 1, 1, 6) # hour 3 rounds up to the 6h bucket
    @test r2[:offset][1] == DateTime(2024, 1, 2, 0)
    @test r2[:fmt][1] == "2024-01-01 00:00:00"
    @test r2[:fmt][13] == "2024-01-01 12:00:00"

    # nulls propagate through dt accessors on a Date column
    ks = kitchen_sink_df()
    r3 = select(ks, alias(Dt.year(col("date")), "y"), alias(Dt.month(col("date")), "mo"), alias(Dt.day(col("date")), "d"))
    @test isequal(r3[:y], [2024, 2024, 2024, missing])
    @test isequal(r3[:mo], [1, 1, 1, missing])
    @test isequal(r3[:d], [1, 2, 3, missing])
end

@testset "Dt.offset_by month-end clamps rather than overflows (py-polars test_date_offset_by)" begin
    df = DataFrame((; d = [Date(2020, 1, 31), Date(2020, 1, 1), Date(2020, 1, 2)]))
    r = select(df, alias(Dt.offset_by(col("d"), lit("1mo")), "o"))
    @test collect(r[:o]) == [Date(2020, 2, 29), Date(2020, 2, 1), Date(2020, 2, 2)]
end

@testset "Dt.truncate / Dt.round / Dt.offset_by null propagation" begin
    df = DataFrame((; t = Union{Missing, DateTime}[DateTime(2024, 1, 1, 5, 30), missing]))
    r = select(
        df, alias(Dt.truncate(col("t"), lit("1h")), "trunc"),
        alias(Dt.round(col("t"), lit("1h")), "round"),
        alias(Dt.offset_by(col("t"), lit("1d")), "off"),
    )
    @test isequal(collect(r[:trunc]), [DateTime(2024, 1, 1, 5), missing])
    @test isequal(collect(r[:round]), [DateTime(2024, 1, 1, 6), missing])
    @test isequal(collect(r[:off]), [DateTime(2024, 1, 2, 5, 30), missing])
end

@testset "Dt.truncate / Dt.round with different duration strings" begin
    df = DataFrame((; dt = [DateTime(2024, 1, 1, 5, 30, 45), DateTime(2024, 1, 1, 14, 45, 30)]))

    for duration in ["1h", "2h", "1d", "1w"]
        r_trunc = select(df, alias(Dt.truncate(col("dt"), lit(duration)), "trunc"))
        @test size(r_trunc) == (2, 1)
    end

    for duration in ["1h", "6h", "1d"]
        r_round = select(df, alias(Dt.round(col("dt"), lit(duration)), "round"))
        @test size(r_round) == (2, 1)
    end

    r_offset_1d = select(df, alias(Dt.offset_by(col("dt"), lit("1d")), "offset_1d"))
    @test r_offset_1d[:offset_1d][1] == DateTime(2024, 1, 2, 5, 30, 45)

    r_offset_1h = select(df, alias(Dt.offset_by(col("dt"), lit("1h")), "offset_1h"))
    @test r_offset_1h[:offset_1h][1] == DateTime(2024, 1, 1, 6, 30, 45)
end

@testset "Dt.week / Dt.quarter" begin
    df = DataFrame((; d = [Date(2022, 1, 1), Date(2022, 4, 1), Date(2022, 7, 1), Date(2022, 10, 1), Date(2024, 3, 15)]))
    r = select(df, alias(Dt.quarter(col("d")), "q"), alias(Dt.week(col("d")), "wk"))
    @test collect(r[:q]) == [1, 2, 3, 4, 1]
    @test r[:wk][5] == 11 # ISO week 11 for 2024-03-15

    # py-polars test_quarter: a whole monthly date range
    df2 = DataFrame((; d = [Date(2022, m, 1) for m in 1:12]))
    r2 = select(df2, alias(Dt.quarter(col("d")), "q"))
    @test collect(r2[:q]) == [1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4]

    # null propagation
    ks = kitchen_sink_df()
    r3 = select(ks, alias(Dt.week(col("date")), "wk"), alias(Dt.quarter(col("date")), "q"))
    @test ismissing(collect(r3[:wk])[4])
    @test ismissing(collect(r3[:q])[4])
end

@testset "Dt.timestamp / Dt.epoch (py-polars test_epoch_matches_timestamp)" begin
    df = DataFrame((; dt = [DateTime(2001, 1, 1), DateTime(2001, 2, 1, 10, 8, 9)]))

    for time_unit in (:ns, :us, :ms)
        r_ts = select(df, alias(Dt.timestamp(col("dt"); time_unit), "ts"))
        r_ep = select(df, alias(Dt.epoch(col("dt"), time_unit), "ep"))
        @test collect(r_ts[:ts]) == collect(r_ep[:ep])
    end

    # default time_unit is :us for both
    r_ts_default = select(df, alias(Dt.timestamp(col("dt")), "ts"))
    r_ts_us = select(df, alias(Dt.timestamp(col("dt"); time_unit = :us), "ts"))
    @test collect(r_ts_default[:ts]) == collect(r_ts_us[:ts])

    r_ep_default = select(df, alias(Dt.epoch(col("dt")), "ep"))
    @test collect(r_ep_default[:ep]) == collect(r_ts_us[:ts])

    # epoch(:s) == timestamp(:ms) floor-divided by 1000; epoch(:d) additionally casts to Int32
    r_s = select(df, alias(Dt.epoch(col("dt"), :s), "ep"))
    r_ms = select(df, alias(Dt.timestamp(col("dt"); time_unit = :ms), "ts"))
    @test collect(r_s[:ep]) == collect(r_ms[:ts]) .÷ 1000

    r_d = select(df, alias(Dt.epoch(col("dt"), :d), "ep"))
    @test collect(r_d[:ep]) == Int32.(collect(r_ms[:ts]) .÷ (1000 * 3600 * 24))

    # negative (pre-1970) timestamps must floor, not truncate, towards -Inf -- the reason
    # Dt.epoch uses floor_div internally rather than plain division
    df_pre1970 = DataFrame((; dt = [DateTime(1969, 12, 31, 23, 59, 59)]))
    r_pre = select(df_pre1970, alias(Dt.epoch(col("dt"), :s), "s"), alias(Dt.epoch(col("dt"), :d), "d"))
    @test collect(r_pre[:s]) == [-1]
    @test collect(r_pre[:d]) == Int32[-1]

    @test_throws ErrorException Dt.timestamp(col("dt"); time_unit = :bogus)
    @test_throws ErrorException Dt.epoch(col("dt"), :bogus)

    # curried forms for |> pipelines
    r_curried = select(df, alias(col("dt") |> Dt.timestamp(time_unit = :ms), "ts"))
    @test collect(r_curried[:ts]) == collect(r_ms[:ts])

    # null propagation
    ks = kitchen_sink_df()
    r_null = select(ks, alias(Dt.timestamp(col("datetime")), "ts"), alias(Dt.epoch(col("datetime")), "ep"))
    @test ismissing(collect(r_null[:ts])[3])
    @test ismissing(collect(r_null[:ep])[3])
end

@testset "Dt.month_start / Dt.month_end unavailable in this build (needs the month_start/month_end Cargo features)" begin
    df = DataFrame((; d = [Date(2024, 3, 15)]))
    @test_throws ErrorException Dt.month_start(col("d"))
    @test_throws ErrorException Dt.month_end(col("d"))
end

@testset "Dt.strftime with various formats" begin
    df = DataFrame((; dt = [DateTime(2024, 1, 15, 9, 30, 45)]))

    formats = [
        ("%Y-%m-%d", "2024-01-15"),
        ("%H:%M:%S", "09:30:45"),
        ("%Y/%m/%d %H:%M", "2024/01/15 09:30"),
        ("%B %d, %Y", "January 15, 2024"),  # full month name
    ]

    for (fmt, expected) in formats
        r = select(df, alias(Dt.strftime(col("dt"), fmt), "formatted"))
        @test r[:formatted][1] == expected
    end
end
