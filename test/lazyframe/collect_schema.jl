@testset "collect_schema" begin
    df = DataFrame((; x = collect(1:5), y = ["a", "b", "c", "d", "e"]))
    lf = lazy(df)

    sch = collect_schema(lf)
    @test sch.names == (:x, :y)
    @test sch.types == (Union{Missing, Int64}, Union{Missing, String})

    sch2 = collect_schema(with_columns(lf, (col("x") * 2) |> alias("z")))
    @test sch2.names == (:x, :y, :z)
    @test sch2.types[3] == Union{Missing, Int64}

    @test_throws Exception collect_schema(filter(lf, col("nonexistent") > 0))
end

@testset "schema mismatch across concat" begin
    df_a = DataFrame((; x = [1, 2], y = [10, 20]))

    # column-name mismatch: concat() and collect_schema() both succeed silently, reporting
    # only the first frame's schema -- the error only surfaces at collect() time
    df_b_name_mismatch = DataFrame((; x = [3, 4], z = [30, 40]))
    lf_name_mismatch = concat([lazy(df_a), lazy(df_b_name_mismatch)])
    sch = collect_schema(lf_name_mismatch)
    @test sch.names == (:x, :y)  # first frame's schema, mismatch not detected here
    @test_throws Exception collect(lf_name_mismatch)

    # dtype mismatch on a shared column name: collect_schema() throws immediately
    df_b_dtype_mismatch = DataFrame((; x = ["a", "b"], y = [30, 40]))
    lf_dtype_mismatch = concat([lazy(df_a), lazy(df_b_dtype_mismatch)])
    @test_throws Exception collect_schema(lf_dtype_mismatch)
end

@testset "collect engine=:streaming" begin
    df = DataFrame((; x = collect(1:10), g = repeat(["a", "b"], 5)))
    lf = lazy(df) |> x -> filter(x, col("x") > 2) |> x -> with_columns(x, (col("x") * 2) |> alias("y"))

    default_result = collect(lf; engine = :default)
    streaming_result = collect(lf; engine = :streaming)

    @test default_result[:x] == streaming_result[:x]
    @test default_result[:y] == streaming_result[:y]
    @test default_result[:g] == streaming_result[:g]

    @test_throws Exception collect(lf; engine = :bogus)
end
