@testset "sort" begin
    df = DataFrame((; letters = ["c", "a", "b", missing, "a"], idx = [1, 2, 3, 4, 5]))

    # ascending, nulls_last=true (default), stable ties keep original relative order
    s1 = sort(df, col("letters"))
    @test collect(skipmissing(s1[:letters])) == ["a", "a", "b", "c"]
    @test ismissing(s1[:letters][end])
    @test s1[:idx] == [2, 5, 3, 1, 4]  # the two "a" rows (idx 2, 5) keep their relative order

    # descending
    s2 = sort(df, col("letters"); rev = true)
    @test collect(skipmissing(s2[:letters])) == ["c", "b", "a", "a"]
    @test ismissing(s2[:letters][end])  # nulls_last=true still applies regardless of rev

    # nulls_last=false
    s3 = sort(df, col("letters"); nulls_last = false)
    @test ismissing(s3[:letters][1])
    @test collect(skipmissing(s3[:letters])) == ["a", "a", "b", "c"]

    # multi-column sort with a per-column rev vector
    df2 = DataFrame((; g = ["a", "a", "b", "b"], v = [2, 1, 4, 3]))
    s4 = sort(df2, col("g"), col("v"); rev = [false, true])
    @test s4[:g] == ["a", "a", "b", "b"]
    @test s4[:v] == [2, 1, 4, 3]

    # LazyFrame form agrees with the DataFrame form
    s5 = sort(lazy(df), col("letters")) |> collect
    @test isequal(collect(s5[:letters]), collect(s1[:letters]))

    # stable=false: order among equal sort keys is unspecified
    df3 = DataFrame((; key = [1, 2, 1, 2, 1], val = [10, 20, 30, 40, 50]))
    s_unstable = sort(df3, col("key"); stable = false)
    sorted_vals = s_unstable[:val]
    # All 1's should come before all 2's
    ones_indices = findall(==(1), s_unstable[:key])
    twos_indices = findall(==(2), s_unstable[:key])
    @test isempty(ones_indices) || isempty(twos_indices) || maximum(ones_indices) < minimum(twos_indices)
end

@testset "sort by expression" begin
    df = DataFrame(
        (;
            x = [3, 1, 2],
            y = [30, 10, 20],
        )
    )

    # Sort by computed expression (x * 2)
    s_expr = sort(df, col("x") * 2)
    @test s_expr[:x] == [1, 2, 3]

    # Sort by string length expression
    df_str = DataFrame((; s = ["apple", "pie", "banana"], val = [1, 2, 3]))
    s_len = sort(df_str, Strings.len_chars(col("s")))
    @test s_len[:s] == ["pie", "apple", "banana"]  # lengths: 3, 5, 6
end

@testset "multi-column sort with nulls_last" begin
    df = DataFrame(
        (;
            g = ["a", "a", "b", "b"],
            v = [2, missing, 1, missing],
        )
    )

    # Sort by g ascending, then v ascending with nulls_last=true
    s_nulls_last = sort(df, col("g"), col("v"); nulls_last = true)
    @test s_nulls_last[:g] == ["a", "a", "b", "b"]
    # For group "a": [2, missing] → 2 comes first, missing last
    # For group "b": [1, missing] → 1 comes first, missing last
    @test s_nulls_last[:v][1] == 2
    @test ismissing(s_nulls_last[:v][2])
    @test s_nulls_last[:v][3] == 1
    @test ismissing(s_nulls_last[:v][4])

    # Sort with nulls_last=false
    s_nulls_first = sort(df, col("g"), col("v"); nulls_last = false)
    # For each group, nulls should come first: [missing, 2, missing, 1]
    @test ismissing(s_nulls_first[:v][1])
    @test s_nulls_first[:v][2] == 2
    @test ismissing(s_nulls_first[:v][3])
    @test s_nulls_first[:v][4] == 1
end

@testset "sort: a wrong-length `rev` raises ArgumentError" begin
    # Validating a user-supplied argument, so a real exception rather than an `@assert` (which
    # the Julia manual is explicit must not be used for this -- assertions may be disabled).
    df = DataFrame((; g = ["a", "b"], v = [1, 2]))

    @test_throws ArgumentError sort(df, col("g"), col("v"); rev = [true])
    @test_throws ArgumentError sort(df, col("g"); rev = [true, false])
    @test_throws ArgumentError sort(lazy(df), col("g"), col("v"); rev = Bool[])

    err = try
        sort(df, col("g"), col("v"); rev = [true])
    catch e
        e
    end
    @test err isa ArgumentError
    @test contains(err.msg, "2 expressions")
    @test contains(err.msg, "1 rev")

    # a scalar `rev` is broadcast over every expression and stays valid
    @test names(sort(df, col("g"), col("v"); rev = true)) == ["g", "v"]
end

@testset "top_k / bottom_k (frame-level)" begin
    df = DataFrame((; g = ["a", "b", "a", "b", "a"], v = [3, 1, 5, 2, 4]))

    r_top = top_k(df, 3, col("v"))
    @test size(r_top) == (3, 2)
    @test collect(r_top[:v]) == [5, 4, 3]

    r_bottom = bottom_k(df, 2, col("v"))
    @test collect(r_bottom[:v]) == [1, 2]

    # multi-key `by`, with a per-key `rev` (same convention as `Base.sort` -- see the module note
    # on `top_k` for why `nulls_last` isn't a parameter here, unlike `sort`)
    r_multi = top_k(df, 2, col("g"), col("v"); rev = [false, true])
    @test collect(r_multi[:g]) == ["b", "b"]
    @test collect(r_multi[:v]) == [1, 2]

    # k larger than the row count returns every row rather than erroring
    r_over = top_k(df, 100, col("v"))
    @test size(r_over) == (5, 2)

    # LazyFrame form agrees
    r_lazy = top_k(lazy(df), 3, col("v")) |> collect
    @test isequal(collect(r_lazy[:v]), collect(r_top[:v]))

    # `rev` length is validated the same way `sort` validates it
    @test_throws ArgumentError top_k(df, 2, col("g"), col("v"); rev = [true])

    # distinct from the `Expr`-level `top_k`/`bottom_k` (top/bottom *values* of one column, not
    # whole rows)
    r_expr = select(df, alias(top_k(col("v"), lit(3)), "v"))
    @test Set(collect(r_expr[:v])) == Set([5, 4, 3])
end

@testset "slice (frame-level)" begin
    df = DataFrame((; x = collect(1:10)))

    r = slice(df, 2, 3)
    @test collect(r[:x]) == [3, 4, 5]

    # negative offset counts from the end
    r_neg = slice(df, -3, 2)
    @test collect(r_neg[:x]) == [8, 9]

    # a zero-length slice is a valid, empty result rather than an error
    r_zero = slice(df, 0, 0)
    @test size(r_zero) == (0, 1)

    # a length longer than what's available is clamped, not an error
    r_over = slice(df, 8, 100)
    @test collect(r_over[:x]) == [9, 10]

    # LazyFrame form agrees
    r_lazy = slice(lazy(df), 2, 3) |> collect
    @test isequal(collect(r_lazy[:x]), collect(r[:x]))

    # distinct from the `Expr`-level `slice` (slices one expression's own result, not the frame's
    # rows)
    r_expr = select(df, alias(slice(col("x"), 2, 3), "x"))
    @test collect(r_expr[:x]) == [3, 4, 5]
end
