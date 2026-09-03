@testset "datetime constructor (py-polars functions/as_datatype/test_datetime.py)" begin
    df = DataFrame((; d = [1, 2, 3]))
    r = select(df, alias(datetime(2024, 1, col("d")), "r"))
    @test r[:r] == [DateTime(2024, 1, 1), DateTime(2024, 1, 2), DateTime(2024, 1, 3)]

    # all-literal fast path (`DatetimeArgs::as_literal` upstream): with every component a plain
    # scalar, the result does not broadcast to `df`'s row count -- `select` never broadcasts a
    # bare literal expression to match the frame's row count (confirmed with `select(df,
    # alias(lit(5), "r"))` -> `[5]`, not `[5, 5, 5]`), so this is baseline `select` behavior, not
    # something specific to `datetime`.
    r2 = select(df, alias(datetime(2024, 1, 1; hour = 12, minute = 30), "r"))
    @test r2[:r] == [DateTime(2024, 1, 1, 12, 30)]

    # null propagation: a missing component poisons only that row
    dfm = DataFrame((; y = [2024, missing], m = [1, 2], d = [1, 2]))
    rm = select(dfm, alias(datetime(col("y"), col("m"), col("d")), "r"))
    @test isequal(rm[:r], [DateTime(2024, 1, 1), missing])

    # test_date_datetime: pl.datetime(...).dt.hour() and pl.date(...).dt.day() round-trip their
    # own input columns exactly
    dfh = DataFrame((; year = [2001, 2002, 2003], month = [1, 2, 3], day = [1, 2, 3], hour = [23, 12, 8]))
    outh = select(
        dfh,
        col(:year), col(:month), col(:day), col(:hour),
        alias(cast(Dt.hour(datetime(col("year"), col("month"), col("day"); hour = col("hour"))), Int64), "h2"),
        alias(cast(Dt.day(date(col("year"), col("month"), col("day"))), Int64), "date"),
    )
    @test outh[:date] == dfh[:day]
    @test outh[:h2] == dfh[:hour]

    # test_date_invalid_component / test_datetime_invalid_date_component: an out-of-range
    # calendar component raises cleanly rather than aborting
    df1 = DataFrame((; x = [1]))
    for (y, m, d) in ((2025, 13, 1), (2025, 1, 32), (2025, 2, 29))
        @test_throws PolarsError select(df1, date(y, m, d))
        @test_throws PolarsError select(df1, datetime(y, m, d))
    end

    # test_datetime_invalid_time_component: an out-of-range time-of-day component raises too
    @test_throws PolarsError select(df1, datetime(2025, 1, 1; hour = 25))
    @test_throws PolarsError select(df1, datetime(2025, 1, 1; minute = 60))
    @test_throws PolarsError select(df1, datetime(2025, 1, 1; second = 60))
    @test_throws PolarsError select(df1, datetime(2025, 1, 1; microsecond = 2_000_000))

    # test_datetime_time_unit: parametrized time_unit, component round-trip
    for tu in (:ms, :us, :ns)
        r_tu = select(df1, alias(datetime(2022, 1, 2; time_unit = tu), "r"))
        @test size(r_tu) == (1, 1)
    end

    # test_datetime_time_zone: parametrized time zone, component round-trip (size-only, since
    # reading a tz-aware value back requires TimeZones.jl, per CLAUDE.md)
    for tz in (nothing, "Europe/Amsterdam", "UTC")
        r_tz = select(df1, alias(datetime(2022, 1, 2; hour = 10, time_zone = tz), "r"))
        @test size(r_tz) == (1, 1)
    end

    # time zone + ambiguous cross the ABI as strings: exercised with a real IANA zone
    # (Europe/Paris) rather than only ASCII placeholders, per CLAUDE.md's ncodeunits warning.
    # 2024-01-01 is not a DST fall-back, so this is unambiguous and just proves the tz round-trips.
    dftz = DataFrame((; x = [1]))
    rtz = select(dftz, alias(datetime(2024, 1, 1; hour = 12, time_zone = "Europe/Paris"), "r"))
    @test size(rtz) == (1, 1) # builds and collects fine even without TimeZones.jl loaded

    # test_datetime_ambiguous_time_zone / test_datetime_ambiguous_time_zone_earliest:
    # 2018-10-28 02:30 local is the actual DST fall-back in Europe/Brussels (upstream's own
    # fixture). ambiguous="raise" (the default) must raise a PolarsError, not silently pick one
    # offset or abort the process; ambiguous="earliest"/"latest" resolve to distinct UTC instants
    # (checked via Dt.timestamp, since reading the tz-aware value itself needs TimeZones.jl).
    err = try
        select(dftz, alias(datetime(2018, 10, 28; hour = 2, minute = 30, time_zone = "Europe/Brussels"), "r"))
        nothing
    catch e
        e
    end
    @test err isa Polars.PolarsError

    r_earliest_wall = select(
        dftz,
        alias(
            Dt.replace_time_zone(
                datetime(2018, 10, 28; hour = 2, minute = 30, time_zone = "Europe/Brussels", ambiguous = "earliest"),
                nothing,
            ), "r",
        ),
    )
    @test r_earliest_wall[:r] == [DateTime(2018, 10, 28, 2, 30, 0)]

    r_ts_earliest = select(
        dftz,
        alias(
            Dt.timestamp(datetime(2018, 10, 28; hour = 2, minute = 30, time_zone = "Europe/Brussels", ambiguous = "earliest")),
            "r",
        ),
    )
    r_ts_latest = select(
        dftz,
        alias(
            Dt.timestamp(datetime(2018, 10, 28; hour = 2, minute = 30, time_zone = "Europe/Brussels", ambiguous = "latest")),
            "r",
        ),
    )
    @test r_ts_earliest[:r] != r_ts_latest[:r] # distinct UTC offsets, per upstream's own assertion (`result.fold == 0` for earliest)

    # non-ASCII string argument (`ncodeunits` vs `length` bug class): an invalid non-ASCII time
    # zone name must round-trip cleanly through the ABI and fail with a normal PolarsError, never
    # `incomplete utf-8 byte sequence`.
    err2 = try
        select(dftz, alias(datetime(2024, 1, 1; time_zone = "héllo/Zone"), "r"))
        nothing
    catch e
        e
    end
    @test err2 isa Polars.PolarsError
    @test !occursin("incomplete utf-8 byte sequence", sprint(showerror, err2))

    # test_datetime_invalid_time_zone: an unparseable (but ASCII) time zone name raises on both an
    # empty and a non-empty input column
    dfe = DataFrame((; year = Int32[]))
    @test_throws PolarsError select(dfe, alias(datetime(col("year"), 1, 1; time_zone = "foo"), "r"))
    df2024 = DataFrame((; year = [2024]))
    @test_throws PolarsError select(df2024, alias(datetime(col("year"), 1, 1; time_zone = "foo"), "r"))

    # test_datetime_from_empty_column: empty input propagates through both select and with_columns
    @test size(select(dfe, alias(datetime(col("year"), 1, 1), "datetime"))) == (0, 1)
    @test size(with_columns(dfe, alias(datetime(col("year"), 1, 1), "datetime"))) == (0, 2)

    # test_datetime_name (Step 8 divergence, see `datetime`'s docstring in src/expr/ranges.jl):
    # upstream names the output column after the first non-literal argument's own name ("year"),
    # or "literal" when the first argument is itself a literal. This package's vendored
    # `polars-plan` (0.54.4) always aliases to the fixed name "datetime" -- a `// TODO: follow
    # left-hand rule in Polars 2.0` not yet implemented in that crate version, confirmed by reading
    # its own source directly. Recorded as `@test_broken` against upstream's expectation, alongside
    # the actual (asserted-as-fact) behavior.
    @test_broken names(select(dfh, datetime(col("year"), col("month"), col("day"); hour = col("hour")))) == ["year"]
    @test names(select(dfh, datetime(col("year"), col("month"), col("day"); hour = col("hour")))) == ["datetime"]
    @test_broken names(select(dfh, datetime(2024, col("month"), col("day"); hour = col("hour")))) == ["literal"]
    @test names(select(dfh, datetime(2024, col("month"), col("day"); hour = col("hour")))) == ["datetime"]
