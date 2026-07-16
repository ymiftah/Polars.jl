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
    df = DataFrame((;
        x = [1, 2, 3, 4, 5],
        y = [10, 20, 30, 40, 50],
        flag = [true, false, true, false, true]
    ))

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
    df = DataFrame((;
        x = [1, 2, 3],
        y = ["a", "b", "c"]
    ))

    # Filter with impossible condition
    r_empty = filter(df, col("x") > 100)
    @test size(r_empty) == (0, 2)
    @test Tables.columnnames(r_empty) == (:x, :y)
end

@testset "filter with null-producing predicates" begin
    df = DataFrame((;
        a = [1, 2, 3, missing],
        b = [10, 20, missing, 40]
    ))

    # Predicate that produces nulls: a == b (comparing a and b)
    # Rows with null in either a or b will produce null result, which excludes the row
    r_nullpred = filter(df, col("a") == col("b"))
    @test size(r_nullpred) == (0, 2)  # No row matches (1≠10, 2≠20, etc.)

    # Filter with is_null produces nulls for non-null values, which excludes those rows
    r_has_null = filter(df, (col("a") |> is_null) | (col("b") |> is_null))
    @test size(r_has_null) == (2, 2)  # rows 3 and 4 have nulls
end
