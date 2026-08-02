@testset "is_duplicated / is_unique" begin
    df = DataFrame((; x = [1, 2, 2, 3, 3, 3]))

    r = select(df, alias(is_duplicated(col("x")), "dup"), alias(is_unique(col("x")), "uniq"))
    @test r[:dup] == [false, true, true, true, true, true]
    @test r[:uniq] == [true, false, false, false, false, false]

    # inspecting duplicates before deciding how to handle them (complements frame-level unique)
    dup_rows = filter(df, is_duplicated(col("x")))
    @test dup_rows[:x] == [2, 2, 3, 3, 3]
end

@testset "is_first_distinct / is_last_distinct (see plans/parity/gap_closure_scope.md)" begin
    df = DataFrame((; x = [1, 1, 2, 2, 3]))

    r = select(df, alias(is_first_distinct(col("x")), "first"), alias(is_last_distinct(col("x")), "last"))
    @test collect(r[:first]) == [true, false, true, false, true]
    @test collect(r[:last]) == [false, true, false, true, true]

    # a value with a single occurrence is both first and last
    df_single = DataFrame((; x = [1, 2, 1]))
    r_single = select(df_single, alias(is_first_distinct(col("x")), "first"), alias(is_last_distinct(col("x")), "last"))
    @test collect(r_single[:first]) == [true, true, false]
    @test collect(r_single[:last]) == [false, true, true]
end

@testset "is_unique / is_duplicated / n_unique on empty and all-null input (py-polars test_is_unique_null / test_is_duplicated_null / test_n_unique_null)" begin
    df_empty = DataFrame((; x = Union{Missing, Int}[]))
    @test isempty(collect(select(df_empty, alias(is_unique(col("x")), "u"))[:u]))
    @test isempty(collect(select(df_empty, alias(is_duplicated(col("x")), "d"))[:d]))
    @test only(select(df_empty, alias(n_unique(col("x")), "n"))[:n]) == 0

    df_one_null = DataFrame((; x = Union{Missing, Int}[missing]))
    @test collect(select(df_one_null, alias(is_unique(col("x")), "u"))[:u]) == [true]
    @test collect(select(df_one_null, alias(is_duplicated(col("x")), "d"))[:d]) == [false]
    @test only(select(df_one_null, alias(n_unique(col("x")), "n"))[:n]) == 1

    df_all_null = DataFrame((; x = Union{Missing, Int}[missing, missing, missing]))
    @test collect(select(df_all_null, alias(is_unique(col("x")), "u"))[:u]) == [false, false, false]
    @test collect(select(df_all_null, alias(is_duplicated(col("x")), "d"))[:d]) == [true, true, true]
    @test only(select(df_all_null, alias(n_unique(col("x")), "n"))[:n]) == 1
end
