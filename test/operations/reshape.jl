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

@testset "pivot" begin
    df = DataFrame((; id = [1, 1, 2, 2], var = ["a", "b", "a", "b"], val = [10, 20, 30, 40]))

    r = pivot(df, "var", "id", "val")
    r = sort(r, col("id"))
    @test Set(string.(Tables.columnnames(r))) == Set(["id", "a", "b"])
    @test r[:id] == [1, 2]
    @test r[:a] == [10, 30]
    @test r[:b] == [20, 40]

    # custom agg (default is first): sum over duplicate (id, var) pairs
    df2 = DataFrame((; id = [1, 1, 1, 2], var = ["a", "a", "b", "a"], val = [10, 20, 30, 40]))
    r2 = sort(pivot(df2, "var", "id", "val"; agg = Base.sum(element())), col("id"))
    @test r2[:a] == [30, 40]
    @test r2[:b] == [30, 0]

    # multiple `values` columns: column names combine value+on-value (auto behavior for >1 values)
    df3 = DataFrame((; id = [1, 2], var = ["a", "b"], v1 = [1, 2], v2 = [10, 20]))
    r3 = pivot(df3, "var", "id", ["v1", "v2"])
    @test Set(string.(Tables.columnnames(r3))) == Set(["id", "v1_a", "v1_b", "v2_a", "v2_b"])
    r3 = sort(r3, col("id"))
    @test isequal(r3[:v1_a], [1, missing])
    @test isequal(r3[:v1_b], [missing, 2])

    # Vector on/index/values args accepted alongside plain strings
    r4 = sort(pivot(df, ["var"], ["id"], ["val"]), col("id"))
    @test r4[:a] == r[:a]

    @test_throws ErrorException pivot(df, "var", "id", "val"; column_naming = :bogus)
end

@testset "element" begin
    # element() is only valid as the argument to an aggregate function passed to pivot's
    # `agg=` kwarg (it errors as "not allowed in this context" in a plain select) -- it stands
    # in for the values at each (index, on) cell being reduced.
    df = DataFrame((; id = [1, 1, 1, 2], var = ["a", "a", "b", "a"], val = [10, 20, 30, 40]))

    @test_throws PolarsError select(df, alias(Base.sum(element()), "total"))

    # sum aggregation of duplicates
    r_sum = sort(pivot(df, "var", "id", "val"; agg = Base.sum(element())), col("id"))
    @test r_sum[:a] == [30, 40]  # id=1: 10+20, id=2: 40
    @test r_sum[:b] == [30, 0]   # id=1: 30, id=2: 0 (missing)

    # mean aggregation of duplicates
    r_mean = sort(pivot(df, "var", "id", "val"; agg = mean(element())), col("id"))
    @test r_mean[:a] == [15.0, 40.0]  # id=1: mean(10,20), id=2: 40

    # max/min aggregation of duplicates
    r_max = sort(pivot(df, "var", "id", "val"; agg = Polars.max(element())), col("id"))
    @test r_max[:a] == [20, 40]
    r_min = sort(pivot(df, "var", "id", "val"; agg = Polars.min(element())), col("id"))
    @test r_min[:a] == [10, 40]
end
