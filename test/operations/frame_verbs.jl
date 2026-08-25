@testset "get_column / Polars.item (API gap batch four, Phase 5)" begin
    df = DataFrame((; x = [1, 2, 3], y = ["a", "b", "c"]))

    # get_column matches plain getindex, same values and name
    gc = get_column(df, "x")
    @test collect(gc) == collect(df[:x])
    @test Polars.name(gc) == "x"
    @test collect(get_column(df, :y)) == collect(df[:y])

    # nonexistent column name -> clean PolarsError, not a panic, naming the missing column
    @test_throws PolarsError get_column(df, "nonexistent")
    try
        get_column(df, "nonexistent")
        @test false
    catch e
        @test e isa PolarsError
        @test occursin("nonexistent", e.message)
    end

    # `default` keyword (mirrors py-polars' `get_column(name, default=...)`, df_test.py:156-164):
    # a nonexistent column returns `default` instead of raising, including `default=nothing`
    # itself as a valid (non-raising) default -- distinct from the keyword being omitted entirely
    default_series = Series("x", ["?", "?", "?"])
    @test collect(get_column(df, "nonexistent"; default = default_series)) == ["?", "?", "?"]
    @test get_column(df, "nonexistent"; default = nothing) === nothing
    # a column that DOES exist ignores `default` and returns the real column
    @test collect(get_column(df, "x"; default = default_series)) == collect(df[:x])

    # Polars.item(series) on length-1/length-0/length-N
    @test Polars.item(Series("s", [42])) == 42
    @test_throws ErrorException Polars.item(Series("s", Int[]))
    @test_throws ErrorException Polars.item(Series("s", [1, 2]))

    # Polars.item(df) on a genuine 1x1 frame
    @test Polars.item(DataFrame((; x = [7]))) == 7

    # Polars.item(df) on 1xN / Nx1 / NxM frames should all error (strict (1,1)-only semantics)
    @test_throws ErrorException Polars.item(DataFrame((; x = [1], y = [2]))) # 1x2
    @test_throws ErrorException Polars.item(DataFrame((; x = [1, 2]))) # 2x1
    @test_throws ErrorException Polars.item(df) # 3x2

    # Polars.item(df, row, col) with both col forms (name and integer index)
    @test Polars.item(df, 2, "x") == 2
    @test Polars.item(df, 2, :x) == 2
    @test Polars.item(df, 2, 1) == 2
    @test Polars.item(df, 3, "y") == "c"
end

@testset "unique" begin
    df = DataFrame((; g = ["a", "a", "b", "b"], x = [1, 2, 3, 4]))

    r_first = Base.unique(df, ["g"]; keep = :first)
    @test size(r_first) == (2, 2)
    @test Set(r_first[:g]) == Set(["a", "b"])

    r_last = Base.unique(df, ["g"]; keep = :last)
    @test size(r_last) == (2, 2)

    # keep=:none drops ALL rows sharing a duplicate key (not just extras)
    r_none = Base.unique(df, ["g"]; keep = :none)
    @test size(r_none) == (0, 2)  # all rows are duplicates, so all are dropped

    # no subset -> unique across all columns
    df2 = DataFrame((; x = [1, 1, 2], y = [1, 1, 2]))
    r_all = Base.unique(df2)
    @test size(r_all) == (2, 2)

    @test_throws ErrorException Base.unique(df, ["g"]; keep = :bogus)

    # LazyFrame entry point agrees
    r_lazy = Base.unique(lazy(df), ["g"]; keep = :first) |> collect
    @test size(r_lazy) == size(r_first)
end

@testset "drop" begin
    df = DataFrame((; a = [1, 2], b = [3, 4], c = [5, 6]))

    r = drop(df, ["b"])
    @test Tables.columnnames(r) == (:a, :c)
    @test r[:a] == [1, 2]
    @test r[:c] == [5, 6]

    r2 = drop(df, ["a", "c"])
    @test Tables.columnnames(r2) == (:b,)

    # drop non-existent column should error
    @test_throws PolarsError drop(df, ["nonexistent"])

    # drop all columns results in a fully empty DataFrame (0 rows, 0 cols) -- with no columns
    # to carry a row count, there's nothing to preserve it against (matches select() with zero
    # expressions, see test/operations/select_with_columns.jl)
    r_all = drop(df, ["a", "b", "c"])
    @test size(r_all) == (0, 0)
