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

@testset "DataFrame(series::AbstractVector{<:Series})" begin
    a = Series("a", [1, 2, 3])
    b = Series("b", ["x", "y", "z"])
    df = DataFrame([a, b])
    @test size(df) == (3, 2)
    @test Polars.names(df) == ["a", "b"]
    @test collect(df[:a]) == [1, 2, 3]
    @test collect(df[:b]) == ["x", "y", "z"]

    # the input series are cloned, not consumed -- both the DataFrame and the originals stay usable
    @test collect(a) == [1, 2, 3]

    # an empty-named series falls back to "column_i" (0-based)
    unnamed = Series("", [true, false])
    df_unnamed = DataFrame([unnamed])
    @test Polars.names(df_unnamed) == ["column_0"]

    # duplicate resulting names raise, same as any other DataFrame constructor
    @test_throws PolarsError DataFrame([Series("dup", [1]), Series("dup", [2])])
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

@testset "bare all-missing column (Vector{Missing}) builds a genuine Null-dtype column, not a crash (see plans/parity/gap_closure_scope.md A2)" begin
    # `DataFrame((; x = [missing, missing]))` used to raise `UndefVarError: T not defined in
    # static parameter matching` from deep inside Arrow-schema resolution -- Missing's own
    # `MaybeMissing{Missing}` == `Union{Missing,Missing}` collapse hit the same hazard already
    # guarded for `Any` (src/arrow/array.jl), but without an equivalent guard. Fixed with a
    # concrete `format(::Type{Missing})` method; live-verified end-to-end (not just that
    # construction no longer crashes) across schema, group_by, filter, and a parquet round-trip.
    df = DataFrame((; x = Vector{Missing}(missing, 2)))
    @test size(df) == (2, 1)
    @test isequal(collect(df[:x]), [missing, missing])
    @test Polars.schema(df).types == (Union{Missing, Nothing},)

    # bare untyped literal (the exact form from the original crash report) works the same way
    df_lit = DataFrame((; x = [missing, missing]))
    @test isequal(collect(df_lit[:x]), [missing, missing])

    # survives a group_by/agg and a filter, not just construction+readback
    df_g = DataFrame((; g = ["a", "a", "b"], x = Vector{Missing}(missing, 3)))
    r = collect(agg(group_by(lazy(df_g), "g"), count(col("x"))))
    by_group = Dict(zip(r[:g], r[:x]))
    @test by_group == Dict("a" => UInt32(0), "b" => UInt32(0)) # count excludes nulls
    @test size(filter(df_g, is_null(col("x")))) == (3, 2)

    # round-trips through parquet
    path = write_temp_parquet(df)
    @test isequal(collect(read_parquet(path)[:x]), [missing, missing])
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