end

@testset "duration constructor (py-polars functions/as_datatype/test_duration.py)" begin
    df = DataFrame((; x = [1]))
    r = select(df, alias(duration(; days = 1, hours = 2), "r"))
    @test r[:r] == [Dates.Hour(26)]

    r2 = select(df, alias(duration(; days = 1, hours = 2, time_unit = :ms), "r"))
    @test eltype(r2[:r]) == Dates.Millisecond
    @test r2[:r] == [Dates.Hour(26)]

    dfm = DataFrame((; d = Union{Int, Missing}[1, missing]))
    rm = select(dfm, alias(duration(; days = col("d")), "r"))
    @test isequal(rm[:r], [Dates.Day(1), missing])

    # test_empty_duration: empty input, default time_unit :us, shape (0, 1)
    dfe = DataFrame((; days = Int32[]))
    re = select(dfe, alias(duration(; days = col("days")), "duration"))
    @test size(re) == (0, 1)

    # test_duration_time_units: components summed and re-expressed exactly at ns precision
    r_ns = select(df, alias(duration(; days = 1, minutes = 2, seconds = 3, milliseconds = 4, microseconds = 5, nanoseconds = 6, time_unit = :ns), "r"))
    @test r_ns[:r] == [Dates.Nanosecond(86523004005006)]

    # test_duration_subseconds_us: sub-second components round-trip identically to their
    # pre-summed equivalent at each time_unit -- a genuine rounding/truncation domain-edge case
    r_ms_a = select(df, alias(duration(; milliseconds = 6, microseconds = 4_005, nanoseconds = 1_002_003, time_unit = :ms), "d"))
    r_ms_b = select(df, alias(duration(; milliseconds = 11, time_unit = :ms), "d"))
    @test r_ms_a[:d] == r_ms_b[:d]

    r_us_a = select(df, alias(duration(; milliseconds = 6, microseconds = 4_005, nanoseconds = 1_002_003, time_unit = :us), "d"))
    r_us_b = select(df, alias(duration(; microseconds = 11_007, time_unit = :us), "d"))
    @test r_us_a[:d] == r_us_b[:d]

    r_ns_a = select(df, alias(duration(; milliseconds = 6, microseconds = 4_005, nanoseconds = 1_002_003, time_unit = :ns), "d"))
    r_ns_b = select(df, alias(duration(; nanoseconds = 11_007_003, time_unit = :ns), "d"))
    @test r_ns_a[:d] == r_ns_b[:d]

    # test_duration_time_unit_ms: an unspecified time_unit defaults to :us, not :ms, even when only
    # a millisecond-scale component is given
    r_default = select(df, alias(duration(; milliseconds = 4), "d"))
    r_us_explicit = select(df, alias(duration(; milliseconds = 4, time_unit = :us), "d"))
    @test r_default[:d] == r_us_explicit[:d]

    # test_datetime_duration_offset / test_date_duration_offset: adding/subtracting a
    # component-built duration against a Datetime/Date column
    dfdt = DataFrame((; dt = [DateTime(1999, 1, 1, 7), DateTime(2022, 1, 2, 14)], add = [1, 2]))
    outdt = select(
        dfdt,
        alias(col("dt") + duration(; weeks = col("add")), "add_weeks"),
        alias(col("dt") + duration(; days = col("add")), "add_days"),
        alias(col("dt") + duration(; hours = col("add")), "add_hours"),
        alias(col("dt") + duration(; seconds = col("add")), "add_seconds"),
        alias(col("dt") + duration(; microseconds = col("add") * lit(1000)), "add_usecs"),
    )
    @test outdt[:add_weeks] == [DateTime(1999, 1, 8, 7), DateTime(2022, 1, 16, 14)]
    @test outdt[:add_days] == [DateTime(1999, 1, 2, 7), DateTime(2022, 1, 4, 14)]
    @test outdt[:add_hours] == [DateTime(1999, 1, 1, 8), DateTime(2022, 1, 2, 16)]
    @test outdt[:add_seconds] == [DateTime(1999, 1, 1, 7, 0, 1), DateTime(2022, 1, 2, 14, 0, 2)]
    @test outdt[:add_usecs] == [DateTime(1999, 1, 1, 7, 0, 0, 1), DateTime(2022, 1, 2, 14, 0, 0, 2)]

    dfd = DataFrame((; d = [Date(10, 1, 1), Date(2000, 7, 5)], offset = [365, 7]))
    outd = select(
        dfd,
        alias(col("d") + duration(; days = col("offset")), "add_days"),
        alias(col("d") - duration(; days = col("offset")), "sub_days"),
        alias(col("d") + duration(; weeks = col("offset")), "add_weeks"),
        alias(col("d") - duration(; weeks = col("offset")), "sub_weeks"),
    )
    @test outd[:add_days] == [Date(11, 1, 1), Date(2000, 7, 12)]
    @test outd[:sub_days] == [Date(9, 1, 1), Date(2000, 6, 28)]
    @test outd[:add_weeks] == [Date(16, 12, 30), Date(2000, 8, 23)]
    @test outd[:sub_weeks] == [Date(3, 1, 3), Date(2000, 5, 17)]

    # test_duration_wildcard_expansion: a wildcard argument expands to one output column per input
    # column, each keeping its own name via `keep_name` (upstream: `.name.keep()`) -- without it,
    # every expansion collides under `duration`'s own default name ("literal", since the unset
    # `weeks` field stays `lit(0)` and governs the default name; confirmed live, matches the
    # single-arg case above where duration(; days=...) alone also defaults to no fixed rename).
    dfw = DataFrame((; a = [1], b = [2]))
    rw = select(dfw, keep_name(duration(; hours = col("*"))))
    @test names(rw) == ["a", "b"]
    @test rw[:a] == [Dates.Second(3600)]
    @test rw[:b] == [Dates.Second(7200)]
