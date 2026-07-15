@testset "List column construction from Vector{Vector{T}}" begin
    df = DataFrame((; x = [[1, 2], [3], [4, 5, 6]]))
    path = write_temp_parquet(df)
    r = read_parquet(path)

    @test size(r) == (3, 1)
    @test collect(r[:x][1]) == [1, 2]
    @test collect(r[:x][2]) == [3]
    @test collect(r[:x][3]) == [4, 5, 6]

    # verify via flatten (Milestone A), independent of direct row indexing
    @test collect(select(r, flatten(col("x")))[:x]) == [1, 2, 3, 4, 5, 6]

    # String element type
    df2 = DataFrame((; s = [["a", "b"], ["c"]]))
    r2 = read_parquet(write_temp_parquet(df2))
    @test collect(r2[:s][1]) == ["a", "b"]
    @test collect(r2[:s][2]) == ["c"]

    # nullable list (missing sublist)
    df3 = DataFrame((; x = Union{Missing, Vector{Int}}[[1, 2], missing, [3]]))
    r3 = read_parquet(write_temp_parquet(df3))
    @test collect(r3[:x][1]) == [1, 2]
    @test ismissing(r3[:x][2])
    @test collect(r3[:x][3]) == [3]
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
