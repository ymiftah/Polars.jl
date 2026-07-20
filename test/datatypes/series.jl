@testset "Series" begin
    values = [1, 2, 3, 4, 5]
    s = Series(:values, values)
    @test sum(values) == sum(s)
end

@testset "Series name" begin
    # Test name on directly constructed Series
    s = Series(:test_col, [1, 2, 3])
    @test Polars.name(s) == "test_col"

    # Test name on Series obtained via DataFrame column access
    df = DataFrame((; x = [10, 20, 30], y = ["a", "b", "c"]))
    s_x = df[:x]
    @test Polars.name(s_x) == "x"
    s_y = df[:y]
    @test Polars.name(s_y) == "y"

    # Test name consistency after operations (e.g., via select)
    result = select(df, col("x") |> alias("renamed"))
    s_renamed = result[:renamed]
    @test Polars.name(s_renamed) == "renamed"
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

    @testset "string/binary (P1.2 bulk read via Arrow view arrays)" begin
        # Bulk path must agree with the (still-correct, just slow) per-element getindex path
        # across short (<=12 bytes, inline in the Arrow "view" struct), long (out-of-line, in a
        # variadic data buffer), empty, and non-ASCII values.
        for (values, T) in (
                (["hi", "café", "a"^30, "", "π_test", "日本語"], String),
                ([UInt8[1, 2, 3], UInt8[], rand(UInt8, 30), rand(UInt8, 5)], Vector{UInt8}),
            )
            s = Series(:x, values)
            @test s.fmt in ("vu", "vz")
            bulk = collect(s)
            @test bulk == [s[i] for i in eachindex(s)]
            @test bulk isa Vector{T}
        end

        s = Series(:x, Union{String, Missing}["hi", missing, "a"^30, "", missing])
        @test isequal(collect(s), [s[i] for i in eachindex(s)])

        s = Series(:x, Union{Vector{UInt8}, Missing}[UInt8[1, 2], missing, rand(UInt8, 30)])
        @test isequal(collect(s), [s[i] for i in eachindex(s)])

        # sliced (non-zero ArrowArray offset) -- must still index the right logical rows
        df = DataFrame((; s = ["a", "bb", "café", missing, "e"^20, "f", "g"^15]))
        sl = df[:s][3:6]
        @test isequal(collect(sl), [sl[i] for i in eachindex(sl)])
        @test isequal(collect(sl), ["café", missing, "e"^20, "f"])
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
        h = Polars._export_carray(s)
        Polars.release!(h)  # eager release, as the copy path does
        Polars.release!(h)  # must be a no-op, not a double-free
        finalize(h)          # forcing the finalizer too must also be a no-op
        GC.gc()
    end

    @testset "List: bulk read (leaf child) vs per-element agreement" begin
        # A List<Int64> column IS a read_series bulk-read target (leaf child format) -- elements
        # materialize as plain Vectors now, not nested Series (see arrow/read.jl's _read_list).
        df = DataFrame((; x = [[1, 2, 3], [4, 5]]))
        s = df[:x]
        @test Polars.read_series(s) !== nothing
        bulk = collect(s)
        # eltype conservatively includes Missing at the element level even though this column's
        # elements happen to have none -- parse_format can't know actual child nullability from
        # the schema alone (see _read_list's docstring); matches Series{T}'s declared eltype.
        @test bulk isa Vector{Vector{Union{Int64, Missing}}}
        @test bulk == [[1, 2, 3], [4, 5]]
        @test bulk == [s[i] for i in eachindex(s)] # bulk vs per-element agreement (value-equal
        # despite differing concrete eltypes -- getindex's single-row path isn't widened)
        @test s[1] isa Vector{Int64}
    end

    @testset "List: per-element fallback for nested/struct/categorical children" begin
        # Deliberately out of the bulk-read scope (see _read_list's docstring) -- these still
        # fall back to the per-element path, and must still produce correct results there.
        df_nested = DataFrame((; x = [[[1, 2], [3]], [[4, 5, 6]]]))
        s_nested = df_nested[:x]
        @test Polars.read_series(s_nested) === nothing
        bulk_nested = collect(s_nested)
        @test bulk_nested == [[[1, 2], [3]], [[4, 5, 6]]]

        df_struct_list = DataFrame((; x = [[(a = 1, b = "x"), (a = 2, b = "y")], [(a = 3, b = "z")]]))
        s_struct_list = df_struct_list[:x]
        @test Polars.read_series(s_struct_list) === nothing
        bulk_struct_list = collect(s_struct_list)
        @test length(bulk_struct_list) == 2
        @test bulk_struct_list[1][1].a == 1
        @test bulk_struct_list[2][1].b == "z"
    end
