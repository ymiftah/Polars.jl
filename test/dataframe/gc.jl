@testset "GC C Data interface" begin
    GC.gc(true)

    @test isempty(Polars.LIVE_ARRAYS)
    @test isempty(Polars.LIVE_SCHEMAS)
end

@testset "GC releases depth-≥2 nested schemas/arrays (P0.6)" begin
    # Nesting deeper than one level must not leave anything rooted in
    # `LIVE_SCHEMAS`/`LIVE_ARRAYS`: a list-of-list-of-list and a struct-with-a-struct-field both
    # have grandchildren, which are reachable only transitively through their parents. Build both
    # shapes, drop every reference, and force collection.
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
    # `arrowtable` roots only the top-level array/schema, and only once every column has been
    # built without error, so a throw partway through column construction (a column built before
    # the failing one, or a partially built schema tree) leaves nothing rooted that no owner will
    # ever release -- such an entry would leak permanently, since nothing else references it.
    # Exercise several
    # distinct failure shapes: an out-of-range `DateTime` (ms->ns `InexactError` in `arrowvector`),
    # a bare-`Any` column (the deliberate `format(::Type{Any})` error), and a mutable struct column
    # (the deliberate `format` rejection, which fails before any buffer is built). A nullable
    # `NamedTuple` column used to be a fourth shape here -- a bare `MethodError` from the array
    # builder, since `arrowvector` had no method for it -- but the generic struct fallback added
    # for that column shape means every immutable struct type now either builds or raises a
    # specific error from `format`, so a bare `MethodError` is no longer reachable at all.
    for _ in 1:5
        @test_throws InexactError DataFrame((; a = Int64[1], b = [DateTime(1600, 1, 1)]))
    end
    for _ in 1:5
        @test_throws ErrorException DataFrame((; a = Int64[1], b = Any[1, "two"]))
    end
    for _ in 1:5
        @test_throws ErrorException DataFrame(
            (;
                a = Int64[1],
                b = [MutableColumnElement(1)],
            )
        )
    end
    GC.gc(true)
    GC.gc(true)

    @test isempty(Polars.LIVE_ARRAYS)
    @test isempty(Polars.LIVE_SCHEMAS)
end
