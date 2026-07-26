@testset "GC C Data interface" begin
    GC.gc(true)

    @test isempty(Polars.LIVE_ARRAYS)
    @test isempty(Polars.LIVE_SCHEMAS)
end

@testset "GC releases depth-≥2 nested schemas/arrays (P0.6)" begin
    # `release_schema!`/`release_array!` used to unroot only the *immediate* children of the
    # top-level column schema/array; every nesting level registers itself independently in
    # `set_private_data!`, so a list-of-list-of-list or struct-with-a-struct-field left its
    # grandchildren permanently rooted in `LIVE_SCHEMAS`/`LIVE_ARRAYS`. Build both shapes, drop
    # every reference, and force collection.
    for _ in 1:20
        df = DataFrame((; x = [[[1, 2], [3]], [[4]], Vector{Vector{Int}}()]))
        df = nothing
    end
    for _ in 1:20
        df = DataFrame((; s = [(a = (b = 1, c = 2),)]))
        df = nothing
    end
    GC.gc(true)
    GC.gc(true)

    @test isempty(Polars.LIVE_ARRAYS)
    @test isempty(Polars.LIVE_SCHEMAS)
end
