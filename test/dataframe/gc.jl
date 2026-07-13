@testset "GC C Data interface" begin
    GC.gc(true)

    @test isempty(Polars.LIVE_ARRAYS)
    @test isempty(Polars.LIVE_SCHEMAS)
end
