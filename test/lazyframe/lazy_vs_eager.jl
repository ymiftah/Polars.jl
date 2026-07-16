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

@testset "LazyFrame reusability" begin
    df = DataFrame((; x = [1, 2, 3, 4, 5]))
    lf = lazy(df)

    # collecting the same LazyFrame twice gives equal results -- collect doesn't consume it
    r1 = collect(lf)
    r2 = collect(lf)
    @test r1[:x] == r2[:x]

    # deriving two different frames from the same lf via different verbs doesn't
    # cross-contaminate -- each verb clones internally before mutating
    doubled = with_columns(lf, (col("x") * 2) |> alias("y")) |> collect
    filtered = filter(lf, col("x") > 2) |> collect
    @test Tables.columnnames(doubled) == (:x, :y)
    @test Tables.columnnames(filtered) == (:x,)
    @test collect(lf)[:x] == df[:x]  # original lf still usable, unaffected by either derivation

    # Polars.clone produces an independently usable copy
    lf_clone = Polars.clone(lf)
    @test collect(lf_clone)[:x] == collect(lf)[:x]
end
