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

@testset "Dt.millisecond / Dt.microsecond / Dt.nanosecond (API gap audit quick-win batch)" begin
    # Each is the sub-second part of the timestamp expressed at that unit's own resolution (not a
    # decomposed digit group), so a 123ms sub-second component reads as 123/123_000/123_000_000 at
    # ms/us/ns resolution respectively -- mirroring the existing `total_milliseconds` family's
    # scaling convention. `Dates.DateTime` itself only carries millisecond precision, so the
    # microsecond/nanosecond values below are exact multiples of the millisecond value, not
    # independent sub-millisecond data.
    df = DataFrame((; ts = [DateTime(2024, 3, 15, 14, 30, 45, 123), DateTime(2024, 3, 15, 14, 30, 46, 0)]))
    r = select(
        df, alias(Dt.millisecond(col("ts")), "ms"),
        alias(Dt.microsecond(col("ts")), "us"),
        alias(Dt.nanosecond(col("ts")), "ns")
    )
    @test collect(r[:ms]) == [123, 0]
    @test collect(r[:us]) == [123_000, 0]
    @test collect(r[:ns]) == [123_000_000, 0]

    # null propagation -- `date` (a plain `Date`, no time-of-day) does not support these accessors
    # at all (`PolarsError: nanosecond operation not supported for dtype date`), so this uses the
    # `datetime` column, whose null sits at index 3.
    ks = kitchen_sink_df()
    r2 = select(
        ks, alias(Dt.millisecond(col("datetime")), "ms"), alias(Dt.microsecond(col("datetime")), "us"),
        alias(Dt.nanosecond(col("datetime")), "ns")
    )
    @test ismissing(collect(r2[:ms])[3])
    @test ismissing(collect(r2[:us])[3])
    @test ismissing(collect(r2[:ns])[3])
end

@testset "Dt.millisecond / Dt.microsecond / Dt.nanosecond: genuine sub-millisecond precision (py-polars test_temporal.py's nanosecond fixture)" begin
    # `Dates.DateTime` literals only carry millisecond precision, so the round-number fixture
    # above (123ms -> 123_000us -> 123_000_000ns) can't distinguish a correct scaling
    # implementation from one that's merely consistent at multiples of 1000. Upstream's own
    # fixture uses genuine microsecond-level values (555555, 986754, 123456), so this builds the
    # same precision here via an Int64-nanoseconds-since-epoch `cast_datetime(...; time_unit=:ns)`
    # instead, bypassing `DateTime`'s ms cap -- `datetime(2000, 1, 1, 1, 1, 1, 555555)` from
    # upstream's `test_data`, at whole-second boundaries so the microsecond count *is* the entire
    # sub-second part (matching upstream's `v.microsecond` semantics exactly, not an addition to
    # a nonzero millisecond).
    whole_seconds = [
        DateTime(2000, 1, 1, 1, 1, 1), DateTime(2024, 3, 15, 14, 30, 45),
    ]
    sub_second_us = [555555, 986754] # upstream's own values (test_temporal.py ~line 320)
    epoch = DateTime(1970, 1, 1)
    ns_since_epoch = [
        Dates.value(s - epoch) * 1_000_000 + us * 1000 for
            (s, us) in zip(whole_seconds, sub_second_us)
    ]
    df = DataFrame((; ns = ns_since_epoch))
    r = select(df, alias(cast_datetime(col("ns"); time_unit = :ns), "dtm"))
    r2 = select(
        r, alias(Dt.millisecond(col("dtm")), "ms"), alias(Dt.microsecond(col("dtm")), "us"),
        alias(Dt.nanosecond(col("dtm")), "ns")
    )
    @test collect(r2[:us]) == sub_second_us
    @test collect(r2[:ms]) == [us ÷ 1000 for us in sub_second_us] # upstream: v.microsecond // 1000
    @test collect(r2[:ns]) == [us * 1000 for us in sub_second_us] # upstream: v.microsecond * 1000
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

