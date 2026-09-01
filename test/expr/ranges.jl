@testset "datetime constructor" begin
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

    # time zone + ambiguous cross the ABI as strings: exercised with a real IANA zone
    # (Europe/Paris) rather than only ASCII placeholders, per CLAUDE.md's ncodeunits warning.
    # 2024-01-01 is not a DST fall-back, so this is unambiguous and just proves the tz round-trips.
    dftz = DataFrame((; x = [1]))
    rtz = select(dftz, alias(datetime(2024, 1, 1; hour = 12, time_zone = "Europe/Paris"), "r"))
    @test size(rtz) == (1, 1) # builds and collects fine even without TimeZones.jl loaded

    # 2024-10-27 02:30 local is the actual DST fall-back in Europe/Paris: ambiguous="raise" (the
    # default) must raise a PolarsError, not silently pick one offset or abort the process.
    err = try
        select(dftz, alias(datetime(2024, 10, 27; hour = 2, minute = 30, time_zone = "Europe/Paris", ambiguous = "raise"), "r"))
        nothing
    catch e
        e
    end
    @test err isa Polars.PolarsError
    @test occursin("ambiguous", sprint(showerror, err))

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
end

@testset "duration constructor" begin
    df = DataFrame((; x = [1]))
    r = select(df, alias(duration(; days = 1, hours = 2), "r"))
    @test r[:r] == [Dates.Hour(26)]

    r2 = select(df, alias(duration(; days = 1, hours = 2, time_unit = :ms), "r"))
    @test eltype(r2[:r]) == Dates.Millisecond
    @test r2[:r] == [Dates.Hour(26)]

    dfm = DataFrame((; d = Union{Int, Missing}[1, missing]))
    rm = select(dfm, alias(duration(; days = col("d")), "r"))
    @test isequal(rm[:r], [Dates.Day(1), missing])
end

@testset "date constructor" begin
    df = DataFrame((; d = [1, 2, 3]))
    r = select(df, alias(date(2024, 1, col("d")), "r"))
    @test r[:r] == [Date(2024, 1, 1), Date(2024, 1, 2), Date(2024, 1, 3)]
end

@testset "time constructor" begin
    df = DataFrame((; x = [1]))
    r = select(df, alias(time(9, 30), "r"))
    @test r[:r] == [Dates.Time(9, 30)]

    # zero-argument Base.time() (wall-clock seconds) must still work after adding this method
    @test time() isa Float64
end

@testset "from_epoch" begin
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
end
