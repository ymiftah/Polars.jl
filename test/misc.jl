@testset "version" begin
    v = Polars.version()
    @test v isa VersionNumber
    @test v == v"0.51.0"
end