@testset "Dt.to_string: upstream's current name for Dt.strftime, same underlying binding (py-polars datatypes/test_temporal.py::test_temporal_to_string_iso_default, test_temporal_to_string_error, test_to_string_invalid_format, test_tz_aware_to_string)" begin
    dt_df = DataFrame((; dt = [DateTime(2024, 1, 15, 9, 30, 45)]))
    d_df = DataFrame((; d = [Date(2024, 1, 15), Date(2024, 6, 30)]))
    t_df = DataFrame((; t = [Time(10, 30, 15)]))

    # Datetime
    r_dt = select(dt_df, alias(Dt.to_string(col("dt"), "%Y-%m-%d %H:%M:%S"), "s"))
    @test r_dt[:s][1] == "2024-01-15 09:30:45"

    # Date
    r_d = select(d_df, alias(Dt.to_string(col("d"), "%Y/%m/%d"), "s"))
    @test r_d[:s] == ["2024/01/15", "2024/06/30"]

    # Time
    r_t = select(t_df, alias(Dt.to_string(col("t"), "%H:%M:%S"), "s"))
    @test r_t[:s][1] == "10:30:15"

    # a non-ASCII format string exercises the `ncodeunits`-not-`length` string-marshalling
    # convention: the literal characters in the format string pass through untouched, on both
    # sides of a chrono specifier
    r_unicode = select(d_df, alias(Dt.to_string(col("d"), "jour: %d héllo"), "s"))
    @test r_unicode[:s] == ["jour: 15 héllo", "jour: 30 héllo"]

    # agrees with Dt.strftime, since upstream defines strftime in terms of to_string -- confirmed
    # live against upstream's own Python source (`py-polars/src/polars/expr/datetime.py`):
    # `strftime` literally calls `self._pyexpr.dt_to_string(format)`, the same binding `to_string`
    # calls, so this package's shared `polars_expr_dt_strftime` binding for both is not a
    # simplification, it is exactly upstream's own architecture.
    r_strftime = select(dt_df, alias(Dt.strftime(col("dt"), "%Y-%m-%d %H:%M:%S"), "s"))
    @test r_dt[:s] == r_strftime[:s]

    # curried pipe form
    r_curry = select(d_df, alias(col("d") |> Dt.to_string("%Y/%m/%d"), "s"))
    @test r_curry[:s] == r_d[:s]

    # nulls propagate
    ks = kitchen_sink_df()
    r_null = select(ks, alias(Dt.to_string(col("date"), "%Y-%m-%d"), "s"))
    @test isequal(r_null[:s], ["2024-01-01", "2024-01-02", "2024-01-03", missing])

    # test_temporal_to_string_iso_default: the special sentinel format strings "iso"/"iso:strict"
    # are not chrono format strings -- they're recognized by name inside the same Rust dispatch and
    # pass straight through this package's binding unmodified
    dfdtm = DataFrame((; dtm = [DateTime(1980, 8, 10, 0, 10, 20), DateTime(2010, 10, 20, 8, 25, 35)]))
    r_iso = select(dfdtm, alias(Dt.to_string(col("dtm"), "iso"), "s"))
    r_iso_strict = select(dfdtm, alias(Dt.to_string(col("dtm"), "iso:strict"), "s"))
    @test r_iso[:s][1] == "1980-08-10 00:10:20.000000000" # this package's DateTime columns default to :ns precision
    @test r_iso_strict[:s][1] == "1980-08-10T00:10:20.000000000" # only the date/time separator differs
    @test occursin(" ", r_iso[:s][1]) && !occursin("T", r_iso[:s][1])
    @test occursin("T", r_iso_strict[:s][1])

    r_diso = select(d_df, alias(Dt.to_string(col("d"), "iso"), "s"))
    @test r_diso[:s] == ["2024-01-15", "2024-06-30"]

    # test_temporal_to_string_iso_default's "polars" format string (`td.dt.to_string("polars")`),
    # for a component-built Duration column (this package has no literal `timedelta` constructor,
    # so built via `duration`, this batch's other function under test)
    lfd = select(
        lazy(DataFrame((; x = [1]))),
        alias(
            duration(;
                days = [-1, 13, 0], seconds = [-42, 0, 0], hours = [0, 14, 0], microseconds = [0, 1001, 0],
            ), "td",
        ),
    )
    dfdur = collect(lfd)
    r_pl = select(dfdur, alias(Dt.to_string(col("td"), "polars"), "s"))
    @test r_pl[:s] == ["-1d -42s", "13d 14h 1001µs", "0µs"]
    r_iso_td = select(dfdur, alias(Dt.to_string(col("td"), "iso"), "s"))
    @test r_iso_td[:s] == ["-P1DT42S", "P13DT14H0.001001S", "PT0S"]

    # test_temporal_to_string_error: "polars" is not a valid to_string format for a non-Duration
    # dtype
    @test_throws PolarsError select(d_df, alias(Dt.to_string(col("d"), "polars"), "s"))

    # test_to_string_invalid_format: formatting a timezone-naive Datetime with a tz-dependent
    # chrono specifier (`%z`) raises cleanly
    @test_throws PolarsError select(dt_df, alias(Dt.to_string(col("dt"), "%z"), "s"))

    # this package's `to_string`/`strftime` require an explicit format argument -- there is no
    # zero-argument overload defaulting to `"iso"` the way upstream's `format: str | None = None`
    # does (Step 8 API divergence: not fixed here, a small independent addition)
    @test_throws MethodError Dt.to_string(col("d"))
