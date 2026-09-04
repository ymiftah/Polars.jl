@testset "select" begin
    df = DataFrame((; x = [1, 2, 3], y = [10, 20, 30]))

    # subset + computed/renamed column
    sel = select(df, col("x"), (col("y") * 2) |> alias("y2"))
    @test Tables.columnnames(sel) == (:x, :y2)
    @test sel[:x] == [1, 2, 3]
    @test sel[:y2] == [20, 40, 60]

    # plain String column name shorthand
    sel_str = select(df, "x")
    @test Tables.columnnames(sel_str) == (:x,)

    # wildcard selects every column
    wildcard = select(df, col("*"))
    @test Tables.columnnames(wildcard) == (:x, :y)

    # LazyFrame form agrees
    sel_lazy = select(lazy(df), col("x")) |> collect
    @test sel_lazy[:x] == sel_str[:x]

    # selecting non-existent column raises error
    @test_throws PolarsError select(df, col("nonexistent"))

    # select with zero expressions returns a fully empty DataFrame (0 rows, 0 cols) --
    # with no columns to carry a row count, there's nothing to preserve it against
    df_zero = select(df)
    @test size(df_zero) == (0, 0)
end

@testset "with_columns" begin
    df = DataFrame((; x = [1, 2, 3], y = [10, 20, 30]))

    wc = with_columns(df, (col("x") + col("y")) |> alias("total"))
    @test Tables.columnnames(wc) == (:x, :y, :total)
    @test wc[:total] == [11, 22, 33]

    # multiple expressions in one call
    wc2 = with_columns(df, (col("x") * 2) |> alias("x2"), (col("y") * 2) |> alias("y2"))
    @test Tables.columnnames(wc2) == (:x, :y, :x2, :y2)
    @test wc2[:x2] == [2, 4, 6]
    @test wc2[:y2] == [20, 40, 60]

    # LazyFrame form agrees
    wc_lazy = with_columns(lazy(df), (col("x") + col("y")) |> alias("total")) |> collect
    @test wc_lazy[:total] == wc[:total]

    # with_columns overwriting an existing column name
    wc_overwrite = with_columns(df, col("x") * 10 |> alias("x"))
    @test Tables.columnnames(wc_overwrite) == (:x, :y)
    @test wc_overwrite[:x] == [10, 20, 30]
    @test wc_overwrite[:y] == [10, 20, 30]

    # zero expressions is a genuine no-op, not an error (py-polars test_with_columns_empty)
    wc_empty = with_columns(df)
    @test Tables.columnnames(wc_empty) == (:x, :y)
    @test wc_empty[:x] == df[:x]
end

@testset "select duplicate output name (py-polars test_select_duplicate_name)" begin
    # this is a Step-5-priority abort-safety check: two expressions producing the same output
    # name must be a clean PolarsError, not a process abort -- it's caught by the query planner
    # before any data is touched
    df = DataFrame((; x = [1]))
    @test_throws PolarsError select(df, col("x"), col("x"))
end

@testset "Symbol column references (Julia-side P2.4)" begin
    # `_as_expr` (expr/expr.jl) coerces String *or* Symbol column references to `col(...)` and is
    # shared by every verb below, so `select(df, :x)` reaches `col` as a `String` rather than
    # hitting `MethodError: ncodeunits(::Symbol)` inside it.
    df = DataFrame((; x = [1, 2, 3], y = [10, 20, 30]))

    @test collect(select(df, :x)[1]) == [1, 2, 3]
    @test col(:x) isa Polars.Expr
    @test collect(filter(df, col(:x) > 1)[:x]) == [2, 3]
    @test collect(sort(df, :x; rev = true)[:x]) == [3, 2, 1]

    gb = group_by(lazy(df), :x)
    r = collect(agg(gb, Base.sum(col(:y))))
    @test sort(collect(r[:y])) == [10, 20, 30]

    df2 = DataFrame((; x = [1, 2], z = ["a", "b"]))
    @test collect(innerjoin(df, df2, :x)[:z]) == ["a", "b"]

    # curried `over`/`sort_by` also accept Symbol partition/by-keys
    dfg = DataFrame((; g = ["a", "a", "b"], x = [1, 2, 3]))
    r2 = select(dfg, alias(Base.sum(col("x")) |> over(:g), "s"))
    @test collect(r2[:s]) == [3, 3, 3]

    r3 = select(df, alias(col("x") |> sort_by(:y; rev = true), "sb"))
    @test collect(r3[:sb]) == [3, 2, 1]
end

@testset "select/with_columns accept a vector of expressions" begin
    df = DataFrame((; a = [1, 2], b = [3, 4], c = [5, 6]))

    @test Polars.names(select(df, [:a, :b])) == ["a", "b"]
    @test Polars.names(select(df, ["a", "c"])) == ["a", "c"]
    @test Polars.names(select(df, [col("a"), col("b") |> alias("bb")])) == ["a", "bb"]
    @test Polars.names(select(df, :a, [:b, :c])) == ["a", "b", "c"]

    @test collect(with_columns(df, [col("a") * 2 |> alias("a2")])[:a2]) == [2, 4]

    # A horizontal reduction (the @wrap_multi_expr_function family) too.
    @test collect(select(df, sum_horizontal([col("a"), col("b")]) |> alias("s"))[:s]) == [4, 6]
end

@testset "lit is not flattened by _expr_vector" begin
    # A genuine list *value* reaches the plan through `lit`, which returns an `Expr` -- so
    # `_expr_flatten`'s `AbstractVector` branch never sees the raw `[1, 2, 3]`, only the `Expr`
    # `lit([1, 2, 3])` wraps it in. `lit` of a Julia vector builds a literal Series (one row per
    # element, not one list-per-row) -- unchanged from before this flattening rule existed.
    df = DataFrame((; a = [1, 2]))
    r = select(df, lit([1, 2, 3]) |> alias("l"))
    @test size(r) == (3, 1)
    @test collect(r[:l]) == [1, 2, 3]
end
