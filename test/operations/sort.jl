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
    # Check that values are correctly sorted by key (but order among ties is not guaranteed)
    sorted_vals = s_unstable[:val]
    # All 1's should come before all 2's
    ones_indices = findall(==(1), s_unstable[:key])
    twos_indices = findall(==(2), s_unstable[:key])
    @test isempty(ones_indices) || isempty(twos_indices) || maximum(ones_indices) < minimum(twos_indices)
end
