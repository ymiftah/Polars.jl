@testset "fill_null / fill_nan" begin
    df = DataFrame((; x = [1.0, missing, 3.0, NaN]))

    r = select(df, fill_null(col("x"), lit(0.0)) |> alias("filled"))
    @test r[:filled][1] == 1.0
    @test r[:filled][2] == 0.0
    @test r[:filled][3] == 3.0
    @test isnan(r[:filled][4])

    df2 = DataFrame((; x = [1.0, NaN, missing, 4.0]))
    r2 = select(df2, fill_nan(col("x"), lit(-1.0)) |> alias("filled"))
    @test r2[:filled][1] == 1.0
    @test r2[:filled][2] == -1.0
    @test ismissing(r2[:filled][3])
    @test r2[:filled][4] == 4.0
end

@testset "is_in" begin
    df = DataFrame((; g = ["a", "a", "b", "c"]))

    # membership set built from a literal list expression via implode
    membership = implode(lit("a"))
    r = select(df, is_in(col("g"), membership) |> alias("is_a"))
    @test r[:is_a] == [true, true, false, false]

    filtered = filter(df, is_in(col("g"), membership))
    @test filtered[:g] == ["a", "a"]
end