end

@testset "Series getindex out-of-bounds (regression: FFI panic in polars_series_get)" begin
    # `polars_series_get` backs the Date/DateTime/Duration/String/List/Struct getindex methods
    # (unlike the numeric/bool methods, which go through the already-fallible `gen_series_get!`
    # family) -- an out-of-bounds index here used to `.unwrap()` a Rust panic straight across the
    # FFI boundary, crashing the whole Julia process instead of raising a catchable error.
    s_str = Series(:names, ["a", "b"])
    @test_throws PolarsError s_str[5]
    @test s_str[1] == "a" # in-bounds access still correct after the fix

    s_date = Series(:dates, [Date(2024, 1, 1)])
    @test_throws PolarsError s_date[5]
    @test s_date[1] == Date(2024, 1, 1)

    s_dt = Series(:dts, [DateTime(2024, 1, 1)])
    @test_throws PolarsError s_dt[5]
    @test s_dt[1] == DateTime(2024, 1, 1)

    df_list = DataFrame((; x = [1, 2, 3]))
    s_list = select(df_list, implode(col("x")) |> alias("l"))[:l]
    @test_throws PolarsError s_list[5]
    @test s_list[1] isa Vector

    df_struct = DataFrame((; a = [1], b = ["x"]))
    s_struct = select(df_struct, as_struct(col("a"), col("b")) |> alias("s"))[:s]
    @test_throws PolarsError s_struct[5]
    @test s_struct[1].a == 1
end

@testset "Series getindex out-of-bounds on the numeric/bool path" begin
    # gen_series_get!-backed getters (numeric/bool) are a separate code path from
    # polars_series_get (Date/String/List/Struct, covered above) -- confirm they're
    # independently fallible on out-of-bounds too, not just in-bounds-correct.
    s_num = Series(:nums, [1, 2, 3])
    @test_throws PolarsError s_num[5]
    @test s_num[1] == 1

    s_bool = Series(:flags, [true, false])
    @test_throws PolarsError s_bool[5]
    @test s_bool[1] == true
end

@testset "Series getindex with negative/zero index" begin
    # No negative-index support (no wraparound-from-end semantics) -- these are simply
    # invalid indices and error, across both getindex code paths.
    s_num = Series(:nums, [1, 2, 3])
    @test_throws Exception s_num[-1]
    @test_throws Exception s_num[0]

    s_str = Series(:names, ["a", "b"])
    @test_throws Exception s_str[-1]
    @test_throws Exception s_str[0]
end

@testset "Series slicing" begin
    # Zero-copy row-range slicing via UnitRange getindex, backed by polars_series_slice.
    s = Series(:nums, [1, 2, 3, 4, 5])
    @test collect(s[1:2]) == [1, 2]
    @test collect(s[2:4]) == [2, 3, 4]

    # full range
    @test collect(s[1:5]) == [1, 2, 3, 4, 5]

    # empty range
    @test collect(s[3:2]) == Int64[]

    # range at the end
    @test collect(s[4:5]) == [4, 5]

    # out-of-bounds range raises
    @test_throws BoundsError s[4:10]

    # non-numeric element types slice correctly too
    s_str = Series(:names, ["a", "b", "c", "d"])
    @test collect(s_str[2:3]) == ["b", "c"]

    # null propagation through a slice
    s_null = Series(:vals, Union{Int64, Missing}[1, missing, 3, missing, 5])
    sub = s_null[2:4]
    @test isequal(collect(sub), [missing, 3, missing])
    @test sub.null_count == 2

    # scalar indexing is unaffected by the new UnitRange method
    @test s[1] == 1
    @test_throws PolarsError s[100]
end

@testset "Boolean Series all/any with nulls" begin
    # No dedicated Polars all/any override exists for Series -- Series{T} <: AbstractVector{T},
    # so Julia's generic all/any fallback (iteration-based) already implements correct
    # three-valued (Kleene) logic for free. Pure test-coverage gap, not a source gap.
    s_allmissing_true = Series(:flags, Union{Bool, Missing}[true, missing, true])
    @test ismissing(all(s_allmissing_true))  # can't rule out the missing being false
    @test any(s_allmissing_true) == true      # short-circuits on a definite true

    s_hasfalse = Series(:flags, Union{Bool, Missing}[false, missing])
    @test all(s_hasfalse) == false            # short-circuits on a definite false
    @test ismissing(any(s_hasfalse))          # can't rule out the missing being true

    s_empty = Series(:flags, Bool[])
    @test all(s_empty) == true
    @test any(s_empty) == false
end
