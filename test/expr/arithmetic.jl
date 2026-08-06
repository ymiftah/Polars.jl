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

@testset "unary negation (-expr) (see plans/parity/gap_closure_scope.md)" begin
    df = DataFrame((; a = Union{Missing, Int}[1, -2, 3, missing]))
    r = select(df, alias(-col("a"), "n"))
    @test isequal(collect(r[:n]), [-1, 2, -3, missing])
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

@testset "boolean operators Kleene three-valued logic with missing" begin
    # `&`/`|` on Polars.jl route through the same Rust `Expr::and`/`Expr::or` as py-polars'
    # `&`/`|` dunders (verified against `polars-compute`'s `boolean::and`/`or` kernel source,
    # explicitly Kleene-logic), so a `false`/`true` operand short-circuits regardless of a
    # `missing` on the other side -- distinct from strict null propagation, where any missing
    # operand would poison the whole row.
    df = DataFrame((; a = [false, true, missing], b = Union{Missing, Bool}[missing, missing, missing]))
    r = select(df, alias(col("a") & col("b"), "and"), alias(col("a") | col("b"), "or"))
    @test isequal(collect(r[:and]), [false, missing, missing]) # false & anything = false
    @test isequal(collect(r[:or]), [missing, true, missing]) # true | anything = true

    # bitwise `|`/`&` also work on plain integer columns (not just Bool), per py-polars'
    # test_bitwise_6311 -- these are the same Rust operator, not a separate boolean-only path
    df_int = DataFrame((; flag = [0, 0, 0, 0]))
    r_int = select(df_int, alias(Polars.or(col("flag"), lit(2)), "flag"))
    @test collect(r_int[:flag]) == [2, 2, 2, 2]
end

@testset "arithmetic null propagation (py-polars test_arithmetic_null_count / test_null_column_arithmetic)" begin
    # one operand missing per-row, both broadcast directions
    df = DataFrame((; a = [1, missing, 2], b = [missing, 2, 1]))
    r = select(
        df, alias(col("a") + col("b"), "add"),
        alias(lit(1) + col("b"), "broadcast_left"),
        alias(col("a") + lit(1), "broadcast_right"),
    )
    @test isequal(collect(r[:add]), [missing, missing, 3])
    @test isequal(collect(r[:broadcast_left]), [missing, 3, 2])
    @test isequal(collect(r[:broadcast_right]), [2, missing, 3])

    # an entirely-null column: every row of the result is missing, not an error. Uses an
    # explicitly-typed `Union{Missing,Int}` fixture rather than the bare `[missing, missing]`
    # literal -- the latter constructs as a plain `Vector{Missing}`, which currently crashes
    # DataFrame construction with an UndefVarError (see plans/parity/batch-1-math-arithmetic.md;
    # genuine Julia-side gap, deferred to the dataframe/construction.jl batch, not this one).
    df_null = DataFrame((; a = Union{Missing, Int}[missing, missing], b = Union{Missing, Int}[missing, missing]))
    r_null = select(df_null, alias(col("a") + col("b"), "add"))
    @test isequal(collect(r_null[:add]), [missing, missing])
end

@testset "pow: null exponent raises cleanly (py-polars test_power_series, Step 5 process-abort check)" begin
    df = DataFrame((; a = [1, 2]))
    @test_throws PolarsError select(df, alias(col("a")^lit(missing), "a"))
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
    @test r_pow[:pow][2] ≈ 1 / 9

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

@testset "floor_div" begin
    # float operands: floor_div rounds down towards negative infinity, unlike div/`/` (the exact
    # quotient) -- this is the behavior Dt.epoch relies on for pre-1970 (negative) timestamps.
    df = DataFrame((; a = [-1.0, 7.5, -7.5], b = [2.0, 2.0, 2.0]))
    r = select(df, alias(floor_div(col("a"), col("b")), "fd"), alias(div(col("a"), col("b")), "d"))
    @test collect(r[:fd]) == [-1.0, 3.0, -4.0]
    @test collect(r[:d]) == [-0.5, 3.75, -3.75]

    # integer operands: div/`/` already floors here, so floor_div agrees with it exactly
    df_int = DataFrame((; a = Int64[-1, 1, -1, 1, 7, -7], b = Int64[2, 2, -2, -2, 2, 2]))
    r_int = select(df_int, alias(floor_div(col("a"), col("b")), "fd"), alias(div(col("a"), col("b")), "d"))
    @test collect(r_int[:fd]) == collect(r_int[:d]) == [-1, 0, 0, -1, 3, -4]
