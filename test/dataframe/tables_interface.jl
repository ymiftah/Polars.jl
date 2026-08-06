# Tables.jl interface conformance for `DataFrame`/`DataFrameColumns`, plus the column-name cache
# that positional access depends on.

@testset "Tables.rows: the row half of the interface actually exists" begin
    # `Tables.rowaccess(::DataFrame) = true` declares this method to Tables.jl, which takes the
    # declaration as a promise -- without a definition to back it, row-oriented consumers fall
    # through to Tables.jl's own fallbacks rather than anything this package guarantees.
    df = DataFrame((; a = [1, 2, 3], b = ["x", "y", "z"]))

    rows = collect(Tables.rows(df))
    @test length(rows) == 3
    @test Tables.getcolumn(rows[1], :a) == 1
    @test Tables.getcolumn(rows[1], :b) == "x"
    @test Tables.getcolumn(rows[3], :a) == 3

    # the standard consumers built on top of `rows`
    @test Tables.rowtable(df) == [(a = 1, b = "x"), (a = 2, b = "y"), (a = 3, b = "z")]

    # nulls survive the trip as `missing`, and the row iterator is not fooled by them
    df_null = DataFrame((; a = [1, missing, 3]))
    @test isequal(Tables.rowtable(df_null), [(a = 1,), (a = missing,), (a = 3,)])

    # a frame with no rows iterates zero times rather than erroring
    @test isempty(Tables.rowtable(DataFrame((; a = Int64[], b = String[]))))
end

@testset "Tables.columns is idempotent" begin
    # Anything `Tables.columns` returns must itself answer `Tables.columns` -- generic Tables.jl
    # machinery (`columntable`, `rows`, ...) re-normalizes a table before consuming it.
    df = DataFrame((; a = [1, 2], b = ["x", "y"]))
    cols = Tables.columns(df)
    @test Tables.columns(cols) === cols
    @test Tables.istable(cols)
    @test Tables.columnaccess(cols)
    @test Tables.columnnames(cols) == (:a, :b)
    @test collect(Tables.getcolumn(cols, :a)) == [1, 2]
    @test collect(Tables.getcolumn(cols, 2)) == ["x", "y"]
    @test Tables.schema(cols) == Tables.schema(df)
end

@testset "DataFrameColumns is concretely typed" begin
    # `names` is an `NTuple{N,Symbol}` with `N` a type parameter, rather than an abstract
    # `Tuple{Vararg{Symbol}}` whose every access would box.
    cols = Tables.columns(DataFrame((; a = [1], b = [2], c = [3])))
    @test isconcretetype(typeof(cols))
    @test typeof(cols) == Polars.DataFrameColumns{3}
    @test fieldtype(typeof(cols), :names) == NTuple{3, Symbol}
end

@testset "column names are cached per handle" begin
    # An unmemoized `_column_names` call costs a ccall plus a full Arrow schema export and parse,
    # which would make positional column access O(ncols) *per column*. The cache is sound because
    # no C entry point renames/adds/drops a column of an existing frame in place.
    df = DataFrame((; a = [1, 2], b = ["x", "y"], c = [1.5, 2.5]))
    @test df.column_names === nothing # nothing computed until asked

    @test Tables.columnnames(df) == (:a, :b, :c)
    @test df.column_names == (:a, :b, :c) # ... and memoized from then on
    @test Tables.columnnames(df) == (:a, :b, :c) # second read is served from the cache
    @test names(df) == ["a", "b", "c"]

    # positional access agrees with by-name access, cache or no cache
    @test collect(Tables.getcolumn(df, 1)) == [1, 2]
    @test collect(Tables.getcolumn(df, 3)) == [1.5, 2.5]
    @test collect(df[2]) == ["x", "y"]

    # a derived frame is a separate handle with its own (independent) cache
    dropped = drop(df, ["b"])
    @test dropped.column_names === nothing
    @test names(dropped) == ["a", "c"]
    @test names(df) == ["a", "b", "c"] # the original is untouched
end

@testset "DataFrame column indexing accepts any AbstractString" begin
    df = DataFrame((; abc = [1, 2, 3]))

    @test collect(df["abc"]) == [1, 2, 3]
    @test collect(df[:abc]) == [1, 2, 3]
    # a `SubString` is an `AbstractString` like any other, so it indexes the same way
    @test collect(df[SubString("abc_suffix", 1, 3)]) == [1, 2, 3]
    @test collect(get_column(df, SubString("abc_suffix", 1, 3))) == [1, 2, 3]

    # a missing column still raises, whichever spelling is used
    @test_throws PolarsError df["nope"]
    @test_throws PolarsError df[:nope]
    @test get_column(df, "nope"; default = nothing) === nothing
end
