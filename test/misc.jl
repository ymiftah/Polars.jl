@testset "version" begin
    v = Polars.version()
    @test v isa VersionNumber
    @test v == v"0.54.4"
end
