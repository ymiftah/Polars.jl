@testset "describe" begin
    df = DataFrame(
        (;
            x = [1, 2, 3, 4, missing],
            s = ["a", "b", "b", "c", "c"],
            d = [Date(2024, 1, 1), Date(2024, 1, 2), Date(2024, 1, 3), Date(2024, 1, 4), Date(2024, 1, 5)],
        )
    )
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

    # fractional percentiles must keep their distinguishing precision in the label -- 99.9% and
    # 99.99% previously both rounded to the same "100%" (a real bug, fixed alongside this test;
    # py-polars test_df_describe_quantile_precision)
    r4 = describe(df; percentiles = [0.99, 0.999, 0.9999])
    @test all(in(collect(r4[:statistic])), ["99%", "99.9%", "99.99%"])
    @test length(unique(collect(r4[:statistic]))) == length(r4[:statistic])  # no more label collisions
end

@testset "describe edge cases (py-polars test_df_describe_empty_column, test_df_describe_empty)" begin
    # a 0-row frame with a real (typed) schema still describes cleanly: count/null_count are 0,
    # everything else is `missing` rather than an error
    df_empty_col = DataFrame((; a = Int64[]))
    r = describe(df_empty_col)
    @test collect(r[:statistic]) == ["count", "null_count", "mean", "std", "min", "25%", "50%", "75%", "max"]
    @test r[:a][1] == "0" && r[:a][2] == "0"  # count, null_count
    @test all(ismissing, collect(r[:a])[3:end])

    # a genuinely columnless (0-row, 0-column) frame has nothing to describe -- upstream raises
    # `TypeError: cannot describe a DataFrame that has no columns`; confirmed live divergence here
    # (this wrapper currently returns a (9, 1) frame with just the `statistic` column instead of
    # raising) -- see plans/parity/api_gap_audit.md Group 11's Batch 12 entry.
    @test_broken (
        try
            describe(DataFrame(NamedTuple()))
            false
        catch e
            e isa PolarsError || e isa ErrorException
        end
    )
end
