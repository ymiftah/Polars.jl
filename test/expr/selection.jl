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
    # lazyframe/test_lazyframe.py::test_arg_unique
    df = DataFrame((; a = [4, 1, 4]))
    r = select(df, alias(arg_unique(col("a")), "a"))
    @test r[:a] == UInt32[0, 1]
    @test eltype(r[:a]) == UInt32 # pl.get_index_type()

    # series/test_series.py:427-431 (a non-trivial run of duplicates, not just adjacent pairs)
    df2 = DataFrame((; a = [2, 1, 1, 4, 4, 4]))
    r2 = select(df2, alias(arg_unique(col("a")), "a"))
    @test r2[:a] == UInt32[0, 1, 3]

    dfm = DataFrame((; y = Union{Int, Missing}[1, missing, 1]))
    r_missing = select(dfm, alias(arg_unique(col("y")), "au"))
    @test r_missing[:au] == UInt32[0, 1] # `missing` counts as its own distinct value

    # empty input
    dfe = DataFrame((; y = Int64[]))
    r_empty = select(dfe, alias(arg_unique(col("y")), "au"))
    @test r_empty[:au] == UInt32[]

    # datatypes/test_float.py::test_unique (nulls variant): NaN and -0.0 dedup like their upstream
    # IEEE-754 equals (-0.0 == 0.0, and any two NaN payloads/signs collapse together), and
    # `gather(arg_unique(...))` round-trips the first-occurrence unique subsequence exactly
    dff = DataFrame((; x = Union{Float64, Missing}[-0.0, -NaN, 0.0, missing, 1.0, NaN]))
    r_nan = select(dff, alias(gather(col("x"), arg_unique(col("x"))), "g"))
    @test isequal(collect(r_nan[:g]), [-0.0, NaN, missing, 1.0])
end

@testset "extend_constant: appends n copies of value" begin
    # operations/test_extend_constant.py::test_extend_constant (a slice of the parametrized cases:
    # Int64/Float64/String/missing-const, since our literal `convert(Expr, ...)` overloads don't
    # cover every dtype upstream parametrizes over, e.g. Int8/date/datetime/time/duration)
    df = DataFrame((; a = Union{Int64, Missing}[missing]))
    r = select(df, alias(extend_constant(col("a"), 1, 3), "e"))
    @test isequal(collect(r[:e]), [missing, 1, 1, 1])

    dff = DataFrame((; a = Union{Float64, Missing}[missing]))
    r_f = select(dff, alias(extend_constant(col("a"), 4.5, 3), "e"))
    @test isequal(collect(r_f[:e]), [missing, 4.5, 4.5, 4.5])

    dfs = DataFrame((; a = Union{String, Missing}[missing]))
    r_s = select(dfs, alias(extend_constant(col("a"), "hi", 3), "e"))
    @test isequal(collect(r_s[:e]), [missing, "hi", "hi", "hi"])

    # value may be `missing`, appending nulls
    r_null = select(dff, alias(extend_constant(col("a"), missing, 3), "e"))
    @test isequal(collect(r_null[:e]), [missing, missing, missing, missing])

    # n as an expression (`pl.lit(2)` upstream), not just a literal Int
    r_nexpr = select(df, alias(extend_constant(col("a"), 1, lit(2)), "e"))
    @test isequal(collect(r_nexpr[:e]), [missing, 1, 1])

    # value as an expression (`pl.lit(const, dtype=dtype)` upstream)
    r_vexpr = select(df, alias(extend_constant(col("a"), lit(1), 3), "e"))
    @test isequal(collect(r_vexpr[:e]), [missing, 1, 1, 1])

    # operations/test_extend_constant.py::test_extend_by_not_uint_expr -- a non-scalar `value`/`n`
    # raises ShapeError upstream ("must be a scalar value"); here that surfaces as PolarsError
    @test_throws PolarsError collect(select(lazy(df), alias(extend_constant(col("a"), implode(lit([2, 3])), 3), "e")))
    @test_throws PolarsError collect(select(lazy(df), alias(extend_constant(col("a"), 1, implode(lit([2, 3]))), "e")))
end

