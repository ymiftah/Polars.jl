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

@testset "unnest" begin
    # basic single struct column, via the DataFrame convenience wrapper
    people = DataFrame((; id = [1, 2], info = [(name = "Alice", age = 30), (name = "Bob", age = 25)]))
    u = unnest(people, ["info"])
    @test Tables.columnnames(u) == (:id, :name, :age)
    @test u[:id] == [1, 2]
    @test u[:name] == ["Alice", "Bob"]
    @test u[:age] == [30, 25]

    # multiple struct columns unnested at once, each in field order
    multi = DataFrame(
        (;
            id = [1, 2],
            a = [(x = 1, y = 2), (x = 3, y = 4)],
            b = [(p = "q", r = "s"), (p = "t", r = "u")],
        )
    )
    um = unnest(multi, ["a", "b"])
    @test Tables.columnnames(um) == (:id, :x, :y, :p, :r)
    @test um[:x] == [1, 3]
    @test um[:p] == ["q", "t"]

    # separator: absent -> bare field name; present -> "<column><separator><field>"
    u_nosep = unnest(people, ["info"])
    @test Tables.columnnames(u_nosep) == (:id, :name, :age)
    u_sep = unnest(people, ["info"]; separator = "_")
    @test Tables.columnnames(u_sep) == (:id, :info_name, :info_age)
    @test u_sep[:info_name] == ["Alice", "Bob"]

    # struct-of-struct, one level deep: unnesting the outer column leaves the inner field
    # still struct-typed (does not recursively flatten) -- a second unnest is needed
    nested = DataFrame(
        (;
            id = [1, 2],
            outer = [(inner = (a = 1, b = 2), z = 100), (inner = (a = 3, b = 4), z = 200)],
        )
    )
    once = unnest(nested, ["outer"])
    @test Tables.columnnames(once) == (:id, :inner, :z)
    @test once[:inner][1] isa NamedTuple
    @test once[:inner][1].a == 1
    twice = unnest(once, ["inner"])
    @test Tables.columnnames(twice) == (:id, :a, :b, :z)
    @test twice[:a] == [1, 3]
    @test twice[:b] == [2, 4]

    # whole-row-null struct entry: unnests to `missing` fields, not an error. There is no
    # direct Julia-side constructor for a Vector{Union{Missing,<:NamedTuple}} struct column
    # (see `arrowvector`), so build a valid struct column and null out a row via `when`.
    base = DataFrame((; id = [1, 2], s = [(a = 1, b = 2), (a = 3, b = 4)]))
    nulled = with_columns(base, alias(when(col("id") == 1, lit(missing), col("s")), "s"))
    @test isequal(nulled[:s], [missing, (a = 3, b = 4)])
    un = unnest(nulled, ["s"])
    @test Tables.columnnames(un) == (:id, :a, :b)
    @test isequal(un[:a], [missing, 3])
    @test isequal(un[:b], [missing, 4])

    # name collision -> a clean PolarsError, not a crash: two unnested fields sharing a name
    collide = DataFrame(
        (;
            id = [1, 2],
            a = [(v = 1,), (v = 2,)],
            b = [(v = 10,), (v = 20,)],
        )
    )
    @test_throws PolarsError unnest(collide, ["a", "b"])

    # name collision -> an unnested field colliding with an existing column
    collide2 = DataFrame((; v = [100, 200], a = [(v = 1,), (v = 2,)]))
    @test_throws PolarsError unnest(collide2, ["a"])

    # unnesting a nonexistent column errors (strict-by-name), not a silent no-op
    @test_throws PolarsError unnest(people, ["nope"])

    # unnesting a non-struct-typed column also errors cleanly
    @test_throws PolarsError unnest(people, ["id"])

    # empty frame: schema still gets flattened, zero rows
    empty_people = filter(people, col("id") == 999)
    @test size(empty_people) == (0, 2)
    u_empty = unnest(empty_people, ["info"])
    @test Tables.columnnames(u_empty) == (:id, :name, :age)
    @test size(u_empty) == (0, 3)

    # exercised via the LazyFrame path directly, not only the DataFrame wrapper
    lf = lazy(people)
    lf_result = unnest(lf, ["info"])
    @test lf_result isa Polars.LazyFrame
    collected = collect(lf_result)
    @test Tables.columnnames(collected) == (:id, :name, :age)
    @test collected[:name] == ["Alice", "Bob"]

    # ...and the LazyFrame path surfaces the same strict-by-name error, not a crash
    @test_throws PolarsError collect(unnest(lf, ["nope"]))
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
