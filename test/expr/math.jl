@testset "round / clip" begin
    df = DataFrame((; x = [1.234, -1.234, 2.5, -2.5]))

    r = select(df, alias(Base.round(col("x"), 1), "r1"))
    @test r[:r1] ≈ [1.2, -1.2, 2.5, -2.5]

    r0 = select(df, alias(Base.round(col("x")), "r0"))
    @test r0[:r0] ≈ [1.0, -1.0, 2.0, -2.0] # :half_to_even (banker's rounding)

    df_ties = DataFrame((; x = [2.5, -2.5]))
    r_away = select(df_ties, alias(Base.round(col("x"); mode = :half_away_from_zero), "r"))
    @test r_away[:r] ≈ [3.0, -3.0]

    @test_throws ErrorException Base.round(col("x"); mode = :bogus)

    df2 = DataFrame((; x = [1.0, 5.0, 10.0]))
    r_clip = select(df2, alias(clip(col("x"), lit(2.0), lit(8.0)), "c"))
    @test r_clip[:c] == [2.0, 5.0, 8.0]

    # round on an integer column is a no-op (py-polars test_round_int)
    df_int = DataFrame((; x = [1, 2, 3]))
    r_int = select(df_int, alias(Base.round(col("x")), "r"))
    @test r_int[:r] == [1, 2, 3]

    # clip: a null bound (per-row, not a scalar) passes that side through unclamped -- upstream
    # test_clip_int's exact fixture, including its own missing/mixed-bound rows
    df_clip_null = DataFrame(
        (;
            a = [1, 2, 3, 4, 5, missing],
            mn = [0, -1, 4, missing, 4, -10],
            mx = [2, 1, 8, 5, missing, 10],
        )
    )
    r_clip_null = select(df_clip_null, alias(clip(col("a"), col("mn"), col("mx")), "clip"))
    @test isequal(collect(r_clip_null[:clip]), [1, 1, 4, 4, 5, missing])
end

@testset "clip_min / clip_max: single-sided clip, missing passes through (see plans/parity/gap_closure_scope.md)" begin
    df = DataFrame((; a = Union{Missing, Int}[1, 5, 10, missing]))

    r_min = select(df, alias(clip_min(col("a"), 3), "n"))
    @test isequal(collect(r_min[:n]), [3, 5, 10, missing])

    r_max = select(df, alias(clip_max(col("a"), 3), "n"))
    @test isequal(collect(r_max[:n]), [1, 3, 3, missing])

    # curried forms for |> pipelines
    r_min_curried = select(df, alias(col("a") |> clip_min(3), "n"))
    @test isequal(collect(r_min_curried[:n]), collect(r_min[:n]))
    r_max_curried = select(df, alias(col("a") |> clip_max(3), "n"))
    @test isequal(collect(r_max_curried[:n]), collect(r_max[:n]))
end

@testset "log / exp / sqrt / sign / %" begin
    df = DataFrame((; x = [1.0, 4.0, 9.0]))

    r = select(
        df, alias(Base.log(lit(2.0), col("x")), "log2"),
        alias(Polars.exp(col("x")), "exp"),
        alias(Base.sqrt(col("x")), "sqrt"),
        alias(Polars.sign(col("x") .- 4.0), "sign")
    )
    @test r[:log2] ≈ log2.([1.0, 4.0, 9.0])
    @test r[:exp] ≈ exp.([1.0, 4.0, 9.0])
    @test r[:sqrt] ≈ [1.0, 2.0, 3.0]
    @test r[:sign] == [-1.0, 0.0, 1.0]

    df2 = DataFrame((; x = [7, 8, 9, 10]))
    r2 = select(df2, alias(col("x") % lit(3), "m"))
    @test r2[:m] == [1, 2, 0, 1]
end