end

@testset "date constructor (py-polars functions/as_datatype/test_datetime.py::date_)" begin
    df = DataFrame((; d = [1, 2, 3]))
    r = select(df, alias(date(2024, 1, col("d")), "r"))
    @test r[:r] == [Date(2024, 1, 1), Date(2024, 1, 2), Date(2024, 1, 3)]

    # matches upstream's own explicit `.alias("date")` -- see the src/expr/ranges.jl fix note
    @test names(select(df, date(2024, 1, col("d")))) == ["date"]
end

@testset "time constructor (py-polars functions/as_datatype/test_time.py)" begin
    df = DataFrame((; x = [1]))
    r = select(df, alias(time(9, 30), "r"))
    @test r[:r] == [Dates.Time(9, 30)]

    # matches upstream's own explicit `.alias("time")` -- see the src/expr/ranges.jl fix note
    @test names(select(df, time(9, 30))) == ["time"]

    # zero-argument Base.time() (wall-clock seconds) must still work after adding this method
    @test time() isa Float64

    # test_time: pl.time(...).dt.hour()/.minute()/.second()/.microsecond() round-trip the input
    # columns exactly
    dft = DataFrame((; hour = [7, 14, 21], minute_ = [10, 20, 30], second_ = [15, 30, 45], micro = [123456, 555555, 987654]))
    outt = select(
        dft,
        col(:hour), col(:minute_), col(:second_), col(:micro),
        alias(cast(Dt.hour(time(col("hour"), col("minute_"), col("second_"), col("micro"))), Int64), "h2"),
        alias(cast(Dt.minute(time(col("hour"), col("minute_"), col("second_"), col("micro"))), Int64), "m2"),
        alias(cast(Dt.second(time(col("hour"), col("minute_"), col("second_"), col("micro"))), Int64), "s2"),
        alias(cast(Dt.microsecond(time(col("hour"), col("minute_"), col("second_"), col("micro"))), Int64), "ms2"),
    )
    @test outt[:h2] == dft[:hour]
    @test outt[:m2] == dft[:minute_]
    @test outt[:s2] == dft[:second_]
    @test outt[:ms2] == dft[:micro]
