@testset "Lists namespace" begin
    # There is no write-side arrow support for constructing a List column directly from a
    # Vector{Vector{T}} via DataFrame(table) -- genuine list-typed columns only arise as query
    # results (e.g. implode, or a group_by aggregation without a reduction). Build one that way,
    # matching how a real user would end up with a List column.
    base = DataFrame((; g = ["a", "a", "a", "b", "b"], v = [1, 2, 3, 4, 5]))
    lst = group_by(lazy(base), "g") |> x -> agg(x, implode(col("v"))) |> collect

    r = select(
        lst, col("g"), Lists.max(col("v")) |> alias("max"),
        Lists.min(col("v")) |> alias("min"),
        Lists.sum(col("v")) |> alias("sum"),
        Lists.mean(col("v")) |> alias("mean"),
        Lists.first(col("v")) |> alias("first"),
        Lists.last(col("v")) |> alias("last"),
        Lists.reverse(col("v")) |> alias("rev"),
        Lists.arg_max(col("v")) |> alias("arg_max"),
        Lists.arg_min(col("v")) |> alias("arg_min")
    )
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

    r3 = select(
        lst, col("g"),
        Lists.lengths(col("v")) |> alias("len"),
        Lists.get(col("v"), lit(0)) |> alias("get0"),
        Lists.get(col("v"), lit(99); null_on_oob = true) |> alias("get_oob"),
        Lists.contains(col("v"), lit(2)) |> alias("has2"),
    )
    by_group3(colname) = Dict(zip(r3[:g], r3[colname]))
    @test by_group3(:len) == Dict("a" => 3, "b" => 2)
    @test by_group3(:get0) == Dict("a" => 1, "b" => 4)
    @test all(ismissing, values(by_group3(:get_oob)))
    @test by_group3(:has2) == Dict("a" => true, "b" => false)

    # `get` errors (rather than returning null) on an out-of-bounds index by default.
    @test_throws Exception collect(select(lst, Lists.get(col("v"), lit(99))))
end

@testset "Lists namespace with nested nulls and empty lists" begin
    # Create a DataFrame with list operations that produce empty or null lists
    df = DataFrame(
        (;
            v = [[1, 2, 3], Int64[], [missing, 4, 5]],
        )
    )

    # Lists.head on empty list should return empty list
    r_head_empty = select(df, Lists.head(col("v"), lit(1)) |> alias("h"))
    @test collect(r_head_empty[:h][2]) == Int64[]

    # Lists.max/min on lists with nulls should handle correctly
    r_max = select(df, Lists.max(col("v")) |> alias("max"))
    max_vals = collect(r_max[:max])
    @test max_vals[1] == 3  # [1, 2, 3] -> 3
    @test ismissing(max_vals[2])  # [] -> missing
    @test max_vals[3] == 5  # [missing, 4, 5] -> 5

    # Lists.lengths on empty lists
    r_len = select(df, Lists.lengths(col("v")) |> alias("len"))
    @test r_len[:len] == [3, 0, 3]

    # Lists.get with null elements
    r_get = select(df, Lists.get(col("v"), lit(0); null_on_oob = true) |> alias("g0"))
    get_vals = collect(r_get[:g0])
    @test get_vals[1] == 1
    @test ismissing(get_vals[2])  # empty list -> null
    @test ismissing(get_vals[3])  # [missing, ...] at index 0 is missing
end

@testset "Lists.get: negative indices, null index, whole-row-null list (py-polars test_list_arr_get*)" begin
    df = DataFrame((; a = [[1, 2, 3], [4, 5], [6, 7, 8, 9]]))
    # negative index counts from the end, matching Python's list.get(-1)
    r_last = select(df, Lists.get(col("a"), lit(-1)) |> alias("last"))
    @test collect(r_last[:last]) == [3, 5, 9]
    r_neg3 = select(df, Lists.get(col("a"), lit(-3); null_on_oob = true) |> alias("n3"))
    @test isequal(collect(r_neg3[:n3]), [1, missing, 7])  # out-of-range negative -> null

    # a null index (not an out-of-bounds value index) propagates to a null result
    r_nullidx = select(df, Lists.get(col("a"), lit(missing)) |> alias("g"))
    @test isequal(collect(r_nullidx[:g]), [missing, missing, missing])

    # a whole-row-null list (the list itself is missing, not just an element within it)
    df2 = DataFrame((; a = Union{Missing, Vector{Int}}[missing, [1, 2]]))
    r2 = select(df2, Lists.get(col("a"), lit(0); null_on_oob = true) |> alias("g"))
    @test isequal(collect(r2[:g]), [missing, 1])
end

@testset "Lists.sum over Boolean lists (py-polars test_list_sum_and_dtypes)" begin
    df = DataFrame((; a = [[true], [true, true], [true, false, true], [true, true, true]]))
    r = select(df, Lists.sum(col("a")) |> alias("s"))
    @test collect(r[:s]) == [1, 2, 2, 3]
