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

    # py-polars test_drop: "*" wildcard-drops every column (shape (3, 0)). Confirmed divergence,
    # live-verified: our `drop` calls the Rust `Selector::ByName` primitive directly with the
    # literal string "*", which has no glob meaning there (unlike `col("*")`'s expression-level
    # wildcard) -- it looks for an actual column named "*" and raises `ColumnNotFoundError`-
    # equivalent instead. See plans/parity/api_gap_audit.md Group 1.
    @test_broken size(drop(df, ["*"])) == (3, 0)
end

@testset "drop_nulls: empty explicit subset does NOT no-op here (py-polars test_drop_nulls_empty_subset diverges)" begin
    # Upstream distinguishes subset=None (check all columns, the default) from subset=[]
    # (explicitly check zero columns -> nothing can be null -> unchanged). Our FFI layer collapses
    # both onto the same `None` (see `c-polars/src/ffi_util.rs::selector_by_name_opt`'s doc
    # comment), so an explicitly-empty `String[]` here means "check all columns", the same as
    # omitting the argument -- not upstream's no-op. Confirmed live: both give the same (smaller)
    # result on a frame where every row has a null somewhere.
    df = DataFrame((; a = [1, missing], b = [missing, 2]))
    r_explicit_empty = drop_nulls(df, String[])
    r_default = drop_nulls(df)
    @test size(r_explicit_empty) == size(r_default) == (0, 2)
    @test_broken size(drop_nulls(df, String[])) == (2, 2)  # upstream: explicit [] is a no-op
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

    # simultaneous swap (a<->b): both renames apply against the ORIGINAL names, not sequentially
    # -- a naive sequential rename would either collide or silently lose a column
    # (py-polars test_rename_swap)
    df_swap = DataFrame((; a = [1, 2, 3, 4, 5], b = [5, 4, 3, 2, 1]))
    r_swap = Base.rename(df_swap, ["a", "b"], ["b", "a"])
    @test Tables.columnnames(r_swap) == (:b, :a)
    @test r_swap[:a] == [5, 4, 3, 2, 1]
    @test r_swap[:b] == [1, 2, 3, 4, 5]

    # identity rename(s) -- renaming a column to its own current name is a no-op, not an error,
    # including when every column is renamed to itself at once (py-polars test_rename_same_name)
    df_id = DataFrame((; nrs = [1, 2, 3], groups = ["A", "B", "C"]))
    r_id_one = Base.rename(df_id, ["groups"], ["groups"])
    @test Tables.columnnames(r_id_one) == (:nrs, :groups)
    r_id_all = Base.rename(df_id, ["nrs", "groups"], ["nrs", "groups"])
    @test Tables.columnnames(r_id_all) == (:nrs, :groups)
    @test r_id_all[:groups] == df_id[:groups]
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

    # `Date` (not just `DateTime`) works too (py-polars test_upsample_date)
    df_date = DataFrame((; date = [Date(2025, 1, 1), Date(2026, 1, 1)]))
    r_date = upsample(df_date, "date"; every = "3mo")
    @test collect(r_date[:date]) ==
        [Date(2025, 1, 1), Date(2025, 4, 1), Date(2025, 7, 1), Date(2025, 10, 1), Date(2026, 1, 1)]

    # a calendar duration ("1h") against a plain integer time column is a Step-5 abort-safety
    # check: upstream needs its own index-duration syntax ("2i") there, and raises cleanly rather
    # than misinterpreting the unit (py-polars test_upsample_index_invalid)
    df_int = DataFrame((; index = Int64[1, 2, 4, 5, 7]))
    @test_throws PolarsError upsample(df_int, "index"; every = "1h")

    # `by` naming the same column as `time_column` is a legal (if unusual) degenerate case: every
    # group has exactly one row, so nothing is inserted (py-polars test_upsample_with_group_by_15530)
    df_grp = DataFrame(
        (;
            time = [
                DateTime(2025, 1, 1, 9, 0), DateTime(2025, 1, 1, 9, 0),
                DateTime(2025, 1, 1, 9, 2), DateTime(2025, 1, 1, 9, 2),
            ],
            symbol = ["AAPL", "MSFT", "AAPL", "MSFT"],
        )
    )
    r_self_group = upsample(df_grp, "time"; by = ["time"], every = "1d")
    @test size(r_self_group) == size(df_grp)

    # duplicate `by` names -- clean PolarsError (py-polars raises DuplicateError), not a crash
    @test_throws PolarsError upsample(df_grp, "time"; by = ["time", "time"], every = "1d")

    # an empty (0-row) frame has no time values to infer upsample boundaries from -- clean
    # PolarsError, not a crash (py-polars test_upsample_empty_dataframe_with_group_by_26342)
    df_empty = DataFrame((; time = DateTime[], my_group = Int32[]))
    @test_throws PolarsError upsample(df_empty, "time"; by = ["my_group"], every = "15m")
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

