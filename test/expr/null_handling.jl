@testset "fill_null / fill_nan" begin
    df = DataFrame((; x = [1.0, missing, 3.0, NaN]))

    r = select(df, fill_null(col("x"), lit(0.0)) |> alias("filled"))
    @test r[:filled][1] == 1.0
    @test r[:filled][2] == 0.0
    @test r[:filled][3] == 3.0
    @test isnan(r[:filled][4])

    df2 = DataFrame((; x = [1.0, NaN, missing, 4.0]))
    r2 = select(df2, fill_nan(col("x"), lit(-1.0)) |> alias("filled"))
    @test r2[:filled][1] == 1.0
    @test r2[:filled][2] == -1.0
    @test ismissing(r2[:filled][3])
    @test r2[:filled][4] == 4.0
end

@testset "fill_null with strategy" begin
    df = DataFrame((; x = [1, missing, missing, 4, missing]))

    fwd = select(df, alias(fill_null(col("x"); strategy = :forward), "f"))
    @test isequal(collect(fwd[:f]), [1, 1, 1, 4, 4])

    bwd = select(df, alias(fill_null(col("x"); strategy = :backward), "f"))
    @test isequal(collect(bwd[:f]), [1, 4, 4, 4, missing])

    bwd_limited = select(df, alias(fill_null(col("x"); strategy = :backward, limit = 1), "f"))
    @test isequal(collect(bwd_limited[:f]), [1, missing, 4, 4, missing])

    r_mean = select(df, alias(fill_null(col("x"); strategy = :mean), "f"))
    @test collect(r_mean[:f]) == [1, 2, 2, 4, 2] # mean(1, 4) = 2.5, truncated back to the Int64 dtype

    r_min = select(df, alias(fill_null(col("x"); strategy = :min), "f"))
    @test isequal(collect(r_min[:f]), [1, 1, 1, 4, 1])

    r_max = select(df, alias(fill_null(col("x"); strategy = :max), "f"))
    @test isequal(collect(r_max[:f]), [1, 4, 4, 4, 4])

    r_zero = select(df, alias(fill_null(col("x"); strategy = :zero), "f"))
    @test collect(r_zero[:f]) == [1, 0, 0, 4, 0]

    r_one = select(df, alias(fill_null(col("x"); strategy = :one), "f"))
    @test collect(r_one[:f]) == [1, 1, 1, 4, 1]

    # curried form for |> pipelines
    r_curried = select(df, alias(col("x") |> fill_null(strategy = :zero), "f"))
    @test collect(r_curried[:f]) == [1, 0, 0, 4, 0]

    @test_throws ErrorException fill_null(col("x"); strategy = :bogus)
end

@testset "coalesce" begin
    df = DataFrame((; a = [missing, 2, missing], b = [1, missing, missing], c = [9, 9, 9]))

    r = select(df, alias(Base.coalesce(col("a"), col("b"), col("c")), "r"))
    @test r[:r] == [1, 2, 9]

    # Base.coalesce still works on plain Julia values (no type piracy introduced)
    @test Base.coalesce(missing, 5) == 5
end

@testset "interpolate" begin
    df = DataFrame((; x = [missing, 1.0, missing, missing, 4.0, missing]))

    r_linear = select(df, alias(interpolate(col("x")), "i"))
    linear = [r_linear[:i][i] for i in 1:6]
    @test ismissing(linear[1])
    @test linear[2:5] ≈ [1.0, 2.0, 3.0, 4.0]
    @test ismissing(linear[6])

    r_nearest = select(df, alias(interpolate(col("x"); method = :nearest), "i"))
    nearest = [r_nearest[:i][i] for i in 1:6]
    @test ismissing(nearest[1])
    @test nearest[2:5] ≈ [1.0, 1.0, 4.0, 4.0]
    @test ismissing(nearest[6])

    @test_throws ErrorException interpolate(col("x"); method = :bogus)
end

@testset "is_in" begin
    df = DataFrame((; g = ["a", "a", "b", "c"]))

    # membership set built from a literal list expression via implode
    membership = implode(lit("a"))
    r = select(df, is_in(col("g"), membership) |> alias("is_a"))
    @test r[:is_a] == [true, true, false, false]

    filtered = filter(df, is_in(col("g"), membership))
    @test filtered[:g] == ["a", "a"]

    # multi-value membership: implode(lit(::Vector)) (see test/expr/lit_vector.jl) replaces what
    # used to require chaining several single-value implode(lit(x))s together
    filtered_multi = filter(df, is_in(col("g"), implode(lit(["a", "c"]))))
    @test filtered_multi[:g] == ["a", "a", "c"]
end
