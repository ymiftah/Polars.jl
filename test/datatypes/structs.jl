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

    # Renaming two fields to the same name errors at collect/select time
    @test_throws PolarsError select(r, Structs.rename_fields(col("s"), ["same", "same", "c"]))
end

@testset "Struct field holding a null temporal value (Julia-side P0.9)" begin
    # `load_value(::Value{<:Period})`/`(::Value{DateTime})`/`(::Value{Date})`/`(::Value{Time})`
    # used to lack the `PolarsValueTypeNull` guard every other `load_value` method has. A
    # *bare* untyped null (e.g. `lit(missing)`) is caught one level up by the NamedTuple loader's
    # `PolarsValueTypeUnknown` check -- but a null value in a schema-typed struct field reports
    # its real dtype even while null, bypassing that check and reaching these methods directly,
    # where they used to error ("value is not of type datetime") instead of returning `missing`.
    dt_nt = NamedTuple{(:a, :b), Tuple{Union{DateTime, Missing}, Int}}
    df = DataFrame((; s = dt_nt[(a = DateTime(2024, 1, 1), b = 1), (a = missing, b = 2)]))
    r = collect(df[:s])
    @test r[1].a == DateTime(2024, 1, 1)
    @test ismissing(r[2].a)

    date_nt = NamedTuple{(:a, :b), Tuple{Union{Date, Missing}, Int}}
    df2 = DataFrame((; s = date_nt[(a = Date(2024, 1, 1), b = 1), (a = missing, b = 2)]))
    r2 = collect(df2[:s])
    @test r2[1].a == Date(2024, 1, 1)
    @test ismissing(r2[2].a)

    time_nt = NamedTuple{(:a, :b), Tuple{Union{Dates.Time, Missing}, Int}}
    df3 = DataFrame((; s = time_nt[(a = Dates.Time(1, 2, 3), b = 1), (a = missing, b = 2)]))
    r3 = collect(df3[:s])
    @test r3[1].a == Dates.Time(1, 2, 3)
    @test ismissing(r3[2].a)
end

@testset "Column type Any raises a clear error, not infinite recursion (Julia-side, found during P0.9)" begin
    # `MaybeMissing{Any}` (== `Union{Any, Union{Any,Missing}}`) collapses to the literal type
    # `Any`, so `format(Any)` used to dispatch to the `MaybeMissing{T}` method with `T = Any`
    # solved from that same collapse -- whose body calls `format(Any)` again: unconditional
    # infinite recursion (`StackOverflowError`, not a catchable Julia error). Reachable from a
    # `Vector{<:NamedTuple}` built from row literals whose fields don't share one concrete type
    # across rows (e.g. mixing a concrete value and bare `missing` without a `Union` annotation).
    @test_throws Exception DataFrame((; s = [(a = DateTime(2024, 1, 1), b = 1), (a = missing, b = 2)]))
    @test_throws Exception DataFrame((; x = Any[1, missing]))
    try
        DataFrame((; x = Any[1, missing]))
    catch e
        @test !(e isa StackOverflowError)
    end
end