@testset "frame-level aggregations (sum/mean/min/max/median/std/var/quantile/prod)" begin
    df = DataFrame((; a = [1, 2, 3, 4], b = [4.0, 5.0, 6.0, 7.0]))

    r_sum = Base.sum(df)
    @test names(r_sum) == ["a", "b"]
    @test size(r_sum) == (1, 2)
    @test collect(r_sum[:a]) == [10]
    @test collect(r_sum[:b]) == [22.0]

    @test collect(mean(df)[:a]) == [2.5]
    @test collect(Base.min(df)[:a]) == [1]
    @test collect(Base.max(df)[:a]) == [4]
    @test collect(median(df)[:a]) == [2.5]
    @test collect(std(df)[:a]) ≈ [1.2909944487358056]
    @test collect(var(df)[:a]) ≈ [1.6666666666666667]
    @test collect(std(df; ddof = 0)[:a]) ≈ [std(collect(df[:a]); corrected = false)]
    @test collect(quantile(df, 0.5)[:a]) == [3.0]

    # LazyFrame form agrees, for every one of the above
    @test isequal(collect((Base.sum(lazy(df)) |> collect)[:a]), collect(r_sum[:a]))
    @test isequal(collect((mean(lazy(df)) |> collect)[:a]), collect(mean(df)[:a]))
    @test isequal(collect((quantile(lazy(df), 0.5) |> collect)[:a]), collect(quantile(df, 0.5)[:a]))

    # non-numeric (String) column: `missing` in the result rather than a whole-frame `PolarsError`
    # -- these delegate to upstream's own null-tolerant `LazyFrame::sum`/etc, not a naive
    # `select(df, sum(col("*")))` composition (verified live: the latter does raise)
    df_str = DataFrame((; a = [1, 2, 3], s = ["x", "y", "z"]))
    @test isequal(collect(Base.sum(df_str)[:s]), [missing])
    @test isequal(collect(mean(df_str)[:s]), [missing])
    @test isequal(collect(median(df_str)[:s]), [missing])

    # a `Bool` column sums to a `UInt32` count of `true`s, matching upstream (including on an
    # empty column, per py-polars' own `test_sum_empty_column_names`)
    df_bool_empty = DataFrame((; x = Bool[], y = Bool[]))
    r_bool = Base.sum(df_bool_empty)
    @test collect(r_bool[:x]) == [0]
    @test collect(r_bool[:y]) == [0]
    @test eltype(collect(r_bool[:x])) == UInt32

    # nulls are skipped within a column (matching the per-`Expr` aggregation), but an all-null
    # column has nothing to aggregate and stays `missing`
    df_null = DataFrame((; a = [1, missing, 3], allnull = [missing, missing, missing]))
    @test collect(Base.sum(df_null)[:a]) == [4]
    @test isequal(collect(Base.sum(df_null)[:allnull]), [missing])

    # `prod`: unlike the others, upstream has no `LazyFrame::product` at all -- py-polars'
    # `DataFrame.product()` is pure-Python, branching per column dtype (numeric or `Bool` computes
    # a product, anything else becomes `null`), which is what this composes instead. Matches
    # py-polars' own `test_product` fixture exactly (int/float/two bool columns, one string).
    df_prod = DataFrame(
        (;
            int = [1, 2, 3], flt = [-1.0, 12.0, 9.0],
            bool_0 = [true, false, true], bool_1 = [true, true, true], str = ["a", "b", "c"],
        )
    )
    r_prod = Base.prod(df_prod)
    @test names(r_prod) == ["int", "flt", "bool_0", "bool_1", "str"]
    @test collect(r_prod[:int]) == [6]
    @test collect(r_prod[:flt]) == [-108.0]
    @test collect(r_prod[:bool_0]) == [0]
    @test collect(r_prod[:bool_1]) == [1]
    @test isequal(collect(r_prod[:str]), [missing])

    # LazyFrame form agrees
    r_prod_lazy = Base.prod(lazy(df_prod)) |> collect
    @test collect(r_prod_lazy[:int]) == [6]
    @test isequal(collect(r_prod_lazy[:str]), [missing])
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

    # a `Null`-dtype column (an all-`missing` column built with no other type hint) is compatible
    # with any concrete dtype in one direction only: it can be appended onto a typed column
    # (upcasting), but a typed column cannot be appended onto a `Null` one -- asymmetric on
    # purpose (py-polars test_vstack_with_null_column)
    typed = DataFrame((; x = [3.5]))
    null_col = DataFrame((; x = [missing]))
    r_null = vstack(typed, null_col)
    @test isequal(collect(r_null[:x]), [3.5, missing])
    @test_throws PolarsError vstack(null_col, typed)
