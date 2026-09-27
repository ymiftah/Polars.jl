@testset "head" begin
    df = DataFrame((; x = collect(1:5), y = ["a", "b", "c", "d", "e"]))

    h = head(df, 2)
    @test size(h) == (2, 2)
    @test h[:x] == [1, 2]

    h = head(lazy(df), 3) |> collect
    @test size(h) == (3, 2)
    @test h[:x] == [1, 2, 3]

    # n=0 and n larger than the row count are both plain, non-error edge cases
    @test size(head(df, 0)) == (0, 2)
    @test size(head(df, 100)) == (5, 2)

    # a negative n (upstream's `height + n`) is not supported and raises an `ArgumentError`; the
    # FFI takes an unsigned count
    @test_throws ArgumentError head(df, -2)
    @test_throws ArgumentError head(lazy(df), -2)
end
