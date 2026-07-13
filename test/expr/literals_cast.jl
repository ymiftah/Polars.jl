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
