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

@testset "arrowtable does not leak LIVE_ARRAYS/LIVE_SCHEMAS on partial construction failure" begin
    # Regression test: `arrowtable` used to root every nesting level (not just the top-level
    # array/schema), so a throw partway through column construction (a column built before the
    # failing one, or a partially built schema tree) left already-rooted entries with no owner to
    # ever release them -- a permanent leak, since nothing else references them. Exercise several
    # distinct failure shapes: an out-of-range `DateTime` (ms->ns `InexactError` in `arrowvector`),
    # a bare-`Any` column (the deliberate `format(::Type{Any})` error), and a column type with no
    # `arrowvector` method at all.
    for _ in 1:5
        @test_throws InexactError DataFrame((; a = Int64[1], b = [DateTime(1600, 1, 1)]))
    end
    for _ in 1:5
        @test_throws ErrorException DataFrame((; a = Int64[1], b = Any[1, "two"]))
    end
    for _ in 1:5
        @test_throws MethodError DataFrame(
            (;
                a = Int64[1],
                b = Union{NamedTuple{(:q,), Tuple{Int}}, Missing}[(q = 1,)],
            )
        )
    end
    GC.gc(true)
    GC.gc(true)

    @test isempty(Polars.LIVE_ARRAYS)
    @test isempty(Polars.LIVE_SCHEMAS)
end
