# py-polars/tests/unit/operations/test_cut.py, test_qcut.py

@testset "cut: happy path (py-polars test_cut)" begin
    df = DataFrame((; a = [-2, -1, 0, 1, 2]))

    r = select(df, alias(Polars.cut(col("a"), [-1.0, 1.0]), "a"))
    @test collect(r[:a]) == ["(-inf, -1]", "(-inf, -1]", "(-1, 1]", "(-1, 1]", "(1, inf]"]
end

@testset "cut: null propagation, explicit labels (py-polars test_cut_null_values)" begin
    df = DataFrame((; x = Union{Float64, Missing}[-1.0, missing, 1.0, 2.0, missing, 8.0, 4.0]))

    r = select(df, alias(Polars.cut(col("x"), [1.5, 5.0]; labels = ["a", "b", "c"]), "x"))
    @test isequal(collect(r[:x]), ["a", missing, "a", "b", missing, "c", "b"])
end

@testset "cut: fast-unique breakpoints, both variants (py-polars test_cut_fast_unique_15981)" begin
    df = DataFrame((; x = [1, 2, 3, 4, 5]))

    r1 = select(df, alias(Polars.cut(col("x"), [2.0, 4.0]), "x"))
    @test collect(r1[:x]) == ["(-inf, 2]", "(-inf, 2]", "(2, 4]", "(2, 4]", "(4, inf]"]

    r2 = select(df, alias(Polars.cut(col("x"), [99.0, 101.0]), "x"))
    @test collect(r2[:x]) == fill("(-inf, 99]", 5)
end

@testset "cut: left_closed flips interval boundary semantics" begin
    df = DataFrame((; x = [-2, -1, 0, 1, 2]))

    r_right = select(df, alias(Polars.cut(col("x"), [-1.0, 1.0]; left_closed = false), "x"))
    @test collect(r_right[:x]) == ["(-inf, -1]", "(-inf, -1]", "(-1, 1]", "(-1, 1]", "(1, inf]"]

    r_left = select(df, alias(Polars.cut(col("x"), [-1.0, 1.0]; left_closed = true), "x"))
    @test collect(r_left[:x]) == ["[-inf, -1)", "[-1, 1)", "[-1, 1)", "[1, inf)", "[1, inf)"]
end

@testset "cut: wrong label count raises cleanly (not a process abort)" begin
    df = DataFrame((; x = [1, 2, 3]))
    @test_throws PolarsError select(df, Polars.cut(col("x"), [1.0]; labels = ["a", "b", "c"]))
end

@testset "cut: non-numeric input yields nulls rather than raising" begin
    # divergence from upstream, which rejects the dtype: here every row is silently null. Not a
    # crash, but not an error either -- asserted so the behaviour is pinned rather than assumed.
    df = DataFrame((; x = ["a", "b", "c"]))
    r = select(df, alias(Polars.cut(col("x"), [1.0]), "x"))
    @test all(ismissing, collect(r[:x]))
end

@testset "cut curried form" begin
    df = DataFrame((; x = [-2, -1, 0, 1, 2]))
    r_direct = select(df, alias(Polars.cut(col("x"), [-1.0, 1.0]), "r"))
    r_curried = select(df, alias(col("x") |> Polars.cut([-1.0, 1.0]), "r"))
    @test collect(r_direct[:r]) == collect(r_curried[:r])
end

@testset "qcut: happy path (py-polars test_qcut)" begin
    df = DataFrame((; a = [-2, -1, 0, 1, 2]))

    r = select(df, alias(qcut(col("a"), [0.25, 0.5]), "a"))
    @test collect(r[:a]) == ["(-inf, -1]", "(-inf, -1]", "(-1, 0]", "(0, inf]", "(0, inf]"]
end

@testset "qcut_uniform: bin count + labels + left_closed (py-polars test_qcut_n)" begin
    df = DataFrame((; a = [-2, -1, 0, 1, 2]))

    r = select(df, alias(qcut_uniform(col("a"), 2; labels = ["x", "y"], left_closed = true), "a"))
    @test collect(r[:a]) == ["x", "x", "y", "y", "y"]
end

