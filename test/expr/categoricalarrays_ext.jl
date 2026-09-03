using CategoricalArrays

@testset "CategoricalArrays extension" begin
    @test Base.get_extension(Polars, :PolarsCategoricalArraysExt) !== nothing

    # upstream test_cut fixture
    df = DataFrame((; a = [-2.0, -1.0, 0.0, 1.0, 2.0]))
    vals(e) = collect(select(df, alias(e, "r"))[:r])

    # `cut` is unexported here, so with CategoricalArrays loaded the bare name is its generic --
    # this method dispatches an Expr back to this package, reaching the same implementation
    @test vals(cut(col("a"), [-1.0, 1.0])) == vals(Polars.cut(col("a"), [-1.0, 1.0]))

    # keywords pass through
    @test vals(cut(col("a"), [-1.0, 1.0]; labels = ["lo", "mid", "hi"])) ==
        vals(Polars.cut(col("a"), [-1.0, 1.0]; labels = ["lo", "mid", "hi"]))
    @test vals(cut(col("a"), [-1.0, 1.0]; left_closed = true)) ==
        vals(Polars.cut(col("a"), [-1.0, 1.0]; left_closed = true))

    # CategoricalArrays' own vector method is unaffected
    @test cut([-2.0, 0.0, 2.0], [-Inf, 0.0, Inf]) isa AbstractVector
end

@testset "CategoricalArrays extension: column materialization" begin
    # Happy path, with a null and a repeated value
    df = DataFrame((; s = ["a", "b", missing, "a", "c"]))
    cat_series = select(df, cast_categorical(col("s")))[:s]

    @test eltype(cat_series) == Union{Missing, CategoricalValue{String, UInt32}}
    materialized = collect(cat_series)
    @test materialized isa CategoricalArray
    @test ismissing(materialized[3])
    @test collect(skipmissing(materialized)) == ["a", "b", "a", "c"]
    @test Set(levels(materialized)) == Set(["a", "b", "c"])

    # No nulls: eltype narrows accordingly, same as every other dtype's Series{T}
    df_no_nulls = DataFrame((; s = ["x", "y", "x"]))
    cat_no_nulls = select(df_no_nulls, cast_categorical(col("s")))[:s]
    @test eltype(cat_no_nulls) == CategoricalValue{String, UInt32}
    materialized_no_nulls = collect(cat_no_nulls)
    @test materialized_no_nulls isa CategoricalArray
    @test !any(ismissing, materialized_no_nulls)
    @test String.(materialized_no_nulls) == ["x", "y", "x"]

    # Empty column
    df_empty = DataFrame((; s = String[]))
    cat_empty = select(df_empty, cast_categorical(col("s")))[:s]
    materialized_empty = collect(cat_empty)
    @test materialized_empty isa CategoricalArray
    @test isempty(materialized_empty)

    # A category that never appears in this particular column does not leak in as a level, even
    # though it's part of the same global category registry from an earlier column in this test
    # session (see docs/src/limitations.md)
    df_other = DataFrame((; s = ["p", "q"]))
    cat_other = collect(select(df_other, cast_categorical(col("s")))[:s])
    @test Set(String.(levels(cat_other))) == Set(["p", "q"])

    # `dtype(series)` still doesn't distinguish Categorical from String, unaffected by this
    # extension being loaded
    plain_series = select(df, col("s"))[:s]
    @test Polars.dtype(cat_series) == Polars.dtype(plain_series)
end
