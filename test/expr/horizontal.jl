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

@testset "concat_str" begin
    df = DataFrame((; a = ["x", "y", missing], b = [1, 2, 3], c = [1.5, missing, 3.5]))

    # default separator="" and ignore_nulls=false: a null in the row poisons the whole result
    r_default = select(df, alias(concat_str(col("a"), col("b")), "r"))
    @test isequal(collect(r_default[:r]), ["x1", "y2", missing])

    # a non-empty separator, and non-string dtypes cast to string first
    r_sep = select(df, alias(concat_str(col("a"), col("b"), col("c"); separator = "-"), "r"))
    @test r_sep[:r][1] == "x-1-1.5"
    @test ismissing(r_sep[:r][2]) # c is missing here
    @test ismissing(r_sep[:r][3]) # a is missing here

    # ignore_nulls=true: nulls are skipped rather than poisoning the row
    r_ignore = select(df, alias(concat_str(col("a"), col("b"), col("c"); ignore_nulls = true), "r"))
    @test r_ignore[:r][1] == "x11.5"
    @test r_ignore[:r][2] == "y2" # c is missing here, skipped rather than poisoning the row
    @test r_ignore[:r][3] == "33.5" # a is missing here, skipped rather than poisoning the row

    # a unicode separator exercises the `ncodeunits`-not-`length` string-marshalling convention
    r_unicode = select(df, alias(concat_str(col("a"), col("b"); separator = "→", ignore_nulls = true), "r"))
    @test r_unicode[:r][1] == "x→1"

    # LazyFrame form agrees
    r_lazy = collect(select(lazy(df), alias(concat_str(col("a"), col("b")), "r")))
    @test isequal(collect(r_lazy[:r]), collect(r_default[:r]))

    # single-expr and zero-expr calls are valid (upstream has no non-emptiness check on this one,
    # unlike concat_list below)
    r_single = select(df, alias(concat_str(col("b")), "r"))
    @test r_single[:r] == ["1", "2", "3"]
end

@testset "concat_list" begin
    df = DataFrame((; a = [1, 2, missing], b = [4, 5, 6]))

    r = select(df, alias(concat_list(col("a"), col("b")), "r"))
    @test isequal(collect(r[:r]), [[1, 4], [2, 5], [missing, 6]])

    # concatenating a List-typed expression with a scalar column flattens one level, not nested
    r_three = select(df, alias(concat_list(col("a"), col("b"), col("b") * 10), "r"))
    @test isequal(collect(r_three[:r]), [[1, 4, 40], [2, 5, 50], [missing, 6, 60]])

    # LazyFrame form agrees
    r_lazy = collect(select(lazy(df), alias(concat_list(col("a"), col("b")), "r")))
    @test isequal(collect(r_lazy[:r]), collect(r[:r]))

    # empty input errors cleanly rather than panicking (upstream's own `polars_ensure!`)
    @test_throws PolarsError concat_list()
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

@testset "horizontal reductions: mismatched-length inputs raise cleanly (py-polars test_shape_mismatch_19336)" begin
    for f in (min_horizontal, max_horizontal, sum_horizontal, mean_horizontal)
        @test_throws PolarsError select(
            DataFrame(NamedTuple()), f(lit(Series(:_, [1, 2, 3])), lit(Series(:_, [1, 2])))
        )
    end
end