end

@testset "rename" begin
    df = DataFrame((; a = [1, 2], b = [3, 4], c = [5, 6]))

    r = Base.rename(df, ["a", "c"], ["A", "C"])
    @test Tables.columnnames(r) == (:A, :b, :C)
    @test r[:A] == [1, 2]
    @test r[:C] == [5, 6]

    @test_throws ErrorException Base.rename(df, ["a"], ["A", "B"])

    # strict=false: attempting to rename a column that doesn't exist should NOT error
    r_lenient = Base.rename(df, ["a", "nonexistent"], ["A", "X"]; strict = false)
    @test Tables.columnnames(r_lenient) == (:A, :b, :c)  # only 'a' was renamed; 'nonexistent' was ignored
    @test r_lenient[:A] == [1, 2]

    # rename creating a name collision should error
    @test_throws PolarsError Base.rename(df, ["a", "b"], ["X", "X"])
end

@testset "drop_nulls (frame-level)" begin
    df = DataFrame((; a = [1, missing, 3], b = [missing, 2, 3]))

    r_all = drop_nulls(df)
    @test size(r_all) == (1, 2) # only row 3 has no nulls at all

    r_subset = drop_nulls(df, ["a"])
    @test size(r_subset) == (2, 2) # drops only the row where `a` is null

    # drop_nulls on subset: row with null in non-subset column is retained
    df2 = DataFrame((; a = [1, 2, 3], b = [missing, missing, 3], c = [10, 20, 30]))
    r_subset_b = drop_nulls(df2, ["b"])
    @test size(r_subset_b) == (1, 3)  # only row 3 has non-null b
    @test r_subset_b[:a] == [3]
    @test r_subset_b[:c] == [30]

    # drop_nulls on all columns vs on subset ["a", "b"] (c has no nulls)
    r_abc = drop_nulls(df2, ["a", "b", "c"])
    r_ab = drop_nulls(df2, ["a", "b"])
    @test size(r_abc) == (1, 3)  # rows 1 and 2 have nulls in b
    @test size(r_ab) == (1, 3)   # same result since we're only checking a and b
end

@testset "tail" begin
    df = DataFrame((; x = collect(1:10)))

    r = Base.tail(df, 3)
    @test r[:x] == [8, 9, 10]

    r_default = Base.tail(df)
    @test size(r_default) == (5, 1) # default n=5, matching head's default
end

@testset "upsample" begin
    df = DataFrame(
        (;
            time = [DateTime(2024, 1, 1, 0), DateTime(2024, 1, 1, 2), DateTime(2024, 1, 1, 3)],
            v = [1, 2, 3],
        )
    )

    r = upsample(df, "time"; every = "1h")
    @test r[:time] == DateTime(2024, 1, 1, 0) .+ Hour.(0:3)
    @test r[:v][1] == 1
    @test ismissing(r[:v][2])
    @test r[:v][3] == 2
    @test r[:v][4] == 3

    # grouped by an extra key
    df2 = DataFrame(
        (;
            g = ["a", "a", "b", "b"],
            time = [
                DateTime(2024, 1, 1, 0), DateTime(2024, 1, 1, 2),
                DateTime(2024, 1, 1, 0), DateTime(2024, 1, 1, 1),
            ],
            v = [10, 20, 30, 40],
        )
    )
    r2 = upsample(df2, "time"; by = ["g"], every = "1h")
    @test size(r2) == (5, 3) # a: 0,1,2 (3 rows) + b: 0,1 (2 rows)

    # stable=false: allow unstable ordering among upsampled rows
    r_unstable = upsample(df, "time"; every = "1h", stable = false)
    @test size(r_unstable) == (4, 2)
    @test r_unstable[:time] |> collect |> sort == r[:time] |> collect |> sort
end

@testset "with_row_index" begin
    df = DataFrame((; x = [10, 20, 30]))

    r = with_row_index(df)
    @test Tables.columnnames(r) == (:index, :x)
    @test r[:index] == UInt32[0, 1, 2]

    r_named = with_row_index(df, "idx"; offset = 10)
    @test Tables.columnnames(r_named) == (:idx, :x)
    @test r_named[:idx] == UInt32[10, 11, 12]
end

