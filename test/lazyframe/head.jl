@testset "head" begin
    df = DataFrame((; x = collect(1:5), y = ["a", "b", "c", "d", "e"]))

    h = head(df, 2)
    @test size(h) == (2, 2)
    @test h[:x] == [1, 2]

    h = head(lazy(df), 3) |> collect
    @test size(h) == (3, 2)
    @test h[:x] == [1, 2, 3]
end
