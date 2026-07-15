@testset "Series" begin
    values = [1, 2, 3, 4, 5]
    s = Series(:values, values)
    @test sum(values) == sum(s)
end

@testset "Series getindex across dtypes" begin
    s_str = Series(:names, ["a", "b", missing, "d"])
    @test s_str[1] == "a"
    @test s_str[2] == "b"
    @test ismissing(s_str[3])
    @test s_str[4] == "d"

    s_bool = Series(:flags, [true, false, true, missing])
    @test s_bool[1] == true
    @test s_bool[2] == false
    @test s_bool[3] == true
    @test ismissing(s_bool[4])

    s_date = Series(:dates, [Date(2024, 1, 1), missing, Date(2024, 1, 3)])
    @test s_date[1] == Date(2024, 1, 1)
    @test ismissing(s_date[2])
    @test s_date[3] == Date(2024, 1, 3)

    s_dt = Series(:dts, [DateTime(2024, 1, 1, 1, 2, 3), missing])
    @test s_dt[1] == DateTime(2024, 1, 1, 1, 2, 3)
    @test ismissing(s_dt[2])

    # eltype is the real Dates.DateTime (not an internal wrapper), so collect/copy/broadcast
    # all work directly -- no more direct-indexing-only workaround needed.
    @test eltype(s_dt) == Union{Missing, DateTime}
    @test isequal(collect(s_dt), [DateTime(2024, 1, 1, 1, 2, 3), missing])
    @test isequal(copy(s_dt), collect(s_dt))

    # Duration columns can't be constructed directly (no write-side arrow support for
    # Duration, unlike Date/DateTime), but arise naturally from datetime subtraction.
    df_dt = DataFrame(
        (;
            a = [DateTime(2024, 1, 1, 10, 0, 0), DateTime(2024, 1, 2, 0, 0, 0)],
            b = [DateTime(2024, 1, 1, 8, 0, 0), DateTime(2024, 1, 1, 0, 0, 0)],
        )
    )
    diffs = select(df_dt, (col("a") - col("b")) |> alias("diff"))[:diff]
    @test diffs[1] == Dates.Nanosecond(2 * 3600 * 1_000_000_000)
    @test diffs[2] == Dates.Nanosecond(24 * 3600 * 1_000_000_000)

    # eltype is the real, resolution-specific Dates.Nanosecond -- collect works here too
    @test eltype(diffs) == Dates.Nanosecond
    @test collect(diffs) == [Dates.Nanosecond(2 * 3600 * 1_000_000_000), Dates.Nanosecond(24 * 3600 * 1_000_000_000)]
end

@testset "Series getindex out-of-bounds (regression: FFI panic in polars_series_get)" begin
    # `polars_series_get` backs the Date/DateTime/Duration/String/List/Struct getindex methods
    # (unlike the numeric/bool methods, which go through the already-fallible `gen_series_get!`
    # family) -- an out-of-bounds index here used to `.unwrap()` a Rust panic straight across the
    # FFI boundary, crashing the whole Julia process instead of raising a catchable error.
    s_str = Series(:names, ["a", "b"])
    @test_throws ErrorException s_str[5]
    @test s_str[1] == "a" # in-bounds access still correct after the fix

    s_date = Series(:dates, [Date(2024, 1, 1)])
    @test_throws ErrorException s_date[5]
    @test s_date[1] == Date(2024, 1, 1)

    s_dt = Series(:dts, [DateTime(2024, 1, 1)])
    @test_throws ErrorException s_dt[5]
    @test s_dt[1] == DateTime(2024, 1, 1)

    df_list = DataFrame((; x = [1, 2, 3]))
    s_list = select(df_list, implode(col("x")) |> alias("l"))[:l]
    @test_throws ErrorException s_list[5]
    @test s_list[1] isa Series

    df_struct = DataFrame((; a = [1], b = ["x"]))
    s_struct = select(df_struct, as_struct(col("a"), col("b")) |> alias("s"))[:s]
    @test_throws ErrorException s_struct[5]
    @test s_struct[1].a == 1
end
