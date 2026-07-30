@testset "basic aggregations" begin
    df = DataFrame((; x = [1.0, 2.0, 3.0, 4.0]))

    r = select(
        df, Polars.sum(col("x")) |> alias("sum"),
        prod(col("x")) |> alias("prod"),
        mean(col("x")) |> alias("mean"),
        median(col("x")) |> alias("median"),
        Polars.min(col("x")) |> alias("min"),
        Polars.max(col("x")) |> alias("max"),
        arg_min(col("x")) |> alias("arg_min"),
        arg_max(col("x")) |> alias("arg_max")
    )
    @test only(r[:sum]) == 10.0
    @test only(r[:prod]) == 24.0
    @test only(r[:mean]) == 2.5
    @test only(r[:median]) == 2.5
    @test only(r[:min]) == 1.0
    @test only(r[:max]) == 4.0
    @test only(r[:arg_min]) == 0
    @test only(r[:arg_max]) == 3

    df_dup = DataFrame((; x = [1, 2, 2, 3, 3, 3]))
    r2 = select(
        df_dup, n_unique(col("x")) |> alias("n_unique"),
        Polars.count(col("x")) |> alias("count"),
        Polars.first(col("x")) |> alias("first"),
        Polars.last(col("x")) |> alias("last")
    )
    @test only(r2[:n_unique]) == 3
    @test only(r2[:count]) == 6
    @test only(r2[:first]) == 1
    @test only(r2[:last]) == 3
    @test sort(collect(select(df_dup, Polars.unique(col("x")))[:x])) == [1, 2, 3]
end

@testset "nan-propagating min/max" begin
    df = DataFrame((; x = [1.0, 2.0, NaN, 4.0]))

    r = select(df, nan_min(col("x")) |> alias("nan_min"), nan_max(col("x")) |> alias("nan_max"))
    @test isnan(only(collect(r[:nan_min])))
    @test isnan(only(collect(r[:nan_max])))
end

@testset "math functions" begin
    df = DataFrame((; x = [-1.5, 2.5, 0.0]))

    r = select(
        df, Polars.floor(col("x")) |> alias("floor"),
        Polars.ceil(col("x")) |> alias("ceil"),
        Polars.abs(col("x")) |> alias("abs")
    )
    @test collect(r[:floor]) == [-2.0, 2.0, 0.0]
    @test collect(r[:ceil]) == [-1.0, 3.0, 0.0]
    @test collect(r[:abs]) == [1.5, 2.5, 0.0]

    trig = DataFrame((; x = [0.0, 1.0]))
    rt = select(
        trig, Polars.cos(col("x")) |> alias("cos"),
        Polars.sin(col("x")) |> alias("sin"),
        Polars.tan(col("x")) |> alias("tan"),
        cosh(col("x")) |> alias("cosh"),
        sinh(col("x")) |> alias("sinh"),
        tanh(col("x")) |> alias("tanh")
    )
    @test collect(rt[:cos]) ≈ cos.([0.0, 1.0])
    @test collect(rt[:sin]) ≈ sin.([0.0, 1.0])
    @test collect(rt[:tan]) ≈ tan.([0.0, 1.0])
    @test collect(rt[:cosh]) ≈ cosh.([0.0, 1.0])
    @test collect(rt[:sinh]) ≈ sinh.([0.0, 1.0])
    @test collect(rt[:tanh]) ≈ tanh.([0.0, 1.0])
end

@testset "null/nan predicates" begin
    df = DataFrame((; x = [1.0, Inf, NaN, missing]))

    r = select(
        df, is_finite(col("x")) |> alias("fin"),
        is_infinite(col("x")) |> alias("inf"),
        is_nan(col("x")) |> alias("nan"),
        is_null(col("x")) |> alias("null"),
        is_not_null(col("x")) |> alias("notnull")
    )
    @test collect(skipmissing(r[:fin])) == [true, false, false]
    @test collect(skipmissing(r[:inf])) == [false, true, false]
    @test collect(skipmissing(r[:nan])) == [false, false, true]
    @test r[:null] == [false, false, false, true]
    @test r[:notnull] == [true, true, true, false]

    r2 = select(df, null_count(col("x")) |> alias("null_count"))
    @test only(r2[:null_count]) == 1

    df2 = DataFrame((; x = [1.0, NaN, missing, 4.0]))
    @test collect(skipmissing(select(df2, drop_nans(col("x")))[:x])) == [1.0, 4.0]
    @test isnan(collect(select(df2, drop_nulls(col("x")))[:x])[2])
end

@testset "aggregation edge cases" begin
    # All-null column
    df_null = DataFrame((; x = Union{Float64, Missing}[missing, missing, missing]))
    r_null = select(df_null, median(col("x")) |> alias("med"), prod(col("x")) |> alias("prod"))
    @test ismissing(only(r_null[:med]))
    @test only(r_null[:prod]) == 1.0  # prod of no values is the multiplicative identity

    # Single-element column
    df_single = DataFrame((; x = [42.0]))
    r_single = select(df_single, median(col("x")) |> alias("med"), prod(col("x")) |> alias("prod"))
    @test only(r_single[:med]) == 42.0
    @test only(r_single[:prod]) == 42.0

    # Empty column
    df_empty = DataFrame((; x = Float64[]))
    r_empty = select(df_empty, median(col("x")) |> alias("med"), prod(col("x")) |> alias("prod"))
    @test ismissing(only(r_empty[:med]))
    @test only(r_empty[:prod]) == 1.0  # prod of no values is the multiplicative identity

    # nan_min/max with all-null
    df_nan_null = DataFrame((; x = Union{Float64, Missing}[missing, missing]))
    r_nan_null = select(df_nan_null, nan_min(col("x")) |> alias("nm"), nan_max(col("x")) |> alias("xm"))
    @test ismissing(only(r_nan_null[:nm]))
    @test ismissing(only(r_nan_null[:xm]))

    # nan_min/max with a single-element column
    r_nan_single = select(df_single, nan_min(col("x")) |> alias("nm"), nan_max(col("x")) |> alias("xm"))
    @test only(r_nan_single[:nm]) == 42.0
    @test only(r_nan_single[:xm]) == 42.0

    # nan_min/max with an empty column
    r_nan_empty = select(df_empty, nan_min(col("x")) |> alias("nm"), nan_max(col("x")) |> alias("xm"))
    @test ismissing(only(r_nan_empty[:nm]))
    @test ismissing(only(r_nan_empty[:xm]))
