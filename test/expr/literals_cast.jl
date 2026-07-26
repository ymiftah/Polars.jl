@testset "nth" begin
    df = DataFrame((; a = [1, 2, 3], b = [10, 20, 30], c = [100, 200, 300]))

    @test Tables.columnnames(select(df, Polars.nth(1))) == (:a,)
    @test Tables.columnnames(select(df, Polars.nth(2))) == (:b,)
    @test Tables.columnnames(select(df, Polars.nth(3))) == (:c,)
    @test Tables.columnnames(select(df, Polars.nth(-1))) == (:c,)
end

@testset "lit" begin
    df = DataFrame((; a = [1, 2, 3]))

    # a bare literal broadcasts to match the frame's row count
    sel = select(df, col("a"), lit(99) |> alias("k"))
    @test sel[:a] == [1, 2, 3]
    @test collect(sel[:k]) == [99, 99, 99]

    wc = with_columns(df, lit(99) |> alias("k"))
    @test collect(wc[:k]) == [99, 99, 99]
end

@testset "literal convert overloads (Base.convert(::Type{Expr}, ...))" begin
    # one case per Base.convert(::Type{Expr}, ...) method in src/expr/expr.jl -- only Int64
    # (via lit(99) above) had direct coverage before this
    df = DataFrame((; a = [1, 2, 3]))

    # lit(v) alone doesn't broadcast to the frame's row count -- it needs a sibling column
    # expression in the same select (matching the established lit(99) pattern above)
    @test collect(select(df, col("a"), lit(Int32(7)) |> alias("k"))[:k]) == fill(Int32(7), 3)
    @test collect(select(df, col("a"), lit(UInt32(7)) |> alias("k"))[:k]) == fill(UInt32(7), 3)
    @test collect(select(df, col("a"), lit(UInt64(7)) |> alias("k"))[:k]) == fill(UInt64(7), 3)
    @test collect(select(df, col("a"), lit(true) |> alias("k"))[:k]) == fill(true, 3)
    @test collect(select(df, col("a"), lit(Float32(1.5)) |> alias("k"))[:k]) == fill(Float32(1.5), 3)
    @test collect(select(df, col("a"), lit(1.5) |> alias("k"))[:k]) == fill(1.5, 3)
    @test collect(select(df, col("a"), lit("hi") |> alias("k"))[:k]) == fill("hi", 3)

    # missing -> null literal: the resulting column has Julia eltype Union{Missing,Nothing}
    # (the Null dtype)
    r_missing = select(df, col("a"), lit(missing) |> alias("k"))
    @test eltype(r_missing[:k]) == Union{Missing, Nothing}
    @test all(ismissing, collect(r_missing[:k]))

    # AbstractVector -> a Series-backed literal (distinct code path: builds a throwaway
    # DataFrame internally via polars_expr_lit_series) -- zero coverage before this
    r_vec = select(df, (col("a") + lit([10, 20, 30])) |> alias("k"))
    @test collect(r_vec[:k]) == [11, 22, 33]

    # Colon -> col("*")
    r_colon = select(df, convert(Polars.Expr, :))
    @test Tables.columnnames(r_colon) == (:a,)

    # Date/Time/DateTime literals (P7 of the gap-closure plan): no dedicated FFI primitive --
    # composed from an integer literal + cast, reusing arrowvector's own epoch-math formulas
    # (src/arrow/array.jl). Each case below round-trips a real VALUE through filter/comparison
    # against a matching column, not just "doesn't error".
    dfd = DataFrame((; d = [Date(2024, 3, 15), Date(2024, 3, 16), Date(2024, 3, 17)]))
    r_date = filter(dfd, col("d") == lit(Date(2024, 3, 15)))
    @test collect(r_date[:d]) == [Date(2024, 3, 15)]

    dft = DataFrame((; t = [Dates.Time(13, 45, 30), Dates.Time(1, 2, 3)]))
    r_time = filter(dft, col("t") == lit(Dates.Time(13, 45, 30)))
    @test collect(r_time[:t]) == [Dates.Time(13, 45, 30)]

    dfdt = DataFrame((; dt = [DateTime(2024, 3, 15, 10, 30, 0), DateTime(2024, 3, 16)]))
    r_dt = filter(dfdt, col("dt") == lit(DateTime(2024, 3, 15, 10, 30, 0)))
    @test collect(r_dt[:dt]) == [DateTime(2024, 3, 15, 10, 30, 0)]

    # pre-1970 date: negative epoch days -- signed Int32 arithmetic must not wrap
    d_old = Date(1900, 1, 1)
    @test Dates.value(d_old - Date(1970, 1, 1)) < 0
    dfold = DataFrame((; d = [Date(1900, 1, 1), Date(2024, 1, 1)]))
    r_old = filter(dfold, col("d") == lit(d_old))
    @test collect(r_old[:d]) == [d_old]

    # col("d") - lit(Date(1970,1,1)) cross-checks the epoch math independently of the round-trips
    # above. Polars represents Date - Date as a Duration in microseconds (not raw epoch days), so
    # the expected epoch-day count is scaled to microseconds before comparing.
    dfcheck = DataFrame((; d = [Date(1900, 1, 1), Date(1970, 1, 1), Date(2024, 3, 15)]))
    r_epoch = select(dfcheck, (col("d") - lit(Date(1970, 1, 1))) |> alias("epoch"))
    expected_days = [
        Dates.value(d - Date(1970, 1, 1)) for d in [Date(1900, 1, 1), Date(1970, 1, 1), Date(2024, 3, 15)]
    ]
    @test collect(r_epoch[:epoch]) == Dates.Microsecond.(Dates.Day.(expected_days))

    # a :ns-built DateTime literal compared against a column at a different native resolution
    # (:us) -- polars aligns the units transparently for a comparison (this does NOT extend to
    # `join`, which requires both sides at a matching resolution -- see docs/src/limitations.md)
    dfus = DataFrame((; x = [0, 1000, 2000]))
    dfus_dt = select(dfus, cast_datetime(col("x"); time_unit = :us) |> alias("dt"))
    dtval = DateTime(1970, 1, 1, 0, 0, 0, 1) # 1 ms = 1000 us after epoch -> matches row x=1000
    r_cross = filter(dfus_dt, col("dt") == lit(dtval))
    @test collect(r_cross[:dt]) == [dtval]

    # far-future DateTime literal: built at :ns, so nanoseconds-since-epoch overflows Int64
    # outside ~1678-2262 -- this must error loudly (Dates.jl's own checked Millisecond ->
    # Nanosecond conversion throws InexactError), not silently produce a wrong value
    @test_throws InexactError lit(DateTime(2300, 1, 1))

    # Meta.is_literal (Task 3) reports false for these -- a Cast(Literal(...)) tree, not a
    # genuine Literal node -- diverging from py-polars, but cosmetic only (see
    # docs/src/limitations.md)
    @test Polars.Meta.is_literal(lit(Date(2024, 3, 15))) == false
    @test Polars.Meta.is_literal(lit(1)) == true
