@testset "sort_by" begin
    df = DataFrame((; g = ["a", "a", "b", "b"], x = [3, 1, 4, 2], y = [10, 20, 30, 40]))

    # per-group sort: not expressible via frame-level sort, since each group needs its own order
    r = collect(agg(group_by(lazy(df), "g"), alias(sort_by(col("x"), col("y"); rev = true), "sorted_x")))
    r = sort(r, col("g"))
    @test r[:g] == ["a", "b"]
    @test collect(r[:sorted_x][1]) == [1, 3]
    @test collect(r[:sorted_x][2]) == [2, 4]

    # multiple by-columns and per-column rev: sort x by (y ascending, then z descending)
    df2 = DataFrame((; x = [1, 2, 3, 4], y = [2, 1, 2, 1], z = [3, 5, 1, 2]))
    r2 = select(df2, alias(sort_by(col("x"), col("y"), col("z"); rev = [false, true]), "s"))
    @test r2[:s] == [2, 4, 1, 3]
end

@testset "sort_by curried form" begin
    df = DataFrame((; g = ["a", "a", "b", "b"], x = [3, 1, 4, 2], y = [10, 20, 30, 40]))

    r = collect(agg(group_by(lazy(df), "g"), alias(col("x") |> sort_by("y"; rev = true), "sorted_x")))
    r = sort(r, col("g"))
    @test collect(r[:sorted_x][1]) == [1, 3]
    @test collect(r[:sorted_x][2]) == [2, 4]

    # multi-column curried form, agrees with the non-curried form
    df2 = DataFrame((; x = [1, 2, 3, 4], y = [2, 1, 2, 1], z = [3, 5, 1, 2]))
    r2 = select(df2, alias(col("x") |> sort_by("y", "z"; rev = [false, true]), "s"))
    r2_direct = select(df2, alias(sort_by(col("x"), col("y"), col("z"); rev = [false, true]), "s"))
    @test r2[:s] == r2_direct[:s]

    # a bare Expr argument is not curried -- it resolves to the original sort_by(expr, by...)
    # with zero by-keys, since it's ambiguous with sort_by's own `expr` argument
    r_bare = sort_by(col("x"))
    @test r_bare isa Polars.Expr
end

@testset "arg_sort" begin
    df = DataFrame((; x = [3, 1, 4, 2]))

    r = select(df, alias(arg_sort(col("x")), "idx"))
    @test r[:idx] == [1, 3, 0, 2]

    r_desc = select(df, alias(arg_sort(col("x"); descending = true), "idx"))
    @test r_desc[:idx] == [2, 0, 3, 1]
end

@testset "arg_sort nulls_last (py-polars test_arg_sort_nulls)" begin
    df = DataFrame((; a = Union{Missing, Float64}[1.0, 2.0, 3.0, missing, missing]))

    r_last = select(df, alias(arg_sort(col("a"); nulls_last = true), "i"))
    @test collect(r_last[:i]) == [0, 1, 2, 3, 4]

    r_first = select(df, alias(arg_sort(col("a"); nulls_last = false), "i"))
    @test collect(r_first[:i]) == [3, 4, 0, 1, 2]

    # the frame-level sort agrees
    @test isequal(collect(Base.sort(df, "a"; nulls_last = false)[:a]), [missing, missing, 1.0, 2.0, 3.0])
    @test isequal(collect(Base.sort(df, "a"; nulls_last = true)[:a]), [1.0, 2.0, 3.0, missing, missing])
end

@testset "top_k" begin
    df = DataFrame((; x = [3, 1, 4, 2, 9]))

    r = select(df, alias(top_k(col("x"), lit(2)), "t"))
    @test sort(r[:t]) == [4, 9]

    r_int = select(df, alias(top_k(col("x"), 3), "t"))
    @test sort(r_int[:t]) == [3, 4, 9]
end

@testset "top_k: empty input, and nulls sort last / are excluded by valid_count (py-polars test_top_k_empty, test_top_k_nulls)" begin
    df_empty = DataFrame((; test = Float64[]))
    @test isempty(collect(select(df_empty, alias(top_k(col("test"), 2), "test"))[:test]))

    df = DataFrame((; x = Union{Missing, Int}[3, 1, missing, 4, missing, 2]))
    valid_count = 4 # 6 total - 2 nulls

    r_valid = select(df, alias(top_k(col("x"), valid_count), "t"))
    @test sort(collect(r_valid[:t])) == [1, 2, 3, 4]

    r_full = select(df, alias(top_k(col("x"), 6), "t"))
    full = collect(r_full[:t])
    @test count(ismissing, full) == 2
    @test sort(filter(!ismissing, full)) == [1, 2, 3, 4]