end

@testset "derived comparison operators: <=, >=, != (Julia-side P2.1)" begin
    # polars' C ABI only wraps `eq`/`lt`/`gt` directly; `<=`/`>=`/`!=` are composed from those via
    # `not` (see `_le`/`_ge`/`_neq` in expr/expr.jl). Must agree with `eq`/`lt`/`gt` themselves,
    # including on rows with a null operand (where `not` must propagate null, not just flip a
    # `Bool`, for `<=`/`>=`/`!=` to have the right null semantics).
    df = DataFrame((; x = [1, 2, 3, missing], y = [2, 2, 2, 2]))

    r = select(
        df,
        (col("x") <= col("y")) |> alias("le"),
        (col("x") >= col("y")) |> alias("ge"),
        (col("x") != col("y")) |> alias("ne"),
    )
    @test isequal(collect(r[:le]), [true, true, false, missing])
    @test isequal(collect(r[:ge]), [false, true, true, missing])
    @test isequal(collect(r[:ne]), [true, false, true, missing])
end

@testset "arccos / degrees / radians (API gap batch four, Phase 1; fixture mirrors py-polars' test_trigonometric)" begin
    # Upstream's exact fixture (`test_trigonometric` in series_test.py, parametrized over `arccos`
    # among others): null propagates as null, NaN propagates as NaN, and `arccos(π)` is NaN because
    # π > 1 is out of arccos's [-1, 1] domain -- the edge a happy-path-only fixture would miss.
    dftrig = DataFrame((; a = Union{Float64, Missing}[0.0, π, missing, NaN]))

    r = select(dftrig, alias(arccos(col("a")), "arccos"))
    out = collect(r[:arccos])
    @test out[1] ≈ acos(0.0)
    @test isnan(out[2]) # out-of-domain (π > 1), not an error
    @test ismissing(out[3])
    @test isnan(out[4])

    # degrees/radians over the same fixture, at least the null case (both are pure elementwise
    # linear scalings with no domain restriction, so no analogous NaN-from-domain case exists)
    r2 = select(dftrig, alias(degrees(col("a")), "deg"), alias(radians(col("a")), "rad"))
    deg = collect(r2[:deg])
    rad = collect(r2[:rad])
    @test deg[1] ≈ 0.0 && rad[1] ≈ 0.0
    @test deg[2] ≈ 180.0 && rad[2] ≈ π * π / 180
    @test ismissing(deg[3]) && ismissing(rad[3])
    @test isnan(deg[4]) && isnan(rad[4])

    # test_trigonometric_invalid_input: a String column must raise a catchable PolarsError, not
    # abort the process -- CLAUDE.md documents two real incidents of exactly this failure mode for
    # other functions, so this matters more here than it does upstream. Message text is
    # deliberately not asserted on, only that it raises cleanly.
    dfstr = DataFrame((; s = ["1", "2", "3"]))
    @test_throws PolarsError select(dfstr, arccos(col("s")))
end

@testset "arcsin / arctan (py-polars test_trigonometric fixture)" begin
    # Same fixture/shape as the `arccos` testset above: null propagates, NaN propagates,
    # `arcsin(π)` is NaN (π > 1, out of arcsin's [-1, 1] domain) while `arctan` has no domain
    # restriction at all.
    dftrig = DataFrame((; a = Union{Float64, Missing}[0.0, π, missing, NaN]))

    r = select(dftrig, alias(arcsin(col("a")), "asin"), alias(arctan(col("a")), "atan"))
    asin_out = collect(r[:asin])
    atan_out = collect(r[:atan])

    @test asin_out[1] ≈ asin(0.0)
    @test isnan(asin_out[2]) # out-of-domain (π > 1), not an error
    @test ismissing(asin_out[3])
    @test isnan(asin_out[4])

    @test atan_out[1] ≈ atan(0.0)
    @test atan_out[2] ≈ atan(π) # no domain restriction
    @test ismissing(atan_out[3])
    @test isnan(atan_out[4])

    dfstr = DataFrame((; s = ["1", "2", "3"]))
    @test_throws PolarsError select(dfstr, arcsin(col("s")))
    @test_throws PolarsError select(dfstr, arctan(col("s")))
