@testset "Structs namespace" begin
    # Struct column construction from Vector{<:NamedTuple} (Milestone E3b) and value_counts
    # (Tier 1) both provide genuine struct-typed columns from pure Julia now -- field_by_name
    # is already covered via the write path in datatypes/list_struct_write.jl; this covers the
    # remaining field_by_index/rename_fields.
    df = DataFrame((; s = [(a = 1, b = "x"), (a = 2, b = "y"), (a = 3, b = "z")]))
    r = read_parquet(write_temp_parquet(df))

    fa = select(r, Structs.field_by_index(col("s"), 0))
    fb = select(r, Structs.field_by_index(col("s"), 1))
    @test fa[:a] == [1, 2, 3]
    @test fb[:b] == ["x", "y", "z"]

    renamed = select(r, Structs.rename_fields(col("s"), ["first", "second"]))
    @test Set(propertynames(renamed[:s][1])) == Set([:first, :second])
    @test renamed[:s][1].first == 1
    @test renamed[:s][1].second == "x"

    # Fix2 curried forms compose via |>
    fa2 = select(r, col("s") |> Structs.field_by_index(0))
    @test fa2[:a] == [1, 2, 3]
end

@testset "Structs namespace edge cases" begin
    # Struct with multiple fields
    df = DataFrame((; s = [(x = 10, y = 20, z = 30), (x = 11, y = 21, z = 31)]))
    r = read_parquet(write_temp_parquet(df))

    # Access each field by index
    fx = select(r, Structs.field_by_index(col("s"), 0))
    fy = select(r, Structs.field_by_index(col("s"), 1))
    fz = select(r, Structs.field_by_index(col("s"), 2))
    @test fx[:x] == [10, 11]
    @test fy[:y] == [20, 21]
    @test fz[:z] == [30, 31]

    # Rename multiple fields
    renamed_multi = select(r, Structs.rename_fields(col("s"), ["a", "b", "c"]))
    @test Set(propertynames(renamed_multi[:s][1])) == Set([:a, :b, :c])
    @test renamed_multi[:s][1].a == 10
    @test renamed_multi[:s][1].b == 20
    @test renamed_multi[:s][1].c == 30
end
