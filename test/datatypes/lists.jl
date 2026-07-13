@testset "Lists namespace" begin
    # There is no write-side arrow support for constructing a List column directly from a
    # Vector{Vector{T}} via DataFrame(table) -- genuine list-typed columns only arise as query
    # results (e.g. implode, or a group_by aggregation without a reduction). Build one that way,
    # matching how a real user would end up with a List column.
    base = DataFrame((; g = ["a", "a", "a", "b", "b"], v = [1, 2, 3, 4, 5]))
    lst = group_by(lazy(base), "g") |> x -> agg(x, implode(col("v"))) |> collect

    r = select(lst, col("g"), Lists.max(col("v")) |> alias("max"),
                    Lists.min(col("v")) |> alias("min"),
                    Lists.sum(col("v")) |> alias("sum"),
                    Lists.mean(col("v")) |> alias("mean"),
                    Lists.first(col("v")) |> alias("first"),
                    Lists.last(col("v")) |> alias("last"),
                    Lists.reverse(col("v")) |> alias("rev"),
                    Lists.arg_max(col("v")) |> alias("arg_max"),
                    Lists.arg_min(col("v")) |> alias("arg_min"))
    # group_by doesn't guarantee row order, so index results by group key (house convention)
    by_group(colname) = Dict(zip(r[:g], r[colname]))
    @test by_group(:max) == Dict("a" => 3, "b" => 5)
    @test by_group(:min) == Dict("a" => 1, "b" => 4)
    @test by_group(:sum) == Dict("a" => 6, "b" => 9)
    @test by_group(:mean) == Dict("a" => 2.0, "b" => 4.5)
    @test by_group(:first) == Dict("a" => 1, "b" => 4)
    @test by_group(:last) == Dict("a" => 3, "b" => 5)
    @test by_group(:arg_max) == Dict("a" => 2, "b" => 1)  # 0-based index of the max within each list
    @test by_group(:arg_min) == Dict("a" => 0, "b" => 0)

    rev_by_group = Dict(g => collect(rev) for (g, rev) in zip(r[:g], r[:rev]))
    @test rev_by_group == Dict("a" => [3, 2, 1], "b" => [5, 4])

    head_r = select(lst, col("g"), Lists.head(col("v"), lit(2)) |> alias("h"))
    head_by_group = Dict(g => collect(h) for (g, h) in zip(head_r[:g], head_r[:h]))
    @test head_by_group == Dict("a" => [1, 2], "b" => [4, 5])

    # unique / unique_stable
    base2 = DataFrame((; g = ["a", "a", "a", "a"], v = [1, 2, 2, 1]))
    lst2 = group_by(lazy(base2), "g") |> x -> agg(x, implode(col("v"))) |> collect
    r2 = select(lst2, Lists.unique(col("v")) |> alias("u"), Lists.unique_stable(col("v")) |> alias("us"))
    @test sort(collect(only(r2[:u]))) == [1, 2]
    @test collect(only(r2[:us])) == [1, 2]

    # lengths/get/contains are referenced on the Julia side (Lists module) but their Rust
    # implementations are commented out in c-polars/src/expr.rs (no feature-gate reason given,
    # unlike Strings.titlecase) -- so no ccall binding exists for any of the three.
    @test_broken select(lst, Lists.lengths(col("v"))) isa Any
    @test_broken select(lst, Lists.get(col("v"), lit(0))) isa Any
    @test_broken select(lst, Lists.contains(col("v"), lit(1))) isa Any
end
