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
