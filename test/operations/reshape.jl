@testset "explode" begin
    # build a list-typed column via group_by + implode (no direct Vector{Vector} construction
    # path from Julia yet, see CLAUDE.md's known sharp edges), then explode it back
    df = DataFrame((; g = ["a", "a", "b", "b", "b"], x = [1, 2, 10, 20, 30]))
    listed = agg(group_by(lazy(df), "g"), Polars.implode(col("x"))) |> collect

    exploded = explode(listed, ["x"])
    @test size(exploded) == (5, 2)
    @test Set(zip(exploded[:g], exploded[:x])) == Set(zip(df[:g], df[:x]))

    # LazyFrame entry point agrees
    exploded_lazy = explode(lazy(listed), ["x"]) |> collect
    @test size(exploded_lazy) == size(exploded)
end

@testset "unpivot" begin
    wide = DataFrame((; id = [1, 2], a = [10, 20], b = [100, 200]))

    long = unpivot(wide, ["id"])
    @test Tables.columnnames(long) == (:id, :variable, :value)
    @test long[:id] == [1, 2, 1, 2]
    @test long[:variable] == ["a", "a", "b", "b"]
    @test long[:value] == [10, 20, 100, 200]

    # restrict to a subset of melted columns, custom output names
    partial = unpivot(wide, ["id"]; on = ["a"], variable_name = "key", value_name = "val")
    @test Tables.columnnames(partial) == (:id, :key, :val)
    @test partial[:key] == ["a", "a"]
    @test partial[:val] == [10, 20]

    # LazyFrame entry point agrees
    long_lazy = unpivot(lazy(wide), ["id"]) |> collect
    @test long_lazy[:value] == long[:value]
end