end

@testset "bottom_k: the complement of top_k (see plans/parity/gap_closure_scope.md)" begin
    df = DataFrame((; x = [3, 1, 4, 1, 5]))

    r = select(df, alias(bottom_k(col("x"), lit(2)), "b"))
    @test sort(collect(r[:b])) == [1, 1]

    r_int = select(df, alias(bottom_k(col("x"), 3), "b"))
    @test sort(collect(r_int[:b])) == [1, 1, 3]

    # curried form, matches the non-curried result
    r_curried = select(df, alias(col("x") |> bottom_k(2), "b"))
    @test sort(collect(r_curried[:b])) == sort(collect(r[:b]))

    # nulls: same convention as top_k -- when k covers the whole column, nulls are included
    df_null = DataFrame((; x = Union{Missing, Int}[3, missing, 1, missing]))
    r_null = select(df_null, alias(bottom_k(col("x"), 4), "b"))
    out = collect(r_null[:b])
    @test count(ismissing, out) == 2
    @test sort(filter(!ismissing, out)) == [1, 3]
end

@testset "gather" begin
    df = DataFrame((; a = [1, 2, 3, 4]))

    # upstream test_gather.py:11 -- negative indices count from the end; 0-based (see docstring)
    r = select(df, gather(col("a"), lit([0, -1])) |> alias("g"))
    @test r[:g] == [1, 4]

    # null_on_oob = true -> missing instead of raising
    r_null = select(df, gather(col("a"), lit([0, 99]); null_on_oob = true) |> alias("g"))
    @test isequal(collect(r_null[:g]), [1, missing])

    # null_on_oob = false (default) -> a catchable PolarsError, not a process abort -- the
    # highest-value check in this testset (see CLAUDE.md's `polars_series_get` history)
    @test_throws PolarsError collect(select(lazy(df), gather(col("a"), lit([99])) |> alias("g")))
end

@testset "gather_every" begin
    df = DataFrame((; a = collect(1:10)))

    r = select(df, gather_every(col("a"), 3) |> alias("g"))
    @test r[:g] == [1, 4, 7, 10]

    r_offset = select(df, gather_every(col("a"), 3; offset = 1) |> alias("g"))
    @test r_offset[:g] == [2, 5, 8]
end

@testset "value_counts" begin
    df = DataFrame((; g = ["a", "a", "b", "b", "b"]))

    r = collect(select(lazy(df), alias(value_counts(col("g"); sort = true), "vc")))
    s = r[:vc]
    vals = [s[i] for i in 1:length(s)]
    @test vals == [(g = "b", count = UInt32(3)), (g = "a", count = UInt32(2))]

    r_norm = collect(select(lazy(df), alias(value_counts(col("g"); sort = true, normalize = true), "vc")))
    s_norm = r_norm[:vc]
    vals_norm = [s_norm[i] for i in 1:length(s_norm)]
    @test vals_norm[1].g == "b"
    @test vals_norm[1].count ≈ 0.6
    @test vals_norm[2].g == "a"
    @test vals_norm[2].count ≈ 0.4

    r_named = collect(select(lazy(df), alias(value_counts(col("g"); name = "n"), "vc")))
    @test :n in propertynames(r_named[:vc][1])
end

@testset "value_counts: name collision raises cleanly, and exact sort tie-break order (py-polars test_value_counts_duplicate_name / test_value_counts_expr)" begin
    # counting a column literally named "count" without overriding `name` would produce a
    # duplicate field name in the output Struct -- must raise a clean PolarsError, not corrupt
    # the result or abort the process (Step 5 -- process-abort check, see CLAUDE.md)
    df_collide = DataFrame((; count = [1, 0, 1]))
    @test_throws PolarsError select(df_collide, alias(value_counts(col("count")), "vc"))

    r_custom = select(df_collide, alias(value_counts(col("count"); name = "n"), "vc"))
    @test :n in propertynames(collect(r_custom[:vc])[1])

    # exact tie-break order when sort=true and two values tie on count: upstream's own fixture
    df_ties = DataFrame((; id = ["a", "b", "b", "c", "c", "c", "d", "d"]))
    r_ties = collect(select(lazy(df_ties), alias(value_counts(col("id"); sort = true), "vc")))
    s_ties = r_ties[:vc]
    @test [(v.id, v.count) for v in s_ties] ==
        [("c", UInt32(3)), ("b", UInt32(2)), ("d", UInt32(2)), ("a", UInt32(1))]