end

@testset "Dt.iso_year / is_leap_year / century / millennium (py-polars test_dt_extract_datetime_component / test_iso_year / test_is_leap_year)" begin
    # upstream's `series_of_int_dates` fixture (day-since-epoch [8401, 10000, 20000, 30000]),
    # given here as the equivalent literal dates -- 1993-01-01 lands in ISO year **1992** (Jan 1
    # 1993 was a Friday, so it belongs to the last ISO week of the prior year), the one genuinely
    # tricky value in this fixture.
    dates = [Date(1993, 1, 1), Date(1997, 5, 19), Date(2024, 10, 4), Date(2052, 2, 20)]
    df = DataFrame((; d = dates))
    r = select(
        df, alias(Dt.millennium(col("d")), "mil"), alias(Dt.century(col("d")), "cen"),
        alias(Dt.iso_year(col("d")), "isoy")
    )
    @test collect(r[:mil]) == [2, 2, 3, 3]
    @test collect(r[:cen]) == [20, 20, 21, 21]
    @test collect(r[:isoy]) == [1992, 1997, 2024, 2052]

    # upstream additionally parametrizes this over a time zone (`Asia/Kathmandu`), checking these
    # local-component accessors are tz-invariant
    tz_col = Dt.replace_time_zone(cast_datetime(col("d")), "Asia/Kathmandu")
    r_tz = select(
        df, alias(Dt.millennium(tz_col), "mil"), alias(Dt.century(tz_col), "cen"),
        alias(Dt.iso_year(tz_col), "isoy")
    )
    @test collect(r_tz[:mil]) == collect(r[:mil])
    @test collect(r_tz[:cen]) == collect(r[:cen])
    @test collect(r_tz[:isoy]) == collect(r[:isoy])

    # upstream's `test_is_leap_year` ranges Jan-1 1990..2004 by 1y; ported as the equivalent
    # literal year list rather than via a (currently unwrapped) date range.
    leap_years_df = DataFrame((; d = [Date(y, 1, 1) for y in 1990:2004]))
    r_leap = select(leap_years_df, alias(Dt.is_leap_year(col("d")), "leap"))
    @test collect(r_leap[:leap]) ==
        [false, false, true, false, false, false, true, false, false, false, true, false, false, false, true]

    # null propagation
    ks = kitchen_sink_df()
    r_null = select(
        ks, alias(Dt.iso_year(col("datetime")), "isoy"), alias(Dt.is_leap_year(col("datetime")), "leap"),
        alias(Dt.century(col("datetime")), "cen"), alias(Dt.millennium(col("datetime")), "mil")
    )
    @test ismissing(collect(r_null[:isoy])[3])
    @test ismissing(collect(r_null[:leap])[3])
    @test ismissing(collect(r_null[:cen])[3])
    @test ismissing(collect(r_null[:mil])[3])
