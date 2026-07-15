@testset "scan_parquet" begin
    dir = mktempdir()
    write_parquet(
        joinpath(mkpath(joinpath(dir, "year=2023")), "part.parquet"),
        DataFrame((; category = ["a", "b", "a", "b"], amount = [10, 20, 30, 40]))
    )
    write_parquet(
        joinpath(mkpath(joinpath(dir, "year=2024")), "part.parquet"),
        DataFrame((; category = ["a", "b", "a", "b"], amount = [100, 200, 300, 400]))
    )

    lf = scan_parquet(dir)
    @test lf isa Polars.LazyFrame

    all_rows = collect(lf)
    @test size(all_rows) == (8, 3)
    @test Set(all_rows[:year]) == Set([2023, 2024])

    result = lf |>
        x -> filter(x, col("year") == 2024) |>
        x -> group_by(x, "category") |>
        x -> agg(x, Polars.sum(col("amount"))) |>
        collect

    by_category = Dict(zip(result[:category], result[:amount]))
    @test by_category["a"] == 400
    @test by_category["b"] == 600
end

@testset "scan_parquet options" begin
    dir = mktempdir()
    write_parquet(
        joinpath(mkpath(joinpath(dir, "year=2023")), "part.parquet"),
        DataFrame((; category = ["a", "b", "a", "b"], amount = [10, 20, 30, 40]))
    )
    write_parquet(
        joinpath(mkpath(joinpath(dir, "year=2024")), "part.parquet"),
        DataFrame((; category = ["a", "b", "a", "b"], amount = [100, 200, 300, 400]))
    )

    @testset "n_rows truncates" begin
        @test size(read_parquet(dir; n_rows = 3)) == (3, 3)
    end

    @testset "row_index_name / row_index_offset" begin
        df = read_parquet(dir; row_index_name = "idx", row_index_offset = 5)
        @test Tables.columnnames(df)[1] == :idx
        @test Vector(df[:idx]) == 5:12
    end

    @testset "parallel strategies all succeed" begin
        for p in (:auto, :none, :columns, :row_groups)
            @test size(collect(scan_parquet(dir; parallel = p))) == (8, 3)
        end
        @test_throws Exception scan_parquet(dir; parallel = :bogus)
    end

    @testset "hive_partitioning=false disables partition-column detection" begin
        df = read_parquet(dir; hive_partitioning = false)
        @test Set(Tables.columnnames(df)) == Set([:category, :amount])
    end

    @testset "include_file_paths adds a source-path column" begin
        df = read_parquet(dir; include_file_paths = "src_path")
        @test length(unique(Vector(df[:src_path]))) == 2
    end
end