@testset "shuffle: random permutation, reproducible with a seed" begin
    # operations/test_random.py::test_shuffle_series -- an exact upstream-pinned permutation for a
    # given seed, live-verified to match bit-for-bit (same underlying Rust RNG/seeding scheme)
    df = DataFrame((; a = [1, 2, 3]))
    r = select(df, alias(shuffle(col("a"); seed = 1), "s"))
    @test r[:s] == [2, 3, 1]

    df4 = DataFrame((; x = [1.0, 2.0, 3.0, 4.0]))

    r1 = select(df4, alias(shuffle(col("x"); seed = 42), "s"))
    r2 = select(df4, alias(shuffle(col("x"); seed = 42), "s"))
    @test r1[:s] == r2[:s] # same seed -> same permutation

    @test sort(r1[:s]) == sort(df4[:x]) # multiset of values is preserved

    # nothing (default): draws a fresh seed each call, still preserves the multiset
    r3 = select(df4, alias(shuffle(col("x")), "s"))
    @test sort(r3[:s]) == sort(df4[:x])

    # operations/test_random.py::test_shuffle_group_by_reseed -- a fixed seed reseeds identically
    # per group, so every group ends up with the *same* shuffled order
    n = 5
    dfg = DataFrame(
        (;
            l = repeat([1, 2, 3], n),
            group = sort(repeat(0:(n - 1); inner = 3)),
        )
    )
    shuffled = collect(agg(group_by(lazy(dfg), "group"), alias(shuffle(col("l"); seed = 0xDEADBEEF), "l")))
    shuffled = Base.sort(shuffled, col("group"))
    per_group = collect(shuffled[:l])
    @test all(==(per_group[1]), per_group)

    # empty input
    dfe = DataFrame((; a = Int64[]))
    r_empty = select(dfe, alias(shuffle(col("a"); seed = 1), "s"))
    @test r_empty[:s] == Int64[]

    # null propagation: nulls are shuffled along with the rest, multiset preserved
    dfm = DataFrame((; a = Union{Int64, Missing}[1, missing, 3]))
    r_null = select(dfm, alias(shuffle(col("a"); seed = 1), "s"))
    @test isequal(sort(collect(r_null[:s])), sort(collect(dfm[:a])))
end

@testset "Base.reshape: builds an Array-dtype plan and materializes as Vector{T} per row" begin
    df = DataFrame((; x = [1.0, 2.0, 3.0, 4.0]))
    lf = select(lazy(df), alias(Base.reshape(col("x"), 2, 2), "r"))

    # building the plan and running `explain` on it both succeed
    @test occursin("reshape()", explain(lf))

    # collect_schema/schema resolve the Array dtype fine, and the collected DataFrame's Array
    # column materializes as a Vector{T} per row (same shape as List)
    @test collect_schema(lf) == Tables.Schema((:r,), (Union{Missing, Vector{Union{Missing, Float64}}},))
    d = collect(lf)
    @test collect(d[:r]) == [[1.0, 2.0], [3.0, 4.0]]

    # operations/test_reshape.py::test_reshape -- upstream's `(-1, 2)` and `(2, 2)` both produce
    # the same reshape given this length-4 input; `-1` as the first dimension is inferred here too.
    lf2 = select(lazy(df), alias(Base.reshape(col("x"), -1, 2), "r"))
    @test occursin("reshape()", explain(lf2))
    @test collect(collect(lf2)[:r]) == [[1.0, 2.0], [3.0, 4.0]]

    # operations/test_reshape.py::test_reshape -- upstream's own dedicated non-first-`-1` error
    # case is `pl.col("a").reshape((2, -1))`, raising "can only infer the first dimension" even
    # though the earlier `(-1, 2)`-family shapes above resolve fine: this package's restriction to
    # inferring only the first `-1` matches upstream exactly, not a divergence
    @test_throws PolarsError collect(select(lazy(df), alias(Base.reshape(col("x"), 2, -1), "r")))

    # operations/test_reshape.py -- further upstream error-path fixtures, all raise cleanly here
    # rather than aborting the process (Step 5): empty dims panics deep in polars-plan's own schema
    # resolution (`range start index 1 out of range for slice of length 0`, live-observed), but
    # `guard_error` catches it before it crosses the FFI boundary and surfaces a clean PolarsError
    @test_throws PolarsError collect(select(lazy(df), alias(Base.reshape(col("x")), "r")))
    @test_throws PolarsError collect(select(lazy(df), alias(Base.reshape(col("x"), -1, -1), "r"))) # multiple inferred dims
    @test_throws PolarsError collect(select(lazy(df), alias(Base.reshape(col("x"), 5, 1), "r"))) # size doesn't fit
    @test_throws PolarsError collect(select(lazy(df), alias(Base.reshape(col("x"), -1, 0), "r"))) # zero dim, non-empty array

    # empty input: reshape((0,)) on an empty series is valid; reshape((1,)) is not (size mismatch)
    dfe = DataFrame((; x = Int64[]))
    lfe = select(lazy(dfe), alias(Base.reshape(col("x"), 0), "r"))
    @test occursin("reshape()", explain(lfe))
    @test_throws PolarsError collect(select(lazy(dfe), alias(Base.reshape(col("x"), 1), "r")))

    # higher-dimensional reshape: an inferred first dim and a fully explicit one agree
    df3 = DataFrame((; x = collect(1:(3 * 5 * 7 * 2))))
    lf3a = select(lazy(df3), alias(Base.reshape(col("x"), 3, 5, 7, 2), "r"))
    lf3b = select(lazy(df3), alias(Base.reshape(col("x"), -1, 5, 7, 2), "r"))
    @test occursin("reshape()", explain(lf3a))
    @test occursin("reshape()", explain(lf3b))

    # a >2-dimensional reshape nests more than one Array level deep: schema resolution still
    # works (it's purely recursive, no data read), but reading the values back raises a clean
    # error rather than materializing incorrectly or crashing -- only a single Array level
    # materializes (see Base.reshape's docstring / Limitations)
    @test collect_schema(lf3a) isa Tables.Schema
    d3a = collect(lf3a)
    @test_throws ErrorException collect(d3a[:r])
end