end

@testset "Lists.mean/min/max with a whole-row-null list, not just a null element within a list (py-polars test_list_mean, test_list_min_max_13978)" begin
    df_mean = DataFrame((; a = Union{Missing, Vector{Int}}[[1], [1, 2, 3], [1, 2, 3, 4], missing]))
    r_mean = select(df_mean, Lists.mean(col("a")) |> alias("m"))
    @test isequal(collect(r_mean[:m]), [1.0, 2.0, 2.5, missing])

    df_mm = DataFrame((; a = Union{Missing, Vector{Int}}[missing, [1, 2, 3]]))
    r_mm = select(df_mm, Lists.min(col("a")) |> alias("mn"), Lists.max(col("a")) |> alias("mx"))
    @test isequal(collect(r_mm[:mn]), [missing, 1])
    @test isequal(collect(r_mm[:mx]), [missing, 3])
end

@testset "Lists.sort (py-polars test_list_ordering)" begin
    df = DataFrame((; a = [[2, 1], [1, 3, 2]]))
    r = select(df, alias(Lists.sort(col("a")), "s"))
    @test collect(r[:s]) == [[1, 2], [1, 2, 3]]

    df_nulls = DataFrame((; a = [Union{Missing, Int64}[missing, 1, 2], Union{Missing, Int64}[-1, missing, 9]]))
    r_last = select(df_nulls, alias(Lists.sort(col("a"); nulls_last = true), "s"))
    @test isequal(collect(r_last[:s]), [[1, 2, missing], [-1, 9, missing]])

    r_first = select(df_nulls, alias(Lists.sort(col("a"); nulls_last = false), "s"))
    @test isequal(collect(r_first[:s]), [[missing, 1, 2], [missing, -1, 9]])

    r_desc = select(df, alias(Lists.sort(col("a"); descending = true), "s"))
    @test collect(r_desc[:s]) == [[2, 1], [3, 2, 1]]

    # curried form for |> pipelines
    r_curried = select(df, alias(col("a") |> Lists.sort(), "s"))
    @test collect(r_curried[:s]) == collect(r[:s])
end

@testset "Lists.join (py-polars test_list_join)" begin
    df = DataFrame(
        (;
            a = Union{Missing, Vector{Union{Missing, String}}}[["ab", "c", "d"], ["e", "f"], ["g"], String[], missing],
            separator = Union{Missing, String}["&", missing, "*", "_", "*"],
        )
    )
    r_lit = select(df, alias(Lists.join(col("a"), lit("-")), "j"))
    @test isequal(collect(r_lit[:j]), ["ab-c-d", "e-f", "g", "", missing])

    r_col = select(df, alias(Lists.join(col("a"), col("separator")), "j"))
    @test isequal(collect(r_col[:j]), ["ab&c&d", missing, "g", "", missing])

    # ignore_nulls
    df2 = DataFrame(
        (;
            a = Union{Missing, Vector{Union{Missing, String}}}[
                ["a", missing, "b", missing], missing, [missing, missing], ["c", "d"], String[],
            ],
            separator = ["-", "&", " ", "@", "/"],
        )
    )
    # the default is ignore_nulls=true (py-polars: `join(separator, *, ignore_nulls=True)`) --
    # pinned here with no keyword at all, since df's own default-vs-explicit calls above happen
    # to agree (no *inner* nulls in that fixture) and so can't catch a wrong default
    r_default = select(df2, alias(Lists.join(col("a"), lit("-")), "j"))
    @test isequal(collect(r_default[:j]), ["a-b", missing, "", "c-d", ""])

    r_ignore = select(df2, alias(Lists.join(col("a"), lit("-"); ignore_nulls = true), "j"))
    @test isequal(collect(r_ignore[:j]), ["a-b", missing, "", "c-d", ""])

    r_ignore_col = select(df2, alias(Lists.join(col("a"), col("separator"); ignore_nulls = true), "j"))
    @test isequal(collect(r_ignore_col[:j]), ["a-b", missing, "", "c@d", ""])

    r_propagate = select(df2, alias(Lists.join(col("a"), lit("-"); ignore_nulls = false), "j"))
    @test isequal(collect(r_propagate[:j]), [missing, missing, missing, "c-d", ""])

    # curried form for |> pipelines
    r_curried = select(df, alias(col("a") |> Lists.join("-"), "j"))
    @test isequal(collect(r_curried[:j]), collect(r_lit[:j]))
end