end

@testset "sort(expr): sorts expr's own values, not by a different key" begin
    df = DataFrame((; x = [3, 1, 4, 1, 5]))

    r = select(df, alias(sort(col("x")), "s"))
    @test collect(r[:s]) == [1, 1, 3, 4, 5]

    r_rev = select(df, alias(sort(col("x"); rev = true), "s"))
    @test collect(r_rev[:s]) == [5, 4, 3, 1, 1]

    # per-group sort of the expression's own values (distinct from frame-level sort)
    df2 = DataFrame((; g = ["a", "a", "b", "b"], x = [3, 1, 4, 2]))
    r2 = collect(agg(group_by(lazy(df2), "g"), alias(sort(col("x")), "sorted_x")))
    r2 = Base.sort(r2, col("g"))
    @test collect(r2[:sorted_x][1]) == [1, 3]
    @test collect(r2[:sorted_x][2]) == [2, 4]
end

@testset "sort(expr) nulls_last" begin
    df = DataFrame((; a = Union{Missing, Float64}[3.0, missing, 1.0, missing, 2.0]))

    r_last = select(df, alias(sort(col("a"); nulls_last = true), "s"))
    @test isequal(collect(r_last[:s]), [1.0, 2.0, 3.0, missing, missing])

    r_first = select(df, alias(sort(col("a"); nulls_last = false), "s"))
    @test isequal(collect(r_first[:s]), [missing, missing, 1.0, 2.0, 3.0])
end

@testset "top_k_by / bottom_k_by: the k rows with the largest/smallest by-key" begin
    df = DataFrame((; g = ["a", "a", "b", "b", "b"], x = [3, 1, 10, 20, 5]))

    r_top = collect(agg(group_by(lazy(df), "g"), alias(top_k_by(col("x"), 1, col("x")), "top1")))
    r_top = Base.sort(r_top, col("g"))
    @test collect(r_top[:top1][1]) == [3]
    @test collect(r_top[:top1][2]) == [20]

    r_bottom = collect(agg(group_by(lazy(df), "g"), alias(bottom_k_by(col("x"), 1, col("x")), "bottom1")))
    r_bottom = Base.sort(r_bottom, col("g"))
    @test collect(r_bottom[:bottom1][1]) == [1]
    @test collect(r_bottom[:bottom1][2]) == [5]

    # multi-key with per-key rev
    df2 = DataFrame((; x = [1, 2, 3, 4], y = [2, 1, 2, 1], z = [3, 5, 1, 2]))
    r2 = select(df2, alias(top_k_by(col("x"), 4, col("y"), col("z"); rev = [false, true]), "t"))
    r2_bottom = select(df2, alias(bottom_k_by(col("x"), 4, col("y"), col("z"); rev = [false, true]), "b"))
    @test sort(collect(r2[:t])) == sort(collect(r2_bottom[:b])) == [1, 2, 3, 4]
end

@testset "top_k_by / bottom_k_by: a wrong-length `rev` raises ArgumentError" begin
    df = DataFrame((; x = [1, 2, 3], y = [3, 2, 1], z = [1, 1, 1]))

    @test_throws ArgumentError select(df, top_k_by(col("x"), 2, col("y"), col("z"); rev = [true]))
    @test_throws ArgumentError select(df, bottom_k_by(col("x"), 2, col("y"), col("z"); rev = [true]))
end

@testset "sort_by: a wrong-length `rev` raises ArgumentError" begin
    # Matches `sort`'s own frame-level validation -- see test/operations/sort.jl.
    df = DataFrame((; x = [1, 2, 3], y = [3, 2, 1], z = [1, 1, 1]))

    @test_throws ArgumentError select(df, sort_by(col("x"), col("y"), col("z"); rev = [true]))
    @test_throws ArgumentError select(df, sort_by(col("x"), col("y"); rev = [true, false, true]))

    err = try
        sort_by(col("x"), col("y"), col("z"); rev = [true])
    catch e
        e
    end
    @test err isa ArgumentError
    @test contains(err.msg, "2 by expressions")
    @test contains(err.msg, "1 rev")
end
