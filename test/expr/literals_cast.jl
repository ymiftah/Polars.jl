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

@testset "Null-dtype DataFrame show/print" begin
    # The full PrettyTables render (MIME"text/plain" -- see P2.5) routes through the same scalar
    # Series getindex as collect() -- a regression guard beyond the collect()-only cases above.
    df = DataFrame((; a = [1, 2, 3]))
    r = select(df, col("a"), lit(missing) |> alias("k"))
    show_str = repr("text/plain", r)
    @test !isempty(show_str)
    @test contains(show_str, "missing")
end