end

@testset "Dt.datetime (py-polars test_dt_datetime_deprecated)" begin
    # Deprecated upstream in favor of `replace_time_zone(expr, nothing)`, which it is exactly
    # equivalent to: strips a time-zone label back to naive, keeping the *wall-clock* value.
    df = DataFrame((; d = [DateTime(2022, 1, 1, 23)]))
    tz_col = Dt.replace_time_zone(col("d"), "Asia/Kathmandu")
    r = select(df, alias(Dt.datetime(tz_col), "stripped"))
    @test collect(r[:stripped]) == [DateTime(2022, 1, 1, 23)]
    @test eltype(collect(r[:stripped])) == DateTime # naive again, not a ZonedDateTime

    # on an already-naive column it's an identity op
    r_naive = select(df, alias(Dt.datetime(col("d")), "same"))
    @test collect(r_naive[:same]) == df[:d]
end

@testset "Dt.cast_time_unit / Dt.with_time_unit (Group 4 gap closure)" begin
    # `cast_time_unit` rescales the underlying integer; `with_time_unit` only relabels it. A
    # `Vector{DateTime}`-built column is natively `:ns` (see CLAUDE.md's literal-construction
    # note), so relabeling as `:ms` without rescaling reads the raw nanosecond count back out as
    # if it were already a millisecond count -- 1000x too large.
    df = DataFrame((; d = [DateTime(2024, 1, 15, 10, 0, 0, 123)]))

    r_ts_ms = select(df, alias(Dt.timestamp(col("d"); time_unit = :ms), "ts"))
    r_cast = select(
        df, alias(Dt.timestamp(Dt.cast_time_unit(col("d"); time_unit = :ms); time_unit = :ms), "ts")
    )
    @test collect(r_cast[:ts]) == collect(r_ts_ms[:ts])

    r_with = select(
        df, alias(Dt.timestamp(Dt.with_time_unit(col("d"); time_unit = :ms); time_unit = :ms), "ts")
    )
    r_ts_ns = select(df, alias(Dt.timestamp(col("d"); time_unit = :ns), "ts"))
    @test collect(r_with[:ts]) == collect(r_ts_ns[:ts]) # relabeled raw ns count read back as if ms

    @test_throws ErrorException Dt.cast_time_unit(col("d"); time_unit = :bogus)
    @test_throws ErrorException Dt.with_time_unit(col("d"); time_unit = :bogus)

    # curried forms
    r_cast_curried = select(df, alias(col("d") |> Dt.cast_time_unit(time_unit = :ms), "d"))
    r_cast_direct = select(df, alias(Dt.cast_time_unit(col("d"); time_unit = :ms), "d"))
    @test collect(r_cast_curried[:d]) == collect(r_cast_direct[:d])
end

@testset "Dt.combine (py-polars test_date_time_combine)" begin
    df = DataFrame(
        (;
            dtm = [DateTime(2022, 12, 31, 10, 30, 45), DateTime(2023, 7, 5, 23, 59, 59)],
            dt = [Date(2022, 10, 10), Date(2022, 7, 5)],
            tm = [Time(1, 2, 3, 456), Time(7, 8, 9, 101)],
        )
    )
    r = select(
        df, alias(Dt.combine(col("dtm"), col("tm")), "d1"), # time component overwritten by tm
        alias(Dt.combine(col("dt"), col("tm")), "d2"), # date + time combined as-is
        alias(Dt.combine(col("dt"), lit(Time(4, 5, 6))), "d3") # date + a literal time
    )
    @test collect(r[:d1]) == [DateTime(2022, 12, 31, 1, 2, 3, 456), DateTime(2023, 7, 5, 7, 8, 9, 101)]
    @test collect(r[:d2]) == [DateTime(2022, 10, 10, 1, 2, 3, 456), DateTime(2022, 7, 5, 7, 8, 9, 101)]
    @test collect(r[:d3]) == [DateTime(2022, 10, 10, 4, 5, 6), DateTime(2022, 7, 5, 4, 5, 6)]

    # curried form + explicit time_unit
    r_curried = select(df, alias(col("dtm") |> Dt.combine(col("tm")), "d1"))
    @test collect(r_curried[:d1]) == collect(r[:d1])
    r_ns = select(df, alias(Dt.combine(col("dtm"), col("tm"); time_unit = :ns), "d1"))
    @test collect(r_ns[:d1]) == collect(r[:d1])
