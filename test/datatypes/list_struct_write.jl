@testset "List column construction from Vector{Vector{T}}" begin
    df = DataFrame((; x = [[1, 2], [3], [4, 5, 6]]))
    path = write_temp_parquet(df)
    r = read_parquet(path)

    @test size(r) == (3, 1)
    # List elements are plain Vectors (not nested Series), so getindex already returns the
    # materialized row -- no collect() needed.
    @test r[:x][1] == [1, 2]
    @test r[:x][2] == [3]
    @test r[:x][3] == [4, 5, 6]
    @test collect(r[:x]) == [[1, 2], [3], [4, 5, 6]] # bulk path agrees

    # verify via flatten (Milestone A), independent of direct row indexing
    @test collect(select(r, flatten(col("x")))[:x]) == [1, 2, 3, 4, 5, 6]

    # String element type
    df2 = DataFrame((; s = [["a", "b"], ["c"]]))
    r2 = read_parquet(write_temp_parquet(df2))
    @test r2[:s][1] == ["a", "b"]
    @test r2[:s][2] == ["c"]
    @test collect(r2[:s]) == [["a", "b"], ["c"]]

    # nullable list (missing sublist)
    df3 = DataFrame((; x = Union{Missing, Vector{Int}}[[1, 2], missing, [3]]))
    r3 = read_parquet(write_temp_parquet(df3))
    @test r3[:x][1] == [1, 2]
    @test ismissing(r3[:x][2])
    @test r3[:x][3] == [3]
    @test isequal(collect(r3[:x]), [[1, 2], missing, [3]])
end

@testset "Struct column construction from Vector{<:NamedTuple}" begin
    df = DataFrame((; s = [(a = 1, b = "x"), (a = 2, b = "y"), (a = 3, b = "z")]))
    path = write_temp_parquet(df)
    r = read_parquet(path)

    @test size(r) == (3, 1)

    # verify via Structs.field_by_name (Milestone A)
    fa = select(r, Structs.field_by_name(col("s"), "a"))
    fb = select(r, Structs.field_by_name(col("s"), "b"))
    @test fa[:a] == [1, 2, 3]
    @test fb[:b] == ["x", "y", "z"]
end

# Top level, outside any @testset -- a `struct` cannot be declared inside one.
struct StructWritePoint
    x::Int
    y::String
end

@testset "struct columns: nullable NamedTuple and plain immutable struct" begin
    # `format` maps any immutable struct (and strips Missing first) to "+s", but `arrowvector`
    # used to have only a `Vector{<:NamedTuple}` method -- so both of these raised a bare
    # MethodError from the array builder after the schema had already been built.
    df = DataFrame((; n = Union{NamedTuple{(:a,), Tuple{Int}}, Missing}[(a = 1,), missing, (a = 3,)]))
    @test size(df) == (3, 1)
    @test df[:n][1] == (a = 1,)
    @test ismissing(df[:n][2])
    @test df[:n][3] == (a = 3,)

    # A plain immutable struct column, which `format(ImmutableColumnElement) == "+s"` promises.
    df2 = DataFrame((; p = [StructWritePoint(1, "a"), StructWritePoint(2, "b")]))
    @test size(df2) == (2, 1)
    @test df2[:p][1] == (x = 1, y = "a")
    @test df2[:p][2] == (x = 2, y = "b")

    # Nullable plain struct.
    df3 = DataFrame((; p = Union{StructWritePoint, Missing}[StructWritePoint(1, "a"), missing]))
    @test size(df3) == (2, 1)
    @test df3[:p][1] == (x = 1, y = "a")
    @test ismissing(df3[:p][2])

    # The plain (non-nullable) NamedTuple path must be unchanged, including through parquet.
    df4 = DataFrame((; n = [(a = 1, b = "x"), (a = 2, b = "y")]))
    r4 = read_parquet(write_temp_parquet(df4))
    @test r4[:n][1] == (a = 1, b = "x")
    @test r4[:n][2] == (a = 2, b = "y")

    # A nested struct field still recurses.
    df5 = DataFrame((; n = [(a = (b = 1,),), (a = (b = 2,),)]))
    @test df5[:n][1] == (a = (b = 1,),)

    # A mutable struct is still rejected, by `format`, before reaching `arrowvector`.
    @test_throws ErrorException DataFrame((; x = [MutableColumnElement(1)]))

    # Regression guard for the Task 9 interaction: a Period is an immutable struct, so without
    # Task 9's dedicated Duration mapping this generic method would silently turn it into a
    # `(value = Int64,)` struct column. It must stay a Duration.
    df6 = DataFrame((; d = [Millisecond(5), Millisecond(7)]))
    @test collect(df6[:d]) == [Millisecond(5), Millisecond(7)]
end
