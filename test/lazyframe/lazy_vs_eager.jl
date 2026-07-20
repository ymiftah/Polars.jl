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

@testset "LazyFrame/LazyGroupBy show (P2.5)" begin
    # Used to dump the raw `mutable struct` with its `Ptr` field (e.g.
    # `Polars.LazyFrame(Ptr{...}(0x...))`) -- meaningless to a user and non-reproducible between
    # runs. `LazyFrame` now shows its column names via the cheap, non-executing
    # `collect_schema`; `LazyGroupBy` has no resolved schema of its own to show (that depends on
    # the `agg()` call that hasn't happened yet) so it gets a minimal placeholder instead.
    df = DataFrame((; x = [1, 2, 3], y = ["a", "b", "c"]))
    lf = lazy(df)

    s = sprint(show, lf)
    @test !contains(s, "Ptr")
    @test contains(s, "x")
    @test contains(s, "y")

    # an unresolvable plan (references a non-existent column) must not make `show` itself throw
    bad_lf = filter(lf, col("nonexistent") > 1)
    @test !isempty(sprint(show, bad_lf))

    gb = group_by(lf, "x")
    s_gb = sprint(show, gb)
    @test !contains(s_gb, "Ptr")
    @test !isempty(s_gb)
end
