@testset "arithmetic operators" begin
    df = DataFrame((; x = [1, 2, 3], y = [10, 20, 30]))

    r = select(
        df, (col("x") + col("y")) |> alias("add"),
        (col("y") - col("x")) |> alias("sub"),
        (col("x") * col("y")) |> alias("mul"),
        (col("y") / col("x")) |> alias("div"),
        (col("x")^2) |> alias("pow")
    )
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

    r = select(
        df, (col("a") & col("b")) |> alias("and"),
        (col("a") | col("b")) |> alias("or"),
        xor(col("a"), col("b")) |> alias("xorcol")
    )
    @test collect(r[:and]) == [true, false, false, false]
    @test collect(r[:or]) == [true, true, true, false]
    @test collect(r[:xorcol]) == [false, true, true, false]
end

@testset "arithmetic edge cases" begin
    # Division by zero produces Inf (for float division)
    df_div = DataFrame((; x = [1.0, 2.0, 3.0], y = [1.0, 0.0, -1.0]))
    r_div = select(df_div, col("x") / col("y") |> alias("div"))
    @test r_div[:div][1] == 1.0
    @test isinf(r_div[:div][2]) && r_div[:div][2] > 0
    @test r_div[:div][3] == -3.0

    # Negative exponent produces fractional result
    df_pow = DataFrame((; x = [2.0, 3.0], n = [-1.0, -2.0]))
    r_pow = select(df_pow, col("x")^col("n") |> alias("pow"))
    @test r_pow[:pow][1] ≈ 0.5
    @test r_pow[:pow][2] ≈ 1/9

    # Modulo operation
    df_mod = DataFrame((; x = [10, 11, 12], y = [3, 3, 3]))
    r_mod = select(df_mod, (col("x") % col("y")) |> alias("rem"))
    @test collect(r_mod[:rem]) == [1, 2, 0]
end

@testset "direct-call arithmetic functions" begin
    # These functions are often called via operators, but also exist as direct callables
    df = DataFrame((; x = [1, 2, 3], y = [2, 2, 2]))

    # Direct-call forms should match operator forms
    r_op = select(df, (col("x") + col("y")) |> alias("add"))
    r_fn = select(df, add(col("x"), col("y")) |> alias("add"))
    @test r_op[:add] == r_fn[:add]

    r_op_sub = select(df, (col("x") - col("y")) |> alias("sub"))
    r_fn_sub = select(df, sub(col("x"), col("y")) |> alias("sub"))
    @test r_op_sub[:sub] == r_fn_sub[:sub]

    r_op_mul = select(df, (col("x") * col("y")) |> alias("mul"))
    r_fn_mul = select(df, mul(col("x"), col("y")) |> alias("mul"))
    @test r_op_mul[:mul] == r_fn_mul[:mul]

    r_op_div = select(df, (col("x") / col("y")) |> alias("div"))
    r_fn_div = select(df, div(col("x"), col("y")) |> alias("div"))
    @test collect(r_op_div[:div]) == collect(r_fn_div[:div])

    r_op_pow = select(df, (col("x")^2) |> alias("pow"))
    r_fn_pow = select(df, pow(col("x"), lit(2)) |> alias("pow"))
    @test collect(r_op_pow[:pow]) == collect(r_fn_pow[:pow])

    r_op_rem = select(df, (col("x") % col("y")) |> alias("rem"))
    r_fn_rem = select(df, rem(col("x"), col("y")) |> alias("rem"))
    @test collect(r_op_rem[:rem]) == collect(r_fn_rem[:rem])

    # Comparison functions
    r_eq = select(df, eq(col("x"), col("y")) |> alias("eq"))
    @test collect(r_eq[:eq]) == [false, true, false]

    # lt collides with the non-exported Base.lt (used internally for sorting), so Polars
    # extends that method directly instead of exporting a bare `lt`
    r_lt = select(df, Base.lt(col("x"), col("y")) |> alias("lt"))
    @test collect(r_lt[:lt]) == [true, false, false]

    r_gt = select(df, gt(col("x"), col("y")) |> alias("gt"))
    @test collect(r_gt[:gt]) == [false, false, true]

    # Boolean functions
    r_and = select(df, and(col("x") > 1, col("y") == 2) |> alias("and"))
    @test collect(r_and[:and]) == [false, true, true]

    r_or = select(df, or(col("x") < 2, col("y") > 2) |> alias("or"))
    @test collect(r_or[:or]) == [true, false, false]
end
