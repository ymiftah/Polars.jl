@testset "basic aggregations" begin
    df = DataFrame((; x = [1.0, 2.0, 3.0, 4.0]))

    r = select(df, Polars.sum(col("x")) |> alias("sum"),
                   # `product` collides with an unexported Base.product, so the macro that
                   # generates these wrappers extends Base.product instead of defining
                   # Polars.product -- unlike Polars.sum/min/max, it must be called as
                   # Base.product since Polars re-exposes only Base's *exported* names.
                   Base.product(col("x")) |> alias("product"),
                   mean(col("x")) |> alias("mean"),
                   median(col("x")) |> alias("median"),
                   Polars.min(col("x")) |> alias("min"),
                   Polars.max(col("x")) |> alias("max"),
                   arg_min(col("x")) |> alias("arg_min"),
                   arg_max(col("x")) |> alias("arg_max"))
    @test only(r[:sum]) == 10.0
    @test only(r[:product]) == 24.0
    @test only(r[:mean]) == 2.5
    @test only(r[:median]) == 2.5
    @test only(r[:min]) == 1.0
    @test only(r[:max]) == 4.0
    @test only(r[:arg_min]) == 0
    @test only(r[:arg_max]) == 3

    df_dup = DataFrame((; x = [1, 2, 2, 3, 3, 3]))
    r2 = select(df_dup, n_unique(col("x")) |> alias("n_unique"),
                        Polars.count(col("x")) |> alias("count"),
                        Polars.first(col("x")) |> alias("first"),
                        Polars.last(col("x")) |> alias("last"))
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

    r = select(df, Polars.floor(col("x")) |> alias("floor"),
                   Polars.ceil(col("x")) |> alias("ceil"),
                   Polars.abs(col("x")) |> alias("abs"))
    @test collect(r[:floor]) == [-2.0, 2.0, 0.0]
    @test collect(r[:ceil]) == [-1.0, 3.0, 0.0]
    @test collect(r[:abs]) == [1.5, 2.5, 0.0]

    trig = DataFrame((; x = [0.0, 1.0]))
    rt = select(trig, Polars.cos(col("x")) |> alias("cos"),
                      Polars.sin(col("x")) |> alias("sin"),
                      Polars.tan(col("x")) |> alias("tan"),
                      cosh(col("x")) |> alias("cosh"),
                      sinh(col("x")) |> alias("sinh"),
                      tanh(col("x")) |> alias("tanh"))
    @test collect(rt[:cos]) ≈ cos.([0.0, 1.0])
    @test collect(rt[:sin]) ≈ sin.([0.0, 1.0])
    @test collect(rt[:tan]) ≈ tan.([0.0, 1.0])
    @test collect(rt[:cosh]) ≈ cosh.([0.0, 1.0])
    @test collect(rt[:sinh]) ≈ sinh.([0.0, 1.0])
    @test collect(rt[:tanh]) ≈ tanh.([0.0, 1.0])
end

@testset "null/nan predicates" begin
    df = DataFrame((; x = [1.0, Inf, NaN, missing]))

    r = select(df, is_finite(col("x")) |> alias("fin"),
                   is_infinite(col("x")) |> alias("inf"),
                   is_nan(col("x")) |> alias("nan"),
                   is_null(col("x")) |> alias("null"),
                   is_not_null(col("x")) |> alias("notnull"))
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
