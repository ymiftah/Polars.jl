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
