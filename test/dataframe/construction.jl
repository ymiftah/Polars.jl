@testset "Create from C Data interface" begin
    table = (; x = randn(Float32, 100))

    df = DataFrame(table)
    s = only(select(df, col("x") |> sum)[:x])

    @test s ≈ sum(table.x)

    df = nothing
end

@testset "Base.show(io, ::MIME\"text/plain\", df::DataFrame) -- full PrettyTables render" begin
    # Small non-empty DataFrame containing column names
    df_small = DataFrame((; a = [1, 2, 3], b = ["x", "y", "z"]))
    show_str = repr("text/plain", df_small)
    @test !isempty(show_str)
    @test contains(show_str, "a")
    @test contains(show_str, "b")

    # Empty DataFrame (0 rows)
    df_empty = DataFrame((; a = Int64[], b = String[]))
    show_str_empty = repr("text/plain", df_empty)
    @test !isempty(show_str_empty)
    @test contains(show_str_empty, "a")
    @test contains(show_str_empty, "b")

    # Wide DataFrame (>10 columns) to test truncation/layout handling
    cols = (; [Symbol("col$i") => collect(1:5) for i in 1:12]...)
    df_wide = DataFrame(cols)
    show_str_wide = repr("text/plain", df_wide)
    @test !isempty(show_str_wide)
    # Check that at least some column names appear
    @test contains(show_str_wide, "col1") || contains(show_str_wide, "col")
end

@testset "Base.show(io, df::DataFrame) -- compact 2-arg form (P2.5)" begin
    # The plain 2-arg `show` (used by `println`/`string`/`sprint(show, df)`, and by a
    # `DataFrame` nested inside another container's own display, e.g. `[df, df]`) is compact and
    # doesn't grow with row/column count -- the full PrettyTables render lives on the
    # `MIME"text/plain"` method above instead (tested there), reached by the REPL's own top-level
    # display and by `repr("text/plain", df)`/`show(io, MIME("text/plain"), df)` explicitly.
    df = DataFrame((; a = [1, 2, 3], b = ["x", "y", "z"]))
    @test sprint(show, df) == "3×2 DataFrame"
    @test sprint(print, df) == "3×2 DataFrame"

    # nesting inside another container's display must not explode into a full table per element
    nested = sprint(show, [df, df])
    @test !contains(nested, "─") # PrettyTables' horizontal rule character never appears
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

@testset "Base.names/Tables.columnnames read only the schema, no query (P1.3)" begin
    # `Tables.columnnames`/`Tables.getcolumn(df, ::Int)` used to call `schema(df)`, which runs a
    # null-count `select` over every column just to answer "what are the names" -- cheap on tiny
    # test frames, but a real cost on a wide/long one. `Base.names`/`Tables.columnnames` now read
    # only the Arrow schema.
    df = DataFrame((; a = [1, 2, 3], b = ["x", "y", "z"], c = [1.5, missing, 3.5]))
    @test Polars.names(df) == ["a", "b", "c"]
    @test Tables.columnnames(df) == (:a, :b, :c)
    @test Tables.getcolumn(df, 2) == ["x", "y", "z"]
    @test Tables.getcolumn(df, 1) == [1, 2, 3]

    # `Tables.schema` must still report the null-count-refined types (the thing `Base.names`
    # deliberately skips computing)
    sch = Tables.schema(df)
    @test sch.names == (:a, :b, :c)
    @test sch.types == (Int64, String, Union{Missing, Float64})
end