@testset "sqrt / log / abs domain edges and wrong-dtype (py-polars test_sqrt_neg_inf, test_log_exp, test_abs_non_numeric)" begin
    # sqrt of negative -> NaN, sqrt(0) -> 0, sqrt(Inf) -> Inf -- upstream's exact fixture
    df_sqrt = DataFrame((; val = [-Inf, -9.0, 0.0, 9.0, Inf]))
    r_sqrt = select(df_sqrt, alias(Base.sqrt(col("val")), "sqrt"))
    out_sqrt = collect(r_sqrt[:sqrt])
    @test isnan(out_sqrt[1]) && isnan(out_sqrt[2])
    @test out_sqrt[3] == 0.0 && out_sqrt[4] == 3.0 && isinf(out_sqrt[5]) && out_sqrt[5] > 0

    # log domain edges: log(0) -> -Inf, log(negative) -> NaN (base e via lit(exp(1.0)); note the
    # base comes first, matching Base.log(b, x) -- see CLAUDE.md's `@wrap_simple_ops` note)
    df_log = DataFrame((; x = [0.0, -1.0, exp(1.0)]))
    r_log = select(df_log, alias(Base.log(lit(exp(1.0)), col("x")), "ln"))
    out_log = collect(r_log[:ln])
    @test isinf(out_log[1]) && out_log[1] < 0
    @test isnan(out_log[2])
    @test out_log[3] ≈ 1.0

    # abs: missing propagates, non-numeric (String) raises a clean PolarsError rather than
    # aborting the process (Step 5 -- process-abort check, see CLAUDE.md)
    df_abs = DataFrame((; a = [-1, 0, 1, missing]))
    r_abs = select(df_abs, alias(abs(col("a")), "a"))
    @test isequal(collect(r_abs[:a]), [1, 0, 1, missing])

    df_abs_str = DataFrame((; a = ["p", "q", "r"]))
    @test_throws PolarsError select(df_abs_str, alias(abs(col("a")), "a"))
end

@testset "is_between (py-polars test_is_between / test_is_between_data_types)" begin
    # upstream fixture is fruits_cars_df()'s A column, [1, 2, 3, 4, 5]
    df = fruits_cars_df()

    r = select(df, alias(is_between(col("A"), 2, 4), "b"))
    @test r[:b] == [false, true, true, true, false]

    r = select(df, alias(is_between(col("A"), 2, 4; closed = :both), "b"))
    @test r[:b] == [false, true, true, true, false]

    r = select(df, alias(is_between(col("A"), 2, 4; closed = :none), "b"))
    @test r[:b] == [false, false, true, false, false]

    r = select(df, alias(is_between(col("A"), 2, 4; closed = :left), "b"))
    @test r[:b] == [false, true, true, false, false]

    r = select(df, alias(is_between(col("A"), 2, 4; closed = :right), "b"))
    @test r[:b] == [false, false, true, true, false]

    @test_throws ErrorException is_between(col("A"), 2, 4; closed = :bogus)

    # non-numeric bounds: strings and dates must not be silently numeric-only
    df_types = DataFrame(
        (;
            flt = [1.4, 1.2, 2.5],
            str = ["xyz", "str", "abc"],
            dt = [Date(2020, 1, 1), Date(2020, 2, 2), Date(2020, 3, 3)],
        )
    )
    r_flt = select(df_types, alias(is_between(col("flt"), 1, 2.3), "b"))
    @test r_flt[:b] == [true, true, false]

    r_str = select(df_types, alias(is_between(col("str"), "aaa", "s"), "b"))
    @test r_str[:b] == [false, false, true]

    r_dt = select(df_types, alias(is_between(col("dt"), Date(2020, 1, 15), Date(2020, 3, 1)), "b"))
    @test r_dt[:b] == [false, true, false]
end

