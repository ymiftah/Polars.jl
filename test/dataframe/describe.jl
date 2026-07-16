@testset "describe" begin
    df = DataFrame((;
        x = [1, 2, 3, 4, missing],
        s = ["a", "b", "b", "c", "c"],
        d = [Date(2024, 1, 1), Date(2024, 1, 2), Date(2024, 1, 3), Date(2024, 1, 4), Date(2024, 1, 5)],
    ))
    r = describe(df)

    @test size(r) == (9, 4)
    @test r[:statistic] == ["count", "null_count", "mean", "std", "min", "25%", "50%", "75%", "max"]

    function stat(name)
        i = findfirst(==(name), r[:statistic])
        return (r[:x][i], r[:s][i], r[:d][i])
    end

    # numeric column: full stat set, correctly stringified
    @test parse(Int, stat("count")[1]) == 4
    @test parse(Int, stat("null_count")[1]) == 1
    @test parse(Float64, stat("mean")[1]) ≈ 2.5
    @test parse(Float64, stat("std")[1]) ≈ sqrt(5 / 3)
    @test parse(Int, stat("min")[1]) == 1
    @test parse(Int, stat("max")[1]) == 4

    # string column: mean/std/percentiles are missing, min/max/count/null_count still apply
    @test parse(Int, stat("count")[2]) == 5
    @test parse(Int, stat("null_count")[2]) == 0
    @test ismissing(stat("mean")[2])
    @test ismissing(stat("std")[2])
    @test ismissing(stat("25%")[2])
    @test stat("min")[2] == "a"
    @test stat("max")[2] == "c"

    # date column: same reduced stat set as string, but min/max are still meaningful
    @test ismissing(stat("mean")[3])
    @test stat("min")[3] == "2024-01-01"
    @test stat("max")[3] == "2024-01-05"

    # custom percentiles
    r2 = describe(df; percentiles = [0.1, 0.9])
    @test r2[:statistic] == ["count", "null_count", "mean", "std", "min", "10%", "90%", "max"]

    # empty percentiles: drops all percentile rows, leaves the rest of the stat set intact
    r3 = describe(df; percentiles = Float64[])
    @test r3[:statistic] == ["count", "null_count", "mean", "std", "min", "max"]
end