@testset "Symbol column identifiers (verbs.jl/reshape.jl)" begin
    # Every verb here accepts a `Symbol` wherever it accepts a column name. The verbs taking a
    # list of names route through `_name_ptrs`, which converts to `String` first; a single-name
    # verb like `with_row_index` has to do the same conversion itself before `ncodeunits`, which
    # has no `Symbol` method.
    df = DataFrame((; g = ["a", "a", "b", "b"], x = [1, 2, 3, 4]))

    r_idx = with_row_index(df, :idx)
    @test Tables.columnnames(r_idx) == (:idx, :g, :x)

    r_unique_vec = Base.unique(df, [:g]; keep = :first)
    @test size(r_unique_vec) == (2, 2)
    r_unique_vararg = Base.unique(df, :g; keep = :first)
    @test size(r_unique_vararg) == (2, 2)

    r_drop = drop(df, [:x])
    @test Tables.columnnames(r_drop) == (:g,)

    r_rename_vec = Base.rename(df, [:g], [:group])
    @test Tables.columnnames(r_rename_vec) == (:group, :x)
    r_rename_pair = Base.rename(df, :g => :group)
    @test Tables.columnnames(r_rename_pair) == (:group, :x)
    # mixed String/Symbol pair also works
    r_rename_mixed = Base.rename(df, "g" => :group)
    @test Tables.columnnames(r_rename_mixed) == (:group, :x)

    df_nulls = DataFrame((; a = [1, missing, 3], b = [1, 2, 3]))
    r_drop_nulls = drop_nulls(df_nulls, [:a])
    @test size(r_drop_nulls) == (2, 2)

    df_time = DataFrame((; time = [DateTime(2024, 1, 1, 0), DateTime(2024, 1, 1, 2)], v = [1, 2]))
    r_upsample = upsample(df_time, :time; every = "1h")
    @test size(r_upsample) == (3, 2)
end

@testset "hstack" begin
    df = DataFrame((; a = [1, 2, 3], b = [4, 5, 6]))

    # single Series attached
    c = Series("c", [7, 8, 9])
    r = hstack(df, [c])
    @test Tables.columnnames(r) == (:a, :b, :c)
    @test collect(r[:c]) == [7, 8, 9]

    # multiple Series attached at once, mixed dtypes
    d = Series("d", [10, 11, 12])
    e = Series("e", ["x", "y", "z"])
    r2 = hstack(df, Polars.Series[c, d, e])
    @test Tables.columnnames(r2) == (:a, :b, :c, :d, :e)
    @test collect(r2[:e]) == ["x", "y", "z"]

    # length mismatch -- clean PolarsError, not a crash (live-verified: this is a real
    # DataFrame::new validation path, see plans/definitive_guide_gap_closure.md)
    short = Series("short", [1, 2])
    @test_throws PolarsError hstack(df, [short])
    long = Series("long", [1, 2, 3, 4, 5])
    @test_throws PolarsError hstack(df, [long])

    # duplicate name between df and an attached Series -- errors, does not silently overwrite
    dup_existing = Series("a", [100, 200, 300])
    @test_throws PolarsError hstack(df, [dup_existing])

    # duplicate name between two attached Series
    x1 = Series("x", [1, 2, 3])
    x2 = Series("x", [4, 5, 6])
    @test_throws PolarsError hstack(df, Polars.Series[x1, x2])

    # attaching to an empty (0-row, non-zero-width) DataFrame: a matching (0-length) Series
    # attaches cleanly; a non-empty one is a length mismatch like any other height mismatch
    empty_df = filter(df, col("a") .> 999)
    @test size(empty_df) == (0, 2)
    r_empty = hstack(empty_df, [Series("c", Int[])])
    @test size(r_empty) == (0, 3)
    @test_throws PolarsError hstack(empty_df, [Series("c", [1, 2, 3])])

    # attaching to a truly empty (0 rows, 0 columns) DataFrame: still a height mismatch --
    # `hstack`'s height comes from `df`'s own stored height (0 here), it is not inferred from
    # the incoming Series (verified live)
    truly_empty = DataFrame(NamedTuple())
    @test size(truly_empty) == (0, 0)
    @test_throws PolarsError hstack(truly_empty, [Series("z", [1, 2, 3])])
end