end

@testset "count excludes nulls, unlike size (py-polars test_count)" begin
    df = DataFrame(
        (;
            nulls = Union{Missing, Int}[missing, missing, missing],
            one_null_str = ["one", missing, "three"],
            one_null_float = [1.0, 2.0, missing],
            no_nulls_int = [1, 2, 3],
        )
    )
    r = select(
        df, alias(Polars.count(col("nulls")), "nulls"),
        alias(Polars.count(col("one_null_str")), "one_null_str"),
        alias(Polars.count(col("one_null_float")), "one_null_float"),
        alias(Polars.count(col("no_nulls_int")), "no_nulls_int"),
    )
    @test only(r[:nulls]) == 0
    @test only(r[:one_null_str]) == 2
    @test only(r[:one_null_float]) == 2
    @test only(r[:no_nulls_int]) == 3
end

@testset "aggregations on Boolean dtype (py-polars test_boolean_aggs)" begin
    df = DataFrame((; bool = [true, false, missing, true]))
    r = select(df, alias(mean(col("bool")), "mean"), alias(Polars.std(col("bool")), "std"), alias(Polars.var(col("bool")), "var"))
    @test only(r[:mean]) ≈ 0.6666666666666666
    @test only(r[:std]) ≈ 0.5773502691896258
    @test only(r[:var]) ≈ 0.33333333333333337
end

@testset "sum: empty/all-null identity is 0, not missing (py-polars test_sum_empty_and_null_set)" begin
    df_empty = DataFrame((; a = Float32[]))
    @test only(select(df_empty, alias(Polars.sum(col("a")), "s"))[:s]) == 0.0

    df_null = DataFrame((; a = Union{Missing, Float32}[missing]))
    @test only(select(df_null, alias(Polars.sum(col("a")), "s"))[:s]) == 0.0
end

@testset "sum_horizontal: a missing operand is the identity, not propagated (py-polars test_horizontal_sum_null_to_identity)" begin
    df = DataFrame((; a = [1, 5], b = Union{Missing, Int}[10, missing]))
    r = select(df, alias(sum_horizontal(col("a"), col("b")), "s"))
    @test collect(r[:s]) == [11, 5]
end

@testset "grouped min/max/mean: NaN vs null vs Inf asymmetry (py-polars test_nan_inf_aggregation)" begin
    # min/max treat NaN as non-extremal when a real value exists in the same group ([NaN,5] ->
    # min=max=5), but mean is poisoned by any NaN -> NaN. All-null groups return missing for all
    # three; Inf behaves as an ordinary value throughout. Upstream's exact 6-group fixture.
    df = DataFrame(
        (;
            g = [
                "both_nan", "both_nan", "nan_5", "nan_5", "nan_null", "nan_null",
                "both_none", "both_none", "both_inf", "both_inf", "inf_null", "inf_null",
            ],
            v = Union{Float64, Missing}[NaN, NaN, NaN, 5.0, NaN, missing, missing, missing, Inf, Inf, Inf, missing],
        )
    )
    r = collect(
        agg(
            group_by(lazy(df), "g"), alias(Polars.min(col("v")), "min"),
            alias(Polars.max(col("v")), "max"), alias(mean(col("v")), "mean"),
        )
    )
    byrow = Dict(r[:g][i] => (min = r[:min][i], max = r[:max][i], mean = r[:mean][i]) for i in 1:size(r, 1))

    @test isnan(byrow["both_nan"].min) && isnan(byrow["both_nan"].max) && isnan(byrow["both_nan"].mean)
    @test byrow["nan_5"].min == 5.0 && byrow["nan_5"].max == 5.0 && isnan(byrow["nan_5"].mean)
    @test isnan(byrow["nan_null"].min) && isnan(byrow["nan_null"].max) && isnan(byrow["nan_null"].mean)
    @test ismissing(byrow["both_none"].min) && ismissing(byrow["both_none"].max) && ismissing(byrow["both_none"].mean)
    @test isinf(byrow["both_inf"].min) && isinf(byrow["both_inf"].max) && isinf(byrow["both_inf"].mean)
    @test isinf(byrow["inf_null"].min) && isinf(byrow["inf_null"].max) && isinf(byrow["inf_null"].mean)
end

@testset "keep_name / implode / flatten / reverse" begin
    df = DataFrame((; x = [1, 2, 3]))

    r = select(df, (col("x") |> Polars.sum) |> keep_name)
    @test Tables.columnnames(r) == (:x,)

    imploded = select(df, implode(col("x")))
    @test size(imploded) == (1, 1)
    @test collect(only(imploded[:x])) == [1, 2, 3]

    flat = select(imploded, flatten(col("x")))
    @test collect(flat[:x]) == [1, 2, 3]

    rev = select(df, Polars.reverse(col("x")))
    @test collect(rev[:x]) == [3, 2, 1]
end
