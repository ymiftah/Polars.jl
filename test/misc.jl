@testset "version" begin
    v = Polars.version()
    @test v isa VersionNumber
    @test v == v"0.54.4"
end

@testset "PolarsError (Julia-side P2.3)" begin
    # FFI errors (via `polars_error`) used to raise a plain `ErrorException`, indistinguishable
    # from any other Julia error -- callers couldn't `catch` specifically a polars-originated
    # failure (a bad column name, an unencodable cast, ...) without also catching bugs in their
    # own code. `PolarsError` is exported and carries the raw polars-side message unmodified.
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
