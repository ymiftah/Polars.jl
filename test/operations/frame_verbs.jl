@testset "unique" begin
    df = DataFrame((; g = ["a", "a", "b", "b"], x = [1, 2, 3, 4]))

    r_first = Base.unique(df, ["g"]; keep = :first)
    @test size(r_first) == (2, 2)
    @test Set(r_first[:g]) == Set(["a", "b"])

    r_last = Base.unique(df, ["g"]; keep = :last)
    @test size(r_last) == (2, 2)

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
end

@testset "rename" begin
    df = DataFrame((; a = [1, 2], b = [3, 4], c = [5, 6]))

    r = Base.rename(df, ["a", "c"], ["A", "C"])
    @test Tables.columnnames(r) == (:A, :b, :C)
    @test r[:A] == [1, 2]
    @test r[:C] == [5, 6]

    @test_throws ErrorException Base.rename(df, ["a"], ["A", "B"])
end

@testset "drop_nulls (frame-level)" begin
    df = DataFrame((; a = [1, missing, 3], b = [missing, 2, 3]))

    r_all = drop_nulls(df)
    @test size(r_all) == (1, 2) # only row 3 has no nulls at all

    r_subset = drop_nulls(df, ["a"])
    @test size(r_subset) == (2, 2) # drops only the row where `a` is null
end

@testset "tail" begin
    df = DataFrame((; x = collect(1:10)))

    r = Base.tail(df, 3)
    @test r[:x] == [8, 9, 10]

    r_default = Base.tail(df)
    @test size(r_default) == (5, 1) # default n=5, matching head's default
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