end

@testset "Dt.combine on a Time-typed column raises cleanly (py-polars test_combine_unsupported_types)" begin
    df = DataFrame((; t = [Time(1, 2)]))
    @test_throws PolarsError collect(select(df, alias(Dt.combine(col("t"), lit(Time(3, 4))), "x")))
end

@testset "Dt.replace (py-polars test_replace_expr_datetime / test_replace_expr_date / test_replace_int_datetime)" begin
    # upstream's own fixture uses replacement years/base years as low as 1-9 AD, which our
    # `:ns`-only DateTime column construction can't represent (~1678-2262 range, see
    # docs/src/limitations.md) -- adapted to in-range years while keeping the exact same shape:
    # each of the 7 component columns has exactly one `missing` at a different row, proving a
    # `missing` in *that row's* component falls back to the *original* value for that field only
    # (not the whole row), while every other field in that row is still replaced.
    df = DataFrame(
        (;
            dates = Union{Missing, DateTime}[fill(DateTime(2088, 8, 8, 8, 8, 8, 8), 7); missing],
            year = Union{Missing, Int}[missing, 2001, 2002, 2003, 2004, 2005, 2006, 2007],
            month = Union{Missing, Int}[1, missing, 3, 4, 5, 6, 7, 8],
            day = Union{Missing, Int}[1, 2, missing, 4, 5, 6, 7, 8],
            hour = Union{Missing, Int}[1, 2, 3, missing, 5, 6, 7, 8],
            minute = Union{Missing, Int}[1, 2, 3, 4, missing, 6, 7, 8],
            second = Union{Missing, Int}[1, 2, 3, 4, 5, missing, 7, 8],
            microsecond = Union{Missing, Int}[1000, 2000, 3000, 4000, 5000, 6000, missing, 8000],
        )
    )
    r = select(
        df, alias(
            Dt.replace(
                col("dates"); year = col("year"), month = col("month"), day = col("day"),
                hour = col("hour"), minute = col("minute"), second = col("second"),
                microsecond = col("microsecond")
            ), "r"
        )
    )
    @test isequal(
        collect(r[:r]), [
            DateTime(2088, 1, 1, 1, 1, 1, 1), DateTime(2001, 8, 2, 2, 2, 2, 2),
            DateTime(2002, 3, 8, 3, 3, 3, 3), DateTime(2003, 4, 4, 8, 4, 4, 4),
            DateTime(2004, 5, 5, 5, 8, 5, 5), DateTime(2005, 6, 6, 6, 6, 8, 6),
            DateTime(2006, 7, 7, 7, 7, 7, 8), missing,
        ]
    )

    # the `Date`-typed sibling (test_replace_expr_date), same per-row-null-per-field shape
    df_date = DataFrame(
        (;
            dates = Union{Missing, Date}[Date(2088, 8, 8), Date(2088, 8, 8), Date(2088, 8, 8), missing],
            year = Union{Missing, Int}[missing, 2002, 2003, 4],
            month = Union{Missing, Int}[1, missing, 3, 4],
            day = Union{Missing, Int}[1, 2, missing, 4],
        )
    )
    r_date = select(
        df_date, alias(
            Dt.replace(col("dates"); year = col("year"), month = col("month"), day = col("day")), "r"
        )
    )
    @test isequal(collect(r_date[:r]), [Date(2088, 1, 1), Date(2002, 8, 2), Date(2003, 3, 8), missing])

    # test_replace_int_datetime's shape: `dt.replace()` with no args is the identity, and each
    # single-field replacement leaves every other field untouched -- adapted to in-range base
    # years (upstream literally uses years 1/2/3, which our `:ns`-only columns can't represent).
    df2 = DataFrame(
        (;
            a = Union{Missing, DateTime}[
                DateTime(2001, 2, 2, 2, 2, 2, 2), DateTime(2002, 3, 3, 3, 3, 3, 3),
                DateTime(2003, 4, 4, 4, 4, 4, 4), missing,
            ],
        )
    )
    r_none = select(df2, alias(Dt.replace(col("a")), "x"))
    @test isequal(collect(r_none[:x]), df2[:a])

    r_year = select(df2, alias(Dt.replace(col("a"); year = 2090), "x"))
    @test isequal(
        collect(r_year[:x]),
        [DateTime(2090, 2, 2, 2, 2, 2, 2), DateTime(2090, 3, 3, 3, 3, 3, 3), DateTime(2090, 4, 4, 4, 4, 4, 4), missing]
    )
    r_month = select(df2, alias(Dt.replace(col("a"); month = 9), "x"))
    @test isequal(
        collect(r_month[:x]),
        [DateTime(2001, 9, 2, 2, 2, 2, 2), DateTime(2002, 9, 3, 3, 3, 3, 3), DateTime(2003, 9, 4, 4, 4, 4, 4), missing]
    )
    r_ms = select(df2, alias(Dt.replace(col("a"); microsecond = 9000), "x"))
    @test isequal(
        collect(r_ms[:x]),
        [DateTime(2001, 2, 2, 2, 2, 2, 9), DateTime(2002, 3, 3, 3, 3, 3, 9), DateTime(2003, 4, 4, 4, 4, 4, 9), missing]
    )
