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

@testset "construction from various shapes" begin
    # multi-typed NamedTuple-of-vectors (the standard Tables.jl column-oriented shape)
    df = DataFrame((; i = [1, 2, 3], f = [1.5, 2.5, 3.5], s = ["a", "b", "c"], b = [true, false, true], d = [Date(2024, 1, 1), Date(2024, 1, 2), Date(2024, 1, 3)]))
    @test size(df) == (3, 5)
    @test collect(df[:i]) == [1, 2, 3]
    @test collect(df[:f]) == [1.5, 2.5, 3.5]
    @test collect(df[:s]) == ["a", "b", "c"]
    @test collect(df[:b]) == [true, false, true]
    @test collect(df[:d]) == [Date(2024, 1, 1), Date(2024, 1, 2), Date(2024, 1, 3)]

    # row-oriented Tables.jl input: Vector{<:NamedTuple}
    rows = [(; a = 1, b = "x"), (; a = 2, b = "y"), (; a = 3, b = "z")]
    df_rows = DataFrame(rows)
    @test size(df_rows) == (3, 2)
    @test collect(df_rows[:a]) == [1, 2, 3]
    @test collect(df_rows[:b]) == ["x", "y", "z"]
end

@testset "mixed-type column coercion" begin
    # Int/Float64 mix in a single column literal promotes to Float64 (plain Julia array
    # promotion, not a Polars-specific coercion path)
    df = DataFrame((; x = [1, 2.5, 3]))
    @test eltype(collect(df[:x])) == Float64
    @test collect(df[:x]) == [1.0, 2.5, 3.0]

    # missing mixed into a column literal promotes to Union{T,Missing}
    df_null = DataFrame((; x = [1, missing, 3]))
    @test isequal(collect(df_null[:x]), [1, missing, 3])
    @test Polars.schema(df_null).types == (Union{Missing, Int64},)
end