@testset "arctan2/dot (py-polars sql/test_trigonometric.py::test_arctan2, expr/test_exprs.py::test_dot_in_group_by, series/test_series.py::test_dot)" begin
    # quadrant fixture straight from upstream's own arctan2 test (sql/test_trigonometric.py):
    # y/x = ±√2/2 in every sign combination, covering all four quadrants -- expected values are
    # the SQL test's ATAN2D degrees fixture converted to radians ([45,-45,135,-135]°)
    sq = sqrt(2) / 2
    df_quad = DataFrame((; y = [sq, -sq, sq, -sq], x = [sq, sq, -sq, -sq]))
    r_quad = select(df_quad, alias(arctan2(col("y"), col("x")), "a"))
    @test r_quad[:a] ≈ [π / 4, -π / 4, 3π / 4, -3π / 4]

    df = DataFrame((; x = [1.0, 2.0, 3.0, 4.0]))

    # arctan2(y, x) -- note the y-then-x argument order (matches upstream and C's atan2)
    r = select(df, alias(arctan2(col("x"), lit(1.0)), "a"))
    @test r[:a] ≈ atan.(df[:x], 1.0)

    # dot product: sum of elementwise product
    r_dot = select(df, alias(dot(col("x"), col("x")), "d"))
    @test only(r_dot[:d]) == 30.0

    # grouped dot, upstream's exact fixture (expr/test_exprs.py::test_dot_in_group_by): group "a"
    # is rows 1:3 of x=[1,1,1,1,1,1] against y=[1,2,3,4,5,6] -> 1+2+3=6; group "b" -> 4+5+6=15
    df_grp = DataFrame(
        (;
            group = ["a", "a", "a", "b", "b", "b"],
            gx = [1, 1, 1, 1, 1, 1],
            gy = [1, 2, 3, 4, 5, 6],
        )
    )
    r_grp = collect(agg(group_by(lazy(df_grp), "group"; maintain_order = true), alias(dot(col("gx"), col("gy")), "dot")))
    @test collect(r_grp[:group]) == ["a", "b"]
    @test collect(r_grp[:dot]) == [6, 15]

    # null propagation: dot's sum ignores the null pairwise product, matching Expr::sum
    dfm = DataFrame((; x = Union{Float64, Missing}[1.0, missing]))
    r_dot_null = select(dfm, alias(dot(col("x"), col("x")), "d"))
    @test only(r_dot_null[:d]) == 1.0

    # arctan2 null propagation
    dfm2 = DataFrame((; x = Union{Float64, Missing}[1.0, missing]))
    r_null = select(dfm2, alias(arctan2(col("x"), lit(1.0)), "a"))
    @test isequal(collect(r_null[:a]), [atan(1.0, 1.0), missing])

    # dtype coercion, not a raise: arctan2 non-strictly casts a non-float operand to Float64 --
    # confirmed against upstream Rust (`crates/polars-expr/src/dispatch/trigonometry.rs`:
    # `arctan2_on_columns` falls through to `y.cast(&DataType::Float64)?` for any non-float
    # dtype). A parseable numeric string coerces; an unparseable one becomes `missing`, it does
    # NOT raise -- unlike the unary trig functions (`sin`, `cosh`, ...), which upstream's own
    # test_trigonometric_invalid_input asserts DO raise on a String column.
    df_str = DataFrame((; a = ["1.0", "2.0", "abc"]))
    r_str = select(df_str, alias(arctan2(col("a"), col("a")), "a"))
    @test isequal(collect(r_str[:a]), [atan(1.0, 1.0), atan(2.0, 2.0), missing])

    # wrong-dtype raises cleanly for dot (Step 5 -- process-abort check)
    df_dot_str = DataFrame((; a = ["p", "q", "r"]))
    @test_throws PolarsError select(df_dot_str, alias(dot(col("a"), col("a")), "d"))
end

@testset "entropy (py-polars series.py docstring, expr/test_exprs.py::test_entropy)" begin
    df = DataFrame((; y = [1, 1, 2, 2]))
    r = select(df, alias(entropy(col("y")), "e"))
    @test only(r[:e]) ≈ 1.3296613488547582

    # curried form (keyword-only, for |> pipelines)
    r2 = select(df, alias(col("y") |> entropy(), "e"))
    @test only(r2[:e]) ≈ 1.3296613488547582

    # base=2 gives a different value than the natural-log default
    r_base2 = select(df, alias(entropy(col("y"); base = 2), "e"))
    @test only(r_base2[:e]) != only(r[:e])

    # grouped entropy, upstream's exact fixture (expr/test_exprs.py::test_entropy),
    # normalize=True (our default): three groups over id=[1,2,1,4,5,4,6,7]
    df_grp = DataFrame(
        (;
            group = ["A", "A", "A", "B", "B", "B", "B", "C"],
            id = [1, 2, 1, 4, 5, 4, 6, 7],
        )
    )
    r_grp = collect(agg(group_by(lazy(df_grp), "group"; maintain_order = true), alias(entropy(col("id"); normalize = true), "id")))
    @test collect(r_grp[:group]) == ["A", "B", "C"]
    @test collect(r_grp[:id]) ≈ [1.0397207708399179, 1.371381017771811, 0.0]

    # base/normalize default check (py-polars series.py: `def entropy(self, base=math.e, *,
    # normalize=True)`) -- Series.entropy() docstring's own example fixture
    df_doc = DataFrame((; a = [0.99, 0.005, 0.005]))
    r_doc = select(df_doc, alias(entropy(col("a"); normalize = true), "e"))
    @test only(r_doc[:e]) ≈ 0.06293300616044681

    # wrong-dtype raises cleanly rather than aborting (Step 5)
    df_str = DataFrame((; a = ["p", "q", "r"]))
    @test_throws PolarsError select(df_str, alias(entropy(col("a")), "e"))