end

@testset "Dt.replace invalid components raise cleanly (py-polars test_replace_date_invalid_components / test_replace_datetime_invalid_date_components / test_replace_datetime_invalid_time_components)" begin
    # a load-bearing check per CLAUDE.md/pypolars-test-parity: these are process-abort hazards,
    # not routine input validation, until proven otherwise -- each must raise `PolarsError`
    # cleanly rather than crash the process.
    df_date = DataFrame((; a = [Date(2025, 1, 1)]))
    @test_throws PolarsError collect(select(df_date, alias(Dt.replace(col("a"); month = 13), "x")))
    @test_throws PolarsError collect(select(df_date, alias(Dt.replace(col("a"); day = 32), "x")))

    df_dt = DataFrame((; a = [DateTime(2025, 1, 1)]))
    @test_throws PolarsError collect(select(df_dt, alias(Dt.replace(col("a"); month = 13), "x")))
    @test_throws PolarsError collect(select(df_dt, alias(Dt.replace(col("a"); day = 32), "x")))
    @test_throws PolarsError collect(select(df_dt, alias(Dt.replace(col("a"); hour = 25), "x")))
    @test_throws PolarsError collect(select(df_dt, alias(Dt.replace(col("a"); minute = 61), "x")))
    @test_throws PolarsError collect(select(df_dt, alias(Dt.replace(col("a"); second = 61), "x")))
    @test_throws PolarsError collect(select(df_dt, alias(Dt.replace(col("a"); microsecond = 2_000_000), "x")))
end

@testset "Dt.replace: a replaced year outside the :ns range raises rather than crashing" begin
    # Not in upstream (whose own equivalent fixture runs at `:us` resolution, well inside range):
    # this package's `Vector{DateTime}`-built columns are always `:ns` (documented limitation, see
    # Group 1 of plans/parity/group1_group4_closure.md). Replacing to a year far outside
    # `:ns`'s ~1678-2262 window hits an internal `unwrap()` panic in polars-time's own `replace`
    # kernel -- caught by `guard_error`'s `catch_unwind` as a clean `PolarsError`, not a process
    # abort, which is the FFI panic-safety contract this test exists to pin down.
    df = DataFrame((; a = [DateTime(2001, 2, 2)]))
    @test_throws PolarsError collect(select(df, alias(Dt.replace(col("a"); year = 9), "x")))
end
