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

@testset "Dt.truncate / Dt.round with different duration strings" begin
    df = DataFrame((; dt = [DateTime(2024, 1, 1, 5, 30, 45), DateTime(2024, 1, 1, 14, 45, 30)]))

    # Test different duration units for truncate
    for duration in ["1h", "2h", "1d", "1w"]
        r_trunc = select(df, alias(Dt.truncate(col("dt"), lit(duration)), "trunc"))
        @test size(r_trunc) == (2, 1)  # Should work for all durations
    end

    # Test different duration units for round
    for duration in ["1h", "6h", "1d"]
        r_round = select(df, alias(Dt.round(col("dt"), lit(duration)), "round"))
        @test size(r_round) == (2, 1)  # Should work for all durations
    end

    # Test offset_by with various duration strings
    r_offset_1d = select(df, alias(Dt.offset_by(col("dt"), lit("1d")), "offset_1d"))
    @test r_offset_1d[:offset_1d][1] == DateTime(2024, 1, 2, 5, 30, 45)

    r_offset_1h = select(df, alias(Dt.offset_by(col("dt"), lit("1h")), "offset_1h"))
    @test r_offset_1h[:offset_1h][1] == DateTime(2024, 1, 1, 6, 30, 45)
end

@testset "Dt.strftime with various formats" begin
    df = DataFrame((; dt = DateTime(2024, 1, 15, 9, 30, 45)))

    # Test various format strings
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