end

@testset "from_epoch (py-polars lazyframe/test_lazyframe.py::test_from_epoch, test_from_epoch_str; series/test_series.py::test_from_epoch_expr, test_from_epoch_seq_input)" begin
    df = DataFrame((; e = [0, 86400, 172800]))

    r = select(df, alias(from_epoch(col("e")), "r"))  # :s default
    @test r[:r] == [DateTime(1970, 1, 1), DateTime(1970, 1, 2), DateTime(1970, 1, 3)]

    # :d interprets the raw integer as a day count, not a rescaled second count -- a distinct
    # fixture from the :s case above.
    dfd = DataFrame((; e = [0, 2, 4]))
    r2 = select(dfd, alias(from_epoch(col("e"), :d), "r"))
    @test r2[:r] == [Date(1970, 1, 1), Date(1970, 1, 3), Date(1970, 1, 5)]

    r3 = select(df, alias(from_epoch(col("e"), :ms), "r"))
    @test r3[:r] == DateTime(1970, 1, 1) .+ Dates.Millisecond.([0, 86400, 172800])

    @test_throws ErrorException from_epoch(col("e"), :bogus)

    # test_from_epoch (lazyframe): upstream's own exact fixture, every time_unit against a single
    # instant (2006-05-17 15:34:04)
    dfe = DataFrame(
        (;
            timestamp_d = [13285],
            timestamp_s = [1147880044],
            timestamp_ms = [1147880044 * 1_000],
            timestamp_us = [1147880044 * 1_000_000],
            timestamp_ns = [1147880044 * 1_000_000_000],
        )
    )
    re = select(
        dfe,
        alias(from_epoch(col("timestamp_d"), :d), "d"),
        alias(from_epoch(col("timestamp_s"), :s), "s"),
        alias(from_epoch(col("timestamp_ms"), :ms), "ms"),
        alias(from_epoch(col("timestamp_us"), :us), "us"),
        alias(from_epoch(col("timestamp_ns"), :ns), "ns"),
    )
    exp = DateTime(2006, 5, 17, 15, 34, 4)
    @test re[:d] == [Date(2006, 5, 17)]
    @test re[:s] == [exp]
    @test re[:ms] == [exp]
    @test re[:us] == [exp]
    @test re[:ns] == [exp]

    # test_from_epoch_seq_input's fixture, ported to the Expr-level entry point
    r_seq = select(DataFrame((; x = [1147880044])), alias(from_epoch(col("x")), "r"))
    @test r_seq[:r] == [exp]

    # null propagation and empty input
    dfm = DataFrame((; x = Union{Int, Missing}[1147880044, missing]))
    rm = select(dfm, alias(from_epoch(col("x"), :s), "r"))
    @test isequal(collect(rm[:r]), [exp, missing])

    dfempty = DataFrame((; x = Int[]))
    @test size(select(dfempty, alias(from_epoch(col("x"), :s), "r"))) == (0, 1)

    # test_from_epoch (docstring fixture): fractional-second float input at time_unit="s" must
    # keep full microsecond precision (upstream scales x1_000_000 and lands on Datetime(:us)) --
    # this was a genuine bug (fixed in src/expr/ranges.jl): the old implementation scaled x1_000
    # to Datetime(:ms), silently truncating sub-millisecond precision. Checked via `Dt.microsecond`
    # rather than round-tripping through Julia's own `DateTime` (millisecond resolution only, so it
    # cannot itself distinguish the two).
    dff = DataFrame((; ts = [-609066.723456, 1066445333.8888, 3405071999.987654]))
    r_us_component = select(dff, alias(cast(Dt.microsecond(from_epoch(col("ts"), :s)), Int64), "us"))
    @test r_us_component[:us] == [276544, 888800, 987654]

    # test_from_epoch_str: a String column raises cleanly on the scaled (:s/:ms) paths (the
    # multiplication itself fails before ever reaching the cast) rather than silently returning
    # `missing` -- this was the same bug: before the fix, :ms went straight to a lenient
    # string-to-datetime cast, which nulls unparseable input instead of raising.
    dfstr = DataFrame((; x = ["1147880044000"]))
    @test_throws PolarsError select(dfstr, alias(from_epoch(col("x"), :ms), "r"))
    @test_throws PolarsError select(dfstr, alias(from_epoch(col("x"), :s), "r"))
