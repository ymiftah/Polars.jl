@testset "filter(expr, predicate): filters expr's own values, distinct from frame-level filter" begin
    df = DataFrame((; g = ["a", "a", "b", "b", "b"], x = [1, 2, 10, 20, 30]))

    r = select(df, alias(filter(col("x"), col("x") .> 5), "f"))
    @test collect(r[:f]) == [10, 20, 30]

    # typical use: an aggregation over a filtered subset, per group
    r2 = collect(agg(group_by(lazy(df), "g"), Polars.sum(filter(col("x"), col("x") .> 5)) |> alias("s")))
    r2 = Base.sort(r2, col("g"))
    @test collect(r2[:s]) == [0, 60]

    # predicate accepts a column-name string/Symbol too (a boolean column used directly, same
    # coercion frame-level filter already uses via _as_expr)
    df_flag = DataFrame((; x = [1, 2, 3, 4], flag = [true, false, true, false]))
    r3 = select(df_flag, alias(filter(col("x"), "flag"), "f"))
    @test collect(r3[:f]) == [1, 3]
end

@testset "head(expr, n) / tail(expr, n): distinct from frame-level head/tail" begin
    df = DataFrame((; x = collect(1:10)))

    @test collect(select(df, alias(head(col("x"), 3), "h"))[:h]) == [1, 2, 3]
    @test collect(select(df, alias(tail(col("x"), 3), "t"))[:t]) == [8, 9, 10]

    # default length (upstream's own default of 10)
    df_big = DataFrame((; x = collect(1:20)))
    @test length(collect(select(df_big, alias(head(col("x")), "h"))[:h])) == 10
    @test length(collect(select(df_big, alias(tail(col("x")), "t"))[:t])) == 10

    # per-group, inside agg -- distinct from frame-level head/tail which take whole rows
    df2 = DataFrame((; g = ["a", "a", "a", "b", "b"], x = [1, 2, 3, 4, 5]))
    r = collect(agg(group_by(lazy(df2), "g"), alias(head(col("x"), 2), "h")))
    r = Base.sort(r, col("g"))
    @test collect(r[:h][1]) == [1, 2]
    @test collect(r[:h][2]) == [4, 5]
end

@testset "limit(expr, n) is an alias for head(expr, n)" begin
    df = DataFrame((; x = collect(1:10)))
    @test collect(select(df, alias(limit(col("x"), 4), "l"))[:l]) ==
        collect(select(df, alias(head(col("x"), 4), "h"))[:h])
end

@testset "slice(expr, offset, length): 0-based, negative offset counts from the end" begin
    df = DataFrame((; x = collect(1:10)))

    @test collect(select(df, alias(slice(col("x"), 2, 3), "s"))[:s]) == [3, 4, 5]

    # negative offset
    @test collect(select(df, alias(slice(col("x"), -3, 3), "s"))[:s]) == [8, 9, 10]

    # offset/length accept Expr too, not just literal integers
    @test collect(select(df, alias(slice(col("x"), lit(0), lit(2)), "s"))[:s]) == [1, 2]
end

@testset "get(expr, index): scalar counterpart to gather" begin
    df = DataFrame((; x = [10, 20, 30, 40]))

    # get reduces to a single value (like item), not one-per-row
    @test collect(select(df, alias(get(col("x"), 0), "g"))[:g]) == [10]
    @test collect(select(df, alias(get(col("x"), -1), "g"))[:g]) == [40]

    # null_on_oob = false (default) -> a catchable PolarsError, not a process abort
    @test_throws PolarsError collect(select(lazy(df), alias(get(col("x"), 99), "g")))

    # null_on_oob = true -> missing instead of raising
    r_null = select(df, alias(get(col("x"), 99; null_on_oob = true), "g"))
    @test isequal(collect(r_null[:g]), [missing])

    # index as Expr, e.g. driven by arg_max -- typical "value at the row where y is max" idiom
    df2 = DataFrame((; x = [10, 20, 30], y = [1, 5, 2]))
    r2 = select(df2, alias(get(col("x"), arg_max(col("y"))), "g"))
    @test collect(r2[:g]) == [20]

    # per-group, inside agg -- one value per group, driven by that group's own arg_max
    df3 = DataFrame((; g = ["a", "a", "b", "b"], x = [10, 20, 30, 40], y = [1, 5, 9, 2]))
    r3 = collect(agg(group_by(lazy(df3), "g"), alias(get(col("x"), arg_max(col("y"))), "picked")))
    r3 = Base.sort(r3, col("g"))
    @test collect(r3[:picked]) == [20, 30]
end
