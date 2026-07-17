@testset "is_duplicated / is_unique" begin
    df = DataFrame((; x = [1, 2, 2, 3, 3, 3]))

    r = select(df, alias(is_duplicated(col("x")), "dup"), alias(is_unique(col("x")), "uniq"))
    @test r[:dup] == [false, true, true, true, true, true]
    @test r[:uniq] == [true, false, false, false, false, false]

    # inspecting duplicates before deciding how to handle them (complements frame-level unique)
    dup_rows = filter(df, is_duplicated(col("x")))
    @test dup_rows[:x] == [2, 2, 3, 3, 3]
end
