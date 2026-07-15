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

@testset "top_k" begin
    df = DataFrame((; x = [3, 1, 4, 2, 9]))

    r = select(df, alias(top_k(col("x"), lit(2)), "t"))
    @test sort(r[:t]) == [4, 9]

    r_int = select(df, alias(top_k(col("x"), 3), "t"))
    @test sort(r_int[:t]) == [3, 4, 9]
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
