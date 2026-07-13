@testset "Lazy vs Eager" begin
    table = (; x = randn(Float32, 100), cond = rand(Bool, 100))
    df = DataFrame(table)

    function selector(df)
        df = with_columns(df, cos(col("x") * 1.5) |> alias("tmp"))
        filter(df, col("cond") & (col("x") < 0.0))
    end

    df2 = df |> lazy |> selector |> collect
    df = selector(df)

    @test df[:tmp] == df2[:tmp]
end
