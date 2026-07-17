using TimeZones

@testset "Dt.replace_time_zone / convert_time_zone (TimeZones.jl extension)" begin
    df = DataFrame((; t = [DateTime(2024, 6, 15, 12, 0, 0), DateTime(2024, 12, 15, 12, 0, 0)]))

    # attach a UTC label to a naive column
    utc = select(df, alias(Dt.replace_time_zone(col("t"), "UTC"), "t"))
    zdt_utc = collect(utc[:t])
    @test zdt_utc isa Vector{ZonedDateTime}
    @test all(==(TimeZone("UTC")), TimeZones.timezone.(zdt_utc))
    @test Dates.hour.(zdt_utc) == [12, 12]

    # convert_time_zone preserves the instant, relabels into a new zone -- local hour shifts by
    # the (DST-dependent) UTC offset
    ny = select(utc, alias(Dt.convert_time_zone(col("t"), "America/New_York"), "t"))
    zdt_ny = collect(ny[:t])
    @test all(==(TimeZone("America/New_York")), TimeZones.timezone.(zdt_ny))
    @test Dates.hour.(zdt_ny) == [8, 7] # EDT (UTC-4) in June, EST (UTC-5) in December

    # replace_time_zone(nothing) strips back to naive, keeping the *current* wall-clock value --
    # readable without the extension too
    naive_again = select(utc, alias(Dt.replace_time_zone(col("t"), nothing), "t"))
    @test eltype(naive_again[:t]) == Dates.DateTime
    @test collect(naive_again[:t]) == df[:t]

    naive_from_ny = select(ny, alias(Dt.replace_time_zone(col("t"), nothing), "t"))
    @test collect(naive_from_ny[:t]) == [DateTime(2024, 6, 15, 8), DateTime(2024, 12, 15, 7)]

    # non_existent / ambiguous keyword plumbing at least doesn't error for the common values
    r = select(df, alias(Dt.replace_time_zone(col("t"), "UTC"; ambiguous = "raise", non_existent = :null), "t"))
    @test collect(r[:t]) isa Vector{ZonedDateTime}
    @test_throws ErrorException Dt.replace_time_zone(col("t"), "UTC"; non_existent = :bogus)
end

@testset "curried Dt.replace_time_zone / convert_time_zone" begin
    df = DataFrame((; t = [DateTime(2024, 6, 15, 12, 0, 0), DateTime(2024, 12, 15, 12, 0, 0)]))

    r_direct = select(df, alias(Dt.replace_time_zone(col("t"), "UTC"), "t"))
    r_curried = select(df, alias(col("t") |> Dt.replace_time_zone("UTC"), "t"))
    @test collect(r_direct[:t]) == collect(r_curried[:t])

    r_direct2 = select(r_direct, alias(Dt.convert_time_zone(col("t"), "America/New_York"), "t"))
    r_curried2 = select(r_curried, alias(col("t") |> Dt.convert_time_zone("America/New_York"), "t"))
    @test collect(r_direct2[:t]) == collect(r_curried2[:t])

    # curried form also plumbs ambiguous/non_existent through correctly
    r_direct3 = select(df, alias(Dt.replace_time_zone(col("t"), "UTC"; non_existent = :null), "t"))
    r_curried3 = select(df, alias(col("t") |> Dt.replace_time_zone("UTC"; non_existent = :null), "t"))
    @test collect(r_direct3[:t]) == collect(r_curried3[:t])
end
