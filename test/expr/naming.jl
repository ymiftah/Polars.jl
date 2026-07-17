@testset "alias/prefix/suffix" begin
    df = DataFrame((; x = [1, 2, 3]))

    r_alias = select(df, col("x") |> alias("renamed"))
    @test Tables.columnnames(r_alias) == (:renamed,)
    @test r_alias[:renamed] == [1, 2, 3]

    r_prefix = select(df, col("x") |> prefix("pre_"))
    @test Tables.columnnames(r_prefix) == (:pre_x,)

    r_suffix = select(df, col("x") |> suffix("_suf"))
    @test Tables.columnnames(r_suffix) == (:x_suf,)

    # curried forms compose the same way through |>
    r_curried = select(df, col("x") |> alias("renamed") |> prefix("pre_"))
    @test Tables.columnnames(r_curried) == (:pre_renamed,)
end
