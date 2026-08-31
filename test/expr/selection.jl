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

@testset "arg_unique: row indices of first occurrence, in order" begin
    df = DataFrame((; y = [1, 1, 2, 2]))
    r = select(df, alias(arg_unique(col("y")), "au"))
    @test r[:au] == UInt32[0, 2]

    dfm = DataFrame((; y = Union{Int, Missing}[1, missing, 1]))
    r_missing = select(dfm, alias(arg_unique(col("y")), "au"))
    @test r_missing[:au] == UInt32[0, 1] # `missing` counts as its own distinct value
end

@testset "extend_constant: appends n copies of value" begin
    df = DataFrame((; y = [1, 1, 2, 2]))
    r = select(df, alias(extend_constant(col("y"), 0, 2), "e"))
    @test r[:e] == [1, 1, 2, 2, 0, 0]

    # value may be `missing`, appending nulls
    r_null = select(df, alias(extend_constant(col("y"), missing, 1), "e"))
    @test isequal(collect(r_null[:e]), [1, 1, 2, 2, missing])
end

@testset "shuffle: random permutation, reproducible with a seed" begin
    df = DataFrame((; x = [1.0, 2.0, 3.0, 4.0]))

    r1 = select(df, alias(shuffle(col("x"); seed = 42), "s"))
    r2 = select(df, alias(shuffle(col("x"); seed = 42), "s"))
    @test r1[:s] == r2[:s] # same seed -> same permutation

    @test sort(r1[:s]) == sort(df[:x]) # multiset of values is preserved

    # nothing (default): draws a fresh seed each call, still preserves the multiset
    r3 = select(df, alias(shuffle(col("x")), "s"))
    @test sort(r3[:s]) == sort(df[:x])
end

@testset "Base.reshape: builds an Array-dtype plan; materializing/introspecting it is not yet supported" begin
    df = DataFrame((; x = [1.0, 2.0, 3.0, 4.0]))
    lf = select(lazy(df), alias(Base.reshape(col("x"), 2, 2), "r"))

    # building the plan and running `explain` on it both succeed
    @test occursin("reshape()", explain(lf))

    # collect() itself succeeds -- the failure is in resolving the Array dtype afterward
    d = collect(lf)

    # neither collect_schema nor indexing into the Array column can materialize/introspect it yet
    @test_throws ErrorException collect_schema(lf)
    @test_throws ErrorException d[:r]

    # a single -1 as the *first* dimension is inferred from the length; upstream only supports
    # inferring the first dimension, not any other position (verified live)
    lf2 = select(lazy(df), alias(Base.reshape(col("x"), -1, 2), "r"))
    @test occursin("reshape()", explain(lf2))
end
