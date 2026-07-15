@testset "scan_csv / read_csv / write_csv" begin
    df = DataFrame((; category = ["a", "b", "a", "b"], amount = [10, 20, 30, 40]))
    path = write_temp_csv(df)

    lf = scan_csv(path)
    @test lf isa Polars.LazyFrame

    all_rows = collect(lf)
    @test size(all_rows) == (4, 2)
    @test all_rows[:category] == df[:category]
    @test all_rows[:amount] == df[:amount]

    # read_csv is the eager entry point (collect ∘ scan_csv)
    eager = read_csv(path)
    @test eager isa Polars.DataFrame
    @test eager[:category] == df[:category]
    @test eager[:amount] == df[:amount]

    result = lf |>
        x -> group_by(x, "category") |>
        x -> agg(x, Polars.sum(col("amount"))) |>
        collect

    by_category = Dict(zip(result[:category], result[:amount]))
    @test by_category["a"] == 40
    @test by_category["b"] == 60
end

@testset "scan_csv options" begin
    dir = mktempdir()

    @testset "n_rows / row_index_name / row_index_offset" begin
        path = joinpath(dir, "basic.csv")
        write_csv(path, DataFrame((; a = [1, 2, 3])))
        @test size(read_csv(path; n_rows = 2)) == (2, 1)
        idx = read_csv(path; row_index_name = "idx", row_index_offset = 10)
        @test Tables.columnnames(idx)[1] == :idx
        @test Vector(idx[:idx]) == [10, 11, 12]
    end

    @testset "separator / quote_char / comment_prefix" begin
        path = joinpath(dir, "opts.csv")
        write(path, "# a comment\na;b\n1;\"has;semicolon\"\n2;plain\n")
        df = read_csv(path; separator = ';', comment_prefix = "#")
        @test collect(df[:b]) == ["has;semicolon", "plain"]

        no_quote_path = joinpath(dir, "noquote.csv")
        write(no_quote_path, "a\n\"literal\"\n")
        df2 = read_csv(no_quote_path; quote_char = nothing)
        @test collect(df2[:a]) == ["\"literal\""]
    end

    @testset "skip_rows / has_header" begin
        path = joinpath(dir, "skip.csv")
        write(path, "junk\na,b\n1,2\n")
        df = read_csv(path; skip_rows = 1)
        @test Tables.columnnames(df) == (:a, :b)

        path2 = joinpath(dir, "noheader.csv")
        write(path2, "1,x\n2,y\n")
        df2 = read_csv(path2; has_header = false)
        @test collect(df2[Symbol("column_1")]) == [1, 2]
    end

    @testset "null_value / missing_is_null" begin
        path = joinpath(dir, "nulls.csv")
        write(path, "a,b\n1,NA\n2,20\n")
        df = read_csv(path; null_value = "NA")
        @test isequal(collect(df[:b]), [missing, 20])
    end

    @testset "try_parse_dates" begin
        path = joinpath(dir, "dates.csv")
        write(path, "d\n2024-01-01\n2024-01-02\n")
        df = read_csv(path; try_parse_dates = true)
        @test eltype(df[:d]) == Date
    end

    @testset "allow_missing_columns" begin
        multi = mkpath(joinpath(dir, "multi"))
        write_csv(joinpath(multi, "f1.csv"), DataFrame((; x = [1, 2], y = [3, 4])))
        write_csv(joinpath(multi, "f2.csv"), DataFrame((; x = [5, 6])))
        @test_throws Exception collect(scan_csv(joinpath(multi, "*.csv")))
        df = read_csv(joinpath(multi, "*.csv"); allow_missing_columns = true)
        @test size(df) == (4, 2)
    end
end
