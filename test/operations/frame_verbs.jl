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
    @test_throws ErrorException drop(df, ["nonexistent"])

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
    @test_throws ErrorException Base.rename(df, ["a", "b"], ["X", "X"])
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
    # Just verify it runs and produces correct values (row order may vary)
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
