@testset "arithmetic operators" begin
    df = DataFrame((; x = [1, 2, 3], y = [10, 20, 30]))

    r = select(df, (col("x") + col("y")) |> alias("add"),
                   (col("y") - col("x")) |> alias("sub"),
                   (col("x") * col("y")) |> alias("mul"),
                   (col("y") / col("x")) |> alias("div"),
                   (col("x") ^ 2) |> alias("pow"))
    @test r[:add] == [11, 22, 33]
    @test r[:sub] == [9, 18, 27]
    @test r[:mul] == [10, 40, 90]
    @test collect(r[:div]) == [10.0, 10.0, 10.0]
    @test collect(r[:pow]) == [1, 4, 9]

    # mixed scalar/Expr promotion, both directions
    r2 = select(df, (col("x") + 1) |> alias("addscalar"), (1 + col("x")) |> alias("scalaradd"))
    @test r2[:addscalar] == [2, 3, 4]
    @test r2[:scalaradd] == [2, 3, 4]
end

@testset "comparison operators" begin
    df = DataFrame((; x = [1, 2, 3]))

    @test filter(df, col("x") == 2)[:x] == [2]
    @test filter(df, col("x") < 2)[:x] == [1]
    @test filter(df, col("x") > 2)[:x] == [3]
end

@testset "boolean operators" begin
    df = DataFrame((; a = [true, true, false, false], b = [true, false, true, false]))

    r = select(df, (col("a") & col("b")) |> alias("and"),
                   (col("a") | col("b")) |> alias("or"),
                   xor(col("a"), col("b")) |> alias("xorcol"))
    @test collect(r[:and]) == [true, false, false, false]
    @test collect(r[:or]) == [true, true, true, false]
    @test collect(r[:xorcol]) == [false, true, true, false]
end