end

@testset "limit/reverse/null_count/count/fill_nan/explain/cache (frame-level)" begin
    df = DataFrame((; a = [1.0, NaN, 3.0, missing], b = [10, 20, 30, 40]))

    # limit is a plain alias for head
    r_limit = limit(df, 2)
    @test size(r_limit) == (2, 2)
    @test collect(r_limit[:b]) == [10, 20]
    @test isequal(collect(limit(df, 2)[:a]), collect(head(df, 2)[:a]))

    # limit(df, n) with n > row count returns everything, same as head
    r_limit_over = limit(df, 100)
    @test size(r_limit_over) == (4, 2)

    # LazyFrame form agrees
    r_limit_lazy = limit(lazy(df), 2) |> collect
    @test size(r_limit_lazy) == (2, 2)

    # upstream test_limit (py-polars lazyframe/test_lazyframe.py): limit(1) on a LazyFrame
    # equals the first row of the collected frame, fixture from the `fruits_cars` conftest fixture
    fruits_cars = DataFrame(
        (;
            A = [1, 2, 3, 4, 5],
            fruits = ["banana", "banana", "apple", "apple", "banana"],
            B = [5, 4, 3, 2, 1],
            cars = ["beetle", "audi", "beetle", "beetle", "beetle"],
        )
    )
    r_limit_fc = limit(lazy(fruits_cars), 1) |> collect
    @test collect(r_limit_fc[:A]) == [1]
    @test collect(r_limit_fc[:fruits]) == ["banana"]
    @test collect(r_limit_fc[:cars]) == ["beetle"]

    # reverse: row order flips; round-trips back to the original
    r_rev = Base.reverse(df)
    @test collect(r_rev[:b]) == [40, 30, 20, 10]
    @test isequal(Base.reverse(Base.reverse(df)), df)

    r_rev_lazy = Base.reverse(lazy(df)) |> collect
    @test collect(r_rev_lazy[:b]) == [40, 30, 20, 10]

    # upstream test_reverse_df (py-polars operations/test_reverse.py)
    r_rev_upstream = Base.reverse(lazy(DataFrame((; a = [1, 2], b = [3, 4])))) |> collect
    @test collect(r_rev_upstream[:a]) == [2, 1]
    @test collect(r_rev_upstream[:b]) == [4, 3]

    # reverse preserves schema on a 0-row frame (upstream test_reverse_list_22829, minus the
    # List(Binary) dtype which is out of scope for this sweep -- schema preservation on a plain
    # numeric 0-row frame is the part that's portable)
    r_rev_empty = Base.reverse(DataFrame((; x = Int[], y = Int[])))
    @test size(r_rev_empty) == (0, 2)

    # null_count and count disagree on a column with a `missing`: null_count counts nulls,
    # count counts non-nulls -- the whole point of having both. Live-verified: `a` has one
    # `missing` (NaN is not null), `b` has none.
    r_nc = null_count(df)
    @test collect(r_nc[:a]) == [1]
    @test collect(r_nc[:b]) == [0]

    r_cnt = count(df)
    @test collect(r_cnt[:a]) == [3]
    @test collect(r_cnt[:b]) == [4]

    # LazyFrame forms agree
    r_nc_lazy = null_count(lazy(df)) |> collect
    @test collect(r_nc_lazy[:a]) == [1]
    r_cnt_lazy = count(lazy(df)) |> collect
    @test collect(r_cnt_lazy[:a]) == [3]

    # a fully-null column counts to 0 (not the row count), confirming `count` really is
    # non-null-count, not row-count
    df_allnull = DataFrame((; a = [missing, missing, missing], b = [1, 2, 3]))
    @test collect(count(df_allnull)[:a]) == [0]
    @test collect(count(df_allnull)[:b]) == [3]
    @test collect(null_count(df_allnull)[:a]) == [3]

    # upstream test_null_count (py-polars lazyframe/test_lazyframe.py): a=[1,2,None,2] (1 null),
    # b=[None,3,None,3] (2 nulls)
    lf_nc = lazy(DataFrame((; a = [1, 2, missing, 2], b = [missing, 3, missing, 3])))
    r_nc_upstream = null_count(lf_nc) |> collect
    @test collect(r_nc_upstream[:a]) == [1]
    @test collect(r_nc_upstream[:b]) == [2]

    # upstream test_count (py-polars operations/test_statistics.py): non-null counts per column,
    # cast to the index dtype (UInt32 here); verifies dtype, not just value
    df_count = DataFrame(
        (;
            nulls = [missing, missing, missing],
            one_null_str = ["one", missing, "three"],
            one_null_float = [1.0, 2.0, missing],
            no_nulls_int = [1, 2, 3],
        )
    )
    r_count_upstream = count(df_count)
    @test collect(r_count_upstream[:nulls]) == [0]
    @test collect(r_count_upstream[:one_null_str]) == [2]
    @test collect(r_count_upstream[:one_null_float]) == [2]
    @test collect(r_count_upstream[:no_nulls_int]) == [3]
    @test eltype(collect(r_count_upstream[:nulls])) == UInt32

    # upstream's hypothesis test_null_count carries two explicit (non-generated) @example cases:
    # a schema-only 0-row frame (null_count.shape == (1, ncols)) and a fully empty 0x0 frame
    # (shape == (1, 0)). The 0-row/N-col case matches for both null_count and count; the 0x0 case
    # does not -- see the note below and plans/parity/tier12-sweep-frame-verbs.md.
    df_schema_only = DataFrame((; x = Int[], y = Int[], z = Int[]))
    @test size(null_count(df_schema_only)) == (1, 3)
    @test size(count(df_schema_only)) == (1, 3)

    # a genuinely 0-column DataFrame: upstream's own hypothesis @example asserts shape (1, 0) for
    # null_count on `pl.DataFrame()`. Our implementation is `collect ∘ null_count ∘ lazy`, and
    # LazyFrame::null_count()/count() on a 0-column input never emits a row to begin with, giving
    # (0, 0) instead -- upstream's eager `DataFrame.null_count()` goes through a *different* Rust
    # binding (`PyDataFrame.null_count`, not the lazy planner) that apparently special-cases this.
    # This is a Rust/FFI-path divergence, not a Julia-side marshalling bug (no Rust changes in
    # this task) -- @test_broken per the parity skill, recorded in the plan note.
    df_zero_cols = DataFrame(NamedTuple())
    @test size(df_zero_cols) == (0, 0)
    @test_broken size(null_count(df_zero_cols)) == (1, 0)
    @test size(null_count(df_zero_cols)) == (0, 0) # documents actual current behavior
    @test_broken size(count(df_zero_cols)) == (1, 0)
    @test size(count(df_zero_cols)) == (0, 0)

    # fill_nan replaces only NaN, leaves `missing` untouched -- distinct concepts
    r_fn = fill_nan(df, 0.0)
    @test isequal(collect(r_fn[:a]), [1.0, 0.0, 3.0, missing])
    @test collect(r_fn[:b]) == [10, 20, 30, 40] # untouched, no NaN/missing here

    r_fn_lazy = fill_nan(lazy(df), 0.0) |> collect
    @test isequal(collect(r_fn_lazy[:a]), [1.0, 0.0, 3.0, missing])

    # fill_nan accepts an Expr, not just a plain scalar
    r_fn_expr = fill_nan(df, lit(-1.0))
    @test isequal(collect(r_fn_expr[:a]), [1.0, -1.0, 3.0, missing])

    # upstream test_fill_nan (py-polars dataframe/test_df.py + lazyframe/test_lazyframe.py):
    # fill_nan(None) turns NaN into a genuine null, not a no-op -- distinct from the default-value
    # case above (verified live: `convert(Expr, missing)` already exists, see src/expr/expr.jl)
    df_fn = DataFrame((; a = [1.0, NaN, 3.0]))
    r_fn_none = fill_nan(df_fn, missing)
    @test isequal(collect(r_fn_none[:a]), [1.0, missing, 3.0])
    r_fn_none_lazy = fill_nan(lazy(df_fn), missing) |> collect
    @test isequal(collect(r_fn_none_lazy[:a]), [1.0, missing, 3.0])

    # fill_nan only touches float columns -- a Datetime column (and its dtype) passes through
    # unchanged even though the frame also has a NaN-bearing float column (upstream test_fill_nan,
    # dataframe/test_df.py: `df.fill_nan(2.0).dtypes == [pl.Float64, pl.Datetime]`)
    df_fn_dt = DataFrame(
        (; a = [1.0, NaN, 3.0], b = [DateTime(2001, 2, 2), DateTime(2002, 2, 2), DateTime(2003, 2, 2)])
    )
    r_fn_dt = fill_nan(df_fn_dt, 2.0)
    @test isequal(collect(r_fn_dt[:a]), [1.0, 2.0, 3.0])
    @test collect(r_fn_dt[:b]) == [DateTime(2001, 2, 2), DateTime(2002, 2, 2), DateTime(2003, 2, 2)]

    # explain: optimized plan contains the DF scan node
    plan = explain(lazy(df))
    @test occursin("DF [\"a\", \"b\"]", plan)

    # explain(optimized=false) differs from the optimized plan once there's something for the
    # optimizer to do (projection pushdown trims the unused column here)
    df3 = DataFrame((; a = [1, 2, 3, 4], b = [10, 20, 30, 40], c = [100, 200, 300, 400]))
    lf3 = select(filter(lazy(df3), col("a") > 1), col("a"))
    @test explain(lf3; optimized = true) != explain(lf3; optimized = false)
    @test occursin("PROJECT[\"a\"]", explain(lf3; optimized = true))
    @test occursin("SELECT", explain(lf3; optimized = false))

    # upstream test_describe_plan (py-polars lazyframe/test_lazyframe.py): explain returns a
    # String for both optimized values
    @test explain(lazy(DataFrame((; a = [1]))); optimized = true) isa String
    @test explain(lazy(DataFrame((; a = [1]))); optimized = false) isa String

    # cache is result-preserving: collecting a cached plan agrees with collecting the plain one
    r_cache = collect(cache(lazy(df)))
    @test isequal(collect(r_cache[:a]), collect(df[:a]))
    @test collect(r_cache[:b]) == collect(df[:b])

    # upstream test_cache_hit_with_proj_and_pred_pushdown (py-polars lazyframe/test_lazyframe.py):
    # concatenating a cached LazyFrame with itself dedups to a single CACHE node id in the
    # optimized plan, and collecting still returns each branch's rows
    lf_cache = lazy(DataFrame((; a = [1, 2, 3], b = [3, 4, 5], c = ["x", "y", "z"])))
    cached = cache(lf_cache)
    q = select(Polars.concat(Polars.LazyFrame[cached, cached]), "a", "b")
    r_q = collect(q)
    @test collect(r_q[:a]) == [1, 2, 3, 1, 2, 3]
    q_plan = explain(q)
    cache_ids = [m.match for m in eachmatch(r"CACHE\[id: [^\]]+\]", q_plan)]
    @test length(cache_ids) == 2
    @test cache_ids[1] == cache_ids[2] # both branches share the same cache id
end