end

@testset "int_range (py-polars functions/range/test_int_range.py)" begin
    df = DataFrame((; x = [1]))

    # test_int_range: basic sequence, exclusive end
    r = select(df, alias(int_range(0, 3), "r"))
    @test r[:r] == [0, 1, 2]

    # test_int_range_decreasing: a negative step counts down. `stop` is exclusive (Python's
    # `range(10, -1, -1)` stops at 0, not -1 -- Julia's `10:-1:-1` would include -1, so the
    # expected values are spelled out rather than built from a Julia range literal).
    @test select(df, alias(int_range(10, 1; step = -2), "r"))[:r] == collect(10:-2:2)
    @test select(df, alias(int_range(10, -1; step = -1), "r"))[:r] == collect(10:-1:0)

    # test_int_range_expr: end computed from an expression (here, `len()`), not a plain scalar
    dfe = DataFrame((; a = ["foobar", "barfoo"]))
    oute = select(dfe, int_range(0, len() * 10))
    @test size(oute) == (20, 1)
    @test collect(oute[1])[end] == 19

    # test_int_range_schema: the default dtype is Int64
    rd = select(df, alias(int_range(-3, 3), "r"))
    @test eltype(rd[:r]) == Int64

    # test_int_range_null_input: a null bound raises rather than aborting
    @test_throws PolarsError select(df, int_range(3, missing; step = -1, dtype = UInt32))

    # test_int_range_non_integer_dtype: a non-integer `dtype` raises (checked at execution time,
    # since `int_range` itself does not validate `dtype` eagerly)
    @test_throws PolarsError select(df, int_range(3, -1; step = -1, dtype = Float64))