@testset "fill_null (frame-level)" begin
    df = DataFrame((; a = [1, missing, 3], b = [missing, "y", "z"]))

    # `fill_value` is cast to each column's own dtype rather than requiring an exact match --
    # the Int literal `0` becomes the string `"0"` in `b` (verified live), same as upstream.
    r = fill_null(df, lit(0))
    @test collect(r[:a]) == [1, 0, 3]
    @test collect(r[:b]) == ["0", "y", "z"]

    # LazyFrame form agrees
    r_lazy = fill_null(lazy(df), lit(0)) |> collect
    @test isequal(collect(r_lazy[:a]), collect(r[:a]))
    @test isequal(collect(r_lazy[:b]), collect(r[:b]))

    # distinct from the `Expr`-level `fill_null`, which only touches the column it's called on
    r_expr = select(df, alias(fill_null(col("a"), lit(0)), "a"))
    @test collect(r_expr[:a]) == [1, 0, 3]
end

@testset "cast (frame-level)" begin
    df = DataFrame((; a = [1, 2, missing], b = ["x", "y", "z"]))

    # AbstractDict form: only the named column(s) change, everything else is untouched
    r = cast(df, Dict("a" => Float64))
    @test eltype(collect(r[:a])) == Union{Missing, Float64}
    @test isequal(collect(r[:a]), [1.0, 2.0, missing])
    @test collect(r[:b]) == ["x", "y", "z"]

    # strict=false (default): overflow becomes `missing` rather than raising
    df_overflow = DataFrame((; a = [300]))
    r_nonstrict = cast(df_overflow, Dict("a" => UInt8))
    @test ismissing(r_nonstrict[:a][1])
    # strict=true raises instead
    @test_throws PolarsError cast(df_overflow, Dict("a" => UInt8); strict = true)

    # single-`Type` form: every column is cast, including numeric ones together
    df_num = DataFrame((; a = [1, 2, 3], b = [4.0, 5.0, 6.0]))
    r_all = cast(df_num, Float32)
    @test eltype(collect(r_all[:a])) == Float32
    @test eltype(collect(r_all[:b])) == Float32

    # non-strict (default): a non-numeric String column casts to `missing` per row rather than
    # raising -- matches the single-`Expr` `cast`'s own non-strict convention
    r_str = cast(df, Float64)
    @test isequal(collect(r_str[:a]), [1.0, 2.0, missing])
    @test all(ismissing, collect(r_str[:b]))
    # strict=true does raise on that same non-numeric column
    @test_throws PolarsError cast(df, Float64; strict = true)

    # LazyFrame form agrees, for both call shapes
    r_lazy_dict = cast(lazy(df), Dict("a" => Float64)) |> collect
    @test isequal(collect(r_lazy_dict[:a]), collect(r[:a]))
    r_lazy_all = cast(lazy(df_num), Float32) |> collect
    @test eltype(collect(r_lazy_all[:a])) == Float32

    # a dtype the plain FFI type code can't carry (needs a time unit/zone) is a clean Julia-side
    # error, not a silent misconversion -- the scope cut documented on `Polars.cast`(df, dtype)
    @test_throws ErrorException cast(df_num, DateTime)
end

@testset "vstack" begin
    df1 = DataFrame((; a = [1, 2], b = [10, 20]))
    df2 = DataFrame((; a = [3, 4], b = [30, 40]))

    # matching schema
    r = vstack(df1, df2)
    @test size(r) == (4, 2)
    @test collect(r[:a]) == [1, 2, 3, 4]
    @test collect(r[:b]) == [10, 20, 30, 40]

    # 0-row other
    empty_other = filter(df2, col("a") .> 999)
    @test size(empty_other) == (0, 2)
    r_empty = vstack(df1, empty_other)
    @test size(r_empty) == (2, 2)
    @test collect(r_empty[:a]) == [1, 2]

    # schema mismatch: different column count -- clean PolarsError, not a crash (vstack does no
    # supertype casting, unlike concat's :vertical_relaxed mode -- verified live)
    df_narrow = DataFrame((; a = [1, 2]))
    @test_throws PolarsError vstack(df1, df_narrow)

    # schema mismatch: same column count, different column name
    df_renamed = DataFrame((; a = [1, 2], c = [10, 20]))
    @test_throws PolarsError vstack(df1, df_renamed)

    # schema mismatch: same names, incompatible dtype
    df_wrong_dtype = DataFrame((; a = ["x", "y"], b = [10, 20]))
    @test_throws PolarsError vstack(df1, df_wrong_dtype)
end
