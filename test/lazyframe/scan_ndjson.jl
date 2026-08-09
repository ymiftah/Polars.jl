@testset "scan_ndjson / read_ndjson" begin
    df = DataFrame((; category = ["a", "b", "a", "b"], amount = [10, 20, 30, 40]))
    dir = mktempdir()
    path = joinpath(dir, "data.jsonl")
    write_ndjson(path, df)

    lf = scan_ndjson(path)
    @test lf isa Polars.LazyFrame

    all_rows = collect(lf)
    @test size(all_rows) == (4, 2)
    @test all_rows[:category] == df[:category]
    @test all_rows[:amount] == df[:amount]

    result = lf |>
        x -> group_by(x, "category") |>
        x -> agg(x, Polars.sum(col("amount"))) |>
        collect

    by_category = Dict(zip(result[:category], result[:amount]))
    @test by_category["a"] == 40
    @test by_category["b"] == 60
end

@testset "scan_ndjson options" begin
    dir = mktempdir()

    @testset "n_rows / row_index_name / row_index_offset" begin
        path = joinpath(dir, "basic.jsonl")
        write_ndjson(path, DataFrame((; a = [1, 2, 3])))
        @test size(read_ndjson(path; n_rows = 2)) == (2, 1)
        idx = read_ndjson(path; row_index_name = "idx", row_index_offset = 10)
        @test Tables.columnnames(idx)[1] == :idx
        @test Vector(idx[:idx]) == [10, 11, 12]
    end

    @testset "infer_schema_length" begin
        path = joinpath(dir, "infer.jsonl")
        write(path, "{\"a\":1}\n{\"a\":2}\n{\"a\":\"not_a_number\"}\n")
        df_full = read_ndjson(path; infer_schema_length = nothing)
        @test collect(df_full[:a]) == ["1", "2", "not_a_number"]
    end

    @testset "ignore_errors" begin
        path = joinpath(dir, "type_errors.jsonl")
        write(path, "{\"a\":1}\n{\"a\":2}\n")
        df = read_ndjson(path; ignore_errors = true)
        @test collect(df[:a]) == [1, 2]
    end

    @testset "low_memory / rechunk accepted without error" begin
        path = joinpath(dir, "flags.jsonl")
        write_ndjson(path, DataFrame((; a = [1, 2, 3])))
        df = read_ndjson(path; low_memory = true, rechunk = true)
        @test collect(df[:a]) == [1, 2, 3]
    end

    @testset "include_file_paths" begin
        path = joinpath(dir, "withpath.jsonl")
        write_ndjson(path, DataFrame((; a = [1, 2])))
        df = read_ndjson(path; include_file_paths = "src")
        @test all(occursin("withpath.jsonl", s) for s in collect(df[:src]))
    end
end
