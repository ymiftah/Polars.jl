@testset "horizontal reductions" begin
    df = DataFrame((; a = [1, 2, missing], b = [4, missing, 6], c = [7, 8, 9]))

    r_all = select(df, alias(all_horizontal(col("a") .> 0, col("c") .> 0), "r"))
    @test isequal(r_all[:r], [true, true, missing])

    r_any = select(df, alias(any_horizontal(col("a") .> 1, col("c") .> 8), "r"))
    @test r_any[:r] == [false, true, true]

    r_min = select(df, alias(min_horizontal(col("a"), col("b"), col("c")), "r"))
    @test r_min[:r] == [1, 2, 6]

    r_max = select(df, alias(max_horizontal(col("a"), col("b"), col("c")), "r"))
    @test r_max[:r] == [7, 8, 9]

    r_sum_ignore = select(df, alias(sum_horizontal(col("a"), col("b"), col("c")), "r"))
    @test r_sum_ignore[:r] == [12, 10, 15]

    r_sum_strict = select(
        df, alias(sum_horizontal(col("a"), col("b"), col("c"); ignore_nulls = false), "r")
    )
    @test r_sum_strict[:r][1] == 12
    @test ismissing(r_sum_strict[:r][2])
    @test ismissing(r_sum_strict[:r][3])

    r_mean = select(df, alias(mean_horizontal(col("a"), col("b"), col("c")), "r"))
    @test r_mean[:r] ≈ [4.0, 5.0, 7.5]
end

@testset "as_struct" begin
    df = DataFrame((; a = [1, 2], b = ["x", "y"]))

    r = select(df, alias(as_struct(col("a"), col("b")), "s"))
    fa = select(r, Structs.field_by_name(col("s"), "a"))
    fb = select(r, Structs.field_by_name(col("s"), "b"))
    @test fa[:a] == [1, 2]
    @test fb[:b] == ["x", "y"]

    @test_throws PolarsError as_struct()
end
