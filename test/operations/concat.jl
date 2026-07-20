@testset "concat" begin
    a = DataFrame((; id = [1, 2], name = ["x", "y"]))
    b = DataFrame((; id = [3, 4], name = ["z", "w"]))

    r = concat([a, b])
    @test size(r) == (4, 2)
    @test r[:id] == [1, 2, 3, 4]
    @test r[:name] == ["x", "y", "z", "w"]

    # LazyFrame entry point agrees, and stacks the first frame (regression: previously the
    # first frame in the list was silently dropped)
    r_lazy = concat([lazy(a), lazy(b)]) |> collect
    @test r_lazy[:id] == r[:id]
    @test r_lazy[:name] == r[:name]

    # concatenating a frame with itself doubles it, including the first occurrence
    r_self = concat([a, a])
    @test size(r_self) == (4, 2)
    @test r_self[:id] == [1, 2, 1, 2]

    # single-frame concat is a no-op
    r_single = concat([a])
    @test size(r_single) == (2, 2)
    @test r_single[:id] == [1, 2]

    # explicit how=:vertical agrees with the default
    r_explicit = concat([a, b]; how = :vertical)
    @test r_explicit[:id] == r[:id]
end

@testset "concat how modes" begin
    a = DataFrame((; id = [1, 2], name = ["x", "y"]))

    # :diagonal -- frames with different columns, missing filled with `missing`
    c = DataFrame((; id = [3, 4], extra = [true, false]))
    r_diag = concat([a, c]; how = :diagonal)
    @test size(r_diag) == (4, 3)
    @test Set(names(r_diag)) == Set(["id", "name", "extra"])
    @test r_diag[:id] == [1, 2, 3, 4]
    @test isequal(collect(r_diag[:name]), ["x", "y", missing, missing])
    @test isequal(collect(r_diag[:extra]), [missing, missing, true, false])

    # :vertical_relaxed -- differing-but-compatible dtypes cast to their common supertype
    d_int = DataFrame((; v = [1, 2]))
    d_float = DataFrame((; v = [3.5, 4.5]))
    r_relaxed = concat([d_int, d_float]; how = :vertical_relaxed)
    @test eltype(r_relaxed[:v]) == Float64
    @test collect(r_relaxed[:v]) == [1.0, 2.0, 3.5, 4.5]

    # :diagonal_relaxed combines both behaviors
    r_diag_relaxed = concat([d_int, DataFrame((; v = [5.5], w = [true]))]; how = :diagonal_relaxed)
    @test size(r_diag_relaxed) == (3, 2)
    @test eltype(r_diag_relaxed[:v]) == Float64

    # :horizontal -- stack columns side by side (same row count required)
    e = DataFrame((; extra = [10, 20]))
    r_horiz = concat([a, e]; how = :horizontal)
    @test size(r_horiz) == (2, 3)
    @test Set(names(r_horiz)) == Set(["id", "name", "extra"])
    @test r_horiz[:extra] == [10, 20]

    @test_throws ErrorException concat([a, e]; how = :bogus)
end
