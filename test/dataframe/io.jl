alleq(a, b) = length(a) == length(b) && all(isequal(a[i], b[i]) for i in eachindex(a))

@testset "Date" begin
    dates = [Date(2024, 1, 1), Date(2024, 1, 2), Date(2024, 1, 3)]
    df = DataFrame((; d = dates))

    @test Polars.schema(df).types == (Date,)
    @test df[:d] == dates

    path = write_temp_parquet(df)
    df2 = read_parquet(path)
    @test df2[:d] == dates
end

@testset "parquet round-trip across dtypes" begin
    df = DataFrame(
        (;
            i = [1, 2, 3, missing],
            f = [1.5, 2.5, missing, 4.5],
            b = [true, false, true, missing],
            s = ["a", "b", missing, "d"],
            d = [Date(2024, 1, 1), Date(2024, 1, 2), missing, Date(2024, 1, 4)],
            dt = [DateTime(2024, 1, 1, 1), missing, DateTime(2024, 1, 1, 3), DateTime(2024, 1, 1, 4)],
        )
    )

    path = write_temp_parquet(df)
    df2 = read_parquet(path)

    @test size(df2) == size(df)
    @test alleq(df2[:i], df[:i])
    @test alleq(df2[:f], df[:f])
    @test alleq(df2[:b], df[:b])
    @test alleq(df2[:s], df[:s])
    @test alleq(df2[:d], df[:d])
    @test alleq(df2[:dt], df[:dt])
end
