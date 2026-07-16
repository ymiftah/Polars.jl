@testset "Series" begin
    values = [1, 2, 3, 4, 5]
    s = Series(:values, values)
    @test sum(values) == sum(s)
end

@testset "Series name" begin
    # Test name on directly constructed Series
    s = Series(:test_col, [1, 2, 3])
    @test name(s) == "test_col"

    # Test name on Series obtained via DataFrame column access
    df = DataFrame((; x = [10, 20, 30], y = ["a", "b", "c"]))
    s_x = df[:x]
    @test name(s_x) == "x"
    s_y = df[:y]
    @test name(s_y) == "y"

    # Test name consistency after operations (e.g., via select)
    result = select(df, col("x") |> alias("renamed"))
    s_renamed = result[:renamed]
    @test name(s_renamed) == "renamed"
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

@testset "bulk/zero-copy Series materialization (read_series/collect)" begin
    # Bulk-copy path must agree with the existing per-element getindex path across every type
    # category read_series supports, both with and without nulls.
    @testset "numeric" begin
        for (values, T) in (
                (Int64[1, 2, 3, 4, 5], Int64),
                (Float64[1.5, 2.5, 3.5], Float64),
                (Int32[10, 20, 30], Int32),
            )
            s = Series(:x, values)
            bulk = collect(s)
            @test bulk == [s[i] for i in eachindex(s)]
            @test bulk isa Vector{T}
        end

        s = Series(:x, Union{Int64, Missing}[1, missing, 3, missing, 5])
        bulk = collect(s)
        @test isequal(bulk, [s[i] for i in eachindex(s)])
        @test bulk isa Vector{Union{Int64, Missing}}
    end

    @testset "bool" begin
        s = Series(:x, [true, false, true])
        @test collect(s) == [s[i] for i in eachindex(s)]

        s = Series(:x, Union{Bool, Missing}[true, missing, false])
        @test isequal(collect(s), [s[i] for i in eachindex(s)])
    end

    @testset "date/datetime" begin
        s = Series(:x, [Date(2024, 1, 1), Date(2024, 6, 15)])
        @test collect(s) == [s[i] for i in eachindex(s)]

        s = Series(:x, Union{Date, Missing}[Date(2024, 1, 1), missing])
        @test isequal(collect(s), [s[i] for i in eachindex(s)])

        s = Series(:x, [DateTime(2024, 1, 1, 10, 30, 0), DateTime(2024, 6, 15)])
        @test collect(s) == [s[i] for i in eachindex(s)]

        s = Series(:x, Union{DateTime, Missing}[DateTime(2024, 1, 1), missing])
        @test isequal(collect(s), [s[i] for i in eachindex(s)])
    end

    @testset "empty series" begin
        @test collect(Series(:x, Int64[])) == Int64[]
        @test collect(Series(:x, Date[])) == Date[]
    end

    @testset "sliced/offset series (post-filter/head)" begin
        df = DataFrame((; x = collect(1:20)))
        lf = lazy(df)

        s = Polars.collect(head(lf, 5))[:x]
        @test collect(s) == [s[i] for i in eachindex(s)] == 1:5

        s = Polars.collect(filter(lf, col("x") > 10))[:x]
        @test collect(s) == [s[i] for i in eachindex(s)] == 11:20
    end

    @testset "true zero-copy opt-in" begin
        s = Series(:x, Int64[10, 20, 30, 40, 50])
        arr = Polars.read_series(s; zerocopy = true)
        @test arr == collect(s)

        # the borrowed buffer must stay valid (and correct) after the source Series/DataFrame
        # are dropped and GC'd -- the whole point of the release-on-finalize keeper.
        s = nothing
        GC.gc()
        @test arr == [10, 20, 30, 40, 50]
    end

    @testset "double-release is idempotent (no double-free)" begin
        s = Series(:x, Union{Int64, Missing}[1, missing, 3])
        h = Polars.ExportedArray(Polars.polars_series_export_carray(s))
        Polars.release!(h)  # eager release, as the copy path does
        Polars.release!(h)  # must be a no-op, not a double-free
        finalize(h)          # forcing the finalizer too must also be a no-op
        GC.gc()
    end

    @testset "fallback to per-element for unsupported types" begin
        s = Series(:x, ["hello", "world"])
        @test Polars.read_series(s) === nothing
        @test collect(s) == [s[i] for i in eachindex(s)]

        df = DataFrame((; x = [[1, 2, 3], [4, 5]]))
        s = df[:x]
        @test Polars.read_series(s) === nothing
        bulk = collect(s)
        @test length(bulk) == 2
        @test collect(bulk[1]) == [1, 2, 3]
        @test collect(bulk[2]) == [4, 5]
    end
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