end

@testset "date_range (py-polars functions/range/test_date_range.py)" begin
    # test_date_range: monthly interval between two Dates
    r = select(DataFrame((; x = [1])), alias(date_range(Date(2022, 1, 1), Date(2022, 3, 1); interval = "1mo"), "r"))
    @test r[:r] == [Date(2022, 1, 1), Date(2022, 2, 1), Date(2022, 3, 1)]

    # default interval "1d", default closed :both
    rd = select(DataFrame((; x = [1])), alias(date_range(Date(2022, 1, 1), Date(2022, 1, 3)), "r"))
    @test rd[:r] == [Date(2022, 1, 1), Date(2022, 1, 2), Date(2022, 1, 3)]

    # test_date_range_start_end_interval_forwards: every `closed` variant, plus the
    # wrong-direction-is-empty case
    start, stop = Date(2025, 1, 1), Date(2025, 1, 10)
    df1 = DataFrame((; x = [1]))
    @test select(df1, alias(date_range(start, stop; interval = "3d", closed = :left), "r"))[:r] ==
        [Date(2025, 1, 1), Date(2025, 1, 4), Date(2025, 1, 7)]
    @test select(df1, alias(date_range(start, stop; interval = "3d", closed = :right), "r"))[:r] ==
        [Date(2025, 1, 4), Date(2025, 1, 7), Date(2025, 1, 10)]
    @test select(df1, alias(date_range(start, stop; interval = "3d", closed = :none), "r"))[:r] ==
        [Date(2025, 1, 4), Date(2025, 1, 7)]
    @test select(df1, alias(date_range(start, stop; interval = "3d", closed = :both), "r"))[:r] ==
        [Date(2025, 1, 1), Date(2025, 1, 4), Date(2025, 1, 7), Date(2025, 1, 10)]
    @test size(select(df1, alias(date_range(stop, start; interval = "3d"), "r"))) == (0, 1)

    # test_date_range_end_of_month_5441: month-end clamping
    rmo = select(df1, alias(date_range(Date(2020, 1, 31), Date(2020, 3, 31); interval = "1mo", closed = :both), "r"))
    @test rmo[:r] == [Date(2020, 1, 31), Date(2020, 2, 29), Date(2020, 3, 31)]

    # test_date_range_start_later_than_end: an empty (not erroring) result
    @test size(select(df1, alias(date_range(Date(2000, 3, 20), Date(2000, 3, 5)), "r"))) == (0, 1)

    # test_date_range_24h_interval_raises: `interval` for `date_range` must be a whole number of
    # days -- raised directly from the `date_range` call (interval validation happens while
    # building the expression, not at `select`/execution time)
    @test_throws PolarsError date_range(Date(2022, 1, 1), Date(2022, 1, 3); interval = "24h")

    # test_date_range_invalid_time_unit: an unparseable interval string raises the same way
    @test_throws PolarsError date_range(Date(2021, 12, 16), Date(2021, 12, 18); interval = "1X")

    # test_date_range_datetime_input: `start`/`stop` accept `DateTime`s too (truncated to `Date`)
    rdt = select(df1, alias(date_range(DateTime(2022, 1, 1, 12), DateTime(2022, 1, 3); interval = "1d"), "r"))
    @test rdt[:r] == [Date(2022, 1, 1), Date(2022, 1, 2), Date(2022, 1, 3)]

    # test_date_range_expr_scalar: `start`/`stop` as aggregation expressions, not plain scalars
    dfa = DataFrame((; a = [Date(2025, 1, 3), Date(2025, 1, 1)]))
    ra = select(dfa, alias(date_range(min(col("a")), max(col("a")); interval = "1d"), "r"))
    @test ra[:r] == [Date(2025, 1, 1), Date(2025, 1, 2), Date(2025, 1, 3)]
end