@testset "qcut: null propagation, explicit labels (py-polars test_qcut_null_values)" begin
    df = DataFrame((; x = Union{Float64, Missing}[-1.0, missing, 1.0, 2.0, missing, 8.0, 4.0]))

    r = select(df, alias(qcut(col("x"), [0.2, 0.3]; labels = ["a", "b", "c"]), "x"))
    @test isequal(collect(r[:x]), ["a", missing, "b", "c", missing, "c", "c"])
end

@testset "qcut: all-null input short-circuits to all-missing, with or without labels (py-polars test_qcut_full_null / test_qcut_full_null_with_labels)" begin
    df = DataFrame((; a = Union{Float64, Missing}[missing, missing, missing, missing]))

    # all-null short-circuits: no breakpoints are computed, so every row is simply null. This is
    # distinct from all-NaN below, which reaches the breakpoint computation and raises.
    r = select(df, alias(qcut(col("a"), [0.25, 0.5]), "a"))
    @test all(ismissing, collect(r[:a]))

    # the all-null short-circuit bypasses label-count validation entirely
    r_labelled = select(df, alias(qcut(col("a"), [0.25, 0.5]; labels = ["1", "2", "3"]), "a"))
    @test all(ismissing, collect(r_labelled[:a]))
end

@testset "qcut: allow_duplicates (py-polars test_qcut_allow_duplicates)" begin
    df = DataFrame((; x = [1, 2, 2, 3]))

    @test_throws PolarsError select(df, qcut(col("x"), [0.5, 0.51]))

    r = select(df, alias(qcut(col("x"), [0.5, 0.51]; allow_duplicates = true), "x"))
    @test collect(r[:x]) == ["(-inf, 2]", "(-inf, 2]", "(-inf, 2]", "(2, inf]"]
end

@testset "qcut: NaN dropped from breakpoint computation, propagates as missing (py-polars test_qcut_nan_input_values)" begin
    df = DataFrame((; a = [1.0, 2.0, 3.0, 4.0, NaN]))

    # polars-ops 0.55.2 fixed the panic from the previous divergence noted here (a None-unwrap in
    # cut.rs on NaN input, polars-ops-0.54.4 src/series/ops/cut.rs:206): NaN is now dropped before
    # computing breakpoints and the NaN row comes back null, matching upstream's documented
    # behavior.
    r = select(df, alias(qcut(col("a"), [0.5, 1.0]), "a"))
    @test isequal(collect(r[:a]), ["(-inf, 2.5]", "(-inf, 2.5]", "(2.5, 4]", "(2.5, 4]", missing])
end

@testset "qcut: all-NaN input does not abort the process, regression (py-polars test_qcut_full_nan)" begin
    df = DataFrame((; a = [NaN, NaN]))

    # same fix as the NaN-mixed case above: now returns all-null rather than raising.
    r = select(df, alias(qcut(col("a"), [0.25, 0.5]), "a"))
    @test isequal(collect(r[:a]), [missing, missing])
end

@testset "qcut: infinite input gives a NaN breakpoint, raises cleanly (py-polars test_qcut_inf_breakpoint_raises)" begin
    df = DataFrame((; a = [Inf, -Inf]))
    @test_throws PolarsError select(df, qcut(col("a"), [0.3, 0.6]))
end

@testset "qcut: NaN with infinities raises (py-polars test_qcut_inf_breakpoint_raises)" begin
    # polars-ops 0.55.2 also fixed the previous divergence here: this used to silently produce a
    # single (-inf, inf] bucket with the NaN row null; it now raises on the NaN breakpoint like the
    # infinite-input case above, matching upstream.
    df = DataFrame((; a = [NaN, Inf, -Inf]))
    @test_throws PolarsError collect(select(df, alias(qcut(col("a"), [0.5]), "a")))
end

@testset "qcut/qcut_uniform curried forms" begin
    df = DataFrame((; x = [-2, -1, 0, 1, 2]))

    r_direct = select(df, alias(qcut(col("x"), [0.25, 0.5]), "r"))
    r_curried = select(df, alias(col("x") |> qcut([0.25, 0.5]), "r"))
    @test collect(r_direct[:r]) == collect(r_curried[:r])

    ru_direct = select(df, alias(qcut_uniform(col("x"), 2), "r"))
    ru_curried = select(df, alias(col("x") |> qcut_uniform(2), "r"))
    @test collect(ru_direct[:r]) == collect(ru_curried[:r])
end
