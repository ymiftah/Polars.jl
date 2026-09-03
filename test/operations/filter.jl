@testset "filter" begin
    df = DataFrame((; x = [1, 2, 3, 3.1, missing]))

    @test filter(df, col("x") >= 2) |> size == (3, 1)
    @test filter(df, col("x") > 2) |> size == (2, 1)
    @test filter(df, col("x") == 2) |> size == (1, 1)

    @test filter(df, col("x") |> is_null) |> size == (1, 1)
    @test filter(df, col("x") |> is_null |> Polars.not) |> size == (4, 1)

    # LazyFrame form agrees
    @test filter(lazy(df), col("x") >= 2) |> collect |> size == (3, 1)
end

@testset "filter with combined predicates" begin
    df = DataFrame(
        (;
            x = [1, 2, 3, 4, 5],
            y = [10, 20, 30, 40, 50],
            flag = [true, false, true, false, true],
        )
    )

    # AND predicate: x > 2 AND flag == true
    r_and = filter(df, (col("x") > 2) & (col("flag") == true))
    @test size(r_and) == (2, 3)
    @test r_and[:x] == [3, 5]

    # OR predicate: x < 2 OR x > 4
    r_or = filter(df, (col("x") < 2) | (col("x") > 4))
    @test size(r_or) == (2, 3)
    @test r_or[:x] == [1, 5]

    # Complex: (x > 2 AND flag) OR y > 35
    r_complex = filter(df, ((col("x") > 2) & (col("flag") == true)) | (col("y") > 35))
    @test size(r_complex) == (3, 3)
    @test r_complex[:x] == [3, 4, 5]
end

@testset "filter emptying the DataFrame" begin
    df = DataFrame(
        (;
            x = [1, 2, 3],
            y = ["a", "b", "c"],
        )
    )

    # Filter with impossible condition
    r_empty = filter(df, col("x") > 100)
    @test size(r_empty) == (0, 2)
    @test Tables.columnnames(r_empty) == (:x, :y)
end

@testset "filter with null-producing predicates" begin
    df = DataFrame(
        (;
            a = [1, 2, 3, missing],
            b = [10, 20, missing, 40],
        )
    )

    # Predicate that produces nulls: a == b (comparing a and b)
    # Rows with null in either a or b will produce null result, which excludes the row
    r_nullpred = filter(df, col("a") == col("b"))
    @test size(r_nullpred) == (0, 2)  # No row matches (1≠10, 2≠20, etc.)

    # Filter with is_null produces nulls for non-null values, which excludes those rows
    r_has_null = filter(df, (col("a") |> is_null) | (col("b") |> is_null))
    @test size(r_has_null) == (2, 2)  # rows 3 and 4 have nulls
end

@testset "filter on empty frames (py-polars test_filter_on_empty)" begin
    # an is_null() predicate against a zero-row column of various dtypes stays empty rather than
    # erroring -- there's nothing to iterate, but the predicate must still resolve cleanly
    for col_ in (Int32[], Bool[], String[], Vector{UInt8}[])
        df = DataFrame((; a = col_))
        r = filter(df, col("a") |> is_null)
        @test size(r) == (0, 1)
    end
end

@testset "filter(lit(true)) preserves an all-null column (py-polars test_filter_19771)" begin
    # a predicate that's true for every row is a genuine no-op -- it must not coerce the column's
    # existing `missing`s into anything else
    df = DataFrame((; a = Union{Missing, Int}[missing, missing]))
    r = filter(df, lit(true))
    @test size(r) == (2, 1)
    @test isequal(collect(r[:a]), [missing, missing])
end
