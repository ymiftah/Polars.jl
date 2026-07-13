@testset "collect_schema" begin
    df = DataFrame((; x = collect(1:5), y = ["a", "b", "c", "d", "e"]))
    lf = lazy(df)

    sch = collect_schema(lf)
    @test sch.names == (:x, :y)
    @test sch.types == (Union{Missing,Int64}, Union{Missing,String})

    sch2 = collect_schema(with_columns(lf, (col("x") * 2) |> alias("z")))
    @test sch2.names == (:x, :y, :z)
    @test sch2.types[3] == Union{Missing,Int64}

    @test_throws Exception collect_schema(filter(lf, col("nonexistent") > 0))
end

@testset "collect engine=:streaming" begin
    df = DataFrame((; x = collect(1:10), g = repeat(["a", "b"], 5)))
    lf = lazy(df) |> x -> filter(x, col("x") > 2) |> x -> with_columns(x, (col("x") * 2) |> alias("y"))

    default_result = collect(lf; engine=:default)
    streaming_result = collect(lf; engine=:streaming)

    @test default_result[:x] == streaming_result[:x]
    @test default_result[:y] == streaming_result[:y]
    @test default_result[:g] == streaming_result[:g]

    @test_throws Exception collect(lf; engine=:bogus)
end
