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
