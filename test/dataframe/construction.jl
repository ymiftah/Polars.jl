@testset "Create from C Data interface" begin
    table = (; x = randn(Float32, 100))

    df = DataFrame(table)
    s = only(select(df, col("x") |> sum)[:x])

    @test s ≈ sum(table.x)

    df = nothing
end

@testset "Base.show(io, df::DataFrame)" begin
    # Small non-empty DataFrame containing column names
    df_small = DataFrame((; a = [1, 2, 3], b = ["x", "y", "z"]))
    show_str = sprint(show, df_small)
    @test !isempty(show_str)
    @test contains(show_str, "a")
    @test contains(show_str, "b")

    # Empty DataFrame (0 rows)
    df_empty = DataFrame((; a = Int64[], b = String[]))
    show_str_empty = sprint(show, df_empty)
    @test !isempty(show_str_empty)
    @test contains(show_str_empty, "a")
    @test contains(show_str_empty, "b")

    # Wide DataFrame (>10 columns) to test truncation/layout handling
    cols = (; [Symbol("col$i") => collect(1:5) for i in 1:12]...)
    df_wide = DataFrame(cols)
    show_str_wide = sprint(show, df_wide)
    @test !isempty(show_str_wide)
    # Check that at least some column names appear
    @test contains(show_str_wide, "col1") || contains(show_str_wide, "col")
end
