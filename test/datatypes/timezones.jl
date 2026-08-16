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

@testset "Dt.base_utc_offset / Dt.dst_offset (py-polars test_base_utc_offset / test_dst_offset)" begin
    # Pacific/Apia famously skipped a calendar day (Dec 30 2011) when Samoa switched sides of the
    # International Date Line, flipping its base offset from UTC-11 to UTC+13 -- a sharper fixture
    # than an ordinary DST transition, and upstream's own choice for this test.
    df = DataFrame((; d = [DateTime(2011, 12, 29), DateTime(2012, 1, 1)]))
    tz_col = Dt.replace_time_zone(col("d"), "Pacific/Apia")
    r = select(df, alias(Dt.base_utc_offset(tz_col), "off"))
    @test collect(r[:off]) == [Dates.Millisecond(-11 * 3600 * 1000), Dates.Millisecond(13 * 3600 * 1000)]

    # Europe/London: Oct 25 2020 (pre-transition, BST/+1h DST) vs Oct 26 2020 (post, GMT/no DST)
    df2 = DataFrame((; d = [DateTime(2020, 10, 25), DateTime(2020, 10, 26)]))
    tz_col2 = Dt.replace_time_zone(col("d"), "Europe/London")
    r2 = select(df2, alias(Dt.dst_offset(tz_col2), "off"))
    @test collect(r2[:off]) == [Dates.Millisecond(3600 * 1000), Dates.Millisecond(0)]

    # both require a time-zone-aware Datetime -- a naive column raises cleanly
    @test_throws PolarsError collect(select(df, alias(Dt.base_utc_offset(col("d")), "x")))
    @test_throws PolarsError collect(select(df, alias(Dt.dst_offset(col("d")), "x")))
end

@testset "null in a timezone-aware struct field (PolarsTimeZonesExt.load_value)" begin
    # Same shape as the P0.9 guard covered in test/datatypes/structs.jl, for the `ZonedDateTime`
    # loader the TimeZones extension supplies. A null *column* element never reaches `load_value`
    # (`getindex` short-circuits on the validity bitmap first), but a null in a schema-typed
    # struct field does: it reports its real dtype even while null, so it slips past the
    # NamedTuple loader's `PolarsValueTypeUnknown` check and lands here. Without the null guard
    # every other `load_value` method has, this failed with polars' own "expected a datetime
    # value, got Null" instead of yielding `missing`.
    df = DataFrame((; t = [DateTime(2024, 6, 15, 12), missing], i = [1, 2]))
    zoned = select(df, alias(Dt.replace_time_zone(col("t"), "UTC"), "t"), col("i"))
    s = select(zoned, alias(as_struct(col("t"), col("i")), "s"))[:s]

    r = collect(s)
    @test r[1].t isa ZonedDateTime
    @test Dates.hour(r[1].t) == 12
    @test r[1].i == 1
    @test ismissing(r[2].t)
    @test r[2].i == 2

    # the plain column path (short-circuited by the validity bitmap) still agrees
    @test ismissing(collect(zoned[:t])[2])
end