end

@testset "cast" begin
    df = DataFrame((; x = [1, 2, 3]))

    to_float = select(df, col("x") |> cast(Float64))
    @test eltype(to_float[:x]) == Float64
    @test collect(to_float[:x]) == [1.0, 2.0, 3.0]

    to_string = select(df, col("x") |> cast(String))
    @test eltype(to_string[:x]) == String
    @test collect(to_string[:x]) == ["1", "2", "3"]

    to_bool = select(df, col("x") |> cast(Bool))
    @test collect(to_bool[:x]) == [true, true, true]

    # lossy Float -> Int cast truncates towards zero
    dff = DataFrame((; x = [1.7, 2.3, -1.9]))
    truncated = select(dff, col("x") |> cast(Int64))
    @test collect(truncated[:x]) == [1, 2, -1]
end

@testset "cast to every remaining supported dtype" begin
    df = DataFrame((; x = [1, 2, 3]))

    for T in (UInt8, UInt16, UInt32, UInt64, Int8, Int16, Int32, Float32)
        r = select(df, col("x") |> cast(T))
        @test eltype(r[:x]) == T
        @test collect(r[:x]) == T[1, 2, 3]
    end

    # Missing target dtype: casts every value to null
    r_null = select(df, col("x") |> cast(Missing))
    @test all(ismissing, collect(r_null[:x]))

    # unsupported target dtype errors
    @test_throws ErrorException cast(Complex{Float64})(col("x"))