end

@testset "lower_bound/upper_bound (py-polars series/test_series.py::test_upper_lower_bounds)" begin
    # upstream's exact dtype table -- every fixed-width integer type plus the two floats, whose
    # bounds are ±Inf rather than a finite Float32/Float64 max (a natural mismatch to check: the
    # generic `typemin`/`typemax` intuition from the integer cases does NOT extend to floats)
    for (T, lo, hi) in (
            (Int8, -128, 127), (UInt8, 0, 255),
            (Int16, -32768, 32767), (UInt16, 0, 65535),
            (Int32, -2147483648, 2147483647), (UInt32, 0, 4294967295),
            (Int64, -9223372036854775808, 9223372036854775807), (UInt64, 0, 18446744073709551615),
        )
        # upstream's fixture is an EMPTY series (`pl.Series("s", dtype=dtype)`) -- lower_bound/
        # upper_bound are dtype-derived, not data-derived, so this doubles as the empty-input case
        df = DataFrame((; x = T[]))
        r = select(df, alias(lower_bound(col("x")), "lb"), alias(upper_bound(col("x")), "ub"))
        @test only(r[:lb]) == lo
        @test only(r[:ub]) == hi
    end

    for T in (Float32, Float64)
        df = DataFrame((; x = T[]))
        r = select(df, alias(lower_bound(col("x")), "lb"), alias(upper_bound(col("x")), "ub"))
        @test isinf(only(r[:lb])) && only(r[:lb]) < 0
        @test isinf(only(r[:ub])) && only(r[:ub]) > 0
    end

    # non-empty Int64 sanity check (matches the previously live-verified fact for this batch)
    df = DataFrame((; y = [1, 1, 2, 2]))
    r = select(df, alias(lower_bound(col("y")), "lb"), alias(upper_bound(col("y")), "ub"))
    @test only(r[:lb]) == typemin(Int64)
    @test only(r[:ub]) == typemax(Int64)

    # wrong-dtype raises cleanly rather than aborting (Step 5)
    df_str = DataFrame((; a = ["p", "q", "r"]))
    @test_throws PolarsError select(df_str, alias(lower_bound(col("a")), "lb"))
end

@testset "to_physical" begin
    df = DataFrame((; y = [1, 1, 2, 2]))
    r = select(df, alias(to_physical(col("y")), "p"))
    @test r[:p] == [1, 1, 2, 2] # already-physical dtype: unchanged

    df_date = DataFrame((; d = [Date(1970, 1, 2), Date(1970, 1, 1)]))
    r_date = select(df_date, alias(to_physical(col("d")), "p"))
    @test r_date[:p] == Int32[1, 0] # days since epoch

    # casting a categorical results in a UInt32 physical repr (upstream's exact assertion,
    # `s.to_physical().dtype == pl.UInt32`, series/test_series.py::test_to_physical); this
    # package has no `Enum` dtype (upstream's other to_physical case, Enum -> UInt8), so that half
    # of the upstream test doesn't port -- see the parity note's Step 8 divergence entry
    df_cat = DataFrame((; c = ["cat1"]))
    r_cat = select(df_cat, alias(cast_categorical(col("c")) |> to_physical, "p"))
    @test collect(r_cat[:p]) isa AbstractVector{UInt32}
    @test only(collect(r_cat[:p])) == 0x00000000
end
