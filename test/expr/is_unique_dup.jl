@testset "is_duplicated / is_unique" begin
    df = DataFrame((; x = [1, 2, 2, 3, 3, 3]))

    r = select(df, alias(is_duplicated(col("x")), "dup"), alias(is_unique(col("x")), "uniq"))
    @test r[:dup] == [false, true, true, true, true, true]
    @test r[:uniq] == [true, false, false, false, false, false]

    # inspecting duplicates before deciding how to handle them (complements frame-level unique)
    dup_rows = filter(df, is_duplicated(col("x")))
    @test dup_rows[:x] == [2, 2, 3, 3, 3]
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
