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

    # a negative n is NOT supported here (upstream's `height + n` convenience needs a materialized
    # row count this wrapper doesn't compute) -- it must raise a clear `ArgumentError`, not the
    # bare `InexactError: convert(UInt64, ...)` that leaked through before this was fixed (the
    # underlying `polars_lazy_frame_head`/`_tail` FFI functions take an unsigned `usize`)
    @test_throws ArgumentError head(df, -2)
    @test_throws ArgumentError head(lazy(df), -2)
end