end

@testset "cast to parameterized dtypes (DateTime/Duration/Decimal/Categorical)" begin
    df = DataFrame((; x = [1000, 2000, 3000]))

    # DateTime: naive (default) and timezone-aware, each time_unit
    to_dt = select(df, col("x") |> cast(DateTime; time_unit = :ms))
    @test eltype(to_dt[:x]) == DateTime
    @test collect(to_dt[:x]) == [
        DateTime(1970, 1, 1, 0, 0, 1), DateTime(1970, 1, 1, 0, 0, 2), DateTime(1970, 1, 1, 0, 0, 3),
    ]

    to_dt_direct = select(df, cast_datetime(col("x"); time_unit = :ms))
    @test collect(to_dt_direct[:x]) == collect(to_dt[:x])

    to_dt_ns = select(df, col("x") |> cast(DateTime; time_unit = :ns))
    @test eltype(to_dt_ns[:x]) == DateTime

    @test_throws ErrorException cast(col("x"), DateTime; time_unit = :bogus)

    # Duration: via cast(expr, Dates.Millisecond/Microsecond/Nanosecond) and via cast_duration
    to_dur_ms = select(df, col("x") |> cast(Dates.Millisecond))
    @test eltype(to_dur_ms[:x]) == Dates.Millisecond
    @test collect(to_dur_ms[:x]) == Dates.Millisecond.([1000, 2000, 3000])

    to_dur_us = select(df, col("x") |> cast(Dates.Microsecond))
    @test collect(to_dur_us[:x]) == Dates.Microsecond.([1000, 2000, 3000])

    to_dur_ns = select(df, col("x") |> cast(Dates.Nanosecond))
    @test collect(to_dur_ns[:x]) == Dates.Nanosecond.([1000, 2000, 3000])

    to_dur_direct = select(df, cast_duration(col("x"); time_unit = :ms))
    @test collect(to_dur_direct[:x]) == collect(to_dur_ms[:x])

    to_dur_curried = select(df, col("x") |> cast_duration(time_unit = :ms))
    @test collect(to_dur_curried[:x]) == collect(to_dur_ms[:x])

    # Decimal: no Julia read path yet, but the cast itself (and a round trip via write) must not
    # crash -- see cast_decimal's docstring
    to_dec = select(df, cast_decimal(col("x"), 10, 2))
    @test size(to_dec) == (3, 1)
    to_dec_curried = select(df, col("x") |> cast_decimal(10, 2))
    @test size(to_dec_curried) == (3, 1)

    # Categorical: casts, and reads back as String with no extra step
    dfs = DataFrame((; s = ["a", "b", "a", "c"]))
    to_cat = select(dfs, cast_categorical(col("s")))
    @test collect(to_cat[:s]) == ["a", "b", "a", "c"]
end

@testset "Null-dtype DataFrame show/print" begin
    # The full PrettyTables render (MIME"text/plain" -- see P2.5) routes through the same scalar
    # Series getindex as collect() -- a regression guard beyond the collect()-only cases above.
    df = DataFrame((; a = [1, 2, 3]))
    r = select(df, col("a"), lit(missing) |> alias("k"))
    show_str = repr("text/plain", r)
    @test !isempty(show_str)
    @test contains(show_str, "missing")
end