@testset "datetime_range (py-polars functions/range/test_datetime_range.py)" begin
    df1 = DataFrame((; x = [1]))

    # test_datetime_range: 2h interval between a DateTime and a Date, swept over every time_unit
    for tu in (:ms, :us, :ns)
        rtu = select(df1, alias(datetime_range(DateTime(2020, 1, 1), Date(2020, 1, 2); interval = "2h", time_unit = tu), "r"))
        @test size(rtu) == (13, 1)
        @test rtu[:r][1] == DateTime(2020, 1, 1)
        @test rtu[:r][end] == DateTime(2020, 1, 2)
    end

    # test_datetime_range_start_end_interval_forwards (adapted to `Date`, the naive/no-time_zone
    # case): every `closed` variant, plus the wrong-direction-is-empty case
    start, stop = Date(2025, 1, 1), Date(2025, 1, 10)
    @test select(df1, alias(datetime_range(start, stop; interval = "3d", closed = :left), "r"))[:r] ==
        DateTime.([Date(2025, 1, 1), Date(2025, 1, 4), Date(2025, 1, 7)])
    @test select(df1, alias(datetime_range(start, stop; interval = "3d", closed = :right), "r"))[:r] ==
        DateTime.([Date(2025, 1, 4), Date(2025, 1, 7), Date(2025, 1, 10)])
    @test select(df1, alias(datetime_range(start, stop; interval = "3d", closed = :none), "r"))[:r] ==
        DateTime.([Date(2025, 1, 4), Date(2025, 1, 7)])
    @test select(df1, alias(datetime_range(start, stop; interval = "3d", closed = :both), "r"))[:r] ==
        DateTime.([Date(2025, 1, 1), Date(2025, 1, 4), Date(2025, 1, 7), Date(2025, 1, 10)])
    @test size(select(df1, alias(datetime_range(stop, start; interval = "3d"), "r"))) == (0, 1)

    # test_datetime_range_invalid_time_unit: an unparseable interval string raises directly from
    # the `datetime_range` call
    @test_throws PolarsError datetime_range(DateTime(2021, 12, 16), DateTime(2021, 12, 16, 3); interval = "1X")

    # test_datetime_range_invalid_time_zone: an unparseable time zone name raises directly too
    @test_throws PolarsError datetime_range(DateTime(2001, 1, 1), DateTime(2001, 1, 3); time_zone = "foo")

    # time_zone round-trips through the ABI cleanly (size-only check, since reading a tz-aware
    # value back requires TimeZones.jl, per CLAUDE.md -- same convention as `datetime`'s own tests)
    for tz in (nothing, "Europe/Amsterdam", "UTC")
        rtz = select(df1, alias(datetime_range(DateTime(2022, 1, 1), DateTime(2022, 1, 2); interval = "6h", time_zone = tz), "r"))
        @test size(rtz) == (5, 1)
    end
end

@testset "time_range (py-polars functions/range/test_time_range.py)" begin
    df1 = DataFrame((; x = [1]))

    # test_time_range_eager_explode-equivalent: a plain hourly sequence
    r = select(df1, alias(time_range(Time(9, 0), Time(11, 0); interval = "1h"), "r"))
    @test r[:r] == [Time(9, 0), Time(10, 0), Time(11, 0)]

    # test_time_range_start_equals_end / test_time_range_start_equals_end_open: a degenerate
    # `start == stop` range is a single point under `:both`, empty under every other `closed`
    t = Time(12, 0)
    @test select(df1, alias(time_range(t, t; closed = :both), "r"))[:r] == [t]
    for closed in (:left, :right, :none)
        @test size(select(df1, alias(time_range(t, t; closed = closed), "r"))) == (0, 1)
    end

    # test_time_range_start_later_than_end: an empty (not erroring) result
    @test size(select(df1, alias(time_range(Time(12), Time(11)), "r"))) == (0, 1)

    # test_time_range_lit_lazy: exact fixture, closed = :right, sub-second interval
    rlit = select(
        df1,
        alias(time_range(Time(1, 2, 3), Time(23, 59, 59); interval = "5h45m10s333ms", closed = :right), "r"),
    )
    @test rlit[:r] == [Time(6, 47, 13, 333), Time(12, 32, 23, 666), Time(18, 17, 33, 999)]

    # test_time_range_invalid_step: a non-positive interval raises (checked at execution time)
    @test_throws PolarsError select(df1, alias(time_range(Time(11), Time(12); interval = "-10m"), "r"))
end