end

@testset "log1p / log10 (API gap batch four, Phase 1; domain edges per py-polars' test_exp_log1p)" begin
    dflog = DataFrame((; x = [0.0, -1.0, -2.0, 1.0, 9.0]))
    r = select(dflog, alias(Base.log1p(col("x")), "log1p"))
    out = collect(r[:log1p])
    @test out[1] == 0.0
    @test isinf(out[2]) && out[2] < 0 # log1p(-1) -> -Inf
    @test isnan(out[3]) # log1p(-2) -> NaN, below domain
    @test out[4] ≈ Base.log1p(1.0)
    @test out[5] ≈ Base.log1p(9.0)

    dflog10 = DataFrame((; x = [1.0, 10.0, 100.0, 0.0, -5.0]))
    r2 = select(dflog10, alias(Base.log10(col("x")), "log10"))
    out2 = collect(r2[:log10])
    @test out2[1:3] ≈ [0.0, 1.0, 2.0]
    @test isinf(out2[4]) && out2[4] < 0 # log10(0) -> -Inf
    @test isnan(out2[5]) # log10(negative) -> NaN

    # missing passthrough for both
    dfmissing = DataFrame((; x = Union{Float64, Missing}[1.0, missing]))
    r3 = select(dfmissing, alias(Base.log1p(col("x")), "log1p"), alias(Base.log10(col("x")), "log10"))
    @test ismissing(collect(r3[:log1p])[2])
    @test ismissing(collect(r3[:log10])[2])
end

@testset "Expr <: Number was dropped -- explicit mixed-argument operators (Julia-side P2.1)" begin
    df = DataFrame((; x = [1, 2, 3]))

    # both mixed-argument orders, for every operator category -- note operand order matters for
    # the non-symmetric comparisons (`2 <= col("x")` is "is 2 <= x", the reverse of
    # `col("x") <= 2`), unlike `!=` which is symmetric either way
    r = select(
        df,
        (col("x") <= 2) |> alias("le1"), (2 <= col("x")) |> alias("le2"),
        (col("x") >= 2) |> alias("ge1"), (2 >= col("x")) |> alias("ge2"),
        (col("x") != 2) |> alias("ne1"), (2 != col("x")) |> alias("ne2"),
    )
    @test collect(r[:le1]) == [true, true, false]
    @test collect(r[:le2]) == [false, true, true]
    @test collect(r[:ge1]) == [false, true, true]
    @test collect(r[:ge2]) == [true, true, false]
    @test collect(r[:ne1]) == collect(r[:ne2]) == [true, false, true]

    # a literal `missing` operand builds a real null-literal comparison, not Julia's own
    # `missing`-propagation short-circuit (which would return the bare value `missing`, not an
    # `Expr`) -- this is what resolves the `Expr`/`Missing` method ambiguity described in
    # expr/expr.jl.
    for expr in (
            col("x") == missing, missing == col("x"),
            col("x") < missing, missing < col("x"),
            col("x") + missing, missing + col("x"),
        )
        @test expr isa Polars.Expr
    end

    # dot-broadcasting treats `Expr` as a scalar rather than trying to iterate it
    @test collect(select(df, col("x") .> 1)[:x]) == [false, true, true]

    # `isless`/`isequal`/sorting a `Vector{Expr}` are deliberately unsupported: an `Expr`
    # comparison builds another `Expr`, and answering with that instead of a `Bool` would violate
    # both functions' contracts
    @test_throws MethodError isless(col("x"), col("y"))
    @test_throws MethodError sort([col("x"), col("y")])
end
