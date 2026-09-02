@testset "sample_n" begin
    df = DataFrame((; x = collect(1:20)))

    r = select(df, alias(sample_n(col("x"), 5; seed = 42), "s"))
    @test length(r[:s]) == 5
    @test allunique(r[:s])  # with_replacement=false by default
    @test all(v -> v in 1:20, r[:s])

    # same seed gives reproducible output
    r2 = select(df, alias(sample_n(col("x"), 5; seed = 42), "s"))
    @test r[:s] == r2[:s]

    # different seed can give a different sample
    r3 = select(df, alias(sample_n(col("x"), 5; seed = 43), "s"))
    @test length(r3[:s]) == 5

    # with_replacement allows sampling more than the population size, with duplicates possible
    r_wr = select(df, alias(sample_n(col("x"), 30; with_replacement = true, seed = 1), "s"))
    @test length(r_wr[:s]) == 30

    # shuffle=false (the default), without replacement, preserves the sampled rows' original
    # relative order -- across several seeds, not just one (py-polars
    # test_sample_no_shuffle_preserves_order_23557, adapted from `DataFrame.sample` to the
    # `Expr`-level `sample_n` this wrapper actually has)
    df_small = DataFrame((; a = [1, 2, 3, 4]))
    for seed in 0:9
        v = collect(select(df_small, sample_n(col("a"), 3; shuffle = false, seed))[:a])
        @test v == sort(v)
    end

    # NOTE: py-polars' `test_sample_no_shuffle_with_replacement_preserves_order_23557` asserts the
    # same order-preservation additionally holds under `with_replacement=true`, but that test
    # exercises `DataFrame.sample()` (which this wrapper doesn't have at all -- a separate,
    # already-recorded gap), not `Expr.sample_n`. Live-verified this does NOT hold for
    # `Expr.sample_n(...; shuffle=false, with_replacement=true)`: draws come back in arbitrary
    # order (e.g. `[2, 2, 2]`, `[4, 3, 1]`, `[3, 3, 2]` across ten seeds), never sorted. Whether
    # that is `DataFrame.sample()` applying extra ordering beyond what `Expr.sample_n` itself
    # does, or a version-specific difference, wasn't investigated further -- recorded as its own
    # narrow finding rather than asserted either way.
end

@testset "sample_frac" begin
    df = DataFrame((; x = collect(1:20)))

    r = select(df, alias(sample_frac(col("x"), 0.5; seed = 42), "s"))
    @test length(r[:s]) == 10
    @test allunique(r[:s])

    r2 = select(df, alias(sample_frac(col("x"), 0.5; seed = 42), "s"))
    @test r[:s] == r2[:s]

    r_wr = select(df, alias(sample_frac(col("x"), 2.0; with_replacement = true, seed = 1), "s"))
    @test length(r_wr[:s]) == 40
end
