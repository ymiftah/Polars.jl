@testset "version" begin
    v = Polars.version()
    @test v isa VersionNumber
    @test v == v"0.54.4"
end

@testset "PolarsError (Julia-side P2.3)" begin
    # FFI errors (via `polars_error`) raise an exported `PolarsError` carrying the raw polars-side
    # message unmodified, so callers can `catch` a polars-originated failure (a bad column name, an
    # unencodable cast, ...) specifically, rather than a plain `ErrorException` indistinguishable
    # from a bug in their own code.
    df = DataFrame((; x = [1, 2, 3]))
    err = try
        select(df, col("nonexistent"))
        nothing
    catch e
        e
    end
    @test err isa PolarsError
    @test err isa Exception
    @test err.message isa String
    @test occursin("nonexistent", err.message)
    @test startswith(sprint(showerror, err), "PolarsError: ")
end

@testset "nth (py-polars functions/test_nth.py, adjusted for 1-based indexing)" begin
    # `nth` here is 1-indexed ("columns start at 1", per its own docstring), unlike upstream's
    # 0-indexed `pl.nth` -- `nth(1)` is the first column, matching upstream's `pl.nth(0)`.
    # Negative indices are NOT shifted (both conventions already count from the end the same way).
    df = DataFrame((; a = [1, 2], b = [3, 4], c = [5, 6]))
    @test Tables.columnnames(select(df, nth(1))) == (:a,)
    @test Tables.columnnames(select(df, nth(-1))) == (:c,)

    # two `nth` expressions resolving to the same column is a Step-5 abort-safety check: a clean
    # PolarsError, not a crash (py-polars test_nth_duplicate)
    @test_throws PolarsError select(df, nth(1), nth(1))
end