@testset "Lists.slice (py-polars test_list_slice)" begin
    df = DataFrame((; lst = [[1, 2, 3, 4], [10, 2, 1]], offset = [1, 2], len = [3, 2]))

    r = select(df, alias(Lists.slice(col("lst"), col("offset"), col("len")), "s"))
    @test collect(r[:s]) == [[2, 3, 4], [1]]

    r_len1 = select(df, alias(Lists.slice(col("lst"), col("offset"), lit(1)), "s"))
    @test collect(r_len1[:s]) == [[2], [1]]

    r_negoff = select(df, alias(Lists.slice(col("lst"), lit(-2), col("len")), "s"))
    @test collect(r_negoff[:s]) == [[3, 4], [2, 1]]

    # null length extends to the end of the list
    r_toend = select(df, alias(Lists.slice(col("lst"), lit(1), lit(missing)), "s"))
    @test collect(r_toend[:s]) == [[2, 3, 4], [2, 1]]

    # curried form for |> pipelines
    r_curried = select(df, alias(col("lst") |> Lists.slice(1, 2), "s"))
    @test collect(r_curried[:s]) == [[2, 3], [2, 1]]
end

@testset "Lists.diff (py-polars test_list_diff)" begin
    df = DataFrame((; a = [[1, 2], [10, 2, 1]]))
    r = select(df, alias(Lists.diff(col("a")), "d"))
    @test isequal(collect(r[:d]), [[missing, 1], [missing, -8, -1]])

    df2 = DataFrame((; a = [[1, 3, 6, 10]]))
    r_drop = select(df2, alias(Lists.diff(col("a"), 2; null_behavior = :drop), "d"))
    @test collect(r_drop[:d]) == [[5, 7]]

    @test_throws ErrorException Lists.diff(col("a"); null_behavior = :bogus)
end

@testset "Lists.n_unique (py-polars test_list_n_unique)" begin
    df = DataFrame(
        (;
            a = Union{Missing, Vector{Union{Missing, Int64}}}[[1, 1, 2], [3, 3], [missing], missing, Int64[]],
        )
    )
    r = select(df, alias(Lists.n_unique(col("a")), "nu"))
    @test isequal(collect(r[:nu]), [2, 1, 1, missing, 0])
end

@testset "Lists.any / Lists.all (py-polars test_list_any / test_list_all)" begin
    a = Vector{Union{Bool, Missing}}[
        [true], [false], [true, true], [true, false], [false, false], [missing], Bool[],
    ]
    df = DataFrame((; a = a))

    r_any = select(df, alias(Lists.any(col("a")), "any"))
    @test collect(r_any[:any]) == [true, false, true, true, false, false, false]

    r_all = select(df, alias(Lists.all(col("a")), "all"))
    @test collect(r_all[:all]) == [true, false, true, false, false, true, true]

    # ignore_nulls=false switches to three-valued (Kleene) logic: a null with no True (any) / no
    # False (all) makes the whole list's result null instead of false/true
    r_any_kleene = select(df, alias(Lists.any(col("a"); ignore_nulls = false), "any"))
    @test isequal(collect(r_any_kleene[:any]), [true, false, true, true, false, missing, false])

    r_all_kleene = select(df, alias(Lists.all(col("a"); ignore_nulls = false), "all"))
    @test isequal(collect(r_all_kleene[:all]), [true, false, true, false, false, missing, true])
end

@testset "Lists.to_struct: one field per list position (see plans/parity/gap_closure_scope.md Group C, batch-9-lists-structs.md)" begin
    df = DataFrame((; a = [[1, 2], [3, 4]]))
    r = select(df, alias(Lists.to_struct(col("a"), ["x", "y"]), "s"))
    vals = collect(r[:s])
    @test vals[1] == (x = 1, y = 2)
    @test vals[2] == (x = 3, y = 4)

    # a shorter list gets missing for the trailing fields, not an error
    df_short = DataFrame((; a = [[1], [3, 4]]))
    r_short = select(df_short, alias(Lists.to_struct(col("a"), ["x", "y"]), "s"))
    vals_short = collect(r_short[:s])
    @test vals_short[1].x == 1
    @test ismissing(vals_short[1].y)
    @test vals_short[2] == (x = 3, y = 4)
end

@testset "Lists.unique on Boolean lists collapses repeated nulls to one (py-polars test_list_unique_boolean_22753)" begin
    df = DataFrame(
        (;
            a = [
                Union{Missing, Bool}[],
                Union{Missing, Bool}[missing],
                Union{Missing, Bool}[missing, missing],
                Union{Missing, Bool}[missing, missing, missing, false],
                Union{Missing, Bool}[
                    missing, missing, missing, false, missing, missing, missing, true, true,
                ],
            ],
        )
    )
    r = select(df, Lists.unique(col("a")) |> alias("u"))
    # unique's own element order isn't guaranteed (docstring), so compare as sets per row
    rows = [Set(collect(row)) for row in collect(r[:u])]
    @test rows == [
        Set{Union{Missing, Bool}}(), Set([missing]), Set([missing]), Set([missing, false]),
        Set([missing, false, true]),
    ]
end
