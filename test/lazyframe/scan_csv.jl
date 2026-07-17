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

        # missing_is_null: default true means an empty field is null; false keeps it as ""
        empty_path = joinpath(dir, "empty_field.csv")
        write(empty_path, "a,b\n1,\n2,x\n")
        default_df = read_csv(empty_path)
        @test isequal(collect(default_df[:b]), [missing, "x"])
        kept_df = read_csv(empty_path; missing_is_null = false)
        @test collect(kept_df[:b]) == ["", "x"]
    end

    @testset "skip_rows_after_header" begin
        path = joinpath(dir, "skip_after_header.csv")
        write(path, "a,b\n1,x\n2,y\n3,z\n")
        df = read_csv(path; skip_rows_after_header = 1)
        @test collect(df[:a]) == [2, 3]
        @test collect(df[:b]) == ["y", "z"]
    end

    @testset "truncate_ragged_lines" begin
        path = joinpath(dir, "ragged.csv")
        write(path, "a,b\n1,2,3\n4,5\n")
        @test_throws Exception collect(scan_csv(path))
        df = read_csv(path; truncate_ragged_lines = true)
        @test collect(df[:a]) == [1, 4]
        @test collect(df[:b]) == [2, 5]
    end

    @testset "infer_schema_length" begin
        # first 2 rows look like small integers; a later row has a string value -- a short
        # infer_schema_length can miss the true (String) dtype and error/mis-parse, while
        # scanning the full file (infer_schema_length = nothing) infers String correctly
        path = joinpath(dir, "infer.csv")
        write(path, "a\n1\n2\nnot_a_number\n")
        df_full = read_csv(path; infer_schema_length = nothing)
        @test collect(df_full[:a]) == ["1", "2", "not_a_number"]
    end

    @testset "ignore_errors" begin
        path = joinpath(dir, "type_errors.csv")
        write(path, "a\n1\n2\n")
        # sanity: with a schema/dtype conflict avoided, ignore_errors just doesn't break a
        # well-formed parse
        df = read_csv(path; ignore_errors = true)
        @test collect(df[:a]) == [1, 2]
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
