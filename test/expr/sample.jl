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
